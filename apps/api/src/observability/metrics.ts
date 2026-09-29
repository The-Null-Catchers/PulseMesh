import type { FastifyInstance } from "fastify";
import {
  Counter,
  Gauge,
  Histogram,
  Registry,
  collectDefaultMetrics,
} from "@prometheus-io/client";
import { Queue } from "bullmq";
import { queueRedis } from "../realtime/bus.js";
import { activeWebSocketConnections } from "../realtime/gateway.js";
import { connectedPresenceUsers } from "../presence/service.js";

export const metricsRegistry = new Registry();

collectDefaultMetrics({
  register: metricsRegistry,
  prefix: "pulsemesh_api_",
});

export const httpRequests = new Counter({
  name: "pulsemesh_http_requests_total",
  help: "Completed HTTP requests",
  labelNames: ["method", "route", "status"] as const,
  registers: [metricsRegistry],
});

export const httpErrors = new Counter({
  name: "pulsemesh_http_errors_total",
  help: "HTTP responses with a 5xx status",
  labelNames: ["method", "route", "status"] as const,
  registers: [metricsRegistry],
});

export const httpDuration = new Histogram({
  name: "pulsemesh_http_request_duration_seconds",
  help: "HTTP request latency in seconds",
  labelNames: ["method", "route", "status"] as const,
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [metricsRegistry],
});

export const messagesCreated = new Counter({
  name: "pulsemesh_messages_created_total",
  help: "Durable messages created by destination kind",
  labelNames: ["destination"] as const,
  registers: [metricsRegistry],
});

new Gauge({
  name: "pulsemesh_websocket_connections",
  help: "Active WebSocket connections on this API instance",
  registers: [metricsRegistry],
  collect() {
    this.set(activeWebSocketConnections());
  },
});

new Gauge({
  name: "pulsemesh_connected_users",
  help: "Users with at least one unexpired presence session",
  registers: [metricsRegistry],
  async collect() {
    this.set(await connectedPresenceUsers());
  },
});

const notificationQueue = new Queue("notifications", {
  connection: queueRedis,
});
const fileQueue = new Queue("files", {
  connection: queueRedis,
});

new Gauge({
  name: "pulsemesh_job_queue_depth",
  help: "BullMQ jobs by queue and state",
  labelNames: ["queue", "state"] as const,
  registers: [metricsRegistry],
  async collect() {
    for (const queue of [notificationQueue, fileQueue]) {
      const counts = await queue.getJobCounts(
        "wait",
        "active",
        "delayed",
        "failed",
      );
      for (const state of ["wait", "active", "delayed", "failed"] as const) {
        this.set({ queue: queue.name, state }, counts[state] ?? 0);
      }
    }
  },
});

const starts = new WeakMap<object, bigint>();

export function registerHttpMetrics(app: FastifyInstance): void {
  app.addHook("onRequest", (request, _reply, done) => {
    starts.set(request, process.hrtime.bigint());
    done();
  });

  app.addHook("onResponse", (request, reply, done) => {
    const route = request.routeOptions.url ?? "unmatched";
    const status = String(reply.statusCode);
    const labels = {
      method: request.method,
      route,
      status,
    };

    httpRequests.inc(labels);
    if (reply.statusCode >= 500) {
      httpErrors.inc(labels);
    }

    const started = starts.get(request);
    if (started !== undefined) {
      const elapsed = Number(process.hrtime.bigint() - started) / 1_000_000_000;
      httpDuration.observe(labels, elapsed);
      starts.delete(request);
    }
    done();
  });

  app.addHook("onClose", async () => {
    await Promise.all([notificationQueue.close(), fileQueue.close()]);
  });
}

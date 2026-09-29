import type { FastifyInstance } from "fastify";
import { S3Client, HeadBucketCommand } from "@aws-sdk/client-s3";
import { pool } from "../db/index.js";
import { config } from "../config.js";
import { redis } from "../realtime/bus.js";
import { activeWebSocketConnections } from "../realtime/gateway.js";

const s3 = new S3Client({
  region: config.S3_REGION,
  endpoint: config.S3_ENDPOINT,
  forcePathStyle: config.S3_FORCE_PATH_STYLE,
  credentials: {
    accessKeyId: config.S3_ACCESS_KEY,
    secretAccessKey: config.S3_SECRET_KEY,
  },
});

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get("/health", async () => ({ status: "ok", service: "pulsemesh-api" }));

  app.get("/health/ready", async (_request, reply) => {
    const dependencies = {
      postgres: false,
      redis: false,
      objectStorage: false,
    };
    try {
      await pool.query("SELECT 1");
      dependencies.postgres = true;
    } catch {}
    try {
      dependencies.redis = (await redis.ping()) === "PONG";
    } catch {}
    try {
      await s3.send(new HeadBucketCommand({ Bucket: config.S3_BUCKET }));
      dependencies.objectStorage = true;
    } catch {}

    const ready = Object.values(dependencies).every(Boolean);
    return reply.code(ready ? 200 : 503).send({
      status: ready ? "ready" : "not_ready",
      dependencies,
    });
  });

  app.get("/metrics-lite", async () => ({
    activeWebSocketConnections: activeWebSocketConnections(),
  }));
}

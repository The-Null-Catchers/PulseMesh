import type { FastifyInstance } from "fastify";
import { randomToken } from "@pulsemesh/shared";
import { redis } from "./bus.js";

const TICKET_TTL_SECONDS = 30;

export async function realtimeTicketRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.post(
    "/realtime/ticket",
    { preHandler: app.authenticate },
    async (request) => {
      const ticket = randomToken(24);
      await redis.set(
        "realtime:ticket:" + ticket,
        JSON.stringify({
          userId: request.auth?.userId,
          sessionId: request.auth?.sessionId,
        }),
        "EX",
        TICKET_TTL_SECONDS,
        "NX",
      );
      return { ticket, expiresIn: TICKET_TTL_SECONDS };
    },
  );
}

export async function consumeRealtimeTicket(
  ticket: string,
): Promise<{ userId: string; sessionId: string } | null> {
  const value = await redis.call("GETDEL", "realtime:ticket:" + ticket);
  if (typeof value !== "string") return null;
  return JSON.parse(value) as { userId: string; sessionId: string };
}

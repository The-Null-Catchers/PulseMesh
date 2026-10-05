import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { getUserProfile, updateUserProfile } from "./service.js";

const profileUpdateSchema = z
  .object({
    username: z
      .string()
      .trim()
      .min(3)
      .max(32)
      .regex(/^[a-zA-Z0-9._-]+$/)
      .optional(),
    displayName: z.string().trim().min(1).max(80).optional(),
    avatarUrl: z.string().url().max(2048).nullable().optional(),
    bio: z.string().trim().max(500).nullable().optional(),
    timezone: z.string().trim().min(1).max(80).optional(),
    statusText: z.string().trim().max(120).nullable().optional(),
  })
  .strict();

export async function profileRoutes(app: FastifyInstance): Promise<void> {
  app.get("/profile", { preHandler: app.authenticate }, async (request) => {
    const userId = request.auth?.userId;
    if (!userId) throw new Error("Missing user");
    return getUserProfile(userId);
  });

  app.patch("/profile", { preHandler: app.authenticate }, async (request) => {
    const userId = request.auth?.userId;
    if (!userId) throw new Error("Missing user");

    const body = profileUpdateSchema.parse(request.body);
    return updateUserProfile(userId, body);
  });
}

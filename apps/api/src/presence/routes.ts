import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { isWorkspaceMember } from "../authorization/service.js";
import { AppError } from "../errors.js";
import {
  broadcastPresence,
  currentPresence,
  listWorkspacePresence,
  updatePresenceSettings,
} from "./service.js";

export async function presenceRoutes(app: FastifyInstance): Promise<void> {
  app.get("/presence", { preHandler: app.authenticate }, async (request) => {
    const userId = request.auth?.userId;
    if (!userId) throw new Error("Missing user");
    return currentPresence(userId);
  });

  app.get(
    "/workspaces/:workspaceId/presence",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ workspaceId: z.string().uuid() })
        .parse(request.params);
      const userId = request.auth?.userId;
      if (!userId || !(await isWorkspaceMember(userId, params.workspaceId))) {
        throw new AppError(
          403,
          "PRESENCE_ACCESS_DENIED",
          "Workspace access denied",
        );
      }

      return { items: await listWorkspacePresence(params.workspaceId) };
    },
  );

  app.put("/presence", { preHandler: app.authenticate }, async (request) => {
    const body = z
      .object({
        status: z.enum(["online", "idle", "do-not-disturb"]),
        customText: z.string().trim().max(120).nullable().default(null),
        activeWorkspaceId: z.string().uuid().nullable().optional(),
      })
      .parse(request.body);

    const userId = request.auth?.userId;
    if (!userId) throw new Error("Missing user");

    if (
      body.activeWorkspaceId &&
      !(await isWorkspaceMember(userId, body.activeWorkspaceId))
    ) {
      throw new AppError(
        403,
        "ACTIVE_WORKSPACE_DENIED",
        "Active workspace must be one of your workspaces",
      );
    }

    const snapshot = await updatePresenceSettings({
      userId,
      status: body.status,
      customText: body.customText,
      ...(body.activeWorkspaceId !== undefined
        ? { activeWorkspaceId: body.activeWorkspaceId }
        : {}),
    });
    await broadcastPresence(userId);
    return snapshot;
  });
}

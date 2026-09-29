import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool, withTransaction } from "../db/index.js";

const rolePermissionMap: Record<string, string[]> = {
  Admin: [
    "workspace.manage",
    "workspace.invite",
    "workspace.roles.manage",
    "channel.create",
    "channel.update",
    "channel.delete",
    "message.send",
    "message.delete",
    "message.pin",
    "member.kick",
    "member.ban",
    "call.create",
    "call.manage",
    "moderation.manage",
    "moderation.manage",
    "audit.view",
  ],
  Moderator: [
    "message.send",
    "message.delete",
    "message.pin",
    "member.kick",
    "member.ban",
    "call.create",
    "call.manage",
  ],
  Member: ["message.send", "call.create"],
  Guest: ["message.send"],
};

async function createDefaultRoles(
  client: import("pg").PoolClient,
  workspaceId: string,
) {
  const roleIds = new Map<string, string>();

  const owner = await client.query<{ id: string }>(
    "INSERT INTO roles (workspace_id,name,is_system) VALUES ($1,'Owner',true) RETURNING id",
    [workspaceId],
  );
  const ownerId = owner.rows[0]?.id;
  if (!ownerId) throw new Error("Owner role creation failed");
  roleIds.set("Owner", ownerId);
  await client.query(
    "INSERT INTO role_permissions (role_id,permission_id) SELECT $1,id FROM permissions ON CONFLICT DO NOTHING",
    [ownerId],
  );

  for (const [name, permissionKeys] of Object.entries(rolePermissionMap)) {
    const role = await client.query<{ id: string }>(
      "INSERT INTO roles (workspace_id,name,is_system) VALUES ($1,$2,true) RETURNING id",
      [workspaceId, name],
    );
    const roleId = role.rows[0]?.id;
    if (!roleId) continue;
    roleIds.set(name, roleId);
    await client.query(
      "INSERT INTO role_permissions (role_id,permission_id) SELECT $1,id FROM permissions WHERE key=ANY($2::text[]) ON CONFLICT DO NOTHING",
      [roleId, permissionKeys],
    );
  }

  return roleIds;
}

export async function workspaceRoutes(app: FastifyInstance): Promise<void> {
  app.get("/workspaces", { preHandler: app.authenticate }, async (request) => {
    const result = await pool.query(
      "SELECT w.id,w.name,w.slug,w.avatar_url,w.description,r.name AS role FROM workspaces w JOIN workspace_members wm ON wm.workspace_id=w.id JOIN roles r ON r.id=wm.role_id WHERE wm.user_id=$1 ORDER BY w.name",
      [request.auth?.userId],
    );
    return { items: result.rows };
  });

  app.post(
    "/workspaces",
    { preHandler: app.authenticate },
    async (request, reply) => {
      const body = z
        .object({
          name: z.string().min(2).max(80),
          slug: z
            .string()
            .min(2)
            .max(64)
            .regex(/^[a-z0-9-]+$/),
          description: z.string().max(500).optional(),
        })
        .parse(request.body);

      const userId = request.auth?.userId;
      if (!userId) throw new Error("Missing authenticated user");

      const workspace = await withTransaction(async (client) => {
        const created = await client.query<{
          id: string;
          name: string;
          slug: string;
        }>(
          "INSERT INTO workspaces (name,slug,description,owner_user_id) VALUES ($1,$2,$3,$4) RETURNING id,name,slug",
          [body.name, body.slug, body.description ?? null, userId],
        );
        const row = created.rows[0];
        if (!row) throw new Error("Workspace creation failed");
        const roles = await createDefaultRoles(client, row.id);
        const ownerRoleId = roles.get("Owner");
        if (!ownerRoleId) throw new Error("Owner role missing");

        await client.query(
          "INSERT INTO workspace_members (workspace_id,user_id,role_id) VALUES ($1,$2,$3)",
          [row.id, userId, ownerRoleId],
        );
        await client.query(
          "INSERT INTO channels (workspace_id,name,kind,visibility,position,created_by) VALUES ($1,'general','text','public',0,$2)",
          [row.id, userId],
        );
        await client.query(
          "INSERT INTO audit_logs (workspace_id,actor_user_id,action,target_type,target_id) VALUES ($1,$2,'workspace.created','workspace',$1::text)",
          [row.id, userId],
        );
        return row;
      });

      return reply.code(201).send(workspace);
    },
  );
}

import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool, withTransaction } from "../db/index.js";
import { AppError } from "../errors.js";
import { canAccessConversation } from "../authorization/service.js";

const encodedKey = z
  .string()
  .min(16)
  .max(8192)
  .regex(/^[A-Za-z0-9+/_=-]+$/);

const bundleSchema = z.object({
  registrationId: z.number().int().min(1).max(2147483647),
  identityKeyPublic: encodedKey,
  signedPreKey: z.object({
    id: z.number().int().nonnegative(),
    publicKey: encodedKey,
    signature: encodedKey,
  }),
  oneTimePreKeys: z
    .array(
      z.object({
        id: z.number().int().nonnegative(),
        publicKey: encodedKey,
      }),
    )
    .max(100)
    .default([]),
});

function identity(request: {
  auth?: { userId?: string; sessionId?: string } | null;
}) {
  const userId = request.auth?.userId;
  const sessionId = request.auth?.sessionId;
  if (!userId || !sessionId) {
    throw new Error("Missing authenticated identity");
  }
  return { userId, sessionId };
}

async function directMembers(conversationId: string): Promise<string[]> {
  const conversation = await pool.query<{ kind: string }>(
    "SELECT kind FROM conversations WHERE id=$1",
    [conversationId],
  );
  const row = conversation.rows[0];
  if (!row) {
    throw new AppError(404, "CONVERSATION_NOT_FOUND", "Conversation not found");
  }
  if (row.kind !== "direct") {
    throw new AppError(
      409,
      "E2EE_DIRECT_ONLY",
      "Initial E2EE is available only for direct conversations",
    );
  }

  const members = await pool.query<{ user_id: string }>(
    "SELECT user_id FROM conversation_members WHERE conversation_id=$1 ORDER BY user_id",
    [conversationId],
  );
  if (members.rows.length !== 2) {
    throw new AppError(
      409,
      "E2EE_DIRECT_MEMBER_COUNT",
      "Encrypted direct conversations require exactly two members",
    );
  }
  return members.rows.map((member) => member.user_id);
}

export async function e2eeRoutes(app: FastifyInstance): Promise<void> {
  app.put(
    "/e2ee/device-bundle",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
    },
    async (request) => {
      const current = identity(request);
      const body = bundleSchema.parse(request.body);

      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO e2ee_device_bundles (
            session_id,user_id,registration_id,identity_key_public,
            signed_pre_key_id,signed_pre_key_public,signed_pre_key_signature
          ) VALUES ($1,$2,$3,$4,$5,$6,$7)
          ON CONFLICT (session_id)
          DO UPDATE SET
            registration_id=EXCLUDED.registration_id,
            identity_key_public=EXCLUDED.identity_key_public,
            signed_pre_key_id=EXCLUDED.signed_pre_key_id,
            signed_pre_key_public=EXCLUDED.signed_pre_key_public,
            signed_pre_key_signature=EXCLUDED.signed_pre_key_signature,
            revision=e2ee_device_bundles.revision+1,
            updated_at=now()`,
          [
            current.sessionId,
            current.userId,
            body.registrationId,
            body.identityKeyPublic,
            body.signedPreKey.id,
            body.signedPreKey.publicKey,
            body.signedPreKey.signature,
          ],
        );

        for (const preKey of body.oneTimePreKeys) {
          await client.query(
            `INSERT INTO e2ee_one_time_prekeys (
              session_id,key_id,public_key
            ) VALUES ($1,$2,$3)
            ON CONFLICT (session_id,key_id) DO NOTHING`,
            [current.sessionId, preKey.id, preKey.publicKey],
          );
        }
      });

      return { ok: true };
    },
  );

  app.delete(
    "/e2ee/device-bundle",
    { preHandler: app.authenticate },
    async (request) => {
      const current = identity(request);
      await pool.query(
        "DELETE FROM e2ee_device_bundles WHERE session_id=$1 AND user_id=$2",
        [current.sessionId, current.userId],
      );
      return { ok: true };
    },
  );

  app.post(
    "/conversations/:conversationId/e2ee/enable",
    { preHandler: app.authenticate },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const current = identity(request);

      if (
        !(await canAccessConversation(current.userId, params.conversationId))
      ) {
        throw new AppError(
          403,
          "CONVERSATION_ACCESS_DENIED",
          "Conversation access denied",
        );
      }

      const members = await directMembers(params.conversationId);
      const bundleCoverage = await pool.query<{ user_id: string }>(
        `SELECT DISTINCT b.user_id
         FROM e2ee_device_bundles b
         JOIN sessions s ON s.id=b.session_id
         WHERE b.user_id=ANY($1::uuid[])
           AND s.revoked_at IS NULL
           AND s.expires_at>now()`,
        [members],
      );

      if (bundleCoverage.rows.length !== members.length) {
        throw new AppError(
          409,
          "E2EE_KEYS_INCOMPLETE",
          "Every participant must publish an active E2EE device bundle first",
        );
      }

      await pool.query(
        `UPDATE conversations
         SET encryption_mode='e2ee_v1',updated_at=now()
         WHERE id=$1`,
        [params.conversationId],
      );

      return { ok: true, encryptionMode: "e2ee_v1" };
    },
  );

  app.post(
    "/conversations/:conversationId/e2ee/key-bundles",
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
    },
    async (request) => {
      const params = z
        .object({ conversationId: z.string().uuid() })
        .parse(request.params);
      const current = identity(request);

      if (
        !(await canAccessConversation(current.userId, params.conversationId))
      ) {
        throw new AppError(
          403,
          "CONVERSATION_ACCESS_DENIED",
          "Conversation access denied",
        );
      }

      const members = await directMembers(params.conversationId);
      const targetUserId = members.find((member) => member !== current.userId);
      if (!targetUserId) {
        throw new AppError(
          409,
          "E2EE_PEER_NOT_FOUND",
          "Encrypted peer not found",
        );
      }

      return withTransaction(async (client) => {
        const bundles = await client.query<{
          session_id: string;
          registration_id: number;
          identity_key_public: string;
          signed_pre_key_id: number;
          signed_pre_key_public: string;
          signed_pre_key_signature: string;
          revision: string;
        }>(
          `SELECT
            b.session_id,b.registration_id,b.identity_key_public,
            b.signed_pre_key_id,b.signed_pre_key_public,
            b.signed_pre_key_signature,b.revision::text
           FROM e2ee_device_bundles b
           JOIN sessions s ON s.id=b.session_id
           WHERE b.user_id=$1
             AND s.revoked_at IS NULL
             AND s.expires_at>now()
           ORDER BY b.created_at,b.session_id`,
          [targetUserId],
        );

        const items = [];
        for (const bundle of bundles.rows) {
          const preKey = await client.query<{
            key_id: number;
            public_key: string;
          }>(
            `WITH selected AS (
              SELECT session_id,key_id
              FROM e2ee_one_time_prekeys
              WHERE session_id=$1 AND claimed_at IS NULL
              ORDER BY key_id
              FOR UPDATE SKIP LOCKED
              LIMIT 1
            )
            UPDATE e2ee_one_time_prekeys p
            SET claimed_at=now()
            FROM selected
            WHERE p.session_id=selected.session_id
              AND p.key_id=selected.key_id
            RETURNING p.key_id,p.public_key`,
            [bundle.session_id],
          );

          const oneTime = preKey.rows[0];
          items.push({
            deviceSessionId: bundle.session_id,
            registrationId: bundle.registration_id,
            identityKeyPublic: bundle.identity_key_public,
            signedPreKey: {
              id: bundle.signed_pre_key_id,
              publicKey: bundle.signed_pre_key_public,
              signature: bundle.signed_pre_key_signature,
            },
            oneTimePreKey: oneTime
              ? {
                  id: oneTime.key_id,
                  publicKey: oneTime.public_key,
                }
              : null,
            revision: bundle.revision,
          });
        }

        return {
          userId: targetUserId,
          protocol: "libsignal-v1",
          devices: items,
        };
      });
    },
  );
}

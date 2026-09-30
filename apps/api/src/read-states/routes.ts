import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";
import {
  canAccessChannel,
  canAccessConversation,
} from "../authorization/service.js";

export async function readStateRoutes(app: FastifyInstance): Promise<void> {
  app.put("/read-state", { preHandler: app.authenticate }, async (request) => {
    const body = z
      .object({
        channelId: z.string().uuid().optional(),
        conversationId: z.string().uuid().optional(),
        lastReadMessageId: z.string().uuid(),
      })
      .refine(
        (value) => Boolean(value.channelId) !== Boolean(value.conversationId),
        {
          message: "Exactly one destination is required",
        },
      )
      .parse(request.body);

    const userId = request.auth?.userId;
    if (!userId) throw new Error("Missing user");

    if (body.channelId && !(await canAccessChannel(userId, body.channelId))) {
      throw new AppError(403, "READ_STATE_DENIED", "Channel access denied");
    }
    if (
      body.conversationId &&
      !(await canAccessConversation(userId, body.conversationId))
    ) {
      throw new AppError(
        403,
        "READ_STATE_DENIED",
        "Conversation access denied",
      );
    }

    const destinationMessage = await pool.query<{ id: string }>(
      `SELECT id
       FROM messages
       WHERE id=$1
         AND deleted_at IS NULL
         AND (
           ($2::uuid IS NOT NULL AND channel_id=$2)
           OR
           ($3::uuid IS NOT NULL AND conversation_id=$3)
         )
         AND NOT EXISTS (
           SELECT 1
           FROM message_hidden_users hidden
           WHERE hidden.message_id=messages.id AND hidden.user_id=$4
         )
       LIMIT 1`,
      [
        body.lastReadMessageId,
        body.channelId ?? null,
        body.conversationId ?? null,
        userId,
      ],
    );

    if (!destinationMessage.rows[0]) {
      throw new AppError(
        400,
        "READ_STATE_MESSAGE_MISMATCH",
        "Read-state message does not belong to the destination",
      );
    }

    if (body.channelId) {
      await pool.query(
        "INSERT INTO read_states (user_id,channel_id,last_read_message_id,last_read_at) VALUES ($1,$2,$3,now()) ON CONFLICT (user_id,channel_id) WHERE channel_id IS NOT NULL DO UPDATE SET last_read_message_id=EXCLUDED.last_read_message_id,last_read_at=now()",
        [userId, body.channelId, body.lastReadMessageId],
      );
    } else {
      await pool.query(
        "INSERT INTO read_states (user_id,conversation_id,last_read_message_id,last_read_at) VALUES ($1,$2,$3,now()) ON CONFLICT (user_id,conversation_id) WHERE conversation_id IS NOT NULL DO UPDATE SET last_read_message_id=EXCLUDED.last_read_message_id,last_read_at=now()",
        [userId, body.conversationId, body.lastReadMessageId],
      );
    }

    return { ok: true };
  });
}

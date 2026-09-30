import { randomUUID } from "node:crypto";
import type { RealtimeEvent } from "@pulsemesh/realtime";
import { pool } from "../db/index.js";
import { publishRealtime } from "../realtime/bus.js";

type InboxRecipient = {
  user_id: string;
};

async function messageRecipients(input: {
  senderUserId: string;
  channelId: string | null;
  conversationId: string | null;
}): Promise<string[]> {
  if (input.channelId) {
    const result = await pool.query<InboxRecipient>(
      `SELECT wm.user_id
       FROM channels c
       JOIN workspace_members wm ON wm.workspace_id=c.workspace_id
       LEFT JOIN channel_members cm
         ON cm.channel_id=c.id AND cm.user_id=wm.user_id
       WHERE c.id=$1
         AND wm.user_id<>$2
         AND (c.visibility<>'private' OR cm.user_id IS NOT NULL)`,
      [input.channelId, input.senderUserId],
    );
    return result.rows.map((row) => row.user_id);
  }

  if (input.conversationId) {
    const result = await pool.query<InboxRecipient>(
      `SELECT user_id
       FROM conversation_members
       WHERE conversation_id=$1 AND user_id<>$2`,
      [input.conversationId, input.senderUserId],
    );
    return result.rows.map((row) => row.user_id);
  }

  return [];
}

export async function publishInboxMessageEvents(input: {
  messageId: string;
  senderUserId: string;
  channelId: string | null;
  conversationId: string | null;
  createdAt: Date;
}): Promise<void> {
  const recipients = await messageRecipients(input);

  for (let offset = 0; offset < recipients.length; offset += 50) {
    const batch = recipients.slice(offset, offset + 50);
    await Promise.all(
      batch.map((userId) => {
        const event: RealtimeEvent = {
          id: randomUUID(),
          type: "inbox.message",
          room: "user:" + userId,
          occurredAt: input.createdAt.toISOString(),
          payload: {
            messageId: input.messageId,
            channelId: input.channelId,
            conversationId: input.conversationId,
            senderId: input.senderUserId,
            createdAt: input.createdAt.toISOString(),
          },
        };
        return publishRealtime(event);
      }),
    );
  }
}

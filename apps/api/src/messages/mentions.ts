import { pool } from '../db/index.js';

export interface ParsedMentions {
  usernames: string[];
  broadcast: boolean;
}

export function parseMentions(body: string): ParsedMentions {
  const usernames = new Set<string>();
  let broadcast = false;
  const pattern = /(?:^|[\s(])@([a-zA-Z0-9_.-]{1,32})\b/g;

  for (const match of body.matchAll(pattern)) {
    const value = match[1]?.toLowerCase();
    if (!value) continue;

    if (value === 'everyone' || value === 'channel') {
      broadcast = true;
    } else {
      usernames.add(value);
    }
  }

  return { usernames: [...usernames], broadcast };
}

export async function createMentionNotifications(input: {
  messageId: string;
  senderUserId: string;
  body: string;
  channelId?: string;
  conversationId?: string;
}): Promise<void> {
  const parsed = parseMentions(input.body);
  if (!parsed.broadcast && parsed.usernames.length === 0) return;

  let recipients: Array<{ id: string }> = [];

  if (input.channelId) {
    const result = await pool.query<{ id: string }>(
      "SELECT DISTINCT u.id FROM channels c JOIN workspace_members wm ON wm.workspace_id=c.workspace_id JOIN users u ON u.id=wm.user_id LEFT JOIN channel_members cm ON cm.channel_id=c.id AND cm.user_id=u.id WHERE c.id=$1 AND u.id<>$2 AND (c.visibility<>'private' OR cm.user_id IS NOT NULL) AND ($3::boolean OR lower(u.username)=ANY($4::text[]))",
      [
        input.channelId,
        input.senderUserId,
        parsed.broadcast,
        parsed.usernames
      ]
    );
    recipients = result.rows;
  }

  if (input.conversationId) {
    const result = await pool.query<{ id: string }>(
      "SELECT u.id FROM conversation_members cm JOIN users u ON u.id=cm.user_id WHERE cm.conversation_id=$1 AND u.id<>$2 AND ($3::boolean OR lower(u.username)=ANY($4::text[]))",
      [
        input.conversationId,
        input.senderUserId,
        parsed.broadcast,
        parsed.usernames
      ]
    );
    recipients = result.rows;
  }

  for (const recipient of recipients) {
    const dedupeKey = 'mention:' + input.messageId + ':' + recipient.id;

    await pool.query(
      "INSERT INTO notifications (user_id,kind,payload,dedupe_key) VALUES ($1,'mention',$2::jsonb,$3) ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING",
      [
        recipient.id,
        JSON.stringify({
          messageId: input.messageId,
          channelId: input.channelId ?? null,
          conversationId: input.conversationId ?? null,
          senderUserId: input.senderUserId
        }),
        dedupeKey
      ]
    );
  }
}

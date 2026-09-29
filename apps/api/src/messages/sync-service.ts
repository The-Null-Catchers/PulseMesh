import { pool } from '../db/index.js';

export type MessageSyncRow = {
  sync_cursor: string;
  event_type: 'message.upsert' | 'message.delete';
  entity_id: string;
  target_user_id: string | null;
  hidden_for_user: boolean;
  id: string | null;
  client_message_id: string | null;
  channel_id: string | null;
  conversation_id: string | null;
  body: string | null;
  reply_to_message_id: string | null;
  created_at: Date | null;
  edited_at: Date | null;
  deleted_at: Date | null;
  sender_id: string | null;
  username: string | null;
  display_name: string | null;
  avatar_url: string | null;
  attachments: unknown[] | null;
};

export function mapMessageSyncRow(
  row: MessageSyncRow,
  userId: string
) {
  if (
    row.target_user_id !== null &&
    row.target_user_id !== userId
  ) {
    return null;
  }

  const deleted =
    row.event_type === 'message.delete' ||
    row.hidden_for_user ||
    row.deleted_at !== null ||
    row.id === null;

  return {
    cursor: row.sync_cursor,
    type: deleted ? ('delete' as const) : ('upsert' as const),
    messageId: row.entity_id,
    message: deleted
      ? null
      : {
          id: row.id,
          clientMessageId: row.client_message_id,
          channelId: row.channel_id,
          conversationId: row.conversation_id,
          body: row.body ?? '',
          replyToMessageId: row.reply_to_message_id,
          attachments: row.attachments ?? [],
          createdAt: row.created_at?.toISOString() ?? null,
          editedAt: row.edited_at?.toISOString() ?? null,
          sender: {
            id: row.sender_id,
            username: row.username,
            displayName: row.display_name,
            avatarUrl: row.avatar_url
          }
        }
  };
}

export async function latestMessageSyncCursor(input: {
  roomKind: 'channel' | 'conversation';
  roomId: string;
}) {
  const result = await pool.query<{ cursor: string }>(
    `SELECT COALESCE(MAX(id),0)::text AS cursor
     FROM message_sync_events
     WHERE room_kind=$1 AND room_id=$2`,
    [input.roomKind, input.roomId]
  );

  return result.rows[0]?.cursor ?? '0';
}

export async function syncMessageChanges(input: {
  roomKind: 'channel' | 'conversation';
  roomId: string;
  userId: string;
  after: string;
  limit: number;
}) {
  const result = await pool.query<MessageSyncRow>(
    `SELECT
      se.id::text AS sync_cursor,
      se.event_type,
      se.message_id AS entity_id,
      se.target_user_id,
      EXISTS(
        SELECT 1
        FROM message_hidden_users h
        WHERE h.message_id=se.message_id AND h.user_id=$4
      ) AS hidden_for_user,
      m.id,
      m.client_message_id,
      m.channel_id,
      m.conversation_id,
      m.body,
      m.reply_to_message_id,
      m.created_at,
      m.edited_at,
      m.deleted_at,
      u.id AS sender_id,
      u.username,
      u.display_name,
      u.avatar_url,
      COALESCE(
        (
          SELECT json_agg(
            json_build_object(
              'id',f.id,
              'name',f.original_name,
              'mimeType',COALESCE(f.detected_mime_type,f.mime_type),
              'sizeBytes',f.size_bytes,
              'width',f.width,
              'height',f.height,
              'durationMs',f.duration_ms,
              'hasThumbnail',(f.thumbnail_key IS NOT NULL)
            )
            ORDER BY ma.position
          )
          FROM message_attachments ma
          JOIN files f ON f.id=ma.file_id
          WHERE ma.message_id=m.id AND f.status='ready'
        ),
        '[]'::json
      ) AS attachments
    FROM message_sync_events se
    LEFT JOIN messages m ON m.id=se.message_id
    LEFT JOIN users u ON u.id=m.sender_user_id
    WHERE
      se.room_kind=$1
      AND se.room_id=$2
      AND se.id>$3::bigint
    ORDER BY se.id ASC
    LIMIT $5`,
    [
      input.roomKind,
      input.roomId,
      input.after,
      input.userId,
      input.limit + 1
    ]
  );

  const hasMore = result.rows.length > input.limit;
  const rows = result.rows.slice(0, input.limit);
  const last = rows[rows.length - 1];

  return {
    changes: rows
      .map((row) => mapMessageSyncRow(row, input.userId))
      .filter((change) => change !== null),
    nextAfter: last?.sync_cursor ?? input.after,
    hasMore
  };
}

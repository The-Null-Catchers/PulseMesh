import { pool } from "../db/index.js";
import { mapMessageSyncRow, type MessageSyncRow } from "./sync-model.js";

export async function latestMessageSyncCursor(input: {
  roomKind: "channel" | "conversation";
  roomId: string;
}) {
  const result = await pool.query<{ cursor: string }>(
    `SELECT COALESCE(MAX(id),0)::text AS cursor
     FROM message_sync_events
     WHERE room_kind=$1 AND room_id=$2`,
    [input.roomKind, input.roomId],
  );

  return result.rows[0]?.cursor ?? "0";
}

export async function syncMessageChanges(input: {
  roomKind: "channel" | "conversation";
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
      m.encryption_version,
      m.encrypted_payload,
      m.reply_to_message_id,
      m.thread_root_message_id,
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
    [input.roomKind, input.roomId, input.after, input.userId, input.limit + 1],
  );

  const hasMore = result.rows.length > input.limit;
  const rows = result.rows.slice(0, input.limit);
  const last = rows[rows.length - 1];

  return {
    changes: rows
      .map((row) => mapMessageSyncRow(row, input.userId))
      .filter((change) => change !== null),
    nextAfter: last?.sync_cursor ?? input.after,
    hasMore,
  };
}

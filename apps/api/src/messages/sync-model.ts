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

CREATE INDEX IF NOT EXISTS messages_channel_unread_idx
  ON messages(channel_id,created_at,id)
  INCLUDE (sender_user_id)
  WHERE channel_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS messages_conversation_unread_idx
  ON messages(conversation_id,created_at,id)
  INCLUDE (sender_user_id)
  WHERE conversation_id IS NOT NULL AND deleted_at IS NULL;

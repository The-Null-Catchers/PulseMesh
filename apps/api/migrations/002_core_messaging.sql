ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS quote_message_id uuid REFERENCES messages(id),
  ADD COLUMN IF NOT EXISTS forwarded_from_message_id uuid REFERENCES messages(id);

ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS dedupe_key text;

CREATE UNIQUE INDEX IF NOT EXISTS notifications_dedupe_key_unique
  ON notifications(dedupe_key)
  WHERE dedupe_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS message_hidden_users (
  message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  hidden_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(message_id,user_id)
);

CREATE TABLE IF NOT EXISTS message_pins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  channel_id uuid REFERENCES channels(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES conversations(id) ON DELETE CASCADE,
  pinned_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT message_pin_destination_check CHECK (
    (channel_id IS NOT NULL AND conversation_id IS NULL)
    OR
    (channel_id IS NULL AND conversation_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS message_pins_channel_unique
  ON message_pins(channel_id,message_id)
  WHERE channel_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS message_pins_conversation_unique
  ON message_pins(conversation_id,message_id)
  WHERE conversation_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS message_pins_channel_created_idx
  ON message_pins(channel_id,created_at DESC);

CREATE INDEX IF NOT EXISTS message_pins_conversation_created_idx
  ON message_pins(conversation_id,created_at DESC);

CREATE TABLE IF NOT EXISTS bookmarks (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,message_id)
);

CREATE INDEX IF NOT EXISTS bookmarks_user_created_idx
  ON bookmarks(user_id,created_at DESC);

CREATE TABLE IF NOT EXISTS channel_preferences (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel_id uuid NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
  pinned boolean NOT NULL DEFAULT false,
  muted_until timestamptz,
  notification_level text CHECK (
    notification_level IS NULL OR notification_level IN ('all','mentions','nothing')
  ),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,channel_id)
);

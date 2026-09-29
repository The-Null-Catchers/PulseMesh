ALTER TABLE files
  ADD COLUMN IF NOT EXISTS detected_mime_type text,
  ADD COLUMN IF NOT EXISTS preview_key text,
  ADD COLUMN IF NOT EXISTS checksum_sha256 text,
  ADD COLUMN IF NOT EXISTS processing_error text,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

CREATE INDEX IF NOT EXISTS files_owner_created_idx
  ON files(owner_user_id,created_at DESC);

CREATE INDEX IF NOT EXISTS files_processing_idx
  ON files(status,created_at)
  WHERE status IN ('pending','uploaded','processing');

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz;

CREATE TABLE IF NOT EXISTS notification_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform text NOT NULL CHECK (platform IN ('android','ios')),
  fcm_token text NOT NULL UNIQUE,
  enabled boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notification_devices_user_idx
  ON notification_devices(user_id,enabled);

CREATE TABLE IF NOT EXISTS web_push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  endpoint text NOT NULL UNIQUE,
  p256dh text NOT NULL,
  auth text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS web_push_subscriptions_user_idx
  ON web_push_subscriptions(user_id,enabled);

CREATE UNIQUE INDEX IF NOT EXISTS notification_preferences_global_unique
  ON notification_preferences(user_id)
  WHERE workspace_id IS NULL AND channel_id IS NULL AND conversation_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS notification_preferences_workspace_unique
  ON notification_preferences(user_id,workspace_id)
  WHERE workspace_id IS NOT NULL AND channel_id IS NULL AND conversation_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS notification_preferences_channel_unique
  ON notification_preferences(user_id,channel_id)
  WHERE channel_id IS NOT NULL AND workspace_id IS NULL AND conversation_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS notification_preferences_conversation_unique
  ON notification_preferences(user_id,conversation_id)
  WHERE conversation_id IS NOT NULL AND workspace_id IS NULL AND channel_id IS NULL;

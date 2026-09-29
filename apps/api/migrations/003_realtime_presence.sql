ALTER TABLE users
  ADD COLUMN IF NOT EXISTS presence_mode text NOT NULL DEFAULT 'online'
    CHECK (presence_mode IN ('online','idle','do-not-disturb')),
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

CREATE INDEX IF NOT EXISTS users_last_seen_idx
  ON users(last_seen_at DESC)
  WHERE last_seen_at IS NOT NULL;

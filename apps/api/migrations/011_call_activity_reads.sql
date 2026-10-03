CREATE TABLE IF NOT EXISTS call_activity_reads (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS call_invites_user_missed_created_idx
  ON call_invites(user_id,created_at DESC)
  WHERE status IN ('missed','declined');

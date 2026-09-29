ALTER TABLE calls
  ADD COLUMN IF NOT EXISTS provider text NOT NULL DEFAULT 'mesh',
  ADD COLUMN IF NOT EXISTS metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE call_participants
  ADD COLUMN IF NOT EXISTS session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS muted boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS deafened boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS camera_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS screen_sharing boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS connection_state text NOT NULL DEFAULT 'connected',
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='calls_destination_check'
  ) THEN
    ALTER TABLE calls ADD CONSTRAINT calls_destination_check CHECK (
      (channel_id IS NOT NULL AND conversation_id IS NULL)
      OR
      (channel_id IS NULL AND conversation_id IS NOT NULL)
    );
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS calls_active_channel_unique
  ON calls(channel_id)
  WHERE channel_id IS NOT NULL AND status='active';

CREATE UNIQUE INDEX IF NOT EXISTS calls_active_conversation_unique
  ON calls(conversation_id)
  WHERE conversation_id IS NOT NULL AND status='active';

CREATE UNIQUE INDEX IF NOT EXISTS call_participants_active_session_unique
  ON call_participants(call_id,session_id)
  WHERE session_id IS NOT NULL AND left_at IS NULL;

CREATE INDEX IF NOT EXISTS call_participants_call_active_idx
  ON call_participants(call_id,joined_at)
  WHERE left_at IS NULL;

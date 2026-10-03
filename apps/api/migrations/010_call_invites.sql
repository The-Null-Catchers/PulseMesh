CREATE TABLE IF NOT EXISTS call_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id uuid NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (
    status IN ('pending','accepted','declined','missed')
  ),
  expires_at timestamptz NOT NULL,
  responded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(call_id,user_id)
);

CREATE INDEX IF NOT EXISTS call_invites_user_pending_idx
  ON call_invites(user_id,expires_at)
  WHERE status='pending';

CREATE OR REPLACE FUNCTION pulsemesh_seed_call_invites()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.conversation_id IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO call_invites (call_id,user_id,expires_at)
  SELECT NEW.id,cm.user_id,NEW.started_at + interval '45 seconds'
  FROM conversation_members cm
  WHERE cm.conversation_id=NEW.conversation_id
    AND cm.user_id<>NEW.created_by
  ON CONFLICT (call_id,user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS calls_seed_invites ON calls;
CREATE TRIGGER calls_seed_invites
AFTER INSERT ON calls
FOR EACH ROW
EXECUTE FUNCTION pulsemesh_seed_call_invites();

CREATE OR REPLACE FUNCTION pulsemesh_close_pending_call_invites()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status='active' AND NEW.status<>'active' THEN
    UPDATE call_invites
    SET status='missed',
        responded_at=COALESCE(responded_at,now()),
        updated_at=now()
    WHERE call_id=NEW.id AND status='pending';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS calls_close_pending_invites ON calls;
CREATE TRIGGER calls_close_pending_invites
AFTER UPDATE OF status ON calls
FOR EACH ROW
EXECUTE FUNCTION pulsemesh_close_pending_call_invites();

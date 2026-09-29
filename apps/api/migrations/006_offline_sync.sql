CREATE TABLE IF NOT EXISTS message_sync_events (
  id bigserial PRIMARY KEY,
  room_kind text NOT NULL CHECK (room_kind IN ('channel','conversation')),
  room_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('message.upsert','message.delete')),
  message_id uuid NOT NULL,
  target_user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE message_sync_events
  ADD COLUMN IF NOT EXISTS target_user_id uuid REFERENCES users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS message_sync_events_room_cursor_idx
  ON message_sync_events(room_kind,room_id,id);

CREATE INDEX IF NOT EXISTS message_sync_events_message_idx
  ON message_sync_events(message_id,id DESC);

CREATE INDEX IF NOT EXISTS message_sync_events_target_user_idx
  ON message_sync_events(target_user_id,id)
  WHERE target_user_id IS NOT NULL;

INSERT INTO message_sync_events (
  room_kind,
  room_id,
  event_type,
  message_id,
  occurred_at
)
SELECT
  CASE
    WHEN channel_id IS NOT NULL THEN 'channel'
    ELSE 'conversation'
  END,
  COALESCE(channel_id,conversation_id),
  CASE
    WHEN deleted_at IS NOT NULL THEN 'message.delete'
    ELSE 'message.upsert'
  END,
  id,
  COALESCE(edited_at,deleted_at,created_at)
FROM messages
WHERE channel_id IS NOT NULL OR conversation_id IS NOT NULL
ORDER BY created_at,id;

CREATE OR REPLACE FUNCTION pulsemesh_record_message_sync_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  source_row messages%ROWTYPE;
  sync_room_kind text;
  sync_room_id uuid;
  sync_event_type text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    source_row := OLD;
    sync_event_type := 'message.delete';
  ELSE
    source_row := NEW;
    sync_event_type :=
      CASE
        WHEN NEW.deleted_at IS NOT NULL THEN 'message.delete'
        ELSE 'message.upsert'
      END;
  END IF;

  IF source_row.channel_id IS NOT NULL THEN
    sync_room_kind := 'channel';
    sync_room_id := source_row.channel_id;
  ELSIF source_row.conversation_id IS NOT NULL THEN
    sync_room_kind := 'conversation';
    sync_room_id := source_row.conversation_id;
  ELSE
    RETURN COALESCE(NEW,OLD);
  END IF;

  INSERT INTO message_sync_events (
    room_kind,
    room_id,
    event_type,
    message_id,
    occurred_at
  )
  VALUES (
    sync_room_kind,
    sync_room_id,
    sync_event_type,
    source_row.id,
    now()
  );

  RETURN COALESCE(NEW,OLD);
END
$$;

DROP TRIGGER IF EXISTS messages_sync_event_trigger ON messages;

CREATE TRIGGER messages_sync_event_trigger
AFTER INSERT OR UPDATE OR DELETE ON messages
FOR EACH ROW
EXECUTE FUNCTION pulsemesh_record_message_sync_event();

CREATE OR REPLACE FUNCTION pulsemesh_record_hidden_message_sync_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  source_message_id uuid;
  source_user_id uuid;
  sync_room_kind text;
  sync_room_id uuid;
  sync_event_type text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    source_message_id := OLD.message_id;
    source_user_id := OLD.user_id;
    sync_event_type := 'message.upsert';
  ELSE
    source_message_id := NEW.message_id;
    source_user_id := NEW.user_id;
    sync_event_type := 'message.delete';
  END IF;

  SELECT
    CASE WHEN channel_id IS NOT NULL THEN 'channel' ELSE 'conversation' END,
    COALESCE(channel_id,conversation_id)
  INTO sync_room_kind,sync_room_id
  FROM messages
  WHERE id=source_message_id;

  IF sync_room_id IS NULL THEN
    RETURN COALESCE(NEW,OLD);
  END IF;

  INSERT INTO message_sync_events (
    room_kind,
    room_id,
    event_type,
    message_id,
    target_user_id,
    occurred_at
  )
  VALUES (
    sync_room_kind,
    sync_room_id,
    sync_event_type,
    source_message_id,
    source_user_id,
    now()
  );

  RETURN COALESCE(NEW,OLD);
END
$$;

DROP TRIGGER IF EXISTS message_hidden_users_sync_event_trigger
  ON message_hidden_users;

CREATE TRIGGER message_hidden_users_sync_event_trigger
AFTER INSERT OR DELETE ON message_hidden_users
FOR EACH ROW
EXECUTE FUNCTION pulsemesh_record_hidden_message_sync_event();

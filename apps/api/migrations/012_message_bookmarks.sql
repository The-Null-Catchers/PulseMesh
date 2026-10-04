CREATE TABLE message_bookmarks (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, message_id)
);

CREATE INDEX message_bookmarks_user_created_idx
  ON message_bookmarks (user_id, created_at DESC, message_id DESC);

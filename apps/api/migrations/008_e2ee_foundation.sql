ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS encryption_mode text NOT NULL DEFAULT 'none'
    CHECK (encryption_mode IN ('none','e2ee_v1'));

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS encryption_version text,
  ADD COLUMN IF NOT EXISTS encrypted_payload text;

ALTER TABLE messages
  ADD CONSTRAINT messages_encryption_shape_check
  CHECK (
    (encryption_version IS NULL AND encrypted_payload IS NULL)
    OR
    (
      encryption_version='libsignal-v1'
      AND encrypted_payload IS NOT NULL
      AND body=''
      AND octet_length(encrypted_payload) <= 262144
    )
  ) NOT VALID;

ALTER TABLE messages
  VALIDATE CONSTRAINT messages_encryption_shape_check;

CREATE TABLE IF NOT EXISTS e2ee_device_bundles (
  session_id uuid PRIMARY KEY REFERENCES sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  registration_id integer NOT NULL CHECK (registration_id BETWEEN 1 AND 2147483647),
  identity_key_public text NOT NULL,
  signed_pre_key_id integer NOT NULL CHECK (signed_pre_key_id >= 0),
  signed_pre_key_public text NOT NULL,
  signed_pre_key_signature text NOT NULL,
  revision bigint NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS e2ee_device_bundles_user_idx
  ON e2ee_device_bundles(user_id,updated_at DESC);

CREATE TABLE IF NOT EXISTS e2ee_one_time_prekeys (
  session_id uuid NOT NULL REFERENCES e2ee_device_bundles(session_id) ON DELETE CASCADE,
  key_id integer NOT NULL CHECK (key_id >= 0),
  public_key text NOT NULL,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(session_id,key_id)
);

CREATE INDEX IF NOT EXISTS e2ee_one_time_prekeys_available_idx
  ON e2ee_one_time_prekeys(session_id,key_id)
  WHERE claimed_at IS NULL;

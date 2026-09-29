INSERT INTO permissions (key,description) VALUES
  ('moderation.manage','Manage reports, timeouts, bans and channel locks'),
  ('audit.view','View workspace audit logs')
ON CONFLICT (key) DO NOTHING;

INSERT INTO role_permissions (role_id,permission_id)
SELECT r.id,p.id
FROM roles r
CROSS JOIN permissions p
WHERE
  r.is_system=true
  AND (
    r.name='Owner'
    OR (r.name='Admin' AND p.key IN ('moderation.manage','audit.view'))
    OR (r.name='Moderator' AND p.key='moderation.manage')
  )
  AND p.key IN ('moderation.manage','audit.view')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS workspace_bans (
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  banned_by uuid NOT NULL REFERENCES users(id),
  reason text,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(workspace_id,user_id)
);

CREATE INDEX IF NOT EXISTS workspace_bans_active_idx
  ON workspace_bans(workspace_id,expires_at)
  WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS workspace_moderation_rules (
  workspace_id uuid PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
  max_messages_per_10_seconds integer NOT NULL DEFAULT 8 CHECK (max_messages_per_10_seconds BETWEEN 1 AND 100),
  max_mentions_per_message integer NOT NULL DEFAULT 12 CHECK (max_mentions_per_message BETWEEN 1 AND 100),
  repeated_content_window_seconds integer NOT NULL DEFAULT 60 CHECK (repeated_content_window_seconds BETWEEN 5 AND 3600),
  repeated_content_limit integer NOT NULL DEFAULT 4 CHECK (repeated_content_limit BETWEEN 2 AND 50),
  updated_by uuid REFERENCES users(id),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE channels
  ADD COLUMN IF NOT EXISTS locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS locked_by uuid REFERENCES users(id);

CREATE INDEX IF NOT EXISTS reports_workspace_status_created_idx
  ON reports(workspace_id,status,created_at DESC,id DESC);

CREATE INDEX IF NOT EXISTS moderation_actions_workspace_created_idx
  ON moderation_actions(workspace_id,created_at DESC,id DESC);

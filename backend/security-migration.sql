-- Additive security migration: apply after admin-migration.sql.
CREATE TABLE IF NOT EXISTS muwa_request_limits (
 bucket text PRIMARY KEY, window_start timestamptz NOT NULL DEFAULT now(),
 attempts integer NOT NULL CHECK (attempts > 0), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS muwa_request_limits_updated_idx ON muwa_request_limits(updated_at);
CREATE TABLE IF NOT EXISTS publication_uploads (
 id uuid PRIMARY KEY, draft_id uuid NOT NULL REFERENCES publication_drafts(id),
 user_id integer NOT NULL REFERENCES users(id), part text NOT NULL CHECK (part IN ('audio','cover','submission')),
 filename text NOT NULL UNIQUE, content_type text NOT NULL,
 size_bytes bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 104857600),
 expected_sha256 text CHECK (expected_sha256 IS NULL OR expected_sha256 ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS publication_uploads_user_created_idx ON publication_uploads(user_id,created_at);
CREATE INDEX IF NOT EXISTS publication_uploads_draft_idx ON publication_uploads(draft_id);
ALTER TABLE publication_drafts ADD COLUMN IF NOT EXISTS media_snapshot jsonb;
ALTER TABLE catalog_uploads ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
CREATE INDEX IF NOT EXISTS publication_drafts_user_active_idx ON publication_drafts(user_id,created_at) WHERE status IN ('uploading','pending');
CREATE TABLE IF NOT EXISTS muwa_diagnostics (
 id uuid PRIMARY KEY, user_id integer NOT NULL REFERENCES users(id), platform text NOT NULL CHECK (platform IN ('iOS','Android')),
 version text NOT NULL, build text NOT NULL, area text NOT NULL, error_type text NOT NULL, error_code integer NOT NULL DEFAULT 0,
 occurred_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS muwa_diagnostics_received_idx ON muwa_diagnostics(received_at DESC);
CREATE INDEX IF NOT EXISTS muwa_diagnostics_user_received_idx ON muwa_diagnostics(user_id,received_at DESC);
-- No admin, Premium or auth-secret provisioning is part of this migration.

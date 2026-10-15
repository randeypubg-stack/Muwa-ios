-- Additive Muwa control panel schema. Existing accounts, sessions and contracts stay intact.
CREATE TABLE IF NOT EXISTS catalog_tracks (
 id text PRIMARY KEY CHECK (id ~ '^[A-Za-z0-9_-]{1,80}$'),
 title text NOT NULL, artist text NOT NULL, language text NOT NULL DEFAULT 'ar',
 duration double precision NOT NULL DEFAULT 0 CHECK (duration >= 0 AND duration <= 86400),
 audio_url text, artwork_url text, audio_filename text, cover_filename text,
 status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
 revision integer NOT NULL DEFAULT 1, captions_revision integer NOT NULL DEFAULT 0,
 captions jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(captions)='array'),
 source_submission_id uuid UNIQUE,
 created_by integer REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (status <> 'published' OR (duration > 0 AND audio_url IS NOT NULL AND length(trim(title)) > 0))
);
CREATE INDEX IF NOT EXISTS catalog_tracks_status_created_idx ON catalog_tracks(status,created_at DESC,id);
CREATE TABLE IF NOT EXISTS catalog_uploads (
 id uuid PRIMARY KEY, user_id integer NOT NULL REFERENCES users(id),
 track_id text REFERENCES catalog_tracks(id), submission_id uuid,
 files jsonb NOT NULL CHECK (jsonb_typeof(files)='array'),
 expires_at timestamptz NOT NULL, consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS catalog_uploads_expiry_idx ON catalog_uploads(expires_at);
CREATE TABLE IF NOT EXISTS publication_drafts (
 id uuid PRIMARY KEY, user_id integer REFERENCES users(id),
 status text NOT NULL DEFAULT 'uploading' CHECK (status IN ('uploading','pending','published','rejected')),
 title text NOT NULL DEFAULT '', artist text NOT NULL DEFAULT '', language text NOT NULL DEFAULT 'ar',
 audio_key text, cover_key text, rejection_reason text,
 track_id text REFERENCES catalog_tracks(id), revision integer NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS publication_drafts_status_updated_idx ON publication_drafts(status,updated_at DESC,id);
CREATE TABLE IF NOT EXISTS admin_audit_events (
 id bigserial PRIMARY KEY, actor_id integer REFERENCES users(id),
 action text NOT NULL, entity_id text NOT NULL, details jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS admin_audit_events_created_idx ON admin_audit_events(created_at DESC,id DESC);
-- No role/entitlement changes here. Assign the owner's admin role only after identity is specified.

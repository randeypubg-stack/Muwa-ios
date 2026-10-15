-- Apply after admin-migration.sql and security-migration.sql. No new accounts,
-- roles, Premium grants or public media access are created by this migration.
CREATE TABLE IF NOT EXISTS catalog_audio_fingerprints (
 track_id text PRIMARY KEY REFERENCES catalog_tracks(id) ON DELETE CASCADE,
 sha256 text NOT NULL CHECK (sha256 ~ '^[a-f0-9]{64}$'),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS catalog_audio_fingerprints_sha_idx
 ON catalog_audio_fingerprints(sha256,track_id);
CREATE TABLE IF NOT EXISTS catalog_telegram_sources (
 channel_id text NOT NULL CHECK (channel_id ~ '^-[0-9]{13,16}$'),
 message_id integer NOT NULL CHECK (message_id > 0),
 audio_sha256 text NOT NULL CHECK (audio_sha256 ~ '^[a-f0-9]{64}$'),
 track_id text NOT NULL REFERENCES catalog_tracks(id),
 imported_by integer NOT NULL REFERENCES users(id),
 imported_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (channel_id,message_id)
);
CREATE INDEX IF NOT EXISTS catalog_telegram_sources_track_idx
 ON catalog_telegram_sources(track_id);
-- Forwarding to an owner-only bot has its own namespace. A private chat or
-- bot ID must never be misrepresented as the ID of a broadcast channel.
CREATE TABLE IF NOT EXISTS catalog_telegram_bot_sources (
 bot_id bigint NOT NULL CHECK (bot_id > 0 AND bot_id <= 9007199254740991),
 chat_id bigint NOT NULL CHECK (chat_id > 0 AND chat_id <= 9007199254740991),
 message_id integer NOT NULL CHECK (message_id > 0),
 audio_sha256 text NOT NULL CHECK (audio_sha256 ~ '^[a-f0-9]{64}$'),
 track_id text NOT NULL REFERENCES catalog_tracks(id) ON DELETE CASCADE,
 imported_by integer NOT NULL REFERENCES users(id),
 imported_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (bot_id,chat_id,message_id)
);
CREATE INDEX IF NOT EXISTS catalog_telegram_bot_sources_track_idx
 ON catalog_telegram_bot_sources(track_id);
-- Existing static tracks have no verified local fingerprint. They are never
-- falsely declared deduplicated by title. Backfill requires reading their bytes.

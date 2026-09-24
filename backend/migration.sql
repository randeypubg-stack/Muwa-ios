CREATE TABLE IF NOT EXISTS subtitle_vtwo_cache (
 cache_key text PRIMARY KEY,
 kind text NOT NULL CHECK(kind IN ('original','translation')),
 payload jsonb,
 lease_token text NOT NULL,
 lease_until timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS subtitle_vtwo_limits (
 user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 usage_day date NOT NULL,
 calls integer NOT NULL CHECK(calls >= 0),
 PRIMARY KEY(user_id,usage_day)
);

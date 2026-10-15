-- Fresh Beget installation, explicitly selected by the owner on 4 October 2026.
-- Do not run against or replace the old Floot database.
CREATE TYPE user_role AS ENUM ('user','admin');
CREATE TABLE users (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 email text NOT NULL, display_name text NOT NULL,
 avatar_url text, role user_role NOT NULL DEFAULT 'user',
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (email = lower(trim(email)) AND length(email) <= 254)
);
CREATE UNIQUE INDEX users_email_idx ON users (lower(email));
CREATE TABLE user_passwords (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id integer NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
 password_hash text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE sessions (
 id text PRIMARY KEY CHECK (id ~ '^[a-f0-9]{64}$'),
 user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(), last_accessed timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL
);
CREATE INDEX sessions_user_idx ON sessions(user_id);
CREATE INDEX sessions_expiry_idx ON sessions(expires_at);
CREATE TABLE login_attempts (
 id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 email text NOT NULL, success boolean NOT NULL DEFAULT false,
 attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_failed_idx ON login_attempts(email,attempted_at DESC) WHERE success=false;
CREATE INDEX login_attempts_time_idx ON login_attempts(attempted_at);
CREATE TABLE owner_setup (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 token_hash text NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz NOT NULL, consumed_at timestamptz,
 email text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);

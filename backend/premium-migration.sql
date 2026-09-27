CREATE TABLE IF NOT EXISTS premium_access (
  user_id integer PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz, updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS premium_code_admins (user_id integer PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS premium_codes (
  id uuid PRIMARY KEY, code_hash text NOT NULL UNIQUE, label text NOT NULL,
  duration_days integer NOT NULL CHECK(duration_days BETWEEN 1 AND 365),
  max_uses integer NOT NULL CHECK(max_uses BETWEEN 1 AND 1000),
  uses integer NOT NULL DEFAULT 0 CHECK(uses >= 0 AND uses <= max_uses),
  expires_at timestamptz NOT NULL, disabled boolean NOT NULL DEFAULT false,
  created_by integer NOT NULL REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS premium_redemptions (
  code_id uuid NOT NULL REFERENCES premium_codes(id), user_id integer NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(code_id,user_id)
);
CREATE TABLE IF NOT EXISTS premium_code_limits (
  user_id integer PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  window_start timestamptz NOT NULL DEFAULT now(), attempts integer NOT NULL DEFAULT 1
);
-- Provisioning an owner's grant/admin is a separate, explicitly authorized operation.
-- Never infer entitlement or administration from a client-supplied email.

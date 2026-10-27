-- Social Clone license dashboard — D1 schema (free tier).
-- Apply with: wrangler d1 execute social-clone-dashboard --file=schema.sql
-- (or the D1 REST query endpoint once a token with D1 scope exists).

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'teacher')),
  salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  balance_pkr INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

-- Wallet ledger: admin credits a teacher's PKR balance; each teacher
-- self-generated code debits it (SC5 Rs 1,400, SC10 Rs 1,680).
-- Existing live databases created from the older schema need:
--   ALTER TABLE users ADD COLUMN balance_pkr INTEGER NOT NULL DEFAULT 0;
-- plus the transactions table below (CREATE IF NOT EXISTS covers it).
CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY,
  teacher_id TEXT NOT NULL REFERENCES users(id),
  kind TEXT NOT NULL CHECK (kind IN ('credit', 'debit')),
  amount_pkr INTEGER NOT NULL,
  tier TEXT,
  code TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  created_by TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  expires_at INTEGER NOT NULL
);

-- Status meanings:
--   unused      — issued, never redeemed (or reactivated: binding cleared).
--   used        — redeemed and bound to a device (activated).
--   deactivated — admin-disabled; redeem is rejected until reactivated.
-- expires_at is OPTIONAL (NULL = never expires). A code whose expires_at
-- is set and in the past is "expired": redeem rejects it, and the report
-- counts it separately. No code that exists today has an expiry, so
-- adding the column changes nothing for existing rows.
-- NOTE: this dashboard has never been deployed, so no live D1 database
-- exists yet; this schema is what a fresh deploy creates. A pre-existing
-- test database built from the older schema must be recreated (the
-- CHECK constraint on status cannot be widened by ALTER TABLE alone).
CREATE TABLE IF NOT EXISTS licenses (
  code TEXT PRIMARY KEY,
  tier TEXT NOT NULL CHECK (tier IN ('SC5', 'SC10')),
  max_profiles INTEGER NOT NULL,
  teacher_id TEXT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'unused' CHECK (status IN ('unused', 'used', 'deactivated')),
  device_id TEXT,
  redeemed_at INTEGER,
  expires_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_licenses_teacher ON licenses (teacher_id);
CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses (status);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_teacher ON transactions (teacher_id);

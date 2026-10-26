-- Social Clone license dashboard — D1 schema (free tier).
-- Apply with: wrangler d1 execute social-clone-dashboard --file=schema.sql
-- (or the D1 REST query endpoint once a token with D1 scope exists).

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('admin', 'teacher')),
  salt TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  expires_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS licenses (
  code TEXT PRIMARY KEY,
  tier TEXT NOT NULL CHECK (tier IN ('SC5', 'SC10')),
  max_profiles INTEGER NOT NULL,
  teacher_id TEXT NOT NULL REFERENCES users(id),
  status TEXT NOT NULL DEFAULT 'unused' CHECK (status IN ('unused', 'used')),
  device_id TEXT,
  redeemed_at INTEGER,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_licenses_teacher ON licenses (teacher_id);
CREATE INDEX IF NOT EXISTS idx_licenses_status ON licenses (status);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions (user_id);

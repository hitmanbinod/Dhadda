-- Dhadda sync vault. The server stores ciphertext only; never plaintext data.
CREATE TABLE IF NOT EXISTS vaults (
  vault_id   TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_seq   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS rows (
  vault_id  TEXT NOT NULL,
  t         TEXT NOT NULL,
  id        TEXT NOT NULL,
  ua        INTEGER NOT NULL,
  d         INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  iv        TEXT NOT NULL,
  ct        TEXT NOT NULL,
  seq       INTEGER NOT NULL,
  pushed_at INTEGER NOT NULL,
  PRIMARY KEY (vault_id, t, id),
  FOREIGN KEY (vault_id) REFERENCES vaults(vault_id)
);

CREATE INDEX IF NOT EXISTS idx_rows_seq ON rows(vault_id, seq);
CREATE INDEX IF NOT EXISTS idx_rows_ua ON rows(vault_id, t, id, ua);

-- Server-side tombstones older than 180 days (pushed_at) may be deleted by a
-- maintenance job; local tombstones are kept longer by both clients.

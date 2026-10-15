
CREATE TABLE IF NOT EXISTS branches (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,
  branch_id TEXT,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  price INTEGER NOT NULL DEFAULT 0,
  stock INTEGER NOT NULL DEFAULT 0,
  image_key TEXT,
  updated_at TEXT NOT NULL,
  UNIQUE(branch_id, code)
);

CREATE INDEX IF NOT EXISTS idx_products_code
ON products(code);

CREATE INDEX IF NOT EXISTS idx_products_name
ON products(name);

CREATE TABLE IF NOT EXISTS transactions (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  branch_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  payment TEXT NOT NULL,
  total INTEGER NOT NULL,
  payload TEXT NOT NULL,
  received_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_transactions_branch_time
ON transactions(branch_id, created_at);

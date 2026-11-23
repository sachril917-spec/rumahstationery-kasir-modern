-- ADL central module records. Additive only; does not alter cashier tables or stock.
CREATE TABLE IF NOT EXISTS adl_central_records (
 id TEXT PRIMARY KEY, module TEXT NOT NULL, title TEXT NOT NULL,
 code TEXT NOT NULL DEFAULT '', branch TEXT NOT NULL DEFAULT '',
 quantity REAL NOT NULL DEFAULT 0, amount INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL DEFAULT 'AKTIF', payload TEXT NOT NULL DEFAULT '{}',
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_adl_central_module_date ON adl_central_records(module,created_at);

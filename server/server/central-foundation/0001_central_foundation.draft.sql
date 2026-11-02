-- DRAF SAJA: jangan jalankan di D1 produksi sebelum audit dan backup.
-- Tabel lama branches/products/transactions sengaja tidak diubah.

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  branch_id TEXT NOT NULL,
  device_name TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('android', 'windows')),
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT NOT NULL,
  last_seen_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_devices_branch_active ON devices(branch_id, active);

CREATE TABLE IF NOT EXISTS product_prices (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  price_type TEXT NOT NULL CHECK (price_type IN ('retail', 'wholesale', 'member')),
  min_quantity INTEGER NOT NULL DEFAULT 1 CHECK (min_quantity >= 1),
  price INTEGER NOT NULL CHECK (price >= 0),
  effective_from TEXT NOT NULL,
  effective_until TEXT,
  updated_at TEXT NOT NULL,
  UNIQUE(product_id, price_type, min_quantity, effective_from)
);
CREATE INDEX IF NOT EXISTS idx_product_prices_product_date
ON product_prices(product_id, effective_from, effective_until);

CREATE TABLE IF NOT EXISTS stock_movements (
  id TEXT PRIMARY KEY,
  branch_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  movement_type TEXT NOT NULL CHECK (
    movement_type IN ('opening', 'purchase_receipt', 'transfer_in', 'transfer_out',
                      'sale', 'sale_return', 'adjustment')
  ),
  quantity INTEGER NOT NULL CHECK (quantity <> 0),
  reference_id TEXT,
  device_id TEXT,
  occurred_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_stock_movements_branch_product_time
ON stock_movements(branch_id, product_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements(reference_id);

CREATE TABLE IF NOT EXISTS stock_transfers (
  id TEXT PRIMARY KEY,
  source_branch_id TEXT NOT NULL,
  destination_branch_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'sent', 'received', 'cancelled')),
  created_by_device_id TEXT,
  received_by_device_id TEXT,
  created_at TEXT NOT NULL,
  sent_at TEXT,
  received_at TEXT,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_source_status
ON stock_transfers(source_branch_id, status);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_destination_status
ON stock_transfers(destination_branch_id, status);

CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id TEXT PRIMARY KEY,
  transfer_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity_sent INTEGER NOT NULL CHECK (quantity_sent > 0),
  quantity_received INTEGER CHECK (quantity_received IS NULL OR quantity_received >= 0),
  UNIQUE(transfer_id, product_id),
  FOREIGN KEY (transfer_id) REFERENCES stock_transfers(id)
);

CREATE TABLE IF NOT EXISTS sync_receipts (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  response_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sync_receipts_device_time ON sync_receipts(device_id, created_at);

CREATE TABLE IF NOT EXISTS audit_log (
  id TEXT PRIMARY KEY,
  actor_device_id TEXT,
  branch_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  details_json TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_audit_log_branch_time ON audit_log(branch_id, created_at);

-- Rumah Stationery / ADL - additive central purchasing schema
-- DESIGN/MIGRATION SCRIPT ONLY: NOT EXECUTED.
-- Does not alter or delete existing app tables/data. Back up D1 before applying.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS central_branches (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  branch_type TEXT NOT NULL CHECK (branch_type IN ('WAREHOUSE','STORE')),
  address TEXT, phone TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS suppliers (
  id TEXT PRIMARY KEY, supplier_code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
  contact_person TEXT, phone TEXT, email TEXT, address TEXT, tax_number TEXT, notes TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- One central catalog; inventory is tracked separately per location.
CREATE TABLE IF NOT EXISTS master_products (
  id TEXT PRIMARY KEY, barcode TEXT UNIQUE, sku TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
  category TEXT, brand TEXT, unit TEXT NOT NULL DEFAULT 'pcs', purchase_unit TEXT,
  conversion_factor REAL NOT NULL DEFAULT 1 CHECK (conversion_factor > 0),
  default_cost INTEGER NOT NULL DEFAULT 0 CHECK (default_cost >= 0),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  image_key TEXT, notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS product_prices (
  id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES master_products(id),
  price_level TEXT NOT NULL, min_quantity REAL NOT NULL DEFAULT 1 CHECK (min_quantity > 0),
  price INTEGER NOT NULL CHECK (price >= 0), valid_from TEXT, valid_until TEXT,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(product_id, price_level, min_quantity, valid_from)
);

CREATE TABLE IF NOT EXISTS purchases (
  id TEXT PRIMARY KEY, purchase_number TEXT NOT NULL UNIQUE,
  supplier_id TEXT NOT NULL REFERENCES suppliers(id),
  warehouse_branch_id TEXT NOT NULL REFERENCES central_branches(id),
  supplier_invoice_number TEXT, purchase_date TEXT NOT NULL, due_date TEXT,
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ORDERED','PARTIAL','RECEIVED','CANCELLED')),
  subtotal INTEGER NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  discount_total INTEGER NOT NULL DEFAULT 0 CHECK (discount_total >= 0),
  tax_total INTEGER NOT NULL DEFAULT 0 CHECK (tax_total >= 0),
  grand_total INTEGER NOT NULL DEFAULT 0 CHECK (grand_total >= 0),
  notes TEXT, created_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS purchase_items (
  id TEXT PRIMARY KEY, purchase_id TEXT NOT NULL REFERENCES purchases(id),
  product_id TEXT NOT NULL REFERENCES master_products(id),
  quantity REAL NOT NULL CHECK (quantity > 0), unit TEXT NOT NULL,
  unit_cost INTEGER NOT NULL CHECK (unit_cost >= 0),
  discount INTEGER NOT NULL DEFAULT 0 CHECK (discount >= 0),
  line_total INTEGER NOT NULL CHECK (line_total >= 0),
  received_quantity REAL NOT NULL DEFAULT 0 CHECK (received_quantity >= 0), notes TEXT
);

CREATE TABLE IF NOT EXISTS goods_receipts (
  id TEXT PRIMARY KEY, receipt_number TEXT NOT NULL UNIQUE,
  purchase_id TEXT NOT NULL REFERENCES purchases(id),
  warehouse_branch_id TEXT NOT NULL REFERENCES central_branches(id),
  received_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'POSTED' CHECK (status IN ('DRAFT','POSTED','VOID')),
  received_by TEXT, notes TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS goods_receipt_items (
  id TEXT PRIMARY KEY, receipt_id TEXT NOT NULL REFERENCES goods_receipts(id),
  purchase_item_id TEXT NOT NULL REFERENCES purchase_items(id),
  product_id TEXT NOT NULL REFERENCES master_products(id),
  quantity REAL NOT NULL CHECK (quantity > 0), unit_cost INTEGER NOT NULL CHECK (unit_cost >= 0)
);

CREATE TABLE IF NOT EXISTS location_stock (
  location_id TEXT NOT NULL REFERENCES central_branches(id),
  product_id TEXT NOT NULL REFERENCES master_products(id),
  quantity REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY(location_id, product_id)
);

CREATE TABLE IF NOT EXISTS stock_movements (
  id TEXT PRIMARY KEY, product_id TEXT NOT NULL REFERENCES master_products(id),
  from_location_id TEXT REFERENCES central_branches(id),
  to_location_id TEXT REFERENCES central_branches(id),
  movement_type TEXT NOT NULL CHECK (movement_type IN ('PURCHASE_RECEIPT','TRANSFER_OUT','TRANSFER_IN','ADJUSTMENT_IN','ADJUSTMENT_OUT','SALE','RETURN')),
  quantity REAL NOT NULL CHECK (quantity > 0), unit_cost INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
  reference_type TEXT, reference_id TEXT, occurred_at TEXT NOT NULL, created_by TEXT, notes TEXT,
  CHECK (from_location_id IS NOT NULL OR to_location_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS branch_transfers (
  id TEXT PRIMARY KEY, transfer_number TEXT NOT NULL UNIQUE,
  from_location_id TEXT NOT NULL REFERENCES central_branches(id),
  to_location_id TEXT NOT NULL REFERENCES central_branches(id), transfer_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','SENT','PARTIAL','RECEIVED','CANCELLED')),
  notes TEXT, created_by TEXT, received_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK (from_location_id <> to_location_id)
);

CREATE TABLE IF NOT EXISTS branch_transfer_items (
  id TEXT PRIMARY KEY, transfer_id TEXT NOT NULL REFERENCES branch_transfers(id),
  product_id TEXT NOT NULL REFERENCES master_products(id),
  quantity_sent REAL NOT NULL CHECK (quantity_sent > 0),
  quantity_received REAL NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
  unit_cost INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost >= 0), notes TEXT
);

CREATE TABLE IF NOT EXISTS supplier_payments (
  id TEXT PRIMARY KEY, purchase_id TEXT NOT NULL REFERENCES purchases(id),
  supplier_id TEXT NOT NULL REFERENCES suppliers(id), payment_date TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0), payment_method TEXT NOT NULL,
  reference_number TEXT, notes TEXT, created_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Store password hashes only, never plain-text passwords.
CREATE TABLE IF NOT EXISTS app_users (
  id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('OWNER','ADMIN','PURCHASING','WAREHOUSE','FINANCE','BRANCH_MANAGER','CASHIER')),
  location_id TEXT REFERENCES central_branches(id),
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)), last_login_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY, user_id TEXT REFERENCES app_users(id), action TEXT NOT NULL,
  entity_type TEXT NOT NULL, entity_id TEXT, before_json TEXT, after_json TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_master_products_name ON master_products(name);
CREATE INDEX IF NOT EXISTS idx_product_prices_product ON product_prices(product_id, price_level);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier_date ON purchases(supplier_id, purchase_date);
CREATE INDEX IF NOT EXISTS idx_purchases_status ON purchases(status, purchase_date);
CREATE INDEX IF NOT EXISTS idx_receipts_purchase ON goods_receipts(purchase_id, received_at);
CREATE INDEX IF NOT EXISTS idx_location_stock_product ON location_stock(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_date ON stock_movements(product_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_transfers_date_status ON branch_transfers(transfer_date, status);
CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier_date ON supplier_payments(supplier_id, payment_date);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id, created_at);

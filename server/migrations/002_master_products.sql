-- Master barang terpusat ADL. Tidak menyimpan stok cabang.
CREATE TABLE IF NOT EXISTS master_products (
 code TEXT PRIMARY KEY, barcode TEXT NOT NULL DEFAULT '', name TEXT NOT NULL DEFAULT '',
 cost_price INTEGER NOT NULL DEFAULT 0, price INTEGER NOT NULL DEFAULT 0, middle_price INTEGER NOT NULL DEFAULT 0, middle_qty INTEGER NOT NULL DEFAULT 1, member_price INTEGER NOT NULL DEFAULT 0,
 unit TEXT NOT NULL DEFAULT 'PCS', unit2 TEXT NOT NULL DEFAULT '', unit2_qty INTEGER NOT NULL DEFAULT 1, unit3 TEXT NOT NULL DEFAULT '', unit3_qty INTEGER NOT NULL DEFAULT 1,
 sales_price INTEGER NOT NULL DEFAULT 0, special_price INTEGER NOT NULL DEFAULT 0, supplier_code TEXT NOT NULL DEFAULT '', discount INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_master_products_name ON master_products(name);
CREATE INDEX IF NOT EXISTS idx_master_products_barcode ON master_products(barcode);

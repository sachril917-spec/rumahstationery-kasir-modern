# Fondasi Server Pusat — Rumah Stationery

## Status aman
Paket ini ditujukan untuk branch `feature/central-server-foundation`, bukan `main`. Paket ini belum mengubah aplikasi Flutter, Worker produksi, database D1, atau data transaksi.

File SQL di bawah adalah DRAF MIGRASI. Jangan jalankan di D1 produksi sebelum nama binding, ID database, skema aktif, dan backup diverifikasi.

## Arsitektur sasaran
1. Android dan Windows tetap menyimpan transaksi pada SQLite lokal agar kasir tetap berjalan saat internet putus.
2. Cloudflare Worker menjadi API HTTPS antara perangkat cabang dan D1.
3. Kantor pusat mengelola master barang dan daftar harga.
4. Penjualan dan mutasi stok dikirim sebagai antrean yang dapat dicoba ulang.
5. Setiap kiriman memakai ID unik agar retry tidak menggandakan transaksi atau mutasi stok.
6. Transfer stok memakai status draft, sent, received, atau cancelled. Stok cabang tujuan baru bertambah setelah penerimaan dikonfirmasi.

## Tabel tambahan dalam draf
`devices`, `product_prices`, `stock_movements`, `stock_transfers`, `stock_transfer_items`, `sync_receipts`, dan `audit_log`.

Draf sengaja tidak mengubah tabel lama `branches`, `products`, dan `transactions`.

## Langkah sebelum API dibuat
1. Verifikasi Worker dan D1 yang benar-benar aktif, lalu backup database.
2. Cocokkan binding D1 dan skema transaksi aktif dengan kode Worker.
3. Review draf SQL dan uji pada database staging.
4. Buat autentikasi perangkat dan sinkronisasi master.
5. Uji satu perangkat Windows dan satu Android.
6. Pilot satu cabang, lalu perluas bertahap ke 17 cabang.

## Keamanan
- Jangan menaruh API key rahasia di GitHub atau kode sumber.
- Jangan memakai satu identitas perangkat untuk semua kasir.
- Batasi perangkat ke cabang yang terdaftar.
- Gunakan HTTPS, validasi payload, batas ukuran batch, dan audit log.
- Sediakan backup dan prosedur pemulihan sebelum migrasi.

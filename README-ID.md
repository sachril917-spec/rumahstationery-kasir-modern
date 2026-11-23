# Rumah Stationery Kasir — Flutter starter

Ini source code awal, bukan APK/EXE yang sudah dibangun. Aplikasi memakai SQLite lokal agar transaksi dasar dapat dicatat tanpa internet.

## Saat ini tersedia
- Kasir sederhana, pencarian barang, keranjang, diskon, metode pembayaran.
- Simpan transaksi dan stok lokal.
- Daftar/tambah barang dasar.
- Database SQLite dengan indeks nama dan kode.
- Skema awal database server dan Worker health check.

## Belum tersedia
Server pusat aktif, login, sinkronisasi multi-perangkat, konflik stok, impor massal Excel, foto produk, scan kamera, printer struk, retur, laporan lengkap, dan pengujian performa 15.000 item. Jangan gunakan untuk pembukuan operasional sungguhan sebelum fungsi tersebut selesai dan diuji.

## Build Android
Memerlukan komputer/lingkungan build dengan Flutter SDK dan Android SDK:
1. Ekstrak ZIP.
2. Jalankan `flutter pub get`.
3. Jalankan `flutter run`.
4. Build APK: `flutter build apk --release`.
File hasil biasanya `build/app/outputs/flutter-apk/app-release.apk`.

## Build Windows
Memerlukan Windows, Flutter SDK, Visual Studio workload Desktop development with C++:
1. `flutter config --enable-windows-desktop`
2. `flutter create --platforms=windows .` (jika folder platform belum ada)
3. `flutter pub get`
4. `flutter build windows --release`

Server folder hanya starter. Worker belum mengaktifkan sync. Sebelum produksi, implementasikan autentikasi, otorisasi cabang, validasi, idempotensi transaksi, antrean sync, aturan konflik stok, backup, dan audit log.


## Update Server Pusat ADL - modul dasar (tambahan)
1. Backup database D1 sebelum deploy.
2. Jalankan SQL `server/migrations/003_adl_central_modules.sql` pada D1. SQL ini hanya membuat tabel `adl_central_records` dan index baru; tidak mengubah tabel kasir.
3. Deploy `server/worker.js` ke Worker yang sama.
4. Build ulang Admin Android dan Windows dari folder masing-masing.
5. Hubungkan Admin memakai `ADMIN_API_KEY`.

Menu Data Cabang, Pembelian, Supplier, Gudang Pusat, Distribusi, Stok Cabang, Harga Jual, Pengeluaran, Hutang Supplier, Pengguna, dan Riwayat Aktivitas kini mempunyai penyimpanan catatan dasar di server. Catatan ini belum melakukan posting stok otomatis atau perhitungan hutang/pembayaran; proses transaksi inventori penuh memerlukan tahap workflow berikutnya. Tabel dan transaksi kasir lama tidak dihapus.

### Catatan kompatibilitas migrasi
Gunakan hanya `server/migrations/003_adl_central_modules.sql` untuk menu catatan dasar pada paket ini. Jangan jalankan `001_central_purchasing.sql` pada database yang sudah memakai tabel `master_products` dari `002_master_products.sql`/Worker lama sebelum skema master disatukan; kedua rancangan tersebut memakai bentuk tabel `master_products` yang berbeda. Migrasi 003 aman berdampingan karena hanya membuat `adl_central_records`.

### Batas fungsi paket ini
Menu tambahan saat ini mendukung tambah, daftar, muat ulang, dan hapus catatan dasar per modul. Ini membuat menu tidak lagi menjadi halaman kosong dan datanya tersimpan di D1. Paket ini belum mengotomatiskan alur bisnis lengkap seperti posting penerimaan ke stok gudang, pengurangan stok saat transfer, penerimaan cabang, kalkulasi saldo hutang, maupun pembatasan hak akses per peran. Jangan gunakan catatan dasar ini sebagai pembukuan final sebelum alur transaksi tersebut ditambahkan dan diuji.

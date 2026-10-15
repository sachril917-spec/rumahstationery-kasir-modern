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

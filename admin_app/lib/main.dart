import 'package:flutter/material.dart';

void main() => runApp(const AdlAdminApp());

class AdlAdminApp extends StatelessWidget {
  const AdlAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Server ADL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF17365D),
        ),
      ),
      home: const AdminHome(),
    );
  }
}

const menus = [
  ('Dashboard', Icons.dashboard),
  ('Data Cabang', Icons.store),
  ('Pembelian', Icons.shopping_cart),
  ('Supplier', Icons.local_shipping),
  ('Master Barang', Icons.inventory_2),
  ('Barang Masuk', Icons.move_to_inbox),
  ('Gudang Pusat', Icons.warehouse),
  ('Distribusi Cabang', Icons.outbox),
  ('Stok Cabang', Icons.storefront),
  ('Harga Jual', Icons.sell),
  ('Penjualan', Icons.point_of_sale),
  ('Pengeluaran', Icons.receipt_long),
  ('Hutang Supplier', Icons.account_balance_wallet),
  ('Laporan', Icons.analytics),
  ('Pengguna & Hak Akses', Icons.manage_accounts),
  ('Riwayat Aktivitas', Icons.history),
  ('Pengaturan Server', Icons.settings),
];

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ADMIN SERVER ADL'),
      ),
      drawer: NavigationDrawer(
        selectedIndex: selected,
        onDestinationSelected: (i) {
          setState(() => selected = i);
          Navigator.pop(context);
        },
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'RUMAH STATIONERY',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (int i = 0; i < menus.length; i++)
            NavigationDrawerDestination(
              icon: Icon(menus[i].$2),
              label: Text(menus[i].$1),
            ),
        ],
      ),
      body: selected == 0
          ? dashboard()
          : modulePage(menus[selected].$1),
    );
  }

  Widget dashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Dashboard Pusat',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const Text('Pengelolaan 17 cabang dan 1 gudang pusat'),
        const SizedBox(height: 20),
        stat('17', 'Cabang'),
        stat('1', 'Gudang Pusat'),
        stat('—', 'Master Barang'),
        stat('—', 'Penjualan Hari Ini'),
        const SizedBox(height: 15),
        const Text(
          'MENU OPERASIONAL',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (int i = 1; i < menus.length; i++)
          Card(
            child: ListTile(
              leading: Icon(menus[i].$2),
              title: Text(menus[i].$1),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => selected = i),
            ),
          ),
      ],
    );
  }

  Widget stat(String value, String label) {
    return Card(
      child: ListTile(
        title: Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(label),
      ),
    );
  }

  Widget modulePage(String name) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 45),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Menu sudah disiapkan. '
              'Fungsi penyimpanan dan koneksi database '
              'akan dihubungkan pada tahap integrasi server.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
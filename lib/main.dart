
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await KasirDB.instance.init();
  runApp(const RumahStationeryApp());
}

class KasirDB {
  KasirDB._();
  static final instance = KasirDB._();
  late Database db;

  Future<void> init() async {
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'rumah_stationery.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id TEXT PRIMARY KEY,
            code TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            price INTEGER NOT NULL,
            stock INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_product_name ON products(name)'
        );
        await db.execute(
          'CREATE INDEX idx_product_code ON products(code)'
        );
        await db.execute('''
          CREATE TABLE transactions(
            id TEXT PRIMARY KEY,
            time TEXT NOT NULL,
            branch TEXT NOT NULL,
            payment TEXT NOT NULL,
            total INTEGER NOT NULL,
            payload TEXT NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        final samples = [
          ['RS001', 'Pulpen Standard', 2500, 120],
          ['RS002', 'Buku Tulis', 3000, 85],
          ['RS003', 'Tinta Epson 664', 95000, 24],
          ['RS004', 'Kertas A4', 58000, 60],
        ];
        for (final item in samples) {
          await db.insert('products', {
            'id': const Uuid().v4(),
            'code': item[0],
            'name': item[1],
            'price': item[2],
            'stock': item[3],
          });
        }
      },
    );
  }

  Future<List<Map<String, Object?>>> searchProducts(
      String query) async {
    if (query.trim().isEmpty) {
      return db.query(
        'products',
        orderBy: 'name COLLATE NOCASE',
        limit: 300,
      );
    }
    return db.query(
      'products',
      where: 'name LIKE ? OR code LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'name COLLATE NOCASE',
      limit: 100,
    );
  }

  Future<void> addProduct(
    String code, String name, int price, int stock,
  ) async {
    await db.insert('products', {
      'id': const Uuid().v4(),
      'code': code.trim(),
      'name': name.trim(),
      'price': price,
      'stock': stock,
    });
  }

  Future<void> saveTransaction({
    required List<Map<String, dynamic>> items,
    required String payment,
    required int total,
    required String branch,
  }) async {
    final transactionId = const Uuid().v4();

    await db.transaction((txn) async {
      for (final item in items) {
        final rows = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [item['id']],
        );

        if (rows.isNotEmpty) {
          final currentStock = rows.first['stock'] as int;
          final quantity = item['qty'] as int;

          if (currentStock < quantity) {
            throw Exception('Stok tidak mencukupi');
          }

          await txn.update(
            'products',
            {'stock': currentStock - quantity},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }

      await txn.insert('transactions', {
        'id': transactionId,
        'time': DateTime.now().toUtc().toIso8601String(),
        'branch': branch,
        'payment': payment,
        'total': total,
        'payload': items.toString(),
        'sync_status': 'pending',
      });
    });
  }
}

class RumahStationeryApp extends StatelessWidget {
  const RumahStationeryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rumah Stationery Kasir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1769E0),
        ),
        useMaterial3: true,
      ),
      home: const KasirHome(),
    );
  }
}

class KasirHome extends StatefulWidget {
  const KasirHome({super.key});

  @override
  State<KasirHome> createState() => _KasirHomeState();
}

class _KasirHomeState extends State<KasirHome> {
  final searchController = TextEditingController();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final priceController = TextEditingController();
  final stockController = TextEditingController();
  List<Map<String, Object?>> products = [];
  final Map<String, Map<String, dynamic>> cart = {};
  String payment = 'Tunai';
  String branch = 'Rumah Stationery';
  int page = 0;

  int get subtotal => cart.values.fold(
    0,
    (sum, item) =>
      sum + (item['price'] as int) * (item['qty'] as int),
  );

  String money(int value) =>
      'Rp ${value.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]}.',
      )}';

  @override
  void initState() {
    super.initState();
    refreshProducts();
  }

  @override
  void dispose() {
    searchController.dispose();
    codeController.dispose();
    nameController.dispose();
    priceController.dispose();
    stockController.dispose();
    super.dispose();
  }

  Future<void> refreshProducts() async {
    final result = await KasirDB.instance.searchProducts(
      searchController.text,
    );
    if (mounted) setState(() => products = result);
  }

  void addToCart(Map<String, Object?> product) {
    final id = product['id'] as String;
    setState(() {
      if (cart.containsKey(id)) {
        cart[id]!['qty'] = (cart[id]!['qty'] as int) + 1;
      } else {
        cart[id] = {
          'id': id,
          'name': product['name'],
          'price': product['price'],
          'qty': 1,
        };
      }
    });
  }

  void notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      cashierPage(),
      productPage(),
      
FutureBuilder<List<Map<String, Object?>>>(
  future: KasirDB.instance.db.query(
    'transactions',
    orderBy: 'time DESC',
  ),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(
        child: Text('Gagal membaca transaksi: ${snapshot.error}'),
      );
    }

    final rows = snapshot.data ?? [];

    if (rows.isEmpty) {
      return const Center(
        child: Text('Belum ada transaksi tersimpan'),
      );
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text('Rp ${row['total'] ?? 0}'),
            subtitle: Text(
              '${row['time'] ?? '-'}\n'
              'Pembayaran: ${row['payment'] ?? '-'} • '
              'Status: ${row['sync_status'] ?? 'pending'}',
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  },
)
,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RUMAH STATIONERY',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF102A56),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(child: pages[page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (value) =>
            setState(() => page = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale),
            label: 'Kasir',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2),
            label: 'Barang',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Transaksi',
          ),
        ],
      ),
    );
  }

  Widget cashierPage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Cari nama atau kode barang',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => refreshProducts(),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              childAspectRatio: 1.35,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Card(
                child: InkWell(
                  onTap: () => addToCart(product),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.inventory_2_outlined),
                        Text(
                          '${product['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          money(product['price'] as int),
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text('Stok ${product['stock']}'),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                'Keranjang: ${cart.length} jenis • ${money(subtotal)}',
              ),
              DropdownButton<String>(
                value: payment,
                items: ['Tunai', 'Transfer', 'QRIS']
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => payment = value ?? 'Tunai'),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (cart.isEmpty) {
                      notify('Keranjang masih kosong');
                      return;
                    }
                    try {
                      await KasirDB.instance.saveTransaction(
                        items: cart.values
                            .map((item) =>
                                Map<String, dynamic>.from(item))
                            .toList(),
                        payment: payment,
                        total: subtotal,
                        branch: branch,
                      );
                      setState(() => cart.clear());
                      await refreshProducts();
                      notify('Transaksi tersimpan secara offline');
                    } catch (error) {
                      notify('Transaksi gagal: $error');
                    }
                  },
                  child: Text('Bayar • ${money(subtotal)}'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget productPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Tambah barang',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        TextField(
          controller: codeController,
          decoration: const InputDecoration(labelText: 'Kode barang'),
        ),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nama barang'),
        ),
        TextField(
          controller: priceController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga jual'),
        ),
        TextField(
          controller: stockController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Stok'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            try {
              await KasirDB.instance.addProduct(
                codeController.text,
                nameController.text,
                int.parse(priceController.text),
                int.parse(stockController.text),
              );
              codeController.clear();
              nameController.clear();
              priceController.clear();
              stockController.clear();
              await refreshProducts();
              notify('Barang berhasil disimpan');
            } catch (_) {
              notify('Periksa data dan pastikan kode barang unik');
            }
          },
          child: const Text('Simpan barang'),
        ),
        const Divider(height: 28),
        ...products.map(
          (product) => ListTile(
            leading: const Icon(Icons.inventory_2),
            title: Text('${product['name']}'),
            subtitle: Text(
              '${product['code']} • ${money(product['price'] as int)}',
            ),
            trailing: Text('Stok ${product['stock']}'),
          ),
        ),
      ],
    );
  }
}

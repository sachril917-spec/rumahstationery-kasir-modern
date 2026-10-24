import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
const apiKey = String.fromEnvironment('API_KEY');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await KasirDB.instance.init();
  runApp(const RumahStationeryApp());
}

class KasirDB {
  KasirDB._();
  static final instance = KasirDB._();
  late Database db;
  final _uuid = const Uuid();

  Future<void> init() async {
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'rumah_stationery.db'),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE products(
          id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
          cost_price INTEGER NOT NULL DEFAULT 0, price INTEGER NOT NULL,
          middle_price INTEGER NOT NULL DEFAULT 0, middle_qty INTEGER NOT NULL DEFAULT 1, member_price INTEGER NOT NULL DEFAULT 0,
          stock INTEGER NOT NULL)''');
        await db.execute('CREATE INDEX idx_product_name ON products(name)');
        await db.execute('CREATE INDEX idx_product_code ON products(code)');
        await db.execute('''CREATE TABLE members(
          id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
          phone TEXT NOT NULL DEFAULT '', price_level TEXT NOT NULL DEFAULT 'Retail',
          discount_percent REAL NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE transactions(
          id TEXT PRIMARY KEY, invoice_no TEXT NOT NULL, time TEXT NOT NULL,
          branch TEXT NOT NULL, cashier TEXT NOT NULL DEFAULT '',
          member_code TEXT NOT NULL DEFAULT '', member_name TEXT NOT NULL DEFAULT '',
          payment TEXT NOT NULL, subtotal INTEGER NOT NULL DEFAULT 0,
          item_discount INTEGER NOT NULL DEFAULT 0,
          transaction_discount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL, payload TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending')''');
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE products ADD COLUMN cost_price INTEGER NOT NULL DEFAULT 0');
          await db.execute("ALTER TABLE transactions ADD COLUMN invoice_no TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE transactions ADD COLUMN cashier TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE transactions ADD COLUMN member_code TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE transactions ADD COLUMN member_name TEXT NOT NULL DEFAULT ''");
          await db.execute('ALTER TABLE transactions ADD COLUMN subtotal INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE transactions ADD COLUMN item_discount INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE transactions ADD COLUMN transaction_discount INTEGER NOT NULL DEFAULT 0');
          await db.execute('''CREATE TABLE IF NOT EXISTS members(
            id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '', price_level TEXT NOT NULL DEFAULT 'Retail',
            discount_percent REAL NOT NULL DEFAULT 0)''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE products ADD COLUMN middle_price INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE products ADD COLUMN middle_qty INTEGER NOT NULL DEFAULT 1');
          await db.execute('ALTER TABLE products ADD COLUMN member_price INTEGER NOT NULL DEFAULT 0');
          await db.execute('UPDATE products SET middle_price = price, middle_qty = 1, member_price = price WHERE middle_price = 0');
        }
      },
    );
  }

  Future<void> _seed(Database db) async {
    final samples = [
      ['RS001', 'Pulpen Standard', 0, 2500, 120],
      ['RS002', 'Buku Tulis', 0, 3000, 85],
      ['RS003', 'Tinta Epson 664', 0, 95000, 24],
      ['RS004', 'Kertas A4', 0, 58000, 60],
    ];
    for (final item in samples) {
      await db.insert('products', {
        'id': _uuid.v4(), 'code': item[0], 'name': item[1],
        'cost_price': item[2], 'price': item[3], 'middle_price': item[3],
        'middle_qty': 1, 'member_price': item[3], 'stock': item[4],
      });
    }
  }

  Future<List<Map<String, Object?>>> searchProducts(String query) async {
    if (query.trim().isEmpty) {
      return db.query('products', orderBy: 'name COLLATE NOCASE', limit: 300);
    }
    return db.query('products', where: 'name LIKE ? OR code LIKE ?',
      whereArgs: ['%${query.trim()}%', '%${query.trim()}%'],
      orderBy: 'name COLLATE NOCASE', limit: 100);
  }

  Future<void> addProduct(String code, String name, int cost, int retailPrice, int memberMiddlePrice, int middleQty, int stock) async {
    if (middleQty < 1) throw Exception('Isi satuan tengah minimal 1 pcs');
    final memberSmallPrice = memberMiddlePrice ~/ middleQty;
    await db.insert('products', {
      'id': _uuid.v4(), 'code': code.trim(), 'name': name.trim(),
      'cost_price': cost, 'price': retailPrice,
      'middle_price': memberMiddlePrice, 'middle_qty': middleQty,
      'member_price': memberSmallPrice, 'stock': stock,
    });
  }

  Future<void> addMember(String code, String name, String phone, String level, double discount) async {
    await db.insert('members', {
      'id': _uuid.v4(), 'code': code.trim(), 'name': name.trim(), 'phone': phone.trim(),
      'price_level': level, 'discount_percent': discount,
    });
  }

  Future<String> nextInvoice() async {
    final now = DateTime.now();
    final prefix = 'RS${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final row = await db.rawQuery('SELECT COUNT(*) AS n FROM transactions WHERE invoice_no LIKE ?', ['$prefix%']);
    final count = (row.first['n'] as int? ?? 0) + 1;
    return '$prefix-${count.toString().padLeft(4, '0')}';
  }

  Future<void> saveTransaction({
    required List<Map<String, dynamic>> items, required String payment,
    required int subtotal, required int itemDiscount, required int transactionDiscount,
    required int total, required String branch, required String cashier,
    required String memberCode, required String memberName,
  }) async {
    final transactionId = _uuid.v4();
    final invoice = await nextInvoice();
    await db.transaction((txn) async {
      for (final item in items) {
        final rows = await txn.query('products', where: 'id = ?', whereArgs: [item['id']]);
        if (rows.isEmpty) throw Exception('Barang ${item['name']} tidak ditemukan');
        final currentStock = rows.first['stock'] as int;
        final quantity = item['qty'] as int;
        if (currentStock < quantity) throw Exception('Stok ${item['name']} tidak mencukupi');
        await txn.update('products', {'stock': currentStock - quantity}, where: 'id = ?', whereArgs: [item['id']]);
      }
      await txn.insert('transactions', {
        'id': transactionId, 'invoice_no': invoice,
        'time': DateTime.now().toIso8601String(), 'branch': branch,
        'cashier': cashier, 'member_code': memberCode, 'member_name': memberName,
        'payment': payment, 'subtotal': subtotal, 'item_discount': itemDiscount,
        'transaction_discount': transactionDiscount, 'total': total,
        'payload': jsonEncode(items), 'sync_status': 'pending',
      
      });
    });
  }

  Future<int> syncPendingTransactions({
    required String apiKey,
  }) async {
    final pending = await db.query(
      'transactions',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'time ASC',
      limit: 100,
    );

    if (pending.isEmpty) return 0;

    final groups = <String, List<Map<String, Object?>>>{};

    for (final row in pending) {
      final branch = '${row['branch']}';
      groups.putIfAbsent(branch, () => []).add(row);
    }

    var syncedCount = 0;

    for (final entry in groups.entries) {
      final transactions = entry.value.map((row) => {
        'id': row['id'],
        'created_at': row['time'],
        'payment': row['payment'],
        'total': row['total'],
        'payload': row['payload'],
      }).toList();

      final response = await http.post(
        Uri.parse(
          'https://rumah-stationery-api.sachril917.workers.dev/sync/transactions',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'device_id': 'rumah-stationery-android',
          'branch_id': entry.key,
          'transactions': transactions,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Sinkronisasi gagal: ${response.statusCode}');
      }

      final result = jsonDecode(response.body);

      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Sinkronisasi gagal');
      }

      for (final row in entry.value) {
        await db.update(
          'transactions',
          {'sync_status': 'synced'},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        syncedCount++;
      }
    }

    return syncedCount;
  }
}

class RumahStationeryApp extends StatelessWidget {

  const RumahStationeryApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Rumah Stationery Kasir', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769E0)), useMaterial3: true),
    home: const KasirHome(),
  );
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
  final costController = TextEditingController(text: '0');
  final priceController = TextEditingController();
  final memberMiddlePriceController = TextEditingController();
  final middleQtyController = TextEditingController(text: '10');
  final stockController = TextEditingController();
  final cashierController = TextEditingController(text: 'Kasir 1');
  final branchController = TextEditingController(text: 'Rumah Stationery');
  final memberCodeController = TextEditingController();
  final memberNameController = TextEditingController();
  final memberPhoneController = TextEditingController();
  final memberDiscountController = TextEditingController(text: '0');
  final memberLevelController = TextEditingController(text: 'Retail');
  final transactionDiscountController = TextEditingController(text: '0');
  final memberLookupController = TextEditingController();
  List<Map<String, Object?>> products = [];
  List<Map<String, Object?>> members = [];
  final Map<String, Map<String, dynamic>> cart = {};
  String payment = 'Tunai';
  int page = 0;

  int get subtotal => cart.values.fold(0, (sum, item) => sum + (item['price'] as int) * (item['qty'] as int));
  int get itemDiscountTotal => cart.values.fold(0, (sum, item) => sum + (item['discount'] as int));
  int get transactionDiscount => int.tryParse(transactionDiscountController.text) ?? 0;
  int get total => (subtotal - itemDiscountTotal - transactionDiscount).clamp(0, 1 << 62).toInt();
  String money(int value) => 'Rp ${value.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  String dateNow() { final n = DateTime.now(); return '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}'; }

  @override
  void initState() { super.initState(); refreshProducts(); refreshMembers(); }
  @override
  void dispose() {
    for (final c in [searchController, codeController, nameController, costController, priceController, stockController, cashierController, branchController, memberCodeController, memberNameController, memberPhoneController, memberDiscountController, memberLevelController, transactionDiscountController, memberLookupController, middleQtyController, memberMiddlePriceController]) { c.dispose(); }
    super.dispose();
  }
  Future<void> refreshProducts() async { final r = await KasirDB.instance.searchProducts(searchController.text); if (mounted) setState(() => products = r); }
  Future<void> refreshMembers() async { final r = await KasirDB.instance.db.query('members', orderBy: 'name COLLATE NOCASE'); if (mounted) setState(() => members = r); }
  void notify(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void addToCart(Map<String, Object?> product) {
    final id = product['id'] as String;
    setState(() {
      if (cart.containsKey(id)) { cart[id]!['qty'] = (cart[id]!['qty'] as int) + 1; }
      else { final memberActive = memberCodeController.text.trim().isNotEmpty; final chosenPrice = memberActive ? ((product['member_price'] as int?) ?? (product['price'] as int)) : (product['price'] as int); cart[id] = {'id': id, 'name': product['name'], 'price': chosenPrice, 'qty': 1, 'discount': 0}; }
    });
  }

  Future<void> editCartItem(String id) async {
    final item = cart[id]!;
    final qty = TextEditingController(text: '${item['qty']}');
    final disc = TextEditingController(text: '${item['discount']}');
    final result = await showDialog<Map<String, int>>(context: context, builder: (context) => AlertDialog(
      title: Text('Atur ${item['name']}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Jumlah barang')),
        TextField(controller: disc, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diskon barang (Rp, total baris)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')), FilledButton(onPressed: () {
        final q = int.tryParse(qty.text); final d = int.tryParse(disc.text);
        if (q == null || q < 1 || d == null || d < 0 || d > (item['price'] as int) * q) return;
        Navigator.pop(context, {'qty': q, 'discount': d});
      }, child: const Text('Simpan'))],
    ));
    qty.dispose(); disc.dispose();
    if (result != null) setState(() { item['qty'] = result['qty']; item['discount'] = result['discount']; });
  }

  
  Future<void> chooseMember() async {
    final search = TextEditingController();

    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = members.where((m) {
              final text =
                  '${m['name']} ${m['code']} ${m['phone']}'
                      .toLowerCase();
              return text.contains(search.text.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Pilih member'),
              content: SizedBox(
                width: 360,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Cari kode/nama/telepon',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              title: const Text('Tanpa member'),
                              onTap: () {
                                Navigator.pop(
                                  dialogContext,
                                  <String, Object?>{},
                                );
                              },
                            );
                          }

                          final m = filtered[index - 1];

                          return ListTile(
                            title: Text('${m['name']}'),
                            subtitle: Text(
                              "${m['code']} • ${m['phone']}",
                            ),
                            onTap: () {
                              Navigator.pop(dialogContext, m);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );

    search.dispose();

    if (selected == null || !mounted) return;

    setState(() {
      memberCodeController.text = '${selected['code'] ?? ''}';
      memberNameController.text = '${selected['name'] ?? ''}';

      for (final entry in cart.entries) {
        for (final product in products) {
          if (product['id'] == entry.key) {
            final isMember =
                memberCodeController.text.trim().isNotEmpty;

            entry.value['price'] = isMember
                ? ((product['member_price'] as int?) ??
                    (product['price'] as int))
                : (product['price'] as int);
            break;
          }
        }
      }

      final discountValue = selected['discount_percent'];
      if (discountValue != null) {
        final percent = (discountValue as num).toDouble();
        transactionDiscountController.text =
            ((subtotal - itemDiscountTotal) * percent / 100)
                .round()
                .toString();
      } else {
        transactionDiscountController.text = '0';
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final pages = [cashierPage(), productPage(), memberPage(), transactionPage(), adminPage()];
    return Scaffold(
      appBar: AppBar(title: const Text('RUMAH STATIONERY', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF102A56), foregroundColor: Colors.white),
      body: SafeArea(child: pages[page]),
      bottomNavigationBar: NavigationBar(selectedIndex: page, onDestinationSelected: (v) => setState(() => page = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Kasir'),
        NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Barang'),
        NavigationDestination(icon: Icon(Icons.people), label: 'Member'),
        NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Transaksi'),
        NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
      ]),
    );
  }

  Widget cashierPage() => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: TextField(controller: searchController, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cari nama atau kode barang', border: OutlineInputBorder()), onChanged: (_) => refreshProducts())),
    Expanded(child: GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: 1.35, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: products.length, itemBuilder: (context, index) {
      final product = products[index];
      return Card(child: InkWell(onTap: () => addToCart(product), child: Padding(padding: const EdgeInsets.all(10), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.inventory_2_outlined), Text('${product['name']}', maxLines: 2, overflow: TextOverflow.ellipsis), Text(money(product['price'] as int), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)), Text('Stok ${product['stock']}')]))));
    })),
    Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [Expanded(child: Text('Tanggal: ${dateNow()}')), Expanded(child: Text('Item: ${cart.length}', textAlign: TextAlign.end))]),
      Row(children: [Expanded(child: TextField(controller: cashierController, decoration: const InputDecoration(labelText: 'Nama kasir'))), const SizedBox(width: 8), Expanded(child: TextField(controller: branchController, decoration: const InputDecoration(labelText: 'Cabang')))]),
      Row(children: [Expanded(child: TextField(controller: memberNameController, readOnly: true, decoration: const InputDecoration(labelText: 'Member', hintText: 'Opsional'), onTap: chooseMember)), IconButton(tooltip: 'Pilih member', onPressed: chooseMember, icon: const Icon(Icons.person_search)), IconButton(tooltip: 'Hapus member', onPressed: () => setState(() { memberCodeController.clear(); memberNameController.clear(); for (final entry in cart.entries) { for (final product in products) { if (product['id'] == entry.key) { entry.value['price'] = product['price']; break; } } } }), icon: const Icon(Icons.person_off))]),
      if (memberCodeController.text.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text('Kode member: ${memberCodeController.text}')),
      if (cart.isNotEmpty) SizedBox(height: 68, child: ListView(children: cart.entries.map((entry) { final item = entry.value; return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${item['name']} × ${item['qty']}'), subtitle: Text('Diskon barang: ${money(item['discount'] as int)}'), trailing: Wrap(spacing: 0, children: [Text(money((item['price'] as int) * (item['qty'] as int) - (item['discount'] as int))), IconButton(onPressed: () => editCartItem(entry.key), icon: const Icon(Icons.edit, size: 18)), IconButton(onPressed: () => setState(() => cart.remove(entry.key)), icon: const Icon(Icons.close, size: 18))])); }).toList())),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal'), Text(money(subtotal))]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Diskon barang'), Text(money(itemDiscountTotal))]),
      TextField(controller: transactionDiscountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diskon total transaksi (Rp)'), onChanged: (_) => setState(() {})),
      DropdownButton<String>(value: payment, items: ['Tunai', 'Transfer', 'QRIS'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => payment = v ?? 'Tunai')),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: () async {
        if (cart.isEmpty) { notify('Keranjang masih kosong'); return; }
        if (transactionDiscount < 0 || transactionDiscount > subtotal - itemDiscountTotal) { notify('Diskon total tidak boleh melebihi subtotal setelah diskon barang'); return; }
        try {
          await KasirDB.instance.saveTransaction(items: cart.values.map((v) => Map<String, dynamic>.from(v)).toList(), payment: payment, subtotal: subtotal, itemDiscount: itemDiscountTotal, transactionDiscount: transactionDiscount, total: total, branch: branchController.text.trim().isEmpty ? 'Rumah Stationery' : branchController.text.trim(), cashier: cashierController.text.trim(), memberCode: memberCodeController.text.trim(), memberName: memberNameController.text.trim());
          setState(() { cart.clear(); transactionDiscountController.text = '0'; memberCodeController.clear(); memberNameController.clear(); });
          await refreshProducts(); notify('Transaksi tersimpan offline');
        } catch (e) { notify('Transaksi gagal: $e'); }
      }, child: Text('Bayar • ${money(total)}'))),
    ])),
  ]);

  Widget productPage() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Tambah barang', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Kode barang')),
    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nama barang')),
    TextField(controller: costController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga modal')),
    TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga eceran umum per pcs')),
    TextField(controller: memberMiddlePriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga member satuan tengah (mis. 1 pak)')),
    TextField(controller: middleQtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Isi satuan tengah (berapa pcs kecil)')),
    ValueListenableBuilder<TextEditingValue>(valueListenable: memberMiddlePriceController, builder: (context, priceText, _) => ValueListenableBuilder<TextEditingValue>(valueListenable: middleQtyController, builder: (context, qtyText, __) {
      final middle = int.tryParse(priceText.text) ?? 0; final qty = int.tryParse(qtyText.text) ?? 0;
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(qty > 0 ? 'Harga member per pcs otomatis: ${money(middle ~/ qty)}' : 'Isi satuan tengah harus lebih dari 0'));
    })),
    TextField(controller: stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok awal (dalam satuan kecil/pcs)')),
    const SizedBox(height: 12), FilledButton(onPressed: () async {
      final cost = int.tryParse(costController.text); final retail = int.tryParse(priceController.text); final middle = int.tryParse(memberMiddlePriceController.text); final middleQty = int.tryParse(middleQtyController.text); final stock = int.tryParse(stockController.text);
      if (codeController.text.trim().isEmpty || nameController.text.trim().isEmpty || cost == null || retail == null || middle == null || middleQty == null || stock == null || cost < 0 || retail < 0 || middle < 0 || middleQty < 1 || stock < 0) { notify('Lengkapi data; isi satuan tengah minimal 1'); return; }
      try { await KasirDB.instance.addProduct(codeController.text, nameController.text, cost, retail, middle, middleQty, stock); codeController.clear(); nameController.clear(); costController.text = '0'; priceController.clear(); memberMiddlePriceController.clear(); middleQtyController.text = '10'; stockController.clear(); await refreshProducts(); notify('Barang tersimpan; harga pcs dihitung otomatis'); }
      catch (_) { notify('Periksa data dan pastikan kode barang unik'); }
    }, child: const Text('Simpan barang')),
    const Divider(height: 28),
    ...products.map((product) => ListTile(leading: const Icon(Icons.inventory_2), title: Text('${product['name']}'), subtitle: Text('${product['code']} • Modal ${money((product['cost_price'] as int?) ?? 0)} • Member tengah ${money((product['middle_price'] as int?) ?? (product['price'] as int))} / ${(product['middle_qty'] as int?) ?? 1} pcs • Member kecil ${money((product['member_price'] as int?) ?? (product['price'] as int))} • Eceran ${money(product['price'] as int)}'), trailing: Text('Stok ${product['stock']}'))),
  ]);

  Widget memberPage() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Data member', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    TextField(controller: memberCodeController, decoration: const InputDecoration(labelText: 'Kode member unik')),
    TextField(controller: memberNameController, readOnly: false, decoration: const InputDecoration(labelText: 'Nama member')),
    TextField(controller: memberPhoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor telepon')),
    TextField(controller: memberLevelController, decoration: const InputDecoration(labelText: 'Jenis harga (Retail/Grosir)')),
    TextField(controller: memberDiscountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Diskon member (%)')),
    const SizedBox(height: 12), FilledButton(onPressed: () async {
      final d = double.tryParse(memberDiscountController.text) ?? -1;
      if (memberCodeController.text.trim().isEmpty || memberNameController.text.trim().isEmpty || d < 0 || d > 100) { notify('Kode, nama, dan diskon 0–100% harus benar'); return; }
      try { await KasirDB.instance.addMember(memberCodeController.text, memberNameController.text, memberPhoneController.text, memberLevelController.text.trim().isEmpty ? 'Retail' : memberLevelController.text.trim(), d); memberCodeController.clear(); memberNameController.clear(); memberPhoneController.clear(); memberDiscountController.text = '0'; await refreshMembers(); notify('Member berhasil disimpan'); }
      catch (_) { notify('Gagal menyimpan. Pastikan kode member belum dipakai'); }
    }, child: const Text('Simpan member')),
    const Divider(height: 28),
    
    ...members.map((m) => ListTile(
      leading: const Icon(Icons.person),
      title: Text('${m['name']}'),
      subtitle: Text(
        "${m['code']} • ${m['phone']} • ${m['price_level']} • diskon ${m['discount_percent']}%",
      ),
    )),
  ]);


  Widget transactionPage() => FutureBuilder<List<Map<String, Object?>>>(future: KasirDB.instance.db.query('transactions', orderBy: 'time DESC'), builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Text('Gagal membaca transaksi: ${snapshot.error}'));
    final rows = snapshot.data ?? [];
    if (rows.isEmpty) return const Center(child: Text('Belum ada transaksi'));
    return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
      final row = rows[i]; final when = DateTime.tryParse('${row['time']}');
      return ListTile(leading: const Icon(Icons.receipt_long), title: Text('${row['invoice_no'] ?? 'Transaksi ${i + 1}'}'), subtitle: Text('${when == null ? row['time'] : '${when.day.toString().padLeft(2, '0')}/${when.month.toString().padLeft(2, '0')}/${when.year} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}'} • ${row['branch']} • ${row['cashier']}\nMember: ${row['member_name'] ?? '-'} • ${row['payment']}\nSubtotal ${money((row['subtotal'] as int?) ?? (row['total'] as int))} • Diskon ${money(((row['item_discount'] as int?) ?? 0) + ((row['transaction_discount'] as int?) ?? 0))}', maxLines: 3), trailing: Text(money(row['total'] as int), style: const TextStyle(fontWeight: FontWeight.bold)));
    });
  });

  Widget adminPage() => ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Pengaturan admin', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Pengaturan lokal untuk APK ini. Login admin, pembatasan hak akses, dan sinkronisasi server belum diaktifkan.'),
    const SizedBox(height: 12),
    TextField(controller: branchController, decoration: const InputDecoration(labelText: 'Nama cabang perangkat ini')),
    TextField(controller: cashierController, decoration: const InputDecoration(labelText: 'Nama kasir default')),
    const SizedBox(height: 12),
    FilledButton.icon(onPressed: () => notify('Pengaturan dipakai pada transaksi berikutnya'), icon: const Icon(Icons.save), label: const Text('Simpan pengaturan untuk sesi ini')),
    const Divider(height: 32),
    
ListTile(
  leading: const Icon(Icons.cloud_upload),
  title: const Text('Sinkronisasi server'),
  subtitle: const Text('Kirim transaksi pending ke server'),
  onTap: () async {
    if (apiKey.isEmpty) {
      notify('API_KEY belum tersedia. Build ulang APK.');
      return;
    }

    try {
      final count = await KasirDB.instance
          .syncPendingTransactions(apiKey: apiKey);

      if (!mounted) return;
      notify('Sinkronisasi berhasil: $count transaksi');
    } catch (e) {
      if (!mounted) return;
      notify('Sinkronisasi gagal: $e');
    }
  },
),

    const ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Web admin'), subtitle: Text('Belum tersedia pada paket ini; tahap berikutnya perlu API server, login, dan dashboard web.')),
  ]);
}

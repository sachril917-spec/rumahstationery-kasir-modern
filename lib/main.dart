import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

const apiKey = String.fromEnvironment('API_KEY');
const apiUrl = 'https://rumah-stationery-api.sachril917.workers.dev';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await KasirDB.instance.init();
  runApp(const RumahStationeryApp());
}

class KasirDB {
  KasirDB._();
  static final instance = KasirDB._();
  late Database db;
  final uuid = const Uuid();

  Future<void> init() async {
    db = await openDatabase(
      p.join(await getDatabasesPath(), 'rumah_stationery.db'),
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''CREATE TABLE products(
          id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
          cost_price INTEGER NOT NULL DEFAULT 0, price INTEGER NOT NULL,
          middle_price INTEGER NOT NULL DEFAULT 0, middle_qty INTEGER NOT NULL DEFAULT 1,
          member_price INTEGER NOT NULL DEFAULT 0, stock INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE members(
          id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
          phone TEXT NOT NULL DEFAULT '', price_level TEXT NOT NULL DEFAULT 'Retail',
          discount_percent REAL NOT NULL DEFAULT 0)''');
        await db.execute('''CREATE TABLE transactions(
          id TEXT PRIMARY KEY, invoice_no TEXT NOT NULL, time TEXT NOT NULL,
          branch TEXT NOT NULL, cashier TEXT NOT NULL DEFAULT '',
          member_code TEXT NOT NULL DEFAULT '', member_name TEXT NOT NULL DEFAULT '',
          payment TEXT NOT NULL DEFAULT 'Tunai', amount_paid INTEGER NOT NULL DEFAULT 0,
          change_amount INTEGER NOT NULL DEFAULT 0, subtotal INTEGER NOT NULL DEFAULT 0,
          item_discount INTEGER NOT NULL DEFAULT 0, transaction_discount INTEGER NOT NULL DEFAULT 0,
          total INTEGER NOT NULL, payload TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending')''');
        await _seed(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE products ADD COLUMN cost_price INTEGER NOT NULL DEFAULT 0');
          for (final sql in [
            "ALTER TABLE transactions ADD COLUMN invoice_no TEXT NOT NULL DEFAULT ''",
            "ALTER TABLE transactions ADD COLUMN cashier TEXT NOT NULL DEFAULT ''",
            "ALTER TABLE transactions ADD COLUMN member_code TEXT NOT NULL DEFAULT ''",
            "ALTER TABLE transactions ADD COLUMN member_name TEXT NOT NULL DEFAULT ''",
            "ALTER TABLE transactions ADD COLUMN subtotal INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE transactions ADD COLUMN item_discount INTEGER NOT NULL DEFAULT 0",
            "ALTER TABLE transactions ADD COLUMN transaction_discount INTEGER NOT NULL DEFAULT 0",
          ]) {
            await db.execute(sql);
          }
          await db.execute('''CREATE TABLE IF NOT EXISTS members(
            id TEXT PRIMARY KEY, code TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
            phone TEXT NOT NULL DEFAULT '', price_level TEXT NOT NULL DEFAULT 'Retail',
            discount_percent REAL NOT NULL DEFAULT 0)''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE products ADD COLUMN middle_price INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE products ADD COLUMN middle_qty INTEGER NOT NULL DEFAULT 1');
          await db.execute('ALTER TABLE products ADD COLUMN member_price INTEGER NOT NULL DEFAULT 0');
          await db.execute('UPDATE products SET middle_price=price, middle_qty=1, member_price=price WHERE middle_price=0');
        }
        if (oldVersion < 4) {
          await db.execute("ALTER TABLE transactions ADD COLUMN amount_paid INTEGER NOT NULL DEFAULT 0");
          await db.execute("ALTER TABLE transactions ADD COLUMN change_amount INTEGER NOT NULL DEFAULT 0");
        }
      },
    );
  }

  Future<void> _seed(Database db) async {
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    if (n > 0) return;
    final rows = [
      ['RS001', 'Pulpen Standard', 2500, 120],
      ['RS002', 'Buku Tulis', 3000, 85],
      ['RS003', 'Tinta Epson 664', 95000, 24],
      ['RS004', 'Kertas A4', 58000, 60],
    ];
    for (final r in rows) {
      await db.insert('products', {
        'id': uuid.v4(), 'code': r[0], 'name': r[1], 'cost_price': 0,
        'price': r[2], 'middle_price': r[2], 'middle_qty': 1,
        'member_price': r[2], 'stock': r[3],
      });
    }
  }

  Future<List<Map<String, Object?>>> products(String q) => q.trim().isEmpty
      ? db.query('products', orderBy: 'name COLLATE NOCASE')
      : db.query('products', where: 'name LIKE ? OR code LIKE ?',
          whereArgs: ['%${q.trim()}%', '%${q.trim()}%'],
          orderBy: 'name COLLATE NOCASE');

  Future<List<Map<String, Object?>>> members() =>
      db.query('members', orderBy: 'name COLLATE NOCASE');

  Future<List<Map<String, Object?>>> transactions() =>
      db.query('transactions', orderBy: 'time DESC');

  Future<void> addProduct(String code, String name, int cost, int price,
      int middlePrice, int middleQty, int stock) async {
    if (middleQty < 1) throw Exception('Isi satuan tengah minimal 1');
    await db.insert('products', {
      'id': uuid.v4(), 'code': code.trim(), 'name': name.trim(),
      'cost_price': cost, 'price': price, 'middle_price': middlePrice,
      'middle_qty': middleQty, 'member_price': middlePrice ~/ middleQty,
      'stock': stock,
    });
  }

  Future<void> updateProduct(String id, String code, String name, int cost,
      int price, int middlePrice, int middleQty, int stock) async {
    if (middleQty < 1) throw Exception('Isi satuan tengah minimal 1');
    await db.update('products', {
      'code': code.trim(), 'name': name.trim(), 'cost_price': cost,
      'price': price, 'middle_price': middlePrice, 'middle_qty': middleQty,
      'member_price': middlePrice ~/ middleQty, 'stock': stock,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteProduct(String id) async {
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addMember(String code, String name, String phone,
      String level, double discount) async {
    await db.insert('members', {
      'id': uuid.v4(), 'code': code.trim(), 'name': name.trim(),
      'phone': phone.trim(), 'price_level': level,
      'discount_percent': discount,
    });
  }

  Future<void> updateMember(String id, String code, String name, String phone,
      String level, double discount) async {
    await db.update('members', {
      'code': code.trim(), 'name': name.trim(), 'phone': phone.trim(),
      'price_level': level, 'discount_percent': discount,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMember(String id) async {
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> invoice() async {
    final d = DateTime.now();
    final prefix = 'RS${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final rows = await db.rawQuery(
      'SELECT invoice_no FROM transactions WHERE invoice_no LIKE ? ORDER BY invoice_no DESC LIMIT 1',
      ['$prefix-%'],
    );
    var next = 1;
    if (rows.isNotEmpty) {
      final suffix = int.tryParse('${rows.first['invoice_no']}'.split('-').last);
      if (suffix != null) next = suffix + 1;
    }
    return '$prefix-${next.toString().padLeft(4, '0')}';
  }

  Future<void> save({
    required List<Map<String, dynamic>> items,
    required String method,
    required int paid,
    required int subtotal,
    required int itemDiscount,
    required int txnDiscount,
    required int total,
    required String branch,
    required String cashier,
    required String memberCode,
    required String memberName,
  }) async {
    if (items.isEmpty) throw Exception('Keranjang kosong');
    if (method == 'Tunai' && paid < total) throw Exception('Uang diterima kurang dari total');
    final change = method == 'Tunai' ? paid - total : 0;
    final invoiceNo = await invoice();
    await db.transaction((t) async {
      for (final item in items) {
        final rows = await t.query('products', where: 'id = ?', whereArgs: [item['id']]);
        if (rows.isEmpty) throw Exception('Barang tidak ditemukan: ${item['name']}');
        final currentStock = rows.first['stock'] as int;
        final itemQty = item['qty'] as int;
        if (itemQty < 1 || currentStock < itemQty) {
          throw Exception('Stok ${item['name']} tidak cukup');
        }
        await t.update('products', {'stock': currentStock - itemQty},
            where: 'id = ?', whereArgs: [item['id']]);
      }
      await t.insert('transactions', {
        'id': uuid.v4(), 'invoice_no': invoiceNo,
        'time': DateTime.now().toIso8601String(), 'branch': branch,
        'cashier': cashier, 'member_code': memberCode, 'member_name': memberName,
        'payment': method, 'amount_paid': paid, 'change_amount': change,
        'subtotal': subtotal, 'item_discount': itemDiscount,
        'transaction_discount': txnDiscount, 'total': total,
        'payload': jsonEncode(items), 'sync_status': 'pending',
      });
    });
  }

  Future<int> sync(String key) async {
    final rows = await db.query('transactions',
        where: "sync_status = 'pending'", orderBy: 'time ASC', limit: 100);
    if (rows.isEmpty) return 0;
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      groups.putIfAbsent('${row['branch']}', () => []).add(row);
    }
    var count = 0;
    for (final group in groups.entries) {
      final txs = group.value.map((r) => {
        'id': '${r['id']}', 'created_at': '${r['time']}',
        'payment': '${r['payment']}', 'amount_paid': r['amount_paid'] ?? r['total'],
        'change_amount': r['change_amount'] ?? 0, 'total': r['total'],
        'payload': {
          'items': jsonDecode('${r['payload']}'), 'invoice_no': r['invoice_no'],
          'cashier': r['cashier'], 'member_code': r['member_code'],
          'member_name': r['member_name'], 'subtotal': r['subtotal'],
          'item_discount': r['item_discount'],
          'transaction_discount': r['transaction_discount'],
        },
      }).toList();
      final response = await http.post(
        Uri.parse('$apiUrl/sync/transactions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
        body: jsonEncode({'device_id': 'rumah-stationery-android',
          'branch_id': group.key, 'transactions': txs}),
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      final result = jsonDecode(response.body);
      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Sinkronisasi gagal');
      }
      for (final row in group.value) {
        await db.update('transactions', {'sync_status': 'synced'},
            where: 'id = ?', whereArgs: [row['id']]);
        count++;
      }
    }
    return count;
  }
}

class RumahStationeryApp extends StatelessWidget {
  const RumahStationeryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Rumah Stationery Kasir',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769E0)),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF102A56), foregroundColor: Colors.white,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late DateTime _now;
  Timer? _clockTimer;
  Timer? _searchTimer;

  final search = TextEditingController();
  final code = TextEditingController();
  final name = TextEditingController();
  final cost = TextEditingController(text: '0');
  final price = TextEditingController();
  final middlePrice = TextEditingController();
  final qty = TextEditingController(text: '10');
  final stock = TextEditingController();
  final cashier = TextEditingController(text: 'Kasir 1');
  final branch = TextEditingController(text: 'PERCOBAAN APK BARU');
  final memberCode = TextEditingController();
  final memberName = TextEditingController();
  final phone = TextEditingController();
  final discount = TextEditingController(text: '0');
  final level = TextEditingController(text: 'Retail');
  final txnDiscount = TextEditingController(text: '0');
  final cash = TextEditingController();

  List<Map<String, Object?>> ps = [];
  List<Map<String, Object?>> ms = [];
  List<Map<String, Object?>> txRows = [];
  String? editingProductId;
  String? editingMemberId;
  Map<String, Object?>? selectedMember;
  final Map<String, Map<String, dynamic>> cart = {};
  String method = 'Tunai';
  int tab = 0;
  bool saving = false;
  bool syncing = false;

  String get dateLabel {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    const months = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];
    return '${days[_now.weekday - 1]}, ${_now.day} ${months[_now.month - 1]} ${_now.year}';
  }

  String get timeLabel =>
      '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}:${_now.second.toString().padLeft(2, '0')} WIB';

  String money(int value) {
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return '${value < 0 ? '- ' : ''}Rp $out';
  }

  int get subtotal => cart.values.fold(0,
      (sum, item) => sum + (item['price'] as int) * (item['qty'] as int));
  int get itemDisc => cart.values.fold(0,
      (sum, item) => sum + (item['discount'] as int));
  int get disc => int.tryParse(txnDiscount.text) ?? 0;
  int get total => (subtotal - itemDisc - disc).clamp(0, 1 << 62).toInt();
  int get paid => method == 'Tunai' ? (int.tryParse(cash.text) ?? 0) : total;
  int get change => method == 'Tunai' && paid >= total ? paid - total : 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    refreshAll();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _searchTimer?.cancel();
    for (final controller in [
      search, code, name, cost, price, middlePrice, qty, stock,
      cashier, branch, memberCode, memberName, phone, discount,
      level, txnDiscount, cash,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void msg(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> refreshAll() async {
    final db = KasirDB.instance;
    final products = await db.products(search.text);
    final members = await db.members();
    final transactions = await db.transactions();
    if (!mounted) return;
    setState(() {
      ps = products;
      ms = members;
      txRows = transactions;
      _repriceCart();
    });
  }

  void searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), refreshAll);
  }

  int _memberUnitPrice(Map<String, Object?> product) {
    final base = (product['member_price'] as int?) ?? (product['price'] as int);
    final percent = (selectedMember?['discount_percent'] as num?)?.toDouble() ?? 0;
    return (base * (1 - percent / 100)).round().clamp(0, 1 << 62).toInt();
  }

  void _repriceCart() {
    for (final entry in cart.entries) {
      Map<String, Object?>? product;
      for (final candidate in ps) {
        if ('${candidate['id']}' == entry.key) {
          product = candidate;
          break;
        }
      }
      if (product == null) continue;
      entry.value['price'] = selectedMember == null
          ? product['price'] as int
          : _memberUnitPrice(product);
    }
  }

  void addProductToCart(Map<String, Object?> product) {
    final id = '${product['id']}';
    final available = product['stock'] as int;
    if (available <= 0) { msg('Stok barang habis'); return; }
    setState(() {
      if (cart.containsKey(id)) {
        final nextQty = (cart[id]!['qty'] as int) + 1;
        if (nextQty > available) {
          msg('Jumlah melebihi stok tersedia');
          return;
        }
        cart[id]!['qty'] = nextQty;
      } else {
        cart[id] = {
          'id': id, 'name': product['name'],
          'price': selectedMember == null
              ? product['price'] as int : _memberUnitPrice(product),
          'qty': 1, 'discount': 0,
        };
      }
    });
  }

  Future<void> chooseMember() async {
    final selected = await showDialog<Map<String, Object?>?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih member'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, <String, Object?>{'_clear': true}),
            child: const Text('Tanpa member / harga umum'),
          ),
          ...ms.map((m) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, m),
            child: Text('${m['name']} • ${m['code']} (${m['price_level']})'),
          )),
        ],
      ),
    );
    if (selected == null) return;
    setState(() {
      if (selected['_clear'] == true) {
        selectedMember = null;
        memberCode.clear();
        memberName.clear();
      } else {
        selectedMember = selected;
        memberCode.text = '${selected['code'] ?? ''}';
        memberName.text = '${selected['name'] ?? ''}';
      }
      _repriceCart();
    });
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title), content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ya')),
          ],
        ),
      ) ?? false;

  Future<void> saveProduct() async {
    final c = int.tryParse(cost.text);
    final pr = int.tryParse(price.text);
    final mp = int.tryParse(middlePrice.text);
    final q = int.tryParse(qty.text);
    final s = int.tryParse(stock.text);
    if (code.text.trim().isEmpty || name.text.trim().isEmpty ||
        c == null || pr == null || mp == null || q == null || s == null ||
        c < 0 || pr < 0 || mp < 0 || q < 1 || s < 0) {
      msg('Periksa kode, nama, harga, isi satuan, dan stok barang.');
      return;
    }
    try {
      if (editingProductId == null) {
        await KasirDB.instance.addProduct(code.text, name.text, c, pr, mp, q, s);
      } else {
        await KasirDB.instance.updateProduct(editingProductId!, code.text,
            name.text, c, pr, mp, q, s);
      }
      editingProductId = null;
      code.clear(); name.clear(); cost.text = '0'; price.clear();
      middlePrice.clear(); qty.text = '10'; stock.clear();
      await refreshAll();
      msg('Barang berhasil disimpan');
    } catch (e) {
      msg('Gagal menyimpan barang. Pastikan kode unik. ($e)');
    }
  }

  void editProduct(Map<String, Object?> item) {
    setState(() {
      editingProductId = '${item['id']}';
      code.text = '${item['code']}'; name.text = '${item['name']}';
      cost.text = '${item['cost_price'] ?? 0}'; price.text = '${item['price']}';
      middlePrice.text = '${item['middle_price'] ?? 0}';
      qty.text = '${item['middle_qty'] ?? 1}'; stock.text = '${item['stock']}';
      tab = 1;
    });
  }

  Future<void> deleteProduct(Map<String, Object?> item) async {
    if (!await confirm('Hapus barang?', 'Hapus ${item['name']} dari daftar barang?')) return;
    await KasirDB.instance.deleteProduct('${item['id']}');
    await refreshAll();
    msg('Barang dihapus');
  }

  Future<void> saveMember() async {
    final d = double.tryParse(discount.text.replaceAll(',', '.'));
    if (memberCode.text.trim().isEmpty || memberName.text.trim().isEmpty ||
        d == null || d < 0 || d > 100) {
      msg('Kode, nama, dan diskon member harus valid (0–100%).');
      return;
    }
    try {
      final memberLevel = level.text.trim().isEmpty ? 'Retail' : level.text.trim();
      if (editingMemberId == null) {
        await KasirDB.instance.addMember(memberCode.text, memberName.text,
            phone.text, memberLevel, d);
      } else {
        await KasirDB.instance.updateMember(editingMemberId!, memberCode.text,
            memberName.text, phone.text, memberLevel, d);
      }
      editingMemberId = null;
      memberCode.clear(); memberName.clear(); phone.clear();
      level.text = 'Retail'; discount.text = '0';
      await refreshAll();
      msg('Data member berhasil disimpan');
    } catch (e) {
      msg('Gagal menyimpan member. Pastikan kode unik. ($e)');
    }
  }

  void editMember(Map<String, Object?> m) {
    setState(() {
      editingMemberId = '${m['id']}';
      memberCode.text = '${m['code']}'; memberName.text = '${m['name']}';
      phone.text = '${m['phone']}'; level.text = '${m['price_level']}';
      discount.text = '${m['discount_percent']}'; tab = 2;
    });
  }

  Future<void> deleteMember(Map<String, Object?> m) async {
    if (!await confirm('Hapus member?', 'Hapus ${m['name']}?')) return;
    await KasirDB.instance.deleteMember('${m['id']}');
    if (selectedMember?['id'] == m['id']) {
      selectedMember = null; memberCode.clear(); memberName.clear();
      _repriceCart();
    }
    await refreshAll();
    msg('Member dihapus');
  }

  Future<void> saveTransaction() async {
    if (saving) return;
    if (cart.isEmpty) { msg('Keranjang masih kosong'); return; }
    if (disc < 0 || disc > subtotal - itemDisc ||
        itemDisc < 0 || itemDisc > subtotal) {
      msg('Diskon tidak valid'); return;
    }
    if (method == 'Tunai' && paid < total) { msg('Uang diterima kurang'); return; }
    setState(() => saving = true);
    try {
      await KasirDB.instance.save(
        items: cart.values.map((e) => Map<String, dynamic>.from(e)).toList(),
        method: method, paid: paid, subtotal: subtotal, itemDiscount: itemDisc,
        txnDiscount: disc, total: total,
        branch: branch.text.trim().isEmpty ? 'Rumah Stationery' : branch.text.trim(),
        cashier: cashier.text.trim(), memberCode: memberCode.text,
        memberName: memberName.text,
      );
      setState(() {
        cart.clear(); cash.clear(); txnDiscount.text = '0';
        selectedMember = null; memberCode.clear(); memberName.clear();
      });
      await refreshAll();
      msg('Transaksi tersimpan offline');
    } catch (e) {
      msg('Transaksi gagal: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> syncTransactions() async {
    if (apiKey.isEmpty) { msg('API_KEY belum tersedia. Build APK dengan secret API_KEY.'); return; }
    if (syncing) return;
    setState(() => syncing = true);
    try {
      final count = await KasirDB.instance.sync(apiKey);
      await refreshAll();
      msg('Sinkronisasi berhasil: $count transaksi');
    } catch (e) {
      msg('Sinkronisasi gagal: $e');
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> checkUpdate() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/sachril917-spec/rumahstationery-kasir-modern/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (response.statusCode != 200) {
        msg('Gagal cek update. Periksa koneksi internet.'); return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name']?.toString() ?? 'Versi terbaru';
      final releaseUrl = data['html_url']?.toString();
      String? apkUrl;
      String? apkName;
      final assets = data['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is Map && '${asset['name']}'.toLowerCase().endsWith('.apk')) {
            apkUrl = asset['browser_download_url']?.toString();
            apkName = asset['name']?.toString();
            break;
          }
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update Rumah Stationery'),
          content: Text(apkUrl != null
              ? 'Rilis terbaru: $tag\nFile: $apkName\n\nUnduh APK lalu buka file dan pilih Perbarui. Jangan uninstall aplikasi.'
              : 'Rilis $tag ditemukan, tetapi file APK belum tersedia.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final target = apkUrl ?? releaseUrl;
                if (target == null) return;
                final uri = Uri.tryParse(target);
                if (uri == null) return;
                final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!opened && mounted) msg('Tidak bisa membuka link unduhan.');
              },
              child: Text(apkUrl != null ? 'Unduh APK' : 'Buka Rilis'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) msg('Gagal cek update. Coba lagi. ($e)');
    }
  }

  Widget titleSection(String title, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      if (subtitle != null) ...[
        const SizedBox(height: 3),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
      ],
    ]),
  );

  Widget cashierPage() => LayoutBuilder(builder: (context, constraints) {
    final compact = constraints.maxHeight < 650;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: TextField(
          controller: search, onChanged: searchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search), hintText: 'Cari nama atau kode barang',
          ),
        ),
      ),
      Expanded(
        child: ps.isEmpty
            ? const Center(child: Text('Barang belum tersedia. Tambahkan di menu Barang.'))
            : GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190, mainAxisSpacing: 8, crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                ),
                itemCount: ps.length,
                itemBuilder: (context, index) {
                  final item = ps[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => addProductToCart(item),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('${item['name']}', textAlign: TextAlign.center,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(money(item['price'] as int),
                              style: const TextStyle(color: Color(0xFF1769E0), fontWeight: FontWeight.bold)),
                          Text('Stok ${item['stock']}', style: const TextStyle(fontSize: 12)),
                          const Icon(Icons.add_circle_outline, size: 18),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
      Container(
        decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE1E5EC))),
        ),
        padding: EdgeInsets.fromLTRB(12, compact ? 5 : 8, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: cashier,
                decoration: const InputDecoration(labelText: 'Nama kasir', isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: branch,
                decoration: const InputDecoration(labelText: 'Cabang', isDense: true))),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(child: TextField(
              controller: memberName, readOnly: true, onTap: chooseMember,
              decoration: const InputDecoration(labelText: 'Member', isDense: true,
                  prefixIcon: Icon(Icons.person)),
            )),
            IconButton(onPressed: chooseMember, tooltip: 'Pilih member', icon: const Icon(Icons.person_search)),
          ]),
          if (cart.isNotEmpty)
            SizedBox(
              height: compact ? 55 : 76,
              child: ListView(
                children: cart.entries.map((entry) => ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  title: Text('${entry.value['name']} × ${entry.value['qty']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Harga ${money(entry.value['price'] as int)} • Diskon ${money(entry.value['discount'] as int)}'),
                  trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
                    Text(money((entry.value['price'] as int) * (entry.value['qty'] as int))),
                    IconButton(visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => cart.remove(entry.key)),
                      icon: const Icon(Icons.close, size: 19)),
                  ]),
                )).toList(),
              ),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Subtotal'), Text(money(subtotal), style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          Row(children: [
            Expanded(child: TextField(
              controller: txnDiscount, keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Diskon transaksi (Rp)', isDense: true),
            )),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: method,
              items: ['Tunai', 'Transfer', 'QRIS'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() { method = v ?? 'Tunai'; cash.clear(); }),
            ),
          ]),
          if (method == 'Tunai')
            TextField(controller: cash, keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Uang diterima (Rp)', isDense: true)),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Kembalian: ${money(change)}', style: const TextStyle(fontSize: 12)),
            Text('TOTAL ${money(total)}', style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1769E0))),
          ]),
          const SizedBox(height: 5),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: saving ? null : saveTransaction,
            icon: saving
                ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle),
            label: Text(saving ? 'Menyimpan...' : 'BAYAR • ${money(total)}'),
          )),
        ]),
      ),
    ]);
  });

  Widget productPage() => ListView(padding: const EdgeInsets.all(16), children: [
    titleSection(editingProductId == null ? 'Tambah barang' : 'Edit barang',
        subtitle: 'Masukkan harga, isi satuan tengah, dan stok'),
    TextField(controller: code, decoration: const InputDecoration(labelText: 'Kode barang')),
    const SizedBox(height: 8),
    TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama barang')),
    const SizedBox(height: 8),
    TextField(controller: cost, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Harga modal (Rp)')),
    const SizedBox(height: 8),
    TextField(controller: price, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Harga eceran (Rp)')),
    const SizedBox(height: 8),
    TextField(controller: middlePrice, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Harga satuan tengah (Rp)')),
    const SizedBox(height: 8),
    TextField(controller: qty, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Isi satuan tengah (pcs)')),
    const SizedBox(height: 8),
    TextField(controller: stock, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Stok awal (pcs)')),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: FilledButton.icon(
        onPressed: saveProduct, icon: const Icon(Icons.save),
        label: Text(editingProductId == null ? 'Simpan barang' : 'Simpan perubahan'))),
      if (editingProductId != null) ...[
        const SizedBox(width: 8),
        OutlinedButton(onPressed: () => setState(() {
          editingProductId = null; code.clear(); name.clear(); cost.text = '0';
          price.clear(); middlePrice.clear(); qty.text = '10'; stock.clear();
        }), child: const Text('Batal')),
      ],
    ]),
    const Divider(height: 28),
    titleSection('Daftar barang', subtitle: '${ps.length} barang tersimpan di perangkat'),
    ...ps.map((item) => Card(child: ListTile(
      title: Text('${item['name']}'),
      subtitle: Text('${item['code']} • Eceran ${money(item['price'] as int)} • Stok ${item['stock']}'),
      trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () => editProduct(item)),
        IconButton(tooltip: 'Hapus', icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => deleteProduct(item)),
      ]),
    ))),
  ]);

  Widget memberPage() => ListView(padding: const EdgeInsets.all(16), children: [
    titleSection(editingMemberId == null ? 'Tambah member' : 'Edit member',
        subtitle: 'Atur level harga dan diskon khusus member'),
    TextField(controller: memberCode, decoration: const InputDecoration(labelText: 'Kode member')),
    const SizedBox(height: 8),
    TextField(controller: memberName, decoration: const InputDecoration(labelText: 'Nama member')),
    const SizedBox(height: 8),
    TextField(controller: phone, keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Nomor telepon')),
    const SizedBox(height: 8),
    DropdownButtonFormField<String>(
      value: ['Retail', 'Grosir', 'Khusus'].contains(level.text) ? level.text : 'Retail',
      decoration: const InputDecoration(labelText: 'Level harga'),
      items: const [
        DropdownMenuItem(value: 'Retail', child: Text('Retail')),
        DropdownMenuItem(value: 'Grosir', child: Text('Grosir')),
        DropdownMenuItem(value: 'Khusus', child: Text('Khusus')),
      ],
      onChanged: (v) => level.text = v ?? 'Retail',
    ),
    const SizedBox(height: 8),
    TextField(controller: discount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Diskon tambahan (%)')),
    const SizedBox(height: 12),
    Row(children: [
      Expanded(child: FilledButton.icon(onPressed: saveMember,
          icon: const Icon(Icons.save),
          label: Text(editingMemberId == null ? 'Simpan member' : 'Simpan perubahan'))),
      if (editingMemberId != null) ...[
        const SizedBox(width: 8),
        OutlinedButton(onPressed: () => setState(() {
          editingMemberId = null; memberCode.clear(); memberName.clear();
          phone.clear(); level.text = 'Retail'; discount.text = '0';
        }), child: const Text('Batal')),
      ],
    ]),
    const Divider(height: 28),
    titleSection('Daftar member', subtitle: '${ms.length} member terdaftar'),
    ...ms.map((m) => Card(child: ListTile(
      title: Text('${m['name']}'),
      subtitle: Text("${m['code']} • ${m['phone']}\n${m['price_level']} • Diskon ${m['discount_percent']}%"),
      isThreeLine: true,
      trailing: Wrap(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.edit, color: Colors.blue),
            onPressed: () => editMember(m)),
        IconButton(icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => deleteMember(m)),
      ]),
    ))),
  ]);

  Widget transactionPage() => txRows.isEmpty
      ? const Center(child: Text('Belum ada transaksi'))
      : RefreshIndicator(
          onRefresh: refreshAll,
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: txRows.length,
            itemBuilder: (context, index) {
              final r = txRows[index];
              final synced = r['sync_status'] == 'synced';
              return Card(child: ListTile(
                title: Text('${r['invoice_no']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${r['branch']} • ${r['cashier']} • ${r['payment']}\n"
                    "Dibayar ${money((r['amount_paid'] as int?) ?? 0)}"
                    " • Kembalian ${money((r['change_amount'] as int?) ?? 0)}"),
                isThreeLine: true,
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(money((r['total'] as int?) ?? 0),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Icon(synced ? Icons.cloud_done : Icons.cloud_upload_outlined,
                      size: 17, color: synced ? Colors.green : Colors.orange),
                ]),
              ));
            },
          ),
        );

  Widget adminPage() => ListView(padding: const EdgeInsets.all(16), children: [
    titleSection('Pengaturan admin', subtitle: 'Identitas cabang dan pengelolaan aplikasi'),
    TextField(controller: branch, decoration: const InputDecoration(labelText: 'Nama cabang')),
    const SizedBox(height: 8),
    TextField(controller: cashier, decoration: const InputDecoration(labelText: 'Nama kasir')),
    const SizedBox(height: 16),
    FilledButton.icon(icon: const Icon(Icons.system_update),
        label: const Text('Cek Update Aplikasi'), onPressed: checkUpdate),
    const SizedBox(height: 12),
    Card(child: ListTile(
      leading: syncing
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cloud_upload, color: Color(0xFF1769E0)),
      title: const Text('Sinkronisasi server'),
      subtitle: const Text('Kirim transaksi pending ke Cloudflare'),
      trailing: const Icon(Icons.chevron_right),
      onTap: syncing ? null : syncTransactions,
    )),
    Card(child: ListTile(
      leading: const Icon(Icons.storage),
      title: const Text('Status penyimpanan lokal'),
      subtitle: Text('${txRows.length} transaksi tersimpan di perangkat'),
    )),
    const Padding(
      padding: EdgeInsets.only(top: 16),
      child: Text('Transaksi disimpan offline terlebih dahulu. Sinkronkan saat internet tersedia.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
    ),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 82,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('RUMAH STATIONERY',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Row(children: [
          Expanded(child: Text(dateLabel, style: const TextStyle(fontSize: 11))),
          Text(timeLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ]),
    ),
    body: SafeArea(child: IndexedStack(index: tab, children: [
      cashierPage(), productPage(), memberPage(), transactionPage(), adminPage(),
    ])),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Kasir'),
        NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Barang'),
        NavigationDestination(icon: Icon(Icons.people), label: 'Member'),
        NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Transaksi'),
        NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
      ],
    ),
  );
}

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


void main() async {
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
    db = await openDatabase(p.join(await getDatabasesPath(), 'rumah_stationery.db'),
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
          ]) { await db.execute(sql); }
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
      });
  }

  Future<void> _seed(Database db) async {
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    if (n != 0) return;
    final rows = [['RS001','Pulpen Standard',2500,120],['RS002','Buku Tulis',3000,85],['RS003','Tinta Epson 664',95000,24],['RS004','Kertas A4',58000,60]];
    for (final r in rows) {
      await db.insert('products', {'id':uuid.v4(),'code':r[0],'name':r[1],'cost_price':0,'price':r[2],
        'middle_price':r[2],'middle_qty':1,'member_price':r[2],'stock':r[3]});
    }
  }

  Future<List<Map<String,Object?>>> products(String q) => q.trim().isEmpty
      ? db.query('products', orderBy:'name COLLATE NOCASE')
      : db.query('products', where:'name LIKE ? OR code LIKE ?', whereArgs:['%${q.trim()}%','%${q.trim()}%'], orderBy:'name COLLATE NOCASE');

  Future<List<Map<String,Object?>>> members() => db.query('members', orderBy:'name COLLATE NOCASE');

  Future<void> addProduct(String code,String name,int cost,int price,int mid,int qty,int stock) async {
    if (qty < 1) throw Exception('Isi satuan tengah minimal 1');
    await db.insert('products', {'id':uuid.v4(),'code':code.trim(),'name':name.trim(),'cost_price':cost,
      'price':price,'middle_price':mid,'middle_qty':qty,'member_price':mid~/qty,'stock':stock});
  }

  Future<void> addMember(String code,String name,String phone,String level,double discount) async {
    await db.insert('members', {'id':uuid.v4(),'code':code.trim(),'name':name.trim(),'phone':phone.trim(),
      'price_level':level,'discount_percent':discount});
  }

  Future<void> updateProduct(
    String id, String code, String name, int cost,
    int price, int mid, int qty, int stock,
  ) async {
    if (qty < 1) throw Exception('Isi satuan minimal 1');
    await db.update('products', {
      'code': code.trim(),
      'name': name.trim(),
      'cost_price': cost,
      'price': price,
      'middle_price': mid,
      'middle_qty': qty,
      'member_price': mid ~/ qty,
      'stock': stock,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteProduct(String id) async {
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMember(
    String id, String code, String name, String phone,
    String level, double discount,
  ) async {
    await db.update('members', {
      'code': code.trim(),
      'name': name.trim(),
      'phone': phone.trim(),
      'price_level': level,
      'discount_percent': discount,
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteMember(String id) async {
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> invoice() async {
    final d=DateTime.now(); final prefix='RS${d.year}${d.month.toString().padLeft(2,'0')}${d.day.toString().padLeft(2,'0')}';
    final r=await db.rawQuery('SELECT COUNT(*) n FROM transactions WHERE invoice_no LIKE ?',['$prefix%']);
    return '$prefix-${((r.first['n'] as int? ?? 0)+1).toString().padLeft(4,'0')}';
  }

  Future<void> save({required List<Map<String,dynamic>> items, required String method,
    required int paid, required int subtotal, required int itemDiscount, required int txnDiscount,
    required int total, required String branch, required String cashier, required String memberCode,
    required String memberName}) async {
    if (method=='Tunai' && paid<total) throw Exception('Uang diterima kurang dari total');
    final change=method=='Tunai' ? paid-total : 0;
        final invoiceNo = await invoice();
    await db.transaction((t) async {
      for (final i in items) {
        final r=await t.query('products',where:'id=?',whereArgs:[i['id']]);
        if(r.isEmpty) throw Exception('Barang tidak ditemukan: ${i['name']}');
        final stock=r.first['stock'] as int, qty=i['qty'] as int;
        if(stock<qty) throw Exception('Stok ${i['name']} tidak cukup');
        await t.update('products',{'stock':stock-qty},where:'id=?',whereArgs:[i['id']]);
      }
      await t.insert('transactions', {'id':uuid.v4(),'invoice_no':invoiceNo,'time':DateTime.now().toIso8601String(),
        'branch':branch,'cashier':cashier,'member_code':memberCode,'member_name':memberName,'payment':method,
        'amount_paid':paid,'change_amount':change,'subtotal':subtotal,'item_discount':itemDiscount,
        'transaction_discount':txnDiscount,'total':total,'payload':jsonEncode(items),'sync_status':'pending'});
    });
  }

  Future<int> sync(String key) async {
    final rows=await db.query('transactions',where:"sync_status='pending'",orderBy:'time ASC',limit:100);
    if(rows.isEmpty) return 0;
    final groups=<String,List<Map<String,Object?>>>{};
    for(final r in rows){groups.putIfAbsent('${r['branch']}',()=>[]).add(r);}
    var count=0;
    for(final e in groups.entries){
      final txs=e.value.map((r)=>{'id':'${r['id']}','created_at':'${r['time']}','payment':'${r['payment']}',
        'amount_paid':r['amount_paid'] ?? r['total'],'change_amount':r['change_amount'] ?? 0,'total':r['total'],
        'payload':{'items':jsonDecode('${r['payload']}'),'invoice_no':r['invoice_no'],'cashier':r['cashier'],
          'member_code':r['member_code'],'member_name':r['member_name'],'subtotal':r['subtotal'],
          'item_discount':r['item_discount'],'transaction_discount':r['transaction_discount']}}).toList();
      final response=await http.post(Uri.parse('$apiUrl/sync/transactions'),
        headers:{'Content-Type':'application/json','Authorization':'Bearer $key'},
        body:jsonEncode({'device_id':'rumah-stationery-android','branch_id':e.key,'transactions':txs}))
        .timeout(const Duration(seconds:25));
      if(response.statusCode!=200) throw Exception('HTTP ${response.statusCode}: ${response.body}');
      final result=jsonDecode(response.body);
      if(result['success']!=true) throw Exception(result['message'] ?? 'Sinkronisasi gagal');
      for(final r in e.value){await db.update('transactions',{'sync_status':'synced'},where:'id=?',whereArgs:[r['id']]);count++;}
    }
    return count;
  }
}

class RumahStationeryApp extends StatelessWidget {
  const RumahStationeryApp({super.key});
  @override Widget build(BuildContext context)=>MaterialApp(title:'Rumah Stationery Kasir',debugShowCheckedModeBanner:false,
    theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF1769E0)),useMaterial3:true),home:const Home());
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> {
  final search=TextEditingController(),code=TextEditingController(),name=TextEditingController(),cost=TextEditingController(text:'0'),
    price=TextEditingController(),mid=TextEditingController(),qty=TextEditingController(text:'10'),stock=TextEditingController(),
    cashier=TextEditingController(text:'Kasir 1'),branch=TextEditingController(text:'PERCOBAAN APK BARU'),memberCode=TextEditingController(),
    memberName=TextEditingController(),phone=TextEditingController(),discount=TextEditingController(text:'0'),
    level=TextEditingController(text:'Retail'),txnDiscount=TextEditingController(text:'0'),cash=TextEditingController();
  List<Map<String,Object?>> ps=[],ms=[];
  final Map<String,Map<String,dynamic>> cart={};
  String method='Tunai'; int tab=0;
  int get subtotal=>cart.values.fold(0,(s,i)=>s+(i['price'] as int)*(i['qty'] as int));
  int get itemDisc=>cart.values.fold(0,(s,i)=>s+(i['discount'] as int));
  int get disc=>int.tryParse(txnDiscount.text)??0;
  int get total=>(subtotal-itemDisc-disc).clamp(0,1<<62).toInt();
  int get paid=>method=='Tunai'?(int.tryParse(cash.text)??0):total;
  int get change=>method=='Tunai'&&paid>=total?paid-total:0;
  String money(int n)=>'Rp ${n.toString().replaceAllMapped(RegExp(r"(\\d)(?=(\\d{3})+(?!\\d))"),(m)=>'${m[1]}.')}';
  void msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  Future<void> refresh() async {final a=await KasirDB.instance.products(search.text),b=await KasirDB.instance.members();if(mounted)setState(()=>{ps=a,ms=b});}
  @override void initState(){super.initState();refresh();}
  @override void dispose(){for(final c in [search,code,name,cost,price,mid,qty,stock,cashier,branch,memberCode,memberName,phone,discount,level,txnDiscount,cash]){c.dispose();}super.dispose();}
  void add(Map<String,Object?> p){final id='${p['id']}';setState((){if(cart.containsKey(id)){cart[id]!['qty']=(cart[id]!['qty'] as int)+1;}else{final m=memberCode.text.isNotEmpty;cart[id]={'id':id,'name':p['name'],'price':m?(p['member_price'] as int):(p['price'] as int),'qty':1,'discount':0};}});}
  Future<void> chooseMember() async {
    final selected=await showDialog<Map<String,Object?>>(context:context,builder:(ctx)=>SimpleDialog(title:const Text('Pilih member'),children:[
      SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,<String,Object?>{}),child:const Text('Tanpa member')),
      ...ms.map((m)=>SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,m),child:Text('${m['name']} • ${m['code']}')))
    ]));
    if(selected==null)return;
    setState(()=>{memberCode.text='${selected['code']??''}',memberName.text='${selected['name']??''}'});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('RUMAH STATIONERY'),backgroundColor:const Color(0xFF102A56),foregroundColor:Colors.white),
    body:SafeArea(child:IndexedStack(index:tab,children:[cashierPage(),productPage(),memberPage(),transactionPage(),adminPage()])),
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[
      NavigationDestination(icon:Icon(Icons.point_of_sale),label:'Kasir'),NavigationDestination(icon:Icon(Icons.inventory_2),label:'Barang'),
      NavigationDestination(icon:Icon(Icons.people),label:'Member'),NavigationDestination(icon:Icon(Icons.receipt_long),label:'Transaksi'),
      NavigationDestination(icon:Icon(Icons.admin_panel_settings),label:'Admin')]));
  Widget cashierPage()=>Column(children:[
    Padding(padding:const EdgeInsets.all(8),child:TextField(controller:search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Cari barang/kode',border:OutlineInputBorder()),onChanged:(_)=>refresh())),
    Expanded(child:GridView.builder(padding:const EdgeInsets.all(8),gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:190,childAspectRatio:1.3),itemCount:ps.length,itemBuilder:(c,i){final p=ps[i];return Card(child:InkWell(onTap:()=>add(p),child:Padding(padding:const EdgeInsets.all(8),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('${p['name']}',textAlign:TextAlign.center),Text(money(p['price'] as int)),Text('Stok ${p['stock']}')]))));})),
    Container(padding:const EdgeInsets.all(8),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Row(children:[Expanded(child:TextField(controller:cashier,decoration:const InputDecoration(labelText:'Kasir'))),const SizedBox(width:8),Expanded(child:TextField(controller:branch,decoration:const InputDecoration(labelText:'Cabang')))]),
      Row(children:[Expanded(child:TextField(controller:memberName,readOnly:true,decoration:const InputDecoration(labelText:'Member'),onTap:chooseMember)),IconButton(onPressed:chooseMember,icon:const Icon(Icons.person_search))]),
      if(cart.isNotEmpty) SizedBox(height:65,child:ListView(children:cart.entries.map((e)=>ListTile(dense:true,title:Text('${e.value['name']} × ${e.value['qty']}'),subtitle:Text('Diskon baris ${money(e.value['discount'] as int)}'),trailing:Wrap(children:[Text(money((e.value['price'] as int)*(e.value['qty'] as int))),IconButton(onPressed:()=>setState(()=>cart.remove(e.key)),icon:const Icon(Icons.close))]))).toList())),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal'),Text(money(subtotal))]),
      TextField(controller:txnDiscount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Diskon transaksi (Rp)'),onChanged:(_)=>setState((){}) ),
      DropdownButton<String>(value:method,items:['Tunai','Transfer','QRIS'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>{method=v??'Tunai',cash.clear()})),
      if(method=='Tunai') TextField(controller:cash,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Uang diterima (Rp)'),onChanged:(_)=>setState((){})),
      Align(alignment:Alignment.centerRight,child:Text('Kembalian: ${money(change)}',style:const TextStyle(fontWeight:FontWeight.bold))),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{
        if(cart.isEmpty){msg('Keranjang kosong');return;} if(disc<0||disc>subtotal-itemDisc){msg('Diskon tidak valid');return;}if(method=='Tunai'&&paid<total){msg('Uang diterima kurang');return;}
        try{await KasirDB.instance.save(items:cart.values.map((e)=>Map<String,dynamic>.from(e)).toList(),method:method,paid:paid,subtotal:subtotal,itemDiscount:itemDisc,txnDiscount:disc,total:total,branch:branch.text.trim().isEmpty?'Rumah Stationery':branch.text.trim(),cashier:cashier.text.trim(),memberCode:memberCode.text,memberName:memberName.text);
          setState(()=>{cart.clear(),cash.clear(),txnDiscount.text='0',memberCode.clear(),memberName.clear()});await refresh();msg('Transaksi tersimpan offline');
        }catch(e){msg('Transaksi gagal: $e');}
      },child:Text('Bayar • ${money(total)}')))
    ]))
  ]);
  Widget productPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Tambah barang',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    TextField(controller:code,decoration:const InputDecoration(labelText:'Kode barang')),TextField(controller:name,decoration:const InputDecoration(labelText:'Nama barang')),
    TextField(controller:cost,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga modal')),
    TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga eceran')),
    TextField(controller:mid,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Harga member satuan tengah')),
    TextField(controller:qty,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Isi satuan tengah (pcs)')),
    TextField(controller:stock,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Stok awal')),
    FilledButton(onPressed:()async{final c=int.tryParse(cost.text),pr=int.tryParse(price.text),m=int.tryParse(mid.text),q=int.tryParse(qty.text),s=int.tryParse(stock.text);
      if(code.text.trim().isEmpty||name.text.trim().isEmpty||c==null||pr==null||m==null||q==null||s==null||c<0||pr<0||m<0||q<1||s<0){msg('Periksa data barang');return;}
      try{await KasirDB.instance.addProduct(code.text,name.text,c,pr,m,q,s);code.clear();name.clear();cost.text='0';price.clear();mid.clear();qty.text='10';stock.clear();await refresh();msg('Barang disimpan');}catch(e){msg('Gagal: pastikan kode unik');}
    },child:const Text('Simpan barang')),
    ...ps.map((p)=>ListTile(title:Text('${p['name']}'),subtitle:Text('${p['code']} • Modal ${money((p['cost_price'] as int?)??0)} • Eceran ${money(p['price'] as int)} • Member ${money(p['member_price'] as int)}'),trailing:Text('Stok ${p['stock']}')))
  ]);
  Widget memberPage()=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Data member',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
    TextField(controller:memberCode,decoration:const InputDecoration(labelText:'Kode member')),TextField(controller:memberName,decoration:const InputDecoration(labelText:'Nama')),
    TextField(controller:phone,decoration:const InputDecoration(labelText:'Telepon')),TextField(controller:level,decoration:const InputDecoration(labelText:'Level harga')),
    TextField(controller:discount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Diskon %')),
    FilledButton(onPressed:()async{final d=double.tryParse(discount.text)??-1;if(memberCode.text.trim().isEmpty||memberName.text.trim().isEmpty||d<0||d>100){msg('Data member tidak valid');return;}
      try{await KasirDB.instance.addMember(memberCode.text,memberName.text,phone.text,level.text,d);memberCode.clear();memberName.clear();phone.clear();discount.text='0';await refresh();msg('Member disimpan');}catch(e){msg('Kode member mungkin sudah dipakai');}
    },child:const Text('Simpan member')),
    ...ms.map((m)=>ListTile(title:Text('${m['name']}'),subtitle:Text("${m['code']} • ${m['phone']} • ${m['price_level']} • ${m['discount_percent']}%")))
  ]);
  
Widget transactionPage() => FutureBuilder<List<Map<String, Object?>>>(
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

    final rows = snapshot.data ?? <Map<String, Object?>>[];

    if (rows.isEmpty) {
      return const Center(child: Text('Belum ada transaksi'));
    }

    return ListView(
      children: rows.map<Widget>((r) {
        return ListTile(
          title: Text('${r['invoice_no']}'),
          subtitle: Text(
            "${r['branch']} • ${r['cashier']} • ${r['payment']}\n"
            "Dibayar ${money((r['amount_paid'] as int?) ?? 0)}"
            " • Kembalian ${money((r['change_amount'] as int?) ?? 0)}",
          ),
          trailing: Text(money((r['total'] as int?) ?? 0)),
        );
      }).toList(),
    );
  },
);

    

Widget adminPage() => ListView(
  padding: const EdgeInsets.all(16),
  children: [
    const Text(
      'Pengaturan admin',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    ),
    TextField(
      controller: branch,
      decoration: const InputDecoration(labelText: 'Nama cabang'),
    ),
    TextField(
      controller: cashier,
      decoration: const InputDecoration(labelText: 'Nama kasir'),
    ),
    const SizedBox(height: 16),

    FilledButton.icon(
      icon: const Icon(Icons.system_update),
      label: const Text('Cek Update Aplikasi'),
      onPressed: () async {
        try {
          final response = await http.get(
            Uri.parse(
              'https://api.github.com/repos/'
              'sachril917-spec/rumahstationery-kasir-modern/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github+json'},
          ).timeout(const Duration(seconds: 20));

          if (!mounted) return;

          if (response.statusCode != 200) {
            msg('Gagal cek update. Periksa koneksi internet.');
            return;
          }

          final data =
              jsonDecode(response.body) as Map<String, dynamic>;
          final tag = data['tag_name']?.toString() ?? 'Versi terbaru';
          final releaseUrl = data['html_url']?.toString();

          String? apkUrl;
          String? apkName;
          final assets = data['assets'];

          if (assets is List) {
            for (final asset in assets) {
              if (asset is Map &&
                  asset['name'] is String &&
                  (asset['name'] as String)
                      .toLowerCase()
                      .endsWith('.apk')) {
                apkUrl = asset['browser_download_url']?.toString();
                apkName = asset['name']?.toString();
                break;
              }
            }
          }

          if (!mounted) return;

          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Update Rumah Stationery'),
              content: Text(
                apkUrl != null
                    ? 'Rilis terbaru: $tag\n'
                        'File: $apkName\n\n'
                        'Unduh APK, lalu buka file dan pilih '
                        'Perbarui. Jangan uninstall aplikasi.'
                    : 'Rilis $tag ditemukan, tetapi file APK '
                        'belum tersedia di rilis ini.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Tutup'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    final target = apkUrl ?? releaseUrl;
                    if (target == null) return;

                    final uri = Uri.tryParse(target);
                    if (uri == null) return;

                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );

                    if (!opened && mounted) {
                      msg('Tidak bisa membuka link unduhan.');
                    }
                  },
                  child: Text(
                    apkUrl != null ? 'Unduh APK' : 'Buka Rilis',
                  ),
                ),
              ],
            ),
          );
        } catch (e) {
          if (mounted) {
            msg('Gagal cek update. Coba lagi.');
          }
        }
      },
    ),

    const SizedBox(height: 12),

    ListTile(
      leading: const Icon(Icons.cloud_upload),
      title: const Text('Sinkronisasi server'),
      subtitle: const Text('Kirim transaksi pending'),
      onTap: () async {
        if (apiKey.isEmpty) {
          msg('API_KEY belum tersedia. Build APK dengan secret API_KEY.');
          return;
        }
        try {
          final n = await KasirDB.instance.sync(apiKey);
          if (mounted) {
            msg('Sinkronisasi berhasil: $n transaksi');
          }
        } catch (e) {
          if (mounted) msg('Sinkronisasi gagal: $e');
        }
      },
    ),
  ],
);


}
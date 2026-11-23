import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

void main() => runApp(const AdlAdminApp());
const api = 'https://rumah-stationery-api.sachril917.workers.dev';
const menus = [
('Dashboard',Icons.dashboard),('Data Cabang',Icons.store),('Pembelian',Icons.shopping_cart),
('Supplier',Icons.local_shipping),('Master Barang',Icons.inventory_2),('Barang Masuk',Icons.move_to_inbox),
('Gudang Pusat',Icons.warehouse),('Distribusi Cabang',Icons.outbox),('Stok Cabang',Icons.storefront),
('Harga Jual',Icons.sell),('Penjualan',Icons.point_of_sale),('Pengeluaran',Icons.receipt_long),
('Hutang Supplier',Icons.account_balance_wallet),('Laporan',Icons.analytics),
('Pengguna & Hak Akses',Icons.manage_accounts),('Riwayat Aktivitas',Icons.history),
('Pengaturan Server',Icons.settings)];

class AdlAdminApp extends StatelessWidget {
 const AdlAdminApp({super.key});
 @override Widget build(BuildContext context)=>MaterialApp(
  title:'ADL Admin Server',debugShowCheckedModeBanner:false,
  theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF17365D))),
  home:const AdminHome());
}
class AdminHome extends StatefulWidget {
 const AdminHome({super.key});
 @override State<AdminHome> createState()=>_AdminHomeState();
}
class _AdminHomeState extends State<AdminHome>{
 static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
 static const String _adminKeyStorageName = 'adl_admin_api_key';
 int selected=0; String keyAdmin='',search=''; bool loading=false; String? error;
 Map<String,dynamic>? overview; List<dynamic> products=[],masterProducts=[],sales=[]; DateTime date=DateTime.now();
List<dynamic> receipts = [];
List<dynamic> centralRecords = [];
final centralTitle = TextEditingController(); final centralCode = TextEditingController(); final centralBranch = TextEditingController(); final centralQty = TextEditingController(text:'0'); final centralAmount = TextEditingController(text:'0'); final centralStatus = TextEditingController(text:'AKTIF');
String get centralModule => const {1:'branches',2:'purchases',3:'suppliers',6:'warehouse_stock',7:'transfers',8:'branch_stock',9:'prices',11:'expenses',12:'supplier_debts',14:'users',15:'activity_logs'}[selected] ?? 'reports';
final supplierController = TextEditingController();
final quantityController = TextEditingController();
final costController = TextEditingController();
final notesController = TextEditingController();
String? receiptProductId;
 String get day=>'${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
 Map<String,String> get headers=>{'Authorization':'Bearer $keyAdmin','Content-Type':'application/json'};
 @override void initState(){
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_)=>_restoreAdminKey());
 }

 Future<void> _restoreAdminKey() async {
  try {
   final saved = await _secureStorage.read(key: _adminKeyStorageName);
   if (!mounted) return;
   if (saved == null || saved.isEmpty) {
    await enterKey();
    return;
   }

   setState(() { keyAdmin = saved; loading = true; error = null; });
   try {
    final result = await callApi('GET', '/admin/overview?date=$day');
    if (mounted) setState(() { overview = result; error = null; });
   } catch (e) {
    if (mounted) setState(() {
     error = 'Kunci tersimpan belum dapat digunakan atau server tidak dapat dijangkau: ${e.toString().replaceFirst('Exception: ', '')}';
    });
   } finally {
    if (mounted) setState(() => loading = false);
   }
  } catch (e) {
   if (mounted) setState(() {
    error = 'Tidak dapat membaca penyimpanan kunci Admin: $e';
   });
   if (mounted) await enterKey();
  }
 }

 Future<void> enterKey() async{
  final c=TextEditingController(text:keyAdmin);
  final v=await showDialog<String>(context:context,barrierDismissible:false,builder:(d)=>AlertDialog(
   title:const Text('Kunci Admin Server'),content:TextField(controller:c,obscureText:true,
   decoration:const InputDecoration(labelText:'ADMIN_API_KEY')),
   actions:[FilledButton(onPressed:()=>Navigator.pop(d,c.text.trim()),child:const Text('Hubungkan'))]));
  c.dispose();
  if(v==null||v.isEmpty)return;

  final previousKey = keyAdmin;
  if (mounted) setState(() { keyAdmin = v; loading = true; error = null; });
  try {
   final result = await callApi('GET', '/admin/overview?date=$day');
   await _secureStorage.write(key: _adminKeyStorageName, value: v);
   if (mounted) setState(() { overview = result; error = null; });
  } catch (e) {
   if (mounted) setState(() {
    keyAdmin = previousKey;
    error = 'Gagal menghubungkan Admin: ${e.toString().replaceFirst('Exception: ', '')}';
   });
   if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(content: Text(error ?? 'Gagal menghubungkan Admin.')),
    );
   }
  } finally {
   if (mounted) setState(() => loading = false);
  }
 }
 Future<Map<String,dynamic>> callApi(String method,String path,[Map<String,dynamic>? body])async{
  final u=Uri.parse('$api$path');late http.Response r;
  if(method=='GET'){r=await http.get(u,headers:headers).timeout(const Duration(seconds:30));}
  else if(method=='POST'){r=await http.post(u,headers:headers,body:jsonEncode(body)).timeout(const Duration(seconds:30));}
  else{r=await http.put(u,headers:headers,body:jsonEncode(body)).timeout(const Duration(seconds:30));}
  final x=jsonDecode(r.body);if(x is! Map<String,dynamic>)throw Exception('Respons server tidak valid.');
  if(r.statusCode<200||r.statusCode>=300||x['success']!=true)throw Exception(x['message']??'HTTP ${r.statusCode}');
  return x;
 }
 Future<void> busy(Future<void> Function() f)async{
  setState(() {
  loading = true;
  error = null;
});
  try{await f();}catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>loading=false);}
 }
 Future<void> loadOverview()=>busy(()async{final x=await callApi('GET','/admin/overview?date=$day');if(mounted)setState(()=>overview=x);});
 Future<void> loadProducts()=>busy(()async{final x=await callApi('GET','/admin/master-products?limit=500');if(mounted)setState(()=>masterProducts=(x['products'] as List?)??[]);});
Future<void> loadGoodsReceipts() => busy(() async {
  final r = await Future.wait([
    callApi('GET', '/admin/products'),
    callApi('GET', '/admin/goods-receipts'),
  ]);

  if (mounted) {
    setState(() {
      products = (r[0]['products'] as List?) ?? [];
      receipts = (r[1]['receipts'] as List?) ?? [];

      if (receiptProductId == null && products.isNotEmpty) {
        receiptProductId = '${products.first['id']}';
      }
    });
  }
});

Future<void> saveGoodsReceipt() async {
  final qty = int.tryParse(quantityController.text.trim());
  final cost = int.tryParse(costController.text.trim());

  if (receiptProductId == null ||
      supplierController.text.trim().isEmpty ||
      qty == null || qty <= 0 ||
      cost == null || cost < 0) {
    setState(() {
      error = 'Lengkapi barang, supplier, jumlah, dan harga beli.';
    });
    return;
  }

  await busy(() async {
    final saved = await callApi('POST', '/admin/goods-receipts', {
      'product_id': receiptProductId,
      'supplier_name': supplierController.text.trim(),
      'quantity': qty,
      'unit_cost': cost,
      'notes': notesController.text.trim(),
    });

    final r = await Future.wait([
      callApi('GET', '/admin/products'),
      callApi('GET', '/admin/goods-receipts'),
    ]);

    if (mounted) {
      setState(() {
        products = (r[0]['products'] as List?) ?? [];
        receipts = (r[1]['receipts'] as List?) ?? [];
        quantityController.clear();
        costController.clear();
        notesController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tersimpan ${saved['receipt_number']}; stok bertambah $qty',
          ),
        ),
      );
    }
  });
}
 Future<void> loadSales()=>busy(()async{final x=await callApi('GET','/admin/sales?date=$day');if(mounted)setState(()=>sales=(x['transaksi'] as List?)??[]);});
 void choose(int i) {
  Navigator.pop(context);
  setState(() => selected = i);

  if (i == 0) loadOverview();
  if (i == 4) loadProducts();
  if (i == 5) loadGoodsReceipts();
  if (i == 10 || i == 13) loadSales();
  if ([1,2,3,6,7,8,9,11,12,14,15].contains(i)) loadCentral();
}
 Future<void> chooseDate()async{final v=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime(2100));if(v==null)return;setState(()=>date=v);if(selected==0)loadOverview();if(selected==10||selected==13)loadSales();}
 String rupiah(dynamic v){final n=(v is num?v:num.tryParse('$v')??0).round().toString();final b=StringBuffer();for(var i=0;i<n.length;i++){if(i>0&&(n.length-i)%3==0)b.write('.');b.write(n[i]);}return 'Rp $b';}
 Future<void> editProduct([Map<String,dynamic>? p])async{
  final form=GlobalKey<FormState>();
  final fields=<String,TextEditingController>{
   'code':TextEditingController(text:'${p?['code']??''}'),
   'barcode':TextEditingController(text:'${p?['barcode']??''}'),
   'name':TextEditingController(text:'${p?['name']??''}'),
   'cost_price':TextEditingController(text:'${p?['cost_price']??0}'),
   'price':TextEditingController(text:'${p?['price']??0}'),
   'middle_price':TextEditingController(text:'${p?['middle_price']??0}'),
   'middle_qty':TextEditingController(text:'${p?['middle_qty']??1}'),
   'member_price':TextEditingController(text:'${p?['member_price']??0}'),
   'unit':TextEditingController(text:'${p?['unit']??'PCS'}'),
   'unit2':TextEditingController(text:'${p?['unit2']??''}'),
   'unit2_qty':TextEditingController(text:'${p?['unit2_qty']??1}'),
   'unit3':TextEditingController(text:'${p?['unit3']??''}'),
   'unit3_qty':TextEditingController(text:'${p?['unit3_qty']??1}'),
   'sales_price':TextEditingController(text:'${p?['sales_price']??0}'),
   'special_price':TextEditingController(text:'${p?['special_price']??0}'),
   'supplier_code':TextEditingController(text:'${p?['supplier_code']??''}'),
   'discount':TextEditingController(text:'${p?['discount']??0}'),
   'category':TextEditingController(text:'${p?['category']??''}'),
  };
  final editing=p!=null;
  final data=await showDialog<Map<String,dynamic>>(context:context,builder:(d)=>AlertDialog(
   title:Text(editing?'Edit Master Barang':'Tambah Master Barang'),
   content:Form(key:form,child:SizedBox(width:460,height:520,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    for(final entry in fields.entries) Padding(padding:const EdgeInsets.only(bottom:8),child:TextFormField(controller:entry.value,
      keyboardType: const {'cost_price','price','middle_price','middle_qty','member_price','unit2_qty','unit3_qty','sales_price','special_price','discount'}.contains(entry.key)?TextInputType.number:TextInputType.text,
      decoration:InputDecoration(labelText:entry.key),
      validator:(v)=>entry.key=='code'||entry.key=='name'?(v==null||v.trim().isEmpty?'Wajib diisi':null):null)),
   ])))),
   actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Batal')),
    FilledButton(onPressed:(){if(!form.currentState!.validate())return;final out=<String,dynamic>{};for(final e in fields.entries){final k=e.key;final v=e.value.text.trim();out[k]=const {'cost_price','price','middle_price','middle_qty','member_price','unit2_qty','unit3_qty','sales_price','special_price','discount'}.contains(k)?(int.tryParse(v)??0):v;}Navigator.pop(d,out);},child:const Text('Simpan'))]));
  final out=data;
  for(final c in fields.values){c.dispose();}
  if(out==null)return;
  await busy(()async{await callApi(editing?'PUT':'POST','/admin/master-products',out);
   final x=await callApi('GET','/admin/master-products?limit=500');if(mounted){setState(()=>masterProducts=(x['products'] as List?)??[]);
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Master barang tersimpan di server pusat')));}});
 }

 bool updatingAdmin = false;
 Future<void> updateAdminApk() async {
  if (updatingAdmin) return;
  setState(() => updatingAdmin = true);
  try {
   final check = await http.get(
    Uri.parse('https://api.github.com/repos/sachril917-spec/rumahstationery-kasir-modern/releases?per_page=100'),
    headers: {'Accept': 'application/vnd.github+json'},
   ).timeout(const Duration(seconds: 30));
   if (check.statusCode != 200) throw Exception('Gagal memeriksa update GitHub (HTTP ${check.statusCode}).');
   final releases = jsonDecode(check.body) as List<dynamic>;
   final admin = releases.where((e) => RegExp(r'^admin-build-\d+$').hasMatch('${e['tag_name']}') && e['draft'] != true).toList();
   if (admin.isEmpty) throw Exception('Belum ada update Admin yang diterbitkan.');
   admin.sort((a,b) => int.parse('${b['tag_name']}'.replaceFirst('admin-build-', '')).compareTo(int.parse('${a['tag_name']}'.replaceFirst('admin-build-', ''))));
   final latest = admin.first as Map<String,dynamic>;
   final latestBuild = int.parse('${latest['tag_name']}'.replaceFirst('admin-build-', ''));
   final info = await PackageInfo.fromPlatform();
   final installedBuild = int.tryParse(info.buildNumber) ?? 0;
   if (latestBuild <= installedBuild) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin sudah menggunakan versi terbaru.')));
    return;
   }
   final assets = latest['assets'] as List<dynamic>? ?? [];
   final matches = assets.where((a) => a['name'] == 'ADL-Admin-Server.apk').toList();
   if (matches.isEmpty) throw Exception('File APK pada Release tidak ditemukan.');
   final url = matches.first['browser_download_url'] as String;
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update build $latestBuild tersedia. Mengunduh...')));
   final response = await http.get(Uri.parse(url)).timeout(const Duration(minutes: 3));
   if (response.statusCode != 200 || response.bodyBytes.isEmpty) throw Exception('Gagal mengunduh APK.');
   final dir = await getTemporaryDirectory();
   final file = File('${dir.path}/ADL-Admin-Server-update.apk');
   await file.writeAsBytes(response.bodyBytes, flush: true);
   final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
   if (result.type != ResultType.done) throw Exception('APK terunduh, tetapi installer tidak terbuka: ${result.message}');
  } catch (e) {
   if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update gagal: ${e.toString().replaceFirst('Exception: ', '')}')));
  } finally {
   if (mounted) setState(() => updatingAdmin = false);
  }
 }

 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(menus[selected].$1.toUpperCase()),actions:[
   IconButton(onPressed:enterKey,icon:const Icon(Icons.key),tooltip:'Ganti kunci Admin'),
   IconButton(onPressed:()=>selected==4?loadProducts():(selected==10||selected==13)?loadSales():loadOverview(),icon:const Icon(Icons.refresh))]),
  drawer:NavigationDrawer(selectedIndex:selected,onDestinationSelected:choose,children:[
   const Padding(padding:EdgeInsets.all(20),child:Text('RUMAH STATIONERY • ADL',style:TextStyle(fontWeight:FontWeight.bold))),
   for(var i=0;i<menus.length;i++)NavigationDrawerDestination(icon:Icon(menus[i].$2),label:Text(menus[i].$1))]),
  body:page());
 Widget page() {
  if (selected == 16) return ListView(padding:const EdgeInsets.all(20),children:[const Text('PENGATURAN SERVER',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:10),Text(keyAdmin.isEmpty?'Admin belum terhubung.':'Kunci Admin sudah tersimpan aman di perangkat.'),const SizedBox(height:12),FilledButton.icon(onPressed:enterKey,icon:const Icon(Icons.key),label:const Text('GANTI / HUBUNGKAN KUNCI ADMIN')),if(error!=null)errorCard()]);
  if (selected == 0) return dashboard();
  if (selected == 4) return productPage();
  if (selected == 5) return goodsReceiptPage();
  if (selected == 10 || selected == 13) return salesPage();
  if ([1,2,3,6,7,8,9,11,12,14,15].contains(selected)) return centralPage();

  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        '${menus[selected].$1}\n\nMenu ini belum dihubungkan ke database.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
      ),
    ),
  );
}
 Widget dashboard()=>RefreshIndicator(onRefresh:loadOverview,child:ListView(padding:const EdgeInsets.all(16),children:[
  const Text('Dashboard Pusat ADL',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const Text('Ringkasan data dari Cloudflare D1'),
   Card(child: ListTile(
    leading: const Icon(Icons.system_update_alt, color: Color(0xFF1769AA)),
    title: const Text('Update Admin Server', style: TextStyle(fontWeight: FontWeight.bold)),
    subtitle: const Text('Periksa dan pasang update terbaru'),
    trailing: updatingAdmin ? const SizedBox(width:24,height:24,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.download),
    onTap: updatingAdmin ? null : updateAdminApk,
   )), 
  OutlinedButton.icon(onPressed:chooseDate,icon:const Icon(Icons.calendar_month),label:Text('Tanggal: $day')),
  if(loading)const LinearProgressIndicator(),if(error!=null)errorCard(),
  if(overview!=null)...[stat('${overview!['products']??0}','Master Barang'),stat('${overview!['total_stock']??0}','Total Stok'),
   stat('${overview!['sales_count']??0}','Transaksi'),stat(rupiah(overview!['sales_total']),'Penjualan'),
   stat('${overview!['expenses_count']??0}','Jumlah Pengeluaran'),stat(rupiah(overview!['expenses_total']),'Total Pengeluaran'),
   const Text('PENJUALAN PER CABANG',style:TextStyle(fontWeight:FontWeight.bold)),
   ...((overview!['branch_sales'] as List?)??[]).map((e){final x=e as Map<String,dynamic>;return Card(child:ListTile(
    title:Text('${x['branch_id']??'-'}'),subtitle:Text('${x['count']??0} transaksi'),trailing:Text(rupiah(x['total']))));})]
 ]));
 Widget productPage(){
  final q=search.toLowerCase();final list=masterProducts.where((e){final x=e as Map<String,dynamic>;return '${x['name']??''}'.toLowerCase().contains(q)||'${x['barcode']??''}'.toLowerCase().contains(q)||'${x['code']??''}'.toLowerCase().contains(q);}).toList();
  return Column(children:[
   Padding(padding:const EdgeInsets.fromLTRB(12,12,12,4),child:TextField(onChanged:(v)=>setState(()=>search=v),
    decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Cari nama barang / barcode',border:const OutlineInputBorder(),
     suffixIcon:search.isEmpty?null:IconButton(onPressed:()=>setState(()=>search=''),icon:const Icon(Icons.close))))),
   Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(children:[
    Expanded(child:Text('${list.length} barang')),FilledButton.icon(onPressed:()=>editProduct(),icon:const Icon(Icons.add),label:const Text('Tambah'))])),
   if(loading)const LinearProgressIndicator(),if(error!=null)errorCard(),
   Expanded(child:list.isEmpty?Center(child:Text(masterProducts.isEmpty?'Belum ada master barang di server.':'Barang tidak ditemukan.')):
    ListView.builder(itemCount:list.length,itemBuilder:(c,i){final x=list[i] as Map<String,dynamic>;return Card(child:ListTile(
     title:Text('${x['name']??'-'}'),subtitle:Text('Kode: ${x['code']??'-'} | Barcode: ${x['barcode']??'-'}\\nHarga: ${rupiah(x['price'])}'),isThreeLine:true,
     trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(rupiah(x['price']),style:const TextStyle(fontWeight:FontWeight.bold)),const Text('EDIT',style:TextStyle(fontSize:11))]),
     onTap:()=>editProduct(x)));})),
  ]);
 }
Widget goodsReceiptPage() {
  String money(dynamic v) => rupiah(v);

  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'PENERIMAAN BARANG GUDANG PUSAT',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),

      const SizedBox(height: 8),

      const Text(
        'Barang diterima dari supplier akan menambah stok dan tercatat di riwayat.',
      ),

      const SizedBox(height: 12),

      if (loading) const LinearProgressIndicator(),
      if (error != null) errorCard(),

      TextField(
        controller: supplierController,
        decoration: const InputDecoration(
          labelText: 'Nama supplier *',
          border: OutlineInputBorder(),
        ),
      ),

      const SizedBox(height: 10),

      DropdownButtonFormField<String>(
        value: products.any((e) => '${e['id']}' == receiptProductId)
            ? receiptProductId
            : null,
        decoration: const InputDecoration(
          labelText: 'Pilih barang *',
          border: OutlineInputBorder(),
        ),
        items: products.map((e) {
          return DropdownMenuItem<String>(
            value: '${e['id']}',
            child: Text(
              '${e['name']} (stok: ${e['stock']})',
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (v) {
          setState(() => receiptProductId = v);
        },
      ),

      const SizedBox(height: 10),

      TextField(
        controller: quantityController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Jumlah diterima *',
          border: OutlineInputBorder(),
        ),
      ),

      const SizedBox(height: 10),

      TextField(
        controller: costController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Harga beli per unit (Rp) *',
          border: OutlineInputBorder(),
        ),
      ),

      const SizedBox(height: 10),

      TextField(
        controller: notesController,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Catatan (opsional)',
          border: OutlineInputBorder(),
        ),
      ),

      const SizedBox(height: 12),

      FilledButton.icon(
        onPressed: loading ? null : saveGoodsReceipt,
        icon: const Icon(Icons.save),
        label: const Text('SIMPAN BARANG MASUK'),
      ),

      const Divider(height: 28),

      const Text(
        'RIWAYAT BARANG MASUK',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),

      if (receipts.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Belum ada riwayat barang masuk.'),
        ),

      ...receipts.map((e) {
        final x = e as Map<String, dynamic>;

        return Card(
          child: ListTile(
            title: Text('${x['product_name']}'),
            subtitle: Text(
              '${x['receipt_number']} • Supplier: ${x['supplier_name']}\n'
              '${x['received_at']} • Qty: ${x['quantity']} × '
              '${money(x['unit_cost'])}',
            ),
            isThreeLine: true,
            trailing: Text(
              money(x['total_cost']),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }),
    ],
  );
}
 Widget salesPage()=>Column(children:[
  Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:Text('Tanggal: $day')),
   TextButton.icon(onPressed:chooseDate,icon:const Icon(Icons.calendar_month),label:const Text('Pilih tanggal'))])),
  if(loading)const LinearProgressIndicator(),if(error!=null)errorCard(),
  Expanded(child:sales.isEmpty?const Center(child:Text('Belum ada transaksi pada tanggal ini.')):
   ListView.builder(itemCount:sales.length,itemBuilder:(c,i){final x=sales[i] as Map<String,dynamic>;return Card(child:ListTile(
    title:Text('${x['id']??'-'}'),subtitle:Text('${x['branch_id']??'-'} • ${x['created_at']??'-'} • ${x['payment']??'-'}'),trailing:Text(rupiah(x['total']))));}))
 ]);
 Future<void> loadCentral() => busy(() async {
  final x=await callApi('GET','/admin/central/$centralModule');
  if(mounted)setState(()=>centralRecords=(x['records'] as List?)??[]);
 });
 Future<void> addCentralRecord() async {
  centralTitle.clear(); centralCode.clear(); centralBranch.clear(); centralQty.text='0'; centralAmount.text='0'; centralStatus.text='AKTIF';
  final form=GlobalKey<FormState>();
  final result=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(
   title:Text('Tambah ${menus[selected].$1}'),
   content:Form(key:form,child:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextFormField(controller:centralTitle,decoration:const InputDecoration(labelText:'Nama / Keterangan *'),validator:(v)=>v==null||v.trim().isEmpty?'Wajib diisi':null),
    TextFormField(controller:centralCode,decoration:const InputDecoration(labelText:'Kode / Nomor')),
    TextFormField(controller:centralBranch,decoration:const InputDecoration(labelText:'Cabang / Lokasi')),
    TextFormField(controller:centralQty,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Jumlah')),
    TextFormField(controller:centralAmount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Nominal (Rp)')),
    TextFormField(controller:centralStatus,decoration:const InputDecoration(labelText:'Status')),
   ])))),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(d,form.currentState!.validate()),child:const Text('Simpan'))]));
  if(result!=true)return;
  await busy(()async{
   await callApi('POST','/admin/central/$centralModule',{'title':centralTitle.text.trim(),'code':centralCode.text.trim(),'branch':centralBranch.text.trim(),'quantity':double.tryParse(centralQty.text) ?? 0,'amount':int.tryParse(centralAmount.text) ?? 0,'status':centralStatus.text.trim(),'module_label':menus[selected].$1});
   final x=await callApi('GET','/admin/central/$centralModule'); if(mounted)setState(()=>centralRecords=(x['records'] as List?)??[]);
  });
 }
 Widget centralPage()=>RefreshIndicator(onRefresh:loadCentral,child:ListView(padding:const EdgeInsets.all(14),children:[
  Text(menus[selected].$1,style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
  const SizedBox(height:5),Text('Data tersimpan di server pusat ADL • ${centralRecords.length} catatan'),
  const SizedBox(height:12),Row(children:[Expanded(child:OutlinedButton.icon(onPressed:loadCentral,icon:const Icon(Icons.refresh),label:const Text('Muat ulang'))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:loading?null:addCentralRecord,icon:const Icon(Icons.add),label:const Text('Tambah data')))]),
  if(loading)const LinearProgressIndicator(),if(error!=null)errorCard(),
  if(centralRecords.isEmpty)const Padding(padding:EdgeInsets.all(28),child:Center(child:Text('Belum ada data. Tekan Tambah data untuk mulai.'))),
  ...centralRecords.map((e){final x=e as Map<String,dynamic>;return Card(child:ListTile(title:Text('${x['title']??'-'}'),subtitle:Text('Kode: ${x['code']??'-'} • Cabang: ${x['branch']??'-'}\nJumlah: ${x['quantity']??0} • Status: ${x['status']??'-'}'),isThreeLine:true,trailing:Text(rupiah(x['amount'])) ,onLongPress:()=>_deleteCentral('${x['id']}')));})
 ]));
 Future<void> _deleteCentral(String id)async{final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('Hapus data?'),content:const Text('Data ini akan dihapus dari modul.'),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('Hapus'))]));if(ok!=true)return;await busy(()async{await http.delete(Uri.parse('$api/admin/central/$centralModule?id=$id'),headers:headers).then((r){final x=jsonDecode(r.body);if(r.statusCode<200||r.statusCode>=300||x['success']!=true)throw Exception(x['message']??'Gagal hapus');});final x=await callApi('GET','/admin/central/$centralModule');if(mounted)setState(()=>centralRecords=(x['records'] as List?)??[]);});}

 Widget stat(String v,String l)=>Card(child:ListTile(title:Text(v,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),subtitle:Text(l)));
 Widget errorCard()=>Card(color:Theme.of(context).colorScheme.errorContainer,child:Padding(padding:const EdgeInsets.all(12),child:Text(error??'')));
}

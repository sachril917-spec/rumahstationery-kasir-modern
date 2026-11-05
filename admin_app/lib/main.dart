import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const AdlAdminApp());

const api = 'https://rumah-stationery-api.sachril917.workers.dev';
const menus = [
  ('Dashboard', Icons.dashboard), ('Data Cabang', Icons.store),
  ('Pembelian', Icons.shopping_cart), ('Supplier', Icons.local_shipping),
  ('Master Barang', Icons.inventory_2), ('Barang Masuk', Icons.move_to_inbox),
  ('Gudang Pusat', Icons.warehouse), ('Distribusi Cabang', Icons.outbox),
  ('Stok Cabang', Icons.storefront), ('Harga Jual', Icons.sell),
  ('Penjualan', Icons.point_of_sale), ('Pengeluaran', Icons.receipt_long),
  ('Hutang Supplier', Icons.account_balance_wallet), ('Laporan', Icons.analytics),
  ('Pengguna & Hak Akses', Icons.manage_accounts),
  ('Riwayat Aktivitas', Icons.history), ('Pengaturan Server', Icons.settings),
];

class AdlAdminApp extends StatelessWidget {
  const AdlAdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Admin Server ADL', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF17365D))),
    home: const AdminHome(),
  );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int selected = 0;
  String keyAdmin = '';
  bool loading = false;
  String? error;
  Map<String,dynamic>? overview;
  List<dynamic> products = [], sales = [];
  DateTime date = DateTime.now();

  String get day => '${date.year.toString().padLeft(4,'0')}-'
    '${date.month.toString().padLeft(2,'0')}-'
    '${date.day.toString().padLeft(2,'0')}';

  Map<String,String> get headers => {'Authorization':'Bearer $keyAdmin'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => enterKey());
  }

  Future<void> enterKey() async {
    final c = TextEditingController(text: keyAdmin);
    final value = await showDialog<String>(context: context, barrierDismissible:false,
      builder: (d) => AlertDialog(
        title: const Text('Kunci Admin Server'),
        content: TextField(controller:c, obscureText:true,
          decoration: const InputDecoration(labelText:'ADMIN_API_KEY')),
        actions:[FilledButton(onPressed:()=>Navigator.pop(d,c.text.trim()),
          child:const Text('Hubungkan'))],
      ));
    c.dispose();
    if (value == null || value.isEmpty) return;
    setState(()=>keyAdmin=value);
    await loadOverview();
  }

  Future<Map<String,dynamic>> getData(String path) async {
    final r=await http.get(Uri.parse('$api$path'),headers:headers)
      .timeout(const Duration(seconds:25));
    final v=jsonDecode(r.body);
    if (v is! Map<String,dynamic>) throw Exception('Respons server tidak valid.');
    if (r.statusCode<200 || r.statusCode>=300 || v['success']!=true) {
      throw Exception(v['message'] ?? 'HTTP ${r.statusCode}');
    }
    return v;
  }

  Future<void> runLoad(Future<void> Function() action) async {
    setState(() { loading = true; error = null; });
    try { await action(); }
    catch(e) { if(mounted) setState(()=>error=e.toString().replaceFirst('Exception: ','')); }
    finally { if(mounted) setState(()=>loading=false); }
  }

  Future<void> loadOverview() => runLoad(() async {
    final v=await getData('/admin/overview?date=$day');
    if(mounted) setState(()=>overview=v);
  });
  Future<void> loadProducts() => runLoad(() async {
    final v=await getData('/admin/products');
    if(mounted) setState(()=>products=(v['products'] as List?) ?? []);
  });
  Future<void> loadSales() => runLoad(() async {
    final v=await getData('/admin/sales?date=$day');
    if(mounted) setState(()=>sales=(v['transaksi'] as List?) ?? []);
  });

  void choose(int i) {
    setState(()=>selected=i);
    Navigator.pop(context);
    if(i==0) loadOverview();
    if(i==4) loadProducts();
    if(i==10 || i==13) loadSales();
  }

  Future<void> chooseDate() async {
    final v=await showDatePicker(context:context,initialDate:date,
      firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(v==null) return;
    setState(()=>date=v);
    if(selected==0) loadOverview();
    if(selected==10 || selected==13) loadSales();
  }

  String rupiah(dynamic v) {
    final n=(v is num ? v : 0).round().toString();
    final b=StringBuffer();
    for(var i=0;i<n.length;i++){if(i>0 && (n.length-i)%3==0)b.write('.');b.write(n[i]);}
    return 'Rp $b';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(menus[selected].$1.toUpperCase()),actions:[
      IconButton(onPressed:enterKey,icon:const Icon(Icons.key),tooltip:'Ganti API key'),
      IconButton(onPressed:()=>selected==4?loadProducts():
        (selected==10||selected==13)?loadSales():loadOverview(),
        icon:const Icon(Icons.refresh)),
    ]),
    drawer:NavigationDrawer(selectedIndex:selected,onDestinationSelected:choose,
      children:[
        const Padding(padding:EdgeInsets.all(20),child:Text('RUMAH STATIONERY • ADL',
          style:TextStyle(fontWeight:FontWeight.bold))),
        for(var i=0;i<menus.length;i++) NavigationDrawerDestination(
          icon:Icon(menus[i].$2),label:Text(menus[i].$1)),
      ]),
    body:page(),
  );

  Widget page() {
    if(selected==0) return dashboard();
    if(selected==4) return productPage();
    if(selected==10||selected==13) return salesPage();
    return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text(
      '${menus[selected].$1}\n\nMenu ini belum dihubungkan ke database. '
      'Saat ini Dashboard, Master Barang (baca), dan Penjualan (baca) sudah terhubung.',
      textAlign:TextAlign.center,style:const TextStyle(fontSize:18))));
  }

  Widget dashboard() => RefreshIndicator(onRefresh:loadOverview,child:ListView(
    padding:const EdgeInsets.all(16),children:[
      const Text('Dashboard Pusat ADL',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
      const Text('Ringkasan data dari Cloudflare D1'),
      OutlinedButton.icon(onPressed:chooseDate,icon:const Icon(Icons.calendar_month),
        label:Text('Tanggal: $day')),
      if(loading) const LinearProgressIndicator(),
      if(error!=null) errorCard(),
      if(overview!=null)...[
        stat('${overview!['products']??0}','Master Barang'),
        stat('${overview!['total_stock']??0}','Total Stok'),
        stat('${overview!['sales_count']??0}','Transaksi'),
        stat(rupiah(overview!['sales_total']),'Penjualan'),
        stat('${overview!['expenses_count']??0}','Jumlah Pengeluaran'),
        stat(rupiah(overview!['expenses_total']),'Total Pengeluaran'),
        const SizedBox(height:12),
        const Text('PENJUALAN PER CABANG',style:TextStyle(fontWeight:FontWeight.bold)),
        ...((overview!['branch_sales'] as List?)??[]).map((x){
          final r=x as Map<String,dynamic>;
          return Card(child:ListTile(title:Text('${r['branch_id']??'-'}'),
            subtitle:Text('${r['count']??0} transaksi'),trailing:Text(rupiah(r['total']))));
        }),
      ],
    ]));

  Widget productPage()=>Column(children:[
    if(loading) const LinearProgressIndicator(),
    if(error!=null) errorCard(),
    Expanded(child:products.isEmpty?const Center(child:Text('Belum ada data barang.')):
      ListView.builder(itemCount:products.length,itemBuilder:(c,i){
        final x=products[i] as Map<String,dynamic>;
        return Card(child:ListTile(title:Text('${x['name']??'-'}'),
          subtitle:Text('Barcode: ${x['barcode']??'-'} • Stok: ${x['stock']??0}'),
          trailing:Text(rupiah(x['price']))));
      })),
  ]);

  Widget salesPage()=>Column(children:[
    Padding(padding:const EdgeInsets.all(12),child:Row(children:[
      Expanded(child:Text('Tanggal: $day')),
      TextButton.icon(onPressed:chooseDate,icon:const Icon(Icons.calendar_month),
        label:const Text('Pilih tanggal')),
    ])),
    if(loading) const LinearProgressIndicator(),
    if(error!=null) errorCard(),
    Expanded(child:sales.isEmpty?const Center(child:Text('Belum ada transaksi pada tanggal ini.')):
      ListView.builder(itemCount:sales.length,itemBuilder:(c,i){
        final x=sales[i] as Map<String,dynamic>;
        return Card(child:ListTile(title:Text('${x['id']??'-'}'),
          subtitle:Text('${x['branch_id']??'-'} • ${x['created_at']??'-'} • ${x['payment']??'-'}'),
          trailing:Text(rupiah(x['total']))));
      })),
  ]);

  Widget stat(String value,String label)=>Card(child:ListTile(
    title:Text(value,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
    subtitle:Text(label)));
  Widget errorCard()=>Card(color:Theme.of(context).colorScheme.errorContainer,
    child:Padding(padding:const EdgeInsets.all(12),child:Text(error??'')));
}

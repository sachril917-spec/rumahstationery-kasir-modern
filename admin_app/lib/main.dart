import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
 int selected=0; String keyAdmin='',search=''; bool loading=false; String? error;
 Map<String,dynamic>? overview; List<dynamic> products=[],sales=[]; DateTime date=DateTime.now();
 String get day=>'${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
 Map<String,String> get headers=>{'Authorization':'Bearer $keyAdmin','Content-Type':'application/json'};
 @override void initState(){super.initState();WidgetsBinding.instance.addPostFrameCallback((_)=>enterKey());}
 Future<void> enterKey() async{
  final c=TextEditingController(text:keyAdmin);
  final v=await showDialog<String>(context:context,barrierDismissible:false,builder:(d)=>AlertDialog(
   title:const Text('Kunci Admin Server'),content:TextField(controller:c,obscureText:true,
   decoration:const InputDecoration(labelText:'ADMIN_API_KEY')),
   actions:[FilledButton(onPressed:()=>Navigator.pop(d,c.text.trim()),child:const Text('Hubungkan'))]));
  c.dispose();if(v==null||v.isEmpty)return;setState(()=>keyAdmin=v);await loadOverview();
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
  setState(()=>{loading=true,error=null});
  try{await f();}catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
  finally{if(mounted)setState(()=>loading=false);}
 }
 Future<void> loadOverview()=>busy(()async{final x=await callApi('GET','/admin/overview?date=$day');if(mounted)setState(()=>overview=x);});
 Future<void> loadProducts()=>busy(()async{final x=await callApi('GET','/admin/products');if(mounted)setState(()=>products=(x['products'] as List?)??[]);});
 Future<void> loadSales()=>busy(()async{final x=await callApi('GET','/admin/sales?date=$day');if(mounted)setState(()=>sales=(x['transaksi'] as List?)??[]);});
 void choose(int i){Navigator.pop(context);setState(()=>selected=i);if(i==0)loadOverview();if(i==4)loadProducts();if(i==10||i==13)loadSales();}
 Future<void> chooseDate()async{final v=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2020),lastDate:DateTime(2100));if(v==null)return;setState(()=>date=v);if(selected==0)loadOverview();if(selected==10||selected==13)loadSales();}
 String rupiah(dynamic v){final n=(v is num?v:num.tryParse('$v')??0).round().toString();final b=StringBuffer();for(var i=0;i<n.length;i++){if(i>0&&(n.length-i)%3==0)b.write('.');b.write(n[i]);}return 'Rp $b';}
 Future<void> editProduct([Map<String,dynamic>? p])async{
  final form=GlobalKey<FormState>();final barcode=TextEditingController(text:'${p?['barcode']??''}');
  final name=TextEditingController(text:'${p?['name']??''}');final price=TextEditingController(text:'${p?['price']??''}');
  final stock=TextEditingController(text:'${p?['stock']??0}');final editing=p!=null;
  final data=await showDialog<Map<String,dynamic>>(context:context,builder:(d)=>AlertDialog(
   title:Text(editing?'Edit Barang':'Tambah Barang'),
   content:Form(key:form,child:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextFormField(controller:barcode,decoration:const InputDecoration(labelText:'Barcode (opsional)')),
    TextFormField(controller:name,decoration:const InputDecoration(labelText:'Nama barang *'),validator:(v)=>v==null||v.trim().isEmpty?'Nama wajib diisi':null),
    TextFormField(controller:price,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Harga jual *'),
     validator:(v){final n=double.tryParse(v??'');return n==null||n<0?'Harga tidak valid':null;}),
    TextFormField(controller:stock,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Stok *'),
     validator:(v){final n=int.tryParse(v??'');return n==null||n<0?'Stok harus bilangan bulat 0 atau lebih':null;})
   ])))),
   actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Batal')),
    FilledButton(onPressed:(){if(!form.currentState!.validate())return;Navigator.pop(d,{
     if(editing)'id':p['id'],'barcode':barcode.text.trim(),'name':name.text.trim(),
     'price':double.parse(price.text),'stock':int.parse(stock.text)});},child:Text(editing?'Simpan':'Tambah'))]));
  barcode.dispose();name.dispose();price.dispose();stock.dispose();if(data==null)return;
  await busy(()async{await callApi(editing?'PUT':'POST','/admin/products',data);
   final x=await callApi('GET','/admin/products');if(mounted){setState(()=>products=(x['products'] as List?)??[]);
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(editing?'Barang diperbarui':'Barang ditambahkan')));}});
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(menus[selected].$1.toUpperCase()),actions:[
   IconButton(onPressed:enterKey,icon:const Icon(Icons.key),tooltip:'Ganti kunci Admin'),
   IconButton(onPressed:()=>selected==4?loadProducts():(selected==10||selected==13)?loadSales():loadOverview(),icon:const Icon(Icons.refresh))]),
  drawer:NavigationDrawer(selectedIndex:selected,onDestinationSelected:choose,children:[
   const Padding(padding:EdgeInsets.all(20),child:Text('RUMAH STATIONERY • ADL',style:TextStyle(fontWeight:FontWeight.bold))),
   for(var i=0;i<menus.length;i++)NavigationDrawerDestination(icon:Icon(menus[i].$2),label:Text(menus[i].$1))]),
  body:page());
 Widget page(){if(selected==0)return dashboard();if(selected==4)return productPage();if(selected==10||selected==13)return salesPage();
  return Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('${menus[selected].$1}\n\nMenu ini belum dihubungkan ke database.',textAlign:TextAlign.center,style:const TextStyle(fontSize:18))));}
 Widget dashboard()=>RefreshIndicator(onRefresh:loadOverview,child:ListView(padding:const EdgeInsets.all(16),children:[
  const Text('Dashboard Pusat ADL',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const Text('Ringkasan data dari Cloudflare D1'),
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
  final q=search.toLowerCase();final list=products.where((e){final x=e as Map<String,dynamic>;return '${x['name']??''}'.toLowerCase().contains(q)||'${x['barcode']??''}'.toLowerCase().contains(q);}).toList();
  return Column(children:[
   Padding(padding:const EdgeInsets.fromLTRB(12,12,12,4),child:TextField(onChanged:(v)=>setState(()=>search=v),
    decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Cari nama barang / barcode',border:const OutlineInputBorder(),
     suffixIcon:search.isEmpty?null:IconButton(onPressed:()=>setState(()=>search=''),icon:const Icon(Icons.close))))),
   Padding(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),child:Row(children:[
    Expanded(child:Text('${list.length} barang')),FilledButton.icon(onPressed:()=>editProduct(),icon:const Icon(Icons.add),label:const Text('Tambah'))])),
   if(loading)const LinearProgressIndicator(),if(error!=null)errorCard(),
   Expanded(child:list.isEmpty?Center(child:Text(products.isEmpty?'Belum ada data barang.':'Barang tidak ditemukan.')):
    ListView.builder(itemCount:list.length,itemBuilder:(c,i){final x=list[i] as Map<String,dynamic>;return Card(child:ListTile(
     title:Text('${x['name']??'-'}'),subtitle:Text('Barcode: ${x['barcode']??'-'}\\nStok: ${x['stock']??0}'),isThreeLine:true,
     trailing:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(rupiah(x['price']),style:const TextStyle(fontWeight:FontWeight.bold)),const Text('EDIT',style:TextStyle(fontSize:11))]),
     onTap:()=>editProduct(x)));})),
  ]);
 }
 Widget salesPage()=>Column(children:[
  Padding(padding:const EdgeInsets.all(12),child:Row(children:[Expanded(child:Text('Tanggal: $day')),
   TextButton.icon(onPressed:chooseDate,icon:const Icon(Icons.calendar_month),label:const Text('Pilih tanggal'))])),
  if(loading)const LinearProgressIndicator(),if(error!=null)errorCard(),
  Expanded(child:sales.isEmpty?const Center(child:Text('Belum ada transaksi pada tanggal ini.')):
   ListView.builder(itemCount:sales.length,itemBuilder:(c,i){final x=sales[i] as Map<String,dynamic>;return Card(child:ListTile(
    title:Text('${x['id']??'-'}'),subtitle:Text('${x['branch_id']??'-'} • ${x['created_at']??'-'} • ${x['payment']??'-'}'),trailing:Text(rupiah(x['total']))));}))
 ]);
 Widget stat(String v,String l)=>Card(child:ListTile(title:Text(v,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),subtitle:Text(l)));
 Widget errorCard()=>Card(color:Theme.of(context).colorScheme.errorContainer,child:Padding(padding:const EdgeInsets.all(12),child:Text(error??'')));
}

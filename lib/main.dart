import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

const String supabaseUrl = "https://hbewnquphiwvxaxittrl.supabase.co";
const String supabaseKey = "sb_publishable_HA1-PBV55kEZet2GG_IBdg_HjUzfOxf";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  } catch (_) {}
  runApp(const MaterialApp(
    home: AppGateway(),
    debugShowCheckedModeBanner: false,
  ));
}

class AppGateway extends StatelessWidget {
  const AppGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('होटल मैनेजमेंट सिस्टम', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roleCard(context, '🖥️ काउंटर मास्टर (ओनर)', 'बिलिंग, मेन्यू, प्रिंटर, पार्सल व गल्ला', const Color(0xFF0F172A), 'counter'),
            const SizedBox(height: 18),
            _roleCard(context, '📱 वेटर मोड', 'टेबल ऑर्डर, त्वरित KOT व रनिंग टेबल', const Color(0xFFEA580C), 'waiter'),
            const SizedBox(height: 18),
            _roleCard(context, '👨‍🍳 कुक मोड', 'किचन डिस्प्ले (KDS) व राशन मांग', const Color(0xFF0D9488), 'cook'),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(BuildContext ctx, String title, String sub, Color col, String role) {
    return InkWell(
      onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => StaffAuthScreen(role: role))),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: col,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: col.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white60, size: 18)
          ],
        ),
      ),
    );
  }
}

// ---------------- ऑथेंटिकेशन स्क्रीन ----------------
class StaffAuthScreen extends StatefulWidget {
  final String role;
  const StaffAuthScreen({super.key, required this.role});
  @override
  State<StaffAuthScreen> createState() => _StaffAuthScreenState();
}

class _StaffAuthScreenState extends State<StaffAuthScreen> {
  final _codeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  void _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _codeCtrl.text = prefs.getString('saved_store_code') ?? '';
  }

  void _verify() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final pin = _pinCtrl.text.trim();
    if (code.isEmpty || pin.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select()
          .eq('store_code', code)
          .maybeSingle();

      if (res == null || res['is_active'] == false) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कोड गलत है या लाइसेंस ब्लॉक है!')));
        setState(() => _loading = false);
        return;
      }

      bool ok = false;
      if (widget.role == 'counter' && res['master_pin'] == pin) ok = true;
      if (widget.role == 'waiter' && (res['waiter_pin'] ?? '1111') == pin) ok = true;
      if (widget.role == 'cook' && (res['cook_pin'] ?? '2222') == pin) ok = true;

      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_store_code', code);
        if (!mounted) return;
        if (widget.role == 'counter') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FullCounterApp(
            storeCode: code,
            tables: res['total_tables'] ?? 10,
            hotelName: res['name'] ?? 'होटल',
            initialWaiterPin: res['waiter_pin'] ?? '1111',
            initialCookPin: res['cook_pin'] ?? '2222',
          )));
        } else if (widget.role == 'waiter') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FullWaiterApp(storeCode: code, tables: res['total_tables'] ?? 10)));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CookApp(storeCode: code)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पिन सही नहीं है!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('कनेक्शन एरर: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.role == 'counter' ? 'काउंटर लॉगिन' : (widget.role == 'waiter' ? 'वेटर लॉगिन' : 'कुक लॉगिन')), backgroundColor: const Color(0xFF0F172A)),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'स्टोर कोड (उदा. 101)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: 'पिन कोड', border: OutlineInputBorder()), keyboardType: TextInputType.number, obscureText: true),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                      onPressed: _verify,
                      child: const Text('लॉगिन करें', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  )
          ],
        ),
      ),
    );
  }
}

// ---------------- 1. काउंटर मास्टर ऐप (ओनर) ----------------
class FullCounterApp extends StatefulWidget {
  final String storeCode;
  final String hotelName;
  final int tables;
  final String initialWaiterPin;
  final String initialCookPin;
  const FullCounterApp({
    super.key,
    required this.storeCode,
    required this.hotelName,
    required this.tables,
    required this.initialWaiterPin,
    required this.initialCookPin,
  });
  @override
  State<FullCounterApp> createState() => _FullCounterAppState();
}

class _FullCounterAppState extends State<FullCounterApp> {
  int _currentTab = 0;
  String localIp = 'ढूंढ रहा है...';
  ServerSocket? server;
  bool isPrinterConnected = false;

  late String waiterPin;
  late String cookPin;

  List<Map<String, dynamic>> hotelMenu = [
    {'id': 1, 'name': 'दाल तड़का', 'price': 120.0, 'cat': 'सब्जी/दाल', 'available': true},
    {'id': 2, 'name': 'पनीर बटर मसाला', 'price': 180.0, 'cat': 'सब्जी/दाल', 'available': true},
    {'id': 3, 'name': 'तंदूरी रोटी', 'price': 12.0, 'cat': 'रोटी', 'available': true},
    {'id': 4, 'name': 'बटर रोटी', 'price': 15.0, 'cat': 'रोटी', 'available': true},
    {'id': 5, 'name': 'जीरा राइस', 'price': 100.0, 'cat': 'चावल', 'available': true},
    {'id': 6, 'name': 'मसाला छाछ', 'price': 25.0, 'cat': 'पेय', 'available': true},
  ];

  Map<int, List<Map<String, dynamic>>> activeOrders = {};
  double totalCashSales = 0;
  double totalOnlineSales = 0;
  List<Map<String, dynamic>> dailyExpenses = [];

  @override
  void initState() {
    super.initState();
    waiterPin = widget.initialWaiterPin;
    cookPin = widget.initialCookPin;
    _loadLocalMenu();
    _startServer();
    _checkPrinterStatus();
  }

  void _checkPrinterStatus() async {
    final bool result = await PrintBluetoothThermal.connectionStatus;
    setState(() => isPrinterConnected = result);
  }

  void _loadLocalMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMenu = prefs.getString('custom_menu_${widget.storeCode}');
    if (savedMenu != null) {
      setState(() {
        hotelMenu = List<Map<String, dynamic>>.from(jsonDecode(savedMenu));
      });
    }
  }

  void _saveLocalMenu() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_menu_${widget.storeCode}', jsonEncode(hotelMenu));
  }

  void _startServer() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() => localIp = addr.address);
            break;
          }
        }
      }
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
      server!.listen((Socket client) {
        client.listen((data) {
          try {
            final msg = jsonDecode(utf8.decode(data));
            if (msg['type'] == 'GET_MENU') {
              client.write(jsonEncode({'type': 'MENU_DATA', 'menu': hotelMenu}) + "\n");
            } else if (msg['type'] == 'GET_RUNNING_TABLES') {
              client.write(jsonEncode({'type': 'RUNNING_TABLES', 'data': activeOrders}) + "\n");
            } else if (msg['type'] == 'NEW_KOT') {
              int tbl = msg['table'];
              List items = msg['items'];
              setState(() {
                if (!activeOrders.containsKey(tbl)) activeOrders[tbl] = [];
                for (var it in items) {
                  activeOrders[tbl]!.add(Map<String, dynamic>.from(it));
                }
              });
              client.write(jsonEncode({'status': 'SUCCESS'}) + "\n");
            }
          } catch (_) {}
        });
      });
    } catch (_) {}
  }

  void _openPrinterDialog() async {
    List<BluetoothInfo> availablePrinters = await PrintBluetoothThermal.pairedBluetooths;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ब्लूटूथ प्रिंटर चुनें'),
        content: SizedBox(
          width: double.maxFinite,
          child: availablePrinters.isEmpty
              ? const Text('कोई पेयर्ड डिवाइस नहीं मिला। कृपया पहले फोन सेटिंग के ब्लूटूथ में प्रिंटर को पेयर करें।')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: availablePrinters.length,
                  itemBuilder: (ctx, i) {
                    final p = availablePrinters[i];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text(p.macAdress),
                      trailing: const Icon(Icons.print),
                      onTap: () async {
                        Navigator.pop(context);
                        bool ok = await PrintBluetoothThermal.connect(macPrinterAddress: p.macAdress);
                        setState(() => isPrinterConnected = ok);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok ? 'प्रिंटर कनेक्ट हो गया!' : 'कनेक्शन विफल!'),
                            backgroundColor: ok ? Colors.green : Colors.red,
                          ));
                        }
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _printReceipt(int id, double total, List<Map<String, dynamic>> items, String payMode) async {
    if (!await PrintBluetoothThermal.connectionStatus) return;
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      String orderTitle = id > 0 ? 'टेबल: T-$id' : 'पार्सल: P-${-id}';

      bytes += generator.text(widget.hotelName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('$orderTitle | $payMode', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('दिनांक: ${DateTime.now().toString().substring(0, 16)}', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.hr();

      for (var it in items) {
        bytes += generator.row([
          PosColumn(text: it['name'], width: 7),
          PosColumn(text: 'x${it['qty']}', width: 2),
          PosColumn(text: '${it['price'] * it['qty']}', width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.hr();
      bytes += generator.text('कुल बिल: Rs. $total', styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2));
      bytes += generator.hr();
      bytes += generator.text('धन्यवाद! फिर पधारें', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {}
  }

  void _settleBill(int id) {
    List<Map<String, dynamic>> items = activeOrders[id] ?? [];
    double total = items.fold(0, (sum, it) => sum + (it['price'] * it['qty']));
    String title = id > 0 ? 'टेबल T-$id का बिल' : 'पार्सल P-${-id} का बिल';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$title (कुल: ₹$total)'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('${it['name']} x ${it['qty']}'), Text('₹${it['price'] * it['qty']}')],
                ),
              )),
              const Divider(),
              const Text('भुगतान माध्यम चुनें:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      await _printReceipt(id, total, items, 'नकद (CASH)');
                      setState(() {
                        totalCashSales += total;
                        activeOrders.remove(id);
                      });
                      if (!mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text('💵 नकद (Cash)', style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    onPressed: () async {
                      await _printReceipt(id, total, items, 'ऑनलाइन (ONLINE)');
                      setState(() {
                        totalOnlineSales += total;
                        activeOrders.remove(id);
                      });
                      if (!mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text('📱 ऑनलाइन', style: TextStyle(color: Colors.white)),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _createTakeawayOrder() {
    int nextParcelId = -1;
    while (activeOrders.containsKey(nextParcelId)) {
      nextParcelId--;
    }

    final Map<String, int> parcelCart = {};
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('नया पार्सल (P-${-nextParcelId}) पैक ऑर्डर'),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              itemCount: hotelMenu.where((m) => m['available'] == true).length,
              itemBuilder: (c, i) {
                final itm = hotelMenu.where((m) => m['available'] == true).toList()[i];
                final qty = parcelCart[itm['name']] ?? 0;
                return ListTile(
                  dense: true,
                  title: Text(itm['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('₹${itm['price']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (qty > 0) IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setDState(() => parcelCart[itm['name']] = qty - 1)),
                      if (qty > 0) Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => setDState(() => parcelCart[itm['name']] = qty + 1)),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () {
                if (parcelCart.isEmpty) return;
                List<Map<String, dynamic>> items = [];
                parcelCart.forEach((k, v) {
                  if (v > 0) {
                    final it = hotelMenu.firstWhere((e) => e['name'] == k);
                    items.add({'name': k, 'qty': v, 'price': it['price']});
                  }
                });
                setState(() {
                  activeOrders[nextParcelId] = items;
                });
                Navigator.pop(context);
              },
              child: const Text('पार्सल बिल बनाएँ', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _itemDialog([Map<String, dynamic>? item]) {
    final nameCtrl = TextEditingController(text: item?['name'] ?? '');
    final priceCtrl = TextEditingController(text: item != null ? item['price'].toString() : '');
    String cat = item?['cat'] ?? 'सब्जी/दाल';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(item == null ? 'नया व्यंजन जोड़ें' : 'व्यंजन संपादित करें'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nam

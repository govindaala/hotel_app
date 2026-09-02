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
  } catch (e) {
    debugPrint("Supabase Init Error: $e");
  }
  runApp(const MaterialApp(
    home: AppGateway(),
    debugShowCheckedModeBanner: false,
  ));
}

// ==========================================
// 1. GATEWAY & AUTHENTICATION
// ==========================================

class AppGateway extends StatelessWidget {
  const AppGateway({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('होटल POS सिस्टम', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roleCard(context, '🖥️ काउंटर मास्टर (ओनर)', 'बिलिंग, मेन्यू, थर्मल प्रिंटर, पार्सल व गल्ला', const Color(0xFF0F172A), 'counter'),
            const SizedBox(height: 18),
            _roleCard(context, '📱 वेटर मोड (ऑर्डरिंग)', 'टेबल ऑर्डर, त्वरित KOT, सर्च व रनिंग टेबल', const Color(0xFFEA580C), 'waiter'),
            const SizedBox(height: 18),
            _roleCard(context, '👨‍🍳 कुक मोड (किचन KDS)', 'लाइव KOT स्क्रीन, तैयार मार्क व राशन मांग', const Color(0xFF0D9488), 'cook'),
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

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _codeCtrl.text = prefs.getString('saved_store_code') ?? '';
      });
    }
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
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FullCookApp(storeCode: code)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पिन सही नहीं है!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('कनेक्शन एरर (इंटरनेट चेक करें): $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.role == 'counter' ? 'काउंटर लॉगिन' : (widget.role == 'waiter' ? 'वेटर लॉगिन' : 'कुक लॉगिन'), style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF0F172A)),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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

// ==========================================
// 2. COUNTER / OWNER MODULE
// ==========================================

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
  String localIp = 'IP ढूँढ रहा है...';
  ServerSocket? server;
  final List<Socket> connectedClients = [];
  bool isPrinterConnected = false;

  late String waiterPin;
  late String cookPin;

  List<Map<String, dynamic>> hotelMenu = [
    {'id': 1, 'name': 'दाल तड़का', 'price': 120.0, 'cat': 'सब्जी/दाल', 'available': true},
    {'id': 2, 'name': 'पनीर मसाला', 'price': 180.0, 'cat': 'सब्जी/दाल', 'available': true},
    {'id': 3, 'name': 'तंदूरी रोटी', 'price': 12.0, 'cat': 'रोटी', 'available': true},
    {'id': 4, 'name': 'जीरा राइस', 'price': 100.0, 'cat': 'चावल', 'available': true},
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

  @override
  void dispose() {
    server?.close();
    for (var client in connectedClients) {
      client.destroy();
    }
    super.dispose();
  }

  void _checkPrinterStatus() async {
    try {
      final bool result = await PrintBluetoothThermal.connectionStatus;
      if (mounted) setState(() => isPrinterConnected = result);
    } catch (_) {}
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
      // Find non-loopback IPv4 (Hotspot or Wi-Fi)
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => localIp = addr.address);
            break;
          }
        }
      }
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
      server!.listen((Socket client) {
        connectedClients.add(client);
        client.listen((data) {
          try {
            final lines = utf8.decode(data).split("\n");
            for(var line in lines) {
              if (line.trim().isEmpty) continue;
              final msg = jsonDecode(line);
              
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
                _broadcastToKitchen(msg); // Send to Cook
              }
            }
          } catch (_) {}
        }, 
        onDone: () => connectedClients.remove(client),
        onError: (e) => connectedClients.remove(client));
      });
    } catch (_) {}
  }

  void _broadcastToKitchen(dynamic data) {
    // Avoid concurrent modification issues
    final clientsCopy = List<Socket>.from(connectedClients);
    for (var c in clientsCopy) {
      try {
        c.write(jsonEncode(data) + "\n");
      } catch (_) {
        connectedClients.remove(c);
      }
    }
  }

  void _openPrinterDialog() async {
    List<BluetoothInfo> availablePrinters = [];
    try {
      availablePrinters = await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {}
    
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ब्लूटूथ प्रिंटर चुनें'),
        content: SizedBox(
          width: double.maxFinite,
          child: availablePrinters.isEmpty
              ? const Text('कोई पेयर्ड डिवाइस नहीं मिला। कृपया फोन की सेटिंग में प्रिंटर को पेयर करें।')
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
                        bool ok = false;
                        try {
                          ok = await PrintBluetoothThermal.connect(macPrinterAddress: p.macAdress);
                        } catch (_) {}
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
    bool isConn = false;
    try { isConn = await PrintBluetoothThermal.connectionStatus; } catch(_) {}
    if (!isConn) return;

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      String orderTitle = id > 0 ? 'Table: T-$id' : 'Parcel: P-${-id}';

      bytes += generator.text(widget.hotelName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('$orderTitle | $payMode', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Date: ${DateTime.now().toString().substring(0, 16)}', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.hr();

      for (var it in items) {
        bytes += generator.row([
          PosColumn(text: it['name'], width: 7),
          PosColumn(text: 'x${it['qty']}', width: 2),
          PosColumn(text: '${it['price'] * it['qty']}', width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.hr();
      bytes += generator.text('Total: Rs. $total', styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2));
      bytes += generator.hr();
      bytes += generator.text('Thank You! Visit Again.', styles: const PosStyles(align: PosAlign.center));
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
                      await _printReceipt(id, total, items, 'CASH');
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
                      await _printReceipt(id, total, items, 'ONLINE');
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
          title: Text('नया पार्सल (P-${-nextParcelId})'),
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
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'व्यंजन का नाम', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'कीमत (₹)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: cat,
              items: ['सब्जी/दाल', 'रोटी', 'चावल', 'पेय', 'स्नैक्स', 'अन्य'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => cat = v!,
              decoration: const InputDecoration(labelText: 'कैटेगरी', border: OutlineInputBorder()),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () {
              if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) return;
              setState(() {
                if (item == null) {
                  hotelMenu.add({
                    'id': DateTime.now().millisecondsSinceEpoch,
                    'name': nameCtrl.text.trim(),
                    'price': double.parse(priceCtrl.text.trim()),
                    'cat': cat,
                    'available': true,
                  });
                } else {
                  item['name'] = nameCtrl.text.trim();
                  item['price'] = double.parse(priceCtrl.text.trim());
                  item['cat'] = cat;
                }
              });
              _saveLocalMenu();
              Navigator.pop(context);
            },
            child: const Text('सेव करें', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _updateStaffPinDialog() {
    final wPinCtrl = TextEditingController(text: waiterPin);
    final cPinCtrl = TextEditingController(text: cookPin);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('स्टाफ लॉगिन पिन बदलें'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: wPinCtrl, decoration: const InputDecoration(labelText: 'वेटर पिन (4 अंक)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
            TextField(controller: cPinCtrl, decoration: const InputDecoration(labelText: 'कुक पिन (4 अंक)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () async {
              try {
                await Supabase.instance.client.from('restaurants').update({
                  'waiter_pin': wPinCtrl.text.trim(),
                  'cook_pin': cPinCtrl.text.trim(),
                }).eq('store_code', widget.storeCode);

                setState(() {
                  waiterPin = wPinCtrl.text.trim();
                  cookPin = cPinCtrl.text.trim();
                });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पिन अपडेट हो गया!')));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
              }
            },
            child: const Text('अपडेट करें', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _addExpenseDialog() {
    final itemCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('दुकान का खर्च दर्ज करें'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: itemCtrl, decoration: const InputDecoration(labelText: 'खर्च का नाम (उदा. दूध/सब्जी)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: amtCtrl, decoration: const InputDecoration(labelText: 'रकम ₹', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () {
              if (itemCtrl.text.isEmpty || amtCtrl.text.isEmpty) return;
              setState(() {
                dailyExpenses.add({
                  'name': itemCtrl.text.trim(),
                  'amount': double.parse(amtCtrl.text.trim()),
                  'time': DateTime.now().toLocal().toString().substring(11, 16)
                });
              });
              Navigator.pop(context);
            },
            child: const Text('जोड़ें', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalExpenses = dailyExpenses.fold(0, (sum, it) => sum + it['amount']);
    double netSales = (totalCashSales + totalOnlineSales) - totalExpenses;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('${widget.storeCode} - मास्टर', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.print, color: isPrinterConnected ? Colors.greenAccent : Colors.white),
            onPressed: _openPrinterDialog,
            tooltip: 'प्रिंटर कनेक्ट करें',
          ),
          IconButton(
            icon: const Icon(Icons.lock_person, color: Colors.amberAccent),
            onPressed: _updateStaffPinDialog,
            tooltip: 'स्टाफ पिन बदलें',
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Container(
            color: const Color(0xFF1E293B),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(child: Text('वाई-फाई IP: $localIp (हॉटस्पॉट चालू रखें)', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold))),
          ),
        ),
      ),
      body: [
        // Tab 0: Tables & Parcel
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('डाइन-इन व पार्सल:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
                    onPressed: _createTakeawayOrder,
                    icon: const Icon(Icons.takeout_dining, color: Colors.white, size: 18),
                    label: const Text('नया पार्सल', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            ),
            if (activeOrders.keys.any((k) => k < 0))
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: activeOrders.keys.where((k) => k < 0).map((pId) {
                    double pBill = activeOrders[pId]!.fold(0, (s, it) => s + (it['price'] * it['qty']));
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        backgroundColor: Colors.amber.shade200,
                        avatar: const Icon(Icons.shopping_bag, size: 16, color: Colors.brown),
                        label: Text('P-${-pId} (₹$pBill)'),
                        onPressed: () => _settleBill(pId),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: widget.tables,
                itemBuilder: (ctx, i) {
                  int tbl = i + 1;
                  bool hasOrder = activeOrders.containsKey(tbl) && activeOrders[tbl]!.isNotEmpty;
                  double bill = (activeOrders[tbl] ?? []).fold(0, (sum, it) => sum + (it['price'] * it['qty']));
                  return InkWell(
                    onTap: hasOrder ? () => _settleBill(tbl) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: hasOrder ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('T-$tbl', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(hasOrder ? '₹$bill' : 'खाली', style: const TextStyle(color: Colors.white, fontSize: 14)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        // Tab 1: Menu
        Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF0F172A),
            onPressed: () => _itemDialog(),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('नया व्यंजन', style: TextStyle(color: Colors.white)),
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: hotelMenu.length,
            itemBuilder: (ctx, i) {
              final itm = hotelMenu[i];
              bool isAvail = itm['available'] ?? true;
              return Card(
                elevation: 1,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  title: Text(itm['name'], style: TextStyle(fontWeight: FontWeight.bold, decoration: isAvail ? null : TextDecoration.lineThrough)),
                  subtitle: Text('${itm['cat']} • ₹${itm['price']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: isAvail,
                        activeColor: Colors.green,
                        onChanged: (val) {
                          setState(() => itm['available'] = val);
                          _saveLocalMenu();
                        },
                      ),
                      IconButton(icon: const Icon(Icons.edit, color: Colors.blueGrey), onPressed: () => _itemDialog(itm)),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () {
                          setState(() => hotelMenu.removeAt(i));
                          _saveLocalMenu();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Tab 2: Expenses
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('💵 नकद बिक्री:'), Text('₹$totalCashSales', style: const TextStyle(fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('📱 ऑनलाइन बिक्री:'), Text('₹$totalOnlineSales', style: const TextStyle(fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('🔻 दैनिक खर्च:'), Text('- ₹$totalExpenses', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                      const Divider(),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('शुद्ध गल्ला बैलेंस:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('₹$netSales', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green))
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('दुकान का खर्च', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                    onPressed: _addExpenseDialog,
                    child: const Text('+ खर्च', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: dailyExpenses.isEmpty
                    ? const Center(child: Text('आज कोई खर्च दर्ज नहीं है', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: dailyExpenses.length,
                        itemBuilder: (ctx, i) {
                          final exp = dailyExpenses[i];
                          return ListTile(
                            dense: true,
                            title: Text(exp['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('समय: ${exp['time']}'),
                            trailing: Text('- ₹${exp['amount']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
              )
            ],
          ),
        ),
      ][_currentTab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        selectedItemColor: const Color(0xFF0F172A),
        onTap: (idx) => setState(() => _currentTab = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.table_bar), label: 'टेबल्स'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'मेन्यू'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'गल्ला'),
        ],
      ),
    );
  }
}

// ==========================================
// 3. WAITER MODULE
// ==========================================

class FullWaiterApp extends StatefulWidget {
  final String storeCode;
  final int tables;
  const FullWaiterApp({super.key, required this.storeCode, required this.tables});

  @override
  State<FullWaiterApp> createState() => _FullWaiterAppState();
}

class _FullWaiterAppState extends State<FullWaiterApp> {
  final _counterIpCtrl = TextEditingController(text: '192.168.43.1');
  bool _isConnected = false;

  List<Map<String, dynamic>> menu = [];
  Map<int, List<Map<String, dynamic>>> liveTables = {};

  String selectedCategory = 'सभी';
  String searchQuery = '';
  final Set<String> categories = {'सभी'};

  @override
  void initState() {
    super.initState();
    _loadSavedCounterIp();
  }

  @override
  void dispose() {
    _counterIpCtrl.dispose();
    super.dispose();
  }

  void _loadSavedCounterIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('saved_counter_ip');
    if (savedIp != null) {
      if(mounted) setState(() => _counterIpCtrl.text = savedIp);
    }
    _syncWithCounter();
  }

  void _syncWithCounter() async {
    final ip = _counterIpCtrl.text.trim();
    if (ip.isEmpty) return;

    try {
      final socket = await Socket.connect(ip, 4040, timeout: const Duration(seconds: 3));
      
      socket.write(jsonEncode({'type': 'GET_MENU'}) + "\n");
      socket.write(jsonEncode({'type': 'GET_RUNNING_TABLES'}) + "\n");

      socket.listen((data) {
        final lines = utf8.decode(data).split('\n');
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final res = jsonDecode(line);
            if (res['type'] == 'MENU_DATA') {
              if (mounted) {
                setState(() {
                  menu = List<Map<String, dynamic>>.from(res['menu']);
                  categories.clear();
                  categories.add('सभी');
                  for (var it in menu) {
                    if (it['cat'] != null) categories.add(it['cat']);
                  }
                  _isConnected = true;
                });
              }
            } else if (res['type'] == 'RUNNING_TABLES') {
              if (mounted) {
                setState(() {
                  liveTables = Map<int, List<Map<String, dynamic>>>.from(
                    (res['data'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), List<Map<String, dynamic>>.from(v))),
                  );
                });
              }
            }
          } catch (_) {}
        }
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_counter_ip', ip);
    } catch (_) {
      if(mounted) setState(() => _isConnected = false);
    }
  }

  void _openOrderScreen(int tableNum) {
    final Map<int, int> cart = {};
    final Map<int, String> notes = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBState) {
          final filtered = menu.where((item) {
            final matchCat = (selectedCategory == 'सभी' || item['cat'] == selectedCategory);
            final matchSearch = item['name'].toString().toLowerCase().contains(searchQuery.toLowerCase());
            return matchCat && matchSearch;
          }).toList();

          double currentTotal = 0;
          cart.forEach((id, qty) {
            final it = menu.firstWhere((e) => e['id'] == id);
            currentTotal += (it['price'] * qty);
          });

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('टेबल T-$tableNum ऑर्डर', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'व्यंजन खोजें...',
                    prefixIcon: const Icon(Icons.search),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (val) => setBState(() => searchQuery = val),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((cat) {
                      final isSel = selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(cat),
                          selected: isSel,
                          selectedColor: const Color(0xFFEA580C),
                          labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87),
                          onSelected: (_) => setBState(() => selectedCategory = cat),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (c, idx) {
                      final item = filtered[idx];
                      final isAvailable = item['available'] ?? true;
                      final qty = cart[item['id']] ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isAvailable ? Colors.white : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold, color: isAvailable ? Colors.black : Colors.grey)),
                          subtitle: Text('₹${item['price']} • ${item['cat']}'),
                          trailing: !isAvailable
                              ? const Text('आउट', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (qty > 0)
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                        onPressed: () => setBState(() => cart[item['id']] = qty - 1),
                                      ),
                                    if (qty > 0) Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                      onPressed: () => setBState(() => cart[item['id']] = qty + 1),
                                    ),
                                    if (qty > 0)
                                      IconButton(
                                        icon: Icon(Icons.note_alt_outlined, color: notes.containsKey(item['id']) ? Colors.orange : Colors.grey),
                                        onPressed: () {
                                          final noteCtrl = TextEditingController(text: notes[item['id']] ?? '');
                                          showDialog(
                                            context: context,
                                            builder: (_) => AlertDialog(
                                              title: Text('${item['name']} निर्देश'),
                                              content: TextField(controller: noteCtrl, decoration: const InputDecoration(hintText: 'उदा. कम तीखा')),
                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    if (noteCtrl.text.isNotEmpty) {
                                                      setBState(() => notes[item['id']] = noteCtrl.text.trim());
                                                    }
                                                    Navigator.pop(context);
                                                  },
                                                  child: const Text('सेव'),
                                                )
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('कुल: ₹$currentTotal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                        onPressed: currentTotal == 0
                            ? null
                            : () async {
                                List<Map<String, dynamic>> orderItems = [];
                                cart.forEach((id, qty) {
                                  if (qty > 0) {
                                    final it = menu.firstWhere((e) => e['id'] == id);
                                    orderItems.add({
                                      'name': it['name'],
                                      'price': it['price'],
                                      'qty': qty,
                                      'note': notes[id] ?? '',
                                    });
                                  }
                                });

                                try {
                                  final socket = await Socket.connect(_counterIpCtrl.text.trim(), 4040, timeout: const Duration(seconds: 3));
                                  socket.write(jsonEncode({
                                    'type': 'NEW_KOT',
                                    'table': tableNum,
                                    'items': orderItems,
                                  }) + "\n");
                                  await socket.flush();
                                  await socket.close();

                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('T-$tableNum का KOT भेजा गया!'), backgroundColor: Colors.green));
                                  }
                                  _syncWithCounter();
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
                                }
                              },
                        icon: const Icon(Icons.send, color: Colors.white),
                        label: const Text('KOT भेजें', style: TextStyle(color: Colors.white, fontSize: 16)),
                      )
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _viewRunningTable(int tableNum) {
    final items = liveTables[tableNum] ?? [];
    double total = items.fold(0, (sum, it) => sum + (it['price'] * it['qty']));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('टेबल T-$tableNum (चालू)'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...items.map((it) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${it['name']} x ${it['qty']}'),
                    subtitle: it['note'] != null && it['note'].toString().isNotEmpty ? Text('नोट: ${it['note']}', style: const TextStyle(color: Colors.orange)) : null,
                    trailing: Text('₹${it['price'] * it['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('कुल रकम:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('₹$total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                ],
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('बंद करें')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
            onPressed: () {
              Navigator.pop(context);
              _openOrderScreen(tableNum);
            },
            child: const Text('+ और जोड़ें', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('${widget.storeCode} - वेटर', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFEA580C),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _syncWithCounter,
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Container(
            color: const Color(0xFFC2410C),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _counterIpCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'काउंटर IP',
                      hintStyle: TextStyle(color: Colors.white60),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _syncWithCounter,
                  child: Text(_isConnected ? '● कनेक्टेड' : 'कनेक्ट करें', style: TextStyle(color: _isConnected ? Colors.greenAccent : Colors.yellowAccent, fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('टेबल चुनें:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: widget.tables,
                itemBuilder: (ctx, i) {
                  int tbl = i + 1;
                  bool isOccupied = liveTables.containsKey(tbl) && liveTables[tbl]!.isNotEmpty;

                  return InkWell(
                    onTap: () {
                      if (isOccupied) {
                        _viewRunningTable(tbl);
                      } else {
                        _openOrderScreen(tbl);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isOccupied ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('T-$tbl', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(isOccupied ? 'रनिंग ऑर्डर' : 'खाली', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 4. COOK MODULE (KDS)
// ==========================================

class FullCookApp extends StatefulWidget {
  final String storeCode;
  const FullCookApp({super.key, required this.storeCode});

  @override
  State<FullCookApp> createState() => _FullCookAppState();
}

class _FullCookAppState extends State<FullCookApp> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ipCtrl = TextEditingController(text: '192.168.43.1');
  Socket? kitchenSocket;
  bool isConnected = false;
  List<Map<String, dynamic>> kitchenOrders = [];

  final List<String> presetRations = [
    'गेहूं का आटा (50 KG)',
    'बासमती चावल (25 KG)',
    'सोयाबीन तेल (15 Ltr)',
    'ताजा पनीर (5 KG)',
    'शक्कर (50 KG)',
    'चाय पत्ती (5 KG)',
    'कमर्शियल गैस सिलेंडर (19 KG)'
  ];
  final Map<String, bool> selectedRations = {};
  final _customItemCtrl = TextEditingController();
  final _customQtyCtrl = TextEditingController();
  bool _rationLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    for (var r in presetRations) {
      selectedRations[r] = false;
    }
    _loadSavedIpAndConnect();
  }

  @override
  void dispose() {
    kitchenSocket?.destroy();
    _tabController.dispose();
    _ipCtrl.dispose();
    _customItemCtrl.dispose();
    _customQtyCtrl.dispose();
    super.dispose();
  }

  void _loadSavedIpAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_counter_ip');
    if (saved != null) {
      if(mounted) setState(() => _ipCtrl.text = saved);
    }
    _connectToCounter();
  }

  void _connectToCounter() async {
    try {
      if (kitchenSocket != null) {
        kitchenSocket!.destroy();
      }
      
      kitchenSocket = await Socket.connect(_ipCtrl.text.trim(), 4040, timeout: const Duration(seconds: 3));
      if(mounted) setState(() => isConnected = true);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_counter_ip', _ipCtrl.text.trim());

      kitchenSocket!.listen((data) {
        try {
          final lines = utf8.decode(data).split("\n");
          for (var line in lines) {
            if (line.trim().isEmpty) continue;
            final msg = jsonDecode(line);
            if (msg['type'] == 'NEW_KOT') {
              if (mounted) {
                setState(() {
                  kitchenOrders.insert(0, Map<String, dynamic>.from(msg));
                });
              }
            }
          }
        } catch (_) {}
      }, onDone: () {
        if(mounted) setState(() => isConnected = false);
      }, onError: (e) {
        if(mounted) setState(() => isConnected = false);
      });
    } catch (_) {
      if(mounted) setState(() => isConnected = false);
    }
  }

  void _sendBulkRationDemand() async {
    List<Map<String, dynamic>> toInsert = [];

    selectedRations.forEach((item, isChecked) {
      if (isChecked) {
        toInsert.add({
          'store_code': widget.storeCode,
          'item_name': item,
          'quantity': '1 Unit',
        });
      }
    });

    if (_customItemCtrl.text.isNotEmpty && _customQtyCtrl.text.isNotEmpty) {
      toInsert.add({
        'store_code': widget.storeCode,
        'item_name': _customItemCtrl.text.trim(),
        'quantity': _customQtyCtrl.text.trim(),
      });
    }

    if (toInsert.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया कोई राशन सामग्री चुनें!')));
      return;
    }

    setState(() => _rationLoading = true);
    try {
      await Supabase.instance.client.from('ration_demands').insert(toInsert);
      setState(() {
        for (var k in selectedRations.keys) {
          selectedRations[k] = false;
        }
        _customItemCtrl.clear();
        _customQtyCtrl.clear();
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ राशन मांग सप्लाई पोर्टल पर दर्ज हो गई!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
    } finally {
      if (mounted) setState(() => _rationLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('${widget.storeCode} - कुक', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D9488),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.soup_kitchen), text: 'लाइव KOT'),
            Tab(icon: Icon(Icons.shopping_basket), text: 'थोक राशन'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              Container(
                color: const Color(0xFF115E59),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'काउंटर IP',
                          hintStyle: TextStyle(color: Colors.white60),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _connectToCounter,
                      child: Text(isConnected ? '● कनेक्टेड' : 'कनेक्ट करें', style: TextStyle(color: isConnected ? Colors.greenAccent : Colors.yellowAccent, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
              Expanded(
                child: kitchenOrders.isEmpty
                    ? const Center(child: Text('अभी कोई नया KOT नहीं है 👨‍🍳', style: TextStyle(color: Colors.grey, fontSize: 16)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: kitchenOrders.length,
                        itemBuilder: (ctx, i) {
                          final order = kitchenOrders[i];
                          final items = order['items'] as List;
                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Table T-${order['table']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                                        onPressed: () => setState(() => kitchenOrders.removeAt(i)),
                                        child: const Text('तैयार (Done) ✓', style: TextStyle(color: Colors.white)),
                                      )
                                    ],
                                  ),
                                  const Divider(),
                                  ...items.map((it) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${it['name']}  x  ${it['qty']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            if (it['note'] != null && it['note'].toString().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8.0),
                                                child: Text('(${it['note']})', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 15)),
                                              )
                                          ],
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              )
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('राशन सामग्री चुनें:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      ...presetRations.map((item) => CheckboxListTile(
                            dense: true,
                            title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600)),
                            value: selectedRations[item],
                            activeColor: const Color(0xFF0D9488),
                            onChanged: (val) => setState(() => selectedRations[item] = val!),
                          )),
                      const Divider(),
                      const Text('अन्य कोई सामान:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _customItemCtrl, decoration: const InputDecoration(labelText: 'सामान का नाम', isDense: true, border: OutlineInputBorder()))),
                          const SizedBox(width: 8),
                          SizedBox(width: 100, child: TextField(controller: _customQtyCtrl, decoration: const InputDecoration(labelText: 'मात्रा', isDense: true, border: OutlineInputBorder()))),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                _rationLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                          onPressed: _sendBulkRationDemand,
                          child: const Text('पोर्टल पर मांग भेजें 🚀', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      )
              ],
            ),
          )
        ],
      ),
    );
  }
}

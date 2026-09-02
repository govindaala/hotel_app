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
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => WaiterApp(storeCode: code, tables: res['total_tables'] ?? 10)));
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
      appBar: AppBar(title: Text(widget.role == 'counter' ? 'काउंटर लॉगिन' : 'स्टाफ लॉगिन'), backgroundColor: const Color(0xFF0F172A)),
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

  // होटल का मेन्यू
  List<Map<String, dynamic>> hotelMenu = [
    {'id': 1, 'name': 'दाल तड़का', 'price': 120.0, 'cat': 'सब्जी/दाल', 'available': true},
    {'id': 2, 'name': 'पनीर बटर मसाला', 'price': 180.0, 'cat': 'सब्जी/दाल', 'available': true},
    {'id': 3, 'name': 'तंदूरी रोटी', 'price': 12.0, 'cat': 'रोटी', 'available': true},
    {'id': 4, 'name': 'बटर रोटी', 'price': 15.0, 'cat': 'रोटी', 'available': true},
    {'id': 5, 'name': 'जीरा राइस', 'price': 100.0, 'cat': 'चावल', 'available': true},
    {'id': 6, 'name': 'मसाला छाछ', 'price': 25.0, 'cat': 'पेय', 'available': true},
  ];

  // टेबल और पार्सल ऑर्डर्स (पॉज़िटिव नंबर = टेबल T-1, T-2... और नेगेटिव नंबर = पार्सल P-1, P-2...)
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
            } else if (msg['type'] == 'NEW_KOT') {
              int tbl = msg['table'];
              List items = msg['items'];
              setState(() {
                if (!activeOrders.containsKey(tbl)) activeOrders[tbl] = [];
                for (var it in items) {
                  activeOrders[tbl]!.add(Map<String, dynamic>.from(it));
                }
              });
            }
          } catch (_) {}
        });
      });
    } catch (_) {}
  }

  // ब्लूटूथ थर्मल प्रिंटर डायलॉग
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

  // थर्मल रसीद प्रिंट
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

  // टेबल या पार्सल का बिल सेटल करना
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

  // पार्सल (Takeaway) का नया ऑर्डर काउंटर से ही तुरंत जोड़ना
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

  // नया मेन्यू आइटम जोड़ना / एडिट करना
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

  // स्टाफ़ पिन बदलने का फ़ीचर
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

  // दैनिक खर्च जोड़ने का डायलॉग
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
            TextField(controller: itemCtrl, decoration: const InputDecoration(labelText: 'खर्च का नाम (उदा. दूध/सब्जी/बर्फ)', border: OutlineInputBorder())),
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
        title: Text('${widget.storeCode} - काउंटर'),
        backgroundColor: const Color(0xFF0F172A),
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
        // 1. टेबल्स व पार्सल स्क्रीन
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('डाइन-इन टेबल्स व पार्सल:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
                    onPressed: _createTakeawayOrder,
                    icon: const Icon(Icons.takeout_dining, color: Colors.white, size: 18),
                    label: const Text('+ नया पार्सल', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            ),
            // अगर कोई पार्सल एक्टिव है तो उसकी पट्टी
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

        // 2. मेन्यू प्रबंधन (नया व्यंजन व स्टॉक टॉगल)
        Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF0F172A),
            onPressed: () => _itemDialog(),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('नया व्यंजन जोड़ें', style: TextStyle(color: Colors.white)),
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

        // 3. गल्ला व दैनिक खर्च
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
                  const Text('दुकान का दैनिक खर्च', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                    onPressed: _addExpenseDialog,
                    child: const Text('+ खर्च जोड़ें', style: TextStyle(color: Colors.white)),
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
          BottomNavigationBarItem(icon: Icon(Icons.table_bar), label: 'टेबल्स व पार्सल'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'मेन्यू कार्ड'),
          BottomNavigationBarItem(icon: Icon(Icons.calculate), label: 'गल्ला व हिसाब'),
        ],
      ),
    );
  }
}

// ---------------- 2. वेटर ऐप (कदम 2 में अपग्रेड होगा) ----------------
class WaiterApp extends StatelessWidget {
  final String storeCode;
  final int tables;
  const WaiterApp({super.key, required this.storeCode, required this.tables});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('वेटर - $storeCode'), backgroundColor: const Color(0xFFEA580C)),
      body: const Center(child: Text('वेटर मॉड्यूल (कदम 2 में पूरी तरह अपग्रेड होगा)')),
    );
  }
}

// ---------------- 3. कुक ऐप (कदम 3 में अपग्रेड होगा) ----------------
class CookApp extends StatelessWidget {
  final String storeCode;
  const CookApp({super.key, required this.storeCode});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('कुक - $storeCode'), backgroundColor: const Color(0xFF0D9488)),
      body: const Center(child: Text('कुक मॉड्यूल (कदम 3 में पूरी तरह अपग्रेड होगा)')),
    );
  }
}

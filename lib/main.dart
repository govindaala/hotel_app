import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String supabaseUrl = "https://hbewnquphiwvxaxittrl.supabase.co";
const String supabaseKey = "sb_publishable_HA1-PBV55kEZet2GG_IBdg_HjUzfOxf";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const MaterialApp(
    home: AppGateway(),
    debugShowCheckedModeBanner: false,
  ));
}

class AppGateway extends StatefulWidget {
  const AppGateway({super.key});
  @override
  State<AppGateway> createState() => _AppGatewayState();
}

class _AppGatewayState extends State<AppGateway> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('होटल मैनेजमेंट सिस्टम'),
        backgroundColor: Colors.indigo,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roleCard(
              title: '🖥️ काउंटर मोड (मास्टर)',
              desc: 'बिलिंग, टेबल मैनेजमेंट, KOT सर्वर',
              color: Colors.indigo,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffAuthScreen(role: 'counter'))),
            ),
            const SizedBox(height: 20),
            _roleCard(
              title: '📱 वेटर मोड (ऑर्डरिंग)',
              desc: 'टेबल ऑर्डर, तुरंत किचन KOT',
              color: Colors.deepOrange,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffAuthScreen(role: 'waiter'))),
            ),
            const SizedBox(height: 20),
            _roleCard(
              title: '👨‍🍳 कुक मोड (किचन डिस्प्ले)',
              desc: 'लाइव KOT, ऑर्डर तैयार करना, राशन मांग',
              color: Colors.teal,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffAuthScreen(role: 'cook'))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCard({required String title, required String desc, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ---------------- PIN ऑथेंटिकेशन ----------------
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
    _loadSavedCredentials();
  }

  void _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('saved_store_code') ?? '';
    if (savedCode.isNotEmpty) {
      _codeCtrl.text = savedCode;
    }
  }

  void _verifyLogin() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final pin = _pinCtrl.text.trim();

    if (code.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया कोड और पिन दोनों दर्ज करें!')));
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select()
          .eq('store_code', code)
          .maybeSingle();

      if (res == null || res['is_active'] == false) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('स्टोर कोड मौजूद नहीं है या ब्लॉक है!')));
        setState(() => _loading = false);
        return;
      }

      bool authSuccess = false;
      if (widget.role == 'counter' && res['master_pin'] == pin) authSuccess = true;
      if (widget.role == 'waiter' && (res['waiter_pin'] ?? '1111') == pin) authSuccess = true;
      if (widget.role == 'cook' && (res['cook_pin'] ?? '2222') == pin) authSuccess = true;

      if (authSuccess) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_store_code', code);

        if (!mounted) return;
        if (widget.role == 'counter') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CounterDashboard(storeCode: code, totalTables: res['total_tables'] ?? 10)));
        } else if (widget.role == 'waiter') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => WaiterDashboard(storeCode: code, totalTables: res['total_tables'] ?? 10)));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CookDashboard(storeCode: code)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पिन सही नहीं है! काउंटर: 6-अंक पिन, वेटर: 1111, कुक: 2222')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('कनेक्शन एरर: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.role == 'counter' ? 'काउंटर लॉगिन' : (widget.role == 'waiter' ? 'वेटर लॉगिन' : 'कुक लॉगिन');
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.indigo),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'स्टोर कोड (उदा. 101 / TEST101)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: 'पिन कोड', border: OutlineInputBorder()), keyboardType: TextInputType.number, obscureText: true),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                      onPressed: _verifyLogin,
                      child: const Text('प्रवेश करें', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  )
          ],
        ),
      ),
    );
  }
}

// ---------------- 1. काउंटर स्क्रीन ----------------
class CounterDashboard extends StatefulWidget {
  final String storeCode;
  final int totalTables;
  const CounterDashboard({super.key, required this.storeCode, required this.totalTables});
  @override
  State<CounterDashboard> createState() => _CounterDashboardState();
}

class _CounterDashboardState extends State<CounterDashboard> {
  String localIp = 'ढूंढ रहा है...';
  ServerSocket? server;
  final List<Socket> connectedClients = [];
  Map<int, List<Map<String, dynamic>>> activeTableOrders = {};
  Map<int, double> tableTotals = {};

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  void _startServer() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          setState(() => localIp = addr.address);
          break;
        }
      }
    }

    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
      server!.listen((Socket client) {
        connectedClients.add(client);
        client.listen((data) {
          try {
            final msg = jsonDecode(utf8.decode(data));
            if (msg['type'] == 'NEW_ORDER') {
              int tbl = msg['table'];
              List items = msg['items'];
              double amt = double.parse(msg['total'].toString());

              setState(() {
                if (!activeTableOrders.containsKey(tbl)) {
                  activeTableOrders[tbl] = [];
                }
                for (var itm in items) {
                  activeTableOrders[tbl]!.add(Map<String, dynamic>.from(itm));
                }
                tableTotals[tbl] = (tableTotals[tbl] ?? 0) + amt;
              });

              // कुक की स्क्रीन को तुरंत ब्रॉडकास्ट करें
              _broadcastToCook(msg);
            }
          } catch (_) {}
        }, onDone: () => connectedClients.remove(client));
      });
    } catch (_) {}
  }

  void _broadcastToCook(dynamic data) {
    for (var c in connectedClients) {
      try {
        c.write(jsonEncode(data) + "\n");
      } catch (_) {}
    }
  }

  void _settleBill(int tbl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('टेबल T-$tbl बिल सेटलमेंट'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('कुल बिल: ₹${tableTotals[tbl] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            const Divider(),
            ...?(activeTableOrders[tbl]?.map((e) => Text('• ${e['name']} x ${e['qty']} = ₹${e['price'] * e['qty']}'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              setState(() {
                activeTableOrders.remove(tbl);
                tableTotals.remove(tbl);
              });
              Navigator.pop(context);
            },
            child: const Text('नकद भुगतान प्राप्त (खाली करें)', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.storeCode} - काउंटर'),
        backgroundColor: Colors.indigo,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Container(
            color: Colors.indigo.shade800,
            padding: const EdgeInsets.only(bottom: 4),
            child: Center(
              child: Text('वाई-फाई IP: $localIp (वेटर व कुक ऐप में यही डालें)', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: widget.totalTables,
        itemBuilder: (ctx, i) {
          int tbl = i + 1;
          bool isOccupied = tableTotals.containsKey(tbl);
          return InkWell(
            onTap: isOccupied ? () => _settleBill(tbl) : null,
            child: Container(
              decoration: BoxDecoration(
                color: isOccupied ? Colors.red.shade400 : Colors.green.shade500,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('T-$tbl', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(isOccupied ? '₹${tableTotals[tbl]}' : 'खाली', style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- 2. वेटर स्क्रीन ----------------
class WaiterDashboard extends StatefulWidget {
  final String storeCode;
  final int totalTables;
  const WaiterDashboard({super.key, required this.storeCode, required this.totalTables});
  @override
  State<WaiterDashboard> createState() => _WaiterDashboardState();
}

class _WaiterDashboardState extends State<WaiterDashboard> {
  int selectedTable = 1;
  final _ipCtrl = TextEditingController(text: '192.168.1.');
  final List<Map<String, dynamic>> menu = [
    {'name': 'दाल तड़का', 'price': 120},
    {'name': 'पनीर बटर मसाला', 'price': 180},
    {'name': 'तंदूरी रोटी', 'price': 12},
    {'name': 'बटर रोटी', 'price': 15},
    {'name': 'जीरा राइस', 'price': 100},
    {'name': 'चाय / कॉफ़ी', 'price': 20},
  ];
  final Map<String, int> cart = {};

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  void _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('counter_ip');
    if (saved != null && saved.isNotEmpty) {
      _ipCtrl.text = saved;
    }
  }

  void _sendOrder() async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया कोई आइटम चुनें!')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('counter_ip', _ipCtrl.text.trim());

    List<Map<String, dynamic>> itemsList = [];
    double total = 0;
    cart.forEach((name, qty) {
      if (qty > 0) {
        final item = menu.firstWhere((e) => e['name'] == name);
        total += item['price'] * qty;
        itemsList.add({'name': name, 'qty': qty, 'price': item['price']});
      }
    });

    try {
      final socket = await Socket.connect(_ipCtrl.text.trim(), 4040, timeout: const Duration(seconds: 3));
      final payload = jsonEncode({
        'type': 'NEW_ORDER',
        'table': selectedTable,
        'total': total,
        'items': itemsList,
        'time': DateTime.now().toIso8601String(),
      });
      socket.write(payload);
      await socket.flush();
      await socket.close();

      setState(() => cart.clear());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ ऑर्डर काउंटर व किचन को भेजा गया!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('कनेक्ट नहीं हो सका! काउंटर IP सही डालें: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('वेटर - ${widget.storeCode}'), backgroundColor: Colors.deepOrange),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                const Text('काउंटर IP: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Expanded(child: TextField(controller: _ipCtrl, decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'उदा. 192.168.1.5'))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('टेबल चुनें:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                DropdownButton<int>(
                  value: selectedTable,
                  items: List.generate(widget.totalTables, (i) => DropdownMenuItem(value: i + 1, child: Text('Table ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)))),
                  onChanged: (v) => setState(() => selectedTable = v!),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: menu.length,
              itemBuilder: (ctx, i) {
                final item = menu[i];
                final qty = cart[item['name']] ?? 0;
                return ListTile(
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('₹${item['price']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (qty > 0)
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () => setState(() => cart[item['name']] = qty - 1),
                        ),
                      if (qty > 0) Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: () => setState(() => cart[item['name']] = qty + 1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: _sendOrder,
                child: const Text('KOT भेजें (किचन + काउंटर)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ---------------- 3. कुक स्क्रीन (KDS + राशन) ----------------
class CookDashboard extends StatefulWidget {
  final String storeCode;
  const CookDashboard({super.key, required this.storeCode});
  @override
  State<CookDashboard> createState() => _CookDashboardState();
}

class _CookDashboardState extends State<CookDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ipCtrl = TextEditingController(text: '192.168.1.');
  Socket? kitchenSocket;
  bool isConnected = false;
  List<Map<String, dynamic>> kitchenOrders = [];

  // राशन कंट्रोलर
  final _itemCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  bool _rationLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _connectToCounter() async {
    try {
      kitchenSocket = await Socket.connect(_ipCtrl.text.trim(), 4040, timeout: const Duration(seconds: 3));
      setState(() => isConnected = true);
      kitchenSocket!.listen((data) {
        try {
          final lines = utf8.decode(data).split("\n");
          for (var line in lines) {
            if (line.trim().isEmpty) continue;
            final msg = jsonDecode(line);
            if (msg['type'] == 'NEW_ORDER') {
              setState(() {
                kitchenOrders.insert(0, Map<String, dynamic>.from(msg));
              });
            }
          }
        } catch (_) {}
      }, onDone: () => setState(() => isConnected = false), onError: (_) => setState(() => isConnected = false));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('काउंटर से कनेक्ट नहीं हो सका! IP चेक करें।')));
    }
  }

  void _sendRationDemand() async {
    if (_itemCtrl.text.isEmpty || _qtyCtrl.text.isEmpty) return;
    setState(() => _rationLoading = true);
    try {
      await Supabase.instance.client.from('ration_demands').insert({
        'store_code': widget.storeCode,
        'item_name': _itemCtrl.text.trim(),
        'quantity': _qtyCtrl.text.trim(),
      });
      _itemCtrl.clear();
      _qtyCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ राशन मांग पोर्टल पर भेज दी गई!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
    } finally {
      if (mounted) setState(() => _rationLoading = false);
    }
  }

  @override
  void dispose() {
    kitchenSocket?.destroy();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('किचन - ${widget.storeCode}'),
        backgroundColor: Colors.teal,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant), text: 'लाइव KOT ऑर्डर्स'),
            Tab(icon: Icon(Icons.shopping_cart), text: 'राशन मांग (थोक)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // KOT स्क्रीन
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade200,
                child: Row(
                  children: [
                    Expanded(child: TextField(controller: _ipCtrl, decoration: const InputDecoration(labelText: 'काउंटर IP', isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: isConnected ? Colors.green : Colors.teal),
                      onPressed: _connectToCounter,
                      child: Text(isConnected ? 'कनेक्टेड ✓' : 'कनेक्ट करें', style: const TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
              Expanded(
                child: kitchenOrders.isEmpty
                    ? const Center(child: Text('अभी कोई नया ऑर्डर नहीं है...', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: kitchenOrders.length,
                        itemBuilder: (ctx, i) {
                          final order = kitchenOrders[i];
                          final items = order['items'] as List;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Table ${order['table']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                        onPressed: () => setState(() => kitchenOrders.removeAt(i)),
                                        child: const Text('तैयार (Done)', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      )
                                    ],
                                  ),
                                  const Divider(),
                                  ...items.map((it) => Text('• ${it['name']}  x  ${it['qty']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              )
            ],
          ),

          // राशन स्क्रीन
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                TextField(controller: _itemCtrl, decoration: const InputDecoration(labelText: 'सामग्री नाम (उदा. बासमती चावल / तेल / पनीर)', border: OutlineInputBorder())),
                const SizedBox(height: 16),
                TextField(controller: _qtyCtrl, decoration: const InputDecoration(labelText: 'मात्रा (उदा. 25 KG / 15 Ltr)', border: OutlineInputBorder())),
                const SizedBox(height: 24),
                _rationLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                          onPressed: _sendRationDemand,
                          child: const Text('मांग पोर्टल पर दर्ज करें', style: TextStyle(color: Colors.white, fontSize: 16)),
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

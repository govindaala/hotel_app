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
    home: RoleSelectScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

// ---------------- 1. मुख्य प्रवेश स्क्रीन ----------------
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('होटल मैनेजमेंट गेटवे'), backgroundColor: Colors.indigo),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRoleBtn(context, '🖥️ काउंटर मोड (मास्टर)', Colors.indigo, const CounterLoginScreen()),
            const SizedBox(height: 16),
            _buildRoleBtn(context, '📱 वेटर मोड (ऑर्डरिंग)', Colors.orange, const WaiterScreen()),
            const SizedBox(height: 16),
            _buildRoleBtn(context, '👨‍🍳 कुक मोड (किचन + राशन)', Colors.teal, const CookScreen()),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBtn(BuildContext ctx, String label, Color col, Widget target) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: col, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => target)),
        child: Text(label, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ---------------- 2. काउंटर मोड (मास्टर व बिलिंग) ----------------
class CounterLoginScreen extends StatefulWidget {
  const CounterLoginScreen({super.key});
  @override
  State<CounterLoginScreen> createState() => _CounterLoginScreenState();
}

class _CounterLoginScreenState extends State<CounterLoginScreen> {
  final _codeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;

  void _login() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select()
          .eq('store_code', _codeCtrl.text.trim().toUpperCase())
          .eq('master_pin', _pinCtrl.text.trim())
          .maybeSingle();

      if (res != null && res['is_active'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('store_code', res['store_code']);
        await prefs.setInt('tables', res['total_tables']);
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CounterDashboard(tables: res['total_tables'], code: res['store_code'])));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('गलत कोड/पिन या अकाउंट ब्लॉक है!')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('काउंटर एक्टिवेशन'), backgroundColor: Colors.indigo),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'स्टोर कोड (उदा. SGB-101)')),
            TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: '6-अंकों का मास्टर पिन'), keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, minimumSize: const Size(double.infinity, 48)),
                    child: const Text('लॉगिन करें', style: TextStyle(color: Colors.white)),
                  ),
          ],
        ),
      ),
    );
  }
}

class CounterDashboard extends StatefulWidget {
  final int tables;
  final String code;
  const CounterDashboard({super.key, required this.tables, required this.code});
  @override
  State<CounterDashboard> createState() => _CounterDashboardState();
}

class _CounterDashboardState extends State<CounterDashboard> {
  late int tableCount;
  Map<int, double> tableBills = {};
  ServerSocket? server;

  @override
  void initState() {
    super.initState();
    tableCount = widget.tables;
    _startLocalSocketServer();
  }

  void _startLocalSocketServer() async {
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
      server!.listen((Socket client) {
        client.listen((data) {
          final msg = String.fromCharCodes(data);
          final parsed = jsonDecode(msg);
          if (parsed['type'] == 'KOT') {
            setState(() {
              int tbl = parsed['table'];
              double amt = double.parse(parsed['total'].toString());
              tableBills[tbl] = (tableBills[tbl] ?? 0) + amt;
            });
          }
        });
      });
    } catch (_) {}
  }

  void _settleBill(int tbl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('टेबल T-$tbl बिल सेटलमेंट'),
        content: Text('कुल देय राशि: ₹${tableBills[tbl] ?? 0}\n\nक्या ग्राहक से नकद प्राप्त हो गया?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              setState(() {
                tableBills.remove(tbl);
              });
              Navigator.pop(context);
            },
            child: const Text('PAYMENT OK (खाली करें)', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.code} - काउंटर'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => setState(() => tableCount++),
            tooltip: 'टेबल बढ़ाएँ',
          ),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => setState(() { if(tableCount > 1) tableCount--; }),
            tooltip: 'टेबल घटाएँ',
          )
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: tableCount,
        itemBuilder: (ctx, i) {
          int tbl = i + 1;
          bool isOccupied = tableBills.containsKey(tbl);
          return InkWell(
            onTap: isOccupied ? () => _settleBill(tbl) : null,
            child: Container(
              decoration: BoxDecoration(
                color: isOccupied ? Colors.red.shade400 : Colors.green.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('T-$tbl', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    isOccupied ? '₹${tableBills[tbl]}' : 'खाली',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- 3. वेटर मोड (ऑर्डरिंग) ----------------
class WaiterScreen extends StatefulWidget {
  const WaiterScreen({super.key});
  @override
  State<WaiterScreen> createState() => _WaiterScreenState();
}

class _WaiterScreenState extends State<WaiterScreen> {
  int selectedTable = 1;
  final List<Map<String, dynamic>> menu = [
    {'name': 'दाल तड़का', 'price': 120},
    {'name': 'पनीर बटर मसाला', 'price': 180},
    {'name': 'तंदूरी रोटी', 'price': 12},
    {'name': 'जीरा राइस', 'price': 100},
  ];
  final Map<String, int> cart = {};

  void _sendOrder() async {
    if (cart.isEmpty) return;
    double total = 0;
    cart.forEach((k, v) {
      final item = menu.firstWhere((e) => e['name'] == k);
      total += (item['price'] * v);
    });

    try {
      final socket = await Socket.connect('192.168.1.100', 4040, timeout: const Duration(seconds: 2));
      socket.write(jsonEncode({'type': 'KOT', 'table': selectedTable, 'total': total, 'items': cart}));
      await socket.flush();
      await socket.close();
    } catch (_) {}

    setState(() => cart.clear());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ऑर्डर किचन व काउंटर को भेजा गया!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('वेटर ऑर्डरिंग'), backgroundColor: Colors.orange),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                const Text('टेबल चुनें: ', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<int>(
                  value: selectedTable,
                  items: List.generate(20, (i) => DropdownMenuItem(value: i + 1, child: Text('Table ${i + 1}'))),
                  onChanged: (v) => setState(() => selectedTable = v!),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: menu.length,
              itemBuilder: (ctx, i) {
                final item = menu[i];
                return ListTile(
                  title: Text(item['name']),
                  subtitle: Text('₹${item['price']}'),
                  trailing: Row(
                    mainAxisSize: intelligence_min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() {
                          if ((cart[item['name']] ?? 0) > 0) cart[item['name']] = cart[item['name']]! - 1;
                        }),
                      ),
                      Text('${cart[item['name']] ?? 0}', style: const TextStyle(fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() {
                          cart[item['name']] = (cart[item['name']] ?? 0) + 1;
                        }),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(double.infinity, 50)),
            onPressed: _sendOrder,
            child: const Text('KOT भेजें (किचन)', style: TextStyle(color: Colors.white, fontSize: 16)),
          )
        ],
      ),
    );
  }
}

// ---------------- 4. कुक मोड (राशन मांग) ----------------
class CookScreen extends StatefulWidget {
  const CookScreen({super.key});
  @override
  State<CookScreen> createState() => _CookScreenState();
}

class _CookScreenState extends State<CookScreen> {
  final _itemCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  void _submitRation() async {
    if (_itemCtrl.text.isEmpty || _qtyCtrl.text.isEmpty) return;
    try {
      await Supabase.instance.client.from('ration_demands').insert({
        'store_code': _codeCtrl.text.trim().toUpperCase(),
        'item_name': _itemCtrl.text.trim(),
        'quantity': _qtyCtrl.text.trim(),
      });
      _itemCtrl.clear();
      _qtyCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('राशन मांग पोर्टल पर दर्ज हो गई!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('कुक स्क्रीन (राशन मांग)'), backgroundColor: Colors.teal),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'स्टोर कोड (उदा. SGB-101)')),
            TextField(controller: _itemCtrl, decoration: const InputDecoration(labelText: 'सामग्री नाम (उदा. बासमती चावल / तेल)')),
            TextField(controller: _qtyCtrl, decoration: const InputDecoration(labelText: 'मात्रा (उदा. 25 KG / 5 Ltr)')),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, minimumSize: const Size(double.infinity, 48)),
              onPressed: _submitRation,
              child: const Text('राशन मांग भेजें', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }
}

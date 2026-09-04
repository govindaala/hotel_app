import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:screenshot/screenshot.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';

// नए मॉड्यूल्स इम्पोर्ट
import 'models/restaurant_profile_model.dart';
import 'models/expense_model.dart';
import 'screens/admin/restaurant_settings_screen.dart';
import 'screens/admin/daily_expense_screen.dart';
import 'screens/waiter/waiter_menu_order_view.dart';
import 'data/menu_data_source.dart';

const String supabaseUrl = "https://hbewnquphiwvxaxittrl.supabase.co";
const String supabaseKey = "sb_publishable_HA1-PBV55kEZet2GG_IBdg_HjUzfOxf";

const int currentAppVersionCode = 2; // नया वर्शन

// ==========================================
// 1. हिंदी वॉयस इंजन (Text-to-Speech)
// ==========================================
class VoiceService {
  static final FlutterTts _tts = FlutterTts();
  static bool _isInit = false;

  static Future<void> init() async {
    if (_isInit) return;
    try {
      await _tts.setLanguage("hi-IN");
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.32);
      _isInit = true;
    } catch (_) {}
  }

  static Future<void> speak(String text) async {
    await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }
}

// ==========================================
// बैकग्राउंड ऑटो-अपडेट चेकर व डाउनलोडर
// ==========================================
Future<void> checkForAppUpdates(BuildContext context) async {
  try {
    final response = await http.get(Uri.parse('https://govindaala.github.io/hotel_app/app_config.json'));
    if (response.statusCode != 200) return;

    final config = jsonDecode(response.body);
    final int latestVersionCode = config['version_code'] ?? 1;
    final String apkUrl = config['apk_url'] ?? '';
    final String updateMsg = config['update_message'] ?? 'होटल POS का नया वर्शन उपलब्ध है! कृपया अपडेट करें।';

    if (latestVersionCode > currentAppVersionCode && apkUrl.isNotEmpty && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          String downloadProgress = "0";
          bool isDownloading = false;

          return StatefulBuilder(
            builder: (dialogCtx, setDState) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.system_update, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text('ऐप अपडेट उपलब्ध है', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(updateMsg, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 16),
                    if (isDownloading) ...[
                      LinearProgressIndicator(value: (double.tryParse(downloadProgress) ?? 0) / 100),
                      const SizedBox(height: 10),
                      Text('डाउनलोड हो रहा है: $downloadProgress%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]
                  ],
                ),
                actions: [
                  if (!isDownloading) ...[
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बाद में')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      onPressed: () {
                        setDState(() => isDownloading = true);
                        try {
                          OtaUpdate().execute(apkUrl, destinationFilename: 'aala_pos.apk').listen(
                            (OtaEvent event) {
                              if (event.status == OtaStatus.DOWNLOADING) {
                                setDState(() => downloadProgress = event.value ?? "0");
                              } else if (event.status == OtaStatus.INSTALLING) {
                                Navigator.pop(ctx);
                              }
                            },
                            onError: (e) {
                              setDState(() => isDownloading = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('डाउनलोड एरर: $e')));
                            },
                          );
                        } catch (e) {
                          setDState(() => isDownloading = false);
                        }
                      },
                      child: const Text('अपडेट करें', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ],
              );
            },
          );
        },
      );
    }
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  } catch (_) {}
  await VoiceService.init();

  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  final String savedRole = prefs.getString('saved_role') ?? '';
  final String savedStoreCode = prefs.getString('saved_store_code') ?? '111';
  final String savedStaffId = prefs.getString('saved_staff_id') ?? '';
  final String savedHotelName = prefs.getString('saved_hotel_name') ?? 'होटल';
  final int savedTables = prefs.getInt('saved_tables') ?? 10;

  Widget initialScreen = const AppGateway();
  if (isLoggedIn) {
    if (savedRole == 'counter') {
      initialScreen = FullCounterApp(storeCode: savedStoreCode, hotelName: savedHotelName, tables: savedTables);
    } else if (savedRole == 'waiter') {
      initialScreen = FullWaiterApp(storeCode: savedStoreCode, tables: savedTables, staffId: savedStaffId);
    } else if (savedRole == 'cook') {
      initialScreen = FullCookApp(storeCode: savedStoreCode);
    }
  }

  runApp(MaterialApp(
    home: initialScreen,
    debugShowCheckedModeBanner: false,
  ));
}

// ==========================================
// 2. ऐप गेटवे (रोल चयन)
// ==========================================
class AppGateway extends StatefulWidget {
  const AppGateway({super.key});
  @override
  State<AppGateway> createState() => _AppGatewayState();
}

class _AppGatewayState extends State<AppGateway> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForAppUpdates(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('AALA POS सिस्टम', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roleCard(context, '🖥️ मास्टर / ओनर', 'बिलिंग, मेन्यू, राशन व स्टाफ़ प्रबंधन', const Color(0xFF0F172A), 'counter'),
            const SizedBox(height: 18),
            _roleCard(context, '📱 वेटर मोड', 'टेबल ऑर्डर, री-ऑर्डर व KOT', const Color(0xFFEA580C), 'waiter'),
            const SizedBox(height: 18),
            _roleCard(context, '👨‍🍳 कुक मोड (KDS)', 'लाइव किचन KOT व राशन मांग', const Color(0xFF0D9488), 'cook'),
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
        decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ),
    );
  }
}

// ==========================================
// 3. लॉगिन स्क्रीन
// ==========================================
class StaffAuthScreen extends StatefulWidget {
  final String role;
  const StaffAuthScreen({super.key, required this.role});
  @override
  State<StaffAuthScreen> createState() => _StaffAuthScreenState();
}

class _StaffAuthScreenState extends State<StaffAuthScreen> {
  final _codeCtrl = TextEditingController(text: '111');
  final _idCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;

  void _verify() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final staffId = _idCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (code.isEmpty || pin.isEmpty || (widget.role != 'counter' && staffId.isEmpty)) return;

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    try {
      if (widget.role == 'counter') {
        Map<String, dynamic>? res;
        try {
          res = await Supabase.instance.client.from('restaurants').select().eq('store_code', code).maybeSingle();
        } catch (_) {}

        final cachedPin = prefs.getString('cached_master_pin_$code');
        if ((res != null && res['master_pin'] == pin) || cachedPin == pin) {
          await prefs.setBool('is_logged_in', true);
          await prefs.setString('saved_role', 'counter');
          await prefs.setString('saved_store_code', code);
          await prefs.setString('saved_hotel_name', res?['name'] ?? 'होटल');
          await prefs.setInt('saved_tables', res?['total_tables'] ?? 10);
          await prefs.setString('cached_master_pin_$code', pin);

          if (mounted) {
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => FullCounterApp(storeCode: code, hotelName: res?['name'] ?? 'होटल', tables: res?['total_tables'] ?? 10)), (r) => false);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कोड या पिन गलत है!')));
        }
      } else {
        bool isValid = false;
        try {
          final res = await Supabase.instance.client.from('hotel_staff').select().eq('store_code', code).eq('staff_id', staffId).eq('pin', pin).eq('role', widget.role).maybeSingle();
          if (res != null) isValid = true;
        } catch (_) {}

        if (prefs.getString('cached_staff_pin_${code}_$staffId') == pin) isValid = true;

        if (isValid) {
          await prefs.setBool('is_logged_in', true);
          await prefs.setString('saved_role', widget.role);
          await prefs.setString('saved_store_code', code);
          await prefs.setString('saved_staff_id', staffId);
          await prefs.setString('cached_staff_pin_${code}_$staffId', pin);

          if (mounted) {
            if (widget.role == 'waiter') {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => FullWaiterApp(storeCode: code, tables: 10, staffId: staffId)), (r) => false);
            } else {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => FullCookApp(storeCode: code)), (r) => false);
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('स्टाफ ID या पिन गलत है!')));
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.role} लॉगिन', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF0F172A)),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'स्टोर कोड', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          if (widget.role != 'counter') ...[
            TextField(controller: _idCtrl, decoration: const InputDecoration(labelText: 'स्टाफ ID', border: OutlineInputBorder())),
            const SizedBox(height: 16),
          ],
          TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: 'पिन कोड', border: OutlineInputBorder()), obscureText: true, keyboardType: TextInputType.number),
          const SizedBox(height: 24),
          _loading ? const CircularProgressIndicator() : ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), minimumSize: const Size.fromHeight(50)),
            onPressed: _verify,
            child: const Text('लॉगिन करें', style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ]),
      ),
    );
  }
}

// ==========================================
// 4. काउंटर मास्टर ऐप
// ==========================================
class FullCounterApp extends StatefulWidget {
  final String storeCode, hotelName;
  final int tables;
  const FullCounterApp({super.key, required this.storeCode, required this.hotelName, required this.tables});
  @override
  State<FullCounterApp> createState() => _FullCounterAppState();
}

class _FullCounterAppState extends State<FullCounterApp> {
  int _currentTab = 0;
  String localIp = 'IP ढूँढ रहा है...';
  ServerSocket? server;
  final List<Socket> connectedClients = [];

  List<Map<String, dynamic>> hotelMenu = [];
  Map<int, List<Map<String, dynamic>>> activeOrders = {};
  Map<int, String> tableStateMap = {};
  List<Map<String, dynamic>> rationDemands = [];
  final Set<int> _spokenBillTables = {};
  Timer? _cloudSyncTimer;

  bool _isPrinterConnected = false;
  RestaurantProfileModel? _restoProfile;

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _loadRestoProfile();
    _startLocalSocketServer();
    _syncMasterData();
    _checkPrinterStatus();
    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) => _syncMasterData());
    WidgetsBinding.instance.addPostFrameCallback((_) => checkForAppUpdates(context));
  }

  @override
  void dispose() {
    _cloudSyncTimer?.cancel();
    server?.close();
    super.dispose();
  }

  void _loadRestoProfile() async {
    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select()
          .eq('store_code', widget.storeCode)
          .maybeSingle();
      if (res != null) {
        setState(() => _restoProfile = RestaurantProfileModel.fromMap(res));
      }
    } catch (_) {}
  }

  void _checkPrinterStatus() async {
    try {
      final bool status = await PrintBluetoothThermal.connectionStatus;
      if (mounted) setState(() => _isPrinterConnected = status);
    } catch (_) {}
  }

  void _startLocalSocketServer() async {
    try {
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
            for (var line in lines) {
              if (line.trim().isEmpty) continue;
              final msg = jsonDecode(line);

              if (msg['type'] == 'GET_MENU') {
                client.write(jsonEncode({'type': 'MENU_DATA', 'menu': hotelMenu}) + "\n");
              } else if (msg['type'] == 'NEW_KOT') {
                int tbl = msg['table'];
                setState(() {
                  if (!activeOrders.containsKey(tbl)) activeOrders[tbl] = [];
                  activeOrders[tbl]!.addAll(List<Map<String, dynamic>>.from(msg['items']));
                  tableStateMap[tbl] = 'running';
                });
                _broadcastLocal(msg);
              } else if (msg['type'] == 'BILL_READY') {
                int tbl = msg['table'];
                setState(() => tableStateMap[tbl] = 'bill_ready');
                if (!_spokenBillTables.contains(tbl)) {
                  _spokenBillTables.add(tbl);
                  VoiceService.speak("टेबल $tbl का बिल तैयार है");
                }
              } else if (msg['type'] == 'ORDER_READY') {
                _broadcastLocal(msg);
              } else if (msg['type'] == 'RATION_DEMAND') {
                _syncMasterData();
              }
            }
          } catch (_) {}
        }, onDone: () => connectedClients.remove(client), onError: (_) => connectedClients.remove(client));
      });
    } catch (_) {}
  }

  void _broadcastLocal(dynamic data) {
    for (var c in List<Socket>.from(connectedClients)) {
      try {
        c.write(jsonEncode(data) + "\n");
      } catch (_) {
        connectedClients.remove(c);
      }
    }
  }

  void _loadMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_menu_${widget.storeCode}');
    if (saved != null) {
      setState(() => hotelMenu = List<Map<String, dynamic>>.from(jsonDecode(saved)));
    } else {
      // 14 कैटेगरीज वाला नया मेन्यू
      setState(() {
        hotelMenu = kRestaurantMenu.map((m) => {
          'id': m.id,
          'name': m.name,
          'price': m.price,
          'cat': m.category,
          'available': true,
        }).toList();
      });
      await prefs.setString('saved_menu_${widget.storeCode}', jsonEncode(hotelMenu));
    }
  }

  void _syncMasterData() async {
    try {
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10)).toIso8601String();
      final res = await Supabase.instance.client
          .from('ration_demands')
          .select()
          .eq('store_code', widget.storeCode)
          .gte('created_at', tenDaysAgo)
          .order('created_at', ascending: false);
      if (res != null && mounted) setState(() => rationDemands = List<Map<String, dynamic>>.from(res));
    } catch (_) {}

    try {
      final kots = await Supabase.instance.client
          .from('hotel_kots')
          .select()
          .eq('store_code', widget.storeCode)
          .neq('status', 'settled');

      if (kots != null && mounted) {
        Map<int, List<Map<String, dynamic>>> tempOrders = {};
        Map<int, String> tempStates = {};

        for (var k in kots) {
          int tbl = k['table_no'];
          String st = k['status'];
          List items = jsonDecode(k['items'].toString());
          if (!tempOrders.containsKey(tbl)) tempOrders[tbl] = [];
          tempOrders[tbl]!.addAll(List<Map<String, dynamic>>.from(items));
          if (st == 'bill_ready') tempStates[tbl] = 'bill_ready';
          else if (!tempStates.containsKey(tbl)) tempStates[tbl] = 'running';

          if (st == 'bill_ready' && !_spokenBillTables.contains(tbl)) {
            _spokenBillTables.add(tbl);
            VoiceService.speak("टेबल $tbl का बिल तैयार है");
          }
        }
        setState(() {
          activeOrders = tempOrders;
          tableStateMap = tempStates;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.hotelName} (मास्टर)', style: const TextStyle(color: Colors.white, fontSize: 17)),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          // 1. दैनिक खर्च बटन
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
            tooltip: 'दैनिक खर्च',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DailyExpenseScreen(
                    restaurantId: widget.storeCode,
                    totalCashSalesToday: 0.0,
                    initialExpenses: const [],
                    onAddExpense: (newExpense) async {
                      try {
                        await Supabase.instance.client.from('daily_expenses').insert(newExpense.toMap());
                      } catch (_) {}
                    },
                  ),
                ),
              );
            },
          ),
          // 2. रेस्टोरेंट सेटिंग्स (⚙️) बटन
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'होटल सेटिंग्स',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RestaurantSettingsScreen(
                    initialProfile: _restoProfile,
                    onSave: (updated) async {
                      setState(() => _restoProfile = updated);
                      try {
                        await Supabase.instance.client.from('restaurants').upsert(updated.toMap());
                      } catch (_) {}
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
            },
          )
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('हॉटस्पॉट IP: $localIp', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                Text('कनेक्टेड: ${connectedClients.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: _currentTab == 0 ? _buildTablesTab() : _buildRationTab(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'टेबल्स व बिल'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'राशन मांग'),
        ],
      ),
    );
  }

  Widget _buildTablesTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: widget.tables,
      itemBuilder: (context, index) {
        int tableNo = index + 1;
        String state = tableStateMap[tableNo] ?? 'empty';
        Color col = Colors.grey.shade300;
        if (state == 'running') col = Colors.orange.shade200;
        if (state == 'bill_ready') col = Colors.green.shade300;

        return InkWell(
          onTap: () => _openTableDetail(tableNo),
          child: Container(
            decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('टेबल $tableNo', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(state == 'running' ? 'चल रहा है' : state == 'bill_ready' ? 'बिल तैयार' : 'खाली', style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openTableDetail(int tbl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final items = activeOrders[tbl] ?? [];
        double total = items.fold(0.0, (s, i) => s + ((i['price'] as num) * (i['qty'] as num)));

        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('टेबल $tbl - ऑर्डर विवरण', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('कोई सक्रिय ऑर्डर नहीं'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          title: Text(items[i]['name']),
                          trailing: Text('${items[i]['qty']} x ₹${items[i]['price']} = ₹${(items[i]['qty'] as num) * (items[i]['price'] as num)}'),
                        ),
                      ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('कुल राशि:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('₹ $total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(48)),
                onPressed: items.isEmpty ? null : () async {
                  setState(() {
                    activeOrders.remove(tbl);
                    tableStateMap[tbl] = 'empty';
                  });
                  try {
                    await Supabase.instance.client.from('hotel_kots').update({'status': 'settled'}).eq('store_code', widget.storeCode).eq('table_no', tbl);
                  } catch (_) {}
                  Navigator.pop(ctx);
                },
                child: const Text('बिल सेटल करें (भुगतान पूरा)', style: TextStyle(color: Colors.white, fontSize: 16)),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildRationTab() {
    return rationDemands.isEmpty
        ? const Center(child: Text('कोई राशन मांग नहीं आई'))
        : ListView.builder(
            itemCount: rationDemands.length,
            itemBuilder: (_, i) {
              final r = rationDemands[i];
              return ListTile(
                title: Text(r['item_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text('${r['qty'] ?? ''} ${r['unit'] ?? ''}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                subtitle: Text('दिनांक: ${r['created_at']?.toString().split('T').first ?? ''}'),
              );
            },
          );
  }
}

// ==========================================
// 5. वेटर ऐप (14 कैटेगरी मेन्यू फ़िल्टर के साथ)
// ==========================================
class FullWaiterApp extends StatefulWidget {
  final String storeCode;
  final int tables;
  final String staffId;
  const FullWaiterApp({super.key, required this.storeCode, required this.tables, required this.staffId});
  @override
  State<FullWaiterApp> createState() => _FullWaiterAppState();
}

class _FullWaiterAppState extends State<FullWaiterApp> {
  int _selectedTable = 1;
  final List<Map<String, dynamic>> _currentKot = [];
  Socket? socket;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  void _connectSocket() async {
    try {
      socket = await Socket.connect('192.168.43.1', 4040, timeout: const Duration(seconds: 2));
      setState(() => _isConnected = true);
    } catch (_) {
      setState(() => _isConnected = false);
    }
  }

  void _sendKot() async {
    if (_currentKot.isEmpty) return;
    final kotData = {
      'type': 'NEW_KOT',
      'store_code': widget.storeCode,
      'table': _selectedTable,
      'staff_id': widget.staffId,
      'items': _currentKot,
    };

    if (_isConnected && socket != null) {
      try {
        socket!.write(jsonEncode(kotData) + "\n");
      } catch (_) {}
    }

    try {
      await Supabase.instance.client.from('hotel_kots').insert({
        'store_code': widget.storeCode,
        'table_no': _selectedTable,
        'items': jsonEncode(_currentKot),
        'status': 'running',
      });
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('KOT किचन भेज दी गई!')));
    setState(() => _currentKot.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('वेटर - टेबल $_selectedTable', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFEA580C),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
            },
          )
        ],
      ),
      body: Column(
        children: [
          // टेबल चयन रो
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: widget.tables,
              itemBuilder: (ctx, i) {
                int tbl = i + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text('T-$tbl'),
                    selected: _selectedTable == tbl,
                    onSelected: (s) => setState(() => _selectedTable = tbl),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // नया 14-कैटेगरी वेटर मेन्यू विजेट
          Expanded(
            child: WaiterMenuOrderView(
              onAddItem: (item) {
                setState(() {
                  final idx = _currentKot.indexWhere((e) => e['name'] == item.name);
                  if (idx >= 0) {
                    _currentKot[idx]['qty'] = (_currentKot[idx]['qty'] as int) + 1;
                  } else {
                    _currentKot.add({
                      'id': item.id,
                      'name': item.name,
                      'price': item.price,
                      'qty': 1,
                    });
                  }
                });
              },
            ),
          ),

          // करेंट ऑर्डर समरी और KOT भेजें बटन
          if (_currentKot.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Expanded(
                    child: Text('चुने गए आइटम: ${_currentKot.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
                    onPressed: _sendKot,
                    icon: const Icon(Icons.send, color: Colors.white),
                    label: const Text('KOT भेजें', style: TextStyle(color: Colors.white)),
                  )
                ],
              ),
            )
        ],
      ),
    );
  }
}

// ==========================================
// 6. कुक KDS ऐप
// ==========================================
class FullCookApp extends StatefulWidget {
  final String storeCode;
  const FullCookApp({super.key, required this.storeCode});
  @override
  State<FullCookApp> createState() => _FullCookAppState();
}

class _FullCookAppState extends State<FullCookApp> {
  final List<Map<String, dynamic>> _kots = [];

  @override
  void initState() {
    super.initState();
    _fetchKots();
  }

  void _fetchKots() async {
    try {
      final res = await Supabase.instance.client
          .from('hotel_kots')
          .select()
          .eq('store_code', widget.storeCode)
          .eq('status', 'running');
      if (res != null && mounted) {
        setState(() => _kots.addAll(List<Map<String, dynamic>>.from(res)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('किचन KDS (कुक)', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0D9488),
      ),
      body: _kots.isEmpty
          ? const Center(child: Text('कोई लंबित KOT नहीं है'))
          : ListView.builder(
              itemCount: _kots.length,
              itemBuilder: (ctx, i) {
                final k = _kots[i];
                final items = jsonDecode(k['items'].toString());
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text('टेबल #${k['table_no']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(items.map((e) => "${e['name']} x ${e['qty']}").join(", ")),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488)),
                      onPressed: () {
                        setState(() => _kots.removeAt(i));
                      },
                      child: const Text('तैयार', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

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

const String supabaseUrl = "https://hbewnquphiwvxaxittrl.supabase.co";
const String supabaseKey = "sb_publishable_HA1-PBV55kEZet2GG_IBdg_HjUzfOxf";

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
      await _tts.setSpeechRate(0.32); // धीमी और स्पष्ट आवाज़
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

final List<Map<String, dynamic>> defaultHotelMenu = [
  {'id': 1, 'name': 'दाल तड़का', 'price': 120.0, 'cat': 'सब्जी', 'available': true},
  {'id': 2, 'name': 'पनीर बटर मसाला', 'price': 180.0, 'cat': 'सब्जी', 'available': true},
  {'id': 3, 'name': 'तंदूरी रोटी', 'price': 12.0, 'cat': 'रोटी', 'available': true},
  {'id': 4, 'name': 'जीरा राइस', 'price': 100.0, 'cat': 'चावल', 'available': true},
];

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
class AppGateway extends StatelessWidget {
  const AppGateway({super.key});

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
  String _connectedPrinterMac = '';

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _startLocalSocketServer();
    _syncMasterData();
    _checkPrinterStatus();
    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) => _syncMasterData());
  }

  @override
  void dispose() {
    _cloudSyncTimer?.cancel();
    server?.close();
    super.dispose();
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
      setState(() => hotelMenu = List.from(defaultHotelMenu));
      await prefs.setString('saved_menu_${widget.storeCode}', jsonEncode(hotelMenu));
    }
  }

  void _saveMenu() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_menu_${widget.storeCode}', jsonEncode(hotelMenu));
    _broadcastLocal({'type': 'MENU_DATA', 'menu': hotelMenu});
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

  void _toggleRationReceived(String id, bool currentStatus) async {
    try {
      await Supabase.instance.client.from('ration_demands').update({'is_received': !currentStatus}).eq('id', id);
      _syncMasterData();
    } catch (_) {}
  }

  // ==================================================================
  // स्मार्ट राशन रिपोर्ट: फ़िल्टर, ऑटो-योग और शुद्ध हिंदी PDF जनरेशन
  // ==================================================================
  void _openRationExportFilterModal() {
    if (rationDemands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('निर्यात के लिए कोई राशन डेटा उपलब्ध नहीं है')));
      return;
    }

    String selectedPeriod = '10_days'; // 'today', '3_days', '10_days'
    bool onlyPending = true;
    bool autoMergeQty = true;

    // उपलब्ध सभी अद्वितीय सामग्रियों की सूची
    final Set<String> allItems = rationDemands.map((e) => e['item_name'].toString().trim()).toSet();
    final Set<String> selectedItems = Set.from(allItems);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.amber),
                SizedBox(width: 8),
                Text('राशन PDF फ़िल्टर', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('समय सीमा चुनें:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('आज का'),
                          selected: selectedPeriod == 'today',
                          onSelected: (v) => setDState(() => selectedPeriod = 'today'),
                        ),
                        ChoiceChip(
                          label: const Text('पिछले 3 दिन'),
                          selected: selectedPeriod == '3_days',
                          onSelected: (v) => setDState(() => selectedPeriod = '3_days'),
                        ),
                        ChoiceChip(
                          label: const Text('पूरे 10 दिन'),
                          selected: selectedPeriod == '10_days',
                          onSelected: (v) => setDState(() => selectedPeriod = '10_days'),
                        ),
                      ],
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('केवल पेंडिंग सामान (बाज़ार पर्ची)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('जो सामान आ चुका है उसे न जोड़ें', style: TextStyle(fontSize: 12)),
                      value: onlyPending,
                      onChanged: (val) => setDState(() => onlyPending = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('समान सामग्री की मात्रा जोड़ें (Merge)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: const Text('उदा. आलू 5kg + आलू 10kg = आलू 15kg', style: TextStyle(fontSize: 12)),
                      value: autoMergeQty,
                      onChanged: (val) => setDState(() => autoMergeQty = val),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('सामग्री का चुनाव:', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () {
                            setDState(() {
                              if (selectedItems.length == allItems.length) {
                                selectedItems.clear();
                              } else {
                                selectedItems.addAll(allItems);
                              }
                            });
                          },
                          child: Text(selectedItems.length == allItems.length ? 'सब हटाएं' : 'सब चुनें'),
                        )
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      children: allItems.map((name) {
                        final isChecked = selectedItems.contains(name);
                        return FilterChip(
                          label: Text(name),
                          selected: isChecked,
                          onSelected: (val) {
                            setDState(() {
                              if (val) {
                                selectedItems.add(name);
                              } else {
                                selectedItems.remove(name);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द करें')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                icon: const Icon(Icons.download, color: Colors.white, size: 18),
                label: const Text('PDF तैयार करें', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _processAndExportRationPdf(selectedPeriod, onlyPending, autoMergeQty, selectedItems);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _processAndExportRationPdf(String period, bool onlyPending, bool autoMergeQty, Set<String> selectedItems) async {
    DateTime cutoff = DateTime.now().subtract(const Duration(days: 10));
    if (period == 'today') {
      cutoff = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    } else if (period == '3_days') {
      cutoff = DateTime.now().subtract(const Duration(days: 3));
    }

    // 1. प्राथमिक फ़िल्टरिंग
    List<Map<String, dynamic>> filtered = rationDemands.where((r) {
      final String name = r['item_name'].toString().trim();
      if (!selectedItems.contains(name)) return false;
      if (onlyPending && r['is_received'] == true) return false;

      final createdAt = DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now();
      return createdAt.isAfter(cutoff) || createdAt.isAtSameMomentAs(cutoff);
    }).toList();

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('चुने गए फ़िल्टर के अनुसार कोई रिकॉर्ड नहीं मिला!')));
      return;
    }

    // 2. मात्रा का स्वतः जोड़ (Auto-Merge)
    List<Map<String, dynamic>> finalRows = [];
    if (autoMergeQty) {
      Map<String, Map<String, dynamic>> mergedMap = {};
      for (var r in filtered) {
        String name = r['item_name'].toString().trim();
        String rawQty = r['quantity'].toString().trim();
        final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(rawQty);
        double val = match != null ? (double.tryParse(match.group(1)!) ?? 1.0) : 1.0;
        String unit = rawQty.replaceAll(RegExp(r'[\d\.\s]'), '');
        if (unit.isEmpty) unit = 'यूनिट';

        if (!mergedMap.containsKey(name)) {
          mergedMap[name] = {
            'item_name': name,
            'total_qty': val,
            'unit': unit,
            'is_received': r['is_received'] == true,
            'date': (r['created_at'] ?? '').substring(0, 10),
          };
        } else {
          mergedMap[name]!['total_qty'] = (mergedMap[name]!['total_qty'] as double) + val;
          if (r['is_received'] != true) mergedMap[name]!['is_received'] = false;
        }
      }

      mergedMap.forEach((k, v) {
        double q = v['total_qty'];
        String formattedQty = q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(1);
        finalRows.add({
          'item_name': v['item_name'],
          'quantity': '$formattedQty ${v['unit']}',
          'is_received': v['is_received'],
          'created_at': v['date'],
        });
      });
    } else {
      finalRows = filtered;
    }

    // 3. शुद्ध हिंदी स्क्रीनशॉट रेंडरिंग व PDF निर्माण
    try {
      final Uint8List imageBytes = await ScreenshotController().captureFromWidget(
        Container(
          width: 600,
          color: Colors.white,
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.hotelName} - राशन मांग सूची', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 4),
              Text(
                'पर्ची प्रकार: ${onlyPending ? "केवल बाज़ार मांग (पेंडिंग)" : "समग्र राशन रिकॉर्ड"} | दिनांक: ${DateTime.now().toString().substring(0, 10)}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.black, thickness: 1.5),
              const SizedBox(height: 10),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(4.5),
                  1: FlexColumnWidth(2.5),
                  2: FlexColumnWidth(3),
                },
                children: [
                  const TableRow(
                    decoration: BoxDecoration(color: Color(0xFFF1F5F9)),
                    children: [
                      Padding(padding: EdgeInsets.all(8), child: Text('सामग्री व मात्रा', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black))),
                      Padding(padding: EdgeInsets.all(8), child: Text('स्थिति', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black))),
                      Padding(padding: EdgeInsets.all(8), child: Text('दिनांक', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black))),
                    ],
                  ),
                  ...finalRows.map((r) {
                    final bool isRec = r['is_received'] == true;
                    return TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Text('${r['item_name']} (${r['quantity']})', style: const TextStyle(fontSize: 15, color: Colors.black, fontWeight: FontWeight.w500))),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Text(
                            isRec ? 'आ गया ✓' : 'पेंडिंग ⏳',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isRec ? Colors.green.shade800 : Colors.orange.shade900),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8), child: Text((r['created_at'] ?? '').substring(0, 10), style: const TextStyle(fontSize: 14, color: Colors.black87))),
                      ],
                    );
                  }),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.black26),
              Align(alignment: Alignment.centerRight, child: Text('कुल सामग्री: ${finalRows.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            ],
          ),
        ),
        delay: const Duration(milliseconds: 50),
        pixelRatio: 2.0,
      );

      final pdf = pw.Document();
      final pdfImage = pw.MemoryImage(imageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Center(child: pw.Image(pdfImage)),
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ration_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: '🛒 ${widget.hotelName} राशन पर्ची');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF जनरेशन त्रुटि: $e')));
    }
  }

  // ==========================================
  // ब्लूटूथ प्रिंटर स्कैन व कनेक्शन डायलॉग
  // ==========================================
  void _showPrinterDialog() async {
    List<BluetoothInfo> availablePrinters = [];
    bool scanning = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          if (scanning) {
            PrintBluetoothThermal.pairedBluetooths.then((list) {
              setDState(() {
                availablePrinters = list;
                scanning = false;
              });
            }).catchError((_) {
              setDState(() => scanning = false);
            });
          }

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ब्लूटूथ प्रिंटर'),
                _isPrinterConnected
                    ? const Text('कनेक्टेड ✓', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))
                    : const Text('डिस्कनेक्टेड', style: TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 250,
              child: scanning
                  ? const Center(child: CircularProgressIndicator())
                  : availablePrinters.isEmpty
                      ? const Center(child: Text('कोई ब्लूटूथ प्रिंटर पेयर नहीं मिला!\nफ़ोन की ब्लूटूथ सेटिंग में जाकर प्रिंटर पेयर करें।', textAlign: TextAlign.center))
                      : ListView.builder(
                          itemCount: availablePrinters.length,
                          itemBuilder: (context, index) {
                            final p = availablePrinters[index];
                            final bool isThisConnected = _isPrinterConnected && _connectedPrinterMac == p.macAdress;

                            return ListTile(
                              leading: Icon(Icons.print, color: isThisConnected ? Colors.green : Colors.grey),
                              title: Text(p.name.isNotEmpty ? p.name : 'थर्मल प्रिंटर'),
                              subtitle: Text(p.macAdress),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: isThisConnected ? Colors.red : Colors.green),
                                onPressed: () async {
                                  if (isThisConnected) {
                                    await PrintBluetoothThermal.disconnect;
                                    setState(() => _isPrinterConnected = false);
                                    setDState(() {});
                                  } else {
                                    final bool res = await PrintBluetoothThermal.connect(macPrinterAddress: p.macAdress);
                                    setState(() {
                                      _isPrinterConnected = res;
                                      if (res) _connectedPrinterMac = p.macAdress;
                                    });
                                    setDState(() {});
                                    if (res && mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('प्रिंटर सफलतापूर्वक कनेक्ट हुआ!'), backgroundColor: Colors.green));
                                    }
                                  }
                                },
                                child: Text(isThisConnected ? 'हटाएँ' : 'कनेक्ट', style: const TextStyle(color: Colors.white)),
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद करें')),
            ],
          );
        },
      ),
    );
  }

  // थर्मल प्रिंटर से बिल रसीद प्रिंट करना
  Future<void> _printBillReceipt(int tbl, List<Map<String, dynamic>> items, double total) async {
    final bool isConn = await PrintBluetoothThermal.connectionStatus;
    if (!isConn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ प्रिंटर कनेक्ट नहीं है! ऊपर 🖨️ आइकन से प्रिंटर कनेक्ट करें।'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      bytes += generator.text(widget.hotelName, styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('टेबल: T-$tbl', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('दिनांक: ${DateTime.now().toString().substring(0, 16)}', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.hr();

      for (var it in items) {
        bytes += generator.row([
          PosColumn(text: it['name'].toString(), width: 7),
          PosColumn(text: 'x${it['qty']}', width: 2),
          PosColumn(text: '${(it['price'] * it['qty']).toInt()}', width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.hr();
      bytes += generator.text('कुल बिल: Rs ${total.toStringAsFixed(2)}', styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size1, width: PosTextSize.size2));
      bytes += generator.feed(1);
      bytes += generator.text('धन्यवाद! फिर पधारें', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      await PrintBluetoothThermal.writeBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('पर्ची प्रिंट हो गई ✓'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('प्रिंट एरर: $e')));
      }
    }
  }

  // ==========================================
  // स्टाफ़ प्रबंधन (कुक/वेटर जोड़ें या हटाएँ)
  // ==========================================
  void _showStaffManagementDialog() {
    final staffIdCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String selectedRole = 'waiter';
    List<Map<String, dynamic>> staffList = [];
    bool loading = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          void fetchStaff() async {
            try {
              final res = await Supabase.instance.client
                  .from('hotel_staff')
                  .select()
                  .eq('store_code', widget.storeCode);
              if (res != null) {
                setDState(() {
                  staffList = List<Map<String, dynamic>>.from(res);
                  loading = false;
                });
              }
            } catch (_) {
              setDState(() => loading = false);
            }
          }

          if (loading) fetchStaff();

          return AlertDialog(
            title: const Text('👥 स्टाफ़ प्रबंधन (कुक/वेटर)'),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: TextField(controller: staffIdCtrl, decoration: const InputDecoration(labelText: 'स्टाफ़ ID (उदा. W1, C1)', isDense: true))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: '4-अंक पिन', isDense: true), keyboardType: TextInputType.number, obscureText: true)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            DropdownButton<String>(
                              value: selectedRole,
                              items: const [
                                DropdownMenuItem(value: 'waiter', child: Text('वेटर (Waiter)')),
                                DropdownMenuItem(value: 'cook', child: Text('कुक (Cook)')),
                              ],
                              onChanged: (v) => setDState(() => selectedRole = v!),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                              onPressed: () async {
                                final sid = staffIdCtrl.text.trim();
                                final spin = pinCtrl.text.trim();
                                if (sid.isEmpty || spin.isEmpty) return;

                                try {
                                  await Supabase.instance.client.from('hotel_staff').insert({
                                    'store_code': widget.storeCode,
                                    'staff_id': sid,
                                    'pin': spin,
                                    'role': selectedRole,
                                  });
                                  staffIdCtrl.clear();
                                  pinCtrl.clear();
                                  fetchStaff();
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
                                }
                              },
                              child: const Text('जोड़ें +', style: TextStyle(color: Colors.white)),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Align(alignment: Alignment.centerLeft, child: Text('मौजूदा स्टाफ़ सूची:', style: TextStyle(fontWeight: FontWeight.bold))),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : staffList.isEmpty
                            ? const Center(child: Text('कोई स्टाफ़ नहीं जुड़ा है'))
                            : ListView.builder(
                                itemCount: staffList.length,
                                itemBuilder: (context, index) {
                                  final s = staffList[index];
                                  final isCook = s['role'] == 'cook';
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: isCook ? Colors.teal : Colors.orange,
                                      child: Text(isCook ? '👨‍🍳' : '📱'),
                                    ),
                                    title: Text('${s['staff_id']} (${isCook ? 'कुक' : 'वेटर'})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('पिन: ${s['pin']}'),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () async {
                                        try {
                                          await Supabase.instance.client
                                              .from('hotel_staff')
                                              .delete()
                                              .eq('store_code', widget.storeCode)
                                              .eq('staff_id', s['staff_id']);
                                          fetchStaff();
                                        } catch (_) {}
                                      },
                                    ),
                                  );
                                },
                              ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद करें')),
            ],
          );
        },
      ),
    );
  }

  void _openAddEditMenuModal([Map<String, dynamic>? itemToEdit, int? editIndex]) {
    final nameCtrl = TextEditingController(text: itemToEdit?['name'] ?? '');
    final priceCtrl = TextEditingController(text: itemToEdit != null ? itemToEdit['price'].toString() : '');
    String cat = itemToEdit?['cat'] ?? 'सब्जी';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          title: Text(itemToEdit == null ? 'नया व्यंजन जोड़ें' : 'व्यंजन एडिट करें'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'व्यंजन का नाम')),
              TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'कीमत ₹'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              DropdownButton<String>(
                isExpanded: true,
                value: cat,
                items: const [
                  DropdownMenuItem(value: 'सब्जी', child: Text('सब्जी')),
                  DropdownMenuItem(value: 'रोटी', child: Text('रोटी')),
                  DropdownMenuItem(value: 'चावल', child: Text('चावल')),
                  DropdownMenuItem(value: 'नाश्ता', child: Text('नाश्ता')),
                ],
                onChanged: (v) => setDState(() => cat = v!),
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty) {
                  setState(() {
                    if (itemToEdit == null) {
                      hotelMenu.add({'id': DateTime.now().millisecondsSinceEpoch, 'name': nameCtrl.text.trim(), 'price': double.parse(priceCtrl.text), 'cat': cat, 'available': true});
                    } else {
                      hotelMenu[editIndex!] = {'id': itemToEdit['id'], 'name': nameCtrl.text.trim(), 'price': double.parse(priceCtrl.text), 'cat': cat, 'available': itemToEdit['available'] ?? true};
                    }
                  });
                  _saveMenu();
                  Navigator.pop(ctx);
                }
              },
              child: const Text('सेव करें', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _settleBill(int tbl) {
    List<Map<String, dynamic>> items = activeOrders[tbl] ?? [];
    double total = items.fold(0, (sum, it) => sum + (it['price'] * it['qty']));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('टेबल T-$tbl का बिल: ₹$total'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ऑर्डर किए गए व्यंजन:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...items.map((it) => Text('• ${it['name']} x ${it['qty']} = ₹${(it['price'] * it['qty']).toInt()}')),
            const Divider(),
            const Text('प्रिंट पर्ची निकालें या सीधे बिल सेटल करें:'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            icon: const Icon(Icons.print, color: Colors.white, size: 18),
            label: const Text('प्रिंट पर्ची', style: TextStyle(color: Colors.white)),
            onPressed: () => _printBillReceipt(tbl, items, total),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Supabase.instance.client.from('hotel_kots').update({'status': 'settled'}).eq('store_code', widget.storeCode).eq('table_no', tbl);
              } catch (_) {}
              _spokenBillTables.remove(tbl);
              setState(() {
                activeOrders.remove(tbl);
                tableStateMap.remove(tbl);
              });
            },
            child: const Text('बिल सेटल करें', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.hotelName} (मास्टर)', style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF0F172A),
          actions: [
            IconButton(
              icon: Icon(Icons.print, color: _isPrinterConnected ? Colors.greenAccent : Colors.white),
              tooltip: 'ब्लूटूथ प्रिंटर कनेक्ट करें',
              onPressed: _showPrinterDialog,
            ),
            IconButton(
              icon: const Icon(Icons.group, color: Colors.orangeAccent),
              tooltip: 'स्टाफ़ प्रबंधन (कुक/वेटर)',
              onPressed: _showStaffManagementDialog,
            ),
            IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.amber), tooltip: 'राशन PDF डाउनलोड', onPressed: _openRationExportFilterModal),
            IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), tooltip: 'लॉगआउट', onPressed: _logout),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(26),
            child: Container(
              color: const Color(0xFF1E293B),
              child: Center(child: Text('हॉटस्पॉट चालू रखें | वाई-फ़ाई सर्वर IP: $localIp', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13))),
            ),
          ),
        ),
        body: [
          GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: widget.tables,
            itemBuilder: (ctx, i) {
              int tbl = i + 1;
              String st = tableStateMap[tbl] ?? 'empty';
              Color c = st == 'bill_ready' ? Colors.purple : (st == 'running' ? Colors.red : Colors.green);
              String label = st == 'bill_ready' ? 'बिल तैयार 🔔' : (st == 'running' ? 'ऑर्डर चालू' : 'खाली');

              return InkWell(
                onTap: st != 'empty' ? () => _settleBill(tbl) : null,
                child: Container(
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text('T-$tbl\n$label', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                ),
              );
            },
          ),
          Scaffold(
            floatingActionButton: FloatingActionButton(
              backgroundColor: const Color(0xFF0F172A),
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () => _openAddEditMenuModal(),
            ),
            body: ListView.builder(
              itemCount: hotelMenu.length,
              itemBuilder: (ctx, i) {
                final item = hotelMenu[i];
                return ListTile(
                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('₹${item['price']} (${item['cat']})'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _openAddEditMenuModal(item, i)),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                        setState(() => hotelMenu.removeAt(i));
                        _saveMenu();
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
          rationDemands.isEmpty
              ? const Center(child: Text('10 दिनों में कोई राशन मांग दर्ज नहीं है'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rationDemands.length,
                  itemBuilder: (ctx, i) {
                    final r = rationDemands[i];
                    final bool isRec = r['is_received'] == true;
                    return Card(
                      color: isRec ? Colors.green.shade50 : Colors.white,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: isRec ? Colors.green : Colors.orange, width: 1.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        title: Text(r['item_name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isRec ? Colors.green.shade900 : Colors.black)),
                        subtitle: Text('मात्रा: ${r['quantity']} | दिनांक: ${(r['created_at'] ?? '').substring(0, 10)}'),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: isRec ? Colors.green : Colors.orange),
                          onPressed: () => _toggleRationReceived(r['id'], isRec),
                          child: Text(isRec ? 'आ गया ✓' : 'पेंडिंग', style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    );
                  },
                ),
        ][_currentTab],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTab,
          selectedItemColor: const Color(0xFF0F172A),
          onTap: (i) => setState(() => _currentTab = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.table_bar), label: 'टेबल्स'),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'मेन्यू'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_basket), label: 'राशन रिकॉर्ड (10 दिन)'),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 5. वेटर ऐप
// ==========================================
class FullWaiterApp extends StatefulWidget {
  final String storeCode, staffId;
  final int tables;
  const FullWaiterApp({super.key, required this.storeCode, required this.tables, required this.staffId});
  @override
  State<FullWaiterApp> createState() => _FullWaiterAppState();
}

class _FullWaiterAppState extends State<FullWaiterApp> {
  String _counterIp = '192.168.43.1';
  bool _socketConnected = false;
  Socket? _waiterSocket;
  List<Map<String, dynamic>> menu = [];
  Map<int, List<Map<String, dynamic>>> liveTables = {};
  Map<int, String> tableStatus = {};
  final Set<String> _spokenReadyKots = {};
  Timer? _waiterSyncTimer;

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _initNetworkAndSync();
    _waiterSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_socketConnected) _connectToSocket();
      _syncFromCloud();
    });
  }

  @override
  void dispose() {
    _waiterSyncTimer?.cancel();
    _waiterSocket?.destroy();
    super.dispose();
  }

  void _initNetworkAndSync() async {
    final prefs = await SharedPreferences.getInstance();
    _counterIp = prefs.getString('saved_counter_ip') ?? '192.168.43.1';
    _connectToSocket();
    _syncFromCloud();
  }

  void _connectToSocket() async {
    try {
      _waiterSocket = await Socket.connect(_counterIp, 4040, timeout: const Duration(seconds: 2));
      if (mounted) setState(() => _socketConnected = true);
      _waiterSocket!.write(jsonEncode({'type': 'GET_MENU'}) + "\n");

      _waiterSocket!.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var l in lines) {
          if (l.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(l);
            if (msg['type'] == 'MENU_DATA' && mounted) {
              setState(() => menu = List<Map<String, dynamic>>.from(msg['menu']));
            } else if (msg['type'] == 'ORDER_READY') {
              int tbl = msg['table'];
              VoiceService.speak("टेबल $tbl का ऑर्डर तैयार है");
            }
          } catch (_) {}
        }
      }, onDone: () => setState(() => _socketConnected = false), onError: (_) => setState(() => _socketConnected = false));
    } catch (_) {
      if (mounted && _socketConnected) setState(() => _socketConnected = false);
    }
  }

  void _loadMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_menu_${widget.storeCode}');
    if (saved != null) {
      setState(() => menu = List<Map<String, dynamic>>.from(jsonDecode(saved)));
    } else {
      setState(() => menu = List.from(defaultHotelMenu));
    }
  }

  void _syncFromCloud() async {
    try {
      final kots = await Supabase.instance.client
          .from('hotel_kots')
          .select()
          .eq('store_code', widget.storeCode)
          .neq('status', 'settled');

      if (kots != null && mounted) {
        Map<int, List<Map<String, dynamic>>> tempOrders = {};
        Map<int, String> tempStatus = {};

        for (var k in kots) {
          int tbl = k['table_no'];
          String st = k['status'];
          String id = k['id'];
          List items = jsonDecode(k['items'].toString());
          if (!tempOrders.containsKey(tbl)) tempOrders[tbl] = [];
          tempOrders[tbl]!.addAll(List<Map<String, dynamic>>.from(items));
          tempStatus[tbl] = st;

          if (st == 'ready' && !_spokenReadyKots.contains(id)) {
            _spokenReadyKots.add(id);
            VoiceService.speak("टेबल $tbl का ऑर्डर तैयार है");
          }
        }
        setState(() {
          liveTables = tempOrders;
          tableStatus = tempStatus;
        });
      }
    } catch (_) {}
  }

  void _openOrderSheet(int tableNum) {
    final Map<int, int> cart = {};
    final List<Map<String, dynamic>> existingItems = liveTables[tableNum] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBState) {
          double newTotal = 0;
          cart.forEach((id, qty) {
            final it = menu.firstWhere((e) => e['id'] == id, orElse: () => {'price': 0});
            newTotal += ((it['price'] ?? 0) * qty);
          });

          return Container(
            height: MediaQuery.of(context).size.height * 0.88,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('टेबल T-$tableNum ऑर्डर व री-ऑर्डर', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ]),
                const Divider(),
                if (existingItems.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('चालू खाना (पहले से ऑर्डर्ड):', style: TextStyle(fontWeight: FontWeight.bold)),
                        ...existingItems.map((e) => Text('• ${e['name']} x ${e['qty']}')),
                      ],
                    ),
                  ),
                  const Divider(),
                ],
                const Align(alignment: Alignment.centerLeft, child: Text('+ अतिरिक्त व्यंजन / रोटी जोड़ें:', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(
                  child: ListView.builder(
                    itemCount: menu.length,
                    itemBuilder: (c, idx) {
                      final item = menu[idx];
                      final qty = cart[item['id']] ?? 0;
                      return ListTile(
                        title: Text(item['name']),
                        subtitle: Text('₹${item['price']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (qty > 0) IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setBState(() => cart[item['id']] = qty - 1)),
                            if (qty > 0) Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => setBState(() => cart[item['id']] = qty + 1)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (existingItems.isNotEmpty)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                        onPressed: () async {
                          if (_socketConnected && _waiterSocket != null) {
                            try { _waiterSocket!.write(jsonEncode({'type': 'BILL_READY', 'table': tableNum}) + "\n"); } catch (_) {}
                          }
                          try {
                            await Supabase.instance.client.from('hotel_kots').update({'status': 'bill_ready'}).eq('store_code', widget.storeCode).eq('table_no', tableNum);
                          } catch (_) {}

                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('T-$tableNum का खाना पूरा (Done) हुआ! मास्टर को अलर्ट भेजा गया।')));
                          }
                          _syncFromCloud();
                        },
                        child: const Text('खाना पूरा (Done)', style: TextStyle(color: Colors.white)),
                      ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      onPressed: newTotal == 0 ? null : () async {
                        List<Map<String, dynamic>> newOrderItems = [];
                        cart.forEach((id, qty) {
                          if (qty > 0) {
                            final it = menu.firstWhere((e) => e['id'] == id);
                            newOrderItems.add({'name': it['name'], 'price': it['price'], 'qty': qty});
                          }
                        });

                        if (_socketConnected && _waiterSocket != null) {
                          try {
                            _waiterSocket!.write(jsonEncode({'type': 'NEW_KOT', 'table': tableNum, 'items': newOrderItems}) + "\n");
                          } catch (_) {}
                        }

                        try {
                          await Supabase.instance.client.from('hotel_kots').insert({
                            'store_code': widget.storeCode,
                            'table_no': tableNum,
                            'items': jsonEncode(newOrderItems),
                            'status': 'pending'
                          });
                        } catch (_) {}

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('T-$tableNum का KOT कुक को भेजा गया!'), backgroundColor: Colors.green));
                        }
                        _syncFromCloud();
                      },
                      child: const Text('KOT भेजें', style: TextStyle(color: Colors.white)),
                    )
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _manualIpDialog() {
    final ipCtrl = TextEditingController(text: _counterIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('काउंटर IP बदलें'),
        content: TextField(controller: ipCtrl, decoration: const InputDecoration(labelText: 'मास्टर का IP एड्रेस')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            onPressed: () async {
              setState(() => _counterIp = ipCtrl.text.trim());
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('saved_counter_ip', _counterIp);
              Navigator.pop(ctx);
              _connectToSocket();
            },
            child: const Text('सेव करें'),
          )
        ],
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('वेटर: ${widget.staffId}', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.orange,
          actions: [
            IconButton(icon: const Icon(Icons.settings, color: Colors.white), tooltip: 'काउंटर IP', onPressed: _manualIpDialog),
            IconButton(icon: const Icon(Icons.logout, color: Colors.white), tooltip: 'लॉगआउट', onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: _socketConnected ? Colors.green.shade700 : Colors.blueGrey,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_socketConnected ? '🟢 लोकल LAN कनेक्टेड ($_counterIp)' : '⚪ क्लाउड सिंक मोड (इंटरनेट चालू रखें)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const Text('ऑटो-सिंक चालू', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: widget.tables,
                itemBuilder: (ctx, i) {
                  int tbl = i + 1;
                  bool isOccupied = liveTables.containsKey(tbl) && liveTables[tbl]!.isNotEmpty;
                  String st = tableStatus[tbl] ?? '';
                  Color c = st == 'bill_ready' ? Colors.purple : (isOccupied ? Colors.red : Colors.green);
                  String txt = st == 'bill_ready' ? 'बिल तैयार' : (isOccupied ? 'रनिंग' : 'खाली');

                  return InkWell(
                    onTap: () => _openOrderSheet(tbl),
                    child: Container(
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text('T-$tbl\n$txt', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
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
// 6. कुक ऐप
// ==========================================
class FullCookApp extends StatefulWidget {
  final String storeCode;
  const FullCookApp({super.key, required this.storeCode});
  @override
  State<FullCookApp> createState() => _FullCookAppState();
}

class _FullCookAppState extends State<FullCookApp> {
  String _counterIp = '192.168.43.1';
  bool _socketConnected = false;
  Socket? _cookSocket;
  List<Map<String, dynamic>> kitchenOrders = [];
  List<String> presetRations = ['आटा', 'चावल', 'तेल', 'पनीर', 'शक्कर'];
  final Map<String, String> selectedRations = {};
  final _customItemCtrl = TextEditingController();
  final Set<String> _spokenOrderKots = {};
  Timer? _cookSyncTimer;

  @override
  void initState() {
    super.initState();
    _loadPresetRations();
    _initNetworkAndSync();
    _cookSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_socketConnected) _connectToSocket();
      _syncFromCloud();
    });
  }

  @override
  void dispose() {
    _cookSyncTimer?.cancel();
    _cookSocket?.destroy();
    super.dispose();
  }

  void _initNetworkAndSync() async {
    final prefs = await SharedPreferences.getInstance();
    _counterIp = prefs.getString('saved_counter_ip') ?? '192.168.43.1';
    _connectToSocket();
    _syncFromCloud();
  }

  void _connectToSocket() async {
    try {
      _cookSocket = await Socket.connect(_counterIp, 4040, timeout: const Duration(seconds: 2));
      if (mounted) setState(() => _socketConnected = true);

      _cookSocket!.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var l in lines) {
          if (l.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(l);
            if (msg['type'] == 'NEW_KOT' && mounted) {
              int tbl = msg['table'];
              setState(() => kitchenOrders.insert(0, Map<String, dynamic>.from(msg)));
              VoiceService.speak("टेबल $tbl पर नया ऑर्डर आया है");
            }
          } catch (_) {}
        }
      }, onDone: () => setState(() => _socketConnected = false), onError: (_) => setState(() => _socketConnected = false));
    } catch (_) {
      if (mounted && _socketConnected) setState(() => _socketConnected = false);
    }
  }

  void _loadPresetRations() async {
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getStringList('custom_preset_rations_${widget.storeCode}');
    if (local != null && local.isNotEmpty) {
      setState(() => presetRations = local);
    }
    try {
      final res = await Supabase.instance.client.from('hotel_preset_rations').select().eq('store_code', widget.storeCode);
      if (res != null) {
        for (var r in res) {
          if (!presetRations.contains(r['item_name'])) presetRations.add(r['item_name']);
        }
        await prefs.setStringList('custom_preset_rations_${widget.storeCode}', presetRations);
        setState(() {});
      }
    } catch (_) {}
  }

  void _syncFromCloud() async {
    try {
      final res = await Supabase.instance.client
          .from('hotel_kots')
          .select()
          .eq('store_code', widget.storeCode)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (res != null && mounted) {
        List<Map<String, dynamic>> loaded = [];
        for (var r in res) {
          String id = r['id'];
          int tbl = r['table_no'];
          loaded.add({'id': id, 'table': tbl, 'items': jsonDecode(r['items'].toString())});

          if (!_spokenOrderKots.contains(id)) {
            _spokenOrderKots.add(id);
            VoiceService.speak("टेबल $tbl पर नया ऑर्डर आया है");
          }
        }
        setState(() => kitchenOrders = loaded);
      }
    } catch (_) {}
  }

  void _markOrderReady(int index) async {
    final order = kitchenOrders[index];
    setState(() => kitchenOrders.removeAt(index));

    if (_socketConnected && _cookSocket != null) {
      try { _cookSocket!.write(jsonEncode({'type': 'ORDER_READY', 'table': order['table']}) + "\n"); } catch (_) {}
    }

    if (order['id'] != null) {
      try {
        await Supabase.instance.client.from('hotel_kots').update({'status': 'ready'}).eq('id', order['id']);
      } catch (_) {}
    }
  }

  void _addPermanentRationItem() async {
    final name = _customItemCtrl.text.trim();
    if (name.isEmpty) return;

    if (!presetRations.contains(name)) {
      setState(() => presetRations.add(name));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('custom_preset_rations_${widget.storeCode}', presetRations);

      try {
        await Supabase.instance.client.from('hotel_preset_rations').insert({'store_code': widget.storeCode, 'item_name': name});
      } catch (_) {}
    }
    _customItemCtrl.clear();
  }

  void _sendRationDemand() async {
    if (selectedRations.isEmpty) return;

    try {
      List<Map<String, dynamic>> inserts = [];
      selectedRations.forEach((name, qty) {
        inserts.add({'store_code': widget.storeCode, 'item_name': name, 'quantity': qty, 'is_received': false});
      });

      await Supabase.instance.client.from('ration_demands').insert(inserts);

      if (_socketConnected && _cookSocket != null) {
        try { _cookSocket!.write(jsonEncode({'type': 'RATION_DEMAND'}) + "\n"); } catch (_) {}
      }

      setState(() => selectedRations.clear());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('राशन मांग मास्टर को भेज दी गई!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('कुक KDS', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.teal,
            actions: [
              IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout),
            ],
            bottom: const TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white54, tabs: [Tab(text: 'लाइव KOT'), Tab(text: 'राशन मांग')]),
          ),
          body: TabBarView(
            children: [
              Column(
                children: [
                  Container(
                    color: _socketConnected ? Colors.teal.shade800 : Colors.blueGrey,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_socketConnected ? '🟢 लोकल LAN कनेक्टेड' : '⚪ क्लाउड सिंक मोड', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        const Text('ऑटो-सिंक चालू', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: kitchenOrders.isEmpty
                        ? const Center(child: Text('कोई नया KOT नहीं है 👨‍🍳', style: TextStyle(fontSize: 16)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: kitchenOrders.length,
                            itemBuilder: (ctx, i) {
                              final ord = kitchenOrders[i];
                              final items = ord['items'] as List;
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('टेबल: T-${ord['table']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                                          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => _markOrderReady(i), child: const Text('तैयार ✓', style: TextStyle(color: Colors.white))),
                                        ],
                                      ),
                                      const Divider(),
                                      ...items.map((it) => Text('${it['name']} x ${it['qty']}', style: const TextStyle(fontSize: 16))),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _customItemCtrl, decoration: const InputDecoration(hintText: 'नया सामान (उदा. आलू, गोभी)'))),
                        IconButton(icon: const Icon(Icons.add_box, color: Colors.teal, size: 36), onPressed: _addPermanentRationItem),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: presetRations.length,
                        itemBuilder: (c, i) {
                          String itemName = presetRations[i];
                          bool isChecked = selectedRations.containsKey(itemName);
                          return ListTile(
                            leading: Checkbox(
                              value: isChecked,
                              onChanged: (val) {
                                setState(() {
                                  if (val!) selectedRations[itemName] = "1 KG";
                                  else selectedRations.remove(itemName);
                                });
                              },
                            ),
                            title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: isChecked
                                ? SizedBox(
                                    width: 80,
                                    child: TextField(
                                      onChanged: (v) => selectedRations[itemName] = v,
                                      decoration: const InputDecoration(hintText: '1 KG', border: OutlineInputBorder(), isDense: true),
                                    ),
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: _sendRationDemand, child: const Text('मांग मास्टर को भेजें', style: TextStyle(color: Colors.white, fontSize: 16))),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

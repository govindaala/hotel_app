// lib/main.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

// मॉडल्स व स्क्रीन फ़ाइलें
import 'models/restaurant_profile_model.dart';
import 'models/expense_model.dart';
import 'screens/admin/counter_sale_screen.dart';
import 'screens/admin/restaurant_settings_screen.dart';
import 'screens/admin/daily_expense_screen.dart';
import 'screens/waiter/waiter_menu_order_view.dart';
import 'screens/admin/counter_report_screen.dart';
import 'Data/Menu_data_source.dart';
import 'receipt_generator.dart';

// एडवांस्ड ERP, QR व लर्निंग मॉड्यूल्स
import 'screens/admin/partner_ledger_screen.dart';
import 'screens/admin/star_waiter_screen.dart';
import 'screens/admin/vendor_ration_screen.dart';
import 'screens/admin/qr_table_generator_screen.dart';
import 'services/kitchen_learning_service.dart';

const String supabaseUrl = "https://hbewnquphiwvxaxittrl.supabase.co";
const String supabaseKey = "sb_publishable_HA1-PBV55kEZet2GG_IBdg_HjUzfOxf";

const int currentAppVersionCode = 4;
const int tcpServerPort = 4040;
const int udpDiscoveryPort = 4042;

// =========================================================================
// 1. नॉन-ब्लॉकिंग वॉयस सर्विस
// =========================================================================
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
    try {
      if (!_isInit) await init();
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }
}

Future<void> checkForAppUpdates(BuildContext context) async {
  try {
    final response = await http
        .get(Uri.parse(
            'https://govindaala.github.io/hotel_app/app_config.json?t=${DateTime.now().millisecondsSinceEpoch}'))
        .timeout(const Duration(seconds: 4));

    if (response.statusCode != 200) return;

    final config = jsonDecode(response.body);
    final int latestVersionCode = config['version_code'] ?? 1;
    final String apkUrl = config['apk_url'] ?? '';
    final String updateMsg = config['update_message'] ??
        'होटल POS का नया वर्शन उपलब्ध है! कृपया अपडेट करें।';

    if (latestVersionCode > currentAppVersionCode &&
        apkUrl.isNotEmpty &&
        context.mounted) {
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
                    Text('ऐप अपडेट उपलब्ध है',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(updateMsg, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 16),
                    if (isDownloading) ...[
                      LinearProgressIndicator(
                          value: (double.tryParse(downloadProgress) ?? 0) / 100),
                      const SizedBox(height: 10),
                      Text('डाउनलोड हो रहा है: $downloadProgress%',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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
                          OtaUpdate()
                              .execute(apkUrl, destinationFilename: 'aala_pos.apk')
                              .listen((OtaEvent event) {
                            if (event.status == OtaStatus.DOWNLOADING) {
                              setDState(() => downloadProgress = event.value ?? "0");
                            } else if (event.status == OtaStatus.INSTALLING) {
                              Navigator.pop(ctx);
                            }
                          }, onError: (_) => setDState(() => isDownloading = false));
                        } catch (_) {
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

final List<Map<String, dynamic>> defaultHotelMenu = kRestaurantMenu
    .map((m) => {
          'id': m.id,
          'name': m.name,
          'price': m.price,
          'cat': m.category,
          'available': m.isAvailable,
        })
    .toList();

// =========================================================================
// 2. मुख्य मेन (main) - सुपर फ़ास्ट 1 सेकंड स्टार्टअप
// =========================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final results = await Future.wait([
    Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey)
        .catchError((_) => null as Supabase),
    SharedPreferences.getInstance(),
  ]);

  unawaited(VoiceService.init());

  final prefs = results[1] as SharedPreferences;
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  final String savedRole = prefs.getString('saved_role') ?? '';
  final String savedStoreCode = prefs.getString('saved_store_code') ?? '111';
  final String savedStaffId = prefs.getString('saved_staff_id') ?? '';
  final String savedHotelName = prefs.getString('saved_hotel_name') ?? 'होटल';
  final int savedTables = prefs.getInt('saved_tables') ?? 10;
  final String savedPartnerId = prefs.getString('saved_active_partner_id') ?? 'P1';
  final String savedPartnerName = prefs.getString('saved_active_partner_name') ?? 'पार्टनर';

  Widget initialScreen = const AppGateway();
  if (isLoggedIn) {
    if (savedRole == 'counter') {
      initialScreen = FullCounterApp(
        storeCode: savedStoreCode,
        hotelName: savedHotelName,
        tables: savedTables,
        activePartnerId: savedPartnerId,
        activePartnerName: savedPartnerName,
      );
    } else if (savedRole == 'waiter') {
      initialScreen = FullWaiterApp(
          storeCode: savedStoreCode, tables: savedTables, staffId: savedStaffId);
    } else if (savedRole == 'cook') {
      initialScreen = FullCookApp(storeCode: savedStoreCode);
    }
  }

  runApp(MaterialApp(
    home: initialScreen,
    debugShowCheckedModeBanner: false,
  ));
}

// =========================================================================
// 3. ऐप गेटवे
// =========================================================================
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
        title: const Text('AALA POS सिस्टम',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roleCard(context, '🖥️ मास्टर / ओनर (डबल लॉक)',
                'बिलिंग, मेन्यू, पार्टनर लेज़र व QR ऑर्डर', const Color(0xFF0F172A), 'counter'),
            const SizedBox(height: 18),
            _roleCard(context, '📱 वेटर मोड',
                'टेबल ऑर्डर, री-ऑर्डर व KOT', const Color(0xFFEA580C), 'waiter'),
            const SizedBox(height: 18),
            _roleCard(context, '👨‍🍳 कुक मोड (KDS)',
                'किचन KOT, राशन मांग व सेल्फ-लर्निंग', const Color(0xFF0D9488), 'cook'),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(BuildContext ctx, String title, String sub, Color col, String role) {
    return InkWell(
      onTap: () => Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => StaffAuthScreen(role: role))),
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

// =========================================================================
// 4. स्टाफ़ ऑथेंटिकेशन (डबल लॉक लॉगिन)
// =========================================================================
class StaffAuthScreen extends StatefulWidget {
  final String role;
  const StaffAuthScreen({super.key, required this.role});
  @override
  State<StaffAuthScreen> createState() => _StaffAuthScreenState();
}

class _StaffAuthScreenState extends State<StaffAuthScreen> {
  final _codeCtrl = TextEditingController(text: '111');
  final _storePinCtrl = TextEditingController();
  final _partnerPinCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  bool _loading = false;

  RawDatagramSocket? _discoverySocket;
  String _discoveredMasterIp = '';
  String _discoveredStoreCode = '';
  bool _masterFound = false;

  @override
  void initState() {
    super.initState();
    _startUdpDiscovery();
  }

  @override
  void dispose() {
    _discoverySocket?.close();
    _codeCtrl.dispose();
    _storePinCtrl.dispose();
    _partnerPinCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  void _startUdpDiscovery() async {
    try {
      _discoverySocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, udpDiscoveryPort,
          reuseAddress: true, reusePort: true);
      _discoverySocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _discoverySocket?.receive();
          if (datagram != null) {
            try {
              final payload = utf8.decode(datagram.data);
              final data = jsonDecode(payload);
              if (data['app'] == 'AALA_POS' && mounted) {
                final String sCode = data['store_code'] ?? '';
                final String mIp = data['master_ip'] ?? '';
                setState(() {
                  _discoveredMasterIp = mIp;
                  _discoveredStoreCode = sCode;
                  _masterFound = true;
                  if (_codeCtrl.text.isEmpty || _codeCtrl.text == '111') {
                    _codeCtrl.text = sCode;
                  }
                });
              }
            } catch (_) {}
          }
        }
      });
    } catch (_) {}
  }

  void _verify() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया स्टोर कोड दर्ज करें!')));
      return;
    }

    if (widget.role == 'counter') {
      final storePin = _storePinCtrl.text.trim();
      final partnerPin = _partnerPinCtrl.text.trim();

      if (storePin.isEmpty || partnerPin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('कृपया स्टोर पिन और पार्टनर पिन दोनों भरें!')));
        return;
      }

      setState(() => _loading = true);

      try {
        final restoRes = await Supabase.instance.client
            .from('restaurants')
            .select('*')
            .eq('store_code', code)
            .maybeSingle();

        final cachedMasterPin = prefs.getString('cached_master_pin_$code');
        final bool isStorePinValid = (restoRes != null &&
                (restoRes['master_pin'] == storePin || restoRes['pin'] == storePin)) ||
            (cachedMasterPin == storePin);

        if (!isStorePinValid) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ ताला 1 विफल: गलत स्टोर कोड या स्टोर मास्टर पिन!')));
          return;
        }

        final partnerRes = await Supabase.instance.client
            .from('restaurant_partners')
            .select('*')
            .eq('store_code', code)
            .eq('login_pin', partnerPin)
            .eq('is_active', true)
            .maybeSingle();

        String activePartnerId = 'P1';
        String activePartnerName = 'पार्टनर';

        if (partnerRes != null) {
          activePartnerId = partnerRes['partner_id'] ?? 'P1';
          activePartnerName = partnerRes['partner_name'] ?? 'पार्टनर';
        } else if (partnerPin == storePin) {
          activePartnerId = 'SUPER_ADMIN';
          activePartnerName = 'मास्टर एडमिन';
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ ताला 2 विफल: अमान्य पार्टनर पिन!')));
          return;
        }

        await prefs.setBool('is_logged_in', true);
        await prefs.setString('saved_role', 'counter');
        await prefs.setString('saved_store_code', code);
        await prefs.setString('saved_hotel_name', restoRes?['name'] ?? 'होटल');
        await prefs.setInt('saved_tables', restoRes?['total_tables'] ?? 10);
        await prefs.setString('cached_master_pin_$code', storePin);

        await prefs.setString('saved_active_partner_id', activePartnerId);
        await prefs.setString('saved_active_partner_name', activePartnerName);

        VoiceService.speak("होटल लॉगिन सफल। स्वागत है $activePartnerName");

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => FullCounterApp(
                storeCode: code,
                hotelName: restoRes?['name'] ?? 'होटल',
                tables: restoRes?['total_tables'] ?? 10,
                activePartnerId: activePartnerId,
                activePartnerName: activePartnerName,
              ),
            ),
            (r) => false,
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final staffId = _idCtrl.text.trim();
    final pin = _partnerPinCtrl.text.trim();

    if (staffId.isEmpty || pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कृपया स्टाफ़ ID और पिन दोनों भरें!')));
      return;
    }

    setState(() => _loading = true);

    final String targetIp = _discoveredMasterIp.isNotEmpty
        ? _discoveredMasterIp
        : (prefs.getString('saved_counter_ip') ?? '192.168.43.1');

    bool authSuccess = false;
    String hotelName = 'होटल';
    int tableCount = 10;

    try {
      final socket = await Socket.connect(targetIp, tcpServerPort, timeout: const Duration(milliseconds: 1500));
      final completer = Completer<bool>();
      final authPacket = jsonEncode({
        'type': 'AUTH_STAFF',
        'role': widget.role,
        'store_code': code,
        'staff_id': staffId,
        'pin': pin,
      });

      socket.write(authPacket + "\n");
      await socket.flush();

      socket.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var l in lines) {
          if (l.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(l);
            if (msg['type'] == 'AUTH_RESULT') {
              if (msg['success'] == true) {
                hotelName = msg['hotel_name'] ?? 'होटल';
                tableCount = msg['tables'] ?? 10;
                if (!completer.isCompleted) completer.complete(true);
              } else {
                if (!completer.isCompleted) completer.complete(false);
              }
            }
          } catch (_) {}
        }
      }, onError: (_) => !completer.isCompleted ? completer.complete(false) : null,
         onDone: () => !completer.isCompleted ? completer.complete(false) : null);

      authSuccess = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => false);
      await socket.close();
    } catch (_) {
      authSuccess = false;
    }

    if (!authSuccess) {
      try {
        final res = await Supabase.instance.client
            .from('hotel_staff')
            .select()
            .eq('store_code', code)
            .eq('staff_id', staffId)
            .eq('pin', pin)
            .eq('role', widget.role)
            .maybeSingle();
        if (res != null) authSuccess = true;
      } catch (_) {}

      if (prefs.getString('cached_staff_pin_${code}_$staffId') == pin) {
        authSuccess = true;
      }
    }

    if (authSuccess) {
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('saved_role', widget.role);
      await prefs.setString('saved_store_code', code);
      await prefs.setString('saved_staff_id', staffId);
      await prefs.setString('saved_counter_ip', targetIp);
      await prefs.setString('cached_staff_pin_${code}_$staffId', pin);

      if (mounted) {
        if (widget.role == 'waiter') {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => FullWaiterApp(storeCode: code, tables: tableCount, staffId: staffId)),
              (r) => false);
        } else {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => FullCookApp(storeCode: code)),
              (r) => false);
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('स्टाफ ID या पिन गलत है!')));
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final bool isCounter = widget.role == 'counter';

    return Scaffold(
      appBar: AppBar(
        title: Text(isCounter ? 'काउंटर मास्टर लॉगिन' : '${widget.role} लॉगिन',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            if (!isCounter)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _masterFound ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _masterFound ? Colors.green : Colors.grey.shade400),
                ),
                child: Row(
                  children: [
                    Icon(_masterFound ? Icons.wifi_tethering : Icons.wifi_off,
                        color: _masterFound ? Colors.green : Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _masterFound ? '🟢 काउंटर कनेक्टेड: $_discoveredMasterIp' : '⚪ वाई-फ़ाई हॉटस्पॉट स्कैन...',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _masterFound ? Colors.green.shade900 : Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'स्टोर कोड (Store Code)',
                hintText: 'उदा. 111',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 16),

            if (isCounter) ...[
              TextField(
                controller: _storePinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '🔒 ताला 1: स्टोर मास्टर पिन (साझा पिन)',
                  hintText: 'उदा. 9999',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.domain_verification),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _partnerPinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '👤 ताला 2: व्यक्तिगत पार्टनर पिन',
                  hintText: 'उदा. 1212 (गोविंद) / 1580 (राहुल)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
            ],

            if (!isCounter) ...[
              TextField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  labelText: 'स्टाफ ID (उदा. W1, C1)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _partnerPinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '4-अंक स्टाफ पिन',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],

            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _verify,
                    child: const Text('प्रवेश करें (डबल लॉक अनलॉक)',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 5. काउंटर मास्टर ऐप
// =========================================================================
class FullCounterApp extends StatefulWidget {
  final String storeCode, hotelName;
  final int tables;
  final String activePartnerId;
  final String activePartnerName;

  const FullCounterApp({
    super.key,
    required this.storeCode,
    required this.hotelName,
    required this.tables,
    required this.activePartnerId,
    required this.activePartnerName,
  });

  @override
  State<FullCounterApp> createState() => _FullCounterAppState();
}

class _FullCounterAppState extends State<FullCounterApp> {
  int _currentTab = 0;
  String localIp = 'IP ढूँढ रहा है...';
  ServerSocket? server;
  final List<Socket> connectedClients = [];

  late String _currentPartnerId;
  late String _currentPartnerName;

  RawDatagramSocket? _udpBeaconSocket;
  Timer? _udpBeaconTimer;
  List<Map<String, dynamic>> _staffCache = [];

  List<Map<String, dynamic>> hotelMenu = [];
  Map<int, List<Map<String, dynamic>>> activeOrders = {};
  Map<int, String> tableStateMap = {};
  Map<int, String> tableWaiterMap = {};
  List<Map<String, dynamic>> rationDemands = [];
  final Set<int> _spokenBillTables = {};
  Timer? _cloudSyncTimer;

  bool _isPrinterConnected = false;
  RestaurantProfileModel? _restoProfile;

  Map<int, List<Map<String, dynamic>>> parcelOrders = {};
  int _parcelSeq = 1;

  double todayCashTotal = 0.0;
  double todayBankTotal = 0.0;
  double todayExpensesTotal = 0.0;

  List<Map<String, dynamic>> pendingQrOrders = [];
  RealtimeChannel? _qrOrderChannel;

  @override
  void initState() {
    super.initState();
    _currentPartnerId = widget.activePartnerId;
    _currentPartnerName = widget.activePartnerName;

    _loadMenu();
    _loadRestoProfile();
    _loadStaffCache();
    _startLocalSocketServer();
    _startUdpBeacon();
    _syncMasterData();
    _fetchDailyBalances();
    _checkPrinterStatus();
    _listenToLiveQrOrders();

    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _syncMasterData();
      _fetchDailyBalances();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => checkForAppUpdates(context));
  }

  @override
  void dispose() {
    _qrOrderChannel?.unsubscribe();
    _udpBeaconTimer?.cancel();
    _udpBeaconSocket?.close();
    _cloudSyncTimer?.cancel();
    server?.close();
    super.dispose();
  }

  void _listenToLiveQrOrders() {
    try {
      _qrOrderChannel = Supabase.instance.client
          .channel('public:qr_orders')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'qr_orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'store_code',
              value: widget.storeCode,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord['status'] == 'PENDING_APPROVAL') {
                setState(() => pendingQrOrders.insert(0, newRecord));
                final int tbl = newRecord['table_no'] ?? 0;
                VoiceService.speak("टेबल $tbl से नया ऑनलाइन QR ऑर्डर आया है");
              }
            },
          )
          .subscribe();

      _fetchPendingQrOrders();
    } catch (_) {}
  }

  Future<void> _fetchPendingQrOrders() async {
    try {
      final res = await Supabase.instance.client
          .from('qr_orders')
          .select('*')
          .eq('store_code', widget.storeCode)
          .eq('status', 'PENDING_APPROVAL')
          .order('created_at', ascending: false);

      if (res != null && mounted) {
        setState(() => pendingQrOrders = List<Map<String, dynamic>>.from(res));
      }
    } catch (_) {}
  }

  Future<void> _handleQrOrderAction(Map<String, dynamic> qrOrder, bool isAccepted) async {
    final String orderId = qrOrder['id'].toString();
    final int tbl = qrOrder['table_no'] ?? 0;

    dynamic rawItems = qrOrder['items'];
    List<Map<String, dynamic>> itemsList = [];
    if (rawItems is List) {
      itemsList = List<Map<String, dynamic>>.from(rawItems);
    } else if (rawItems is String) {
      itemsList = List<Map<String, dynamic>>.from(jsonDecode(rawItems));
    }

    if (isAccepted) {
      setState(() {
        activeOrders.putIfAbsent(tbl, () => []);
        activeOrders[tbl]!.addAll(itemsList);
        tableStateMap[tbl] = 'running';
        tableWaiterMap[tbl] = 'QR_CUSTOMER';
        pendingQrOrders.removeWhere((o) => o['id'] == orderId);
      });

      _broadcastLocal({
        'type': 'NEW_KOT',
        'table': tbl,
        'waiter_id': 'QR_CUSTOMER',
        'items': itemsList,
      });

      try {
        await Supabase.instance.client.from('hotel_kots').insert({
          'store_code': widget.storeCode,
          'table_no': tbl,
          'waiter_id': 'QR_CUSTOMER',
          'items': jsonEncode(itemsList),
          'status': 'pending',
          'source': 'QR_DIGITAL',
          'created_at': DateTime.now().toIso8601String(),
        });

        await Supabase.instance.client
            .from('qr_orders')
            .update({'status': 'ACCEPTED'})
            .eq('id', orderId);
      } catch (_) {}

      VoiceService.speak("टेबल $tbl का QR ऑर्डर स्वीकार किया गया");
    } else {
      setState(() => pendingQrOrders.removeWhere((o) => o['id'] == orderId));

      try {
        await Supabase.instance.client
            .from('qr_orders')
            .update({'status': 'REJECTED'})
            .eq('id', orderId);
      } catch (_) {}

      VoiceService.speak("टेबल $tbl का QR ऑर्डर निरस्त किया गया");
    }
  }

  void _openPendingQrOrdersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('🔔 पेंडिंग ग्राहक QR ऑर्डर्स',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(),
                if (pendingQrOrders.isEmpty)
                  const Expanded(child: Center(child: Text('कोई पेंडिंग QR ऑर्डर नहीं है')))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: pendingQrOrders.length,
                      itemBuilder: (context, i) {
                        final ord = pendingQrOrders[i];
                        final int tbl = ord['table_no'] ?? 0;
                        dynamic rawItems = ord['items'];
                        List items = (rawItems is List) ? rawItems : [];
                        if (rawItems is String) {
                          try { items = jsonDecode(rawItems); } catch (_) {}
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Table T-$tbl (QR Order)',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange)),
                                    Text('₹${ord['total_amount']}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                                  ],
                                ),
                                const Divider(),
                                ...items.map((it) => Text('• ${it['name']} x ${it['qty']}')),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                      onPressed: () {
                                        _handleQrOrderAction(ord, false);
                                        setSheetState(() {});
                                      },
                                      child: const Text('निरस्त करें'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                      onPressed: () {
                                        _handleQrOrderAction(ord, true);
                                        setSheetState(() {});
                                      },
                                      child: const Text('स्वीकार करें (KOT)', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPartnerHandoverDialog() {
    final pinCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.handshake_outlined, color: Colors.indigo),
            SizedBox(width: 8),
            Text('गल्ला हैंडओवर (Partner Switch)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('वर्तमान में लॉगिन: $_currentPartnerName', style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'आने वाले पार्टनर का 4-अंक पिन दर्ज करें',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () async {
              final enteredPin = pinCtrl.text.trim();
              final res = await Supabase.instance.client
                  .from('restaurant_partners')
                  .select('*')
                  .eq('store_code', widget.storeCode)
                  .eq('login_pin', enteredPin)
                  .eq('is_active', true)
                  .maybeSingle();

              if (res != null) {
                final newName = res['partner_name'] ?? 'Partner';
                final newId = res['partner_id'] ?? 'P';

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('saved_active_partner_id', newId);
                await prefs.setString('saved_active_partner_name', newName);

                setState(() {
                  _currentPartnerId = newId;
                  _currentPartnerName = newName;
                });

                Navigator.pop(ctx);
                VoiceService.speak("गल्ला हैंडओवर संपन्न। स्वागत है $newName");
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('❌ अमान्य पिन! यह किसी पार्टनर का पिन नहीं है।')));
              }
            },
            child: const Text('हैंडओवर करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openStaffManagementDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDState) {
          final waiters = _staffCache.where((s) => s['role'] == 'waiter').toList();
          final cooks = _staffCache.where((s) => s['role'] == 'cook').toList();

          void openAddStaffDialog() {
            final idCtrl = TextEditingController();
            final nameCtrl = TextEditingController();
            final pinCtrl = TextEditingController();
            String selectedRole = 'waiter';

            showDialog(
              context: dialogContext,
              builder: (addCtx) => StatefulBuilder(
                builder: (addCtx2, setRoleState) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  title: const Text('➕ नया स्टाफ़ जोड़ें', style: TextStyle(fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(labelText: 'पद (Role)', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'waiter', child: Text('📱 वेटर (Waiter)')),
                          DropdownMenuItem(value: 'cook', child: Text('👨‍🍳 कुक (Cook)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setRoleState(() => selectedRole = val);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: idCtrl,
                        decoration: InputDecoration(
                          labelText: 'स्टाफ़ ID',
                          hintText: selectedRole == 'waiter' ? 'उदा. W1, W2' : 'उदा. C1, C2',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'स्टाफ़ का नाम (उदा. राजू)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: pinCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        decoration: const InputDecoration(
                          labelText: '4-अंक लॉगिन पिन',
                          hintText: 'उदा. 1234',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.pin),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(addCtx), child: const Text('रद्द')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                      onPressed: () async {
                        final sId = idCtrl.text.trim().toUpperCase();
                        final sName = nameCtrl.text.trim();
                        final sPin = pinCtrl.text.trim();

                        if (sId.isEmpty || sPin.length != 4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('कृपया सही ID और 4-अंक पिन दर्ज करें!')),
                          );
                          return;
                        }

                        final newStaff = {
                          'store_code': widget.storeCode,
                          'staff_id': sId,
                          'name': sName.isNotEmpty ? sName : sId,
                          'role': selectedRole,
                          'pin': sPin,
                          'is_active': true,
                        };

                        try {
                          await Supabase.instance.client.from('hotel_staff').upsert(
                            newStaff,
                            onConflict: 'store_code,staff_id',
                          );

                          setState(() {
                            _staffCache.removeWhere((s) => s['staff_id'] == sId);
                            _staffCache.add(newStaff);
                          });

                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('saved_staff_cache_${widget.storeCode}', jsonEncode(_staffCache));
                          await prefs.setString('cached_staff_pin_${widget.storeCode}_$sId', sPin);

                          setDState(() {});
                          Navigator.pop(addCtx);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('✅ $sId ($selectedRole) सफलतापूर्वक जुड़ गया!'), backgroundColor: Colors.green),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
                        }
                      },
                      child: const Text('सेव करें', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.badge_outlined, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text('स्टाफ़ ID व पिन', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white, size: 16),
                  label: const Text('नया ID', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: openAddStaffDialog,
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: _staffCache.isEmpty
                  ? const Center(child: Text('कोई स्टाफ़ नहीं है। "+ नया ID" दबाकर जोड़ें।', style: TextStyle(color: Colors.grey)))
                  : ListView(
                      children: [
                        if (waiters.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('📱 वेटर स्टाफ़ (Waiters):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          ),
                          ...waiters.map((w) => Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.person, color: Colors.white, size: 18)),
                                  title: Text('${w['name']} (${w['staff_id']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('लॉगिन पिन: ${w['pin']}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () async {
                                      try {
                                        await Supabase.instance.client
                                            .from('hotel_staff')
                                            .delete()
                                            .eq('store_code', widget.storeCode)
                                            .eq('staff_id', w['staff_id']);

                                        setState(() {
                                          _staffCache.removeWhere((s) => s['staff_id'] == w['staff_id']);
                                        });

                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setString('saved_staff_cache_${widget.storeCode}', jsonEncode(_staffCache));
                                        setDState(() {});
                                      } catch (_) {}
                                    },
                                  ),
                                ),
                              )),
                          const Divider(),
                        ],
                        if (cooks.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text('👨‍🍳 कुक स्टाफ़ (Cooks):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                          ),
                          ...cooks.map((c) => Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.restaurant, color: Colors.white, size: 18)),
                                  title: Text('${c['name']} (${c['staff_id']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('लॉगिन पिन: ${c['pin']}'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () async {
                                      try {
                                        await Supabase.instance.client
                                            .from('hotel_staff')
                                            .delete()
                                            .eq('store_code', widget.storeCode)
                                            .eq('staff_id', c['staff_id']);

                                        setState(() {
                                          _staffCache.removeWhere((s) => s['staff_id'] == c['staff_id']);
                                        });

                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setString('saved_staff_cache_${widget.storeCode}', jsonEncode(_staffCache));
                                        setDState(() {});
                                      } catch (_) {}
                                    },
                                  ),
                                ),
                              )),
                        ],
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

  void _startUdpBeacon() async {
    try {
      _udpBeaconSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpBeaconSocket?.broadcastEnabled = true;

      _udpBeaconTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (localIp != 'IP ढूँढ रहा है...') {
          final beacon = jsonEncode({
            'app': 'AALA_POS',
            'store_code': widget.storeCode,
            'hotel_name': widget.hotelName,
            'master_ip': localIp,
            'port': tcpServerPort,
          });
          _udpBeaconSocket?.send(utf8.encode(beacon), InternetAddress('255.255.255.255'), udpDiscoveryPort);
        }
      });
    } catch (_) {}
  }

  void _loadStaffCache() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_staff_cache_${widget.storeCode}');
    if (saved != null) {
      _staffCache = List<Map<String, dynamic>>.from(jsonDecode(saved));
    }
    try {
      final res = await Supabase.instance.client.from('hotel_staff').select().eq('store_code', widget.storeCode);
      if (res != null) {
        _staffCache = List<Map<String, dynamic>>.from(res);
        await prefs.setString('saved_staff_cache_${widget.storeCode}', jsonEncode(_staffCache));
      }
    } catch (_) {}
  }

  void _loadRestoProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('saved_hotel_name') ?? widget.hotelName;
    final savedAddr = prefs.getString('saved_hotel_address') ?? '';
    final savedPhone = prefs.getString('saved_hotel_phone') ?? '';
    final savedUpi = prefs.getString('saved_hotel_upi') ?? '';

    if (mounted) {
      setState(() {
        _restoProfile = RestaurantProfileModel.fromMap({
          'store_code': widget.storeCode,
          'name': savedName,
          'phone': savedPhone,
          'address': savedAddr,
          'upi_id': savedUpi,
        });
      });
    }

    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select('*')
          .eq('store_code', widget.storeCode)
          .maybeSingle();

      if (res != null && mounted) {
        final profile = RestaurantProfileModel.fromMap(res);
        setState(() => _restoProfile = profile);
      }
    } catch (_) {}
  }

  void _checkPrinterStatus() async {
    try {
      final bool status = await PrintBluetoothThermal.connectionStatus;
      if (mounted) setState(() => _isPrinterConnected = status);
    } catch (_) {}
  }

  // ब्लूटूथ प्रिंटर पेयरिंग डायलॉग (d.macAdress फ़िक्स के साथ)
  void _openPrinterDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.print, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('ब्लूटूथ प्रिंटर सेटअप', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: FutureBuilder<List<BluetoothInfo>>(
            future: PrintBluetoothThermal.pairedBluetooths,
            builder: (c, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
              }
              final list = snap.data ?? [];
              if (list.isEmpty) {
                return const Text('कोई पेयर्ड ब्लूटूथ प्रिंटर नहीं मिला। कृपया पहले फ़ोन सेटिंग्स में प्रिंटर पेयर करें।');
              }
              return SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, idx) {
                    final d = list[idx];
                    return ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(d.name),
                      subtitle: Text(d.macAdress), // Single 'd' macAdress fix
                      onTap: () async {
                        final bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: d.macAdress); // Single 'd' macAdress fix
                        setState(() => _isPrinterConnected = connected);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(connected ? 'प्रिंटर कनेक्ट हो गया!' : 'कनेक्शन विफल!'),
                            backgroundColor: connected ? Colors.green : Colors.red,
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद करें')),
          ],
        ),
      ),
    );
  }

  void _fetchDailyBalances() async {
    try {
      final todayStart = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).toIso8601String();
      final res = await Supabase.instance.client
          .from('daily_expenses')
          .select()
          .eq('restaurant_id', widget.storeCode)
          .gte('created_at', todayStart);

      if (res != null && mounted) {
        double cash = 0.0;
        double bank = 0.0;
        double exp = 0.0;

        for (var row in res) {
          final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
          final title = (row['title'] ?? '').toString();
          final type = (row['type'] ?? '').toString().toUpperCase();

          if (type == 'CASH_IN' || type.contains('SALE') || type.contains('INCOME')) {
            if (title.contains('(UPI)') || title.contains('बैंक')) {
              bank += amt;
            } else {
              cash += amt;
            }
          } else {
            exp += amt;
          }
        }

        setState(() {
          todayCashTotal = cash;
          todayBankTotal = bank;
          todayExpensesTotal = exp;
        });
      }
    } catch (_) {}
  }

  void _startLocalSocketServer() async {
    try {
      final interfaces = await NetworkInterface.list()
          .timeout(const Duration(milliseconds: 1500), onTimeout: () => []);

      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (mounted) setState(() => localIp = addr.address);
            break;
          }
        }
      }

      server = await ServerSocket.bind(InternetAddress.anyIPv4, tcpServerPort);
      server!.listen((Socket client) {
        connectedClients.add(client);
        client.listen((data) {
          try {
            final lines = utf8.decode(data).split("\n");
            for (var line in lines) {
              if (line.trim().isEmpty) continue;
              final msg = jsonDecode(line);

              if (msg['type'] == 'AUTH_STAFF') {
                final sRole = msg['role'] ?? '';
                final sId = msg['staff_id'] ?? '';
                final sPin = msg['pin'] ?? '';

                bool matched = _staffCache.any((s) =>
                    s['staff_id'] == sId && s['pin'] == sPin && s['role'] == sRole);

                if (!matched && _staffCache.isEmpty) matched = true;

                client.write(jsonEncode({
                      'type': 'AUTH_RESULT',
                      'success': matched,
                      'hotel_name': widget.hotelName,
                      'tables': widget.tables,
                    }) + "\n");
              } else if (msg['type'] == 'GET_MENU') {
                client.write(jsonEncode({'type': 'MENU_DATA', 'menu': hotelMenu}) + "\n");
              } else if (msg['type'] == 'NEW_KOT') {
                int tbl = msg['table'];
                if (msg['waiter_id'] != null) {
                  tableWaiterMap[tbl] = msg['waiter_id'].toString();
                }
                setState(() {
                  if (tbl >= 900) {
                    parcelOrders.putIfAbsent(tbl, () => []);
                    parcelOrders[tbl]!.addAll(List<Map<String, dynamic>>.from(msg['items']));
                  } else {
                    activeOrders.putIfAbsent(tbl, () => []);
                    activeOrders[tbl]!.addAll(List<Map<String, dynamic>>.from(msg['items']));
                    tableStateMap[tbl] = 'running';
                  }
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
        },
            onDone: () => connectedClients.remove(client),
            onError: (_) => connectedClients.remove(client));
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
      if (res != null && mounted) {
        setState(() => rationDemands = List<Map<String, dynamic>>.from(res));
      }
    } catch (_) {}

    try {
      final kots = await Supabase.instance.client
          .from('hotel_kots')
          .select()
          .eq('store_code', widget.storeCode)
          .neq('status', 'settled');

      if (kots != null && mounted) {
        for (var k in kots) {
          int tbl = k['table_no'] ?? 0;
          String st = k['status'] ?? 'pending';

          if (k['waiter_id'] != null) {
            tableWaiterMap[tbl] = k['waiter_id'].toString();
          }

          dynamic rawItems = k['items'];
          List itemsList = (rawItems is List) ? rawItems : [];
          if (rawItems is String) {
            try { itemsList = jsonDecode(rawItems); } catch (_) {}
          }

          if (tbl >= 900) {
            parcelOrders.putIfAbsent(tbl, () => []);
            if (parcelOrders[tbl]!.isEmpty) {
              parcelOrders[tbl] = List<Map<String, dynamic>>.from(itemsList);
            }
          } else if (tbl > 0) {
            activeOrders.putIfAbsent(tbl, () => []);
            if (activeOrders[tbl]!.isEmpty) {
              activeOrders[tbl] = List<Map<String, dynamic>>.from(itemsList);
            }
            if (st == 'bill_ready') {
              tableStateMap[tbl] = 'bill_ready';
            } else if (!tableStateMap.containsKey(tbl)) {
              tableStateMap[tbl] = 'running';
            }

            if (st == 'bill_ready' && !_spokenBillTables.contains(tbl)) {
              _spokenBillTables.add(tbl);
              VoiceService.speak("टेबल $tbl का बिल तैयार है");
            }
          }
        }
        setState(() {});
      }
    } catch (_) {}
  }

  void _shiftTable(int fromTable) {
    List<int> emptyTables = [];
    for (int i = 1; i <= widget.tables; i++) {
      if (!activeOrders.containsKey(i) || activeOrders[i]!.isEmpty) {
        emptyTables.add(i);
      }
    }

    if (emptyTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ कोई भी अन्य टेबल खाली नहीं है!'), backgroundColor: Colors.orange),
      );
      return;
    }

    int targetTable = emptyTables.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.blue),
              const SizedBox(width: 8),
              Text('टेबल T-$fromTable को शिफ्ट करें',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('T-$fromTable का पूरा बिल किस खाली टेबल पर ट्रांसफर करना है?', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: targetTable,
                decoration: const InputDecoration(
                  labelText: 'नई खाली टेबल चुनें',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.table_restaurant),
                ),
                items: emptyTables
                    .map((t) => DropdownMenuItem(value: t, child: Text('T-$t (खाली)')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDState(() => targetTable = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);

                final itemsToMove = List<Map<String, dynamic>>.from(activeOrders[fromTable] ?? []);

                setState(() {
                  activeOrders[targetTable] = itemsToMove;
                  tableStateMap[targetTable] = tableStateMap[fromTable] ?? 'running';
                  if (tableWaiterMap.containsKey(fromTable)) {
                    tableWaiterMap[targetTable] = tableWaiterMap[fromTable]!;
                    tableWaiterMap.remove(fromTable);
                  }
                  activeOrders.remove(fromTable);
                  tableStateMap.remove(fromTable);
                  _spokenBillTables.remove(fromTable);
                });

                _broadcastLocal({
                  'type': 'TABLE_SHIFT',
                  'from_table': fromTable,
                  'to_table': targetTable,
                  'items': itemsToMove,
                });

                try {
                  await Supabase.instance.client
                      .from('hotel_kots')
                      .update({
                        'table_no': targetTable,
                        'table_name': 'T-$targetTable'
                      })
                      .eq('store_code', widget.storeCode)
                      .eq('table_no', fromTable)
                      .neq('status', 'settled');
                } catch (_) {}

                VoiceService.speak("टेबल $fromTable का ऑर्डर टेबल $targetTable पर शिफ्ट किया गया");
              },
              child: const Text('शिफ्ट करें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _openCounterTakeOrderSheet(int tbl) {
    final Map<dynamic, int> cart = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('🍽️ टेबल T-$tbl पर नया ऑर्डर लें',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: WaiterMenuOrderView(
                    cart: cart,
                    onAddItem: (item) {
                      setBState(() => cart[item.id] = (cart[item.id] ?? 0) + 1);
                    },
                    onRemoveItem: (item) {
                      setBState(() {
                        if (cart.containsKey(item.id)) {
                          if (cart[item.id]! > 1) {
                            cart[item.id] = cart[item.id]! - 1;
                          } else {
                            cart.remove(item.id);
                          }
                        }
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                    onPressed: cart.isEmpty
                        ? null
                        : () async {
                            List<Map<String, dynamic>> newOrderItems = [];
                            cart.forEach((id, qty) {
                              if (qty > 0) {
                                final it = kRestaurantMenu.firstWhere((e) => e.id == id);
                                newOrderItems.add({'name': it.name, 'price': it.price, 'qty': qty});
                              }
                            });

                            setState(() {
                              activeOrders[tbl] = newOrderItems;
                              tableStateMap[tbl] = 'running';
                              tableWaiterMap[tbl] = 'COUNTER';
                            });

                            _broadcastLocal({
                              'type': 'NEW_KOT',
                              'table': tbl,
                              'waiter_id': 'COUNTER',
                              'items': newOrderItems,
                            });

                            try {
                              await Supabase.instance.client.from('hotel_kots').insert({
                                'store_code': widget.storeCode,
                                'table_no': tbl,
                                'waiter_id': 'COUNTER',
                                'items': jsonEncode(newOrderItems),
                                'status': 'pending',
                                'source': 'COUNTER',
                                'created_at': DateTime.now().toIso8601String(),
                              });
                            } catch (_) {}

                            if (mounted) Navigator.pop(context);
                            VoiceService.speak("टेबल $tbl का KOT किचन भेज दिया गया");
                          },
                    child: const Text('किचन KOT भेजें ➔',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _settleBill(int tbl) {
    bool isParcel = tbl >= 900;
    List<Map<String, dynamic>> items = isParcel
        ? (parcelOrders[tbl] ?? [])
        : (activeOrders[tbl] ?? []);
    double subTotal = items.fold(0, (sum, it) => sum + (it['price'] * it['qty']));
    final pctCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          double enteredPct = double.tryParse(pctCtrl.text.trim()) ?? 0.0;
          if (enteredPct < 0) enteredPct = 0;
          if (enteredPct > 99) enteredPct = 99;

          final double discountAmt = (subTotal * enteredPct) / 100;
          final double finalPayable = (subTotal - discountAmt) < 0 ? 0.0 : (subTotal - discountAmt);

          void completeSettlement(String mode) async {
            Navigator.pop(context);

            final String currentWaiterId = tableWaiterMap[tbl] ?? 'SELF_COUNTER';
            final String generatedBillNo = 'BILL-${DateTime.now().millisecondsSinceEpoch % 100000}';

            try {
              await Supabase.instance.client
                  .from('hotel_kots')
                  .update({'status': 'settled'})
                  .eq('store_code', widget.storeCode)
                  .eq('table_no', tbl);
            } catch (_) {}

            try {
              final invoiceRes = await Supabase.instance.client.from('invoices').insert({
                'store_code': widget.storeCode,
                'bill_no': generatedBillNo,
                'table_no': tbl,
                'waiter_id': isParcel ? 'PARCEL' : currentWaiterId,
                'cashier_partner_id': _currentPartnerId,
                'subtotal': subTotal,
                'discount_amt': discountAmt,
                'final_amount': finalPayable,
                'payment_mode': mode,
                'created_at': DateTime.now().toIso8601String(),
              }).select('id').maybeSingle();

              if (invoiceRes != null && invoiceRes['id'] != null) {
                final String newInvoiceId = invoiceRes['id'].toString();
                final List<Map<String, dynamic>> itemsToInsert = items.map((it) {
                  final double p = (it['price'] as num?)?.toDouble() ?? 0.0;
                  final int q = (it['qty'] as num?)?.toInt() ?? 1;
                  return {
                    'invoice_id': newInvoiceId,
                    'item_name': it['name'] ?? '',
                    'category': it['category'] ?? it['cat'] ?? 'General',
                    'price': p,
                    'qty': q,
                    'total_price': p * q,
                  };
                }).toList();
                await Supabase.instance.client.from('invoice_items').insert(itemsToInsert);
              }
            } catch (_) {}

            try {
              final source = isParcel ? 'PARCEL P-${tbl - 900}' : 'Table T-$tbl';
              await Supabase.instance.client.from('daily_expenses').insert({
                'restaurant_id': widget.storeCode,
                'title': '$source Sale ($mode) [प्रभारी: $_currentPartnerName]',
                'amount': finalPayable,
                'type': 'CASH_IN',
                'created_at': DateTime.now().toIso8601String(),
              });
            } catch (_) {}

            if (isParcel) {
              setState(() => parcelOrders.remove(tbl));
            } else {
              _spokenBillTables.remove(tbl);
              setState(() {
                activeOrders.remove(tbl);
                tableStateMap.remove(tbl);
                tableWaiterMap.remove(tbl);
              });
            }

            _fetchDailyBalances();
            VoiceService.speak("बिल ₹${finalPayable.toInt()} $mode से प्राप्त हुआ");
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(isParcel ? '📦 पार्सल बिल (P-${tbl - 900})' : 'टेबल T-$tbl का बिल',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...items.map((it) => Text('• ${it['name']} x ${it['qty']} = ₹${(it['price'] * it['qty']).toInt()}')),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('उप-योग (Subtotal):', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      Text('₹${subTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: pctCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDState(() {}),
                    decoration: InputDecoration(
                      labelText: 'छूट प्रतिशत (1% - 99%)',
                      suffixText: '% OFF',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.percent, color: Colors.deepOrange),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('कुल देय राशि:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('₹${finalPayable.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                  const Divider(),
                  if (!isParcel)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.swap_horiz, size: 16),
                            label: const Text('शिफ्ट करें', style: TextStyle(fontSize: 12)),
                            onPressed: () => _shiftTable(tbl),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+ डिश जोड़ें', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _openCounterTakeOrderSheet(tbl);
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => completeSettlement('CASH'),
                child: const Text('💵 कैश मिला', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () => completeSettlement('UPI'),
                child: const Text('📱 UPI मिला', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openParcelOrderSheet() {
    final int parcelId = 900 + _parcelSeq;
    _parcelSeq++;

    final Map<dynamic, int> cart = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('📦 नया पार्सल ऑर्डर (P-${parcelId - 900})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: WaiterMenuOrderView(
                    onAddItem: (item) {
                      setBState(() => cart[item.id] = (cart[item.id] ?? 0) + 1);
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                    onPressed: cart.isEmpty
                        ? null
                        : () async {
                            List<Map<String, dynamic>> newOrderItems = [];
                            cart.forEach((id, qty) {
                              if (qty > 0) {
                                final it = kRestaurantMenu.firstWhere((e) => e.id == id);
                                newOrderItems.add({'name': it.name, 'price': it.price, 'qty': qty});
                              }
                            });

                            _broadcastLocal({'type': 'NEW_KOT', 'table': parcelId, 'items': newOrderItems});

                            try {
                              await Supabase.instance.client.from('hotel_kots').insert({
                                'store_code': widget.storeCode,
                                'table_no': parcelId,
                                'items': jsonEncode(newOrderItems),
                                'status': 'pending',
                                'source': 'PARCEL',
                                'created_at': DateTime.now().toIso8601String(),
                              });
                            } catch (_) {}

                            setState(() => parcelOrders[parcelId] = newOrderItems);
                            if (mounted) Navigator.pop(context);
                          },
                    child: const Text('पार्सल KOT भेजें ➔',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _openDishEditDialog([Map<String, dynamic>? dish]) {
    final nameCtrl = TextEditingController(text: dish?['name'] ?? '');
    final priceCtrl = TextEditingController(text: dish != null ? dish['price'].toString() : '');
    final catCtrl = TextEditingController(text: dish?['cat'] ?? 'सब्जी');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dish == null ? 'नई डिश जोड़ें' : 'डिश विवरण बदलें'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'डिश का नाम')),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'कीमत (₹)')),
            TextField(controller: catCtrl, decoration: const InputDecoration(labelText: 'श्रेणी (Category)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
              if (name.isEmpty || price <= 0) return;

              setState(() {
                if (dish == null) {
                  hotelMenu.add({
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'name': name,
                    'price': price,
                    'cat': catCtrl.text.trim(),
                    'available': true,
                  });
                } else {
                  dish['name'] = name;
                  dish['price'] = price;
                  dish['cat'] = catCtrl.text.trim();
                }
              });
              _saveMenu();
              Navigator.pop(ctx);
            },
            child: const Text('सुरक्षित करें'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double netCashInRegister = todayCashTotal - todayExpensesTotal;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.hotelName, style: const TextStyle(color: Colors.white, fontSize: 17)),
              Row(
                children: [
                  const Icon(Icons.verified_user, color: Colors.greenAccent, size: 13),
                  const SizedBox(width: 4),
                  Text('प्रभारी: $_currentPartnerName',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0F172A),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz, color: Colors.amberAccent, size: 18),
              label: const Text('हैंडओवर', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              onPressed: _showPartnerHandoverDialog,
            ),
            IconButton(
              icon: const Icon(Icons.badge_outlined, color: Colors.cyanAccent),
              tooltip: 'स्टाफ़ वेटर/कुक ID',
              onPressed: _openStaffManagementDialog,
            ),
            IconButton(
              icon: Icon(Icons.print, color: _isPrinterConnected ? Colors.greenAccent : Colors.white70),
              tooltip: 'प्रिंटर कनेक्ट करें',
              onPressed: _openPrinterDialog,
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_2, color: Colors.white),
              tooltip: 'टेबल QR स्टैंडी',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrTableGeneratorScreen(
                    storeCode: widget.storeCode,
                    hotelName: widget.hotelName,
                    totalTables: widget.tables,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined, color: Colors.lightGreenAccent),
              tooltip: 'स्मार्ट राशन',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VendorRationScreen(storeCode: widget.storeCode)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.emoji_events_outlined, color: Colors.amberAccent),
              tooltip: 'स्टार वेटर',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StarWaiterScreen(storeCode: widget.storeCode)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.handshake_outlined, color: Colors.cyanAccent),
              tooltip: 'पार्टनर लेज़र',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PartnerLedgerScreen(storeCode: widget.storeCode)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              tooltip: 'होटल सेटिंग्स',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RestaurantSettingsScreen(
                    storeCode: widget.storeCode,
                    initialProfile: _restoProfile,
                    onSave: (p) => setState(() => _restoProfile = p),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded, color: Colors.orangeAccent),
              tooltip: 'रिपोर्ट्स',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CounterReportsScreen(storeCode: widget.storeCode)),
              ),
            ),
            IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: _logout),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(26),
            child: Container(
              color: const Color(0xFF1E293B),
              child: Center(
                  child: Text('हॉटस्पॉट सर्वर IP: $localIp (ऑटो-डिस्कवरी सक्रिय)',
                      style: const TextStyle(color: Colors.yellowAccent, fontSize: 13))),
            ),
          ),
        ),

        body: _currentTab == 0
            ? _buildTablesView(netCashInRegister)
            : (_currentTab == 1 ? _buildMenuView() : _buildQuickPosView()),

        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (idx) => setState(() => _currentTab = idx),
          backgroundColor: const Color(0xFF0F172A),
          selectedItemColor: Colors.amber,
          unselectedItemColor: Colors.white60,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.table_restaurant), label: 'टेबल्स व पार्सल'),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'होटल मेन्यू'),
            BottomNavigationBarItem(icon: Icon(Icons.flash_on), label: 'क्विक बिलिंग (POS)'),
          ],
        ),
      ),
    );
  }

  Widget _buildTablesView(double netCashInRegister) {
    return Column(
      children: [
        if (pendingQrOrders.isNotEmpty)
          Container(
            color: Colors.amber.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.deepOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('🔔 ${pendingQrOrders.length} नए QR टेबल ऑर्डर मंज़ूरी हेतु पेंडिंग हैं!',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                  onPressed: _openPendingQrOrdersSheet,
                  child: const Text('जाँचें ➔', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade700, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💵 गल्ला (रोकड़)',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('₹${netCashInRegister.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade700, width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📱 बैंक (UPI)',
                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      Text('₹${todayBankTotal.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openParcelOrderSheet,
                  icon: const Icon(Icons.takeout_dining, color: Colors.white, size: 20),
                  label: const Text("📦 पार्सल ऑर्डर", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrangeAccent,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (parcelOrders.isNotEmpty)
          Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: parcelOrders.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    backgroundColor: Colors.deepOrange.shade100,
                    avatar: const Icon(Icons.shopping_bag, color: Colors.deepOrange, size: 18),
                    label: Text('P-${e.key - 900} (बिल करें)',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    onPressed: () => _settleBill(e.key),
                  ),
                );
              }).toList(),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: widget.tables,
            itemBuilder: (ctx, i) {
              int tbl = i + 1;
              String st = tableStateMap[tbl] ?? 'empty';
              Color c = st == 'bill_ready'
                  ? Colors.purple
                  : (st == 'running' ? Colors.red : Colors.green);
              String label = st == 'bill_ready' ? 'बिल तैयार 🔔' : (st == 'running' ? 'ऑर्डर चालू' : 'खाली (टैप करें)');

              return InkWell(
                onTap: () {
                  if (st == 'empty') {
                    _openCounterTakeOrderSheet(tbl);
                  } else {
                    _settleBill(tbl);
                  }
                },
                child: Container(
                  decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text('T-$tbl\n$label',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMenuView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('नई डिश जोड़ें', style: TextStyle(color: Colors.white)),
        onPressed: () => _openDishEditDialog(),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: hotelMenu.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, idx) {
          final it = hotelMenu[idx];
          final bool isAvail = it['available'] != false;

          return Card(
            child: ListTile(
              title: Text(it['name'], style: TextStyle(fontWeight: FontWeight.bold, decoration: isAvail ? null : TextDecoration.lineThrough)),
              subtitle: Text('श्रेणी: ${it['cat'] ?? 'General'}  •  भाव: ₹${it['price']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: isAvail,
                    activeColor: Colors.green,
                    onChanged: (val) {
                      setState(() => it['available'] = val);
                      _saveMenu();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _openDishEditDialog(it),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // काउंटर डायरेक्ट क्विक POS (Fix: Sirf storeCode pass kiya hai)
  Widget _buildQuickPosView() {
    return CounterSaleScreen(
      storeCode: widget.storeCode,
    );
  }
}

// =========================================================================
// 6. वेटर ऐप
// =========================================================================
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

    _waiterSyncTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_socketConnected) {
        _connectToSocket();
        _syncFromCloud();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => checkForAppUpdates(context));
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
      _waiterSocket = await Socket.connect(_counterIp, tcpServerPort, timeout: const Duration(seconds: 2));
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
      },
          onDone: () => setState(() => _socketConnected = false),
          onError: (_) => setState(() => _socketConnected = false));
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

          dynamic rawItems = k['items'];
          List items = (rawItems is List) ? rawItems : [];
          if (rawItems is String) {
            try { items = jsonDecode(rawItems); } catch (_) {}
          }

          tempOrders.putIfAbsent(tbl, () => []);
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
    final Map<dynamic, int> cart = {};
    final List<Map<String, dynamic>> existingItems = liveTables[tableNum] ?? [];
    double waiterDiscountAmt = 0.0;
    double waiterDiscountPct = 0.0;

    void askMasterPinForDiscount(StateSetter setBState, double currentTotal) {
      final pinCtrl = TextEditingController();
      showDialog(
        context: context,
        builder: (pCtx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.lock, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('काउंटर अनुमति आवश्यक', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('छूट हेतु काउंटर मास्टर अपना 4-अंक स्टोर पिन डालें:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'मास्टर पिन (Counter PIN)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(pCtx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                final enteredPin = pinCtrl.text.trim();
                final prefs = await SharedPreferences.getInstance();
                final savedMasterPin = prefs.getString('cached_master_pin_${widget.storeCode}');

                bool isAuthorized = (savedMasterPin != null && enteredPin == savedMasterPin);

                if (!isAuthorized) {
                  try {
                    final res = await Supabase.instance.client
                        .from('restaurants')
                        .select('master_pin, pin')
                        .eq('store_code', widget.storeCode)
                        .maybeSingle();
                    if (res != null && (res['master_pin'] == enteredPin || res['pin'] == enteredPin)) {
                      isAuthorized = true;
                      await prefs.setString('cached_master_pin_${widget.storeCode}', enteredPin);
                    }
                  } catch (_) {}
                }

                if (isAuthorized) {
                  Navigator.pop(pCtx);

                  final pctInputCtrl = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: const Text('छूट प्रतिशत (%) दर्ज करें', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      content: TextField(
                        controller: pctInputCtrl,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'प्रतिशत (1% से 99%)',
                          suffixText: '%',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('रद्द')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                          onPressed: () {
                            double val = double.tryParse(pctInputCtrl.text.trim()) ?? 0.0;
                            if (val > 99) val = 99;
                            if (val > 0) {
                              setBState(() {
                                waiterDiscountPct = val;
                                waiterDiscountAmt = (currentTotal * val) / 100;
                              });
                              Navigator.pop(dCtx);
                            }
                          },
                          child: const Text('लागू करें', style: TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('❌ गलत काउंटर पिन!'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('सत्यापित करें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBState) {
          final List<Map<String, dynamic>> draftItems = [];
          double draftTotal = 0.0;
          cart.forEach((id, qty) {
            if (qty > 0) {
              final it = kRestaurantMenu.firstWhere((e) => e.id == id,
                  orElse: () => MenuItemModel(id: id.toString(), name: 'Item', price: 0, category: 'अन्य'));
              draftItems.add({'id': id, 'name': it.name, 'price': it.price, 'qty': qty});
              draftTotal += (it.price * qty);
            }
          });

          final double netTotal = (draftTotal - waiterDiscountAmt) < 0 ? 0 : (draftTotal - waiterDiscountAmt);

          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('टेबल T-$tableNum ऑर्डर व री-ऑर्डर', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                if (existingItems.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('टेबल पर चालू खाना:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ...existingItems.map((e) => Text('• ${e['name']} x ${e['qty']}', style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Expanded(
                  child: WaiterMenuOrderView(
                    cart: cart,
                    onAddItem: (item) {
                      setBState(() => cart[item.id] = (cart[item.id] ?? 0) + 1);
                    },
                    onRemoveItem: (item) {
                      setBState(() {
                        if (cart.containsKey(item.id)) {
                          if (cart[item.id]! > 1) {
                            cart[item.id] = cart[item.id]! - 1;
                          } else {
                            cart.remove(item.id);
                          }
                        }
                      });
                    },
                  ),
                ),
                const Divider(thickness: 1.2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lock_outline, size: 15, color: Colors.redAccent),
                      label: Text(
                        waiterDiscountAmt > 0 ? '${waiterDiscountPct.toInt()}% छूट लागू' : 'छूट (% Off)',
                        style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => askMasterPinForDiscount(setBState, draftTotal),
                    ),
                    Text('कुल: ₹${netTotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (existingItems.isNotEmpty)
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.purple),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            if (_socketConnected && _waiterSocket != null) {
                              try {
                                _waiterSocket!.write(jsonEncode({'type': 'BILL_READY', 'table': tableNum}) + "\n");
                              } catch (_) {}
                            }
                            try {
                              await Supabase.instance.client
                                  .from('hotel_kots')
                                  .update({'status': 'bill_ready'})
                                  .eq('store_code', widget.storeCode)
                                  .eq('table_no', tableNum);
                            } catch (_) {}
                            if (mounted) Navigator.pop(context);
                            _syncFromCloud();
                          },
                          child: const Text('बिल तैयार', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    if (existingItems.isNotEmpty) const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        label: Text(
                          cart.isEmpty ? 'KOT भेजें' : 'KOT भेजें (${draftItems.length} व्यंजन)',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        onPressed: cart.isEmpty
                            ? null
                            : () async {
                                List<Map<String, dynamic>> newOrderItems = [];
                                cart.forEach((id, qty) {
                                  if (qty > 0) {
                                    final it = kRestaurantMenu.firstWhere((e) => e.id == id);
                                    newOrderItems.add({'name': it.name, 'price': it.price, 'qty': qty});
                                  }
                                });

                                if (_socketConnected && _waiterSocket != null) {
                                  try {
                                    _waiterSocket!.write(jsonEncode({
                                          'type': 'NEW_KOT',
                                          'table': tableNum,
                                          'waiter_id': widget.staffId,
                                          'items': newOrderItems,
                                        }) + "\n");
                                  } catch (_) {}
                                }

                                try {
                                  await Supabase.instance.client.from('hotel_kots').insert({
                                    'store_code': widget.storeCode,
                                    'table_no': tableNum,
                                    'waiter_id': widget.staffId,
                                    'items': jsonEncode(newOrderItems),
                                    'status': 'pending',
                                    'source': 'WAITER',
                                    'created_at': DateTime.now().toIso8601String(),
                                  });
                                } catch (_) {}

                                if (mounted) Navigator.pop(context);
                                _syncFromCloud();
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
    }
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
            IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: _socketConnected ? Colors.green.shade700 : Colors.blueGrey.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_socketConnected ? '🟢 हॉटस्पॉट कनेक्टेड' : '⚪ वाई-फ़ाई स्कैन...',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  const Text('लोकल LAN', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: widget.tables,
                itemBuilder: (ctx, i) {
                  int tbl = i + 1;
                  bool isOccupied = liveTables.containsKey(tbl) && liveTables[tbl]!.isNotEmpty;
                  String st = tableStatus[tbl] ?? '';
                  Color c = st == 'bill_ready'
                      ? Colors.purple
                      : (isOccupied ? Colors.red : Colors.green);
                  String txt = st == 'bill_ready' ? 'बिल तैयार' : (isOccupied ? 'रनिंग' : 'खाली');

                  return InkWell(
                    onTap: () => _openOrderSheet(tbl),
                    child: Container(
                      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
                      child: Center(
                          child: Text('T-$tbl\n$txt',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
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

// =========================================================================
// 7. कुक KDS
// =========================================================================
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
  final Set<String> _spokenOrderKots = {};
  Timer? _cookSyncTimer;

  @override
  void initState() {
    super.initState();
    _initNetworkAndSync();

    _cookSyncTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_socketConnected) {
        _connectToSocket();
        _syncFromCloud();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => checkForAppUpdates(context));
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
      _cookSocket = await Socket.connect(_counterIp, tcpServerPort, timeout: const Duration(seconds: 2));
      if (mounted) setState(() => _socketConnected = true);

      _cookSocket!.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var l in lines) {
          if (l.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(l);
            if (msg['type'] == 'NEW_KOT' && mounted) {
              int tbl = msg['table'];
              final newKotMap = Map<String, dynamic>.from(msg);
              newKotMap['created_at'] = DateTime.now().toIso8601String();
              setState(() => kitchenOrders.insert(0, newKotMap));

              if (tbl >= 900) {
                VoiceService.speak("नया पार्सल ऑर्डर आया है");
              } else {
                VoiceService.speak("टेबल $tbl पर नया ऑर्डर आया है");
              }
            } else if (msg['type'] == 'TABLE_SHIFT' && mounted) {
              int fromTbl = msg['from_table'];
              int toTbl = msg['to_table'];
              setState(() {
                for (var ord in kitchenOrders) {
                  if (ord['table'] == fromTbl) {
                    ord['table'] = toTbl;
                  }
                }
              });
              VoiceService.speak("टेबल $fromTbl का ऑर्डर टेबल $toTbl पर शिफ्ट हुआ");
            }
          } catch (_) {}
        }
      },
          onDone: () => setState(() => _socketConnected = false),
          onError: (_) => setState(() => _socketConnected = false));
    } catch (_) {
      if (mounted && _socketConnected) setState(() => _socketConnected = false);
    }
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

          dynamic rawItems = r['items'];
          List items = (rawItems is List) ? rawItems : [];
          if (rawItems is String) {
            try { items = jsonDecode(rawItems); } catch (_) {}
          }

          loaded.add({
            'id': id,
            'table': tbl,
            'items': items,
            'created_at': r['created_at'],
          });

          if (!_spokenOrderKots.contains(id)) {
            _spokenOrderKots.add(id);
            if (tbl >= 900) {
              VoiceService.speak("नया पार्सल ऑर्डर आया है");
            } else {
              VoiceService.speak("टेबल $tbl पर नया ऑर्डर आया है");
            }
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
      try {
        _cookSocket!.write(jsonEncode({'type': 'ORDER_READY', 'table': order['table']}) + "\n");
      } catch (_) {}
    }

    if (order['id'] != null) {
      try {
        final kotId = order['id'].toString();
        final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '') ?? DateTime.now();

        await KitchenLearningService.recordKotCompletionAndLearn(
          storeCode: widget.storeCode,
          kotId: kotId,
          createdAt: createdAt,
        );
      } catch (_) {
        try {
          await Supabase.instance.client
              .from('hotel_kots')
              .update({'status': 'ready'}).eq('id', order['id']);
        } catch (_) {}
      }
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AppGateway()), (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('कुक KDS', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.teal,
          actions: [
            IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: _socketConnected ? Colors.teal.shade800 : Colors.blueGrey.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_socketConnected ? '🟢 हॉटस्पॉट सर्वर कनेक्टेड' : '⚪ वाई-फ़ाई स्कैन...',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
                        final bool isParcel = ord['table'] >= 900;

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isParcel ? '📦 पार्सल: P-${ord['table'] - 900}' : 'टेबल: T-${ord['table']}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isParcel ? Colors.deepOrange : Colors.teal,
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: isParcel ? Colors.deepOrange : Colors.teal),
                                      onPressed: () => _markOrderReady(i),
                                      child: const Text('तैयार ✓', style: TextStyle(color: Colors.white)),
                                    ),
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
      ),
    );
  }
}

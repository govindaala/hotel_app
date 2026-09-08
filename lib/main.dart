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

// =========================================================================
// 1. मॉड्यूल्स व स्क्रीन फ़ाइलें (Imports & Models)
// =========================================================================
import 'models/restaurant_profile_model.dart';
import 'models/expense_model.dart';
import 'screens/admin/counter_sale_screen.dart';
import 'screens/admin/restaurant_settings_screen.dart';
import 'screens/admin/daily_expense_screen.dart';
import 'screens/waiter/waiter_menu_order_view.dart';
import 'screens/admin/counter_report_screen.dart';
import 'Data/Menu_data_source.dart';
import 'receipt_generator.dart';

// =========================================================================
// 2. ग्लोबल कॉन्फ़िगरेशन व वर्शन (Global Constants)
// =========================================================================
const String supabaseUrl = "https://hbewnquphiwvxaxittrl.supabase.co";
const String supabaseKey = "sb_publishable_HA1-PBV55kEZet2GG_IBdg_HjUzfOxf";

const int currentAppVersionCode = 4;
const int tcpServerPort = 4040;
const int udpDiscoveryPort = 4042;

// =========================================================================
// 3. हिंदी वॉयस इंजन सर्विस (Text-to-Speech)
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
    await init();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }
}

// =========================================================================
// 4. बैकग्राउंड ऑटो-अपडेट चेकर व डाउनलोडर (OTA Update)
// =========================================================================
Future<void> checkForAppUpdates(BuildContext context) async {
  try {
    final response = await http.get(Uri.parse(
        'https://govindaala.github.io/hotel_app/app_config.json?t=${DateTime.now().millisecondsSinceEpoch}'));

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
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
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
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('बाद में')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
                      onPressed: () {
                        setDState(() => isDownloading = true);
                        try {
                          OtaUpdate()
                              .execute(apkUrl, destinationFilename: 'aala_pos.apk')
                              .listen(
                            (OtaEvent event) {
                              if (event.status == OtaStatus.DOWNLOADING) {
                                setDState(
                                    () => downloadProgress = event.value ?? "0");
                              } else if (event.status == OtaStatus.INSTALLING) {
                                Navigator.pop(ctx);
                              }
                            },
                            onError: (e) {
                              setDState(() => isDownloading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('डाउनलोड एरर: $e')));
                            },
                          );
                        } catch (e) {
                          setDState(() => isDownloading = false);
                        }
                      },
                      child: const Text('अपडेट करें',
                          style: TextStyle(color: Colors.white)),
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

// डिफ़ॉल्ट होटल मेन्यू मैपिंग
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
// 5. मुख्य मेन (main) फ़ंक्शन - ऐप की शुरुआत
// =========================================================================
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
      initialScreen = FullCounterApp(
          storeCode: savedStoreCode,
          hotelName: savedHotelName,
          tables: savedTables);
    } else if (savedRole == 'waiter') {
      initialScreen = FullWaiterApp(
          storeCode: savedStoreCode,
          tables: savedTables,
          staffId: savedStaffId);
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
// 6. ऐप गेटवे (रोल चयन स्क्रीन: काउंटर, वेटर, कुक)
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => checkForAppUpdates(context));
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
            _roleCard(context, '🖥️ मास्टर / ओनर',
                'बिलिंग, मेन्यू, राशन व स्टाफ़ प्रबंधन', const Color(0xFF0F172A), 'counter'),
            const SizedBox(height: 18),
            _roleCard(context, '📱 वेटर मोड',
                'टेबल ऑर्डर, री-ऑर्डर व KOT', const Color(0xFFEA580C), 'waiter'),
            const SizedBox(height: 18),
            _roleCard(context, '👨‍🍳 कुक मोड (KDS)',
                'लाइव किचन KOT व राशन मांग', const Color(0xFF0D9488), 'cook'),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(
      BuildContext ctx, String title, String sub, Color col, String role) {
    return InkWell(
      onTap: () => Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => StaffAuthScreen(role: role))),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration:
            BoxDecoration(color: col, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(sub,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      ),
    );
  }
}

// =========================================================================
// 7. स्टाफ़ ऑथेंटिकेशन (लोकल वाई-फ़ाई हॉटस्पॉट ऑटो-डिस्कवरी व पिन लॉगिन)
// =========================================================================
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
    final staffId = _idCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (code.isEmpty || pin.isEmpty || (widget.role != 'counter' && staffId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('कृपया सभी फ़ील्ड्स भरें!')));
      return;
    }

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    if (widget.role == 'counter') {
      try {
        Map<String, dynamic>? res;
        try {
          res = await Supabase.instance.client
              .from('restaurants')
              .select()
              .eq('store_code', code)
              .maybeSingle();
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
            Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => FullCounterApp(
                        storeCode: code,
                        hotelName: res?['name'] ?? 'होटल',
                        tables: res?['total_tables'] ?? 10)),
                (r) => false);
          }
          return;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('कोड या पिन गलत है!')));
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final String targetIp = _discoveredMasterIp.isNotEmpty
        ? _discoveredMasterIp
        : (prefs.getString('saved_counter_ip') ?? '192.168.43.1');

    bool authSuccess = false;
    String hotelName = 'होटल';
    int tableCount = 10;

    try {
      final socket = await Socket.connect(targetIp, tcpServerPort,
          timeout: const Duration(milliseconds: 1500));

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
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(false);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(false);
      });

      authSuccess = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
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
                  builder: (_) => FullWaiterApp(
                      storeCode: code, tables: tableCount, staffId: staffId)),
              (r) => false);
        } else {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => FullCookApp(storeCode: code)),
              (r) => false);
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('स्टाफ ID या पिन गलत है! (काउंटर से मिलान करें)')));
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.role} लॉगिन',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            if (widget.role != 'counter')
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _masterFound
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _masterFound ? Colors.green : Colors.grey.shade400),
                ),
                child: Row(
                  children: [
                    Icon(
                      _masterFound ? Icons.wifi_tethering : Icons.wifi_off,
                      color: _masterFound ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _masterFound
                            ? '🟢 काउंटर कनेक्टेड: $_discoveredMasterIp'
                            : '⚪ वाई-फ़ाई हॉटस्पॉट स्कैन हो रहा है...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _masterFound
                              ? Colors.green.shade900
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'स्टोर कोड (हॉटस्पॉट से ऑटो-फ़िल)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.store),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.role != 'counter') ...[
              TextField(
                controller: _idCtrl,
                decoration: const InputDecoration(
                  labelText: 'स्टाफ ID (उदा. W1, C1)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _pinCtrl,
              decoration: const InputDecoration(
                labelText: '4-अंक पिन कोड',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
              obscureText: true,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _verify,
                    child: const Text('लॉगिन करें',
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 8. काउंटर मास्टर ऐप (डैशबोर्ड, लोकल TCP सर्वर, बिलिंग व सेटलमेंट)
// =========================================================================
class FullCounterApp extends StatefulWidget {
  final String storeCode, hotelName;
  final int tables;
  const FullCounterApp(
      {super.key,
      required this.storeCode,
      required this.hotelName,
      required this.tables});
  @override
  State<FullCounterApp> createState() => _FullCounterAppState();
}

class _FullCounterAppState extends State<FullCounterApp> {
  int _currentTab = 0;
  String localIp = 'IP ढूँढ रहा है...';
  ServerSocket? server;
  final List<Socket> connectedClients = [];

  RawDatagramSocket? _udpBeaconSocket;
  Timer? _udpBeaconTimer;
  List<Map<String, dynamic>> _staffCache = [];

  List<Map<String, dynamic>> hotelMenu = [];
  Map<int, List<Map<String, dynamic>>> activeOrders = {};
  Map<int, String> tableStateMap = {};
  List<Map<String, dynamic>> rationDemands = [];
  final Set<int> _spokenBillTables = {};
  Timer? _cloudSyncTimer;

  bool _isPrinterConnected = false;
  String _connectedPrinterMac = '';
  RestaurantProfileModel? _restoProfile;

  Map<int, List<Map<String, dynamic>>> parcelOrders = {};
  double todayCashTotal = 0.0;
  double todayBankTotal = 0.0;
  double todayExpensesTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _loadRestoProfile();
    _loadStaffCache();
    _startLocalSocketServer();
    _startUdpBeacon();
    _syncMasterData();
    _fetchDailyBalances();
    _checkPrinterStatus();
    _cloudSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _syncMasterData();
      _fetchDailyBalances();
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => checkForAppUpdates(context));
  }

  @override
  void dispose() {
    _udpBeaconTimer?.cancel();
    _udpBeaconSocket?.close();
    _cloudSyncTimer?.cancel();
    server?.close();
    super.dispose();
  }

  // UDP बीकॉस ब्रॉडकास्ट (वेटर/कुक को काउंटर ढूँढने के लिए)
  void _startUdpBeacon() async {
    try {
      _udpBeaconSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
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
          _udpBeaconSocket?.send(
            utf8.encode(beacon),
            InternetAddress('255.255.255.255'),
            udpDiscoveryPort,
          );
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
      final res = await Supabase.instance.client
          .from('hotel_staff')
          .select()
          .eq('store_code', widget.storeCode);
      if (res != null) {
        _staffCache = List<Map<String, dynamic>>.from(res);
        await prefs.setString(
            'saved_staff_cache_${widget.storeCode}', jsonEncode(_staffCache));
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
          .select()
          .eq('store_code', widget.storeCode)
          .maybeSingle();

      if (res != null && mounted) {
        final profile = RestaurantProfileModel.fromMap(res);
        setState(() => _restoProfile = profile);
        if (profile.name.isNotEmpty) {
          await prefs.setString('saved_hotel_name', profile.name);
        }
        if (profile.address != null) {
          await prefs.setString('saved_hotel_address', profile.address!);
        }
        if (profile.phone != null) {
          await prefs.setString('saved_hotel_phone', profile.phone!);
        }
        if (profile.upiId != null) {
          await prefs.setString('saved_hotel_upi', profile.upiId!);
        }
      }
    } catch (_) {}
  }

  void _checkPrinterStatus() async {
    try {
      final bool status = await PrintBluetoothThermal.connectionStatus;
      if (mounted) setState(() => _isPrinterConnected = status);
    } catch (_) {}
  }

  void _fetchDailyBalances() async {
    try {
      final todayStart = DateTime(DateTime.now().year, DateTime.now().month,
              DateTime.now().day)
          .toIso8601String();
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
          final type = (row['type'] ?? '').toString();

          if (type == 'CASH_IN') {
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

  // लोकल TCP सॉकेट सर्वर (ऑफ़लाइन हॉटस्पॉट सिंक के लिए)
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
                    s['staff_id'] == sId &&
                    s['pin'] == sPin &&
                    s['role'] == sRole);

                if (!matched && _staffCache.isEmpty) {
                  matched = true;
                }

                client.write(jsonEncode({
                      'type': 'AUTH_RESULT',
                      'success': matched,
                      'hotel_name': widget.hotelName,
                      'tables': widget.tables,
                    }) +
                    "\n");
              } else if (msg['type'] == 'GET_MENU') {
                client.write(jsonEncode(
                        {'type': 'MENU_DATA', 'menu': hotelMenu}) +
                    "\n");
              } else if (msg['type'] == 'NEW_KOT') {
                int tbl = msg['table'];
                setState(() {
                  if (tbl >= 900) {
                    parcelOrders.putIfAbsent(tbl, () => []);
                    parcelOrders[tbl]!
                        .addAll(List<Map<String, dynamic>>.from(msg['items']));
                  } else {
                    activeOrders.putIfAbsent(tbl, () => []);
                    activeOrders[tbl]!
                        .addAll(List<Map<String, dynamic>>.from(msg['items']));
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
      setState(
          () => hotelMenu = List<Map<String, dynamic>>.from(jsonDecode(saved)));
    } else {
      setState(() => hotelMenu = List.from(defaultHotelMenu));
      await prefs.setString(
          'saved_menu_${widget.storeCode}', jsonEncode(hotelMenu));
    }
  }

  void _saveMenu() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_menu_${widget.storeCode}', jsonEncode(hotelMenu));
    _broadcastLocal({'type': 'MENU_DATA', 'menu': hotelMenu});
  }

  void _syncMasterData() async {
    try {
      final tenDaysAgo =
          DateTime.now().subtract(const Duration(days: 10)).toIso8601String();
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

          dynamic rawItems = k['items'];
          List itemsList = [];
          if (rawItems is List) {
            itemsList = rawItems;
          } else if (rawItems is String) {
            try {
              itemsList = jsonDecode(rawItems);
            } catch (_) {}
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

  void _toggleRationReceived(String id, bool currentStatus) async {
    try {
      await Supabase.instance.client
          .from('ration_demands')
          .update({'is_received': !currentStatus}).eq('id', id);
      _syncMasterData();
    } catch (_) {}
  }

  // राशन पर्ची PDF फ़िल्टर मॉडल
  void _openRationExportFilterModal() {
    if (rationDemands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('निर्यात के लिए कोई राशन डेटा उपलब्ध नहीं है')));
      return;
    }

    String selectedPeriod = '10_days';
    bool onlyPending = true;
    bool autoMergeQty = true;

    final Set<String> allItems =
        rationDemands.map((e) => e['item_name'].toString().trim()).toSet();
    final Set<String> selectedItems = Set.from(allItems);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.shopping_cart_checkout, color: Colors.amber),
                SizedBox(width: 8),
                Text('राशन PDF फ़िल्टर',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('समय सीमा चुनें:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('आज का'),
                          selected: selectedPeriod == 'today',
                          onSelected: (v) =>
                              setDState(() => selectedPeriod = 'today'),
                        ),
                        ChoiceChip(
                          label: const Text('पिछले 3 दिन'),
                          selected: selectedPeriod == '3_days',
                          onSelected: (v) =>
                              setDState(() => selectedPeriod = '3_days'),
                        ),
                        ChoiceChip(
                          label: const Text('पूरे 10 दिन'),
                          selected: selectedPeriod == '10_days',
                          onSelected: (v) =>
                              setDState(() => selectedPeriod = '10_days'),
                        ),
                      ],
                    ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('केवल पेंडिंग सामान (बाज़ार पर्ची)',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      value: onlyPending,
                      onChanged: (val) => setDState(() => onlyPending = val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('समान सामग्री मात्रा जोड़ें (Merge)',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      value: autoMergeQty,
                      onChanged: (val) => setDState(() => autoMergeQty = val),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('रद्द करें')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A)),
                icon: const Icon(Icons.download, color: Colors.white, size: 18),
                label: const Text('PDF तैयार करें',
                    style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _processAndExportRationPdf(selectedPeriod, onlyPending,
                      autoMergeQty, selectedItems);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // राशन पर्ची PDF जनरेटर (HD शुद्ध हिंदी)
  void _processAndExportRationPdf(String period, bool onlyPending,
      bool autoMergeQty, Set<String> selectedItems) async {
    DateTime cutoff = DateTime.now().subtract(const Duration(days: 10));
    if (period == 'today') {
      cutoff = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    } else if (period == '3_days') {
      cutoff = DateTime.now().subtract(const Duration(days: 3));
    }

    List<Map<String, dynamic>> filtered = rationDemands.where((r) {
      final String name = r['item_name'].toString().trim();
      if (!selectedItems.contains(name)) return false;
      if (onlyPending && r['is_received'] == true) return false;

      final createdAt = DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now();
      return createdAt.isAfter(cutoff) || createdAt.isAtSameMomentAs(cutoff);
    }).toList();

    if (filtered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('चुने गए फ़िल्टर के अनुसार कोई रिकॉर्ड नहीं मिला!')));
      return;
    }

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
              Text('${widget.hotelName} - राशन मांग सूची',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
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
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(imageBytes))),
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ration_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: '🛒 ${widget.hotelName} राशन पर्ची');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF एरर: $e')));
    }
  }

  void _openComprehensivePdfReportModal() {
    String selectedRange = 'today';
    DateTimeRange? customRange;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.analytics_outlined, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('वित्तीय व POS ऑडिट PDF',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('रिपोर्ट की समय सीमा चुनें:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('आज (Daily)'),
                        selected: selectedRange == 'today',
                        onSelected: (v) =>
                            setDState(() => selectedRange = 'today'),
                      ),
                      ChoiceChip(
                        label: const Text('साप्ताहिक (7 दिन)'),
                        selected: selectedRange == 'weekly',
                        onSelected: (v) =>
                            setDState(() => selectedRange = 'weekly'),
                      ),
                      ChoiceChip(
                        label: const Text('मासिक (30 दिन)'),
                        selected: selectedRange == 'monthly',
                        onSelected: (v) =>
                            setDState(() => selectedRange = 'monthly'),
                      ),
                      ChoiceChip(
                        label: const Text('वार्षिक (Yearly)'),
                        selected: selectedRange == 'yearly',
                        onSelected: (v) =>
                            setDState(() => selectedRange = 'yearly'),
                      ),
                      ChoiceChip(
                        label: const Text('कस्टम तारीख़ें'),
                        selected: selectedRange == 'custom',
                        onSelected: (v) async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setDState(() {
                              selectedRange = 'custom';
                              customRange = picked;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('रद्द')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A)),
                icon: const Icon(Icons.picture_as_pdf,
                    color: Colors.white, size: 18),
                label: const Text('A4 PDF शेयर करें',
                    style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _generateAndShareFinancialAuditPdf(
                      selectedRange, customRange);
                },
              ),
            ],
          );
        },
      ),
    );
  }
  // समरी कार्ड हेल्पर विजेट
  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // वित्तीय ऑडिट A4 लेज़र PDF रिपोर्ट (मल्टी-पेज एक्सेल लॉजिक)
  void _generateAndShareFinancialAuditPdf(String range, DateTimeRange? customRange) async {
    DateTime startCutoff;
    DateTime endCutoff;
    String rangeLabel = '';

    final now = DateTime.now();
    if (range == 'today') {
      startCutoff = DateTime(now.year, now.month, now.day, 0, 0, 0);
      endCutoff = DateTime(now.year, now.month, now.day, 23, 59, 59);
      rangeLabel = 'दैनिक लेज़र (${now.day}/${now.month}/${now.year})';
    } else if (range == 'weekly') {
      startCutoff = now.subtract(const Duration(days: 7));
      endCutoff = DateTime(now.year, now.month, now.day, 23, 59, 59);
      rangeLabel = 'साप्ताहिक ऑडिट (पिछले 7 दिन)';
    } else if (range == 'monthly') {
      startCutoff = now.subtract(const Duration(days: 30));
      endCutoff = DateTime(now.year, now.month, now.day, 23, 59, 59);
      rangeLabel = 'मासिक ऑडिट (पिछले 30 दिन)';
    } else if (range == 'yearly') {
      startCutoff = DateTime(now.year, 1, 1, 0, 0, 0);
      endCutoff = DateTime(now.year, 12, 31, 23, 59, 59);
      rangeLabel = 'वार्षिक ऑडिट (${now.year})';
    } else if (range == 'custom' && customRange != null) {
      startCutoff = DateTime(customRange.start.year, customRange.start.month, customRange.start.day, 0, 0, 0);
      endCutoff = DateTime(customRange.end.year, customRange.end.month, customRange.end.day, 23, 59, 59);
      rangeLabel = 'कस्टम अवधि (${startCutoff.day}/${startCutoff.month} से ${endCutoff.day}/${endCutoff.month})';
    } else {
      startCutoff = DateTime(now.year, now.month, now.day, 0, 0, 0);
      endCutoff = DateTime(now.year, now.month, now.day, 23, 59, 59);
      rangeLabel = 'दैनिक लेज़र रिपोर्ट';
    }

    try {
      final res = await Supabase.instance.client
          .from('daily_expenses')
          .select()
          .eq('restaurant_id', widget.storeCode)
          .gte('created_at', startCutoff.toUtc().toIso8601String())
          .lte('created_at', endCutoff.toUtc().toIso8601String())
          .order('created_at', ascending: false);

      if (res == null || (res as List).isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('चुनी गई अवधि में कोई रिकॉर्ड दर्ज नहीं है!')),
          );
        }
        return;
      }

      final List rows = res;
      double totalCashIn = 0.0;
      double totalBankUpi = 0.0;
      double totalExpenses = 0.0;

      for (var r in rows) {
        final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
        final title = (r['title'] ?? '').toString();
        final type = (r['type'] ?? '').toString();

        if (type == 'CASH_IN') {
          if (title.contains('(UPI)') || title.contains('बैंक')) {
            totalBankUpi += amt;
          } else {
            totalCashIn += amt;
          }
        } else {
          totalExpenses += amt;
        }
      }

      final double grossSales = totalCashIn + totalBankUpi;
      final double netCashInHand = totalCashIn - totalExpenses;

      String formatRowDate(String? iso) {
        if (iso == null || iso.isEmpty) return "-";
        final dt = DateTime.tryParse(iso)?.toLocal();
        if (dt == null) return iso;
        final d = "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
        final t = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
        return "$d\n$t";
      }

      // पेज ब्रेक लॉजिक: पहले पेज पर 10 रिकॉर्ड, बाकी पर 15 रिकॉर्ड
      final List<List<dynamic>> pagesData = [];
      const int firstPageLimit = 10;
      const int otherPageLimit = 15;

      if (rows.length <= firstPageLimit) {
        pagesData.add(rows);
      } else {
        pagesData.add(rows.sublist(0, firstPageLimit));
        int current = firstPageLimit;
        while (current < rows.length) {
          int end = (current + otherPageLimit < rows.length) ? current + otherPageLimit : rows.length;
          pagesData.add(rows.sublist(current, end));
          current = end;
        }
      }

      final pdf = pw.Document();
      final int totalPages = pagesData.length;

      for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final currentRows = pagesData[pageIndex];
        final bool isFirstPage = (pageIndex == 0);

        final Uint8List pageImage = await ScreenshotController().captureFromWidget(
          Material(
            color: Colors.white,
            child: Container(
              width: 780,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.hotelName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      Text(
                        'पेज ${pageIndex + 1} / $totalPages',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                    ],
                  ),
                  Text(
                    'वित्तीय लेज़र एवं ऑडिट रिपोर्ट | $rangeLabel',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  const Divider(color: Colors.black87, thickness: 1.2),

                  if (isFirstPage) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black26),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildSummaryItem('कुल बिक्री (Gross)', '₹${grossSales.toStringAsFixed(0)}', Colors.blue.shade900)),
                              Expanded(child: _buildSummaryItem('नकद (Cash)', '₹${totalCashIn.toStringAsFixed(0)}', Colors.green.shade800)),
                              Expanded(child: _buildSummaryItem('ऑनलाइन (UPI)', '₹${totalBankUpi.toStringAsFixed(0)}', Colors.purple.shade800)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1, color: Colors.black12),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildSummaryItem('कुल खर्च (Expense)', '₹${totalExpenses.toStringAsFixed(0)}', Colors.red.shade800)),
                              Expanded(child: _buildSummaryItem('रोकड़ गल्ला (Net Cash)', '₹${netCashInHand.toStringAsFixed(0)}', Colors.black)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    const SizedBox(height: 10),
                  ],

                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2.2),
                      1: FlexColumnWidth(4.8),
                      2: FlexColumnWidth(1.4),
                      3: FlexColumnWidth(1.6),
                    },
                    border: TableBorder.all(color: Colors.black38, width: 0.8),
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: Color(0xFFE2E8F0)),
                        children: [
                          Padding(padding: EdgeInsets.all(7), child: Text('दिनांक व समय', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))),
                          Padding(padding: EdgeInsets.all(7), child: Text('विवरण (Particulars)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))),
                          Padding(padding: EdgeInsets.all(7), child: Text('प्रकार', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))),
                          Padding(padding: EdgeInsets.all(7), child: Text('रकम (₹)', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black))),
                        ],
                      ),
                      ...currentRows.map<TableRow>((r) {
                        final bool isCashIn = (r['type'] ?? '') == 'CASH_IN';
                        return TableRow(
                          children: [
                            Padding(padding: const EdgeInsets.all(6), child: Text(formatRowDate(r['created_at']), style: const TextStyle(fontSize: 11, color: Colors.black87))),
                            Padding(padding: const EdgeInsets.all(6), child: Text('${r['title'] ?? '-'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black))),
                            Padding(padding: const EdgeInsets.all(6), child: Text(isCashIn ? 'जमा (IN)' : 'खर्च (OUT)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isCashIn ? Colors.green.shade800 : Colors.red.shade800))),
                            Padding(padding: const EdgeInsets.all(6), child: Text('₹${r['amount']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black))),
                          ],
                        );
                      }).toList(),
                    ],
                  ),

                  if (pageIndex == totalPages - 1) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('कुल रिकॉर्ड्स: ${rows.length} | रिपोर्ट समाप्त', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          delay: const Duration(milliseconds: 50),
          pixelRatio: 2.2,
        );

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(12),
            build: (pw.Context context) => pw.Center(child: pw.Image(pw.MemoryImage(pageImage))),
          ),
        );
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/Ledger_Audit_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)], text: '📊 ${widget.hotelName} लेज़र ऑडिट रिपोर्ट ($rangeLabel)');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('रिपोर्ट त्रुटि: $e')));
    }
  }



  // ब्लूटूथ प्रिंटर डायलॉग
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
                    ? const Text('कनेक्टेड ✓',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.bold))
                    : const Text('डिस्कनेक्टेड',
                        style: TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 250,
              child: scanning
                  ? const Center(child: CircularProgressIndicator())
                  : availablePrinters.isEmpty
                      ? const Center(
                          child: Text(
                              'कोई ब्लूटूथ प्रिंटर पेयर नहीं मिला!\nफ़ोन की ब्लूटूथ सेटिंग में जाकर प्रिंटर पेयर करें।',
                              textAlign: TextAlign.center))
                      : ListView.builder(
                          itemCount: availablePrinters.length,
                          itemBuilder: (context, index) {
                            final p = availablePrinters[index];
                            final bool isThis = _isPrinterConnected &&
                                _connectedPrinterMac == p.macAdress;

                            return ListTile(
                              leading: Icon(Icons.print,
                                  color: isThis ? Colors.green : Colors.grey),
                              title: Text(p.name.isNotEmpty
                                  ? p.name
                                  : 'थर्मल प्रिंटर'),
                              subtitle: Text(p.macAdress),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        isThis ? Colors.red : Colors.green),
                                onPressed: () async {
                                  if (isThis) {
                                    await PrintBluetoothThermal.disconnect;
                                    setState(
                                        () => _isPrinterConnected = false);
                                    setDState(() {});
                                  } else {
                                    final res =
                                        await PrintBluetoothThermal.connect(
                                            macPrinterAddress: p.macAdress);
                                    setState(() {
                                      _isPrinterConnected = res;
                                      if (res) {
                                        _connectedPrinterMac = p.macAdress;
                                      }
                                    });
                                    setDState(() {});
                                  }
                                },
                                child: Text(isThis ? 'हटाएँ' : 'कनेक्ट',
                                    style:
                                        const TextStyle(color: Colors.white)),
                              ),
                            );
                          },
                        ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('बंद करें')),
            ],
          );
        },
      ),
    );
  }

  // थर्मल प्रिंटर बिल प्रिंटिंग
  Future<void> _printBillReceipt(
      int tbl, List<Map<String, dynamic>> items, double total) async {
    final bool isConn = await PrintBluetoothThermal.connectionStatus;
    if (!isConn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('⚠️ प्रिंटर कनेक्ट नहीं है!'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      final String header =
          tbl >= 900 ? '📦 पार्सल पर्ची (Takeaway)' : 'टेबल: T-$tbl';
      bytes += generator.text(widget.hotelName,
          styles: const PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2));
      bytes += generator.text(header,
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.hr();

      for (var it in items) {
        bytes += generator.row([
          PosColumn(text: it['name'].toString(), width: 7),
          PosColumn(text: 'x${it['qty']}', width: 2),
          PosColumn(
              text: '${(it['price'] * it['qty']).toInt()}',
              width: 3,
              styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.hr();
      bytes += generator.text('कुल: Rs ${total.toStringAsFixed(2)}',
          styles: const PosStyles(bold: true, align: PosAlign.right));
      bytes += generator.feed(2);
      bytes += generator.cut();

      await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {}
  }

  // =========================================================================
  // WhatsApp रसीद PDF शेयरिंग (नेटिव PDF और ऑफलाइन QR के साथ)
  // =========================================================================
  Future<void> _shareReceiptPdf(
      int tbl, List<Map<String, dynamic>> items, double subTotal,
      {double discount = 0.0, double discountPct = 0.0}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int printerWidthMm = prefs.getInt('saved_printer_width_mm') ?? 80;

      final String rawUpi = _restoProfile?.upiId ?? '';
      final String upiId = rawUpi.isNotEmpty ? rawUpi : "";
      final String restoAddr = _restoProfile?.address ?? '';
      final String restoPhone = _restoProfile?.phone ?? '';
      final String gstNo = _restoProfile?.gstNumber ?? '';
      final String fssaiNo = _restoProfile?.fssaiNumber ?? '';
      final String reviewUrl = prefs.getString('saved_hotel_review_url') ?? '';

      final pdfDoc = await buildThermalReceiptPdf(
        hotelName: widget.hotelName,
        address: restoAddr,
        phone: restoPhone,
        fssai: fssaiNo,
        gstin: gstNo,
        tbl: tbl,
        items: items,
        subTotal: subTotal,
        discount: discount,
        discountPct: discountPct,
        upiId: upiId,
        reviewUrl: reviewUrl,
        paperWidthMm: printerWidthMm,
      );

      final output = await getTemporaryDirectory();
      final bool isParcel = tbl >= 900;
      final String receiptTitle = isParcel ? "पार्सल (P-${tbl - 900})" : "टेबल: T-$tbl";

      final file = File("${output.path}/Bill_${tbl}_${DateTime.now().millisecondsSinceEpoch}.pdf");
      await file.writeAsBytes(await pdfDoc.save());

      final double finalTotal = (subTotal - discount) < 0 ? 0.0 : (subTotal - discount);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "नमस्ते! ${widget.hotelName} से आपका बिल ($receiptTitle)। कुल राशि: ₹$finalTotal",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('शेयर एरर: $e')));
      }
    }
  }

  void _showStaffManagementDialog() {
    final staffIdCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String selectedRole = 'waiter';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) {
          return AlertDialog(
            title: const Text('👥 स्टाफ़ प्रबंधन'),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: TextField(
                              controller: staffIdCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'ID (W1, C1)', isDense: true))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextField(
                              controller: pinCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'पिन', isDense: true),
                              keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      DropdownButton<String>(
                        value: selectedRole,
                        items: const [
                          DropdownMenuItem(
                              value: 'waiter', child: Text('वेटर')),
                          DropdownMenuItem(
                              value: 'cook', child: Text('कुक')),
                        ],
                        onChanged: (v) => setDState(() => selectedRole = v!),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A)),
                        onPressed: () async {
                          final sid = staffIdCtrl.text.trim();
                          final spin = pinCtrl.text.trim();
                          if (sid.isEmpty || spin.isEmpty) return;

                          final newStaff = {
                            'store_code': widget.storeCode,
                            'staff_id': sid,
                            'pin': spin,
                            'role': selectedRole,
                          };

                          setState(() => _staffCache.add(newStaff));
                          setDState(() {});

                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                              'saved_staff_cache_${widget.storeCode}',
                              jsonEncode(_staffCache));

                          try {
                            await Supabase.instance.client
                                .from('hotel_staff')
                                .insert(newStaff);
                          } catch (_) {}

                          staffIdCtrl.clear();
                          pinCtrl.clear();
                        },
                        child: const Text('जोड़ें +',
                            style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _staffCache.length,
                      itemBuilder: (ctx, i) {
                        final s = _staffCache[i];
                        return ListTile(
                          dense: true,
                          title: Text('${s['staff_id']} (${s['role']})'),
                          subtitle: Text('पिन: ${s['pin']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              setState(() => _staffCache.removeAt(i));
                              setDState(() {});
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setString(
                                  'saved_staff_cache_${widget.storeCode}',
                                  jsonEncode(_staffCache));
                              try {
                                await Supabase.instance.client
                                    .from('hotel_staff')
                                    .delete()
                                    .eq('store_code', widget.storeCode)
                                    .eq('staff_id', s['staff_id']);
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
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('बंद करें')),
            ],
          );
        },
      ),
    );
  }

  void _openAddEditMenuModal([Map<String, dynamic>? itemToEdit, int? editIndex]) {
    final nameCtrl = TextEditingController(text: itemToEdit?['name'] ?? '');
    final priceCtrl = TextEditingController(
        text: itemToEdit != null ? itemToEdit['price'].toString() : '');
    String cat = itemToEdit?['cat'] ?? 'सब्जी';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (c, setDState) => AlertDialog(
          title: Text(itemToEdit == null ? 'नया व्यंजन जोड़ें' : 'व्यंजन एडिट करें'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'व्यंजन का नाम')),
              TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'कीमत ₹'),
                  keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A)),
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty) {
                  setState(() {
                    if (itemToEdit == null) {
                      hotelMenu.add({
                        'id': DateTime.now().millisecondsSinceEpoch,
                        'name': nameCtrl.text.trim(),
                        'price': double.parse(priceCtrl.text),
                        'cat': cat,
                        'available': true
                      });
                    } else {
                      hotelMenu[editIndex!] = {
                        'id': itemToEdit['id'],
                        'name': nameCtrl.text.trim(),
                        'price': double.parse(priceCtrl.text),
                        'cat': cat,
                        'available': itemToEdit['available'] ?? true
                      };
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

  // टेबल शिफ्टिंग / ट्रांसफर फ़ंक्शन
  void _shiftTable(int fromTable) {
    List<int> emptyTables = [];
    for (int i = 1; i <= widget.tables; i++) {
      if (!activeOrders.containsKey(i) || activeOrders[i]!.isEmpty) {
        emptyTables.add(i);
      }
    }

    if (emptyTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ कोई भी अन्य टेबल खाली नहीं है!'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    int targetTable = emptyTables.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz, color: Colors.blue),
              const SizedBox(width: 8),
              Text('टेबल T-$fromTable को शिफ्ट करें',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('T-$fromTable का पूरा बिल किस खाली टेबल पर ट्रांसफर करना है?',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: targetTable,
                decoration: const InputDecoration(
                  labelText: 'नई खाली टेबल चुनें',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.table_restaurant),
                ),
                items: emptyTables
                    .map((t) =>
                        DropdownMenuItem(value: t, child: Text('T-$t (खाली)')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDState(() => targetTable = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                Navigator.pop(ctx);
                Navigator.pop(context);

                final itemsToMove = List<Map<String, dynamic>>.from(
                    activeOrders[fromTable] ?? []);

                setState(() {
                  activeOrders[targetTable] = itemsToMove;
                  tableStateMap[targetTable] =
                      tableStateMap[fromTable] ?? 'running';
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

                VoiceService.speak(
                    "टेबल $fromTable का ऑर्डर टेबल $targetTable पर शिफ्ट किया गया");
              },
              child: const Text('शिफ्ट करें',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // काउंटर बिल सेटलमेंट (1% से 99% खुला डिस्काउंट इनपुट बॉक्स के साथ)
  // =========================================================================
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

            try {
              await Supabase.instance.client
                  .from('hotel_kots')
                  .update({'status': 'settled'})
                  .eq('store_code', widget.storeCode)
                  .eq('table_no', tbl);
            } catch (_) {}

            try {
              final source = isParcel ? 'PARCEL P-${tbl - 900}' : 'Table T-$tbl';
              await Supabase.instance.client.from('daily_expenses').insert({
                'restaurant_id': widget.storeCode,
                'title': '$source Sale ($mode)${enteredPct > 0 ? " [छूट $enteredPct% (-₹${discountAmt.toInt()})]" : ""}',
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
                      hintText: 'उदा. 10 या 25',
                      suffixText: '% OFF',
                      suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      prefixIcon: const Icon(Icons.percent, color: Colors.deepOrange),
                    ),
                  ),
                  if (enteredPct > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('छूट राशि ($enteredPct%):', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                        Text('-₹${discountAmt.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.print, size: 16),
                          label: const Text('प्रिंट पर्ची'),
                          onPressed: () => _printBillReceipt(tbl, items, finalPayable),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.share, size: 16, color: Colors.green),
                          label: const Text('WhatsApp'),
                          onPressed: () => _shareReceiptPdf(tbl, items, subTotal, discount: discountAmt, discountPct: enteredPct),
                        ),
                      ),
                    ],
                  ),
                  if (!isParcel)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                          label: const Text('टेबल शिफ्ट करें (Shift Table)'),
                          onPressed: () => _shiftTable(tbl),
                        ),
                      ),
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
    final int parcelId = 900 + (parcelOrders.length + 1);
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
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange)),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: WaiterMenuOrderView(
                    onAddItem: (item) {
                      setBState(() {
                        cart[item.id] = (cart[item.id] ?? 0) + 1;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange),
                    onPressed: cart.isEmpty
                        ? null
                        : () async {
                            List<Map<String, dynamic>> newOrderItems = [];
                            cart.forEach((id, qty) {
                              if (qty > 0) {
                                final it =
                                    kRestaurantMenu.firstWhere((e) => e.id == id);
                                newOrderItems.add({
                                  'name': it.name,
                                  'price': it.price,
                                  'qty': qty
                                });
                              }
                            });

                            final kotMsg = {
                              'type': 'NEW_KOT',
                              'table': parcelId,
                              'items': newOrderItems
                            };
                            _broadcastLocal(kotMsg);

                            try {
                              await Supabase.instance.client
                                  .from('hotel_kots')
                                  .insert({
                                'store_code': widget.storeCode,
                                'table_no': parcelId,
                                'items': jsonEncode(newOrderItems),
                                'status': 'pending'
                              });
                            } catch (_) {}

                            setState(() {
                              parcelOrders[parcelId] = newOrderItems;
                            });

                            if (mounted) Navigator.pop(context);
                          },
                    child: const Text('पार्सल KOT भेजें ➔',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  void _openQuickCounterSaleDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CounterSaleScreen(storeCode: widget.storeCode),
      ),
    );
    _fetchDailyBalances();

    if (result != null && result is Map) {
      final String tableStr = (result['table'] ?? '').toString();
      final List rawItems = (result['items'] as List?) ?? [];
      final int? tbl =
          int.tryParse(tableStr.replaceAll(RegExp(r'[^0-9]'), ''));

      if (tbl != null && rawItems.isNotEmpty) {
        final newItems = rawItems
            .map((v) => {
                  'name': v['name']?.toString() ?? '',
                  'qty': int.tryParse(v['qty'].toString()) ?? 1,
                  'price': double.tryParse(v['price'].toString()) ?? 0.0,
                })
            .toList();

        setState(() {
          activeOrders.putIfAbsent(tbl, () => []);
          activeOrders[tbl]!.addAll(newItems);
          tableStateMap[tbl] = 'running';
        });

        _broadcastLocal({'type': 'NEW_KOT', 'table': tbl, 'items': newItems});
      }
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AppGateway()),
          (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double netCashInRegister = todayCashTotal - todayExpensesTotal;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.hotelName} (मास्टर)',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF0F172A),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white),
              tooltip: 'दैनिक खर्च व गल्ला',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DailyExpenseScreen(
                    restaurantId: widget.storeCode,
                    totalCashSalesToday: todayCashTotal,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bar_chart_rounded, color: Colors.amber),
              tooltip: 'माय रिपोर्ट्स',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CounterReportsScreen(storeCode: widget.storeCode),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.analytics_outlined, color: Colors.cyanAccent),
              tooltip: 'लेज़र ऑडिट PDF',
              onPressed: _openComprehensivePdfReportModal,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              tooltip: 'होटल सेटिंग्स',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RestaurantSettingsScreen(
                    initialProfile: _restoProfile,
                    storeCode: widget.storeCode,
                    onSave: (updated) =>
                        setState(() => _restoProfile = updated),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.print,
                  color: _isPrinterConnected
                      ? Colors.greenAccent
                      : Colors.white),
              tooltip: 'प्रिंटर',
              onPressed: _showPrinterDialog,
            ),
            IconButton(
              icon: const Icon(Icons.group, color: Colors.orangeAccent),
              tooltip: 'स्टाफ़',
              onPressed: _showStaffManagementDialog,
            ),
            IconButton(
                icon: const Icon(Icons.shopping_cart_checkout,
                    color: Colors.amber),
                tooltip: 'राशन मांग पर्ची',
                onPressed: _openRationExportFilterModal),
            IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                tooltip: 'लॉगआउट',
                onPressed: _logout),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(26),
            child: Container(
              color: const Color(0xFF1E293B),
              child: Center(
                  child: Text(
                      'हॉटस्पॉट चालू रखें | सर्वर IP: $localIp (ऑटो-डिस्कवरी सक्रिय)',
                      style: const TextStyle(
                          color: Colors.yellowAccent, fontSize: 13))),
            ),
          ),
        ),
        body: [
          Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: const Color(0xFF0F172A),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.green.shade700, width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💵 गल्ला (रोकड़)',
                                style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                            Text('₹${netCashInRegister.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.blue.shade700, width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('📱 बैंक (UPI)',
                                style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                            Text('₹${todayBankTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
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
                        icon: const Icon(Icons.takeout_dining,
                            color: Colors.white, size: 20),
                        label: const Text("📦 पार्सल ऑर्डर",
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrangeAccent,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openQuickCounterSaleDialog,
                        icon: const Icon(Icons.flash_on,
                            color: Colors.amberAccent, size: 20),
                        label: const Text("⚡ काउंटर सेल",
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (parcelOrders.isNotEmpty)
                Container(
                  height: 52,
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: parcelOrders.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ActionChip(
                          backgroundColor: Colors.deepOrange.shade100,
                          avatar: const Icon(Icons.shopping_bag,
                              color: Colors.deepOrange, size: 18),
                          label: Text('P-${e.key - 900} (बिल करें)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange)),
                          onPressed: () => _settleBill(e.key),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10),
                  itemCount: widget.tables,
                  itemBuilder: (ctx, i) {
                    int tbl = i + 1;
                    String st = tableStateMap[tbl] ?? 'empty';
                    Color c = st == 'bill_ready'
                        ? Colors.purple
                        : (st == 'running' ? Colors.red : Colors.green);
                    String label = st == 'bill_ready'
                        ? 'बिल तैयार 🔔'
                        : (st == 'running' ? 'ऑर्डर चालू' : 'खाली');

                    return InkWell(
                      onTap: st != 'empty' ? () => _settleBill(tbl) : null,
                      child: Container(
                        decoration: BoxDecoration(
                            color: c, borderRadius: BorderRadius.circular(10)),
                        child: Center(
                            child: Text('T-$tbl\n$label',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold))),
                      ),
                    );
                  },
                ),
              ),
            ],
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
                  title: Text(item['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('₹${item['price']} (${item['cat']})'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _openAddEditMenuModal(item, i)),
                      IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
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
              ? const Center(
                  child: Text('10 दिनों में कोई राशन मांग दर्ज नहीं है'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rationDemands.length,
                  itemBuilder: (ctx, i) {
                    final r = rationDemands[i];
                    final bool isRec = r['is_received'] == true;
                    return Card(
                      color: isRec ? Colors.green.shade50 : Colors.white,
                      child: ListTile(
                        title: Text(r['item_name'],
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(
                            'मात्रा: ${r['quantity']} | दिनांक: ${(r['created_at'] ?? '').substring(0, 10)}'),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isRec ? Colors.green : Colors.orange),
                          onPressed: () =>
                              _toggleRationReceived(r['id'], isRec),
                          child: Text(isRec ? 'आ गया ✓' : 'पेंडिंग',
                              style: const TextStyle(color: Colors.white)),
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
            BottomNavigationBarItem(
                icon: Icon(Icons.table_bar), label: 'टेबल्स'),
            BottomNavigationBarItem(
                icon: Icon(Icons.menu_book), label: 'मेन्यू'),
            BottomNavigationBarItem(
                icon: Icon(Icons.shopping_basket),
                label: 'राशन रिकॉर्ड'),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// 9. वेटर ऐप (लोकल वाई-फ़ाई हॉटस्पॉट ऑटो-सिंक व ऑर्डरिंग)
// =========================================================================
class FullWaiterApp extends StatefulWidget {
  final String storeCode, staffId;
  final int tables;
  const FullWaiterApp(
      {super.key,
      required this.storeCode,
      required this.tables,
      required this.staffId});
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => checkForAppUpdates(context));
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
      _waiterSocket = await Socket.connect(_counterIp, tcpServerPort,
          timeout: const Duration(seconds: 2));
      if (mounted) setState(() => _socketConnected = true);
      _waiterSocket!.write(jsonEncode({'type': 'GET_MENU'}) + "\n");

      _waiterSocket!.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var l in lines) {
          if (l.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(l);
            if (msg['type'] == 'MENU_DATA' && mounted) {
              setState(() =>
                  menu = List<Map<String, dynamic>>.from(msg['menu']));
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
      if (mounted && _socketConnected) {
        setState(() => _socketConnected = false);
      }
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
          List items = [];
          if (rawItems is List) {
            items = rawItems;
          } else if (rawItems is String) {
            try {
              items = jsonDecode(rawItems);
            } catch (_) {}
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
              const Text('छूट लागू करने के लिए काउंटर मास्टर अपना 4-अंक पिन डालें:', style: TextStyle(fontSize: 13)),
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

                if (enteredPin == savedMasterPin || (savedMasterPin == null && enteredPin.length == 4)) {
                  Navigator.pop(pCtx);

                  final pctInputCtrl = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: const Text('छूट प्रतिशत (%) दर्ज करें', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: pctInputCtrl,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'प्रतिशत (1% से 99%)',
                              hintText: 'उदा. 10, 25 या 50',
                              suffixText: '%',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('✅ $val% छूट लागू कर दी गई (-₹${waiterDiscountAmt.toStringAsFixed(0)})'), backgroundColor: Colors.green),
                              );
                            }
                          },
                          child: const Text('लागू करें', style: TextStyle(color: Colors.white)),
                        )
                      ],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('❌ गलत काउंटर पिन! छूट की अनुमति नहीं है।'), backgroundColor: Colors.red),
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
                    Text('टेबल T-$tableNum ऑर्डर व री-ऑर्डर',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      setBState(() {
                        cart[item.id] = (cart[item.id] ?? 0) + 1;
                      });
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
                if (draftItems.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('🛒 KOT प्रिव्यू (सामग्री जाँचें व बदलें):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                            Text('₹${draftTotal.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 90),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: draftItems.length,
                            itemBuilder: (c, i) {
                              final it = draftItems[i];
                              return Row(
                                children: [
                                  Expanded(child: Text('${it['name']} x${it['qty']}', style: const TextStyle(fontSize: 13))),
                                  Text('₹${(it['price'] * it['qty']).toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    onPressed: () => setBState(() => cart.remove(it['id'])),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (waiterDiscountAmt > 0)
                          Text('छूट: -₹${waiterDiscountAmt.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                        Text('कुल: ₹${netTotal.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
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
                                          'items': newOrderItems,
                                        }) +
                                        "\n");
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

  void _manualIpDialog() {
    final ipCtrl = TextEditingController(text: _counterIp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('काउंटर IP बदलें'),
        content: TextField(
            controller: ipCtrl,
            decoration:
                const InputDecoration(labelText: 'मास्टर का IP एड्रेस')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
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
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AppGateway()),
          (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text('वेटर: ${widget.staffId}',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.orange,
          actions: [
            IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: _manualIpDialog),
            IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: _socketConnected
                  ? Colors.green.shade700
                  : Colors.blueGrey.shade800,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      _socketConnected
                          ? '🟢 वाई-फ़ाई हॉटस्पॉट कनेक्टेड ($_counterIp)'
                          : '⚪ सर्वर से जुड़ रहा है...',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  const Text('लोकल LAN',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10),
                itemCount: widget.tables,
                itemBuilder: (ctx, i) {
                  int tbl = i + 1;
                  bool isOccupied = liveTables.containsKey(tbl) &&
                      liveTables[tbl]!.isNotEmpty;
                  String st = tableStatus[tbl] ?? '';
                  Color c = st == 'bill_ready'
                      ? Colors.purple
                      : (isOccupied ? Colors.red : Colors.green);
                  String txt = st == 'bill_ready'
                      ? 'बिल तैयार'
                      : (isOccupied ? 'रनिंग' : 'खाली');

                  return InkWell(
                    onTap: () => _openOrderSheet(tbl),
                    child: Container(
                      decoration: BoxDecoration(
                          color: c, borderRadius: BorderRadius.circular(10)),
                      child: Center(
                          child: Text('T-$tbl\n$txt',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold))),
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
// 10. कुक KDS (किचन डिस्प्ले सिस्टम)
// =========================================================================
    // =========================================================================
// 10. कुक KDS (किचन डिस्प्ले सिस्टम - राशन मांग सहित)
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
  List<String> presetRations = ['आटा', 'चावल', 'तेल', 'पनीर', 'शक्कर', 'दूध', 'सब्जी', 'मसाले'];
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => checkForAppUpdates(context));
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
      _cookSocket = await Socket.connect(_counterIp, tcpServerPort,
          timeout: const Duration(seconds: 2));
      if (mounted) setState(() => _socketConnected = true);

      _cookSocket!.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var l in lines) {
          if (l.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(l);
            if (msg['type'] == 'NEW_KOT' && mounted) {
              int tbl = msg['table'];
              setState(() =>
                  kitchenOrders.insert(0, Map<String, dynamic>.from(msg)));
              if (tbl >= 900) {
                VoiceService.speak("नया पार्सल ऑर्डर आया है");
              } else {
                VoiceService.speak("टेबल $tbl पर नया ऑर्डर आया है");
              }
            }
          } catch (_) {}
        }
      },
          onDone: () => setState(() => _socketConnected = false),
          onError: (_) => setState(() => _socketConnected = false));
    } catch (_) {
      if (mounted && _socketConnected) {
        setState(() => _socketConnected = false);
      }
    }
  }

  void _loadPresetRations() async {
    final prefs = await SharedPreferences.getInstance();
    final local =
        prefs.getStringList('custom_preset_rations_${widget.storeCode}');
    if (local != null && local.isNotEmpty) {
      setState(() => presetRations = local);
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
          List items = [];
          if (rawItems is List) {
            items = rawItems;
          } else if (rawItems is String) {
            try {
              items = jsonDecode(rawItems);
            } catch (_) {}
          }

          loaded.add({'id': id, 'table': tbl, 'items': items});

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
        _cookSocket!.write(jsonEncode(
                {'type': 'ORDER_READY', 'table': order['table']}) +
            "\n");
      } catch (_) {}
    }

    if (order['id'] != null) {
      try {
        await Supabase.instance.client
            .from('hotel_kots')
            .update({'status': 'ready'}).eq('id', order['id']);
      } catch (_) {}
    }
  }

  // ==========================================
  // रसोई राशन मांग डायलॉग (Ration Demand Sheet)
  // ==========================================
  void _openRationDemandDialog() {
    final itemCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    String selectedPreset = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shopping_basket, color: Colors.orange, size: 24),
                        SizedBox(width: 8),
                        Text('रसोई राशन मांग (Kitchen Demand)',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 6),
                const Text('त्वरित चयन करें:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: presetRations.map((item) {
                    final isSel = selectedPreset == item;
                    return ChoiceChip(
                      label: Text(item),
                      selected: isSel,
                      selectedColor: Colors.orange.shade100,
                      onSelected: (val) {
                        setDState(() {
                          selectedPreset = val ? item : '';
                          if (val) itemCtrl.text = item;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: itemCtrl,
                  decoration: const InputDecoration(
                    labelText: 'सामग्री का नाम (उदा. दूध, आटा, टमाटर)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.fastfood_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'मात्रा व इकाई (उदा. 5 किलो, 2 पैकेट, 10 लीटर)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.send),
                  label: const Text('काउंटर पर मांग भेजें ➔',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final item = itemCtrl.text.trim();
                    final qty = qtyCtrl.text.trim();

                    if (item.isEmpty || qty.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('कृपया सामग्री और मात्रा दोनों भरें!')),
                      );
                      return;
                    }

                    Navigator.pop(ctx);
                    await _sendRationDemand(item, qty);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendRationDemand(String item, String qty) async {
    // 1. लोकल हॉटस्पॉट से काउंटर पर भेजना
    if (_socketConnected && _cookSocket != null) {
      try {
        _cookSocket!.write(jsonEncode({
          'type': 'RATION_DEMAND',
          'item_name': item,
          'quantity': qty,
        }) + "\n");
      } catch (_) {}
    }

    // 2. Supabase डेटाबेस में स्टोर करना (ताकि काउंटर की राशन पर्ची में जुड़ जाए)
    try {
      await Supabase.instance.client.from('ration_demands').insert({
        'store_code': widget.storeCode,
        'item_name': item,
        'quantity': qty,
        'is_received': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('मांग काउंटर पर भेज दी गई: $item ($qty)'),
          backgroundColor: Colors.green.shade800,
        ),
      );
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AppGateway()),
          (r) => false);
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
            // राशन मांग बटन
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.shopping_basket, size: 18),
              label: const Text('राशन मांग', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: _openRationDemandDialog,
            ),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: _logout),
          ],
        ),
        body: Column(
          children: [
            Container(
              color: _socketConnected
                  ? Colors.teal.shade800
                  : Colors.blueGrey.shade800,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      _socketConnected
                          ? '🟢 हॉटस्पॉट सर्वर कनेक्टेड'
                          : '⚪ सर्वर से जुड़ रहा है...',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                  const Text('ऑटो-सिंक चालू',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              child: kitchenOrders.isEmpty
                  ? const Center(
                      child: Text('कोई नया KOT नहीं है 👨‍🍳',
                          style: TextStyle(fontSize: 16)))
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isParcel
                                          ? '📦 पार्सल: P-${ord['table'] - 900}'
                                          : 'टेबल: T-${ord['table']}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isParcel
                                            ? Colors.deepOrange
                                            : Colors.teal,
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: isParcel
                                              ? Colors.deepOrange
                                              : Colors.teal),
                                      onPressed: () => _markOrderReady(i),
                                      child: const Text('तैयार ✓',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                ...items.map((it) => Text(
                                    '${it['name']} x ${it['qty']}',
                                    style: const TextStyle(fontSize: 16))),
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



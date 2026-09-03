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
import 'package:image/image.dart' as img;

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

// ==========================================
// 1. ऐप गेटवे (रोल चयन स्क्रीन)
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _roleCard(context, '🖥️ मास्टर / ओनर', 'बिलिंग, मेन्यू, स्टाफ व गल्ला', const Color(0xFF0F172A), 'counter'),
            const SizedBox(height: 18),
            _roleCard(context, '📱 वेटर मोड', 'टेबल ऑर्डर, सर्च व ऑटो-सिंक KOT', const Color(0xFFEA580C), 'waiter'),
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

// ==========================================
// 2. लॉगिन स्क्रीन
// ==========================================
class StaffAuthScreen extends StatefulWidget {
  final String role;
  const StaffAuthScreen({super.key, required this.role});
  @override
  State<StaffAuthScreen> createState() => _StaffAuthScreenState();
}

class _StaffAuthScreenState extends State<StaffAuthScreen> {
  final _codeCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
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
          if (res != null) {
            await prefs.setString('cached_master_pin_$code', res['master_pin'] ?? '');
            await prefs.setString('cached_hotel_name_$code', res['name'] ?? 'होटल');
            await prefs.setInt('cached_tables_$code', res['total_tables'] ?? 10);
          }
        } catch (_) {
          final cachedPin = prefs.getString('cached_master_pin_$code');
          if (cachedPin != null) {
            res = {
              'master_pin': cachedPin,
              'name': prefs.getString('cached_hotel_name_$code') ?? 'होटल',
              'total_tables': prefs.getInt('cached_tables_$code') ?? 10,
              'is_active': true
            };
          }
        }

        if (res != null && res['master_pin'] == pin && res['is_active'] != false) {
          await prefs.setString('saved_store_code', code);
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FullCounterApp(
              storeCode: code,
              hotelName: res?['name'] ?? 'होटल',
              tables: res?['total_tables'] ?? 10,
            )));
          }
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('कोड या पिन गलत है!')));
        }
      } else {
        bool isValid = false;
        try {
          final res = await Supabase.instance.client
              .from('hotel_staff')
              .select()
              .eq('store_code', code)
              .eq('staff_id', staffId)
              .eq('pin', pin)
              .eq('role', widget.role)
              .maybeSingle();

          if (res != null) {
            isValid = true;
            await prefs.setString('cached_staff_pin_${code}_${staffId}', pin);
          }
        } catch (_) {
          final cachedStaffPin = prefs.getString('cached_staff_pin_${code}_${staffId}');
          if (cachedStaffPin == pin) isValid = true;
        }

        if (isValid) {
          await prefs.setString('saved_store_code', code);
          if (mounted) {
            if (widget.role == 'waiter') {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FullWaiterApp(storeCode: code, tables: 10, staffId: staffId)));
            } else {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FullCookApp(storeCode: code)));
            }
          }
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('स्टाफ ID या पिन अमान्य है!')));
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == 'counter' ? 'मास्टर लॉगिन' : (widget.role == 'waiter' ? 'वेटर लॉगिन' : 'कुक लॉगिन'), style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'स्टोर कोड (उदा. 111)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            if (widget.role != 'counter') ...[
              TextField(controller: _idCtrl, decoration: const InputDecoration(labelText: 'स्टाफ ID (उदा. Waiter1)', border: OutlineInputBorder())),
              const SizedBox(height: 16),
            ],
            TextField(controller: _pinCtrl, decoration: const InputDecoration(labelText: 'पिन कोड', border: OutlineInputBorder()), obscureText: true, keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            _loading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                      onPressed: _verify,
                      child: const Text('लॉगिन करें', style: TextStyle(color: Colors.white, fontSize: 18)),
                    ),
                  )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 3. काउंटर मास्टर ऐप
// ==========================================
class FullCounterApp extends StatefulWidget {
  final String storeCode;
  final String hotelName;
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
  bool isPrinterConnected = false;

  List<Map<String, dynamic>> hotelMenu = [
    {'id': 1, 'name': 'दाल तड़का', 'price': 120.0, 'cat': 'सब्जी', 'available': true},
    {'id': 2, 'name': 'पनीर बटर मसाला', 'price': 180.0, 'cat': 'सब्जी', 'available': true},
    {'id': 3, 'name': 'तंदूरी रोटी', 'price': 12.0, 'cat': 'रोटी', 'available': true},
    {'id': 4, 'name': 'जीरा राइस', 'price': 100.0, 'cat': 'चावल', 'available': true},
  ];

  Map<int, List<Map<String, dynamic>>> activeOrders = {};
  List<Map<String, dynamic>> liveRationDemands = [];
  ScreenshotController screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _loadLocalMenu();
    _startServer();
    _checkPrinterStatus();
    _loadCloudRations();
  }

  void _loadLocalMenu() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('custom_menu_${widget.storeCode}');
    if (saved != null) setState(() => hotelMenu = List<Map<String, dynamic>>.from(jsonDecode(saved)));
  }

  void _saveLocalMenu() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_menu_${widget.storeCode}', jsonEncode(hotelMenu));
    _broadcastMenuUpdate();
  }

  void _loadCloudRations() async {
    try {
      final res = await Supabase.instance.client
          .from('ration_demands')
          .select()
          .eq('store_code', widget.storeCode)
          .order('created_at', { 'ascending': false });
      if (res != null && mounted) {
        setState(() {
          liveRationDemands = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (_) {}
  }

  void _checkPrinterStatus() async {
    try {
      final bool result = await PrintBluetoothThermal.connectionStatus;
      if (mounted) setState(() => isPrinterConnected = result);
    } catch (_) {}
  }

  void _startServer() async {
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
              } else if (msg['type'] == 'GET_RUNNING_TABLES') {
                client.write(jsonEncode({'type': 'RUNNING_TABLES', 'data': activeOrders}) + "\n");
              } else if (msg['type'] == 'NEW_KOT') {
                setState(() {
                  int tbl = msg['table'];
                  if (!activeOrders.containsKey(tbl)) activeOrders[tbl] = [];
                  activeOrders[tbl]!.addAll(List<Map<String, dynamic>>.from(msg['items']));
                });
                client.write(jsonEncode({'status': 'SUCCESS'}) + "\n");
                _broadcastToKitchen(msg);
              } else if (msg['type'] == 'RATION_DEMAND') {
                setState(() {
                  liveRationDemands.insertAll(0, List<Map<String, dynamic>>.from(msg['items']));
                });
              }
            }
          } catch (_) {}
        }, onDone: () => connectedClients.remove(client), onError: (_) => connectedClients.remove(client));
      });
    } catch (_) {}
  }

  void _broadcastMenuUpdate() {
    for (var c in List<Socket>.from(connectedClients)) {
      try {
        c.write(jsonEncode({'type': 'MENU_DATA', 'menu': hotelMenu}) + "\n");
      } catch (_) {
        connectedClients.remove(c);
      }
    }
  }

  void _broadcastToKitchen(dynamic data) {
    for (var c in List<Socket>.from(connectedClients)) {
      try {
        c.write(jsonEncode(data) + "\n");
      } catch (_) {
        connectedClients.remove(c);
      }
    }
  }

  void _openStaffManager() async {
    List<Map<String, dynamic>> staffList = [];
    final prefs = await SharedPreferences.getInstance();

    try {
      final res = await Supabase.instance.client
          .from('hotel_staff')
          .select()
          .eq('store_code', widget.storeCode);
      if (res != null) {
        staffList = List<Map<String, dynamic>>.from(res);
        await prefs.setString('cached_staff_list_${widget.storeCode}', jsonEncode(staffList));
      }
    } catch (_) {
      final cached = prefs.getString('cached_staff_list_${widget.storeCode}');
      if (cached != null) staffList = List<Map<String, dynamic>>.from(jsonDecode(cached));
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('👥 स्टाफ प्रबंधन (वेटर व कुक)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), minimumSize: const Size.fromHeight(45)),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('+ नया स्टाफ जोड़ें', style: TextStyle(color: Colors.white, fontSize: 16)),
                onPressed: () => _addNewStaffDialog(context, () async {
                  final cached = prefs.getString('cached_staff_list_${widget.storeCode}');
                  if (cached != null) setModalState(() => staffList = List<Map<String, dynamic>>.from(jsonDecode(cached)));
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: staffList.isEmpty
                    ? const Center(child: Text('कोई स्टाफ नहीं जुड़ा है। ऊपर बटन दबाकर जोड़ें।'))
                    : ListView.builder(
                        itemCount: staffList.length,
                        itemBuilder: (c, idx) {
                          final st = staffList[idx];
                          final bool isWaiter = st['role'] == 'waiter';
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isWaiter ? Colors.orange : Colors.teal,
                                child: Text(isWaiter ? 'W' : 'C', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              title: Text('${st['staff_id']} (${isWaiter ? 'वेटर' : 'कुक'})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('पिन: ${st['pin']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _editStaffPin(st['staff_id'], st['pin'], () async {
                                      final cached = prefs.getString('cached_staff_list_${widget.storeCode}');
                                      if (cached != null) setModalState(() => staffList = List<Map<String, dynamic>>.from(jsonDecode(cached)));
                                    }),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteStaff(st['staff_id'], () {
                                      setModalState(() => staffList.removeAt(idx));
                                    }),
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
        ),
      ),
    );
  }

  void _addNewStaffDialog(BuildContext ctx, VoidCallback onSuccess) {
    final idCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    String selectedRole = 'waiter';

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('नया स्टाफ जोड़ें'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: idCtrl, decoration: const InputDecoration(labelText: 'स्टाफ ID / नाम (उदा. Waiter1)')),
              TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: '4-अंकों का पिन'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedRole,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'waiter', child: Text('वेटर (Waiter)')),
                  DropdownMenuItem(value: 'cook', child: Text('कुक (Cook)')),
                ],
                onChanged: (v) => setDState(() => selectedRole = v!),
              )
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('रद्द')),
            ElevatedButton(
              onPressed: () async {
                final sId = idCtrl.text.trim();
                final sPin = pinCtrl.text.trim();
                if (sId.isEmpty || sPin.isEmpty) return;

                final prefs = await SharedPreferences.getInstance();
                try {
                  await Supabase.instance.client.from('hotel_staff').insert({
                    'store_code': widget.storeCode,
                    'staff_id': sId,
                    'pin': sPin,
                    'role': selectedRole,
                  });
                } catch (_) {}

                List<Map<String, dynamic>> current = [];
                final cached = prefs.getString('cached_staff_list_${widget.storeCode}');
                if (cached != null) current = List<Map<String, dynamic>>.from(jsonDecode(cached));
                current.add({'store_code': widget.storeCode, 'staff_id': sId, 'pin': sPin, 'role': selectedRole});
                await prefs.setString('cached_staff_list_${widget.storeCode}', jsonEncode(current));
                await prefs.setString('cached_staff_pin_${widget.storeCode}_$sId', sPin);

                Navigator.pop(dCtx);
                onSuccess();
              },
              child: const Text('सेव करें'),
            )
          ],
        ),
      ),
    );
  }

  void _editStaffPin(String staffId, String oldPin, VoidCallback onSuccess) {
    final pinCtrl = TextEditingController(text: oldPin);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('$staffId का पिन बदलें'),
        content: TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: 'नया 4-अंकों का पिन'), keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('रद्द')),
          ElevatedButton(
            onPressed: () async {
              final newPin = pinCtrl.text.trim();
              if (newPin.isEmpty) return;

              final prefs = await SharedPreferences.getInstance();
              try {
                await Supabase.instance.client
                    .from('hotel_staff')
                    .update({'pin': newPin})
                    .eq('store_code', widget.storeCode)
                    .eq('staff_id', staffId);
              } catch (_) {}

              final cached = prefs.getString('cached_staff_list_${widget.storeCode}');
              if (cached != null) {
                List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(jsonDecode(cached));
                for (var s in list) {
                  if (s['staff_id'] == staffId) s['pin'] = newPin;
                }
                await prefs.setString('cached_staff_list_${widget.storeCode}', jsonEncode(list));
              }
              await prefs.setString('cached_staff_pin_${widget.storeCode}_$staffId', newPin);

              Navigator.pop(dCtx);
              onSuccess();
            },
            child: const Text('अपडेट करें'),
          )
        ],
      ),
    );
  }

  void _deleteStaff(String staffId, VoidCallback onDeleted) {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('स्टाफ हटाएं'),
        content: Text('क्या आप सचमुच $staffId को हटाना चाहते हैं?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              try {
                await Supabase.instance.client
                    .from('hotel_staff')
                    .delete()
                    .eq('store_code', widget.storeCode)
                    .eq('staff_id', staffId);
              } catch (_) {}

              final cached = prefs.getString('cached_staff_list_${widget.storeCode}');
              if (cached != null) {
                List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(jsonDecode(cached));
                list.removeWhere((item) => item['staff_id'] == staffId);
                await prefs.setString('cached_staff_list_${widget.storeCode}', jsonEncode(list));
              }
              await prefs.remove('cached_staff_pin_${widget.storeCode}_$staffId');

              Navigator.pop(dCtx);
              onDeleted();
            },
            child: const Text('हटाएं', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _printHindiReceipt(int id, double total, List<Map<String, dynamic>> items) async {
    if (!await PrintBluetoothThermal.connectionStatus) return;

    Widget receipt = Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.hotelName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black)),
          Text(id > 0 ? 'टेबल: T-$id' : 'पार्सल: P-${-id}', style: const TextStyle(fontSize: 18, color: Colors.black)),
          Text('दिनांक: ${DateTime.now().toString().substring(0, 16)}', style: const TextStyle(fontSize: 14, color: Colors.black)),
          const Divider(color: Colors.black, thickness: 1.5),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('${it['name']} x ${it['qty']}', style: const TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w600))),
                    Text('₹${it['price'] * it['qty']}', style: const TextStyle(fontSize: 18, color: Colors.black)),
                  ],
                ),
              )),
          const Divider(color: Colors.black, thickness: 1.5),
          Text('कुल बिल: ₹$total', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 6),
          const Text('धन्यवाद! फिर पधारें', style: TextStyle(fontSize: 16, color: Colors.black)),
        ],
      ),
    );

    try {
      final imageBytes = await screenshotController.captureFromWidget(receipt);
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage != null) {
        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm58, profile);
        List<int> bytes = [];
        bytes += generator.imageRaster(decodedImage);
        bytes += generator.feed(2);
        bytes += generator.cut();
        await PrintBluetoothThermal.writeBytes(bytes);
      }
    } catch (_) {}
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
              ? const Text('कोई पेयर्ड डिवाइस नहीं मिला। कृपया फोन की ब्लूटूथ सेटिंग में प्रिंटर पेयर करें।')
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
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _settleBill(int id) {
    List<Map<String, dynamic>> items = activeOrders[id] ?? [];
    double total = items.fold(0, (sum, it) => sum + (it['price'] * it['qty']));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${id > 0 ? "टेबल T-$id" : "पार्सल P-${-id}"} का बिल: ₹$total'),
        content: const Text('क्या आप बिल सेटल और हिंदी पर्ची प्रिंट करना चाहते हैं?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              Navigator.pop(ctx);
              await _printHindiReceipt(id, total, items);
              setState(() => activeOrders.remove(id));
            },
            child: const Text('प्रिंट व सेटल', style: TextStyle(color: Colors.white)),
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
        title: Text('${widget.storeCode} - मास्टर', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'रिफ्रेश करें', onPressed: () { _loadCloudRations(); setState(() {}); }),
          IconButton(icon: const Icon(Icons.group, color: Colors.amberAccent), onPressed: _openStaffManager, tooltip: 'स्टाफ प्रबंधन'),
          IconButton(icon: Icon(Icons.print, color: isPrinterConnected ? Colors.greenAccent : Colors.white), onPressed: _openPrinterDialog),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(26),
          child: Container(
            color: const Color(0xFF1E293B),
            child: Center(child: Text('हॉटस्पॉट चालू रखें | वाई-फाई IP: $localIp', style: const TextStyle(color: Colors.yellowAccent))),
          ),
        ),
      ),
      body: [
        // Tab 0: टेबल (Pull-to-Refresh सहित)
        RefreshIndicator(
          onRefresh: () async { setState(() {}); },
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
            itemCount: widget.tables,
            itemBuilder: (ctx, i) {
              int tbl = i + 1;
              bool hasOrder = activeOrders.containsKey(tbl) && activeOrders[tbl]!.isNotEmpty;
              return InkWell(
                onTap: hasOrder ? () => _settleBill(tbl) : null,
                child: Container(
                  decoration: BoxDecoration(color: hasOrder ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(10)),
                  child: Center(
                    child: Text('T-$tbl\n${hasOrder ? "ऑर्डर चालू" : "खाली"}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
        ),
        // Tab 1: मेन्यू
        Scaffold(
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFF0F172A),
            child: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              final nCtrl = TextEditingController();
              final pCtrl = TextEditingController();
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('नया व्यंजन जोड़ें'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: nCtrl, decoration: const InputDecoration(labelText: 'नाम')),
                      TextField(controller: pCtrl, decoration: const InputDecoration(labelText: 'कीमत ₹'), keyboardType: TextInputType.number),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
                    ElevatedButton(
                      onPressed: () {
                        if (nCtrl.text.isNotEmpty && pCtrl.text.isNotEmpty) {
                          setState(() => hotelMenu.add({'id': DateTime.now().millisecondsSinceEpoch, 'name': nCtrl.text.trim(), 'price': double.parse(pCtrl.text), 'cat': 'सामान्य', 'available': true}));
                          _saveLocalMenu();
                          Navigator.pop(context);
                        }
                      },
                      child: const Text('सेव'),
                    )
                  ],
                ),
              );
            },
          ),
          body: ListView.builder(
            itemCount: hotelMenu.length,
            itemBuilder: (ctx, i) {
              final itm = hotelMenu[i];
              return ListTile(
                title: Text(itm['name']),
                subtitle: Text('₹${itm['price']}'),
                trailing: Switch(
                  value: itm['available'] ?? true,
                  onChanged: (v) {
                    setState(() => itm['available'] = v);
                    _saveLocalMenu();
                  },
                ),
              );
            },
          ),
        ),
        // Tab 2: राशन मांग (Pull-to-Refresh सहित)
        RefreshIndicator(
          onRefresh: () async { _loadCloudRations(); },
          child: liveRationDemands.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 120), Center(child: Text('कुक ने अभी कोई राशन मांग नहीं भेजी है\n(नीचे खींचकर रिफ्रेश करें)', textAlign: TextAlign.center))])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: liveRationDemands.length,
                  itemBuilder: (ctx, i) => Card(
                    child: ListTile(
                      title: Text(liveRationDemands[i]['item_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      trailing: Text(liveRationDemands[i]['quantity'], style: const TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
        ),
      ][_currentTab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        selectedItemColor: const Color(0xFF0F172A),
        onTap: (i) => setState(() => _currentTab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.table_bar), label: 'टेबल्स'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'मेन्यू'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_basket), label: 'किचन मांग'),
        ],
      ),
    );
  }
}

// ==========================================
// 4. वेटर ऐप (100% ऑटो सिंक + Pull to Refresh)
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
  bool _isConnected = false;
  List<Map<String, dynamic>> menu = [];
  Map<int, List<Map<String, dynamic>>> liveTables = {};
  Timer? _autoSyncTimer;

  @override
  void initState() {
    super.initState();
    _initAutoSync();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  void _initAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_counter_ip');
    if (saved != null && saved.isNotEmpty) {
      _counterIp = saved;
    }
    _syncWithCounter();

    // हर 4 सेकंड में ऑटो सिंक (हाथ से सिंक दबाने की कोई ज़रूरत नहीं)
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _syncWithCounter();
    });
  }

  Future<void> _syncWithCounter() async {
    try {
      final socket = await Socket.connect(_counterIp, 4040, timeout: const Duration(seconds: 2));
      socket.write(jsonEncode({'type': 'GET_MENU'}) + "\n");
      socket.write(jsonEncode({'type': 'GET_RUNNING_TABLES'}) + "\n");

      socket.listen((data) {
        final lines = utf8.decode(data).split('\n');
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final res = jsonDecode(line);
            if (res['type'] == 'MENU_DATA') {
              if (mounted) setState(() { menu = List<Map<String, dynamic>>.from(res['menu']); _isConnected = true; });
            } else if (res['type'] == 'RUNNING_TABLES') {
              if (mounted) {
                setState(() {
                  liveTables = Map<int, List<Map<String, dynamic>>>.from(
                    (res['data'] as Map).map((k, v) => MapEntry(int.parse(k.toString()), List<Map<String, dynamic>>.from(v))),
                  );
                  _isConnected = true;
                });
              }
            }
          } catch (_) {}
        }
      });
    } catch (_) {
      if (mounted && _isConnected) setState(() => _isConnected = false);
    }
  }

  void _openOrderSheet(int tableNum) {
    final Map<int, int> cart = {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setBState) {
          double currentTotal = 0;
          cart.forEach((id, qty) {
            final it = menu.firstWhere((e) => e['id'] == id, orElse: () => {'price': 0});
            currentTotal += ((it['price'] ?? 0) * qty);
          });

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('टेबल T-$tableNum ऑर्डर', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: menu.isEmpty
                      ? const Center(child: Text('काउंटर से मेन्यू लोड हो रहा है... कृपया 1 सेकंड रुकें'))
                      : ListView.builder(
                          itemCount: menu.length,
                          itemBuilder: (c, idx) {
                            final item = menu[idx];
                            final isAvail = item['available'] ?? true;
                            final qty = cart[item['id']] ?? 0;

                            return ListTile(
                              title: Text(item['name'], style: TextStyle(color: isAvail ? Colors.black : Colors.grey)),
                              subtitle: Text('₹${item['price']}'),
                              trailing: !isAvail
                                  ? const Text('खत्म', style: TextStyle(color: Colors.red))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (qty > 0) IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => setBState(() => cart[item['id']] = qty - 1)),
                                        if (qty > 0) Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    Text('कुल: ₹$currentTotal', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                      onPressed: currentTotal == 0
                          ? null
                          : () async {
                              List<Map<String, dynamic>> orderItems = [];
                              cart.forEach((id, qty) {
                                if (qty > 0) {
                                  final it = menu.firstWhere((e) => e['id'] == id);
                                  orderItems.add({'name': it['name'], 'price': it['price'], 'qty': qty});
                                }
                              });
                              try {
                                final socket = await Socket.connect(_counterIp, 4040, timeout: const Duration(seconds: 3));
                                socket.write(jsonEncode({'type': 'NEW_KOT', 'table': tableNum, 'items': orderItems}) + "\n");
                                await socket.flush();
                                await socket.close();
                                if (mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('T-$tableNum का KOT काउंटर पर भेजा गया!'), backgroundColor: Colors.green));
                                }
                                _syncWithCounter();
                              } catch (_) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('काउंटर से कनेक्शन फेल! हॉटस्पॉट चेक करें')));
                              }
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
              _syncWithCounter();
            },
            child: const Text('सेव करें'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('वेटर: ${widget.staffId}', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), tooltip: 'रीफ्रेश करें', onPressed: _syncWithCounter),
          IconButton(icon: const Icon(Icons.settings, color: Colors.white70), tooltip: 'IP सेटिंग्स', onPressed: _manualIpDialog),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: _isConnected ? Colors.green.shade700 : Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isConnected ? '🟢 काउंटर से ऑटो-कनेक्टेड ($_counterIp)' : '🔴 काउंटर ढूँढ रहा है... (हॉटस्पॉट जोड़ें)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Text('ऑटो-सिंक चालू', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _syncWithCounter(),
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: widget.tables,
                itemBuilder: (ctx, i) {
                  int tbl = i + 1;
                  bool isOccupied = liveTables.containsKey(tbl) && liveTables[tbl]!.isNotEmpty;
                  return InkWell(
                    onTap: () => _openOrderSheet(tbl),
                    child: Container(
                      decoration: BoxDecoration(color: isOccupied ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text('T-$tbl\n${isOccupied ? "रनिंग" : "खाली"}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. कुक ऐप (ऑटो-कनेक्ट + Pull to Refresh)
// ==========================================
class FullCookApp extends StatefulWidget {
  final String storeCode;
  const FullCookApp({super.key, required this.storeCode});
  @override
  State<FullCookApp> createState() => _FullCookAppState();
}

class _FullCookAppState extends State<FullCookApp> {
  String _counterIp = '192.168.43.1';
  Socket? kitchenSocket;
  bool isConnected = false;
  List<Map<String, dynamic>> kitchenOrders = [];
  Timer? _reconnectTimer;

  List<String> presetRations = ['आटा', 'चावल', 'तेल', 'पनीर', 'शक्कर'];
  final Map<String, String> selectedRations = {};
  final _customItemCtrl = TextEditingController();
  final _customQtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    kitchenSocket?.destroy();
    super.dispose();
  }

  void _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('saved_counter_ip');
    if (savedIp != null && savedIp.isNotEmpty) _counterIp = savedIp;

    final savedList = prefs.getStringList('custom_ration_list_${widget.storeCode}');
    if (savedList != null && savedList.isNotEmpty && mounted) {
      setState(() => presetRations = savedList);
    }
    _connectToCounter();

    // हर 5 सेकंड में ऑटो-रिकनेक्ट
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isConnected) _connectToCounter();
    });
  }

  void _saveRationList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('custom_ration_list_${widget.storeCode}', presetRations);
  }

  void _connectToCounter() async {
    try {
      kitchenSocket = await Socket.connect(_counterIp, 4040, timeout: const Duration(seconds: 2));
      if (mounted) setState(() => isConnected = true);
      kitchenSocket!.listen((data) {
        final lines = utf8.decode(data).split("\n");
        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(line);
            if (msg['type'] == 'NEW_KOT' && mounted) {
              setState(() => kitchenOrders.insert(0, Map<String, dynamic>.from(msg)));
            }
          } catch (_) {}
        }
      }, onDone: () { if (mounted) setState(() => isConnected = false); }, onError: (_) { if (mounted) setState(() => isConnected = false); });
    } catch (_) {
      if (mounted && isConnected) setState(() => isConnected = false);
    }
  }

  void _addNewRationItem() {
    if (_customItemCtrl.text.isNotEmpty) {
      setState(() {
        presetRations.add(_customItemCtrl.text.trim());
        if (_customQtyCtrl.text.isNotEmpty) {
          selectedRations[_customItemCtrl.text.trim()] = _customQtyCtrl.text.trim();
        }
      });
      _saveRationList();
      _customItemCtrl.clear();
      _customQtyCtrl.clear();
    }
  }

  void _sendBulkRationDemand() async {
    if (selectedRations.isEmpty) return;

    List<Map<String, dynamic>> itemsToSend = [];
    selectedRations.forEach((name, qty) => itemsToSend.add({'item_name': name, 'quantity': qty}));

    try {
      List<Map<String, dynamic>> dbInsert = itemsToSend.map((e) => {'store_code': widget.storeCode, 'item_name': e['item_name'], 'quantity': e['quantity']}).toList();
      await Supabase.instance.client.from('ration_demands').insert(dbInsert);

      if (isConnected && kitchenSocket != null) {
        kitchenSocket!.write(jsonEncode({'type': 'RATION_DEMAND', 'items': itemsToSend}) + "\n");
      }

      setState(() => selectedRations.clear());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('मांग काउंटर और एडमिन को भेज दी गई!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('एरर: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('कुक KDS', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.teal,
          actions: [
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _connectToCounter),
          ],
          bottom: const TabBar(labelColor: Colors.white, unselectedLabelColor: Colors.white54, tabs: [Tab(text: 'लाइव KOT'), Tab(text: 'थोक राशन')]),
        ),
        body: TabBarView(
          children: [
            Column(
              children: [
                Container(
                  color: isConnected ? Colors.teal.shade800 : Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isConnected ? '🟢 काउंटर से लाइव कनेक्टेड' : '🔴 काउंटर कनेक्ट कर रहा है...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const Text('ऑटो सिंक चालू', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async { _connectToCounter(); },
                    child: kitchenOrders.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 120), Center(child: Text('कोई नया KOT नहीं है 👨‍🍳\n(नीचे खींचकर रिफ्रेश करें)', textAlign: TextAlign.center))])
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: kitchenOrders.length,
                            itemBuilder: (ctx, i) {
                              final order = kitchenOrders[i];
                              final items = order['items'] as List;
                              return Card(
                                margin: const EdgeInsets.all(8),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('टेबल: T-${order['table']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
                                          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () => setState(() => kitchenOrders.removeAt(i)), child: const Text('तैयार ✓', style: TextStyle(color: Colors.white)))
                                        ],
                                      ),
                                      const Divider(),
                                      ...items.map((it) => Text('${it['name']} x ${it['qty']}', style: const TextStyle(fontSize: 18))),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                )
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 2, child: TextField(controller: _customItemCtrl, decoration: const InputDecoration(hintText: 'नया सामान (जैसे: हरी मिर्च)'))),
                      const SizedBox(width: 8),
                      Expanded(flex: 1, child: TextField(controller: _customQtyCtrl, decoration: const InputDecoration(hintText: 'मात्रा'))),
                      IconButton(icon: const Icon(Icons.add_box, color: Colors.teal, size: 35), onPressed: _addNewRationItem)
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
                                  width: 90,
                                  child: TextField(
                                    onChanged: (val) => selectedRations[itemName] = val,
                                    decoration: const InputDecoration(hintText: 'मात्रा', border: OutlineInputBorder(), isDense: true),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                      onPressed: _sendBulkRationDemand,
                      child: const Text('मांग भेजें', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

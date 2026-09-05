import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/restaurant_profile_model.dart';
import '../../Data/Menu_data_source.dart';

class RestaurantSettingsScreen extends StatefulWidget {
  final RestaurantProfileModel? initialProfile;
  final String storeCode;
  final Function(RestaurantProfileModel) onSave;

  const RestaurantSettingsScreen({
    super.key,
    this.initialProfile,
    required this.storeCode,
    required this.onSave,
  });

  @override
  State<RestaurantSettingsScreen> createState() => _RestaurantSettingsScreenState();
}

class _RestaurantSettingsScreenState extends State<RestaurantSettingsScreen> {
  final TextEditingController _upiCtrl = TextEditingController();
  final TextEditingController _reviewCtrl = TextEditingController();
  bool _isLoading = true;
  RestaurantProfileModel? _currentProfile;

  // मेन्यू स्टॉक कंट्रोल लिस्ट
  List<MenuItemModel> _menuList = [];
  String _selectedCategory = 'सभी (All)';

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    String upi = prefs.getString('saved_hotel_upi') ?? widget.initialProfile?.upiId ?? '';
    String review = prefs.getString('saved_hotel_review') ?? widget.initialProfile?.googleReviewLink ?? '';

    // 1. होटल प्रोफ़ाइल लोड करना
    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select()
          .eq('store_code', widget.storeCode)
          .maybeSingle();

      if (res != null) {
        _currentProfile = RestaurantProfileModel.fromMap(res);
        upi = res['upi_id']?.toString() ?? upi;
        review = res['google_review_link']?.toString() ?? review;

        if (upi.isNotEmpty) await prefs.setString('saved_hotel_upi', upi);
        if (review.isNotEmpty) await prefs.setString('saved_hotel_review', review);
      }
    } catch (_) {}

    _currentProfile ??= widget.initialProfile;

    // 2. मेन्यू स्टॉक स्थिति लोड करना
    try {
      final menuRes = await Supabase.instance.client
          .from('menu_items')
          .select()
          .eq('restaurant_id', widget.storeCode);

      final Map<String, bool> statusMap = {};
      for (var item in menuRes) {
        statusMap[item['id'].toString()] = item['is_available'] ?? true;
      }

      _menuList = kRestaurantMenu.map((item) {
        final isAvail = statusMap[item.id] ?? true;
        return item.copyWith(isAvailable: isAvail);
      }).toList();
    } catch (_) {
      _menuList = List.from(kRestaurantMenu);
    }

    if (mounted) {
      setState(() {
        _upiCtrl.text = upi;
        _reviewCtrl.text = review;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final upi = _upiCtrl.text.trim();
    final review = _reviewCtrl.text.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_hotel_upi', upi);
    await prefs.setString('saved_hotel_review', review);

    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({
            'upi_id': upi.isEmpty ? null : upi,
            'google_review_link': review.isEmpty ? null : review,
          })
          .eq('store_code', widget.storeCode);
    } catch (_) {}

    final updatedMap = _currentProfile?.toMap() ?? {'store_code': widget.storeCode, 'name': ''};
    updatedMap['upi_id'] = upi;
    updatedMap['google_review_link'] = review;
    widget.onSave(RestaurantProfileModel.fromMap(updatedMap));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ सेटिंग्स सुरक्षित हो गईं!'), backgroundColor: Colors.teal),
      );
    }
  }

  // आइटम ऑन / ऑफ़ (पॉज़ / एक्टिव) करने का लॉजिक
  Future<void> _toggleItemStatus(MenuItemModel item) async {
    final newStatus = !item.isAvailable;

    setState(() {
      final idx = _menuList.indexWhere((m) => m.id == item.id);
      if (idx != -1) {
        _menuList[idx] = item.copyWith(isAvailable: newStatus);
      }
    });

    try {
      await Supabase.instance.client.from('menu_items').upsert({
        'id': item.id,
        'restaurant_id': widget.storeCode,
        'name': item.name,
        'category': item.category,
        'price': item.price,
        'is_available': newStatus,
      }, onConflict: 'id,restaurant_id');
    } catch (e) {
      debugPrint("Item status update error: $e");
    }
  }

  @override
  void dispose() {
    _upiCtrl.dispose();
    _reviewCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMenu = _selectedCategory == 'सभी (All)'
        ? _menuList
        : _menuList.where((i) => i.category == _selectedCategory).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('होटल मास्टर सेटिंग्स', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF0F172A),
          bottom: const TabBar(
            indicatorColor: Color(0xFFEA580C),
            labelColor: Color(0xFFEA580C),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.qr_code), text: 'UPI व QR सेटिंग्स'),
              Tab(icon: Icon(Icons.restaurant_menu), text: 'मेन्यू स्टॉक (Pause/Active)'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // ================= टैब 1: UPI और QR सेटिंग्स =================
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // होटल मास्टर डेटा (Read Only)
                        Card(
                          color: Colors.grey.shade100,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.lock_outline, size: 18, color: Colors.grey),
                                    SizedBox(width: 6),
                                    Text('मास्टर विवरण (एडमिन द्वारा नियंत्रित)', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(),
                                Text('होटल: ${_currentProfile?.name ?? "सेट नहीं"}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('मोबाइल: ${_currentProfile?.phone ?? "सेट नहीं"}'),
                                Text('पता: ${_currentProfile?.address ?? "सेट नहीं"}'),
                                if (_currentProfile?.gstNumber != null && _currentProfile!.gstNumber!.isNotEmpty)
                                  Text('GSTIN: ${_currentProfile!.gstNumber}'),
                                if (_currentProfile?.fssaiNumber != null && _currentProfile!.fssaiNumber!.isNotEmpty)
                                  Text('FSSAI: ${_currentProfile!.fssaiNumber}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        TextField(
                          controller: _upiCtrl,
                          decoration: InputDecoration(
                            labelText: 'पेमेंट QR के लिए UPI ID',
                            hintText: 'उदा. merchant@okaxis',
                            prefixIcon: const Icon(Icons.qr_code_2, color: Colors.orange),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 14),

                        TextField(
                          controller: _reviewCtrl,
                          decoration: InputDecoration(
                            labelText: 'Google Review Link (रिव्यू QR के लिए)',
                            hintText: 'https://g.page/r/.../review',
                            prefixIcon: const Icon(Icons.star, color: Colors.amber),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
                            onPressed: _saveSettings,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text('सेटिंग्स सुरक्षित (Save) करें', style: TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ================= टैब 2: मेन्यू स्टॉक कंट्रोल =================
                  Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: kMenuCategories.map((cat) {
                            final isSel = _selectedCategory == cat;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(cat),
                                selected: isSel,
                                selectedColor: const Color(0xFFEA580C),
                                labelStyle: TextStyle(color: isSel ? Colors.white : Colors.black87),
                                onSelected: (val) => setState(() => _selectedCategory = cat),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filteredMenu.length,
                          itemBuilder: (ctx, idx) {
                            final item = filteredMenu[idx];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: item.isAvailable ? Colors.grey.shade300 : Colors.redAccent,
                                ),
                              ),
                              child: ListTile(
                                title: Text(
                                  item.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    decoration: item.isAvailable ? null : TextDecoration.lineThrough,
                                    color: item.isAvailable ? Colors.black87 : Colors.grey,
                                  ),
                                ),
                                subtitle: Text(
                                  '₹${item.price.toStringAsFixed(0)}  •  ${item.isAvailable ? "उपलब्ध (Active)" : "बंद (Out of Stock)"}',
                                  style: TextStyle(
                                    color: item.isAvailable ? Colors.green : Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: Switch(
                                  value: item.isAvailable,
                                  activeColor: Colors.green,
                                  inactiveThumbColor: Colors.redAccent,
                                  onChanged: (val) => _toggleItemStatus(item),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

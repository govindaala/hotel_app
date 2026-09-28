// lib/screens/admin/restaurant_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/restaurant_profile_model.dart';
import '../../models/partner_model.dart';
import '../../models/vendor_model.dart';

class RestaurantSettingsScreen extends StatefulWidget {
  final RestaurantProfileModel? initialProfile;
  final String storeCode;
  final Function(RestaurantProfileModel)? onSave;

  const RestaurantSettingsScreen({
    Key? key,
    this.initialProfile,
    required this.storeCode,
    this.onSave,
  }) : super(key: key);

  @override
  State<RestaurantSettingsScreen> createState() => _RestaurantSettingsScreenState();
}

class _RestaurantSettingsScreenState extends State<RestaurantSettingsScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _isLoading = false;

  // 1. होटल प्रोफ़ाइल फ़ील्ड्स
  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _upiCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _fssaiCtrl;

  // 2. पार्टनर्स व वेंडर्स डेटा
  List<RestaurantPartnerModel> _partners = [];
  List<HotelVendorModel> _vendors = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _nameCtrl = TextEditingController(text: widget.initialProfile?.name ?? '');
    _addressCtrl = TextEditingController(text: widget.initialProfile?.address ?? '');
    _phoneCtrl = TextEditingController(text: widget.initialProfile?.phone ?? '');
    _upiCtrl = TextEditingController(text: widget.initialProfile?.upiId ?? '');
    _gstCtrl = TextEditingController(text: widget.initialProfile?.gstNumber ?? '');
    _fssaiCtrl = TextEditingController(text: widget.initialProfile?.fssaiNumber ?? '');

    _fetchPartnersAndVendors();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _upiCtrl.dispose();
    _gstCtrl.dispose();
    _fssaiCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPartnersAndVendors() async {
    setState(() => _isLoading = true);
    try {
      // पार्टनर्स लोड करना
      final pRes = await _supabase
          .from('restaurant_partners')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: true);

      // वेंडर्स लोड करना
      final vRes = await _supabase
          .from('hotel_vendors')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: true);

      setState(() {
        _partners = (pRes as List).map((e) => RestaurantPartnerModel.fromMap(e)).toList();
        _vendors = (vRes as List).map((e) => HotelVendorModel.fromMap(e)).toList();
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // =========================================================================
  // 1. होटल प्रोफ़ाइल सेव करना
  // =========================================================================
  Future<void> _saveHotelProfile() async {
    setState(() => _isLoading = true);
    final updated = RestaurantProfileModel(
      storeCode: widget.storeCode,
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      upiId: _upiCtrl.text.trim(),
      gstNumber: _gstCtrl.text.trim(),
      fssaiNumber: _fssaiCtrl.text.trim(),
    );

    try {
      await _supabase.from('restaurants').upsert(updated.toMap());

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_hotel_name', updated.name);
      await prefs.setString('saved_hotel_address', updated.address ?? '');
      await prefs.setString('saved_hotel_phone', updated.phone ?? '');
      await prefs.setString('saved_hotel_upi', updated.upiId ?? '');

      if (widget.onSave != null) widget.onSave!(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('होटल प्रोफ़ाइल सफलतापूर्वक सुरक्षित हुई!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('सेव करने में त्रुटि: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // =========================================================================
  // 2. नया पार्टनर जोड़ना / एडिट डायलॉग
  // =========================================================================
  void _openPartnerDialog([RestaurantPartnerModel? partner]) {
    final nameCtrl = TextEditingController(text: partner?.partnerName ?? '');
    final phoneCtrl = TextEditingController(text: partner?.phone ?? '');
    final pinCtrl = TextEditingController(text: partner?.loginPin ?? '');
    final shareCtrl = TextEditingController(
      text: partner != null ? partner.sharePercentage.toStringAsFixed(0) : '25',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(partner == null ? '🤝 नया पार्टनर जोड़ें' : 'पार्टनर विवरण बदलें',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'पार्टनर का नाम', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'मोबाइल नंबर', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: '4-अंकों का लॉगिन पिन',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.pin),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shareCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'हिस्सेदारी प्रतिशत (Share %)',
                  border: OutlineInputBorder(),
                  suffixText: '%',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final pin = pinCtrl.text.trim();
              final share = double.tryParse(shareCtrl.text.trim()) ?? 0.0;

              if (name.isEmpty || pin.length != 4 || share <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('कृपया सही नाम, 4-अंक पिन और शेयर दर्ज करें!')),
                );
                return;
              }

              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              final partnerId = partner?.partnerId ?? 'P${_partners.length + 1}';
              final partnerMap = {
                'store_code': widget.storeCode,
                'partner_id': partnerId,
                'partner_name': name,
                'phone': phoneCtrl.text.trim(),
                'login_pin': pin,
                'share_percentage': share,
                'is_active': true,
              };

              try {
                await _supabase.from('restaurant_partners').upsert(
                  partnerMap,
                  onConflict: 'store_code,partner_id',
                );
                _fetchPartnersAndVendors();
              } catch (_) {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('सेव करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. नया वेंडर जोड़ना / एडिट डायलॉग
  // =========================================================================
  void _openVendorDialog([HotelVendorModel? vendor]) {
    final nameCtrl = TextEditingController(text: vendor?.vendorName ?? '');
    final phoneCtrl = TextEditingController(text: vendor?.phone ?? '');
    String category = vendor?.category ?? 'VEGETABLE';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(vendor == null ? '🛒 नया वेंडर / सप्लायर जोड़ें' : 'वेंडर विवरण बदलें',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'वेंडर/दुकान का नाम', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'श्रेणी (Category)', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'VEGETABLE', child: Text('🥦 सब्जी मंडी')),
                    DropdownMenuItem(value: 'DAIRY', child: Text('🥛 डेयरी (दूध, पनीर)')),
                    DropdownMenuItem(value: 'GROCERY', child: Text('🌾 किराना व मसाले')),
                    DropdownMenuItem(value: 'MEAT', child: Text('🍗 मीट / चिकन')),
                    DropdownMenuItem(value: 'OTHER', child: Text('📦 अन्य सामग्री')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDState(() => category = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp मोबाइल नंबर',
                    hintText: '10 अंकों का नंबर',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(ctx);
                setState(() => _isLoading = true);

                final vendorData = {
                  'store_code': widget.storeCode,
                  'vendor_name': name,
                  'vendor_category': category,
                  'phone': phoneCtrl.text.trim(),
                  'is_active': true,
                };

                try {
                  if (vendor != null && vendor.id.isNotEmpty) {
                    await _supabase.from('hotel_vendors').update(vendorData).eq('id', vendor.id);
                  } else {
                    await _supabase.from('hotel_vendors').insert(vendorData);
                  }
                  _fetchPartnersAndVendors();
                } catch (_) {
                  setState(() => _isLoading = false);
                }
              },
              child: const Text('सेव करें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('होटल ERP सेटिंग्स', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.store), text: 'होटल प्रोफ़ाइल'),
            Tab(icon: Icon(Icons.handshake), text: 'पार्टनर्स'),
            Tab(icon: Icon(Icons.local_shipping), text: 'वेंडर्स'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // ---------------- TAB 1: प्रोफ़ाइल ----------------
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'होटल का नाम', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'संपर्क नंबर', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(labelText: 'होटल का पता', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _upiCtrl,
                        decoration: const InputDecoration(
                          labelText: 'UPI आईडी (बिल QR कोड हेतु)',
                          hintText: 'उदा. hotel@okicici',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _gstCtrl,
                        decoration: const InputDecoration(labelText: 'GSTIN (वैकल्पिक)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _fssaiCtrl,
                        decoration: const InputDecoration(labelText: 'FSSAI नंबर (वैकल्पिक)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: const Text('प्रोफ़ाइल अपडेट करें', style: TextStyle(color: Colors.white, fontSize: 16)),
                          onPressed: _saveHotelProfile,
                        ),
                      ),
                    ],
                  ),
                ),

                // ---------------- TAB 2: पार्टनर्स ----------------
                Scaffold(
                  backgroundColor: Colors.transparent,
                  floatingActionButton: FloatingActionButton.extended(
                    backgroundColor: const Color(0xFF0F172A),
                    icon: const Icon(Icons.person_add, color: Colors.white),
                    label: const Text('नया पार्टनर', style: TextStyle(color: Colors.white)),
                    onPressed: () => _openPartnerDialog(),
                  ),
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.indigo[100]!),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.indigo),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'कुल शेयर: ${_partners.fold<double>(0.0, (sum, p) => sum + p.sharePercentage).toStringAsFixed(0)}% / 100%',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_partners.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('कोई पार्टनर नहीं है। नीचे बटन दबाकर जोड़ें।', style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ..._partners.map((p) => Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF0F172A),
                                  child: Text(p.partnerName[0], style: const TextStyle(color: Colors.white)),
                                ),
                                title: Text(p.partnerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('शेयर: ${p.sharePercentage.toStringAsFixed(0)}%  •  पिन: ${p.loginPin}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _openPartnerDialog(p),
                                ),
                              ),
                            )),
                    ],
                  ),
                ),

                // ---------------- TAB 3: वेंडर्स ----------------
                Scaffold(
                  backgroundColor: Colors.transparent,
                  floatingActionButton: FloatingActionButton.extended(
                    backgroundColor: Colors.teal[800],
                    icon: const Icon(Icons.add_business, color: Colors.white),
                    label: const Text('नया वेंडर', style: TextStyle(color: Colors.white)),
                    onPressed: () => _openVendorDialog(),
                  ),
                  body: _vendors.isEmpty
                      ? const Center(
                          child: Text('कोई वेंडर दर्ज नहीं है। नीचे बटन दबाकर जोड़ें।', style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _vendors.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final v = _vendors[idx];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal[50],
                                  child: Icon(
                                    v.category == 'DAIRY'
                                        ? Icons.local_drink
                                        : v.category == 'VEGETABLE'
                                            ? Icons.eco
                                            : Icons.storefront,
                                    color: Colors.teal[800],
                                  ),
                                ),
                                title: Text(v.vendorName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('केटेगरी: ${v.category}  •  फ़ोन: ${v.phone ?? "N/A"}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _openVendorDialog(v),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

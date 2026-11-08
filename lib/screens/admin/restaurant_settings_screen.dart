import 'dart:convert';
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

  late TextEditingController _nameCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _upiCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _fssaiCtrl;
  late TextEditingController _reviewCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _customerFactsCtrl;
  late TextEditingController _customerTrackingApiCtrl;
  bool _showCustomerTimer = true;

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
    _reviewCtrl = TextEditingController(text: widget.initialProfile?.googleReviewLink ?? '');
    _footerCtrl = TextEditingController(text: widget.initialProfile?.footerMessage ?? '');
    _customerFactsCtrl = TextEditingController();
    _customerTrackingApiCtrl = TextEditingController();

    _fetchPartnersAndVendors();
    _loadCustomerExperienceSettings();
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
    _reviewCtrl.dispose();
    _footerCtrl.dispose();
    _customerFactsCtrl.dispose();
    _customerTrackingApiCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerExperienceSettings() async {
    try {
      final row = await _supabase
          .from('restaurants')
          .select('customer_facts, show_customer_timer, customer_tracking_api_url')
          .eq('store_code', widget.storeCode)
          .maybeSingle();
      if (!mounted || row == null) return;
      final rawFacts = row['customer_facts'];
      List<dynamic> facts = [];
      if (rawFacts is List) {
        facts = rawFacts;
      } else if (rawFacts is String && rawFacts.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawFacts);
          if (decoded is List) facts = decoded;
        } catch (_) {}
      }
      setState(() {
        _customerFactsCtrl.text = facts.map((e) => e.toString()).join('\n');
        _showCustomerTimer = row['show_customer_timer'] != false;
        _customerTrackingApiCtrl.text = (row['customer_tracking_api_url'] ?? '').toString();
      });
    } catch (error) {
      debugPrint('Customer screen settings could not be loaded: $error');
    }
  }

  Future<void> _fetchPartnersAndVendors() async {
    setState(() => _isLoading = true);
    try {
      final pRes = await _supabase
          .from('restaurant_partners')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: true);

      final vRes = await _supabase
          .from('hotel_vendors')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: true);

      if (mounted) setState(() {
        _partners = (pRes as List).map((e) => RestaurantPartnerModel.fromMap(e)).toList();
        _vendors = (vRes as List).map((e) => HotelVendorModel.fromMap(e)).toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _settleVendorBalance(HotelVendorModel vendor) async {
    if (vendor.currentBalance <= 0) return;
    final amountCtrl = TextEditingController();
    String paymentMode = 'DRAWER_CASH';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('वेंडर भुगतान: ${vendor.vendorName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('कुल बकाया: ₹${vendor.currentBalance.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'भुगतान राशि',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: paymentMode,
                decoration: const InputDecoration(labelText: 'भुगतान माध्यम', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'DRAWER_CASH', child: Text('कैश गल्ला')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI / बैंक')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => paymentMode = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('रद्द करें'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amount <= 0 || amount > vendor.currentBalance) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('राशि शून्य से अधिक और बकाया से कम/बराबर होनी चाहिए।')),
                  );
                  return;
                }

                String? expenseId;
                try {
                  final expense = await _supabase.from('daily_expenses').insert({
                    'restaurant_id': widget.storeCode,
                    'store_code': widget.storeCode,
                    'title': 'वेंडर भुगतान: ${vendor.vendorName}',
                    'amount': amount,
                    'type': paymentMode == 'UPI' ? 'VENDOR_PAYMENT_UPI' : 'VENDOR_PAYMENT_CASH',
                    'created_at': DateTime.now().toIso8601String(),
                  }).select('id').single();
                  expenseId = expense['id'].toString();

                  await _supabase.from('hotel_vendors').update({
                    'current_balance': vendor.currentBalance - amount,
                  }).eq('id', vendor.id);

                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (expenseId != null) {
                    try {
                      await _supabase.from('daily_expenses').delete().eq('id', expenseId);
                    } catch (_) {}
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('वेंडर भुगतान सेव नहीं हुआ: $error')),
                    );
                  }
                }
              },
              child: const Text('भुगतान सेव करें'),
            ),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    if (saved == true) await _fetchPartnersAndVendors();
  }

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
      googleReviewLink: _reviewCtrl.text.trim(),
      footerMessage: _footerCtrl.text.trim(),
    );

    try {
      await _supabase.from('restaurants').upsert(updated.toMap());
      final customerFacts = _customerFactsCtrl.text
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .take(50)
          .toList();
      await _supabase.from('restaurants').update({
        'customer_facts': customerFacts,
        'show_customer_timer': _showCustomerTimer,
        'customer_tracking_api_url': _customerTrackingApiCtrl.text.trim().replaceAll(RegExp(r'/+      }).eq('store_code', widget.storeCode);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_hotel_name', updated.name);
      await prefs.setString('saved_hotel_address', updated.address ?? '');
      await prefs.setString('saved_hotel_phone', updated.phone ?? '');
      await prefs.setString('saved_hotel_upi', updated.upiId ?? '');
      await prefs.setString('saved_hotel_review', updated.googleReviewLink ?? '');
      await prefs.setString('saved_hotel_footer', updated.footerMessage ?? '');

      if (widget.onSave != null) widget.onSave!(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('होटल प्रोफ़ाइल सफलतापूर्वक सुरक्षित हुई!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // वेंडर डायलॉग (काउंटर लोकल सप्लायर जोड़ सकता है)
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
        title: const Text('होटल सेटिंग्स', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.store), text: 'होटल प्रोफ़ाइल'),
            Tab(icon: Icon(Icons.handshake), text: 'पार्टनर्स (View)'),
            Tab(icon: Icon(Icons.local_shipping), text: 'वेंडर्स'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 1. HOTEL PROFILE TAB
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
                          labelText: 'UPI ID (बिल QR कोड हेतु)',
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reviewCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Google Review लिंक (वैकल्पिक)',
                          hintText: 'https://g.page/r/...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _footerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'बिल के नीचे संदेश (वैकल्पिक)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ग्राहक स्क्रीन पर लाइव टाइमर दिखाएँ'),
                        subtitle: const Text('ऑर्डर तैयार होने का अनुमान और उलटी गिनती'),
                        value: _showCustomerTimer,
                        onChanged: (value) => setState(() => _showCustomerTimer = value),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customerTrackingApiCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Customer tracking API URL',
                          hintText: 'https://your-render-service.onrender.com',
                          helperText: 'Render पर Python Intelligence Engine deploy करने के बाद इसका URL यहाँ डालें।',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customerFactsCtrl,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: 3000,
                        decoration: const InputDecoration(
                          labelText: 'ग्राहक स्क्रीन पर होटल की खासियतें',
                          hintText: 'हर लाइन में एक तथ्य लिखें। अधिकतम 50 तथ्य।\nजैसे: शुद्ध ताज़ी सामग्री\nपरिवार के लिए अलग बैठने की व्यवस्था\nघर जैसा ताज़ा भोजन',
                          helperText: 'ऑर्डर ट्रैकिंग कार्ड के साथ एक-एक तथ्य अपने आप बदलता रहेगा।',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
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

                // 2. READ-ONLY PARTNERS TAB (Super Admin Controlled)
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'सुरक्षा नियम: पार्टनर्स जोड़ना या उनका शेयर % बदलना केवल सुपर एडमिन पोर्टल से ही संभव है।',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_partners.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('कोई पार्टनर पंजीकृत नहीं है। सुपर एडमिन पोर्टल से जोड़ें।', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      ..._partners.map((p) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0F172A),
                                child: Text(p.partnerName.isNotEmpty ? p.partnerName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                              ),
                              title: Text(p.partnerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('शेयर: ${p.sharePercentage.toStringAsFixed(0)}%  •  पिन: ****  •  ID: ${p.partnerId}'),
                              trailing: const Icon(Icons.verified, color: Colors.green, size: 20),
                            ),
                          )),
                  ],
                ),

                // 3. VENDORS TAB
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
                                subtitle: Text('केटेगरी: ${v.category}  •  फ़ोन: ${v.phone ?? "N/A"}  •  बकाया: ₹${v.currentBalance.toStringAsFixed(0)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (v.currentBalance > 0)
                                      IconButton(
                                        tooltip: 'बकाया भुगतान',
                                        icon: const Icon(Icons.payments, color: Colors.green),
                                        onPressed: () => _settleVendorBalance(v),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _openVendorDialog(v),
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
  }
}
), ''),
      }).eq('store_code', widget.storeCode);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_hotel_name', updated.name);
      await prefs.setString('saved_hotel_address', updated.address ?? '');
      await prefs.setString('saved_hotel_phone', updated.phone ?? '');
      await prefs.setString('saved_hotel_upi', updated.upiId ?? '');
      await prefs.setString('saved_hotel_review', updated.googleReviewLink ?? '');
      await prefs.setString('saved_hotel_footer', updated.footerMessage ?? '');

      if (widget.onSave != null) widget.onSave!(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('होटल प्रोफ़ाइल सफलतापूर्वक सुरक्षित हुई!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // वेंडर डायलॉग (काउंटर लोकल सप्लायर जोड़ सकता है)
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
        title: const Text('होटल सेटिंग्स', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.store), text: 'होटल प्रोफ़ाइल'),
            Tab(icon: Icon(Icons.handshake), text: 'पार्टनर्स (View)'),
            Tab(icon: Icon(Icons.local_shipping), text: 'वेंडर्स'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // 1. HOTEL PROFILE TAB
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
                          labelText: 'UPI ID (बिल QR कोड हेतु)',
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reviewCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Google Review लिंक (वैकल्पिक)',
                          hintText: 'https://g.page/r/...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _footerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'बिल के नीचे संदेश (वैकल्पिक)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ग्राहक स्क्रीन पर लाइव टाइमर दिखाएँ'),
                        subtitle: const Text('ऑर्डर तैयार होने का अनुमान और उलटी गिनती'),
                        value: _showCustomerTimer,
                        onChanged: (value) => setState(() => _showCustomerTimer = value),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customerFactsCtrl,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: 3000,
                        decoration: const InputDecoration(
                          labelText: 'ग्राहक स्क्रीन पर होटल की खासियतें',
                          hintText: 'हर लाइन में एक तथ्य लिखें। अधिकतम 50 तथ्य।\nजैसे: शुद्ध ताज़ी सामग्री\nपरिवार के लिए अलग बैठने की व्यवस्था\nघर जैसा ताज़ा भोजन',
                          helperText: 'ऑर्डर ट्रैकिंग कार्ड के साथ एक-एक तथ्य अपने आप बदलता रहेगा।',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
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

                // 2. READ-ONLY PARTNERS TAB (Super Admin Controlled)
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber[200]!),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'सुरक्षा नियम: पार्टनर्स जोड़ना या उनका शेयर % बदलना केवल सुपर एडमिन पोर्टल से ही संभव है।',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_partners.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('कोई पार्टनर पंजीकृत नहीं है। सुपर एडमिन पोर्टल से जोड़ें।', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      ..._partners.map((p) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF0F172A),
                                child: Text(p.partnerName.isNotEmpty ? p.partnerName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                              ),
                              title: Text(p.partnerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('शेयर: ${p.sharePercentage.toStringAsFixed(0)}%  •  पिन: ****  •  ID: ${p.partnerId}'),
                              trailing: const Icon(Icons.verified, color: Colors.green, size: 20),
                            ),
                          )),
                  ],
                ),

                // 3. VENDORS TAB
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
                                subtitle: Text('केटेगरी: ${v.category}  •  फ़ोन: ${v.phone ?? "N/A"}  •  बकाया: ₹${v.currentBalance.toStringAsFixed(0)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (v.currentBalance > 0)
                                      IconButton(
                                        tooltip: 'बकाया भुगतान',
                                        icon: const Icon(Icons.payments, color: Colors.green),
                                        onPressed: () => _settleVendorBalance(v),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _openVendorDialog(v),
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
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/restaurant_profile_model.dart';

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

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    String upi = prefs.getString('saved_hotel_upi') ?? widget.initialProfile?.upiId ?? '';
    String review = prefs.getString('saved_hotel_review') ?? widget.initialProfile?.googleReviewLink ?? '';

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
    } catch (e) {
      debugPrint("Fetch profile error: $e");
    }

    _currentProfile ??= widget.initialProfile;

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

    setState(() => _isLoading = true);

    // 1. SharedPreferences में लोकल सेव
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_hotel_upi', upi);
    await prefs.setString('saved_hotel_review', review);

    // 2. Supabase में अपडेट
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({
            'upi_id': upi.isEmpty ? null : upi,
            'google_review_link': review.isEmpty ? null : review,
          })
          .eq('store_code', widget.storeCode);
    } catch (e) {
      debugPrint("Supabase update error: $e");
    }

    final updatedMap = _currentProfile?.toMap() ?? {'store_code': widget.storeCode, 'name': ''};
    updatedMap['upi_id'] = upi;
    updatedMap['google_review_link'] = review;
    final updated = RestaurantProfileModel.fromMap(updatedMap);

    widget.onSave(updated);

    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ UPI ID और Review Link सुरक्षित हो गए!'),
          backgroundColor: Colors.teal,
        ),
      );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('काउंटर सेटिंग्स (QR व पेमेंट)', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // होटल का मास्टर विवरण (केवल देखने के लिए)
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
                              Text(
                                'मास्टर विवरण (एडमिन द्वारा नियंत्रित)',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                            ],
                          ),
                          const Divider(),
                          Text('होटल: ${_currentProfile?.name.isNotEmpty == true ? _currentProfile!.name : "सेट नहीं"}', style: const TextStyle(fontWeight: FontWeight.w600)),
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

                  const Text(
                    'होटल काउंटर सेटिंग्स',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 12),

                  // UPI ID इनपुट
                  TextField(
                    controller: _upiCtrl,
                    decoration: InputDecoration(
                      labelText: 'पेमेंट QR के लिए UPI ID',
                      hintText: 'उदा. merchant@okaxis या 9876543210@paytm',
                      prefixIcon: const Icon(Icons.qr_code_2, color: Colors.orange),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Google Review Link इनपुट
                  TextField(
                    controller: _reviewCtrl,
                    decoration: InputDecoration(
                      labelText: 'Google Review Link (रिव्यू QR कोड के लिए)',
                      hintText: 'https://g.page/r/.../review',
                      prefixIcon: const Icon(Icons.star, color: Colors.amber),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 24),

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
    );
  }
}

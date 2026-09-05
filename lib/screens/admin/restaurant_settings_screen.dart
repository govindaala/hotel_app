import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _upiCtrl;
  late TextEditingController _gstCtrl;
  late TextEditingController _reviewCtrl;
  late TextEditingController _footerCtrl;

  bool _isEditing = false; // लॉक/एडिट मोड
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialProfile?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.initialProfile?.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.initialProfile?.address ?? '');
    _upiCtrl = TextEditingController(text: widget.initialProfile?.upiId ?? '');
    _gstCtrl = TextEditingController(text: '');
    _reviewCtrl = TextEditingController(text: '');
    _footerCtrl = TextEditingController(text: 'Thank You! Visit Again! 🙏');

    // अगर पहले से डेटा खाली है तो एडिट मोड खुला रहेगा
    if (widget.initialProfile == null || (widget.initialProfile!.phone?.isEmpty ?? true)) {
      _isEditing = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _upiCtrl.dispose();
    _gstCtrl.dispose();
    _reviewCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final upi = _upiCtrl.text.trim();

    if (name.isEmpty || phone.isEmpty || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया नाम, मोबाइल नंबर और पता अवश्य भरें!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final updatedModel = RestaurantProfileModel.fromMap({
      'store_code': widget.storeCode,
      'name': name,
      'phone': phone,
      'address': address,
      'upi_id': upi,
      'gst_number': _gstCtrl.text.trim(),
      'google_review_link': _reviewCtrl.text.trim(),
      'footer_message': _footerCtrl.text.trim(),
    });

    // 1. फ़ोन मेमोरी में सेव
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_hotel_name', name);
    await prefs.setString('saved_hotel_address_${widget.storeCode}', address);
    await prefs.setString('saved_hotel_phone_${widget.storeCode}', phone);
    await prefs.setString('saved_hotel_upi_${widget.storeCode}', upi);

    // 2. Supabase सर्वर पर सेव
    try {
      await Supabase.instance.client.from('restaurants').upsert({
        'store_code': widget.storeCode,
        'name': name,
        'phone': phone,
        'address': address,
        'upi_id': upi,
        'gst_number': _gstCtrl.text.trim(),
        'google_review_link': _reviewCtrl.text.trim(),
        'footer_message': _footerCtrl.text.trim(),
      }, onConflict: 'store_code');
    } catch (e) {
      debugPrint("Supabase profile upsert error: $e");
    }

    widget.onSave(updatedModel);

    setState(() {
      _isLoading = false;
      _isEditing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ प्रोफ़ाइल सर्वर और फ़ोन पर सुरक्षित हो गई!'), backgroundColor: Colors.teal),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('होटल प्रोफ़ाइल व सेटिंग्स', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          if (!_isEditing)
            TextButton.icon(
              icon: const Icon(Icons.edit, color: Colors.orangeAccent, size: 18),
              label: const Text('एडिट करें', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isEditing ? Colors.orange.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isEditing ? Colors.orange : Colors.green),
              ),
              child: Row(
                children: [
                  Icon(_isEditing ? Icons.edit_note : Icons.lock_outline, color: _isEditing ? Colors.orange : Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isEditing ? 'एडिट मोड चालू है: आप विवरण बदल सकते हैं।' : 'व्यू मोड: डेटा सुरक्षित (Locked) है। बदलाव के लिए ऊपर "एडिट करें" दबाएँ।',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _isEditing ? Colors.orange.shade900 : Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildField('होटल / रेस्टोरेंट का नाम *', _nameCtrl, Icons.store),
            _buildField('संपर्क नंबर (Mobile) *', _phoneCtrl, Icons.phone, keyboard: TextInputType.phone),
            _buildField('होटल का पता (Address) *', _addressCtrl, Icons.location_on, maxLines: 2),
            _buildField('UPI ID (जैसे: shop@upi) - QR बिल के लिए', _upiCtrl, Icons.qr_code),
            _buildField('GSTIN / FSSAI नंबर (वैकल्पिक)', _gstCtrl, Icons.receipt_long),
            _buildField('Google Review Link (रिव्यू QR के लिए)', _reviewCtrl, Icons.star_border),
            _buildField('बिल फुटर संदेश (Footer Message)', _footerCtrl, Icons.message),

            const SizedBox(height: 24),

            if (_isEditing)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isLoading ? null : _saveSettings,
                  icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.save, color: Colors.white),
                  label: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('सेटिंग्स सुरक्षित (Save) करें', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon, {TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: TextField(
        controller: ctrl,
        enabled: _isEditing,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: _isEditing ? Colors.orange : Colors.grey),
          filled: !_isEditing,
          fillColor: Colors.grey.shade100,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade400),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }
}

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
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _upiCtrl = TextEditingController();
  final TextEditingController _gstCtrl = TextEditingController();
  final TextEditingController _reviewCtrl = TextEditingController();
  final TextEditingController _footerCtrl = TextEditingController();

  bool _isEditing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  // फ़ोन मेमोरी और Supabase से डेटा खींचना
  Future<void> _loadCurrentData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. सबसे पहले फ़ोन मेमोरी से भरें
    String name = prefs.getString('saved_hotel_name') ?? widget.initialProfile?.name ?? 'होटल';
    String phone = prefs.getString('saved_hotel_phone') ?? widget.initialProfile?.phone ?? '';
    String address = prefs.getString('saved_hotel_address') ?? widget.initialProfile?.address ?? '';
    String upi = prefs.getString('saved_hotel_upi') ?? widget.initialProfile?.upiId ?? '';

    // 2. Supabase सर्वर से क्रॉस चेक करें
    try {
      final res = await Supabase.instance.client
          .from('restaurants')
          .select()
          .eq('store_code', widget.storeCode)
          .maybeSingle();

      if (res != null) {
        if ((res['name'] ?? '').toString().isNotEmpty) name = res['name'];
        if ((res['phone'] ?? '').toString().isNotEmpty) phone = res['phone'];
        if ((res['address'] ?? '').toString().isNotEmpty) address = res['address'];
        if ((res['upi_id'] ?? '').toString().isNotEmpty) upi = res['upi_id'];
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _nameCtrl.text = name;
        _phoneCtrl.text = phone;
        _addressCtrl.text = address;
        _upiCtrl.text = upi;
        _footerCtrl.text = 'Thank You! Visit Again! 🙏';
        _isLoading = false;
        // अगर फ़ोन और पता खाली है तो एडिट मोड खोलें, वर्ना लॉक रखें
        _isEditing = (phone.isEmpty && address.isEmpty);
      });
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

    // 1. फ़ोन मेमोरी (SharedPreferences) में पक्का सेव
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_hotel_name', name);
    await prefs.setString('saved_hotel_phone', phone);
    await prefs.setString('saved_hotel_address', address);
    await prefs.setString('saved_hotel_upi', upi);

    // 2. Supabase क्लाउड में पक्का सेव
    try {
      await Supabase.instance.client.from('restaurants').upsert({
        'store_code': widget.storeCode,
        'name': name,
        'phone': phone,
        'address': address,
        'upi_id': upi,
      }, onConflict: 'store_code');
    } catch (e) {
      debugPrint("Supabase save error: $e");
    }

    // 3. मॉडल बनाकर वापस भेजना
    final updatedModel = RestaurantProfileModel.fromMap({
      'store_code': widget.storeCode,
      'name': name,
      'phone': phone,
      'address': address,
      'upi_id': upi,
    });

    widget.onSave(updatedModel);

    setState(() {
      _isLoading = false;
      _isEditing = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ प्रोफ़ाइल सुरक्षित हो गई!'), backgroundColor: Colors.teal),
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
          if (!_isEditing && !_isLoading)
            TextButton.icon(
              icon: const Icon(Icons.edit, color: Colors.orangeAccent, size: 18),
              label: const Text('एडिट करें', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: const Text('सेटिंग्स सुरक्षित (Save) करें', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
        ),
      ),
    );
  }
}

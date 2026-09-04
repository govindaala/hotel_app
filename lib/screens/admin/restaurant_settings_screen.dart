import 'package:flutter/material.dart';
import '../../models/restaurant_profile_model.dart';

class RestaurantSettingsScreen extends StatefulWidget {
  final RestaurantProfileModel? initialProfile;
  final Function(RestaurantProfileModel updatedProfile) onSave;

  const RestaurantSettingsScreen({
    super.key,
    this.initialProfile,
    required this.onSave,
  });

  @override
  State<RestaurantSettingsScreen> createState() => _RestaurantSettingsScreenState();
}

class _RestaurantSettingsScreenState extends State<RestaurantSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _gstinCtrl;
  late TextEditingController _upiCtrl;
  late TextEditingController _footerCtrl;
  late TextEditingController _reviewUrlCtrl;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _phoneCtrl = TextEditingController(text: p?.phone ?? '');
    _addressCtrl = TextEditingController(text: p?.address ?? '');
    _gstinCtrl = TextEditingController(text: p?.gstin ?? '');
    _upiCtrl = TextEditingController(text: p?.upiId ?? '');
    _footerCtrl = TextEditingController(text: p?.footerMessage ?? 'धन्यवाद! फिर पधारें! 🙏');
    _reviewUrlCtrl = TextEditingController(text: p?.reviewUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _gstinCtrl.dispose();
    _upiCtrl.dispose();
    _footerCtrl.dispose();
    _reviewUrlCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final updated = RestaurantProfileModel(
        id: widget.initialProfile?.id ?? '',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        gstin: _gstinCtrl.text.trim().isEmpty ? null : _gstinCtrl.text.trim(),
        upiId: _upiCtrl.text.trim().isEmpty ? null : _upiCtrl.text.trim(),
        footerMessage: _footerCtrl.text.trim(),
        reviewUrl: _reviewUrlCtrl.text.trim().isEmpty ? null : _reviewUrlCtrl.text.trim(),
      );
      widget.onSave(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('प्रोफ़ाइल सेटिंग्स सुरक्षित हो गईं!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('होटल प्रोफ़ाइल व सेटिंग्स'),
        backgroundColor: Colors.deepOrange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'होटल / रेस्टोरेंट का नाम *', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'नाम दर्ज करें' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'संपर्क नंबर (Mobile) *', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'नंबर दर्ज करें' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'होटल का पता (Address) *', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'पता दर्ज करें' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _upiCtrl,
                decoration: const InputDecoration(labelText: 'UPI ID (जैसे: shop@upi) - QR बिल के लिए', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _gstinCtrl,
                decoration: const InputDecoration(labelText: 'GSTIN / FSSAI नंबर (वैकल्पिक)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reviewUrlCtrl,
                decoration: const InputDecoration(labelText: 'Google Review Link (रिव्यू QR के लिए)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _footerCtrl,
                decoration: const InputDecoration(labelText: 'बिल फुटर संदेश (Footer Message)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                  onPressed: _submit,
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: const Text('सेटिंग्स सेव करें', style: TextStyle(fontSize: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// lib/screens/admin/vendor_ration_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/vendor_model.dart';
import '../../models/partner_model.dart';
import '../../services/kitchen_learning_service.dart';

class VendorRationScreen extends StatefulWidget {
  final String storeCode;

  const VendorRationScreen({Key? key, required this.storeCode}) : super(key: key);

  @override
  State<VendorRationScreen> createState() => _VendorRationScreenState();
}

class _VendorRationScreenState extends State<VendorRationScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<AdvancedRationDemandModel> _demands = [];
  List<HotelVendorModel> _vendors = [];
  List<RestaurantPartnerModel> _partners = [];
  List<Map<String, dynamic>> _aiPredictions = [];

  String _selectedCategory = 'ALL'; // 'ALL', 'DAIRY', 'VEGETABLE', 'GROCERY'

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      // 1. वेंडर्स लोड करना
      final vendorRes = await _supabase
          .from('hotel_vendors')
          .select('*')
          .eq('store_code', widget.storeCode);

      final loadedVendors = (vendorRes as List)
          .map((v) => HotelVendorModel.fromMap(v))
          .where((vendor) => vendor.isActive)
          .toList();

      final partnerRes = await _supabase
          .from('restaurant_partners')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: true);
      final loadedPartners = (partnerRes as List)
          .map((row) => RestaurantPartnerModel.fromMap(row))
          .toList();

      // 2. राशन डिमांड्स लोड करना
      final demandsRes = await _supabase
          .from('ration_demands')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: false)
          .limit(100);

      final loadedDemands = (demandsRes as List)
          .map((d) => AdvancedRationDemandModel.fromMap(d))
          .toList();

      // 3. AI वीकेंड प्रेडिक्शन फेच करना
      final predictions = await KitchenLearningService.predictWeekendRation(
        storeCode: widget.storeCode,
      );

      if (mounted) setState(() {
        _vendors = loadedVendors;
        _partners = loadedPartners;
        _demands = loadedDemands;
        _aiPredictions = predictions;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('डेटा लोड त्रुटि: $e')),
        );
      }
    }
  }

  // वेंडर को व्हाट्सएप पर सामान की लिस्ट भेजना
  Future<void> _sendWhatsAppSlip(String category) async {
    final pendingItems = _demands
        .where((d) => !d.isReceived && (category == 'ALL' || d.vendorCategory == category))
        .toList();

    if (pendingItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('भेजने के लिए कोई पेंडिंग सामान नहीं है')),
      );
      return;
    }

    final vendor = _vendors.firstWhere(
      (v) => v.category == category,
      orElse: () => HotelVendorModel(
        id: '',
        storeCode: widget.storeCode,
        vendorName: 'सप्लायर',
        category: category,
        phone: '',
      ),
    );

    final buffer = StringBuffer();
    buffer.writeln('📋 *होटल राशन आवश्यकता (${vendor.vendorName})*');
    buffer.writeln('होटल कोड: ${widget.storeCode}');
    buffer.writeln('दिनांक: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}');
    buffer.writeln('---------------------------');

    for (int i = 0; i < pendingItems.length; i++) {
      buffer.writeln('${i + 1}. ${pendingItems[i].itemName} - *${pendingItems[i].quantity}*');
    }
    buffer.writeln('---------------------------');
    buffer.writeln('कृपया जल्द से जल्द भेजें। धन्यवाद!');

    final message = Uri.encodeComponent(buffer.toString());
    final phone = vendor.phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final urlString = phone.isNotEmpty
        ? 'whatsapp://send?phone=91$phone&text=$message'
        : 'whatsapp://send?text=$message';

    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // यदि वॉट्सऐप प्रोटोकॉल न खुले, तो वेब लिंक का बैकअप
      final webUrl = Uri.parse(
        phone.isNotEmpty
            ? 'https://wa.me/91$phone?text=$message'
            : 'https://wa.me/?text=$message',
      );
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  // सामान रिसीव करना और खर्च का माध्यम दर्ज करना
  void _openReceiveDialog(AdvancedRationDemandModel item) {
    final costController = TextEditingController(
      text: item.purchaseCost > 0 ? item.purchaseCost.toStringAsFixed(2) : '',
    );
    String paidBy = item.paidBy;
    final categoryVendors = _vendors
        .where((vendor) => item.vendorCategory == null || vendor.category == item.vendorCategory)
        .toList();
    final availableVendors = categoryVendors.isNotEmpty ? categoryVendors : _vendors;
    String? selectedVendorId = availableVendors.any((v) => v.id == item.vendorId)
        ? item.vendorId
        : (availableVendors.isNotEmpty ? availableVendors.first.id : null);
    String? selectedPartnerId = _partners.isNotEmpty ? _partners.first.partnerId : null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('सामान रिसीव: ${item.itemName}', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('मात्रा: ${item.quantity}', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedVendorId,
                  decoration: const InputDecoration(
                    labelText: 'सप्लायर / वेंडर',
                    border: OutlineInputBorder(),
                  ),
                  items: availableVendors.map((vendor) => DropdownMenuItem(
                    value: vendor.id,
                    child: Text(vendor.vendorName),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => selectedVendorId = value),
                ),
                if (availableVendors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('वेंडर दर्ज नहीं है; क्रेडिट पर रिसीव करने से पहले वेंडर जोड़ें।',
                        style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'खरीद लागत (₹)',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('भुगतान का माध्यम:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: paidBy,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'DRAWER_CASH', child: Text('होटल गल्ले से कैश')),
                    DropdownMenuItem(value: 'UPI', child: Text('ऑनलाइन UPI')),
                    DropdownMenuItem(value: 'PARTNER_POCKET', child: Text('पार्टनर ने अपनी जेब से दिया')),
                    DropdownMenuItem(value: 'CREDIT', child: Text('उधारी / वेंडर खाता')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => paidBy = value);
                  },
                ),
                if (paidBy == 'PARTNER_POCKET') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedPartnerId,
                    decoration: const InputDecoration(
                      labelText: 'खर्च करने वाला पार्टनर',
                      border: OutlineInputBorder(),
                    ),
                    items: _partners.map((partner) => DropdownMenuItem(
                      value: partner.partnerId,
                      child: Text(partner.partnerName),
                    )).toList(),
                    onChanged: (value) => setDialogState(() => selectedPartnerId = value),
                  ),
                  if (_partners.isEmpty)
                    const Text('पहले होटल सेटिंग्स में पार्टनर जोड़ें।',
                        style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                ],
                if (paidBy == 'CREDIT')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('उधारी राशि वेंडर के बकाया बैलेंस में जुड़ेगी।',
                        style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('रद्द करें'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () async {
                final cost = double.tryParse(costController.text.trim()) ?? 0.0;
                if (cost <= 0) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('सही खरीद लागत दर्ज करें।')),
                  );
                  return;
                }
                if (paidBy == 'CREDIT' && selectedVendorId == null) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('उधारी दर्ज करने के लिए वेंडर चुनें।')),
                  );
                  return;
                }
                if (paidBy == 'PARTNER_POCKET' && selectedPartnerId == null) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('पार्टनर चुनें।')),
                  );
                  return;
                }

                final matchingVendor = availableVendors.where((v) => v.id == selectedVendorId);
                final selectedVendor = matchingVendor.isEmpty ? null : matchingVendor.first;
                final matchingPartner = _partners.where((p) => p.partnerId == selectedPartnerId);
                final selectedPartner = matchingPartner.isEmpty ? null : matchingPartner.first;
                final expenseType = switch (paidBy) {
                  'UPI' => 'EXPENSE_UPI',
                  'PARTNER_POCKET' => 'EXPENSE_PARTNER',
                  'CREDIT' => 'EXPENSE_CREDIT',
                  _ => 'EXPENSE_CASH',
                };
                final now = DateTime.now().toIso8601String();
                String? expenseId;
                String? ledgerId;
                bool vendorBalanceUpdated = false;

                try {
                  final expenseRow = await _supabase.from('daily_expenses').insert({
                    'store_code': widget.storeCode,
                    'restaurant_id': widget.storeCode,
                    'title': 'राशन खरीद: ${item.itemName} (${item.quantity})',
                    'amount': cost,
                    'type': expenseType,
                    'created_at': now,
                  }).select('id').single();
                  expenseId = expenseRow['id'].toString();

                  if (paidBy == 'PARTNER_POCKET' && selectedPartner != null) {
                    final ledgerRow = await _supabase.from('partner_ledger').insert({
                      'store_code': widget.storeCode,
                      'partner_id': selectedPartner.partnerId,
                      'partner_name': selectedPartner.partnerName,
                      'type': 'POCKET_EXPENSE',
                      'amount': cost,
                      'note': 'राशन खरीद: ${item.itemName} (${item.quantity})',
                      'created_at': now,
                    }).select('id').single();
                    ledgerId = ledgerRow['id'].toString();
                  }

                  if (paidBy == 'CREDIT' && selectedVendor != null) {
                    await _supabase.from('hotel_vendors').update({
                      'current_balance': selectedVendor.currentBalance + cost,
                    }).eq('id', selectedVendor.id);
                    vendorBalanceUpdated = true;
                  }

                  await _supabase.from('ration_demands').update({
                    'is_received': true,
                    'purchase_cost': cost,
                    'paid_by': paidBy,
                    'vendor_id': selectedVendorId,
                    'vendor_category': selectedVendor?.category ?? item.vendorCategory,
                    'partner_name': selectedPartner?.partnerName,
                  }).eq('id', item.id);

                  if (mounted) Navigator.pop(dialogContext);
                  await _loadAllData();
                } catch (error) {
                  if (vendorBalanceUpdated && selectedVendor != null) {
                    try {
                      await _supabase.from('hotel_vendors').update({
                        'current_balance': selectedVendor.currentBalance,
                      }).eq('id', selectedVendor.id);
                    } catch (_) {}
                  }
                  if (ledgerId != null) {
                    try {
                      await _supabase.from('partner_ledger').delete().eq('id', ledgerId);
                    } catch (_) {}
                  }
                  if (expenseId != null) {
                    try {
                      await _supabase.from('daily_expenses').delete().eq('id', expenseId);
                    } catch (_) {}
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text('रिसीव/लेजर अपडेट नहीं हुआ; कृपया दोबारा जाँचें: $error')),
                    );
                  }
                }
              },
              child: const Text('कन्फर्म रिसीव', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // AI अनुमान को एक टैप में राशन लिस्ट में जोड़ना
  Future<void> _applyAiPrediction(Map<String, dynamic> p) async {
    try {
      await _supabase.from('ration_demands').insert({
        'store_code': widget.storeCode,
        'item_name': p['item_name'],
        'quantity': p['quantity'],
        'is_received': false,
        'vendor_category': p['item_name'].toString().contains('दूध') || p['item_name'].toString().contains('पनीर')
            ? 'DAIRY'
            : p['item_name'].toString().contains('प्याज') || p['item_name'].toString().contains('टमाटर')
                ? 'VEGETABLE'
                : 'GROCERY',
        'created_at': DateTime.now().toIso8601String(),
      });
      _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${p['item_name']} राशन लिस्ट में जुड़ गया')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final filteredDemands = _selectedCategory == 'ALL'
        ? _demands
        : _demands.where((d) => d.vendorCategory == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('स्मार्ट राशन व वेंडर प्रबंधन', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAllData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 1. AI वीकेंड प्रेडिक्शन कार्ड (Smart Grocery Forecast)
                  if (_aiPredictions.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF312E81), Color(0xFF4338CA)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'AI वीकेंड राशन अनुमान (पिछले 3 हफ़्तों की सेल से)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _aiPredictions.map((pred) {
                              return ActionChip(
                                backgroundColor: Colors.white.withOpacity(0.15),
                                label: Text(
                                  '+ ${pred['item_name']}: ${pred['quantity']}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                onPressed: () => _applyAiPrediction(pred),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 2. वेंडर व्हाट्सएप पर्ची शॉर्टकट्स
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          label: const Text('सब्जी पर्ची', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () => _sendWhatsAppSlip('VEGETABLE'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          label: const Text('डेयरी पर्ची', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () => _sendWhatsAppSlip('DAIRY'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[800],
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                          label: const Text('किराना पर्ची', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onPressed: () => _sendWhatsAppSlip('GROCERY'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 3. केटेगरी फ़िल्टर टैब्स
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterBadge('सभी', 'ALL'),
                        const SizedBox(width: 8),
                        _buildFilterBadge('🥦 सब्जियां', 'VEGETABLE'),
                        const SizedBox(width: 8),
                        _buildFilterBadge('🥛 डेयरी', 'DAIRY'),
                        const SizedBox(width: 8),
                        _buildFilterBadge('🌾 किराना', 'GROCERY'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. राशन मांग सूची
                  if (filteredDemands.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('इस केटेगरी में कोई राशन डिमांड नहीं है', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredDemands.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final item = filteredDemands[idx];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: item.isReceived ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: item.isReceived ? Colors.green[50] : Colors.orange[50],
                                child: Icon(
                                  item.isReceived ? Icons.check_circle : Icons.hourglass_top,
                                  color: item.isReceived ? Colors.green[700] : Colors.orange[800],
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.itemName,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        decoration: item.isReceived ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'मात्रा: ${item.quantity}  •  ${item.vendorCategory ?? "GROCERY"}',
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                    if (item.isReceived && item.purchaseCost > 0)
                                      Text(
                                        'भुगतान: ₹${item.purchaseCost.toStringAsFixed(0)} (${item.paidBy})',
                                        style: TextStyle(color: Colors.green[800], fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                              ),
                              if (!item.isReceived)
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo[600],
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () => _openReceiveDialog(item),
                                  child: const Text('रिसीव', style: TextStyle(color: Colors.white, fontSize: 12)),
                                )
                              else
                                const Chip(
                                  label: Text('आ गया', style: TextStyle(fontSize: 11, color: Colors.green)),
                                  backgroundColor: Color(0xFFDCFCE7),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterBadge(String title, String val) {
    final isSelected = _selectedCategory == val;
    return ChoiceChip(
      label: Text(title),
      selected: isSelected,
      selectedColor: const Color(0xFF0F172A),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (_) => setState(() => _selectedCategory = val),
    );
  }
}

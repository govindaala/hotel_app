// lib/screens/admin/partner_ledger_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/partner_model.dart';

class PartnerLedgerScreen extends StatefulWidget {
  final String storeCode;

  const PartnerLedgerScreen({Key? key, required this.storeCode}) : super(key: key);

  @override
  State<PartnerLedgerScreen> createState() => _PartnerLedgerScreenState();
}

class _PartnerLedgerScreenState extends State<PartnerLedgerScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<RestaurantPartnerModel> _partners = [];
  List<PartnerLedgerModel> _ledgerHistory = [];

  double _monthlySales = 0.0;
  double _monthlyExpenses = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchPartnerData();
  }

  Future<void> _fetchPartnerData() async {
    setState(() => _isLoading = true);
    try {
      final partnersRes = await _supabase
          .from('restaurant_partners')
          .select('*')
          .eq('store_code', widget.storeCode)
          .eq('is_active', true);

      final List<RestaurantPartnerModel> loadedPartners = (partnersRes as List)
          .map((e) => RestaurantPartnerModel.fromMap(e))
          .toList();

      final ledgerRes = await _supabase
          .from('partner_ledger')
          .select('*')
          .eq('store_code', widget.storeCode)
          .order('created_at', ascending: false)
          .limit(100);

      final List<PartnerLedgerModel> loadedLedger = (ledgerRes as List)
          .map((e) => PartnerLedgerModel.fromMap(e))
          .toList();

      final now = DateTime.now();
      final firstDayOfMonth = DateTime(now.year, now.month, 1).toIso8601String();

      final expenseData = await _supabase
          .from('daily_expenses')
          .select('amount, type')
          .eq('store_code', widget.storeCode)
          .gte('created_at', firstDayOfMonth);

      double salesSum = 0.0;
      double expenseSum = 0.0;

      for (var row in (expenseData as List)) {
        final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (row['type'] ?? '').toString().toUpperCase();
        if (type.contains('SALE') || type.contains('INCOME')) {
          salesSum += amt;
        } else {
          expenseSum += amt;
        }
      }

      setState(() {
        _partners = loadedPartners;
        _ledgerHistory = loadedLedger;
        _monthlySales = salesSum;
        _monthlyExpenses = expenseSum;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('डेटा लोड करने में त्रुटि: $e')),
        );
      }
    }
  }

  void _openAddTransactionModal(String defaultType) {
    if (_partners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया पहले एडमिन से पार्टनर जोड़ें')),
      );
      return;
    }

    RestaurantPartnerModel selectedPartner = _partners.first;
    String type = defaultType;
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type == 'POCKET_EXPENSE'
                        ? 'पार्टनर ने जेब से खर्च किया (+ क्रेडिट)'
                        : 'पार्टनर ने गल्ले से पैसा निकाला (- डेबिट)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: type == 'POCKET_EXPENSE' ? Colors.green[800] : Colors.red[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<RestaurantPartnerModel>(
                    value: selectedPartner,
                    decoration: const InputDecoration(
                      labelText: 'पार्टनर चुनें',
                      border: OutlineInputBorder(),
                    ),
                    items: _partners.map((p) {
                      return DropdownMenuItem(
                        value: p,
                        child: Text('${p.partnerName} (${p.sharePercentage.toStringAsFixed(0)}%)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedPartner = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'रकम (₹)',
                      border: OutlineInputBorder(),
                      prefixText: '₹ ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'विवरण (उदा. मंडी से टमाटर/व्यक्तिगत खर्च)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: type == 'POCKET_EXPENSE' ? Colors.green[700] : Colors.red[700],
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final amt = double.tryParse(amountController.text.trim()) ?? 0.0;
                        if (amt <= 0) return;

                        final newLedger = PartnerLedgerModel(
                          id: '',
                          storeCode: widget.storeCode,
                          partnerId: selectedPartner.partnerId,
                          partnerName: selectedPartner.partnerName,
                          type: type,
                          amount: amt,
                          note: noteController.text.trim(),
                          createdAt: DateTime.now(),
                        );

                        await _supabase.from('partner_ledger').insert(newLedger.toMap());
                        Navigator.pop(ctx);
                        _fetchPartnerData();
                      },
                      child: const Text('सुरक्षित करें (Save)', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showProfitSplitDialog() {
    final double netProfit = (_monthlySales - _monthlyExpenses).clamp(0.0, double.infinity);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('📊 चालू माह का बंटवारा (Profit Split Audit)', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[50],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('कुल बिक्री (Sales):'),
                          Text('₹${_monthlySales.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('कुल खर्चे (Expenses):'),
                          Text('₹${_monthlyExpenses.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('शुद्ध मुनाफा (Net Profit):', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text('₹${netProfit.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('पार्टनर-वाइज़ फाइनल पे-आउट:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._partners.map((p) {
                  final double baseShare = (netProfit * p.sharePercentage) / 100.0;

                  double pocketExp = 0.0;
                  double drawings = 0.0;

                  for (var row in _ledgerHistory) {
                    if (row.partnerId == p.partnerId) {
                      if (row.type == 'POCKET_EXPENSE') pocketExp += row.amount;
                      if (row.type == 'DRAWING') drawings += row.amount;
                    }
                  }

                  final double finalPayout = baseShare + pocketExp - drawings;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p.partnerName} (${p.sharePercentage.toStringAsFixed(0)}% शेयर)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('• मुनाफे का हिस्सा: ₹${baseShare.toStringAsFixed(0)}'),
                        Text('• जेब से किया खर्च: +₹${pocketExp.toStringAsFixed(0)}', style: const TextStyle(color: Colors.green)),
                        Text('• गल्ले से निकाला एडवांस: -₹${drawings.toStringAsFixed(0)}', style: const TextStyle(color: Colors.red)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('अंतिम मिलने योग्य रकम:', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('₹${finalPayout.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('बंद करें'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('पार्टनर लेज़र व लाभ बंटवारा', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'प्रॉफिट-स्प्लिट गणना',
            onPressed: _showProfitSplitDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPartnerData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchPartnerData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 20),
                            label: const Text('जेब से खर्च', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => _openAddTransactionModal('POCKET_EXPENSE'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[700],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 20),
                            label: const Text('गल्ले से निकासी', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => _openAddTransactionModal('DRAWING'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const Text('पार्टनर्स एवं हिस्सेदारी', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    if (_partners.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber[300]!),
                        ),
                        child: const Text('कोई पार्टनर नहीं मिला। कृपया एडमिन से पार्टनर जोड़ें।'),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _partners.length,
                        itemBuilder: (ctx, i) {
                          final p = _partners[i];
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: Colors.indigo[100],
                                        child: Text(p.partnerName[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          p.partnerName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text('शेयर: ${p.sharePercentage.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('पिन: ****', style: TextStyle(color: Colors.blueGrey[400], fontSize: 11)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('हाल के लेन-देन (Ledger Activity)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: _showProfitSplitDialog,
                          child: const Text('पूर्ण रिपोर्ट >'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_ledgerHistory.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('अभी तक कोई लेन-देन दर्ज नहीं है।', style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _ledgerHistory.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final entry = _ledgerHistory[i];
                          final isPocket = entry.type == 'POCKET_EXPENSE';
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPocket ? Colors.green[50] : Colors.red[50],
                              child: Icon(
                                isPocket ? Icons.arrow_upward : Icons.arrow_downward,
                                color: isPocket ? Colors.green[700] : Colors.red[700],
                                size: 18,
                              ),
                            ),
                            title: Text(entry.partnerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(entry.note ?? (isPocket ? 'जेब खर्च' : 'गल्ला निकासी')),
                            trailing: Text(
                              '${isPocket ? "+" : "-"}₹${entry.amount.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isPocket ? Colors.green[700] : Colors.red[700],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

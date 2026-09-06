import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CounterReportsScreen extends StatefulWidget {
  final String storeCode;

  const CounterReportsScreen({Key? key, required this.storeCode}) : super(key: key);

  @override
  State<CounterReportsScreen> createState() => _CounterReportsScreenState();
}

class _CounterReportsScreenState extends State<CounterReportsScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String? errorMessage;
  int recordCount = 0;

  String selectedFilter = 'This Month'; // 'Today', 'This Week', 'This Month'
  String chartView = 'Month'; // 'Year', 'Month', 'Day'

  double totalSales = 0.0;
  double avgDailySales = 0.0;

  // 1. मोड-वाइज (Pick Up vs Table)
  int pickupOrders = 0;
  double pickupAmount = 0.0;
  int tableOrders = 0;
  double tableAmount = 0.0;

  // 2. पेमेंट मोड-वाइज
  double cashAmount = 0.0;
  double upiAmount = 0.0;
  double otherAmount = 0.0;

  // 4. चार्ट डेटा (दिन और उनकी सेल)
  Map<int, double> dailyChartData = {};

  @override
  void initState() {
    super.initState();
    loadReportData();
  }

  Future<void> loadReportData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final now = DateTime.now();
      DateTime startDate;

      if (selectedFilter == 'Today') {
        startDate = DateTime(now.year, now.month, now.day);
      } else if (selectedFilter == 'This Week') {
        startDate = now.subtract(Duration(days: now.weekday - 1));
      } else {
        // This Month
        startDate = DateTime(now.year, now.month, 1);
      }

      // Supabase से daily_expenses टेबल का डेटा फेच करें
      final response = await supabase
          .from('daily_expenses')
          .select('*')
          .eq('restaurant_id', widget.storeCode)
          .gte('created_at', startDate.toIso8601String())
          .order('created_at', ascending: true);

      final List<dynamic> salesList = response as List<dynamic>;

      // गणनाएँ रीसेट करें
      totalSales = 0.0;
      pickupOrders = 0;
      pickupAmount = 0.0;
      tableOrders = 0;
      tableAmount = 0.0;
      cashAmount = 0.0;
      upiAmount = 0.0;
      otherAmount = 0.0;
      dailyChartData.clear();
      recordCount = 0;

      for (var sale in salesList) {
        final String title = (sale['title'] ?? '').toString().toUpperCase();
        final String type = (sale['type'] ?? '').toString().toLowerCase();
        
        // सिर्फ "जमा" (Income/Sale) वाले रिकॉर्ड ही लें (खर्च को छोड़ दें)
        if (type == 'expense' || (!title.contains('SALE') && !title.contains('सेल') && !title.contains('(CASH)') && !title.contains('(UPI)'))) {
          continue; 
        }

        final double amount = ((sale['amount'] ?? 0.0) as num).toDouble();
        if (amount <= 0) continue;

        recordCount++;
        totalSales += amount;

        // मोड-वाइज (Pick Up vs Dine-In)
        if (title.contains('PARCEL') || title.contains('पार्सल') || title.contains('PICKUP')) {
          pickupOrders++;
          pickupAmount += amount;
        } else if (title.contains('TABLE') || title.contains('टेबल')) {
          tableOrders++;
          tableAmount += amount;
        }

        // पेमेंट मोड-वाइज
        if (title.contains('UPI') || title.contains('ONLINE')) {
          upiAmount += amount;
        } else if (title.contains('CASH') || title.contains('नकद')) {
          cashAmount += amount;
        } else {
          otherAmount += amount;
        }

        // चार्ट डेटा (तारीख वार ग्रुपिंग)
        final DateTime createdAt = DateTime.tryParse(sale['created_at'].toString()) ?? now;
        dailyChartData[createdAt.day] = (dailyChartData[createdAt.day] ?? 0.0) + amount;
      }

      // औसत दैनिक सेल
      final int daysCount = now.day > 0 ? now.day : 1;
      avgDailySales = totalSales / (selectedFilter == 'Today' ? 1 : daysCount);

    } catch (e) {
      errorMessage = e.toString();
      debugPrint('Report Fetch Error: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'माय रिपोर्ट्स (${widget.storeCode})',
          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0284C7)),
            onPressed: loadReportData,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('डेटा लोड नहीं हुआ:\n$errorMessage', style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),

                  if (errorMessage == null && recordCount == 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('स्टोर कोड "${widget.storeCode}" के लिए इस समयावधि ($selectedFilter) में कोई बिक्री रिकॉर्ड नहीं मिला।', style: const TextStyle(color: Color(0xFF92400E), fontSize: 12)),
                          ),
                        ],
                      ),
                    ),

                  _buildSalesChartCard(),
                  const SizedBox(height: 16),
                  _buildFilterCard(),
                  const SizedBox(height: 16),
                  _buildModeWiseCard(),
                  const SizedBox(height: 16),
                  _buildPaymentWiseCard(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildSalesChartCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, color: Color(0xFF0284C7), size: 20),
                SizedBox(width: 8),
                Text('Sales Chart', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: ['Year', 'Month', 'Day'].map((view) {
                  final isSelected = chartView == view;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => chartView = view),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF08566E) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(view, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Text('₹${totalSales.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Avg:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Text('₹${avgDailySales.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(10, (index) {
                  final day = index + 1;
                  final dayAmount = dailyChartData[day] ?? 0.0;
                  final maxVal = totalSales > 0 ? totalSales * 0.4 : 1000.0;
                  final double barHeight = (dayAmount / maxVal).clamp(0.08, 1.0) * 80;

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (dayAmount > 0)
                          Text('${(dayAmount / 1000).toStringAsFixed(1)}K', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF08566E))),
                        const SizedBox(height: 2),
                        Container(
                          width: 14,
                          height: barHeight,
                          decoration: BoxDecoration(color: dayAmount > 0 ? const Color(0xFF08566E) : const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(height: 4),
                        Text('$day', style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Text('Select Period', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
            ],
          ),
          DropdownButton<String>(
            value: selectedFilter,
            underline: const SizedBox(),
            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF0284C7)),
            items: ['Today', 'This Week', 'This Month'].map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => selectedFilter = val);
                loadReportData();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeWiseCard() {
    return _buildCard(
      title: 'Mode-wise Breakdown',
      icon: Icons.pie_chart_outline,
      iconColor: Colors.teal,
      children: [
        _buildRowItem(icon: Icons.directions_walk, title: 'Pick Up', subtitle: '$pickupOrders orders', amount: pickupAmount),
        const Divider(height: 16),
        _buildRowItem(icon: Icons.table_restaurant_outlined, title: 'Table', subtitle: '$tableOrders orders', amount: tableAmount),
        const Divider(height: 20, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('TOTAL (${pickupOrders + tableOrders} orders)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text('₹${(pickupAmount + tableAmount).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentWiseCard() {
    return _buildCard(
      title: 'Payment Mode-wise Breakdown',
      icon: Icons.account_balance_wallet_outlined,
      iconColor: Colors.blueAccent,
      children: [
        _buildRowItem(icon: Icons.money, title: 'Cash', amount: cashAmount),
        const Divider(height: 16),
        _buildRowItem(icon: Icons.qr_code_2, title: 'UPI', amount: upiAmount),
        const Divider(height: 20, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text('₹${(cashAmount + upiAmount).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildCard({required String title, required IconData icon, required Color iconColor, required List<Widget> children}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildRowItem({required IconData icon, required String title, String? subtitle, required double amount}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        if (subtitle != null) ...[
          const Spacer(),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        ],
        const Spacer(),
        Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
      ],
    );
  }
}

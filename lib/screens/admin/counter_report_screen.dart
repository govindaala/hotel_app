import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

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

  String selectedFilter = 'This Month'; // 'Today', 'This Week', 'This Month'
  int touchedBarIndex = -1;
  int touchedPieIndex = -1;

  double totalSales = 0.0;
  double avgSales = 0.0;
  int totalOrders = 0;

  // मोड-वाइज (पिकअप बनाम टेबल)
  int pickupOrders = 0;
  double pickupAmount = 0.0;
  int tableOrders = 0;
  double tableAmount = 0.0;

  // पेमेंट मोड-वाइज
  double cashAmount = 0.0;
  double upiAmount = 0.0;

  // चार्ट डेटा बकेट्स
  Map<int, double> chartDataBuckets = {};

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
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
      } else {
        startDate = DateTime(now.year, now.month, 1);
      }

      final response = await supabase
          .from('daily_expenses')
          .select('*')
          .eq('restaurant_id', widget.storeCode)
          .gte('created_at', startDate.toIso8601String())
          .order('created_at', ascending: true);

      final List<dynamic> salesList = response as List<dynamic>;

      totalSales = 0.0;
      totalOrders = 0;
      pickupOrders = 0;
      pickupAmount = 0.0;
      tableOrders = 0;
      tableAmount = 0.0;
      cashAmount = 0.0;
      upiAmount = 0.0;
      chartDataBuckets.clear();

      for (var sale in salesList) {
        final String title = (sale['title'] ?? '').toString().toUpperCase();
        final String type = (sale['type'] ?? '').toString().toUpperCase();

        // केवल बिक्री / जमा रिकॉर्ड लें
        if (type == 'EXPENSE') continue;
        if (!type.contains('CASH_IN') && !title.contains('SALE') && !title.contains('सेल')) {
          continue;
        }

        final double amount = ((sale['amount'] ?? 0.0) as num).toDouble();
        if (amount <= 0) continue;

        totalOrders++;
        totalSales += amount;

        // मोड वर्गीकरण
        if (title.contains('PARCEL') || title.contains('पार्सल') || title.contains('PICKUP')) {
          pickupOrders++;
          pickupAmount += amount;
        } else {
          tableOrders++;
          tableAmount += amount;
        }

        // भुगतान माध्यम
        if (title.contains('UPI') || title.contains('ONLINE') || title.contains('बैंक')) {
          upiAmount += amount;
        } else {
          cashAmount += amount;
        }

        // टाइम बकेटिंग
        final DateTime dt = DateTime.tryParse(sale['created_at'].toString()) ?? now;
        if (selectedFilter == 'Today') {
          // घंटों के अनुसार (0-23)
          chartDataBuckets[dt.hour] = (chartDataBuckets[dt.hour] ?? 0.0) + amount;
        } else if (selectedFilter == 'This Week') {
          // सप्ताह के दिन अनुसार (1-7)
          chartDataBuckets[dt.weekday] = (chartDataBuckets[dt.weekday] ?? 0.0) + amount;
        } else {
          // महीने की तारीख अनुसार (1-31)
          chartDataBuckets[dt.day] = (chartDataBuckets[dt.day] ?? 0.0) + amount;
        }
      }

      final int divisor = selectedFilter == 'Today'
          ? (now.hour > 0 ? now.hour : 1)
          : (selectedFilter == 'This Week' ? now.weekday : (now.day > 0 ? now.day : 1));
      avgSales = totalSales / divisor;
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'बिक्री विश्लेषण (${widget.storeCode})',
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (errorMessage != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Text('त्रुटि: $errorMessage', style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),

                  _buildPeriodSelector(),
                  const SizedBox(height: 16),
                  _buildMetricsRow(),
                  const SizedBox(height: 16),
                  _buildBarChartCard(),
                  const SizedBox(height: 16),
                  _buildPaymentRatioCard(),
                  const SizedBox(height: 16),
                  _buildOrderModeCard(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: ['Today', 'This Week', 'This Month'].map((period) {
          final isSel = selectedFilter == period;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => selectedFilter = period);
                loadReportData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFF0F172A) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Text(
                  period == 'Today' ? 'आज' : (period == 'This Week' ? 'साप्ताहिक' : 'मासिक'),
                  style: TextStyle(
                    color: isSel ? Colors.white : const Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        _buildMetricBox('कुल बिक्री', '₹${totalSales.toStringAsFixed(0)}', const Color(0xFF0284C7), Icons.payments_outlined),
        const SizedBox(width: 8),
        _buildMetricBox('औसत बिक्री', '₹${avgSales.toStringAsFixed(0)}', const Color(0xFFD97706), Icons.trending_up),
        const SizedBox(width: 8),
        _buildMetricBox('कुल ऑर्डर्स', '$totalOrders', const Color(0xFF059669), Icons.receipt_long_outlined),
      ],
    );
  }

  Widget _buildMetricBox(String title, String val, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(val, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartCard() {
    final List<BarChartGroupData> barGroups = [];
    int maxItems = selectedFilter == 'Today' ? 24 : (selectedFilter == 'This Week' ? 7 : 31);
    double maxY = 1000;

    for (int i = 1; i <= maxItems; i++) {
      final val = chartDataBuckets[selectedFilter == 'Today' ? i - 1 : i] ?? 0.0;
      if (val > maxY) maxY = val;
    }
    maxY = (maxY * 1.25).ceilToDouble();

    for (int i = 1; i <= maxItems; i++) {
      final key = selectedFilter == 'Today' ? i - 1 : i;
      final val = chartDataBuckets[key] ?? 0.0;
      final isTouched = (i - 1) == touchedBarIndex;

      barGroups.add(
        BarChartGroupData(
          x: key,
          barRods: [
            BarChartRodData(
              toY: val,
              gradient: LinearGradient(
                colors: isTouched
                    ? [Colors.tealAccent, Colors.teal]
                    : [const Color(0xFF0284C7), const Color(0xFF0F172A)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: selectedFilter == 'This Month' ? 6 : 14,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: const Color(0xFFF1F5F9),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  selectedFilter == 'Today' ? 'घंटे अनुसार बिक्री (Peak Hours)' : 'बिक्री ट्रेंड्स',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                ),
                const Icon(Icons.bar_chart, color: Color(0xFF0284C7), size: 20),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF0F172A),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '₹${rod.toY.toStringAsFixed(0)}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      },
                    ),
                    touchCallback: (event, response) {
                      setState(() {
                        if (response?.spot != null && event is! FlTapUpEvent && event is! FlPanEndEvent) {
                          touchedBarIndex = response!.spot!.touchedBarGroupIndex;
                        } else {
                          touchedBarIndex = -1;
                        }
                      });
                    },
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          final int intVal = val.toInt();
                          if (selectedFilter == 'Today') {
                            if (intVal % 4 == 0) {
                              return Text('${intVal}h', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)));
                            }
                          } else if (selectedFilter == 'This Week') {
                            const days = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];
                            if (intVal >= 1 && intVal <= 7) {
                              return Text(days[intVal - 1], style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)));
                            }
                          } else {
                            if (intVal % 5 == 0 || intVal == 1) {
                              return Text('$intVal', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)));
                            }
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRatioCard() {
    final double cashPct = totalSales > 0 ? (cashAmount / totalSales) * 100 : 0.0;
    final double upiPct = totalSales > 0 ? (upiAmount / totalSales) * 100 : 0.0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('भुगतान विभाजन (Cash vs UPI)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Icon(Icons.pie_chart_outline, color: Colors.blueAccent, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  height: 110,
                  width: 110,
                  child: totalSales == 0
                      ? const Center(child: Text('डेटा नहीं', style: TextStyle(color: Colors.grey, fontSize: 11)))
                      : PieChart(
                          PieChartData(
                            centerSpaceRadius: 28,
                            sectionsSpace: 3,
                            sections: [
                              PieChartSectionData(
                                value: cashAmount,
                                color: const Color(0xFF10B981),
                                radius: 24,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: upiAmount,
                                color: const Color(0xFF0284C7),
                                radius: 24,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _buildPaymentLegendRow('नकद (Cash)', '₹${cashAmount.toStringAsFixed(0)}', '${cashPct.toStringAsFixed(1)}%', const Color(0xFF10B981)),
                      const SizedBox(height: 10),
                      _buildPaymentLegendRow('ऑनलाइन (UPI)', '₹${upiAmount.toStringAsFixed(0)}', '${upiPct.toStringAsFixed(1)}%', const Color(0xFF0284C7)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentLegendRow(String title, String amt, String pct, Color dotColor) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
        Text(amt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(width: 6),
        Text('($pct)', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
      ],
    );
  }

  Widget _buildOrderModeCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ऑर्डर प्रकार (Dine-In vs Takeaway)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 14),
            _buildOrderModeRow(Icons.table_restaurant_outlined, 'डाइन-इन टेबल', '$tableOrders ऑर्डर्स', '₹${tableAmount.toStringAsFixed(0)}', const Color(0xFF2563EB)),
            const Divider(height: 18),
            _buildOrderModeRow(Icons.takeout_dining_outlined, 'पार्सल / टेकअवे', '$pickupOrders ऑर्डर्स', '₹${pickupAmount.toStringAsFixed(0)}', const Color(0xFFEA580C)),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderModeRow(IconData icon, String title, String count, String total, Color iconColor) {
    return Row(
      children: [
        CircleAvatar(radius: 16, backgroundColor: iconColor.withOpacity(0.1), child: Icon(icon, size: 18, color: iconColor)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
              Text(count, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
        Text(total, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
      ],
    );
  }
}

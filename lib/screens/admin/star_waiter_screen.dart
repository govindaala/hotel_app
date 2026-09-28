// lib/screens/admin/star_waiter_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WaiterPerformanceModel {
  final String waiterId;
  String waiterName;
  double totalSales;
  int tablesServed;
  double get aov => tablesServed > 0 ? (totalSales / tablesServed) : 0.0;
  double get commission => totalSales * 0.01; // 1% डिफ़ॉल्ट इंसेंटिव

  WaiterPerformanceModel({
    required this.waiterId,
    required this.waiterName,
    this.totalSales = 0.0,
    this.tablesServed = 0,
  });
}

class StarWaiterScreen extends StatefulWidget {
  final String storeCode;

  const StarWaiterScreen({Key? key, required this.storeCode}) : super(key: key);

  @override
  State<StarWaiterScreen> createState() => _StarWaiterScreenState();
}

class _StarWaiterScreenState extends State<StarWaiterScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _selectedFilter = 'THIS_MONTH'; // 'TODAY', 'THIS_MONTH'
  List<WaiterPerformanceModel> _leaderboard = [];

  @override
  void initState() {
    super.initState();
    _fetchWaiterAnalytics();
  }

  Future<void> _fetchWaiterAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      DateTime startDate;

      if (_selectedFilter == 'TODAY') {
        startDate = DateTime(now.year, now.month, now.day);
      } else {
        startDate = DateTime(now.year, now.month, 1);
      }

      // 1. स्टाफ टेबल से वेटर्स के असली नाम फेच करना
      final staffRes = await _supabase
          .from('hotel_staff')
          .select('staff_id, name')
          .eq('store_code', widget.storeCode);

      final Map<String, String> staffNames = {};
      for (var s in (staffRes as List)) {
        staffNames[s['staff_id'].toString()] = s['name']?.toString() ?? s['staff_id'].toString();
      }

      // 2. इनवॉइस टेबल से वेटर-वाइज सेल्स डेटा फेच करना
      final invoicesRes = await _supabase
          .from('invoices')
          .select('waiter_id, final_amount')
          .eq('store_code', widget.storeCode)
          .gte('created_at', startDate.toIso8601String());

      final Map<String, WaiterPerformanceModel> agg = {};

      for (var row in (invoicesRes as List)) {
        final wId = row['waiter_id']?.toString() ?? 'SELF_COUNTER';
        final amt = (row['final_amount'] as num?)?.toDouble() ?? 0.0;

        if (!agg.containsKey(wId)) {
          agg[wId] = WaiterPerformanceModel(
            waiterId: wId,
            waiterName: staffNames[wId] ?? (wId == 'SELF_COUNTER' ? 'काउंटर डायरेक्ट' : 'वेटर $wId'),
          );
        }

        agg[wId]!.totalSales += amt;
        agg[wId]!.tablesServed += 1;
      }

      // यदि इनवॉइस अभी नया है तो KOTs से भी बैकअप डेटा मिलाना
      if (agg.isEmpty) {
        final kotsRes = await _supabase
            .from('hotel_kots')
            .select('waiter_id, total_amount')
            .eq('store_code', widget.storeCode)
            .gte('created_at', startDate.toIso8601String());

        for (var row in (kotsRes as List)) {
          final wId = row['waiter_id']?.toString() ?? 'WAITER_1';
          final amt = (row['total_amount'] as num?)?.toDouble() ?? 0.0;

          if (!agg.containsKey(wId)) {
            agg[wId] = WaiterPerformanceModel(
              waiterId: wId,
              waiterName: staffNames[wId] ?? 'वेटर $wId',
            );
          }
          agg[wId]!.totalSales += amt;
          agg[wId]!.tablesServed += 1;
        }
      }

      final list = agg.values.toList();
      // सेल्स के आधार पर रैंकिंग (घटते क्रम में)
      list.sort((a, b) => b.totalSales.compareTo(a.totalSales));

      setState(() {
        _leaderboard = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('🏆 स्टार वेटर लीडरबोर्ड', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchWaiterAnalytics,
          ),
        ],
      ),
      body: Column(
        children: [
          // फ़िल्टर टैब्स (आज vs इस महीने)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                _buildFilterChip('इस माह की रैंकिंग', 'THIS_MONTH'),
                const SizedBox(width: 10),
                _buildFilterChip('आज का प्रदर्शन', 'TODAY'),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                : _leaderboard.isEmpty
                    ? const Center(
                        child: Text(
                          'इस अवधि में कोई वेटर ऑर्डर दर्ज नहीं है।',
                          style: TextStyle(color: Colors.white70, fontSize: 15),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchWaiterAnalytics,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            // टॉप 3 पोडियम कार्ड (शीर्ष वेटर हाइलाइट)
                            if (_leaderboard.isNotEmpty) _buildTopThreePodium(),
                            const SizedBox(height: 20),

                            const Text(
                              'समस्त वेटर प्रदर्शन व इंसेंटिव (1% कमीशन)',
                              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 10),

                            // पूर्ण सूची
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _leaderboard.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, idx) {
                                final w = _leaderboard[idx];
                                return _buildWaiterCard(w, idx + 1);
                              },
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () {
        if (_selectedFilter != value) {
          setState(() => _selectedFilter = value);
          _fetchWaiterAnalytics();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildTopThreePodium() {
    final top1 = _leaderboard.isNotEmpty ? _leaderboard[0] : null;
    final top2 = _leaderboard.length > 1 ? _leaderboard[1] : null;
    final top3 = _leaderboard.length > 2 ? _leaderboard[2] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (top2 != null) _buildPodiumColumn(top2, '🥈 2nd', Colors.grey[300]!, 100),
          if (top1 != null) _buildPodiumColumn(top1, '👑 1st (Star)', Colors.amber, 130),
          if (top3 != null) _buildPodiumColumn(top3, '🥉 3rd', Colors.brown[300]!, 85),
        ],
      ),
    );
  }

  Widget _buildPodiumColumn(WaiterPerformanceModel w, String title, Color color, double height) {
    return Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withOpacity(0.2),
          child: Text(w.waiterName[0], style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const SizedBox(height: 6),
        Text(
          w.waiterName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '₹${w.totalSales.toStringAsFixed(0)}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        Container(
          width: 75,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildWaiterCard(WaiterPerformanceModel w, int rank) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: rank <= 3 ? Colors.amber.withOpacity(0.2) : Colors.white12,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank <= 3 ? Colors.amber : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.waiterName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'टेबल्स: ${w.tablesServed}  •  औसत बिल (AOV): ₹${w.aov.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${w.totalSales.toStringAsFixed(0)}',
                style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 2),
              Text(
                'इंसेंटिव: +₹${w.commission.toStringAsFixed(0)}',
                style: const TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

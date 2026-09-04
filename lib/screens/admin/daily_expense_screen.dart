import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DailyExpenseScreen extends StatefulWidget {
  final String restaurantId;
  const DailyExpenseScreen({super.key, required this.restaurantId});

  @override
  State<DailyExpenseScreen> createState() => _DailyExpenseScreenState();
}

class _DailyExpenseScreenState extends State<DailyExpenseScreen> {
  final supabase = Supabase.instance.client;
  String _selectedFilter = 'आज';
  DateTimeRange? _customDateRange;
  bool _isLoading = false;
  List<Map<String, dynamic>> _records = [];

  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type = 'EXPENSE'; // EXPENSE या CASH_IN

  @override
  void initState() {
    super.initState();
    _fetchRecords();
  }

  DateTime get _now => DateTime.now();

  DateTimeRange _calculateRange() {
    if (_selectedFilter == 'कस्टम' && _customDateRange != null) {
      return _customDateRange!;
    }
    final today = DateTime(_now.year, _now.month, _now.day);
    if (_selectedFilter == 'साप्ताहिक') {
      return DateTimeRange(
        start: today.subtract(Duration(days: _now.weekday - 1)),
        end: today.add(const Duration(days: 1)),
      );
    } else if (_selectedFilter == 'मासिक') {
      return DateTimeRange(
        start: DateTime(_now.year, _now.month, 1),
        end: today.add(const Duration(days: 1)),
      );
    } else if (_selectedFilter == 'वार्षिक') {
      return DateTimeRange(
        start: DateTime(_now.year, 1, 1),
        end: today.add(const Duration(days: 1)),
      );
    }
    // आज
    return DateTimeRange(
      start: today,
      end: today.add(const Duration(days: 1)),
    );
  }

  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    try {
      final range = _calculateRange();
      final res = await supabase
          .from('daily_expenses')
          .select()
          .eq('restaurant_id', widget.restaurantId)
          .gte('created_at', range.start.toIso8601String())
          .lt('created_at', range.end.toIso8601String())
          .order('created_at', ascending: false);

      setState(() {
        _records = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('डेटा लोड नहीं हुआ: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addRecord() async {
    final title = _titleCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (title.isEmpty || amount <= 0) return;

    try {
      await supabase.from('daily_expenses').insert({
        'restaurant_id': widget.restaurantId,
        'title': title,
        'amount': amount,
        'type': _type,
        'created_at': DateTime.now().toIso8601String(),
      });
      _titleCtrl.clear();
      _amountCtrl.clear();
      Navigator.pop(context);
      _fetchRecords();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('सेव नहीं हुआ: $e')),
      );
    }
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('गल्ले का नया लेन-देन', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('खर्च (Out)'),
                      selected: _type == 'EXPENSE',
                      selectedColor: Colors.redAccent,
                      onSelected: (val) => setDlgState(() => _type = 'EXPENSE'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('जमा (In)'),
                      selected: _type == 'CASH_IN',
                      selectedColor: Colors.green,
                      onSelected: (val) => setDlgState(() => _type = 'CASH_IN'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'विवरण (जैसे: दूध, सब्ज़ी, अतिरिक्त गल्ला)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'रकम (₹)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('रद्द'),
            ),
            ElevatedButton(
              onPressed: _addRecord,
              child: const Text('सेव करें'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double totalIn = 0;
    double totalOut = 0;
    for (var r in _records) {
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      if (r['type'] == 'CASH_IN') {
        totalIn += amt;
      } else {
        totalOut += amt;
      }
    }
    final netCash = totalIn - totalOut;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('गल्ले का विस्तृत हिसाब'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          IconButton(
            onPressed: _fetchRecords,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: Colors.amber[700],
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text(
          'नया खर्च/जमा',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: ['आज', 'साप्ताहिक', 'मासिक', 'वार्षिक', 'कस्टम'].map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    selectedColor: Colors.amber[700],
                    labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                    backgroundColor: const Color(0xFF1E293B),
                    onSelected: (val) async {
                      if (filter == 'कस्टम') {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2023),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          _customDateRange = picked;
                          _selectedFilter = 'कस्टम';
                          _fetchRecords();
                        }
                      } else {
                        setState(() => _selectedFilter = filter);
                        _fetchRecords();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildSummaryBox('जमा (+)', '₹$totalIn', Colors.green),
                const SizedBox(width: 8),
                _buildSummaryBox('खर्च (-)', '₹$totalOut', Colors.redAccent),
                const SizedBox(width: 8),
                _buildSummaryBox('बचत', '₹$netCash', Colors.amber),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const Center(
                        child: Text(
                          'इस अवधि में कोई रिकॉर्ड नहीं मिला',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _records.length,
                        itemBuilder: (ctx, i) {
                          final r = _records[i];
                          final isIncome = r['type'] == 'CASH_IN';
                          final date = DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now();
                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: Icon(
                                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isIncome ? Colors.green : Colors.redAccent,
                              ),
                              title: Text(
                                r['title'] ?? '',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                DateFormat('dd MMM yyyy, hh:mm a').format(date),
                                style: const TextStyle(color: Colors.white54),
                              ),
                              trailing: Text(
                                '${isIncome ? "+" : "-"}₹${r['amount']}',
                                style: TextStyle(
                                  color: isIncome ? Colors.green : Colors.redAccent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
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

  Widget _buildSummaryBox(String title, String val, MaterialColor color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                val,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

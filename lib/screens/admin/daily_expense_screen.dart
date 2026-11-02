import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DailyExpenseScreen extends StatefulWidget {
  final String restaurantId;
  final double totalCashSalesToday;
  final List<dynamic> initialExpenses;
  final Function(dynamic)? onAddExpense;

  const DailyExpenseScreen({
    super.key,
    required this.restaurantId,
    this.totalCashSalesToday = 0.0,
    this.initialExpenses = const [],
    this.onAddExpense,
  });

  @override
  State<DailyExpenseScreen> createState() => _DailyExpenseScreenState();
}

class _DailyExpenseScreenState extends State<DailyExpenseScreen> {
  final supabase = Supabase.instance.client;

  String _selectedFilter = 'आज';
  DateTimeRange? _customDateRange;
  bool _isLoading = false;
  List<Map<String, dynamic>> _records = [];

  // ओपनिंग गल्ला व क्लोजिंग मिलान
  double _openingCash = 0.0;
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _type = 'EXPENSE'; // EXPENSE या CASH_IN
  String _selectedCategory = 'राशन/सब्जी';

  final List<String> _expenseCategories = [
    'राशन/सब्जी',
    'दूध/डेयरी',
    'गैस सिलिंडर',
    'स्टाफ एडवांस/वेतन',
    'दुकान मरम्मत',
    'मालिक निकासी (Self)',
    'अन्य'
  ];

  @override
  void initState() {
    super.initState();
    _loadOpeningCash();
    _fetchRecords();
  }

  DateTime get _now => DateTime.now();

  String get _todayKey =>
      'opening_cash_${widget.restaurantId}_${_now.year}_${_now.month}_${_now.day}';

  Future<void> _loadOpeningCash() async {
    final prefs = await SharedPreferences.getInstance();
    var openingCash = prefs.getDouble(_todayKey) ?? 0.0;
    final dayStart = DateTime(_now.year, _now.month, _now.day);
    final nextDay = dayStart.add(const Duration(days: 1));

    try {
      final rows = await supabase
          .from('daily_expenses')
          .select('amount')
          .eq('restaurant_id', widget.restaurantId)
          .eq('type', 'OPENING_CASH')
          .gte('created_at', dayStart.toIso8601String())
          .lt('created_at', nextDay.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        openingCash = (rows.first['amount'] as num?)?.toDouble() ?? openingCash;
        await prefs.setDouble(_todayKey, openingCash);
      }
    } catch (_) {}

    if (mounted) setState(() => _openingCash = openingCash);
  }

  Future<void> _saveOpeningCash(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_todayKey, amount);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final nextDay = dayStart.add(const Duration(days: 1));

    try {
      final existing = await supabase
          .from('daily_expenses')
          .select('id')
          .eq('restaurant_id', widget.restaurantId)
          .eq('type', 'OPENING_CASH')
          .gte('created_at', dayStart.toIso8601String())
          .lt('created_at', nextDay.toIso8601String())
          .order('created_at', ascending: false)
          .limit(1);

      if (existing.isNotEmpty) {
        await supabase.from('daily_expenses').update({
          'title': 'दिन की शुरुआती रोकड़',
          'amount': amount,
          'created_at': now.toIso8601String(),
        }).eq('id', existing.first['id']);
      } else {
        await supabase.from('daily_expenses').insert({
          'restaurant_id': widget.restaurantId,
          'store_code': widget.restaurantId,
          'title': 'दिन की शुरुआती रोकड़',
          'amount': amount,
          'type': 'OPENING_CASH',
          'created_at': now.toIso8601String(),
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ओपनिंग गल्ला डिवाइस पर सेव हुआ, क्लाउड सिंक नहीं हुआ: $error')),
        );
      }
    }

    if (mounted) {
      setState(() => _openingCash = amount);
      await _fetchRecords();
    }
  }

  Future<void> _saveClosingAudit({
    required double expectedCash,
    required double actualCash,
  }) async {
    final difference = actualCash - expectedCash;
    await supabase.from('daily_expenses').insert({
      'restaurant_id': widget.restaurantId,
      'store_code': widget.restaurantId,
      'title': 'क्लोजिंग ऑडिट | सिस्टम ₹${expectedCash.toStringAsFixed(2)} | वास्तविक ₹${actualCash.toStringAsFixed(2)} | अंतर ₹${difference.toStringAsFixed(2)}',
      'amount': actualCash,
      'type': 'CASH_CLOSING',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _fetchRecords();
  }

  DateTimeRange _calculateRange() {
    if (_selectedFilter == 'कस्टम' && _customDateRange != null) {
      final selected = _customDateRange!;
      final endExclusive = DateTime(
        selected.end.year,
        selected.end.month,
        selected.end.day,
      ).add(const Duration(days: 1));
      return DateTimeRange(start: selected.start, end: endExclusive);
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

      if (mounted) {
        setState(() {
          _records = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('डेटा लोड नहीं हुआ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addRecord() async {
    final titleText = _titleCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (titleText.isEmpty || amount <= 0) return;

    final String finalTitle = _type == 'EXPENSE'
        ? '[$_selectedCategory] $titleText'
        : titleText;

    try {
      await supabase.from('daily_expenses').insert({
        'restaurant_id': widget.restaurantId,
        'title': finalTitle,
        'amount': amount,
        'type': _type,
        'created_at': DateTime.now().toIso8601String(),
      });

      _titleCtrl.clear();
      _amountCtrl.clear();
      if (mounted) Navigator.pop(context);
      _fetchRecords();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('सेव नहीं हुआ: $e')),
        );
      }
    }
  }

  // 1. सुबह का ओपनिंग कैश सेट करने का डायलॉग
  void _showOpeningCashDialog() {
    final ctrl = TextEditingController(
      text: _openingCash > 0 ? _openingCash.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('शुरुआती गल्ला (Opening Float)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'सुबह काउंटर खोलते समय गल्ले में चेंज / रोकड़ कितनी रखी गई थी?',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'ओपनिंग कैश (₹)',
                hintText: 'उदा. 1500',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () {
              final val = double.tryParse(ctrl.text.trim()) ?? 0.0;
              _saveOpeningCash(val);
              Navigator.pop(ctx);
            },
            child: const Text('सेट करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 2. रात का गल्ला मिलान व क्लोजिंग ऑडिट (Shift Closing)
  void _showClosingAuditDialog(double expectedCash) {
    final actualCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) {
          final double actualCash = double.tryParse(actualCtrl.text.trim()) ?? 0.0;
          final double diff = actualCash - expectedCash;
          final bool hasEntered = actualCtrl.text.trim().isNotEmpty;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock_clock_outlined, color: Colors.teal),
                SizedBox(width: 8),
                Text('गल्ला मिलान व क्लोजिंग', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('सिस्टम अनुसार रोकड़:', style: TextStyle(fontSize: 13)),
                            Text('₹${expectedCash.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: actualCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setDState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'वास्तविक गल्ला गिनकर लिखें (₹)',
                      hintText: 'उदा. 4500',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calculate_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasEntered)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: diff == 0
                            ? Colors.green.shade50
                            : (diff < 0 ? Colors.red.shade50 : Colors.amber.shade50),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: diff == 0
                              ? Colors.green
                              : (diff < 0 ? Colors.red : Colors.orange),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            diff == 0
                                ? '✅ गल्ला शत-प्रतिशत सही मिला!'
                                : (diff < 0
                                    ? '⚠️ गल्ले में ₹${diff.abs().toStringAsFixed(0)} की कमी (Shortage) है!'
                                    : 'ℹ️ गल्ले में ₹${diff.toStringAsFixed(0)} अधिक (Surplus) हैं!'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: diff == 0
                                  ? Colors.green.shade800
                                  : (diff < 0 ? Colors.red.shade800 : Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('बंद करें')),
              ElevatedButton(
                onPressed: hasEntered
                    ? () async {
                        try {
                          await _saveClosingAudit(
                            expectedCash: expectedCash,
                            actualCash: actualCash,
                          );
                          if (mounted) Navigator.pop(ctx);
                        } catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('क्लोजिंग ऑडिट सेव नहीं हुआ: $error')),
                            );
                          }
                        }
                      }
                    : null,
                child: const Text('क्लोजिंग सेव करें'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 3. नया खर्च या जमा जोड़ने का डायलॉग
  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('गल्ले का नया लेन-देन', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('खर्च (Out)'),
                        selected: _type == 'EXPENSE',
                        selectedColor: Colors.red.shade100,
                        onSelected: (val) => setDlgState(() => _type = 'EXPENSE'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('जमा (In)'),
                        selected: _type == 'CASH_IN',
                        selectedColor: Colors.green.shade100,
                        onSelected: (val) => setDlgState(() => _type = 'CASH_IN'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_type == 'EXPENSE') ...[
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'खर्च की श्रेणी',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _expenseCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setDlgState(() => _selectedCategory = v!),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: _type == 'EXPENSE' ? 'विवरण (जैसे 5kg आलू, अमूल दूध)' : 'विवरण (जैसे अतिरिक्त रोकड़ जमा)',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'रकम (₹)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: _addRecord,
              child: const Text('सेव करें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double cashIn = 0;
    double bankIn = 0;
    double cashOut = 0;
    double bankOut = 0;
    double partnerOut = 0;
    double creditOut = 0;

    for (final record in _records) {
      final amount = (record['amount'] as num?)?.toDouble() ?? 0.0;
      final type = (record['type'] ?? '').toString().toUpperCase();
      final title = (record['title'] ?? '').toString();

      if (type == 'CASH_IN') {
        if (title.contains('(UPI)') || title.contains('बैंक')) {
          bankIn += amount;
        } else {
          cashIn += amount;
        }
      } else if (type == 'EXPENSE_UPI' || type == 'BANK_OUT' || type == 'VENDOR_PAYMENT_UPI') {
        bankOut += amount;
      } else if (type == 'EXPENSE_PARTNER') {
        partnerOut += amount;
      } else if (type == 'EXPENSE_CREDIT') {
        creditOut += amount;
      } else if (type == 'EXPENSE' || type == 'EXPENSE_CASH' || type == 'CASH_OUT' || type == 'VENDOR_PAYMENT_CASH') {
        cashOut += amount;
      }
    }

    final double expectedDrawerCash = _openingCash + cashIn - cashOut;
    final double expectedBankBalance = bankIn - bankOut;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('गल्ला व रोकड़ हिसाब', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'ओपनिंग गल्ला सेट करें',
            onPressed: _showOpeningCashDialog,
            icon: const Icon(Icons.wb_sunny_outlined, color: Colors.orange),
          ),
          IconButton(
            tooltip: 'गल्ला क्लोजिंग ऑडिट',
            onPressed: () {
              if (_selectedFilter != 'आज') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('क्लोजिंग ऑडिट केवल आज के रिकॉर्ड पर किया जा सकता है।')),
                );
                return;
              }
              _showClosingAuditDialog(expectedDrawerCash);
            },
            icon: const Icon(Icons.verified_outlined, color: Colors.teal),
          ),
          IconButton(
            tooltip: 'रीफ़्रेश',
            onPressed: _fetchRecords,
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: const Color(0xFF0F172A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('नया खर्च / जमा', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // फ़िल्टर चिप्स
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
                    selectedColor: const Color(0xFF0F172A),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    onSelected: (val) async {
                      if (filter == 'कस्टम') {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2024),
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

          // समरी कार्ड्स
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildSummaryBox('शुरुआती गल्ला', '₹${_openingCash.toStringAsFixed(0)}', Colors.orange, Icons.wb_sunny_outlined),
                    const SizedBox(width: 8),
                    _buildSummaryBox('कैश जमा (+)', '₹${cashIn.toStringAsFixed(0)}', Colors.green, Icons.arrow_downward),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSummaryBox('कैश खर्च (-)', '₹${cashOut.toStringAsFixed(0)}', Colors.redAccent, Icons.arrow_upward),
                    const SizedBox(width: 8),
                    _buildSummaryBox('हाथ में गल्ला रोकड़', '₹${expectedDrawerCash.toStringAsFixed(0)}', const Color(0xFF0F172A), Icons.account_balance_wallet),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSummaryBox('UPI जमा', '₹${bankIn.toStringAsFixed(0)}', Colors.blue, Icons.account_balance),
                    const SizedBox(width: 8),
                    _buildSummaryBox('UPI खर्च', '₹${bankOut.toStringAsFixed(0)}', Colors.deepOrange, Icons.account_balance_wallet),
                    const SizedBox(width: 8),
                    _buildSummaryBox('UPI शुद्ध', '₹${expectedBankBalance.toStringAsFixed(0)}', const Color(0xFF0F172A), Icons.savings),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSummaryBox('पार्टनर खर्च', '₹${partnerOut.toStringAsFixed(0)}', Colors.deepPurple, Icons.person),
                    const SizedBox(width: 8),
                    _buildSummaryBox('उधारी खरीद', '₹${creditOut.toStringAsFixed(0)}', Colors.brown, Icons.receipt_long),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),
          const Divider(height: 1),

          // लेन-देन सूची
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? const Center(
                        child: Text('इस अवधि में कोई रिकॉर्ड दर्ज नहीं मिला', style: TextStyle(color: Colors.black45)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _records.length,
                        itemBuilder: (ctx, i) {
                          final r = _records[i];
                          final recordType = (r['type'] ?? '').toString().toUpperCase();
                          final isIncome = recordType == 'CASH_IN';
                          final isAudit = recordType == 'OPENING_CASH' || recordType == 'CASH_CLOSING';
                          final date = DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now();

                          return Card(
                            color: Colors.white,
                            elevation: 0,
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isAudit ? const Color(0xFFEFF6FF) : (isIncome ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2)),
                                child: Icon(
                                  isAudit ? Icons.verified_outlined : (isIncome ? Icons.arrow_downward : Icons.arrow_upward),
                                  color: isAudit ? Colors.blueGrey : (isIncome ? const Color(0xFF059669) : Colors.redAccent),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                r['title'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                              ),
                              subtitle: Text(
                                DateFormat('dd MMM yyyy, hh:mm a').format(date),
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                              ),
                              trailing: Text(
                                '${isAudit ? "" : (isIncome ? "+" : "-")}₹${r['amount']}',
                                style: TextStyle(
                                  color: isAudit ? Colors.blueGrey : (isIncome ? const Color(0xFF059669) : Colors.redAccent),
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

  Widget _buildSummaryBox(String title, String val, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
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
          ],
        ),
      ),
    );
  }
}

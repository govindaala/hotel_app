import 'package:flutter/material.dart';
import '../../models/expense_model.dart';

class DailyExpenseScreen extends StatefulWidget {
  final String restaurantId;
  final double totalCashSalesToday; // आज की कुल नकद बिक्री
  final List<ExpenseModel> initialExpenses;
  final Function(ExpenseModel newExpense) onAddExpense;

  const DailyExpenseScreen({
    super.key,
    required this.restaurantId,
    required this.totalCashSalesToday,
    required this.initialExpenses,
    required this.onAddExpense,
  });

  @override
  State<DailyExpenseScreen> createState() => _DailyExpenseScreenState();
}

class _DailyExpenseScreenState extends State<DailyExpenseScreen> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _selectedMode = 'CASH';

  late List<ExpenseModel> _expenses;

  @override
  void initState() {
    super.initState();
    _expenses = List.from(widget.initialExpenses);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  double get _totalCashExpense {
    return _expenses
        .where((e) => e.paymentMode == 'CASH')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  double get _netCashInHand {
    return widget.totalCashSalesToday - _totalCashExpense;
  }

  void _showAddExpenseDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('नया खर्च दर्ज करें'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'खर्च का विवरण (जैसे: सब्जी, दूध, गैस)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'रकम (₹)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('भुगतान मोड: '),
                  ChoiceChip(
                    label: const Text('गल्ला (CASH)'),
                    selected: _selectedMode == 'CASH',
                    onSelected: (val) => setDialogState(() => _selectedMode = 'CASH'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('ऑनलाइन (UPI)'),
                    selected: _selectedMode == 'UPI',
                    onSelected: (val) => setDialogState(() => _selectedMode = 'UPI'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('रद्द करें'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () {
                final name = _nameCtrl.text.trim();
                final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
                if (name.isNotEmpty && amount > 0) {
                  final expense = ExpenseModel(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    restaurantId: widget.restaurantId,
                    expenseName: name,
                    amount: amount,
                    paymentMode: _selectedMode,
                    createdAt: DateTime.now(),
                  );
                  widget.onAddExpense(expense);
                  setState(() {
                    _expenses.insert(0, expense);
                  });
                  _nameCtrl.clear();
                  _amountCtrl.clear();
                  Navigator.pop(ctx);
                }
              },
              child: const Text('जोड़ें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('दैनिक खर्च व गल्ला हिसाब'),
        backgroundColor: Colors.deepOrange,
      ),
      body: Column(
        children: [
          // 1. गल्ला समरी कार्ड
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.deepOrange.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('आज की कुल नकद बिक्री:'),
                    Text('₹ ${widget.totalCashSalesToday.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('गल्ले से नकद खर्च:'),
                    Text('- ₹ ${_totalCashExpense.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('शाम को गल्ले में शेष नकद (Net Cash):',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('₹ ${_netCashInHand.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  ],
                ),
              ],
            ),
          ),

          // 2. खर्चों की लिस्ट
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('आज के खर्चे (Petty Cash):',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _showAddExpenseDialog,
                  icon: const Icon(Icons.add_circle, color: Colors.deepOrange),
                  label: const Text('नया खर्च'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _expenses.isEmpty
                ? const Center(child: Text('आज कोई खर्च दर्ज नहीं किया गया।'))
                : ListView.separated(
                    itemCount: _expenses.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _expenses[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.paymentMode == 'CASH'
                              ? Colors.amber.shade100
                              : Colors.blue.shade100,
                          child: Icon(
                            item.paymentMode == 'CASH'
                                ? Icons.payments_outlined
                                : Icons.qr_code,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                        title: Text(item.expenseName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            'मोड: ${item.paymentMode} • ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        trailing: Text('₹ ${item.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

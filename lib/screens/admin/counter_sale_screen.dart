import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CounterSaleScreen extends StatefulWidget {
  final String storeCode;
  final int tableCount; // होटल की असली टेबल संख्या

  const CounterSaleScreen({
    Key? key,
    required this.storeCode,
    this.tableCount = 10, // डिफ़ॉल्ट 10 टेबल
  }) : super(key: key);

  @override
  State<CounterSaleScreen> createState() => _CounterSaleScreenState();
}

class _CounterSaleScreenState extends State<CounterSaleScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String? fetchErrorMessage;

  Map<String, List<Map<String, dynamic>>> inventoryGroups = {};
  String? selectedCategory;
  final Map<String, Map<String, dynamic>> cart = {};

  String selectedTable = 'काउंटर सेल (डायरेक्ट)';
  late List<String> availableTables;

  @override
  void initState() {
    super.initState();
    // होटल की असली टेबल संख्या के अनुसार डायनामिक लिस्ट बनाना
    availableTables = [
      'काउंटर सेल (डायरेक्ट)',
      ...List.generate(widget.tableCount, (index) => 'T-${index + 1}'),
    ];
    _loadHybridInventory();
  }

  Future<void> _loadHybridInventory() async {
    setState(() {
      isLoading = true;
      fetchErrorMessage = null;
    });

    try {
      // 1. ग्लोबल कॉमन प्रोडक्ट्स फेच करना (जहाँ restaurant_id null है)
      final List<dynamic> globalData = await supabase
          .from('counter_inventory')
          .select('*')
          .filter('restaurant_id', 'is', null);

      // 2. इस होटल के अपने प्रोडक्ट्स फेच करना
      final List<dynamic> localData = await supabase
          .from('counter_inventory')
          .select('*')
          .eq('restaurant_id', widget.storeCode);

      final Map<String, Map<String, dynamic>> mergedMap = {};

      // पहले ग्लोबल डालें
      for (var row in globalData) {
        final key = '${row['item_name']}_${row['variant_label']}';
        mergedMap[key] = Map<String, dynamic>.from(row);
      }

      // लोकल से ओवरराइड करें
      for (var row in localData) {
        final key = '${row['item_name']}_${row['variant_label']}';
        mergedMap[key] = Map<String, dynamic>.from(row);
      }

      // कैटेगरी अनुसार ग्रुपिंग
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var item in mergedMap.values) {
        final cat = item['item_name'].toString();
        grouped.putIfAbsent(cat, () => []).add(item);
      }

      setState(() {
        inventoryGroups = grouped;
        if (grouped.isNotEmpty) {
          selectedCategory = grouped.keys.first;
        }
      });
    } catch (e) {
      setState(() => fetchErrorMessage = 'डेटा लोड एरर: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _addToCart(String name, String variant, double price) {
    final key = '$name ($variant)';
    setState(() {
      if (cart.containsKey(key)) {
        cart[key]!['qty'] = (cart[key]!['qty'] as int) + 1;
      } else {
        cart[key] = {'name': name, 'variant': variant, 'price': price, 'qty': 1};
      }
    });
  }

  void _removeFromCart(String key) {
    setState(() {
      if (cart.containsKey(key)) {
        if ((cart[key]!['qty'] as int) > 1) {
          cart[key]!['qty'] = (cart[key]!['qty'] as int) - 1;
        } else {
          cart.remove(key);
        }
      }
    });
  }

  double get grandTotal {
    double sum = 0.0;
    cart.forEach((_, item) => sum += (item['price'] as double) * (item['qty'] as int));
    return sum;
  }

  Future<void> _processCheckout(String mode) async {
    if (cart.isEmpty) return;

    final double total = grandTotal;
    final List<String> details = cart.values
        .map((v) => '${v['name']} (${v['variant']}) x${v['qty']}')
        .toList();

    try {
      if (selectedTable != 'काउंटर सेल (डायरेक्ट)') {
        await supabase.from('hotel_kots').insert({
          'restaurant_id': widget.storeCode,
          'table_name': selectedTable,
          'items': cart.values.map((v) => {
            'item_name': '${v['name']} (${v['variant']})',
            'qty': v['qty'],
            'price': v['price'],
            'total': v['price'] * v['qty'],
          }).toList(),
          'status': 'served',
          'created_at': DateTime.now().toIso8601String(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$selectedTable में जुड़ा: ₹$total'), backgroundColor: Colors.teal),
          );
        }
      } else {
        await supabase.from('daily_expenses').insert({
          'restaurant_id': widget.storeCode,
          'title': 'काउंटर सेल: ${details.join(", ")} ($mode)',
          'amount': total,
          'type': 'CASH_IN',
          'created_at': DateTime.now().toIso8601String(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('काउंटर बिक्री दर्ज: ₹$total ($mode)'), backgroundColor: Colors.green),
          );
        }
      }

      setState(() => cart.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('एरर: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openAddCustomVariantDialog() {
    final nameCtrl = TextEditingController(text: selectedCategory ?? '');
    final varCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('नया सामान / रेट जोड़ें', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'सामान (उदा. चिप्स, पानी)')),
            TextField(controller: varCtrl, decoration: const InputDecoration(labelText: 'रेंज / पैक (उदा. ₹15 वाला)')),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'कीमत (₹)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () async {
              final n = nameCtrl.text.trim();
              final v = varCtrl.text.trim();
              final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
              if (n.isNotEmpty && v.isNotEmpty && p > 0) {
                await supabase.from('counter_inventory').insert({
                  'restaurant_id': widget.storeCode,
                  'item_name': n,
                  'variant_label': v,
                  'price': p,
                });
                Navigator.pop(ctx);
                _loadHybridInventory();
              }
            },
            child: const Text('सुरक्षित करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTable = selectedTable != 'काउंटर सेल (डायरेक्ट)';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('⚡ काउंटर सेल व इन्वेंटरी', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0284C7)),
            tooltip: 'नया आइटम / रेट जोड़ें',
            onPressed: _openAddCustomVariantDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: _loadHybridInventory,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : fetchErrorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 10),
                        Text(fetchErrorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _loadHybridInventory, child: const Text('पुनः प्रयास करें')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: isTable ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                      child: Row(
                        children: [
                          Icon(Icons.table_restaurant, color: isTable ? const Color(0xFF2563EB) : const Color(0xFF64748B), size: 20),
                          const SizedBox(width: 8),
                          const Text('बिल किसमें जोड़ना है?:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const Spacer(),
                          DropdownButton<String>(
                            value: selectedTable,
                            underline: const SizedBox(),
                            style: TextStyle(fontWeight: FontWeight.bold, color: isTable ? const Color(0xFF2563EB) : const Color(0xFF0F172A), fontSize: 13),
                            items: availableTables.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => selectedTable = val);
                            },
                          ),
                        ],
                      ),
                    ),

                    if (inventoryGroups.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('कोई आइटम उपलब्ध नहीं\n(डेटाबेस में टेबल खाली है)', textAlign: TextAlign.center),
                        ),
                      )
                    else ...[
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        color: Colors.white,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: inventoryGroups.keys.map((name) {
                            final isSel = selectedCategory == name;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: isSel ? Colors.white : Colors.black87, fontSize: 12)),
                                selected: isSel,
                                selectedColor: const Color(0xFF0F172A),
                                backgroundColor: const Color(0xFFF1F5F9),
                                onSelected: (_) => setState(() => selectedCategory = name),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const Divider(height: 1),

                      Expanded(
                        child: selectedCategory == null || !inventoryGroups.containsKey(selectedCategory)
                            ? const SizedBox()
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 2.2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: inventoryGroups[selectedCategory]!.length,
                                itemBuilder: (ctx, i) {
                                  final v = inventoryGroups[selectedCategory]![i];
                                  final double price = ((v['price'] ?? 0) as num).toDouble();
                                  final String label = v['variant_label'] ?? '';

                                  return InkWell(
                                    onTap: () => _addToCart(selectedCategory!, label, price),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                                Text('₹$price', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 14)),
                                              ],
                                            ),
                                          ),
                                          const CircleAvatar(
                                            radius: 12,
                                            backgroundColor: Color(0xFFECFDF5),
                                            child: Icon(Icons.add, size: 16, color: Color(0xFF059669)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -3))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cart.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 110),
                              child: ListView(
                                shrinkWrap: true,
                                children: cart.entries.map((e) {
                                  final item = e.value;
                                  return Row(
                                    children: [
                                      Expanded(child: Text('${item['name']} - ${item['variant']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                                        onPressed: () => _removeFromCart(e.key),
                                      ),
                                      Text('${item['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 18),
                                        onPressed: () => _addToCart(item['name'], item['variant'], item['price']),
                                      ),
                                      SizedBox(
                                        width: 55,
                                        child: Text('₹${(item['price'] * item['qty']).toStringAsFixed(0)}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          const Divider(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(isTable ? '$selectedTable में जुड़ेगा:' : 'कुल राशि:', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              Text('₹${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (isTable)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.add_task, color: Colors.white),
                                label: Text('$selectedTable के बिल में जोड़ें', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                                onPressed: cart.isEmpty ? null : () => _processCheckout('TABLE'),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.money, color: Colors.white),
                                    label: const Text('नकद मिला', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    onPressed: cart.isEmpty ? null : () => _processCheckout('CASH'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.qr_code, color: Colors.white),
                                    label: const Text('UPI मिला', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    onPressed: cart.isEmpty ? null : () => _processCheckout('UPI'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

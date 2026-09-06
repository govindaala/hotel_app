import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class CounterSaleScreen extends StatefulWidget {
  final String storeCode;
  const CounterSaleScreen({Key? key, required this.storeCode}) : super(key: key);

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
  List<String> availableTables = ['काउंटर सेल (डायरेक्ट)'];

  @override
  void initState() {
    super.initState();
    _initScreenData();
  }

  Future<void> _initScreenData() async {
    setState(() {
      isLoading = true;
      fetchErrorMessage = null;
    });

    // 1. टेबल संख्या निकालना
    int count = 10;
    try {
      final hotelRes = await supabase
          .from('restaurant_profiles')
          .select('*')
          .eq('restaurant_id', widget.storeCode)
          .maybeSingle();

      if (hotelRes != null) {
        final val = hotelRes['total_tables'] ?? hotelRes['tables_count'] ?? hotelRes['table_count'];
        if (val != null) count = int.tryParse(val.toString()) ?? 10;
      }
    } catch (_) {
      count = 10;
    }

    setState(() {
      availableTables = [
        'काउंटर सेल (डायरेक्ट)',
        ...List.generate(count, (i) => 'T-${i + 1}'),
      ];
    });

    // 2. इन्वेंटरी लोड करना
    try {
      final List<dynamic> allRows = await supabase
          .from('counter_inventory')
          .select('*')
          .order('id', ascending: true);

      final Map<String, Map<String, dynamic>> mergedMap = {};

      for (var row in allRows) {
        if (row['restaurant_id'] == null) {
          final key = '${row['item_name']}_${row['variant_label']}';
          mergedMap[key] = Map<String, dynamic>.from(row);
        }
      }

      for (var row in allRows) {
        if (row['restaurant_id']?.toString() == widget.storeCode) {
          final key = '${row['item_name']}_${row['variant_label']}';
          mergedMap[key] = Map<String, dynamic>.from(row);
        }
      }

      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var item in mergedMap.values) {
        final cat = item['item_name'].toString();
        grouped.putIfAbsent(cat, () => []).add(item);
      }

      setState(() {
        inventoryGroups = grouped;
        if (grouped.isNotEmpty) {
          if (selectedCategory == null || !grouped.containsKey(selectedCategory)) {
            selectedCategory = grouped.keys.first;
          }
        } else {
          selectedCategory = null;
        }
      });
    } catch (e) {
      setState(() => fetchErrorMessage = 'डेटा लोड एरर: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  // स्टॉक 0 होने पर बिल में न जुड़ने का कड़ा नियम
  void _addToCart(dynamic id, String name, String variant, double price, int stock) {
    if (stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ यह सामान स्टॉक में नहीं है (Stock: 0)!'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final key = '$name ($variant)';
    final currentQty = cart[key]?['qty'] ?? 0;

    if (currentQty >= stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('माफ़ करें! सिर्फ $stock स्टॉक ही बचा है।'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      if (cart.containsKey(key)) {
        cart[key]!['qty'] = (cart[key]!['qty'] as int) + 1;
      } else {
        cart[key] = {'id': id, 'name': name, 'variant': variant, 'price': price, 'qty': 1, 'stock': stock};
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

  Future<void> _printReceipt(String mode, double total) async {
    try {
      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) return;

      String billText = """
       काउंटर बिक्री पर्ची       
================================
तारीख: ${DateTime.now().toString().substring(0, 16)}
मोड: $mode  | टेबल: $selectedTable
--------------------------------
सामान              मात्रा   रकम
--------------------------------
""";
      for (var item in cart.values) {
        String name = "${item['name']} ${item['variant']}";
        if (name.length > 16) name = name.substring(0, 16);
        billText += "${name.padRight(16)} ${item['qty'].toString().padRight(4)} ₹${(item['price'] * item['qty']).toInt()}\n";
      }

      billText += """
--------------------------------
कुल देय राशि:         ₹${total.toStringAsFixed(2)}
================================
        धन्यवाद! फिर पधारें        
\n\n\n
""";
      await PrintBluetoothThermal.writeBytes(billText.codeUnits);
    } catch (_) {}
  }

  Future<void> _processCheckout(String mode, {bool shouldPrint = false}) async {
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
      } else {
        await supabase.from('daily_expenses').insert({
          'restaurant_id': widget.storeCode,
          'title': 'काउंटर सेल: ${details.join(", ")} ($mode)',
          'amount': total,
          'type': 'CASH_IN',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // बिक्री होते ही स्टॉक कम करना
      for (var item in cart.values) {
        if (item['id'] != null) {
          final int remaining = ((item['stock'] ?? 0) as int) - (item['qty'] as int);
          await supabase.from('counter_inventory').update({
            'stock_qty': remaining < 0 ? 0 : remaining,
          }).eq('id', item['id']);
        }
      }

      if (shouldPrint) {
        await _printReceipt(mode, total);
      }

            if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('बिक्री दर्ज हुई: ₹$total ($mode)'), backgroundColor: Colors.green),
        );

        // अगर टेबल (T-2 आदि) में सामान जोड़ा है, तो स्क्रीन बंद कर सामान T-2 को सौंपें
        if (selectedTable != 'काउंटर सेल (डायरेक्ट)') {
          Navigator.pop(context, {
            'table': selectedTable,
            'items': cart.values.map((v) => {
              'name': '${v['name']} (${v['variant']})',
              'qty': v['qty'],
              'price': v['price'],
            }).toList(),
          });
          return;
        }
      }

      setState(() => cart.clear());
      _initScreenData();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('एरर: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // किसी भी प्रोडक्ट को डेटाबेस से डिलीट करना
  Future<void> _deleteProduct(dynamic id, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('सामान डिलीट करें?'),
        content: Text('क्या आप "$label" को इन्वेंटरी से पूरी तरह हटाना चाहते हैं?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('हाँ, डिलीट करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && id != null) {
      await supabase.from('counter_inventory').delete().eq('id', id);
      _initScreenData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$label" डिलीट हो गया!'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // किसी सामान का स्टॉक सीधे बदलना (+ जोड़ना या - घटाना)
  void _openStockAdjustDialog(Map<String, dynamic> item) {
    final stockCtrl = TextEditingController(text: '${item['stock_qty'] ?? 0}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('स्टॉक बदलें: ${item['item_name']} (${item['variant_label']})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('मौजूदा स्टॉक: ${item['stock_qty'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey)),
            const SizedBox(height: 12),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'नया सही स्टॉक सेट करें',
                hintText: 'उदा. 40 या 100',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () async {
              final int newQty = int.tryParse(stockCtrl.text.trim()) ?? 0;
              if (item['id'] != null) {
                await supabase.from('counter_inventory').update({
                  'stock_qty': newQty < 0 ? 0 : newQty,
                }).eq('id', item['id']);

                Navigator.pop(ctx);
                _initScreenData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('स्टॉक अपडेट होकर $newQty हो गया!'), backgroundColor: Colors.teal),
                );
              }
            },
            child: const Text('सुरक्षित करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // कार्ड पर लॉन्ग-प्रेस करने पर खुलने वाला मेनू
  void _showItemOptions(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note, color: Colors.blue),
              title: const Text('स्टॉक संख्या बदलें (+ जोड़ें / - घटाएँ)'),
              subtitle: Text('वर्तमान स्टॉक: ${item['stock_qty'] ?? 0}'),
              onTap: () {
                Navigator.pop(ctx);
                _openStockAdjustDialog(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('यह सामान/वेरिएंट डिलीट करें', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteProduct(item['id'], '${item['item_name']} - ${item['variant_label']}');
              },
            ),
          ],
        ),
      ),
    );
  }

  // नया सामान जोड़ना (+)
  void _openAddCustomVariantDialog() {
    final nameCtrl = TextEditingController(text: selectedCategory ?? '');
    final varCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '50');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('➕ नया सामान / रेट जोड़ें', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'सामान (उदा. चिप्स, पानी)')),
              TextField(controller: varCtrl, decoration: const InputDecoration(labelText: 'रेंज / पैक (उदा. ₹15 वाला)')),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'कीमत (₹)')),
              TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'शुरुआती स्टॉक संख्या')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
            onPressed: () async {
              final n = nameCtrl.text.trim();
              final v = varCtrl.text.trim();
              final p = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
              final s = int.tryParse(stockCtrl.text.trim()) ?? 0;

              if (n.isNotEmpty && v.isNotEmpty && p > 0) {
                await supabase.from('counter_inventory').insert({
                  'restaurant_id': widget.storeCode,
                  'item_name': n,
                  'variant_label': v,
                  'price': p,
                  'stock_qty': s < 0 ? 0 : s,
                });
                Navigator.pop(ctx);
                _initScreenData();
              }
            },
            child: const Text('सुरक्षित करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // क्विक स्टॉक डायलॉग (📦)
  void _openQuickStockDialog() {
    final List<Map<String, dynamic>> allItemsList = [];
    inventoryGroups.forEach((_, list) => allItemsList.addAll(list));

    if (allItemsList.isEmpty) return;

    Map<String, dynamic>? selectedItem = allItemsList.first;
    final qtyCtrl = TextEditingController();
    bool isAdding = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('📦 इन्वेंटरी स्टॉक समायोजन', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selectedItem,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'सामान चुनें'),
                  items: allItemsList.map((item) {
                    return DropdownMenuItem(
                      value: item,
                      child: Text('${item['item_name']} - ${item['variant_label']} (स्टॉक: ${item['stock_qty'] ?? 0})', style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (val) => setDState(() => selectedItem = val),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('+ जोड़ें (आया)'),
                      selected: isAdding,
                      selectedColor: Colors.green.shade100,
                      onSelected: (_) => setDState(() => isAdding = true),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('- घटाएँ (टूटा/हटा)'),
                      selected: !isAdding,
                      selectedColor: Colors.red.shade100,
                      onSelected: (_) => setDState(() => isAdding = false),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isAdding ? 'कितना स्टॉक आया?' : 'कितना स्टॉक कम करना है?',
                    hintText: 'उदा. 50',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                final int changeQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                if (selectedItem != null && changeQty > 0) {
                  final int currentStock = (selectedItem!['stock_qty'] ?? 0) as int;
                  final int newStock = isAdding ? (currentStock + changeQty) : (currentStock - changeQty);

                  await supabase.from('counter_inventory').update({
                    'stock_qty': newStock < 0 ? 0 : newStock,
                  }).eq('id', selectedItem!['id']);

                  Navigator.pop(ctx);
                  _initScreenData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('स्टॉक अपडेट होकर $newStock हो गया!'), backgroundColor: Colors.teal),
                  );
                }
              },
              child: const Text('अपडेट करें', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
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
            tooltip: 'नया सामान जोड़ें',
            onPressed: _openAddCustomVariantDialog,
          ),
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF059669)),
            tooltip: 'स्टॉक जोड़ें/घटाएँ',
            onPressed: _openQuickStockDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            tooltip: 'रीफ़्रेश',
            onPressed: _initScreenData,
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
                        ElevatedButton(onPressed: _initScreenData, child: const Text('पुनः प्रयास करें')),
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
                          child: Text('कोई आइटम उपलब्ध नहीं\n(ऊपर + दबाकर नया सामान जोड़ें)', textAlign: TextAlign.center),
                        ),
                      )
                    else ...[
                      Container(
                        height: 50,
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

                      // ग्रिड कार्ड्स
                      Expanded(
                        child: selectedCategory == null || !inventoryGroups.containsKey(selectedCategory)
                            ? const SizedBox()
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 1.8,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: inventoryGroups[selectedCategory]!.length,
                                itemBuilder: (ctx, i) {
                                  final v = inventoryGroups[selectedCategory]![i];
                                  final double price = ((v['price'] ?? 0) as num).toDouble();
                                  final String label = v['variant_label'] ?? '';
                                  final int stock = (v['stock_qty'] ?? 0) as int;
                                  final bool isOutOfStock = stock <= 0;

                                  return InkWell(
                                    onTap: () => _addToCart(v['id'], selectedCategory!, label, price, stock),
                                    onLongPress: () => _showItemOptions(v), // दबाकर रखने पर डिलीट या स्टॉक एडिट मेनू
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isOutOfStock ? const Color(0xFFF8FAFC) : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isOutOfStock
                                              ? Colors.red.shade200
                                              : (stock <= 5 ? Colors.orange.shade300 : const Color(0xFFE2E8F0)),
                                          width: isOutOfStock ? 1.2 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  label,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isOutOfStock ? Colors.black45 : Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                ),
                                              ),
                                              Text(
                                                '₹$price',
                                                style: TextStyle(
                                                  color: isOutOfStock ? Colors.grey : const Color(0xFF059669),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isOutOfStock
                                                      ? Colors.red.shade50
                                                      : (stock <= 5 ? Colors.orange.shade50 : Colors.blueGrey.shade50),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  isOutOfStock ? 'स्टॉक: 0 (खत्म)' : 'स्टॉक: $stock',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: isOutOfStock
                                                        ? Colors.red
                                                        : (stock <= 5 ? Colors.orange.shade800 : Colors.blueGrey),
                                                  ),
                                                ),
                                              ),
                                              CircleAvatar(
                                                radius: 11,
                                                backgroundColor: isOutOfStock ? Colors.grey.shade200 : const Color(0xFFECFDF5),
                                                child: Icon(
                                                  isOutOfStock ? Icons.block : Icons.add,
                                                  size: 14,
                                                  color: isOutOfStock ? Colors.grey : const Color(0xFF059669),
                                                ),
                                              ),
                                            ],
                                          )
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],

                    // बॉटम कार्ट व पेमेंट बार
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -3))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cart.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 90),
                              child: ListView(
                                shrinkWrap: true,
                                children: cart.entries.map((e) {
                                  final item = e.value;
                                  return Row(
                                    children: [
                                      Expanded(child: Text('${item['name']} (${item['variant']})', style: const TextStyle(fontSize: 12))),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 17),
                                        onPressed: () => _removeFromCart(e.key),
                                      ),
                                      Text('${item['qty']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: Colors.green, size: 17),
                                        onPressed: () => _addToCart(item['id'], item['name'], item['variant'], item['price'], item['stock']),
                                      ),
                                      SizedBox(
                                        width: 50,
                                        child: Text('₹${(item['price'] * item['qty']).toInt()}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(isTable ? '$selectedTable कुल:' : 'कुल देय:', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              Text('₹${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (isTable)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 12)),
                                icon: const Icon(Icons.add_task, color: Colors.white),
                                label: Text('$selectedTable में जोड़ें', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                onPressed: cart.isEmpty ? null : () => _processCheckout('TABLE'),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), padding: const EdgeInsets.symmetric(vertical: 12)),
                                    icon: const Icon(Icons.money, color: Colors.white, size: 18),
                                    label: const Text('नकद', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    onPressed: cart.isEmpty ? null : () => _processCheckout('CASH'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), padding: const EdgeInsets.symmetric(vertical: 12)),
                                    icon: const Icon(Icons.qr_code, color: Colors.white, size: 18),
                                    label: const Text('UPI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    onPressed: cart.isEmpty ? null : () => _processCheckout('UPI'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), padding: const EdgeInsets.symmetric(vertical: 12)),
                                    icon: const Icon(Icons.print, color: Colors.white, size: 18),
                                    label: const Text('प्रिंट', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    onPressed: cart.isEmpty ? null : () => _processCheckout('PAID_PRINT', shouldPrint: true),
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

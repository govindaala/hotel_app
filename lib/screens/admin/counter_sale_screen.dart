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

    try {
      // 1. टेबल संख्या निकालना
      final hotelRes = await supabase
          .from('restaurant_profiles')
          .select('*')
          .eq('restaurant_id', widget.storeCode)
          .maybeSingle();

      int count = 10;
      if (hotelRes != null) {
        final val = hotelRes['total_tables'] ?? hotelRes['tables_count'] ?? hotelRes['table_count'];
        if (val != null) count = int.tryParse(val.toString()) ?? 10;
      }

      availableTables = [
        'काउंटर सेल (डायरेक्ट)',
        ...List.generate(count, (i) => 'T-${i + 1}'),
      ];

      // 2. इन्वेंटरी व स्टॉक लोड करना
      final List<dynamic> allRows = await supabase.from('counter_inventory').select('*');
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
        if (grouped.isNotEmpty && (selectedCategory == null || !grouped.containsKey(selectedCategory))) {
          selectedCategory = grouped.keys.first;
        }
      });
    } catch (e) {
      setState(() => fetchErrorMessage = 'डेटा लोड एरर: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _addToCart(dynamic id, String name, String variant, double price, int stock) {
    final key = '$name ($variant)';
    final currentQty = cart[key]?['qty'] ?? 0;

    if (stock > 0 && currentQty >= stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('माफ़ करें! सिर्फ $stock स्टॉक बचा है।'), backgroundColor: Colors.orange),
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

  // थर्मल प्रिंटर से बिल प्रिंट करना
  Future<void> _printReceipt(String mode, double total, List<String> itemsDetails) async {
    try {
      bool isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) return;

      List<int> bytes = [];
      String billText = """
       काउंटर बिक्री पर्ची       
================================
तारीख: ${DateTime.now().toString().substring(0, 16)}
प्रकार: $mode  | टेबल: $selectedTable
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
      bytes = billText.codeUnits;
      await PrintBluetoothThermal.writeBytes(bytes);
    } catch (_) {}
  }

  // बिक्री पूरी करना व स्टॉक कम करना
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

      // डेटाबेस में स्टॉक घटाना (Stock Decrement)
      for (var item in cart.values) {
        if (item['id'] != null) {
          final int remaining = ((item['stock'] ?? 0) as int) - (item['qty'] as int);
          await supabase.from('counter_inventory').update({
            'stock_qty': remaining < 0 ? 0 : remaining,
          }).eq('id', item['id']);
        }
      }

      if (shouldPrint) {
        await _printReceipt(mode, total, details);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('बिक्री दर्ज हुई: ₹$total ($mode)'), backgroundColor: Colors.green),
        );
      }

      setState(() => cart.clear());
      _initScreenData(); // नया स्टॉक रिफ़्रेश
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('एरर: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // नया स्टॉक जोड़ना (जैसे 100 बोतल पानी आया)
  void _openAddStockDialog() {
    Map<String, dynamic>? selectedItem;
    final qtyCtrl = TextEditingController();

    // सभी आइटम्स की फ्लैट लिस्ट
    final List<Map<String, dynamic>> allItemsList = [];
    inventoryGroups.forEach((_, list) => allItemsList.addAll(list));

    if (allItemsList.isNotEmpty) selectedItem = allItemsList.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: const Text('📦 इन्वेंटरी स्टॉक जोड़ें', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Map<String, dynamic>>(
                value: selectedItem,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'सामान चुनें'),
                items: allItemsList.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text('${item['item_name']} - ${item['variant_label']} (मौजूदा: ${item['stock_qty'] ?? 0})', style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) => setDState(() => selectedItem = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'कितनी मात्रा आई? (उदा. 100)', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () async {
                final int addQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                if (selectedItem != null && addQty > 0) {
                  final int currentStock = (selectedItem!['stock_qty'] ?? 0) as int;
                  await supabase.from('counter_inventory').update({
                    'stock_qty': currentStock + addQty,
                  }).eq('id', selectedItem!['id']);

                  Navigator.pop(ctx);
                  _initScreenData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${selectedItem!['item_name']} में +$addQty स्टॉक जुड़ा!'), backgroundColor: Colors.teal),
                  );
                }
              },
              child: const Text('स्टॉक सेव करें', style: TextStyle(color: Colors.white)),
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
            icon: const Icon(Icons.inventory_2_outlined, color: Color(0xFF059669)),
            tooltip: 'स्टॉक जोड़ें',
            onPressed: _openAddStockDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: _initScreenData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // टेबल सेलेक्टर
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

                // कैटेगरी टैब्स
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

                // आइटम्स व स्टॉक कार्ड
                Expanded(
                  child: selectedCategory == null || !inventoryGroups.containsKey(selectedCategory)
                      ? const Center(child: Text('कोई आइटम उपलब्ध नहीं'))
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

                            return InkWell(
                              onTap: () => _addToCart(v['id'], selectedCategory!, label, price, stock),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: stock <= 5 ? Colors.red.shade200 : const Color(0xFFE2E8F0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1)),
                                        Text('₹$price', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 14)),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: stock <= 5 ? Colors.red.shade50 : Colors.blueGrey.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'स्टॉक: $stock',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: stock <= 5 ? Colors.red : Colors.blueGrey),
                                          ),
                                        ),
                                        const CircleAvatar(
                                          radius: 11,
                                          backgroundColor: Color(0xFFECFDF5),
                                          child: Icon(Icons.add, size: 15, color: Color(0xFF059669)),
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

                // बॉटम कार्ट व बिल प्रिंट बटन्स
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

                      // ऐक्शन बटन्स
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
                            // बिल प्रिंट बटन
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

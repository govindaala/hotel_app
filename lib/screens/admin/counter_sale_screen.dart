import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../receipt_generator.dart';
import '../../services/usb_printer_service.dart';
import '../../services/offline_database.dart';

class CounterSaleScreen extends StatefulWidget {
  final String storeCode;
  final void Function(Map<String, dynamic> kot)? onTableOrderAdded;

  const CounterSaleScreen({
    Key? key,
    required this.storeCode,
    this.onTableOrderAdded,
  }) : super(key: key);

  @override
  State<CounterSaleScreen> createState() => _CounterSaleScreenState();
}

class _CounterSaleScreenState extends State<CounterSaleScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String? fetchErrorMessage;

  Map<String, dynamic> _hotelProfile = {};
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

    final prefs = await SharedPreferences.getInstance();

    // 1. होटल प्रोफ़ाइल पहले लोकल कैश से दिखाएँ; इंटरनेट मिलने पर क्लाउड से ताज़ा करें।
    int count = 10;
    _hotelProfile = {
      'name': prefs.getString('saved_hotel_name') ?? 'AALA',
      'address': prefs.getString('saved_hotel_address') ?? '',
      'phone': prefs.getString('saved_hotel_phone') ?? '',
      'upi_id': prefs.getString('saved_hotel_upi') ?? '',
      'google_review_link': prefs.getString('saved_hotel_review') ?? '',
      'footer_message': prefs.getString('saved_hotel_footer') ?? '',
    };
    try {
      final hotelRes = await supabase
          .from('restaurants')
          .select('total_tables, name, address, phone, upi_id, gst_number, fssai_number, google_review_link, footer_message')
          .eq('store_code', widget.storeCode)
          .maybeSingle();

      if (hotelRes != null) {
        _hotelProfile = Map<String, dynamic>.from(hotelRes);
        count = int.tryParse(hotelRes['total_tables']?.toString() ?? '') ?? 10;
        await prefs.setString('saved_hotel_name', (_hotelProfile['name'] ?? 'AALA').toString());
        await prefs.setString('saved_hotel_address', (_hotelProfile['address'] ?? '').toString());
        await prefs.setString('saved_hotel_phone', (_hotelProfile['phone'] ?? '').toString());
        await prefs.setString('saved_hotel_upi', (_hotelProfile['upi_id'] ?? '').toString());
        await prefs.setString('saved_hotel_review', (_hotelProfile['google_review_link'] ?? '').toString());
        await prefs.setString('saved_hotel_footer', (_hotelProfile['footer_message'] ?? '').toString());
      }
    } catch (_) {
      count = prefs.getInt('saved_tables') ?? 10;
    }

    if (!mounted) return;
    setState(() {
      availableTables = [
        'काउंटर सेल (डायरेक्ट)',
        ...List.generate(count, (i) => 'T-${i + 1}'),
      ];
    });

    // 2. कैश्ड इन्वेंटरी तुरंत उपलब्ध रखें; नेटवर्क आने पर सर्वर डेटा अपडेट करें।
    final cacheKey = 'saved_counter_inventory_${widget.storeCode}';
    final cachedJson = prefs.getString(cacheKey);
    bool hasLocalInventory = false;
    if (cachedJson != null) {
      try {
        final cachedRows = List<Map<String, dynamic>>.from(jsonDecode(cachedJson));
        final grouped = _groupInventoryRows(cachedRows);
        if (mounted) {
          setState(() {
            inventoryGroups = grouped;
            selectedCategory = grouped.isEmpty ? null : (selectedCategory != null && grouped.containsKey(selectedCategory) ? selectedCategory : grouped.keys.first);
          });
        }
        hasLocalInventory = cachedRows.isNotEmpty;
      } catch (error) {
        debugPrint('Saved counter inventory cache is invalid: $error');
      }
    }

    try {
      final List<dynamic> allRows = await supabase
          .from('counter_inventory')
          .select('*')
          .order('id', ascending: true);
      final rows = allRows.map((row) => Map<String, dynamic>.from(row)).toList();
      await prefs.setString(cacheKey, jsonEncode(rows));
      final grouped = _groupInventoryRows(rows);
      if (mounted) {
        setState(() {
          inventoryGroups = grouped;
          selectedCategory = grouped.isEmpty ? null : (selectedCategory != null && grouped.containsKey(selectedCategory) ? selectedCategory : grouped.keys.first);
        });
      }
    } catch (error) {
      if (!hasLocalInventory && mounted) {
        setState(() => fetchErrorMessage = 'इन्वेंटरी अभी उपलब्ध नहीं है। पहली बार डेटा लोड करने के लिए इंटरनेट कनेक्शन चाहिए: $error');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveInventoryCache() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = inventoryGroups.values.expand((items) => items).toList();
    await prefs.setString('saved_counter_inventory_${widget.storeCode}', jsonEncode(rows));
  }

  Map<String, List<Map<String, dynamic>>> _groupInventoryRows(List<dynamic> allRows) {
    final Map<String, Map<String, dynamic>> mergedMap = {};
    for (final row in allRows) {
      if (row['restaurant_id'] == null) {
        final key = '${row['item_name']}_${row['variant_label']}';
        mergedMap[key] = Map<String, dynamic>.from(row);
      }
    }
    for (final row in allRows) {
      if (row['restaurant_id']?.toString() == widget.storeCode) {
        final key = '${row['item_name']}_${row['variant_label']}';
        mergedMap[key] = Map<String, dynamic>.from(row);
      }
    }
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in mergedMap.values) {
      final category = item['item_name'].toString();
      grouped.putIfAbsent(category, () => []).add(item);
    }
    return grouped;
  }

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
          content: Text('माफ़ करें! केवल $stock स्टॉक ही उपलब्ध है।'),
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
        cart[key] = {
          'id': id,
          'name': name,
          'variant': variant,
          'price': price,
          'qty': 1,
          'stock': stock
        };
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

  Future<void> _printReceipt(String mode, double total, {String? billNo}) async {
    try {
      final receiptItems = cart.values.map((item) => {
        'name': '${item['name']} ${item['variant']}',
        'qty': item['qty'],
        'price': item['price'],
      }).toList();
      final invoiceNo = billNo ?? 'POS-${DateTime.now().millisecondsSinceEpoch}';
      bool printed = false;

      final receipt = await buildThermalReceiptPdf(
        hotelName: (_hotelProfile['name'] ?? 'AALA').toString(),
        address: _hotelProfile['address']?.toString(),
        phone: _hotelProfile['phone']?.toString(),
        fssai: _hotelProfile['fssai_number']?.toString(),
        gstin: _hotelProfile['gst_number']?.toString(),
        tbl: 0,
        billNo: invoiceNo,
        paymentMode: mode,
        cashierName: 'Counter',
        footerMessage: _hotelProfile['footer_message']?.toString(),
        items: receiptItems,
        subTotal: total,
        discount: 0,
        discountPct: 0,
        upiId: _hotelProfile['upi_id']?.toString(),
        reviewUrl: _hotelProfile['google_review_link']?.toString(),
        paperWidthMm: 58,
        onImageGenerated: (imageBytes) async {
          printed = await UsbThermalPrinterManager.instance
              .printPngImage(imageBytes, paperWidthMm: 58);
        },
      );

      final directory = await getTemporaryDirectory();
      final pdfFile = File('${directory.path}/$invoiceNo.pdf');
      await pdfFile.writeAsBytes(await receipt.save(), flush: true);

      if (!mounted) return;
      final shouldShare = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('काउंटर बिल तैयार है'),
          content: Text(printed
              ? 'बिल थर्मल प्रिंटर पर प्रिंट हो गया। क्या PDF भी शेयर करनी है?'
              : 'थर्मल प्रिंटर कनेक्ट नहीं है। क्या PDF WhatsApp पर भेजनी है?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('बाद में'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.share),
              label: const Text('शेयर करें'),
            ),
          ],
        ),
      );
      if (shouldShare == true) {
        await Share.shareXFiles(
          [XFile(pdfFile.path)],
          text: '${_hotelProfile['name'] ?? 'AALA'} का काउंटर बिल $invoiceNo',
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('बिल PDF/प्रिंट में समस्या: $error')),
        );
      }
    }
  }

  Future<void> _processCheckout(String mode) async {
    if (cart.isEmpty) return;

    final double total = grandTotal;
    final List<String> details = cart.values
        .map((v) => '${v['name']} (${v['variant']}) x${v['qty']}')
        .toList();

    try {
      int? tableOrderNumber;
      List<Map<String, dynamic>>? tableOrderItems;
      String? tableOrderId;
      String? tableOrderCreatedAt;
      String? directSaleBillNo;

      if (selectedTable != 'काउंटर सेल (डायरेक्ट)') {
        final int tblNum = int.tryParse(selectedTable.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final formattedItems = cart.values.map((v) => {
          'name': '${v['name']} (${v['variant']})',
          'item_name': '${v['name']} (${v['variant']})',
          'qty': v['qty'],
          'price': v['price'],
          'total': v['price'] * v['qty'],
        }).toList();

        Map<String, dynamic> createdKot;
        try {
          final cloudKot = await supabase.from('hotel_kots').insert({
            'store_code': widget.storeCode,
            'restaurant_id': widget.storeCode,
            'table_no': tblNum,
            'table_name': selectedTable,
            'items': jsonEncode(formattedItems),
            'status': 'pending',
            'source': 'COUNTER_POS',
            'waiter_id': 'COUNTER',
            'created_at': DateTime.now().toIso8601String(),
          }).select('id, created_at').single();
          createdKot = Map<String, dynamic>.from(cloudKot);
        } catch (cloudError) {
          final localId = OfflineDatabase.instance.createId();
          final localCreatedAt = DateTime.now().toIso8601String();
          await OfflineDatabase.instance.enqueue(
            id: localId,
            storeCode: widget.storeCode,
            entity: 'hotel_kots',
            payload: {
              'id': localId,
              'store_code': widget.storeCode,
              'restaurant_id': widget.storeCode,
              'table_no': tblNum,
              'table_name': selectedTable,
              'items': jsonEncode(formattedItems),
              'status': 'pending',
              'source': 'COUNTER_POS_OFFLINE',
              'waiter_id': 'COUNTER',
              'created_at': localCreatedAt,
            },
          );
          createdKot = {'id': localId, 'created_at': localCreatedAt};
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('इंटरनेट उपलब्ध नहीं है। KOT इस डिवाइस में सुरक्षित है और नेटवर्क आने पर Sync होगा।'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          debugPrint('Counter KOT queued for offline sync: $cloudError');
        }
        tableOrderNumber = tblNum;
        tableOrderItems = formattedItems;
        tableOrderId = createdKot['id'].toString();
        tableOrderCreatedAt = createdKot['created_at'].toString();
      } else {
        final paymentMode = mode == 'UPI' ? 'UPI' : 'CASH';
        final billNo = 'POS-${DateTime.now().millisecondsSinceEpoch}';
        directSaleBillNo = billNo;
        final invoice = await supabase.from('invoices').insert({
          'store_code': widget.storeCode,
          'bill_no': billNo,
          'table_no': 0,
          'waiter_id': null,
          'subtotal': total,
          'discount_pct': 0,
          'discount_amt': 0,
          'final_amount': total,
          'payment_mode': paymentMode,
          'cashier_partner_name': 'Counter Sale',
          'created_at': DateTime.now().toIso8601String(),
        }).select('id').single();

        final invoiceItems = cart.values.map((item) => {
          'invoice_id': invoice['id'],
          'item_id': item['id']?.toString(),
          'item_name': '${item['name']} (${item['variant']})',
          'category': item['name'],
          'price': item['price'],
          'qty': item['qty'],
          'total_price': (item['price'] as num) * (item['qty'] as num),
        }).toList();
        try {
          await supabase.from('invoice_items').insert(invoiceItems);
        } catch (error) {
          await supabase.from('invoices').delete().eq('id', invoice['id']);
          rethrow;
        }

        // Invoice मुख्य बिक्री रिकॉर्ड है; cash-ledger sync failure से sale retry न हो।
        try {
          await supabase.from('daily_expenses').insert({
            'restaurant_id': widget.storeCode,
            'store_code': widget.storeCode,
            'title': 'काउंटर सेल: ${details.join(", ")} ($paymentMode)',
            'amount': total,
            'type': 'CASH_IN',
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('बिक्री सेव है, लेकिन कैश लेजर सिंक नहीं हुआ: $error')),
            );
          }
        }
      }

      // बिक्री/KOT के बाद स्टॉक लोकल में तुरंत घटाएँ और इंटरनेट आने पर क्लाउड Sync करें।
      for (final item in cart.values) {
        if (item['id'] == null) continue;
        final int currentStock = (item['stock'] as num?)?.toInt() ?? 0;
        final int quantity = (item['qty'] as num?)?.toInt() ?? 0;
        final int remaining = (currentStock - quantity).clamp(0, 1 << 31).toInt();
        for (final group in inventoryGroups.values) {
          for (final row in group) {
            if (row['id'].toString() == item['id'].toString()) {
              row['stock_qty'] = remaining;
            }
          }
        }
        try {
          await supabase.from('counter_inventory').update({
            'stock_qty': remaining,
          }).eq('id', item['id']);
        } catch (error) {
          await OfflineDatabase.instance.enqueue(
            id: 'inventory-${item['id']}',
            storeCode: widget.storeCode,
            entity: 'counter_inventory_update',
            payload: {'id': item['id'], 'stock_qty': remaining},
          );
          debugPrint('Inventory update queued for offline sync: $error');
        }
      }
      await _saveInventoryCache();

      if (tableOrderNumber != null && tableOrderItems != null) {
        widget.onTableOrderAdded?.call({
          'type': 'NEW_KOT',
          'table': tableOrderNumber,
          'waiter_id': 'COUNTER',
          'items': tableOrderItems,
          'id': tableOrderId,
          'created_at': tableOrderCreatedAt,
        });
      }

      if (selectedTable == 'काउंटर सेल (डायरेक्ट)') {
        await _printReceipt(mode == 'PAID_PRINT' ? 'CASH' : mode, total, billNo: directSaleBillNo);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(selectedTable != 'काउंटर सेल (डायरेक्ट)'
                ? '$selectedTable में सामान जोड़ दिया गया!'
                : 'बिक्री दर्ज हुई: ₹$total ($mode)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

      }

      if (mounted) {
        setState(() => cart.clear());
        _initScreenData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('एरर: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openStockAdjustDialog(Map<String, dynamic> item) {
    final stockCtrl = TextEditingController(text: '${item['stock_qty'] ?? 0}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('स्टॉक बदलें: ${item['item_name']} (${item['variant_label']})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('मौजूदा स्टॉक: ${item['stock_qty'] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey)),
            const SizedBox(height: 12),
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'नया सही स्टॉक सेट करें',
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
              }
            },
            child: const Text('सुरक्षित करें', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showItemOptions(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
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
              title: const Text('यह सामान डिलीट करें',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(ctx);
                if (item['id'] != null) {
                  await supabase.from('counter_inventory').delete().eq('id', item['id']);
                  _initScreenData();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAddCustomVariantDialog() {
    final nameCtrl = TextEditingController(text: selectedCategory ?? '');
    final varCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '50');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('➕ नया सामान / रेट जोड़ें',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'सामान (उदा. चिप्स, पानी)')),
              TextField(controller: varCtrl, decoration: const InputDecoration(labelText: 'रेंज / पैक (उदा. ₹20 वाला)')),
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

  @override
  Widget build(BuildContext context) {
    final bool isTable = selectedTable != 'काउंटर सेल (डायरेक्ट)';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('⚡ काउंटर सेल व इन्वेंटरी',
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18)),
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
                          Icon(Icons.table_restaurant,
                              color: isTable ? const Color(0xFF2563EB) : const Color(0xFF64748B), size: 20),
                          const SizedBox(width: 8),
                          const Text('बिल किसमें जोड़ना है?:',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const Spacer(),
                          DropdownButton<String>(
                            value: selectedTable,
                            underline: const SizedBox(),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isTable ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
                                fontSize: 13),
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
                          child: Text('कोई सामान उपलब्ध नहीं\n(ऊपर + दबाकर जोड़ें)', textAlign: TextAlign.center),
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
                                label: Text(name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSel ? Colors.white : Colors.black87,
                                        fontSize: 12)),
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
                                    onLongPress: () => _showItemOptions(v),
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
                                    label: const Text('नकद + प्रिंट', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    onPressed: cart.isEmpty ? null : () => _processCheckout('PAID_PRINT'),
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

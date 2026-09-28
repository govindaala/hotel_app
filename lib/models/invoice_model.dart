// lib/models/invoice_model.dart

// 1. बिल में शामिल प्रत्येक डिश का आइटम-वाइज़ मॉडल
class InvoiceItemModel {
  final String id;
  final String invoiceId;
  final String itemId;
  final String itemName;
  final String category;
  final double price;
  final int qty;
  final double totalPrice;

  const InvoiceItemModel({
    required this.id,
    required this.invoiceId,
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.price,
    required this.qty,
    required this.totalPrice,
  });

  factory InvoiceItemModel.fromMap(Map<String, dynamic> map) {
    return InvoiceItemModel(
      id: map['id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      itemId: map['item_id']?.toString() ?? '',
      itemName: map['item_name']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      qty: (map['qty'] as num?)?.toInt() ?? 1,
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'invoice_id': invoiceId,
      'item_id': itemId,
      'item_name': itemName,
      'category': category,
      'price': price,
      'qty': qty,
      'total_price': totalPrice,
    };
  }
}

// 2. मुख्य इनवॉइस मॉडल (बिल हेडर + ऑडिट डेटा)
class InvoiceModel {
  final String id;
  final String storeCode;
  final String billNo;
  final int tableNo;
  final String? waiterId; // स्टार वेटर ट्रैकिंग
  final String? cashierPartnerId; // किस पार्टनर की शिफ्ट में बिल कटा
  final double subtotal;
  final double discountPct;
  final double discountAmt;
  final double finalAmount;
  final String paymentMode; // 'CASH', 'UPI'
  final DateTime createdAt;
  final List<InvoiceItemModel>? items;

  const InvoiceModel({
    required this.id,
    required this.storeCode,
    required this.billNo,
    required this.tableNo,
    this.waiterId,
    this.cashierPartnerId,
    required this.subtotal,
    this.discountPct = 0.0,
    this.discountAmt = 0.0,
    required this.finalAmount,
    this.paymentMode = 'CASH',
    required this.createdAt,
    this.items,
  });

  factory InvoiceModel.fromMap(
    Map<String, dynamic> map, {
    List<InvoiceItemModel>? items,
  }) {
    return InvoiceModel(
      id: map['id']?.toString() ?? '',
      storeCode: map['store_code']?.toString() ?? '',
      billNo: map['bill_no']?.toString() ?? '',
      tableNo: (map['table_no'] as num?)?.toInt() ?? 0,
      waiterId: map['waiter_id']?.toString(),
      cashierPartnerId: map['cashier_partner_id']?.toString(),
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountPct: (map['discount_pct'] as num?)?.toDouble() ?? 0.0,
      discountAmt: (map['discount_amt'] as num?)?.toDouble() ?? 0.0,
      finalAmount: (map['final_amount'] as num?)?.toDouble() ?? 0.0,
      paymentMode: map['payment_mode']?.toString() ?? 'CASH',
      createdAt: map['created_at'] != null
          ? (DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
      items: items,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_code': storeCode,
      'bill_no': billNo,
      'table_no': tableNo,
      'waiter_id': waiterId,
      'cashier_partner_id': cashierPartnerId,
      'subtotal': subtotal,
      'discount_pct': discountPct,
      'discount_amt': discountAmt,
      'final_amount': finalAmount,
      'payment_mode': paymentMode,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

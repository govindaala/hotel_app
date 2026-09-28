// lib/models/vendor_model.dart

// 1. वेंडर / सप्लायर मास्टर मॉडल
class HotelVendorModel {
  final String id;
  final String storeCode;
  final String vendorName;
  final String category; // 'DAIRY', 'VEGETABLE', 'GROCERY', 'MEAT', 'OTHER'
  final String? phone;
  final double currentBalance; // उधारी / पेंडिंग बैलेंस (यदि होटल पर बकाया है)
  final bool isActive;
  final DateTime? createdAt;

  const HotelVendorModel({
    required this.id,
    required this.storeCode,
    required this.vendorName,
    required this.category,
    this.phone,
    this.currentBalance = 0.0,
    this.isActive = true,
    this.createdAt,
  });

  factory HotelVendorModel.fromMap(Map<String, dynamic> map) {
    return HotelVendorModel(
      id: map['id']?.toString() ?? '',
      storeCode: map['store_code']?.toString() ?? '',
      vendorName: map['vendor_name']?.toString() ?? '',
      category: map['vendor_category']?.toString() ??
          map['category']?.toString() ??
          'GROCERY',
      phone: map['phone']?.toString(),
      currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0.0,
      isActive: map['is_active'] ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_code': storeCode,
      'vendor_name': vendorName,
      'vendor_category': category,
      'phone': phone,
      'current_balance': currentBalance,
      'is_active': isActive,
    };
  }

  HotelVendorModel copyWith({
    String? id,
    String? storeCode,
    String? vendorName,
    String? category,
    String? phone,
    double? currentBalance,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return HotelVendorModel(
      id: id ?? this.id,
      storeCode: storeCode ?? this.storeCode,
      vendorName: vendorName ?? this.vendorName,
      category: category ?? this.category,
      phone: phone ?? this.phone,
      currentBalance: currentBalance ?? this.currentBalance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// 2. एडवांस राशन डिमांड मॉडल (वेंडर + खरीद लागत + पेमेंट मोड लिंकिंग)
class AdvancedRationDemandModel {
  final String id;
  final String storeCode;
  final String itemName;
  final String quantity;
  final bool isReceived;
  final String? vendorId;
  final String? vendorCategory;
  final double purchaseCost;
  final String paidBy; // 'DRAWER_CASH', 'UPI', 'PARTNER_POCKET', 'CREDIT'
  final String? partnerName;
  final DateTime createdAt;

  const AdvancedRationDemandModel({
    required this.id,
    required this.storeCode,
    required this.itemName,
    required this.quantity,
    this.isReceived = false,
    this.vendorId,
    this.vendorCategory,
    this.purchaseCost = 0.0,
    this.paidBy = 'DRAWER_CASH',
    this.partnerName,
    required this.createdAt,
  });

  factory AdvancedRationDemandModel.fromMap(Map<String, dynamic> map) {
    return AdvancedRationDemandModel(
      id: map['id']?.toString() ?? '',
      storeCode: map['store_code']?.toString() ?? '',
      itemName: map['item_name']?.toString() ?? '',
      quantity: map['quantity']?.toString() ?? '',
      isReceived: map['is_received'] ?? false,
      vendorId: map['vendor_id']?.toString(),
      vendorCategory: map['vendor_category']?.toString(),
      purchaseCost: (map['purchase_cost'] as num?)?.toDouble() ?? 0.0,
      paidBy: map['paid_by']?.toString() ?? 'DRAWER_CASH',
      partnerName: map['partner_name']?.toString(),
      createdAt: map['created_at'] != null
          ? (DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_code': storeCode,
      'item_name': itemName,
      'quantity': quantity,
      'is_received': isReceived,
      'vendor_id': vendorId,
      'vendor_category': vendorCategory,
      'purchase_cost': purchaseCost,
      'paid_by': paidBy,
      'partner_name': partnerName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

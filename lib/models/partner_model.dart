// lib/models/partner_model.dart

class RestaurantPartnerModel {
  final String id;
  final String storeCode;
  final String partnerId; // e.g. 'P1', 'P2'
  final String partnerName;
  final String? phone;
  final String loginPin; // 4-अंकों का व्यक्तिगत लॉगिन पिन
  final double sharePercentage; // e.g. 50.0, 25.0
  final bool isActive;
  final DateTime? createdAt;

  const RestaurantPartnerModel({
    required this.id,
    required this.storeCode,
    required this.partnerId,
    required this.partnerName,
    this.phone,
    required this.loginPin,
    required this.sharePercentage,
    this.isActive = true,
    this.createdAt,
  });

  factory RestaurantPartnerModel.fromMap(Map<String, dynamic> map) {
    return RestaurantPartnerModel(
      id: map['id']?.toString() ?? '',
      storeCode: map['store_code']?.toString() ?? '',
      partnerId: map['partner_id']?.toString() ?? '',
      partnerName: map['partner_name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      loginPin: map['login_pin']?.toString() ?? '0000',
      sharePercentage: (map['share_percentage'] as num?)?.toDouble() ?? 0.0,
      isActive: map['is_active'] ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_code': storeCode,
      'partner_id': partnerId,
      'partner_name': partnerName,
      'phone': phone,
      'login_pin': loginPin,
      'share_percentage': sharePercentage,
      'is_active': isActive,
    };
  }
}

// पार्टनर्स के व्यक्तिगत लेन-देन (जेब खर्च vs गल्ला विड्रॉल)
class PartnerLedgerModel {
  final String id;
  final String storeCode;
  final String partnerId;
  final String partnerName;
  final String type; // 'POCKET_EXPENSE', 'DRAWING', 'SETTLEMENT'
  final double amount;
  final String? note;
  final DateTime createdAt;

  const PartnerLedgerModel({
    required this.id,
    required this.storeCode,
    required this.partnerId,
    required this.partnerName,
    required this.type,
    required this.amount,
    this.note,
    required this.createdAt,
  });

  factory PartnerLedgerModel.fromMap(Map<String, dynamic> map) {
    return PartnerLedgerModel(
      id: map['id']?.toString() ?? '',
      storeCode: map['store_code']?.toString() ?? '',
      partnerId: map['partner_id']?.toString() ?? '',
      partnerName: map['partner_name']?.toString() ?? '',
      type: map['type']?.toString() ?? 'POCKET_EXPENSE',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      note: map['note']?.toString(),
      createdAt: map['created_at'] != null
          ? (DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_code': storeCode,
      'partner_id': partnerId,
      'partner_name': partnerName,
      'type': type,
      'amount': amount,
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

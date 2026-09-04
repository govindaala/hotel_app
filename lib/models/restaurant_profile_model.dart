class RestaurantProfileModel {
  final String id;
  final String name;
  final String phone;
  final String address;
  final String? gstin;
  final String? fssai;
  final String? upiId;
  final String footerMessage;
  final String? reviewUrl;

  const RestaurantProfileModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    this.gstin,
    this.fssai,
    this.upiId,
    this.footerMessage = 'Thank You! Visit Again! 🙏',
    this.reviewUrl,
  });

  factory RestaurantProfileModel.fromMap(Map<String, dynamic> map) {
    return RestaurantProfileModel(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      address: map['address'] ?? '',
      gstin: map['gstin'],
      fssai: map['fssai'],
      upiId: map['upi_id'],
      footerMessage: map['footer_message'] ?? 'Thank You! Visit Again! 🙏',
      reviewUrl: map['review_url'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'gstin': gstin,
      'fssai': fssai,
      'upi_id': upiId,
      'footer_message': footerMessage,
      'review_url': reviewUrl,
    };
  }
}

class RestaurantProfileModel {
  final String storeCode;
  final String name;
  final String? phone;
  final String? address;
  final String? upiId;
  final String? gstNumber;
  final String? fssaiNumber;
  final String? googleReviewLink;
  final String? footerMessage;

  RestaurantProfileModel({
    required this.storeCode,
    required this.name,
    this.phone,
    this.address,
    this.upiId,
    this.gstNumber,
    this.fssaiNumber,
    this.googleReviewLink,
    this.footerMessage,
  });

  factory RestaurantProfileModel.fromMap(Map<String, dynamic> map) {
    return RestaurantProfileModel(
      storeCode: (map['store_code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      phone: map['phone']?.toString(),
      address: map['address']?.toString(),
      upiId: map['upi_id']?.toString(),
      gstNumber: map['gst_number']?.toString(),
      fssaiNumber: map['fssai_number']?.toString(),
      googleReviewLink: map['google_review_link']?.toString(),
      footerMessage: map['footer_message']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'store_code': storeCode,
      'name': name,
      'phone': phone,
      'address': address,
      'upi_id': upiId,
      'gst_number': gstNumber,
      'fssai_number': fssaiNumber,
      'google_review_link': googleReviewLink,
      'footer_message': footerMessage,
    };
  }
}

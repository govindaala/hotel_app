class MenuItemModel {
  final String id;
  final String category;
  final String name;
  final double price;
  final bool isAvailable; // पॉज़ और एक्टिव (In Stock / Out of Stock) के लिए

  const MenuItemModel({
    required this.id,
    required this.category,
    required this.name,
    required this.price,
    this.isAvailable = true, // डिफ़ॉल्ट रूप से चालू रहेगा
  });

  MenuItemModel copyWith({
    String? id,
    String? category,
    String? name,
    double? price,
    bool? isAvailable,
  }) {
    return MenuItemModel(
      id: id ?? this.id,
      category: category ?? this.category,
      name: name ?? this.name,
      price: price ?? this.price,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  factory MenuItemModel.fromMap(Map<String, dynamic> map) {
    return MenuItemModel(
      id: (map['id'] ?? '').toString(),
      category: (map['category'] ?? 'अन्य').toString(),
      name: (map['name'] ?? '').toString(),
      price: ((map['price'] ?? 0.0) as num).toDouble(),
      isAvailable: map['is_available'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': name,
      'price': price,
      'is_available': isAvailable,
    };
  }
}

const List<String> kMenuCategories = [
  'सभी (All)',
  'ब्रेकफास्ट (Breakfast)',
  'स्नैक्स (Snacks)',
  'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)',
  'मेन कोर्स (Main Course Indian)',
  'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)',
  'चावल / पुलाव / बिरयानी (Rice Ka Khazana)',
  'रायता (Raita)',
  'सलाद (Salad)',
  'पापड़ (Papad)',
  'सूप (Soups)',
  'ठंडे पेय (Cold Beverages)',
  'गर्म पेय (Hot Beverages)',
  'एक्स्ट्रा (Extra)',
  'स्पेशल थाली (Special Thali)',
];

final List<MenuItemModel> kRestaurantMenu = [
  // 1. ब्रेकफास्ट
  const MenuItemModel(id: 'bf_1', category: 'ब्रेकफास्ट (Breakfast)', name: 'बटर टोस्ट (2 पीस)', price: 50),
  const MenuItemModel(id: 'bf_2', category: 'ब्रेकफास्ट (Breakfast)', name: 'प्लेन टोस्ट (2 पीस)', price: 40),
  const MenuItemModel(id: 'bf_3', category: 'ब्रेकफास्ट (Breakfast)', name: 'बटर टोस्ट जेम', price: 80),
  const MenuItemModel(id: 'bf_4', category: 'ब्रेकफास्ट (Breakfast)', name: 'पूरी सब्जी (6 नग)', price: 150),
  const MenuItemModel(id: 'bf_5', category: 'ब्रेकफास्ट (Breakfast)', name: 'मिक्स पराठा', price: 80),
  const MenuItemModel(id: 'bf_6', category: 'ब्रेकफास्ट (Breakfast)', name: 'पनीर पराठा', price: 100),
  const MenuItemModel(id: 'bf_7', category: 'ब्रेकफास्ट (Breakfast)', name: 'प्लेन पराठा', price: 50),
  const MenuItemModel(id: 'bf_8', category: 'ब्रेकफास्ट (Breakfast)', name: 'आलू पराठा', price: 80),
  const MenuItemModel(id: 'bf_9', category: 'ब्रेकफास्ट (Breakfast)', name: 'प्याज पराठा', price: 80),
  const MenuItemModel(id: 'bf_10', category: 'ब्रेकफास्ट (Breakfast)', name: 'पिनट मसाला', price: 120),

  // 2. स्नैक्स
  const MenuItemModel(id: 'sn_1', category: 'स्नैक्स (Snacks)', name: 'छोला भटूरा', price: 150),
  const MenuItemModel(id: 'sn_2', category: 'स्नैक्स (Snacks)', name: 'सेण्डविच शाकाहारी', price: 80),
  const MenuItemModel(id: 'sn_3', category: 'स्नैक्स (Snacks)', name: 'चीज सेण्डविच', price: 100),
  const MenuItemModel(id: 'sn_4', category: 'स्नैक्स (Snacks)', name: 'फ्रेंच फ्राई', price: 120),
  const MenuItemModel(id: 'sn_5', category: 'स्नैक्स (Snacks)', name: 'पनीर टिक्का', price: 200),
  const MenuItemModel(id: 'sn_6', category: 'स्नैक्स (Snacks)', name: 'पकोड़ा शाकाहारी', price: 120),
  const MenuItemModel(id: 'sn_7', category: 'स्नैक्स (Snacks)', name: 'पनीर पकोड़ा', price: 160),

  // 3. चाइनीज और कॉन्टिनेंटल
  const MenuItemModel(id: 'ch_1', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'चावल फ्राई शाकाहारी', price: 150),
  const MenuItemModel(id: 'ch_2', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'पनीर मिर्च', price: 200),
  const MenuItemModel(id: 'ch_3', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'वेज मेगी', price: 60),
  const MenuItemModel(id: 'ch_4', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'चीज मेगी', price: 100),
  const MenuItemModel(id: 'ch_5', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'मसाला मेगी', price: 100),
  const MenuItemModel(id: 'ch_6', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'पनीर चिल्ली ग्रेवी', price: 230),
  const MenuItemModel(id: 'ch_7', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'पनीर चिल्ली ड्राई', price: 250),
  const MenuItemModel(id: 'ch_8', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'वेज मंचुरियन', price: 200),
  const MenuItemModel(id: 'ch_9', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'वेज चाऊमिन', price: 140),
  const MenuItemModel(id: 'ch_10', category: 'चाइनीज और कॉन्टिनेंटल (Chinese & Continental)', name: 'हक्का नूडल्स', price: 130),

  // 4. मेन कोर्स
  const MenuItemModel(id: 'mc_1', category: 'मेन कोर्स (Main Course Indian)', name: 'दाल पीली तड़का', price: 160),
  const MenuItemModel(id: 'mc_2', category: 'मेन कोर्स (Main Course Indian)', name: 'दाल मखानी', price: 190),
  const MenuItemModel(id: 'mc_3', category: 'मेन कोर्स (Main Course Indian)', name: 'हांडी दाल स्पेशल', price: 180),
  const MenuItemModel(id: 'mc_4', category: 'मेन कोर्स (Main Course Indian)', name: 'नवरत्न कोरमा', price: 290),
  const MenuItemModel(id: 'mc_5', category: 'मेन कोर्स (Main Course Indian)', name: 'जीरा आलू', price: 170),
  const MenuItemModel(id: 'mc_6', category: 'मेन कोर्स (Main Course Indian)', name: 'आलू मसाला', price: 170),
  const MenuItemModel(id: 'mc_7', category: 'मेन कोर्स (Main Course Indian)', name: 'आलू मटर', price: 170),
  const MenuItemModel(id: 'mc_8', category: 'मेन कोर्स (Main Course Indian)', name: 'कश्मीरी दम आलू', price: 250),
  const MenuItemModel(id: 'mc_9', category: 'मेन कोर्स (Main Course Indian)', name: 'आलू दो प्याज स्पेशल', price: 200),
  const MenuItemModel(id: 'mc_10', category: 'मेन कोर्स (Main Course Indian)', name: 'मिक्स (शाकाहारी)', price: 190),
  const MenuItemModel(id: 'mc_11', category: 'मेन कोर्स (Main Course Indian)', name: 'सेव टमाटर', price: 160),
  const MenuItemModel(id: 'mc_12', category: 'मेन कोर्स (Main Course Indian)', name: 'स्टफ्ड टमाटर', price: 220),
  const MenuItemModel(id: 'mc_13', category: 'मेन कोर्स (Main Course Indian)', name: 'हरियाली कोफ्ता', price: 230),
  const MenuItemModel(id: 'mc_14', category: 'मेन कोर्स (Main Course Indian)', name: 'पंजाबी चना मसाला', price: 200),
  const MenuItemModel(id: 'mc_15', category: 'मेन कोर्स (Main Course Indian)', name: 'मशरूम मसाला', price: 250),
  const MenuItemModel(id: 'mc_16', category: 'मेन कोर्स (Main Course Indian)', name: 'मटर मशरूम टकाटक', price: 250),
  const MenuItemModel(id: 'mc_17', category: 'मेन कोर्स (Main Course Indian)', name: 'मलाई कोफ्ता', price: 230),
  const MenuItemModel(id: 'mc_18', category: 'मेन कोर्स (Main Course Indian)', name: 'पालक पनीर', price: 220),
  const MenuItemModel(id: 'mc_19', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर भुर्जी', price: 250),
  const MenuItemModel(id: 'mc_20', category: 'मेन कोर्स (Main Course Indian)', name: 'मटर पनीर', price: 240),
  const MenuItemModel(id: 'mc_21', category: 'मेन कोर्स (Main Course Indian)', name: 'कढ़ाई पनीर', price: 260),
  const MenuItemModel(id: 'mc_22', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर टिक्का मसाला', price: 260),
  const MenuItemModel(id: 'mc_23', category: 'मेन कोर्स (Main Course Indian)', name: 'बटर पनीर मसाला', price: 250),
  const MenuItemModel(id: 'mc_24', category: 'मेन कोर्स (Main Course Indian)', name: 'शाही पनीर', price: 240),
  const MenuItemModel(id: 'mc_25', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर पसंदा', price: 260),
  const MenuItemModel(id: 'mc_26', category: 'मेन कोर्स (Main Course Indian)', name: 'खोया पनीर', price: 250),
  const MenuItemModel(id: 'mc_27', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर टिक्का लवाबदार', price: 250),
  const MenuItemModel(id: 'mc_28', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर दो प्याज', price: 240),
  const MenuItemModel(id: 'mc_29', category: 'मेन कोर्स (Main Course Indian)', name: 'शिमला मिर्च', price: 230),
  const MenuItemModel(id: 'mc_30', category: 'मेन कोर्स (Main Course Indian)', name: 'आलू छोला', price: 180),
  const MenuItemModel(id: 'mc_31', category: 'मेन कोर्स (Main Course Indian)', name: 'काजू पनीर', price: 280),
  const MenuItemModel(id: 'mc_32', category: 'मेन कोर्स (Main Course Indian)', name: 'काजू करी', price: 300),
  const MenuItemModel(id: 'mc_33', category: 'मेन कोर्स (Main Course Indian)', name: 'काजू कोफ्ता', price: 250),
  const MenuItemModel(id: 'mc_34', category: 'मेन कोर्स (Main Course Indian)', name: 'काजू मसाला', price: 310),
  const MenuItemModel(id: 'mc_35', category: 'मेन कोर्स (Main Course Indian)', name: 'छोला पनीर', price: 270),
  const MenuItemModel(id: 'mc_36', category: 'मेन कोर्स (Main Course Indian)', name: 'सेव भाजी', price: 180),
  const MenuItemModel(id: 'mc_37', category: 'मेन कोर्स (Main Course Indian)', name: 'आलू गोभी', price: 150),
  const MenuItemModel(id: 'mc_38', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर मारवाड़ी', price: 290),
  const MenuItemModel(id: 'mc_39', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर राजस्थानी', price: 280),
  const MenuItemModel(id: 'mc_40', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर पंजाबी', price: 290),
  const MenuItemModel(id: 'mc_41', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर अंगारा', price: 320),
  const MenuItemModel(id: 'mc_42', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर कोरमा', price: 300),
  const MenuItemModel(id: 'mc_43', category: 'मेन कोर्स (Main Course Indian)', name: 'हांडी पनीर', price: 250),
  const MenuItemModel(id: 'mc_44', category: 'मेन कोर्स (Main Course Indian)', name: 'पनीर लसोइनी', price: 270),
  const MenuItemModel(id: 'mc_45', category: 'मेन कोर्स (Main Course Indian)', name: 'कढ़ाई मशरूम', price: 270),
  const MenuItemModel(id: 'mc_46', category: 'मेन कोर्स (Main Course Indian)', name: 'मशरूम दो प्याज', price: 250),

  // 5. तंदूरी ब्रेड्स / रोटियां
  const MenuItemModel(id: 'tb_1', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'तन्दूरी रोटी प्लेन', price: 15),
  const MenuItemModel(id: 'tb_2', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'तन्दूरी रोटी (मक्खन)', price: 20),
  const MenuItemModel(id: 'tb_3', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'तवा रोटी सादा', price: 15),
  const MenuItemModel(id: 'tb_4', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'तवा रोटी मक्खन', price: 20),
  const MenuItemModel(id: 'tb_5', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'मिस्सी रोटी मक्खन', price: 50),
  const MenuItemModel(id: 'tb_6', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'नान सादा', price: 50),
  const MenuItemModel(id: 'tb_7', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'नान बटर', price: 60),
  const MenuItemModel(id: 'tb_8', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'गारलिक नान', price: 80),
  const MenuItemModel(id: 'tb_9', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'स्टफ नान मक्खन', price: 100),
  const MenuItemModel(id: 'tb_10', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'पनीर नान मक्खन', price: 100),
  const MenuItemModel(id: 'tb_11', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'लच्छा पराठा', price: 60),
  const MenuItemModel(id: 'tb_12', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'स्टफ पराठा', price: 80),
  const MenuItemModel(id: 'tb_13', category: 'तंदूरी ब्रेड्स / रोटियां (Tandoori Breads)', name: 'चीज नान', price: 90),

  // 6. चावल / पुलाव / बिरयानी
  const MenuItemModel(id: 'rc_1', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'सादा चावल', price: 100),
  const MenuItemModel(id: 'rc_2', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'जीरा चावल', price: 120),
  const MenuItemModel(id: 'rc_3', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'शाकाहारी पुलाव', price: 150),
  const MenuItemModel(id: 'rc_4', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'मटर पुलाव', price: 150),
  const MenuItemModel(id: 'rc_5', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'शाकाहारी बिरयानी', price: 150),
  const MenuItemModel(id: 'rc_6', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'कश्मीरी पुलाव', price: 170),
  const MenuItemModel(id: 'rc_7', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'काजू पुलाव', price: 150),
  const MenuItemModel(id: 'rc_8', category: 'चावल / पुलाव / बिरयानी (Rice Ka Khazana)', name: 'पनीर पुलाव', price: 160),

  // 7. रायता
  const MenuItemModel(id: 'rt_1', category: 'रायता (Raita)', name: 'रायता सादा', price: 80),
  const MenuItemModel(id: 'rt_2', category: 'रायता (Raita)', name: 'दही सादा', price: 80),
  const MenuItemModel(id: 'rt_3', category: 'रायता (Raita)', name: 'मिक्स शाकाहारी रायता', price: 110),
  const MenuItemModel(id: 'rt_4', category: 'रायता (Raita)', name: 'बूंदी रायता', price: 100),
  const MenuItemModel(id: 'rt_5', category: 'रायता (Raita)', name: 'पाइनेपल रायता', price: 120),
  const MenuItemModel(id: 'rt_6', category: 'रायता (Raita)', name: 'फ्रूट रायता', price: 120),
  const MenuItemModel(id: 'rt_7', category: 'रायता (Raita)', name: 'प्याज रायता', price: 100),
  const MenuItemModel(id: 'rt_8', category: 'रायता (Raita)', name: 'आलू रायता', price: 100),
  const MenuItemModel(id: 'rt_9', category: 'रायता (Raita)', name: 'दही फ्राई', price: 150),

  // 8. सलाद
  const MenuItemModel(id: 'sl_1', category: 'सलाद (Salad)', name: 'ग्रीन सलाद', price: 50),
  const MenuItemModel(id: 'sl_2', category: 'सलाद (Salad)', name: 'प्याज सलाद', price: 35),
  const MenuItemModel(id: 'sl_3', category: 'सलाद (Salad)', name: 'टमाटर सलाद', price: 50),
  const MenuItemModel(id: 'sl_4', category: 'सलाद (Salad)', name: 'खीरा सलाद', price: 50),
  const MenuItemModel(id: 'sl_5', category: 'सलाद (Salad)', name: 'कचुम्बर सलाद', price: 70),

  // 9. पापड़
  const MenuItemModel(id: 'pd_1', category: 'पापड़ (Papad)', name: 'रोस्टेड पापड़', price: 20),
  const MenuItemModel(id: 'pd_2', category: 'पापड़ (Papad)', name: 'तले हुए पापड़', price: 40),
  const MenuItemModel(id: 'pd_3', category: 'पापड़ (Papad)', name: 'मसाला पापड़', price: 50),

  // 10. सूप
  const MenuItemModel(id: 'sp_1', category: 'सूप (Soups)', name: 'टमाटर सूप क्रीम', price: 120),
  const MenuItemModel(id: 'sp_2', category: 'सूप (Soups)', name: 'स्वीट कॉर्न सूप मीठा शाकाहारी', price: 120),
  const MenuItemModel(id: 'sp_3', category: 'सूप (Soups)', name: 'सूप शाकाहारी (वेज)', price: 100),
  const MenuItemModel(id: 'sp_4', category: 'सूप (Soups)', name: 'मशरूम सूप क्रीम', price: 160),

  // 11. ठंडे पेय
  const MenuItemModel(id: 'cb_1', category: 'ठंडे पेय (Cold Beverages)', name: 'ठंडा दूध', price: 40),
  const MenuItemModel(id: 'cb_2', category: 'ठंडे पेय (Cold Beverages)', name: 'कोल्ड कॉफी', price: 120),
  const MenuItemModel(id: 'cb_3', category: 'ठंडे पेय (Cold Beverages)', name: 'कोल्ड कॉफी आइसक्रीम', price: 150),
  const MenuItemModel(id: 'cb_4', category: 'ठंडे पेय (Cold Beverages)', name: 'फ्रेश लेमन सोडा', price: 60),
  const MenuItemModel(id: 'cb_5', category: 'ठंडे पेय (Cold Beverages)', name: 'सादा सोडा', price: 20),
  const MenuItemModel(id: 'cb_6', category: 'ठंडे पेय (Cold Beverages)', name: 'लस्सी मीठी', price: 80),
  const MenuItemModel(id: 'cb_7', category: 'ठंडे पेय (Cold Beverages)', name: 'लस्सी नमकीन', price: 60),
  const MenuItemModel(id: 'cb_8', category: 'ठंडे पेय (Cold Beverages)', name: 'छाछ', price: 30),

  // 12. गर्म पेय
  const MenuItemModel(id: 'hb_1', category: 'गर्म पेय (Hot Beverages)', name: 'चाय', price: 20),
  const MenuItemModel(id: 'hb_2', category: 'गर्म पेय (Hot Beverages)', name: 'मसाला चाय', price: 25),
  const MenuItemModel(id: 'hb_3', category: 'गर्म पेय (Hot Beverages)', name: 'नींबू काली चाय', price: 25),
  const MenuItemModel(id: 'hb_4', category: 'गर्म पेय (Hot Beverages)', name: 'कॉफी हाट', price: 50),
  const MenuItemModel(id: 'hb_5', category: 'गर्म पेय (Hot Beverages)', name: 'ब्लैक कॉफी', price: 50),
  const MenuItemModel(id: 'hb_6', category: 'गर्म पेय (Hot Beverages)', name: 'गर्म दूध', price: 50),

  // 13. एक्स्ट्रा
  const MenuItemModel(id: 'ex_1', category: 'एक्स्ट्रा (Extra)', name: 'चटनी', price: 120),
  const MenuItemModel(id: 'ex_2', category: 'एक्स्ट्रा (Extra)', name: 'मक्खन (50 ग्राम)', price: 40),
  const MenuItemModel(id: 'ex_3', category: 'एक्स्ट्रा (Extra)', name: 'मक्खन (100 ग्राम)', price: 80),
  const MenuItemModel(id: 'ex_4', category: 'एक्स्ट्रा (Extra)', name: 'अतिरिक्त भटूरे और भाजी', price: 40),

  // 14. स्पेशल थाली
  const MenuItemModel(
    id: 'th_1',
    category: 'स्पेशल थाली (Special Thali)',
    name: 'स्पेशल थाली (दाल, मिक्स वेज, पनीर, राईस, छाछ, मिठाई, पापड़, 4 चपाती, 1 लच्छा पराठा)',
    price: 350,
  ),
];

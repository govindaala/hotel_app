// lib/services/kitchen_learning_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class KitchenLearningService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // -------------------------------------------------------------
  // 1. डायनेमिक कुकिंग टाइमर (Kitchen Prep Time Estimator)
  // -------------------------------------------------------------

  /// किसी नए ऑर्डर के तैयार होने के कुल मिनट का अनुमान लगाना
  static Future<int> estimateOrderPrepMinutes({
    required String storeCode,
    required List<Map<String, dynamic>> items,
    required int pendingOrdersAhead,
  }) async {
    // 1. आधार समय (Base Time) तय करना
    double basePrepMinutes = 14.0; // डिफ़ॉल्ट आधार समय

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAvg = prefs.getDouble('learned_avg_prep_time_$storeCode');

      if (cachedAvg != null && cachedAvg > 5) {
        // यदि 15-30 दिन का सीखा हुआ डेटा उपलब्ध है
        basePrepMinutes = cachedAvg;
      } else {
        // शुरुआती फेज़: डिश के प्रकार से अनुमान
        bool hasHeavyMainCourse = false;
        bool hasOnlyBeverages = true;

        for (var it in items) {
          final name = (it['name'] ?? '').toString().toLowerCase();
          final cat = (it['category'] ?? it['cat'] ?? '').toString().toLowerCase();

          if (cat.contains('main course') || name.contains('paneer') || name.contains('thali')) {
            hasHeavyMainCourse = true;
            hasOnlyBeverages = false;
          } else if (!cat.contains('beverage') && !cat.contains('tea') && !cat.contains('coffee')) {
            hasOnlyBeverages = false;
          }
        }

        if (hasOnlyBeverages) {
          basePrepMinutes = 8.0; // सिर्फ चाय/पेय
        } else if (hasHeavyMainCourse) {
          basePrepMinutes = 20.0; // भारी भोजन/पनीर स्पेशल
        } else {
          basePrepMinutes = 14.0; // सामान्य स्नैक्स/नाश्ता
        }
      }
    } catch (_) {}

    // 2. किचन कतार का लोड (Queue Buffer)
    // प्रत्येक पूर्व ऑर्डर के लिए औसतन 5.5 मिनट का कतार बफर
    double queueDelayFactor = 5.5;

    try {
      final prefs = await SharedPreferences.getInstance();
      final learnedQueue = prefs.getDouble('learned_queue_factor_$storeCode');
      if (learnedQueue != null && learnedQueue > 2) {
        queueDelayFactor = learnedQueue;
      }
    } catch (_) {}

    final double totalEstimated = basePrepMinutes + (pendingOrdersAhead * queueDelayFactor);
    return totalEstimated.round();
  }

  /// जब कुक KDS में 'Ready' दबाए, तब वास्तविक समय दर्ज करके सिस्टम को सिखाना
  static Future<void> recordKotCompletionAndLearn({
    required String storeCode,
    required String kotId,
    required DateTime createdAt,
  }) async {
    final now = DateTime.now();
    final int diffMinutes = now.difference(createdAt).inMinutes;
    final int actualPrepMinutes = diffMinutes < 1 ? 1 : diffMinutes;

    try {
      // 1. Supabase में तैयार होने का समय और लगे मिनट अपडेट करना
      await _supabase.from('hotel_kots').update({
        'status': 'ready',
        'ready_at': now.toIso8601String(),
        'actual_prep_minutes': actualPrepMinutes,
      }).eq('id', kotId);

      // 2. ऑटो-लर्निंग: पिछले 30 पूर्ण ऑर्डर्स का रोलिंग औसत निकालना
      final history = await _supabase
          .from('hotel_kots')
          .select('actual_prep_minutes')
          .eq('store_code', storeCode)
          .eq('status', 'ready')
          .not('actual_prep_minutes', 'is', null)
          .order('ready_at', ascending: false)
          .limit(30);

      if (history.isNotEmpty) {
        double sum = 0;
        int count = 0;
        for (var row in history) {
          final m = (row['actual_prep_minutes'] as num?)?.toDouble() ?? 0.0;
          if (m > 2 && m < 90) { // असामान्य त्रुटियों को फ़िल्टर करना
            sum += m;
            count++;
          }
        }

        if (count >= 10) {
          final double rollingAvg = sum / count;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble('learned_avg_prep_time_$storeCode', rollingAvg);

          // कतार फैक्टर का ऑटोमैटिक अनुकूलन
          final double dynamicQueueFactor = (rollingAvg * 0.35).clamp(3.0, 8.0);
          await prefs.setDouble('learned_queue_factor_$storeCode', dynamicQueueFactor);
        }
      }
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // 2. वीकेंड राशन प्रेडिक्शन (Predictive Grocery Forecasting)
  // -------------------------------------------------------------

  /// पिछले 3 वीकेंड्स (शुक्रवार से रविवार) की खपत देखकर आगामी वीकेंड का राशन अनुमान
  static Future<List<Map<String, dynamic>>> predictWeekendRation({
    required String storeCode,
  }) async {
    final List<Map<String, dynamic>> predictions = [];

    try {
      final now = DateTime.now();
      final threeWeeksAgo = now.subtract(const Duration(days: 21)).toIso8601String();

      // पिछले 21 दिनों के इनवॉइस आइटम्स फेच करना
      final salesData = await _supabase
          .from('invoice_items')
          .select('item_name, qty, category')
          .gte('created_at', threeWeeksAgo);

      if (salesData.isEmpty) {
        // यदि इनवॉइस डेटा अभी नया है, तो बेसिक अनुमान सूची लौटाना
        return [
          {'item_name': 'पनीर (Paneer)', 'quantity': '12 KG', 'reason': 'वीकेंड स्पेशल औसत'},
          {'item_name': 'प्याज (Onion)', 'quantity': '30 KG', 'reason': 'सामान्य वीकेंड खपत'},
          {'item_name': 'टमाटर (Tomato)', 'quantity': '20 KG', 'reason': 'ग्रेवी व सलाद आवश्यकता'},
          {'item_name': 'दूध (Milk)', 'quantity': '15 Ltr', 'reason': 'चाय व मिष्ठान'},
        ];
      }

      int paneerDishesCount = 0;
      int gravyDishesCount = 0;
      int teaCoffeeCount = 0;

      for (var row in salesData) {
        final name = (row['item_name'] ?? '').toString().toLowerCase();
        final qty = (row['qty'] as num?)?.toInt() ?? 1;

        if (name.contains('paneer')) {
          paneerDishesCount += qty;
        }
        if (name.contains('curry') || name.contains('masala') || name.contains('dal')) {
          gravyDishesCount += qty;
        }
        if (name.contains('tea') || name.contains('chai') || name.contains('coffee')) {
          teaCoffeeCount += qty;
        }
      }

      // 3 हफ़्तों का औसत प्रति वीकेंड (Recipe BOM फ़ॉर्मूला)
      // 1 पनीर डिश ≈ 140 ग्राम पनीर
      final double estimatedPaneerKg = ((paneerDishesCount / 3) * 0.14).clamp(5.0, 50.0);
      // प्रति 10 ग्रेवी डिश ≈ 1.5 किलो प्याज, 1 किलो टमाटर
      final double estimatedOnionKg = ((gravyDishesCount / 3) * 0.15).clamp(10.0, 80.0);
      final double estimatedTomatoKg = ((gravyDishesCount / 3) * 0.10).clamp(8.0, 50.0);
      // प्रति 10 कप चाय ≈ 1.2 लीटर दूध
      final double estimatedMilkLtr = ((teaCoffeeCount / 3) * 0.12).clamp(5.0, 40.0);

      predictions.add({
        'item_name': 'पनीर (Paneer)',
        'quantity': '${estimatedPaneerKg.toStringAsFixed(1)} KG',
        'reason': 'पिछले 3 वीकेंड्स में औसतन ${(paneerDishesCount / 3).round()} पनीर डिशेज़ बिकीं',
      });
      predictions.add({
        'item_name': 'प्याज (Onion)',
        'quantity': '${estimatedOnionKg.toStringAsFixed(1)} KG',
        'reason': 'मुख्य ग्रेवी डिशेज़ की औसत खपत के आधार पर',
      });
      predictions.add({
        'item_name': 'टमाटर (Tomato)',
        'quantity': '${estimatedTomatoKg.toStringAsFixed(1)} KG',
        'reason': 'सूप, सलाद व मसाला ग्रेवी हेतु',
      });
      predictions.add({
        'item_name': 'दूध (Fresh Milk)',
        'quantity': '${estimatedMilkLtr.toStringAsFixed(1)} Ltr',
        'reason': 'हॉट बेवरेजेस व शेक की औसत वीकेंड मांग',
      });
    } catch (_) {}

    return predictions;
  }
}

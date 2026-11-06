import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends store-scoped business records only; no customer PII or credentials.
class IntelligentReportService {
  IntelligentReportService._();

  static const String _apiBaseUrl = String.fromEnvironment(
    'AALA_INTELLIGENCE_API_URL',
    defaultValue: '',
  );
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> _fetchAllRows(
    Future<dynamic> Function(int from, int to) pageRequest,
  ) async {
    const pageSize = 1000;
    const maxPages = 20;
    final rows = <Map<String, dynamic>>[];
    for (var page = 0; page < maxPages; page++) {
      final response = await pageRequest(page * pageSize, (page + 1) * pageSize - 1);
      final batch = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      rows.addAll(batch);
      if (batch.length < pageSize) return rows;
    }
    throw StateError('इस अवधि में 20,000 से अधिक रिकॉर्ड हैं। छोटी अवधि चुनें।');
  }

  static Future<void> generateAndShare({
    required String storeCode,
    required String hotelName,
    required String periodLabel,
    required DateTime startDate,
    required DateTime endDateExclusive,
  }) async {
    if (_apiBaseUrl.trim().isEmpty) {
      throw StateError(
        'Python रिपोर्ट सर्वर कॉन्फ़िगर नहीं है। Render पर सेवा deploy करके '
        'AALA_INTELLIGENCE_API_URL के साथ APK build करें।',
      );
    }

    final start = startDate.toIso8601String();
    final end = endDateExclusive.toIso8601String();

    final invoices = await _fetchAllRows((from, to) => _supabase
        .from('invoices')
        .select('final_amount, payment_mode, table_no, created_at')
        .eq('store_code', storeCode)
        .gte('created_at', start)
        .lt('created_at', end)
        .order('created_at', ascending: true)
        .range(from, to));

    final invoiceItems = await _fetchAllRows((from, to) => _supabase
        .from('invoice_items')
        .select('item_name, category, qty, price, total_price, invoices!inner(store_code, created_at)')
        .eq('invoices.store_code', storeCode)
        .gte('invoices.created_at', start)
        .lt('invoices.created_at', end)
        .range(from, to));

    final purchases = await _fetchAllRows((from, to) => _supabase
        .from('ration_demands')
        .select('item_name, quantity, is_received, purchase_cost, vendor_category, created_at')
        .eq('store_code', storeCode)
        .gte('created_at', start)
        .lt('created_at', end)
        .range(from, to));

    final expenses = await _fetchAllRows((from, to) => _supabase
        .from('daily_expenses')
        .select('title, amount, type, created_at')
        .or('restaurant_id.eq.$storeCode,store_code.eq.$storeCode')
        .gte('created_at', start)
        .lt('created_at', end)
        .range(from, to));

    final kots = await _fetchAllRows((from, to) => _supabase
        .from('hotel_kots')
        .select('status, actual_prep_minutes, created_at')
        .eq('store_code', storeCode)
        .gte('created_at', start)
        .lt('created_at', end)
        .range(from, to));

    final payload = <String, dynamic>{
      'store_code': storeCode,
      'hotel_name': hotelName,
      'period_label': periodLabel,
      'start_date': startDate.toIso8601String().split('T').first,
      'end_date': endDateExclusive.subtract(const Duration(days: 1))
          .toIso8601String().split('T').first,
      'invoices': invoices,
      'invoice_items': invoiceItems,
      'purchases': purchases,
      'expenses': expenses,
      'kots': kots,
    };

    final base = _apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final response = await http.post(
      Uri.parse('$base/v1/report.pdf'),
      headers: const {'Content-Type': 'application/json', 'Accept': 'application/pdf'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 90));

    if (response.statusCode != 200 ||
        response.bodyBytes.length < 5 ||
        String.fromCharCodes(response.bodyBytes.take(5)) != '%PDF-') {
      var detail = 'HTTP ${response.statusCode}';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['detail'] != null) {
          detail = decoded['detail'].toString();
        }
      } catch (_) {}
      throw HttpException('इंटेलिजेंट रिपोर्ट नहीं बन सकी: $detail');
    }

    final directory = await getTemporaryDirectory();
    final safeStore = storeCode.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      '${directory.path}/AALA-Intelligence-$safeStore-${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(response.bodyBytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: '$hotelName — $periodLabel की AALA POS इंटेलिजेंट रिपोर्ट',
    );
  }
}

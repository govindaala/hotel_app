import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/kot_payload.dart';

void main() {
  group('buildKotPayload', () {
    test('keeps one client ID and immutable order data for retry', () {
      final createdAt = DateTime.parse('2026-11-08T10:30:00.000Z');
      const id = '2f4a8c10-7d11-4b19-9b3f-0e4f6a8d1c20';
      const storeCode = 'HOTEL-01';
      final items = [
        {'name': 'Tea', 'price': 15, 'qty': 2},
      ];

      final payload = buildKotPayload(
        id: id,
        storeCode: storeCode,
        tableNo: 4,
        tableName: 'T-4',
        items: items,
        source: 'COUNTER_POS',
        waiterId: 'COUNTER',
        createdAt: createdAt,
        customerName: 'Walk-in',
        customerPhone: '',
      );

      expect(payload['id'], id);
      expect(payload['store_code'], storeCode);
      expect(payload['restaurant_id'], storeCode);
      expect(payload['table_no'], 4);
      expect(payload['status'], 'pending');
      expect(payload['created_at'], createdAt.toIso8601String());
      expect(jsonDecode(payload['items'] as String), items);
      expect(payload['customer_name'], 'Walk-in');
      expect(payload['customer_phone'], '');
    });
  });

  group('isRetryableNetworkError', () {
    test('queues transport failures but not application errors', () {
      expect(isRetryableNetworkError(SocketException('offline')), isTrue);
      expect(isRetryableNetworkError(TimeoutException('timed out')), isTrue);
      expect(isRetryableNetworkError(StateError('invalid payload')), isFalse);
    });
  });
}

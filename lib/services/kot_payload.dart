import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Builds a KOT with a client-generated ID so an ambiguous network retry
/// upserts the same order instead of creating a second kitchen ticket.
Map<String, dynamic> buildKotPayload({
  required String id,
  required String storeCode,
  required int tableNo,
  required String tableName,
  required List<Map<String, dynamic>> items,
  required String source,
  required String waiterId,
  required DateTime createdAt,
  String? customerName,
  String? customerPhone,
}) {
  return {
    'id': id,
    'store_code': storeCode,
    'restaurant_id': storeCode,
    'table_no': tableNo,
    'table_name': tableName,
    'items': jsonEncode(items),
    'status': 'pending',
    'source': source,
    'waiter_id': waiterId,
    if (customerName != null) 'customer_name': customerName,
    if (customerPhone != null) 'customer_phone': customerPhone,
    'created_at': createdAt.toIso8601String(),
  };
}

/// Only transport failures should be queued. Server validation/permission
/// errors must remain visible instead of becoming permanently stuck records.
bool isRetryableNetworkError(Object error) {
  return error is IOException ||
      error is TimeoutException ||
      error is http.ClientException;
}


/// Builds a tenant-scoped, idempotent status update for the local retry queue.
Map<String, dynamic> buildKotStatusPayload({
  required String id,
  required String storeCode,
  required String status,
}) {
  return {
    'id': id,
    'store_code': storeCode,
    'status': status,
  };
}

String buildKotStatusOperationId(String kotId, String status) =>
    '$kotId-status-$status';

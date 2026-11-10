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


/// Only these KOT states are written by the offline status queue.
bool isSupportedKotStatus(String status) =>
    const {'pending', 'preparing', 'ready'}.contains(status);

/// Builds a tenant-scoped, idempotent status update for the local retry queue.
/// Preparing operations retain their original start time and QR order link.
Map<String, dynamic> buildKotStatusPayload({
  required String id,
  required String storeCode,
  required String status,
  String? startedAt,
  String? qrOrderId,
}) {
  return {
    'id': id,
    'store_code': storeCode,
    'status': status,
    if (startedAt != null) 'started_at': startedAt,
    if (qrOrderId != null && qrOrderId.isNotEmpty) 'qr_order_id': qrOrderId,
  };
}

String buildKotStatusOperationId(String kotId, String status) =>
    '$kotId-status-$status';

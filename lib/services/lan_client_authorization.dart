import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'line_json_protocol.dart';

/// Limits repeated failed LAN authentication attempts per remote IP.
class LanAuthRateLimiter {
  LanAuthRateLimiter({
    this.maxAttempts = 5,
    this.window = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxAttempts;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _failures = {};

  bool isBlocked(String key) => _recentFailures(key).length >= maxAttempts;

  void recordFailure(String key) {
    final recent = _recentFailures(key)..add(_now());
    _failures[key] = recent;
  }

  void clear(String key) {
    _failures.remove(key);
  }

  List<DateTime> _recentFailures(String key) {
    final cutoff = _now().subtract(window);
    final recent = (_failures[key] ?? const <DateTime>[])
        .where((attempt) => attempt.isAfter(cutoff))
        .toList();
    if (recent.isEmpty) {
      _failures.remove(key);
    } else {
      _failures[key] = recent;
    }
    return recent;
  }
}

/// Challenge-response and role checks for the counter's local TCP protocol.
///
/// The staff PIN is never sent over the LAN. The server issues a one-use nonce
/// and both ends calculate an HMAC proof from the PIN and that nonce.
class LanClientAuthorization {
  LanClientAuthorization._();

  static String createNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String createProof({
    required String pin,
    required String nonce,
  }) {
    final nonceBytes = base64Url.decode(nonce);
    final digest = Hmac(sha256, utf8.encode(pin)).convert(nonceBytes);
    return base64UrlEncode(digest.bytes);
  }

  static bool verifyProof({
    required String pin,
    required String nonce,
    required String proof,
  }) {
    try {
      final expected = base64Url.decode(createProof(pin: pin, nonce: nonce));
      final actual = base64Url.decode(proof);
      if (expected.length != actual.length) return false;

      // Compare every byte so a mismatch does not short-circuit the loop.
      var difference = 0;
      for (var index = 0; index < expected.length; index++) {
        difference |= expected[index] ^ actual[index];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic>? findStaff({
    required String expectedStoreCode,
    required String requestedStoreCode,
    required String role,
    required String staffId,
    required List<Map<String, dynamic>> staffCache,
  }) {
    final store = expectedStoreCode.trim().toUpperCase();
    if (store.isEmpty || requestedStoreCode.trim().toUpperCase() != store) {
      return null;
    }
    if (staffId.trim().isEmpty || !{'waiter', 'cook'}.contains(role)) {
      return null;
    }

    for (final staff in staffCache) {
      if (staff['is_active'] == false) continue;
      final rowStore = staff['store_code']?.toString().trim();
      if (rowStore != null &&
          rowStore.isNotEmpty &&
          rowStore.toUpperCase() != store) {
        continue;
      }
      if (staff['staff_id']?.toString().trim() != staffId.trim()) continue;
      if (staff['role']?.toString() != role) continue;
      if ((staff['pin']?.toString().trim() ?? '').isEmpty) continue;
      return Map<String, dynamic>.from(staff);
    }
    return null;
  }

  static bool canHandleMessage({
    required String role,
    required String staffId,
    required Map<String, dynamic> message,
  }) {
    switch (message['type']) {
      case 'GET_MENU':
        return role == 'waiter';
      case 'NEW_KOT':
        return role == 'waiter' &&
            message['waiter_id']?.toString() == staffId;
      case 'BILL_READY':
        return role == 'waiter' &&
            message['staff_id']?.toString() == staffId;
      case 'ORDER_READY':
      case 'RATION_DEMAND':
        return role == 'cook' &&
            message['staff_id']?.toString() == staffId;
      default:
        return false;
    }
  }

  /// Used by the short-lived login check. Persistent waiter/cook sockets use
  /// the same AUTH_HELLO / AUTH_CHALLENGE / AUTH_PROOF sequence and keep their
  /// message subscription alive after AUTH_RESULT.
  static Future<bool> authenticateSocket({
    required Socket socket,
    required String storeCode,
    required String role,
    required String staffId,
    required String pin,
    void Function(Map<String, dynamic> result)? onAuthResult,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final completer = Completer<bool>();
    final subscription = decodeJsonLines(socket).listen(
      (message) {
        if (message['type'] == 'AUTH_CHALLENGE') {
          try {
            final nonce = message['nonce']?.toString() ?? '';
            final proof = createProof(pin: pin, nonce: nonce);
            socket.write(
              jsonEncode({'type': 'AUTH_PROOF', 'proof': proof}) + '\n',
            );
            unawaited(socket.flush());
          } catch (_) {
            if (!completer.isCompleted) completer.complete(false);
          }
        } else if (message['type'] == 'AUTH_RESULT') {
          onAuthResult?.call(message);
          if (!completer.isCompleted) {
            completer.complete(message['success'] == true);
          }
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(false);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    try {
      socket.write(
        jsonEncode({
              'type': 'AUTH_HELLO',
              'store_code': storeCode,
              'role': role,
              'staff_id': staffId,
            }) +
            '\n',
      );
      await socket.flush();
      return await completer.future.timeout(
        timeout,
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    } finally {
      await subscription.cancel();
    }
  }
}

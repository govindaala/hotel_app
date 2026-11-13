import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/lan_client_authorization.dart';

void main() {
  group('LanClientAuthorization challenge response', () {
    final nonce = base64UrlEncode(List<int>.generate(32, (index) => index));

    test('creates a proof accepted only for the matching PIN', () {
      final proof = LanClientAuthorization.createProof(
        pin: '4821',
        nonce: nonce,
      );

      expect(
        LanClientAuthorization.verifyProof(
          pin: '4821',
          nonce: nonce,
          proof: proof,
        ),
        isTrue,
      );
      expect(
        LanClientAuthorization.verifyProof(
          pin: '4822',
          nonce: nonce,
          proof: proof,
        ),
        isFalse,
      );
    });

    test('rejects malformed or tampered proof data', () {
      expect(
        LanClientAuthorization.verifyProof(
          pin: '4821',
          nonce: 'not-a-valid-nonce',
          proof: 'invalid',
        ),
        isFalse,
      );
      expect(
        LanClientAuthorization.verifyProof(
          pin: '4821',
          nonce: nonce,
          proof: 'dGFtcGVyZWQ=',
        ),
        isFalse,
      );
    });
  });

  group('LanClientAuthorization staff and role checks', () {
    final staff = <Map<String, dynamic>>[
      {
        'store_code': 'STORE-1',
        'staff_id': 'W1',
        'role': 'waiter',
        'pin': '4821',
        'is_active': true,
      },
      {
        'store_code': 'STORE-1',
        'staff_id': 'C1',
        'role': 'cook',
        'pin': '5912',
        'is_active': true,
      },
      {
        'store_code': 'STORE-1',
        'staff_id': 'W2',
        'role': 'waiter',
        'pin': '0000',
        'is_active': false,
      },
    ];

    test('matches active staff only within the requested store and role', () {
      expect(
        LanClientAuthorization.findStaff(
          expectedStoreCode: 'STORE-1',
          requestedStoreCode: ' store-1 ',
          role: 'waiter',
          staffId: 'W1',
          staffCache: staff,
        ),
        isNotNull,
      );
      expect(
        LanClientAuthorization.findStaff(
          expectedStoreCode: 'STORE-1',
          requestedStoreCode: 'STORE-2',
          role: 'waiter',
          staffId: 'W1',
          staffCache: staff,
        ),
        isNull,
      );
      expect(
        LanClientAuthorization.findStaff(
          expectedStoreCode: 'STORE-1',
          requestedStoreCode: 'STORE-1',
          role: 'waiter',
          staffId: 'W2',
          staffCache: staff,
        ),
        isNull,
      );
      expect(
        LanClientAuthorization.findStaff(
          expectedStoreCode: 'STORE-1',
          requestedStoreCode: 'STORE-1',
          role: 'owner',
          staffId: 'W1',
          staffCache: staff,
        ),
        isNull,
      );
    });

    test('waiter and cook commands are role- and identity-scoped', () {
      expect(
        LanClientAuthorization.canHandleMessage(
          role: 'waiter',
          staffId: 'W1',
          message: {'type': 'NEW_KOT', 'waiter_id': 'W1'},
        ),
        isTrue,
      );
      expect(
        LanClientAuthorization.canHandleMessage(
          role: 'waiter',
          staffId: 'W1',
          message: {'type': 'NEW_KOT', 'waiter_id': 'W2'},
        ),
        isFalse,
      );
      expect(
        LanClientAuthorization.canHandleMessage(
          role: 'waiter',
          staffId: 'W1',
          message: {'type': 'ORDER_READY', 'staff_id': 'W1'},
        ),
        isFalse,
      );
      expect(
        LanClientAuthorization.canHandleMessage(
          role: 'cook',
          staffId: 'C1',
          message: {'type': 'ORDER_READY', 'staff_id': 'C1'},
        ),
        isTrue,
      );
      expect(
        LanClientAuthorization.canHandleMessage(
          role: 'cook',
          staffId: 'C1',
          message: {'type': 'RATION_DEMAND', 'staff_id': 'C1'},
        ),
        isTrue,
      );
      expect(
        LanClientAuthorization.canHandleMessage(
          role: 'cook',
          staffId: 'C1',
          message: {'type': 'GET_MENU'},
        ),
        isFalse,
      );
    });
  });
}

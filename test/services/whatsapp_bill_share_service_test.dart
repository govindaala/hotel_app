import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/whatsapp_bill_share_service.dart';

void main() {
  group('WhatsAppBillShareService.normalizeIndianPhone', () {
    test('adds India country code to a ten-digit number', () {
      expect(
        WhatsAppBillShareService.normalizeIndianPhone('98765 43210'),
        '919876543210',
      );
    });

    test('preserves a valid number already prefixed with 91', () {
      expect(
        WhatsAppBillShareService.normalizeIndianPhone('+91-98765-43210'),
        '919876543210',
      );
    });

    test('rejects unsupported phone number lengths', () {
      expect(
        () => WhatsAppBillShareService.normalizeIndianPhone('12345'),
        throwsFormatException,
      );
    });

    test('rejects a twelve-digit number without the India prefix', () {
      expect(
        () => WhatsAppBillShareService.normalizeIndianPhone('001234567890'),
        throwsFormatException,
      );
    });
  });
}

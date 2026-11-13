import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/report_request_validation.dart';

void main() {
  group('ReportRequestValidation', () {
    test('trims and accepts a valid store code', () {
      expect(ReportRequestValidation.normalizeStoreCode('  HOTEL_12-A  '), 'HOTEL_12-A');
    });

    test('rejects store codes that can alter a PostgREST filter', () {
      expect(() => ReportRequestValidation.normalizeStoreCode('A,store_code.neq.B'),
          throwsArgumentError);
      expect(() => ReportRequestValidation.normalizeStoreCode(''), throwsArgumentError);
      expect(() => ReportRequestValidation.normalizeStoreCode(List.filled(65, 'A').join()), throwsArgumentError);
    });

    test('accepts a valid exclusive end date', () {
      expect(
        () => ReportRequestValidation.validateDateRange(
          DateTime(2026, 11, 1), DateTime(2026, 11, 2)),
        returnsNormally,
      );
    });

    test('rejects empty or reversed date ranges', () {
      expect(
        () => ReportRequestValidation.validateDateRange(
          DateTime(2026, 11, 2), DateTime(2026, 11, 2)),
        throwsArgumentError,
      );
      expect(
        () => ReportRequestValidation.validateDateRange(
          DateTime(2026, 11, 3), DateTime(2026, 11, 2)),
        throwsArgumentError,
      );
    });
  });
}

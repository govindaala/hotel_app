/// Validates identifiers and ranges before they are interpolated into PostgREST filters.
class ReportRequestValidation {
  ReportRequestValidation._();

  static String normalizeStoreCode(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'storeCode',
          'स्टोर कोड में केवल अक्षर, अंक, हाइफ़न और अंडरस्कोर हो सकते हैं।');
    }
    return normalized;
  }

  static void validateDateRange(DateTime start, DateTime endExclusive) {
    if (!endExclusive.isAfter(start)) {
      throw ArgumentError('रिपोर्ट की अंतिम तारीख, प्रारंभिक तारीख के बाद होनी चाहिए।');
    }
  }
}

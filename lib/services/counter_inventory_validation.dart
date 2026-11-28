/// Returns selected inventory IDs that are absent from a successful server snapshot.
///
/// IDs are compared by their string form because cart identifiers may be numeric
/// while the Supabase response is keyed by string IDs.
List<String> missingCounterInventoryIds({
  required Iterable<Object?> requestedIds,
  required Iterable<Object?> availableIds,
}) {
  final available = <String>{};
  for (final id in availableIds) {
    if (id != null) available.add(id.toString());
  }

  final missing = <String>{};
  for (final id in requestedIds) {
    if (id == null) continue;
    final normalizedId = id.toString();
    if (!available.contains(normalizedId)) missing.add(normalizedId);
  }

  return missing.toList()..sort();
}
/// Builds a safe PostgREST filter for shared catalogue rows and one store's stock.
///
/// Store codes are restricted to the same identifier alphabet used by the
/// inventory loader so they cannot inject additional PostgREST filter clauses.
String counterInventoryScopeFilter(String storeCode) {
  final normalized = storeCode.trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      storeCode,
      'storeCode',
      'Expected 1–64 letters, digits, underscores or hyphens.',
    );
  }
  return 'restaurant_id.is.null,restaurant_id.eq.$normalized';
}

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

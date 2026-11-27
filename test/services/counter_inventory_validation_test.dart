import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/counter_inventory_validation.dart';

void main() {
  group('missingCounterInventoryIds', () {
    test('returns cart item IDs absent from a successful server snapshot', () {
      expect(
        missingCounterInventoryIds(
          requestedIds: ['removed-item', 'active-item'],
          availableIds: ['active-item'],
        ),
        ['removed-item'],
      );
    });

    test('matches numeric IDs when the server returns their string form', () {
      expect(
        missingCounterInventoryIds(
          requestedIds: [42],
          availableIds: ['42'],
        ),
        isEmpty,
      );
    });

    test('deduplicates missing IDs and ignores null identifiers', () {
      expect(
        missingCounterInventoryIds(
          requestedIds: [null, 'missing', 'missing', 42],
          availableIds: [null, 42],
        ),
        ['missing'],
      );
    });

    test('returns no missing IDs when every selected item is present', () {
      expect(
        missingCounterInventoryIds(
          requestedIds: ['item-a', 'item-b'],
          availableIds: ['item-a', 'item-b'],
        ),
        isEmpty,
      );
    });
  });
}

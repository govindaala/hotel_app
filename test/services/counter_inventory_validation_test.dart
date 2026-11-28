import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/counter_inventory_validation.dart';

void main() {
  group('counterInventoryScopeFilter', () {
    test('trims a valid store code and includes only shared and matching rows', () {
      expect(
        counterInventoryScopeFilter('  Garoth_01-2  '),
        'restaurant_id.is.null,restaurant_id.eq.Garoth_01-2',
      );
    });

    test('rejects an empty store code', () {
      expect(() => counterInventoryScopeFilter('  '), throwsArgumentError);
    });

    test('rejects PostgREST filter syntax in a store code', () {
      expect(
        () => counterInventoryScopeFilter('store-a,restaurant_id.eq.store-b'),
        throwsArgumentError,
      );
    });

    test('rejects store codes longer than 64 characters', () {
      expect(
        () => counterInventoryScopeFilter('a' * 65),
        throwsArgumentError,
      );
    });
  });

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

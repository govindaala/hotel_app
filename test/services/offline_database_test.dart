import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/offline_database.dart';

void main() {
  group('inventoryUpdateQueueId', () {
    test('is stable for the same store and inventory item', () {
      expect(
        inventoryUpdateQueueId('STORE-1', 'shared-item-42'),
        'inventory:STORE-1:shared-item-42',
      );
    });

    test('does not collide when stores share the same catalogue item ID', () {
      final firstStore = inventoryUpdateQueueId('STORE-1', 'shared-item-42');
      final secondStore = inventoryUpdateQueueId('STORE-2', 'shared-item-42');

      expect(firstStore, isNot(secondStore));
    });

    test('normalizes surrounding whitespace and accepts numeric item IDs', () {
      expect(
        inventoryUpdateQueueId(' STORE-1 ', 42),
        'inventory:STORE-1:42',
      );
    });

    test('rejects empty store or item identifiers', () {
      expect(() => inventoryUpdateQueueId(' ', '42'), throwsArgumentError);
      expect(() => inventoryUpdateQueueId('STORE-1', ' '), throwsArgumentError);
    });
  });

  group('OfflineDatabase.createId', () {
    test('creates UUID v4 shaped identifiers', () {
      final id = OfflineDatabase.instance.createId();

      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('creates distinct identifiers for separate operations', () {
      final first = OfflineDatabase.instance.createId();
      final second = OfflineDatabase.instance.createId();

      expect(first, isNot(second));
    });
  });
}

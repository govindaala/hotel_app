import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotel_pos/services/line_json_protocol.dart';

void main() {
  group('decodeJsonLines', () {
    test('reassembles split TCP frames and preserves multiple messages', () async {
      final controller = StreamController<List<int>>();
      final decoded = decodeJsonLines(controller.stream).toList();

      controller.add(utf8.encode('{"type":"NEW_'));
      controller.add(utf8.encode('KOT","table":4}\n{"type":"ORDER_READY","table":4}\n'));
      await controller.close();

      expect(await decoded, [
        {'type': 'NEW_KOT', 'table': 4},
        {'type': 'ORDER_READY', 'table': 4},
      ]);
    });

    test('buffers UTF-8 when a code point is split between TCP chunks', () async {
      final controller = StreamController<List<int>>();
      final decoded = decodeJsonLines(controller.stream).toList();
      final prefix = utf8.encode('{"name":"');
      final hindi = utf8.encode('टेबल');

      controller.add([...prefix, ...hindi.take(2)]);
      controller.add([...hindi.skip(2), ...utf8.encode('"}\n')]);
      await controller.close();

      expect(await decoded, [
        {'name': 'टेबल'},
      ]);
    });

    test('skips blank and malformed frames without losing the next valid frame', () async {
      final input = Stream<List<int>>.fromIterable([
        utf8.encode('\nnot-json\n'),
        utf8.encode('{"type":"BILL_READY","table":4}\n'),
      ]);

      expect(await decodeJsonLines(input).toList(), [
        {'type': 'BILL_READY', 'table': 4},
      ]);
    });
  });
}

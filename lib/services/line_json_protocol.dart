import 'dart:async';
import 'dart:convert';

/// Decodes newline-delimited JSON from a TCP byte stream.
///
/// TCP packet boundaries are not message boundaries. This keeps partial UTF-8
/// and JSON frames buffered until a newline terminates the message.
Stream<Map<String, dynamic>> decodeJsonLines(Stream<List<int>> input) async* {
  await for (final line in input.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;

    try {
      final decoded = jsonDecode(line);
      if (decoded is Map) {
        yield Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      // Skip a malformed frame without dropping later complete messages.
    }
  }
}

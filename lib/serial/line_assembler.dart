import 'dart:convert';

/// Turns a stream of byte chunks into complete text lines.
///
/// Splitting happens on the raw `\n` byte before decoding, so a multi-byte
/// UTF-8 character that straddles two chunks is still decoded correctly.
class LineAssembler {
  LineAssembler({this.maxLineBytes = 8192});

  /// A line longer than this is emitted in pieces rather than buffered forever.
  final int maxLineBytes;

  final List<int> _pending = <int>[];

  bool get hasPartial => _pending.isNotEmpty;

  /// Adds received bytes and returns the lines they completed.
  List<String> add(List<int> bytes) {
    final lines = <String>[];
    for (final b in bytes) {
      if (b == 0x0A) {
        lines.add(_take());
      } else {
        _pending.add(b);
        if (_pending.length >= maxLineBytes) lines.add(_take());
      }
    }
    return lines;
  }

  /// Returns the unterminated text received so far (e.g. a prompt), or null.
  String? flush() => _pending.isEmpty ? null : _take();

  void reset() => _pending.clear();

  String _take() {
    var end = _pending.length;
    if (end > 0 && _pending[end - 1] == 0x0D) end--;
    final text = utf8.decode(_pending.sublist(0, end), allowMalformed: true);
    _pending.clear();
    return text;
  }
}

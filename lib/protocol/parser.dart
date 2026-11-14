/// Line parsing for SMP v1 (see docs/PROTOCOL.md) plus the common ESP32 log
/// formats. Pure Dart: no Flutter imports, so it is unit-testable on its own.
library;

enum Level { none, verbose, debug, info, warn, error }

Level levelFromChar(String? c) {
  switch (c) {
    case 'E':
      return Level.error;
    case 'W':
      return Level.warn;
    case 'I':
      return Level.info;
    case 'D':
      return Level.debug;
    case 'V':
      return Level.verbose;
    default:
      return Level.none;
  }
}

enum LineKind { smp, espIdf, arduinoLog, plain }

/// A number found in a line, with the name it will be graphed under.
class NumField {
  const NumField(this.name, this.value, [this.unit = '']);
  final String name;
  final double value;
  final String unit;

  @override
  String toString() => '$name=$value$unit';
}

class ParsedLine {
  const ParsedLine({
    required this.raw,
    required this.kind,
    required this.tag,
    required this.level,
    required this.body,
    required this.groupKey,
    required this.numbers,
  });

  /// The line with ANSI codes and trailing whitespace removed.
  final String raw;
  final LineKind kind;

  /// Label shown in front of the row; null for plain lines.
  final String? tag;
  final Level level;

  /// Text after the tag / log prefix (the whole line for plain lines).
  final String body;

  /// Lines with the same key are "the same kind of message" and share a row.
  final String groupKey;
  final List<NumField> numbers;

  /// SMP protocol lines such as `[!hello]` and `[!cmd]`.
  bool get isMeta => kind == LineKind.smp && tag != null && tag!.startsWith('!');
}

final RegExp _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

// [tag] body   or   [tag:L] body
final RegExp _smp = RegExp(r'^\[([A-Za-z!][A-Za-z0-9_.\-/]{0,31})(?::([EWIDV]))?\]\s?(.*)$');

// arduino-esp32:  [  1234][W][main.cpp:42] loop(): body
final RegExp _arduino = RegExp(r'^\[\s*\d+\]\[([EWIDV])\]\[([^\]:]+):(\d+)\]\s?(.*)$');

// ESP-IDF:  I (1234) wifi: body
final RegExp _idf = RegExp(r'^([EWIDV]) \((\d+)\) ([^:]{1,48}): (.*)$');

// MAC addresses / clock times (aa:bb:cc...), dotted addresses and versions
// (10.0.0.5) and long hex blobs. These vary from line to line but are not
// values anyone wants to graph.
final RegExp _blob = RegExp(
  r'\b(?:[0-9A-Fa-f]{2}[:\-]){2,}[0-9A-Fa-f]{2}\b'
  r'|\b\d{1,3}(?:\.\d{1,3}){2,}\b'
  r'|\b(?=[0-9A-Fa-f]*\d)(?=[0-9A-Fa-f]*[A-Fa-f])[0-9A-Fa-f]{6,}\b',
);

// A number that is not glued to the end of a word (so "ESP32" and "v1.2" stay text).
final RegExp _number = RegExp(
  r'(?<![A-Za-z0-9_.])(?:0[xX][0-9a-fA-F]+|[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)',
);

// "name=" or "name:" directly before a number.
final RegExp _label = RegExp(r'([A-Za-z_][A-Za-z0-9_.]*)\s*[:=]\s*$');

// Unit attached to a number: 23.5C, 41%, 120ms.
final RegExp _unit = RegExp(r'[A-Za-z%°µ]{1,6}(?![A-Za-z0-9_])');

final RegExp _keyValue = RegExp(r'([A-Za-z_][A-Za-z0-9_.]*)=("(?:[^"\\]|\\.)*"|\S*)');

const int _maxNumbersPerLine = 16;

/// Removes ANSI escapes, NULs and trailing whitespace.
String cleanLine(String input) => input.replaceAll(_ansi, '').replaceAll('\u0000', '').trimRight();

/// The line with every number replaced by `#`: its "shape".
String signatureOf(String text) => text.replaceAll(_blob, '#').replaceAll(_number, '#');

/// Finds graphable numbers. Named by a preceding `name=` / `name:`, otherwise
/// by position (`#1`, `#2`, …).
List<NumField> extractNumbers(String body) {
  // Mask blobs with same-length filler so match offsets still line up.
  final masked = body.replaceAllMapped(_blob, (m) => '~' * (m.end - m.start));
  final out = <NumField>[];
  final used = <String, int>{};
  var index = 0;
  for (final m in _number.allMatches(masked)) {
    index++;
    final text = m.group(0)!;
    final double? value = (text.startsWith('0x') || text.startsWith('0X'))
        ? int.tryParse(text.substring(2), radix: 16)?.toDouble()
        : double.tryParse(text);
    if (value == null || !value.isFinite) continue;
    final label = _label.firstMatch(masked.substring(0, m.start))?.group(1);
    final unit = _unit.matchAsPrefix(masked, m.end)?.group(0) ?? '';
    var name = label ?? '#$index';
    final seen = (used[name] ?? 0) + 1;
    used[name] = seen;
    if (seen > 1) name = '$name#$seen';
    out.add(NumField(name, value, unit));
    if (out.length >= _maxNumbersPerLine) break;
  }
  return out;
}

/// Parses `key=value key2="quoted value"` pairs (used for meta lines).
Map<String, String> parseKeyValues(String body) {
  final out = <String, String>{};
  for (final m in _keyValue.allMatches(body)) {
    var value = m.group(2)!;
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    out[m.group(1)!] = value;
  }
  return out;
}

/// Returns null for blank lines.
ParsedLine? parseLine(String input) {
  final raw = cleanLine(input);
  if (raw.trim().isEmpty) return null;

  final a = _arduino.firstMatch(raw);
  if (a != null) {
    final tag = '${a.group(2)}:${a.group(3)}';
    final body = a.group(4)!;
    return ParsedLine(
      raw: raw,
      kind: LineKind.arduinoLog,
      tag: tag,
      level: levelFromChar(a.group(1)),
      body: body,
      groupKey: 'a:$tag',
      numbers: extractNumbers(body),
    );
  }

  final s = _smp.firstMatch(raw);
  if (s != null) {
    final tag = s.group(1)!;
    final body = s.group(3)!;
    final isMeta = tag.startsWith('!');
    return ParsedLine(
      raw: raw,
      kind: LineKind.smp,
      tag: tag,
      level: tag == '!err' ? Level.error : levelFromChar(s.group(2)),
      body: body,
      groupKey: 't:$tag',
      numbers: isMeta ? const [] : extractNumbers(body),
    );
  }

  final i = _idf.firstMatch(raw);
  if (i != null) {
    final tag = i.group(3)!;
    final body = i.group(4)!;
    return ParsedLine(
      raw: raw,
      kind: LineKind.espIdf,
      tag: tag,
      level: levelFromChar(i.group(1)),
      body: body,
      groupKey: 'i:$tag:${signatureOf(body)}',
      numbers: extractNumbers(body),
    );
  }

  return ParsedLine(
    raw: raw,
    kind: LineKind.plain,
    tag: null,
    level: Level.none,
    body: raw,
    groupKey: 'p:${signatureOf(raw)}',
    numbers: extractNumbers(raw),
  );
}

final RegExp _romBoot = RegExp(r'rst:0x[0-9a-fA-F]+ \(|^ESP-ROM:');

/// True for the ESP32 ROM bootloader banner printed after a reset.
bool isRomBootLine(String raw) => _romBoot.hasMatch(raw);

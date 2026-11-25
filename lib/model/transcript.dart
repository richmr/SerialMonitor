import 'dart:collection';
import 'dart:io';

/// Which way a transcript line travelled.
enum Direction { received, sent }

class TranscriptLine {
  const TranscriptLine(this.time, this.direction, this.text);
  final DateTime time;
  final Direction direction;
  final String text;
}

/// The serial stream in arrival order, as it came off the wire (before
/// grouping), so it can be saved to a file. Keeps the most recent
/// [maxLines] in memory, and can also stream every line to a file as it
/// arrives for captures longer than that.
class Transcript {
  Transcript({this.maxLines = 200000});

  final int maxLines;
  final ListQueue<TranscriptLine> _lines = ListQueue<TranscriptLine>();

  IOSink? _sink;
  String? recordingPath;
  int recordedLines = 0;

  /// Lines dropped from memory because [maxLines] was reached.
  int droppedLines = 0;

  int get length => _lines.length;
  Iterable<TranscriptLine> get lines => _lines;
  bool get isRecording => _sink != null;

  void add(TranscriptLine line) {
    _lines.addLast(line);
    while (_lines.length > maxLines) {
      _lines.removeFirst();
      droppedLines++;
    }
    final sink = _sink;
    if (sink != null) {
      sink.writeln(format(line));
      recordedLines++;
    }
  }

  void clear() {
    _lines.clear();
    droppedLines = 0;
  }

  /// One line of a saved file: `14:03:27.512  [env] temp=23.5C`, with sent
  /// commands marked `>`.
  static String format(TranscriptLine line, {bool timestamps = true}) {
    final arrow = line.direction == Direction.sent ? '> ' : '';
    if (!timestamps) return '$arrow${line.text}';
    return '${_stamp(line.time)}  $arrow${line.text}';
  }

  /// Everything in memory, ready to write to a file.
  String export({bool timestamps = true, bool includeSent = true}) {
    final out = StringBuffer();
    for (final l in _lines) {
      if (!includeSent && l.direction == Direction.sent) continue;
      out.writeln(format(l, timestamps: timestamps));
    }
    return out.toString();
  }

  /// Starts appending every new line to [path]. Stops any earlier recording.
  Future<void> startRecording(String path) async {
    await stopRecording();
    final file = File(path);
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    recordingPath = path;
    recordedLines = 0;
  }

  Future<void> stopRecording() async {
    final sink = _sink;
    _sink = null;
    recordingPath = null;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _stamp(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
}

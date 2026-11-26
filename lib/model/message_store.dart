import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../protocol/parser.dart';

class LogEntry {
  const LogEntry(this.time, this.text, this.level);
  final DateTime time;
  final String text;
  final Level level;
}

class SeriesPoint {
  const SeriesPoint(this.time, this.value);
  final DateTime time;
  final double value;
}

/// A bounded, time-ordered ring of (time, value) pairs, stored compactly
/// (16 bytes a point) so long histories stay cheap. Oldest points are
/// dropped once [capacity] is reached. Times are microseconds since epoch.
class PointBuffer extends Iterable<SeriesPoint> {
  PointBuffer(this.capacity) : assert(capacity > 0) {
    final initial = capacity < 64 ? capacity : 64;
    _t = Int64List(initial);
    _v = Float64List(initial);
  }

  final int capacity;
  late Int64List _t;
  late Float64List _v;
  int _start = 0;
  int _len = 0;

  @override
  int get length => _len;

  @override
  bool get isEmpty => _len == 0;

  @override
  bool get isNotEmpty => _len != 0;

  int _slot(int i) {
    final j = _start + i;
    return j < _t.length ? j : j - _t.length;
  }

  int timeAt(int i) => _t[_slot(i)];
  double valueAt(int i) => _v[_slot(i)];

  void add(int micros, double value) {
    if (_len == _t.length && _t.length < capacity) _grow();
    if (_len < _t.length) {
      final j = _slot(_len);
      _t[j] = micros;
      _v[j] = value;
      _len++;
    } else {
      // Full: overwrite the oldest.
      _t[_start] = micros;
      _v[_start] = value;
      _start = _start + 1 == _t.length ? 0 : _start + 1;
    }
  }

  void _grow() {
    final size = (_t.length * 2).clamp(1, capacity);
    final t = Int64List(size);
    final v = Float64List(size);
    for (var i = 0; i < _len; i++) {
      final j = _slot(i);
      t[i] = _t[j];
      v[i] = _v[j];
    }
    _t = t;
    _v = v;
    _start = 0;
  }

  /// Index of the first point at or after [micros] ([length] if none).
  int lowerBound(int micros) {
    var lo = 0;
    var hi = _len;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (timeAt(mid) < micros) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  SeriesPoint elementAt(int index) {
    RangeError.checkValidIndex(index, this);
    return SeriesPoint(DateTime.fromMicrosecondsSinceEpoch(timeAt(index)), valueAt(index));
  }

  @override
  SeriesPoint get first => elementAt(0);

  @override
  SeriesPoint get last => elementAt(_len - 1);

  /// The newest [count] points (fewer if there are not that many).
  List<SeriesPoint> tail(int count) {
    final from = _len > count ? _len - count : 0;
    return <SeriesPoint>[for (var i = from; i < _len; i++) elementAt(i)];
  }

  @override
  Iterator<SeriesPoint> get iterator => Iterable<SeriesPoint>.generate(_len, elementAt).iterator;
}

/// The history of one numeric value inside a message group.
class Series {
  Series(this.name, {int capacity = 50000}) : points = PointBuffer(capacity);
  final String name;
  String unit = '';
  final PointBuffer points;

  double? get last => points.isEmpty ? null : points.valueAt(points.length - 1);
}

/// Where a group's lines come from.
enum GroupKind { device, sent, monitor }

/// One row of the aggregate view: every arrival of one kind of message.
class MessageGroup {
  MessageGroup({required this.key, required this.tag, required this.kind, required this.firstSeen})
      : lastSeen = firstSeen;

  final String key;
  final String? tag;
  final GroupKind kind;
  final DateTime firstSeen;
  DateTime lastSeen;
  Level level = Level.none;

  /// Latest text.
  String text = '';

  /// Total arrivals.
  int count = 0;

  /// How many arrivals in a row have had exactly the current text.
  int repeat = 0;

  final ListQueue<LogEntry> log = ListQueue<LogEntry>();
  final Map<String, Series> series = <String, Series>{};
}

/// Groups incoming lines by kind and keeps a bounded history of each.
class MessageStore extends ChangeNotifier {
  MessageStore({
    this.maxLogPerGroup = 2000,
    this.maxPointsPerSeries = 50000,
    this.maxGroups = 500,
    this.notifyInterval = const Duration(milliseconds: 33),
  });

  final int maxLogPerGroup;
  final int maxPointsPerSeries;
  final int maxGroups;

  /// Listener notifications are batched to at most one per interval, so a
  /// chatty device cannot trigger thousands of repaints per second.
  /// [Duration.zero] notifies immediately (used in tests).
  final Duration notifyInterval;

  static const String overflowKey = '~overflow';

  final Map<String, MessageGroup> _groups = <String, MessageGroup>{};
  Timer? _notifyTimer;

  int totalLines = 0;
  int bootCount = 0;

  /// When the device was last seen restarting. Groups not updated since are stale.
  DateTime? lastBoot;

  /// Rows in first-seen order, so they never move once they appear.
  Iterable<MessageGroup> get groups => _groups.values;
  int get groupCount => _groups.length;
  MessageGroup? group(String? key) => key == null ? null : _groups[key];

  bool isStale(MessageGroup g) {
    final boot = lastBoot;
    return boot != null && g.kind == GroupKind.device && g.lastSeen.isBefore(boot);
  }

  /// Records a parsed device line.
  MessageGroup addLine(ParsedLine line, DateTime time) {
    totalLines++;
    return record(
      key: line.groupKey,
      tag: line.tag,
      text: line.kind == LineKind.plain ? line.raw : line.body,
      level: line.level,
      numbers: line.numbers,
      time: time,
    );
  }

  MessageGroup record({
    required String key,
    required String? tag,
    required String text,
    required DateTime time,
    Level level = Level.none,
    List<NumField> numbers = const <NumField>[],
    GroupKind kind = GroupKind.device,
  }) {
    if (!_groups.containsKey(key) && kind == GroupKind.device && _groups.length >= maxGroups) {
      // Too many distinct shapes (usually noise at the wrong baud rate):
      // collect the rest in one row instead of growing without bound.
      key = overflowKey;
      tag = 'other';
      numbers = const <NumField>[];
    }
    final MessageGroup group = _groups.putIfAbsent(
      key,
      () => MessageGroup(key: key, tag: tag, kind: kind, firstSeen: time),
    );

    group.repeat = (group.count > 0 && group.text == text) ? group.repeat + 1 : 1;
    group.count++;
    group.text = text;
    group.level = level;
    group.lastSeen = time;

    group.log.addLast(LogEntry(time, text, level));
    while (group.log.length > maxLogPerGroup) {
      group.log.removeFirst();
    }

    for (final n in numbers) {
      final s = group.series.putIfAbsent(n.name, () => Series(n.name, capacity: maxPointsPerSeries));
      if (n.unit.isNotEmpty) s.unit = n.unit;
      s.points.add(time.microsecondsSinceEpoch, n.value);
    }

    _scheduleNotify();
    return group;
  }

  /// Notes a device restart. Restarts reported within [debounce] of the
  /// previous one are the same boot (ROM banner, then `[!hello]`).
  bool markBoot(DateTime time, {Duration debounce = const Duration(seconds: 3)}) {
    final last = lastBoot;
    if (last != null && time.difference(last) < debounce) return false;
    lastBoot = time;
    bootCount++;
    _scheduleNotify();
    return true;
  }

  /// Removes one row. It comes back (at the bottom) if that kind of message
  /// arrives again. Returns false if there was no such row.
  bool remove(String key) {
    final removed = _groups.remove(key) != null;
    if (removed) _scheduleNotify();
    return removed;
  }

  /// Removes device rows. Sent-command and monitor rows are kept unless [all].
  void clear({bool all = false}) {
    if (all) {
      _groups.clear();
    } else {
      _groups.removeWhere((_, g) => g.kind == GroupKind.device);
    }
    totalLines = 0;
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (notifyInterval == Duration.zero) {
      notifyListeners();
      return;
    }
    _notifyTimer ??= Timer(notifyInterval, () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    super.dispose();
  }
}

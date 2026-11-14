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

/// The history of one numeric value inside a message group.
class Series {
  Series(this.name);
  final String name;
  String unit = '';
  final ListQueue<SeriesPoint> points = ListQueue<SeriesPoint>();

  double? get last => points.isEmpty ? null : points.last.value;
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
    this.maxPointsPerSeries = 2000,
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
      final s = group.series.putIfAbsent(n.name, () => Series(n.name));
      if (n.unit.isNotEmpty) s.unit = n.unit;
      s.points.addLast(SeriesPoint(time, n.value));
      while (s.points.length > maxPointsPerSeries) {
        s.points.removeFirst();
      }
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

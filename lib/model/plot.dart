import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// Which y-scale a trace is drawn against.
enum PlotAxis { left, right }

/// One value drawn in the plot window: a named value of one message row.
class PlotTrace {
  PlotTrace({
    required this.groupKey,
    required this.seriesName,
    required this.label,
    required this.colorSlot,
    this.axis = PlotAxis.left,
    this.visible = true,
  });

  /// The row ([MessageGroup.key]) and value ([Series.name]) it follows. The
  /// data is looked up from the store each frame, so a trace survives the
  /// row being cleared and picks up again when the message returns.
  final String groupKey;
  final String seriesName;

  /// `tag.value`, e.g. `env.temp`.
  final String label;

  /// Index into the trace palette. Stays with the trace for its lifetime.
  final int colorSlot;
  PlotAxis axis;
  bool visible;

  bool matches(String group, String series) => groupKey == group && seriesName == series;

  Map<String, Object?> toJson() => <String, Object?>{
        'group': groupKey,
        'series': seriesName,
        'label': label,
        'axis': axis.name,
        'visible': visible,
      };
}

/// A saved view, for "back to the previous view".
class PlotView {
  const PlotView({required this.live, required this.end, required this.span, required this.zoomed});
  final bool live;
  final DateTime? end;
  final Duration span;
  final bool zoomed;
}

/// State of the plot window: what is drawn and which slice of time is shown.
///
/// The view is a window of [viewSpan] ending at [viewEnd], or at "now" while
/// [live]. Scrolling, paging or zooming leaves live mode, so new data keeps
/// arriving without moving the view; [goLive] returns to following it.
class PlotModel extends ChangeNotifier {
  static const List<Duration> spans = <Duration>[
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 20),
  ];

  /// One color per trace, never reused while that trace is shown.
  static const int maxTraces = 8;

  final List<PlotTrace> traces = <PlotTrace>[];
  bool open = false;

  /// The selected preset window length.
  Duration span = const Duration(seconds: 30);

  /// Set by a drag-to-zoom; overrides [span] until a preset is picked or
  /// the view goes live again.
  Duration? _zoomSpan;

  bool live = true;
  DateTime? _end;

  final List<PlotView> _history = <PlotView>[];

  /// Where the floating panel sits, relative to the area it floats over.
  /// Null until placed (then it goes to the bottom left).
  Offset? position;
  Size size = const Size(760, 440);

  Duration get viewSpan => _zoomSpan ?? span;
  bool get zoomed => _zoomSpan != null;
  bool get canGoBack => _history.isNotEmpty;

  /// The right edge of the view.
  DateTime viewEnd(DateTime now) => live ? now : (_end ?? now);

  PlotTrace? find(String group, String series) {
    for (final t in traces) {
      if (t.matches(group, series)) return t;
    }
    return null;
  }

  int _freeSlot() {
    final used = <int>{for (final t in traces) t.colorSlot};
    for (var i = 0; i < maxTraces; i++) {
      if (!used.contains(i)) return i;
    }
    return -1;
  }

  /// Adds a trace (or returns the existing one). Null when the plot is full.
  PlotTrace? add(String group, String series, {required String label, PlotAxis axis = PlotAxis.left}) {
    final existing = find(group, series);
    if (existing != null) {
      if (!existing.visible) {
        existing.visible = true;
        notifyListeners();
      }
      return existing;
    }
    final slot = _freeSlot();
    if (slot < 0) return null;
    final trace = PlotTrace(groupKey: group, seriesName: series, label: label, colorSlot: slot, axis: axis);
    traces.add(trace);
    notifyListeners();
    return trace;
  }

  void remove(PlotTrace trace) {
    if (traces.remove(trace)) notifyListeners();
  }

  void setVisible(PlotTrace trace, bool visible) {
    trace.visible = visible;
    notifyListeners();
  }

  void setAxis(PlotTrace trace, PlotAxis axis) {
    trace.axis = axis;
    notifyListeners();
  }

  void setOpen(bool value) {
    if (open == value) return;
    open = value;
    notifyListeners();
  }

  void place(Offset position, Size size) {
    this.position = position;
    this.size = size;
    notifyListeners();
  }

  // ---- the time window ------------------------------------------------------

  PlotView _snapshot() => PlotView(live: live, end: _end, span: viewSpan, zoomed: zoomed);

  void _remember() {
    _history.add(_snapshot());
    if (_history.length > 50) _history.removeAt(0);
  }

  /// Picks a preset window length. Keeps the right edge where it is.
  void setSpan(Duration value, DateTime now) {
    if (value == span && !zoomed) return;
    _remember();
    if (!live) _end = viewEnd(now);
    span = value;
    _zoomSpan = null;
    notifyListeners();
  }

  /// Zooms in on [start]..[end] (a dragged band).
  void zoomTo(DateTime start, DateTime end) {
    if (!end.isAfter(start)) return;
    _remember();
    live = false;
    _end = end;
    _zoomSpan = end.difference(start);
    notifyListeners();
  }

  /// Moves the right edge of the view to [end]. Reaching "now" goes live.
  void scrollTo(DateTime end, DateTime now) {
    if (!end.isBefore(now)) {
      if (!live) {
        live = true;
        _end = null;
        notifyListeners();
      }
      return;
    }
    live = false;
    _end = end;
    notifyListeners();
  }

  /// Moves the view by [fraction] of its width (negative is back in time).
  void pan(double fraction, DateTime now) {
    final shift = Duration(microseconds: (viewSpan.inMicroseconds * fraction).round());
    scrollTo(viewEnd(now).add(shift), now);
  }

  /// Back to following the newest data at the preset window length.
  void goLive() {
    if (live && !zoomed) return;
    _remember();
    live = true;
    _end = null;
    _zoomSpan = null;
    notifyListeners();
  }

  /// Back to the view before the last zoom, preset change or "live".
  void goBack() {
    if (_history.isEmpty) return;
    final v = _history.removeLast();
    live = v.live;
    _end = v.end;
    if (v.zoomed) {
      _zoomSpan = v.span;
    } else {
      _zoomSpan = null;
      span = v.span;
    }
    notifyListeners();
  }

  // ---- saved settings -------------------------------------------------------

  Map<String, Object?> toJson() => <String, Object?>{
        'span': span.inMilliseconds,
        'open': open,
        'width': size.width,
        'height': size.height,
        'traces': <Map<String, Object?>>[for (final t in traces) t.toJson()],
      };

  /// Replaces the traces and window length with saved ones.
  void apply(Map<String, Object?> json) {
    traces.clear();
    _history.clear();
    _zoomSpan = null;
    live = true;
    _end = null;
    final ms = json['span'];
    if (ms is int) {
      final d = Duration(milliseconds: ms);
      if (spans.contains(d)) span = d;
    }
    final w = json['width'];
    final h = json['height'];
    if (w is num && h is num) size = Size(w.toDouble(), h.toDouble());
    final list = json['traces'];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final group = item['group'];
        final series = item['series'];
        if (group is! String || series is! String) continue;
        final label = item['label'] is String ? item['label'] as String : series;
        final axis = item['axis'] == 'right' ? PlotAxis.right : PlotAxis.left;
        final trace = add(group, series, label: label, axis: axis);
        if (trace != null && item['visible'] == false) trace.visible = false;
      }
    }
    open = json['open'] != false && traces.isNotEmpty;
    notifyListeners();
  }
}

/// Plot settings saved per device name, in one JSON file.
class PlotSettingsStore {
  PlotSettingsStore(this.file);

  final File file;

  /// `~/Library/Application Support/SerialMonitor` on macOS,
  /// `%APPDATA%\SerialMonitor` on Windows, `~/.config/serial_monitor` elsewhere.
  static PlotSettingsStore? defaultLocation() {
    final env = Platform.environment;
    String? dir;
    if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null) dir = '$home/Library/Application Support/SerialMonitor';
    } else if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null) dir = '$appData\\SerialMonitor';
    } else {
      final home = env['HOME'];
      if (home != null) dir = '$home/.config/serial_monitor';
    }
    if (dir == null) return null;
    return PlotSettingsStore(File('$dir${Platform.pathSeparator}plot_settings.json'));
  }

  Map<String, Object?> _readAll() {
    try {
      if (!file.existsSync()) return <String, Object?>{};
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Map<String, Object?>? load(String device) {
    final entry = _readAll()[device];
    return entry is Map<String, Object?> ? entry : null;
  }

  bool has(String device) => load(device) != null;

  void save(String device, Map<String, Object?> settings) {
    final all = _readAll()..[device] = settings;
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
  }
}

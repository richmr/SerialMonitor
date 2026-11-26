import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../model/message_store.dart';
import '../model/plot.dart';
import 'style.dart';

/// Trace colors for the dark surface, in fixed order: a trace keeps its
/// slot's color for as long as it is in the plot. Checked for color-vision
/// deficiency separation and contrast against [kBackground].
const List<Color> kTraceColors = <Color>[
  Color(0xFF338CED), // blue
  Color(0xFFE76624), // orange
  Color(0xFF00A888), // aqua
  Color(0xFFD28E05), // yellow
  Color(0xFFE24D8B), // magenta
  Color(0xFF0AAC23), // green
  Color(0xFF9887EF), // violet
  Color(0xFFEB6263), // red
];

Color traceColor(PlotTrace t) => kTraceColors[t.colorSlot % kTraceColors.length];

/// What the chart needs for one trace: the trace and its data (null while
/// the row has no data, e.g. after it was cleared).
class ChartTrace {
  const ChartTrace(this.trace, this.points, this.unit);
  final PlotTrace trace;
  final PointBuffer? points;
  final String unit;
}

/// Multi-trace time chart with an optional second y-scale.
///
/// Drag across it to zoom in on that stretch of time; scroll (wheel or
/// two-finger swipe) to move back and forth; hover for the values at a time.
class PlotChart extends StatefulWidget {
  const PlotChart({
    super.key,
    required this.traces,
    required this.start,
    required this.end,
    required this.onZoom,
    required this.onPan,
  });

  final List<ChartTrace> traces;
  final DateTime start;
  final DateTime end;
  final void Function(DateTime start, DateTime end) onZoom;

  /// Called with a fraction of the view width to move (negative = back).
  final ValueChanged<double> onPan;

  @override
  State<PlotChart> createState() => _PlotChartState();
}

class _PlotChartState extends State<PlotChart> {
  double? _hoverX;
  double? _dragFrom;
  double? _dragTo;

  bool get _hasRight => widget.traces.any((t) => t.trace.visible && t.trace.axis == PlotAxis.right);

  Rect _plotRect(Size size) => ChartGeometry.plotRect(size, hasRight: _hasRight);

  DateTime _timeAt(double x, Rect plot) {
    final s = widget.start.microsecondsSinceEpoch;
    final e = widget.end.microsecondsSinceEpoch;
    final f = ((x - plot.left) / plot.width).clamp(0.0, 1.0);
    return DateTime.fromMicrosecondsSinceEpoch(s + ((e - s) * f).round());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final plot = _plotRect(size);
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final d = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
              if (d != 0 && plot.width > 0) widget.onPan(d / plot.width);
            }
          },
          onPointerPanZoomUpdate: (event) {
            final d = -event.panDelta.dx;
            if (d != 0 && plot.width > 0) widget.onPan(d / plot.width);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (e) => setState(() => _hoverX = plot.contains(e.localPosition) ? e.localPosition.dx : null),
            onExit: (_) => setState(() => _hoverX = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => setState(() {
                _dragFrom = d.localPosition.dx.clamp(plot.left, plot.right);
                _dragTo = _dragFrom;
              }),
              onHorizontalDragUpdate: (d) => setState(() {
                _dragTo = d.localPosition.dx.clamp(plot.left, plot.right);
                _hoverX = null;
              }),
              onHorizontalDragEnd: (_) {
                final a = _dragFrom;
                final b = _dragTo;
                setState(() {
                  _dragFrom = null;
                  _dragTo = null;
                });
                if (a == null || b == null || (a - b).abs() < 4) return;
                widget.onZoom(_timeAt(math.min(a, b), plot), _timeAt(math.max(a, b), plot));
              },
              onHorizontalDragCancel: () => setState(() {
                _dragFrom = null;
                _dragTo = null;
              }),
              child: CustomPaint(
                size: size,
                painter: _PlotPainter(
                  traces: widget.traces,
                  start: widget.start,
                  end: widget.end,
                  hasRight: _hasRight,
                  hoverX: _hoverX,
                  bandFrom: _dragFrom,
                  bandTo: _dragTo,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Margins shared by the painter and the gesture code.
class ChartGeometry {
  static const double axisWidth = 64;
  static const double edge = 12;
  static const double top = 14;
  static const double bottom = 24;

  static Rect plotRect(Size size, {required bool hasRight}) =>
      Rect.fromLTRB(axisWidth, top, size.width - (hasRight ? axisWidth : edge), size.height - bottom);
}

/// A "nice" step (1, 2 or 5 times a power of ten) giving about [count] steps across [range].
double niceStep(double range, int count) {
  if (range <= 0 || count <= 0) return 1;
  final raw = range / count;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final nice = norm < 1.5
      ? 1.0
      : norm < 3
          ? 2.0
          : norm < 7
              ? 5.0
              : 10.0;
  return nice * mag;
}

const List<int> _timeSteps = <int>[
  1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000, // µs → 0.5 s
  1000000, 2000000, 5000000, 10000000, 15000000, 30000000, // → 30 s
  60000000, 120000000, 300000000, 600000000, 900000000, 1800000000, 3600000000,
];

/// A time-axis step (in µs) giving about [count] ticks across [spanMicros].
int timeStep(int spanMicros, int count) {
  final target = spanMicros / math.max(count, 1);
  for (final s in _timeSteps) {
    if (s >= target) return s;
  }
  return _timeSteps.last;
}

class _AxisRange {
  _AxisRange(this.min, this.max);
  double min;
  double max;
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.traces,
    required this.start,
    required this.end,
    required this.hasRight,
    required this.hoverX,
    required this.bandFrom,
    required this.bandTo,
  });

  final List<ChartTrace> traces;
  final DateTime start;
  final DateTime end;
  final bool hasRight;
  final double? hoverX;
  final double? bandFrom;
  final double? bandTo;

  static final TextStyle _axisText = kMono.copyWith(fontSize: 11, color: kMuted);

  TextPainter _text(String s, {TextStyle? style}) => TextPainter(
        text: TextSpan(text: s, style: style ?? _axisText),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  /// Index range of [p] to draw for the view, including one point either
  /// side so lines run off the edges instead of stopping short.
  (int, int) _visible(PointBuffer p, int s, int e) {
    final i0 = math.max(0, p.lowerBound(s) - 1);
    final i1 = math.min(p.length, p.lowerBound(e + 1) + 1);
    return (i0, i1);
  }

  _AxisRange? _range(PlotAxis axis, int s, int e) {
    _AxisRange? r;
    for (final t in traces) {
      final p = t.points;
      if (!t.trace.visible || t.trace.axis != axis || p == null || p.isEmpty) continue;
      final (i0, i1) = _visible(p, s, e);
      for (var i = i0; i < i1; i++) {
        final v = p.valueAt(i);
        if (r == null) {
          r = _AxisRange(v, v);
        } else {
          if (v < r.min) r.min = v;
          if (v > r.max) r.max = v;
        }
      }
    }
    if (r == null) return null;
    if (r.min == r.max) {
      final pad = r.min == 0 ? 1.0 : r.min.abs() * 0.1;
      r.min -= pad;
      r.max += pad;
    } else {
      final pad = (r.max - r.min) * 0.06;
      r.min -= pad;
      r.max += pad;
    }
    return r;
  }

  String _unitFor(PlotAxis axis) {
    final units = <String>{
      for (final t in traces)
        if (t.trace.visible && t.trace.axis == axis && t.unit.isNotEmpty) t.unit,
    };
    return units.length == 1 ? units.first : '';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = ChartGeometry.plotRect(size, hasRight: hasRight);
    if (plot.width <= 4 || plot.height <= 4) return;
    final s = start.microsecondsSinceEpoch;
    final e = end.microsecondsSinceEpoch;
    final span = math.max(1, e - s);
    double xOf(int t) => plot.left + (t - s) / span * plot.width;

    final grid = Paint()
      ..color = kDivider
      ..strokeWidth = 1;

    final left = _range(PlotAxis.left, s, e);
    final right = hasRight ? _range(PlotAxis.right, s, e) : null;

    // Horizontal guides follow the left scale (or the right one if alone).
    _drawYAxis(canvas, plot, left, PlotAxis.left, grid, drawGrid: true);
    if (hasRight) _drawYAxis(canvas, plot, right, PlotAxis.right, grid, drawGrid: left == null);

    // Time axis.
    final step = timeStep(span, math.max(2, (plot.width / 110).floor()));
    final firstTick = (s ~/ step + 1) * step;
    for (var t = firstTick; t <= e; t += step) {
      final x = xOf(t);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid..color = kDivider.withAlpha(120));
      final label = _text(_formatTick(DateTime.fromMicrosecondsSinceEpoch(t), step));
      final lx = (x - label.width / 2).clamp(0.0, size.width - label.width);
      label.paint(canvas, Offset(lx, plot.bottom + 5));
    }
    grid.color = kDivider;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, grid);
    if (hasRight) canvas.drawLine(plot.topRight, plot.bottomRight, grid);

    // Traces.
    canvas.save();
    canvas.clipRect(plot.inflate(2));
    var anyData = false;
    for (final t in traces) {
      final p = t.points;
      final r = t.trace.axis == PlotAxis.left ? left : right;
      if (!t.trace.visible || p == null || p.isEmpty || r == null) continue;
      final (i0, i1) = _visible(p, s, e);
      if (i1 <= i0) continue;
      anyData = true;
      double yOf(double v) => plot.bottom - (v - r.min) / (r.max - r.min) * plot.height;
      _drawTrace(canvas, p, i0, i1, xOf, yOf, plot, traceColor(t.trace));
    }
    canvas.restore();

    if (!anyData) {
      final msg = _text(
        traces.isEmpty ? 'Add a value from a row\'s detail panel' : 'No data in this stretch of time',
        style: kMono.copyWith(color: kMuted),
      );
      msg.paint(canvas, plot.center - Offset(msg.width / 2, msg.height / 2));
    }

    // Drag-to-zoom band.
    final a = bandFrom;
    final b = bandTo;
    if (a != null && b != null && (a - b).abs() >= 1) {
      final band = Rect.fromLTRB(math.min(a, b), plot.top, math.max(a, b), plot.bottom);
      canvas.drawRect(band, Paint()..color = kAccent.withAlpha(40));
      final edge = Paint()
        ..color = kAccent
        ..strokeWidth = 1;
      canvas.drawLine(band.topLeft, band.bottomLeft, edge);
      canvas.drawLine(band.topRight, band.bottomRight, edge);
    }

    final hx = hoverX;
    if (hx != null && a == null) _drawHover(canvas, size, plot, hx, s, span, left, right);
  }

  void _drawYAxis(Canvas canvas, Rect plot, _AxisRange? r, PlotAxis axis, Paint grid, {required bool drawGrid}) {
    final isLeft = axis == PlotAxis.left;
    final x = isLeft ? plot.left : plot.right;

    // Which traces this scale belongs to: their color marks at the top.
    var mx = isLeft ? plot.left - 8 : plot.right + 4;
    for (final t in traces) {
      if (!t.trace.visible || t.trace.axis != axis) continue;
      final paint = Paint()
        ..color = traceColor(t.trace)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(mx, plot.top - 8), Offset(mx + 4, plot.top - 8), paint);
      mx += isLeft ? -8 : 8;
    }
    final unit = _unitFor(axis);
    if (unit.isNotEmpty) {
      final u = _text(unit);
      u.paint(canvas, Offset(isLeft ? 4 : plot.right + ChartGeometry.axisWidth - u.width - 4, plot.top - 12));
    }

    if (r == null) return;
    final step = niceStep(r.max - r.min, math.max(2, (plot.height / 48).floor()));
    final first = (r.min / step).ceil() * step;
    for (var v = first; v <= r.max + step * 1e-9; v += step) {
      final y = plot.bottom - (v - r.min) / (r.max - r.min) * plot.height;
      if (drawGrid) canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid..color = kDivider.withAlpha(120));
      final label = _text(_formatValue(v, step));
      final lx = isLeft ? x - 6 - label.width : x + 6;
      label.paint(canvas, Offset(lx, y - label.height / 2));
    }
    grid.color = kDivider;
  }

  void _drawTrace(
    Canvas canvas,
    PointBuffer p,
    int i0,
    int i1,
    double Function(int) xOf,
    double Function(double) yOf,
    Rect plot,
    Color color,
  ) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final count = i1 - i0;
    final path = Path();

    if (count > plot.width * 2) {
      // Too many points to draw one by one: per pixel column keep the first,
      // min, max and last value, which preserves spikes exactly.
      var col = xOf(p.timeAt(i0)).floor();
      var first = p.valueAt(i0);
      var lo = first;
      var hi = first;
      var last = first;
      var started = false;
      void flush() {
        final x = col.toDouble();
        if (!started) {
          path.moveTo(x, yOf(first));
          started = true;
        } else {
          path.lineTo(x, yOf(first));
        }
        path.lineTo(x, yOf(lo));
        path.lineTo(x, yOf(hi));
        path.lineTo(x, yOf(last));
      }

      for (var i = i0 + 1; i < i1; i++) {
        final c = xOf(p.timeAt(i)).floor();
        final v = p.valueAt(i);
        if (c != col) {
          flush();
          col = c;
          first = v;
          lo = v;
          hi = v;
        }
        if (v < lo) lo = v;
        if (v > hi) hi = v;
        last = v;
      }
      flush();
      canvas.drawPath(path, line..strokeWidth = 1.5);
      return;
    }

    path.moveTo(xOf(p.timeAt(i0)), yOf(p.valueAt(i0)));
    for (var i = i0 + 1; i < i1; i++) {
      path.lineTo(xOf(p.timeAt(i)), yOf(p.valueAt(i)));
    }
    canvas.drawPath(path, line);

    // Sparse data: mark each sample so single points are visible.
    if (count <= plot.width / 10) {
      final dot = Paint()..color = color;
      final ring = Paint()..color = kBackground;
      for (var i = i0; i < i1; i++) {
        final o = Offset(xOf(p.timeAt(i)), yOf(p.valueAt(i)));
        canvas.drawCircle(o, 4, ring);
        canvas.drawCircle(o, 3, dot);
      }
    }
  }

  void _drawHover(
    Canvas canvas,
    Size size,
    Rect plot,
    double hx,
    int s,
    int span,
    _AxisRange? left,
    _AxisRange? right,
  ) {
    final t = s + ((hx - plot.left) / plot.width * span).round();
    canvas.drawLine(
      Offset(hx, plot.top),
      Offset(hx, plot.bottom),
      Paint()
        ..color = kText.withAlpha(90)
        ..strokeWidth = 1,
    );

    // Nearest sample of each visible trace.
    final rows = <(Color, String)>[];
    for (final ct in traces) {
      final p = ct.points;
      final r = ct.trace.axis == PlotAxis.left ? left : right;
      if (!ct.trace.visible || p == null || p.isEmpty || r == null) continue;
      var i = p.lowerBound(t);
      if (i >= p.length) i = p.length - 1;
      if (i > 0 && (t - p.timeAt(i - 1)).abs() < (p.timeAt(i) - t).abs()) i--;
      // Only if the sample is near the cursor (within 3% of the view).
      if ((p.timeAt(i) - t).abs() > span * 0.03) continue;
      final v = p.valueAt(i);
      final o = Offset(
        plot.left + (p.timeAt(i) - s) / span * plot.width,
        plot.bottom - (v - r.min) / (r.max - r.min) * plot.height,
      );
      canvas.drawCircle(o, 5, Paint()..color = kBackground);
      canvas.drawCircle(o, 4, Paint()..color = traceColor(ct.trace));
      rows.add((traceColor(ct.trace), '${ct.trace.label}  ${formatNumber(v)}${ct.unit}'));
    }

    final header = _text(formatTime(DateTime.fromMicrosecondsSinceEpoch(t)), style: _axisText);
    final lines = <TextPainter>[for (final r in rows) _text(r.$2, style: kMono.copyWith(fontSize: 12))];
    var w = header.width;
    for (final l in lines) {
      w = math.max(w, l.width + 14);
    }
    const pad = 8.0;
    const rowH = 18.0;
    final boxW = w + pad * 2;
    final boxH = pad * 2 + header.height + 4 + rows.length * rowH;
    var bx = hx + 12;
    if (bx + boxW > plot.right) bx = hx - 12 - boxW;
    bx = bx.clamp(0.0, math.max(0.0, size.width - boxW));
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(bx, plot.top + 4, boxW, boxH), const Radius.circular(6));
    canvas.drawRRect(box, Paint()..color = kSurface.withAlpha(235));
    canvas.drawRRect(
      box,
      Paint()
        ..color = kDivider
        ..style = PaintingStyle.stroke,
    );
    header.paint(canvas, Offset(bx + pad, plot.top + 4 + pad));
    var y = plot.top + 4 + pad + header.height + 4;
    for (var i = 0; i < lines.length; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx + pad, y + 5, 8, 8), const Radius.circular(2)),
        Paint()..color = rows[i].$1,
      );
      lines[i].paint(canvas, Offset(bx + pad + 14, y));
      y += rowH;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _formatTick(DateTime t, int stepMicros) {
    final hms = '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    if (stepMicros >= 1000000) return hms;
    final ms = t.millisecond.toString().padLeft(3, '0');
    return stepMicros >= 100000 ? '$hms.${ms.substring(0, 1)}' : '$hms.$ms';
  }

  static String _formatValue(double v, double step) {
    if (v.abs() < step * 1e-6) v = 0;
    final decimals = step >= 1 ? 0 : (-math.log(step) / math.ln10).ceil().clamp(0, 8);
    final abs = v.abs();
    if (abs >= 1e6 || (abs > 0 && abs < 1e-4)) return v.toStringAsExponential(1);
    return v.toStringAsFixed(decimals);
  }

  @override
  bool shouldRepaint(covariant _PlotPainter old) => true;
}

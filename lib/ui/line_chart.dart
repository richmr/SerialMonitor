import 'package:flutter/material.dart';

import '../model/message_store.dart';
import 'style.dart';

/// A plain time-series line chart for one value.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.points, this.unit = ''});

  final List<SeriesPoint> points;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LineChartPainter(points, unit), size: Size.infinite);
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.points, this.unit);

  final List<SeriesPoint> points;
  final String unit;

  static const double _left = 64;
  static const double _right = 10;
  static const double _top = 10;
  static const double _bottom = 22;

  void _label(Canvas canvas, String text, Offset at, {bool alignRight = false, Color color = kMuted}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: kMono.copyWith(fontSize: 11, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, alignRight ? Offset(at.dx - painter.width, at.dy) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_left, _top, size.width - _right, size.height - _bottom);
    if (plot.width <= 0 || plot.height <= 0) return;

    final grid = Paint()
      ..color = kDivider
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, grid);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, grid);

    if (points.isEmpty) {
      _label(canvas, 'no data yet', plot.center);
      return;
    }

    var minV = points.first.value;
    var maxV = minV;
    for (final p in points) {
      if (p.value < minV) minV = p.value;
      if (p.value > maxV) maxV = p.value;
    }
    if (minV == maxV) {
      // Flat line: give it some room so it draws mid-height.
      final pad = minV == 0 ? 1.0 : minV.abs() * 0.1;
      minV -= pad;
      maxV += pad;
    }
    final t0 = points.first.time.microsecondsSinceEpoch;
    final t1 = points.last.time.microsecondsSinceEpoch;
    final spanT = t1 > t0 ? (t1 - t0).toDouble() : 1.0;
    final spanV = maxV - minV;

    double x(SeriesPoint p) => plot.left + (p.time.microsecondsSinceEpoch - t0) / spanT * plot.width;
    double y(double v) => plot.bottom - (v - minV) / spanV * plot.height;

    // Horizontal guides at min, middle and max.
    final mid = (minV + maxV) / 2;
    canvas.drawLine(Offset(plot.left, y(mid)), Offset(plot.right, y(mid)), grid);
    canvas.drawLine(plot.topLeft, plot.topRight, grid);
    _label(canvas, formatNumber(maxV), Offset(_left - 6, plot.top - 6), alignRight: true);
    _label(canvas, formatNumber(mid), Offset(_left - 6, y(mid) - 7), alignRight: true);
    _label(canvas, formatNumber(minV), Offset(_left - 6, plot.bottom - 8), alignRight: true);
    _label(canvas, formatTime(points.first.time), Offset(plot.left, plot.bottom + 5));
    _label(canvas, formatTime(points.last.time), Offset(plot.right, plot.bottom + 5), alignRight: true);

    final line = Paint()
      ..color = kAccent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    if (points.length == 1) {
      canvas.drawCircle(Offset(plot.center.dx, y(points.first.value)), 3, Paint()..color = kAccent);
    } else {
      final path = Path()..moveTo(x(points.first), y(points.first.value));
      for (var i = 1; i < points.length; i++) {
        path.lineTo(x(points[i]), y(points[i].value));
      }
      canvas.drawPath(path, line);
      final last = points.last;
      canvas.drawCircle(Offset(x(last), y(last.value)), 3, Paint()..color = kAccent);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => true;
}

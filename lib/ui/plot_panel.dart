import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/plot.dart';
import 'plot_chart.dart';
import 'style.dart';

/// The plot window: a panel floating over the main window that can be moved
/// (drag its title bar) and resized (drag the bottom-right corner).
class PlotPanel extends StatefulWidget {
  const PlotPanel({super.key, required this.app, required this.area});

  final AppController app;

  /// Size of the area the panel floats in; it is kept inside it.
  final Size area;

  static const Size minSize = Size(460, 280);

  @override
  State<PlotPanel> createState() => _PlotPanelState();
}

class _PlotPanelState extends State<PlotPanel> {
  Timer? _tick;

  PlotModel get _plot => widget.app.plot;

  @override
  void initState() {
    super.initState();
    // While live, scroll smoothly even when no data arrives.
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _plot.live) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Size _clampSize(Size s) => Size(
        s.width.clamp(PlotPanel.minSize.width, math.max(PlotPanel.minSize.width, widget.area.width)).toDouble(),
        s.height.clamp(PlotPanel.minSize.height, math.max(PlotPanel.minSize.height, widget.area.height)).toDouble(),
      );

  Offset _clampPosition(Offset p, Size s) => Offset(
        p.dx.clamp(0.0, math.max(0.0, widget.area.width - s.width)).toDouble(),
        p.dy.clamp(0.0, math.max(0.0, widget.area.height - s.height)).toDouble(),
      );

  Offset get _position {
    final size = _clampSize(_plot.size);
    // First placement: bottom left, over the rows and above the command box,
    // so the detail panel on the right (where values are picked) stays clear.
    return _clampPosition(_plot.position ?? Offset(16, widget.area.height - size.height - 60), size);
  }

  @override
  Widget build(BuildContext context) {
    final size = _clampSize(_plot.size);
    final pos = _position;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: size.width,
      height: size.height,
      child: Material(
        color: kSurface,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: kDivider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TitleBar(
                  app: widget.app,
                  onDrag: (delta) => _plot.place(_clampPosition(_position + delta, size), size),
                ),
                const Divider(height: 1),
                _Toolbar(app: widget.app),
                _Legend(app: widget.app),
                Expanded(child: _chart()),
                _TimeScrollbar(app: widget.app),
              ],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: _ResizeGrip(
                onDrag: (delta) {
                  final next = _clampSize(Size(size.width + delta.dx, size.height + delta.dy));
                  _plot.place(_clampPosition(pos, next), next);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chart() {
    final app = widget.app;
    final now = app.now();
    final end = _plot.viewEnd(now);
    final start = end.subtract(_plot.viewSpan);
    final traces = <ChartTrace>[
      for (final t in _plot.traces)
        () {
          final s = app.store.group(t.groupKey)?.series[t.seriesName];
          return ChartTrace(t, s?.points, s?.unit ?? '');
        }(),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
      child: PlotChart(
        traces: traces,
        start: start,
        end: end,
        onZoom: _plot.zoomTo,
        onPan: (fraction) => _plot.pan(fraction, app.now()),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.app, required this.onDrag});

  final AppController app;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final plot = app.plot;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onDrag(d.delta),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
          child: Row(
            children: <Widget>[
              const Icon(Icons.drag_indicator, size: 16, color: kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Plot${app.deviceName.isEmpty ? '' : ' · ${app.deviceName}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: app.deviceName.isEmpty
                    ? 'Save this plot (needs a device that sends [!hello] with its name)'
                    : 'Save this plot for ${app.deviceName}. It opens by itself when ${app.deviceName} connects',
                icon: const Icon(Icons.save_outlined, size: 18),
                onPressed: app.canSavePlot
                    ? () {
                        final error = app.savePlot();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(error ?? 'Plot saved for ${app.deviceName}')));
                      }
                    : null,
              ),
              IconButton(
                tooltip: 'Close (the values stay; reopen from the top bar)',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => plot.setOpen(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.app});

  final AppController app;

  static String spanLabel(Duration d) {
    if (d.inMinutes >= 1 && d.inSeconds % 60 == 0) return '${d.inMinutes}m';
    if (d.inSeconds >= 1) return '${d.inSeconds}s';
    return '${d.inMilliseconds}ms';
  }

  static String _describe(Duration d) {
    final ms = d.inMilliseconds;
    if (ms >= 60000) return '${(ms / 60000).toStringAsFixed(1)} min';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(ms >= 10000 ? 0 : 1)} s';
    return '$ms ms';
  }

  @override
  Widget build(BuildContext context) {
    final plot = app.plot;
    final String status;
    if (plot.live) {
      status = 'Live';
    } else if (plot.zoomed) {
      status = 'Zoomed to ${_describe(plot.viewSpan)}, ending ${formatTime(plot.viewEnd(app.now()))}';
    } else {
      status = 'Paused at ${formatTime(plot.viewEnd(app.now()))}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 2),
      child: Row(
        children: <Widget>[
          for (final d in PlotModel.spans)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _SpanButton(
                label: spanLabel(d),
                selected: !plot.zoomed && plot.span == d,
                onTap: () => plot.setSpan(d, app.now()),
              ),
            ),
          const SizedBox(width: 8),
          Icon(
            Icons.circle,
            size: 8,
            color: plot.live ? const Color(0xFF6CC27A) : kMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Back to the previous view',
            icon: const Icon(Icons.undo, size: 18),
            onPressed: plot.canGoBack ? plot.goBack : null,
          ),
          IconButton(
            tooltip: 'Back to real time',
            icon: const Icon(Icons.fast_forward, size: 18),
            color: plot.live && !plot.zoomed ? null : kAccent,
            onPressed: plot.live && !plot.zoomed ? null : plot.goLive,
          ),
        ],
      ),
    );
  }
}

class _SpanButton extends StatelessWidget {
  const _SpanButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Show $label at a time',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? kAccent.withAlpha(50) : Colors.transparent,
            border: Border.all(color: selected ? kAccent : kDivider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final plot = app.plot;
    if (plot.traces.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          for (final t in plot.traces) _TraceChip(app: app, trace: t),
        ],
      ),
    );
  }
}

class _TraceChip extends StatelessWidget {
  const _TraceChip({required this.app, required this.trace});

  final AppController app;
  final PlotTrace trace;

  @override
  Widget build(BuildContext context) {
    final plot = app.plot;
    final series = app.store.group(trace.groupKey)?.series[trace.seriesName];
    final last = series?.last;
    final color = traceColor(trace);
    final onLeft = trace.axis == PlotAxis.left;
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border.all(color: kDivider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Opacity(
        opacity: trace.visible ? 1 : 0.5,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 14,
              height: 3,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 6),
            Text(trace.label, style: kMono.copyWith(fontSize: 12)),
            const SizedBox(width: 6),
            Text(
              last == null ? 'no data' : '${formatNumber(last)}${series!.unit}',
              style: kMono.copyWith(fontSize: 12, color: kMuted),
            ),
            const SizedBox(width: 2),
            _ChipButton(
              tooltip: onLeft
                  ? 'On the left scale. Click to move it to the right one'
                  : 'On the right scale. Click to move it to the left one',
              onTap: () => plot.setAxis(trace, onLeft ? PlotAxis.right : PlotAxis.left),
              child: Text(onLeft ? 'L' : 'R',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kMuted)),
            ),
            _ChipButton(
              tooltip: trace.visible ? 'Hide' : 'Show',
              onTap: () => plot.setVisible(trace, !trace.visible),
              child: Icon(trace.visible ? Icons.visibility : Icons.visibility_off, size: 14, color: kMuted),
            ),
            _ChipButton(
              tooltip: 'Remove from the plot',
              onTap: () => plot.remove(trace),
              child: const Icon(Icons.close, size: 14, color: kMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: SizedBox(width: 22, height: 22, child: Center(child: child)),
      ),
    );
  }
}

/// Shows where the view sits in all the data held. Drag the thumb to scroll;
/// click either side of it, or the arrows, to move one window length.
class _TimeScrollbar extends StatefulWidget {
  const _TimeScrollbar({required this.app});

  final AppController app;

  @override
  State<_TimeScrollbar> createState() => _TimeScrollbarState();
}

class _TimeScrollbarState extends State<_TimeScrollbar> {
  /// The view's right edge when a thumb drag started, and how far it has moved.
  DateTime? _dragStartEnd;
  double _dragDx = 0;

  PlotModel get _plot => widget.app.plot;

  /// Oldest point held for any visible trace.
  DateTime? _oldest() {
    int? oldest;
    for (final t in _plot.traces) {
      final p = widget.app.store.group(t.groupKey)?.series[t.seriesName]?.points;
      if (p == null || p.isEmpty) continue;
      final first = p.timeAt(0);
      if (oldest == null || first < oldest) oldest = first;
    }
    return oldest == null ? null : DateTime.fromMicrosecondsSinceEpoch(oldest);
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.app.now();
    final span = _plot.viewSpan.inMicroseconds;
    final end = _plot.viewEnd(now).microsecondsSinceEpoch;
    final oldest = _oldest()?.microsecondsSinceEpoch ?? (now.microsecondsSinceEpoch - span);
    final rangeStart = math.min(oldest, end - span);
    final total = math.max(span, now.microsecondsSinceEpoch - rangeStart);
    final thumbStart = (end - span - rangeStart) / total;
    final thumbWidth = span / total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 18, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Back one window',
            icon: const Icon(Icons.chevron_left, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _plot.pan(-1, widget.app.now()),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final thumbW = math.max(18.0, w * thumbWidth).clamp(0.0, w).toDouble();
                final thumbX = ((w - thumbW) * (thumbWidth >= 1 ? 1 : thumbStart / (1 - thumbWidth)))
                    .clamp(0.0, math.max(0.0, w - thumbW))
                    .toDouble();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    final x = d.localPosition.dx;
                    if (x < thumbX) {
                      _plot.pan(-1, widget.app.now());
                    } else if (x > thumbX + thumbW) {
                      _plot.pan(1, widget.app.now());
                    }
                  },
                  onHorizontalDragStart: (d) {
                    final x = d.localPosition.dx;
                    if (x >= thumbX && x <= thumbX + thumbW) {
                      _dragStartEnd = _plot.viewEnd(widget.app.now());
                      _dragDx = 0;
                    }
                  },
                  onHorizontalDragUpdate: (d) {
                    final from = _dragStartEnd;
                    if (from == null || w <= thumbW) return;
                    _dragDx += d.delta.dx;
                    final usable = (1 - thumbWidth) * total;
                    final micros = (_dragDx / (w - thumbW) * usable).round();
                    _plot.scrollTo(from.add(Duration(microseconds: micros)), widget.app.now());
                  },
                  onHorizontalDragEnd: (_) => _dragStartEnd = null,
                  child: SizedBox(
                    height: 18,
                    child: CustomPaint(painter: _ScrollbarPainter(thumbX, thumbW, live: _plot.live)),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Forward one window',
            icon: const Icon(Icons.chevron_right, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: _plot.live ? null : () => _plot.pan(1, widget.app.now()),
          ),
        ],
      ),
    );
  }
}

class _ScrollbarPainter extends CustomPainter {
  _ScrollbarPainter(this.x, this.w, {required this.live});

  final double x;
  final double w;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height / 2 - 4, size.width, 8),
      const Radius.circular(4),
    );
    canvas.drawRRect(track, Paint()..color = kBackground);
    final thumb = RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height / 2 - 5, w, 10), const Radius.circular(5));
    canvas.drawRRect(thumb, Paint()..color = live ? kAccent.withAlpha(160) : kMuted.withAlpha(160));
  }

  @override
  bool shouldRepaint(covariant _ScrollbarPainter old) => old.x != x || old.w != w || old.live != live;
}

class _ResizeGrip extends StatelessWidget {
  const _ResizeGrip({required this.onDrag});

  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => onDrag(d.delta),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CustomPaint(painter: _GripPainter()),
        ),
      ),
    );
  }
}

class _GripPainter extends CustomPainter {
  const _GripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = kMuted
      ..strokeWidth = 1.2;
    for (var i = 1; i <= 3; i++) {
      final o = i * 4.0;
      canvas.drawLine(Offset(size.width - o, size.height - 2), Offset(size.width - 2, size.height - o), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GripPainter old) => false;
}

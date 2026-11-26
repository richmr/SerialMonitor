import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import 'aggregate_view.dart';
import 'command_bar.dart';
import 'connection_bar.dart';
import 'detail_panel.dart';
import 'plot_panel.dart';
import 'style.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: <Widget>[
            Positioned.fill(child: _main()),
            // The plot window floats over everything else.
            ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[app, app.plot, app.store]),
              builder: (context, _) => app.plot.open
                  ? PlotPanel(app: app, area: constraints.biggest)
                  : const Positioned(left: 0, top: 0, child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _main() {
    return Column(
      children: <Widget>[
        // Connection state changes rarely; rebuild it only for those.
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[app, app.session, app.plot]),
          builder: (context, _) => ConnectionBar(app: app),
        ),
        const Divider(height: 1),
        Expanded(
          // The store notifies at most ~30 times a second.
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[app, app.store, app.plot]),
            builder: (context, _) {
              final selected = app.store.group(app.selectedGroup);
              return LayoutBuilder(
                builder: (context, constraints) {
                  // Leave the rows at least this much room, however wide the panel was dragged.
                  const minRowsWidth = 240.0;
                  final maxPanel = (constraints.maxWidth - minRowsWidth).clamp(0.0, double.infinity);
                  final panelWidth = app.detailWidth.clamp(0.0, maxPanel).toDouble();
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: AggregateView(app: app)),
                      if (selected != null) ...<Widget>[
                        _ResizeHandle(
                          onDrag: (dx) => app.setDetailWidth(
                            (app.detailWidth.clamp(0.0, maxPanel) - dx).clamp(0.0, maxPanel).toDouble(),
                          ),
                        ),
                        SizedBox(width: panelWidth, child: DetailPanel(app: app, group: selected)),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[app, app.session]),
          builder: (context, _) => Container(
            color: kSurface,
            child: CommandBar(app: app),
          ),
        ),
      ],
    );
  }
}

/// The divider between the rows and the detail panel. Drag it sideways to
/// resize the panel.
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDrag});

  /// Called with the horizontal movement since the last call.
  final ValueChanged<double> onDrag;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hover || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        // A wide invisible grab area around a thin visible line.
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(width: active ? 3 : 1, color: active ? kAccent : kDivider),
          ),
        ),
      ),
    );
  }
}

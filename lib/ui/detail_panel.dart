import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/message_store.dart';
import '../model/plot.dart';
import '../protocol/parser.dart';
import 'line_chart.dart';
import 'style.dart';

/// Everything about one kind of message: its values (click one to graph it)
/// and the log of every arrival.
class DetailPanel extends StatelessWidget {
  const DetailPanel({super.key, required this.app, required this.group});

  final AppController app;
  final MessageGroup group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final series = g.series[app.selectedSeries];
    final title = g.tag ?? 'Untagged message';

    return Container(
      color: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '$title  ·  ${g.count} received',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kMono.copyWith(color: levelColor(g.level), fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: app.detailTimestamps ? 'Hide timestamps in this log' : 'Show timestamps in this log',
                  isSelected: app.detailTimestamps,
                  icon: const Icon(Icons.schedule, size: 18),
                  selectedIcon: const Icon(Icons.schedule, size: 18, color: kAccent),
                  onPressed: () => app.setDetailTimestamps(!app.detailTimestamps),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => app.select(null),
                ),
              ],
            ),
          ),
          if (g.series.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final s in g.series.values)
                    _ValueChip(
                      series: s,
                      selected: s.name == app.selectedSeries,
                      onTap: () => app.selectSeries(s.name == app.selectedSeries ? null : s.name),
                    ),
                ],
              ),
            ),
          if (series != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      series.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMono.copyWith(color: kMuted),
                    ),
                  ),
                  _PlotButton(app: app, group: g, seriesName: series.name),
                ],
              ),
            ),
          if (series != null)
            SizedBox(
              height: 200,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                child: LineChart(points: series.points.tail(2000), unit: series.unit),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: g.log.length,
              itemExtent: MediaQuery.textScalerOf(context).scale(22),
              itemBuilder: (context, index) {
                // Newest first, so the list does not need to chase the bottom.
                final entry = g.log.elementAt(g.log.length - 1 - index);
                return _LogRow(entry: entry, showTime: app.detailTimestamps);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Sends the graphed value to the plot window (opening it), or adds it
/// alongside what is already plotted there.
class _PlotButton extends StatelessWidget {
  const _PlotButton({required this.app, required this.group, required this.seriesName});

  final AppController app;
  final MessageGroup group;
  final String seriesName;

  @override
  Widget build(BuildContext context) {
    final plot = app.plot;
    final inPlot = plot.find(group.key, seriesName)?.visible ?? false;
    final others = plot.traces.length - (plot.find(group.key, seriesName) == null ? 0 : 1);
    final String label;
    final String tip;
    if (inPlot) {
      label = plot.open ? 'In plot window' : 'Show plot window';
      tip = 'Already in the plot window';
    } else if (plot.open && others > 0) {
      label = 'Add to plot';
      tip = 'Overlay $seriesName on the plot window';
    } else {
      label = 'Plot in window';
      tip = 'Open $seriesName in the plot window';
    }
    return Tooltip(
      message: tip,
      child: TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: Icon(inPlot ? Icons.check : Icons.open_in_new, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: inPlot && plot.open
            ? null
            : () {
                if (!app.plotSeries(group.key, seriesName)) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(content: Text('The plot holds ${PlotModel.maxTraces} values. Remove one first')),
                    );
                }
              },
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.series, required this.selected, required this.onTap});

  final Series series;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final last = series.last;
    return Tooltip(
      message: selected ? 'Hide graph' : 'Graph ${series.name}',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? kAccent.withAlpha(50) : Colors.transparent,
            border: Border.all(color: selected ? kAccent : kDivider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: '${series.name} ', style: kMono.copyWith(color: kMuted)),
                TextSpan(text: last == null ? '–' : '${formatNumber(last)}${series.unit}', style: kMono),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.showTime});

  final LogEntry entry;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final strong = entry.level == Level.error || entry.level == Level.warn;
    return Tooltip(
      message: formatTime(entry.time),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: <Widget>[
            if (showTime) ...<Widget>[
              Text(formatTime(entry.time), style: kMono.copyWith(color: kMuted)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                entry.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: strong ? kMono.copyWith(color: levelColor(entry.level)) : kMono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

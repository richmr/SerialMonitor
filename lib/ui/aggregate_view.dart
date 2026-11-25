import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../model/message_store.dart';
import '../protocol/parser.dart';
import 'style.dart';

/// One row per kind of message, updated in place. Rows keep the position
/// they first appeared in, so nothing scrolls away while you read it.
class AggregateView extends StatefulWidget {
  const AggregateView({super.key, required this.app});

  final AppController app;

  @override
  State<AggregateView> createState() => _AggregateViewState();
}

class _AggregateViewState extends State<AggregateView> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final store = app.store;
    final needle = _filter.toLowerCase();
    final rows = <MessageGroup>[
      for (final g in store.groups)
        if (needle.isEmpty || g.text.toLowerCase().contains(needle) || (g.tag ?? '').toLowerCase().contains(needle)) g,
    ];

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  style: kMono,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.filter_list, size: 18),
                    prefixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 24),
                    hintText: 'Filter rows',
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              Text(
                '${store.totalLines} lines · ${store.groupCount} rows'
                '${store.bootCount > 0 ? ' · ${store.bootCount} restarts' : ''}',
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    store.groupCount == 0 ? 'Nothing received yet' : 'No rows match the filter',
                    style: const TextStyle(color: kMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemExtent: MediaQuery.textScalerOf(context).scale(_GroupRow.height),
                  itemBuilder: (context, index) {
                    final g = rows[index];
                    return _GroupRow(
                      key: ValueKey<String>(g.key),
                      app: app,
                      group: g,
                      selected: g.key == app.selectedGroup,
                      stale: store.isStale(g),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    super.key,
    required this.app,
    required this.group,
    required this.selected,
    required this.stale,
  });

  static const double height = 26;
  static const Duration _flash = Duration(milliseconds: 700);

  final AppController app;
  final MessageGroup group;
  final bool selected;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final color = levelColor(g.level);
    final hasValues = g.series.isNotEmpty;
    final fresh = DateTime.now().difference(g.lastSeen) < _flash;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              '(${g.count})',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: kMono.copyWith(color: kMuted),
            ),
          ),
          const SizedBox(width: 10),
          if (app.showTimestamps) ...<Widget>[
            Text(formatTime(g.lastSeen), style: kMono.copyWith(color: kMuted)),
            const SizedBox(width: 10),
          ],
          if (g.tag != null) ...<Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                g.tag!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kMono.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              g.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (g.level == Level.error || g.level == Level.warn) ? kMono.copyWith(color: color) : kMono,
            ),
          ),
          if (hasValues)
            Tooltip(
              message: 'Graph ${g.series.keys.first}',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => app.select(g.key, series: g.series.keys.first),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.show_chart, size: 16, color: kMuted),
                ),
              ),
            ),
        ],
      ),
    );

    // Briefly tint the row each time it updates, so changes catch the eye.
    // Only the tint is keyed on the count: the tooltip and tap target keep
    // their state, so hovering works even on a row that updates constantly.
    final tinted = TweenAnimationBuilder<double>(
      key: ValueKey<int>(g.count),
      tween: Tween<double>(begin: fresh ? 1 : 0, end: 0),
      duration: _flash,
      builder: (context, t, child) => ColoredBox(
        color: selected ? kAccent.withAlpha(40 + (t * 40).round()) : kAccent.withAlpha((t * 46).round()),
        child: child,
      ),
      child: Opacity(opacity: stale ? 0.45 : 1, child: content),
    );

    return GestureDetector(
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
      child: Tooltip(
        message: 'Last arrival ${formatTime(g.lastSeen)}\n'
            'First arrival ${formatTime(g.firstSeen)}\n'
            '${g.count} total${g.repeat > 1 ? ', last ${g.repeat} identical' : ''}'
            '${stale ? '\nNot seen since the device restarted' : ''}',
        child: InkWell(
          onTap: () => app.select(selected ? null : g.key),
          child: tinted,
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    final g = group;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: 'copy', child: Text('Copy line')),
        const PopupMenuItem<String>(value: 'copyLog', child: Text('Copy all arrivals')),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'delete', child: Text('Delete row')),
      ],
    );
    switch (choice) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: g.tag == null ? g.text : '[${g.tag}] ${g.text}'));
      case 'copyLog':
        final text = g.log.map((e) => '${formatTime(e.time)}  ${e.text}').join('\n');
        await Clipboard.setData(ClipboardData(text: text));
      case 'delete':
        app.deleteRow(g.key);
    }
  }
}

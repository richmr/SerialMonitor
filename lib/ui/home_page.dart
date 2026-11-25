import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import 'aggregate_view.dart';
import 'command_bar.dart';
import 'connection_bar.dart';
import 'detail_panel.dart';
import 'style.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          // Connection state changes rarely; rebuild it only for those.
          ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[app, app.session]),
            builder: (context, _) => ConnectionBar(app: app),
          ),
          const Divider(height: 1),
          Expanded(
            // The store notifies at most ~30 times a second.
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[app, app.store]),
              builder: (context, _) {
                final selected = app.store.group(app.selectedGroup);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: AggregateView(app: app)),
                    if (selected != null) ...<Widget>[
                      const VerticalDivider(width: 1),
                      SizedBox(width: 460, child: DetailPanel(app: app, group: selected)),
                    ],
                  ],
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
      ),
    );
  }
}

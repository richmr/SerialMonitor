import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:serial_monitor/app_controller.dart';
import 'package:serial_monitor/main.dart';
import 'package:serial_monitor/model/message_store.dart';
import 'package:serial_monitor/ui/detail_panel.dart';

import 'session_test.dart' show FakeTransport;

void main() {
  testWidgets('rows update in place and open a log when clicked', (tester) async {
    final app = AppController(FakeTransport(), store: MessageStore(notifyInterval: Duration.zero));
    addTearDown(app.dispose);
    await tester.pumpWidget(SerialMonitorApp(app: app));
    expect(find.text('Nothing received yet'), findsOneWidget);

    app.handleLine('[env] temp=20.0C hum=41%');
    app.handleLine('[env] temp=21.5C hum=40%');
    app.handleLine('heartbeat');
    await tester.pumpAndSettle();

    expect(find.text('env'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('temp=20.0C hum=41%'), findsNothing);
    expect(find.text('temp=21.5C hum=40%'), findsOneWidget);

    await tester.tap(find.text('temp=21.5C hum=40%'));
    await tester.pumpAndSettle();

    // The detail panel lists both arrivals.
    expect(find.textContaining('2 received'), findsOneWidget);
    expect(find.text('temp=20.0C hum=41%'), findsOneWidget);
    expect(find.text('temp=21.5C hum=40%'), findsNWidgets(2));
  });

  testWidgets('right-click deletes a row; the divider resizes the panel; Ctrl/Cmd + zooms', (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppController(FakeTransport(), store: MessageStore(notifyInterval: Duration.zero));
    addTearDown(app.dispose);
    await tester.pumpWidget(SerialMonitorApp(app: app));

    app.handleLine('[env] temp=20.0C');
    app.handleLine('heartbeat');
    await tester.pumpAndSettle();

    // Right-click → Delete row.
    await tester.tap(find.text('heartbeat'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete row'));
    await tester.pumpAndSettle();
    expect(find.text('heartbeat'), findsNothing);
    expect(find.text('env'), findsOneWidget);

    // Open the panel and drag its divider 100px to the left.
    await tester.tap(find.text('temp=20.0C'));
    await tester.pumpAndSettle();
    final panel = find.byType(DetailPanel);
    expect(tester.getSize(panel).width, 460);
    final divider = tester.getTopLeft(panel) - const Offset(3, -200);
    await tester.dragFrom(divider, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, closeTo(560, 1));

    // The panel's own timestamp toggle.
    expect(app.detailTimestamps, isTrue);
    await tester.tap(find.descendant(of: panel, matching: find.byIcon(Icons.schedule)));
    expect(app.detailTimestamps, isFalse);

    final mod = defaultTargetPlatform == TargetPlatform.macOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(mod);
    await tester.pumpAndSettle();
    expect(app.textScale.value, greaterThan(1.0));
  });
}

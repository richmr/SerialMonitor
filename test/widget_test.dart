import 'package:flutter_test/flutter_test.dart';
import 'package:serial_monitor/app_controller.dart';
import 'package:serial_monitor/main.dart';
import 'package:serial_monitor/model/message_store.dart';

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
}

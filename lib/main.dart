import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'serial/libserial_transport.dart';
import 'ui/home_page.dart';
import 'ui/style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppController(LibSerialTransport());
  app.start();
  runApp(SerialMonitorApp(app: app));
}

class SerialMonitorApp extends StatelessWidget {
  const SerialMonitorApp({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serial Monitor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomePage(app: app),
    );
  }
}

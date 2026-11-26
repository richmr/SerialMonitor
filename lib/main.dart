import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'model/plot.dart';
import 'serial/libserial_transport.dart';
import 'ui/home_page.dart';
import 'ui/style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppController(LibSerialTransport(), plotSettings: PlotSettingsStore.defaultLocation());
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
      builder: (context, child) => _ZoomScope(app: app, child: child!),
      home: HomePage(app: app),
    );
  }
}

/// Cmd (macOS) or Ctrl (elsewhere) with + / - / 0 zooms the text.
/// Handled before the focus system so it works whatever has focus,
/// including the command box.
class _ZoomScope extends StatefulWidget {
  const _ZoomScope({required this.app, required this.child});

  final AppController app;
  final Widget child;

  @override
  State<_ZoomScope> createState() => _ZoomScopeState();
}

class _ZoomScopeState extends State<_ZoomScope> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final modifier = defaultTargetPlatform == TargetPlatform.macOS ? keyboard.isMetaPressed : keyboard.isControlPressed;
    if (!modifier || keyboard.isAltPressed) return false;
    final key = event.logicalKey;
    final app = widget.app;
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.add || key == LogicalKeyboardKey.numpadAdd) {
      app.zoomIn();
    } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
      app.zoomOut();
    } else if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      app.zoomReset();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.app.textScale,
      builder: (context, scale, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      child: widget.child,
    );
  }
}

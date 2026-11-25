import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../serial/session.dart';
import 'style.dart';

/// Port / baud selection, connection state and view toggles.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final session = app.session;
    final hasSelected = session.ports.any((p) => p.name == session.portName);
    final active = session.state != LinkState.idle;

    return Container(
      color: kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: hasSelected ? session.portName : null,
                hint: Text(
                  session.portName ?? (session.ports.isEmpty ? 'No serial ports found' : 'Select a port'),
                  overflow: TextOverflow.ellipsis,
                ),
                items: <DropdownMenuItem<String>>[
                  for (final p in session.ports)
                    DropdownMenuItem<String>(
                      value: p.name,
                      child: Text(p.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: session.selectPort,
              ),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            isDense: true,
            value: session.baud,
            items: <DropdownMenuItem<int>>[
              for (final b in SerialSession.baudRates) DropdownMenuItem<int>(value: b, child: Text('$b')),
            ],
            onChanged: (value) {
              if (value == null || value == session.baud) return;
              session.baud = value;
              session.applySettings();
            },
          ),
          const SizedBox(width: 12),
          if (active)
            OutlinedButton(onPressed: session.disconnect, child: const Text('Disconnect'))
          else
            FilledButton(
              onPressed: session.portName == null ? null : session.connect,
              child: const Text('Connect'),
            ),
          const SizedBox(width: 12),
          Flexible(child: _StatusLabel(app: app)),
          const Spacer(),
          IconButton(
            tooltip: 'Restart the ESP32 (pulse EN through RTS)',
            icon: const Icon(Icons.restart_alt),
            onPressed: session.state == LinkState.connected ? session.resetDevice : null,
          ),
          if (session.state == LinkState.released)
            IconButton(
              tooltip: 'Take the port back',
              icon: const Icon(Icons.play_circle_outline),
              onPressed: session.resume,
            )
          else
            IconButton(
              tooltip: 'Release the port so another program can upload',
              icon: const Icon(Icons.pause_circle_outline),
              onPressed: active ? () => session.release() : null,
            ),
          IconButton(
            tooltip: app.showTimestamps ? 'Hide timestamps' : 'Show timestamps on every line',
            isSelected: app.showTimestamps,
            icon: const Icon(Icons.schedule),
            selectedIcon: const Icon(Icons.schedule, color: kAccent),
            onPressed: () => app.setShowTimestamps(!app.showTimestamps),
          ),
          IconButton(
            tooltip: 'Clear all rows',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: app.clear,
          ),
          PopupMenuButton<String>(
            tooltip: 'Options',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _onMenu(context, value),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              CheckedPopupMenuItem<String>(
                value: 'reconnect',
                checked: session.autoReconnect,
                child: const Text('Reconnect automatically'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'clearOnBoot',
                checked: app.clearOnBoot,
                child: const Text('Clear rows when the device restarts'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<String>(
                value: 'dtr',
                checked: session.dtr,
                child: const Text('Assert DTR'),
              ),
              CheckedPopupMenuItem<String>(
                value: 'rts',
                checked: session.rts,
                child: const Text('Assert RTS'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'protocol', child: Text('Load protocol file…')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String value) async {
    final session = app.session;
    switch (value) {
      case 'reconnect':
        session.setAutoReconnect(!session.autoReconnect);
      case 'clearOnBoot':
        app.setClearOnBoot(!app.clearOnBoot);
      case 'dtr':
        session.dtr = !session.dtr;
        session.applySettings();
      case 'rts':
        session.rts = !session.rts;
        session.applySettings();
      case 'protocol':
        await _loadProtocol(context);
    }
  }

  Future<void> _loadProtocol(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String? error;
    try {
      final types = XTypeGroup(label: 'Protocol description', extensions: <String>['json']);
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[types]);
      if (file == null) return;
      error = app.loadProtocol(file.name, await file.readAsString());
    } catch (e) {
      error = 'Could not open the file: $e';
    }
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final session = app.session;
    late final Color color;
    late final String text;
    switch (session.state) {
      case LinkState.connected:
        color = const Color(0xFF6CC27A);
        text = app.deviceName.isEmpty ? 'Connected' : 'Connected · ${app.deviceName}';
      case LinkState.waiting:
        color = const Color(0xFFE5B84B);
        text = 'Waiting for device…';
      case LinkState.released:
        color = kAccent;
        text = 'Released for upload';
      case LinkState.idle:
        color = kMuted;
        text = 'Not connected';
    }
    final error = session.lastError;
    final showError = error != null && session.state != LinkState.connected && session.state != LinkState.released;
    return Tooltip(
      message: showError ? error : text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

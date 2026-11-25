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
          if (app.transcript.isRecording) ...<Widget>[
            _RecordingChip(app: app),
            const SizedBox(width: 8),
          ],
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
            tooltip: app.showTimestamps ? 'Hide row timestamps' : 'Show timestamps on every row',
            isSelected: app.showTimestamps,
            icon: const Icon(Icons.schedule),
            selectedIcon: const Icon(Icons.schedule, color: kAccent),
            onPressed: () => app.setShowTimestamps(!app.showTimestamps),
          ),
          IconButton(
            tooltip: 'Save the serial stream to a file',
            icon: const Icon(Icons.save_alt),
            onPressed: () => _saveStream(context),
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
              CheckedPopupMenuItem<String>(
                value: 'autoDescribe',
                checked: app.autoDescribe,
                child: const Text('Ask SMP devices for their commands (?)'),
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
              const PopupMenuDivider(),
              const PopupMenuItem<String>(value: 'save', child: Text('Save serial stream…')),
              PopupMenuItem<String>(
                value: 'record',
                child: Text(app.transcript.isRecording ? 'Stop recording' : 'Record serial stream to file…'),
              ),
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
      case 'autoDescribe':
        app.setAutoDescribe(!app.autoDescribe);
      case 'protocol':
        await _loadProtocol(context);
      case 'save':
        await _saveStream(context);
      case 'record':
        if (app.transcript.isRecording) {
          await app.stopRecording();
        } else {
          await _startRecording(context);
        }
    }
  }

  static const XTypeGroup _logFiles = XTypeGroup(label: 'Log file', extensions: <String>['log', 'txt']);

  String _suggestedName(String suffix) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final device = app.deviceName.isEmpty ? 'serial' : app.deviceName.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    return '$device-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}$suffix.log';
  }

  Future<void> _saveStream(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (app.transcript.length == 0) {
      messenger.showSnackBar(const SnackBar(content: Text('Nothing received yet: nothing to save')));
      return;
    }
    try {
      final location = await getSaveLocation(
        suggestedName: _suggestedName(''),
        acceptedTypeGroups: const <XTypeGroup>[_logFiles],
      );
      if (location == null) return;
      final count = await app.saveTranscript(location.path);
      final dropped = app.transcript.droppedLines;
      messenger.showSnackBar(SnackBar(
        content: Text('Saved $count lines'
            '${dropped > 0 ? ' (the oldest $dropped were no longer in memory; use Record for long captures)' : ''}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _startRecording(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final location = await getSaveLocation(
        suggestedName: _suggestedName('-rec'),
        acceptedTypeGroups: const <XTypeGroup>[_logFiles],
        confirmButtonText: 'Record',
      );
      if (location == null) return;
      await app.startRecording(location.path);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not start recording: $e')));
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

/// Shown while the stream is being recorded to a file. Click to stop.
class _RecordingChip extends StatelessWidget {
  const _RecordingChip({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Recording to ${app.transcript.recordingPath}\nClick to stop',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: app.stopRecording,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFEF6B6B)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.fiber_manual_record, size: 12, color: Color(0xFFEF6B6B)),
              SizedBox(width: 4),
              Text('REC', style: TextStyle(fontSize: 12, color: Color(0xFFEF6B6B))),
            ],
          ),
        ),
      ),
    );
  }
}

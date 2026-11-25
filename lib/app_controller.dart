import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'model/message_store.dart';
import 'model/transcript.dart';
import 'protocol/parser.dart';
import 'protocol/protocol_doc.dart';
import 'serial/control_server.dart';
import 'serial/session.dart';
import 'serial/transport.dart';

/// Glue between the serial session, the message store and the UI state.
class AppController extends ChangeNotifier {
  AppController(SerialTransport transport, {DateTime Function()? clock, MessageStore? store})
      : _clock = clock ?? DateTime.now,
        store = store ?? MessageStore() {
    session = SerialSession(transport, onLine: handleLine, onEvent: _onSessionEvent, clock: _clock);
    session.addListener(_onSessionChanged);
  }

  static const String sentKey = '~sent';
  static const String monitorKey = '~monitor';
  static const Duration _describeWindow = Duration(seconds: 2);

  final DateTime Function() _clock;
  final MessageStore store;
  late final SerialSession session;
  final ControlServer _control = ControlServer();

  /// Every line in and out, in order, for saving the serial stream.
  final Transcript transcript = Transcript();

  // View options.
  bool showTimestamps = false;
  bool detailTimestamps = true;
  bool clearOnBoot = false;

  /// Width of the detail panel beside the rows (dragged with the divider).
  double detailWidth = 460;
  static const double minDetailWidth = 260;

  /// Text zoom (Cmd/Ctrl +, -, 0). Separate from [notifyListeners] so a zoom
  /// change does not rebuild everything else and vice versa.
  final ValueNotifier<double> textScale = ValueNotifier<double>(1.0);
  static const double minTextScale = 0.6;
  static const double maxTextScale = 2.5;

  /// Send `?` by itself once a connected device turns out to speak SMP, so
  /// its commands are always loaded.
  bool autoDescribe = true;
  bool _autoDescribed = false;
  LinkState _lastLinkState = LinkState.idle;

  // Selection: which row's detail panel is open and which value is graphed.
  String? selectedGroup;
  String? selectedSeries;

  // Commands.
  String deviceName = '';
  String protocolFileName = '';
  final List<CommandSpec> _deviceCommands = <CommandSpec>[];
  List<CommandSpec> _fileCommands = const <CommandSpec>[];
  final List<String> history = <String>[];
  DateTime? _describeSentAt;

  /// Commands announced by the device first, then those from a protocol file.
  List<CommandSpec> get commands {
    final names = <String>{};
    return <CommandSpec>[
      for (final c in <CommandSpec>[..._deviceCommands, ..._fileCommands])
        if (names.add(c.name)) c,
    ];
  }

  Future<void> start() async {
    session.start();
    final error = await _control.start(_handleControl);
    if (error != null) {
      _monitorEvent(
        'Upload hook unavailable: port ${ControlServer.defaultPort} is in use '
        '(is another Serial Monitor running?)',
        true,
      );
    }
  }

  // ---- incoming lines -------------------------------------------------------

  void handleLine(String line) {
    final parsed = parseLine(line);
    if (parsed == null) return;
    final now = _clock();
    transcript.add(TranscriptLine(now, Direction.received, parsed.raw));

    if (parsed.isMeta) {
      final fields = parseKeyValues(parsed.body);
      if (parsed.tag == '!cmd') {
        final spec = CommandSpec.fromFields(fields);
        if (spec != null) {
          _deviceCommands.removeWhere((c) => c.name == spec.name);
          _deviceCommands.add(spec);
          notifyListeners();
        }
        return; // command declarations are not shown as rows
      }
      if (parsed.tag == '!hello') {
        deviceName = fields['name'] ?? '';
        final sent = _describeSentAt;
        final isReplyToDescribe = sent != null && now.difference(sent) < _describeWindow;
        if (!isReplyToDescribe) {
          _deviceCommands.clear();
          _autoDescribed = false; // the device restarted: ask it again
          _noteBoot(now);
        }
        notifyListeners();
      }
    } else if (isRomBootLine(parsed.raw)) {
      _noteBoot(now);
    }

    store.addLine(parsed, now);
    if (parsed.kind == LineKind.smp) _maybeAutoDescribe();
  }

  /// Asks an SMP device for its commands, once per connection (and again
  /// after it restarts), if it has not told us about any yet. The device
  /// only reads input once its setup is done, by which point its commands
  /// are registered, so asking straight after the boot `[!hello]` is fine.
  void _maybeAutoDescribe() {
    if (!autoDescribe || _autoDescribed || _deviceCommands.isNotEmpty) return;
    if (session.state != LinkState.connected) return;
    _autoDescribed = true;
    _sendLine('?', remember: false);
  }

  void _onSessionChanged() {
    final state = session.state;
    if (state == LinkState.connected && _lastLinkState != LinkState.connected) {
      _autoDescribed = false;
    }
    _lastLinkState = state;
  }

  void _noteBoot(DateTime now) {
    if (store.markBoot(now) && clearOnBoot) store.clear();
  }

  // ---- outgoing commands ----------------------------------------------------

  /// Sends a command line to the device. Returns false if not connected.
  bool send(String text) => _sendLine(text.trim(), remember: true);

  bool _sendLine(String command, {required bool remember}) {
    if (command.isEmpty) return false;
    if (!session.send(command)) return false;
    final now = _clock();
    if (command == '?') _describeSentAt = now;
    if (remember) {
      history.remove(command);
      history.insert(0, command);
      if (history.length > 50) history.removeLast();
    }
    transcript.add(TranscriptLine(now, Direction.sent, command));
    store.record(key: sentKey, tag: 'sent', text: command, time: now, kind: GroupKind.sent);
    notifyListeners();
    return true;
  }

  /// Loads a protocol description file's text. Returns an error message or null.
  String? loadProtocol(String fileName, String text) {
    try {
      final doc = ProtocolDoc.fromJson(text);
      _fileCommands = doc.commands;
      protocolFileName = fileName;
      _monitorEvent('Loaded ${doc.commands.length} commands from $fileName', false);
      notifyListeners();
      return null;
    } on FormatException catch (e) {
      return 'Not a valid protocol file: ${e.message}';
    } catch (e) {
      return 'Could not read protocol file: $e';
    }
  }

  // ---- view state -----------------------------------------------------------

  void select(String? groupKey, {String? series}) {
    selectedGroup = groupKey;
    selectedSeries = series;
    notifyListeners();
  }

  void selectSeries(String? name) {
    selectedSeries = name;
    notifyListeners();
  }

  void setShowTimestamps(bool value) {
    showTimestamps = value;
    notifyListeners();
  }

  void setDetailTimestamps(bool value) {
    detailTimestamps = value;
    notifyListeners();
  }

  void setDetailWidth(double value) {
    final next = value < minDetailWidth ? minDetailWidth : value;
    if (next == detailWidth) return;
    detailWidth = next;
    notifyListeners();
  }

  void setAutoDescribe(bool value) {
    autoDescribe = value;
    notifyListeners();
  }

  void zoomIn() => _setTextScale(textScale.value * 1.1);
  void zoomOut() => _setTextScale(textScale.value / 1.1);
  void zoomReset() => _setTextScale(1.0);

  void _setTextScale(double value) {
    // Snap near 1.0 so stepping in and out returns exactly to the default.
    var v = value.clamp(minTextScale, maxTextScale).toDouble();
    if ((v - 1.0).abs() < 0.02) v = 1.0;
    textScale.value = v;
  }

  /// Removes one row from the aggregate view.
  void deleteRow(String key) {
    if (!store.remove(key)) return;
    if (selectedGroup == key) {
      selectedGroup = null;
      selectedSeries = null;
    }
    notifyListeners();
  }

  // ---- saving the stream ----------------------------------------------------

  /// Writes the lines held in memory to [path]. Returns how many were written.
  Future<int> saveTranscript(String path, {bool timestamps = true}) async {
    final count = transcript.length;
    await File(path).writeAsString(transcript.export(timestamps: timestamps));
    _monitorEvent('Saved $count lines to $path', false);
    return count;
  }

  Future<void> startRecording(String path) async {
    await transcript.startRecording(path);
    _monitorEvent('Recording the serial stream to $path', false);
    notifyListeners();
  }

  Future<void> stopRecording() async {
    final path = transcript.recordingPath;
    final count = transcript.recordedLines;
    await transcript.stopRecording();
    if (path != null) _monitorEvent('Stopped recording: $count lines written to $path', false);
    notifyListeners();
  }

  void setClearOnBoot(bool value) {
    clearOnBoot = value;
    notifyListeners();
  }

  void clear() {
    store.clear(all: true);
    selectedGroup = null;
    selectedSeries = null;
    notifyListeners();
  }

  // ---- connection events and the upload hook --------------------------------

  void _onSessionEvent(String message, bool isError) => _monitorEvent(message, isError);

  void _monitorEvent(String message, bool isError) {
    store.record(
      key: monitorKey,
      tag: 'monitor',
      text: message,
      level: isError ? Level.warn : Level.info,
      time: _clock(),
      kind: GroupKind.monitor,
    );
  }

  String _handleControl(String command) {
    final parts = command.split(RegExp(r'\s+'));
    switch (parts.first.toLowerCase()) {
      case 'release':
        final seconds = parts.length > 1 ? int.tryParse(parts[1]) : null;
        final released = session.release(timeout: Duration(seconds: (seconds ?? 120).clamp(1, 3600).toInt()));
        return released ? 'ok released ${session.portName}' : 'ok idle';
      case 'resume':
        session.resume();
        return 'ok ${session.state.name}';
      case 'status':
        return 'ok ${session.state.name} ${session.portName ?? '-'}';
      default:
        return 'error unknown command';
    }
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    unawaited(transcript.stopRecording());
    textScale.dispose();
    _control.stop();
    session.dispose();
    store.dispose();
    super.dispose();
  }
}

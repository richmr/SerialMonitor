import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'line_assembler.dart';
import 'transport.dart';

enum LinkState {
  /// Not connected and not trying to be.
  idle,

  /// Port open, receiving.
  connected,

  /// The port went away (reset, re-flash, unplug) or is busy. Retrying.
  waiting,

  /// Port deliberately closed so another program (an upload) can use it.
  released,
}

/// Owns the serial connection: opens it, splits the bytes into lines, notices
/// when the device goes away and gets it back when it returns.
class SerialSession extends ChangeNotifier {
  SerialSession(
    this._transport, {
    required this.onLine,
    required this.onEvent,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SerialTransport _transport;

  /// Called for every complete line received.
  final void Function(String line) onLine;

  /// Called with connection events worth showing to the user.
  final void Function(String message, bool isError) onEvent;
  final DateTime Function() _clock;

  static const List<int> baudRates = <int>[9600, 19200, 38400, 57600, 74880, 115200, 230400, 460800, 921600];
  static const Duration pollInterval = Duration(milliseconds: 500);
  static const Duration partialLineTimeout = Duration(milliseconds: 250);

  // ESP32 defaults: 115200 8N1. DTR and RTS both asserted leaves the
  // auto-reset circuit idle and lets native-USB boards see a "terminal".
  List<PortInfo> ports = const <PortInfo>[];
  String? portName;
  int baud = 115200;
  bool dtr = true;
  bool rts = true;
  bool autoReconnect = true;
  String lineEnding = '\n';

  LinkState state = LinkState.idle;
  String? lastError;

  final LineAssembler _assembler = LineAssembler();
  StreamSubscription<Uint8List>? _subscription;
  Timer? _pollTimer;
  Timer? _partialTimer;
  DateTime? _releaseDeadline;

  /// Begins watching the port list. Call once.
  void start() {
    refreshPorts();
    _pollTimer ??= Timer.periodic(pollInterval, (_) => tick());
  }

  /// One step of the watchdog; runs every [pollInterval].
  void tick() {
    refreshPorts();
    final present = portName != null && ports.any((p) => p.name == portName);
    switch (state) {
      case LinkState.connected:
        if (!present) _lost('port disappeared');
      case LinkState.waiting:
        if (present) _tryOpen(announceFailure: false);
      case LinkState.released:
        final deadline = _releaseDeadline;
        if (deadline != null && !_clock().isBefore(deadline)) resume();
      case LinkState.idle:
        break;
    }
  }

  void refreshPorts() {
    List<PortInfo> next;
    try {
      next = List<PortInfo>.of(_transport.listPorts());
    } catch (_) {
      return;
    }
    next.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });
    final changed = next.length != ports.length ||
        Iterable<int>.generate(next.length).any((i) => next[i].name != ports[i].name);
    if (!changed) return;
    ports = next;
    if (portName == null) {
      for (final p in next) {
        if (p.isLikelyEsp32) {
          portName = p.name;
          break;
        }
      }
    }
    notifyListeners();
  }

  void selectPort(String? name) {
    if (name == portName) return;
    final wasActive = state == LinkState.connected || state == LinkState.waiting;
    if (wasActive) _close();
    portName = name;
    state = LinkState.idle;
    notifyListeners();
    if (wasActive && name != null) connect();
  }

  /// Applies changed [baud] / [dtr] / [rts] by reopening the port if it is open.
  void applySettings() {
    if (state == LinkState.connected) {
      _close();
      state = LinkState.waiting;
      _tryOpen(announceFailure: true);
    }
    notifyListeners();
  }

  void setAutoReconnect(bool value) {
    autoReconnect = value;
    notifyListeners();
  }

  void connect() {
    if (portName == null) return;
    _releaseDeadline = null;
    if (state == LinkState.connected) return;
    if (_tryOpen(announceFailure: true)) return;
    state = autoReconnect ? LinkState.waiting : LinkState.idle;
    notifyListeners();
  }

  void disconnect() {
    if (state == LinkState.idle) return;
    final wasConnected = state == LinkState.connected;
    _close();
    _releaseDeadline = null;
    state = LinkState.idle;
    if (wasConnected) onEvent('Disconnected from $portName', false);
    notifyListeners();
  }

  /// Closes the port so another program can use it, and stays out of the way
  /// until [resume] or until [timeout] has passed. Returns false when idle.
  bool release({Duration? timeout}) {
    if (state == LinkState.idle) return false;
    if (state == LinkState.connected) _close();
    _releaseDeadline = timeout == null ? null : _clock().add(timeout);
    if (state != LinkState.released) {
      state = LinkState.released;
      onEvent('Released $portName for upload', false);
    }
    notifyListeners();
    return true;
  }

  /// Takes the port back after [release]. Retries until it opens.
  void resume() {
    if (state != LinkState.released) return;
    _releaseDeadline = null;
    state = LinkState.waiting;
    if (!_tryOpen(announceFailure: false)) notifyListeners();
  }

  /// Sends [text] plus the configured line ending. False if not connected.
  bool send(String text) {
    if (state != LinkState.connected) return false;
    try {
      _transport.write(Uint8List.fromList(utf8.encode(text + lineEnding)));
      return true;
    } catch (e) {
      _lost('write failed: $e');
      return false;
    }
  }

  /// Pulses the ESP32 auto-reset circuit (EN low via RTS) to restart the board.
  Future<void> resetDevice() async {
    if (state != LinkState.connected) return;
    try {
      _transport.setLines(dtr: false, rts: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (state != LinkState.connected) return;
      _transport.setLines(dtr: false, rts: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (state != LinkState.connected) return;
      _transport.setLines(dtr: dtr, rts: rts);
      onEvent('Reset pulse sent', false);
    } catch (e) {
      onEvent('Reset failed: $e', true);
    }
  }

  bool _tryOpen({required bool announceFailure}) {
    final name = portName;
    if (name == null) return false;
    try {
      final stream = _transport.open(name, PortSettings(baud: baud, dtr: dtr, rts: rts));
      _assembler.reset();
      _subscription = stream.listen(
        _onData,
        onError: (Object e) => _lost('read error: $e'),
        onDone: () => _lost('port closed'),
      );
      lastError = null;
      state = LinkState.connected;
      onEvent('Connected to $name at $baud baud', false);
      notifyListeners();
      return true;
    } catch (e) {
      final message = '$e';
      final isNew = message != lastError;
      lastError = message;
      if (announceFailure) onEvent('Could not open $name: $message', true);
      if (isNew) notifyListeners();
      return false;
    }
  }

  void _lost(String reason) {
    if (state != LinkState.connected) return;
    _close();
    lastError = reason;
    if (autoReconnect) {
      state = LinkState.waiting;
      onEvent('Lost $portName ($reason). Waiting for it to come back', true);
    } else {
      state = LinkState.idle;
      onEvent('Lost $portName ($reason)', true);
    }
    notifyListeners();
  }

  void _close() {
    _partialTimer?.cancel();
    _partialTimer = null;
    final tail = _assembler.flush();
    if (tail != null) onLine(tail);
    final sub = _subscription;
    _subscription = null;
    if (sub != null) unawaited(sub.cancel());
    _transport.close();
  }

  void _onData(Uint8List bytes) {
    for (final line in _assembler.add(bytes)) {
      onLine(line);
    }
    _partialTimer?.cancel();
    _partialTimer = null;
    if (_assembler.hasPartial) {
      // Text without a newline (a prompt, a half-written line): show it
      // after a short pause rather than waiting for a newline forever.
      _partialTimer = Timer(partialLineTimeout, () {
        _partialTimer = null;
        final tail = _assembler.flush();
        if (tail != null) onLine(tail);
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _close();
    super.dispose();
  }
}

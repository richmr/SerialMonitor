import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serial_monitor/app_controller.dart';
import 'package:serial_monitor/model/message_store.dart';
import 'package:serial_monitor/serial/session.dart';
import 'package:serial_monitor/serial/transport.dart';

/// A scriptable stand-in for the serial backend.
class FakeTransport implements SerialTransport {
  List<String> present = <String>['COM7'];
  bool busy = false;
  StreamController<Uint8List>? device;
  int opens = 0;
  int closes = 0;
  final List<String> written = <String>[];
  final List<String> lines = <String>[];

  bool get isOpen => device != null;

  @override
  List<PortInfo> listPorts() => <PortInfo>[for (final n in present) PortInfo(name: n, vendorId: 0x10C4)];

  @override
  Stream<Uint8List> open(String name, PortSettings settings) {
    if (busy || !present.contains(name)) throw const SerialOpenException('port busy');
    opens++;
    final controller = StreamController<Uint8List>(sync: true);
    device = controller;
    return controller.stream;
  }

  @override
  void write(Uint8List data) => written.add(utf8.decode(data));

  @override
  void setLines({required bool dtr, required bool rts}) => lines.add('dtr=$dtr rts=$rts');

  @override
  void close() {
    if (device != null) closes++;
    device = null;
  }

  void emit(String text) => device!.add(Uint8List.fromList(utf8.encode(text)));
}

void main() {
  late FakeTransport transport;
  late List<String> received;
  late List<String> events;
  late DateTime now;
  late SerialSession session;

  setUp(() {
    transport = FakeTransport();
    received = <String>[];
    events = <String>[];
    now = DateTime(2026, 11, 14, 9);
    session = SerialSession(
      transport,
      onLine: received.add,
      onEvent: (message, isError) => events.add(message),
      clock: () => now,
    );
    session.refreshPorts();
  });

  tearDown(() => session.dispose());

  test('picks the ESP32-looking port and uses ESP32 defaults', () {
    expect(session.portName, 'COM7');
    expect(session.baud, 115200);
    expect(session.state, LinkState.idle);
  });

  test('connect, receive lines, send with line ending', () {
    session.connect();
    expect(session.state, LinkState.connected);
    transport.emit('[a] 1\r\n[b] 2\n');
    expect(received, <String>['[a] 1', '[b] 2']);
    expect(session.send('led on'), isTrue);
    expect(transport.written, <String>['led on\n']);
  });

  test('re-flash on a native-USB board: port vanishes, then comes back', () {
    session.connect();
    transport.present = <String>[];
    session.tick();
    expect(session.state, LinkState.waiting);
    expect(transport.isOpen, isFalse);
    expect(session.send('x'), isFalse);

    session.tick(); // still gone
    expect(session.state, LinkState.waiting);

    transport.present = <String>['COM7'];
    session.tick();
    expect(session.state, LinkState.connected);
    expect(transport.opens, 2);
    transport.emit('[boot] ok\n');
    expect(received, <String>['[boot] ok']);
  });

  test('read error drops to waiting and retries while the port is busy', () {
    session.connect();
    transport.busy = true;
    transport.device!.addError(StateError('device removed'));
    expect(session.state, LinkState.waiting);

    session.tick(); // busy: uploader has it
    expect(session.state, LinkState.waiting);

    transport.busy = false;
    session.tick();
    expect(session.state, LinkState.connected);
  });

  test('without auto-reconnect a lost port goes idle', () {
    session.setAutoReconnect(false);
    session.connect();
    transport.present = <String>[];
    session.tick();
    expect(session.state, LinkState.idle);
  });

  test('release frees the port until resume', () {
    session.connect();
    expect(session.release(timeout: const Duration(seconds: 120)), isTrue);
    expect(session.state, LinkState.released);
    expect(transport.isOpen, isFalse);

    session.tick(); // must not grab the port back mid-upload
    expect(session.state, LinkState.released);
    expect(transport.opens, 1);

    session.resume();
    expect(session.state, LinkState.connected);
    expect(transport.opens, 2);
  });

  test('release times out if resume never arrives', () {
    session.connect();
    session.release(timeout: const Duration(seconds: 120));
    now = now.add(const Duration(seconds: 119));
    session.tick();
    expect(session.state, LinkState.released);
    now = now.add(const Duration(seconds: 2));
    session.tick();
    expect(session.state, LinkState.connected);
  });

  test('release while idle is a no-op', () {
    expect(session.release(), isFalse);
    expect(session.state, LinkState.idle);
  });

  test('disconnect stops reconnecting', () {
    session.connect();
    session.disconnect();
    session.tick();
    expect(session.state, LinkState.idle);
    expect(transport.opens, 1);
  });

  group('AppController', () {
    late AppController app;

    setUp(() {
      app = AppController(
        transport,
        clock: () => now,
        store: MessageStore(notifyInterval: Duration.zero),
      );
      app.session.refreshPorts();
      app.session.connect();
    });

    tearDown(() => app.dispose());

    test('device-declared commands fill the picker and are not shown as rows', () {
      transport.emit('[!hello] smp=1 name="Bench" fw="0.3"\n');
      transport.emit('[!cmd] name=led args="<on|off>" desc="Switch the LED"\n');
      expect(app.deviceName, 'Bench');
      expect(app.commands.single.usage, 'led <on|off>');
      expect(app.store.group('t:!cmd'), isNull);
      expect(app.store.group('t:!hello'), isNotNull);
      expect(app.store.bootCount, 1);
    });

    test('a hello that answers "?" is not a restart', () {
      transport.emit('[!hello] smp=1 name="Bench"\n[!cmd] name=led\n');
      now = now.add(const Duration(seconds: 30));
      expect(app.send('?'), isTrue);
      now = now.add(const Duration(milliseconds: 200));
      transport.emit('[!hello] smp=1 name="Bench"\n[!cmd] name=led\n');
      expect(app.store.bootCount, 1);
      expect(app.commands.length, 1);
    });

    test('sent commands are logged and remembered', () {
      app.send('led on');
      app.send('led off');
      app.send('led on');
      expect(transport.written, <String>['led on\n', 'led off\n', 'led on\n']);
      expect(app.history, <String>['led on', 'led off']);
      expect(app.store.group(AppController.sentKey)!.count, 3);
    });

    test('ROM banner marks a restart and can clear old rows', () {
      transport.emit('[old] 1\n');
      app.setClearOnBoot(true);
      now = now.add(const Duration(seconds: 5));
      transport.emit('rst:0x1 (POWERON_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)\n');
      expect(app.store.bootCount, 1);
      expect(app.store.group('t:old'), isNull);
    });

    test('protocol file commands merge with device commands', () {
      transport.emit('[!cmd] name=led\n');
      final error = app.loadProtocol('bench.smp.json', '{"commands":[{"name":"led"},{"name":"move"}]}');
      expect(error, isNull);
      expect(app.commands.map((c) => c.name), <String>['led', 'move']);
      expect(app.loadProtocol('bad.json', 'nope'), isNotNull);
    });
  });
}

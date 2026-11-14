import 'package:flutter_test/flutter_test.dart';
import 'package:serial_monitor/model/message_store.dart';
import 'package:serial_monitor/protocol/parser.dart';
import 'package:serial_monitor/serial/line_assembler.dart';

void main() {
  final t0 = DateTime(2026, 11, 14, 9);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  MessageStore newStore({int maxGroups = 500}) =>
      MessageStore(notifyInterval: Duration.zero, maxLogPerGroup: 3, maxPointsPerSeries: 3, maxGroups: maxGroups);

  test('same kind of line updates one row in place', () {
    final store = newStore();
    store.addLine(parseLine('[env] temp=20.0C')!, at(0));
    store.addLine(parseLine('heartbeat')!, at(1));
    store.addLine(parseLine('[env] temp=21.5C')!, at(2));

    expect(store.groupCount, 2);
    final env = store.groups.first; // first-seen order
    expect(env.tag, 'env');
    expect(env.count, 2);
    expect(env.text, 'temp=21.5C');
    expect(env.firstSeen, at(0));
    expect(env.lastSeen, at(2));
    expect(env.series['temp']!.last, 21.5);
    expect(env.series['temp']!.unit, 'C');
  });

  test('identical lines count up', () {
    final store = newStore();
    for (var i = 0; i < 4; i++) {
      store.addLine(parseLine('heartbeat')!, at(i));
    }
    final g = store.groups.single;
    expect(g.count, 4);
    expect(g.repeat, 4);
    expect(g.text, 'heartbeat');
  });

  test('history is bounded', () {
    final store = newStore();
    for (var i = 0; i < 10; i++) {
      store.addLine(parseLine('[n] v=$i')!, at(i));
    }
    final g = store.groups.single;
    expect(g.count, 10);
    expect(g.log.map((e) => e.text), <String>['v=7', 'v=8', 'v=9']);
    expect(g.series['v']!.points.map((p) => p.value), <double>[7, 8, 9]);
  });

  test('restart marks older rows stale, and nearby restarts are one boot', () {
    final store = newStore();
    store.addLine(parseLine('[old] x=1')!, at(0));
    expect(store.markBoot(at(10)), isTrue);
    expect(store.markBoot(at(11)), isFalse);
    store.addLine(parseLine('[new] x=1')!, at(12));

    expect(store.bootCount, 1);
    expect(store.isStale(store.group('t:old')!), isTrue);
    expect(store.isStale(store.group('t:new')!), isFalse);
  });

  test('noise cannot create rows without limit', () {
    final store = newStore(maxGroups: 2);
    store.addLine(parseLine('alpha')!, at(0));
    store.addLine(parseLine('beta')!, at(1));
    store.addLine(parseLine('gamma')!, at(2));
    store.addLine(parseLine('delta')!, at(3));
    store.addLine(parseLine('alpha')!, at(4));

    expect(store.groupCount, 3);
    expect(store.group(MessageStore.overflowKey)!.count, 2);
    expect(store.group('p:alpha')!.count, 2);
  });

  test('clear keeps sent and monitor rows unless asked', () {
    final store = newStore();
    store.addLine(parseLine('[a] 1')!, at(0));
    store.record(key: 'sent', tag: 'sent', text: 'led on', time: at(1), kind: GroupKind.sent);
    store.clear();
    expect(store.groups.map((g) => g.key), <String>['sent']);
    store.clear(all: true);
    expect(store.groupCount, 0);
  });

  group('LineAssembler', () {
    test('joins chunks, strips CR, keeps partial text', () {
      final a = LineAssembler();
      expect(a.add('hel'.codeUnits), isEmpty);
      expect(a.add('lo\r\nwor'.codeUnits), <String>['hello']);
      expect(a.hasPartial, isTrue);
      expect(a.flush(), 'wor');
      expect(a.flush(), isNull);
    });

    test('a multi-byte character split across chunks survives', () {
      final a = LineAssembler();
      final bytes = <int>[0x74, 0x3D, 0x32, 0x33, 0xC2, 0xB0, 0x0A]; // "t=23°\n"
      expect(a.add(bytes.sublist(0, 5)), isEmpty);
      expect(a.add(bytes.sublist(5)), <String>['t=23°']);
    });

    test('overlong lines are emitted in pieces', () {
      final a = LineAssembler(maxLineBytes: 4);
      expect(a.add('abcdefghij\n'.codeUnits), <String>['abcd', 'efgh', 'ij']);
    });
  });
}

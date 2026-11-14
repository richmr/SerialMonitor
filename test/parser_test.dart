import 'package:flutter_test/flutter_test.dart';
import 'package:serial_monitor/protocol/parser.dart';
import 'package:serial_monitor/protocol/protocol_doc.dart';

List<String> _numbers(ParsedLine p) => <String>[for (final n in p.numbers) n.toString()];

void main() {
  group('SMP lines', () {
    test('tag, named values and units', () {
      final p = parseLine('[env] temp=23.5C hum=41%')!;
      expect(p.kind, LineKind.smp);
      expect(p.tag, 'env');
      expect(p.level, Level.none);
      expect(p.body, 'temp=23.5C hum=41%');
      expect(p.groupKey, 't:env');
      expect(_numbers(p), <String>['temp=23.5C', 'hum=41.0%']);
    });

    test('level suffix and negative value', () {
      final p = parseLine('[motor/x:W] stall detected pos=-1200')!;
      expect(p.tag, 'motor/x');
      expect(p.level, Level.warn);
      expect(_numbers(p), <String>['pos=-1200.0']);
    });

    test('same tag shares a row whatever the body says', () {
      expect(parseLine('[wifi] connecting')!.groupKey, parseLine('[wifi] got ip 10.0.0.5')!.groupKey);
    });

    test('unnamed values are named by position', () {
      expect(_numbers(parseLine('[imu] 0.02 -0.98 0.11')!), <String>['#1=0.02', '#2=-0.98', '#3=0.11']);
    });

    test('meta lines carry no graph values and parse as key/values', () {
      final p = parseLine(r'[!cmd] name=move args="<steps> [speed]" desc="Move the \"big\" stepper"')!;
      expect(p.isMeta, isTrue);
      expect(p.numbers, isEmpty);
      final f = parseKeyValues(p.body);
      expect(f['name'], 'move');
      expect(f['args'], '<steps> [speed]');
      expect(f['desc'], 'Move the "big" stepper');
      final spec = CommandSpec.fromFields(f)!;
      expect(spec.usage, 'move <steps> [speed]');
      expect(spec.insertText, 'move ');
    });

    test('a bracketed number is not a tag', () {
      expect(parseLine('[1234567] not a tag')!.kind, LineKind.plain);
    });
  });

  group('ESP32 log formats', () {
    test('ESP-IDF, with colour codes stripped', () {
      final p = parseLine('\x1B[0;32mI (523) wifi: connected ip=10.0.0.5 ch=6\x1B[0m')!;
      expect(p.kind, LineKind.espIdf);
      expect(p.tag, 'wifi');
      expect(p.level, Level.info);
      expect(p.body, 'connected ip=10.0.0.5 ch=6');
      expect(p.groupKey, 'i:wifi:connected ip=# ch=#');
      expect(_numbers(p), <String>['ch=6.0']);
    });

    test('arduino-esp32 log groups by file and line', () {
      final p = parseLine('[  1234][W][main.cpp:42] loop(): slow frame 18 ms')!;
      expect(p.kind, LineKind.arduinoLog);
      expect(p.tag, 'main.cpp:42');
      expect(p.level, Level.warn);
      expect(p.groupKey, 'a:main.cpp:42');
      expect(_numbers(p), <String>['#1=18.0']);
    });

    test('ROM boot banner is recognised', () {
      expect(isRomBootLine('rst:0x1 (POWERON_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)'), isTrue);
      expect(isRomBootLine('ESP-ROM:esp32s3-20210327'), isTrue);
      expect(isRomBootLine('[env] temp=1'), isFalse);
    });
  });

  group('plain lines', () {
    test('lines that differ only in numbers share a row', () {
      final a = parseLine('Temp: 23.5 C, Hum: 40 %')!;
      final b = parseLine('Temp: 23.7 C, Hum: 41 %')!;
      expect(a.kind, LineKind.plain);
      expect(a.groupKey, b.groupKey);
      expect(_numbers(a), <String>['Temp=23.5', 'Hum=40.0']);
    });

    test('numbers glued to words stay text', () {
      final p = parseLine('ESP32 v1.2 ready')!;
      expect(p.groupKey, 'p:ESP32 v1.2 ready');
      expect(p.numbers, isEmpty);
    });

    test('MAC addresses and hex blobs are not values', () {
      expect(_numbers(parseLine('mac aa:bb:cc:11:22:33 rssi -67')!), <String>['#1=-67.0']);
      expect(parseLine('id deadbeef01 ok')!.numbers, isEmpty);
      expect(parseLine('id deadbeef01 ok')!.groupKey, parseLine('id 0badcafe77 ok')!.groupKey);
    });

    test('0x values are read as hex', () {
      expect(_numbers(parseLine('addr 0x10 len 16')!), <String>['#1=16.0', '#2=16.0']);
    });

    test('repeated names are kept apart', () {
      expect(_numbers(parseLine('a=1 a=2')!), <String>['a=1.0', 'a#2=2.0']);
    });

    test('blank lines are dropped', () {
      expect(parseLine(''), isNull);
      expect(parseLine('   \r'), isNull);
    });
  });

  test('protocol file', () {
    final doc = ProtocolDoc.fromJson(
      '{"smp":1,"name":"Bench","commands":['
      '{"name":"move","args":"<steps>","desc":"Move","example":"move 200"},'
      '{"name":"stop"},{"oops":true}]}',
    );
    expect(doc.name, 'Bench');
    expect(doc.commands.map((c) => c.name), <String>['move', 'stop']);
    expect(doc.commands.first.insertText, 'move 200');
    expect(doc.commands.last.insertText, 'stop');
    expect(() => ProtocolDoc.fromJson('[1,2]'), throwsFormatException);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:serial_monitor/app_controller.dart';
import 'package:serial_monitor/model/message_store.dart';
import 'package:serial_monitor/model/plot.dart';
import 'package:serial_monitor/ui/plot_chart.dart';

import 'session_test.dart' show FakeTransport;

void main() {
  final t0 = DateTime(2026, 11, 25, 9);
  DateTime at(num seconds) => t0.add(Duration(milliseconds: (seconds * 1000).round()));

  group('PointBuffer', () {
    test('grows, then drops the oldest points once full', () {
      final b = PointBuffer(100);
      for (var i = 0; i < 250; i++) {
        b.add(i, i.toDouble());
      }
      expect(b.length, 100);
      expect(b.timeAt(0), 150);
      expect(b.valueAt(99), 249);
      expect(b.map((p) => p.value).take(2), <double>[150, 151]);
      expect(b.tail(3).map((p) => p.value), <double>[247, 248, 249]);
    });

    test('lowerBound finds the first point at or after a time, across the wrap', () {
      final b = PointBuffer(8);
      for (var i = 0; i < 12; i++) {
        b.add(i * 10, i.toDouble()); // holds 40..110
      }
      expect(b.lowerBound(0), 0);
      expect(b.lowerBound(40), 0);
      expect(b.lowerBound(41), 1);
      expect(b.lowerBound(75), 4);
      expect(b.timeAt(b.lowerBound(75)), 80);
      expect(b.lowerBound(1000), b.length);
    });
  });

  group('PlotModel view', () {
    late PlotModel plot;
    setUp(() => plot = PlotModel());

    test('presets keep the right edge; live follows now', () {
      expect(plot.live, isTrue);
      expect(plot.viewEnd(at(100)), at(100));
      plot.scrollTo(at(50), at(100));
      expect(plot.live, isFalse);
      plot.setSpan(const Duration(minutes: 5), at(120));
      expect(plot.viewSpan, const Duration(minutes: 5));
      expect(plot.viewEnd(at(500)), at(50), reason: 'new data does not move a paused view');
    });

    test('paging moves by the window length and reaching now goes live', () {
      plot.setSpan(const Duration(seconds: 10), at(100));
      plot.pan(-1, at(100));
      expect(plot.viewEnd(at(100)), at(90));
      plot.pan(-1, at(100));
      expect(plot.viewEnd(at(100)), at(80));
      plot.pan(1, at(100));
      plot.pan(1, at(100));
      expect(plot.live, isTrue);
    });

    test('zoom, back to the previous view, back to real time', () {
      plot.setSpan(const Duration(minutes: 1), at(100));
      plot.zoomTo(at(60), at(64));
      expect(plot.zoomed, isTrue);
      expect(plot.live, isFalse);
      expect(plot.viewSpan, const Duration(seconds: 4));
      plot.zoomTo(at(61), at(62));
      expect(plot.viewSpan, const Duration(seconds: 1));

      plot.goBack();
      expect(plot.viewSpan, const Duration(seconds: 4));
      expect(plot.viewEnd(at(200)), at(64));

      plot.goLive();
      expect(plot.live, isTrue);
      expect(plot.zoomed, isFalse);
      expect(plot.viewSpan, const Duration(minutes: 1));

      plot.goBack();
      expect(plot.viewSpan, const Duration(seconds: 4), reason: '"live" can be undone too');
    });

    test('colors stay with their trace and are reused only once freed', () {
      final a = plot.add('t:a', 'x', label: 'a.x')!;
      final b = plot.add('t:b', 'x', label: 'b.x')!;
      plot.remove(a);
      final c = plot.add('t:c', 'x', label: 'c.x')!;
      expect(b.colorSlot, 1);
      expect(c.colorSlot, 0);
      for (var i = 0; i < 10; i++) {
        plot.add('t:n$i', 'x', label: 'n');
      }
      expect(plot.traces, hasLength(PlotModel.maxTraces));
      expect(plot.add('t:more', 'x', label: 'more'), isNull);
    });
  });

  group('AppController plot', () {
    late Directory dir;
    late AppController app;
    late DateTime now;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('plot_test');
      now = t0;
      app = AppController(
        FakeTransport(),
        clock: () => now,
        store: MessageStore(notifyInterval: Duration.zero),
        plotSettings: PlotSettingsStore(File('${dir.path}/plots.json')),
      );
    });

    tearDown(() {
      app.dispose();
      dir.deleteSync(recursive: true);
    });

    void feed(String line, {int times = 5}) {
      for (var i = 0; i < times; i++) {
        app.handleLine(line);
        now = now.add(const Duration(milliseconds: 100));
      }
    }

    test('values that fit share the left scale; different units or ranges get the right one', () {
      feed('[env] temp=21.5C hum=40%');
      feed('[env] temp=22.5C hum=41%');
      feed('[env2] temp=23.0C');
      feed('[power] mv=3300 ma=0.2');
      feed('[power] mv=3310 ma=0.25');

      expect(app.plotSeries('t:env', 'temp'), isTrue);
      expect(app.plot.open, isTrue);
      app.plotSeries('t:env2', 'temp');
      app.plotSeries('t:env', 'hum');
      app.plotSeries('t:power', 'mv');
      final axes = <String, PlotAxis>{for (final t in app.plot.traces) t.label: t.axis};
      expect(axes, <String, PlotAxis>{
        'env.temp': PlotAxis.left,
        'env2.temp': PlotAxis.left, // same unit
        'env.hum': PlotAxis.right, // different unit
        'power.mv': PlotAxis.right, // unitless but 3300 vs ~22
      });
      expect(app.plot.traces.first.label, 'env.temp');
    });

    test('a saved plot comes back when the same device says hello', () {
      app.handleLine('[!hello] smp=1 name="Bench"');
      feed('[env] temp=21.5C');
      app.plotSeries('t:env', 'temp');
      app.plot.setSpan(const Duration(minutes: 5), app.now());
      expect(app.savePlot(), isNull);

      app.plot.remove(app.plot.traces.single);
      app.plot.setOpen(false);
      now = now.add(const Duration(minutes: 1));
      app.handleLine('[!hello] smp=1 name="Other"');
      expect(app.plot.traces, isEmpty);
      app.handleLine('[!hello] smp=1 name="Bench"');
      expect(app.plot.traces.single.label, 'env.temp');
      expect(app.plot.span, const Duration(minutes: 5));
      expect(app.plot.open, isTrue);
    });

    test('a plot being built is not replaced by a saved one', () {
      app.handleLine('[!hello] smp=1 name="Bench"');
      feed('[env] temp=21.5C hum=3%');
      app.plotSeries('t:env', 'temp');
      app.savePlot();
      app.handleLine('[!hello] smp=1 name="Other"');
      app.plot.remove(app.plot.traces.single);
      app.plotSeries('t:env', 'hum');
      app.handleLine('[!hello] smp=1 name="Bench"');
      expect(app.plot.traces.single.label, 'env.hum');
    });

    test('saving needs a device name', () {
      feed('[env] temp=21.5C');
      app.plotSeries('t:env', 'temp');
      expect(app.canSavePlot, isFalse);
      expect(app.savePlot(), isNotNull);
    });
  });

  test('axis steps are 1, 2 or 5 times a power of ten', () {
    expect(niceStep(10, 5), 2);
    expect(niceStep(0.37, 4), 0.1);
    expect(niceStep(3300, 6), 500);
    expect(timeStep(10000000, 5), 2000000);
    expect(timeStep(1200000000, 6), 300000000);
  });
}

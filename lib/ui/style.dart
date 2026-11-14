import 'package:flutter/material.dart';

import '../protocol/parser.dart';

const Color kBackground = Color(0xFF14171C);
const Color kSurface = Color(0xFF1C2027);
const Color kDivider = Color(0xFF2B313B);
const Color kText = Color(0xFFD7DCE3);
const Color kMuted = Color(0xFF8A93A1);
const Color kAccent = Color(0xFF4FB3D9);

/// Monospace text for anything that came off the wire.
const TextStyle kMono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: <String>['Consolas', 'Cascadia Mono', 'Courier New', 'monospace'],
  fontSize: 13,
  height: 1.25,
  color: kText,
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
    dividerColor: kDivider,
    visualDensity: VisualDensity.compact,
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 350)),
  );
}

Color levelColor(Level level) {
  switch (level) {
    case Level.error:
      return const Color(0xFFEF6B6B);
    case Level.warn:
      return const Color(0xFFE5B84B);
    case Level.info:
      return const Color(0xFF6CC27A);
    case Level.debug:
    case Level.verbose:
      return kMuted;
    case Level.none:
      return kAccent;
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 14:03:27.512
String formatTime(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';

/// Compact number: integers without a decimal point, others to 6 significant digits.
String formatNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toStringAsFixed(0);
  var s = v.toStringAsPrecision(6);
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

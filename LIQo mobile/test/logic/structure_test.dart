// The rules of the code base: colour values only in core/theme.dart, colours
// that blend when the theme morphs, a pure-Dart engine, and plain wording only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> dartFiles(String dir) => Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
String rel(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('colour values live only in lib/core/theme.dart', () {
    final colour = RegExp(r'\bColors\.|Color\(0x|Color\.fromRGBO|Color\.fromARGB');
    final offenders = [
      for (final f in dartFiles('lib'))
        if (!rel(f).endsWith('lib/core/theme.dart'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (colour.hasMatch(line)) '${rel(f)}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no colour is chosen with p.dark ? a : b (use pick / mix, so the theme morphs)', () {
    final offenders = [
      for (final f in dartFiles('lib'))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (RegExp(r'\b(p|pal|m|mapPal)\.dark \?').hasMatch(line)) '${rel(f)}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the routing engine is pure Dart: no Flutter, no app code', () {
    final offenders = [
      for (final f in dartFiles('lib/core/engine'))
        for (final line in f.readAsLinesSync())
          if (line.startsWith('import ') && !RegExp(r'''^import '(dart:[a-z]+|package:collection/collection\.dart|(\.\./)?[a-z_/]+\.dart)'( (as|show) .+)?;$''').hasMatch(line)) '${rel(f)}: $line'
          else if (line.startsWith('import ') && line.contains('features/')) '${rel(f)}: $line',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('wording is plain only: tr() takes one phrase (no technical wording)', () {
    final offenders = [
      for (final f in dartFiles('lib'))
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (RegExp(r'''\b(T|tr)\(\s*'[^']*'\s*,\s*'[^']*'\s*\)''').hasMatch(line)) '${rel(f)}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no message bar: user messages go through the shared toast', () {
    final offenders = [
      for (final f in dartFiles('lib'))
        if (f.readAsStringSync().contains('ScaffoldMessenger')) rel(f),
    ];
    expect(offenders, isEmpty);
  });

  test('no left-overs of the removed features (voice, QR codes, parking spot, the demo panel, the Gabay name)', () {
    // the Gabay name inside text the app shows (the pubspec may name the Gabay/app project in a comment)
    final gone = RegExp(r'''speech_to_text|mobile_scanner|audioplayers|gabay://|gabay/haptics|gabay/voice|faaah|demoOpen|findcar|['"]Gabay''');
    final offenders = [
      for (final f in [...dartFiles('lib'), File('pubspec.yaml')])
        for (final (i, line) in f.readAsLinesSync().indexed)
          if (gone.hasMatch(line)) '${rel(f)}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

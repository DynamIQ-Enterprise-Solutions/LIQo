// Platform settings (owner decisions 2026-10-23): two columns, AI floor-plan
// reading on the left, and one card on the right with Sign-in & security then
// General (announcements and any other setting); numbers with − / + and
// their unit; 3 tiles across on wide screens, 2 on medium, 1 on narrow; one
// save bar that appears only when something changed.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/settings/settings_view.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

/// The fake API, with an extra setting the page does not know yet.
class _WithExtra extends FakeApiAdapter {
  _WithExtra() : super(role: 'superadmin');

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.path == '/settings' && options.method == 'GET') {
      return ResponseBody.fromString(
        '{"settings":{"min_password_length":8,"ai_file_size_mb":20,"default_announcement_days":7,"session_timeout_hours":8,"max_login_attempts":5,"export_rows":500},'
        '"rules":{"min_password_length":{"min":6,"max":64,"label":"Minimum password length"},"ai_file_size_mb":{"min":1,"max":50,"label":"AI file size limit (MB)"},'
        '"default_announcement_days":{"min":1,"max":365,"label":"Default announcement duration (days)"},"session_timeout_hours":{"min":1,"max":72,"label":"Session timeout (hours)"},'
        '"max_login_attempts":{"min":3,"max":20,"label":"Max failed sign-ins before lockout"},"export_rows":{"min":10,"max":5000,"label":"Rows per export"}}}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<FakeApiAdapter> _page(WidgetTester tester, {double width = 1200, FakeApiAdapter? fake}) async {
  tester.view.physicalSize = Size(width + 100, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final f = fake ?? FakeApiAdapter(role: 'superadmin');
  ApiClient.instance.dio.httpClientAdapter = f;
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(sp)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: const SettingsView())))),
    ),
  ));
  await _steps(tester);
  return f;
}

Future<void> _leave(WidgetTester tester) async {
  await _steps(tester, 40);
  await tester.pumpWidget(const SizedBox());
  await _steps(tester, 3);
}

Finder _box(String key) => find.descendant(of: find.byKey(ValueKey('setting-$key')), matching: find.byType(TextField));

String _boxText(WidgetTester tester, String key) => tester.widget<TextField>(_box(key)).controller!.text;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _steps(tester, 2);
}

void main() {
  testWidgets('three topic tiles hold the settings, each with its unit', (tester) async {
    await _page(tester);
    for (final (tile, keys) in [
      ('tile-security', ['min_password_length', 'session_timeout_hours', 'max_login_attempts']),
      ('tile-ai', ['ai_file_size_mb', 'ai_start_credits', 'ai_credit_cap']),
      ('tile-general', ['default_announcement_days']),
    ]) {
      for (final k in keys) {
        expect(find.descendant(of: find.byKey(ValueKey(tile)), matching: find.byKey(ValueKey('setting-$k'))), findsOneWidget, reason: '$k in $tile');
      }
    }
    for (final unit in ['characters', 'hours', 'tries', 'days', 'MB']) {
      expect(find.text(unit), findsOneWidget);
    }
    expect(find.text('credits'), findsNWidgets(2), reason: 'starting credits and the cap');
    expect(find.text('Password length'), findsOneWidget);
    expect(find.textContaining('6–64'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-save-bar')), findsNothing, reason: 'nothing changed yet');
    await _leave(tester);
  });

  testWidgets('wide: AI reading on the left; security above General in one card on the right', (tester) async {
    await _page(tester, width: 1400);
    final ai = tester.getRect(find.byKey(const ValueKey('tile-ai')));
    final card = tester.getRect(find.byKey(const ValueKey('tile-rules')));
    final security = tester.getRect(find.byKey(const ValueKey('tile-security')));
    final general = tester.getRect(find.byKey(const ValueKey('tile-general')));
    expect(ai.top, card.top);
    expect(ai.left, lessThan(card.left));
    expect(ai.width, lessThanOrEqualTo(560));
    expect(general.top, greaterThan(security.top));
    expect(card.contains(general.center), isTrue, reason: 'one card');
    await _leave(tester);
  });

  testWidgets('medium: two across; narrow: one column, AI reading first', (tester) async {
    expect(settingsColumns(1400), 2);
    expect(settingsColumns(800), 2);
    expect(settingsColumns(700), 1);
    await _page(tester, width: 500);
    final a = tester.getRect(find.byKey(const ValueKey('tile-ai')));
    final b = tester.getRect(find.byKey(const ValueKey('tile-rules')));
    expect(b.top, greaterThan(a.bottom));
    expect(a.width, closeTo(500, 1));
    await _leave(tester);
  });

  testWidgets('− and + step by one and stop at the ends', (tester) async {
    await _page(tester);
    await _tap(tester, find.byKey(const ValueKey('max_login_attempts-up')));
    expect(_boxText(tester, 'max_login_attempts'), '6');
    expect(find.byKey(const ValueKey('max_login_attempts-changed')), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await _tap(tester, find.byKey(const ValueKey('max_login_attempts-down')));
    }
    expect(_boxText(tester, 'max_login_attempts'), '3', reason: 'the lowest allowed');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('max_login_attempts-down'))).onPressed, isNull);
    await _leave(tester);
  });

  testWidgets('a typed number out of range is refused with the range, and nothing is sent', (tester) async {
    final fake = await _page(tester);
    await tester.enterText(_box('min_password_length'), '3');
    await _steps(tester, 2);
    await _tap(tester, find.byKey(const ValueKey('settings-save')));
    expect(find.text('Password length must be at least 6.'), findsOneWidget);
    expect(fake.writes.where((w) => w.$2 == '/settings'), isEmpty);
    await _leave(tester);
  });

  testWidgets('the save bar counts changes; Discard puts the numbers back', (tester) async {
    await _page(tester);
    await _tap(tester, find.byKey(const ValueKey('session_timeout_hours-up')));
    await _tap(tester, find.byKey(const ValueKey('default_announcement_days-down')));
    expect(find.text('2 changes not saved yet'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('settings-discard')));
    expect(find.byKey(const ValueKey('settings-save-bar')), findsNothing);
    expect(_boxText(tester, 'session_timeout_hours'), '8');
    expect(_boxText(tester, 'default_announcement_days'), '7');
    await _leave(tester);
  });

  testWidgets('Save sends the numbers, and the model when it changed', (tester) async {
    final fake = await _page(tester);
    await _tap(tester, find.byKey(const ValueKey('session_timeout_hours-up')));
    await tester.tap(find.byKey(const ValueKey('ai-model-field')));
    await _steps(tester, 4);
    await tester.tap(find.text('GPT-4o · openai').last);
    await _steps(tester, 4);
    expect(find.text('2 changes not saved yet'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('settings-save')));
    await _steps(tester, 4);
    final put = fake.writes.lastWhere((w) => w.$1 == 'PUT' && w.$2 == '/settings');
    expect((put.$3 as Map)['session_timeout_hours'], 9);
    expect((put.$3 as Map)['min_password_length'], 8);
    expect(fake.writes.where((w) => w.$2 == '/ai/model').single.$3, {'model': 'gpt-4o'});
    expect(find.textContaining('Settings saved.'), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('a setting the page does not know yet goes to "General"', (tester) async {
    await _page(tester, fake: _WithExtra());
    expect(find.descendant(of: find.byKey(const ValueKey('tile-general')), matching: find.byKey(const ValueKey('setting-export_rows'))), findsOneWidget);
    expect(find.text('Rows per export'), findsOneWidget);
    await _leave(tester);
  });
}

// The credit status bar (owner decisions 2026-10-23): a full bar is the wallet
// right after the last top-up; green normally, yellow below 25% left (first
// asked as brand then amber; changed the same day to green / yellow / red),
// red below 10% or when the gateway refuses readings; in Settings and the editor.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/ai/ai_service.dart';
import 'package:gabay_admin/features/ai/credit_bar.dart';
import 'package:gabay_admin/features/settings/settings_view.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

Future<void> _bar(WidgetTester tester, AiQuota q, {bool compact = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: SizedBox(width: 400, child: CreditBar(quota: q, compact: compact))),
  ));
  await tester.pump(const Duration(seconds: 1));
}

/// The fill colour of a meter.
Color? _fill(WidgetTester tester, String key) {
  final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedContainer)));
  return (box.decoration as BoxDecoration?)?.color;
}

double _width(WidgetTester tester, String key) =>
    tester.getSize(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedContainer))).width;

void main() {
  const p = Pal.light;

  testWidgets('plenty left: a green bar filled to the share of the last top-up, no warning', (tester) async {
    await _bar(tester, const AiQuota(balance: 75, full: 100));
    expect(find.text('75% of the last top-up (100) left'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-wallet-status')), findsNothing);
    expect(_fill(tester, 'ai-wallet-meter'), p.green);
    expect(_width(tester, 'ai-wallet-meter'), closeTo(300, 1));
  });

  testWidgets('below a quarter: yellow, "Running low" in a readable yellow', (tester) async {
    await _bar(tester, const AiQuota(balance: 20, full: 100));
    expect(find.text('Running low'), findsOneWidget);
    expect(_fill(tester, 'ai-wallet-meter'), p.caution);
    expect(tester.widget<Text>(find.text('Running low')).style?.color, p.cautionText);
    expect(find.textContaining('Top up the IQGateway wallet soon'), findsOneWidget);
  });

  testWidgets('below a tenth: red, "Almost out"', (tester) async {
    await _bar(tester, const AiQuota(balance: 4.5, full: 100));
    expect(find.text('Almost out'), findsOneWidget);
    expect(_fill(tester, 'ai-wallet-meter'), p.danger);
  });

  testWidgets('blocked by the gateway: red, "Out of credits", with its reason', (tester) async {
    await _bar(tester, const AiQuota(balance: 0, full: 40, blocked: true, reason: 'Out of AI credits.'));
    expect(find.text('Out of credits'), findsOneWidget);
    expect(find.text('Out of AI credits.'), findsOneWidget);
    expect(_width(tester, 'ai-wallet-meter'), 0);
  });

  testWidgets('no full mark yet: the text only, no wallet bar', (tester) async {
    await _bar(tester, const AiQuota(balance: 12));
    expect(find.text('12 credits left'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-wallet-meter')), findsNothing);
  });

  testWidgets("a daily cap adds a second, thinner bar for today's use", (tester) async {
    await _bar(tester, const AiQuota(balance: 75, full: 100, usedToday: 50, dailyCap: 50));
    expect(find.byKey(const ValueKey('ai-daily-meter')), findsOneWidget);
    expect(find.textContaining("Today's cap is reached"), findsOneWidget);
  });

  testWidgets('the compact bar (map editor) keeps the share and status, without the advice', (tester) async {
    await _bar(tester, const AiQuota(balance: 20, full: 100), compact: true);
    expect(find.text('Running low'), findsOneWidget);
    expect(find.textContaining('Top up the IQGateway wallet soon'), findsNothing);
  });

  testWidgets('the Settings page shows the bar from the server', (tester) async {
    tester.view.physicalSize = const Size(1300, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(aiWallet: (12, 100));
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(sp)]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 1200, child: SettingsView()))))),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('ai-wallet-meter')), findsOneWidget);
    expect(find.text('12% of the last top-up (100) left'), findsOneWidget);
    expect(find.text('Running low'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}

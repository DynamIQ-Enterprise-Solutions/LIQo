// Round 20 (owner decisions 2026-10-23): every record page starts with a
// header card; under it (layout A, chosen after two columns looked crowded)
// the short cards sit side by side in pairs, every list is full width, and the
// danger zone comes last. One column at tablet width and below.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/widgets/detail_widgets.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _open(WidgetTester tester, String role, String path, double width) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: role);
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  await c.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: AuthUser(id: role == 'superadmin' ? 1 : 3, email: longEmail, fullName: longPerson, role: role, isActive: true, mustChangePassword: false),
      );
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) => MessageOverlay(child: child ?? const SizedBox.shrink()),
      ),
    ),
  ));
  c.read(routerProvider).go(path);
  await _steps(tester);
  return c;
}

Future<void> _leave(WidgetTester tester, ProviderContainer c) async {
  await _steps(tester, 40);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  await _steps(tester, 3);
}

void main() {
  for (final (role, path, pair, list, danger) in [
    // A superadmin's mall page has one short card (Details), so it spans the width.
    ('superadmin', '/superadmin/malls/1', false, 'Branches of this mall', true),
    ('mall_admin', '/mall-admin/stores/1', true, 'Owners', true),
    ('superadmin', '/superadmin/credit-requests/1', true, null, false),
    ('superadmin', '/superadmin/accounts/3', true, null, true),
  ]) {
    testWidgets('$path: header card, short cards in pairs, lists full width, danger zone last', (tester) async {
      final c = await _open(tester, role, path, 1600);
      final hero = tester.getRect(find.byKey(const ValueKey('record-hero')));
      final details = tester.getRect(find.byType(DetailCard).first);
      expect(details.top, greaterThan(hero.bottom), reason: 'the header card comes first');
      if (pair) {
        final row = find.byKey(const ValueKey('detail-facts-0'));
        final cards = find.descendant(of: row, matching: find.byType(DetailCard));
        expect(cards, findsNWidgets(2));
        final x = tester.getRect(cards.at(0));
        final y = tester.getRect(cards.at(1));
        expect(x.top, y.top, reason: 'side by side');
        expect(x.right, lessThan(y.left));
      } else {
        expect(details.width, closeTo(hero.width, 1), reason: 'a lone short card spans the width');
      }
      if (list != null) {
        final card = tester.getRect(find.ancestor(of: find.text(list).first, matching: find.byType(DetailCard)).first);
        expect(card.width, closeTo(hero.width, 1), reason: 'lists are full width');
        expect(card.top, greaterThan(details.bottom));
      }
      if (danger) {
        final d = tester.getRect(find.byType(DangerZone));
        expect(d.width, closeTo(hero.width, 1));
        final bottoms = find.byType(DetailCard).evaluate().map((e) => tester.getRect(find.byWidget(e.widget)).bottom);
        expect(d.top, greaterThan(bottoms.reduce((p, q) => p > q ? p : q)), reason: 'last');
      }
      await _leave(tester, c);
    });
  }

  testWidgets('a single short card spans the full width (problem report)', (tester) async {
    final c = await _open(tester, 'superadmin', '/superadmin/reports/1', 1600);
    final hero = tester.getRect(find.byKey(const ValueKey('record-hero')));
    final report = tester.getRect(find.ancestor(of: find.text('Report').first, matching: find.byType(DetailCard)).first);
    expect(report.width, closeTo(hero.width, 1));
    await _leave(tester, c);
  });

  testWidgets('narrow: one column, short cards first', (tester) async {
    final c = await _open(tester, 'superadmin', '/superadmin/malls/1', 800);
    expect(find.byKey(const ValueKey('record-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-facts-0')), findsNothing);
    final details = tester.getRect(find.text('Details'));
    final branches = tester.getRect(find.text('Branches of this mall'));
    expect(details.top, lessThan(branches.top));
    await _leave(tester, c);
  });

  testWidgets('My account keeps its header card (the shared one)', (tester) async {
    final c = await _open(tester, 'store_owner', '/store-owner/account', 1400);
    expect(find.byKey(const ValueKey('record-hero')), findsOneWidget);
    await _leave(tester, c);
  });
}

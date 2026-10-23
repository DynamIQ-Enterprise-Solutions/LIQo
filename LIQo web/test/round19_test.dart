// Round 19 (owner decisions 2026-10-23): AI credits per mall admin (their own
// bar, low and zero warnings, requests), the superadmin's credits in Analytics
// (wallet split, give and take back, history), Requests & reports (tabs with
// counts, credit requests decided there), problem reports (top bar, thread,
// statuses, My reports), the model list opening under its field, the My
// account skeleton, and the wizard's starting-credits note.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/accounts/accounts_service.dart';
import 'package:gabay_admin/features/ai/my_credits.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The whole app, signed in as [role], at [path].
Future<(ProviderContainer, FakeApiAdapter)> _app(WidgetTester tester, String role, String path, {FakeApiAdapter? fake, double width = 1400}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final f = fake ?? FakeApiAdapter(role: role);
  ApiClient.instance.dio.httpClientAdapter = f;
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
  return (c, f);
}

Future<void> _leave(WidgetTester tester, ProviderContainer c) async {
  await _steps(tester, 40);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  await _steps(tester, 3);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _steps(tester, 4);
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  final field = find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first, matching: find.byType(TextField));
  await tester.enterText(field.first, text);
  await tester.pump();
}

void main() {
  group('Settings', () {
    testWidgets('the model list opens under its field and leaves the tile visible; given and free show', (tester) async {
      final (c, _) = await _app(tester, 'superadmin', '/superadmin/settings');
      expect(find.byKey(const ValueKey('ai-given-free')), findsOneWidget);
      expect(find.text('Given to mall admins 36 · Free to give 46'), findsOneWidget);
      final field = tester.getRect(find.byKey(const ValueKey('ai-model-field')));
      await _tap(tester, find.byKey(const ValueKey('ai-model-field')));
      final item = tester.getRect(find.text('GPT-4o · openai').last);
      expect(item.top, greaterThanOrEqualTo(field.bottom - 1), reason: 'the list opens below the field');
      final tile = tester.getRect(find.byKey(const ValueKey('tile-ai')));
      expect(field.top, greaterThan(tile.top), reason: 'the tile head stays above the list');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _leave(tester, c);
    });
  });

  group('a mall admin\'s own credits', () {
    testWidgets('My account: the bar, Request credits sends an amount', (tester) async {
      final (c, fake) = await _app(tester, 'mall_admin', '/mall-admin/account');
      expect(find.text('AI credits'), findsOneWidget);
      expect(find.text('12.5 credits left'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('my-credits-request')));
      expect(find.text('Request AI credits'), findsOneWidget);
      await _type(tester, 'How many credits', '5');
      await _tap(tester, find.text('Send request'));
      final post = fake.writes.lastWhere((w) => w.$2 == '/ai/credits/requests');
      expect((post.$3 as Map)['amount'], 5);
      await _leave(tester, c);
    });

    testWidgets('a waiting request shows, with Cancel', (tester) async {
      final (c, fake) = await _app(tester, 'mall_admin', '/mall-admin/account', fake: FakeApiAdapter(role: 'mall_admin', creditRequestPending: true));
      expect(find.byKey(const ValueKey('my-credits-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('my-credits-request')), findsNothing, reason: 'one request at a time');
      await _tap(tester, find.byKey(const ValueKey('my-credits-cancel')));
      expect(fake.writes.any((w) => w.$1 == 'DELETE' && w.$2 == '/ai/credits/requests/mine'), isTrue);
      await _leave(tester, c);
    });

    Future<void> panel(WidgetTester tester, FakeApiAdapter fake) async {
      ApiClient.instance.dio.httpClientAdapter = fake;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: SizedBox(width: 340, child: MyCreditsPanel(compact: true)))),
      ));
      await _steps(tester);
    }

    testWidgets('low: a yellow warning that the balance may go below 0', (tester) async {
      await panel(tester, FakeApiAdapter(role: 'mall_admin', aiMine: (0.3, 20), creditsAvgCost: 0.5));
      expect(find.byKey(const ValueKey('my-credits-low')), findsOneWidget);
      expect(find.textContaining('may go below 0'), findsOneWidget);
    });

    testWidgets('at 0 or below: red, and Request credits stands out', (tester) async {
      await panel(tester, FakeApiAdapter(role: 'mall_admin', aiMine: (-0.03, 5)));
      expect(find.byKey(const ValueKey('my-credits-out')), findsOneWidget);
      expect(find.text('Out of credits'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-credits-request')), findsOneWidget);
    });
  });

  group('Analytics: AI credits', () {
    testWidgets('superadmin: the wallet split, the admins, give and take back, history', (tester) async {
      final (c, fake) = await _app(tester, 'superadmin', '/superadmin/analytics');
      await tester.ensureVisible(find.byKey(const ValueKey('credits-wallet')));
      await _steps(tester, 4);
      expect(find.text('82 credits in the wallet'), findsOneWidget);
      expect(find.text('Given to admins 36'), findsOneWidget);
      expect(find.text('Free to give 46'), findsOneWidget);
      expect(find.byKey(const ValueKey('credits-requests-link')), findsOneWidget);
      expect(find.byKey(const ValueKey('credit-admin-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('ledger-10')), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('credit-give-3')));
      expect(find.textContaining('Give credits to'), findsOneWidget);
      await _type(tester, 'Credits', '2');
      await _tap(tester, find.text('Give credits'));
      final give = fake.writes.lastWhere((w) => w.$2 == '/ai/credits/3/adjust');
      expect((give.$3 as Map)['delta'], 2);

      await _tap(tester, find.byKey(const ValueKey('credit-take-3')));
      await _type(tester, 'Credits', '1.5');
      await _tap(tester, find.text('Take back'));
      final take = fake.writes.lastWhere((w) => w.$2 == '/ai/credits/3/adjust');
      expect((take.$3 as Map)['delta'], -1.5);
      await _leave(tester, c);
    });

    testWidgets('mall owner: their admins only, read only, no wallet', (tester) async {
      final (c, _) = await _app(tester, 'supervisor', '/mall-owner/analytics');
      await tester.ensureVisible(find.byKey(const ValueKey('credits-admins')));
      await _steps(tester, 4);
      expect(find.byKey(const ValueKey('credits-wallet')), findsNothing);
      expect(find.byKey(const ValueKey('credits-history')), findsNothing);
      expect(find.byKey(const ValueKey('credit-admin-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('credit-give-3')), findsNothing);
      await _leave(tester, c);
    });
  });

  group('Requests & reports', () {
    testWidgets('tabs with counts; the old Profile requests link lands on its tab', (tester) async {
      final (c, _) = await _app(tester, 'superadmin', '/superadmin/profile-requests');
      expect(c.read(routerProvider).routeInformationProvider.value.uri.toString(), '/superadmin/requests?tab=profile');
      expect(find.text('Requests & reports'), findsWidgets);
      for (final t in ['all', 'profile', 'credits', 'reports']) {
        expect(find.byKey(ValueKey('requests-tab-$t')), findsOneWidget);
      }
      await _tap(tester, find.byKey(const ValueKey('requests-tab-all')));
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('AI credits'), findsWidgets);
      await _leave(tester, c);
    });

    testWidgets('a credit request is approved (maybe less) or declined on its page', (tester) async {
      final (c, fake) = await _app(tester, 'superadmin', '/superadmin/credit-requests/1');
      expect(find.text('Room under the cap'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('credit-request-approve')));
      await _type(tester, 'Credits to give', '3');
      await _tap(tester, find.text('Give credits'));
      final approve = fake.writes.lastWhere((w) => w.$2 == '/ai/credits/requests/1/approve');
      expect((approve.$3 as Map)['amount'], 3);
      await _leave(tester, c);
    });

    testWidgets('a report: the thread, a reply, and moving it on', (tester) async {
      final (c, fake) = await _app(tester, 'superadmin', '/superadmin/reports/1');
      expect(find.text('Conversation'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('report-reply-0')), matching: find.byType(TextField)), 'Which floor was it?');
      await tester.pump();
      await _tap(tester, find.byKey(const ValueKey('report-send')));
      final msg = fake.writes.lastWhere((w) => w.$2 == '/reports/1/messages');
      expect((msg.$3 as Map)['body'], 'Which floor was it?');
      await _tap(tester, find.byKey(const ValueKey('report-in-progress')));
      final st = fake.writes.lastWhere((w) => w.$2 == '/reports/1/status');
      expect((st.$3 as Map)['status'], 'in_progress');
      await _leave(tester, c);
    });
  });

  group('problem reports', () {
    testWidgets('the top bar button sends a report with the page it came from', (tester) async {
      final (c, fake) = await _app(tester, 'mall_admin', '/mall-admin/stores');
      await _tap(tester, find.byKey(const ValueKey('report-problem')));
      expect(find.text('Report a problem'), findsWidgets);
      await _tap(tester, find.byType(DropdownButton<String>).last);
      await _tap(tester, find.text('Wrong data').last);
      await _type(tester, 'Subject', 'A store shows the wrong hours');
      await _type(tester, 'What happened?', 'Northline shows 9 to 5 but opens at 10.');
      await _tap(tester, find.text('Send report'));
      final post = fake.writes.lastWhere((w) => w.$2 == '/reports');
      expect(post.$3, {'type': 'wrong_data', 'subject': 'A store shows the wrong hours', 'body': 'Northline shows 9 to 5 but opens at 10.', 'pagePath': '/mall-admin/stores'});
      await _leave(tester, c);
    });

    testWidgets('superadmins have no report button; others see My reports in My account', (tester) async {
      final (c, _) = await _app(tester, 'superadmin', '/superadmin/overview');
      expect(find.byKey(const ValueKey('report-problem')), findsNothing);
      await _leave(tester, c);
      final (c2, _) = await _app(tester, 'store_owner', '/store-owner/account');
      expect(find.text('My reports'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-report-1')), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
      await _leave(tester, c2);
    });
  });

  testWidgets('My account shows its own skeleton until it has loaded', (tester) async {
    final (c, _) = await _app(tester, 'mall_admin', '/mall-admin/account', fake: FakeApiAdapter(role: 'mall_admin', hangWhen: RegExp(r'/auth/me$')));
    expect(find.byKey(const ValueKey('account-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('a new mall admin comes back with the credits they start with', () async {
    ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter();
    final (_, _, start) = await AccountsService().create(email: 'new@liqo.local', fullName: 'New Admin', role: 'mall_admin', branchIds: [1]);
    expect(start?.credits, 3);
    expect(start?.note, isNull);
    final (_, _, none) = await AccountsService().create(email: 'own@liqo.local', fullName: 'New Owner', role: 'supervisor', mallIds: [1]);
    expect(none, isNull);
  });
}

// Round 8: logos with a monogram fallback, a store owner's stores, rules for
// another superadmin, releasing a stuck map lock, and own-profile changes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/account/account_view.dart';
import 'package:gabay_admin/features/accounts/account_detail_view.dart';
import 'package:gabay_admin/features/malls/branch_detail_view.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/widgets/logo_image.dart';

import 'support/fake_api.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Pumps [page] for a signed-in [role] against the fake API.
Future<ProviderContainer> _pump(WidgetTester tester, Widget page, {required String role, bool mapLocked = false}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: role, mapLocked: mapLocked);
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(container.dispose);
  await container.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: AuthUser(id: 1, email: longEmail, fullName: longPerson, role: role, isActive: true, mustChangePassword: false),
      );
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 1300, child: page)))),
    ),
  ));
  await _settle(tester);
  return container;
}

void main() {
  testWidgets('a logo without a URL shows the initials', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: LogoImage(url: '', name: 'SM Prime', size: 48))));
    expect(find.text('SP'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: LogoImage(url: null, name: 'Waltermart', size: 48))));
    expect(find.text('W'), findsOneWidget);
  });

  testWidgets('a logo whose image fails to load falls back to the initials', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: LogoImage(url: 'https://nowhere.invalid/logo.png', name: 'Ayala Center', size: 48))));
    // The test environment answers every image request with an error.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('AC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a superadmin sees a store owner's stores on their account page", (tester) async {
    await _pump(tester, const AccountDetailView(accountId: 4), role: 'superadmin');
    expect(find.text('Stores'), findsOneWidget);
    expect(find.text('Northline Apparel Flagship Boutique and Outlet'), findsOneWidget);
  });

  testWidgets("another superadmin's page has no Edit but keeps the danger zone", (tester) async {
    await _pump(tester, const AccountDetailView(accountId: 9), role: 'superadmin');
    expect(find.text('Edit'), findsNothing);
    expect(find.text('DANGER ZONE'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });

  testWidgets('the release-lock button shows only to the superadmin', (tester) async {
    await _pump(tester, const BranchDetailView(branchId: 1), role: 'superadmin', mapLocked: true);
    expect(find.byKey(const ValueKey('release-lock')), findsOneWidget);
  });

  testWidgets('a mall owner does not get the release-lock button', (tester) async {
    await _pump(tester, const BranchDetailView(branchId: 1), role: 'supervisor', mapLocked: true);
    expect(find.text('Being edited by'), findsOneWidget);
    expect(find.byKey(const ValueKey('release-lock')), findsNothing);
  });

  testWidgets('My account: a superadmin edits directly', (tester) async {
    await _pump(tester, const AccountView(), role: 'superadmin');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Request a change'), findsNothing);
    expect(find.text('Waiting for approval'), findsNothing);
  });

  testWidgets('My account: a mall admin with a waiting request sees it and can cancel it', (tester) async {
    await _pump(tester, const AccountView(), role: 'mall_admin');
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Cancel request'), findsOneWidget);
    expect(find.text('Request a change'), findsNothing, reason: 'one request at a time');
    expect(find.text('maria.santos.new.address@example-mall-company.com'), findsOneWidget);
  });
}

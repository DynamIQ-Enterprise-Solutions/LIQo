// Round 14: the mall owner dashboard's second gap review (owner decisions 2026-10-22).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/accounts/account_detail_view.dart';
import 'package:gabay_admin/features/announcements/announcement_detail_view.dart';
import 'package:gabay_admin/features/malls/branch_detail_view.dart';
import 'package:gabay_admin/features/map_editor/map_viewer_view.dart';
import 'package:gabay_admin/shared/lists/list_scaffold.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/models/paged.dart';
import 'package:gabay_admin/shared/widgets/app_shell.dart';
import 'package:gabay_admin/shared/widgets/common.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _signedIn(String role, FakeApiAdapter fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = fake;
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  await container.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: AuthUser(id: 1, email: longEmail, fullName: longPerson, role: role, isActive: true, mustChangePassword: false),
      );
  return container;
}

/// One page on its own, signed in as [role].
Future<void> _page(WidgetTester tester, Widget page, {required String role, FakeApiAdapter? fake}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await _signedIn(role, fake ?? FakeApiAdapter(role: role));
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 1300, child: page)))),
    ),
  ));
  await _steps(tester);
}

void main() {
  testWidgets('a shared announcement: no Edit, no Delete, "Remove from my branches" and a note', (tester) async {
    await _page(tester, const AnnouncementDetailView(announcementId: 1), role: 'supervisor', fake: FakeApiAdapter(role: 'supervisor', sharedAnnouncement: true));
    expect(find.text('Shared with other branches'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Remove from my branches'), findsOneWidget);
  });

  testWidgets('an inactive branch still shows its stores and map, marked hidden while inactive', (tester) async {
    await _page(tester, const BranchDetailView(branchId: 1), role: 'supervisor', fake: FakeApiAdapter(role: 'supervisor', inactiveBranch: true));
    expect(find.textContaining('hidden while inactive'), findsWidgets);
    expect(find.text('No store yet.'), findsNothing);
    expect(find.textContaining('You can still view them here'), findsOneWidget);
  });

  testWidgets('the viewer says once that a branch has no published map, with a way back', (tester) async {
    await _page(tester, const MapViewerView(initialBranchId: 1), role: 'supervisor');
    expect(find.text('No published map yet.'), findsOneWidget);
    expect(find.text('No published map for this branch yet.'), findsNothing, reason: 'no second, duplicate note');
    expect(find.text('Back to branch'), findsOneWidget);
  });

  testWidgets("an owner sees an admin's superior read-only and no Release action", (tester) async {
    await _page(tester, const AccountDetailView(accountId: 3), role: 'supervisor');
    expect(find.text('Reports to'), findsOneWidget);
    expect(find.text('Release'), findsNothing);
  });

  testWidgets('an empty list with a search on says the filters hide things', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ListScaffold<String>(
            fetch: (q) async => PagedResult<String>(items: const [], totalCount: 0, page: 1, pageSize: q.pageSize),
            emptyText: 'No mall admins report to you yet.',
            columns: [ListColumn(label: 'Name', cell: (c, s) => Text(s))],
          ),
        ),
      ),
    ));
    await _steps(tester);
    expect(find.text('No mall admins report to you yet.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await _steps(tester, 8);
    expect(find.text('Nothing matches these filters.'), findsOneWidget);
  });

  testWidgets('overview cards open their pages; activity reads in words', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await _signedIn('supervisor', FakeApiAdapter(role: 'supervisor'));
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          theme: buildTheme(Brightness.light),
          routerConfig: ref.watch(routerProvider),
          builder: (context, child) => MessageOverlay(child: child ?? const SizedBox.shrink()),
        ),
      ),
    ));
    final router = container.read(routerProvider);
    router.go('/mall-owner/overview');
    await _steps(tester);
    expect(find.text('Sign-in failed'), findsOneWidget, reason: '"login_failed" in words');
    await tester.tap(find.text('Active malls'));
    await _steps(tester);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/mall-owner/malls');
  });

  testWidgets('top bar: wordmark, toggle and avatar sit on one centre line', (tester) async {
    tester.view.physicalSize = const Size(1440, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await _signedIn('supervisor', FakeApiAdapter(role: 'supervisor'));
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: Column(children: [TopBar()]))),
    ));
    await _steps(tester, 4);
    final bar = tester.getRect(find.byType(TopBar));
    final logo = tester.getCenter(find.byType(BrandWordmark)).dy;
    final toggle = tester.getCenter(find.byType(ThemeToggleIcon)).dy;
    expect((logo - toggle).abs(), lessThan(1.5));
    expect((toggle - bar.center.dy).abs(), lessThan(1.5), reason: 'centred in the bar, not stuck to its top');
  });
}

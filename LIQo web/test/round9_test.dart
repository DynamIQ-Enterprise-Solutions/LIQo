// Round 9: the mall owner dashboard. The map viewer's store list, the mall
// page for an owner of one branch only, and announcement review by mall admins.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/announcements/announcement_detail_view.dart';
import 'package:gabay_admin/features/malls/mall_detail_view.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/maps_service.dart';
import 'package:gabay_admin/features/map_editor/store_list_panel.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pump(WidgetTester tester, Widget page, {required String role}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: role);
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
}

LayoutDoc _doc() => LayoutDoc(buildings: [
      Building(id: 'bd-1', name: 'Main', levels: [
        Level(id: 'lv-g', name: 'Ground floor', spaces: [Space(id: 'sp-1', name: 'Unit 1')]),
        Level(id: 'lv-2', name: 'Second floor', spaces: [Space(id: 'sp-2', name: 'Unit 2')]),
      ]),
    ]);

const _links = [
  StoreLink(spaceKey: 'sp-1', storeId: 1, storeName: 'Northline Apparel'),
  StoreLink(spaceKey: 'sp-2', storeId: 2, storeName: 'Bayside Books'),
  StoreLink(spaceKey: 'sp-gone', storeId: 3, storeName: 'Cafe Removed'),
];

Widget _panel({String? selectedId, required ValueChanged<String> onPick}) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: SizedBox(width: 300, height: 500, child: StoreListPanel(links: _links, doc: _doc(), selectedId: selectedId, onPick: onPick))),
    );

void main() {
  testWidgets('the store list shows each store with its level, flags missing spaces, and picks a space', (tester) async {
    String? picked;
    await tester.pumpWidget(_panel(onPick: (id) => picked = id));
    expect(find.text('Northline Apparel'), findsOneWidget);
    expect(find.text('Bayside Books'), findsOneWidget);
    expect(find.text('Ground floor · 1 space'), findsOneWidget);
    expect(find.text('Second floor · 1 space'), findsOneWidget);
    expect(find.text('Not on map'), findsOneWidget, reason: 'a link to a space that is not drawn');

    await tester.tap(find.text('Bayside Books'));
    expect(picked, 'sp-2');

    picked = null;
    await tester.tap(find.text('Cafe Removed'));
    expect(picked, isNull, reason: 'nothing to highlight');
  });

  testWidgets('the store search filters by name', (tester) async {
    await tester.pumpWidget(_panel(onPick: (_) {}));
    await tester.enterText(find.byKey(StoreListPanel.searchKey), 'bay');
    await tester.pump();
    expect(find.text('Bayside Books'), findsOneWidget);
    expect(find.text('Northline Apparel'), findsNothing);
    await tester.enterText(find.byKey(StoreListPanel.searchKey), 'zzz');
    await tester.pump();
    expect(find.textContaining('No store matches'), findsOneWidget);
  });

  testWidgets('an owner of one branch sees the mall read-only', (tester) async {
    await _pump(tester, const MallDetailView(mallId: 1), role: 'supervisor');
    expect(find.text('Read only'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('DANGER ZONE'), findsNothing);
  });

  testWidgets('a superadmin can still change the mall', (tester) async {
    await _pump(tester, const MallDetailView(mallId: 1), role: 'superadmin');
    expect(find.text('Read only'), findsNothing);
    expect(find.text('DANGER ZONE'), findsOneWidget);
  });

  testWidgets('a mall owner sees a pending submission waiting for a mall admin, without Approve', (tester) async {
    await _pump(tester, const AnnouncementDetailView(announcementId: 1), role: 'supervisor');
    expect(find.text('Waiting for a mall admin'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('a mall admin reviews the pending submission', (tester) async {
    await _pump(tester, const AnnouncementDetailView(announcementId: 1), role: 'mall_admin');
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Waiting for a mall admin'), findsNothing);
  });
}

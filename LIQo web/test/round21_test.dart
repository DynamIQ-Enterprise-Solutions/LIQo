// Round 21 (owner decisions 2026-10-23): what the shopper app needs from the
// admin screens. Opening hours per weekday and special days (branch and
// store; the store owner too), the store's status for shoppers, the App
// category of a store category, the branch's location from a Google Maps
// link, lifts and escalators out of service, and one uploaded picture per
// announcement (the image link field is gone).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/announcements/announcement_picture.dart';
import 'package:gabay_admin/features/announcements/announcements_view.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/models/opening_hours.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(ProviderContainer, FakeApiAdapter)> _open(WidgetTester tester, String role, String path, double width, {List<Override> overrides = const []}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = FakeApiAdapter(role: role);
  ApiClient.instance.dio.httpClientAdapter = api;
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs), ...overrides]);
  await c.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: AuthUser(id: role == 'store_owner' ? 4 : (role == 'superadmin' ? 1 : 3), email: longEmail, fullName: longPerson, role: role, isActive: true, mustChangePassword: false),
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
  return (c, api);
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
  await _steps(tester, 6);
}

void main() {
  test('hours lines group equal days, mark overnight closes and list special days', () {
    final h = OpeningHours.fromJson(longHours)!;
    expect(weekLines(h), ['Mon–Wed 10:00–21:00', 'Thu Closed', 'Fri 10:00–24:00', 'Sat 22:00–02:00 (next day)', 'Sun Closed']);
    expect(specialText(h.specials.last), '2026-12-25 Closed · Holiday');
    expect(isTime('24:00'), isTrue);
    expect(isTime('9:30'), isFalse);
    expect(isTime('23:59'), isTrue);
  });

  for (final width in [360.0, 1600.0]) {
    testWidgets('store page at ${width.toInt()} px: status for shoppers and opening hours; the editor saves per weekday', (tester) async {
      final (c, api) = await _open(tester, 'mall_admin', '/mall-admin/stores/1', width);
      expect(tester.takeException(), isNull);
      expect(find.text('Status for shoppers'), findsOneWidget);
      expect(find.text('Temporarily closed'), findsWidgets);
      expect(find.text('Mon–Wed 10:00–21:00'), findsOneWidget);
      expect(find.text('Old hours note'), findsWidgets, reason: 'the old free-text hours stay as a note');
      await _tap(tester, find.text('Edit hours'));
      expect(find.byKey(const ValueKey('hours-day-7')), findsOneWidget);
      expect(find.byKey(const ValueKey('hours-special-1')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the editor fits at ${width.toInt()} px');
      await _tap(tester, find.text('Save hours'));
      final write = api.writes.lastWhere((w) => w.$2 == '/stores/1/hours');
      final hours = (write.$3 as Map)['hours'] as Map;
      expect((hours['week'] as List).map((d) => (d as Map)['day']), [1, 2, 3, 5, 6]);
      expect((hours['specials'] as List).last, {'date': '2026-12-25', 'closed': true, 'note': 'Holiday'});
      await _leave(tester, c);
    });
  }

  testWidgets('a store owner changes the status and hours of their store, nothing else', (tester) async {
    final (c, api) = await _open(tester, 'store_owner', '/store-owner/stores/1', 1600);
    expect(find.byKey(const ValueKey('store-status')), findsOneWidget);
    expect(find.text('Edit hours'), findsOneWidget);
    expect(find.text('Edit'), findsNothing, reason: 'other details stay with the mall admin');
    await _tap(tester, find.byKey(const ValueKey('store-status')));
    await _tap(tester, find.text('Being repaired').last);
    expect(api.writes.any((w) => w.$2 == '/stores/1/status' && (w.$3 as Map)['status'] == 'being_repaired'), isTrue);
    await _leave(tester, c);
  });

  testWidgets('branch page: hours, the location from a Google Maps link (checked, then saved) and lifts out of service', (tester) async {
    final (c, api) = await _open(tester, 'mall_admin', '/mall-admin/branch/1', 1600);
    expect(tester.takeException(), isNull);
    expect(find.text('Opening hours'), findsOneWidget);
    expect(find.text('SM Mall of Asia, Seaside Boulevard, Bay City, Pasay, Metro Manila'), findsOneWidget);
    expect(find.textContaining('14.535'), findsNothing, reason: 'the pin numbers stay hidden');
    await _tap(tester, find.text('Change'));
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('maps-link')), matching: find.byType(EditableText)), 'https://maps.app.goo.gl/AbC123');
    await _steps(tester, 2);
    await _tap(tester, find.text('Check the link'));
    expect(find.byKey(const ValueKey('maps-found')), findsOneWidget);
    await _tap(tester, find.text('Yes, save'));
    expect(api.writes.any((w) => w.$2 == '/branches/1/location' && (w.$3 as Map)['mapsLink'] == 'https://maps.app.goo.gl/AbC123'), isTrue);

    expect(find.text('Lifts, escalators and stairs'), findsOneWidget);
    expect(find.text('Out of service'), findsWidgets);
    await _tap(tester, find.text('Back in service'));
    expect(api.writes.any((w) => w.$2 == '/maps/1/connectors/cn-1/out-of-service' && (w.$3 as Map)['out'] == false), isTrue);
    await _leave(tester, c);
  });

  testWidgets('a mall owner sees the lifts out of service but cannot change them', (tester) async {
    final (c, _) = await _open(tester, 'supervisor', '/mall-owner/branches/1', 1600);
    expect(find.text('Lifts, escalators and stairs'), findsOneWidget);
    expect(find.text('Back in service'), findsNothing);
    expect(find.text('Edit hours'), findsOneWidget, reason: 'branch information, as before');
    await _leave(tester, c);
  });

  testWidgets('store category page: the App category the shopper app sorts by', (tester) async {
    final (c, api) = await _open(tester, 'mall_admin', '/mall-admin/options/1', 1600);
    expect(find.text('App category'), findsWidgets);
    expect(find.text('Fashion'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('app-category')));
    await _tap(tester, find.text('Food').last);
    expect(api.writes.any((w) => w.$2 == '/options/1/app-category' && (w.$3 as Map)['appCategory'] == 'food'), isTrue);
    await _leave(tester, c);
  });

  testWidgets('announcements: the link field is gone; one picture is uploaded, shown and replaced', (tester) async {
    expect(announcementFields(owner: false).any((f) => f.name == 'imageUrl'), isFalse);
    expect(announcementFields(owner: true).any((f) => f.name == 'imageUrl'), isFalse);
    final picked = (base64Decode(tinyPng), 'sale.png');
    final (c, api) = await _open(
      tester,
      'store_owner',
      '/store-owner/announcements/1',
      1600,
      overrides: [announcementPicturePickerProvider.overrideWithValue(() async => (Uint8List.fromList(picked.$1), picked.$2))],
    );
    expect(find.text('Picture'), findsOneWidget);
    expect(find.bySemanticsLabel('Announcement picture'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('picture-upload')));
    final upload = api.writes.lastWhere((w) => w.$2 == '/announcements/1/picture');
    expect(upload.$1, 'POST');
    expect((upload.$3 as FormData).files.single.value.filename, 'sale.png');
    await _leave(tester, c);
  });
}

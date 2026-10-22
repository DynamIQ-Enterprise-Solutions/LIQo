// Page changes, frame by frame. During the short fade between two pages both
// are on screen at once; the old page must keep its own height then, not be
// squeezed to the new (often still loading, so short) page. The layout sweep
// jumps 250 ms per frame and never sees these frames, so this test steps
// through them at 16 ms, from first launch and across every page of each role.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/nav/role_nav.dart';

import 'support/fake_api.dart';

Future<void> _frames(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Record pages per role (fake API ids), same list as the layout sweep.
List<String> _detailPathsFor(String role) => switch (role) {
      'superadmin' => ['/superadmin/malls/1', '/superadmin/branches/1', '/superadmin/accounts/3', '/superadmin/profile-requests/1'],
      'supervisor' => ['/mall-owner/malls/1', '/mall-owner/branches/1', '/mall-owner/admins/3', '/mall-owner/stores/1', '/mall-owner/maps?branch=1'],
      'mall_admin' => ['/mall-admin/branch/1', '/mall-admin/stores/1', '/mall-admin/owners/4', '/mall-admin/announcements/1'],
      _ => ['/store-owner/stores/1', '/store-owner/announcements/1'],
    };

void main() {
  for (final role in roleNavs.keys) {
    for (final w in [360.0, 1366.0]) {
      for (final hang in [false, true]) {
        testWidgets('$role page changes stay in bounds at ${w.toInt()} px${hang ? ' while loading' : ''}', (tester) async {
          tester.view.physicalSize = Size(w, w < 800 ? 780 : 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final errors = <String>[];
          final original = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = RegExp(r'error-causing widget was:\s*\n\s*(.+)\n\s*(.+)').firstMatch(d.toString());
            final where = m == null ? '' : m.group(2)!.trim().replaceAll(RegExp(r'file:///.*/lib/'), 'lib/');
            final msg = '${d.exceptionAsString().split('\n').first} <$where>';
            if (!errors.contains(msg)) errors.add(msg);
          };

          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          // Lists answer, everything else may hang: the new page is short while the old one is full.
          ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: role, hangWhen: hang ? RegExp(r'/(analytics|lookups)/|/\d+$') : null);
          final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
          addTearDown(container.dispose);
          await container.read(sessionProvider.notifier).signIn(
                token: 'test-token',
                user: AuthUser(id: 1, email: longEmail, fullName: longPerson, role: role, isActive: true, mustChangePassword: false),
              );
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
          await _frames(tester, 30);

          final router = container.read(routerProvider);
          final nav = navForRole(role);
          final paths = [for (final item in nav.items) item.path, ..._detailPathsFor(role)];
          // Forward through every page, then back the other way, frame by frame.
          for (final path in [...paths, ...paths.reversed]) {
            router.go(path);
            await _frames(tester, 25);
          }
          FlutterError.onError = original;
          tester.takeException();
          expect(errors, isEmpty, reason: 'Layout problems during page changes:\n${errors.join('\n')}');
        });
      }
    }
  }
}

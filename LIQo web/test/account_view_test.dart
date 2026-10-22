// My account: the profile reads from the signed-in user and the appearance
// control changes the app's mode.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/core/theme_mode.dart';
import 'package:gabay_admin/features/account/account_view.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

void main() {
  testWidgets('shows the profile and switches the mode from the appearance control', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).signIn(
          token: 'x.y.z',
          user: const AuthUser(id: 7, email: 'maria@ayala.test', fullName: 'Maria Santos', role: 'mall_admin', isActive: true, mustChangePassword: false),
        );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: AccountView()))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Maria Santos'), findsWidgets);
    expect(find.text('maria@ayala.test'), findsWidgets);
    expect(find.text('MS'), findsOneWidget, reason: 'initials in the avatar');
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(container.read(themeModeProvider), ThemeMode.system, reason: 'follows the device until a choice is made');

    await tester.tap(find.byKey(const ValueKey('mode-dark')));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
    await tester.tap(find.byKey(const ValueKey('mode-light')));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    await tester.tap(find.byKey(const ValueKey('mode-system')));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(tester.takeException(), isNull);
  });
}

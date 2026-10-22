// Switching light and dark (owner decisions 2026-10-22): every colour morphs
// over about 450 ms, the brand images cross-fade in step, and the toggle's
// sun and moon rotate and swap. Moving between pages never shows two pages.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/core/theme_mode.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';
import 'package:gabay_admin/shared/nav/role_nav.dart';
import 'package:gabay_admin/shared/widgets/app_shell.dart';
import 'package:gabay_admin/shared/widgets/common.dart';

import 'support/fake_api.dart';

/// Reads the palette where the widgets read it.
class _Probe extends StatelessWidget {
  const _Probe();

  static Pal? last;

  @override
  Widget build(BuildContext context) {
    last = context.pal;
    return const Column(children: [BrandWordmark(size: 30), ThemeToggleIcon(color: Colors.black)]);
  }
}

void main() {
  testWidgets('switching modes morphs colours, cross-fades the logo and swaps the toggle icon', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    container.read(themeModeProvider.notifier).setDark(false);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: ref.watch(themeModeProvider),
          themeAnimationDuration: motionTheme,
          themeAnimationCurve: Curves.easeInOutCubic,
          home: const Scaffold(body: _Probe()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(_Probe.last!.darkness, 0);
    expect(find.byType(Image), findsOneWidget, reason: 'only the light logo when settled');
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsNothing);

    container.read(themeModeProvider.notifier).setDark(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 225));
    final mid = _Probe.last!;
    expect(mid.darkness, inExclusiveRange(0.0, 1.0), reason: 'half-way, the palette is a blend');
    expect(mid.bg, isNot(Pal.light.bg));
    expect(mid.bg, isNot(Pal.darkPal.bg));
    expect(find.byType(Image), findsNWidgets(2), reason: 'both logos cross-fading');
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.pumpAndSettle();
    expect(_Probe.last!.darkness, 1);
    expect(_Probe.last!.bg, Pal.darkPal.bg);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget, reason: 'dark mode shows the sun (switch to light)');
    expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
  });

  testWidgets('moving between pages: the old page is gone at once, never two pages on screen', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: 'superadmin');
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).signIn(
          token: 'test-token',
          user: const AuthUser(id: 1, email: longEmail, fullName: longPerson, role: 'superadmin', isActive: true, mustChangePassword: false),
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final router = container.read(routerProvider);
    for (final item in navForRole('superadmin').items.take(5)) {
      router.go(item.path);
      for (var f = 0; f < 18; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(ShellPage), findsOneWidget, reason: '${item.path}, frame $f: only one page on screen');
      }
    }
  });
}

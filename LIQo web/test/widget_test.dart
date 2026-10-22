// Smoke tests for the sign-in flow shell: the login page renders and the
// router keeps a signed-out visitor on /login.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/router.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

Future<Widget> _app() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        theme: buildTheme(Brightness.light),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) => MessageOverlay(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
}

void main() {
  testWidgets('signed-out visitor sees the login page', (tester) async {
    await tester.pumpWidget(await _app());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('empty submit shows field errors instead of calling the API', (tester) async {
    await tester.pumpWidget(await _app());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Email address is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });
}

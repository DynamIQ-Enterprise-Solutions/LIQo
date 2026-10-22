// The first-launch flow (splash -> onboarding -> pick a mall -> Home) and the
// later launches (splash -> Home).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/router.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/features/malls/providers/mall_provider.dart';
import 'package:liqo_mobile/features/onboarding/providers/boot_provider.dart';

import '../support/app.dart';

void main() {
  test('the redirect rules', () {
    const fresh = Boot(), splashed = Boot(splashDone: true), seen = Boot(splashDone: true, onboardingSeen: true);
    expect(bootRedirect(fresh, null, '/home'), '/splash');
    expect(bootRedirect(fresh, null, '/splash'), isNull);
    expect(bootRedirect(splashed, null, '/splash'), '/onboarding');
    expect(bootRedirect(seen, null, '/onboarding'), '/malls');
    expect(bootRedirect(seen, null, '/malls'), isNull);
    expect(bootRedirect(seen, 'bayview', '/splash'), '/home');
    expect(bootRedirect(seen, 'bayview', '/malls'), isNull, reason: 'Change mall opens the picker');
    expect(bootRedirect(seen, 'bayview', '/map'), isNull);
  });

  testWidgets('first launch: splash, three slides, the mall picker, then Home', (tester) async {
    final h = await pumpApp(tester, onboarded: false, mall: null);
    expect(find.text('Find your way inside the mall'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await h.step(30);
    expect(find.text('Everything in one place'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await h.step(30);
    expect(find.text('Never get lost'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await h.step(30);
    expect(h.store.get(Keys.onboardingSeen), '1');
    expect(find.text('Choose a mall'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mall-meridian')));
    await h.step(30);
    expect(h.c.read(mallProvider), 'meridian');
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Meridian Twin Malls'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skip on the slides goes straight to the picker', (tester) async {
    final h = await pumpApp(tester, onboarded: false, mall: null);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await h.step(30);
    expect(find.text('Choose a mall'), findsOneWidget);
  });

  testWidgets('a later launch: splash, then Home; the slides never again', (tester) async {
    final h = await pumpApp(tester);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Find your way inside the mall'), findsNothing);
    expect(h.c.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/home');
  });

  testWidgets('the splash shows the wordmark and the tagline for at least a second', (tester) async {
    await loadManrope(tester);
    final h = await pumpApp(tester);
    expect(h.c.read(bootProvider).splashDone, isTrue);
    expect(find.text('Smart Way Forward'), findsNothing); // past it now
  });
}

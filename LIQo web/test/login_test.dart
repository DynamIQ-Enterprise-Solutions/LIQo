// The login page (owner decisions 2026-10-22): the form in its own card, a
// feature carousel beside it on wide windows and under it on narrow ones,
// advancing every 6 s until someone picks a slide, never by itself when the
// device asks for reduced motion, and no overflow in short or narrow windows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/auth/glass.dart';
import 'package:gabay_admin/features/auth/login_ambience.dart';
import 'package:gabay_admin/features/auth/login_features.dart';
import 'package:gabay_admin/features/auth/login_view.dart';
import 'package:gabay_admin/shared/widgets/common.dart';

/// The page never settles (its background moves on purpose), so step time instead.
/// 1.2 s: longer than the entrance and the slide fade, well under the 6 s step.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Size size, {Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(theme: buildTheme(brightness), home: const LoginView()),
  ));
  await _settle(tester);
}

void main() {
  testWidgets('wide window: the carousel sits beside the form and the arrows and dots move it', (tester) async {
    await _pump(tester, const Size(1440, 900));
    expect(find.text('ADMIN CONSOLE'), findsOneWidget);
    expect(find.text('Draw every level of every branch.'), findsOneWidget);
    // Round 14: the tagline under the larger wordmark and in the footer.
    expect(find.text('Smart Way Forward'), findsOneWidget);
    expect(find.text('LIQO Wayfinding Platform · Smart Way Forward'), findsOneWidget);
    final form = tester.getCenter(find.text('ADMIN CONSOLE'));
    final slide = tester.getCenter(find.text('Draw every level of every branch.'));
    expect(slide.dx, lessThan(form.dx), reason: 'carousel on the left, form on the right');

    await tester.tap(find.byKey(FeatureCarousel.nextKey));
    await _settle(tester);
    expect(find.text('Turn a floor plan into a map.'), findsOneWidget);

    await tester.tap(find.byKey(FeatureCarousel.dotKey(3)));
    await _settle(tester);
    expect(find.text('See what changed, and who changed it.'), findsOneWidget);

    await tester.tap(find.byKey(FeatureCarousel.nextKey));
    await _settle(tester);
    expect(find.text('Draw every level of every branch.'), findsOneWidget, reason: 'wraps around');
  });

  // Owner decision 2026-10-23: on big screens the carousel and the form stay one
  // centred block (at most 1440 × 900); the living background fills the rest.
  for (final size in const [Size(1920, 1080), Size(2560, 1440), Size(3440, 1440)]) {
    testWidgets('big screen ${size.width.toInt()} × ${size.height.toInt()}: carousel and form stay one centred block', (tester) async {
      await _pump(tester, size);
      expect(tester.takeException(), isNull);
      final block = tester.getRect(find.byKey(const ValueKey('login-block')));
      expect(block.width, lessThanOrEqualTo(1440));
      expect(block.height, lessThanOrEqualTo(900));
      expect((block.center.dx - size.width / 2).abs(), lessThan(1), reason: 'centred across');
      expect((block.center.dy - size.height / 2).abs(), lessThan(1), reason: 'centred down');
      final carousel = tester.getRect(find.byType(FeatureCarousel));
      final form = tester.getCenter(find.text('ADMIN CONSOLE'));
      expect(block.contains(carousel.topLeft) && block.contains(carousel.bottomRight - const Offset(1, 1)), isTrue);
      expect(block.contains(form), isTrue);
      expect(form.dx - carousel.right, lessThan(500), reason: 'the form sits close to the carousel, not in an empty half');
      expect(find.byType(LoginBackdrop), findsOneWidget);
      expect(tester.getSize(find.byType(LoginBackdrop)), size, reason: 'the living background fills the whole screen');
    });
  }

  testWidgets('it advances every 6 s, and stops for good once someone picks a slide', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await tester.pump(const Duration(seconds: 6));
    await _settle(tester);
    expect(find.text('Turn a floor plan into a map.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await _settle(tester);
    expect(find.text('Keep the directory current.'), findsOneWidget);

    await tester.tap(find.byKey(FeatureCarousel.prevKey));
    await _settle(tester);
    expect(find.text('Turn a floor plan into a map.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 13));
    await _settle(tester);
    expect(find.text('Turn a floor plan into a map.'), findsOneWidget, reason: 'no automatic move after a pick');
  });

  testWidgets('with reduced motion it never moves by itself', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, const Size(1440, 900));
    await tester.pump(const Duration(seconds: 13));
    await _settle(tester);
    expect(find.text('Draw every level of every branch.'), findsOneWidget);
  });

  testWidgets('the background keeps moving; the IQ tile and a faint IQ watermark are shown', (tester) async {
    await _pump(tester, const Size(1440, 900));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'the living background animates');
    expect(find.byType(LoginBackdrop), findsOneWidget);
    expect(find.byType(IqWatermark), findsOneWidget);
    expect(find.byType(BrandTile), findsOneWidget, reason: 'the IQ tile on the card');
  });

  testWidgets('the showcase panel and the sign-in card are frosted glass, in light and dark', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      await _pump(tester, const Size(1440, 900), brightness: b);
      expect(find.byType(GlassSurface), findsNWidgets(2), reason: 'panel and card ($b)');
      expect(find.byType(BackdropFilter), findsNWidgets(2), reason: 'only these two blur what is behind ($b)');
    }
  });

  testWidgets('with reduced motion the whole page stands still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, const Size(1440, 900));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('Sign in'), findsWidgets, reason: 'shown at once, no entrance');
  });

  testWidgets('the watermark is left out when the layout stacks', (tester) async {
    await _pump(tester, const Size(900, 900));
    expect(find.byType(IqWatermark), findsNothing);
    expect(find.byType(LoginBackdrop), findsOneWidget);
  });

  testWidgets('narrow window: the form comes first, the compact carousel under it', (tester) async {
    await _pump(tester, const Size(900, 900));
    final form = tester.getTopLeft(find.text('ADMIN CONSOLE'));
    final slide = tester.getTopLeft(find.text('Draw every level of every branch.'));
    expect(slide.dy, greaterThan(form.dy));
    expect(find.text('MAP EDITOR'), findsOneWidget);
  });

  for (final (size, dark) in [
    (const Size(1051, 640), false),
    (const Size(1366, 640), true),
    (const Size(1920, 1080), true),
    (const Size(1050, 700), false),
    (const Size(360, 640), true),
  ]) {
    testWidgets('no overflow at ${size.width.toInt()}×${size.height.toInt()} ${dark ? 'dark' : 'light'}, on every slide', (tester) async {
      await _pump(tester, size, brightness: dark ? Brightness.dark : Brightness.light);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(FeatureCarousel.dotKey(i)));
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
      }
    });
  }
}

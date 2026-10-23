// The screens outside the map, through the real UI: Home and a category, a
// place's page (Call / Website / Share, the heart, Directions), Search,
// Saved, Route options, Settings (look, text size, language), More, the
// look-only sign in, a post, and switching malls from the header.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liqo_mobile/core/router.dart';
import 'package:liqo_mobile/features/malls/providers/mall_provider.dart';
import 'package:liqo_mobile/features/navigation/models/nav_state.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';
import 'package:liqo_mobile/features/navigation/providers/route_options_provider.dart';
import 'package:liqo_mobile/features/saved/models/saved_items.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';
import 'package:liqo_mobile/features/search/providers/search_providers.dart';
import 'package:liqo_mobile/features/settings/providers/settings_provider.dart';

import '../support/app.dart';
import '../support/spots.dart';

extension on AppHarness {
  NavState get s => c.read(navProvider);
  NavController get nav => c.read(navProvider.notifier);
  /// The page on top: a pushed page's own path, else the tab's.
  String get path {
    final cfg = c.read(routerProvider).routerDelegate.currentConfiguration, last = cfg.last;
    return last is ImperativeRouteMatch ? last.matches.uri.path : cfg.uri.path;
  }

  Future<void> tapKey(String key, {int frames = 30}) async {
    final f = find.byKey(ValueKey(key));
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await step(frames);
  }
}

void main() {
  testWidgets('Home: the categories; Shops lists the stores with pills, kinds, levels and opening status', (tester) async {
    final h = await pumpApp(tester);
    for (final label in ['Shops', 'Food & Dining', 'Restrooms', 'Elevators', 'ATMs', 'Parking']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await h.tapKey('cat-shops');
    expect(h.path, '/home/category/shops');
    expect(find.byKey(const ValueKey('pill-all')), findsOneWidget);
    expect(find.text('Tell us where you are on the map to see how far each place is.'), findsOneWidget);
    expect(find.textContaining('Open · Closes'), findsWidgets);
    await h.tapKey('pill-cinema');
    expect(find.text('Bayview Grand Cinemas'), findsOneWidget);
    expect(find.text('Hypermart Bayview'), findsNothing, reason: 'food is its own category');
    await h.tapKey('row-3-WDS');
    expect(h.path, '/place/bayview/3-WDS');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place page: status, Call, Website, Share, the heart; Directions asks where you are, then routes', (tester) async {
    final h = await pumpApp(tester);
    h.c.read(routerProvider).push('/place/bayview/3-M1');
    await h.step(30);
    expect(find.text('Opal Comics'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-line')), findsOneWidget);
    expect(find.text('Open · Closes 10:00 PM'), findsOneWidget); // 2:30 PM on the test clock
    await h.tapKey('call', frames: 2);
    await h.tapKey('website', frames: 2);
    await tester.tap(find.bySemanticsLabel('Share').first, warnIfMissed: false);
    await tester.tap(find.text('Share'));
    await h.step(2);
    expect(h.actions.calls.single, matches(RegExp(r'^\+63 2 5550 01\d\d$')));
    expect(h.actions.sites.single, startsWith('https://example.com/bayview/opal-comics'));
    expect(h.actions.shares.last, 'Opal Comics — Level 3, Bayview Grand');
    await h.tapKey('fav', frames: 2);
    expect(h.c.read(favouritesProvider.notifier).isFav('bayview', '3-M1'), isTrue);
    expect(h.c.read(visitsProvider('bayview')), {'3-M1': 1}, reason: 'opening a place counts as a visit');
    await h.tapKey('get-directions');
    expect(h.path, '/map');
    expect(h.s.locSheet, isTrue);
    expect(find.text('Tell us where you are, and the way there will show.'), findsOneWidget);
    await h.tapKey('locfloor-0');
    expect(h.s.route!.placeId, '3-M1');
    expect(find.byKey(const ValueKey('nav-banner')), findsOneWidget);
  });

  testWidgets('the Directions button on the map: "Where to?", a pick starts the route; hidden while walking', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    await tester.tap(find.text('Skip for now'));
    await h.step(10);
    await h.tapKey('directions');
    expect(h.path, '/search');
    expect(find.text('Where to?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'Hypermart');
    await h.step(5);
    await h.tapKey('result-G-EHM');
    expect(h.path, '/map');
    expect(h.s.locSheet, isTrue, reason: 'no position yet: it asks first');
    await h.tapKey('locfloor-0', frames: 40);
    expect(h.s.route!.placeId, 'G-EHM');
    expect(find.byKey(const ValueKey('directions')), findsNothing);
    expect(h.c.read(recentsProvider('bayview')), contains('G-EHM'));
  });

  testWidgets('a place closed by its hours can still be routed to, with a note', (tester) async {
    final h = await pumpApp(tester, now: DateTime(2026, 10, 22, 23, 15));
    h.c.read(routerProvider).push('/place/bayview/3-M1');
    await h.step(30);
    expect(find.text('Closed now · Opens 10:00 AM'), findsOneWidget);
    expect(find.text('You can still get directions.'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.descendant(of: find.byKey(const ValueKey('get-directions')), matching: find.byType(FilledButton)));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('Search: results show whether each place is open; a pick becomes a recent search and a visit', (tester) async {
    final h = await pumpApp(tester);
    await h.tapKey('home-search');
    expect(h.path, '/search');
    expect(find.text('Search for a store, a kind of place or a level, like "food" or "level 2".'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'cinema');
    await h.step(5);
    expect(find.byKey(const ValueKey('result-3-WDS')), findsOneWidget);
    expect(find.textContaining('Open · Closes'), findsWidgets);
    await h.tapKey('result-3-WDS');
    expect(h.path, '/place/bayview/3-WDS');
    expect(h.c.read(recentsProvider('bayview')), ['3-WDS']);
    h.c.read(routerProvider).pop();
    await h.step(10);
    await tester.enterText(find.byKey(const ValueKey('search-field')), '');
    await h.step(5);
    expect(find.text('RECENT SEARCHES'), findsOneWidget);
    expect(find.text('MOST VISITED'), findsOneWidget);
    // a filter
    await h.tapKey('filter-food', frames: 5);
    expect(find.text('RECENT SEARCHES'), findsNothing, reason: 'the cinema is not food');
  });

  testWidgets('Saved: places from every mall; a route saved from Your route; the history with how each trip ended', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    h.nav.refineAt(0, 720, 600);
    h.nav.startTo('3-M1');
    await h.step(5);
    h.c.read(routerProvider).push('/route');
    await h.step(30);
    expect(find.text('Your route'), findsOneWidget);
    await h.tapKey('save-route', frames: 2);
    expect(h.c.read(savedRoutesProvider).single.placeId, '3-M1');
    await h.tapKey('end-navigation');
    expect(h.c.read(historyProvider).first.outcome, TripOutcome.stopped);
    h.c.read(favouritesProvider.notifier).toggle('spire', 'R-GDN');
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await h.step(20);
    expect(find.text('Sky Garden'), findsOneWidget);
    expect(find.textContaining('Skyline Spire'), findsOneWidget);
    await tester.tap(find.text('Routes'));
    await h.step(5);
    expect(find.text('Opal Comics'), findsOneWidget);
    expect(find.text('A saved route starts from wherever you are when you open it.'), findsOneWidget);
    await tester.tap(find.text('History'));
    await h.step(5);
    expect(find.text('Stopped'), findsWidgets);
    // opening the saved route: back to the map with its options, from where the shopper is
    await tester.tap(find.text('Routes'));
    await h.step(5);
    await tester.tap(find.text('Opal Comics'));
    await h.step(30);
    expect(h.path, '/map');
    expect(h.s.route!.placeId, '3-M1');
  });

  testWidgets('Route options: Shortest and no stairs, applied to the trip and kept', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    h.nav.refineAt(0, 720, 600);
    h.nav.startTo('3-M1');
    await h.step(5);
    final before = h.s.route;
    await h.tapKey('nav-expand');
    await h.tapKey('route-options');
    expect(h.path, '/route-options');
    await h.tapKey('metric-shortest', frames: 5);
    await h.tapKey('avoid-stairs', frames: 5);
    await h.tapKey('apply');
    expect(h.path, '/map');
    final o = h.c.read(routeOptionsProvider);
    expect((o.metric, o.avoidStairs), ('shortest', true));
    expect(identical(h.s.route, before), isFalse, reason: 'the route was worked out again');
  });

  testWidgets('Settings: dark look, the largest text, high contrast; they are kept', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await h.step(20);
    await h.tapKey('more-settings');
    expect(h.path, '/more/settings');
    await tester.tap(find.text('Dark'));
    await h.step(40);
    expect(Theme.of(tester.element(find.text('Settings').first)).brightness, Brightness.dark);
    await tester.tap(find.text('Largest'));
    await h.step(5);
    expect(MediaQuery.textScalerOf(tester.element(find.text('Settings').first)).scale(1), 1.4);
    await h.tapKey('set-contrast', frames: 40);
    expect(h.c.read(settingsProvider).highContrast, isTrue);
    expect(h.store.get('settings'), allOf(contains('"theme":"dark"'), contains('"textSize":1.4'), contains('"highContrast":true')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with Tagalog chosen, the main screens show no English wording', (tester) async {
    final h = await pumpApp(tester, prefs: {'settings': '{"lang":"tl"}'});
    expect(find.text('Mga kategorya'), findsOneWidget);
    expect(find.text('Mga tindahan'), findsOneWidget);
    for (final en in ['Categories', 'Map', 'Saved', 'More', 'Shops', 'Where do you want to go?']) {
      expect(find.text(en), findsNothing, reason: en);
    }
    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Iba pa'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    expect(find.text('Nasaan ka?'), findsOneWidget);
    expect(find.text('Where are you?'), findsNothing);
    await h.tapKey('locfloor-0');
    expect(find.text('Tapusin'), findsOneWidget);
    await h.tapKey('nav-expand');
    expect(find.text('Humanap ng ibang daan'), findsOneWidget);
    expect(find.text('Find another way'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await h.step(20);
    await h.tapKey('more-settings');
    expect(find.text('WIKA'), findsOneWidget);
    expect(find.text('Pinakamalaki'), findsOneWidget);
    expect(find.text('Text and display'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More: sign in and sign up are look-only ("Accounts are coming soon"); Help and About open', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await h.step(20);
    await h.tapKey('more-signin');
    expect(h.path, '/login');
    await tester.enterText(find.byType(TextField).first, 'someone@example.com');
    await h.tapKey('sign-in', frames: 5);
    expect(find.text('Accounts are coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await h.tapKey('social-google', frames: 5);
    expect(find.text('Accounts are coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Sign up').last);
    await h.step(30);
    expect(h.path, '/signup');
    await h.tapKey('terms', frames: 5);
    expect(find.text('Accounts are coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    h.c.read(routerProvider).go('/more');
    await h.step(30);
    await h.tapKey('more-help');
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Emergency evacuation'), findsOneWidget);
    h.c.read(routerProvider).pop();
    await h.step(30);
    await h.tapKey('more-about');
    expect(find.text('Smart Way Forward'), findsOneWidget);
    expect(find.text('Version 1.0.0'), findsOneWidget);
    await h.tapKey('licences', frames: 30);
    expect(find.byType(LicensePage), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a sample post: the card is labelled, its page says it is a sample', (tester) async {
    final h = await pumpApp(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('post-bay-1')));
    await tester.pump();
    expect(find.text('Sample'), findsWidgets);
    await h.tapKey('post-bay-1');
    expect(h.path, '/post/bay-1');
    expect(find.text('Sunset by the bay'), findsOneWidget);
    expect(find.textContaining('This is a sample post.'), findsOneWidget);
  });

  testWidgets('switching malls from the header ends the trip and clears the position', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    h.nav.refineAt(scenarioStart(h.s.v).lv, 720, 600);
    await h.step(5);
    expect(h.s.route, isNotNull, reason: 'the demo trip');
    // while walking, the map shows no search bar: the mall is changed from Home's header
    expect(find.byKey(const ValueKey('mall-switcher')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await h.step(20);
    await tester.tap(find.byKey(const ValueKey('mall-switcher')));
    await h.step(30);
    await tester.tap(find.byKey(const ValueKey('switch-spire')));
    await h.step(30);
    expect(h.c.read(mallProvider), 'spire');
    expect(h.s.v.id, 'spire');
    expect(h.s.user, isNull);
    expect(h.s.route, isNull);
    expect(h.c.read(historyProvider).first.outcome, TripOutcome.stopped);
    expect(find.text('Skyline Spire'), findsWidgets);
  });
}

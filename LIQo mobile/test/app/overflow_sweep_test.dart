// The layout sweep: every screen, and every state of the Map tab, at phone and
// tablet widths, with long names, in light and in dark high contrast with the
// largest text, and once in Tagalog. Any overflow or exception fails it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/kit/kit_spec.dart';
import 'package:liqo_mobile/core/engine/kit/kit_venue.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/router.dart';
import 'package:liqo_mobile/features/malls/data/bayview.dart';
import 'package:liqo_mobile/features/malls/data/meridian.dart';
import 'package:liqo_mobile/features/malls/data/spire.dart';
import 'package:liqo_mobile/features/malls/providers/mall_provider.dart';
import 'package:liqo_mobile/features/map/providers/map_provider.dart';
import 'package:liqo_mobile/features/navigation/models/route_options.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';
import 'package:liqo_mobile/features/search/providers/search_providers.dart';

import '../support/app.dart';
import '../support/spots.dart';

const widths = [320.0, 360.0, 390.0, 412.0, 480.0, 800.0, 1024.0];

/// The malls again, with very long names for the mall and its big stores.
KitVenue longVenue(String id) {
  final spec = switch (id) { 'meridian' => meridianSpec, 'spire' => spireSpec, _ => bayviewSpec };
  return KitVenue(spec.copyWith(
    name: '${spec.name} Seaside Shopping and Entertainment Campus',
    anchors: [
      for (final a in spec.anchors)
        KAnchor(a.id, a.bld, a.rect, {for (final e in a.names.entries) e.key: ['${e.value[0]} International Flagship Super Centre and Lifestyle Hall', e.value[1]]}, a.doors),
    ],
  ));
}

class Variant {
  const Variant(this.name, {this.prefs = const {}, this.textScale = 1});
  final String name;
  final Map<String, String> prefs;
  final double textScale;
}

const variants = [
  Variant('light'),
  // the largest text: 1.4 on top of a phone at 1.5, capped at 2.0
  Variant('dark, high contrast, largest text', prefs: {'settings': '{"theme":"dark","highContrast":true,"textSize":1.4}'}, textScale: 1.5),
  Variant('Tagalog, larger text', prefs: {'settings': '{"lang":"tl","textSize":1.2}'}),
];

Future<void> check(WidgetTester tester, String where) async {
  final e = tester.takeException();
  if (e != null) fail('$where: $e');
}

void main() {
  for (final v in variants) {
    for (final w in widths) {
      testWidgets('every screen at $w px, ${v.name}', (tester) async {
        final h = await pumpApp(tester, size: Size(w, w >= 800 ? 1180 : 780), textScale: v.textScale, prefs: v.prefs, overrides: [venueProvider.overrideWith((ref, id) => longVenue(id))]);
        final router = h.c.read(routerProvider);
        final nav = h.c.read(navProvider.notifier), map = h.c.read(mapProvider.notifier);
        // long names everywhere: saved places, routes and history from two malls
        h.c.read(favouritesProvider.notifier)
          ..toggle('bayview', 'G-WDS')
          ..toggle('spire', 'R-GDN');
        h.c.read(savedRoutesProvider.notifier).toggle(mallId: 'bayview', placeId: 'G-WDS', placeName: 'Bayview Department Store International Flagship Super Centre and Lifestyle Hall', options: const RouteOptions(metric: 'shortest', avoidStairs: true, avoidEscalators: true), wheelchair: true);
        h.c.read(recentsProvider('bayview').notifier).add('G-WDS');
        h.c.read(visitsProvider('bayview').notifier).visit('G-WDS');
        Future<void> page(String loc, {bool push = false}) async {
          push ? router.push(loc) : router.go(loc);
          await h.step(12);
          await check(tester, loc);
        }

        for (final loc in ['/home', '/home/category/shops', '/home/category/lift', '/home/category/parking', '/saved?tab=places', '/saved?tab=routes', '/more']) {
          await page(loc);
        }
        for (final loc in ['/search', '/place/bayview/G-WDS', '/place/bayview/CONN:M-L1', '/place/bayview/NP-GA', '/route', '/route-options', '/post/bay-1', '/login', '/signup', '/more/settings', '/more/help', '/more/about', '/malls']) {
          await page(loc, push: true);
          router.pop();
          await h.step(4);
        }
        // search with results
        router.push('/search');
        await h.step(12);
        await tester.enterText(find.byKey(const ValueKey('search-field')), 'store');
        await h.step(4);
        await check(tester, 'search results');
        router.pop();
        await h.step(4);

        // ----- the Map tab, state by state -----
        Future<void> state(String name, void Function() set) async {
          set();
          await h.step(12);
          await check(tester, 'map: $name');
        }

        await page('/map');
        await check(tester, 'map: where are you');
        await state('no sheet, the whole site', nav.closeLocation);
        await state('a place', () => nav.pick('G-WDS'));
        await state('nearest, no position', () => nav.showNearest('restroom'));
        final start = scenarioStart(h.c.read(navProvider).v);
        await state('refining a floor', () => nav.locAtFloor(1));
        await state('a position', () => nav.refineAt(start.lv, start.x, start.y));
        await state('nearest', () => nav.showNearest('restroom'));
        await state('nearest, a row previewed', () => nav.previewNearest(h.c.read(navProvider).near!.ids.first));
        await state('a route', () => nav.startTo('3-M1'));
        await state('walking', nav.start);
        final s = h.c.read(navProvider), steps = stepsOf(s.route!);
        final hopAt = steps.firstWhere((x) => x.kind == 'hop').endAt;
        await state('the pause question', nav.pause);
        await state('resumed', nav.resume);
        await state('a ride question', () {
          final hop = s.directions.firstWhere((d) => d.isUpDown);
          nav.debugScrub((hop.atM - .5) / s.route!.total * 1000);
          nav.start();
          s.route!.progress = hop.atM + .3;
          nav.syncUser();
        });
        await state('answered', nav.answerYes);
        await state('riding, the landing', () => nav.debugScrub((hopAt - 2) / s.route!.total * 1000));
        await state('other ways', () {
          nav.debugScrub(200 / s.route!.total * 1000);
          nav.findAnotherWay();
        });
        await state('back on the way', nav.cancelReroute);
        await state('the bottom bar opened', map.toggleNavOpen);
        await state('paused, the bar open', () {
          nav.pause();
          nav.answerYes();
        });
        await state('the bottom bar closed', map.toggleNavOpen);
        // the Layers panel, over the walk
        await tester.tap(find.byKey(const ValueKey('layers')));
        await h.step(30);
        await check(tester, 'map: the Layers panel');
        Navigator.of(tester.element(find.byKey(const ValueKey('layers-3d')))).pop();
        await h.step(30);
        await state('the arrival question', () => nav.debugScrub(1000));
        await state('arrived', nav.confirmArrived);
        await state('all levels', () {
          nav.stop();
          map.toggleStack();
        });
        await state('a floor plan', () {
          map.toggleStack();
          h.c.read(mapProvider).cam.zoom = 5 * s.v.ratio;
          map.notify();
        });
        // the floor picker opened
        await tester.tap(find.byKey(const ValueKey('floors-toggle')));
        await h.step(4);
        await check(tester, 'map: every floor listed');
        await tester.tap(find.byKey(const ValueKey('floors-toggle')));
        await h.step(4);
        await state('no wheelchair route', () {
          s.wcError = 'Bayview Department Store International Flagship Super Centre and Lifestyle Hall';
          s.wcPlace = 'G-WDS';
          nav.finishRefine();
        });
        await state('the evacuation', () {
          nav.stop();
          nav.refineAt(1, 750, 310);
          nav.startEmergency();
        });
        await state('the evacuation, getting help', nav.help);
        await state('out', () => nav.debugScrub(1000));
        await state('no evacuation', nav.stopEmergency);
        await tester.pump(const Duration(seconds: 3)); // the confetti
      });
    }
  }

  for (final w in widths) {
    testWidgets('the first launch at $w px: the splash, the slides and the picker', (tester) async {
      final h = await pumpApp(tester, onboarded: false, mall: null, size: Size(w, w >= 800 ? 1180 : 640), textScale: 1.5, prefs: {'settings': '{"textSize":1.4}'});
      await check(tester, 'onboarding 1');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-next')));
        await h.step(30);
        await check(tester, 'onboarding ${i + 2}');
      }
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await h.step(30);
      await check(tester, 'the picker');
    });
  }
}

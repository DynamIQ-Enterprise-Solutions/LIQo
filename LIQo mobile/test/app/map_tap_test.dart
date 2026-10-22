// Tapping a place on the map after a route was arrived at: the old route goes,
// and the sheet offers the new place (from the demo's map_tap_test), and the
// mall picker's search (from its ux_test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/router.dart';
import 'package:liqo_mobile/features/map/providers/map_provider.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';

import '../support/app.dart';
import '../support/harness.dart';
import '../support/spots.dart';

void main() {
  test('after arriving, a tap on another place drops the finished route', () {
    final h = Harness();
    h.goFrom(scenarioStart(h.v), h.v.tripTarget);
    h.nav.debugScrub(1000);
    h.nav.confirmArrived();
    expect(h.s.arrived, isTrue);
    h.mv.cam.zoom = 5 * h.v.ratio; // a floor plan
    final other = h.v.places.firstWhere((p) => p.kind == 'store' && p.status == 'open' && p.id != h.v.tripTarget);
    h.mv.hits.add('poi', other.id, Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)));
    h.map.mapTap(const Offset(5, 5));
    expect(h.s.place, other.id);
    expect(h.s.route, isNull);
    expect(h.s.arrived, isFalse);
    expect(h.s.playing, isFalse);
    // and from a route still under way, the same
    h.nav.startTo(other.id);
    h.mv.hits.add('poi', h.v.tripTarget, Path()..addRect(const Rect.fromLTWH(20, 0, 10, 10)));
    h.map.mapTap(const Offset(25, 5));
    expect(h.s.place, h.v.tripTarget);
    expect(h.s.route, isNull);
  });

  testWidgets('the sheet shows the tapped place, not an arrival', (tester) async {
    final h = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await h.step(20);
    final nav = h.c.read(navProvider.notifier), s = h.c.read(navProvider), map = h.c.read(mapProvider.notifier);
    final start = scenarioStart(s.v);
    nav.refineAt(start.lv, start.x, start.y);
    nav.debugScrub(1000);
    nav.confirmArrived();
    await h.step(5);
    expect(find.textContaining('You have arrived at'), findsOneWidget);
    h.c.read(mapProvider).cam.zoom = 5 * s.v.ratio;
    final other = s.v.places.firstWhere((p) => p.kind == 'store' && p.status == 'open' && p.id != s.v.tripTarget);
    h.c.read(mapProvider).hits.add('poi', other.id, Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)));
    map.mapTap(const Offset(5, 5));
    await h.step(5);
    expect(find.textContaining('You have arrived'), findsNothing);
    expect(find.text(other.name), findsOneWidget);
    expect(find.text('Get directions'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Choose a mall: the search filters the cards', (tester) async {
    final h = await pumpApp(tester);
    h.c.read(routerProvider).push('/malls');
    await h.step(30);
    Finder card(String id) => find.byKey(ValueKey('mall-$id'), skipOffstage: false);
    await tester.enterText(find.byKey(const ValueKey('mall-search')), 'bridge');
    await tester.pump();
    expect(card('meridian'), findsOneWidget);
    expect(card('spire'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('mall-search')), 'rooftop garden');
    await tester.pump();
    expect(card('spire'), findsOneWidget);
    expect(card('meridian'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('mall-search')), 'zzz');
    await tester.pump();
    expect(find.text('No mall matches "zzz".'), findsOneWidget);
  });
}

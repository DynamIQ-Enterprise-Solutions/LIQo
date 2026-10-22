// Lifts, escalators and stairs as places (the Elevators category), the stairs
// rule under Fastest (stairs only when they save about two minutes), Shortest,
// Avoid stairs, and the evacuation (from the demo's stairs_test).
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';
import 'package:liqo_mobile/features/search/providers/search_providers.dart';

import '../support/harness.dart';
import '../support/spots.dart';

void main() {
  group('the nearest lifts', () {
    test('the lifts on this floor, nearest first, as places you can route to', () {
      final h = Harness();
      h.at(spot(h.v, 0, 750, 350)); // the Grand Court
      h.nav.showNearest('lift');
      final n = h.s.near!;
      expect(n.type, 'lift');
      expect(n.ids, isNotEmpty);
      double? last;
      for (final id in n.ids) {
        expect(id, startsWith('CONN:'));
        final p = h.s.placeById(id)!;
        expect(p.kind, 'conn');
        expect(p.cat, 'lift');
        expect(p.lv, h.s.user!.lv);
        expect(h.text.placeSub(p), startsWith('Lift · '));
        final d = h.s.distOf(p)!;
        if (last != null) expect(d, greaterThanOrEqualTo(last));
        last = d;
      }
      h.nav.startTo(n.ids.first);
      expect(h.s.route, isNotNull);
      expect(h.s.route!.placeId, n.ids.first);
      // a lift is not a visited place
      expect(h.c.read(visitsProvider('bayview')), isEmpty);
    });

    test('with no position there is nothing nearest to show', () {
      final h = Harness();
      h.nav.showNearest('lift');
      expect(h.s.near!.ids, isEmpty);
    });
  });

  group('the stairs rule', () {
    test('Fastest: stairs only when they save about two minutes; Shortest: the least walking', () {
      var seen = 0;
      for (final mall in ['bayview', 'meridian', 'spire']) {
        final h = Harness(mall: mall), from = scenarioStart(h.v);
        h.at(from);
        for (final p in h.v.places.where((p) => p.kind == 'store' && p.status == 'open').take(60)) {
          final withStairs = routesTo(h.s.gr, p.id, p.nodes, from, false, throughStores: true);
          if (withStairs.isEmpty || !NavController.usesStairs(withStairs.first)) continue;
          final noStairs = routesTo(h.s.gr, p.id, p.nodes, from, false, throughStores: true, avoid: {'stairs'});
          h.at(from);
          h.nav.startTo(p.id);
          final chosen = h.s.route!;
          if (noStairs.isNotEmpty && noStairs.first.total < withStairs.first.total + NavController.stairsSaveM) {
            // the stairs save too little: the stairs-free way, with the stairs way still offered
            expect(NavController.usesStairs(chosen), isFalse, reason: '$mall ${p.id}');
            expect(chosen.total, closeTo(noStairs.first.total, .01));
            expect(h.s.routes.any(NavController.usesStairs), isTrue, reason: 'the stairs way is an alternative');
          } else {
            expect(NavController.usesStairs(chosen), isTrue, reason: '$mall ${p.id}: the stairs save more than 2 min');
          }
          // Shortest: the least walking wins, with no stairs rule
          h.options.setMetric(RouteOpts.shortest);
          final shortest = routesTo(h.s.gr, p.id, p.nodes, from, false, throughStores: true, metric: RouteOpts.shortest).first;
          expect(h.s.route!.verts.map((x) => '${x.lv}/${x.x}/${x.y}').join(), shortest.verts.map((x) => '${x.lv}/${x.x}/${x.y}').join(), reason: '$mall ${p.id}');
          h.options.setMetric(RouteOpts.fastest);
          h.nav.stop();
          seen++;
          if (seen >= 6) break;
        }
      }
      expect(seen, greaterThan(0), reason: 'some trip somewhere uses the stairs');
    });

    test('Shortest walks no further than Fastest, and rides count as next to nothing', () {
      final h = Harness();
      final from = scenarioStart(h.v), p = h.v.placeById('3-M1')!;
      double walked(RouteT r) {
        var m = 0.0;
        for (var i = 1; i < r.verts.length; i++) {
          final s = r.seg[i];
          if (s != null && s.kind == 'hop') {
            if (s.ctype == 'stairs' || s.ctype == 'ramp') m += s.d;
          } else {
            m += s?.len ?? 0;
          }
        }
        return m;
      }

      final fast = routesTo(h.s.gr, p.id, p.nodes, from, false, throughStores: true).first;
      final short = routesTo(h.s.gr, p.id, p.nodes, from, false, throughStores: true, metric: RouteOpts.shortest).first;
      expect(walked(short), lessThanOrEqualTo(walked(fast) + 1e-6));
    });

    test('Avoid stairs and wheelchair routes are untouched; the evacuation never takes a lift', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      h.options.setAvoidStairs(true);
      expect(h.s.route, isNotNull);
      expect(NavController.usesStairs(h.s.route!), isFalse);
      h.options.setAvoidStairs(false);
      final steps = stepsOf(h.s.route!);
      h.nav.debugScrub((steps.firstWhere((s) => s.kind == 'hop').endAt + 30) / h.s.route!.total * 1000); // indoors, upstairs
      h.nav.startEmergency();
      expect(h.s.evac, isNotNull);
      expect(h.s.evac!.route!.seg.any((s) => isHop(s) && s!.ctype == 'lift'), isFalse);
      h.nav.stopEmergency();
    });
  });
}

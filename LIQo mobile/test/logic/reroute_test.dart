// Find another way, Get help, and the evacuation (from the demo's reroute_test;
// reported problems, marking a blocked path and "This exit is blocked" were left
// out on 2026-10-22, and so were their tests).
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/reroute.dart';
import 'package:liqo_mobile/core/engine/routing.dart';

import '../support/harness.dart';
import '../support/spots.dart';

/// Bayview, from the terminal to Opal Comics on level 3, walked to [m] metres.
Harness at(double m) {
  final h = Harness();
  h.goFrom(scenarioStart(h.v), '3-M1');
  h.nav.debugScrub(m / h.s.route!.total * 1000);
  return h;
}

/// Metres a little before the first step of a kind (e.g. 'hop').
double metresTo(Harness h, String kind) {
  final steps = stepsOf(h.s.route!);
  final i = steps.indexWhere((s) => s.kind == kind);
  return i <= 0 ? 0 : steps[i - 1].endAt - 5;
}

/// Metres just past the end of the first ride.
double pastTheRide(Harness h) {
  final steps = stepsOf(h.s.route!);
  return steps.firstWhere((s) => s.kind == 'hop').endAt + 30;
}

Set<String> hopTypes(RouteT r) => {for (final s in r.seg) if (isHop(s)) s!.ctype!};
Set<String> hopConns(RouteT r) => {for (final s in r.seg) if (isHop(s)) s!.conn!};

void main() {
  group('find another way', () {
    test('offers the current way plus ways around the stretch ahead, and keeps nothing', () {
      final h = at(120); // outdoors, on the walk from the terminal
      h.nav.findAnotherWay();
      final s = h.s.reroute!, ahead = s.avoid!;
      expect(ahead.edges, isNotEmpty);
      expect(s.options.first.kind, 'current');
      expect(routeHits(s.options.first.route, [ahead]), isTrue);
      final arounds = s.options.where((o) => o.kind == 'around').toList();
      expect(arounds, isNotEmpty);
      expect(arounds.length, lessThanOrEqualTo(3));
      for (final o in arounds) {
        expect(routeHits(o.route, [ahead]), isFalse, reason: 'way around ${o.n}');
      }
      // ways around are different from each other and sorted shortest first
      for (var i = 1; i < arounds.length; i++) {
        expect(routeSimilarity(arounds[i].route, arounds[i - 1].route), lessThanOrEqualTo(.8));
        expect(arounds[i].route.total, greaterThanOrEqualTo(arounds[i - 1].route.total));
      }
      expect(s.options[s.sel].kind, 'around'); // the best way around is preselected
    });

    test('a lift / escalator just ahead is gone around as a whole', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      h.nav.debugScrub(metresTo(h, 'hop') / h.s.route!.total * 1000);
      final before = hopConns(h.s.route!);
      h.nav.findAnotherWay();
      final ahead = h.s.reroute!.avoid!;
      expect(ahead.conns, hasLength(1));
      expect(before, contains(ahead.conns.single));
      h.nav.confirmReroute();
      expect(hopConns(h.s.route!), isNot(contains(ahead.conns.single)));
    });

    test('Go this way blocks nothing: later routes are the usual ones', () {
      final h = at(120);
      h.nav.findAnotherWay();
      h.nav.confirmReroute();
      expect(h.s.reroute, isNull);
      final hyper = h.v.placeById('G-EHM')!;
      h.nav.startTo(hyper.id);
      expect(h.s.route!.total, routesTo(h.s.gr, hyper.id, hyper.nodes, h.s.user!.pos, false, throughStores: true).first.total);
    });

    test('switching back to the current way, and cancelling, both work', () {
      final h = at(120);
      final saved = h.s.route!;
      h.nav.findAnotherWay();
      h.nav.previewOption(0);
      expect(h.s.route, same(h.s.reroute!.options[0].route));
      h.nav.cancelReroute();
      expect(h.s.route, same(saved));
      expect(h.s.reroute, isNull);
    });

    test('similar places are offered, and Get help goes to an information desk', () {
      final h = at(120);
      final dest = h.v.placeById('3-M1')!;
      h.nav.findAnotherWay();
      final s = h.s.reroute!;
      expect(s.nearby, isNotEmpty);
      for (final p in s.nearby) {
        expect(p.cat, dest.cat);
        expect(p.id, isNot(dest.id));
      }
      h.nav.help();
      expect(h.s.placeById(h.s.place!)!.cat, 'info');
      expect(h.s.helpNote, isTrue);
      expect(h.s.reroute, isNull);
    });

    test('nothing to find another way for during an evacuation or after arriving', () {
      final h = at(120);
      h.nav.confirmArrived();
      h.nav.findAnotherWay();
      expect(h.s.reroute, isNull);
    });
  });

  group('evacuation', () {
    test('from level 3: stairs or escalators only, to an exit', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      h.nav.debugScrub(pastTheRide(h) / h.s.route!.total * 1000);
      expect(h.s.user!.lv, greaterThan(h.v.ground));
      h.nav.startEmergency();
      final e = h.s.evac!;
      expect(e.outside, isFalse);
      expect(e.refuge, isFalse);
      expect(e.exit, isNotNull);
      expect(hopTypes(e.route!), isNot(contains('lift')));
      expect(h.s.route!.verts.last.lv, h.v.ground);
    });

    test('wheelchair users upstairs go to a refuge point; on the ground floor straight out', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      h.nav.debugScrub(pastTheRide(h) / h.s.route!.total * 1000);
      h.settings.setWheelchair(true);
      h.nav.startEmergency();
      expect(h.s.evac!.refuge, isTrue);
      expect(h.s.route!.seg.where(isHop), isEmpty);
      h.nav.stopEmergency();
      h.at(spot(h.v, 0, 750, 350)); // the Grand Court, ground floor
      h.nav.startEmergency();
      expect(h.s.evac!.refuge, isFalse);
      expect(h.s.evac!.exit, isNotNull);
    });

    test('already outside: no route, just keep away', () {
      final h = Harness();
      h.at(scenarioStart(h.v)); // the terminal
      h.nav.startEmergency();
      expect(h.s.evac!.outside, isTrue);
      expect(h.s.route, isNull);
    });

    test('with no position yet, "Where are you?" comes first, then the way out', () {
      final h = Harness();
      h.nav.startEmergency();
      expect(h.s.emergency, isTrue);
      expect(h.s.evac, isNull);
      expect(h.s.locSheet, isTrue);
      h.nav.locAtFloor(1);
      expect(h.s.evac, isNotNull);
      expect(h.s.evac!.route, isNotNull);
    });

    test('other trips cannot replace the way out; Back does not stop it', () {
      final h = Harness();
      h.goFrom(scenarioStart(h.v), '3-M1');
      h.nav.debugScrub(pastTheRide(h) / h.s.route!.total * 1000);
      h.nav.startEmergency();
      final r = h.s.route;
      h.nav.startTo('G-EHM');
      expect(h.s.route, same(r));
      h.nav.showNearest('restroom');
      expect(h.s.route, same(r));
      h.nav.stop();
      expect(h.s.route, same(r));
      h.nav.handleBack();
      expect(h.s.emergency, isTrue);
      h.nav.stopEmergency();
      expect(h.s.emergency, isFalse);
    });
  });
}

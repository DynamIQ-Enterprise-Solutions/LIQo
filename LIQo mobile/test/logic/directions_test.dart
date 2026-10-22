// Turn-by-turn directions with landmarks, the buzz before each turn, and the
// map facing the way you walk (from the demo's directions_test, re-targeted to
// the offline malls).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/directions.dart';
import 'package:liqo_mobile/core/engine/graph.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/engine/util.dart';
import 'package:liqo_mobile/features/map/providers/map_provider.dart';
import 'package:liqo_mobile/features/map/services/map_constants.dart';

import '../support/harness.dart';
import '../support/spots.dart';

/// A Bayview trip from the terminal to a level-3 shop of the Main Mall: outdoors, then up.
Harness upstairsTrip() {
  final h = Harness();
  final shop = h.v.places.firstWhere((p) => p.lv == 2 && p.wing == 'M' && p.kind == 'store' && p.status == 'open');
  h.goFrom(scenarioStart(h.v), shop.id);
  return h;
}

void main() {
  group('directionsOf', () {
    test('ends with arriving, and every direction is placed along the route in order', () {
      final h = upstairsTrip(), r = h.s.route!, dirs = directionsOf(r, h.v);
      expect(dirs.last.kind, 'arrive');
      expect(dirs.last.atM, r.total);
      for (var i = 1; i < dirs.length; i++) {
        expect(dirs[i].atM, greaterThanOrEqualTo(dirs[i - 1].atM));
      }
      // the approaches are the walking; the rides themselves are not walked
      var rides = 0.0;
      for (var i = 1; i < r.cum.length; i++) {
        if (isHop(r.seg[i])) rides += r.cum[i] - r.cum[i - 1];
      }
      expect(rides, greaterThan(0));
      expect(dirs.fold(0.0, (m, d) => m + d.approach), closeTo(r.total - rides, .01));
    });

    test('turns are where the route bends, and left/right matches the geometry', () {
      final h = upstairsTrip(), r = h.s.route!, dirs = directionsOf(r, h.v);
      final turns = dirs.where((d) => d.isTurn).toList();
      expect(turns, isNotEmpty);
      for (final t in turns) {
        final i = r.cum.indexWhere((c) => (c - t.atM).abs() < .01);
        expect(i, greaterThan(0), reason: 'a turn sits on a route vertex');
        final a = r.verts[i - 1], b = r.verts[i], c = r.verts[i + 1];
        final h1 = math.atan2(b.y - a.y, b.x - a.x), h2 = math.atan2(c.y - b.y, c.x - b.x);
        var diff = h2 - h1;
        while (diff > math.pi) {
          diff -= 2 * math.pi;
        }
        while (diff <= -math.pi) {
          diff += 2 * math.pi;
        }
        expect(diff.abs() * 180 / math.pi, greaterThanOrEqualTo(turnDeg));
        expect(t.turn!.endsWith(diff > 0 ? 'right' : 'left'), isTrue, reason: '${t.turn} at ${t.atM}');
        if (t.landmark != null) {
          final p = h.s.placeById(t.landmark!)!;
          expect(hypot(p.door[0] - b.x, p.door[1] - b.y), lessThanOrEqualTo(landmarkM));
          expect(t.side, sideOf(h1, p.door[0] - b.x, p.door[1] - b.y));
        }
      }
    });

    test('the ride up is one direction, and the metres count down as you walk', () {
      final h = upstairsTrip(), r = h.s.route!, dirs = h.s.directions;
      final hop = dirs.firstWhere((d) => d.isUpDown);
      expect(hop.to - hop.from, greaterThanOrEqualTo(1));
      final before = upcoming(dirs, hop.atM - .5)!, after = upcoming(dirs, hop.atM + 1)!;
      expect(before.$2, same(hop));
      expect(after.$1, greaterThan(before.$1));
      h.nav.debugScrub((hop.atM - 30) / r.total * 1000);
      expect(h.text.dirSub(hop, h.s.route!.progress), contains('in 30 m'));
      expect(h.text.dirSub(hop, h.s.route!.progress), contains(h.text.connName(hop.id)));
    });

    test('wording: landmark first, metres second; arriving is an expectation', () {
      final h = upstairsTrip(), dirs = h.s.directions, t = h.text;
      final turn = dirs.firstWhere((d) => d.isTurn && d.landmark != null, orElse: () => dirs.firstWhere((d) => d.isTurn));
      final title = t.dirTitle(turn);
      expect(title, startsWith(turn.turn!.startsWith('slight') ? 'Bear' : 'Turn'));
      if (turn.landmark != null) expect(title, contains(' at ${t.placeName(turn.landmark)}'));
      expect(t.dirSub(turn, 0), startsWith('in '));
      final last = dirs.last;
      expect(t.dirTitle(last), last.side == null ? 'Arrive at ${t.placeName(last.landmark)}' : '${t.placeName(last.landmark)} · should be on your ${last.side}');
    });

    test('a slight bend is a turn only at a fork; a corridor that merely curves is followed without a word', () {
      var slight = 0, bends = 0;
      for (final mall in ['bayview', 'meridian', 'spire']) {
        final h = Harness(mall: mall), from = scenarioStart(h.v);
        for (final p in h.v.places.where((p) => p.kind == 'store' && p.status == 'open').take(40)) {
          h.goFrom(from, p.id);
          final r = h.s.route;
          if (r == null) continue;
          final seen = <double>{};
          for (final d in h.s.directions.where((d) => d.isTurn)) {
            if (!d.turn!.startsWith('slight')) continue;
            if (!seen.add(d.atM)) continue;
            slight++;
            // where it is said, another walkway leaves the spot (a choice to make)
            final at = pointAt(r, d.atM), k = nk(at.lv, at.pos[0], at.pos[1]);
            final others = (h.s.gr.adj[k] ?? const <Edge>[]).where((x) => x.kind != 'hop').length;
            expect(others, greaterThanOrEqualTo(3), reason: '$mall ${p.id}: a slight bend at ${d.atM.round()} m with nothing else leaving it');
          }
          // and the bends of 30–50° that are not turns: every one is a plain curve (the route is the straightest way on)
          for (var i = 1; i + 1 < r.verts.length; i++) {
            final a = r.verts[i - 1], b = r.verts[i], c = r.verts[i + 1];
            if (a.lv != b.lv || b.lv != c.lv || isHop(r.seg[i]) || isHop(r.seg[i + 1]) || r.seg[i + 1]?.kind != 'walk') continue;
            final l1 = hypot(b.x - a.x, b.y - a.y), l2 = hypot(c.x - b.x, c.y - b.y);
            if (l1 < minLegM || l2 < minLegM) continue;
            final h1 = math.atan2(b.y - a.y, b.x - a.x), h2 = math.atan2(c.y - b.y, c.x - b.x);
            var diff = h2 - h1;
            while (diff > math.pi) {
              diff -= 2 * math.pi;
            }
            while (diff <= -math.pi) {
              diff += 2 * math.pi;
            }
            final deg = diff.abs() * 180 / math.pi;
            if (deg < turnDeg || deg >= 50) continue;
            bends++;
            final said = h.s.directions.any((d) => d.isTurn && (d.atM - r.cum[i]).abs() < .01);
            expect(said, isFork(h.s.gr, a, b, c, h1), reason: '$mall ${p.id}: bend of ${deg.round()}° at ${r.cum[i].round()} m');
          }
          h.nav.stop();
        }
      }
      expect(bends, greaterThan(0), reason: 'Spire has slight bends round its atrium');
      // Spire's demo trip from the lobby starts with a 45° bend of the corridor: not a turn
      final spire = Harness(mall: 'spire');
      spire.goFrom(scenarioStart(spire.v), spire.v.tripTarget);
      expect(spire.s.directions.first.isTurn, isFalse);
      expect(slight, lessThan(bends), reason: 'most of those bends are just the corridor curving');
    });

    test('every mall: directions exist for the demo trip, with no empty titles', () {
      for (final mall in ['bayview', 'meridian', 'spire']) {
        final h = Harness(mall: mall);
        h.goFrom(scenarioStart(h.v), h.v.tripTarget);
        for (final d in h.s.directions) {
          expect(h.text.dirTitle(d), isNotEmpty, reason: '$mall ${d.kind}');
        }
        expect(h.s.directions.last.kind, 'arrive', reason: mall);
      }
    });
  });

  test('a buzz about 20 m before each turn and each ride, a different one per kind, once', () {
    final h = upstairsTrip(), r = h.s.route!, buzzes = h.haptics.cues;
    final dirs = h.s.directions, first = dirs.firstWhere((d) => d.isTurn || d.isUpDown);
    h.walkTo(first.atM - 40);
    expect(buzzes, isEmpty);
    h.walkTo(first.atM - 15);
    expect(buzzes, hasLength(1));
    expect(buzzes.single, first.isTurn ? (first.turn!.endsWith('left') ? 'left' : 'right') : 'updown');
    h.walkTo(first.atM - 10);
    expect(buzzes, hasLength(1)); // not again
    // every turn and ride gets exactly one buzz over the whole walk
    for (var m = 0.0; m < r.total; m += 2) {
      h.walkTo(m);
    }
    expect(buzzes.length, dirs.where((d) => d.isTurn || d.isUpDown).length);
    // vibration off: silent
    final dest = h.s.place!;
    h.nav.stop();
    h.settings.setVibration(false);
    h.goFrom(scenarioStart(h.v), dest);
    buzzes.clear();
    for (var m = 0.0; m < h.s.route!.total; m += 2) {
      h.walkTo(m);
    }
    expect(buzzes, isEmpty);
  });

  test('heading-up: while walking, the map turns to face the way you go; switching it off turns it back', () {
    final h = upstairsTrip();
    h.map.setHeadingUp(true);
    h.walkTo(5); // a few metres in, so there is a way you are facing (the demo trip started 2 m in)
    h.mv.cam
      ..ex = 0
      ..zoom = 4 * h.v.ratio;
    for (var i = 0; i < 60; i++) {
      h.nav.syncUser();
    }
    final hd = h.s.heading!, cam = h.mv.cam;
    final target = MapController.nearRot(-math.pi / 2 - hd - yaw, cam.rot);
    expect(cam.rot, closeTo(target, .02));
    // forward in the mall is up on the screen
    final yw = yaw + cam.rot, screenDy = math.cos(hd) * math.sin(yw) + math.sin(hd) * math.cos(yw);
    expect(screenDy, closeTo(-1, .02));
    h.map.setHeadingUp(false);
    h.map.tick(Duration.zero);
    h.map.tick(const Duration(seconds: 1));
    expect(cam.rot, closeTo(0, .001));
  });
}

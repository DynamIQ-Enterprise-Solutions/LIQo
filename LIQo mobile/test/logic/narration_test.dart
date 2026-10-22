// Directions worded like a person: landmark first, "then" between close
// directions, metres only where there is nothing to name, what you should see
// after a ride, and the pause and ride checks (from the demo's narration_test;
// the app has no voice, so these are the prompts, the card and the screen reader).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/directions.dart';
import 'package:liqo_mobile/core/engine/util.dart';
import 'package:liqo_mobile/features/navigation/services/narration.dart';

import '../support/harness.dart';
import '../support/spots.dart';

/// Bayview: from the terminal, outdoors to the West Court, in, and up the escalator to Opal Comics on level 3.
Harness upstairsTrip() {
  final h = Harness()..nav.setMapVisible(true);
  h.nav.closeLocation(); // the first visit asks where you are; the test says it below
  h.goFrom(scenarioStart(h.v), '3-M1');
  return h;
}

/// Ticks the clock in 100 ms steps while [go] holds (at most [maxMs]).
int run(Harness h, int t, bool Function() go, {int maxMs = 120000}) {
  final t0 = t;
  while (go() && t - t0 < maxMs) {
    h.nav.tick(Duration(milliseconds: t += 100));
  }
  return t;
}

void main() {
  group('sentences', () {
    test('outdoors there is nothing to name, so about how far; at a door, the door', () {
      final h = upstairsTrip(), t = h.text;
      expect(h.v.placeById('3-M1')!.name, 'Opal Comics');
      expect(t.narrate(0).text, matches(RegExp(r'^Walk straight for about \d+0 m outside, then turn left\.$')));
      final door = h.s.directions.indexWhere((d) => d.kind == 'enter');
      expect(t.narrate(door).text, 'Walk straight towards the West Court south doors, then go in.');
      expect(t.narrate(door).chained, isNull);
      final hop = h.s.directions.indexWhere((d) => d.isUpDown);
      expect(t.narrate(hop).text, 'Walk straight towards West Court escalators, then take it up to level 3.');
    });

    test('a direction within 25 m of the one before is said with it, and the arrival names the side', () {
      final h = upstairsTrip(), t = h.text, dirs = h.s.directions;
      for (var i = 0; i + 1 < dirs.length; i++) {
        final n = t.narrate(i);
        if (dirs[i].kind != 'arrive' && dirs[i + 1].atM - dirs[i].atM <= thenM) {
          expect(n.chained, i + 1, reason: '$i');
        } else {
          expect(n.chained, isNull, reason: '$i');
        }
      }
      final last = t.narrate(dirs.length - 2);
      expect(last.chained, dirs.length - 1);
      expect(last.text, 'Walk straight towards Maple Salon, then turn right. You should see Opal Comics on your left; go in through its doors.');
    });

    test('every mall: a turn at a landmark is "towards <landmark>" with no metres', () {
      for (final mall in ['bayview', 'meridian', 'spire']) {
        final h = Harness(mall: mall);
        h.goFrom(scenarioStart(h.v), h.v.tripTarget);
        final dirs = h.s.directions, t = h.text;
        for (var i = 0; i < dirs.length; i++) {
          final d = dirs[i], text = t.narrate(i).text;
          expect(text, endsWith('.'), reason: '$mall $i');
          expect(text[0], text[0].toUpperCase(), reason: '$mall $i');
          if (d.isTurn && d.landmark != null && d.approach >= shortApproachM) {
            expect(text, contains('towards ${t.placeName(d.landmark)}'), reason: '$mall $i');
            expect(text, isNot(contains(RegExp(r'\d+ m\b'))), reason: '$mall $i: $text');
          }
          if (d.isUpDown) expect(text, contains(d.to > d.from ? 'up to ' : 'down to '), reason: '$mall $i: $text');
        }
      }
    });
  });

  group('what you should see', () {
    test('after the escalator: the card names the places really around the dot, by hand, for 20 m', () {
      final h = upstairsTrip(), t = h.text;
      final hop = h.s.directions.firstWhere((d) => d.isUpDown);
      // up to the escalator, the whole ride, and on
      var m = hop.atM - 30;
      for (; m < hop.atM + 2 || h.s.transit != null; m += .5) {
        h.walkTo(m);
        h.s.checking = false; // the ride question is the next test's
      }
      final at = h.s.rideEndAt!;
      expect(at.$3, 2);
      expect(h.v.levels[at.$3].name, 'Level 3');
      final items = t.seeAround(excludeConn: at.$4, max: 2);
      final line = h.text.afterRideLine;
      if (items.isEmpty) {
        expect(line, isNull);
      } else {
        expect(line, startsWith('If you see '));
        expect(line, endsWith("you're in the right place"));
        for (final (name, _) in items) {
          expect(line, contains(name));
        }
        expect(line, isNot(contains(' is on your ')));
      }
      h.walkTo(at.$2 + 10);
      if (items.isNotEmpty) expect(h.text.afterRideLine, startsWith('If you see '));
      h.walkTo(at.$2 + 25);
      expect(h.text.afterRideLine, isNull);
    });

    test('hands and "ahead" follow the geometry', () {
      final h = Harness(), t = h.text;
      final info = h.v.places.firstWhere((p) => p.cat == 'info');
      final n = h.s.gr.nodes[info.nodes.first]!;
      for (final hd in [0.0, math.pi / 2, math.pi, -math.pi / 3]) {
        final items = t.surroundings(n.lv, n.x, n.y, hd);
        expect(items, isNotEmpty);
        for (final (name, rel) in items) {
          final p = h.v.places.where((p) => p.name == name && p.lv == n.lv).firstOrNull;
          if (p == null) continue; // a lift or escalator
          final dx = p.door[0] - n.x, dy = p.door[1] - n.y;
          var a = math.atan2(dy, dx) - hd;
          while (a > math.pi) {
            a -= 2 * math.pi;
          }
          while (a <= -math.pi) {
            a += 2 * math.pi;
          }
          final deg = a.abs() * 180 / math.pi;
          if (hypot(dx, dy) < 2) {
            expect(rel, 'near');
          } else if (deg < 25) {
            expect(rel, 'ahead', reason: name);
          } else if (deg > 135) {
            expect(rel, 'behind', reason: name);
          } else {
            expect(rel, sideOf(hd, dx, dy), reason: name);
          }
        }
      }
    });

    test('reaching the escalator stops the walk and asks "Are you at ...?"; it carries on by itself, once per ride', () {
      final h = upstairsTrip(), t = h.text, s = h.s;
      final hop = s.directions.indexWhere((d) => d.isUpDown), d = s.directions[hop];
      h.nav.debugScrub((d.atM - 5) / s.route!.total * 1000);
      h.nav.start();
      h.nav.tickerStarted();
      var ms = run(h, 0, () => s.playing, maxMs: 60000);
      expect(s.playing, isFalse);
      expect(s.checking, isTrue);
      expect(s.checkRide, hop);
      expect(s.prompt, 'ride');
      expect(t.checkRideName, t.connName(d.id));
      expect(s.transit, isNotNull); // the dot stands at the foot of the escalator
      final q = h.text.checkQuestion();
      expect(q, startsWith('Are you at ${t.connName(d.id)}? You should be on ground floor'));
      expect(q, endsWith("If that's right, take the escalator up to level 3."));
      expect(q, isNot(contains('see ${t.connName(d.id)}'))); // not told to look for what it is standing at
      expect(s.paused, isTrue);
      // the demo walk answers by itself after two seconds
      final t0 = ms;
      ms = run(h, ms, () => !s.playing, maxMs: 5000);
      expect(ms - t0, inInclusiveRange(2000, 2300));
      expect(s.playing, isTrue);
      expect(s.checking, isFalse);
      expect(s.paused, isFalse);
      // riding on: not asked again; on the landing the card says to keep going; off the top, what to expect
      final landings = <String>{};
      ms = run(h, ms, () {
        final l = h.text.landingShown;
        if (l != null) landings.add(l);
        return s.playing && (s.transit != null || s.user!.lv == h.v.ground);
      });
      expect(s.user!.lv, isNot(h.v.ground));
      expect(s.transit, isNull);
      expect(s.checking, isFalse);
      expect(landings, {'Level 2 · keep going up to level 3'});
      // No at the foot of the escalator opens "Where are you?"
      h.nav.debugScrub((d.atM - 5) / s.route!.total * 1000);
      h.nav.start();
      run(h, ms, () => s.playing, maxMs: 10000);
      expect(s.checking, isTrue); // a new ride after a scrub asks again
      h.nav.answerNo();
      expect(s.locSheet, isTrue);
      expect(s.checking, isFalse);
    });

    test('the ride question waits for the Map tab: no answer by itself while the map is not shown', () {
      final h = upstairsTrip(), s = h.s;
      final d = s.directions.firstWhere((d) => d.isUpDown);
      h.nav.debugScrub((d.atM - 5) / s.route!.total * 1000);
      h.nav.setMapVisible(false);
      h.nav.start();
      h.nav.tickerStarted();
      var ms = run(h, 0, () => s.playing, maxMs: 60000);
      expect(s.checking, isTrue);
      ms = run(h, ms, () => true, maxMs: 6000);
      expect(s.checking, isTrue, reason: 'still waiting while another tab is shown');
      h.nav.setMapVisible(true);
      final t0 = ms;
      ms = run(h, ms, () => !s.playing, maxMs: 5000);
      expect(ms - t0, inInclusiveRange(2000, 2300));
      expect(s.playing, isTrue);
    });

    test('the pause check asks and describes; No opens "Where are you?"', () {
      final h = upstairsTrip(), s = h.s;
      h.nav.start();
      h.walkTo(300);
      h.nav.pause();
      expect(s.playing, isFalse);
      expect(s.checking, isTrue);
      expect(h.text.checkQuestion(), startsWith('Are you here? You should be on ground floor'));
      expect(s.prompt, 'here');
      h.nav.answerYes();
      expect(s.prompt, isNull);
      expect(s.checking, isFalse);
      expect(s.playing, isFalse);
      h.nav.resume();
      expect(s.playing, isTrue);
      h.nav.pause();
      h.nav.answerNo();
      expect(s.checking, isFalse);
      expect(s.locSheet, isTrue);
      expect(s.locFirst, isFalse);
      // relocating restarts the route from there, still paused
      final atm = h.v.places.firstWhere((p) => p.cat == 'atm' && p.lv == h.v.ground);
      h.nav.locAtPlace(atm.id);
      expect(s.locSheet, isFalse);
      expect(s.playing, isFalse);
      expect(s.route!.progress, 0);
      final node = s.gr.nodes[atm.nodes.first]!;
      expect((s.user!.x, s.user!.y), (node.x, node.y));
      // the scrubber clears the question too
      h.nav.resume();
      h.nav.pause();
      h.nav.debugScrub(500);
      expect(s.checking, isFalse);
      h.nav.pause(); // not playing: nothing to pause
      expect(s.checking, isFalse);
    });

    test('the check says one landmark and the one next thing, never the directions after it', () {
      var chainedSeen = 0, crowdedSeen = 0;
      for (final mall in ['bayview', 'meridian', 'spire']) {
        final h = Harness(mall: mall), s = h.s;
        h.goFrom(scenarioStart(h.v), h.v.tripTarget);
        h.nav.start();
        for (var pct = 2; pct < 100; pct += 3) {
          h.walkTo(s.route!.total * pct / 100);
          if (!s.playing) {
            h.nav.answerYes(); // at a lift, escalator or stairs: ride on
            continue;
          }
          final next = s.nextDirection;
          if (next == null) continue;
          final t = h.text, full = t.narrate(next.$1), crowd = t.seeAround();
          if (full.chained != null) chainedSeen++;
          if (crowd.length > 1) crowdedSeen++;
          h.nav.pause();
          final q = h.text.checkQuestion();
          // one landmark: "with X on your left." never "with X, Y and Z"
          final withPart = RegExp(r', with (.+?)\.').firstMatch(q)?.group(1) ?? '';
          expect(withPart, isNot(contains(', ')), reason: '$mall at $pct%: $q');
          expect(withPart, isNot(contains(' and ')), reason: '$mall at $pct%: $q');
          // one next thing: the approach and its action at most, no ", then <the direction after>"
          final next1 = t.narrate(next.$1, chain: false).text;
          expect(q, endsWith(" If that's right, ${lowerFirst(next1)}"), reason: '$mall at $pct%');
          if (full.chained != null) expect(q, isNot(endsWith(full.text.substring(1))), reason: '$mall at $pct%: the chained direction is not in the check');
          h.nav.resume();
          expect(s.playing, isTrue);
        }
      }
      expect(chainedSeen, greaterThan(0), reason: 'some check happened before a chained pair');
      expect(crowdedSeen, greaterThan(0), reason: 'some check happened with several things around');
    });
  });

  test('cue lines along the way: each once, in its place, gone after six seconds', () {
    // Bayview: along the Main Mall's north spine, shops on both sides, to the hypermart
    final h = Harness(), s = h.s;
    h.goFrom(spot(h.v, 0, 480, 300), 'G-EHM');
    final r = s.route!;
    final seen = <String>[];
    String? last;
    for (var m = 0.0; m < r.total; m += 1) {
      h.walkTo(m);
      h.s.checking = false;
      final c = s.cueLine;
      if (c != null && c != last) seen.add(c);
      last = c;
    }
    expect(seen, isNotEmpty);
    expect(seen.where((c) => c.startsWith('You should be passing ')), isNotEmpty);
    expect(seen.last, 'Almost there');
    // shown for six seconds of the clock, then gone
    s.cueLineAt = const Duration(seconds: 10);
    s.now = const Duration(seconds: 12);
    expect(s.cueShown, isNotNull);
    h.nav.tick(const Duration(seconds: 16, milliseconds: 100));
    expect(s.cueShown, isNull);
    expect(upcoming(s.directions, r.total)!.$2.kind, 'arrive');
  });
}

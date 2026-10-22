// Not where the app expected: on a "No, I'm somewhere else" in the pause or ride
// check, a buzz (when vibration is on) and "Where are you?" with the line
// "Looks like you've drifted off the way". From the demo's wrong_way_test; the
// sound, the voice queue and the demo panel's wrong turn were left out.
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/i18n/tagalog.dart';

import '../support/harness.dart';
import '../support/spots.dart';

const line = "Looks like you've drifted off the way. Let's start again from here.";

Harness trip() {
  final h = Harness();
  h.goFrom(scenarioStart(h.v), '3-M1');
  h.nav.start();
  return h;
}

void main() {
  test('"No, I\'m somewhere else" in the pause check: one buzz, then "Where are you?" with the line', () {
    final h = trip(), s = h.s;
    h.walkTo(300);
    h.nav.pause();
    h.haptics.cues.clear();
    h.nav.answerNo();
    expect(h.haptics.cues, ['alert']);
    expect(s.locSheet, isTrue);
    expect(s.locDrift, isTrue);
    h.nav.closeLocation();
    expect(s.locDrift, isFalse, reason: 'the sheet forgets the drift when it closes');
  });

  test('vibration off: no buzz, but "Where are you?" still opens', () {
    final h = trip(), s = h.s;
    h.settings.setVibration(false);
    h.walkTo(300);
    h.nav.pause();
    h.haptics.cues.clear();
    h.nav.answerNo();
    expect(h.haptics.cues, isEmpty);
    expect(s.locSheet, isTrue);
    expect(s.locDrift, isTrue);
  });

  test('"No" in the ride check too; the arrival\'s "No" and "I\'ve arrived" never buzz', () {
    final h = trip(), s = h.s;
    final hop = s.directions.firstWhere((d) => d.isUpDown);
    h.walkTo(hop.atM - 5);
    h.walkTo(hop.atM + .5);
    expect(s.checking, isTrue);
    expect(s.checkRide, isNotNull);
    expect(s.prompt, 'ride');
    h.haptics.cues.clear();
    h.nav.answerNo();
    expect(h.haptics.cues, ['alert']);
    h.nav.closeLocation();
    // at the end: the arrival is confirmed, or denied, without the alert
    h.nav.debugScrub(1000);
    expect(s.prompt, 'end');
    h.haptics.cues.clear();
    h.nav.answerNo();
    expect(h.haptics.cues, isEmpty);
    expect(s.locDrift, isFalse);
    h.nav.closeLocation();
    h.nav.debugScrub(1000);
    h.nav.confirmArrived();
    expect(s.arrived, isTrue);
    expect(h.haptics.cues, isEmpty, reason: 'the arrival buzz is the screen\'s (it celebrates)');
    expect(s.arrivalSeq, 1);
  });

  test('the line has its Tagalog, in the same register', () {
    expect(hasTagalog(line), isTrue);
    expect(tagalog(line), 'Mukhang nalihis ka ng daan. Simulan natin ulit mula rito.');
  });
}

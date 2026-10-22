// Tagalog: every plain phrase the app shows has a Tagalog version, the templates
// fill in names and numbers, unknown text stays English, and a whole trip in
// Tagalog has no English left in it (from the demo's tagalog_test; the screen
// test is in test/app/screens_test.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/i18n/tagalog.dart';
import 'package:liqo_mobile/core/i18n/words.dart';
import 'package:liqo_mobile/features/navigation/services/narration.dart';

import '../support/harness.dart';
import '../support/spots.dart';

/// Every string literal passed straight to `tr(...)` in lib/ (sentences with names or
/// numbers in them are covered by the templates below).
Set<String> trLiterals() {
  final re = RegExp(r'''\btr\(\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*\)''');
  final out = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    for (final m in re.allMatches(f.readAsStringSync())) {
      var lit = m[1]!;
      lit = lit.substring(1, lit.length - 1);
      if (lit.contains(r'$')) continue;
      lit = lit.replaceAll(r"\'", "'").replaceAll(r'\"', '"');
      if (lit.trim().isNotEmpty) out.add(lit);
    }
  }
  return out;
}

void main() {
  test('every plain phrase passed to tr() has a Tagalog version', () {
    final missing = trLiterals().where((l) => !hasTagalog(l)).toList()..sort();
    expect(missing, isEmpty, reason: 'no Tagalog for:\n  ${missing.join('\n  ')}');
  });

  // level names stay as they are ("Ground floor", "Level 2"), like shop names
  test('the words of data shown through tr(): categories, kinds of place, authors', () {
    final missing = <String>[
      for (final s in ['Shops', 'Food & Dining', 'Restrooms', 'Elevators', 'ATMs', 'Parking', 'Fashion', 'Food', 'Gadgets and tech', 'Books and gifts', 'Services', 'Other shops', 'Cinema', 'Arena', 'Garden', 'ATM', 'Information desk', 'Entrance', 'EV charging', 'Lift', 'Escalator', 'Stairs', 'Ramp', 'Mall', 'Store', 'Mall management'])
        if (!hasTagalog(s)) s,
    ];
    expect(missing, isEmpty, reason: 'no Tagalog for:\n  ${missing.join('\n  ')}');
  });

  test('templates: names and numbers are kept, the words around them are Tagalog', () {
    expect(tagalog('Walk 120 m along the North wing, past ATM and Restrooms'), 'Maglakad ng 120 m sa North wing, lampas sa ATM at Restrooms');
    expect(tagalog('Walk 285 m outside'), 'Maglakad ng 285 m sa labas');
    expect(tagalog('Take the escalator up to level 2'), 'Sumakay sa escalator pataas papuntang level 2');
    expect(tagalog('Take the stairs up to level 3'), 'Umakyat sa hagdan papuntang level 3');
    expect(tagalog('Go in through the Grand Entrance'), 'Pumasok sa Grand Entrance');
    expect(tagalog('You have arrived at Zen Gifts'), 'Nakarating ka na sa Zen Gifts');
    expect(tagalog('in 20 m'), '20 m pa');
    expect(tagalog('Route to Zen Gifts, 118 m to go'), 'Ruta papunta sa Zen Gifts, 118 m pa');
    expect(tagalog('Other way 1 (683 m)'), 'Ibang daan 1 (683 m)');
    expect(tagalog('Walk straight towards the Grand Entrance'), 'Dumiretso papunta sa Grand Entrance');
    expect(tagalog('You should see Bay IMAX on your right'), 'Dapat makita mo na ang Bay IMAX sa kanan mo');
    expect(tagalog('Keep straight for about 50 m more'), 'Dumiretso pa nang mga 50 m');
    expect(tagalog("You should be at Zen Gifts now. Tap I've arrived if you are."), 'Dapat nasa Zen Gifts ka na. I-tap ang Nakarating na ako kung oo.');
    // added for LIQo mobile
    expect(tagalog('Open · Closes 9:00 PM'), 'Bukas · Magsasara nang 9:00 PM');
    expect(tagalog('Closed now · Opens 10:00 AM'), 'Sarado ngayon · Magbubukas nang 10:00 AM');
    expect(tagalog('Nearest: ${tagalog('Restrooms')}'), 'Pinakamalapit: Mga CR');
    expect(tagalog('Best way (620 m)'), 'Pinakamagandang daan (620 m)');
    expect(tagalog('Mall: Bayview Grand. Change mall'), 'Mall: Bayview Grand. Palitan ang mall');
    expect(tagalog('There is no way to Zen Gifts from here.'), 'Walang daan papunta sa Zen Gifts mula rito.');
    expect(tagalog('Tell us where you are, and the way there will show.'), 'Sabihin kung nasaan ka, at lalabas ang daan papunta roon.');
    expect(tagalog('Page 2 of 3'), 'Pahina 2 ng 3');
    expect(tagalog('Version 1.0.0'), 'Bersyon 1.0.0');
    expect(tagalog('A drawing of Opal Comics'), 'Larawan ng Opal Comics');
    expect(tagalog('No mall matches "tower".'), 'Walang mall na tumutugma sa "tower".');
    expect(tagalog('3 buildings'), '3 gusali');
  });

  test('every clause along every demo trip has a Tagalog version, and a whole sentence reads naturally', () {
    final missing = <String>{};
    for (final mall in ['bayview', 'meridian', 'spire']) {
      final h = Harness(mall: mall);
      h.goFrom(scenarioStart(h.v), h.v.tripTarget);
      for (var i = 0; i < h.s.directions.length; i++) {
        for (final c in h.text.narrationClauses(i)) {
          if (!hasTagalog(c)) missing.add(c);
        }
      }
      for (final s in ['Zen Gifts ahead', 'Zen Gifts on your left', 'Zen Gifts on your right', 'Zen Gifts behind you', 'You should be on ${h.text.levelLow(h.v.ground)}']) {
        if (!hasTagalog(s)) missing.add(s);
      }
    }
    expect(missing, isEmpty, reason: 'no Tagalog for:\n  ${missing.join('\n  ')}');
    final h = Harness()..settings.setLang('tl');
    h.goFrom(scenarioStart(h.v), '3-M1');
    final door = h.s.directions.indexWhere((d) => d.kind == 'enter');
    expect(h.text.narrate(door).text, 'Dumiretso papunta sa West Court south doors, tapos pumasok.');
    expect(h.text.checkQuestion(), startsWith('Nandito ka ba? Dapat nasa ground floor ka'));
  });

  test('a whole walk in Tagalog: the card and the questions have no English left in them', () {
    final english = RegExp(r'\b(Keep|keep|Turn|turn|Bear|bear|straight|should|You|you|now|Coming|towards|then|Take|take|If|Walk|walk|Are|Almost|Getting|Riding|Paused)\b');
    for (final mall in ['bayview', 'meridian', 'spire']) {
      final h = Harness(mall: mall)..settings.setLang('tl');
      h.goFrom(scenarioStart(h.v), h.v.tripTarget);
      final shown = <String>{};
      h.nav.start();
      for (var m = 0.0; m < h.s.route!.total; m += 1) {
        h.walkTo(m);
        final t = h.text, up = h.s.nextDirection;
        if (h.s.checking) {
          shown.add(t.checkQuestion());
          h.nav.answerYes();
        }
        if (up != null) shown.addAll([t.dirTitle(up.$2), t.dirSub(up.$2, h.s.route!.progress), ?t.dirApproach(up.$2)]);
        if (h.s.cueShown case final c?) shown.add(c);
        if (t.landingShown case final l?) shown.add(l);
        if (t.afterRideLine case final l?) shown.add(l);
      }
      shown.add(h.text.atEndSentence());
      final leftovers = shown.where((s) => english.hasMatch(s.replaceAll(RegExp(r'\b(Tea House|Kids Wear|Kitchen|West Court|East Court|Grand Court)\b'), '')));
      expect(leftovers, isEmpty, reason: '$mall: English left in Tagalog:\n  ${leftovers.join('\n  ')}');
    }
  });

  test('unknown text stays English', () {
    expect(tagalog('Bay IMAX'), 'Bay IMAX');
    expect(tagalog('Some sentence nobody wrote'), 'Some sentence nobody wrote');
    expect(const Words('tl').tr('Find another way'), 'Humanap ng ibang daan');
    expect(const Words('en').tr('Find another way'), 'Find another way');
  });
}

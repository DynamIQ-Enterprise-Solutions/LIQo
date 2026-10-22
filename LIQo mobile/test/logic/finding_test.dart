// Finding places: favourites (in every mall), recent searches and most visited,
// and describing where you are (from the demo's finding_test; codes and voice
// search were left out).
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/features/navigation/services/location_search.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';
import 'package:liqo_mobile/features/search/providers/search_providers.dart';

import '../support/harness.dart';
import '../support/spots.dart';

void main() {
  group('favourites, recents and most visited', () {
    test('a star toggles, per mall; favourites are kept across malls', () {
      final h = Harness(), fav = h.c.read(favouritesProvider.notifier);
      fav.toggle('bayview', 'G-EHM');
      expect(fav.isFav('bayview', 'G-EHM'), isTrue);
      expect(fav.isFav('meridian', 'G-EHM'), isFalse);
      fav.toggle('meridian', '6-BAN');
      expect(h.c.read(favouritesProvider), hasLength(2));
      fav.toggle('bayview', 'G-EHM');
      expect(fav.isFav('bayview', 'G-EHM'), isFalse);
      expect(h.c.read(favouritesProvider).single.mallId, 'meridian');
    });

    test('recent searches: newest first, no repeats, at most 8, per mall', () {
      final h = Harness(), rec = h.c.read(recentsProvider('bayview').notifier);
      final ids = h.v.places.where((p) => p.kind == 'store' && p.status == 'open').take(10).map((p) => p.id).toList();
      for (final id in ids) {
        rec.add(id);
      }
      expect(h.c.read(recentsProvider('bayview')).length, 8);
      expect(h.c.read(recentsProvider('bayview')).first, ids.last);
      rec.add(ids[3]);
      expect(h.c.read(recentsProvider('bayview')).first, ids[3]);
      expect(h.c.read(recentsProvider('bayview')).where((r) => r == ids[3]), hasLength(1));
      expect(h.c.read(recentsProvider('spire')), isEmpty);
    });

    test('most visited: every trip started counts a visit; the most first', () {
      final h = Harness(), from = scenarioStart(h.v);
      for (final id in ['G-EHM', '3-M1', 'G-EHM', 'G-ARENA', 'G-EHM', '3-M1']) {
        h.goFrom(from, id);
      }
      expect(h.c.read(visitsProvider('bayview').notifier).top(2), ['G-EHM', '3-M1']);
    });
  });

  group('describe where you are', () {
    test('"near the ATM beside the escalator": ATMs and places by an escalator, this floor first', () {
      final h = Harness();
      h.at(spot(h.v, 0, 750, 350));
      final res = locationResults(h.s, 'near the ATM beside the escalator');
      expect(res.places, isNotEmpty);
      for (final p in res.places) {
        expect(p.cat == 'atm' || res.near.containsKey(p.id), isTrue, reason: p.name);
      }
      expect(res.places.first.lv, h.s.user!.lv);
      expect(res.near.values.any((c) => c.toLowerCase().contains('escalator')), isTrue);
      // an ATM that is also by an escalator beats one that is not
      final byBoth = res.places.where((p) => p.cat == 'atm' && res.near.containsKey(p.id));
      if (byBoth.isNotEmpty) expect(res.places.first, byBoth.first);
    });

    test('Tagalog, a plain name, a floor, and nonsense; it works before any position too', () {
      final h = Harness();
      expect(h.s.user, isNull);
      final cr = locationResults(h.s, 'malapit ako sa CR').places;
      expect(cr, isNotEmpty);
      expect(cr.every((p) => p.cat == 'restroom'), isTrue);
      final arena = h.v.placeById(h.v.tripTarget)!;
      expect(locationResults(h.s, arena.name).places.first, arena); // a name still finds the place itself first
      final lv2 = h.v.levels.indexWhere((l) => l.short == '2');
      final floor = locationResults(h.s, '2nd floor').places;
      expect(floor, isNotEmpty);
      expect(floor.every((p) => p.lv == lv2), isTrue);
      expect(locationResults(h.s, 'xyzzy blorp').places, isEmpty);
    });
  });
}

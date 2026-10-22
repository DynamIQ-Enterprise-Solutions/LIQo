// "Where are you?": the places the search offers. A name first; failing that, a
// description ("near the ATM beside the escalator, 2nd floor") matched word by
// word, in English or Tagalog (from the demo's AppState.locResults).
import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';
import '../models/nav_state.dart';
import 'narration.dart' show seeM;

class LocationResults {
  const LocationResults(this.places, this.near);
  final List<Place> places;

  /// What a described result is next to, by place id ("Escalator E1"), when a lift, escalator or stairs was named.
  final Map<String, String> near;
}

// words that say where something is, not what it is (English and Tagalog)
const _filler = {
  'near', 'beside', 'next', 'the', 'and', 'with', 'between', 'behind', 'opposite', 'front', 'back', 'side', 'close', 'here', 'there', 'standing', 'right', 'left',
  "i'm", 'just', 'across', 'from', 'along', 'around', 'corner', 'outside', 'inside', 'facing', 'towards', 'toward', 'floor', 'level', 'area', 'somewhere', 'think',
  'palapag', 'malapit', 'tabi', 'ako', 'nasa', 'dito', 'rito', 'harap', 'likod', 'gilid', 'ang', 'nandito', 'may', 'kami', 'mga', 'ito', 'iyan', 'lang', 'yung',
  'kaliwa', 'kanan', 'katabi', 'tapat', 'pagitan', 'labas', 'loob', 'siguro', 'parang',
};
const _synonyms = {
  'cr': 'restroom', 'toilet': 'restroom', 'toilets': 'restroom', 'banyo': 'restroom', 'washroom': 'restroom', 'restrooms': 'restroom', 'comfort': 'restroom',
  'elevator': 'lift', 'elevators': 'lift', 'lifts': 'lift', 'escalators': 'escalator', 'hagdan': 'stairs', 'stair': 'stairs', 'staircase': 'stairs', 'rampa': 'ramp',
  'labasan': 'exit', 'pasukan': 'entrance', 'sinehan': 'cinema', 'pagkain': 'food', 'kainan': 'food', 'atms': 'atm', 'shop': 'store', 'tindahan': 'store',
};
const _floorWords = {'ground': 'G', 'first': '1', '1st': '1', 'second': '2', '2nd': '2', 'third': '3', '3rd': '3', 'fourth': '4', '4th': '4', 'fifth': '5', '5th': '5', 'una': '1', 'ikalawa': '2', 'ikatlo': '3'};

LocationResults locationResults(NavState s, String query) {
  if (query.trim().isEmpty) return const LocationResults([], {});
  // the name itself first (exact, starts with, contains), then the looser word matches
  final q = query.trim().toLowerCase();
  int score(Place p) {
    final n = p.name.toLowerCase();
    return n == q ? 0 : n.startsWith(q) ? 1 : n.contains(q) ? 2 : 3;
  }

  final hits = s.v.places.where((p) => s.matches(p, query)).toList();
  if (hits.isEmpty) return _described(s, q);
  final sorted = stableSorted(hits, (a, b) {
    final d = score(a) - score(b);
    return d != 0 ? d : a.name.length - b.name.length;
  });
  return LocationResults(sorted.take(8).toList(), const {});
}

/// "near the ATM beside the escalator, 2nd floor": any place matching a word, the ones by a named
/// lift, escalator or stairs included; the most words matched first, then the floor named (or the
/// shopper's), then the nearest.
LocationResults _described(NavState s, String q) {
  final v = s.v, words = <String>{};
  int? lvWanted;
  for (var w in q.split(RegExp(r"[^a-z0-9']+"))) {
    if (w.isEmpty) continue;
    w = _synonyms[w] ?? w;
    final lvShort = _floorWords[w] ?? w.toUpperCase();
    final li = s.levels.indexWhere((l) => l.short.toUpperCase() == lvShort);
    if (li >= 0 && (w.length <= 2 || _floorWords.containsKey(w))) {
      lvWanted = li;
      continue;
    }
    if (w.length < 3 || _filler.contains(w)) continue;
    words.add(w);
  }
  if (words.isEmpty && lvWanted == null) return const LocationResults([], {});
  // places by a lift, escalator or stairs that was named
  final byConn = <String, String>{};
  for (final c in v.connectors) {
    if (!words.contains(c.type)) continue;
    for (final MapEntry(key: lv, value: k) in c.at.entries) {
      final n = s.gr.nodes[k];
      if (n == null) continue;
      for (final p in v.places) {
        if (p.lv == lv && hypot(p.door[0] - n.x, p.door[1] - n.y) <= seeM) byConn.putIfAbsent(p.id, () => c.name);
      }
    }
  }
  final connWords = words.where(hopName.containsKey).toSet();
  final u = s.user, home = lvWanted ?? u?.lv ?? v.ground;
  final scored = <(Place, int, double)>[];
  for (final p in v.places) {
    final hay = '${p.name} ${p.cat} ${v.wingNames[p.wing] ?? ''}'.toLowerCase();
    var sc = words.where((w) => !connWords.contains(w) && hay.contains(w)).length;
    if (byConn.containsKey(p.id)) sc++;
    if (sc == 0 && !(words.isEmpty && p.lv == lvWanted)) continue;
    final dist = u == null ? 0.0 : hypot(p.door[0] - u.x, p.door[1] - u.y);
    scored.add((p, sc, dist + (p.lv == home ? 0 : 1e4)));
  }
  scored.sort((a, b) => a.$2 != b.$2 ? b.$2 - a.$2 : a.$3.compareTo(b.$3));
  final out = scored.take(8).map((x) => x.$1).toList();
  return LocationResults(out, {for (final p in out) if (byConn[p.id] != null) p.id: byConn[p.id]!});
}

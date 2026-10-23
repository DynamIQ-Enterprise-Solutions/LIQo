// What the navigation knows in the current mall: where the shopper is, the trip
// and its walk, the "Where are you?" sheet, other ways and the evacuation, plus
// the place lookups and walking distances the screens ask for. Ported from the
// demo's AppState; [NavController] changes it. It is mutable on purpose: the
// simulated walk changes it every frame.
import 'dart:math' as math;

import '../../../core/engine/constants.dart';
import '../../../core/engine/directions.dart';
import '../../../core/engine/graph.dart';
import '../../../core/engine/package/package_venue.dart';
import '../../../core/engine/reroute.dart';
import '../../../core/engine/routing.dart';
import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';

class UserPos {
  final int lv;
  final double x, y;
  final bool out;
  const UserPos(this.lv, this.x, this.y, this.out);
  Pos get pos => Pos(lv, x, y, out);
}

/// The nearest places of a kind (a category chip on the map).
class Near {
  final String type;
  final List<String> ids;
  const Near(this.type, this.ids);
}

const hopName = {'escalator': ['escalator', 'Escalator'], 'stairs': ['stairs', 'Stairs'], 'lift': ['lift', 'Lift'], 'ramp': ['ramp', 'Ramp']};

class NavState {
  NavState(this.v);

  final Venue v;
  Graph get gr => v.graph;
  List<LevelDef> get levels => v.levels;

  /// The everyday routing options (step-free, stairs / escalators avoided, the metric);
  /// cut-throughs are always allowed (owner decision 2026-10-22). Set by the controller.
  RouteOpts routeOpts = const RouteOpts(throughStores: true);

  // ----- where the shopper is -----
  /// Null until the shopper says where they are (there is no fixed start point).
  UserPos? user;
  bool approximate = false, refining = false;
  double? heading;
  Edge? transit;

  // ----- the trip -----
  String? place;
  List<RouteT> routes = [];
  int routeIdx = 0;
  bool arrived = false, atEnd = false;
  bool playing = false, paused = false;

  /// The pause or ride check ("Are you here?", "Are you at the escalator?").
  bool checking = false;

  /// The lift, escalator or stairs (direction index) the question is about, or null for a plain pause.
  int? checkRide;
  (RouteT, int)? askedRide;

  /// The demo walk answers "Are you at ...?" by itself after two seconds (while the map is shown).
  Duration? autoAnswerAt;
  String? wcError, wcPlace;

  /// The route uses stairs or an escalator although the shopper avoids them: nothing else reaches the place.
  String? needsNote;

  /// A lift, escalator or stairs on the route in progress went out of service (live store info):
  /// its name, for the note with "Find another way". The route doesn't change by itself.
  String? outNote;

  /// The route goes to the information desk for help.
  bool helpNote = false;

  /// Counts arrivals, so the screen celebrates each one once.
  int arrivalSeq = 0;
  Near? near;

  /// Browsing a chip list: [place]'s way is drawn and highlighted, the list stays open, and nothing
  /// is a trip until the shopper confirms it (owner decision 2026-10-23).
  bool preview = false;

  /// Where the last ride ended (route, metres, level, connector): the card says what to expect for a few metres.
  (RouteT, double, int, String?)? rideEndAt;
  int? ridingLv;
  RouteT? cuedFor;
  int cuedDir = -1;
  RouteT? cuesFor;
  final cuesSaid = <String>{};
  String? cueLine;
  Duration? cueLineAt;

  /// A destination waiting for the shopper to say where they are (Get Directions with no position yet).
  String? pendingPlace;

  /// The mall's demo trip, waiting for a position (first Map visit per mall per launch).
  bool autoTripPending = false;

  /// The history record of the trip in progress.
  String? tripRecord;

  // ----- other ways and the evacuation -----
  RerouteSession? reroute;
  bool emergency = false;
  Evacuation? evac;
  bool evacHelp = false;

  // ----- "Where are you?" -----
  bool locSheet = false, locFirst = true, locDrift = false, visited = false;
  String locQuery = '';

  // ----- the clock -----
  Duration now = Duration.zero;
  Duration? last;

  /// The Map tab is on screen: questions wait for it, and so does the demo walk's auto-answer.
  bool mapVisible = false;

  RouteT? get route => routeIdx < routes.length ? routes[routeIdx] : null;
  bool get hasPosition => user != null;
  List<int> get levelsDesc => [for (var i = v.levelCount - 1; i >= 0; i--) i];

  /// The question on screen that needs an answer: ride ("Are you at the escalator?"), here (the
  /// pause check) or end ("I've arrived"); null when nothing is asked.
  String? get prompt => checking ? (checkRideIndex != null ? 'ride' : 'here') : atEnd && !arrived && evac == null && route != null ? 'end' : null;

  /// The ride the check is about, when it is about one.
  int? get checkRideIndex {
    final ride = checking ? checkRide : null;
    return ride == null || ride >= directions.length ? null : ride;
  }

  /// Something on the map is pulsing: the ring at the foot of a ride being asked about, the floor chip you ride to.
  bool get pulsing => (checking && checkRide != null) || transit != null;

  /// 0 → 1 every 1.2 s while [pulsing].
  double get pulse => pulsing ? (now.inMilliseconds % 1200) / 1200 : 0;

  /// The level a ride in progress goes to.
  int? get ridingTo {
    final t = transit;
    return t == null ? null : directions.where((d) => d.isUpDown && d.id == t.conn).firstOrNull?.to;
  }

  /// Within 20 m of the destination.
  bool get almostThere => route != null && !arrived && route!.total - route!.progress <= closeNearM;

  /// The last cue, for the card, for six seconds.
  String? get cueShown => cueLineAt != null && (now - cueLineAt!).inSeconds < 6 ? cueLine : null;

  int rideIndex(Edge t) => directions.lastIndexWhere((d) => d.isUpDown && d.id == t.conn && d.atM <= (route?.progress ?? 0) + 0.01);

  // ----- turn-by-turn directions, worked out once per route -----
  RouteT? _dirsFor;
  List<Direction> _dirs = const [];
  List<Direction> get directions {
    final r = route;
    if (r == null) return const [];
    if (!identical(r, _dirsFor)) {
      _dirsFor = r;
      _dirs = directionsOf(r, v);
    }
    return _dirs;
  }

  /// The direction coming up, with its index.
  (int, Direction)? get nextDirection => route == null ? null : upcoming(directions, route!.progress);

  // ----- places -----
  /// A place by id; `CONN:` + a connector id is a lift, escalator or stairs as a place.
  Place? placeById(String id) => id.startsWith('CONN:') ? connPlace(id.substring(5)) : v.placeById(id);

  /// A connector as a place on [lv] (the shopper's floor when it stops there, else its lowest stop).
  Place? connPlace(String cid, [int? lv]) {
    final c = v.connectors.where((c) => c.id == cid).firstOrNull;
    if (c == null) return null;
    final u = user;
    final l = lv ?? (u != null && c.at.containsKey(u.lv) ? u.lv : c.lvs.first), k = c.at[l];
    final n = k == null ? null : gr.nodes[k];
    if (n == null) return null;
    final out = v is PackageVenue && (v as PackageVenue).outOfService.contains(cid);
    return Place(id: 'CONN:$cid', lv: l, name: c.name, cat: c.type, wing: '', rect: [n.x, n.y, n.x, n.y], at: [n.x, n.y], door: [n.x, n.y], kind: 'conn', status: out ? 'maintenance' : 'open', nodes: [k!]);
  }

  /// Every place a shopper looks for: the services on a walkway (ATMs, desks) count only as exits.
  List<Place> bldgPlaces() => v.places.where((p) => p.kind != 'svc' || p.cat == 'exit').toList();

  bool matches(Place p, String q) {
    q = q.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = '${p.name} ${p.cat} ${p.id} ${levels[p.lv].name} level ${levels[p.lv].short} ${v.wingNames[p.wing] ?? ''}'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  // ----- walking distances from the shopper -----
  String _distKey = '';
  Map<String, double>? _dist;
  void clearDistCache() => _distKey = '';

  /// Walking cost from the shopper to every node; empty while there is no position.
  Map<String, double> distances() {
    final u = user;
    if (u == null) return const {};
    final o = routeOpts, from = gr.nearestNodeAt(u.lv, u.x, u.y)!;
    final key = '$from|${o.wheel}|${o.metric}|${o.avoid.join()}';
    if (_distKey != key) {
      _distKey = key;
      _dist = dijkstra(gr, from, o).d;
    }
    return _dist!;
  }

  double? distOf(Place p) {
    final d = distances();
    double? m;
    for (final k in p.nodes) {
      if (d.containsKey(k) && (m == null || d[k]! < m)) m = d[k];
    }
    return m;
  }

  /// Places sorted by walking distance (unreachable last); by name while there is no position.
  List<Place> byDistance(Iterable<Place> ps) {
    if (!hasPosition) return stableSorted(ps, (a, b) => a.name.compareTo(b.name));
    final withD = ps.map((p) => (p, distOf(p) ?? 1e9)).toList();
    return stableSorted(withD, (a, b) => cmpNum(a.$2, b.$2)).map((x) => x.$1).toList();
  }

  /// The nearest three of a kind: a category, or lifts / escalators / stairs on the shopper's floor.
  List<Place> nearest(String type) {
    final u = user;
    if (u == null) return const [];
    final d = distances();
    if (hopName.containsKey(type)) {
      final ps = [for (final c in v.connectors) if (c.type == type && c.at[u.lv] != null) connPlace(c.id, u.lv)].whereType<Place>().where((p) => d.containsKey(p.nodes.first));
      final ranked = ps.map((p) => (p, d[p.nodes.first]!)).toList();
      return stableSorted(ranked, (a, b) => cmpNum(a.$2, b.$2)).take(3).map((x) => x.$1).toList();
    }
    // 'shops' is every store-type place but food (the Shops category)
    bool kind(Place p) => type == 'shops' ? (p.kind == 'store' || p.kind == 'box') && p.cat != 'food' : p.cat == type;
    // closed and being-repaired places too: the list shows their status (owner decision 2026-10-23)
    bool ok(Place p) => kind(p) && p.nodes.any(d.containsKey);
    final ranked = v.places.where(ok).map((p) => (p, p.nodes.where(d.containsKey).map((k) => d[k]!).reduce(math.min))).toList();
    return stableSorted(ranked, (a, b) => cmpNum(a.$2, b.$2)).take(3).map((x) => x.$1).toList();
  }

  /// Other open places of the same kind, nearest first.
  List<Place> similarPlaces(Place p) {
    bool same(Place q) {
      if (q.id == p.id) return false;
      if (p.kind == 'zone') return q.kind == 'zone';
      return q.cat == p.cat && q.status == 'open' && q.kind != 'zone';
    }

    final ranked = [for (final q in v.places.where(same)) (q, distOf(q))].where((x) => x.$2 != null).toList();
    return stableSorted(ranked, (a, b) => cmpNum(a.$2!, b.$2!)).take(3).map((x) => x.$1).toList();
  }

  static String availClass(num a) => a >= availGood ? 'good' : a >= availOk ? 'mid' : 'bad';
}

/// Closeness cues to the destination (metres to go).
const closeFarM = 50.0, closeNearM = 20.0, closeHereM = 5.0;

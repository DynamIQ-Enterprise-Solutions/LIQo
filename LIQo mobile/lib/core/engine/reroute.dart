// Other ways to a place, reported problems, and evacuation to the exits.
// Added for the Android port; the mock-up has neither.
import 'dart:math' as math;

import 'util.dart';
import 'graph.dart';
import 'routing.dart';
import 'venue.dart';

/// How far ahead of the user "Find another way" avoids, in metres.
const double aheadM = 30;

/// How close (in metres) a tap must be to a path or connector to mark it (during an evacuation).
const double markRadiusM = 9;

/// A reported spot. A venue alert ([alert]) is only shown, on the map and on the ways that
/// pass it: the user decides. A path marked blocked or an exit blocked during an evacuation
/// is avoided by the evacuation.
class Problem {
  final int id;
  final Set<String> edges; // undirected edge keys
  final Set<String> conns; // connector ids (lifts, escalators, stairs)
  final String? exitId; // a blocked exit
  final int lv;
  final double x, y; // where the warning marker sits
  final bool alert;
  const Problem({required this.id, this.edges = const {}, this.conns = const {}, this.exitId, required this.lv, required this.x, required this.y, this.alert = false});

  /// The same spot, as a venue alert.
  Problem asAlert() => Problem(id: id, edges: edges, conns: conns, exitId: exitId, lv: lv, x: x, y: y, alert: true);
}

String vertKey(Vert v) => nk(v.lv, v.x, v.y);

/// The edge keys and connector ids a route uses (verts[0] is the user, not a node).
({Set<String> edges, Set<String> conns}) routeParts(RouteT r) {
  final edges = <String>{}, conns = <String>{};
  for (var i = 2; i < r.verts.length; i++) {
    edges.add(edgeKey(vertKey(r.verts[i - 1]), vertKey(r.verts[i])));
    final s = r.seg[i];
    if (isHop(s)) conns.add(s!.conn!);
  }
  return (edges: edges, conns: conns);
}

bool routeHits(RouteT r, Iterable<Problem> ps) {
  final parts = routeParts(r);
  return ps.any((p) => p.edges.any(parts.edges.contains) || p.conns.any(parts.conns.contains));
}

/// The stretch just ahead of the user: the next [aheadM] metres of walking, or the
/// lift / escalator / stairs about to be taken. The destination's own door is never included.
/// A cut-through a store counts as a whole (its doors and its floor): if a door turns out to
/// be locked, the other ways go around the store, not in by its other door.
Problem? problemAhead(Graph gr, RouteT r, int id) {
  final at = pointAt(r, r.progress), last = r.verts.length - 1;
  final edges = <String>{}, conns = <String>{}, stores = <String>{};
  double? mx, my;
  int? mlv;
  // only what is still ahead: the segment the user is on (or has just finished) is
  // never blocked, so they are not cut off from going back
  final first = at.t <= 0 ? at.i : at.i + 1;
  for (var i = math.max(2, first); i < last; i++) {
    if (r.cum[i - 1] - r.progress > aheadM) break;
    final a = r.verts[i - 1], b = r.verts[i], s = r.seg[i];
    if (isHop(s)) {
      conns.add(s!.conn!);
      if (mlv == null) { mlv = a.lv; mx = a.x; my = a.y; }
      break;
    }
    edges.add(edgeKey(vertKey(a), vertKey(b)));
    if (mlv == null) { mlv = a.lv; mx = (a.x + b.x) / 2; my = (a.y + b.y) / 2; }
    if (s?.through != null) stores.add(s!.through!);
  }
  if (mlv == null) return null;
  // not the store the user is already inside: they must not be cut off from its doors
  final inside = at.i < r.seg.length ? r.seg[at.i]?.through : null;
  for (final n in gr.nodes.values) {
    for (final e in gr.adj[n.k]!) {
      if (e.through != null && e.through != inside && stores.contains(e.through)) edges.add(edgeKey(n.k, e.to));
    }
  }
  return Problem(id: id, edges: edges, conns: conns, lv: mlv, x: mx!, y: my!);
}

double _segDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
  final t = l2 == 0 ? 0.0 : clampD(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1);
  return hypot(px - (ax + t * dx), py - (ay + t * dy));
}

/// The path or connector the user tapped on level [lv] (world coordinates), if any.
Problem? problemAtSpot(Venue v, int lv, double x, double y, int id) {
  final gr = v.graph;
  Problem? best;
  var bd = markRadiusM;
  for (final c in v.connectors) {
    final k = c.at[lv];
    if (k == null) continue;
    final n = gr.nodes[k]!, d = hypot(n.x - x, n.y - y) - 2; // connector pins are easier to hit
    if (d < bd) {
      bd = d;
      best = Problem(id: id, conns: {c.id}, lv: lv, x: n.x, y: n.y);
    }
  }
  for (final n in gr.nodes.values) {
    if (n.lv != lv || n.emergencyOnly) continue;
    for (final e in gr.adj[n.k]!) {
      if (e.kind == 'hop' || e.emergencyOnly || n.k.compareTo(e.to) > 0) continue;
      final m = gr.nodes[e.to]!;
      if (m.lv != lv) continue;
      final d = _segDist(x, y, n.x, n.y, m.x, m.y);
      if (d < bd) {
        bd = d;
        best = Problem(id: id, edges: {edgeKey(n.k, e.to)}, lv: lv, x: (n.x + m.x) / 2, y: (n.y + m.y) / 2);
      }
    }
  }
  return best;
}

double _jaccard(Set<String> a, Set<String> b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final inter = a.where(b.contains).length;
  return inter / (a.length + b.length - inter);
}

/// How much two routes share (0 = nothing, 1 = the same edges).
double routeSimilarity(RouteT a, RouteT b) => _jaccard(routeParts(a).edges, routeParts(b).edges);

/// One choice in the "other ways" list.
class RouteOption {
  final RouteT route;
  final String kind; // current: the way being followed | around: avoids the stretch just ahead
  final int n; // 1, 2, 3 for the ways around
  late final RouteStats stats = RouteStats.of(route);
  RouteOption(this.route, this.kind, this.n);
}

/// An open "other ways" choice: the options, and the route to restore on cancel.
class RerouteSession {
  final String placeId;
  final bool fromAlert, wasPlaying;
  final List<RouteT> savedRoutes;
  final int savedIdx;
  final Problem? avoid; // the stretch just ahead that the other ways go around; never kept
  List<RouteOption> options = [];
  List<Place> nearby = [];
  int sel = 0;
  RerouteSession({required this.placeId, required this.fromAlert, required this.wasPlaying, required this.savedRoutes, required this.savedIdx, this.avoid});
}

/// Up to [max] clearly different ways to the place, shortest first. Each round makes
/// the edges already used more expensive, so the next search prefers other paths.
List<RouteT> waysAround(Graph gr, String placeId, List<String> placeNodes, Pos from, RouteOpts base, {int max = 3}) {
  final found = <RouteT>[], mul = <String, double>{};
  for (var t = 0; t < 8 && found.length < max; t++) {
    final r = buildRoute(gr, placeId, placeNodes, from, base.copyWith(edgeMul: Map.of(mul)));
    if (r == null) break;
    final keys = routeParts(r).edges;
    final dup = found.any((f) => _jaccard(keys, routeParts(f).edges) > .8);
    if (!dup && (found.isEmpty || r.total < found.first.total * 2.2)) found.add(r);
    for (final k in keys) {
      mul[k] = (mul[k] ?? 1) * 2;
    }
  }
  return stableSorted(found, (a, b) => cmpNum(a.total, b.total));
}

/// What a route costs: length, level changes, and whether any of it is outdoors.
class RouteStats {
  final double total;
  final int levelChanges;
  final bool outside;
  const RouteStats(this.total, this.levelChanges, this.outside);
  factory RouteStats.of(RouteT r) {
    final steps = stepsOf(r);
    return RouteStats(r.total, steps.where((s) => s.kind == 'hop').fold(0, (n, s) => n + (s.to - s.from).abs()), steps.any((s) => s.kind == 'walk' && s.out));
  }
}

// ===== Evacuation =====

/// The door edges of an exit: blocking an exit bans these.
Set<String> exitEdges(Graph gr, ExitDef e) => {
      for (final x in gr.adj[e.node]!)
        if (x.kind == 'enter') edgeKey(e.node, x.to),
    };

class Evacuation {
  final RouteT? route;
  final ExitDef? exit; // null when going to a refuge point
  final bool refuge; // wait at the stairs for staff
  final bool outside; // already outdoors
  const Evacuation({this.route, this.exit, this.refuge = false, this.outside = false});
}

/// The way out: the nearest open exit by stairs (never lifts). Wheelchair users, and
/// anyone with no exit left, go to the nearest stair landing (a refuge point) instead.
Evacuation evacuate(Venue v, Pos from, {required bool wheel, required Set<String> banEdges, required Set<String> banConn, required Set<String> blockedExits}) {
  final gr = v.graph;
  // outdoors at street level is already out (an open-air gallery upstairs is not)
  if (from.out && from.lv == v.ground) return const Evacuation(outside: true);
  final opts = RouteOpts(wheel: wheel, emergency: true, noLifts: true, banEdges: banEdges, banConn: banConn);
  RouteT? best;
  ExitDef? bestExit;
  for (final e in v.exits) {
    if (blockedExits.contains(e.id)) continue;
    final r = buildRoute(gr, 'EXIT:${e.id}', [e.node], from, opts);
    if (r != null && (best == null || r.total < best.total)) {
      best = r;
      bestExit = e;
    }
  }
  if (best != null) return Evacuation(route: best, exit: bestExit);
  // a refuge point: the stair landing on this level
  final r = buildRoute(gr, 'REFUGE', v.refugeLandings(from.lv), from, opts);
  return Evacuation(route: r, refuge: true);
}

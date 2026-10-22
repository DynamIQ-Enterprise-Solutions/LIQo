// Routing, ported 1:1: a binary heap Dijkstra over the walkway graph.
import 'dart:math' as math;

import 'constants.dart';
import 'util.dart';
import 'graph.dart';
import 'venue.dart';

class RouteOpts {
  final bool wheel;
  final Set<String>? banConn;
  final List<String?>? banEdge;
  // Added for rerouting and evacuation. All default to off, so routes match the demo's.
  final Set<String>? banEdges; // undirected edge keys (see [edgeKey]) the user reported as a problem
  final bool emergency; // allows the evacuation-only basement stairs
  final bool noLifts; // evacuation: never use a lift
  final Map<String, double>? edgeMul; // cost multipliers, to find different ways around
  final bool throughStores; // may cut through a big store (the "Allow shortcuts through stores" setting)
  final Set<String> avoid; // hop types never used: 'stairs', 'escalator' (the user's choice; an evacuation ignores it)
  /// What the route minimises (LIQo mobile, owner decision 2026-10-22): [fastest] is the demo's
  /// cost (walking plus each lift, escalator or stairs in metre-equivalents, waits included);
  /// [shortest] is the fewest metres walked, so a ride on a lift or escalator barely counts.
  final String metric;
  const RouteOpts({this.wheel = false, this.banConn, this.banEdge, this.banEdges, this.emergency = false, this.noLifts = false, this.edgeMul, this.throughStores = false, this.avoid = const {}, this.metric = fastest});

  static const fastest = 'fastest', shortest = 'shortest';

  RouteOpts copyWith({Set<String>? banConn, Map<String, double>? edgeMul}) => RouteOpts(
      wheel: wheel, banConn: banConn ?? this.banConn, banEdge: banEdge, banEdges: banEdges, emergency: emergency, noLifts: noLifts, edgeMul: edgeMul ?? this.edgeMul,
      throughStores: throughStores, avoid: avoid, metric: metric);
}

/// What an edge costs the search. Under [RouteOpts.shortest] a walk costs the metres walked
/// (a store's floor without the cut-through penalty), stairs and a ramp keep their cost (they
/// are walked), and a ride on a lift or escalator costs a token metre, so a ride is never
/// taken for nothing.
double edgeCost(Edge e, RouteOpts opts) {
  if (opts.metric != RouteOpts.shortest) return e.d;
  if (e.kind == 'hop') return e.ctype == 'lift' || e.ctype == 'escalator' ? 1 : e.d;
  return e.len;
}

/// An undirected key for the edge between two graph nodes.
String edgeKey(String a, String b) => a.compareTo(b) < 0 ? '$a~$b' : '$b~$a';

bool blocked(Edge e, RouteOpts opts) {
  if (opts.wheel && (e.w < wheelchairMinWidthM || (e.kind == 'hop' && e.ctype != 'lift' && e.ctype != 'ramp'))) return true;
  if (opts.banConn != null && e.kind == 'hop' && opts.banConn!.contains(e.conn)) return true;
  if (e.emergencyOnly && !opts.emergency) return true;
  if (opts.noLifts && e.kind == 'hop' && e.ctype == 'lift') return true;
  if (e.kind == 'hop' && opts.avoid.contains(e.ctype)) return true;
  // cut-throughs: only when allowed, and never step-free or in an evacuation
  if (e.through != null && (!opts.throughStores || opts.wheel || opts.emergency)) return true;
  return false;
}

class _Heap {
  final a = <(double, String)>[];
  void push(double d, String k) {
    a.add((d, k));
    var i = a.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (a[p].$1 <= a[i].$1) break;
      final t = a[p]; a[p] = a[i]; a[i] = t;
      i = p;
    }
  }

  (double, String) pop() {
    final t = a[0], l = a.removeLast();
    if (a.isNotEmpty) {
      a[0] = l;
      var i = 0;
      for (;;) {
        var m = i;
        final c1 = 2 * i + 1, c2 = c1 + 1;
        if (c1 < a.length && a[c1].$1 < a[m].$1) m = c1;
        if (c2 < a.length && a[c2].$1 < a[m].$1) m = c2;
        if (m == i) break;
        final x = a[m]; a[m] = a[i]; a[i] = x;
        i = m;
      }
    }
    return t;
  }

  int get size => a.length;
}

class DijkstraResult {
  final Map<String, double> d;
  final Map<String, (String, Edge)> prev;
  DijkstraResult(this.d, this.prev);
}

DijkstraResult dijkstra(Graph gr, String from, [RouteOpts opts = const RouteOpts()]) {
  final d = <String, double>{from: 0}, prev = <String, (String, Edge)>{}, h = _Heap()..push(0, from);
  while (h.size > 0) {
    final (du, u) = h.pop();
    if (du > d[u]!) continue;
    for (final e in gr.adj[u]!) {
      if (blocked(e, opts)) continue;
      final be = opts.banEdge;
      if (be != null && ((be[0] == u && be[1] == e.to) || (be[1] == u && be[0] == e.to))) continue;
      final bes = opts.banEdges, mul = opts.edgeMul;
      final key = (bes != null && bes.isNotEmpty) || mul != null ? edgeKey(u, e.to) : null;
      if (key != null && bes != null && bes.contains(key)) continue;
      final cost = edgeCost(e, opts), nd = du + (mul == null ? cost : cost * (mul[key] ?? 1));
      if (nd < (d[e.to] ?? double.infinity)) {
        d[e.to] = nd;
        prev[e.to] = (u, e);
        h.push(nd, e.to);
      }
    }
  }
  return DijkstraResult(d, prev);
}

class Pos {
  final int lv;
  final double x, y;
  final bool out;
  const Pos(this.lv, this.x, this.y, [this.out = false]);
}

class Vert {
  final int lv;
  final double x, y;
  final bool out;
  const Vert(this.lv, this.x, this.y, this.out);
}

class RouteT {
  final String placeId;
  final List<Vert> verts;
  final List<Edge?> seg;
  final List<double> cum;
  final double total;
  double progress = 0;
  final Set<String> conns;
  final RouteOpts opts;
  RouteT(this.placeId, this.verts, this.seg, this.cum, this.total, this.conns, this.opts);
}


RouteT? buildRoute(Graph gr, String placeId, List<String> placeNodes, Pos from, RouteOpts opts) {
  final start = gr.nearestNodeAt(from.lv, from.x, from.y, includeEmergency: opts.emergency)!;
  final r = dijkstra(gr, start, opts), d = r.d, prev = r.prev;
  String? target;
  for (final k in placeNodes) {
    if (d.containsKey(k) && (target == null || d[k]! < d[target]!)) target = k;
  }
  if (target == null) return null;
  final chain = <(String, Edge?)>[];
  for (String? k = target; k != null;) {
    final p = prev[k];
    chain.insert(0, (k, p?.$2));
    k = p?.$1;
  }
  final verts = <Vert>[Vert(from.lv, from.x, from.y, from.out)], seg = <Edge?>[null], conns = <String>{};
  for (final (k, via) in chain) {
    final n = gr.nodes[k]!;
    verts.add(Vert(n.lv, n.x, n.y, n.out));
    seg.add(via);
    if (via != null && via.kind == 'hop') conns.add(via.conn!);
  }
  final cum = <double>[0];
  for (var i = 1; i < verts.length; i++) {
    final a = verts[i - 1], b = verts[i], s = seg[i];
    cum.add(cum[i - 1] + (s != null && s.kind == 'hop' ? s.d : hypot(a.x - b.x, a.y - b.y)));
  }
  return RouteT(placeId, verts, seg, cum, cum.last, conns, opts);
}

List<RouteT> routesTo(Graph gr, String placeId, List<String> placeNodes, Pos from, bool wheel,
    {Set<String>? banEdges, Set<String>? banConn, bool throughStores = false, Set<String> avoid = const {}, String metric = RouteOpts.fastest}) {
  final best = buildRoute(gr, placeId, placeNodes, from, RouteOpts(wheel: wheel, banEdges: banEdges, banConn: banConn, throughStores: throughStores, avoid: avoid, metric: metric));
  if (best == null) return [];
  final out = [best];
  RouteT? alt;
  if (best.conns.isNotEmpty) {
    alt = buildRoute(gr, placeId, placeNodes, from, RouteOpts(wheel: wheel, banEdges: banEdges, banConn: {...best.conns, ...?banConn}, throughStores: throughStores, avoid: avoid, metric: metric));
  } else if (best.verts.length > 3) {
    final i = (best.verts.length / 2).floor(), a = best.verts[i - 1], b = best.verts[i];
    alt = buildRoute(gr, placeId, placeNodes, from,
        RouteOpts(wheel: wheel, banEdges: banEdges, banConn: banConn, throughStores: throughStores, avoid: avoid, metric: metric, banEdge: [gr.nearestNodeAt(a.lv, a.x, a.y), gr.nearestNodeAt(b.lv, b.x, b.y)]));
  }
  if (alt != null && alt.total > best.total + 0.5 && alt.total < best.total * 2) out.add(alt);
  return out;
}

bool isHop(Edge? s) => s != null && s.kind == 'hop';

class PointAt {
  final List<double> pos;
  final int lv;
  final bool out;
  final double? heading;
  final int i;
  final Edge? transit;
  final double t;
  const PointAt(this.pos, this.lv, this.out, this.heading, this.i, this.transit, this.t);
}

PointAt pointAt(RouteT r, double m) {
  m = math.max(0, math.min(r.total, m));
  var i = 1;
  while (i < r.cum.length - 1 && r.cum[i] < m) { i++; }
  final a = r.verts[i - 1], b = r.verts[i];
  var span = r.cum[i] - r.cum[i - 1];
  if (span == 0) span = 1;
  final t = (m - r.cum[i - 1]) / span, s = r.seg[i];
  double? heading;
  for (var j = i; j >= 1; j--) {
    if (!isHop(r.seg[j])) {
      final p = r.verts[j - 1], q = r.verts[j];
      if (hypot(q.x - p.x, q.y - p.y) > 0.01) { heading = math.atan2(q.y - p.y, q.x - p.x); break; }
    }
  }
  if (isHop(s)) return PointAt([a.x, a.y], t < 0.5 ? a.lv : b.lv, false, heading, i, s, t);
  return PointAt([lerp(a.x, b.x, t), lerp(a.y, b.y, t)], a.lv, t < .5 ? a.out : b.out, heading, i, null, t);
}

class Piece {
  final int lv;
  final List<List<double>> pts;
  Piece(this.lv, this.pts);
}

class HopLeft {
  final double x, y;
  final int from;
  int to;
  final String type, id;
  HopLeft(this.x, this.y, this.from, this.to, this.type, this.id);
}

({List<Piece> pieces, List<HopLeft> hopsLeft}) remainingPieces(RouteT r) {
  final at = pointAt(r, r.progress), pieces = <Piece>[], hopsLeft = <HopLeft>[];
  var cur = Piece(at.lv, [at.pos]);
  for (var i = at.i; i < r.verts.length; i++) {
    final v = r.verts[i], s = r.seg[i];
    if (isHop(s)) {
      if (cur.pts.length > 1) pieces.add(cur);
      final a = r.verts[i - 1], last = hopsLeft.isEmpty ? null : hopsLeft.last;
      if (last != null && last.id == s!.conn && last.to == a.lv) {
        last.to = v.lv;
      } else {
        hopsLeft.add(HopLeft(a.x, a.y, a.lv, v.lv, s!.ctype!, s.conn!));
      }
      cur = Piece(v.lv, [[v.x, v.y]]);
    } else {
      cur.pts.add([v.x, v.y]);
    }
  }
  if (cur.pts.length > 1) pieces.add(cur);
  return (pieces: pieces, hopsLeft: hopsLeft);
}

class Step {
  final String kind; // walk | hop | enter | bridge
  final double m;
  final bool out;
  double endAt;
  final String? id, type, label, tech;
  final int from;
  int to;
  final bool into, covered;
  final String? through; // a cut-through: the store walked through
  Step({required this.kind, this.m = 0, this.out = false, required this.endAt, this.id, this.type, this.label, this.tech, this.from = 0, this.to = 0, this.into = false, this.covered = false, this.through});
}

List<Step> stepsOf(RouteT r) {
  final steps = <Step>[];
  var walk = 0.0;
  bool? walkOut;
  var walkCovered = false;
  String? walkThrough;
  void flush(double end) {
    if (walk > 0.5) steps.add(Step(kind: 'walk', m: walk, out: walkOut ?? false, covered: walkCovered, through: walkThrough, endAt: end));
    walk = 0;
    walkOut = null;
    walkCovered = false;
    walkThrough = null;
  }

  for (var i = 1; i < r.verts.length; i++) {
    final s = r.seg[i], a = r.verts[i - 1], b = r.verts[i];
    if (isHop(s)) {
      flush(r.cum[i - 1]);
      final last = steps.isEmpty ? null : steps.last;
      if (last != null && last.kind == 'hop' && last.id == s!.conn && last.to == a.lv) {
        last.to = b.lv;
        last.endAt = r.cum[i];
      } else {
        steps.add(Step(kind: 'hop', id: s!.conn, type: s.ctype, from: a.lv, to: b.lv, endAt: r.cum[i]));
      }
    } else if (s != null && (s.kind == 'enter' || s.kind == 'bridge')) {
      flush(r.cum[i - 1]);
      steps.add(Step(kind: s.kind, label: s.label, tech: s.tech, into: a.out && !b.out, endAt: r.cum[i]));
    } else {
      // a covered walkway, and a cut-through a store, are steps of their own
      final out = a.out && b.out, covered = s?.covered ?? false, through = s?.through;
      if (walkOut != null && (walkOut != out || walkCovered != covered || walkThrough != through)) flush(r.cum[i - 1]);
      walkOut = out;
      walkCovered = covered;
      walkThrough = through;
      walk += r.cum[i] - r.cum[i - 1];
    }
  }
  flush(r.total);
  return steps;
}

/// Convenience over a [Place].
List<RouteT> routesToPlace(Graph gr, Place p, Pos from, bool wheel) => routesTo(gr, p.id, p.nodes, from, wheel);

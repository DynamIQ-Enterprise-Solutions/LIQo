// The walkway graph, ported 1:1 (insertion order included, since routing
// tie-breaks depend on it). Dart map literals keep insertion order, like JS objects.
// Each venue builds its own graph from these primitives (see kit/kit_venue.dart).

import 'constants.dart';
import 'util.dart';
import 'venue.dart';

class GNode {
  final String k;
  final int lv;
  final double x, y;
  bool out;
  String? label;
  bool emergencyOnly = false; // evacuation-only stairs (not in the mock-up)
  bool inner = false; // inside a store, on a cut-through: never anyone's nearest node
  GNode(this.k, this.lv, this.x, this.y, {this.out = false});
}

class Edge {
  final String to;
  final double d;
  /// The physical length walked along the edge, in metres (0 for a hop). [d] is its routing
  /// cost, which can differ: a hop costs metre-equivalents, a store's floor 1.25x its length.
  final double len;
  double w;
  final String kind; // walk | enter | bridge | hop
  final String? label, conn, ctype;
  final String? tech; // technical wording for a bridge step
  final bool emergencyOnly, covered;
  /// A cut-through: the id of the store walked through (its doors and its floor).
  final String? through;
  Edge({required this.to, required this.d, this.len = 0, required this.w, required this.kind, this.label, this.conn, this.ctype, this.tech, this.emergencyOnly = false, this.covered = false, this.through});
}

class EdgeMeta {
  final String kind;
  final String? label, conn, ctype, tech;
  final bool covered;
  final String? through;
  const EdgeMeta(this.kind, {this.label, this.conn, this.ctype, this.tech, this.covered = false, this.through});
  static const walk = EdgeMeta('walk');
}

class Line {
  final List<double> a, b;
  final double w;
  final List<List<double>> pts;
  final bool out;
  final String? zone;
  final String? bld; // the building it belongs to (kit venues)
  final bool covered; // an outdoor walkway with a roof (kit venues)
  Line(this.a, this.b, this.w, this.out, this.zone, {this.bld, this.covered = false}) : pts = [a, b];
  bool get horiz => a[1] == b[1];
}

String _fx(double v) => v.toStringAsFixed(1);
String nk(int lv, double x, double y) => '$lv|${_fx(x)},${_fx(y)}';

bool isOut(Line l) => l.out;
bool isIn(Line l) => !l.out && l.zone == null;

class Graph {
  final int levelCount;
  final nodes = <String, GNode>{};
  final adj = <String, List<Edge>>{};
  late final lines = List.generate(levelCount, (_) => <Line>[]);
  Graph(this.levelCount);

  String node(int lv, double x, double y, {bool? out, String? label}) {
    final k = nk(lv, x, y);
    if (!nodes.containsKey(k)) {
      nodes[k] = GNode(k, lv, x, y);
      adj[k] = [];
    }
    if (out != null) nodes[k]!.out = out;
    if (label != null) nodes[k]!.label = label;
    return k;
  }

  void link(String a, String b, double w, [EdgeMeta? meta, double? cost, bool emergencyOnly = false]) {
    final na = nodes[a]!, nb = nodes[b]!;
    final len = hypot(na.x - nb.x, na.y - nb.y), d = cost ?? len, m = meta ?? EdgeMeta.walk;
    adj[a]!.add(Edge(to: b, d: d, len: len, w: w, kind: m.kind, label: m.label, conn: m.conn, ctype: m.ctype, tech: m.tech, emergencyOnly: emergencyOnly, covered: m.covered, through: m.through));
    adj[b]!.add(Edge(to: a, d: d, len: len, w: w, kind: m.kind, label: m.label, conn: m.conn, ctype: m.ctype, tech: m.tech, emergencyOnly: emergencyOnly, covered: m.covered, through: m.through));
  }

  void line(int lv, List<double> a, List<double> b, double w, {bool out = false, String? zone, String? bld, bool covered = false}) =>
      lines[lv].add(Line(a, b, w, out, zone, bld: bld, covered: covered));

  static bool onLine(Line l, double x, double y) => l.horiz
      ? (y - l.a[1]).abs() < .01 && x >= _min(l.a[0], l.b[0]) - .01 && x <= _max(l.a[0], l.b[0]) + .01
      : (x - l.a[0]).abs() < .01 && y >= _min(l.a[1], l.b[1]) - .01 && y <= _max(l.a[1], l.b[1]) + .01;
  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;

  void put(int lv, double x, double y) {
    for (final l in lines[lv]) {
      if (onLine(l, x, y)) l.pts.add([x, y]);
    }
  }

  /// Nearest line of a kind: returns the projected point, registered on that line.
  ({List<double> p, bool out}) attach(int lv, double x, double y, [bool Function(Line)? filter]) {
    Line? bestL;
    List<double>? bestP;
    var bd = 1e9;
    for (final l in lines[lv]) {
      if (filter != null && !filter(l)) continue;
      final px = l.horiz ? _min(_max(x, _min(l.a[0], l.b[0])), _max(l.a[0], l.b[0])) : l.a[0];
      final py = l.horiz ? l.a[1] : _min(_max(y, _min(l.a[1], l.b[1])), _max(l.a[1], l.b[1]));
      final d = hypot(px - x, py - y);
      if (d < bd) {
        bd = d;
        bestL = l;
        bestP = [px, py];
      }
    }
    bestL!.pts.add(bestP!);
    return (p: bestP, out: bestL.out);
  }

  /// A node at (x,y) joined by a spur to the nearest corridor.
  String doorNode(int lv, double x, double y, double w, [bool Function(Line)? filter]) {
    final dk = node(lv, x, y), pr = attach(lv, x, y, filter), pk = node(lv, pr.p[0], pr.p[1], out: pr.out);
    if (dk != pk) {
      nodes[dk]!.out = pr.out;
      link(dk, pk, 0, EdgeMeta.walk);
      adj[dk]!.last.w = 1.6;
      adj[pk]!.last.w = 1.6;
    }
    return dk;
  }

  /// Turns every line into nodes at its registered points, joined in order.
  void materialise() {
    for (var lv = 0; lv < levelCount; lv++) {
      for (final l in lines[lv]) {
        final seen = <String, List<double>>{};
        for (final p in l.pts) { seen['${_fx(p[0])},${_fx(p[1])}'] = p; }
        final s = stableSorted(seen.values, (p, q) => l.horiz ? cmpNum(p[0], q[0]) : cmpNum(p[1], q[1]));
        final meta = l.covered ? const EdgeMeta('walk', covered: true) : null;
        for (var i = 0; i < s.length; i++) {
          node(lv, s[i][0], s[i][1], out: l.out ? true : null);
          if (i > 0) link(nk(lv, s[i - 1][0], s[i - 1][1]), nk(lv, s[i][0], s[i][1]), l.w, meta);
        }
      }
    }
  }

  /// A hop between each pair of neighbouring stops of each connector.
  void linkHops(List<Connector> connectors) {
    for (final c in connectors) {
      for (var i = 0; i + 1 < c.lvs.length; i++) {
        final a = c.lvs[i], b = c.lvs[i + 1];
        link(c.at[a]!, c.at[b]!, 4, EdgeMeta('hop', conn: c.id, ctype: c.type), c.cost?.call(a, b) ?? hopCost[c.type]);
      }
    }
  }

  /// A cut-through for a big store with several doors (Android port; the mock-up drew a
  /// straight door-to-door line through the shop walls). Each door leads, through its
  /// entrance, to a point just inside the store; those points are joined across the
  /// store's floor, which stays inside its rect. Every edge is tagged with the store, so
  /// routing can leave cut-throughs out (see [blocked]). Crossing the floor costs 1.25x its
  /// length: only a clearly shorter cut-through beats the public corridors.
  void throughBox(Place p, List<String> doors) {
    const inset = 3.0, prefer = 1.25;
    final r = p.rect, meta = EdgeMeta('walk', through: p.id);
    double inside(double v, double lo, double hi) => hi - lo <= 2 * inset ? (lo + hi) / 2 : v.clamp(lo + inset, hi - inset);
    final inner = <String>[];
    for (final dk in doors) {
      final d = nodes[dk]!, ik = node(p.lv, inside(d.x, r[0], r[2]), inside(d.y, r[1], r[3]));
      nodes[ik]!.inner = true;
      if (ik != dk) link(dk, ik, 6, meta);
      inner.add(ik);
    }
    for (var i = 0; i < inner.length; i++) {
      for (var j = i + 1; j < inner.length; j++) {
        final a = nodes[inner[i]]!, b = nodes[inner[j]]!;
        if (a.k != b.k) link(a.k, b.k, 6, meta, hypot(a.x - b.x, a.y - b.y) * prefer);
      }
    }
  }

  void fixUnjoined(List<Place> places) {
    for (final p in places) {
      if (p.nodes.isEmpty) p.nodes = [nearestNodeAt(p.lv, p.door[0], p.door[1])!];
    }
  }

  String? nearestNodeAt(int lv, double x, double y, {bool includeEmergency = false}) {
    String? best;
    var bd = double.infinity;
    for (final n in nodes.values) {
      if (n.lv == lv && !n.inner && (includeEmergency || !n.emergencyOnly)) {
        final dd = hypot(n.x - x, n.y - y);
        if (dd < bd) { bd = dd; best = n.k; }
      }
    }
    return best;
  }

  // ===== Evacuation-only nodes and edges (added for the Android port) =====
  // Flagged emergencyOnly: normal routing never sees them.

  /// Stair id -> level -> node key of the stair door on that level.
  final emergencyStairs = <String, Map<int, String>>{};

  String emergencyNode(int lv, double x, double y) {
    final k = nk(lv, x, y);
    if (!nodes.containsKey(k)) {
      nodes[k] = GNode(k, lv, x, y)..emergencyOnly = true;
      adj[k] = [];
    }
    return k;
  }

  /// A door joined to the nearest aisle after the lines are materialised, splitting that aisle's edge.
  String emergencyDoor(int lv, double x, double y) {
    Line? best;
    List<double>? bp;
    var bd = 1e9;
    for (final l in lines[lv]) {
      final px = l.horiz ? _min(_max(x, _min(l.a[0], l.b[0])), _max(l.a[0], l.b[0])) : l.a[0];
      final py = l.horiz ? l.a[1] : _min(_max(y, _min(l.a[1], l.b[1])), _max(l.a[1], l.b[1]));
      final d = hypot(px - x, py - y);
      if (d < bd) { bd = d; best = l; bp = [px, py]; }
    }
    final l = best!, p = bp!, dk = emergencyNode(lv, x, y);
    final pk = nk(lv, p[0], p[1]);
    if (!nodes.containsKey(pk)) {
      // the aisle nodes either side of the projected point
      double along(List<double> q) => l.horiz ? q[0] : q[1];
      List<double>? lo, hi;
      for (final q in l.pts) {
        if (!nodes.containsKey(nk(lv, q[0], q[1]))) continue;
        if (along(q) <= along(p) && (lo == null || along(q) > along(lo))) lo = q;
        if (along(q) >= along(p) && (hi == null || along(q) < along(hi))) hi = q;
      }
      emergencyNode(lv, p[0], p[1]);
      for (final q in [lo, hi]) {
        if (q != null) link(pk, nk(lv, q[0], q[1]), l.w, EdgeMeta.walk, null, true);
      }
    }
    if (dk != pk) link(dk, pk, 1.6, EdgeMeta.walk, null, true);
    return dk;
  }
}

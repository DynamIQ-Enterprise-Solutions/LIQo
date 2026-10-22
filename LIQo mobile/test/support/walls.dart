// The wall check: walking never passes through a shop, restroom, department
// store or lift/stair core. Diagonals are fine; walls are not. An edge may only
// touch the space it starts or ends in (its own door spur, a cut-through's store).
import 'package:liqo_mobile/core/engine/graph.dart';
import 'package:liqo_mobile/core/engine/venue.dart';

class WallHit {
  final int lv;
  final GNode a, b;
  final Edge e;
  final List<String> crossed;
  WallHit(this.lv, this.a, this.b, this.e, this.crossed);
  @override
  String toString() =>
      'L$lv ${e.kind}${e.label != null ? ' "${e.label}"' : ''} (${a.x.toStringAsFixed(1)},${a.y.toStringAsFixed(1)})->(${b.x.toStringAsFixed(1)},${b.y.toStringAsFixed(1)}) '
      '${(b.x - a.x).abs().toStringAsFixed(0)}x${(b.y - a.y).abs().toStringAsFixed(0)} m through ${crossed.join(', ')}';
}

/// The solid rects on a level, named. Kiosks standing on a walkway (an information desk,
/// an ATM) are not walls: the walkway runs past them.
List<(String, List<double>)> wallsOn(Venue v, int lv) => [
      for (final p in v.places)
        if (p.lv == lv && !p.onLine && (p.kind == 'store' || p.kind == 'box' || (p.kind == 'svc' && _area(p.rect) > 16))) (p.name, p.rect),
      for (final s in v.slots[lv])
        if (s.kind == 'core') ('core ${s.id ?? ''}', s.rect),
    ];

double _area(List<double> r) => (r[2] - r[0]).abs() * (r[3] - r[1]).abs();

bool _contains(List<double> r, double x, double y) => x >= r[0] - .01 && x <= r[2] + .01 && y >= r[1] - .01 && y <= r[3] + .01;

/// Does the segment pass through the rect's interior (shrunk by [inset])? Liang-Barsky clipping.
bool crossesInterior(List<double> r, double x1, double y1, double x2, double y2, {double inset = .5}) {
  final l = r[0] + inset, t = r[1] + inset, rr = r[2] - inset, b = r[3] - inset;
  if (rr <= l || b <= t) return false;
  final dx = x2 - x1, dy = y2 - y1;
  var u0 = 0.0, u1 = 1.0;
  for (final (p, q) in [(-dx, x1 - l), (dx, rr - x1), (-dy, y1 - t), (dy, b - y1)]) {
    if (p == 0) {
      if (q < 0) return false;
    } else {
      final u = q / p;
      if (p < 0) {
        if (u > u1) return false;
        if (u > u0) u0 = u;
      } else {
        if (u < u0) return false;
        if (u < u1) u1 = u;
      }
    }
  }
  return (u1 - u0) * (dx.abs() + dy.abs()) > .01;
}

/// Every walking edge (each once) that passes through a wall it neither starts nor ends in.
List<WallHit> wallHits(Venue v) {
  final gr = v.graph, hits = <WallHit>[];
  final walls = [for (var lv = 0; lv < v.levelCount; lv++) wallsOn(v, lv)];
  for (final a in gr.nodes.values) {
    for (final e in gr.adj[a.k]!) {
      if (e.kind == 'hop' || a.k.compareTo(e.to) >= 0) continue;
      final b = gr.nodes[e.to]!;
      if (a.lv != b.lv) continue;
      final crossed = [
        for (final (name, r) in walls[a.lv])
          if (!_contains(r, a.x, a.y) && !_contains(r, b.x, b.y) && crossesInterior(r, a.x, a.y, b.x, b.y)) name,
      ];
      if (crossed.isNotEmpty) hits.add(WallHit(a.lv, a, b, e, crossed));
    }
  }
  return hits;
}

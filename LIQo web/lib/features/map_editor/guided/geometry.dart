import 'dart:math' as math;
import 'dart:typed_data';

import '../map_models.dart';

// Geometry for the easy editor's tools (Round 18): merging and splitting rooms,
// and snapping what people click so walls can never come out crooked.

double _dist(List<double> a, List<double> b) => math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));

/// Signed area of a ring (positive or negative by winding).
double ringArea(List<List<double>> ring) {
  var a = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i];
    final q = ring[(i + 1) % ring.length];
    a += p[0] * q[1] - q[0] * p[1];
  }
  return a / 2;
}

/// The point snapped to the nearest wall end within [tol] metres, else onto the
/// nearest wall within [tol], else unchanged.
List<double> snapToWalls(List<double> p, List<Wall> walls, {double tol = 0.4}) {
  List<double>? best;
  var bestD = tol;
  for (final w in walls) {
    for (final e in [w.a, w.b]) {
      final d = _dist(e, p);
      if (d < bestD) {
        bestD = d;
        best = [e[0], e[1]];
      }
    }
  }
  if (best != null) return best;
  bestD = tol;
  for (final w in walls) {
    final r = pointToSegment(p[0], p[1], w.a, w.b);
    if (r.dist < bestD) {
      bestD = r.dist;
      best = w.pointAt(r.t);
    }
  }
  return best ?? [p[0], p[1]];
}

/// [b] moved so the line a→b runs exactly straight when it is within [deg] of
/// horizontal or vertical (people rarely mean a slightly slanted wall).
List<double> straighten(List<double> a, List<double> b, {double deg = 8}) {
  final dx = b[0] - a[0];
  final dz = b[1] - a[1];
  final angle = math.atan2(dz.abs(), dx.abs()) * 180 / math.pi;
  if (angle <= deg) return [b[0], a[1]];
  if (angle >= 90 - deg) return [a[0], b[1]];
  return b;
}

/// Clips a ring to one side of the line p→q (Sutherland–Hodgman); [left] picks the side.
List<List<double>> _clip(List<List<double>> ring, List<double> p, List<double> q, bool left) {
  double side(List<double> x) => (q[0] - p[0]) * (x[1] - p[1]) - (q[1] - p[1]) * (x[0] - p[0]);
  bool inside(List<double> x) => left ? side(x) >= 0 : side(x) <= 0;
  final out = <List<double>>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final ia = inside(a);
    final ib = inside(b);
    if (ia) out.add([a[0], a[1]]);
    if (ia != ib) {
      final sa = side(a);
      final sb = side(b);
      final t = sa / (sa - sb);
      out.add([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]);
    }
  }
  return out;
}

/// Where the line through p and q crosses the ring: the first and last crossing
/// (the chord a new wall is placed on), or null when it does not cross.
(List<double>, List<double>)? chord(List<List<double>> ring, List<double> p, List<double> q) {
  final dx = q[0] - p[0];
  final dz = q[1] - p[1];
  final len = math.sqrt(dx * dx + dz * dz);
  if (len == 0) return null;
  final ts = <double>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final ex = b[0] - a[0];
    final ez = b[1] - a[1];
    final den = dx * ez - dz * ex;
    if (den.abs() < 1e-12) continue;
    final t = ((a[0] - p[0]) * ez - (a[1] - p[1]) * ex) / den;
    final s = ((a[0] - p[0]) * dz - (a[1] - p[1]) * dx) / den;
    if (s >= 0 && s <= 1) ts.add(t);
  }
  if (ts.length < 2) return null;
  ts.sort();
  return ([p[0] + dx * ts.first, p[1] + dz * ts.first], [p[0] + dx * ts.last, p[1] + dz * ts.last]);
}

/// Splits a room with the straight line through p and q into two rooms, or
/// null when the line does not cut it into two real pieces (≥ 0.5 m² each).
(List<List<double>>, List<List<double>>)? splitRing(List<List<double>> ring, List<double> p, List<double> q) {
  if (_dist(p, q) < 0.05) return null;
  final a = _clip(ring, p, q, true);
  final b = _clip(ring, p, q, false);
  if (a.length < 3 || b.length < 3 || ringArea(a).abs() < 0.5 || ringArea(b).abs() < 0.5) return null;
  return (a, b);
}

/// The union of two rooms as one ring. The rooms are filled on a fine grid, the
/// gap between them (a wall up to [gap] metres thick) is closed, and the outer
/// edge is traced and simplified. Null when they do not touch across a wall.
List<List<double>>? unionRings(List<List<double>> a, List<List<double>> b, {double gap = 0.5}) {
  var minX = double.infinity, minZ = double.infinity, maxX = -double.infinity, maxZ = -double.infinity;
  for (final p in [...a, ...b]) {
    minX = math.min(minX, p[0]);
    minZ = math.min(minZ, p[1]);
    maxX = math.max(maxX, p[0]);
    maxZ = math.max(maxZ, p[1]);
  }
  minX -= gap + 0.2;
  minZ -= gap + 0.2;
  maxX += gap + 0.2;
  maxZ += gap + 0.2;
  var cell = 0.05;
  final area = (maxX - minX) * (maxZ - minZ);
  if (area / (cell * cell) > 1500000) cell = math.sqrt(area / 1500000);
  final gw = ((maxX - minX) / cell).ceil();
  final gh = ((maxZ - minZ) / cell).ceil();
  var grid = Uint8List(gw * gh);
  final pa = Poly(outer: a);
  final pb = Poly(outer: b);
  for (var y = 0; y < gh; y++) {
    final z = minZ + (y + 0.5) * cell;
    for (var x = 0; x < gw; x++) {
      final px = minX + (x + 0.5) * cell;
      if (pointInPoly(px, z, pa) || pointInPoly(px, z, pb)) grid[y * gw + x] = 1;
    }
  }
  // Closing (grow then shrink) bridges the wall between the rooms.
  final r = (gap / cell / 2).ceil();
  Uint8List pass(Uint8List src, bool grow, bool rows) {
    final out = Uint8List(gw * gh);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        var hit = !grow;
        for (var k = -r; k <= r; k++) {
          final xx = rows ? x + k : x;
          final yy = rows ? y : y + k;
          final v = xx >= 0 && yy >= 0 && xx < gw && yy < gh ? src[yy * gw + xx] : 0;
          if (grow && v == 1) {
            hit = true;
            break;
          }
          if (!grow && v == 0) {
            hit = false;
            break;
          }
        }
        out[y * gw + x] = hit ? 1 : 0;
      }
    }
    return out;
  }

  grid = pass(pass(pass(pass(grid, true, true), true, false), false, true), false, false);
  // One connected piece only: otherwise the rooms do not touch across a wall.
  final seen = Uint8List(gw * gh);
  var start = -1;
  for (var i = 0; i < gw * gh; i++) {
    if (grid[i] == 1) {
      start = i;
      break;
    }
  }
  if (start < 0) return null;
  final stack = [start];
  seen[start] = 1;
  var count = 0;
  while (stack.isNotEmpty) {
    final c = stack.removeLast();
    count++;
    final x = c % gw;
    final y = c ~/ gw;
    for (final n in [if (x > 0) c - 1, if (x < gw - 1) c + 1, if (y > 0) c - gw, if (y < gh - 1) c + gw]) {
      if (grid[n] == 1 && seen[n] == 0) {
        seen[n] = 1;
        stack.add(n);
      }
    }
  }
  var total = 0;
  for (final v in grid) {
    total += v;
  }
  if (count < total) return null;
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < gw && y < gh && grid[y * gw + x] == 1;
  final edges = <int, int>{};
  int key(int x, int y) => y * (gw + 1) + x;
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      if (!inside(x, y)) continue;
      if (!inside(x, y - 1)) edges[key(x, y)] = key(x + 1, y);
      if (!inside(x + 1, y)) edges[key(x + 1, y)] = key(x + 1, y + 1);
      if (!inside(x, y + 1)) edges[key(x + 1, y + 1)] = key(x, y + 1);
      if (!inside(x - 1, y)) edges[key(x, y + 1)] = key(x, y);
    }
  }
  if (edges.isEmpty) return null;
  var k = edges.keys.reduce(math.min);
  final pts = <List<double>>[];
  final visited = <int>{};
  while (!visited.contains(k) && pts.length < 200000) {
    visited.add(k);
    pts.add([minX + (k % (gw + 1)) * cell, minZ + (k ~/ (gw + 1)) * cell]);
    final n = edges[k];
    if (n == null) break;
    k = n;
  }
  return tidyRing(_simplify(pts, cell * 1.5), cell * 1.2);
}

/// Douglas–Peucker on a closed ring.
List<List<double>> _simplify(List<List<double>> pts, double tol) {
  if (pts.length < 4) return pts;
  final keep = List<bool>.filled(pts.length, false);
  keep[0] = true;
  keep[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (s, e) = stack.removeLast();
    var maxD = 0.0;
    var idx = -1;
    final a = pts[s];
    final b = pts[e];
    final len = _dist(a, b) == 0 ? 1.0 : _dist(a, b);
    for (var i = s + 1; i < e; i++) {
      final d = ((b[1] - a[1]) * pts[i][0] - (b[0] - a[0]) * pts[i][1] + b[0] * a[1] - b[1] * a[0]).abs() / len;
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > tol && idx > 0) {
      keep[idx] = true;
      stack.add((s, idx));
      stack.add((idx, e));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

/// Drops points on a straight line between their neighbours, then near-duplicates
/// (keeping the true corner).
List<List<double>> tidyRing(List<List<double>> ring, double tol) {
  final pts = [...ring];
  double off(List<double> x, List<double> a, List<double> b) {
    final l = _dist(a, b) == 0 ? 1.0 : _dist(a, b);
    return ((b[0] - a[0]) * (x[1] - a[1]) - (b[1] - a[1]) * (x[0] - a[0])).abs() / l;
  }

  for (final straightPass in [true, false]) {
    var changed = true;
    while (changed && pts.length > 3) {
      changed = false;
      for (var i = 0; i < pts.length && pts.length > 3; i++) {
        final p = pts[(i - 1 + pts.length) % pts.length];
        final q = pts[i];
        final r = pts[(i + 1) % pts.length];
        var drop = -1;
        if (straightPass) {
          if (_dist(q, p) > tol && _dist(q, r) > tol && off(q, p, r) <= tol * 0.5) drop = i;
        } else if (_dist(q, p) <= tol) {
          final pi = (i - 1 + pts.length) % pts.length;
          final pp = pts[(i - 2 + pts.length) % pts.length];
          drop = off(p, pp, r) <= off(q, pp, r) ? pi : i;
        }
        if (drop >= 0) {
          pts.removeAt(drop);
          changed = true;
          i = math.max(-1, math.min(i, drop) - 2);
        }
      }
    }
  }
  return pts;
}

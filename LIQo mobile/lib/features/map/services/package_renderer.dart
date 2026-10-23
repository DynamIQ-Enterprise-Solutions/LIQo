// Draws a published map (a PackageVenue) with the painter's primitives: the
// site (ground, building masses), one level's plan (outline plates, walkways,
// courts, depth-sorted rooms, boundary and glass walls with gaps at doors,
// lift and stair cores) and the stacked view's plates. Shapes are polygons in
// the package's one branch-wide frame.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine/package/package_venue.dart';
import '../../../core/engine/util.dart';
import 'map_constants.dart';
import 'map_painter.dart';
import 'venue_renderer.dart';

List<double> _centroid(Poly p) {
  var x = 0.0, y = 0.0;
  for (final q in p) {
    x += q[0];
    y += q[1];
  }
  return [x / p.length, y / p.length];
}

class PackageRenderer implements VenueRenderer {
  PackageRenderer(this.v);
  final PackageVenue v;

  /// The fill of a space's floor, or null for a room drawn as a raised block.
  static String? _floorToken(PackageSpace s) => switch (s.type) {
        'corridor' => '--corridor',
        'atrium' => '--plazaG',
        'outdoor' => '--walk',
        'parking' => '--bs',
        _ => null,
      };

  /// A room's block: its height and colours.
  static (double, String, String, String) _block(PackageSpace s) => switch (s.type) {
        'anchor' => (boxH, '--box', '--box-a', '--box-b'),
        'restroom' || 'service' || 'office' || 'storage' => (slabH, '--staff', '--slab-a', '--slab-b'),
        _ => (slabH, '--store', '--slab-a', '--slab-b'),
      };

  int _top(PackageBuilding b) => b.levels.isEmpty ? v.ground : b.levels.reduce(math.max);

  /// A building's footprint: its outline on its lowest level at or above ground (else its bounds).
  Poly _footprint(PackageBuilding b) {
    for (final lv in [...b.levels]..sort()) {
      if (lv < v.ground) continue;
      for (final o in v.outlines[lv]) {
        if (o.building == b.id) return o.outer;
      }
    }
    return rectArrL(b.bounds);
  }

  double _roofZ(PackageBuilding b) => v.zOf(_top(b)) + v.heights[_top(b)];

  void _ground(MapPainter p, bool full) {
    p.group(full ? 1 : .4, () => p.flat(rectArrL(v.bounds), '--walk', 0));
  }

  // ===== The site =====
  @override
  void siteBase(MapPainter p) {
    _ground(p, true);
    final items = <(double, void Function())>[];
    for (final b in v.buildings) {
      if (_top(b) < v.ground) continue; // underground: not seen from outside
      final f = _footprint(b), c = _centroid(f);
      items.add((p.P(c[0], c[1]).dy, () => p.hitGroup('bldg', b.id, () => p.prism(f, math.max(0, v.zOf(b.levels.reduce(math.min))), _roofZ(b), '--roof', '--wall-a', '--wall-b'))));
    }
    for (final it in stableSorted(items, (a, b) => cmpNum(a.$1, b.$1))) {
      it.$2();
    }
  }

  @override
  void siteLabels(MapPainter p) {
    var first = true;
    for (final b in v.buildings) {
      if (_top(b) < v.ground) continue;
      final c = _centroid(_footprint(b)), q = p.P(c[0], c[1], _roofZ(b) + 6);
      if (first) {
        p.text(b.name.toUpperCase(), q.dx, q.dy, size: 13, weight: FontWeight.w800, ls: 1.2);
        first = false;
      } else {
        p.text(b.name, q.dx, q.dy);
      }
    }
  }

  // ===== One level's plan =====
  @override
  void levelBase(MapPainter p, int lv) {
    _ground(p, lv == v.ground);
    final storeLine = p.c('store-line');
    for (final o in v.outlines[lv]) {
      p.prism(o.outer, -plateT, 0, '--floor', '--wall-a', '--wall-b');
      for (final h in o.holes) {
        p.flat(h, '--void', 0.01);
      }
    }
    // walkways first, then rooms as blocks, back to front
    final here = [for (final s in v.spaces) if (s.lv == lv) s];
    for (final s in here) {
      final tok = _floorToken(s);
      if (tok != null && p.visible(s.shape)) p.flat(s.shape, tok, 0.02);
    }
    final walls = [for (final w in v.walls) if (w.lv == lv && (w.kind == 'boundary' || w.kind == 'glass')) w];
    final pieces = <({Poly rect, bool front, bool glass})>[];
    final centre = [(v.bounds[0] + v.bounds[2]) / 2, (v.bounds[1] + v.bounds[3]) / 2];
    for (final w in walls) {
      for (final seg in _splitAtOpenings(w)) {
        pieces.add((rect: p.wallRect(seg[0], seg[1], seg[2], seg[3], math.max(w.t, .4)), front: p.isFrontWall(seg, centre), glass: w.kind == 'glass'));
      }
    }
    void wall(({Poly rect, bool front, bool glass}) x) =>
        x.glass ? p.prism(x.rect, 0, railH, '--glass-top', '--glass-a', '--glass-b') : p.prism(x.rect, 0, wallH, '--wall-top', '--wall-a', '--wall-b');
    for (final x in pieces.where((x) => !x.front)) {
      wall(x);
    }
    final items = <(double, void Function())>[];
    for (final s in here) {
      if (_floorToken(s) != null || s.walkable || !p.visible(s.shape)) continue;
      final (h, top, a, b) = _block(s);
      final c = _centroid(s.shape);
      items.add((p.P(c[0], c[1]).dy, () => p.prism(s.shape, 0, h, top, a, b, storeLine)));
    }
    for (final c in v.connectors) {
      final k = c.at[lv];
      final n = k == null ? null : v.graph.nodes[k];
      if (n == null) continue;
      final (hw, hh, h) = switch (c.type) { 'escalator' => (4.0, 1.8, 1.0), 'ramp' || 'walkway' => (5.0, 3.0, .3), _ => (2.5, 2.5, coreH) };
      items.add((p.P(n.x, n.y).dy + 1, () => p.prism(rectArr(n.x - hw, n.y - hh, n.x + hw, n.y + hh), 0, h, '--col-top', '--col-a', '--col-b')));
    }
    for (final it in stableSorted(items, (a, b) => cmpNum(a.$1, b.$1))) {
      it.$2();
    }
    for (final x in pieces.where((x) => x.front)) {
      wall(x);
    }
  }

  /// A wall, minus gaps where a walkable opening sits on it.
  List<List<double>> _splitAtOpenings(PackageWall w) {
    final ax = w.a[0], ay = w.a[1], dx = w.b[0] - ax, dy = w.b[1] - ay, len = hypot(dx, dy);
    if (len < .01) return const [];
    final gaps = <List<double>>[];
    for (final o in v.openings) {
      if (o.lv != w.lv || !o.walkable) continue;
      final t = ((o.at[0] - ax) * dx + (o.at[1] - ay) * dy) / (len * len);
      if (t < 0 || t > 1) continue;
      final off = ((o.at[0] - ax) * dy - (o.at[1] - ay) * dx).abs() / len;
      if (off > math.max(w.t, .4) + .3) continue;
      gaps.add([t * len - o.w / 2, t * len + o.w / 2]);
    }
    gaps.sort((p, q) => p[0].compareTo(q[0]));
    final out = <List<double>>[];
    var from = 0.0;
    List<double> at(double s) => [ax + dx * s / len, ay + dy * s / len];
    for (final g in gaps) {
      if (g[0] > from + .3) out.add([...at(from), ...at(g[0])]);
      from = math.max(from, g[1]);
    }
    if (len > from + .3) out.add([...at(from), ...at(len)]);
    return out;
  }

  // ===== The stacked view =====
  @override
  void stackPlate(MapPainter p, int lv) {
    MapPainter.curLv = lv;
    for (final o in v.outlines[lv]) {
      p.prism(o.outer, -plateT, 0, '--floor', '--wall-a', '--wall-b');
    }
    for (final s in v.spaces) {
      if (s.lv != lv) continue;
      final tok = _floorToken(s);
      if (tok != null) {
        p.flat(s.shape, tok == '--plazaG' ? '--corridor' : tok, 0.02);
      } else if (!s.walkable) {
        final (_, top, _, _) = _block(s);
        p.flat(s.shape, top, 0.05, '--store-line');
      }
    }
  }
}

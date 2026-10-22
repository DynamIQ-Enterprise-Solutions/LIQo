// Draws a kit venue (the offline malls) with the painter's primitives: the site
// (ground, building masses, roofs, bridges, canopies), one level's plan
// (plates, corridors, courts and atriums, depth-sorted shop prisms, cores,
// walls with door gaps) and the stacked view's plates.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/engine/kit/kit_spec.dart';
import '../../../core/engine/kit/kit_venue.dart';
import '../../../core/engine/rng.dart';
import '../../../core/engine/util.dart';
import 'map_constants.dart';
import 'map_painter.dart';
import 'venue_renderer.dart';

double _fx1(double n) => double.parse(n.toStringAsFixed(1));

class KitRenderer implements VenueRenderer {
  final KitVenue v;
  KitRenderer(this.v);
  KSpec get s => v.spec;

  late final List<List<double>> _trees = () {
    final r = rng(s.seed + 7), t = <List<double>>[];
    for (final (rect, n) in s.trees) {
      for (var i = 0; i < n; i++) {
        final x = rect[0] + r() * (rect[2] - rect[0]);
        final y = rect[1] + r() * (rect[3] - rect[1]);
        t.add([x, y]);
      }
    }
    return t;
  }();

  int _top(KBld b) => b.lvs.reduce(math.max);
  double _roofZ(KBld b) => v.zOf(_top(b)) + (b.kind == 'parking' ? 1.4 : 5);
  double _baseZ(KBld b) => math.max(0, v.zOf(b.lvs.reduce(math.min)));
  List<double> _centre(List<double> r) => [(r[0] + r[2]) / 2, (r[1] + r[3]) / 2];

  // ===== The ground =====
  void _ground(MapPainter p, bool full) {
    final S = p.cam.S;
    p.group(full ? 1 : 0.4, () {
      p.flat(rectArrL(s.site), '--grass', 0);
      for (final gf in s.groundFx) {
        p.flat(rectArrL(gf.rect), '--${gf.token}', 0.02);
      }
      for (final z in v.zones.where((z) => z.wing == 'O')) {
        p.polygon(p.pts(rectArrL(z.rect), .03), fill: p.op(p.c('bs'), .5));
      }
      for (final l in s.lines) {
        if (l.out && l.lvs.contains(v.ground) && (l.bld == null || v.bld(l.bld!).kind == 'station')) {
          p.flat(rectArrL(lineRect(l.x1, l.y1, l.x2, l.y2, l.w + 2)), '--walk', 0.03);
        }
      }
      for (final t in _trees) {
        final q = p.P(t[0], t[1], 0), r = clampD(4.2 * S, 2, 14);
        if (q.dx > -20 && q.dx < p.rx(400) && q.dy > -20 && q.dy < p.by(900)) p.circle(Offset(q.dx, q.dy - r * .6), r, fill: p.c('tree'), stroke: p.c('tree-dark'), sw: .8);
      }
    });
  }

  // ===== The site =====
  @override
  void siteBase(MapPainter p) {
    _ground(p, true);
    final items = <(double, void Function())>[];
    for (final b in s.buildings) {
      if (_top(b) < v.ground && b.kind == 'parking') continue; // underground: not seen from outside
      final c = _centre(b.rect);
      items.add((p.P(c[0], c[1]).dy, () {
        void draw() => _mass(p, b);
        if (b.tappable) {
          p.hitGroup('bldg', b.id, draw);
        } else {
          draw();
        }
      }));
    }
    for (final it in stableSorted(items, (a, b) => cmpNum(a.$1, b.$1))) {
      it.$2();
    }
    // bridges, and canopies over covered walkways
    for (final k in s.links) {
      final z = v.zOf(k.lv);
      if (z <= 0) continue;
      p.prism(rectArrL(lineRect(k.x1, k.y1, k.x2, k.y2, k.w)), z - 1, z + 3, '--glass-top', '--glass-a', '--glass-b');
    }
    for (final l in s.lines) {
      if (l.covered) p.flat(rectArrL(lineRect(l.x1, l.y1, l.x2, l.y2, l.w + 2)), '--glass-top', 3.6);
    }
  }

  void _mass(MapPainter p, KBld b) {
    final r = rectArrL(b.rect), top = _roofZ(b), base = _baseZ(b);
    switch (b.kind) {
      case 'parking': // decks with gaps, so the levels read
        for (final lv in b.lvs) {
          if (v.zOf(lv) < 0) continue;
          p.prism(r, v.zOf(lv) - 1.2, v.zOf(lv) + 1.4, '--bs', '--wall-a', '--wall-b');
        }
      case 'station': // an elevated platform on columns, under a glass canopy
        final z = v.zOf(_top(b));
        for (var x = b.rect[0] + 10; x < b.rect[2]; x += 40) {
          final cy = (b.rect[1] + b.rect[3]) / 2;
          p.prism(rectArr(x - 1.5, cy - 1.5, x + 1.5, cy + 1.5), 0, z - 1, '--col-top', '--col-a', '--col-b');
        }
        p.prism(r, z - 1, z, '--walk', '--wall-a', '--wall-b');
        p.flat(r, '--glass-top', z + 4);
      default:
        p.prism(r, base, top, '--roof', '--wall-a', '--wall-b');
        if (b.kind == 'openair') { // open streets between the buildings of the wing
          for (final l in s.lines.where((l) => l.bld == b.id && l.lvs.contains(_top(b)))) {
            p.flat(rectArrL(lineRect(l.x1, l.y1, l.x2, l.y2, l.w)), '--plazaG', top + .05);
          }
        }
        if (b.roof == 'skylight') {
          for (final l in s.lines.where((l) => l.bld == b.id && !l.out && l.zone == null && l.lvs.contains(_top(b)))) {
            p.flat(rectArrL(lineRect(l.x1, l.y1, l.x2, l.y2, l.w * .7)), '--glass-top', top + .05);
          }
        }
        if (b.roof == 'garden') p.flat(rectArr(b.rect[0] + 6, b.rect[1] + 6, b.rect[2] - 6, b.rect[3] - 6), '--grass', top + .05);
        if (b.roof == 'dome' || b.roof == 'skylight' || b.roof == 'garden') {
          for (final a in s.areas.where((a) => a.bld == b.id && (a.kind == 'void' || a.kind == 'bowl'))) {
            final c = _centre(a.rect), rad = math.min(a.rect[2] - a.rect[0], a.rect[3] - a.rect[1]) / 2;
            p.prism(ngon(c[0], c[1], rad, 16), top, top + math.min(14, rad / 3), '--glass-top', '--glass-a', '--glass-b');
            if (b.roof != 'dome') break;
          }
        }
    }
  }

  @override
  void siteLabels(MapPainter p) {
    var first = true;
    for (final b in s.buildings) {
      if (!b.tappable || (_top(b) < v.ground && b.kind == 'parking')) continue;
      final c = _centre(b.rect), q = p.P(c[0], c[1], _roofZ(b) + 6);
      if (first) {
        p.text(b.name.toUpperCase(), q.dx, q.dy, size: 13, weight: FontWeight.w800, ls: 1.2);
        first = false;
      } else {
        p.text(b.name, q.dx, q.dy);
      }
    }
    for (final l in s.labels) {
      final q = p.P(l.x, l.y, l.z);
      p.text(l.text, q.dx, q.dy, size: l.big ? 13 : 11.5, weight: l.big ? FontWeight.w800 : FontWeight.w600);
    }
    for (final z in v.zones.where((z) => z.wing == 'O')) {
      final q = p.P(z.pt[0], z.pt[1], 0);
      p.hitGroup('poi', z.id, () => p.circle(q, 9, fill: p.c('poi'), stroke: p.pal.white, sw: 2));
      p.text(z.id.substring(z.id.length - 2), q.dx, q.dy + 4, size: 10, fill: p.pal.white, halo: false);
    }
    void poi(String id, double x, double y, String gl, Color fill, String label) {
      final q = p.P(x, y, 0), px = q.dx, py = q.dy;
      p.hitGroup('poi', id, () {
        p.line(Offset(px, py), Offset(px, py - 14), fill, 2);
        p.circle(Offset(px, py - 22), 10, fill: fill, stroke: p.pal.white, sw: 2);
        p.glyph(gl, px - 6.5, py - 28.5, 13, p.pal.white);
      });
      p.text(label, px, py + 9);
    }

    for (final o in s.pois) {
      poi(o.id, o.x, o.y, o.glyph, p.c('poi'), p.tr(o.simple));
    }
    // exits are pinned on the floor plans; on a campus this size they would crowd the overview
  }

  // ===== One level's plan =====
  @override
  void levelBase(MapPainter p, int lv) {
    _ground(p, lv == v.ground);
    final storeLine = p.c('store-line');
    // buildings that end below this level: their roofs, for context
    p.group(.55, () {
      for (final b in s.buildings) {
        if (!b.lvs.contains(lv) && _top(b) < lv && _top(b) >= v.ground && b.kind != 'station') p.flat(rectArrL(b.rect), '--roof', 0.01);
      }
    });
    final here = [for (final b in s.buildings) if (b.lvs.contains(lv)) b];
    for (final b in here) {
      final tok = switch (b.kind) { 'parking' => '--bs', 'openair' => '--plazaG', 'station' => '--walk', _ => '--floor' };
      p.prism(rectArrL(b.rect), -plateT, 0, tok, '--wall-a', '--wall-b');
    }
    // corridors, aisles and paths
    for (final l in s.lines.where((l) => l.lvs.contains(lv))) {
      final r = lineRect(l.x1, l.y1, l.x2, l.y2, l.w);
      if (l.zone != null) {
        _bays(p, l);
      } else {
        p.flat(rectArrL(r), l.out ? '--walk' : '--corridor', 0.02);
      }
    }
    for (final k in s.links.where((k) => k.lv == lv)) {
      p.flat(rectArrL(lineRect(k.x1, k.y1, k.x2, k.y2, k.w)), '--corridor', 0.03);
    }
    // courts, atriums, gardens
    final rails = <({Poly rect, bool front})>[];
    for (final a in s.areas.where((a) => a.lvs.contains(lv))) {
      switch (a.kind) {
        case 'court':
          p.flat(rectArrL(a.rect), lv == v.ground ? '--plazaG' : '--corridor', 0.03, '--outline');
        case 'void':
          p.flat(rectArrL(a.rect), '--void', 0.04);
          final r = a.rect, c = _centre(r);
          for (final w in [[r[0], r[1], r[2], r[1]], [r[2], r[1], r[2], r[3]], [r[2], r[3], r[0], r[3]], [r[0], r[3], r[0], r[1]]]) {
            rails.add((rect: p.wallRect(w[0], w[1], w[2], w[3], .5), front: p.isFrontWall(w, c)));
          }
        case 'boh':
          p.flat(rectArrL(a.rect), '--staff', 0.02);
        case 'garden':
          p.flat(rectArrL(a.rect), '--grass', 0.03);
        case 'plaza' || 'portal':
          p.flat(rectArrL(a.rect), '--plazaG', 0.03);
        case 'bowl':
          final r = a.rect;
          for (var i = 0; i < 3; i++) {
            final d = i * math.min(r[2] - r[0], r[3] - r[1]) / 8;
            p.prism(rectArr(r[0] + d, r[1] + d, r[2] - d, r[3] - d), 0, 1.2 * (3 - i), i == 2 ? '--plazaG' : '--slab-a', '--slab-a', '--slab-b');
          }
      }
    }
    // walls around each building, with gaps where lines and bridges leave it
    final walls = <({Poly rect, bool front})>[];
    for (final b in here.where((b) => b.kind == 'mall' || b.kind == 'arena' || b.kind == 'tower')) {
      final r = b.rect, c = _centre(r);
      for (final e in [[r[0], r[1], r[2], r[1]], [r[2], r[1], r[2], r[3]], [r[2], r[3], r[0], r[3]], [r[0], r[3], r[0], r[1]]]) {
        for (final w in _splitWall(e, lv)) {
          walls.add((rect: p.wallRect(w[0], w[1], w[2], w[3], 2.2), front: p.isFrontWall(w, c)));
        }
      }
    }
    for (final x in walls) {
      if (!x.front) p.prism(x.rect, 0, wallH, '--wall-top', '--wall-a', '--wall-b');
    }
    for (final x in rails) {
      if (!x.front) p.prism(x.rect, 0, railH, '--glass-top', '--glass-a', '--glass-b');
    }
    final items = <(double, void Function())>[];
    for (final k in v.kslots) {
      if (k.lv != lv) continue;
      final poly = rectArrL(k.rect);
      if (!p.visible(poly)) continue;
      final c = _centre(k.rect);
      items.add((p.P(c[0], c[1]).dy, () => p.prism(poly, 0, slabH, k.kind == 'wc' ? '--staff' : '--store', '--slab-a', '--slab-b', storeLine)));
    }
    for (final a in s.anchors.where((a) => a.names.containsKey(lv))) {
      final poly = rectArrL(a.rect);
      if (!p.visible(poly)) continue;
      final c = _centre(a.rect);
      items.add((p.P(c[0], c[1]).dy, () => p.prism(poly, 0, boxH, '--box', '--box-a', '--box-b', storeLine)));
    }
    for (final c in s.conns.where((c) => c.lvs.contains(lv))) {
      final (hw, hh, h) = switch (c.type) { 'escalator' => (4.0, 1.8, 1.0), 'ramp' => (5.0, 3.0, .3), _ => (4.0, 4.0, coreH) };
      items.add((p.P(c.x, c.y).dy + 1, () => p.prism(rectArr(c.x - hw, c.y - hh, c.x + hw, c.y + hh), 0, h, '--col-top', '--col-a', '--col-b')));
    }
    for (final it in stableSorted(items, (a, b) => cmpNum(a.$1, b.$1))) {
      it.$2();
    }
    for (final x in walls) {
      if (x.front) p.prism(x.rect, 0, wallH, '--wall-top', '--wall-a', '--wall-b');
    }
    for (final x in rails) {
      if (x.front) p.prism(x.rect, 0, railH, '--glass-top', '--glass-a', '--glass-b');
    }
    // bridge railings
    for (final k in s.links.where((k) => k.lv == lv)) {
      final horiz = k.y1 == k.y2, o = k.w / 2;
      final sides = horiz ? [[k.x1, k.y1 - o, k.x2, k.y1 - o], [k.x1, k.y1 + o, k.x2, k.y1 + o]] : [[k.x1 - o, k.y1, k.x1 - o, k.y2], [k.x1 + o, k.y1, k.x1 + o, k.y2]];
      for (final w in sides) {
        p.prism(p.wallRect(w[0], w[1], w[2], w[3], .5), 0, railH, '--glass-top', '--glass-a', '--glass-b');
      }
    }
  }

  /// Parking bays along an aisle: dashed bands on both sides, like Aurora's basements.
  void _bays(MapPainter p, KLine l) {
    final dash = [_fx1(math.max(1, p.cam.S * .45)), _fx1(math.max(2, p.cam.S * 2))];
    final horiz = l.y1 == l.y2, a = horiz ? math.min(l.x1, l.x2) : math.min(l.y1, l.y2), b = horiz ? math.max(l.x1, l.x2) : math.max(l.y1, l.y2);
    final c = horiz ? l.y1 : l.x1, o = l.w / 2;
    for (final band in [[c - o - 5.5, c - o], [c + o, c + o + 5.5]]) {
      final r = horiz ? rectArr(a, band[0], b, band[1]) : rectArr(band[0], a, band[1], b);
      p.polygon(p.pts(r, .03), stroke: p.c('bs-line'), sw: .8, dash: dash);
    }
  }

  /// A wall segment, minus door gaps where a line, bridge or exit meets it on this level.
  List<List<double>> _splitWall(List<double> e, int lv) {
    final horiz = e[1] == e[3], a = horiz ? math.min(e[0], e[2]) : math.min(e[1], e[3]), b = horiz ? math.max(e[0], e[2]) : math.max(e[1], e[3]);
    final c = horiz ? e[1] : e[0];
    final gaps = <List<double>>[];
    void gapAt(double x, double y, double w) {
      if (horiz ? (y - c).abs() < 1.5 && x > a && x < b : (x - c).abs() < 1.5 && y > a && y < b) {
        final t = horiz ? x : y;
        gaps.add([t - w / 2, t + w / 2]);
      }
    }

    for (final l in s.lines.where((l) => l.lvs.contains(lv))) {
      gapAt(l.x1, l.y1, l.w);
      gapAt(l.x2, l.y2, l.w);
    }
    for (final k in s.links.where((k) => k.lv == lv)) {
      gapAt(k.x1, k.y1, k.w + 2);
      gapAt(k.x2, k.y2, k.w + 2);
    }
    for (final x in s.exits.where((x) => x.lv == lv)) {
      gapAt(x.ix, x.iy, 10);
    }
    gaps.sort((p, q) => p[0].compareTo(q[0]));
    final out = <List<double>>[];
    var from = a;
    for (final gp in gaps) {
      if (gp[0] > from + .5) out.add(horiz ? [from, c, gp[0], c] : [c, from, c, gp[0]]);
      from = math.max(from, gp[1]);
    }
    if (b > from + .5) out.add(horiz ? [from, c, b, c] : [c, from, c, b]);
    return out;
  }

  // ===== The stacked view =====
  @override
  void stackPlate(MapPainter p, int lv) {
    MapPainter.curLv = lv;
    for (final b in s.buildings.where((b) => b.lvs.contains(lv))) {
      final tok = switch (b.kind) { 'parking' => '--bs', 'openair' => '--plazaG', 'station' => '--walk', _ => '--floor' };
      p.prism(rectArrL(b.rect), -plateT, 0, tok, '--wall-a', '--wall-b');
    }
    for (final l in s.lines.where((l) => l.lvs.contains(lv) && l.zone == null && !l.out)) {
      p.flat(rectArrL(lineRect(l.x1, l.y1, l.x2, l.y2, l.w)), '--corridor', 0.02);
    }
    for (final a in s.areas.where((a) => a.lvs.contains(lv) && a.kind == 'void')) {
      p.flat(rectArrL(a.rect), '--void', 0.04);
    }
    for (final k in v.kslots.where((k) => k.lv == lv)) {
      p.flat(rectArrL(k.rect), k.kind == 'wc' ? '--staff' : '--store', 0.05, '--store-line');
    }
    for (final a in s.anchors.where((a) => a.names.containsKey(lv))) {
      p.prism(rectArrL(a.rect), 0, boxH, '--box', '--box-a', '--box-b', p.c('store-line'));
    }
  }
}

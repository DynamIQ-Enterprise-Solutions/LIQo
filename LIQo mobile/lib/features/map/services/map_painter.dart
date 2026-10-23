// The map: the demo's painter (a port of its mock-up's SVG renderer). Same
// projection, same draw order, same sizes; the colours are LIQo's map tokens
// (MapPal). It reads the navigation (route, dot, places) and the map's camera.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../../core/engine/package/package_venue.dart';
import '../../../core/engine/routing.dart';
import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';
import '../../../core/i18n/words.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/glyphs.dart';
import '../../navigation/models/nav_state.dart';
import '../models/cam.dart';
import '../providers/map_provider.dart';
import 'map_constants.dart';
import 'venue_renderer.dart';

typedef Poly = List<List<double>>;

Poly rectArr(double x1, double y1, double x2, double y2) => [[x1, y1], [x2, y1], [x2, y2], [x1, y2]];
Poly rectArrL(List<double> r) => rectArr(r[0], r[1], r[2], r[3]);
double area(Poly a) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    final p = a[i], q = a[(i + 1) % a.length];
    s += p[0] * q[1] - q[0] * p[1];
  }
  return s / 2;
}

List<double> centroid(Poly a) => [a.fold(0.0, (s, p) => s + p[0]) / a.length, a.fold(0.0, (s, p) => s + p[1]) / a.length];
Poly ngon(double cx, double cy, double r, int n) =>
    [for (var i = 0; i < n; i++) [cx + math.cos(i * 2 * math.pi / n) * r, cy + math.sin(i * 2 * math.pi / n) * r]];


class MapPainter extends CustomPainter {
  final MapView mv;
  final NavState s;
  final MapPal pal;
  final Words w;
  /// A still picture of the whole site (the mall picker's thumbnails): its own camera, no taps, no dot.
  final Cam? preview;
  /// Map labels follow the text size setting (and the phone's font size).
  final double textScale;
  /// Animations are off: no pulsing ring at the stairs, a still one instead.
  final bool reduceMotion;
  MapPainter(this.mv, this.s, this.pal, this.w, {this.preview, this.textScale = 1, this.reduceMotion = false});

  /// A thumbnail of a venue's whole site (no navigation state of its own).
  MapPainter.preview(Venue v, this.pal, this.w, Cam cam)
      : mv = MapView(v),
        s = NavState(v),
        preview = cam,
        textScale = 1,
        reduceMotion = true;

  // The level being drawn, kept across frames like the demo's global.
  static int curLv = 0;

  late Canvas cv;
  late double vw, vh;
  Cam get cam => preview ?? mv.cam;
  Venue get v => s.v;
  String get mode => preview != null ? 'site' : mv.mode;
  double get centreX => preview != null ? vw / 2 : mv.centreX;
  double get centreY => preview != null ? vh / 2 : mv.centreY;
  String tr(String en) => w.tr(en);
  Path? _cap; // collects the shapes of a tappable group

  // ===== Projection =====
  Offset P(double x, double y, [double z = 0, int? lv]) {
    final l = lv ?? curLv, ex = cam.ex, sp = v.stack;
    final u = x - lerp(cam.cx, sp.cx, ex), w = y - lerp(cam.cy, sp.cy, ex);
    final ru = u * cam.c - w * cam.s, rv = u * cam.s + w * cam.c;
    final ky = lerp(1, cam.kyB, cam.tilt), kz = cam.kzB * cam.tilt, lift = ex * (l - sp.mid) * sp.gapM;
    return Offset(centreX + ru * cam.S, centreY + rv * cam.S * ky - (z + lift) * cam.S * kz);
  }

  List<Offset> pts(Poly arr, [double z = 0]) => [for (final p in arr) P(p[0], p[1], z)];

  // Screen bounds were written for the 370 x 824 phone canvas; keep the same margins on any screen.
  double rx(double mock) => vw + (mock - mockW);
  double by(double mock) => vh + (mock - mockH);

  bool visible(Poly poly) {
    var x1 = 1e9, y1 = 1e9, x2 = -1e9, y2 = -1e9;
    for (final p in poly) {
      final q = P(p[0], p[1]);
      x1 = math.min(x1, q.dx); x2 = math.max(x2, q.dx); y1 = math.min(y1, q.dy); y2 = math.max(y2, q.dy);
    }
    return x2 > -60 && x1 < rx(430) && y2 > -80 && y1 < by(900);
  }

  // ===== Drawing primitives =====
  Color c(String token) => pal[token];

  // the evacuation route is drawn red
  String get routeTok => s.evac != null ? 'bad' : 'route';
  String get rimTok => s.evac != null ? 'closed' : 'route-rim';
  Color op(Color col, double o) => col.withValues(alpha: col.a * o);

  void fillPath(Path p, Color col) {
    cv.drawPath(p, Paint()..color = col);
    _cap?.addPath(p, Offset.zero);
  }

  void strokePath(Path p, Color col, double w, {List<double>? dash, StrokeCap cap = StrokeCap.butt}) {
    final paint = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.miter;
    cv.drawPath(dash == null ? p : dashPath(p, dashArray: CircularIntervalList<double>(dash)), paint);
  }

  Path polyPath(List<Offset> o) => Path()..addPolygon(o, true);

  void polygon(List<Offset> o, {Color? fill, Color? stroke, double sw = 1, List<double>? dash}) {
    final p = polyPath(o);
    if (fill != null) fillPath(p, fill);
    if (stroke != null) strokePath(p, stroke, sw, dash: dash);
  }

  void circle(Offset at, double r, {Color? fill, Color? stroke, double sw = 1}) {
    final p = Path()..addOval(Rect.fromCircle(center: at, radius: r));
    if (fill != null) fillPath(p, fill);
    if (stroke != null) strokePath(p, stroke, sw);
  }

  void line(Offset a, Offset b, Color col, double w, {List<double>? dash, double opacity = 1}) =>
      strokePath(Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy), op(col, opacity), w, dash: dash);

  /// stroke-dasharray "0 gap" with round caps: a dot every `gap` px along the polyline.
  void dots(List<Offset> o, Color col, double w, double gap) {
    final paint = Paint()..color = col;
    var carry = 0.0;
    for (var i = 1; i < o.length; i++) {
      final a = o[i - 1], b = o[i], len = (b - a).distance;
      var t = carry;
      while (t <= len) {
        cv.drawCircle(len == 0 ? a : a + (b - a) * (t / len), w / 2, paint);
        t += gap;
      }
      carry = t - len;
    }
    if (o.length == 1) cv.drawCircle(o[0], w / 2, paint);
  }

  /// Dashes along a polyline: the alternative route, told apart from the chosen one by
  /// shape as well as colour.
  void dashes(List<Offset> o, Color col, double w, double dash, double gap) {
    final paint = Paint()..color = col..strokeWidth = w..strokeCap = StrokeCap.round;
    var on = true;
    for (var i = 1; i < o.length; i++) {
      final a = o[i - 1], b = o[i], len = (b - a).distance;
      if (len == 0) continue;
      var t = 0.0;
      while (t < len) {
        final seg = on ? dash : gap, end = math.min(len, t + seg);
        if (on) cv.drawLine(a + (b - a) * (t / len), a + (b - a) * (end / len), paint);
        if (end < len) on = !on;
        t = end;
      }
    }
  }

  void group(double opacity, void Function() body) {
    if (opacity >= 0.999) {
      body();
      return;
    }
    cv.saveLayer(Offset.zero & Size(vw, vh), Paint()..color = pal.white.withValues(alpha: opacity));
    body();
    cv.restore();
  }

  void hitGroup(String kind, String id, void Function() body, {double opacity = 1}) {
    final outer = _cap;
    _cap = Path();
    group(opacity, body);
    if (preview == null) mv.hits.add(kind, id, _cap!);
    _cap = outer;
  }

  void glyph(String id, double x, double y, double size, Color col) => drawGlyph(cv, id, Rect.fromLTWH(x, y, size, size), col);

  // ===== Text (a halo stroke under the fill) =====
  static final Map<String, (TextPainter?, TextPainter)> _textCache = {};
  void text(String s, double x, double y, {double size = 11.5, FontWeight weight = FontWeight.w600, double ls = 0, Color? fill, bool halo = true, double haloW = 4, double opacity = 1}) {
    if (s.isEmpty) return;
    size *= textScale;
    final f = op(fill ?? c('label'), opacity), hc = op(c('halo'), opacity);
    final key = '$s|$size|${weight.value}|$ls|${f.toARGB32()}|${halo ? hc.toARGB32() : 0}|$haloW';
    final tp = _textCache.putIfAbsent(key, () {
      if (_textCache.length > 1500) _textCache.clear();
      TextPainter mk(TextStyle ts) => TextPainter(text: TextSpan(text: s, style: ts), textDirection: TextDirection.ltr)..layout();
      final base = TextStyle(fontFamily: brandFont, fontSize: size, fontWeight: weight, letterSpacing: ls, height: 1);
      return (
        halo
            ? mk(base.copyWith(foreground: Paint()..style = PaintingStyle.stroke..strokeWidth = haloW..strokeJoin = StrokeJoin.round..color = hc))
            : null,
        mk(base.copyWith(color: f)),
      );
    });
    final fillTp = tp.$2;
    final base = fillTp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    // SVG letter-spacing adds after each glyph; centre on the glyphs, not the trailing space
    final o = Offset(x - (fillTp.width - ls) / 2, y - base);
    tp.$1?.paint(cv, o);
    fillTp.paint(cv, o);
  }

  // ===== Shapes =====
  void prism(Poly poly, double z0, double z1, String top, String sideA, String sideB, [Color? topStroke]) {
    final a0 = area(poly);
    if (cam.tilt > 0.02 && z1 > z0) {
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        var nx = b[1] - a[1], ny = -(b[0] - a[0]);
        if (a0 < 0) { nx = -nx; ny = -ny; }
        final nrv = nx * cam.s + ny * cam.c, nru = nx * cam.c - ny * cam.s;
        if (nrv <= 0.001) continue;
        polygon([P(a[0], a[1], z0), P(b[0], b[1], z0), P(b[0], b[1], z1), P(a[0], a[1], z1)], fill: c(nru < 0 ? sideA : sideB));
      }
    }
    polygon(pts(poly, z1), fill: c(top), stroke: topStroke, sw: .8);
  }

  void flat(Poly poly, String fill, [double z = 0.02, String? stroke]) =>
      polygon(pts(poly, z), fill: c(fill), stroke: stroke == null ? null : c(stroke), sw: 1);

  Poly wallRect(double x1, double y1, double x2, double y2, double t) {
    final dx = x2 - x1, dy = y2 - y1, l = hypot(dx, dy), ux = dx / l, uy = dy / l, nx = -uy * t / 2, ny = ux * t / 2, ex = ux * t / 2, ey = uy * t / 2;
    return [[x1 - ex + nx, y1 - ey + ny], [x2 + ex + nx, y2 + ey + ny], [x2 + ex - nx, y2 + ey - ny], [x1 - ex - nx, y1 - ey - ny]];
  }

  bool isFrontWall(List<double> w, List<double> cc) {
    final mx = (w[0] + w[2]) / 2 - cc[0], my = (w[1] + w[3]) / 2 - cc[1];
    return mx * cam.s + my * cam.c > 0;
  }

  // ===== Route layers =====
  void routeSvgFor(RouteT? r, bool selected, int lvOnly) {
    if (r == null) return;
    final pieces = remainingPieces(r).pieces, site = mode == 'site', small = mode != 'building';
    for (final pc in pieces) {
      if (!site && pc.lv != lvOnly) continue;
      final z = site ? v.zOf(pc.lv) + routeZ : routeZ, dim = site && pc.lv > v.ground;
      final p = [for (final q in pc.pts) P(q[0], q[1], z)];
      final w1 = (small ? 5.0 : 9.0) + (pal.hc ? 2 : 0), w2 = small ? 3.0 : 6.0, gap = small ? 7.0 : 12.0;
      if (selected) {
        group(dim ? .6 : 1, () {
          dots(p, c(rimTok), w1, gap);
          dots(p, c(routeTok), w2, gap);
        });
      } else {
        dashes(p, op(c('route-alt'), dim ? .5 : 1), site ? 3 : 4.5, gap * .9, gap * .6);
      }
    }
  }

  /// The way you walk into (from-floor) or out of (to-floor) the lift, escalator or stairs at [h].
  double? _rideHeading(RouteT r, HopLeft h, bool here) {
    final verts = r.verts;
    for (var i = 0; i < verts.length; i++) {
      final a = verts[i];
      if ((a.x - h.x).abs() > .01 || (a.y - h.y).abs() > .01 || a.lv != (here ? h.from : h.to)) continue;
      if (here) {
        for (var k = i; k >= 1; k--) {
          if (isHop(r.seg[k])) continue;
          final p = verts[k - 1], q = verts[k];
          if (hypot(q.x - p.x, q.y - p.y) > .01) return math.atan2(q.y - p.y, q.x - p.x);
        }
      } else {
        for (var k = i + 1; k < verts.length; k++) {
          if (isHop(r.seg[k])) continue;
          final p = verts[k - 1], q = verts[k];
          if (hypot(q.x - p.x, q.y - p.y) > .01) return math.atan2(q.y - p.y, q.x - p.x);
        }
      }
    }
    return null;
  }

  /// Stairs and escalators on the route, drawn as what they are: a 6 × 3 m footprint with treads
  /// and a chevron the way you go, on the floor you leave and the floor you reach.
  void rideFootprint(RouteT r, HopLeft h, bool here) {
    final hd = _rideHeading(r, h, here) ?? 0, cs = math.cos(hd), sn = math.sin(hd);
    Offset w(double along, double across) => P(h.x + along * cs - across * sn, h.y + along * sn + across * cs, routeZ + 1);
    final fill = op(c('route'), pal.hc ? .4 : .25), rim = c('route-rim'), sw = pal.hc ? 2.0 : 1.2;
    // 8 x 4 m: a little larger than life, so it reads at the zoom the route is followed at
    final box = Path()
      ..moveTo(w(-4, -2).dx, w(-4, -2).dy)
      ..lineTo(w(4, -2).dx, w(4, -2).dy)
      ..lineTo(w(4, 2).dx, w(4, 2).dy)
      ..lineTo(w(-4, 2).dx, w(-4, 2).dy)
      ..close();
    cv.drawPath(box, Paint()..color = fill);
    cv.drawPath(box, Paint()..color = rim..style = PaintingStyle.stroke..strokeWidth = sw);
    for (var k = -2; k <= 2; k++) {
      line(w(k * 1.4, -2), w(k * 1.4, 2), rim, sw * .8, opacity: .8);
    }
    // the chevron: the way you travel through it
    final tip = w(3.5, 0), l = w(2.4, -1.1), rr = w(2.4, 1.1);
    cv.drawPath(Path()..moveTo(l.dx, l.dy)..lineTo(tip.dx, tip.dy)..lineTo(rr.dx, rr.dy), Paint()..color = rim..style = PaintingStyle.stroke..strokeWidth = sw * 1.3..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }

  void hopBadges(RouteT? r, int lv) {
    if (r == null || mode == 'site') return;
    final asking = s.checking && s.checkRide != null && s.checkRide! < s.directions.length ? s.directions[s.checkRide!].id : null;
    for (final h in remainingPieces(r).hopsLeft) {
      if (h.from != lv && h.to != lv) continue;
      final q = P(h.x, h.y, routeZ + 3), x = q.dx, y = q.dy, here = h.from == lv, up = h.to > h.from;
      if (h.type != 'lift') rideFootprint(r, h, here);
      // waiting at its foot for "Are you at ...?": a ring that pulses (a still one when animations are off)
      if (here && asking == h.id) {
        if (reduceMotion) {
          circle(q, 16, stroke: c('route'), sw: 3);
        } else {
          final t = s.pulse;
          circle(q, 12 + 10 * t, stroke: op(c('route'), (1 - t) * .8), sw: 3);
        }
      }
      final lab = here ? '${up ? '↑ ' : '↓ '}${tr(v.levels[h.to].name)}' : tr('From ${v.levels[h.from].name.toLowerCase()}');
      final wdt = lab.length * 6.3 + 34;
      line(Offset(x, y), Offset(x, y - 14), c('route-rim'), 2);
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x - wdt / 2, y - 38, wdt, 24), const Radius.circular(12));
      cv.drawRRect(rr, Paint()..color = c('surface'));
      cv.drawRRect(rr, Paint()..color = c('route')..style = PaintingStyle.stroke..strokeWidth = 2.5);
      glyph('g-${h.type}', x - wdt / 2 + 6, y - 35, 18, c('route-text'));
      text(lab, x + 9, y - 22, halo: false);
    }
  }

  static final Path _pinShape = parseSvgPathData('M0 -8 c-3 -8 -15 -11 -15 -25 a15 15 0 0 1 30 0 c0 14 -12 17 -15 25z');

  void destinationPin(RouteT r, int lv) {
    final e = r.verts.last;
    if (s.arrived) return;
    if (mode != 'site' && e.lv != lv) return;
    final q = P(e.x, e.y, mode == 'site' ? v.zOf(e.lv) + routeZ : routeZ), sc = mode == 'site' ? .7 : 1.0;
    cv.save();
    cv.translate(q.dx, q.dy);
    cv.scale(sc);
    circle(Offset.zero, 7, fill: pal.white, stroke: c(routeTok), sw: 4);
    cv.drawPath(_pinShape, Paint()..color = c(routeTok));
    cv.drawPath(_pinShape, Paint()..color = c(rimTok)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    circle(const Offset(0, -33), 5.5, fill: pal.white);
    cv.restore();
  }

  void userSvg(int lv) {
    final u = s.user, site = mode == 'site';
    if (u == null || preview != null) return; // no dot until the shopper says where they are
    if (!site && u.lv != lv) return;
    final q = P(u.x, u.y, site ? v.zOf(u.lv) + routeZ : routeZ), ux = q.dx, uy = q.dy, px = cam.S;
    if (!site && s.heading != null && !s.arrived && s.transit == null) {
      final a = s.heading!;
      final cone = <List<double>>[[u.x, u.y]];
      for (var i = 0; i <= 8; i++) {
        final t = a - coneSpread + i * 2 * coneSpread / 8;
        cone.add([u.x + math.cos(t) * coneRadiusM, u.y + math.sin(t) * coneRadiusM]);
      }
      final k = c('cone');
      cv.drawPath(
        polyPath(pts(cone, routeZ)),
        Paint()..shader = ui.Gradient.radial(q, math.max(0.001, coneRadiusM * px), [k.withValues(alpha: .55), k.withValues(alpha: 0)]),
      );
    }
    if (s.approximate) { // "somewhere on this floor"
      final ar = math.max(14.0, 25 * px);
      circle(q, ar, fill: op(c('accent'), .12));
      strokePath(Path()..addOval(Rect.fromCircle(center: q, radius: ar)), op(c('accent'), .7), 1.5, dash: const [5, 4]);
    }
    final rr = site ? 6.0 : 9.0;
    cv.drawOval(Rect.fromCenter(center: Offset(ux, uy + 3), width: (rr + 4) * 2, height: (rr / 2 + 1) * 2), Paint()..color = pal.dotShadow);
    circle(q, rr * 1.8, fill: op(c('accent'), .2));
    circle(q, rr, fill: c('accent'), stroke: pal.white, sw: 3);
    if (s.transit != null && !site) {
      cv.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(ux - 56, uy - 44, 112, 22), const Radius.circular(11)), Paint()..color = c('accent'));
      final hn = hopName[s.transit!.ctype]!;
      text(tr('On the ${hn[0]}'), ux, uy - 29, size: 11, fill: c('on-accent'), halo: false);
    }
  }

  // ===== Pins and labels =====
  void pinsSvg(int lv) {
    final boxes = <List<double>>[], z = cam.zoom;
    final lod = z < lodPinsZoom ? 0 : z < lodNamesZoom ? 1 : 2;
    final dest = s.place == null ? null : s.placeById(s.place!);
    final nearIds = (s.near?.ids ?? const <String>[]).toSet();
    final list = v.places.where((p) => p.lv == lv);
    bool hit(List<double> b) => boxes.any((q) => b[0] < q[2] && b[2] > q[0] && b[1] < q[3] && b[3] > q[1]);
    final cand = <_Cand>[];
    for (final p in list) {
      final isDest = dest?.id == p.id, isNear = nearIds.contains(p.id), isBox = p.kind == 'box', svc = p.kind == 'svc' || p.kind == 'zone';
      if (!isDest && !isNear) {
        if (lod == 0 && !isBox && p.cat != 'exit' && p.kind != 'zone') continue;
        if (svc && p.cat != 'exit' && lod < 1 && p.kind != 'zone') continue;
      }
      final q = P(p.at[0], p.at[1], p.kind == 'store' ? slabH : isBox ? boxH : 0.4);
      if (q.dx < -30 || q.dx > rx(400) || q.dy < -30 || q.dy > by(900)) continue;
      cand.add(_Cand(p, q.dx, q.dy, isDest ? 0 : isNear ? 1 : isBox ? 2 : p.kind == 'store' ? 4 : 3));
    }
    final sorted = stableSorted(cand, (a, b) => a.pr - b.pr);
    final rBase = lod == 0 ? 9.0 : lod == 1 ? 10.0 : 12.0;
    // reserve pin circles in priority order; a low-priority pin that would sit on another is dropped
    final shown = <_Cand>[];
    for (final cd in sorted) {
      final r = cd.p.kind == 'svc' || cd.p.kind == 'zone' ? rBase * .8 : cd.p.kind == 'box' ? rBase * 1.25 : rBase;
      cd.r = r;
      cd.top = cd.y - r - 8;
      final b = [cd.x - r, cd.top - r, cd.x + r, cd.y];
      if (cd.pr > 2 && hit(b)) continue;
      boxes.add(b);
      shown.add(cd);
    }
    for (final cd in shown) {
      final p = cd.p, dim = p.status != 'open', col = c('poi');
      String? label;
      final wantName = lod >= 2 || p.kind == 'box' && lod >= 1 || cd.pr <= 1 || (p.kind == 'zone' && lod >= 1) || (p.cat == 'exit');
      if (wantName) {
        final w = p.name.length * 6.1 + 8, lb = [cd.x - w / 2, cd.y + 3, cd.x + w / 2, cd.y + 16];
        if (cd.pr <= 1 || !hit(lb)) {
          boxes.add(lb);
          label = p.name;
        }
      }
      hitGroup('poi', p.id, opacity: dim ? .5 : 1, () {
        final outer = _cap;
        _cap = null; // the stem is too thin to tap
        line(Offset(cd.x, cd.y), Offset(cd.x, cd.top + cd.r), col, 2);
        _cap = outer;
        circle(Offset(cd.x, cd.y), 2.5, fill: col);
        circle(Offset(cd.x, cd.top), cd.r, fill: col, stroke: pal.white, sw: 2);
        glyph(glyphOf(p.cat), cd.x - cd.r * .62, cd.top - cd.r * .62, cd.r * 1.24, pal.white);
        if (label != null) text(label, cd.x, cd.y + 14);
      });
    }
    // connector pins appear once the plan is readable
    if (lod >= 1 && v.connectorPinsOn(lv)) {
      final out = v is PackageVenue ? (v as PackageVenue).outOfService : const <String>{};
      for (final cn in v.connectors) {
        final k = cn.at[lv];
        if (k == null) continue;
        final n = v.graph.nodes[k]!, q = P(n.x, n.y, 1.2);
        if (q.dx < -20 || q.dx > rx(390) || q.dy < -20 || q.dy > by(860)) continue;
        // out of service: in the warning colour, crossed out
        final off = out.contains(cn.id);
        circle(q, 7.5, fill: off ? c('bad') : c('conn'), stroke: c('surface'), sw: 1.8);
        glyph('g-${cn.type}', q.dx - 5, q.dy - 5, 10, c('surface'));
        if (off) line(Offset(q.dx - 6, q.dy + 6), Offset(q.dx + 6, q.dy - 6), c('surface'), 2);
      }
    }
    // wing names on the corridors
    if (lod <= 1) {
      for (final (t, x, y) in v.wingLabels(lv)) {
        final q = P(x, y, .2);
        if (q.dx > 0 && q.dx < vw && q.dy > 0 && q.dy < vh) text(tr(t), q.dx, q.dy, size: 10, ls: 2, opacity: .75);
      }
    }
  }

  // ===== The stacked view: every level, lifted apart =====
  void stackLabel(int lv) {
    curLv = lv;
    final la = v.stack.labelAt, q = P(la[0], la[1], 0.5), on = lv == mv.level;
    hitGroup('level', '$lv', () => circle(q, 12, fill: on ? c('accent') : c('surface'), stroke: c('outline'), sw: 1.5));
    text(v.levels[lv].short, q.dx, q.dy + 4.2, size: v.levels[lv].short.length > 2 ? 10 : 12, weight: FontWeight.w700, fill: on ? c('on-accent') : c('text'), halo: false);
  }

  void stackColumns(int lv) { // the lifts, stairs and escalators that join this level to the next stop
    for (final cn in v.connectors) {
      final i = cn.lvs.indexOf(lv);
      if (i < 0 || i + 1 >= cn.lvs.length) continue;
      final up = cn.lvs[i + 1], a = v.graph.nodes[cn.at[lv]]!, b = v.graph.nodes[cn.at[up]]!;
      line(P(a.x, a.y, 0, lv), P(b.x, b.y, 0, up), c('conn'), 1.5, dash: const [3, 4], opacity: .4);
    }
  }

  void stackRouteHops(RouteT r, int lv) { // the route climbing from this level to the next
    for (var i = 1; i < r.verts.length; i++) {
      if (!isHop(r.seg[i]) || r.cum[i] <= r.progress) continue;
      final a = r.verts[i - 1], b = r.verts[i];
      if (math.min(a.lv, b.lv) != lv) continue;
      final p0 = P(a.x, a.y, routeZ, a.lv), p1 = P(b.x, b.y, routeZ, b.lv);
      dots([p0, p1], c(rimTok), 6, 8);
      dots([p0, p1], c(routeTok), 3.5, 8);
    }
  }

  void renderStack(RouteT? r, List<RouteT> alts) {
    final rd = rendererFor(v), n = v.levelCount;
    for (var lv = 0; lv < n; lv++) {
      final dim = lerp(1, lv == mv.level ? 1 : .5, math.min(1, cam.ex * 1.5));
      hitGroup('level', '$lv', () => rd.stackPlate(this, lv), opacity: dim);
      curLv = lv;
      for (final alt in alts) {
        routeSvgFor(alt, false, lv);
      }
      routeSvgFor(r, true, lv);
      stackLabel(lv);
      if (lv < n - 1) {
        stackColumns(lv);
        if (r != null) stackRouteHops(r, lv);
      }
      curLv = lv;
      if (r != null) destinationPin(r, lv);
      userSvg(lv);
    }
  }

  // ===== Whole map =====
  @override
  void paint(Canvas canvas, Size size) {
    cv = canvas;
    vw = size.width;
    vh = size.height;
    canvas.clipRect(Offset.zero & size);
    final rd = rendererFor(v);
    if (preview != null) {
      preview!.prep(v);
      rd.siteBase(this);
      return;
    }
    mv.hits.clear();
    mv.prep();
    final r = s.route, gl = v.ground;
    // the other ways, while they are still worth showing
    final alts = s.routes.length > 1 && r!.progress < altVisibleUntilM ? [for (var i = 0; i < s.routes.length; i++) if (i != s.routeIdx) s.routes[i]] : const <RouteT>[];
    if (mode == 'stack') {
      renderStack(r, alts);
    } else if (mode == 'site') {
      rd.siteBase(this);
      for (final alt in alts) {
        routeSvgFor(alt, false, gl);
      }
      routeSvgFor(r, true, gl);
      rd.siteLabels(this);
      if (r != null) destinationPin(r, gl);
      userSvg(gl);
    } else {
      final lv = mv.level;
      rd.levelBase(this, lv);
      for (final alt in alts) {
        routeSvgFor(alt, false, lv);
      }
      routeSvgFor(r, true, lv);
      pinsSvg(lv);
      hopBadges(r, lv);
      if (r != null) destinationPin(r, lv);
      userSvg(lv);
    }
  }

  @override
  bool shouldRepaint(MapPainter old) => true;
}

class _Cand {
  final Place p;
  final double x, y;
  final int pr;
  double r = 0, top = 0;
  _Cand(this.p, this.x, this.y, this.pr);
}

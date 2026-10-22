// Builds a venue from a KSpec: shop rows along corridors, anchors, services,
// parking zones and connectors, then the walkway graph (graph.dart).
import 'dart:math' as math;

import '../util.dart';
import '../graph.dart';
import '../routing.dart';
import '../venue.dart';
import 'kit_spec.dart';

/// A shop or restroom bay generated along a line, remembered for drawing.
class KSlot {
  final String bld, kind; // store | wc
  final int lv;
  final List<double> rect;
  const KSlot(this.bld, this.kind, this.lv, this.rect);
}

bool _overlap(List<double> a, List<double> b, [double eps = .3]) =>
    a[0] < b[2] - eps && a[2] > b[0] + eps && a[1] < b[3] - eps && a[3] > b[1] + eps;

bool _inside(List<double> a, List<double> b) => a[0] >= b[0] - .5 && a[1] >= b[1] - .5 && a[2] <= b[2] + .5 && a[3] <= b[3] + .5;

List<double> lineRect(double x1, double y1, double x2, double y2, double w) => y1 == y2
    ? [math.min(x1, x2), y1 - w / 2, math.max(x1, x2), y1 + w / 2]
    : [x1 - w / 2, math.min(y1, y2), x1 + w / 2, math.max(y1, y2)];

/// The cost of one hop, in metre-equivalents, by the height climbed: about the
/// mock-up's per-type costs for a 6 m storey, but stairs get tiring fast while lifts
/// and escalators barely notice height (so express escalators win long climbs).
double hopCostFor(String type, double dz) => switch (type) {
      'lift' => 30 + 1.5 * dz,
      'stairs' => 34 + 3 * dz,
      'escalator' => 14 + dz,
      _ => 20 + 2 * dz, // ramp
    };

class KitVenue extends Venue {
  final KSpec spec;
  final kslots = <KSlot>[];
  final _placeBld = <Place, String>{};

  KitVenue(this.spec) : super(spec.seed) {
    // what can be named outdoors: the site's labels and its buildings
    siteLabels.addAll([
      for (final l in spec.labels) if (!l.big) SiteLabel(l.text, l.x, l.y),
      for (final b in spec.buildings) if (b.tappable) SiteLabel(b.name, (b.rect[0] + b.rect[2]) / 2, (b.rect[1] + b.rect[3]) / 2),
    ]);
    _build();
    indexPlaces();
  }

  @override
  String get id => spec.id;
  @override
  String get name => spec.name;
  @override
  String get tagline => spec.tagline;
  @override
  String get keywords => spec.keywords;
  @override
  List<LevelDef> get levels => spec.levels;
  @override
  int get ground => spec.ground;
  @override
  late final Map<String, String> wingNames = {for (final b in spec.buildings) b.id: b.name, 'O': 'Outdoors'};

  KBld bld(String id) => spec.buildings.firstWhere((b) => b.id == id);

  String _wingAt(double x, double y) {
    for (final b in spec.buildings) {
      if (x >= b.rect[0] - .5 && x <= b.rect[2] + .5 && y >= b.rect[1] - .5 && y <= b.rect[3] + .5) return b.id;
    }
    return 'O';
  }

  void _build() {
    final s = spec;
    graph = Graph(levelCount);
    final gr = graph;

    // 1. lines
    for (final l in s.lines) {
      for (final lv in l.lvs) {
        gr.line(lv, [l.x1, l.y1], [l.x2, l.y2], l.w, out: l.out, zone: l.zone, bld: l.bld, covered: l.covered);
      }
    }
    // 2. junctions: every end that touches another line, and every crossing
    for (var lv = 0; lv < levelCount; lv++) {
      final ls = gr.lines[lv];
      for (final l in List.of(ls)) {
        gr.put(lv, l.a[0], l.a[1]);
        gr.put(lv, l.b[0], l.b[1]);
      }
      for (final h in ls.where((l) => l.horiz)) {
        for (final v in ls.where((l) => !l.horiz)) {
          final x = v.a[0], y = h.a[1];
          if (x >= math.min(h.a[0], h.b[0]) && x <= math.max(h.a[0], h.b[0]) && y >= math.min(v.a[1], v.b[1]) && y <= math.max(v.a[1], v.b[1])) {
            gr.put(lv, x, y);
          }
        }
      }
    }

    // 3. shop rows (the seeded random numbers are consumed here, in spec order)
    final reserved = <String, List<List<double>>>{};
    List<List<double>> res(String b, int lv) => reserved.putIfAbsent('$b|$lv', () {
          final r = <List<double>>[];
          for (final a in s.areas) {
            if (a.bld == b && a.lvs.contains(lv)) r.add(a.rect);
          }
          for (final a in s.anchors) {
            if (a.bld == b && a.names.containsKey(lv)) r.add(a.rect);
          }
          for (final c in s.conns) {
            if (c.lvs.contains(lv) && c.blds.contains(b)) {
              final h = c.type == 'escalator' ? 3.0 : 6.0;
              r.add([c.x - 6, c.y - h, c.x + 6, c.y + h]);
            }
          }
          for (final l in s.lines) {
            if (l.lvs.contains(lv)) r.add(lineRect(l.x1, l.y1, l.x2, l.y2, l.w));
          }
          for (final k in s.links) {
            if (k.lv == lv) r.add(lineRect(k.x1, k.y1, k.x2, k.y2, k.w));
          }
          for (final e in s.exits) {
            if (e.lv == lv) r.add([e.ix - 6, e.iy - 6, e.ix + 6, e.iy + 6]);
          }
          return r;
        });
    final counts = <String, int>{};
    for (var lv = 0; lv < levelCount; lv++) {
      for (final l in s.lines) {
        if (!l.lvs.contains(lv) || l.bld == null || (l.rowA == 0 && l.rowB == 0)) continue;
        final b = bld(l.bld!), w = s.weights(b.id, lv), horiz = l.y1 == l.y2;
        final from = horiz ? math.min(l.x1, l.x2) : math.min(l.y1, l.y2), to = horiz ? math.max(l.x1, l.x2) : math.max(l.y1, l.y2);
        for (final side in const [0, 1]) {
          final depth = side == 0 ? l.rowA : l.rowB;
          if (depth == 0) continue;
          for (var t = from; t + l.slot <= to + .01; t += l.slot) {
            final edge = side == 0 ? (horiz ? l.y1 : l.x1) - l.w / 2 : (horiz ? l.y1 : l.x1) + l.w / 2;
            final far = side == 0 ? edge - depth : edge + depth;
            final rect = horiz
                ? [t, math.min(edge, far), t + l.slot, math.max(edge, far)]
                : [math.min(edge, far), t, math.max(edge, far), t + l.slot];
            if (!_inside(rect, b.rect)) continue;
            if (res(b.id, lv).any((r) => _overlap(rect, r))) continue;
            if (kslots.any((k) => k.lv == lv && k.bld == b.id && _overlap(rect, k.rect))) continue;
            final door = horiz ? [t + l.slot / 2, edge] : [edge, t + l.slot / 2];
            final key = '${b.id}|$lv', n = (counts[key] ?? 0) + 1;
            counts[key] = n;
            final short = levels[lv].short;
            if (n % s.wcEvery == s.wcEvery ~/ 2) {
              final p = Place(id: '$short-WC-${b.id}$n', lv: lv, name: 'Restrooms', cat: 'restroom', wing: b.id, rect: rect, door: door, kind: 'svc');
              places.add(p);
              _placeBld[p] = b.id;
              kslots.add(KSlot(b.id, 'wc', lv, rect));
            } else {
              final cat = weightedCat(w), r = rand();
              final status = r < .03 ? 'closed' : r < .05 ? 'maintenance' : r < .065 ? 'comingSoon' : 'open';
              final name = storeName(cat);
              final pw = rand() < .025 ? 0.9 : 1.6;
              final p = Place(id: '$short-${b.id}$n', lv: lv, name: name, cat: cat, wing: b.id, rect: rect, door: door, status: status, w: pw, kind: 'store');
              places.add(p);
              _placeBld[p] = b.id;
              kslots.add(KSlot(b.id, 'store', lv, rect));
            }
          }
        }
      }
    }
    // 4. anchors, services, exits
    for (final a in s.anchors) {
      for (final e in a.names.entries) {
        final p = Place(id: '${levels[e.key].short}-${a.id}', lv: e.key, name: e.value[0], cat: e.value[1], wing: a.bld, rect: a.rect,
            door: [(a.rect[0] + a.rect[2]) / 2, (a.rect[1] + a.rect[3]) / 2], kind: 'box', doors: a.doors);
        places.add(p);
        _placeBld[p] = a.bld;
      }
    }
    for (final v in s.services) {
      final p = Place(id: v.id, lv: v.lv, name: v.name, cat: v.cat, wing: v.bld, rect: [v.x - 2, v.y - 2, v.x + 2, v.y + 2], at: [v.x, v.y], door: [v.x, v.y], kind: 'svc', onLine: true);
      places.add(p);
      _placeBld[p] = v.bld;
    }
    for (final e in s.exits) {
      places.add(Place(id: e.id, lv: e.lv, name: e.name, cat: 'exit', wing: _wingAt(e.ix, e.iy), rect: [e.ix - 3, e.iy - 3, e.ix + 3, e.iy + 3], at: [e.ix, e.iy], door: [e.ix, e.iy], kind: 'svc', exitNode: true));
    }
    // 5. parking zones
    zones = [for (final z in s.zones) Zone(id: z.id, name: z.name, lv: z.lv, pt: [z.x, z.y], wing: _wingAt(z.x, z.y), rect: z.rect, attach: z.zoneTag)];
    for (final z in zones) {
      avail[z.id] = jsRound(5 + rand() * 85);
    }
    for (final z in zones) {
      places.add(Place(id: z.id, lv: z.lv, name: z.name, cat: 'parking', wing: z.wing, rect: [z.pt[0] - 3, z.pt[1] - 3, z.pt[0] + 3, z.pt[1] + 3], at: z.pt, door: z.pt, kind: 'zone', avail: avail[z.id], zone: z));
    }
    // 6. connectors
    connectors = [
      for (final c in s.conns)
        Connector(id: c.id, type: c.type, name: c.name, lvs: c.lvs, pt: [c.x, c.y], bld: c.blds.first,
            cost: (a, b) => hopCostFor(c.type, (levels[b].elev - levels[a].elev).abs())),
    ];

    // ----- the graph -----
    bool Function(Line) only(bool Function(Line) f, int lv) => gr.lines[lv].any(f) ? f : (l) => !l.out;
    // exits: inside and outside points on lines, joined by a door
    for (final e in s.exits) {
      gr.put(e.lv, e.ix, e.iy);
      gr.put(e.lv, e.ox, e.oy);
      final a = gr.node(e.lv, e.ix, e.iy, label: e.label), b = gr.node(e.lv, e.ox, e.oy, out: true, label: e.label);
      gr.link(a, b, 12, EdgeMeta('enter', label: e.label));
    }
    // bridges and links
    for (final k in s.links) {
      gr.put(k.lv, k.x1, k.y1);
      gr.put(k.lv, k.x2, k.y2);
      final a = gr.node(k.lv, k.x1, k.y1), b = gr.node(k.lv, k.x2, k.y2);
      gr.link(a, b, k.w, EdgeMeta('bridge', label: k.label, tech: k.tech));
    }
    for (final p in places) {
      if (p.kind == 'zone') {
        final tag = p.zone!.attach;
        p.nodes = [gr.doorNode(p.lv, p.door[0], p.door[1], 1.6, only((l) => l.zone == tag, p.lv))];
      } else if (p.exitNode) {
        p.nodes = [gr.node(p.lv, p.door[0], p.door[1])];
      } else if (p.kind == 'box') {
        final b = _placeBld[p]!, f = only((l) => l.bld == b && l.zone == null, p.lv);
        p.nodes = [for (final d in p.doors) gr.doorNode(p.lv, d[0], d[1], 6, f)];
        // several doors: a cut-through, in by one door, across the floor, out by another
        if (p.nodes.length > 1 && p.status == 'open') gr.throughBox(p, p.nodes);
      } else if (p.onLine) {
        final b = _placeBld[p]!, pr = gr.attach(p.lv, p.door[0], p.door[1], only((l) => l.bld == b, p.lv));
        p.nodes = [gr.node(p.lv, pr.p[0], pr.p[1])];
      } else {
        final b = _placeBld[p]!;
        p.nodes = [gr.doorNode(p.lv, p.door[0], p.door[1], p.w, only((l) => l.bld == b && l.zone == null, p.lv))];
        if (p.w < 1.6) { // the narrow door applies to the door spur itself
          final dk = p.nodes[0];
          for (final e in gr.adj[dk]!) {
            e.w = p.w;
            for (final back in gr.adj[e.to]!) {
              if (back.to == dk) back.w = p.w;
            }
          }
        }
      }
    }
    for (final c in connectors) {
      final kc = s.conns.firstWhere((k) => k.id == c.id);
      for (final lv in c.lvs) {
        c.at[lv] = gr.doorNode(lv, kc.x, kc.y, 2, only((l) => kc.blds.contains(l.bld ?? ''), lv));
      }
    }
    gr.materialise();
    gr.linkHops(connectors);
    gr.fixUnjoined(places);
  }

  // ===== What the app needs to know =====
  @override
  double get basePx => spec.basePx;
  @override
  View get siteView => spec.siteView;
  @override
  List<double> get siteRect => spec.site;
  @override
  Map<String, View> get buildingViews => spec.buildingViews;
  @override
  List<PadBtn> get pad => spec.pad;
  @override
  StackParams get stack => spec.stack;
  @override
  String get tripTarget => spec.tripTarget;
  @override
  late final List<ExitDef> exits = [for (final e in spec.exits) ExitDef(e.id, e.name, nk(e.lv, e.ox, e.oy))];
  @override
  List<(String, double, double)> wingLabels(int lv) => [for (final w in spec.wingLabels) if (w.$4.contains(lv)) (w.$1, w.$2, w.$3)];
  @override
  Pos levelCentre(int lv) {
    final c = spec.centres[lv] ?? [(spec.site[0] + spec.site[2]) / 2, (spec.site[1] + spec.site[3]) / 2];
    return Pos(lv, c[0], c[1], false);
  }

  @override
  int get buildingCount => spec.buildings.where((b) => b.tappable).length;
  @override
  String get sizeText => spec.sizeText;
}

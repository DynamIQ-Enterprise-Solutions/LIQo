// A declarative description of a venue: the offline malls (features/malls/data).
// Everything is in metres on the site plan (x to the east, y to the south) and
// walkable lines are axis-aligned, like the demo's corridors.
import '../venue.dart';

/// A building: its footprint, the levels it has, and how it looks.
class KBld {
  final String id, name; // id doubles as the wing code of its places
  final List<double> rect;
  final List<int> lvs;
  final String kind; // mall | openair | parking | arena | station | tower
  final String roof; // flat | skylight | dome | garden | canopy | none
  final bool tappable;
  const KBld(this.id, this.name, this.rect, this.lvs, {this.kind = 'mall', this.roof = 'flat', this.tappable = true});
}

/// A walkable line (corridor, aisle, path) on some levels, optionally lined with shops.
/// Side A is north of a horizontal line / west of a vertical one; side B the other side.
class KLine {
  final String? bld;
  final List<int> lvs;
  final double x1, y1, x2, y2, w;
  final bool out, covered;
  final String? zone; // parking aisles
  final double rowA, rowB, slot; // shop depth on each side (0 = none) and shop width
  const KLine(this.bld, this.lvs, this.x1, this.y1, this.x2, this.y2,
      {this.w = 12, this.out = false, this.covered = false, this.zone, this.rowA = 0, this.rowB = 0, this.slot = 10});
}

/// An area drawn on a level and kept free of shops.
class KArea {
  final String bld, kind; // court | void | boh | bowl | garden | portal | plaza
  final List<int> lvs;
  final List<double> rect;
  const KArea(this.bld, this.lvs, this.kind, this.rect);
}

/// A big store spanning several bays, with its own name on each level.
class KAnchor {
  final String id, bld;
  final List<double> rect;
  final Map<int, List<String>> names; // level -> [name, category]
  final List<List<double>> doors;
  const KAnchor(this.id, this.bld, this.rect, this.names, this.doors);
}

/// A lift, stairs, escalator or ramp. [blds] are the buildings whose lines it joins.
class KConn {
  final String id, type, name;
  final List<String> blds; // '' = outdoor lines that belong to no building
  final List<int> lvs;
  final double x, y;
  const KConn(this.id, this.type, this.name, this.blds, this.lvs, this.x, this.y);
}

/// A bridge or link: an explicit edge between two points on lines of one level.
class KLink {
  final int lv;
  final double x1, y1, x2, y2, w;
  final String label, tech;
  const KLink(this.lv, this.x1, this.y1, this.x2, this.y2, this.label, this.tech, {this.w = 6});
}

/// A door to the outside: inside and outside points both lie on lines.
class KExit {
  final String id, name, label;
  final int lv;
  final double ix, iy, ox, oy;
  const KExit(this.id, this.name, this.label, this.lv, this.ix, this.iy, this.ox, this.oy);
}

class KZone {
  final String id, name, zoneTag;
  final int lv;
  final double x, y;
  final List<double> rect;
  const KZone(this.id, this.name, this.lv, this.x, this.y, this.rect, this.zoneTag);
}

/// A service point on a line: ATM, information desk, EV charging.
class KSvc {
  final String id, cat, name, bld;
  final int lv;
  final double x, y;
  const KSvc(this.id, this.cat, this.name, this.bld, this.lv, this.x, this.y);
}

class KGround {
  final String token; // grass | water | road | walk | lot | plazaG | sand
  final List<double> rect;
  const KGround(this.token, this.rect);
}

class KLabel {
  final String text;
  final double x, y, z;
  final bool big;
  const KLabel(this.text, this.x, this.y, this.z, {this.big = false});
}

class KPoi {
  final String id, glyph, simple, tech;
  final double x, y;
  const KPoi(this.id, this.glyph, this.simple, this.tech, this.x, this.y);
}

class KSpec {
  final String id, name, tagline, sizeText, keywords;
  final int seed;
  final List<LevelDef> levels;
  final int ground;
  final double basePx;
  final List<double> site;
  final List<KBld> buildings;
  final List<KLine> lines;
  final List<KArea> areas;
  final List<KAnchor> anchors;
  final List<KConn> conns;
  final List<KLink> links;
  final List<KExit> exits;
  final List<KZone> zones;
  final List<KSvc> services;
  final List<KGround> groundFx;
  final List<(List<double>, int)> trees; // rect, count
  final List<KLabel> labels;
  final List<KPoi> pois;
  final int wcEvery; // every n-th shop slot is a restroom
  final Map<String, double> Function(String bld, int lv) weights;
  final Map<String, View> buildingViews;
  final List<PadBtn> pad;
  final StackParams stack;
  final View siteView;
  final String tripTarget;
  final Map<int, List<double>> centres; // level -> point for "I'm on this floor"
  final List<(String, double, double, List<int>)> wingLabels;
  const KSpec({
    required this.id, required this.name, required this.tagline, required this.sizeText, this.keywords = '', required this.seed,
    required this.levels, required this.ground, required this.basePx, required this.site,
    required this.buildings, required this.lines, this.areas = const [], this.anchors = const [], required this.conns,
    this.links = const [], required this.exits, this.zones = const [], this.services = const [], this.groundFx = const [],
    this.trees = const [], this.labels = const [], this.pois = const [], this.wcEvery = 15, required this.weights,
    required this.buildingViews, required this.pad, required this.stack, required this.siteView,
    required this.tripTarget, required this.centres, this.wingLabels = const [],
  });

  /// The same venue under another name or with other anchors (the layout tests' long names).
  KSpec copyWith({String? name, List<KAnchor>? anchors}) => KSpec(
        id: id, name: name ?? this.name, tagline: tagline, sizeText: sizeText, keywords: keywords, seed: seed,
        levels: levels, ground: ground, basePx: basePx, site: site,
        buildings: buildings, lines: lines, areas: areas, anchors: anchors ?? this.anchors, conns: conns,
        links: links, exits: exits, zones: zones, services: services, groundFx: groundFx,
        trees: trees, labels: labels, pois: pois, wcEvery: wcEvery, weights: weights,
        buildingViews: buildingViews, pad: pad, stack: stack, siteView: siteView,
        tripTarget: tripTarget, centres: centres, wingLabels: wingLabels,
      );
}

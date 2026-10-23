// The generic venue model: places, rooms, parking zones, connectors and the
// walkway graph, plus what a venue tells the app about itself (levels, camera
// presets, the demo trip, exits). The offline malls fill it from a
// declarative spec (kit/); admin-published maps will fill it later.
import 'rng.dart';
import 'graph.dart';
import 'routing.dart';

class LevelDef {
  final String id, short, name;
  final double elev; // metres above (or below) the ground floor
  const LevelDef(this.id, this.short, this.name, [this.elev = 0]);
}

/// A drawn room on a level.
class Slot {
  final List<double> rect;
  final String kind; // store | wc | portal | core
  final String? id;
  const Slot(this.rect, this.kind, [this.id]);
}

class Zone {
  final String id, name, wing, attach;
  final int lv;
  final List<double> pt, rect;
  const Zone({required this.id, required this.name, required this.lv, required this.pt, required this.wing, required this.rect, required this.attach});
}

/// An outdoor landmark with a name and a spot (ground level).
class SiteLabel {
  final String name;
  final double x, y;
  const SiteLabel(this.name, this.x, this.y);
}

class Place {
  final String id, wing, kind;

  /// Name, category and status can change with a published mall's live store info (a store
  /// renamed, moved to another category, closed for repairs) without rebuilding the venue.
  String name, cat, status;
  final int lv;
  final List<double> rect, at, door;
  final double w;
  final String? quad;
  final List<List<double>> doors;
  final bool onLine, exitNode;
  final String? attach;
  final int? avail;
  final Zone? zone;
  List<String> nodes;

  Place({
    required this.id, required this.lv, required this.name, required this.cat, required this.wing, required this.rect,
    List<double>? at, required this.door, String? status, double? w, required this.kind, this.quad,
    this.doors = const [], this.onLine = false, this.exitNode = false, this.attach, this.avail, this.zone, List<String>? nodes,
  })  : at = at ?? [(rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2],
        status = status ?? 'open',
        w = (w == null || w == 0) ? 1.6 : w,
        nodes = nodes ?? [];
}

class Connector {
  final String id, type, name;
  final List<int> lvs; // the levels it stops at, low to high; hops join neighbours in this list
  final bool core;
  final List<double>? pt;
  final String? bld;
  /// The cost of one hop in metre-equivalents; null uses the mock-up's per-type cost.
  final double Function(int from, int to)? cost;
  final Map<int, String> at = {};
  Connector({required this.id, required this.type, required this.name, required this.lvs, this.core = false, this.pt, this.bld, this.cost});
}

/// A way out, for evacuation: [node] is just outside the door.
class ExitDef {
  final String id, name, node;
  const ExitDef(this.id, this.name, this.node);
}

/// A camera preset: where to look, and how close.
class View {
  final double cx, cy, zoom;
  const View(this.cx, this.cy, this.zoom);
}

/// A button of the compass pad (N / W / Court / E / S in Aurora).
class PadBtn {
  final String key, simple, tech;
  final View view;
  final bool main; // drawn in the accent colour, like Aurora's Court
  const PadBtn(this.key, this.simple, this.tech, this.view, {this.main = false});
}

/// The stacked view: centre, scale, how far apart the levels are lifted, the angle.
class StackParams {
  final double cx, cy, s, gapM, yaw, ky, kz, mid;
  final List<double> labelAt; // where each level's chip sits, in plan coordinates
  const StackParams({required this.cx, required this.cy, required this.s, required this.gapM, required this.yaw, required this.ky, required this.kz, required this.mid, required this.labelAt});
}

/// Store names: the mock-up's pools, shared by every venue.
const namePrefix = ['Nova', 'Lumi', 'Aster', 'Vela', 'Orchid', 'Juno', 'Kite', 'Maple', 'Onyx', 'Pearl', 'Quill', 'Rune', 'Sable', 'Tidal', 'Umber', 'Vivid', 'Willow', 'Zephyr', 'Amber', 'Birch', 'Cedar', 'Dune', 'Ember', 'Fable', 'Gala', 'Haven', 'Iris', 'Jade', 'Koi', 'Lark', 'Mosaic', 'Noble', 'Opal', 'Pixel', 'Quartz', 'Raven', 'Sunny', 'Terra', 'Urban', 'Velvet', 'Wren', 'Yarrow', 'Zen', 'Atlas', 'Bloom', 'Coral', 'Delta', 'Echo', 'Flint', 'Grove'];
const nameSuffix = {
  'fashion': ['Atelier', 'Denim', 'Boutique', 'Threads', 'Wear', 'Tailors', 'Outfitters', 'Shoes', 'Kids Wear', 'Lingerie'],
  'food': ['Café', 'Kitchen', 'Noodles', 'Grill', 'Bakery', 'Tea House', 'Burger', 'Sushi', 'Pizza', 'Gelato', 'Ramen', 'Donuts'],
  'tech': ['Mobile', 'Gadgets', 'Electronics', 'Computers', 'Audio', 'Cameras'],
  'books': ['Books', 'Stationery', 'Comics', 'Games'],
  'services': ['Pharmacy', 'Optical', 'Salon', 'Spa', 'Dental', 'Bank', 'Travel', 'Repairs', 'Photo', 'Cleaners'],
  'other': ['Home', 'Gifts', 'Toys', 'Garden', 'Pets', 'Jewels', 'Watches', 'Bags', 'Furniture', 'Crafts'],
};

/// The demo's first venue's scale (px per metre at zoom 1). The map's zoom
/// thresholds were tuned for it; every venue is scaled to match.
const double auroraPxPerM = 0.55;

abstract class Venue {
  Venue(int seed) : rand = rng(seed);

  // ----- identity -----
  String get id;
  String get name;
  String get tagline;
  /// Extra words the picker's search matches (features, look-alikes).
  String get keywords => '';

  // ----- levels -----
  List<LevelDef> get levels;
  int get ground;
  int get levelCount => levels.length;
  double zOf(int lv) => levels[lv].elev - levels[ground].elev;
  Map<String, String> get wingNames;

  // ----- generated content -----
  final double Function() rand;
  final places = <Place>[];
  /// Outdoor landmarks by name (the plaza, the bus stop, a car park), for spoken checkpoints outside.
  final siteLabels = <SiteLabel>[];
  late final List<List<Slot>> slots = List.generate(levelCount, (_) => <Slot>[]);
  final usedNames = <String>{};
  late final List<Zone> zones;
  final avail = <String, int>{};
  late final List<Connector> connectors;
  late final Graph graph;
  final _byId = <String, Place>{};

  /// Call once places are final: JS `PLACES.find(p => p.id === id)` is the first match.
  void indexPlaces() {
    for (final p in places) {
      _byId.putIfAbsent(p.id, () => p);
    }
  }

  Place? placeById(String id) => _byId[id];

  T pick<T>(List<T> a) => a[(rand() * a.length).floor()];

  String storeName(String cat) {
    for (var k = 0; k < 50; k++) {
      final n = '${pick(namePrefix)} ${pick(nameSuffix[cat]!)}';
      if (!usedNames.contains(n)) {
        usedNames.add(n);
        return n;
      }
    }
    return '${pick(namePrefix)} ${pick(nameSuffix[cat]!)} II';
  }

  String weightedCat(Map<String, double> w) {
    final r = rand();
    var s = 0.0;
    for (final k in w.keys) {
      s += w[k]!;
      if (r <= s) return k;
    }
    return 'other';
  }

  // ----- the camera -----
  /// px per metre at zoom 1, chosen so zoom 1 shows the whole site.
  double get basePx;
  /// Zoom factor that keeps Aurora's tuned zoom thresholds at the same on-screen detail.
  double get ratio => auroraPxPerM / basePx;
  View get siteView;
  /// The whole site, in plan coordinates: [x1, y1, x2, y2].
  List<double> get siteRect;
  Map<String, View> get buildingViews; // tapping a building in the site view
  List<PadBtn> get pad;
  StackParams get stack;

  // ----- the demo -----
  String get tripTarget; // the default trip's destination (a place id)

  // ----- emergency -----
  List<ExitDef> get exits;
  /// Stair landings on a level where someone who can't use stairs waits for staff.
  List<String> refugeLandings(int lv) => [
        for (final c in connectors)
          if (c.type == 'stairs' && c.at[lv] != null) c.at[lv]!,
        for (final s in graph.emergencyStairs.values)
          if (s[lv] != null) s[lv]!,
      ];

  // ----- the map -----
  /// Connector pins on a level's plan.
  bool connectorPinsOn(int lv) => true;
  /// Wing names written on the plan: text, x, y.
  List<(String, double, double)> wingLabels(int lv) => const [];
  /// Where an approximate "I'm on this floor" puts the dot.
  Pos levelCentre(int lv);

  // ----- the picker -----
  int get buildingCount;
  String get sizeText;
}

// A venue read from a shopper package: what the server builds when a map is
// published (docs/shopper-package-format.md). The walkway graph, the places,
// the connectors and the exits come ready-made; this only rebuilds them in the
// engine's types, in the package's order (routing tie-breaks follow it), and
// works out the camera presets from the package's bounds.
import 'dart:math' as math;

import '../constants.dart';
import '../graph.dart';
import '../kit/kit_venue.dart' show hopCostFor;
import '../routing.dart';
import '../venue.dart';
import 'live_info.dart';

/// The newest package format this app reads. A higher one means "update the app".
const int packageFormatVersion = 1;

/// A package this app cannot use: unreadable, or a newer format.
class PackageFormatException implements Exception {
  const PackageFormatException(this.message, {this.newerFormat = false});
  final String message;

  /// The package is fine but newer than this app understands.
  final bool newerFormat;
  @override
  String toString() => 'PackageFormatException: $message';
}

typedef Ring = List<List<double>>;

class PackageOutline {
  const PackageOutline(this.building, this.outer, this.holes);
  final String? building;
  final Ring outer;
  final List<Ring> holes;
}

class PackageSpace {
  const PackageSpace({required this.id, required this.lv, required this.name, required this.type, required this.shape, this.storeId, this.walkable = false, this.outdoor = false, this.label});
  final String id, name, type;
  final int lv;
  final Ring shape;
  final String? storeId;
  final bool walkable, outdoor;
  final List<double>? label;
}

class PackageWall {
  const PackageWall(this.lv, this.a, this.b, this.t, this.kind);
  final int lv;
  final List<double> a, b;
  final double t;
  final String kind; // solid | glass | partition | boundary
}

class PackageOpening {
  const PackageOpening(this.id, this.lv, this.kind, this.at, this.w, this.angle, this.walkable);
  final String id, kind;
  final int lv;
  final List<double> at;
  final double w, angle;
  final bool walkable;
}

class PackageFeature {
  const PackageFeature(this.id, this.lv, this.type, this.at, this.label);
  final String id, type;
  final int lv;
  final List<double> at;
  final String? label;
}

class PackageBuilding {
  const PackageBuilding(this.id, this.name, this.short, this.levels, this.bounds);
  final String id, name, short;
  final List<int> levels;
  final List<double> bounds;
}

double _d(Object? v) => (v as num).toDouble();
List<double> _pt(Object? v) => [for (final x in v as List) _d(x)];
Ring _ring(Object? v) => [for (final p in v as List) _pt(p)];
String? _s(Object? v) => v?.toString();

class PackageVenue extends Venue {
  /// [json] is the decoded package. [id] is the app's key for the mall (the branch id, or a
  /// sample's id); [name] and [mallName] come from the directory when the package has none.
  PackageVenue(Map<String, Object?> json, {String? id, String? name, String? mallName}) : super(1) {
    final fv = json['formatVersion'];
    if (fv is! int) throw const PackageFormatException('No format version');
    if (fv > packageFormatVersion) throw PackageFormatException('Format $fv is newer than $packageFormatVersion', newerFormat: true);
    try {
      _read(json, id: id, name: name, mallName: mallName);
    } on PackageFormatException {
      rethrow;
    } catch (e) {
      throw PackageFormatException('Unreadable package: $e');
    }
    indexPlaces();
  }

  late final String _id, _name, _mallName;
  late final int version, formatVersion;
  late final List<LevelDef> _levels;
  late final int _ground;
  late final List<double> bounds;

  // ----- the drawing (package_renderer.dart) -----
  late final List<List<PackageOutline>> outlines;
  late final List<PackageSpace> spaces;
  late final List<PackageWall> walls;
  late final List<PackageOpening> openings;
  late final List<PackageFeature> features;
  late final List<PackageBuilding> buildings;
  late final List<double> heights;

  /// Store ids by place id (the package's, then the live store info's).
  final storeOf = <String, String>{};
  final _baseStoreOf = <String, String>{};

  /// The live store info last applied (applyLive), or null.
  LiveInfo? live;

  /// Each place's name, category and status as the package has them, so live info can be undone.
  final _baseline = <String, (String, String, String)>{};

  /// Applies live store info to the places in place (names, categories, statuses): a trip, a
  /// position and the narration carry on. A store no longer in it falls back to the package.
  void applyLive(LiveInfo? l) {
    live = l;
    for (final p in places) {
      final b = _baseline[p.id];
      if (b != null) {
        p.name = b.$1;
        p.cat = b.$2;
        p.status = b.$3;
      }
    }
    storeOf
      ..clear()
      ..addAll(_baseStoreOf);
    if (l == null) return;
    for (final st in l.stores) {
      for (final sid in st.spaceIds) {
        final p = placeById(sid);
        if (p == null) continue;
        if (st.name.isNotEmpty) p.name = st.name;
        if (st.category != null && storeCats.contains(st.category)) p.cat = st.category!;
        p.status = st.status;
        storeOf[sid] = st.storeId;
      }
    }
  }

  /// Lifts, escalators and stairs out of service now (routes avoid them).
  Set<String> get outOfService => live?.outOfService ?? const {};

  /// Stores on spaces this map doesn't have yet: they come with the next map update.
  List<LiveStore> get storesNotOnMap => [
        for (final st in live?.stores ?? const <LiveStore>[])
          if (!st.spaceIds.any((id) => placeById(id) != null)) st,
      ];

  /// Hand-tuned presets: only the sample malls carry them (published maps get them worked out).
  Map<String, Object?> _presets = const {};
  View _viewOf(Object? v) {
    final l = _pt(v);
    return View(l[0], l[1], l[2]);
  }

  void _read(Map<String, Object?> j, {String? id, String? name, String? mallName}) {
    formatVersion = j['formatVersion']! as int;
    version = (j['version'] as num?)?.toInt() ?? 0;
    _id = id ?? _s(j['branchId']) ?? 'package';
    _name = name ?? _s(j['branchName']) ?? _id;
    _mallName = mallName ?? _s(j['mallName']) ?? '';
    bounds = _pt(j['bounds']);
    if (j['presets'] is Map) _presets = (j['presets']! as Map).cast<String, Object?>();

    // levels, lowest first
    final lvs = (j['levels']! as List).cast<Map<String, Object?>>();
    _levels = [for (final l in lvs) LevelDef(l['id']!.toString(), l['short']!.toString(), l['name']!.toString(), _d(l['elev']))];
    heights = [for (final l in lvs) l['height'] == null ? 4.5 : _d(l['height'])];
    final g = lvs.indexWhere((l) => l['ground'] == true);
    _ground = g < 0 ? 0 : g;
    outlines = [
      for (final l in lvs)
        [
          for (final o in (l['outlines'] as List? ?? const []).cast<Map<String, Object?>>())
            PackageOutline(_s(o['building']), _ring(o['outer']), [for (final h in (o['holes'] as List? ?? const [])) _ring(h)]),
        ],
    ];

    // drawing
    spaces = [
      for (final s in (j['spaces'] as List? ?? const []).cast<Map<String, Object?>>())
        PackageSpace(
          id: s['id']!.toString(), lv: (s['lv']! as num).toInt(), name: s['name']?.toString() ?? '', type: s['type']?.toString() ?? 'custom',
          shape: _ring(s['shape']), storeId: _s(s['storeId']), walkable: s['walkable'] == true, outdoor: s['outdoor'] == true,
          label: s['label'] == null ? null : _pt(s['label']),
        ),
    ];
    walls = [
      for (final w in (j['walls'] as List? ?? const []).cast<Map<String, Object?>>())
        PackageWall((w['lv']! as num).toInt(), _pt(w['a']), _pt(w['b']), w['t'] == null ? .2 : _d(w['t']), w['kind']?.toString() ?? 'solid'),
    ];
    openings = [
      for (final o in (j['openings'] as List? ?? const []).cast<Map<String, Object?>>())
        PackageOpening(o['id']!.toString(), (o['lv']! as num).toInt(), o['kind']?.toString() ?? 'door', _pt(o['at']), o['w'] == null ? 1 : _d(o['w']),
            o['angle'] == null ? 0 : _d(o['angle']), o['walkable'] != false),
    ];
    features = [
      for (final f in (j['features'] as List? ?? const []).cast<Map<String, Object?>>())
        PackageFeature(f['id']!.toString(), (f['lv']! as num).toInt(), f['type']?.toString() ?? 'generic_marker', _pt(f['at']), _s(f['label'])),
    ];
    buildings = [
      for (final b in (j['buildings'] as List? ?? const []).cast<Map<String, Object?>>())
        PackageBuilding(b['id']!.toString(), b['name']?.toString() ?? '', b['short']?.toString() ?? b['name']?.toString() ?? '',
            [for (final x in b['levels'] as List? ?? const []) (x as num).toInt()], _pt(b['bounds'])),
    ];

    // ----- the graph, in the package's order -----
    graph = Graph(_levels.length);
    final gr = graph, key = <String, String>{};
    final gj = j['graph']! as Map<String, Object?>;
    for (final n in (gj['nodes']! as List).cast<Map<String, Object?>>()) {
      final k = gr.node((n['lv']! as num).toInt(), _d(n['x']), _d(n['y']));
      final node = gr.nodes[k]!
        ..out = n['out'] == true
        ..inner = n['inner'] == true
        ..emergencyOnly = n['emergencyOnly'] == true;
      if (n['label'] != null) node.label = n['label'].toString();
      key[n['id']!.toString()] = k;
    }
    String nodeKey(Object? id) => key[id.toString()] ?? (throw PackageFormatException('Unknown node $id'));
    for (final e in (gj['edges']! as List).cast<Map<String, Object?>>()) {
      final a = nodeKey(e['a']), b = nodeKey(e['b']), kind = e['kind']?.toString() ?? 'walk', ctype = _s(e['ctype']);
      final meta = EdgeMeta(kind, label: _s(e['label']), conn: _s(e['conn']), ctype: ctype, tech: _s(e['tech']), covered: e['covered'] == true, through: _s(e['through']));
      // a hop's cost is the app's own, by type and height climbed, so routing tuning lives in one place
      final cost = e['cost'] != null
          ? _d(e['cost'])
          : kind == 'hop'
              ? hopCostFor(ctype ?? 'stairs', (_levels[gr.nodes[b]!.lv].elev - _levels[gr.nodes[a]!.lv].elev).abs())
              : null;
      final w = e['w'] == null ? 3.0 : _d(e['w']), emergency = e['emergencyOnly'] == true;
      if (e['oneWay'] == true) {
        gr.linkOneWay(a, b, w, meta, cost, emergency);
      } else {
        gr.link(a, b, w, meta, cost, emergency);
      }
    }

    // ----- places -----
    for (final p in (j['places']! as List).cast<Map<String, Object?>>()) {
      final at = _pt(p['at']), doors = [for (final d in p['doors'] as List? ?? const []) _pt(d)];
      final rect = p['rect'] == null ? [at[0] - 2, at[1] - 2, at[0] + 2, at[1] + 2] : _pt(p['rect']);
      final place = Place(
        id: p['id']!.toString(), lv: (p['lv']! as num).toInt(), name: p['name']?.toString() ?? '', cat: p['cat']?.toString() ?? 'other',
        wing: p['wing']?.toString() ?? 'O', rect: rect, at: at, door: p['door'] == null ? (doors.isEmpty ? at : doors.first) : _pt(p['door']),
        status: _s(p['status']), w: p['w'] == null ? null : _d(p['w']), kind: p['kind']?.toString() ?? 'store', doors: doors,
        onLine: p['onLine'] == true, exitNode: p['exit'] == true, attach: _s(p['attach']),
        nodes: [for (final n in p['nodes'] as List? ?? const []) nodeKey(n)],
      );
      places.add(place);
      final sid = _s(p['storeId']);
      if (sid != null) storeOf[place.id] = sid;
    }
    zones = const [];

    // ----- connectors and exits -----
    connectors = [
      for (final c in (j['connectors'] as List? ?? const []).cast<Map<String, Object?>>())
        () {
          final stops = (c['stops']! as List).cast<Map<String, Object?>>();
          final conn = Connector(
            id: c['id']!.toString(), type: c['type']?.toString() ?? 'stairs', name: c['name']?.toString() ?? '',
            lvs: [for (final s in stops) (s['lv']! as num).toInt()], bld: _s(c['building']),
          );
          for (final s in stops) {
            conn.at.putIfAbsent((s['lv']! as num).toInt(), () => nodeKey(s['node']));
          }
          return conn;
        }(),
    ];
    exits = [for (final e in (j['exits'] as List? ?? const []).cast<Map<String, Object?>>()) ExitDef(e['id']!.toString(), e['name']?.toString() ?? '', nodeKey(e['node']))];
    gr.fixUnjoined(places);
    for (final p in places) {
      _baseline[p.id] = (p.name, p.cat, p.status);
    }
    _baseStoreOf.addAll(storeOf);
  }

  // ===== What the app needs to know =====
  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  String get tagline => _presets['tagline']?.toString() ?? _mallName;
  @override
  String get keywords => _presets['keywords']?.toString() ?? '';
  @override
  List<LevelDef> get levels => _levels;
  @override
  int get ground => _ground;
  @override
  late final Map<String, String> wingNames = _presets['wingNames'] is Map
      ? (_presets['wingNames']! as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
      : {for (final b in buildings) b.id: b.name, 'O': 'Outdoors'};

  @override
  late final List<ExitDef> exits;

  @override
  String get tripTarget => _presets['demoTrip']?.toString() ?? ''; // published malls: no demo trip (owner, 2026-10-23)

  double get _w => math.max(1, bounds[2] - bounds[0]);
  double get _h => math.max(1, bounds[3] - bounds[1]);
  double get _cx => (bounds[0] + bounds[2]) / 2;
  double get _cy => (bounds[1] + bounds[3]) / 2;

  /// px per metre at zoom 1: the whole site fills the phone's width, like the sample malls.
  @override
  late final double basePx = _presets['basePx'] is num ? (_presets['basePx']! as num).toDouble() : 300 / math.max(_w, _h * .8);
  @override
  late final View siteView = _presets['siteView'] != null ? _viewOf(_presets['siteView']) : View(_cx, _cy, 1);
  @override
  List<double> get siteRect => bounds;

  /// The zoom (in this venue's units) at which [width] metres fill about 300 px.
  double _zoomFor(double width, {double min = 2, double max = 8}) => (545 / math.max(1, width)).clamp(min, max) * ratio;

  @override
  late final Map<String, View> buildingViews = _presets['buildingViews'] is Map
      ? {for (final e in (_presets['buildingViews']! as Map).entries) e.key.toString(): _viewOf(e.value)}
      : {
    for (final b in buildings) b.id: View((b.bounds[0] + b.bounds[2]) / 2, (b.bounds[1] + b.bounds[3]) / 2, _zoomFor(math.max(b.bounds[2] - b.bounds[0], b.bounds[3] - b.bounds[1]))),
  };

  /// "Go to": one button per building, the biggest one first in the brand colour.
  @override
  late final List<PadBtn> pad = _presets['pad'] is List
      ? [
          for (final b in (_presets['pad']! as List).cast<Map<String, Object?>>())
            PadBtn(b['key']!.toString(), b['simple']!.toString(), b['tech']!.toString(), _viewOf(b['view']), main: b['main'] == true),
        ]
      : () {
    final sorted = [...buildings]..sort((a, b) => _area(b.bounds).compareTo(_area(a.bounds)));
    return [
      for (final (i, b) in sorted.indexed)
        PadBtn(b.id, b.short, b.name, View((b.bounds[0] + b.bounds[2]) / 2, (b.bounds[1] + b.bounds[3]) / 2,
            _zoomFor(math.max(b.bounds[2] - b.bounds[0], b.bounds[3] - b.bounds[1]), min: 3)), main: i == 0),
    ];
  }();
  static double _area(List<double> r) => (r[2] - r[0]) * (r[3] - r[1]);

  /// The stacked view: about 340 px of levels on screen, whatever the count.
  @override
  late final StackParams stack = _presets['stack'] is Map
      ? () {
          final st = (_presets['stack']! as Map).cast<String, Object?>();
          return StackParams(cx: _d(st['cx']), cy: _d(st['cy']), s: _d(st['s']), gapM: _d(st['gapM']), yaw: _d(st['yaw']), ky: _d(st['ky']), kz: _d(st['kz']), mid: _d(st['mid']), labelAt: _pt(st['labelAt']));
        }()
      : () {
    final n = math.max(1, levelCount), s = basePx * .85;
    return StackParams(cx: _cx, cy: _cy, s: s, gapM: 340 / (n * s), yaw: stackYaw, ky: stackKy, kz: stackKz, mid: (n - 1) / 2, labelAt: [_cx, _cy + _h * .25]);
  }();

  @override
  List<(String, double, double)> wingLabels(int lv) => [
        for (final w in (_presets['wingLabels'] as List? ?? const []).cast<List>())
          if ((w[3] as List).contains(lv)) (w[0].toString(), _d(w[1]), _d(w[2])),
      ];

  /// Where "I'm on this floor" puts the dot: the walkway point nearest the middle of that floor.
  @override
  Pos levelCentre(int lv) {
    if (_presets['centres'] is Map || _presets['siteView'] != null) {
      final c = (_presets['centres'] as Map?)?['$lv'];
      final p = c == null ? [(bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2] : _pt(c);
      return Pos(lv, p[0], p[1], false);
    }
    final pts = [for (final o in outlines[lv]) ...o.outer];
    final c = pts.isEmpty
        ? [_cx, _cy]
        : [pts.map((p) => p[0]).reduce(math.min) / 2 + pts.map((p) => p[0]).reduce(math.max) / 2, pts.map((p) => p[1]).reduce(math.min) / 2 + pts.map((p) => p[1]).reduce(math.max) / 2];
    final k = graph.nearestNodeAt(lv, c[0], c[1]);
    final n = k == null ? null : graph.nodes[k];
    return Pos(lv, n?.x ?? c[0], n?.y ?? c[1], n?.out ?? false);
  }

  @override
  int get buildingCount => (_presets['buildingCount'] as num?)?.toInt() ?? buildings.length;
  @override
  String get sizeText => _presets['sizeText']?.toString() ?? '${buildings.length} ${buildings.length == 1 ? 'building' : 'buildings'} · $levelCount ${levelCount == 1 ? 'level' : 'levels'}';
}

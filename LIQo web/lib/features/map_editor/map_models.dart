import 'dart:math' as math;
import 'dart:ui';

/// The LIQo branch map document, as a mutable object graph.
///
/// Conventions shared with the server validator and the renderer:
///   metres; x across, z down the plan; rot in degrees clockwise, 0..360.
///   One branch-wide grid; a building has an origin and rotation; a level may add offset and rotation.

typedef Pt = List<double>; // [x, z]

List<double> _pt(dynamic v) => [(v[0] as num).toDouble(), (v[1] as num).toDouble()];
List<List<double>> _ring(dynamic v) => (v as List<dynamic>? ?? []).map(_pt).toList();

class Poly {
  Poly({List<List<double>>? outer, List<List<List<double>>>? holes})
      : outer = outer ?? [],
        holes = holes ?? [];

  List<List<double>> outer;
  List<List<List<double>>> holes;

  factory Poly.fromJson(Map<String, dynamic> j) => Poly(
        outer: _ring(j['outer']),
        holes: (j['holes'] as List<dynamic>? ?? []).map((h) => _ring(h)).toList(),
      );

  Map<String, dynamic> toJson() => {'outer': outer, 'holes': holes};

  double get area => polygonArea(outer) - holes.fold(0.0, (a, h) => a + polygonArea(h));
}

class Wall {
  Wall({required this.id, required this.a, required this.b, this.t = 0.2, this.kind = 'solid'});

  String id;
  List<double> a;
  List<double> b;
  double t;
  String kind;

  factory Wall.fromJson(Map<String, dynamic> j) =>
      Wall(id: j['id'] as String, a: _pt(j['a']), b: _pt(j['b']), t: (j['t'] as num?)?.toDouble() ?? 0.2, kind: j['kind'] as String? ?? 'solid');

  Map<String, dynamic> toJson() => {'id': id, 'a': a, 'b': b, 't': t, 'kind': kind};

  double get length => math.sqrt(math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2));

  List<double> pointAt(double f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
}

class Opening {
  Opening({required this.id, required this.wall, this.at = 0.5, this.w = 1.2, this.kind = 'door', this.label = '', Map<String, dynamic>? props})
      : props = props ?? {};

  String id;
  String wall;
  double at;
  double w;
  String kind;
  String label;
  Map<String, dynamic> props;

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        id: j['id'] as String,
        wall: j['wall'] as String,
        at: (j['at'] as num?)?.toDouble() ?? 0.5,
        w: (j['w'] as num?)?.toDouble() ?? 1.2,
        kind: j['kind'] as String? ?? 'door',
        label: j['label'] as String? ?? '',
        props: (j['props'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {'id': id, 'wall': wall, 'at': at, 'w': w, 'kind': kind, 'label': label, 'props': props};
}

class Space {
  Space({
    required this.id,
    this.name = '',
    this.type = 'retail',
    this.customType = '',
    Poly? shape,
    this.unitType = '',
    this.floorLabel = '',
    this.sloped = false,
    this.walkable = true,
    Map<String, dynamic>? meta,
  })  : shape = shape ?? Poly(),
        meta = meta ?? {};

  String id;
  String name;
  String type;
  String customType;
  Poly shape;
  String unitType;
  String floorLabel;
  bool sloped;
  bool walkable;
  Map<String, dynamic> meta;

  factory Space.fromJson(Map<String, dynamic> j) => Space(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? 'retail',
        customType: j['customType'] as String? ?? '',
        shape: Poly.fromJson((j['shape'] as Map<String, dynamic>?) ?? {}),
        unitType: j['unitType'] as String? ?? '',
        floorLabel: j['floorLabel'] as String? ?? '',
        sloped: j['sloped'] == true,
        walkable: j['walkable'] != false,
        meta: (j['meta'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'customType': customType,
        'shape': shape.toJson(),
        'unitType': unitType,
        'floorLabel': floorLabel,
        'sloped': sloped,
        'walkable': walkable,
        'meta': meta,
      };
}

class Feature {
  Feature({required this.id, required this.type, required this.x, required this.z, this.rot = 0, this.w, this.d, this.h, this.label = '', Map<String, dynamic>? props})
      : props = props ?? {};

  String id;
  String type;
  double x;
  double z;
  double rot;
  double? w;
  double? d;
  double? h;
  String label;
  Map<String, dynamic> props;

  factory Feature.fromJson(Map<String, dynamic> j) => Feature(
        id: j['id'] as String,
        type: j['type'] as String,
        x: (j['x'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
        rot: (j['rot'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble(),
        d: (j['d'] as num?)?.toDouble(),
        h: (j['h'] as num?)?.toDouble(),
        label: j['label'] as String? ?? '',
        props: (j['props'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'z': z,
        'rot': rot,
        if (w != null) 'w': w,
        if (d != null) 'd': d,
        if (h != null) 'h': h,
        'label': label,
        'props': props,
      };
}

/// Uploaded floor plan placed under a level for tracing. Draft only; stripped at publish.
class Backdrop {
  Backdrop({required this.id, this.cx = 0, this.cz = 0, this.mpp = 0.01, this.rot = 0, this.opacity = 0.5, this.locked = false, this.calibrated = false});

  String id;
  double cx;
  double cz;

  /// Metres per image pixel. Kept at 7 decimals: rounding to 1 mm would be a 6 % scale error on a 4000 px plan.
  double mpp;
  double rot;
  double opacity;
  bool locked;

  /// The scale was set on purpose: calibrated by hand, a drawing's unit, or found
  /// from a dimension on the plan (Round 18). A plan only stretched to fit is not.
  bool calibrated;

  factory Backdrop.fromJson(Map<String, dynamic> j) => Backdrop(
        id: j['id'] as String,
        cx: (j['cx'] as num?)?.toDouble() ?? 0,
        cz: (j['cz'] as num?)?.toDouble() ?? 0,
        mpp: (j['mpp'] as num?)?.toDouble() ?? 0.01,
        rot: (j['rot'] as num?)?.toDouble() ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 0.5,
        locked: j['locked'] == true,
        calibrated: j['calibrated'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'cx': cx, 'cz': cz, 'mpp': mpp, 'rot': rot, 'opacity': opacity, 'locked': locked, 'calibrated': calibrated};

  /// A pixel of the [width]×[height] picture, in level metres.
  List<double> toLevel(double px, double py, int width, int height) {
    final r = rot * math.pi / 180;
    final mx = (px - width / 2) * mpp;
    final mz = (py - height / 2) * mpp;
    return [cx + mx * math.cos(r) - mz * math.sin(r), cz + mx * math.sin(r) + mz * math.cos(r)];
  }

  /// A level point, in pixels of the [width]×[height] picture.
  List<double> toPicture(List<double> p, int width, int height) {
    final r = rot * math.pi / 180;
    final dx = p[0] - cx;
    final dz = p[1] - cz;
    return [(dx * math.cos(r) + dz * math.sin(r)) / mpp + width / 2, (-dx * math.sin(r) + dz * math.cos(r)) / mpp + height / 2];
  }

  /// The picture box (fractions) covering a level rectangle from [a] to [b].
  List<double> boxFor(List<double> a, List<double> b, int width, int height) {
    final corners = [
      toPicture([a[0], a[1]], width, height),
      toPicture([b[0], a[1]], width, height),
      toPicture([b[0], b[1]], width, height),
      toPicture([a[0], b[1]], width, height),
    ];
    final xs = corners.map((c) => c[0] / width);
    final ys = corners.map((c) => c[1] / height);
    return [xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max)];
  }
}

class Level {
  Level({
    required this.id,
    this.name = 'Level',
    this.elevation = 0,
    this.height = 4,
    List<double>? offset,
    this.rot = 0,
    this.outline,
    this.backdrop,
    List<Wall>? walls,
    List<Opening>? openings,
    List<Space>? spaces,
    List<Feature>? features,
  })  : offset = offset ?? [0, 0],
        walls = walls ?? [],
        openings = openings ?? [],
        spaces = spaces ?? [],
        features = features ?? [];

  String id;
  String name;
  double elevation;
  double height;
  List<double> offset;
  double rot;
  Poly? outline;
  Backdrop? backdrop;
  List<Wall> walls;
  List<Opening> openings;
  List<Space> spaces;
  List<Feature> features;

  factory Level.fromJson(Map<String, dynamic> j) => Level(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Level',
        elevation: (j['elevation'] as num?)?.toDouble() ?? 0,
        height: (j['height'] as num?)?.toDouble() ?? 4,
        offset: j['offset'] == null ? [0, 0] : _pt(j['offset']),
        rot: (j['rot'] as num?)?.toDouble() ?? 0,
        outline: j['outline'] == null ? null : Poly.fromJson(j['outline'] as Map<String, dynamic>),
        backdrop: j['backdrop'] == null ? null : Backdrop.fromJson(j['backdrop'] as Map<String, dynamic>),
        walls: (j['walls'] as List<dynamic>? ?? []).map((e) => Wall.fromJson(e as Map<String, dynamic>)).toList(),
        openings: (j['openings'] as List<dynamic>? ?? []).map((e) => Opening.fromJson(e as Map<String, dynamic>)).toList(),
        spaces: (j['spaces'] as List<dynamic>? ?? []).map((e) => Space.fromJson(e as Map<String, dynamic>)).toList(),
        features: (j['features'] as List<dynamic>? ?? []).map((e) => Feature.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'elevation': elevation,
        'height': height,
        'offset': offset,
        'rot': rot,
        'outline': outline?.toJson(),
        if (backdrop != null) 'backdrop': backdrop!.toJson(),
        'walls': walls.map((w) => w.toJson()).toList(),
        'openings': openings.map((o) => o.toJson()).toList(),
        'spaces': spaces.map((s) => s.toJson()).toList(),
        'features': features.map((f) => f.toJson()).toList(),
      };

  Wall? wallById(String id) => walls.cast<Wall?>().firstWhere((w) => w!.id == id, orElse: () => null);

  /// Bounding box of everything drawn, in level coordinates.
  Rect bounds() {
    double minX = double.infinity, minZ = double.infinity, maxX = -double.infinity, maxZ = -double.infinity;
    void add(double x, double z) {
      if (x < minX) minX = x;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (z > maxZ) maxZ = z;
    }
    for (final p in outline?.outer ?? const <List<double>>[]) {
      add(p[0], p[1]);
    }
    for (final w in walls) {
      add(w.a[0], w.a[1]);
      add(w.b[0], w.b[1]);
    }
    for (final s in spaces) {
      for (final p in s.shape.outer) {
        add(p[0], p[1]);
      }
    }
    for (final f in features) {
      add(f.x, f.z);
    }
    if (minX == double.infinity) return const Rect.fromLTWH(0, 0, 50, 30);
    return Rect.fromLTRB(minX, minZ, maxX, maxZ);
  }
}

class Building {
  Building({required this.id, this.name = 'Building', List<double>? origin, this.rot = 0, List<Level>? levels})
      : origin = origin ?? [0, 0],
        levels = levels ?? [];

  String id;
  String name;
  List<double> origin;
  double rot;
  List<Level> levels;

  factory Building.fromJson(Map<String, dynamic> j) => Building(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Building',
        origin: j['origin'] == null ? [0, 0] : _pt(j['origin']),
        rot: (j['rot'] as num?)?.toDouble() ?? 0,
        levels: (j['levels'] as List<dynamic>? ?? []).map((e) => Level.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'origin': origin, 'rot': rot, 'levels': levels.map((l) => l.toJson()).toList()};
}

class Endpoint {
  Endpoint({required this.level, required this.x, required this.z, this.rot = 0, this.w = 1.4, this.len = 4});

  String level;
  double x;
  double z;
  double rot;
  double w;
  double len;

  factory Endpoint.fromJson(Map<String, dynamic> j) => Endpoint(
        level: j['level'] as String,
        x: (j['x'] as num).toDouble(),
        z: (j['z'] as num).toDouble(),
        rot: (j['rot'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 1.4,
        len: (j['len'] as num?)?.toDouble() ?? 4,
      );

  Map<String, dynamic> toJson() => {'level': level, 'x': x, 'z': z, 'rot': rot, 'w': w, 'len': len};
}

class Connector {
  Connector({required this.id, this.kind = 'stairs', this.name = '', this.oneWay = false, this.walkable = true, List<Endpoint>? endpoints})
      : endpoints = endpoints ?? [];

  String id;
  String kind;
  String name;
  bool oneWay;
  bool walkable;
  List<Endpoint> endpoints;

  factory Connector.fromJson(Map<String, dynamic> j) => Connector(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'stairs',
        name: j['name'] as String? ?? '',
        oneWay: j['oneWay'] == true,
        walkable: j['walkable'] != false,
        endpoints: (j['endpoints'] as List<dynamic>? ?? []).map((e) => Endpoint.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind, 'name': name, 'oneWay': oneWay, 'walkable': walkable, 'endpoints': endpoints.map((e) => e.toJson()).toList()};
}

class LayoutDoc {
  LayoutDoc({this.catalog = 1, List<Building>? buildings, List<Connector>? connectors})
      : buildings = buildings ?? [],
        connectors = connectors ?? [];

  int catalog;
  List<Building> buildings;
  List<Connector> connectors;

  factory LayoutDoc.fromJson(Map<String, dynamic> j) => LayoutDoc(
        catalog: j['catalog'] as int? ?? 1,
        buildings: (j['buildings'] as List<dynamic>? ?? []).map((e) => Building.fromJson(e as Map<String, dynamic>)).toList(),
        connectors: (j['connectors'] as List<dynamic>? ?? []).map((e) => Connector.fromJson(e as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'spec': 1,
        'units': 'm',
        'catalog': catalog,
        'buildings': buildings.map((b) => b.toJson()).toList(),
        'connectors': connectors.map((c) => c.toJson()).toList(),
      };

  Building? building(String? id) => buildings.cast<Building?>().firstWhere((b) => b!.id == id, orElse: () => null);

  Level? level(String? id) {
    for (final b in buildings) {
      for (final l in b.levels) {
        if (l.id == id) return l;
      }
    }
    return null;
  }

  Building? buildingOfLevel(String? id) {
    for (final b in buildings) {
      if (b.levels.any((l) => l.id == id)) return b;
    }
    return null;
  }

  Iterable<Level> get allLevels sync* {
    for (final b in buildings) {
      yield* b.levels;
    }
  }

  int get spaceCount => allLevels.fold(0, (n, l) => n + l.spaces.length);
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

double polygonArea(List<List<double>> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final q = pts[(i + 1) % pts.length];
    a += p[0] * q[1] - q[0] * p[1];
  }
  return a.abs() / 2;
}

bool pointInRing(double x, double z, List<List<double>> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0], zi = ring[i][1], xj = ring[j][0], zj = ring[j][1];
    final intersect = ((zi > z) != (zj > z)) && (x < (xj - xi) * (z - zi) / ((zj - zi) == 0 ? 1e-9 : (zj - zi)) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

bool pointInPoly(double x, double z, Poly p) {
  if (!pointInRing(x, z, p.outer)) return false;
  for (final h in p.holes) {
    if (pointInRing(x, z, h)) return false;
  }
  return true;
}

/// Distance from point to segment, and the fraction along it (clamped 0..1).
({double dist, double t}) pointToSegment(double px, double pz, List<double> a, List<double> b) {
  final dx = b[0] - a[0], dz = b[1] - a[1];
  final len2 = dx * dx + dz * dz;
  var t = len2 == 0 ? 0.0 : ((px - a[0]) * dx + (pz - a[1]) * dz) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = a[0] + dx * t, cz = a[1] + dz * t;
  return (dist: math.sqrt((px - cx) * (px - cx) + (pz - cz) * (pz - cz)), t: t);
}

double snapTo(double v, double step) => (v / step).round() * step;

/// Snaps the angle of segment a→b to 15° steps, keeping the length.
List<double> snapAngle(List<double> a, List<double> b, {double stepDeg = 15}) {
  final dx = b[0] - a[0], dz = b[1] - a[1];
  final len = math.sqrt(dx * dx + dz * dz);
  if (len == 0) return b;
  final ang = math.atan2(dz, dx);
  final step = stepDeg * math.pi / 180;
  final snapped = (ang / step).round() * step;
  return [a[0] + math.cos(snapped) * len, a[1] + math.sin(snapped) * len];
}

Rect ringBounds(List<List<double>> ring) {
  double minX = double.infinity, minZ = double.infinity, maxX = -double.infinity, maxZ = -double.infinity;
  for (final p in ring) {
    if (p[0] < minX) minX = p[0];
    if (p[1] < minZ) minZ = p[1];
    if (p[0] > maxX) maxX = p[0];
    if (p[1] > maxZ) maxZ = p[1];
  }
  return Rect.fromLTRB(minX, minZ, maxX, maxZ);
}

List<double> ringCentroid(List<List<double>> ring) {
  if (ring.isEmpty) return [0, 0];
  var x = 0.0, z = 0.0;
  for (final p in ring) {
    x += p[0];
    z += p[1];
  }
  return [x / ring.length, z / ring.length];
}

String newId(String prefix) {
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  final r = math.Random();
  final s = List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  return '$prefix-$s';
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import 'map_models.dart';

class MapStatus {
  const MapStatus({
    required this.branchId,
    required this.branchName,
    required this.mallName,
    required this.hasMap,
    required this.draftVersion,
    this.publishedVersion,
    this.publishedAt,
    required this.spaceCount,
    this.lockedBy,
    this.branchActive = true,
  });

  final int branchId;
  final String branchName;
  final String mallName;
  final bool hasMap;
  final int draftVersion;
  final int? publishedVersion;
  final DateTime? publishedAt;
  final int spaceCount;
  final String? lockedBy;

  /// False for a branch its owner deactivated (owners still view it, read-only).
  final bool branchActive;

  factory MapStatus.fromJson(Map<String, dynamic> j) => MapStatus(
        branchId: j['branchId'] as int,
        branchName: j['branchName'] as String,
        mallName: j['mallName'] as String? ?? '',
        hasMap: j['hasMap'] == true,
        draftVersion: j['draftVersion'] as int? ?? 0,
        publishedVersion: j['publishedVersion'] as int?,
        publishedAt: j['publishedAt'] == null ? null : DateTime.parse(j['publishedAt'] as String).toLocal(),
        spaceCount: j['spaceCount'] as int? ?? 0,
        lockedBy: (j['lockedBy'] as Map<String, dynamic>?)?['userName'] as String?,
        branchActive: j['branchActive'] != false,
      );
}

class MapVersion {
  const MapVersion({required this.version, required this.spaceCount, this.note, required this.publishedAt, this.publishedByName});

  final int version;
  final int spaceCount;
  final String? note;
  final DateTime publishedAt;
  final String? publishedByName;

  factory MapVersion.fromJson(Map<String, dynamic> j) => MapVersion(
        version: j['version'] as int,
        spaceCount: j['spaceCount'] as int? ?? 0,
        note: j['note'] as String?,
        publishedAt: DateTime.parse(j['publishedAt'] as String).toLocal(),
        publishedByName: j['publishedByName'] as String?,
      );
}

class MapWarning {
  const MapWarning({required this.code, required this.message, required this.ids});

  final String code;
  final String message;
  final List<String> ids;

  factory MapWarning.fromJson(Map<String, dynamic> j) => MapWarning(code: j['code'] as String, message: j['message'] as String, ids: (j['ids'] as List<dynamic>? ?? []).cast<String>());
}

class MapLock {
  const MapLock({required this.userId, this.userName, required this.expiresAt, required this.mine});

  final int userId;
  final String? userName;
  final DateTime expiresAt;
  final bool mine;

  factory MapLock.fromJson(Map<String, dynamic> j) => MapLock(
        userId: j['userId'] as int,
        userName: j['userName'] as String?,
        expiresAt: DateTime.parse(j['expiresAt'] as String).toLocal(),
        mine: j['mine'] == true,
      );
}

class StoreLink {
  const StoreLink({required this.spaceKey, required this.storeId, required this.storeName});

  final String spaceKey;
  final int storeId;
  final String storeName;

  factory StoreLink.fromJson(Map<String, dynamic> j) => StoreLink(spaceKey: j['spaceKey'] as String, storeId: j['storeId'] as int, storeName: j['storeName'] as String);
}

class MapBundle {
  const MapBundle({
    required this.branchId,
    required this.branchName,
    required this.hasMap,
    this.draft,
    required this.draftVersion,
    this.publishedVersion,
    this.publishedAt,
    this.lock,
    required this.versions,
    required this.storeLinks,
    required this.warnings,
    required this.canEdit,
  });

  final int branchId;
  final String branchName;
  final bool hasMap;
  final Map<String, dynamic>? draft;
  final int draftVersion;
  final int? publishedVersion;
  final DateTime? publishedAt;
  final MapLock? lock;
  final List<MapVersion> versions;
  final List<StoreLink> storeLinks;
  final List<MapWarning> warnings;
  final bool canEdit;

  factory MapBundle.fromJson(Map<String, dynamic> j) {
    final branch = j['branch'] as Map<String, dynamic>;
    final map = j['map'] as Map<String, dynamic>?;
    return MapBundle(
      branchId: branch['id'] as int,
      branchName: '${branch['mallName']} · ${branch['name']}',
      hasMap: map != null,
      draft: map?['draft'] as Map<String, dynamic>?,
      draftVersion: map?['draftVersion'] as int? ?? 0,
      publishedVersion: map?['publishedVersion'] as int?,
      publishedAt: map?['publishedAt'] == null ? null : DateTime.parse(map!['publishedAt'] as String).toLocal(),
      lock: map?['lock'] == null ? null : MapLock.fromJson(map!['lock'] as Map<String, dynamic>),
      versions: (j['versions'] as List<dynamic>? ?? []).map((e) => MapVersion.fromJson(e as Map<String, dynamic>)).toList(),
      storeLinks: (j['storeLinks'] as List<dynamic>? ?? []).map((e) => StoreLink.fromJson(e as Map<String, dynamic>)).toList(),
      warnings: (j['warnings'] as List<dynamic>? ?? []).map((e) => MapWarning.fromJson(e as Map<String, dynamic>)).toList(),
      canEdit: j['canEdit'] == true,
    );
  }
}

class FeatureDef {
  const FeatureDef({required this.key, required this.category, required this.label, required this.size, this.resize, required this.blocks, required this.target, required this.icon});

  final String key;
  final String category;
  final String label;
  final List<double> size;
  final Map<String, List<double>>? resize;
  final bool blocks;
  final bool target;
  final String icon;
}

class MapCatalog {
  const MapCatalog(
      {required this.version,
      required this.categories,
      required this.features,
      required this.spaceTypes,
      required this.wallKinds,
      required this.openingKinds,
      required this.connectorKinds,
      required this.oneWayCapable});

  final int version;
  final List<String> categories;
  final Map<String, FeatureDef> features;
  final List<String> spaceTypes;
  final List<String> wallKinds;
  final List<String> openingKinds;
  final List<String> connectorKinds;
  final List<String> oneWayCapable;

  factory MapCatalog.fromJson(Map<String, dynamic> j) {
    final feats = <String, FeatureDef>{};
    for (final e in (j['features'] as Map<String, dynamic>).entries) {
      final f = e.value as Map<String, dynamic>;
      feats[e.key] = FeatureDef(
        key: e.key,
        category: f['category'] as String,
        label: f['label'] as String,
        size: (f['size'] as List<dynamic>).map((n) => (n as num).toDouble()).toList(),
        resize: f['resize'] == null ? null : (f['resize'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as List<dynamic>).map((n) => (n as num).toDouble()).toList())),
        blocks: f['blocks'] == true,
        target: f['target'] == true,
        icon: f['icon'] as String? ?? 'pin',
      );
    }
    return MapCatalog(
      version: j['version'] as int,
      categories: (j['categories'] as List<dynamic>).cast<String>(),
      features: feats,
      spaceTypes: (j['spaceTypes'] as List<dynamic>).cast<String>(),
      wallKinds: (j['wallKinds'] as List<dynamic>).cast<String>(),
      openingKinds: (j['openingKinds'] as List<dynamic>).cast<String>(),
      connectorKinds: (j['connectorKinds'] as List<dynamic>).cast<String>(),
      oneWayCapable: (j['oneWayCapable'] as List<dynamic>).cast<String>(),
    );
  }
}

class BackdropInfo {
  const BackdropInfo({
    required this.id,
    required this.width,
    required this.height,
    this.originalName,
    required this.uploadedAt,
    this.kind = 'image',
    this.units,
    this.mpp,
    this.needsUnit = false,
  });

  final String id;
  final int width;
  final int height;
  final String? originalName;
  final DateTime uploadedAt;

  /// What was uploaded (Round 16): image, svg, dxf or dwg. Drawings are shown as a PNG.
  final String kind;

  /// The drawing's unit (mm, cm, m, in, ft), when known.
  final String? units;

  /// Exact metres per picture pixel from the drawing's unit; null = calibrate by hand.
  final double? mpp;

  /// A DXF or DWG that does not say its unit: the admin picks it before placing.
  final bool needsUnit;

  bool get isDrawing => kind != 'image';

  factory BackdropInfo.fromJson(Map<String, dynamic> j) => BackdropInfo(
        id: j['id'] as String,
        width: j['width'] as int,
        height: j['height'] as int,
        originalName: j['originalName'] as String?,
        uploadedAt: DateTime.parse(j['uploadedAt'] as String).toLocal(),
        kind: j['kind'] as String? ?? 'image',
        units: j['units'] as String?,
        mpp: (j['mpp'] as num?)?.toDouble(),
        needsUnit: j['needsUnit'] == true,
      );
}

/// Units a DXF or DWG drawing can be in, with their names for people.
const drawingUnits = {'mm': 'millimetres', 'cm': 'centimetres', 'm': 'metres', 'in': 'inches', 'ft': 'feet'};

/// A proposed room whose name matches a store of the branch (Round 15).
class StoreMatch {
  const StoreMatch({required this.spaceId, required this.storeId, required this.storeName, this.exact = false});

  final String spaceId;
  final int storeId;
  final String storeName;
  final bool exact;

  factory StoreMatch.fromJson(Map<String, dynamic> j) => StoreMatch(spaceId: j['spaceId'] as String, storeId: j['storeId'] as int, storeName: j['storeName'] as String, exact: j['exact'] == true);

  StoreMatch withSpace(String id) => StoreMatch(spaceId: id, storeId: storeId, storeName: storeName, exact: exact);
}

/// The plan's scale the AI found from a dimension written on it (Round 18).
class ScaleFound {
  const ScaleFound({required this.mpp, required this.mm});

  final double mpp;
  final int mm;

  static ScaleFound? fromJson(Object? j) => j is Map<String, dynamic> && j['mpp'] is num ? ScaleFound(mpp: (j['mpp'] as num).toDouble(), mm: (j['mm'] as num?)?.round() ?? 0) : null;
}

/// What one AI reading cost, from the gateway's meter.
class AiCost {
  const AiCost({this.model, this.credits = 0, this.usd = 0});

  final String? model;
  final double credits;
  final double usd;

  factory AiCost.fromJson(Map<String, dynamic> j) => AiCost(model: j['model'] as String?, credits: (j['credits'] as num?)?.toDouble() ?? 0, usd: (j['usd'] as num?)?.toDouble() ?? 0);

  AiCost operator +(AiCost o) => AiCost(model: o.model ?? model, credits: credits + o.credits, usd: usd + o.usd);
}

/// Geometry proposed by the AI reading. Nothing here is in the draft until accepted.
class Proposal {
  const Proposal({
    required this.levelId,
    required this.walls,
    required this.openings,
    required this.spaces,
    required this.stats,
    required this.notes,
    required this.usedAi,
    this.outline,
    this.uncertain = const {},
    this.storeMatches = const [],
    this.cost,
    this.sections = 1,
    this.scaleFound,
  });

  /// The scale read from a dimension on the plan, when its scale was never set.
  final ScaleFound? scaleFound;

  final String levelId;
  final List<Wall> walls;
  final List<Opening> openings;
  final List<Space> spaces;
  final Map<String, dynamic> stats;
  final List<String> notes;
  final bool usedAi;

  /// The floor's outline as the AI read it, when the edge was in the picture.
  final Poly? outline;

  /// Ids of pieces the AI was not sure about (shown dashed in amber).
  final Set<String> uncertain;
  final List<StoreMatch> storeMatches;

  /// Total cost of the readings in this proposal.
  final AiCost? cost;

  /// How many readings (whole plan or boxed parts) were merged into it.
  final int sections;

  factory Proposal.fromJson(Map<String, dynamic> j) {
    final p = j['proposal'] as Map<String, dynamic>;
    return Proposal(
      levelId: p['levelId'] as String,
      walls: (p['walls'] as List<dynamic>).map((e) => Wall.fromJson(e as Map<String, dynamic>)).toList(),
      openings: (p['openings'] as List<dynamic>).map((e) => Opening.fromJson(e as Map<String, dynamic>)).toList(),
      spaces: (p['spaces'] as List<dynamic>).map((e) => Space.fromJson(e as Map<String, dynamic>)).toList(),
      outline: p['outline'] == null ? null : Poly.fromJson(p['outline'] as Map<String, dynamic>),
      uncertain: (p['uncertain'] as List<dynamic>? ?? []).cast<String>().toSet(),
      storeMatches: (p['storeMatches'] as List<dynamic>? ?? []).map((e) => StoreMatch.fromJson(e as Map<String, dynamic>)).toList(),
      stats: (j['stats'] as Map<String, dynamic>?) ?? const {},
      notes: (j['notes'] as List<dynamic>? ?? []).cast<String>(),
      usedAi: j['usedAi'] == true,
      cost: j['cost'] == null ? null : AiCost.fromJson(j['cost'] as Map<String, dynamic>),
      scaleFound: ScaleFound.fromJson(j['scaleFound']),
    );
  }

  /// The same proposal with pieces left out (by id), keeping links and marks consistent.
  Proposal without(Set<String> ids, {bool dropOutline = false}) {
    final w = walls.where((x) => !ids.contains(x.id)).toList();
    final wallIds = w.map((x) => x.id).toSet();
    final o = openings.where((x) => !ids.contains(x.id) && wallIds.contains(x.wall)).toList();
    final s = spaces.where((x) => !ids.contains(x.id)).toList();
    final kept = {...wallIds, ...o.map((x) => x.id), ...s.map((x) => x.id)};
    return Proposal(
      levelId: levelId,
      walls: w,
      openings: o,
      spaces: s,
      outline: dropOutline ? null : outline,
      uncertain: uncertain.where(kept.contains).toSet(),
      storeMatches: storeMatches.where((m) => kept.contains(m.spaceId)).toList(),
      stats: stats,
      notes: notes,
      usedAi: usedAi,
      cost: cost,
      sections: sections,
      scaleFound: scaleFound,
    );
  }

  /// Adds another reading of the same level (a further section of a large plan).
  /// Walls already proposed (both ends within 30 cm) and rooms already proposed
  /// (centre inside a proposed room of similar size) are not added twice.
  Proposal merge(Proposal next) {
    bool sameWall(Wall a, Wall b) {
      double d(List<double> p, List<double> q) => math.sqrt(math.pow(p[0] - q[0], 2) + math.pow(p[1] - q[1], 2));
      return (d(a.a, b.a) < 0.3 && d(a.b, b.b) < 0.3) || (d(a.a, b.b) < 0.3 && d(a.b, b.a) < 0.3);
    }

    bool sameSpace(Space a, Space b) {
      final ca = ringCentroid(a.shape.outer);
      final ratio = a.shape.area == 0 ? 0 : b.shape.area / a.shape.area;
      return pointInPoly(ca[0], ca[1], b.shape) && ratio > 0.7 && ratio < 1.3;
    }

    final skip = <String>{
      for (final w in next.walls)
        if (walls.any((x) => sameWall(x, w))) w.id,
      for (final s in next.spaces)
        if (spaces.any((x) => sameSpace(s, x))) s.id,
    };
    final add = next.without(skip);
    final notesAll = [...notes];
    for (final n in add.notes) {
      if (!notesAll.contains(n)) notesAll.add(n);
    }
    final w = [...walls, ...add.walls];
    final o = [...openings, ...add.openings];
    final s = [...spaces, ...add.spaces];
    return Proposal(
      levelId: levelId,
      walls: w,
      openings: o,
      spaces: s,
      outline: outline ?? add.outline,
      uncertain: {...uncertain, ...add.uncertain},
      storeMatches: [...storeMatches, ...add.storeMatches],
      stats: {
        'walls': w.length,
        'doors': o.length,
        'spaces': s.length,
        'wallMetres': w.fold<double>(0, (n, x) => n + x.length).round(),
      },
      notes: notesAll,
      usedAi: usedAi || next.usedAi,
      cost: cost == null ? next.cost : (next.cost == null ? cost : cost! + next.cost!),
      sections: sections + 1,
      scaleFound: scaleFound ?? next.scaleFound,
    );
  }
}

class SaveResult {
  const SaveResult({required this.draftVersion, required this.publishProblems, required this.warnings, required this.spaceCount});

  final int draftVersion;
  final List<String> publishProblems;
  final List<MapWarning> warnings;
  final int spaceCount;
}

/// Thrown when the server refuses a save or publish with a problem list.
class MapProblemsException implements Exception {
  const MapProblemsException(this.message, this.problems);

  final String message;
  final List<String> problems;

  @override
  String toString() => message;
}

class MapStaleException implements Exception {
  const MapStaleException(this.message, this.draftVersion);

  final String message;
  final int? draftVersion;

  @override
  String toString() => message;
}

class MapLockedException implements Exception {
  const MapLockedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MapsService {
  MapsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Map<String, dynamic> _m(Object? d) => d as Map<String, dynamic>;

  Never _rethrow(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['problems'] is List) throw MapProblemsException(data['error'] as String? ?? 'The map has problems.', (data['problems'] as List).cast<String>());
      if (data['code'] == 'MAP_STALE') throw MapStaleException(data['error'] as String, data['draftVersion'] as int?);
      if (e.response?.statusCode == 423) throw MapLockedException(data['error'] as String);
    }
    throw e;
  }

  Future<List<MapStatus>> list() async {
    final r = await _client.dio.get('/maps');
    return (_m(r.data)['items'] as List<dynamic>).map((e) => MapStatus.fromJson(_m(e))).toList();
  }

  /// Superadmin: clear a lock left by a closed or crashed editor. Returns who held it.
  Future<String?> forceReleaseLock(int branchId) async {
    final r = await _client.dio.post('/maps/$branchId/lock/force-release');
    return _m(r.data)['previousHolder'] as String?;
  }

  Future<MapCatalog> catalog() async => MapCatalog.fromJson(_m((await _client.dio.get('/maps/catalog')).data));

  Future<MapBundle> get(int branchId) async => MapBundle.fromJson(_m((await _client.dio.get('/maps/$branchId')).data));

  Future<void> create(int branchId, {String buildingName = 'Main building', String levelName = 'Ground floor', double width = 100, double depth = 60, bool outline = true}) async {
    try {
      await _client.dio.post('/maps/$branchId', data: {'buildingName': buildingName, 'levelName': levelName, 'width': width, 'depth': depth, 'outline': outline});
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<MapLock> lock(int branchId) async {
    try {
      final r = await _client.dio.post('/maps/$branchId/lock');
      return MapLock.fromJson(_m(_m(r.data)['lock']));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> releaseLock(int branchId) async {
    try {
      await _client.dio.post('/maps/$branchId/lock/release');
    } catch (_) {}
  }

  Future<SaveResult> saveDraft(int branchId, LayoutDoc doc, int baseVersion) async {
    try {
      final r = await _client.dio.put('/maps/$branchId/draft', data: {'layout': doc.toJson(), 'baseVersion': baseVersion});
      final d = _m(r.data);
      return SaveResult(
        draftVersion: d['draftVersion'] as int,
        publishProblems: (d['publishProblems'] as List<dynamic>? ?? []).cast<String>(),
        warnings: (d['warnings'] as List<dynamic>? ?? []).map((e) => MapWarning.fromJson(_m(e))).toList(),
        spaceCount: d['spaceCount'] as int? ?? 0,
      );
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<(int publishedVersion, int draftVersion)> publish(int branchId, int baseVersion, {String? note}) async {
    try {
      final r = await _client.dio.post('/maps/$branchId/publish', data: {'baseVersion': baseVersion, if (note != null && note.isNotEmpty) 'note': note});
      final d = _m(r.data);
      return (d['publishedVersion'] as int, d['draftVersion'] as int);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<(int publishedVersion, int draftVersion)> rollback(int branchId, int version) async {
    try {
      final r = await _client.dio.post('/maps/$branchId/rollback', data: {'version': version});
      final d = _m(r.data);
      return (d['publishedVersion'] as int, d['draftVersion'] as int);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> copyTo(int branchId, int targetBranchId, {bool overwrite = false}) async {
    try {
      await _client.dio.post('/maps/$branchId/copy', data: {'targetBranchId': targetBranchId, 'overwrite': overwrite});
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<(LayoutDoc, int, DateTime)?> published(int branchId) async {
    try {
      final r = await _client.dio.get('/maps/$branchId/published');
      final d = _m(r.data);
      return (LayoutDoc.fromJson(_m(d['layout'])), d['version'] as int, DateTime.parse(d['publishedAt'] as String).toLocal());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<LayoutDoc> version(int branchId, int version) async => LayoutDoc.fromJson(_m(_m((await _client.dio.get('/maps/$branchId/versions/$version')).data)['layout']));

  // ---- Backdrops ----

  Future<List<BackdropInfo>> backdrops(int branchId) async =>
      (_m((await _client.dio.get('/maps/$branchId/backdrops')).data)['items'] as List<dynamic>).map((e) => BackdropInfo.fromJson(_m(e))).toList();

  Future<BackdropInfo> uploadBackdrop(int branchId, Uint8List bytes, String fileName) async {
    try {
      final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: fileName)});
      final r = await _client.dio.post('/maps/$branchId/backdrops', data: form);
      return BackdropInfo.fromJson(_m(_m(r.data)['backdrop']));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Uint8List> backdropBytes(int branchId, String key) async {
    final r = await _client.dio.get<List<int>>('/maps/$branchId/backdrops/$key', options: Options(responseType: ResponseType.bytes));
    return Uint8List.fromList(r.data ?? const []);
  }

  /// Sets the unit of a DXF or DWG drawing; the answer carries its exact scale.
  Future<BackdropInfo> setBackdropUnit(int branchId, String key, String unit) async {
    try {
      final r = await _client.dio.put('/maps/$branchId/backdrops/$key/unit', data: {'unit': unit});
      return BackdropInfo.fromJson(_m(_m(r.data)['backdrop']));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<void> deleteBackdrop(int branchId, String key) async {
    try {
      await _client.dio.delete('/maps/$branchId/backdrops/$key');
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Read the plan with AI; [crop] is a box in fractions of the picture [x0, y0, x1, y1].
  Future<Proposal> convert(int branchId, String key, String levelId, {List<double>? crop}) async {
    try {
      final r = await _client.dio.post(
        '/maps/$branchId/backdrops/$key/convert',
        data: {'levelId': levelId, if (crop != null) 'crop': crop},
        options: Options(receiveTimeout: const Duration(minutes: 5)),
      );
      return Proposal.fromJson(_m(r.data));
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Adds one space to a store's links, keeping the store's other spaces.
  Future<void> linkStoreToSpace(int storeId, String spaceKey) async {
    final d = _m((await _client.dio.get('/stores/$storeId')).data);
    final keys = {...(d['spaces'] as List<dynamic>? ?? []).cast<String>(), spaceKey}.toList();
    await _client.dio.put('/stores/$storeId/spaces', data: {'spaceKeys': keys});
  }

  Future<(String? source, List<Map<String, dynamic>> spaces, List<StoreLink> links)> spaces(int branchId) async {
    final d = _m((await _client.dio.get('/maps/$branchId/spaces')).data);
    return (
      d['source'] as String?,
      (d['spaces'] as List<dynamic>).map(_m).toList(),
      (d['links'] as List<dynamic>).map((e) => StoreLink.fromJson(_m(e))).toList(),
    );
  }
}

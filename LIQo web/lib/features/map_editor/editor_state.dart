import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import 'guided/geometry.dart';
import 'map_models.dart';
import 'maps_service.dart';

enum EditorTool { select, wall, space, hole, outline, opening, feature, connector }

/// The easy editor's tools (Round 18). Each one is a single action: it does its
/// one thing and returns to plain selecting, so nothing keeps happening by accident.
enum GuidedTool { none, addWall, addDoor, split, merge, pickStore }

/// The easy editor's door widths, in plain words.
const doorPresets = <String, (String kind, double width)>{
  'Door': ('door', 0.9),
  'Double door': ('door', 1.8),
  'Entrance': ('entrance', 3.0),
  'Shop front': ('shutter', 6.0),
};

enum SaveState { none, dirty, saving, saved, error, conflict }

enum SelKind { none, wall, opening, space, feature, connector, level, building }

class Selection {
  const Selection(this.kind, this.id);

  static const none = Selection(SelKind.none, '');

  final SelKind kind;
  final String id;

  bool get isEmpty => kind == SelKind.none;
}

class EditorData {
  const EditorData({
    this.branchId,
    this.branchName = '',
    this.doc,
    this.catalog,
    this.levelId,
    this.tool = EditorTool.select,
    this.featureType = 'entrance',
    this.connectorKind = 'stairs',
    this.selection = Selection.none,
    this.pending = const [],
    this.saveState = SaveState.none,
    this.draftVersion = 0,
    this.publishedVersion,
    this.publishProblems = const [],
    this.shopperProblems = const [],
    this.shopperWarnings = const [],
    this.shopperCheckedVersion,
    this.checkingShopper = false,
    this.warnings = const [],
    this.versions = const [],
    this.storeLinks = const [],
    this.lock,
    this.canEdit = false,
    this.snap = true,
    this.loading = false,
    this.error,
    this.undoDepth = 0,
    this.redoDepth = 0,
    this.lastSavedAt,
    this.calibrating = false,
    this.calibPoints = const [],
    this.proposal,
    this.converting = false,
    this.cropping = false,
    this.cropBox,
    this.lastCost,
    this.fitRequest = 0,
    this.guided = true,
    this.guidedStep = 0,
    this.guidedTool = GuidedTool.none,
    this.doorPreset = 'Door',
    this.pickStore,
  });

  final int? branchId;
  final String branchName;
  final LayoutDoc? doc;
  final MapCatalog? catalog;
  final String? levelId;
  final EditorTool tool;
  final String featureType;
  final String connectorKind;
  final Selection selection;

  /// Points of the wall chain / polygon in progress (level coordinates).
  final List<List<double>> pending;
  final SaveState saveState;
  final int draftVersion;
  final int? publishedVersion;
  final List<String> publishProblems;

  /// Round 21: what shoppers could not walk to (blocks publishing) and what they would lose (warns), for the draft version checked.
  final List<MapWarning> shopperProblems;
  final List<MapWarning> shopperWarnings;
  final int? shopperCheckedVersion;
  final bool checkingShopper;
  final List<MapWarning> warnings;
  final List<MapVersion> versions;
  final List<StoreLink> storeLinks;
  final MapLock? lock;
  final bool canEdit;
  final bool snap;
  final bool loading;
  final String? error;
  final int undoDepth;
  final int redoDepth;
  final DateTime? lastSavedAt;

  /// Calibration mode: the user clicks two points of known distance on the backdrop.
  final bool calibrating;
  final List<List<double>> calibPoints;

  /// AI reading waiting for review. Drawn over the level, not part of the draft.
  final Proposal? proposal;
  final bool converting;

  /// Box mode: the user drags a box over the plan to read only that part.
  final bool cropping;

  /// The box to read, in fractions of the plan picture [x0, y0, x1, y1]; null = whole plan.
  final List<double>? cropBox;

  /// What the last AI reading cost.
  final AiCost? lastCost;

  /// Bumped when the canvas should frame the level (and its plan) again (Round 17).
  final int fitRequest;

  /// The easy editor (Round 18, owner decision: guided steps for everyone; the
  /// full tools under "Advanced editing").
  final bool guided;

  /// ① Plan ② Scale ③ Read with AI ④ Rooms ⑤ Publish (0–4).
  final int guidedStep;
  final GuidedTool guidedTool;
  final String doorPreset;

  /// The store being placed on the map ("pick a store, then click its room").
  final StoreLink? pickStore;

  bool get editable => canEdit && (lock?.mine ?? false) && saveState != SaveState.conflict;
  Level? get level => doc?.level(levelId);
  Building? get building => doc?.buildingOfLevel(levelId);

  EditorData copyWith({
    int? branchId,
    String? branchName,
    LayoutDoc? doc,
    MapCatalog? catalog,
    String? levelId,
    EditorTool? tool,
    String? featureType,
    String? connectorKind,
    Selection? selection,
    List<List<double>>? pending,
    SaveState? saveState,
    int? draftVersion,
    Object? publishedVersion = _keep,
    List<String>? publishProblems,
    List<MapWarning>? shopperProblems,
    List<MapWarning>? shopperWarnings,
    Object? shopperCheckedVersion = _keep,
    bool? checkingShopper,
    List<MapWarning>? warnings,
    List<MapVersion>? versions,
    List<StoreLink>? storeLinks,
    Object? lock = _keep,
    bool? canEdit,
    bool? snap,
    bool? loading,
    Object? error = _keep,
    int? undoDepth,
    int? redoDepth,
    DateTime? lastSavedAt,
    bool? calibrating,
    List<List<double>>? calibPoints,
    Object? proposal = _keep,
    bool? converting,
    bool? cropping,
    Object? cropBox = _keep,
    Object? lastCost = _keep,
    int? fitRequest,
    bool? guided,
    int? guidedStep,
    GuidedTool? guidedTool,
    String? doorPreset,
    Object? pickStore = _keep,
  }) =>
      EditorData(
        branchId: branchId ?? this.branchId,
        branchName: branchName ?? this.branchName,
        doc: doc ?? this.doc,
        catalog: catalog ?? this.catalog,
        levelId: levelId ?? this.levelId,
        tool: tool ?? this.tool,
        featureType: featureType ?? this.featureType,
        connectorKind: connectorKind ?? this.connectorKind,
        selection: selection ?? this.selection,
        pending: pending ?? this.pending,
        saveState: saveState ?? this.saveState,
        draftVersion: draftVersion ?? this.draftVersion,
        publishedVersion: identical(publishedVersion, _keep) ? this.publishedVersion : publishedVersion as int?,
        publishProblems: publishProblems ?? this.publishProblems,
        shopperProblems: shopperProblems ?? this.shopperProblems,
        shopperWarnings: shopperWarnings ?? this.shopperWarnings,
        shopperCheckedVersion: identical(shopperCheckedVersion, _keep) ? this.shopperCheckedVersion : shopperCheckedVersion as int?,
        checkingShopper: checkingShopper ?? this.checkingShopper,
        warnings: warnings ?? this.warnings,
        versions: versions ?? this.versions,
        storeLinks: storeLinks ?? this.storeLinks,
        lock: identical(lock, _keep) ? this.lock : lock as MapLock?,
        canEdit: canEdit ?? this.canEdit,
        snap: snap ?? this.snap,
        loading: loading ?? this.loading,
        error: identical(error, _keep) ? this.error : error as String?,
        undoDepth: undoDepth ?? this.undoDepth,
        redoDepth: redoDepth ?? this.redoDepth,
        lastSavedAt: lastSavedAt ?? this.lastSavedAt,
        calibrating: calibrating ?? this.calibrating,
        calibPoints: calibPoints ?? this.calibPoints,
        proposal: identical(proposal, _keep) ? this.proposal : proposal as Proposal?,
        converting: converting ?? this.converting,
        cropping: cropping ?? this.cropping,
        cropBox: identical(cropBox, _keep) ? this.cropBox : cropBox as List<double>?,
        lastCost: identical(lastCost, _keep) ? this.lastCost : lastCost as AiCost?,
        fitRequest: fitRequest ?? this.fitRequest,
        guided: guided ?? this.guided,
        guidedStep: guidedStep ?? this.guidedStep,
        guidedTool: guidedTool ?? this.guidedTool,
        doorPreset: doorPreset ?? this.doorPreset,
        pickStore: identical(pickStore, _keep) ? this.pickStore : pickStore as StoreLink?,
      );
}

const _keep = Object();

/// All editing goes through [mutate], which snapshots for undo, marks dirty,
/// and schedules an autosave. The document itself is mutated in place.
class EditorNotifier extends Notifier<EditorData> {
  final _service = MapsService();
  final List<String> _undo = [];
  final List<String> _redo = [];
  Timer? _saveTimer;
  Timer? _lockTimer;
  bool _saveAgain = false;

  @override
  EditorData build() {
    // A different user must never inherit the previous user's map or branch.
    ref.listen(sessionProvider, (prev, next) {
      if (prev?.user?.id != next.user?.id) reset();
    });
    ref.onDispose(() {
      _saveTimer?.cancel();
      _lockTimer?.cancel();
      final id = state.branchId;
      if (id != null && (state.lock?.mine ?? false)) _service.releaseLock(id);
    });
    return const EditorData();
  }

  /// Clears everything except the catalog. Releases the lock if this user held it.
  void reset() {
    _saveTimer?.cancel();
    _lockTimer?.cancel();
    _undo.clear();
    _redo.clear();
    final id = state.branchId;
    // Offline/test documents (loadLocal) have no server lock to release.
    if (_autosave && id != null && (state.lock?.mine ?? false)) _service.releaseLock(id);
    _autosave = true;
    state = EditorData(catalog: state.catalog, guided: state.guided);
  }

  // ---- Loading ----

  Future<void> open(int branchId) async {
    _saveTimer?.cancel();
    _lockTimer?.cancel();
    _undo.clear();
    _redo.clear();
    state = EditorData(branchId: branchId, loading: true, catalog: state.catalog, guided: state.guided);
    try {
      final catalog = state.catalog ?? await _service.catalog();
      final bundle = await _service.get(branchId);
      final doc = bundle.draft == null ? null : LayoutDoc.fromJson(bundle.draft!);
      state = state.copyWith(
        loading: false,
        catalog: catalog,
        branchName: bundle.branchName,
        doc: doc,
        levelId: doc?.allLevels.firstOrNull?.id,
        draftVersion: bundle.draftVersion,
        publishedVersion: bundle.publishedVersion,
        versions: bundle.versions,
        storeLinks: bundle.storeLinks,
        warnings: bundle.warnings,
        lock: bundle.lock,
        canEdit: bundle.canEdit,
        saveState: SaveState.none,
        error: null,
      );
      if (bundle.canEdit && doc != null) await acquireLock();
    } catch (e) {
      state = state.copyWith(loading: false, error: formatApiError(e));
    }
  }

  Future<void> reload() async {
    final id = state.branchId;
    if (id != null) await open(id);
  }

  /// Creates the branch's map. With [outline] false (a map started from an
  /// uploaded plan, Round 17) the first level has no outline yet.
  Future<String?> createMap({String buildingName = 'Main building', String levelName = 'Ground floor', double width = 100, double depth = 60, bool outline = true}) async {
    final id = state.branchId;
    if (id == null) return 'No branch selected.';
    try {
      await _service.create(id, buildingName: buildingName, levelName: levelName, width: width, depth: depth, outline: outline);
      await open(id);
      return null;
    } catch (e) {
      return formatApiError(e);
    }
  }

  Future<String?> acquireLock() async {
    final id = state.branchId;
    if (id == null) return null;
    try {
      final lock = await _service.lock(id);
      state = state.copyWith(lock: lock, error: null);
      _lockTimer?.cancel();
      _lockTimer = Timer.periodic(const Duration(seconds: 60), (_) => _heartbeat());
      return null;
    } on MapLockedException catch (e) {
      state = state.copyWith(lock: null, error: e.message);
      return e.message;
    } catch (e) {
      return formatApiError(e);
    }
  }

  Future<void> _heartbeat() async {
    final id = state.branchId;
    if (id == null || !(state.lock?.mine ?? false)) return;
    try {
      final lock = await _service.lock(id);
      state = state.copyWith(lock: lock);
    } on MapLockedException {
      state = state.copyWith(lock: null, saveState: SaveState.conflict, error: 'Your editing lock expired and someone else took over. Reload to continue.');
    } catch (_) {}
  }

  /// Loads a document without the network. Used by widget tests; with
  /// [autosave] off no timers are created.
  @visibleForTesting

  /// [guided] is off by default here: most canvas tests exercise the advanced tools.
  void loadLocal(LayoutDoc doc, {MapCatalog? catalog, bool editable = true, bool autosave = false, bool guided = false}) {
    _saveTimer?.cancel();
    _lockTimer?.cancel();
    _undo.clear();
    _redo.clear();
    _autosave = autosave;
    state = EditorData(
      branchId: 0,
      branchName: 'Local',
      doc: doc,
      catalog: catalog,
      levelId: doc.allLevels.firstOrNull?.id,
      canEdit: editable,
      lock: editable ? MapLock(userId: 0, expiresAt: DateTime.now().add(const Duration(days: 1)), mine: true) : null,
      guided: guided,
    );
  }

  bool _autosave = true;

  // ---- View state ----

  void setTool(EditorTool tool) => state = state.copyWith(tool: tool, pending: const [], selection: tool == EditorTool.select ? state.selection : Selection.none);
  void setFeatureType(String type) => state = state.copyWith(featureType: type, tool: EditorTool.feature);
  void setConnectorKind(String kind) => state = state.copyWith(connectorKind: kind, tool: EditorTool.connector);
  void toggleSnap() => state = state.copyWith(snap: !state.snap);
  void select(Selection s) => state = state.copyWith(selection: s);
  void selectLevel(String id) => state = state.copyWith(levelId: id, selection: Selection.none, pending: const []);
  void setPending(List<List<double>> pts) => state = state.copyWith(pending: pts);
  void cancelPending() => state = state.copyWith(pending: const []);

  // ---- Undo / redo / mutation ----

  String _snapshot() => jsonEncode(state.doc!.toJson());

  void _restore(String json) {
    final doc = LayoutDoc.fromJson(jsonDecode(json) as Map<String, dynamic>);
    final levelId = doc.level(state.levelId) != null ? state.levelId : doc.allLevels.firstOrNull?.id;
    state = state.copyWith(doc: doc, levelId: levelId, selection: Selection.none, pending: const []);
  }

  /// Apply an edit. Returns false when the editor is read-only.
  bool mutate(void Function(LayoutDoc doc) edit, {bool snapshot = true}) {
    if (!state.editable || state.doc == null) return false;
    if (snapshot) {
      _undo.add(_snapshot());
      if (_undo.length > 100) _undo.removeAt(0);
      _redo.clear();
    }
    edit(state.doc!);
    state = state.copyWith(doc: state.doc, saveState: SaveState.dirty, undoDepth: _undo.length, redoDepth: _redo.length);
    _scheduleSave();
    return true;
  }

  /// Snapshot once at the start of a drag; then call [mutate] with snapshot: false.
  void beginDrag() {
    if (!state.editable || state.doc == null) return;
    _undo.add(_snapshot());
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
    state = state.copyWith(undoDepth: _undo.length, redoDepth: 0);
  }

  void undo() {
    if (_undo.isEmpty || !state.editable) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
    state = state.copyWith(saveState: SaveState.dirty, undoDepth: _undo.length, redoDepth: _redo.length);
    _scheduleSave();
  }

  void redo() {
    if (_redo.isEmpty || !state.editable) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
    state = state.copyWith(saveState: SaveState.dirty, undoDepth: _undo.length, redoDepth: _redo.length);
    _scheduleSave();
  }

  // ---- Saving ----

  void _scheduleSave() {
    if (!_autosave) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), save);
  }

  Future<void> save() async {
    final id = state.branchId;
    final doc = state.doc;
    if (id == null || doc == null || !state.editable) return;
    if (state.saveState == SaveState.saving) {
      _saveAgain = true;
      return;
    }
    _saveTimer?.cancel();
    state = state.copyWith(saveState: SaveState.saving, error: null);
    try {
      final r = await _service.saveDraft(id, doc, state.draftVersion);
      state = state.copyWith(
        saveState: SaveState.saved,
        draftVersion: r.draftVersion,
        publishProblems: r.publishProblems,
        warnings: r.warnings,
        lastSavedAt: DateTime.now(),
      );
      if (_saveAgain) {
        _saveAgain = false;
        state = state.copyWith(saveState: SaveState.dirty);
        _scheduleSave();
      }
    } on MapStaleException catch (e) {
      // Never retry a stale write. The only way out is a reload.
      state = state.copyWith(saveState: SaveState.conflict, error: e.message);
    } on MapProblemsException catch (e) {
      state = state.copyWith(saveState: SaveState.error, error: e.message, publishProblems: e.problems);
    } on MapLockedException catch (e) {
      state = state.copyWith(saveState: SaveState.conflict, lock: null, error: e.message);
    } catch (e) {
      state = state.copyWith(saveState: SaveState.error, error: formatApiError(e));
    }
  }

  /// Round 21: asks the server what publishing would say for the saved draft (saving first when needed).
  Future<void> checkShopper() async {
    final id = state.branchId;
    if (id == null || !state.editable || state.checkingShopper) return;
    if (state.saveState == SaveState.dirty || state.saveState == SaveState.saving) await save();
    if (state.saveState != SaveState.saved && state.saveState != SaveState.none) return;
    final version = state.draftVersion;
    state = state.copyWith(checkingShopper: true);
    try {
      final r = await _service.publishCheck(id);
      state = state.copyWith(checkingShopper: false, shopperProblems: r.problems, shopperWarnings: r.warnings, shopperCheckedVersion: version);
    } catch (_) {
      state = state.copyWith(checkingShopper: false, shopperCheckedVersion: version);
    }
  }

  Future<String?> publish({String? note}) async {
    final id = state.branchId;
    if (id == null) return 'No map open.';
    if (state.saveState == SaveState.dirty || state.saveState == SaveState.saving) await save();
    if (state.saveState != SaveState.saved && state.saveState != SaveState.none) return state.error ?? 'Save failed.';
    try {
      final (pub, draft) = await _service.publish(id, state.draftVersion, note: note);
      final bundle = await _service.get(id);
      state = state.copyWith(publishedVersion: pub, draftVersion: draft, versions: bundle.versions, publishProblems: const [], shopperProblems: const [], error: null);
      return null;
    } on MapProblemsException catch (e) {
      // Round 21: problems for shoppers come with the ids to select; the editor's own come as text.
      state = e.details.isNotEmpty ? state.copyWith(shopperProblems: e.details, shopperCheckedVersion: state.draftVersion) : state.copyWith(publishProblems: e.problems);
      return e.message;
    } catch (e) {
      return formatApiError(e);
    }
  }

  Future<String?> rollback(int version) async {
    final id = state.branchId;
    if (id == null) return 'No map open.';
    try {
      await _service.rollback(id, version);
      await open(id);
      return null;
    } catch (e) {
      return formatApiError(e);
    }
  }

  Future<String?> copyTo(int targetBranchId, {bool overwrite = false}) async {
    final id = state.branchId;
    if (id == null) return 'No map open.';
    try {
      await _service.copyTo(id, targetBranchId, overwrite: overwrite);
      return null;
    } catch (e) {
      return formatApiError(e);
    }
  }

  // ---- Edits on the current level ----

  Level? get _level => state.level;

  double _snap(double v) => state.snap ? snapTo(v, 0.1) : v;
  List<double> snapPoint(List<double> p) => [_snap(p[0]), _snap(p[1])];

  void addWall(List<double> a, List<double> b, {double t = 0.2, String kind = 'solid'}) {
    final lvl = _level;
    if (lvl == null) return;
    final id = newId('w');
    mutate((_) => lvl.walls.add(Wall(id: id, a: snapPoint(a), b: snapPoint(b), t: t, kind: kind)));
    state = state.copyWith(selection: Selection(SelKind.wall, id));
  }

  void addSpace(List<List<double>> ring, {String type = 'retail'}) {
    final lvl = _level;
    if (lvl == null || ring.length < 3) return;
    final id = newId('sp');
    mutate((_) => lvl.spaces.add(Space(id: id, type: type, shape: Poly(outer: ring.map(snapPoint).toList()))));
    state = state.copyWith(selection: Selection(SelKind.space, id), tool: EditorTool.select);
  }

  void setOutline(List<List<double>> ring) {
    final lvl = _level;
    if (lvl == null || ring.length < 3) return;
    mutate((_) => lvl.outline = Poly(outer: ring.map(snapPoint).toList(), holes: lvl.outline?.holes ?? []));
    state = state.copyWith(tool: EditorTool.select);
  }

  /// Adds a hole to the selected space, or to the level outline when nothing is selected.
  void addHole(List<List<double>> ring) {
    final lvl = _level;
    if (lvl == null || ring.length < 3) return;
    final pts = ring.map(snapPoint).toList();
    final sel = state.selection;
    mutate((_) {
      if (sel.kind == SelKind.space) {
        final s = lvl.spaces.firstWhere((x) => x.id == sel.id);
        s.shape.holes.add(pts);
      } else {
        lvl.outline ??= Poly();
        lvl.outline!.holes.add(pts);
      }
    });
    state = state.copyWith(tool: EditorTool.select);
  }

  void addOpening(String wallId, double at, {String kind = 'door', double w = 1.2}) {
    final lvl = _level;
    if (lvl == null) return;
    final id = newId('o');
    mutate((_) => lvl.openings.add(Opening(id: id, wall: wallId, at: at, kind: kind, w: w)));
    state = state.copyWith(selection: Selection(SelKind.opening, id));
  }

  void addFeature(String type, double x, double z) {
    final lvl = _level;
    if (lvl == null) return;
    final id = newId('ft');
    final p = snapPoint([x, z]);
    mutate((_) => lvl.features.add(Feature(id: id, type: type, x: p[0], z: p[1])));
    state = state.copyWith(selection: Selection(SelKind.feature, id));
  }

  /// Places a connector endpoint on the current level. With a connector selected
  /// it adds an endpoint to it; otherwise it starts a new connector.
  void addConnectorEndpoint(double x, double z) {
    final lvl = _level;
    final doc = state.doc;
    if (lvl == null || doc == null) return;
    final p = snapPoint([x, z]);
    final sel = state.selection;
    String id;
    mutate((_) {
      if (sel.kind == SelKind.connector) {
        final c = doc.connectors.firstWhere((x) => x.id == sel.id);
        c.endpoints.add(Endpoint(level: lvl.id, x: p[0], z: p[1]));
        id = c.id;
      } else {
        final c = Connector(id: newId('cn'), kind: state.connectorKind, endpoints: [Endpoint(level: lvl.id, x: p[0], z: p[1])]);
        doc.connectors.add(c);
        id = c.id;
      }
      state = state.copyWith(selection: Selection(SelKind.connector, id));
    });
  }

  void deleteSelection() {
    final lvl = _level;
    final doc = state.doc;
    final sel = state.selection;
    if (lvl == null || doc == null || sel.isEmpty) return;
    mutate((_) {
      switch (sel.kind) {
        case SelKind.wall:
          lvl.walls.removeWhere((w) => w.id == sel.id);
          // Openings die with their wall.
          lvl.openings.removeWhere((o) => o.wall == sel.id);
        case SelKind.opening:
          lvl.openings.removeWhere((o) => o.id == sel.id);
        case SelKind.space:
          lvl.spaces.removeWhere((s) => s.id == sel.id);
        case SelKind.feature:
          lvl.features.removeWhere((f) => f.id == sel.id);
        case SelKind.connector:
          doc.connectors.removeWhere((c) => c.id == sel.id);
        default:
          break;
      }
    });
    state = state.copyWith(selection: Selection.none);
  }

  /// Moves the selection by (dx, dz) metres. Openings ride along with their wall.
  void moveSelection(double dx, double dz, {bool snapshot = true}) {
    final lvl = _level;
    final doc = state.doc;
    final sel = state.selection;
    if (lvl == null || doc == null || sel.isEmpty) return;
    mutate(snapshot: snapshot, (_) {
      switch (sel.kind) {
        case SelKind.wall:
          final w = lvl.wallById(sel.id);
          if (w != null) {
            w.a = [w.a[0] + dx, w.a[1] + dz];
            w.b = [w.b[0] + dx, w.b[1] + dz];
          }
        case SelKind.space:
          final s = lvl.spaces.firstWhere((x) => x.id == sel.id);
          s.shape.outer = s.shape.outer.map((p) => [p[0] + dx, p[1] + dz]).toList();
          s.shape.holes = s.shape.holes.map((h) => h.map((p) => [p[0] + dx, p[1] + dz]).toList()).toList();
        case SelKind.feature:
          final f = lvl.features.firstWhere((x) => x.id == sel.id);
          f.x += dx;
          f.z += dz;
        case SelKind.connector:
          final c = doc.connectors.firstWhere((x) => x.id == sel.id);
          for (final e in c.endpoints.where((e) => e.level == lvl.id)) {
            e.x += dx;
            e.z += dz;
          }
        case SelKind.opening:
          final o = lvl.openings.firstWhere((x) => x.id == sel.id);
          final w = lvl.wallById(o.wall);
          if (w != null) {
            // Slide along the wall: project the moved point back onto it.
            final p = w.pointAt(o.at);
            o.at = pointToSegment(p[0] + dx, p[1] + dz, w.a, w.b).t;
          }
        default:
          break;
      }
    });
  }

  /// Moves one vertex of the selected space / outline ring.
  void moveVertex({required bool outline, required int ringIndex, required int index, required List<double> to, bool snapshot = true}) {
    final lvl = _level;
    if (lvl == null) return;
    final p = snapPoint(to);
    mutate(snapshot: snapshot, (_) {
      final poly = outline ? lvl.outline : lvl.spaces.firstWhere((s) => s.id == state.selection.id).shape;
      if (poly == null) return;
      final ring = ringIndex < 0 ? poly.outer : poly.holes[ringIndex];
      if (index >= 0 && index < ring.length) ring[index] = p;
    });
  }

  void moveWallEnd(String wallId, bool endA, List<double> to, {bool snapshot = true}) {
    final lvl = _level;
    if (lvl == null) return;
    final p = snapPoint(to);
    mutate(snapshot: snapshot, (_) {
      final w = lvl.wallById(wallId);
      if (w == null) return;
      if (endA) {
        w.a = p;
      } else {
        w.b = p;
      }
    });
  }

  /// Splits a wall at fraction [t]; openings stay on the piece they land on.
  void splitWall(String wallId, double t) {
    final lvl = _level;
    if (lvl == null) return;
    mutate((_) {
      final w = lvl.wallById(wallId);
      if (w == null || t <= 0.01 || t >= 0.99) return;
      final mid = w.pointAt(t);
      final second = Wall(id: newId('w'), a: mid, b: w.b, t: w.t, kind: w.kind);
      w.b = mid;
      lvl.walls.insert(lvl.walls.indexOf(w) + 1, second);
      for (final o in lvl.openings.where((o) => o.wall == wallId).toList()) {
        if (o.at > t) {
          o.wall = second.id;
          o.at = (o.at - t) / (1 - t);
        } else {
          o.at = o.at / t;
        }
      }
    });
  }

  // ---- Backdrop (uploaded floor plan) ----

  /// Places an uploaded plan under the current level, centred on its outline (or
  /// a 100 × 60 m area). A drawing with a known unit is placed at its exact scale
  /// (Round 16); a picture is scaled to fit and then calibrated by hand.
  void placeBackdrop(BackdropInfo info) {
    final lvl = _level;
    if (lvl == null) return;
    final box = lvl.outline != null && lvl.outline!.outer.length >= 3 ? ringBounds(lvl.outline!.outer) : const Rect.fromLTWH(0, 0, 100, 60);
    final mpp = info.mpp ?? math.min(box.width / info.width, box.height / info.height);
    mutate((_) => lvl.backdrop = Backdrop(id: info.id, cx: box.center.dx, cz: box.center.dy, mpp: (mpp * 1e7).round() / 1e7, calibrated: info.mpp != null));
    state = state.copyWith(selection: Selection.none);
  }

  void updateBackdrop(void Function(Backdrop b) fn) {
    final lvl = _level;
    if (lvl?.backdrop == null) return;
    mutate((_) => fn(lvl!.backdrop!));
  }

  void removeBackdrop() {
    final lvl = _level;
    if (lvl?.backdrop == null) return;
    mutate((_) => lvl!.backdrop = null);
    state = state.copyWith(calibrating: false, calibPoints: const [], proposal: null, cropping: false, cropBox: null);
  }

  /// Sets the level outline to the image rectangle. Offered only while nothing is drawn.
  void fitOutlineToBackdrop(int widthPx, int heightPx) {
    final lvl = _level;
    final b = lvl?.backdrop;
    if (lvl == null || b == null) return;
    final hw = widthPx * b.mpp / 2;
    final hd = heightPx * b.mpp / 2;
    final rad = b.rot * math.pi / 180;
    List<double> corner(double x, double z) => [b.cx + x * math.cos(rad) - z * math.sin(rad), b.cz + x * math.sin(rad) + z * math.cos(rad)];
    mutate((_) => lvl.outline = Poly(outer: [corner(-hw, -hd), corner(hw, -hd), corner(hw, hd), corner(-hw, hd)]));
  }

  /// Asks the canvas to frame the level and its plan again.
  void requestFit() => state = state.copyWith(fitRequest: state.fitRequest + 1);

  // ---- The easy editor (Round 18) ----

  void setGuided(bool on) => state = state.copyWith(guided: on, guidedTool: GuidedTool.none, pickStore: null, tool: EditorTool.select, pending: const []);
  void setGuidedStep(int step) => state = state.copyWith(guidedStep: step.clamp(0, 4), guidedTool: GuidedTool.none, pickStore: null, pending: const [], calibrating: false, cropping: false);
  void setGuidedTool(GuidedTool tool) => state = state.copyWith(guidedTool: tool, pending: const [], pickStore: tool == GuidedTool.pickStore ? state.pickStore : null);
  void setDoorPreset(String name) => state = state.copyWith(doorPreset: name, guidedTool: GuidedTool.addDoor);
  void cancelGuidedTool() => state = state.copyWith(guidedTool: GuidedTool.none, pending: const [], pickStore: null);

  /// "Pick a store, then click its room."
  void startPlacingStore(StoreLink store) => state = state.copyWith(guidedTool: GuidedTool.pickStore, pickStore: store, pending: const []);

  /// Renames a room (one undo step).
  void renameSpace(String id, String name) {
    final lvl = _level;
    final s = lvl?.spaces.cast<Space?>().firstWhere((x) => x!.id == id, orElse: () => null);
    if (s == null || s.name == name.trim()) return;
    mutate((_) => s.name = name.trim());
  }

  /// Sets a room's type (one undo step).
  void setSpaceType(String id, String type) {
    final lvl = _level;
    final s = lvl?.spaces.cast<Space?>().firstWhere((x) => x!.id == id, orElse: () => null);
    if (s == null || s.type == type) return;
    mutate((_) => s.type = type);
  }

  /// Adds a wall between two clicks: ends snap to nearby walls, and a nearly
  /// straight wall is made straight, so it can never come out crooked.
  void addSnappedWall(List<double> a, List<double> b) {
    final lvl = _level;
    if (lvl == null) return;
    final sa = snapToWalls(a, lvl.walls);
    var sb = snapToWalls(b, lvl.walls);
    final straight = straighten(sa, sb);
    if (straight[0] != sb[0] || straight[1] != sb[1]) sb = snapToWalls(straight, lvl.walls, tol: 0.15);
    if (math.sqrt(math.pow(sb[0] - sa[0], 2) + math.pow(sb[1] - sa[1], 2)) < 0.3) return;
    final id = newId('w');
    mutate((_) => lvl.walls.add(Wall(id: id, a: sa, b: sb, t: 0.15, kind: 'solid')));
    state = state.copyWith(selection: Selection(SelKind.wall, id), guidedTool: GuidedTool.none, pending: const []);
  }

  /// Puts a door (or entrance, shop front) of the chosen width on a wall, where clicked.
  /// Returns a message when it does not fit.
  String? addDoorAt(String wallId, double t) {
    final lvl = _level;
    final w = lvl?.wallById(wallId);
    if (lvl == null || w == null) return null;
    final (kind, width) = doorPresets[state.doorPreset] ?? ('door', 0.9);
    if (width > w.length - 0.05) return 'This wall is too short for a ${state.doorPreset.toLowerCase()} (${width.toStringAsFixed(1)} m).';
    final half = width / 2 / w.length;
    final at = t.clamp(half, 1 - half);
    final id = newId('o');
    mutate((_) => lvl.openings.add(Opening(id: id, wall: wallId, at: at, kind: kind, w: width)));
    state = state.copyWith(selection: Selection(SelKind.opening, id), guidedTool: GuidedTool.none);
    return null;
  }

  /// Splits a room with a straight line from [p] to [q]; a wall is placed on the cut.
  /// Returns a message when the line does not cut the room in two.
  String? splitSpace(String id, List<double> p, List<double> q) {
    final lvl = _level;
    final s = lvl?.spaces.cast<Space?>().firstWhere((x) => x!.id == id, orElse: () => null);
    if (lvl == null || s == null) return null;
    final q2 = straighten(p, q);
    final parts = splitRing(s.shape.outer, p, q2);
    final cut = chord(s.shape.outer, p, q2);
    if (parts == null || cut == null) return 'Draw the line right across the room, from one side to the other.';
    final newRoom = newId('sp');
    final wall = newId('w');
    mutate((_) {
      s.shape = Poly(outer: parts.$1);
      lvl.spaces.insert(lvl.spaces.indexOf(s) + 1, Space(id: newRoom, type: s.type, shape: Poly(outer: parts.$2)));
      lvl.walls.add(Wall(id: wall, a: cut.$1, b: cut.$2, t: 0.1, kind: 'partition'));
    });
    state = state.copyWith(selection: Selection(SelKind.space, newRoom), guidedTool: GuidedTool.none, pending: const []);
    return null;
  }

  /// Joins two neighbouring rooms into one. The wall between them goes too,
  /// unless another room uses it. Returns a message when they do not touch.
  String? mergeSpaces(String keepId, String otherId) {
    final lvl = _level;
    if (lvl == null || keepId == otherId) return null;
    final a = lvl.spaces.cast<Space?>().firstWhere((x) => x!.id == keepId, orElse: () => null);
    final b = lvl.spaces.cast<Space?>().firstWhere((x) => x!.id == otherId, orElse: () => null);
    if (a == null || b == null) return null;
    final ring = unionRings(a.shape.outer, b.shape.outer);
    if (ring == null || ring.length < 3) return 'These two rooms do not touch. Pick a room right next to it.';
    final merged = Poly(outer: ring);
    // Walls inside the merged room that no other room borders.
    final others = lvl.spaces.where((x) => x.id != keepId && x.id != otherId).toList();
    bool insideOther(double x, double z) => others.any((o) => pointInPoly(x, z, o.shape));
    final gone = <String>{};
    for (final w in lvl.walls) {
      final m = w.pointAt(0.5);
      if (!pointInPoly(m[0], m[1], merged)) continue;
      final dx = w.b[0] - w.a[0], dz = w.b[1] - w.a[1];
      final len = w.length == 0 ? 1.0 : w.length;
      final off = w.t / 2 + 0.15;
      final nx = -dz / len * off, nz = dx / len * off;
      if (insideOther(m[0] + nx, m[1] + nz) || insideOther(m[0] - nx, m[1] - nz)) continue;
      // Only a wall the two rooms share: room on one side and the other room on the other.
      final sideA = pointInPoly(m[0] + nx, m[1] + nz, a.shape) || pointInPoly(m[0] + nx, m[1] + nz, b.shape);
      final sideB = pointInPoly(m[0] - nx, m[1] - nz, a.shape) || pointInPoly(m[0] - nx, m[1] - nz, b.shape);
      if (sideA && sideB) gone.add(w.id);
    }
    mutate((_) {
      a.shape = merged;
      if (a.name.isEmpty) a.name = b.name;
      lvl.spaces.remove(b);
      lvl.walls.removeWhere((w) => gone.contains(w.id));
      lvl.openings.removeWhere((o) => gone.contains(o.wall));
    });
    state = state.copyWith(selection: Selection(SelKind.space, keepId), guidedTool: GuidedTool.none);
    return null;
  }

  /// Links a store to a room (store ↔ space links live outside the map, so the
  /// draft is saved first and the link is not part of Undo).
  Future<String?> linkStore(StoreLink store, String spaceId) async {
    state = state.copyWith(guidedTool: GuidedTool.none, pickStore: null);
    if (state.saveState == SaveState.dirty || state.saveState == SaveState.saving) await save();
    if (state.saveState == SaveState.error || state.saveState == SaveState.conflict) return state.error ?? 'Save the map first.';
    try {
      await _service.linkStoreToSpace(store.storeId, spaceId);
      state = state.copyWith(storeLinks: [...state.storeLinks, StoreLink(spaceKey: spaceId, storeId: store.storeId, storeName: store.storeName)]);
      return null;
    } catch (e) {
      return formatApiError(e);
    }
  }

  void startCalibration() => state = state.copyWith(calibrating: true, calibPoints: const [], tool: EditorTool.select, pending: const [], selection: Selection.none, cropping: false);
  void cancelCalibration() => state = state.copyWith(calibrating: false, calibPoints: const []);

  /// Records a calibration click (level coordinates). Two clicks are needed.
  void addCalibrationPoint(List<double> p) {
    if (!state.calibrating) return;
    final pts = [...state.calibPoints, p];
    state = state.copyWith(calibPoints: pts.length > 2 ? [p] : pts);
  }

  /// Rescales the backdrop so the two clicked points are [metres] apart. The first point stays put.
  String? applyCalibration(double metres) {
    final lvl = _level;
    final b = lvl?.backdrop;
    final pts = state.calibPoints;
    if (lvl == null || b == null || pts.length != 2) return 'Click two points first.';
    final clicked = math.sqrt(math.pow(pts[1][0] - pts[0][0], 2) + math.pow(pts[1][1] - pts[0][1], 2));
    if (clicked < 0.01 || metres <= 0) return 'The two points are too close together.';
    final k = metres / clicked;
    final newMpp = b.mpp * k;
    if (newMpp < 0.0001 || newMpp > 1) return 'That scale is outside the allowed range. Check the distance you typed.';
    mutate((_) {
      // Scale about the first point so it does not move.
      b.cx = pts[0][0] + (b.cx - pts[0][0]) * k;
      b.cz = pts[0][1] + (b.cz - pts[0][1]) * k;
      b.mpp = (newMpp * 1e7).round() / 1e7;
      b.calibrated = true;
    });
    state = state.copyWith(calibrating: false, calibPoints: const []);
    return null;
  }

  // ---- AI reading (Round 15) ----

  /// Box mode: the next drag on the canvas marks the part of the plan to read.
  void startCrop() => state = state.copyWith(cropping: true, calibrating: false, calibPoints: const [], tool: EditorTool.select, pending: const [], selection: Selection.none);
  void cancelCrop() => state = state.copyWith(cropping: false);

  /// Sets (or clears) the box to read, in fractions of the plan picture.
  void setCropBox(List<double>? box) {
    if (box == null) {
      state = state.copyWith(cropping: false, cropBox: null);
      return;
    }
    final x0 = math.min(box[0], box[2]).clamp(0.0, 1.0);
    final y0 = math.min(box[1], box[3]).clamp(0.0, 1.0);
    final x1 = math.max(box[0], box[2]).clamp(0.0, 1.0);
    final y1 = math.max(box[1], box[3]).clamp(0.0, 1.0);
    // A click without a drag, or a box off the picture, reads nothing.
    final tooSmall = x1 - x0 < 0.02 || y1 - y0 < 0.02;
    state = state.copyWith(cropping: false, cropBox: tooSmall ? null : [x0, y0, x1, y1]);
  }

  /// Reads the plan (or the boxed part) with AI. With [addToProposal] the result
  /// joins the proposal already on screen, so a large plan can be read in sections.
  Future<String?> convertBackdrop({bool addToProposal = false}) async {
    final id = state.branchId;
    final lvl = _level;
    final b = lvl?.backdrop;
    if (id == null || lvl == null || b == null) return 'Place a plan on this level first.';
    if (state.saveState == SaveState.dirty || state.saveState == SaveState.saving) await save();
    if (state.saveState == SaveState.conflict || state.saveState == SaveState.error) return state.error ?? 'Save the draft first.';
    final current = state.proposal;
    final merging = addToProposal && current != null && current.levelId == lvl.id;
    state = state.copyWith(converting: true, proposal: merging ? current : null, error: null);
    try {
      final p = await _service.convert(id, b.id, lvl.id, crop: state.cropBox);
      // Round 18: the AI read the plan's scale from a dimension on it; the plan
      // takes that scale (its own undo step) so it lines up with the proposal.
      final found = p.scaleFound;
      if (found != null && lvl.backdrop?.id == b.id) {
        mutate((_) {
          b.mpp = found.mpp;
          b.calibrated = true;
        });
      }
      state = state.copyWith(converting: false, proposal: merging ? current.merge(p) : p, lastCost: p.cost);
      return null;
    } catch (e) {
      state = state.copyWith(converting: false);
      return formatApiError(e);
    }
  }

  void discardProposal() => state = state.copyWith(proposal: null);

  /// Puts a proposal on screen without a reading (tests and the layout sweep).
  @visibleForTesting
  void debugSetProposal(Proposal? p) => state = state.copyWith(proposal: p);

  void removeProposalItem(String id) {
    final p = state.proposal;
    if (p == null) return;
    state = state.copyWith(proposal: p.without({id}));
  }

  /// Adds the proposal to its level as ONE undo step. Ids are regenerated if
  /// they collide. The outline replaces the level's outline only when asked.
  /// With [linkStores] the matched stores are linked to their new spaces once
  /// the draft is saved (links live outside the map, so Undo does not remove
  /// them). Returns a message when linking failed, else null.
  Future<String?> acceptProposal({bool walls = true, bool openings = true, bool spaces = true, bool outline = false, bool linkStores = false}) async {
    final p = state.proposal;
    final doc = state.doc;
    if (p == null || doc == null) return null;
    final lvl = doc.level(p.levelId);
    if (lvl == null) return null;
    final taken = <String>{};
    for (final l in doc.allLevels) {
      taken.addAll(l.walls.map((w) => w.id));
      taken.addAll(l.openings.map((o) => o.id));
      taken.addAll(l.spaces.map((s) => s.id));
    }
    final wallIds = <String, String>{};
    final spaceIds = <String, String>{};
    final applied = mutate((_) {
      if (walls) {
        for (final w in p.walls) {
          final id = taken.contains(w.id) ? newId('w') : w.id;
          wallIds[w.id] = id;
          lvl.walls.add(Wall(id: id, a: [...w.a], b: [...w.b], t: w.t, kind: w.kind));
        }
        if (openings) {
          for (final o in p.openings) {
            final wid = wallIds[o.wall];
            if (wid == null) continue;
            lvl.openings.add(Opening(id: taken.contains(o.id) ? newId('o') : o.id, wall: wid, at: o.at, w: o.w, kind: o.kind));
          }
        }
      }
      if (spaces) {
        for (final s in p.spaces) {
          final id = taken.contains(s.id) ? newId('sp') : s.id;
          spaceIds[s.id] = id;
          lvl.spaces.add(Space(id: id, name: s.name, type: s.type, shape: Poly(outer: s.shape.outer.map((pt) => [...pt]).toList())));
        }
      }
      if (outline && p.outline != null) {
        lvl.outline = Poly(outer: p.outline!.outer.map((pt) => [...pt]).toList());
      }
    });
    if (!applied) return null;
    state = state.copyWith(proposal: null, levelId: lvl.id);

    final matches = [
      for (final m in p.storeMatches)
        if (spaceIds[m.spaceId] != null) m.withSpace(spaceIds[m.spaceId]!),
    ];
    if (!linkStores || matches.isEmpty) return null;
    // Links point at space ids in the saved draft, so save first.
    await save();
    if (state.saveState != SaveState.saved) return 'The rooms were added, but the stores were not linked because the draft did not save. Link them from each store page.';
    final linked = <StoreLink>[];
    final failed = <String>[];
    for (final m in matches) {
      try {
        await _service.linkStoreToSpace(m.storeId, m.spaceId);
        linked.add(StoreLink(spaceKey: m.spaceId, storeId: m.storeId, storeName: m.storeName));
      } catch (_) {
        failed.add(m.storeName);
      }
    }
    if (linked.isNotEmpty) state = state.copyWith(storeLinks: [...state.storeLinks, ...linked]);
    return failed.isEmpty ? null : 'These stores could not be linked: ${failed.join(', ')}. Link them from each store page.';
  }

  // ---- Structure ----

  void addLevel(String buildingId, {String name = 'New level', double? elevation}) {
    final doc = state.doc;
    if (doc == null) return;
    final b = doc.building(buildingId);
    if (b == null) return;
    final id = newId('lv');
    mutate((_) {
      final last = b.levels.lastOrNull;
      b.levels.add(Level(
        id: id,
        name: name,
        elevation: elevation ?? ((last?.elevation ?? 0) + (last?.height ?? 4)),
        height: last?.height ?? 4,
        outline: last?.outline == null ? null : Poly.fromJson(last!.outline!.toJson()),
      ));
    });
    state = state.copyWith(levelId: id, selection: Selection(SelKind.level, id));
  }

  void addBuilding({String name = 'New building', List<double>? origin}) {
    final doc = state.doc;
    if (doc == null) return;
    final bid = newId('bd');
    final lid = newId('lv');
    mutate((_) {
      doc.buildings.add(Building(id: bid, name: name, origin: origin ?? [0, 0], levels: [
        Level(
            id: lid,
            name: 'Ground floor',
            outline: Poly(outer: [
              [0, 0],
              [40, 0],
              [40, 30],
              [0, 30]
            ])),
      ]));
    });
    state = state.copyWith(levelId: lid, selection: Selection(SelKind.building, bid));
  }

  void deleteLevel(String levelId) {
    final doc = state.doc;
    if (doc == null) return;
    final b = doc.buildingOfLevel(levelId);
    if (b == null || doc.allLevels.length <= 1) return;
    mutate((_) {
      b.levels.removeWhere((l) => l.id == levelId);
      for (final c in doc.connectors) {
        c.endpoints.removeWhere((e) => e.level == levelId);
      }
      doc.connectors.removeWhere((c) => c.endpoints.length < 2);
    });
    state = state.copyWith(levelId: doc.allLevels.first.id, selection: Selection.none);
  }

  void deleteBuilding(String buildingId) {
    final doc = state.doc;
    if (doc == null || doc.buildings.length <= 1) return;
    mutate((_) {
      final b = doc.building(buildingId);
      if (b == null) return;
      final ids = b.levels.map((l) => l.id).toSet();
      doc.buildings.remove(b);
      for (final c in doc.connectors) {
        c.endpoints.removeWhere((e) => ids.contains(e.level));
      }
      doc.connectors.removeWhere((c) => c.endpoints.length < 2);
    });
    state = state.copyWith(levelId: doc.allLevels.first.id, selection: Selection.none);
  }

  /// Generic property edit on the selected element.
  void edit(void Function(LayoutDoc doc, Level? level) fn) => mutate((doc) => fn(doc, _level));

  void setError(String? message) => state = state.copyWith(error: message);

  /// Read-only view of the published map (supervisor map viewer).
  Future<void> openPublished(int branchId) async {
    _saveTimer?.cancel();
    _lockTimer?.cancel();
    _undo.clear();
    _redo.clear();
    state = EditorData(branchId: branchId, loading: true, catalog: state.catalog);
    try {
      final catalog = state.catalog ?? await _service.catalog();
      final bundle = await _service.get(branchId);
      final pub = await _service.published(branchId);
      state = state.copyWith(
        loading: false,
        catalog: catalog,
        branchName: bundle.branchName,
        doc: pub?.$1,
        levelId: pub?.$1.allLevels.firstOrNull?.id,
        publishedVersion: pub?.$2,
        versions: bundle.versions,
        storeLinks: bundle.storeLinks,
        canEdit: false,
        lock: null,
        saveState: SaveState.none,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: formatApiError(e));
    }
  }

  /// Selects an element anywhere in the document by id, switching level if needed.
  void selectById(String id) {
    final doc = state.doc;
    if (doc == null) return;
    for (final b in doc.buildings) {
      if (b.id == id) {
        state = state.copyWith(levelId: b.levels.firstOrNull?.id ?? state.levelId, selection: Selection(SelKind.building, id));
        return;
      }
      for (final l in b.levels) {
        if (l.id == id) {
          state = state.copyWith(levelId: l.id, selection: Selection(SelKind.level, id));
          return;
        }
        SelKind? kind;
        if (l.walls.any((w) => w.id == id)) kind = SelKind.wall;
        if (l.openings.any((o) => o.id == id)) kind = SelKind.opening;
        if (l.spaces.any((s) => s.id == id)) kind = SelKind.space;
        if (l.features.any((f) => f.id == id)) kind = SelKind.feature;
        if (kind != null) {
          state = state.copyWith(levelId: l.id, selection: Selection(kind, id));
          return;
        }
      }
    }
    if (doc.connectors.any((c) => c.id == id)) {
      final c = doc.connectors.firstWhere((c) => c.id == id);
      final lvl = c.endpoints.any((e) => e.level == state.levelId) ? state.levelId : c.endpoints.firstOrNull?.level;
      state = state.copyWith(levelId: lvl ?? state.levelId, selection: Selection(SelKind.connector, id));
    }
  }
}

final editorProvider = NotifierProvider<EditorNotifier, EditorData>(EditorNotifier.new);

final mapListProvider = FutureProvider.autoDispose<List<MapStatus>>((ref) => MapsService().list());

@visibleForTesting
String debugDump(EditorData d) => d.doc == null ? '' : jsonEncode(d.doc!.toJson());

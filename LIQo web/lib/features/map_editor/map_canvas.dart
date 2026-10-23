import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../shared/messaging/messages.dart';
import 'editor_state.dart';
import 'guided/geometry.dart';
import 'map_models.dart';
import 'maps_service.dart';
import 'plan_image.dart';

/// Top-down 2D canvas. Draws the current level and routes pointer input to the
/// active tool. Right or middle drag pans, wheel zooms at the pointer.
class MapCanvas extends ConsumerStatefulWidget {
  const MapCanvas({super.key});

  @override
  ConsumerState<MapCanvas> createState() => MapCanvasState();
}

enum DragKind { none, pan, move, vertex, wallEnd }

/// Pointer state machine for the canvas.
///
/// Button handling is deliberately defensive. On the web the engine can keep a
/// mouse button marked as "held" after a release it never saw (release outside
/// the window, or swallowed by the browser). So:
///   - the left button present in `buttons` always means a primary action,
///     whatever other bits are set;
///   - pan needs right or middle held AND left not held;
///   - pan ends on pointer-up, pointer-cancel, any hover (no buttons), any move
///     without pan buttons, any new left press, and Escape;
///   - taps and double-taps are detected here from down/up, not by the gesture
///     arena, which rejects presses with mixed buttons.
class MapCanvasState extends ConsumerState<MapCanvas> with SingleTickerProviderStateMixin {
  double _scale = 8; // px per metre
  Offset _origin = const Offset(40, 40); // screen position of level (0,0)
  String? _fittedLevel;
  int _fittedRequest = 0;
  final _focus = FocusNode();

  Offset? _hover;
  DragKind _drag = DragKind.none;
  Offset _dragLast = Offset.zero;
  List<double>? _dragStartPoint;
  bool _vOutline = false;
  int _vRing = -1;
  int _vIndex = -1;
  String? _wallId;
  bool _wallEndA = true;

  // Tap detection
  Offset? _downPos;
  bool _downPrimary = false;
  bool _moved = false;
  bool _dragSnapshotTaken = false;
  DateTime? _lastTapAt;
  Offset? _lastTapPos;

  // Easy editor (Round 18): a left drag pans the map; nothing else moves.
  bool _guidedPan = false;

  // Box mode (AI reading of a part of the plan): screen points of the drag.
  Offset? _boxStart;
  Offset? _boxEnd;

  // Backdrop images by upload key. Fetched with the session token, decoded once.
  final Map<String, ui.Image> _images = {};
  final Set<String> _loadingImages = {};

  /// The real pixel size of each plan (the decoded picture may be smaller).
  final Map<String, Size> _imageSizes = {};

  /// The plan's real pixel size, for every measurement (tests may set one).
  Size? _pictureSize(String? key) => (key == null ? null : _imageSizes[key]) ?? debugPictureSize;

  void _ensureImage(int branchId, String key) {
    if (_images.containsKey(key) || _loadingImages.contains(key)) return;
    _loadingImages.add(key);
    MapsService().backdropBytes(branchId, key).then((bytes) async {
      // Decoded once at screen size; the real pixel size is kept for measuring.
      final plan = await PlanImage.decode(bytes);
      if (!mounted) return;
      setState(() {
        _images[key] = plan.image;
        _imageSizes[key] = plan.original;
        // The plan's size is known now: frame it again if the level is still empty.
        final lvl = ref.read(editorProvider).level;
        if (lvl?.backdrop?.id == key && lvl!.walls.isEmpty && lvl.spaces.isEmpty && lvl.outline == null) _fittedLevel = null;
      });
    }).catchError((_) {
      if (mounted) _loadingImages.remove(key);
    });
  }

  static const _tapSlop = 5.0;
  static const _doubleTapWindow = Duration(milliseconds: 350);

  @visibleForTesting
  Offset get debugOrigin => _origin;
  @visibleForTesting
  double get debugScale => _scale;
  @visibleForTesting
  DragKind get debugDrag => _drag;

  /// Test hook: the picture size used for box mode when no image is loaded.
  @visibleForTesting
  Size? debugPictureSize;

  /// Turns the dragged screen box into a box of the plan picture (fractions).
  void _finishBox(EditorData st, EditorNotifier n) {
    final start = _boxStart;
    final end = _boxEnd;
    setState(() {
      _boxStart = null;
      _boxEnd = null;
    });
    final bd = st.level?.backdrop;
    if (start == null || end == null || bd == null) return;
    final size = _pictureSize(bd.id);
    final w = size?.width.round();
    final h = size?.height.round();
    if (w == null || h == null) {
      n.setError('The plan picture is still loading. Try again in a moment.');
      return;
    }
    final a = toLevel(start);
    final b = toLevel(end);
    n.setCropBox(bd.boxFor([math.min(a[0], b[0]), math.min(a[1], b[1])], [math.max(a[0], b[0]), math.max(a[1], b[1])], w, h));
  }

  // Round 17: a new AI proposal draws itself in (about 0.9 s; at once with reduced motion).
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), value: 1);
  Proposal? _shownProposal;
  Set<String> _revealIds = const {};

  static Set<String> _idsOf(Proposal p) => {...p.walls.map((w) => w.id), ...p.openings.map((o) => o.id), ...p.spaces.map((s) => s.id)};

  /// Starts the draw-in for pieces that were not on screen before (a merged
  /// section animates only its new pieces; dropping a piece animates nothing).
  void _watchProposal(Proposal? next, bool reduceMotion) {
    if (identical(next, _shownProposal)) return;
    final before = _shownProposal == null ? const <String>{} : _idsOf(_shownProposal!);
    _shownProposal = next;
    if (next == null) {
      _revealIds = const {};
      return;
    }
    final fresh = _idsOf(next).difference(before);
    if (fresh.isEmpty || reduceMotion) {
      _revealIds = const {};
      _reveal.value = 1;
      return;
    }
    _revealIds = fresh;
    _reveal.forward(from: 0);
  }

  @visibleForTesting
  double get debugReveal => _reveal.value;

  @override
  void dispose() {
    _reveal.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- button helpers ----

  static bool _hasPrimary(int b) => (b & kPrimaryMouseButton) != 0;
  static bool _panButtons(int b) => (b & (kSecondaryMouseButton | kMiddleMouseButton)) != 0 && !_hasPrimary(b);

  // ---- transforms ----

  List<double> toLevel(Offset p) => [(p.dx - _origin.dx) / _scale, (p.dy - _origin.dy) / _scale];

  /// Frames the level; a placed plan is framed too (Round 17: a map started
  /// from an upload has nothing else on it yet).
  void _fit(Level level, Size size) {
    var b = level.bounds();
    final bd = level.backdrop;
    final picture = bd == null ? null : _pictureSize(bd.id);
    final pw = picture?.width.round();
    final ph = picture?.height.round();
    if (bd != null && pw != null && ph != null) {
      final corners = [bd.toLevel(0, 0, pw, ph), bd.toLevel(pw.toDouble(), 0, pw, ph), bd.toLevel(pw.toDouble(), ph.toDouble(), pw, ph), bd.toLevel(0, ph.toDouble(), pw, ph)];
      final pr = ringBounds(corners);
      final empty = level.walls.isEmpty && level.spaces.isEmpty && level.features.isEmpty && level.outline == null;
      b = empty ? pr : b.expandToInclude(pr);
    }
    final w = math.max(b.width, 10.0);
    final h = math.max(b.height, 10.0);
    _scale = math.min((size.width - 80) / w, (size.height - 80) / h).clamp(1.0, 200.0);
    _origin = Offset(40 - b.left * _scale + ((size.width - 80) - w * _scale) / 2, 40 - b.top * _scale + ((size.height - 80) - h * _scale) / 2);
  }

  // ---- hit testing ----

  Selection _hit(Level level, LayoutDoc doc, List<double> p) {
    final tol = 8 / _scale;
    for (final f in level.features.reversed) {
      if ((f.x - p[0]).abs() < math.max(tol, (f.w ?? 1) / 2) && (f.z - p[1]).abs() < math.max(tol, (f.d ?? 1) / 2)) return Selection(SelKind.feature, f.id);
    }
    for (final c in doc.connectors) {
      for (final e in c.endpoints.where((e) => e.level == level.id)) {
        if ((e.x - p[0]).abs() < math.max(tol, e.w / 2) && (e.z - p[1]).abs() < math.max(tol, e.len / 2)) return Selection(SelKind.connector, c.id);
      }
    }
    for (final o in level.openings) {
      final w = level.wallById(o.wall);
      if (w == null) continue;
      final c = w.pointAt(o.at);
      if (math.sqrt(math.pow(c[0] - p[0], 2) + math.pow(c[1] - p[1], 2)) < math.max(tol, o.w / 2)) return Selection(SelKind.opening, o.id);
    }
    for (final w in level.walls.reversed) {
      if (pointToSegment(p[0], p[1], w.a, w.b).dist < math.max(tol, w.t)) return Selection(SelKind.wall, w.id);
    }
    for (final s in level.spaces.reversed) {
      if (pointInPoly(p[0], p[1], s.shape)) return Selection(SelKind.space, s.id);
    }
    return Selection.none;
  }

  ({bool outline, int ring, int index})? _hitVertex(Level level, Selection sel, List<double> p) {
    final tol = 7 / _scale;
    Poly? poly;
    var outline = false;
    if (sel.kind == SelKind.space) {
      poly = level.spaces.cast<Space?>().firstWhere((s) => s!.id == sel.id, orElse: () => null)?.shape;
    } else if (sel.kind == SelKind.level) {
      poly = level.outline;
      outline = true;
    }
    if (poly == null) return null;
    for (var i = 0; i < poly.outer.length; i++) {
      if ((poly.outer[i][0] - p[0]).abs() < tol && (poly.outer[i][1] - p[1]).abs() < tol) return (outline: outline, ring: -1, index: i);
    }
    for (var r = 0; r < poly.holes.length; r++) {
      for (var i = 0; i < poly.holes[r].length; i++) {
        if ((poly.holes[r][i][0] - p[0]).abs() < tol && (poly.holes[r][i][1] - p[1]).abs() < tol) return (outline: outline, ring: r, index: i);
      }
    }
    return null;
  }

  Wall? _hitWallNear(Level level, List<double> p) {
    final tol = 10 / _scale;
    Wall? best;
    var bestD = tol;
    for (final w in level.walls) {
      final d = pointToSegment(p[0], p[1], w.a, w.b).dist;
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    return best;
  }

  String? _hitProposal(Proposal prop, List<double> p) {
    final tol = 8 / _scale;
    for (final o in prop.openings) {
      final w = prop.walls.cast<Wall?>().firstWhere((x) => x!.id == o.wall, orElse: () => null);
      if (w == null) continue;
      final c = w.pointAt(o.at);
      if (math.sqrt(math.pow(c[0] - p[0], 2) + math.pow(c[1] - p[1], 2)) < math.max(tol, o.w / 2)) return o.id;
    }
    for (final w in prop.walls) {
      if (pointToSegment(p[0], p[1], w.a, w.b).dist < math.max(tol, w.t)) return w.id;
    }
    for (final s in prop.spaces) {
      if (pointInPoly(p[0], p[1], s.shape)) return s.id;
    }
    return null;
  }

  List<double> _snapToWallEnds(Level level, List<double> p) {
    final tol = 12 / _scale;
    for (final w in level.walls) {
      for (final e in [w.a, w.b]) {
        if ((e[0] - p[0]).abs() < tol && (e[1] - p[1]).abs() < tol) return [e[0], e[1]];
      }
    }
    return p;
  }

  bool _near(List<double> a, List<double> b) => (a[0] - b[0]).abs() < 10 / _scale && (a[1] - b[1]).abs() < 10 / _scale;

  // ---- taps ----

  void _tap(Offset pos, EditorData st, EditorNotifier n) {
    final level = st.level;
    final doc = st.doc;
    if (level == null || doc == null) return;
    var p = toLevel(pos);
    if (st.calibrating) {
      // Raw point, no snapping: the user is pointing at ink on the picture.
      n.addCalibrationPoint(p);
      return;
    }
    if (!st.editable && st.tool != EditorTool.select) return;

    switch (st.tool) {
      case EditorTool.select:
        final prop = st.proposal;
        if (prop != null && prop.levelId == level.id) {
          // A click on a proposed piece drops it from the proposal (never from the map).
          final hitId = _hitProposal(prop, p);
          if (hitId != null) {
            n.removeProposalItem(hitId);
            return;
          }
        }
        n.select(_hit(level, doc, p));
      case EditorTool.wall:
        p = _snapToWallEnds(level, n.snapPoint(p));
        if (st.pending.isEmpty) {
          n.setPending([p]);
        } else {
          final last = st.pending.last;
          // Clicking the last point again ends the chain (this is what a double-click does).
          if (_near(last, p)) {
            n.cancelPending();
            return;
          }
          final end = HardwareKeyboard.instance.isShiftPressed || !st.snap ? p : snapAngle(last, p);
          n.addWall(last, end);
          n.setPending([end]);
        }
      case EditorTool.space:
      case EditorTool.hole:
      case EditorTool.outline:
        p = n.snapPoint(p);
        final pts = st.pending;
        // Clicking the first point, or the last point again, closes the shape.
        if (pts.length >= 3 && (_near(pts.first, p) || _near(pts.last, p))) {
          _closePolygon(st, n);
          return;
        }
        if (pts.isNotEmpty && _near(pts.last, p)) return; // ignore a duplicate click
        n.setPending([...pts, p]);
      case EditorTool.opening:
        final w = _hitWallNear(level, p);
        if (w == null) {
          n.setError('Click on a wall to place an opening.');
          return;
        }
        n.addOpening(w.id, pointToSegment(p[0], p[1], w.a, w.b).t);
      case EditorTool.feature:
        n.addFeature(st.featureType, p[0], p[1]);
      case EditorTool.connector:
        n.addConnectorEndpoint(p[0], p[1]);
    }
  }

  void _closePolygon(EditorData st, EditorNotifier n) {
    final pts = st.pending;
    if (pts.length < 3) return;
    switch (st.tool) {
      case EditorTool.space:
        n.addSpace(pts);
      case EditorTool.outline:
        n.setOutline(pts);
      case EditorTool.hole:
        n.addHole(pts);
      default:
        break;
    }
    n.cancelPending();
  }

  // ---- pointer events ----

  void _endDrag() {
    _guidedPan = false;
    _drag = DragKind.none;
    _dragStartPoint = null;
    _downPos = null;
  }

  void _onPointerDown(PointerDownEvent e, EditorData st, EditorNotifier n) {
    _focus.requestFocus();
    if (_panButtons(e.buttons)) {
      _drag = DragKind.pan;
      _dragLast = e.localPosition;
      _downPos = null;
      return;
    }
    if (!_hasPrimary(e.buttons)) return;

    if (st.cropping) {
      _endDrag();
      setState(() {
        _boxStart = e.localPosition;
        _boxEnd = e.localPosition;
      });
      return;
    }

    // The easy editor (Round 18): a left drag pans; only a selected wall's round
    // end handles can be dragged, so a stray drag never moves a piece.
    if (st.guided && !st.calibrating) {
      _endDrag();
      _downPos = e.localPosition;
      _downPrimary = true;
      _moved = false;
      _dragSnapshotTaken = false;
      final level = st.level;
      if (st.editable && level != null && st.selection.kind == SelKind.wall && st.guidedTool == GuidedTool.none) {
        final w = level.wallById(st.selection.id);
        if (w != null) {
          final p = toLevel(e.localPosition);
          final tol = 14 / _scale;
          for (final (endA, pt) in [(true, w.a), (false, w.b)]) {
            if ((pt[0] - p[0]).abs() < tol && (pt[1] - p[1]).abs() < tol) {
              _drag = DragKind.wallEnd;
              _wallId = w.id;
              _wallEndA = endA;
              return;
            }
          }
        }
      }
      _guidedPan = true;
      _dragLast = e.localPosition;
      return;
    }

    // A left press always starts fresh, even if the engine still reports a stale right button.
    _endDrag();
    _downPos = e.localPosition;
    _downPrimary = true;
    _moved = false;
    _dragSnapshotTaken = false;

    if (st.tool != EditorTool.select || !st.editable) return;
    final level = st.level;
    final doc = st.doc;
    if (level == null || doc == null) return;
    final p = toLevel(e.localPosition);

    final v = _hitVertex(level, st.selection, p);
    if (v != null) {
      _drag = DragKind.vertex;
      _vOutline = v.outline;
      _vRing = v.ring;
      _vIndex = v.index;
      return;
    }
    if (st.selection.kind == SelKind.wall) {
      final w = level.wallById(st.selection.id);
      if (w != null) {
        final tol = 7 / _scale;
        for (final (endA, pt) in [(true, w.a), (false, w.b)]) {
          if ((pt[0] - p[0]).abs() < tol && (pt[1] - p[1]).abs() < tol) {
            _drag = DragKind.wallEnd;
            _wallId = w.id;
            _wallEndA = endA;
            return;
          }
        }
      }
    }
    final hit = _hit(level, doc, p);
    if (!hit.isEmpty) {
      if (hit.id != st.selection.id) n.select(hit);
      _drag = DragKind.move;
      _dragStartPoint = p;
    }
  }

  void _onPointerMove(PointerMoveEvent e, EditorData st, EditorNotifier n) {
    setState(() => _hover = e.localPosition);

    if (_boxStart != null) {
      if (_hasPrimary(e.buttons)) {
        setState(() => _boxEnd = e.localPosition);
      } else {
        _finishBox(st, n);
      }
      return;
    }

    if (_guidedPan) {
      if (!_hasPrimary(e.buttons)) {
        _guidedPan = false;
        return;
      }
      if (_downPos != null && (e.localPosition - _downPos!).distance > _tapSlop) _moved = true;
      if (_moved) setState(() => _origin += e.localPosition - _dragLast);
      _dragLast = e.localPosition;
      return;
    }

    if (_drag == DragKind.pan) {
      if (!_panButtons(e.buttons)) {
        // The pan button is no longer held (or the left button joined): stop panning.
        _drag = DragKind.none;
        return;
      }
      setState(() => _origin += e.localPosition - _dragLast);
      _dragLast = e.localPosition;
      return;
    }

    if (_downPos != null && (e.localPosition - _downPos!).distance > _tapSlop) _moved = true;
    if (_moved && _drag != DragKind.none && !_dragSnapshotTaken) {
      // One undo step per drag, taken when the drag really starts.
      _dragSnapshotTaken = true;
      n.beginDrag();
    }
    if (!_moved && _drag != DragKind.none) return; // still within the tap slop
    if (!_hasPrimary(e.buttons)) {
      // Dragging needs the left button; without it the drag is over.
      if (_drag != DragKind.none) _endDrag();
      return;
    }

    switch (_drag) {
      case DragKind.move:
        final p = toLevel(e.localPosition);
        final start = _dragStartPoint!;
        var dx = p[0] - start[0];
        var dz = p[1] - start[1];
        if (st.snap) {
          dx = snapTo(dx, 0.1);
          dz = snapTo(dz, 0.1);
        }
        if (dx != 0 || dz != 0) {
          n.moveSelection(dx, dz, snapshot: false);
          _dragStartPoint = [start[0] + dx, start[1] + dz];
        }
      case DragKind.vertex:
        n.moveVertex(outline: _vOutline, ringIndex: _vRing, index: _vIndex, to: toLevel(e.localPosition), snapshot: false);
      case DragKind.wallEnd:
        final level = st.level;
        var p = toLevel(e.localPosition);
        final w = level?.wallById(_wallId!);
        if (st.guided && level != null && w != null) {
          // Easy editor: the end snaps to nearby walls and keeps the wall straight.
          final others = level.walls.where((x) => x.id != w.id).toList();
          p = straighten(_wallEndA ? w.b : w.a, snapToWalls(p, others, tol: 14 / _scale));
        } else if (level != null) {
          p = _snapToWallEnds(level, p);
        }
        n.moveWallEnd(_wallId!, _wallEndA, p, snapshot: false);
      case DragKind.pan:
      case DragKind.none:
        break;
    }
  }

  void _onPointerHover(PointerHoverEvent e) {
    // No buttons are held during a hover, so nothing can still be dragging.
    if (_drag != DragKind.none || _downPos != null) _endDrag();
    setState(() => _hover = e.localPosition);
  }

  void _onPointerUp(PointerUpEvent e, EditorData st, EditorNotifier n) {
    if (_boxStart != null) {
      _boxEnd = e.localPosition;
      _finishBox(st, n);
      return;
    }
    final tapCandidate = _downPos != null && _downPrimary && !_moved;
    final pos = e.localPosition;
    _endDrag();
    if (!tapCandidate) return;
    if (st.guided && !st.calibrating) {
      _guidedTap(pos, st, n);
      return;
    }

    final now = DateTime.now();
    final isDouble = _lastTapAt != null && now.difference(_lastTapAt!) < _doubleTapWindow && _lastTapPos != null && (pos - _lastTapPos!).distance < _tapSlop * 2;
    _lastTapAt = isDouble ? null : now;
    _lastTapPos = pos;

    if (isDouble) {
      // The first tap of the pair was already applied; a second tap at the same
      // spot finishes a wall chain or polygon, and otherwise is just a tap.
      if (st.tool == EditorTool.wall && st.pending.isNotEmpty) {
        n.cancelPending();
        return;
      }
      if ((st.tool == EditorTool.space || st.tool == EditorTool.hole || st.tool == EditorTool.outline) && st.pending.length >= 3) {
        _closePolygon(st, n);
        return;
      }
    }
    _tap(pos, st, n);
  }

  void _onPointerCancel(PointerCancelEvent e) => _endDrag();

  void _say(String text) => ref.read(messagesProvider.notifier).showError(text);

  Space? _roomAt(Level level, List<double> p) => level.spaces.reversed.cast<Space?>().firstWhere((s) => pointInPoly(p[0], p[1], s!.shape), orElse: () => null);

  /// A click in the easy editor: the chosen tool does its one thing (then the
  /// editor is back to plain selecting), or the click selects what is under it.
  void _guidedTap(Offset pos, EditorData st, EditorNotifier n) {
    final level = st.level;
    final doc = st.doc;
    if (level == null || doc == null) return;
    final p = toLevel(pos);
    if (!st.editable) {
      n.select(_hit(level, doc, p));
      return;
    }
    switch (st.guidedTool) {
      case GuidedTool.addWall:
        if (st.pending.isEmpty) {
          n.setPending([snapToWalls(p, level.walls, tol: 14 / _scale)]);
        } else {
          n.addSnappedWall(st.pending.first, p);
        }
      case GuidedTool.addDoor:
        final w = _hitWallNear(level, p);
        if (w == null) {
          _say('Click right on a wall to put the door there.');
          return;
        }
        final err = n.addDoorAt(w.id, pointToSegment(p[0], p[1], w.a, w.b).t);
        if (err != null) _say(err);
      case GuidedTool.split:
        if (st.pending.isEmpty) {
          n.setPending([p]);
          return;
        }
        final start = st.pending.first;
        final room = st.selection.kind == SelKind.space
            ? level.spaces.cast<Space?>().firstWhere((s) => s!.id == st.selection.id, orElse: () => null)
            : _roomAt(level, [(start[0] + p[0]) / 2, (start[1] + p[1]) / 2]);
        if (room == null) {
          n.cancelPending();
          _say('Draw the line across a room.');
          return;
        }
        final err = n.splitSpace(room.id, start, p);
        if (err != null) {
          n.cancelPending();
          _say(err);
        }
      case GuidedTool.merge:
        final other = _roomAt(level, p);
        if (other == null || st.selection.kind != SelKind.space) {
          _say('Click the room right next to the selected one.');
          return;
        }
        final err = n.mergeSpaces(st.selection.id, other.id);
        if (err != null) _say(err);
      case GuidedTool.pickStore:
        final room = _roomAt(level, p);
        final store = st.pickStore;
        if (room == null || store == null) {
          _say('Click inside the room where this store is.');
          return;
        }
        n.select(Selection(SelKind.space, room.id));
        n.linkStore(store, room.id).then((err) {
          if (!mounted) return;
          final m = ref.read(messagesProvider.notifier);
          err == null ? m.showSuccess('${store.storeName} is now on the map.') : m.showError(err);
        });
      case GuidedTool.none:
        n.select(_hit(level, doc, p));
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // Registering with the resolver claims the wheel for the canvas; the page
    // scroll view registers later and is ignored, so the page stays put.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final scroll = event as PointerScrollEvent;
      zoomAt(scroll.localPosition, scroll.scrollDelta.dy > 0 ? 1 / 1.12 : 1.12);
    });
  }

  @visibleForTesting
  void zoomAt(Offset p, double factor) {
    final next = (_scale * factor).clamp(0.5, 300.0);
    setState(() {
      _origin = p - (p - _origin) * (next / _scale);
      _scale = next;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, EditorData st, EditorNotifier n) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed ? n.redo() : n.undo();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      n.redo();
      return KeyEventResult.handled;
    }
    if (st.guided) {
      // Easy editor: Escape steps back; no other key changes the map (no stray deletes).
      if (k == LogicalKeyboardKey.escape) {
        _endDrag();
        if (st.calibrating) {
          n.cancelCalibration();
        } else if (st.guidedTool != GuidedTool.none) {
          n.cancelGuidedTool();
        } else {
          n.select(Selection.none);
        }
        return KeyEventResult.handled;
      }
      // Keys that edit in the full editor do nothing here, but are kept so the
      // page does not take them (arrows would move the keyboard focus off the map).
      final swallowed = {
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      };
      return swallowed.contains(k) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.escape) {
      _endDrag();
      if (st.cropping || _boxStart != null) {
        setState(() {
          _boxStart = null;
          _boxEnd = null;
        });
        n.cancelCrop();
      } else if (st.pending.isNotEmpty) {
        n.cancelPending();
      } else if (st.tool != EditorTool.select) {
        n.setTool(EditorTool.select);
      } else {
        n.select(Selection.none);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter) {
      if (st.tool == EditorTool.wall) {
        n.cancelPending();
      } else {
        _closePolygon(st, n);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      n.deleteSelection();
      return KeyEventResult.handled;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 1.0 : 0.1;
    if (k == LogicalKeyboardKey.arrowLeft) n.moveSelection(-step, 0);
    if (k == LogicalKeyboardKey.arrowRight) n.moveSelection(step, 0);
    if (k == LogicalKeyboardKey.arrowUp) n.moveSelection(0, -step);
    if (k == LogicalKeyboardKey.arrowDown) n.moveSelection(0, step);
    final tools = <LogicalKeyboardKey, EditorTool>{
      LogicalKeyboardKey.keyV: EditorTool.select,
      LogicalKeyboardKey.keyW: EditorTool.wall,
      LogicalKeyboardKey.keyS: EditorTool.space,
      LogicalKeyboardKey.keyO: EditorTool.opening,
      LogicalKeyboardKey.keyF: EditorTool.feature,
      LogicalKeyboardKey.keyC: EditorTool.connector,
    };
    if (!ctrl && tools.containsKey(k) && st.editable) {
      n.setTool(tools[k]!);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final p = context.pal;
    final level = st.level;

    _watchProposal(st.proposal, MediaQuery.disableAnimationsOf(context));

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (level != null && (_fittedLevel != level.id || _fittedRequest != st.fitRequest)) {
          _fit(level, size);
          _fittedLevel = level.id;
          _fittedRequest = st.fitRequest;
        }
        final bd = level?.backdrop;
        if (bd != null && st.branchId != null) _ensureImage(st.branchId!, bd.id);
        final cursor = st.calibrating || st.cropping
            ? SystemMouseCursors.precise
            : st.tool == EditorTool.select
                ? SystemMouseCursors.basic
                : SystemMouseCursors.precise;
        return Focus(
          focusNode: _focus,
          onKeyEvent: (node, e) => _onKey(node, e, st, n),
          child: MouseRegion(
            cursor: _drag == DragKind.pan ? SystemMouseCursors.grabbing : cursor,
            // MouseRegion callbacks run inside the mouse tracker update; defer the rebuild.
            onExit: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hover = null);
            }),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _onPointerDown(e, st, n),
              onPointerMove: (e) => _onPointerMove(e, st, n),
              onPointerHover: _onPointerHover,
              onPointerUp: (e) => _onPointerUp(e, st, n),
              onPointerCancel: _onPointerCancel,
              onPointerSignal: _onSignal,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: CustomPaint(
                        size: size,
                        painter: _Painter(
                          st: st,
                          scale: _scale,
                          origin: _origin,
                          hover: _hover == null ? null : toLevel(_hover!),
                          pal: p,
                          shift: HardwareKeyboard.instance.isShiftPressed,
                          image: bd == null ? null : _images[bd.id],
                          pictureSize: _pictureSize(bd?.id),
                          boxDrag: _boxStart == null || _boxEnd == null ? null : Rect.fromPoints(_boxStart!, _boxEnd!),
                          reveal: _reveal,
                          revealIds: _revealIds,
                        ),
                        child: level == null ? Center(child: Text('No level to show.', style: ts(13, color: p.muted))) : const SizedBox.expand(),
                      ),
                    ),
                  ),
                  // Big, always-visible zoom and fit buttons (Round 18: easy to move around).
                  if (level != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: _ZoomButtons(
                        onIn: () => zoomAt(size.center(Offset.zero), 1.25),
                        onOut: () => zoomAt(size.center(Offset.zero), 1 / 1.25),
                        onFit: n.requestFit,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

/// Room colours by space type (translucent fills on the 2D canvas; the 3D preview uses their full colour).
const spaceTypeColors = {
  'retail': Color(0x33F97316),
  'food': Color(0x33F59E0B),
  'anchor': Color(0x33C2410C),
  'service': Color(0x3360A5FA),
  'office': Color(0x3394A3B8),
  'storage': Color(0x33A3A3A3),
  'atrium': Color(0x2214B8A6),
  'corridor': Color(0x1A94A3B8),
  'restroom': Color(0x3338BDF8),
  'parking': Color(0x3378716C),
  'outdoor': Color(0x3384CC16),
  'custom': Color(0x33A855F7),
};

class _Painter extends CustomPainter {
  _Painter({
    required this.st,
    required this.scale,
    required this.origin,
    required this.hover,
    required this.pal,
    required this.shift,
    this.image,
    this.pictureSize,
    this.boxDrag,
    this.reveal,
    this.revealIds = const {},
  }) : super(repaint: reveal);

  /// 0 → 1 while new proposal pieces draw themselves in (Round 17).
  final Animation<double>? reveal;

  /// Ids of the proposal pieces that are new and draw in; others are drawn whole.
  final Set<String> revealIds;

  final ui.Image? image;

  /// Stands in for the image size in tests.
  final Size? pictureSize;

  /// The box being dragged in box mode (screen coordinates).
  final Rect? boxDrag;
  final EditorData st;
  final double scale;
  final Offset origin;
  final List<double>? hover;
  final Pal pal;
  final bool shift;

  Offset s(double x, double z) => Offset(origin.dx + x * scale, origin.dy + z * scale);
  Offset sp(List<double> p) => s(p[0], p[1]);

  Path ringPath(List<List<double>> ring) {
    final path = Path();
    for (var i = 0; i < ring.length; i++) {
      final o = sp(ring[i]);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    path.close();
    return path;
  }

  Path polyPath(Poly poly) {
    final path = Path()..fillType = PathFillType.evenOdd;
    path.addPath(ringPath(poly.outer), Offset.zero);
    for (final h in poly.holes) {
      path.addPath(ringPath(h), Offset.zero);
    }
    return path;
  }

  /// A dashed line from [a] to [b] (screen coordinates).
  void dashed(Canvas c, Offset a, Offset b, Paint paint, {double dash = 7, double gap = 5}) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final u = d / len;
    for (var t = 0.0; t < len; t += dash + gap) {
      c.drawLine(a + u * t, a + u * math.min(t + dash, len), paint);
    }
  }

  void dashedRing(Canvas c, List<List<double>> ring, Paint paint) {
    for (var i = 0; i < ring.length; i++) {
      dashed(c, sp(ring[i]), sp(ring[(i + 1) % ring.length]), paint);
    }
  }

  void label(Canvas c, Offset at, String text, {double size = 11, Color? color, FontWeight w = FontWeight.w600, bool center = true}) {
    if (text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color ?? pal.ink, fontWeight: w)),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 160);
    tp.paint(c, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = pal.dark ? const Color(0xFF131316) : const Color(0xFFF4F5F7));
    final level = st.level;
    final doc = st.doc;
    if (level == null || doc == null) return;

    if (scale >= 4) {
      final minor = Paint()
        ..color = pal.dark ? const Color(0x14FFFFFF) : const Color(0x0F000000)
        ..strokeWidth = 1;
      final major = Paint()
        ..color = pal.dark ? const Color(0x26FFFFFF) : const Color(0x1F000000)
        ..strokeWidth = 1;
      final x0 = ((0 - origin.dx) / scale).floor();
      final x1 = ((size.width - origin.dx) / scale).ceil();
      final z0 = ((0 - origin.dy) / scale).floor();
      final z1 = ((size.height - origin.dy) / scale).ceil();
      for (var x = x0; x <= x1; x++) {
        final o = s(x.toDouble(), 0).dx;
        c.drawLine(Offset(o, 0), Offset(o, size.height), x % 10 == 0 ? major : minor);
      }
      for (var z = z0; z <= z1; z++) {
        final o = s(0, z.toDouble()).dy;
        c.drawLine(Offset(0, o), Offset(size.width, o), z % 10 == 0 ? major : minor);
      }
    }

    final sel = st.selection;
    final selPaint = Paint()
      ..color = pal.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Backdrop: the uploaded plan, centred at (cx, cz), rotated, mpp metres per pixel.
    final bd = level.backdrop;
    if (bd != null) {
      final centre = s(bd.cx, bd.cz);
      final img = image;
      c.save();
      c.translate(centre.dx, centre.dy);
      c.rotate(bd.rot * math.pi / 180);
      if (img != null) {
        // Sized by the plan's real pixels; the decoded picture may be smaller.
        final w = (pictureSize?.width ?? img.width.toDouble()) * bd.mpp * scale;
        final h = (pictureSize?.height ?? img.height.toDouble()) * bd.mpp * scale;
        final dst = Rect.fromCenter(center: Offset.zero, width: w, height: h);
        c.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            dst,
            Paint()
              ..color = Color.fromRGBO(255, 255, 255, bd.opacity)
              ..filterQuality = FilterQuality.medium);
        c.drawRect(
            dst,
            Paint()
              ..color = bd.locked ? pal.faint : pal.brand2
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      } else {
        c.drawRect(Rect.fromCenter(center: Offset.zero, width: 60, height: 24), Paint()..color = pal.boxBg);
        label(c, Offset.zero, 'loading plan…', size: 9, color: pal.muted);
      }
      c.restore();
    }

    if (level.outline != null && level.outline!.outer.length >= 3) {
      final path = polyPath(level.outline!);
      c.drawPath(path, Paint()..color = pal.dark ? const Color(0xFF1C1C21) : Colors.white);
      final selected = sel.kind == SelKind.level;
      c.drawPath(
          path,
          Paint()
            ..color = selected ? pal.brand : pal.slate
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.5 : 1.5);
      if (selected) _handles(c, level.outline!);
    }

    for (final sp0 in level.spaces) {
      if (sp0.shape.outer.length < 3) continue;
      final path = polyPath(sp0.shape);
      final selected = sel.kind == SelKind.space && sel.id == sp0.id;
      c.drawPath(path, Paint()..color = spaceTypeColors[sp0.type] ?? spaceTypeColors['custom']!);
      c.drawPath(
          path,
          selected
              ? selPaint
              : (Paint()
                ..color = pal.dark ? const Color(0x66FFFFFF) : const Color(0x66000000)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1));
      final cen = ringCentroid(sp0.shape.outer);
      final linked = st.storeLinks.where((l) => l.spaceKey == sp0.id).map((l) => l.storeName).join(', ');
      if (scale >= 2.5) label(c, sp(cen), sp0.name.isEmpty ? '(${sp0.type})' : sp0.name, size: math.min(12, 3 + scale), color: sp0.name.isEmpty ? pal.muted : pal.ink);
      if (linked.isNotEmpty && scale >= 5) label(c, sp(cen) + const Offset(0, 13), linked, size: 9, color: pal.brand2, w: FontWeight.w500);
      if (sp0.sloped && scale >= 4) label(c, sp(cen) - const Offset(0, 13), 'sloped', size: 9, color: pal.muted);
      if (selected) _handles(c, sp0.shape);
    }

    for (final w in level.walls) {
      final selected = sel.kind == SelKind.wall && sel.id == w.id;
      final color = switch (w.kind) {
        'glass' => const Color(0xFF38BDF8),
        'partition' => pal.faint,
        'boundary' => pal.brand2,
        _ => pal.dark ? const Color(0xFFE5E5E5) : const Color(0xFF262626),
      };
      c.drawLine(
          sp(w.a),
          sp(w.b),
          Paint()
            ..color = selected ? pal.brand : color
            ..strokeWidth = math.max(2, w.t * scale)
            ..strokeCap = StrokeCap.square);
      if (selected) {
        for (final e in [w.a, w.b]) {
          c.drawCircle(sp(e), 5, Paint()..color = Colors.white);
          c.drawCircle(sp(e), 5, selPaint);
        }
        label(c, sp(w.pointAt(0.5)) - const Offset(0, 12), '${w.length.toStringAsFixed(2)} m', size: 10, color: pal.brand2);
      }
    }

    for (final o in level.openings) {
      final w = level.wallById(o.wall);
      if (w == null) continue;
      final cPt = w.pointAt(o.at);
      final dx = w.b[0] - w.a[0], dz = w.b[1] - w.a[1];
      final len = math.sqrt(dx * dx + dz * dz);
      if (len == 0) continue;
      final ux = dx / len, uz = dz / len;
      final a = [cPt[0] - ux * o.w / 2, cPt[1] - uz * o.w / 2];
      final b = [cPt[0] + ux * o.w / 2, cPt[1] + uz * o.w / 2];
      final selected = sel.kind == SelKind.opening && sel.id == o.id;
      c.drawLine(
          sp(a),
          sp(b),
          Paint()
            ..color = pal.dark ? const Color(0xFF1C1C21) : Colors.white
            ..strokeWidth = math.max(3, w.t * scale + 2)
            ..strokeCap = StrokeCap.butt);
      final leaf = Paint()
        ..color = selected ? pal.brand : (o.kind == 'entrance' ? pal.green : const Color(0xFF0EA5E9))
        ..strokeWidth = 2;
      c.drawLine(sp(a), sp(b), leaf);
      final nx = -uz, nz = ux;
      c.drawLine(sp(a), sp([a[0] + nx * 0.6, a[1] + nz * 0.6]), leaf);
      if (scale >= 6 && o.kind != 'door') label(c, sp(cPt) + Offset(nx * 14, nz * 14), o.kind, size: 9, color: pal.muted);
    }

    final cat = st.catalog;
    for (final f in level.features) {
      final def = cat?.features[f.type];
      final w = f.w ?? def?.size[0] ?? 1;
      final d = f.d ?? def?.size[1] ?? 1;
      final selected = sel.kind == SelKind.feature && sel.id == f.id;
      final centre = s(f.x, f.z);
      c.save();
      c.translate(centre.dx, centre.dy);
      c.rotate(f.rot * math.pi / 180);
      final rect = Rect.fromCenter(center: Offset.zero, width: math.max(6, w * scale), height: math.max(6, d * scale));
      c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = (def?.target ?? false) ? const Color(0xCCFB923C) : const Color(0xCC94A3B8));
      if (selected) c.drawRRect(RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(4)), selPaint);
      c.restore();
      if (scale >= 5) label(c, centre + Offset(0, math.max(6, d * scale) / 2 + 9), f.label.isNotEmpty ? f.label : (def?.label ?? f.type), size: 9, color: pal.muted);
    }

    for (final cn in doc.connectors) {
      for (final e in cn.endpoints.where((e) => e.level == level.id)) {
        final selected = sel.kind == SelKind.connector && sel.id == cn.id;
        final centre = s(e.x, e.z);
        c.save();
        c.translate(centre.dx, centre.dy);
        c.rotate(e.rot * math.pi / 180);
        final rect = Rect.fromCenter(center: Offset.zero, width: math.max(8, e.w * scale), height: math.max(8, e.len * scale));
        c.drawRect(rect, Paint()..color = const Color(0xCC8B5CF6));
        c.drawRect(
            rect,
            selected
                ? selPaint
                : (Paint()
                  ..color = const Color(0xFF6D28D9)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1));
        final steps = math.max(2, (e.len / 0.3).floor());
        for (var i = 1; i < steps && i < 40; i++) {
          final y = rect.top + rect.height * i / steps;
          c.drawLine(
              Offset(rect.left, y),
              Offset(rect.right, y),
              Paint()
                ..color = const Color(0x66FFFFFF)
                ..strokeWidth = 1);
        }
        c.restore();
        final others = cn.endpoints.where((x) => x.level != level.id).map((x) => doc.level(x.level)?.name ?? '?').join(', ');
        label(c, centre + Offset(0, math.max(8, e.len * scale) / 2 + 9), '${cn.name.isNotEmpty ? cn.name : cn.kind}${others.isEmpty ? '' : ' → $others'}${cn.oneWay ? ' (one-way)' : ''}',
            size: 9, color: const Color(0xFF6D28D9));
      }
    }

    // AI proposal: teal, on top of the level, never part of it until accepted.
    // Pieces the AI was not sure about are dashed in amber (Round 15).
    final prop = st.proposal;
    if (prop != null && prop.levelId == level.id) {
      final teal = pal.aiProposal;
      final unsure = pal.aiUnsure;
      // Round 17: new pieces draw themselves in. Walls grow first, rooms fade in,
      // doors and labels last. Pieces already on screen are drawn whole.
      final v = reveal?.value ?? 1;
      double phase(String id, double from, double span) => revealIds.contains(id) ? Curves.easeOutCubic.transform(((v - from) / span).clamp(0.0, 1.0)) : 1;
      Color fade(Color col, double k) => col.withValues(alpha: col.a * k);
      final pOutline = prop.outline;
      if (pOutline != null && pOutline.outer.length >= 3) {
        final k = revealIds.isEmpty ? 1.0 : Curves.easeOut.transform((v / 0.6).clamp(0.0, 1.0));
        if (k > 0) {
          dashedRing(
              c,
              pOutline.outer,
              Paint()
                ..color = fade(teal, k)
                ..strokeWidth = 2);
        }
      }
      for (final sp1 in prop.spaces) {
        if (sp1.shape.outer.length < 3) continue;
        final k = phase(sp1.id, 0.25, 0.5);
        if (k <= 0) continue;
        final path = polyPath(sp1.shape);
        final doubt = prop.uncertain.contains(sp1.id);
        c.drawPath(path, Paint()..color = fade(pal.aiProposalFill, k));
        if (doubt) {
          dashedRing(
              c,
              sp1.shape.outer,
              Paint()
                ..color = fade(unsure, k)
                ..strokeWidth = 1.6);
        } else {
          c.drawPath(
              path,
              Paint()
                ..color = fade(teal, k)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2);
        }
        final kl = phase(sp1.id, 0.7, 0.3);
        if (scale >= 2.5 && kl > 0) {
          final match = prop.storeMatches.where((m) => m.spaceId == sp1.id).firstOrNull;
          final cen = sp(ringCentroid(sp1.shape.outer));
          label(c, cen, sp1.name.isEmpty ? '(${sp1.type})' : sp1.name, size: math.min(12, 3 + scale), color: fade(doubt ? unsure : teal, kl));
          if (match != null && scale >= 5) label(c, cen + const Offset(0, 13), '→ ${match.storeName}', size: 9, color: fade(teal, kl), w: FontWeight.w500);
        }
      }
      for (final w in prop.walls) {
        final k = phase(w.id, 0, 0.65);
        if (k <= 0) continue;
        final end = [w.a[0] + (w.b[0] - w.a[0]) * k, w.a[1] + (w.b[1] - w.a[1]) * k];
        final paint = Paint()
          ..strokeWidth = math.max(2, w.t * scale)
          ..strokeCap = StrokeCap.square;
        if (prop.uncertain.contains(w.id)) {
          dashed(c, sp(w.a), sp(end), paint..color = unsure);
        } else {
          c.drawLine(sp(w.a), sp(end), paint..color = teal);
        }
      }
      for (final o in prop.openings) {
        final w = prop.walls.cast<Wall?>().firstWhere((x) => x!.id == o.wall, orElse: () => null);
        if (w == null || phase(o.id, 0.55, 0.3) < 1 && revealIds.contains(o.id) && v < 0.55) continue;
        final cPt = w.pointAt(o.at);
        final dx = w.b[0] - w.a[0], dz = w.b[1] - w.a[1];
        final len = math.sqrt(dx * dx + dz * dz);
        if (len == 0) continue;
        final ux = dx / len, uz = dz / len;
        final a = sp([cPt[0] - ux * o.w / 2, cPt[1] - uz * o.w / 2]);
        final b = sp([cPt[0] + ux * o.w / 2, cPt[1] + uz * o.w / 2]);
        final doubt = prop.uncertain.contains(o.id) || prop.uncertain.contains(w.id);
        // The gap, then the two jambs.
        c.drawLine(
            a,
            b,
            Paint()
              ..color = pal.panel
              ..strokeWidth = math.max(3, w.t * scale + 2)
              ..strokeCap = StrokeCap.butt);
        final jamb = Paint()
          ..color = doubt ? unsure : teal
          ..strokeWidth = 2;
        final nrm = Offset(-uz, ux) * math.max(4, w.t * scale / 2 + 3);
        c.drawLine(a - nrm, a + nrm, jamb);
        c.drawLine(b - nrm, b + nrm, jamb);
        if (doubt) {
          dashed(
              c,
              a,
              b,
              Paint()
                ..color = unsure
                ..strokeWidth = 1.5,
              dash: 4,
              gap: 3);
        }
      }
      final doubts = prop.uncertain.length;
      label(
        c,
        Offset(size.width / 2, 14),
        'AI proposal: ${prop.walls.length} walls, ${prop.openings.length} doors, ${prop.spaces.length} rooms${doubts > 0 ? ', $doubts unsure (dashed)' : ''} · click a piece to drop it',
        size: 11,
        color: teal,
      );
    }

    // The part of the plan to read (box mode).
    final box = st.cropBox;
    final bdx = level.backdrop;
    final picW = pictureSize?.width.round() ?? image?.width;
    final picH = pictureSize?.height.round() ?? image?.height;
    if (box != null && bdx != null && picW != null && picH != null) {
      final ring = [
        bdx.toLevel(box[0] * picW, box[1] * picH, picW, picH),
        bdx.toLevel(box[2] * picW, box[1] * picH, picW, picH),
        bdx.toLevel(box[2] * picW, box[3] * picH, picW, picH),
        bdx.toLevel(box[0] * picW, box[3] * picH, picW, picH),
      ];
      c.drawPath(ringPath(ring), Paint()..color = pal.brand.withValues(alpha: 0.07));
      dashedRing(
          c,
          ring,
          Paint()
            ..color = pal.brand
            ..strokeWidth = 2);
      label(c, sp(ring[0]) + const Offset(4, -10), 'Part to read', size: 10, color: pal.brand2, center: false);
    }
    if (boxDrag != null) {
      c.drawRect(boxDrag!, Paint()..color = pal.brand.withValues(alpha: 0.07));
      c.drawRect(
          boxDrag!,
          Paint()
            ..color = pal.brand
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
    if (st.cropping && boxDrag == null) {
      label(c, Offset(size.width / 2, 14), 'Drag a box over the part of the plan to read · Esc cancels', size: 11, color: pal.brand2);
    }

    // Calibration clicks
    if (st.calibrating) {
      final pts = st.calibPoints;
      final cp = Paint()
        ..color = const Color(0xFFDC2626)
        ..strokeWidth = 1.5;
      for (final pt in pts) {
        final o = sp(pt);
        c.drawLine(o - const Offset(10, 0), o + const Offset(10, 0), cp);
        c.drawLine(o - const Offset(0, 10), o + const Offset(0, 10), cp);
        c.drawCircle(o, 6, cp..style = PaintingStyle.stroke);
      }
      if (pts.length == 2) {
        c.drawLine(
            sp(pts[0]),
            sp(pts[1]),
            Paint()
              ..color = const Color(0xFFDC2626)
              ..strokeWidth = 2);
        final dist = math.sqrt(math.pow(pts[1][0] - pts[0][0], 2) + math.pow(pts[1][1] - pts[0][1], 2));
        final mid = sp([(pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2]);
        label(c, mid - const Offset(0, 14), 'currently ${dist.toStringAsFixed(2)} m', size: 10, color: const Color(0xFFDC2626));
      }
      label(c, Offset(size.width / 2, 14), pts.length < 2 ? 'Calibrate: click two points whose real distance you know (${pts.length}/2)' : 'Now type the real distance in the Blueprint panel',
          size: 11, color: const Color(0xFFDC2626));
    }

    // Easy editor: the selected wall's ends are big round handles (the only things that drag).
    if (st.guided && st.editable && st.selection.kind == SelKind.wall) {
      final w = level.wallById(st.selection.id);
      if (w != null) {
        for (final e in [w.a, w.b]) {
          c.drawCircle(sp(e), 9, Paint()..color = pal.panel);
          c.drawCircle(
              sp(e),
              9,
              Paint()
                ..color = pal.brand
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.5);
        }
      }
    }
    if (st.guided && st.guidedTool != GuidedTool.none) {
      final hint = switch (st.guidedTool) {
        GuidedTool.addWall => st.pending.isEmpty ? 'Click where the new wall starts' : 'Click where it ends',
        GuidedTool.addDoor => 'Click on a wall to put the ${st.doorPreset.toLowerCase()} there',
        GuidedTool.split => st.pending.isEmpty ? 'Click on one side of the room to start the cut' : 'Click on the other side to finish the cut',
        GuidedTool.merge => 'Click the room to join with the selected one',
        GuidedTool.pickStore => 'Click the room where ${st.pickStore?.storeName ?? 'the store'} is',
        GuidedTool.none => '',
      };
      label(c, Offset(size.width / 2, 16), '$hint · Esc cancels', size: 12, color: pal.brand2);
    }

    if (st.pending.isNotEmpty) {
      final pen = Paint()
        ..color = pal.brand
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < st.pending.length; i++) {
        final o = sp(st.pending[i]);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      if (hover != null) {
        var h = hover!;
        if (st.tool == EditorTool.wall && st.snap && !shift) h = snapAngle(st.pending.last, h);
        if (st.snap) h = [snapTo(h[0], 0.1), snapTo(h[1], 0.1)];
        final o = sp(h);
        path.lineTo(o.dx, o.dy);
        final last = st.pending.last;
        final len = math.sqrt(math.pow(h[0] - last[0], 2) + math.pow(h[1] - last[1], 2));
        label(c, o + const Offset(14, -14), '${len.toStringAsFixed(2)} m', size: 10, color: pal.brand2, center: false);
      }
      c.drawPath(path, pen);
      for (final pt in st.pending) {
        c.drawCircle(sp(pt), 4, Paint()..color = pal.brand);
      }
      if (st.tool != EditorTool.wall && st.pending.length >= 3) {
        c.drawCircle(
            sp(st.pending.first),
            7,
            Paint()
              ..color = pal.brand
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }
    }

    if (hover != null && st.tool != EditorTool.select) {
      final h = st.snap ? [snapTo(hover![0], 0.1), snapTo(hover![1], 0.1)] : hover!;
      final o = sp(h);
      final cross = Paint()
        ..color = pal.brand
        ..strokeWidth = 1;
      c.drawLine(o - const Offset(8, 0), o + const Offset(8, 0), cross);
      c.drawLine(o - const Offset(0, 8), o + const Offset(0, 8), cross);
      label(c, o + const Offset(12, 8), '${h[0].toStringAsFixed(1)}, ${h[1].toStringAsFixed(1)}', size: 9, color: pal.muted, center: false);
    }

    final barMetres = scale >= 20
        ? 1
        : scale >= 5
            ? 5
            : scale >= 1.5
                ? 10
                : 50;
    final y = size.height - 18.0;
    c.drawLine(
        Offset(16, y),
        Offset(16 + barMetres * scale, y),
        Paint()
          ..color = pal.ink
          ..strokeWidth = 2);
    label(c, Offset(16, y - 16), '$barMetres m', size: 10, color: pal.muted, center: false);
  }

  void _handles(Canvas c, Poly poly) {
    final fill = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = pal.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final ring in [poly.outer, ...poly.holes]) {
      for (final pt in ring) {
        c.drawCircle(sp(pt), 4.5, fill);
        c.drawCircle(sp(pt), 4.5, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Painter old) => true;
}

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.onIn, required this.onOut, required this.onFit});

  final VoidCallback onIn;
  final VoidCallback onOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // No tooltips inside the map editor: their overlay froze the page in debug
    // mode (see the tool rail); the label goes to screen readers instead.
    Widget b(Key key, IconData icon, String tip, VoidCallback on) => Semantics(
          label: tip,
          button: true,
          child: IconButton(
            key: key,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            icon: Icon(icon, color: p.ink),
            onPressed: on,
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line), boxShadow: p.shadow),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          b(const ValueKey('zoom-in'), Icons.add, 'Zoom in', onIn),
          b(const ValueKey('zoom-out'), Icons.remove, 'Zoom out', onOut),
          b(const ValueKey('zoom-fit'), Icons.fit_screen_outlined, 'Show the whole floor', onFit),
        ],
      ),
    );
  }
}

// The map's own state: the camera, the level shown, following the dot, the
// fly-to animations, tap targets, gestures and the bottom sheet's size (from the
// demo's AppState). It starts afresh in each mall.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/routing.dart';
import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';
import '../../malls/providers/mall_provider.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../models/cam.dart';
import '../services/hit_regions.dart';
import '../services/map_constants.dart';

class _Tween {
  final String key;
  final double ms;
  final void Function(double t) apply;
  Duration? start;
  _Tween(this.key, this.ms, this.apply);
}

class MapView {
  MapView(this.v)
      : level = v.ground,
        cam = Cam()
          ..cx = v.siteView.cx
          ..cy = v.siteView.cy
          ..zoom = v.siteView.zoom;

  final Venue v;
  final Cam cam;
  int level;
  bool follow = true;
  final hits = MapHits();
  final List<_Tween> _tweens = [];

  /// The middle of the map area, set by the screen each layout.
  double centreX = mockW / 2, centreY = 380;

  /// The sheet minimised to one line. A different sheet (a new route, place, evacuation...) opens unminimised.
  bool sheetMin = false;
  String? _sheetFor;

  /// While walking a route: the bottom bar opened to show the notes, other ways and all the steps.
  bool navOpen = false;

  double _z0 = 1, _r0 = 0;

  /// Zoom limits, scaled to the venue (the same on-screen detail in every mall).
  double get zMax => zoomMax * v.ratio;
  String get mode => cam.ex > 0.02 ? 'stack' : cam.zoom < siteZoomMax * v.ratio ? 'site' : 'building';
  bool get rotated => math.atan2(math.sin(cam.rot), math.cos(cam.rot)).abs() > 2 * math.pi / 180;
  bool get animating => _tweens.isNotEmpty;

  void prep() => cam.prep(v);

  /// Screen point -> ground (z = 0) world point, the inverse of the painter's projection outside the stack.
  Offset unproject(Offset sp) {
    prep();
    final ky = lerp(1, cam.kyB, cam.tilt), ru = (sp.dx - centreX) / cam.S, rv = (sp.dy - centreY) / (cam.S * ky);
    final du = ru * cam.c + rv * cam.s, dv = -ru * cam.s + rv * cam.c;
    return Offset(cam.cx + du, cam.cy + dv);
  }
}

class MapController extends Notifier<MapView> {
  @override
  MapView build() {
    final v = ref.watch(currentVenueProvider);
    if (v == null) throw StateError('The map needs a mall');
    return MapView(v);
  }

  MapView get m => state;
  Cam get cam => state.cam;
  Venue get v => state.v;
  String get mode => state.mode;

  void notify() => ref.notifyListeners();

  // ===== Animations =====
  void _addTween(String key, double ms, void Function(double t) apply) {
    m._tweens.removeWhere((t) => t.key == key);
    m._tweens.add(_Tween(key, ms, apply));
    notify();
  }

  void flyTo(double cx, double cy, double zoom, [double ms = 520]) {
    final fcx = cam.cx, fcy = cam.cy, fz = cam.zoom;
    _addTween('fly', ms, (t) {
      cam.cx = lerp(fcx, cx, t);
      cam.cy = lerp(fcy, cy, t);
      cam.zoom = math.exp(lerp(math.log(fz), math.log(zoom), t));
    });
  }

  void tweenProp(String key, double to, [double ms = 480]) {
    final f = switch (key) { 'ex' => cam.ex, 'tilt' => cam.tilt, _ => cam.rot };
    _addTween(key, ms, (t) {
      final x = lerp(f, to, t);
      switch (key) {
        case 'ex':
          cam.ex = x;
        case 'tilt':
          cam.tilt = x;
        default:
          cam.rot = x;
      }
    });
  }

  /// Advances the fly-to animations (driven by the shell's ticker).
  void tick(Duration now) {
    if (m._tweens.isEmpty) return;
    for (final tw in List.of(m._tweens)) {
      tw.start ??= now;
      final t = smooth((now - tw.start!).inMicroseconds / 1000 / tw.ms);
      tw.apply(t);
      if (t >= 1) m._tweens.remove(tw);
    }
    notify();
  }

  // ===== The map tools =====
  /// Leaving the stacked view for the plan (picking a place, starting a route).
  void leaveStack() {
    if (cam.ex > 0.02) tweenProp('ex', 0);
  }

  void toggleStack() {
    final u = ref.read(navProvider).user;
    if (cam.ex < .5) {
      cam.tilt = 1;
      if (u != null) m.level = u.lv;
    }
    tweenProp('ex', cam.ex < .5 ? 1 : 0);
  }

  void toggleTilt() {
    if (mode == 'stack') return;
    tweenProp('tilt', cam.tilt > 0.5 ? 0 : 1, 380);
  }

  void flyToSite() {
    if (mode == 'stack') return;
    flyTo(v.siteView.cx, v.siteView.cy, v.siteView.zoom);
  }

  void flyToWing(String key) {
    if (mode == 'stack') return;
    final w = v.pad.firstWhere((b) => b.key == key).view;
    flyTo(w.cx, w.cy, w.zoom);
  }

  /// Centre on the dot (nothing while the shopper has not said where they are).
  void recenter() {
    final u = ref.read(navProvider).user;
    if (mode == 'stack' || u == null) return;
    if (mode == 'site') m.level = u.lv;
    flyTo(u.x, u.y, math.max(cam.zoom, 3.5 * v.ratio));
  }

  void showLevel(int lv) {
    m.level = lv;
    if (mode == 'site') flyTo(cam.cx, cam.cy, 2 * v.ratio);
    notify();
  }

  /// Fly to a place and show its level.
  void showPlace(Place p) {
    leaveStack();
    m.level = p.lv;
    flyTo(p.at[0], p.at[1], math.max(cam.zoom, 4.5 * v.ratio));
  }

  /// Fly to a spot on a level (the shopper's position, a connector).
  void showSpot(int lv, double x, double y, {double zoom = 3.5}) {
    leaveStack();
    m.level = lv;
    flyTo(x, y, math.max(cam.zoom, zoom * v.ratio));
  }

  void setHeadingUp(bool on) {
    ref.read(settingsProvider.notifier).setHeadingUp(on);
    if (!on) tweenProp('rot', 0);
  }

  void setFollow(bool f) {
    m.follow = f;
    notify();
  }

  /// Heading-up: the map turns so forward on screen is forward in the mall.
  void turnToHeading({required double? heading, required bool playing}) {
    final s = ref.read(settingsProvider);
    if (s.headingUp && playing && heading != null && cam.ex < .5 && mode != 'site') {
      cam.rot = lerp(cam.rot, nearRot(-math.pi / 2 - heading - yaw, cam.rot), .15);
    }
  }

  /// The walk moved the dot: follow it.
  void followDot(PointAt at, {required bool playing}) {
    if (m.follow && playing && mode != 'site') m.level = at.lv;
    if (m.follow && playing && mode != 'stack') {
      cam.cx = lerp(cam.cx, at.pos[0], .12);
      cam.cy = lerp(cam.cy, at.pos[1], .12);
    }
  }

  /// The angle equal to [target] that is nearest to [from], for a smooth turn.
  static double nearRot(double target, double from) {
    var t = target;
    while (t - from > math.pi) {
      t -= 2 * math.pi;
    }
    while (t - from < -math.pi) {
      t += 2 * math.pi;
    }
    return t;
  }

  // ===== Taps and gestures =====
  void mapTap(Offset p) {
    final hit = m.hits.at(p), nav = ref.read(navProvider.notifier), s = ref.read(navProvider);
    if (s.refining && mode == 'building') {
      // saying exactly where I am: the shopper is looking right here, so the camera stays
      final w = m.unproject(p), cx = cam.cx, cy = cam.cy, z = cam.zoom;
      nav.refineAt(m.level, w.dx, w.dy);
      m._tweens.removeWhere((t) => t.key == 'fly');
      cam
        ..cx = cx
        ..cy = cy
        ..zoom = z;
    } else if (mode == 'stack') {
      if (hit != null && hit.kind == 'level') {
        m.level = int.parse(hit.id);
        tweenProp('ex', 0);
      }
    } else if (hit != null && hit.kind == 'poi' && !s.emergency) {
      final pl = nav.selectPlace(hit.id);
      if (pl != null && mode == 'building') m.level = pl.lv;
    } else if (hit != null && hit.kind == 'bldg') {
      final bv = v.buildingViews[hit.id];
      if (bv != null) flyTo(bv.cx, bv.cy, bv.zoom);
      final u = s.user;
      if (u != null) m.level = u.lv;
    }
    notify();
  }

  void gestureStart() {
    m._z0 = cam.zoom;
    m._r0 = cam.rot;
  }

  void gestureUpdate({required Offset focal, required Offset delta, required double scale, required double rotation, required int pointers}) {
    if (mode == 'stack') return;
    if (pointers >= 2) {
      final before = m.unproject(focal);
      cam.zoom = clampD(m._z0 * scale, zoomMin, m.zMax);
      cam.rot = m._r0 + rotation;
      final after = m.unproject(focal);
      cam.cx += before.dx - after.dx;
      cam.cy += before.dy - after.dy;
    }
    // the drag: screen delta -> world delta
    m.prep();
    final ky = lerp(1, cam.kyB, cam.tilt), ru = delta.dx / cam.S, rv = delta.dy / (cam.S * ky);
    final du = ru * cam.c + rv * cam.s, dv = -ru * cam.s + rv * cam.c;
    cam.cx -= du;
    cam.cy -= dv;
    notify();
  }

  // ===== The draggable sheet (summary, minimised) =====
  /// Called while building: a new kind of sheet opens at its summary.
  void syncSheet(String? kind) {
    if (kind != m._sheetFor) {
      m._sheetFor = kind;
      m.sheetMin = false;
      m.navOpen = false;
    }
  }

  void toggleNavOpen() {
    m.navOpen = !m.navOpen;
    notify();
  }

  void sheetUp() {
    if (!m.sheetMin) return;
    m.sheetMin = false;
    notify();
  }

  void sheetDown() {
    if (m.sheetMin) return;
    m.sheetMin = true;
    notify();
  }
}

final mapProvider = NotifierProvider<MapController, MapView>(MapController.new);

// The navigation: starting and walking a trip, saying where you are, other ways,
// getting help and the emergency evacuation. Ported from the demo's AppState
// (its `act()` strings are methods here, with the same guards); the map's
// camera lives in MapController. Voice, QR codes, parking, reported problems
// and the demo panel were left out (owner decisions 2026-10-22).
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/constants.dart';
import '../../../core/engine/directions.dart';
import '../../../core/engine/graph.dart';
import '../../../core/engine/reroute.dart';
import '../../../core/engine/routing.dart';
import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';
import '../../../core/haptics.dart';
import '../../malls/providers/mall_provider.dart';
import '../../map/providers/map_provider.dart';
import '../../saved/models/saved_items.dart';
import '../../saved/providers/saved_providers.dart';
import '../../search/providers/search_providers.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../models/nav_state.dart';
import '../services/narration.dart';
import '../services/nav_text.dart';
import 'route_options_provider.dart';

class NavController extends Notifier<NavState> {
  @override
  NavState build() {
    final v = ref.watch(currentVenueProvider);
    if (v == null) throw StateError('The navigation needs a mall');
    final s = NavState(v)..routeOpts = _opts();
    // a routing preference changed: distances and the active route are worked out again
    ref.listen(settingsProvider.select((x) => x.wheelchair), (_, _) => _wheelChanged());
    ref.listen(routeOptionsProvider, (_, _) => _routingChanged());
    return s;
  }

  NavState get s => state;
  Graph get gr => s.gr;
  Venue get v => s.v;
  MapController get _map => ref.read(mapProvider.notifier);
  MapView get _mv => ref.read(mapProvider);
  String get _mode => _mv.mode;

  /// The words for this state in the chosen language.
  NavText get text => NavText(s, ref.read(wordsProvider), paceFactor: ref.read(settingsProvider).paceFactor);

  void _notify() => ref.notifyListeners();

  RouteOpts _opts() {
    final o = ref.read(routeOptionsProvider), wheel = ref.read(settingsProvider).wheelchair;
    return RouteOpts(wheel: wheel, throughStores: true, avoid: o.avoid, metric: o.metric);
  }

  void _buzz(String cue) {
    if (ref.read(settingsProvider).vibration) ref.read(hapticsProvider).cue(cue);
  }

  bool get animating => s.playing || s.pulsing || (s.checking && s.autoAnswerAt != null) || s.cueLineAt != null;

  /// The ticker restarts its clock; the next walk step must not count the idle gap.
  void tickerStarted() => s.last = null;

  // ===== The Map tab =====
  /// The Map tab came on screen or went away. The first visit per mall per launch asks where
  /// the shopper is, and the mall's demo trip waits for the answer.
  void setMapVisible(bool on) {
    if (s.mapVisible == on) return;
    s.mapVisible = on;
    if (on) {
      if (!s.visited) {
        s.visited = true;
        s.autoTripPending = s.route == null && s.pendingPlace == null && !s.emergency;
        if (s.user == null) {
          if (!s.locSheet) _openLocSheet(first: true);
        } else if (s.autoTripPending) {
          _startAutoTrip();
        }
      }
      // a ride question waiting for the map: the demo walk answers it two seconds after it is seen
      if (s.checking && s.checkRide != null && s.autoAnswerAt == null) s.autoAnswerAt = s.now + const Duration(seconds: 2);
    }
    _notify();
  }

  // ===== The walk =====
  /// Driven by the shell's ticker: the simulated walk at a real walking pace, and the demo
  /// walk's answer to "Are you at ...?".
  void tick(Duration now) {
    s.now = now;
    var changed = false;
    if (s.checking && s.checkRide != null && s.autoAnswerAt != null && now >= s.autoAnswerAt! && s.mapVisible) {
      s.autoAnswerAt = null;
      _resume(s.checkRide);
      changed = true;
    }
    if (!s.checking) s.autoAnswerAt = null;
    if (s.pulsing) changed = true;
    if (s.cueLineAt != null) {
      if ((now - s.cueLineAt!).inSeconds >= 6) s.cueLineAt = null;
      changed = true;
    }
    final r = s.route;
    if (s.playing && r != null && s.last != null) {
      final dt = math.min(0.1, (now - s.last!).inMicroseconds / 1e6);
      r.progress = math.min(r.total, r.progress + dt * walkMps / ref.read(settingsProvider).paceFactor);
      syncUser();
      changed = true;
    }
    s.last = now;
    if (changed) _notify();
  }

  // ===== Routes =====
  /// Stairs are taken by default only when they save this much (metres ≈ 2 min at a walking pace).
  static const stairsSaveM = 144.0;
  static bool usesStairs(RouteT r) => r.seg.any((e) => isHop(e) && e!.ctype == 'stairs');

  void startRoute(Place p) {
    final u = s.user;
    if (u == null) return;
    s.wcError = null;
    s.helpNote = false;
    s.place = p.id;
    s.near = null;
    s.needsNote = null;
    final o = s.routeOpts = _opts();
    var rs = routesTo(gr, p.id, p.nodes, u.pos, o.wheel, throughStores: true, avoid: o.avoid, metric: o.metric);
    // stairs only when they save about two minutes (Fastest only); the stairs way stays as another way
    if (rs.isNotEmpty && !o.wheel && !o.avoid.contains('stairs') && o.metric == RouteOpts.fastest && s.evac == null && usesStairs(rs.first)) {
      final noStairs = routesTo(gr, p.id, p.nodes, u.pos, o.wheel, throughStores: true, avoid: {...o.avoid, 'stairs'}, metric: o.metric);
      if (noStairs.isNotEmpty && noStairs.first.total < rs.first.total + stairsSaveM) {
        rs = [noStairs.first, ...rs.where((x) => (x.total - noStairs.first.total).abs() > .01)];
      }
    }
    if (rs.isEmpty && o.avoid.isNotEmpty && !o.wheel) {
      // strictly avoided, but nothing else reaches the place: use them, and say so
      rs = routesTo(gr, p.id, p.nodes, u.pos, o.wheel, throughStores: true, metric: o.metric);
      if (rs.isNotEmpty) {
        final used = {for (final e in rs.first.seg) if (isHop(e)) e!.ctype!};
        s.needsNote = o.avoid.firstWhere(used.contains, orElse: () => o.avoid.first);
      }
    }
    if (rs.isEmpty) {
      s.routes = [];
      s.wcError = p.name;
      s.wcPlace = p.id;
      return;
    }
    s.routes = rs;
    s.routeIdx = 0;
    for (final x in rs) {
      x.progress = 0;
    }
    s.arrived = false;
    s.atEnd = false;
    s.heading = null;
    s.transit = null;
    syncUser();
  }

  /// Arrived (confirmed, or out of the building): the shell celebrates (vibration, confetti).
  void _celebrate() => s.arrivalSeq++;

  /// Walking on after a pause or a question.
  void _resume([int? ride]) {
    s.checking = false;
    s.paused = false;
    if (!s.playing) _walk();
  }

  void syncUser() {
    final r = s.route;
    if (r == null) return;
    final at = pointAt(r, r.progress);
    s.user = UserPos(at.lv, at.pos[0], at.pos[1], at.out);
    s.heading = at.heading;
    final rode = s.transit;
    s.transit = at.transit;
    // stepping off a lift, escalator or stairs: the card says what the new floor should look like
    if (rode != null && rode.kind == 'hop' && at.transit == null) s.rideEndAt = (r, r.progress, at.lv, rode.conn);
    // reaching a lift, escalator or stairs, the walk stops and asks "Are you at ...?" (once per ride)
    if (s.playing && rode == null && at.transit != null && at.transit!.kind == 'hop') {
      final hi = s.rideIndex(at.transit!);
      if (hi >= 0 && !(s.askedRide != null && identical(s.askedRide!.$1, r) && s.askedRide!.$2 == hi)) {
        s.askedRide = (r, hi);
        s.playing = false;
        s.paused = true;
        s.checking = true;
        s.checkRide = hi;
        // the demo walk: the question is seen, then it carries on (it waits for the Map tab)
        s.autoAnswerAt = s.mapVisible ? s.now + const Duration(seconds: 2) : null;
      }
    }
    // landings: stairs and escalators pass floors you can see; a lift does not
    if (at.transit != null && at.transit!.kind == 'hop') {
      if (rode == null) s.ridingLv = at.lv;
      if (s.ridingLv != at.lv) s.ridingLv = at.lv;
    } else {
      s.ridingLv = null;
    }
    _cueTurn(r);
    _textCues(r);
    _map.turnToHeading(heading: s.heading, playing: s.playing);
    // at the end: an evacuation is over (the dot is outside); a trip waits for the shopper to confirm
    final was = s.arrived;
    s.atEnd = r.progress >= r.total - 0.01;
    if (s.atEnd) s.playing = false;
    if (s.evac != null) s.arrived = s.atEnd;
    if (s.arrived && !was) _celebrate();
    _map.followDot(at, playing: s.playing);
  }

  void stopRoute() {
    _endTrip(TripOutcome.stopped);
    s.routes = [];
    s.place = null;
    s.arrived = false;
    s.atEnd = false;
    s.playing = false;
    s.checking = false;
    s.paused = false;
    s.rideEndAt = null;
    s.cueLine = null;
    s.cueLineAt = null;
    s.heading = null;
    s.transit = null;
    s.wcError = null;
    s.needsNote = null;
    s.near = null;
    s.helpNote = false;
    s.reroute = null;
    s.pendingPlace = null;
  }

  // ===== The trip history =====
  void _beginRecord(Place p) {
    if (p.kind == 'conn' || s.route == null) return;
    final mallId = ref.read(mallProvider);
    if (mallId == null) return;
    final o = ref.read(routeOptionsProvider);
    s.tripRecord = ref.read(historyProvider.notifier).start(mallId: mallId, placeId: p.id, placeName: p.name, options: o, wheelchair: s.routeOpts.wheel);
    ref.read(visitsProvider(mallId).notifier).visit(p.id);
  }

  void _endTrip(TripOutcome outcome) {
    final id = s.tripRecord;
    if (id == null) return;
    s.tripRecord = null;
    ref.read(historyProvider.notifier).finish(id, outcome);
  }

  /// The mall is about to change: the trip in progress counts as stopped.
  void endForSwitch() => _endTrip(TripOutcome.stopped);

  /// A new trip to [p] from where the shopper is.
  void _beginTrip(Place p) {
    _map.leaveStack();
    s.reroute = null;
    _endTrip(TripOutcome.stopped);
    s.autoTripPending = false;
    startRoute(p);
    _beginRecord(p);
    final u = s.user;
    if (u != null) _map.m.level = u.lv;
  }

  void _startAutoTrip() {
    s.autoTripPending = false;
    final p = v.placeById(v.tripTarget);
    if (p != null) _beginTrip(p);
  }

  // ===== What the screens do =====
  /// Get Directions / Go: a route to the place from where the shopper is. With no position yet,
  /// "Where are you?" opens first and the route follows the answer.
  void startTo(String id) {
    if (s.emergency) return;
    final p = s.placeById(id);
    if (p == null) return;
    s.near = null;
    if (s.user == null) {
      stopRoute();
      s.place = id;
      s.pendingPlace = id;
      s.autoTripPending = false;
      _openLocSheet(first: false);
      _notify();
      return;
    }
    _beginTrip(p);
    _notify();
  }

  /// A place tapped on the map (or picked from a list): its card in the sheet. The old route
  /// goes, finished or not.
  Place? selectPlace(String id) {
    if (s.emergency) return null;
    s.reroute = null;
    s.helpNote = false;
    s.place = id;
    s.wcError = null;
    s.near = null;
    if (s.route != null) {
      _endTrip(TripOutcome.stopped);
      s.routes = [];
      s.playing = false;
      s.arrived = false;
      s.atEnd = false;
      s.checking = false;
      s.rideEndAt = null;
    }
    _notify();
    return s.placeById(id);
  }

  /// Pick a place and fly to it.
  void pick(String id) {
    final p = selectPlace(id);
    if (p != null) _map.showPlace(p);
  }

  /// The nearest places of a kind (a chip on the map), or closing that list.
  void showNearest(String type) {
    if (s.emergency) return;
    _map.leaveStack();
    s.reroute = null;
    _endTrip(TripOutcome.stopped);
    s.routes = [];
    s.place = null;
    s.playing = false;
    s.arrived = false;
    s.atEnd = false;
    s.wcError = null;
    if (s.near != null && s.near!.type == type) {
      s.near = null;
    } else {
      final list = s.nearest(type);
      s.near = Near(type, list.map((p) => p.id).toList());
      if (list.isNotEmpty) _map.showSpot(list[0].lv, list[0].at[0], list[0].at[1], zoom: 4);
    }
    _notify();
  }

  void clearNearest() {
    s.near = null;
    _notify();
  }

  void stop() {
    if (s.emergency) return;
    stopRoute();
    _notify();
  }

  void chooseAlternative(int i) {
    if (s.emergency) return;
    s.reroute = null;
    s.routeIdx = i;
    final r = s.route;
    if (r != null) {
      r.progress = 0;
      syncUser();
    }
    _notify();
  }

  /// "I've arrived": the shopper confirms, so now it is a fact.
  void confirmArrived() {
    s.reroute = null;
    final r = s.route;
    if (r != null) {
      r.progress = r.total;
      syncUser();
      if (!s.arrived) {
        s.arrived = true;
        s.playing = false;
        _celebrate();
        _endTrip(TripOutcome.arrived);
      }
    }
    _notify();
  }

  /// Start (or walk again): the simulated walk runs at a walking pace.
  void _walk() {
    if (s.reroute != null) _confirmReroute(); // walking on takes the previewed way
    final r = s.route;
    if (r == null) return;
    if (s.arrived || s.atEnd) {
      r.progress = 0;
      s.arrived = false;
      s.atEnd = false;
      syncUser();
    }
    s.playing = true;
    s.checking = false;
    s.paused = false;
  }

  void start() {
    _walk();
    _notify();
  }

  void pause() {
    if (s.route != null && s.playing) {
      s.playing = false;
      s.paused = true;
      s.checking = true;
      s.checkRide = null;
    }
    _notify();
  }

  void resume() {
    _resume(s.checkRide);
    _notify();
  }

  /// "Yes, I'm here".
  void answerYes() {
    if (s.checkRide != null && !s.playing) {
      _resume(s.checkRide); // at the stairs as expected: ride on
    } else {
      s.checking = false;
    }
    _notify();
  }

  /// "No, I'm somewhere else": after a pause or ride check, a buzz and "Where are you?" with the
  /// drift line; after the arrival question, just "Where are you?".
  void answerNo() {
    final p = s.prompt;
    if (p == 'here' || p == 'ride') {
      s.locDrift = true;
      _buzz('alert');
    }
    s.checking = false;
    _map.m.sheetMin = false;
    s.locSheet = true;
    s.locFirst = false;
    s.locQuery = '';
    _notify();
  }

  /// About 20 m before a turn or a lift / escalator / stairs: one buzz, a different one per kind.
  void _cueTurn(RouteT r) {
    if (!ref.read(settingsProvider).vibration || !s.playing) return;
    if (!identical(r, s.cuedFor)) {
      s.cuedFor = r;
      s.cuedDir = -1;
    }
    final up = upcoming(s.directions, r.progress);
    if (up == null) return;
    final (i, d) = up;
    if (i <= s.cuedDir || !(d.isTurn || d.isUpDown) || d.atM - r.progress > turnCueM) return;
    s.cuedDir = i;
    ref.read(hapticsProvider).cue(d.isTurn ? (d.turn!.endsWith('left') ? 'left' : 'right') : 'updown');
  }

  static const turnCueM = 20.0;

  /// Checkpoints, "coming up" and closeness lines on the direction card, each once, in its place,
  /// and never when a turn is about to be cued.
  void _textCues(RouteT r) {
    if (s.arrived || !s.playing) return;
    final dirs = s.directions, up = upcoming(dirs, r.progress), u = s.user;
    if (up == null || u == null) return;
    final (i, d) = up;
    // riding, or at the foot of a lift, escalator or stairs: the next line waits until you step off
    if (s.transit != null || (i > 0 && dirs[i - 1].isUpDown && u.lv != d.lv)) return;
    if (!identical(r, s.cuesFor)) {
      s.cuesFor = r;
      s.cuesSaid.clear();
    }
    for (final c in text.cuesFor(i)) {
      if (r.progress < c.atM || r.progress > c.atM + 6) continue;
      if (!s.cuesSaid.add('$i:${c.key}')) continue;
      if (_turnCueNear(r.progress)) continue; // the turn's cue wins
      s.cueLine = c.line;
      s.cueLineAt = s.now;
      return;
    }
  }

  /// Is a turn's "coming up" or "now" due within 5 m of here? (A turn already passed does not count.)
  bool _turnCueNear(double m) => s.directions.any((d) => (d.isTurn || d.isUpDown) && d.atM > m - .5 && ((d.atM - turnCueM - m).abs() < 5 || d.atM - m < 5));

  // ===== Other ways =====
  // "Find another way" asks nothing and keeps nothing: it offers ways around the stretch just
  // ahead, and the current way.
  int _problemSeq = 0;

  void findAnotherWay() {
    if (s.emergency) return;
    final r = s.route;
    if (r == null || s.arrived || s.evac != null) return;
    final wasPlaying = s.playing;
    s.playing = false;
    final ahead = problemAhead(gr, r, ++_problemSeq);
    s.reroute = RerouteSession(placeId: r.placeId, fromAlert: false, wasPlaying: wasPlaying, savedRoutes: s.routes, savedIdx: s.routeIdx, avoid: ahead);
    _rebuildOptions();
    _notify();
  }

  void _rebuildOptions() {
    final rr = s.reroute!, p = s.placeById(rr.placeId), u = s.user;
    if (p == null || u == null) return;
    final from = u.pos, o = s.routeOpts;
    final original = buildRoute(gr, p.id, p.nodes, from, o);
    final avoid = rr.avoid;
    var arounds = waysAround(gr, p.id, p.nodes, from, RouteOpts(wheel: o.wheel, throughStores: true, metric: o.metric, banEdges: avoid?.edges, banConn: avoid?.conns));
    final opts = <RouteOption>[];
    if (original != null) {
      // nothing ahead to go around: offer only ways that really differ
      if (avoid == null || !routeHits(original, [avoid])) arounds = arounds.where((a) => routeSimilarity(a, original) <= .8).toList();
      opts.add(RouteOption(original, 'current', 0));
    }
    for (var i = 0; i < arounds.length; i++) {
      opts.add(RouteOption(arounds[i], 'around', i + 1));
    }
    rr.options = opts;
    rr.sel = opts.indexWhere((o) => o.kind == 'around');
    if (rr.sel < 0) rr.sel = 0;
    rr.nearby = s.similarPlaces(p);
    s.routes = [for (final o in opts) o.route];
    s.routeIdx = rr.sel;
    s.arrived = false;
    s.atEnd = false;
    if (s.routes.isNotEmpty) syncUser();
  }

  void previewOption(int i) {
    final rr = s.reroute;
    if (rr == null || i >= rr.options.length) return;
    rr.sel = i;
    s.routeIdx = i;
    syncUser();
    _notify();
  }

  void _confirmReroute() {
    final rr = s.reroute;
    if (rr == null) return;
    if (rr.options.isNotEmpty) {
      s.routes = [rr.options[rr.sel].route];
      s.routeIdx = 0;
      syncUser();
    } else {
      s.routes = rr.savedRoutes;
      s.routeIdx = rr.savedIdx;
    }
    s.reroute = null;
    s.playing = rr.wasPlaying && s.route != null && !s.arrived;
  }

  void confirmReroute() {
    _confirmReroute();
    _notify();
  }

  void _cancelReroute() {
    final rr = s.reroute;
    if (rr == null) return;
    s.routes = rr.savedRoutes;
    s.routeIdx = rr.savedIdx;
    syncUser();
    s.reroute = null;
    s.playing = rr.wasPlaying;
  }

  void cancelReroute() {
    _cancelReroute();
    _notify();
  }

  /// "Or go somewhere similar": a trip there instead.
  void goSimilar(String id) {
    final rr = s.reroute, p = s.placeById(id);
    if (p == null) return;
    s.reroute = null;
    _beginTrip(p);
    s.playing = (rr?.wasPlaying ?? false) && s.route != null;
    _notify();
  }

  /// "Get help": during an evacuation, what to tell staff; otherwise the way to the nearest information desk.
  void help() {
    if (s.emergency) {
      s.evacHelp = !s.evacHelp;
    } else {
      _getHelp();
    }
    _notify();
  }

  void _getHelp() {
    final desks = v.places.where((p) => p.cat == 'info' && p.status == 'open');
    final ranked = [for (final d in desks) (d, s.distOf(d))].where((x) => x.$2 != null).toList();
    if (ranked.isEmpty) return;
    final desk = stableSorted(ranked, (a, b) => cmpNum(a.$2!, b.$2!)).first.$1;
    final rr = s.reroute;
    s.reroute = null;
    _beginTrip(desk);
    s.helpNote = true;
    s.playing = (rr?.wasPlaying ?? false) && s.route != null;
  }

  // ===== Emergency evacuation =====
  /// Started from More. Nothing may replace the way out until it is stopped.
  void startEmergency() {
    if (!s.emergency) {
      s.emergency = true;
      s.reroute = null;
      s.near = null;
      s.evacHelp = false;
      s.pendingPlace = null;
      s.autoTripPending = false;
      _endTrip(TripOutcome.stopped); // evacuations are not recorded; the trip they replace stops
      _map.leaveStack();
      if (s.user == null) {
        // the way out needs to know where you are
        _openLocSheet(first: false);
      } else {
        _evacuate();
      }
    }
    final u = s.user;
    if (u != null) {
      if (u.out) {
        _map.m.level = u.lv;
      } else {
        _map.showSpot(u.lv, u.x, u.y);
      }
    }
    _notify();
  }

  void _evacuate() {
    final u = s.user;
    if (u == null) return;
    final e = evacuate(v, u.pos, wheel: s.routeOpts.wheel, banEdges: const {}, banConn: const {}, blockedExits: const {});
    s.evac = e;
    s.place = null;
    s.wcError = null;
    s.helpNote = false;
    s.routes = e.route == null ? [] : [e.route!];
    s.routeIdx = 0;
    s.arrived = false;
    s.atEnd = false;
    if (s.route != null) syncUser();
  }

  void stopEmergency() {
    s.emergency = false;
    s.evac = null;
    s.evacHelp = false;
    s.routes = [];
    s.playing = false;
    s.arrived = false;
    s.atEnd = false;
    s.heading = null;
    s.transit = null;
    _notify();
  }

  // ===== Where are you? =====
  // There is no real positioning yet (MOKO beacons later), so the shopper says where they are:
  // a place near them (exact) or just their floor (approximate, tap to refine).
  void _openLocSheet({required bool first}) {
    s.locSheet = true;
    s.locFirst = first;
    s.locQuery = '';
    _map.m.sheetMin = false;
  }

  /// The pin button, or the place page's Get Directions with no position yet.
  void openLocation() {
    _openLocSheet(first: false);
    _notify();
  }

  /// Closed without an answer: a destination waiting for it is dropped (Get Directions asks again).
  void closeLocation() {
    s.locSheet = false;
    s.locDrift = false;
    if (s.user == null && s.pendingPlace != null) {
      s.pendingPlace = null;
      s.place = null;
    }
    _notify();
  }

  void setLocQuery(String q) {
    s.locQuery = q;
    _notify();
  }

  void locAtPlace(String id) {
    final p = s.placeById(id);
    if (p != null && p.nodes.isNotEmpty) _setLocationAt(p.nodes.first, approx: false);
    _notify();
  }

  void locAtFloor(int lv) {
    final c = v.levelCentre(lv);
    _setLocationAt(gr.nearestNodeAt(lv, c.x, c.y)!, approx: true);
    _notify();
  }

  void finishRefine() {
    s.refining = false;
    _notify();
  }

  /// A tap while refining an approximate location: the nearest walkable spot on the shown level.
  void refineAt(int lv, double x, double y) {
    final k = gr.nearestNodeAt(lv, x, y);
    if (k == null) return;
    final n = gr.nodes[k]!;
    s.user = UserPos(n.lv, n.x, n.y, n.out);
    s.approximate = false;
    s.refining = false;
    _afterLocation(fly: false);
    _notify();
  }

  void _setLocationAt(String nodeKey, {required bool approx}) {
    final n = gr.nodes[nodeKey]!;
    s.user = UserPos(n.lv, n.x, n.y, n.out);
    s.approximate = approx;
    s.refining = approx;
    _afterLocation();
  }

  void _afterLocation({bool fly = true}) {
    final u = s.user!;
    s.locSheet = false;
    s.locDrift = false;
    s.playing = false;
    s.checking = false;
    s.reroute = null;
    s.heading = null;
    s.transit = null;
    s.clearDistCache();
    _map.m.level = u.lv;
    if (s.evac != null || s.emergency) {
      _evacuate();
    } else if (s.pendingPlace != null) {
      final p = s.placeById(s.pendingPlace!);
      s.pendingPlace = null;
      if (p != null) _beginTrip(p);
    } else if (s.place != null && s.routes.isNotEmpty) {
      final p = s.placeById(s.place!);
      if (p != null) startRoute(p); // the same destination, from here
    } else if (s.autoTripPending) {
      _startAutoTrip();
    }
    if (s.near != null) s.near = Near(s.near!.type, s.nearest(s.near!.type).map((p) => p.id).toList());
    if (fly) {
      _map.leaveStack();
      _map.flyTo(u.x, u.y, math.max(_mv.cam.zoom, 3.5 * v.ratio));
    }
  }

  // ===== Routing preferences =====
  void _wheelChanged() {
    s.routeOpts = _opts();
    s.clearDistCache();
    final p = s.place == null ? null : s.placeById(s.place!);
    if (s.evac != null) {
      _evacuate(); // the way out follows the wheelchair setting
    } else if (s.reroute != null) {
      _rebuildOptions();
    } else if (p != null && (s.route != null || s.wcError != null)) {
      startRoute(p);
    }
    _notify();
  }

  void _routingChanged() {
    s.routeOpts = _opts();
    s.clearDistCache();
    final p = s.place == null ? null : s.placeById(s.place!);
    if (s.reroute != null) {
      _rebuildOptions();
    } else if (s.evac == null && p != null && s.route != null) {
      startRoute(p);
    }
    _notify();
  }

  // ===== Back =====
  /// Returns true when Back closed something on the map; false means Back may leave the Map tab.
  bool handleBack() {
    if (s.locSheet) {
      s.locSheet = false;
      s.locDrift = false;
      if (s.user == null) s.pendingPlace = null;
    } else if (s.refining) {
      s.refining = false;
    } else if (s.reroute != null) {
      _cancelReroute();
    } else if (!s.emergency && (s.wcError != null || s.near != null || s.route != null || s.place != null)) {
      // Back never stops an evacuation
      stopRoute();
    } else if (_mv.cam.ex > 0.5) {
      _map.tweenProp('ex', 0);
    } else {
      return false;
    }
    _notify();
    return true;
  }

  /// Moves the walk to [v] / 1000 of the route, by hand (tests).
  void debugScrub(double v) {
    final r = s.route;
    if (r == null) return;
    s.playing = false;
    s.checking = false;
    s.paused = false;
    s.askedRide = null; // moved by hand: the next ride asks again
    r.progress = r.total * (v / 1000);
    syncUser();
    final u = s.user!;
    if (_mode == 'building') _map.m.level = u.lv;
    _mv.cam
      ..cx = u.x
      ..cy = u.y;
    _notify();
  }
}

final navProvider = NotifierProvider<NavController, NavState>(NavController.new);

/// The navigation's words, for the screens.
final navTextProvider = Provider<NavText>((ref) {
  final s = ref.watch(navProvider);
  return NavText(s, ref.watch(wordsProvider), paceFactor: ref.watch(settingsProvider.select((x) => x.paceFactor)));
});

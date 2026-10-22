// The Map tab, driven through the real UI (from the demo's interaction, pause,
// ux and voice tests): saying where you are, the demo trip, the walk at a real
// pace with its questions, the map's tools and gestures, the sheet, other ways,
// arriving, the evacuation, Back, and what the screen reader hears.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/features/map/providers/map_provider.dart';
import 'package:liqo_mobile/features/navigation/models/nav_state.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';
import 'package:liqo_mobile/features/navigation/services/narration.dart';
import 'package:liqo_mobile/features/settings/providers/settings_provider.dart';

import '../support/app.dart';
import '../support/spots.dart';

extension on AppHarness {
  NavState get s => c.read(navProvider);
  NavController get nav => c.read(navProvider.notifier);
  MapView get mv => c.read(mapProvider);
  MapController get map => c.read(mapProvider.notifier);

  Future<void> openMap() async {
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await step(20);
  }

  /// Says where the shopper is without the sheet (the sheet itself is tested below).
  Future<void> placeAt(Pos p) async {
    nav.refineAt(p.lv, p.x, p.y);
    await step(5);
  }
}

/// A point of the plan on screen, projected the way the painter does.
Offset project(MapView mv, double x, double y, double z) {
  mv.prep();
  final cam = mv.cam;
  final u = x - cam.cx, v = y - cam.cy, ru = u * cam.c - v * cam.s, rv = u * cam.s + v * cam.c;
  final ky = 1 + (cam.kyB - 1) * cam.tilt, kz = cam.kzB * cam.tilt;
  return Offset(mv.centreX + ru * cam.S, mv.centreY + rv * cam.S * ky - z * cam.S * kz);
}

void main() {
  testWidgets('first visit: "Where are you?"; a floor is approximate and a tap refines it; then the demo trip', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    expect(find.text('Where are you?'), findsOneWidget);
    expect(h.s.user, isNull);
    expect(h.s.route, isNull, reason: 'the demo trip waits for a position');
    await tester.tap(find.byKey(const ValueKey('locfloor-0')));
    await h.step(40);
    expect(h.s.approximate, isTrue);
    expect(find.text('Approximate · tap the map where you are'), findsOneWidget);
    // the demo trip has started from the floor's centre
    expect(h.s.place, h.s.v.tripTarget);
    expect(h.s.route, isNotNull);
    // a tap on the plan refines the spot
    h.mv.cam
      ..zoom = 5 * h.s.v.ratio
      ..cx = 750
      ..cy = 350
      ..tilt = 1;
    await tester.pump();
    await tester.tapAt(Offset(h.mv.centreX + 20, h.mv.centreY));
    await h.step(5);
    expect(h.s.approximate, isFalse);
    expect(h.s.refining, isFalse);
    expect(h.s.user!.lv, 0);
    expect(h.s.route!.verts.first.x, h.s.user!.x, reason: 'the route starts from the refined spot');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shop near me, by its name', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await tester.enterText(find.byKey(const ValueKey('loc-search')), 'Information desk');
    await tester.pump();
    final row = find.byKey(const ValueKey('loc-G-INFO'));
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await h.step(40);
    final info = h.s.placeById('G-INFO')!, n = h.s.gr.nodes[info.nodes.first]!;
    expect((h.s.user!.lv, h.s.user!.x, h.s.user!.y), (n.lv, n.x, n.y));
    expect(h.s.locSheet, isFalse);
    expect(h.s.route!.placeId, h.s.v.tripTarget);
  });

  testWidgets('Skip: no position and no trip; distances stay hidden; Get directions asks again', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await tester.tap(find.text('Skip for now'));
    await h.step(10);
    expect(h.s.locSheet, isFalse);
    expect(h.s.user, isNull);
    expect(h.s.route, isNull);
    h.nav.pick('G-EHM');
    await h.step(30);
    expect(find.text('Hypermart Bayview'), findsWidgets);
    expect(find.textContaining('to walk'), findsNothing);
    await tester.tap(find.text('Get directions'));
    await h.step(10);
    expect(h.s.locSheet, isTrue);
    expect(find.text('Tell us where you are, and the way there will show.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('locfloor-0')));
    await h.step(30);
    expect(h.s.route!.placeId, 'G-EHM', reason: 'the waiting destination, not the demo trip');
  });

  testWidgets('Start walks at a real walking pace; pause asks "Are you here?"; No relocates; Resume walks on', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(scenarioStart(h.s.v));
    expect(h.s.route, isNotNull);
    expect(h.s.playing, isFalse);
    await tester.tap(find.bySemanticsLabel('Start the walk'));
    await tester.pump();
    expect(h.s.playing, isTrue);
    final p0 = h.s.route!.progress;
    await h.step(125); // two seconds
    expect(h.s.route!.progress - p0, inInclusiveRange(2.3, 3.3), reason: '1.4 m/s');
    await tester.tap(find.bySemanticsLabel('Pause the walk'));
    await tester.pump();
    expect(h.s.playing, isFalse);
    expect(h.s.checking, isTrue);
    // a pop-up over the map, not a note in the sheet: swiping the sheet down does not hide it
    expect(find.byKey(const ValueKey('prompt')), findsOneWidget);
    expect(find.textContaining('Are you here?'), findsOneWidget);
    h.map.sheetDown();
    await tester.pump();
    expect(find.byKey(const ValueKey('prompt')), findsOneWidget);
    h.map.sheetUp();
    await tester.tap(find.text("Yes, that's right"));
    await tester.pump();
    expect(h.s.checking, isFalse);
    expect(find.textContaining('Are you here?'), findsNothing);
    // again, and this time no
    await tester.tap(find.bySemanticsLabel('Resume the walk'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Pause the walk'));
    await tester.pump();
    await tester.tap(find.text("No, I'm somewhere else"));
    await tester.pump();
    expect(h.s.locSheet, isTrue);
    expect(h.haptics.cues, contains('alert'));
    expect(find.text("Looks like you've drifted off the way. Let's start again from here."), findsOneWidget);
    // a description, not a name
    await tester.enterText(find.byKey(const ValueKey('loc-search')), 'near the ATM beside the escalator');
    await tester.pump();
    final first = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('loc-') && (w.key! as ValueKey<String>).value != 'loc-search').first;
    await tester.ensureVisible(first);
    await tester.pump();
    await tester.tap(first);
    await h.step(10);
    expect(h.s.locSheet, isFalse);
    expect(h.s.route, isNotNull);
    expect(h.s.route!.progress, 0);
    expect(h.s.playing, isFalse);
    await tester.tap(find.bySemanticsLabel('Resume the walk'));
    await tester.pump();
    expect(h.s.playing, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the walk goes on while another tab is shown; its question waits for the Map tab', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(scenarioStart(h.s.v));
    h.nav.startTo('3-M1'); // up the West Court escalators
    final hop = h.s.directions.firstWhere((d) => d.isUpDown);
    h.nav.debugScrub((hop.atM - 3) / h.s.route!.total * 1000);
    h.nav.start();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await h.step(10);
    final p0 = h.s.route!.progress;
    await h.step(60);
    expect(h.s.route!.progress, greaterThan(p0), reason: 'walking on Home');
    await h.step(200);
    expect(h.s.checking, isTrue, reason: 'stopped at the escalator');
    await h.step(200);
    expect(h.s.checking, isTrue, reason: 'still waiting: the map is not shown');
    await h.openMap();
    expect(find.byKey(const ValueKey('prompt')), findsOneWidget);
    await h.step(140);
    expect(h.s.checking, isFalse, reason: 'the demo walk answers two seconds after it is seen');
    expect(h.s.playing, isTrue);
  });

  testWidgets('tapping a building flies in and shows its floor plan', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await tester.tap(find.text('Skip for now'));
    await h.step(10);
    expect(h.mv.mode, 'site');
    expect(find.text('Whole site · tap a building to go in'), findsOneWidget);
    final roof = project(h.mv, 740, 350, h.s.v.zOf(2) + 5);
    await tester.tapAt(roof);
    await h.step(45);
    expect(h.mv.mode, 'building');
    expect(find.byKey(const ValueKey('wing-G')), findsOneWidget); // the wing pad
  });

  testWidgets('level chips, the wing pad and the stacked view; Back leaves the stack', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(spot(h.s.v, 0, 750, 350));
    h.nav.stop();
    h.mv.cam.zoom = 4 * h.s.v.ratio;
    h.map.notify();
    await h.step(5);
    await tester.tap(find.byKey(const ValueKey('level-2')));
    await tester.pump();
    expect(h.mv.level, 2);
    await tester.tap(find.byKey(const ValueKey('wing-G')));
    await h.step(45);
    expect(h.mv.cam.zoom, closeTo(6.5 * h.s.v.ratio, 0.01));
    await tester.tap(find.byKey(const ValueKey('tool-stack')));
    await h.step(45);
    expect(h.mv.mode, 'stack');
    expect(find.text('All levels · tap one to open it'), findsOneWidget);
    // the camera is frozen in the stack
    h.map.flyToSite();
    expect(h.mv.cam.zoom, closeTo(6.5 * h.s.v.ratio, 0.01));
    expect(h.nav.handleBack(), isTrue);
    await h.step(45);
    expect(h.mv.mode, isNot('stack'));
  });

  testWidgets('pinch zooms and two fingers turn the map (there is no compass)', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await tester.tap(find.text('Skip for now'));
    await h.step(10);
    h.mv.cam.zoom = 4 * h.s.v.ratio;
    h.map.notify();
    await tester.pump();
    final c = Offset(h.mv.centreX, h.mv.centreY);
    final a = await tester.startGesture(c + const Offset(-40, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(40, 0), pointer: 2);
    await tester.pump();
    const ang = 30 * math.pi / 180;
    for (var i = 1; i <= 10; i++) {
      final t = i / 10, r = 40 + 40 * t, th = ang * t;
      await a.moveTo(c + Offset(-math.cos(th) * r, -math.sin(th) * r));
      await b.moveTo(c + Offset(math.cos(th) * r, math.sin(th) * r));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(h.mv.cam.zoom, greaterThan(5 * h.s.v.ratio));
    expect(h.mv.cam.rot, inInclusiveRange(ang * .5, ang));
    expect(h.mv.rotated, isTrue);
    expect(find.byKey(const ValueKey('compass')), findsNothing);
  });

  testWidgets('Back closes things in order, then goes Home, then may exit', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    expect(h.s.locSheet, isTrue);
    expect(h.nav.handleBack(), isTrue);
    expect(h.s.locSheet, isFalse);
    await h.placeAt(scenarioStart(h.s.v));
    expect(h.s.route, isNotNull);
    expect(h.nav.handleBack(), isTrue);
    expect(h.s.route, isNull);
    expect(h.nav.handleBack(), isFalse);
    // the shell: Back on the Map tab's first screen goes Home
    await tester.binding.handlePopRoute();
    await h.step(10);
    expect(find.text('Categories'), findsOneWidget);
  });

  testWidgets('the tools and the level chips fold and unfold, and stay so', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(spot(h.s.v, 0, 750, 350));
    h.nav.stop();
    h.mv.cam.zoom = 4 * h.s.v.ratio;
    h.map.notify();
    await h.step(5);
    expect(find.byKey(const ValueKey('tool-3d')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('railfold')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-3d')), findsNothing);
    expect(h.c.read(settingsProvider).railFolded, isTrue);
    await tester.tap(find.byKey(const ValueKey('railfold')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tool-3d')), findsOneWidget);
    expect(find.byKey(const ValueKey('level-4')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('levelsfold')));
    await tester.pump();
    expect(find.byKey(const ValueKey('level-4')), findsNothing);
    expect(h.store.get(Keys.settings), contains('"levelsFolded":true'));
  });

  testWidgets('the sheet swipes down to one line and back up; it never ends the route', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(scenarioStart(h.s.v));
    expect(find.byKey(const ValueKey('direction-card')), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('sheet')), const Offset(0, 160));
    await h.step(5);
    expect(h.mv.sheetMin, isTrue);
    expect(h.s.route, isNotNull);
    expect(find.byKey(const ValueKey('direction-card')), findsNothing);
    expect(find.byKey(const ValueKey('walk')), findsOneWidget, reason: 'the walk button joins the tools');
    await tester.drag(find.byKey(const ValueKey('sheet')), const Offset(0, -120));
    await h.step(5);
    expect(h.mv.sheetMin, isFalse);
    expect(find.byKey(const ValueKey('direction-card')), findsOneWidget);
  });

  testWidgets('Find another way: the options, and the chosen one has its own Go button', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(scenarioStart(h.s.v));
    h.nav.debugScrub(120 / h.s.route!.total * 1000);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reroute')));
    await tester.pump();
    expect(find.text('Your current way'), findsOneWidget);
    expect(find.text('Way around 1'), findsOneWidget);
    final sel = h.s.reroute!.sel;
    await tester.tap(find.byKey(ValueKey('rrgo-$sel')));
    await tester.pump();
    expect(h.s.reroute, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arriving buzzes and fires confetti once; an evacuation gets only the buzz', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(scenarioStart(h.s.v));
    h.nav.debugScrub(1000);
    await tester.pump();
    expect(find.text("I've arrived"), findsOneWidget);
    await tester.tap(find.text("I've arrived"));
    await tester.pump();
    expect(h.s.arrived, isTrue);
    expect(h.haptics.cues.where((c) => c == 'arrive'), hasLength(1));
    expect(find.textContaining('You have arrived at'), findsOneWidget);
    await h.step(5);
    await tester.pump(const Duration(seconds: 3));
    // the evacuation: out of the building is an arrival too, buzzed but not celebrated
    h.nav.stop();
    await h.placeAt(spot(h.s.v, 0, 750, 350));
    h.nav.stop();
    h.nav.startEmergency();
    await tester.pump();
    h.nav.debugScrub(1000);
    await tester.pump();
    expect(h.s.arrived, isTrue);
    expect(h.haptics.cues.where((c) => c == 'arrive'), hasLength(2));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Emergency evacuation from More: the way out on the map, stairs only; Stop ends it', (tester) async {
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(spot(h.s.v, 1, 750, 310));
    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await h.step(10);
    await tester.tap(find.byKey(const ValueKey('more-emergency')));
    await h.step(30);
    expect(h.s.emergency, isTrue);
    expect(find.text('Emergency: get out by the nearest exit'), findsOneWidget);
    expect(find.text('Emergency evacuation'), findsOneWidget);
    expect(find.text('Use the stairs, not the lifts'), findsOneWidget);
    expect(h.s.route!.seg.any((e) => isHop(e) && e!.ctype == 'lift'), isFalse);
    await tester.ensureVisible(find.text('Stop evacuation'));
    await tester.tap(find.text('Stop evacuation'));
    await tester.pump();
    expect(h.s.emergency, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the screen reader: every map button is named; the map is summed up; level chips say where you are', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await pumpApp(tester);
    await h.openMap();
    await h.placeAt(spot(h.s.v, 0, 750, 350));
    h.mv.cam.zoom = 4 * h.s.v.ratio;
    h.map.notify();
    await h.step(5);
    for (final label in ['Set my location', 'Centre on me', '3D view', 'Whole site', 'All levels', 'Hide map tools', 'Hide other levels', 'Where do you want to go?']) {
      expect(find.bySemanticsLabel(label), findsWidgets, reason: label);
    }
    expect(find.bySemanticsLabel(RegExp(r'^Map\. Showing ground floor\. You are on ground floor')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ground floor, you are here')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Mall: Bayview Grand')), findsOneWidget);
    // the direction card says the whole sentence, not the metres
    final next = h.s.nextDirection!;
    expect(find.bySemanticsLabel(h.c.read(navTextProvider).narrate(next.$1).text), findsOneWidget);
    handle.dispose();
  });
}

// Round 18 (owner decisions 2026-10-22): an editor anyone can use. Guided steps
// (Plan, Scale, Read with AI, Rooms, Publish) are the default; dragging only
// moves the view; only a selected wall's round end handles drag; tools do one
// thing each and every change is one Undo away; stray keys never delete.
// The AI's scale (read from a dimension on the plan) is applied as an undo step.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/guided/geometry.dart';
import 'package:gabay_admin/features/map_editor/map_canvas.dart';
import 'package:gabay_admin/features/map_editor/map_editor_view.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/picture_convert.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

/// Two 10 × 10 m rooms side by side, walls around and between them, and a plan.
LayoutDoc _doc({String nameB = 'Unit B'}) => LayoutDoc(buildings: [
      Building(id: 'bd-1', name: 'B', levels: [
        Level(
          id: 'lv-1',
          name: 'G',
          outline: Poly(outer: [[0, 0], [20, 0], [20, 10], [0, 10]]),
          backdrop: Backdrop(id: 'abcdef0123456789abcdef0123456789', cx: 10, cz: 5, mpp: 0.05),
          walls: [
            Wall(id: 'w-top', a: [0, 0], b: [20, 0], t: 0.2, kind: 'solid'),
            Wall(id: 'w-bot', a: [0, 10], b: [20, 10], t: 0.2, kind: 'solid'),
            Wall(id: 'w-mid', a: [10, 0], b: [10, 10], t: 0.15, kind: 'solid'),
          ],
          spaces: [
            Space(id: 'sp-a', name: 'Unit A', type: 'retail', shape: Poly(outer: [[0, 0], [10, 0], [10, 10], [0, 10]])),
            Space(id: 'sp-b', name: nameB, type: 'retail', shape: Poly(outer: [[10, 0], [20, 0], [20, 10], [10, 10]])),
          ],
        ),
      ]),
    ]);

Level _level(ProviderContainer c) => c.read(editorProvider).level!;
Space? _space(ProviderContainer c, String id) => _level(c).spaces.cast<Space?>().firstWhere((s) => s!.id == id, orElse: () => null);

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ---- The canvas on its own ----

late ProviderContainer canvasC;

Future<void> _canvasOnly(WidgetTester tester) async {
  // The plan picture is fetched from the (fake) API.
  ApiClient.instance.dio.httpClientAdapter = FakeApiAdapter(role: 'mall_admin');
  canvasC = ProviderContainer();
  canvasC.read(editorProvider.notifier).loadLocal(_doc(), guided: true);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: canvasC,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: MessageOverlay(child: Center(child: SizedBox(width: 600, height: 400, child: MapCanvas())))),
    ),
  ));
  await tester.pump();
}

/// A canvas test that lets the plan picture's fetch finish before it ends.
void _canvasTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await _steps(tester, 3);
  });
}

MapCanvasState _canvas(WidgetTester t) => t.state<MapCanvasState>(find.byType(MapCanvas));

/// Screen position of a level point, using the canvas's own transform.
Offset _at(WidgetTester t, double x, double z) {
  final c = _canvas(t);
  return t.getTopLeft(find.byType(MapCanvas)) + c.debugOrigin + Offset(x * c.debugScale, z * c.debugScale);
}

Future<void> _drag(WidgetTester tester, Offset from, Offset by) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
  await g.down(from);
  await tester.pump();
  for (var i = 1; i <= 4; i++) {
    await g.moveBy(by / 4);
    await tester.pump();
  }
  await g.up();
  await tester.pump();
}

Future<void> _click(WidgetTester tester, double x, double z) async {
  await tester.tapAt(_at(tester, x, z), kind: PointerDeviceKind.mouse);
  await tester.pump();
}

// ---- The whole editor page ----

Future<(ProviderContainer, FakeApiAdapter, SharedPreferences)> _page(
  WidgetTester tester, {
  LayoutDoc? doc,
  Map<String, Object> prefs = const {},
  (Uint8List, String)? file,
}) async {
  tester.view.physicalSize = const Size(1500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final fake = FakeApiAdapter(role: 'mall_admin');
  ApiClient.instance.dio.httpClientAdapter = fake;
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(sp),
    planFilePickerProvider.overrideWithValue(() async => file),
    pictureConverterProvider.overrideWithValue((b, e) async => Uint8List.fromList(const [1])),
  ]);
  await c.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: const AuthUser(id: 1, email: longEmail, fullName: longPerson, role: 'mall_admin', isActive: true, mustChangePassword: false),
      );
  if (doc != null) c.read(editorProvider.notifier).loadLocal(doc, guided: true);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: SingleChildScrollView(child: MessageOverlay(child: SizedBox(width: 1400, child: MapEditorView())))),
    ),
  ));
  if (doc == null) c.read(editorProvider.notifier).open(1);
  await _steps(tester);
  return (c, fake, sp);
}

Future<void> _leave(WidgetTester tester, ProviderContainer c) async {
  await _steps(tester, 36);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  await _steps(tester, 3);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _steps(tester, 3);
}

void main() {
  group('geometry for the easy tools', () {
    test('a nearly straight line is made straight, a slanted one is kept', () {
      expect(straighten([0, 0], [10, 0.8]), [10, 0]);
      expect(straighten([0, 0], [0.8, 10]), [0, 10]);
      expect(straighten([0, 0], [5, 5]), [5, 5]);
    });

    test('a click snaps to a wall end first, then onto a wall, else stays', () {
      final walls = [Wall(id: 'w', a: [0, 0], b: [10, 0], t: 0.2, kind: 'solid')];
      expect(snapToWalls([9.8, 0.2], walls), [10, 0]);
      final on = snapToWalls([5, 0.3], walls);
      expect(on[0], closeTo(5, 1e-9));
      expect(on[1], closeTo(0, 1e-9));
      expect(snapToWalls([5, 3], walls), [5, 3]);
    });

    test('a room is split in two by a line across it, and not by a line that misses', () {
      final sq = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]];
      final parts = splitRing(sq, [4, 2], [4, 8])!;
      expect(ringArea(parts.$1).abs() + ringArea(parts.$2).abs(), closeTo(100, 1e-6));
      expect({ringArea(parts.$1).abs().round(), ringArea(parts.$2).abs().round()}, {40, 60});
      expect(splitRing(sq, [20, 0], [20, 10]), isNull);
      final cut = chord(sq, [4, 2], [4, 8])!;
      expect([cut.$1[1], cut.$2[1]]..sort(), [0, 10]);
    });

    test('two rooms across a wall join into one; rooms far apart do not', () {
      final a = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]];
      final b = [[10.2, 0.0], [20.0, 0.0], [20.0, 10.0], [10.2, 10.0]];
      final u = unionRings(a, b)!;
      expect(ringArea(u).abs(), closeTo(200, 3));
      expect(u.length, lessThanOrEqualTo(6), reason: 'a clean rectangle, not a staircase');
      expect(unionRings(a, [[15.0, 0.0], [20.0, 0.0], [20.0, 10.0], [15.0, 10.0]]), isNull);
    });
  });

  group('editing steps (each is one Undo)', () {
    late ProviderContainer c;
    late EditorNotifier n;
    setUp(() {
      c = ProviderContainer();
      n = c.read(editorProvider.notifier);
      n.loadLocal(_doc(), guided: true);
    });
    tearDown(() => c.dispose());

    test('renaming and retyping a room, with Undo and Redo', () {
      n.renameSpace('sp-a', '  Coffee Corner ');
      n.setSpaceType('sp-a', 'food');
      expect(_space(c, 'sp-a')!.name, 'Coffee Corner');
      expect(_space(c, 'sp-a')!.type, 'food');
      n.undo();
      expect(_space(c, 'sp-a')!.type, 'retail');
      expect(_space(c, 'sp-a')!.name, 'Coffee Corner');
      n.undo();
      expect(_space(c, 'sp-a')!.name, 'Unit A');
      n.redo();
      expect(_space(c, 'sp-a')!.name, 'Coffee Corner');
    });

    test('an added wall snaps to wall ends and comes out straight; a tiny one is ignored', () {
      n.addSnappedWall([10.2, 0.1], [10.5, 5]);
      final w = _level(c).walls.last;
      expect(w.a, [10, 0], reason: 'snapped to the end of the middle wall');
      expect(w.b[0], closeTo(10, 1e-9), reason: 'straight up and down');
      expect(c.read(editorProvider).selection.id, w.id);
      final count = _level(c).walls.length;
      n.addSnappedWall([3, 3], [3.1, 3.1]);
      expect(_level(c).walls.length, count);
    });

    test('door sizes in plain words, and a door too wide for the wall is refused', () {
      n.addDoorAt('w-top', 0.25);
      var o = _level(c).openings.last;
      expect((o.kind, o.w, o.wall), ('door', 0.9, 'w-top'));
      n.setDoorPreset('Entrance');
      n.addDoorAt('w-bot', 0.5);
      o = _level(c).openings.last;
      expect((o.kind, o.w), ('entrance', 3.0));
      n.setDoorPreset('Shop front');
      n.addDoorAt('w-mid', 0.5);
      expect(_level(c).openings.last.kind, 'shutter');
      n.addSnappedWall([3, 3], [3, 5]);
      expect(n.addDoorAt(_level(c).walls.last.id, 0.5), contains('too short'));
      n.undo();
      n.undo();
      n.undo();
      expect(_level(c).openings.length, 1);
    });

    test('splitting a room makes two rooms with a wall on the cut; Undo puts it back', () {
      expect(n.splitSpace('sp-a', [4, 2], [4.3, 8]), isNull);
      expect(_level(c).spaces.length, 3);
      final cut = _level(c).walls.last;
      expect(cut.kind, 'partition');
      expect(cut.a[0], closeTo(4, 1e-9));
      expect(cut.b[0], closeTo(4, 1e-9), reason: 'the cut is straightened');
      n.undo();
      expect(_level(c).spaces.length, 2);
      expect(n.splitSpace('sp-a', [30, 0], [30, 10]), isNotNull);
    });

    test('joining two rooms removes the wall between them; rooms apart are refused', () {
      expect(n.mergeSpaces('sp-a', 'sp-b'), isNull);
      expect(_level(c).spaces.map((s) => s.id), ['sp-a']);
      expect(_space(c, 'sp-a')!.shape.area, closeTo(200, 3));
      expect(_level(c).wallById('w-mid'), isNull, reason: 'the shared wall goes');
      expect(_level(c).wallById('w-top'), isNotNull, reason: 'outer walls stay');
      n.undo();
      expect(_level(c).spaces.length, 2);
      _level(c).spaces.add(Space(id: 'sp-far', shape: Poly(outer: [[40, 0], [45, 0], [45, 5], [40, 5]])));
      expect(n.mergeSpaces('sp-a', 'sp-far'), contains('do not touch'));
    });

    test('the AI-found scale is applied to the plan as its own undo step', () async {
      final fake = FakeApiAdapter(role: 'mall_admin', aiScaleFound: {'mpp': 0.01, 'mm': 16000});
      ApiClient.instance.dio.httpClientAdapter = fake;
      expect(await n.convertBackdrop(), isNull);
      final bd = _level(c).backdrop!;
      expect(bd.mpp, 0.01);
      expect(bd.calibrated, isTrue);
      expect(c.read(editorProvider).proposal!.scaleFound!.mm, 16000);
      n.undo();
      expect(_level(c).backdrop!.mpp, 0.05);
      expect(_level(c).backdrop!.calibrated, isFalse);
    });
  });

  group('moving around and fixing on the map', () {
    tearDown(() => canvasC.dispose());

    _canvasTest('a left drag moves the view, never a room', (tester) async {
      await _canvasOnly(tester);
      final before = _canvas(tester).debugOrigin;
      final shape = _space(canvasC, 'sp-a')!.shape.outer.map((p) => [...p]).toList();
      await _drag(tester, _at(tester, 5, 5), const Offset(60, 30));
      expect(_canvas(tester).debugOrigin, before + const Offset(60, 30));
      expect(_space(canvasC, 'sp-a')!.shape.outer, shape);
      expect(canvasC.read(editorProvider).undoDepth, 0);
    });

    _canvasTest('a click selects the room under it', (tester) async {
      await _canvasOnly(tester);
      await _click(tester, 15, 5);
      expect(canvasC.read(editorProvider).selection.id, 'sp-b');
    });

    _canvasTest("a selected wall's end handle drags and snaps straight; its body only moves the view", (tester) async {
      await _canvasOnly(tester);
      canvasC.read(editorProvider.notifier).select(const Selection(SelKind.wall, 'w-top'));
      await tester.pump();
      await _drag(tester, _at(tester, 20, 0), _at(tester, 15, 0.4) - _at(tester, 20, 0));
      final w = _level(canvasC).wallById('w-top')!;
      expect(w.b[0], closeTo(15, 0.05));
      expect(w.b[1], 0, reason: 'kept straight');
      expect(canvasC.read(editorProvider).undoDepth, 1);
      final before = _canvas(tester).debugOrigin;
      await _drag(tester, _at(tester, 5, 0), const Offset(0, 40));
      expect(_level(canvasC).wallById('w-top')!.a, [0, 0]);
      expect(_canvas(tester).debugOrigin, before + const Offset(0, 40));
    });

    _canvasTest('Delete and arrow keys change nothing; Esc lets go', (tester) async {
      await _canvasOnly(tester);
      await _click(tester, 5, 5);
      expect(canvasC.read(editorProvider).selection.id, 'sp-a');
      final shape = _space(canvasC, 'sp-a')!.shape.outer.map((p) => [...p]).toList();
      for (final k in [LogicalKeyboardKey.delete, LogicalKeyboardKey.backspace, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowDown]) {
        await tester.sendKeyEvent(k);
      }
      await tester.pump();
      expect(_space(canvasC, 'sp-a')!.shape.outer, shape);
      expect(canvasC.read(editorProvider).undoDepth, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(canvasC.read(editorProvider).selection.isEmpty, isTrue);
    });

    _canvasTest('Add wall: two clicks make one straight wall, then the tool is done', (tester) async {
      await _canvasOnly(tester);
      canvasC.read(editorProvider.notifier).setGuidedTool(GuidedTool.addWall);
      await tester.pump();
      await _click(tester, 3, 3);
      await _click(tester, 3.2, 8);
      final w = _level(canvasC).walls.last;
      expect(w.a[0], closeTo(3, 0.05));
      expect(w.b[0], w.a[0]);
      expect(w.b[1], closeTo(8, 0.05));
      expect(canvasC.read(editorProvider).guidedTool, GuidedTool.none);
    });

    _canvasTest('Add door: a click on a wall puts the chosen size there; a click off a wall explains', (tester) async {
      await _canvasOnly(tester);
      final n = canvasC.read(editorProvider.notifier);
      n.setDoorPreset('Double door');
      await tester.pump();
      await _click(tester, 5, 5);
      expect(_level(canvasC).openings, isEmpty);
      expect(find.textContaining('Click right on a wall'), findsOneWidget);
      await _click(tester, 5, 0);
      final o = _level(canvasC).openings.single;
      expect((o.wall, o.w), ('w-top', 1.8));
      expect(o.at, closeTo(0.25, 0.01));
      await _steps(tester, 60);
    });

    _canvasTest('Split: two clicks across the selected room', (tester) async {
      await _canvasOnly(tester);
      final n = canvasC.read(editorProvider.notifier);
      n.select(const Selection(SelKind.space, 'sp-a'));
      n.setGuidedTool(GuidedTool.split);
      await tester.pump();
      await _click(tester, 5, 2);
      await _click(tester, 5, 8);
      expect(_level(canvasC).spaces.length, 3);
    });

    _canvasTest('Join: select a room, then click the room next to it', (tester) async {
      await _canvasOnly(tester);
      final n = canvasC.read(editorProvider.notifier);
      n.select(const Selection(SelKind.space, 'sp-a'));
      n.setGuidedTool(GuidedTool.merge);
      await tester.pump();
      await _click(tester, 15, 5);
      expect(_level(canvasC).spaces.single.id, 'sp-a');
    });

    _canvasTest('+, − and Fit buttons', (tester) async {
      await _canvasOnly(tester);
      final s0 = _canvas(tester).debugScale;
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pump();
      expect(_canvas(tester).debugScale, closeTo(s0 * 1.25, 1e-9));
      await tester.tap(find.byKey(const ValueKey('zoom-out')));
      await tester.pump();
      expect(_canvas(tester).debugScale, closeTo(s0, 1e-9));
      final fit = canvasC.read(editorProvider).fitRequest;
      await tester.tap(find.byKey(const ValueKey('zoom-fit')));
      await tester.pump();
      expect(canvasC.read(editorProvider).fitRequest, fit + 1);
    });
  });

  group('the easy editor page', () {
    testWidgets('is the default: step bar, no tool rail, Back and Next', (tester) async {
      final (c, _, _) = await _page(tester, doc: _doc());
      expect(c.read(editorProvider).guided, isTrue);
      expect(find.byKey(const ValueKey('guided-step-0')), findsOneWidget);
      expect(find.text('Properties'), findsNothing, reason: 'the full panels are under Advanced editing');
      await _tapKey(tester, 'guided-next');
      expect(c.read(editorProvider).guidedStep, 1);
      expect(find.byKey(const ValueKey('guided-scale-state')), findsOneWidget);
      await _tapKey(tester, 'guided-back');
      expect(c.read(editorProvider).guidedStep, 0);
      await _tapKey(tester, 'guided-step-3');
      expect(find.text('Check the rooms'), findsOneWidget);
      await _leave(tester, c);
    });

    testWidgets('Advanced editing switches to the full editor and is remembered; it switches back', (tester) async {
      final (c, _, sp) = await _page(tester, doc: _doc());
      await _tapKey(tester, 'guided-advanced');
      expect(c.read(editorProvider).guided, isFalse);
      expect(sp.getBool('map.editor.guided'), isFalse);
      expect(find.text('Properties'), findsOneWidget);
      await _tapKey(tester, 'guided-back-to-easy');
      expect(c.read(editorProvider).guided, isTrue);
      expect(sp.getBool('map.editor.guided'), isTrue);
      await _leave(tester, c);
    });

    testWidgets('someone who chose the full editor gets it next time', (tester) async {
      final (c, _, _) = await _page(tester, doc: _doc(), prefs: {'map.editor.guided': false});
      expect(c.read(editorProvider).guided, isFalse);
      expect(find.byKey(const ValueKey('guided-step-0')), findsNothing);
      await _leave(tester, c);
    });

    testWidgets('renaming a room from its card, and Undo at the top', (tester) async {
      final (c, _, _) = await _page(tester, doc: _doc());
      await _tapKey(tester, 'guided-step-3');
      await _tapKey(tester, 'guided-room-sp-b');
      expect(find.byKey(const ValueKey('guided-room-title')), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('room-name-sp-b')), matching: find.byType(TextField)), 'Bakery');
      await tester.pump();
      await _tapKey(tester, 'guided-save-name');
      expect(_space(c, 'sp-b')!.name, 'Bakery');
      await _tapKey(tester, 'guided-undo');
      expect(_space(c, 'sp-b')!.name, 'Unit B');
      await _tapKey(tester, 'guided-redo');
      expect(_space(c, 'sp-b')!.name, 'Bakery');
      await _leave(tester, c);
    });

    testWidgets('pick a store, then click its room: it is linked', (tester) async {
      final (c, fake, _) = await _page(tester, doc: _doc());
      await _tapKey(tester, 'guided-step-3');
      await _steps(tester);
      await _tapKey(tester, 'guided-place-store-1');
      expect(c.read(editorProvider).guidedTool, GuidedTool.pickStore);
      await tester.tapAt(_at(tester, 15, 5), kind: PointerDeviceKind.mouse);
      await _steps(tester, 6);
      final put = fake.writes.lastWhere((w) => w.$2 == '/stores/1/spaces');
      expect(((put.$3 as Map)['spaceKeys'] as List), contains('sp-b'));
      expect(c.read(editorProvider).storeLinks.any((l) => l.storeId == 1 && l.spaceKey == 'sp-b'), isTrue);
      expect(c.read(editorProvider).selection.id, 'sp-b');
      expect(c.read(editorProvider).guidedTool, GuidedTool.none);
      await _leave(tester, c);
    });

    testWidgets('the publish checklist names what is missing and jumps to it', (tester) async {
      final (c, _, _) = await _page(tester, doc: _doc(nameB: ''));
      await _tapKey(tester, 'guided-step-4');
      expect(find.text('1 room has no name.'), findsOneWidget);
      expect(find.byKey(const ValueKey('guided-publish')), findsOneWidget);
      await tester.tap(find.text('1 room has no name.'));
      await _steps(tester, 3);
      expect(c.read(editorProvider).guidedStep, 3);
      expect(c.read(editorProvider).selection.id, 'sp-b');
      expect(find.text('Room without a name'), findsWidgets);
      await _leave(tester, c);
    });

    // Round 21 (P1-08): the Publish step asks the server what shoppers could not walk to.
    testWidgets('the publish step lists what shoppers could not reach, and a click selects the room', (tester) async {
      final (c, fake, _) = await _page(tester, doc: _doc());
      await _tapKey(tester, 'guided-step-4');
      await _steps(tester, 6);
      expect(fake.requests.any((r) => r.contains('/publish-check')), isTrue);
      final problem = find.textContaining("can't be reached");
      expect(problem, findsOneWidget);
      expect(find.textContaining('shoppers may have saved will be gone'), findsOneWidget);
      await tester.tap(problem);
      await _steps(tester, 3);
      expect(c.read(editorProvider).selection.id, 'sp-b');
      await _leave(tester, c);
    });

    testWidgets('starting from a DXF goes straight to Read with AI', (tester) async {
      final (c, _, _) = await _page(tester, file: (Uint8List.fromList(const [1]), 'ground.dxf'));
      await tester.tap(find.text('Upload a floor plan'));
      await _steps(tester, 20);
      expect(c.read(editorProvider).guidedStep, 2);
      expect(find.byKey(const ValueKey('guided-read')), findsOneWidget);
      await _leave(tester, c);
    });

    testWidgets('starting from a picture goes to the scale first', (tester) async {
      final (c, _, _) = await _page(tester, file: (Uint8List.fromList(const [1]), 'scan.png'));
      await tester.tap(find.text('Upload a floor plan'));
      await _steps(tester, 20);
      expect(c.read(editorProvider).guidedStep, 1);
      expect(find.byKey(const ValueKey('guided-calib-start')), findsOneWidget);
      await _leave(tester, c);
    });
  });
}

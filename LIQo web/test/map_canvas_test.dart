// Pointer state machine of the map canvas.
//
// Bug this pins: on the web the engine can keep the right mouse button marked
// as held after a release it never saw. The canvas must stop panning, and left
// clicks must still work, even when every later event carries that stale bit.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map_canvas.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';

LayoutDoc _doc() => LayoutDoc(buildings: [
      Building(id: 'bd-1', name: 'B', levels: [
        Level(
          id: 'lv-1',
          name: 'G',
          outline: Poly(outer: [[0, 0], [50, 0], [50, 30], [0, 30]]),
          spaces: [
            Space(id: 'sp-a', name: 'Unit A', shape: Poly(outer: [[5, 5], [20, 5], [20, 15], [5, 15]])),
          ],
        ),
      ]),
    ]);

late ProviderContainer container;

Future<void> _pump(WidgetTester tester, {bool editable = true}) async {
  container = ProviderContainer();
  container.read(editorProvider.notifier).loadLocal(_doc(), editable: editable);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: Center(child: SizedBox(width: 600, height: 400, child: MapCanvas()))),
      ),
    ),
  );
  await tester.pump();
}

MapCanvasState _canvas(WidgetTester t) => t.state<MapCanvasState>(find.byType(MapCanvas));

/// Screen position of a level point, using the canvas's own transform.
Offset _at(WidgetTester t, double x, double z) {
  final c = _canvas(t);
  final topLeft = t.getTopLeft(find.byType(MapCanvas));
  return topLeft + c.debugOrigin + Offset(x * c.debugScale, z * c.debugScale);
}

void main() {
  tearDown(() => container.dispose());

  testWidgets('right-drag pans and a release ends the pan', (tester) async {
    await _pump(tester);
    final before = _canvas(tester).debugOrigin;
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await g.down(_at(tester, 25, 15));
    await g.moveBy(const Offset(40, 20));
    await tester.pump();
    expect(_canvas(tester).debugDrag, DragKind.pan);
    expect(_canvas(tester).debugOrigin, before + const Offset(40, 20));
    await g.up();
    await tester.pump();
    expect(_canvas(tester).debugDrag, DragKind.none);
  });

  testWidgets('a stale right button does not keep panning and left clicks still select', (tester) async {
    await _pump(tester);
    // Start a pan the normal way.
    final right = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await right.down(_at(tester, 25, 15));
    await right.moveBy(const Offset(10, 10));
    await tester.pump();
    final origin = _canvas(tester).debugOrigin;

    // Simulate the engine's stuck state: the left button goes down while the
    // right bit is still reported. No pointer-up for the right button ever arrives.
    await right.up();
    final both = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton | kSecondaryMouseButton);
    await both.down(_at(tester, 12, 10)); // inside Unit A
    await both.moveBy(const Offset(1, 1)); // within the tap slop
    await tester.pump();
    expect(_canvas(tester).debugOrigin, origin, reason: 'must not pan while the left button is down');
    await both.up();
    await tester.pump();

    expect(container.read(editorProvider).selection.kind, SelKind.space);
    expect(container.read(editorProvider).selection.id, 'sp-a');
    expect(_canvas(tester).debugDrag, DragKind.none);
  });

  testWidgets('a move that reports only a stale right button moves nothing after the release', (tester) async {
    await _pump(tester);
    final right = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await right.down(_at(tester, 25, 15));
    await right.moveBy(const Offset(5, 5));
    await tester.pump();
    // A hover (no buttons) proves the drag is over, even without a pointer-up.
    await right.up();
    await right.moveBy(const Offset(30, 30)); // mouse up → this is a hover
    await tester.pump();
    expect(_canvas(tester).debugDrag, DragKind.none);
    final origin = _canvas(tester).debugOrigin;
    // A later left press-and-drag over empty space must not pan either.
    final left = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await left.down(_at(tester, 40, 25));
    await left.moveBy(const Offset(25, 25));
    await tester.pump();
    expect(_canvas(tester).debugOrigin, origin);
    await left.up();
  });

  testWidgets('left click selects a space and dragging moves it', (tester) async {
    await _pump(tester);
    final left = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await left.down(_at(tester, 12, 10));
    await left.up();
    await tester.pump();
    expect(container.read(editorProvider).selection.id, 'sp-a');

    final scale = _canvas(tester).debugScale;
    await left.down(_at(tester, 12, 10));
    await left.moveBy(Offset(2 * scale, 0)); // 2 m to the right
    await left.up();
    await tester.pump();
    final space = container.read(editorProvider).doc!.level('lv-1')!.spaces.first;
    expect(space.shape.outer.first[0], closeTo(7, 0.11));
    expect(container.read(editorProvider).undoDepth, 1, reason: 'a drag is one undo step');
  });

  testWidgets('space tool: clicks add points and clicking the first point closes the polygon', (tester) async {
    await _pump(tester);
    container.read(editorProvider.notifier).setTool(EditorTool.space);
    await tester.pump();
    final left = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    for (final pt in [(30.0, 20.0), (40.0, 20.0), (40.0, 28.0), (30.0, 28.0)]) {
      await left.down(_at(tester, pt.$1, pt.$2));
      await left.up();
      await tester.pump(const Duration(milliseconds: 400)); // outside the double-tap window
    }
    expect(container.read(editorProvider).pending.length, 4);
    await left.down(_at(tester, 30, 20));
    await left.up();
    await tester.pump();
    final st = container.read(editorProvider);
    expect(st.pending, isEmpty);
    expect(st.doc!.level('lv-1')!.spaces.length, 2);
    expect(st.tool, EditorTool.select);
  });

  testWidgets('wall tool: a double-click ends the chain without a zero-length wall', (tester) async {
    await _pump(tester);
    container.read(editorProvider.notifier).setTool(EditorTool.wall);
    await tester.pump();
    final left = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await left.down(_at(tester, 2, 2));
    await left.up();
    await tester.pump(const Duration(milliseconds: 400));
    await left.down(_at(tester, 12, 2));
    await left.up();
    await tester.pump(const Duration(milliseconds: 50));
    await left.down(_at(tester, 12, 2)); // second click of the double-click
    await left.up();
    await tester.pump();
    final st = container.read(editorProvider);
    expect(st.doc!.level('lv-1')!.walls.length, 1);
    expect(st.doc!.level('lv-1')!.walls.first.length, closeTo(10, 0.01));
    expect(st.pending, isEmpty);
  });

  testWidgets('read-only canvas ignores drawing tools but still pans', (tester) async {
    await _pump(tester, editable: false);
    container.read(editorProvider.notifier).setTool(EditorTool.wall);
    await tester.pump();
    final left = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await left.down(_at(tester, 2, 2));
    await left.up();
    await tester.pump();
    expect(container.read(editorProvider).pending, isEmpty);
    final before = _canvas(tester).debugOrigin;
    final middle = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await middle.down(_at(tester, 25, 15));
    await middle.moveBy(const Offset(15, 0));
    await middle.up();
    await tester.pump();
    expect(_canvas(tester).debugOrigin, before + const Offset(15, 0));
  });

  testWidgets('wheel zooms around the pointer', (tester) async {
    await _pump(tester);
    final c = _canvas(tester);
    final scaleBefore = c.debugScale;
    final p = _at(tester, 25, 15);
    c.zoomAt(p - tester.getTopLeft(find.byType(MapCanvas)), 1.12);
    await tester.pump();
    expect(_canvas(tester).debugScale, closeTo(scaleBefore * 1.12, 1e-6));
    // The point under the pointer stays put.
    expect(_at(tester, 25, 15), offsetMoreOrLessEquals(p, epsilon: 0.01));
  });
}

// Bug this pins: the map editor's branch dropdown asserted ("value not among
// items") when the editor state held a branch id that the loaded list did not
// contain, e.g. after another user signed in or an assignment was removed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map_editor_view.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/maps_service.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {required int staleBranchId, required List<MapStatus> items}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    mapListProvider.overrideWith((ref) async => items),
  ]);
  // A document from "before": its branch is not in the list this user sees.
  container.read(editorProvider.notifier).loadLocal(
        LayoutDoc(buildings: [Building(id: 'bd-1', levels: [Level(id: 'lv-1')])]),
        editable: false,
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(child: MessageOverlay(child: SizedBox(width: 1200, child: MapEditorView())))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('branch picker survives a selected branch that is not in the list', (tester) async {
    final items = [
      const MapStatus(branchId: 7, branchName: 'Branch 7', mallName: 'Mall', hasMap: true, draftVersion: 1, spaceCount: 0),
    ];
    // loadLocal sets branchId = 0, which is not in the list.
    final container = await _pump(tester, staleBranchId: 0, items: items);
    expect(tester.takeException(), isNull);
    expect(find.byType(MapEditorView), findsOneWidget);
    container.dispose();
  });

  testWidgets('branch picker survives an empty branch list', (tester) async {
    final container = await _pump(tester, staleBranchId: 0, items: const []);
    expect(tester.takeException(), isNull);
    expect(find.text('No branches in your scope'), findsOneWidget);
    container.dispose();
  });

  testWidgets('editor state resets when the signed-in user changes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    container.read(editorProvider.notifier).loadLocal(LayoutDoc(buildings: [Building(id: 'bd-1', levels: [Level(id: 'lv-1')])]));
    expect(container.read(editorProvider).doc, isNotNull);

    await container.read(sessionProvider.notifier).signIn(
          token: 'x.y.z',
          user: const AuthUser(id: 42, email: 'a@b.c', fullName: 'A B', role: 'mall_admin', isActive: true, mustChangePassword: false),
        );
    await tester.pump();
    expect(container.read(editorProvider).doc, isNull, reason: 'a new user must not inherit the previous document');
    expect(container.read(editorProvider).branchId, isNull);
  });
}

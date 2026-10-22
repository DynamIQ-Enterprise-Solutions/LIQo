// A branch with no map yet (bug found by the owner, 2026-10-22): the mall
// admin sees "has no map yet" AND a way to create it; creating opens the
// editor on the new map. Round 17 (owner decision 2026-10-22): uploading the
// floor plan is the way to start; creating an empty map by hand is the
// fallback link, which this test follows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map_editor_view.dart';
import 'package:gabay_admin/features/map_editor/maps_service.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a mall admin opens a branch with no map, creates it, and the editor opens on it', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeApiAdapter(role: 'mall_admin');
    ApiClient.instance.dio.httpClientAdapter = fake;
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(child: MessageOverlay(child: SizedBox(width: 1300, child: MapEditorView())))),
      ),
    ));
    // Started, not awaited: the test clock is stepped below.
    container.read(editorProvider.notifier).open(1);
    await _steps(tester);

    expect(find.text('Mall B · Branch Example has no map yet.'), findsOneWidget);
    expect(find.text('Upload a floor plan'), findsOneWidget, reason: 'starting from the plan is offered first');
    expect(find.text('Create map'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('start-map-manual')));
    await _steps(tester);
    expect(find.text('Start a map for this branch'), findsOneWidget);
    await tester.tap(find.text('Create map').last);
    await _steps(tester, 20);

    expect(fake.requests.any((r) => r.startsWith('POST') && r.endsWith('/maps/1')), isTrue);
    expect(find.text('Mall B · Branch Example has no map yet.'), findsNothing);
    expect(container.read(editorProvider).doc, isNotNull, reason: 'the editor holds the new map');
    expect(container.read(editorProvider).canEdit, isTrue);
    tester.takeException();
    // Leaving the editor stops its autosave and lock timers.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    // Closing releases the edit lock; let that request finish.
    await _steps(tester, 3);
  });

  test('the edit flag is read whether or not the branch has a map', () {
    Map<String, dynamic> body(bool canEdit) => {
          'branch': {'id': 1, 'name': 'B', 'mallName': 'M'},
          'map': null,
          'canEdit': canEdit,
        };
    expect(MapBundle.fromJson(body(true)).canEdit, isTrue);
    expect(MapBundle.fromJson(body(false)).canEdit, isFalse);
    expect(MapBundle.fromJson(body(true)).hasMap, isFalse);
  });
}

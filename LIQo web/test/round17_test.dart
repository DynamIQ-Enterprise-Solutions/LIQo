// Round 17 (owner decisions 2026-10-22): a map starts from its floor plan
// (empty-by-hand is the fallback), the AI reading shows a full-screen scan, a
// new proposal draws itself in, and a 3D preview sits beside the canvas.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/map_editor/ai_scan_dialog.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map3d_panel.dart';
import 'package:gabay_admin/features/map_editor/map_canvas.dart';
import 'package:gabay_admin/features/map_editor/map_editor_view.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/maps_service.dart';
import 'package:gabay_admin/features/map_editor/picture_convert.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The editor page for branch 1 ("Mall B · Branch Example", no map yet).
Future<(ProviderContainer, FakeApiAdapter)> _editor(WidgetTester tester, {(Uint8List, String)? file, Map<String, Object> prefs = const {}}) async {
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
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: SingleChildScrollView(child: MessageOverlay(child: SizedBox(width: 1400, child: MapEditorView())))),
    ),
  ));
  c.read(editorProvider.notifier).open(1);
  await _steps(tester);
  return (c, fake);
}

/// Leaves the page so autosave, lock and message timers stop.
Future<void> _leave(WidgetTester tester, ProviderContainer c) async {
  await _steps(tester, 36);
  await tester.pumpWidget(const SizedBox());
  c.dispose();
  await _steps(tester, 3);
}

bool _createdWithoutOutline(FakeApiAdapter fake) =>
    fake.writes.any((w) => w.$1 == 'POST' && w.$2 == '/maps/1' && (w.$3 as Map)['outline'] == false);

void main() {
  testWidgets('no map yet: uploading the plan is offered first, the empty map is the fallback link', (tester) async {
    final (c, _) = await _editor(tester);
    expect(find.text('Start with your floor plan'), findsOneWidget);
    expect(find.text('Upload a floor plan'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-map-manual')), findsOneWidget);
    expect(find.text('Create map'), findsNothing);
    await _leave(tester, c);
  });

  // Owner decision 2026-10-22 (Round 18): the easy editor is the default, so this
  // runs in the full editor (remembered choice) where the Blueprint tab exists.
  testWidgets('a DXF starts the map at its exact size and opens Blueprint', (tester) async {
    final (c, fake) = await _editor(tester, file: (Uint8List.fromList(const [1]), 'ground.dxf'), prefs: {'map.editor.guided': false});
    await tester.tap(find.text('Upload a floor plan'));
    await _steps(tester, 20);
    expect(_createdWithoutOutline(fake), isTrue, reason: 'no made-up rectangle');
    expect(_uploadIndex(fake) < _createIndex(fake), isTrue, reason: 'the plan is uploaded before the map exists');
    final st = c.read(editorProvider);
    final lvl = st.level!;
    expect(lvl.backdrop!.mpp, 0.02);
    final b = ringBounds(lvl.outline!.outer);
    expect(b.width, closeTo(20, 1e-6), reason: '1000 px × 0.02 m');
    expect(b.height, closeTo(12, 1e-6));
    expect(st.fitRequest, greaterThan(0), reason: 'the canvas frames the plan');
    expect(find.text('Read with AI'), findsOneWidget, reason: 'the Blueprint tab is open');
    await _leave(tester, c);
  });

  testWidgets('a picture starts the map with no outline yet (it comes after calibration)', (tester) async {
    final (c, fake) = await _editor(tester, file: (Uint8List.fromList(const [1]), 'scan.png'));
    await tester.tap(find.text('Upload a floor plan'));
    await _steps(tester, 20);
    expect(_createdWithoutOutline(fake), isTrue);
    expect(c.read(editorProvider).level!.backdrop, isNotNull);
    expect(c.read(editorProvider).level!.outline, isNull);
    await _leave(tester, c);
  });

  testWidgets('a drawing whose unit is left for later starts no map', (tester) async {
    final (c, fake) = await _editor(tester, file: (Uint8List.fromList(const [1]), 'nounit.dxf'));
    await tester.tap(find.text('Upload a floor plan'));
    await _steps(tester);
    await tester.tap(find.text('Later'));
    await _steps(tester);
    expect(fake.writes.any((w) => w.$2 == '/maps/1'), isFalse);
    expect(c.read(editorProvider).doc, isNull);
    await _leave(tester, c);
  });

  group('the scan while the AI reads', () {
    Future<Completer<String?>> open(WidgetTester tester, {bool still = false}) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (still) {
        // The dialog reads the app-wide setting, as on a real device.
        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      }
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        })),
      ));
      final done = Completer<String?>();
      showAiScan(ctx, done: done.future, branchId: 1, backdropKey: 'k', crop: const [0.1, 0.1, 0.6, 0.7], loadImage: () async => null);
      await _steps(tester, 3);
      return done;
    }

    testWidgets('shows the plan scan with the time, and closes itself when the reading ends', (tester) async {
      final done = await open(tester);
      expect(find.byKey(const ValueKey('ai-scan-title')), findsOneWidget);
      expect(find.textContaining('boxed part'), findsOneWidget);
      expect(find.textContaining('0:0'), findsOneWidget);
      await _steps(tester, 15);
      expect(find.textContaining('0:01'), findsOneWidget, reason: 'the clock runs');
      done.complete(null);
      await _steps(tester, 6);
      expect(find.byKey(const ValueKey('ai-scan-title')), findsNothing);
    });

    // Owner, 2026-10-22: "the system shall handle graceful error handling".
    testWidgets('a failed reading stops the scan and explains, with Try again and Close', (tester) async {
      final done = await open(tester);
      late Future<bool> result;
      // Re-open to capture the dialog's answer.
      Navigator.of(tester.element(find.byKey(const ValueKey('ai-scan-title'))), rootNavigator: true).pop();
      await _steps(tester, 3);
      final again = Completer<String?>();
      result = showAiScan(tester.element(find.byType(Scaffold)), done: again.future, branchId: 1, backdropKey: 'k', loadImage: () async => null);
      await _steps(tester, 3);
      again.complete('The chosen AI model could not take this reading, so nothing was added and no credits were used.');
      await _steps(tester, 3);
      expect(find.text('The plan could not be read this time'), findsOneWidget);
      expect(find.textContaining('no credits were used'), findsOneWidget);
      expect(find.textContaining('invalid argument'), findsNothing, reason: 'no raw provider text');
      // Nothing keeps moving once it has failed.
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      await tester.tap(find.text('Try again'));
      // It closes on the next frame, then fades out (260 ms).
      await _steps(tester, 8);
      expect(await result, isTrue);
      expect(find.text('The plan could not be read this time'), findsNothing);
      done.complete(null);
    });

    testWidgets('with reduced motion the scan line stands still', (tester) async {
      final done = await open(tester, still: true);
      // Nothing keeps animating, so the screen settles.
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      expect(find.byKey(const ValueKey('ai-scan-title')), findsOneWidget);
      done.complete(null);
      await _steps(tester, 6);
    });
  });

  group('a new proposal draws itself in', () {
    Future<(ProviderContainer, MapCanvasState)> canvas(WidgetTester tester, {bool still = false}) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(editorProvider.notifier).loadLocal(LayoutDoc(buildings: [Building(id: 'bd-1', levels: [Level(id: 'lv-1', name: 'G')])]));
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: MediaQuery(
            data: MediaQueryData(size: const Size(900, 700), disableAnimations: still),
            child: const Scaffold(body: Center(child: SizedBox(width: 600, height: 400, child: MapCanvas()))),
          ),
        ),
      ));
      await tester.pump();
      return (c, tester.state<MapCanvasState>(find.byType(MapCanvas)));
    }

    testWidgets('walls grow, rooms fade in; dropping a piece does not replay it', (tester) async {
      final (c, cv) = await canvas(tester);
      c.read(editorProvider.notifier).debugSetProposal(Proposal.fromJson(FakeApiAdapter.aiProposal()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(cv.debugReveal, inExclusiveRange(0, 1), reason: 'half way: painted without errors');
      await tester.pump(const Duration(milliseconds: 800));
      expect(cv.debugReveal, 1);
      c.read(editorProvider.notifier).removeProposalItem('ai-w-5');
      await tester.pump(const Duration(milliseconds: 50));
      expect(cv.debugReveal, 1);
    });

    testWidgets('with reduced motion it appears at once', (tester) async {
      final (c, cv) = await canvas(tester, still: true);
      c.read(editorProvider.notifier).debugSetProposal(Proposal.fromJson(FakeApiAdapter.aiProposal()));
      await tester.pump();
      expect(cv.debugReveal, 1);
    });
  });

  testWidgets('the 3D preview sits beside the canvas, collapses to a strip and comes back', (tester) async {
    final (c, _) = await _editor(tester, prefs: {'map3d.collapsed': false});
    c.read(editorProvider.notifier).loadLocal(LayoutDoc(buildings: [Building(id: 'bd-1', levels: [Level(id: 'lv-1', name: 'G')])]));
    await _steps(tester, 4);
    expect(find.byKey(const ValueKey('map3d-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('map3d-placeholder')), findsOneWidget);
    await tester.tap(find.byTooltip('Collapse'));
    await _steps(tester, 3);
    expect(find.byKey(const ValueKey('map3d-panel')), findsNothing);
    expect(find.byKey(const ValueKey('map3d-expand')), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('map3d.collapsed'), isTrue, reason: 'remembered on this device');
    await tester.tap(find.byKey(const ValueKey('map3d-expand')));
    await _steps(tester, 3);
    expect(find.byKey(const ValueKey('map3d-panel')), findsOneWidget);
    await _leave(tester, c);
  });

  test('what the 3D preview is given: every level, the proposal, problems, sizes and colours', () {
    final doc = LayoutDoc(buildings: [
      Building(id: 'bd-1', levels: [Level(id: 'lv-1', name: 'G'), Level(id: 'lv-2', name: '2F', elevation: 5)]),
    ]);
    final st = EditorData(
      doc: doc,
      levelId: 'lv-2',
      proposal: Proposal.fromJson(FakeApiAdapter.aiProposal(levelId: 'lv-2')),
      warnings: const [MapWarning(code: 'x', message: 'm', ids: ['w-9'])],
    );
    final m = map3dPayload(st, Pal.light);
    expect(((m['doc'] as Map)['buildings'] as List).first['levels'], hasLength(2));
    expect(m['levelId'], 'lv-2');
    expect((m['proposal'] as Map)['uncertain'], ['ai-sp-2']);
    expect(m['problems'], ['w-9']);
    expect((m['colors'] as Map)['proposal'], startsWith('#'));
    expect(((m['colors'] as Map)['rooms'] as Map).keys, contains('retail'));
  });
}

int _uploadIndex(FakeApiAdapter f) => f.writes.indexWhere((w) => w.$1 == 'POST' && w.$2 == '/maps/1/backdrops');
int _createIndex(FakeApiAdapter f) => f.writes.indexWhere((w) => w.$1 == 'POST' && w.$2 == '/maps/1');

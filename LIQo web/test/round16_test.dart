// Round 16: plans may also be TIFF, WebP, BMP, GIF, HEIC, SVG, DXF or DWG
// (owner decisions 2026-10-22). The file picker and the picture converter are
// replaced by fakes; the fake API answers for the server.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/map_editor/blueprint_panel.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/picture_convert.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

Future<void> _steps(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets the on-screen message (3.2 s) run out, so no timer outlives the test.
Future<void> _quiet(WidgetTester tester) => _steps(tester, 36);

class _Converter {
  final calls = <String>[];

  Future<Uint8List> call(Uint8List bytes, String ext) async {
    calls.add(ext);
    return Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47]);
  }
}

/// The Blueprint panel on a level with no plan yet; [file] is what the picker returns.
Future<ProviderContainer> _panel(WidgetTester tester, FakeApiAdapter fake, {(Uint8List, String)? file, _Converter? converter}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = fake;
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    planFilePickerProvider.overrideWithValue(() async => file),
    pictureConverterProvider.overrideWithValue((converter ?? _Converter()).call),
  ]);
  addTearDown(c.dispose);
  await c.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: const AuthUser(id: 1, email: longEmail, fullName: longPerson, role: 'mall_admin', isActive: true, mustChangePassword: false),
      );
  c.read(editorProvider.notifier).loadLocal(LayoutDoc(buildings: [
    Building(id: 'bd-1', name: 'Main', levels: [Level(id: 'lv-1', name: 'Ground floor', outline: Poly(outer: [[0, 0], [40, 0], [40, 30], [0, 30]]))]),
  ]));
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 340, child: BlueprintPanel())))),
    ),
  ));
  await _steps(tester);
  return c;
}

String? _uploadedName(FakeApiAdapter fake) {
  final up = fake.writes.where((w) => w.$1 == 'POST' && RegExp(r'^/maps/\d+/backdrops$').hasMatch(w.$2)).toList();
  if (up.isEmpty) return null;
  return (up.last.$3 as FormData).files.first.value.filename;
}

void main() {
  test('the picker offers every plan format', () {
    expect(planFileTypes, containsAll(['png', 'jpg', 'jpeg', 'pdf', 'tif', 'tiff', 'webp', 'bmp', 'gif', 'heic', 'heif', 'svg', 'dxf', 'dwg']));
    expect(extensionOf('Level 1.Plan.DXF'), 'dxf');
    expect(extensionOf('noext'), '');
  });

  testWidgets('the empty panel says which files it takes', (tester) async {
    await _panel(tester, FakeApiAdapter(role: 'mall_admin'));
    final text = tester.widget<Text>(find.byKey(const ValueKey('plan-formats'))).data!;
    for (final f in ['PNG', 'JPG', 'TIFF', 'WebP', 'BMP', 'GIF', 'HEIC', 'PDF', 'SVG', 'DXF', 'DWG']) {
      expect(text, contains(f));
    }
  });

  testWidgets('a HEIC photo is turned into a PNG in the browser, then uploaded and placed', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final conv = _Converter();
    final c = await _panel(tester, fake, file: (Uint8List.fromList(const [1, 2, 3]), 'IMG_2041.HEIC'), converter: conv);
    await tester.tap(find.text('Upload plan'));
    await _steps(tester);
    expect(conv.calls, ['heic']);
    expect(_uploadedName(fake), 'IMG_2041.png');
    expect(c.read(editorProvider).level!.backdrop, isNotNull);
    await _quiet(tester);
  });

  testWidgets('a DXF goes up as it is and is placed at its exact scale', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final conv = _Converter();
    final c = await _panel(tester, fake, file: (Uint8List.fromList(const [1]), 'level-1.dxf'), converter: conv);
    await tester.tap(find.text('Upload plan'));
    await _steps(tester);
    expect(conv.calls, isEmpty, reason: 'drawings are read by the server');
    expect(_uploadedName(fake), 'level-1.dxf');
    final bd = c.read(editorProvider).level!.backdrop!;
    expect(bd.mpp, 0.02, reason: 'the scale comes from the drawing, not from fitting the level');
    expect(bd.cx, 20);
    expect(bd.cz, 15);
    expect(find.byKey(const ValueKey('plan-exact-scale')), findsOneWidget);
    expect(find.textContaining('Scale from the drawing (millimetres)'), findsOneWidget);
    await _quiet(tester);
  });

  testWidgets('a DXF without a unit asks for it, then is placed at that scale', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final c = await _panel(tester, fake, file: (Uint8List.fromList(const [1]), 'nounit.dxf'));
    await tester.tap(find.text('Upload plan'));
    await _steps(tester);
    expect(find.text('Which unit is this drawing in?'), findsOneWidget);
    // Nothing chosen: the dialog says so and stays.
    await tester.tap(find.text('Place at this scale'));
    await _steps(tester, 3);
    expect(find.text('Choose the unit.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await _steps(tester, 4);
    await tester.tap(find.text('Millimetres (mm)').last);
    await _steps(tester, 4);
    await tester.tap(find.text('Place at this scale'));
    await _steps(tester);
    final put = fake.writes.where((w) => w.$1 == 'PUT' && w.$2.endsWith('/unit')).toList();
    expect(put, hasLength(1));
    expect(put.single.$3, {'unit': 'mm'});
    expect(c.read(editorProvider).level!.backdrop!.mpp, 0.005);
    await _quiet(tester);
  });

  testWidgets('"Later" leaves the drawing unplaced', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final c = await _panel(tester, fake, file: (Uint8List.fromList(const [1]), 'nounit.dwg'));
    await tester.tap(find.text('Upload plan'));
    await _steps(tester);
    await tester.tap(find.text('Later'));
    await _steps(tester);
    expect(c.read(editorProvider).level!.backdrop, isNull);
    expect(fake.writes.where((w) => w.$2.endsWith('/unit')), isEmpty);
    await _quiet(tester);
  });
}

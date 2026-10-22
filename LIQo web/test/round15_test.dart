// Round 15: floor plans are read with AI through IQGateway (owner decisions 2026-10-22).
// The fake API answers for the server; nothing reaches the gateway.

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/api_client.dart';
import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/ai/ai_settings_card.dart';
import 'package:gabay_admin/features/map_editor/blueprint_panel.dart';
import 'package:gabay_admin/features/map_editor/editor_state.dart';
import 'package:gabay_admin/features/map_editor/map_canvas.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';
import 'package:gabay_admin/features/map_editor/maps_service.dart';
import 'package:gabay_admin/features/map_editor/pdf_document.dart';
import 'package:gabay_admin/shared/messaging/messages.dart';

import 'support/fake_api.dart';

const _key = 'abcdef0123456789abcdef0123456789';

LayoutDoc _doc() => LayoutDoc(buildings: [
      Building(id: 'bd-1', name: 'Main', levels: [
        // A 1000 × 600 px plan at 5 cm per pixel, centred at (25, 15): it covers 0–50 × 0–30 m.
        Level(id: 'lv-1', name: 'Ground floor', backdrop: Backdrop(id: _key, cx: 25, cz: 15, mpp: 0.05)),
      ]),
    ]);

/// Lets the on-screen message (3.2 s) run out, so no timer outlives the test.
Future<void> _quiet(WidgetTester tester) => _steps(tester, 36);

Future<void> _steps(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<ProviderContainer> _container(FakeApiAdapter fake, {String role = 'mall_admin'}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  ApiClient.instance.dio.httpClientAdapter = fake;
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  await c.read(sessionProvider.notifier).signIn(
        token: 'x.y.z',
        user: AuthUser(id: 1, email: longEmail, fullName: longPerson, role: role, isActive: true, mustChangePassword: false),
      );
  return c;
}

/// The Blueprint panel beside nothing else, with the plan placed on the level.
Future<ProviderContainer> _panel(WidgetTester tester, FakeApiAdapter fake) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = await _container(fake);
  addTearDown(c.dispose);
  c.read(editorProvider.notifier).loadLocal(_doc());
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

class _FakePdf implements PdfDocument {
  final rendered = <int>[];
  bool disposed = false;

  // A 1 × 1 white PNG.
  static final png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, //
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0x3F, 0x00, 0x05, 0xFE, 0x02, 0xFE, 0xDC, 0xCC, 0x59, 0xE7, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, //
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  int get pageCount => 4;

  @override
  Future<Uint8List> render(int page, {required int maxSide}) async {
    rendered.add(page);
    return png;
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  testWidgets('the panel offers "Read with AI" with the credit bar; Detect is gone', (tester) async {
    await _panel(tester, FakeApiAdapter(role: 'mall_admin'));
    expect(find.text('Read with AI'), findsOneWidget);
    expect(find.textContaining('Detect'), findsNothing);
    expect(find.text('123456.75 credits left · 37.5 of 50 used today'), findsOneWidget);
    expect(find.textContaining('Reading the whole plan'), findsOneWidget);
  });

  testWidgets('without a model (or a key) the panel says why, and reading sends nothing', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin', aiModel: null);
    await _panel(tester, fake);
    expect(find.byKey(const ValueKey('ai-blocker')), findsOneWidget);
    expect(find.textContaining('chooses it in Settings'), findsOneWidget);
    await tester.tap(find.text('Read with AI'));
    await _steps(tester, 4);
    expect(fake.writes.where((w) => w.$2.endsWith('/convert')), isEmpty);
  });

  testWidgets('an empty wallet: the gateway\'s reason shows and reading sends nothing', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin', aiBlocked: true);
    await _panel(tester, fake);
    expect(find.byKey(const ValueKey('ai-wallet-blocked')), findsOneWidget);
    expect(find.text('Out of AI credits. Contact your administrator to top up.'), findsOneWidget);
    await tester.tap(find.text('Read with AI'));
    await _steps(tester, 4);
    expect(fake.writes.where((w) => w.$2.endsWith('/convert')), isEmpty);
  });

  testWidgets('a reading shows the proposal: unsure pieces, the outline and the store match', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final c = await _panel(tester, fake);
    await tester.tap(find.text('Read with AI'));
    await _steps(tester);
    final p = c.read(editorProvider).proposal!;
    expect(p.uncertain, {'ai-sp-2'});
    expect(find.text('AI proposal'), findsOneWidget);
    expect(find.textContaining('1 unsure piece is dashed in amber'), findsOneWidget);
    expect(find.text('Northline Apparel → Northline Apparel'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-outline')), findsOneWidget);
    expect(find.text('Link matched stores (1)'), findsOneWidget);
    expect(find.text('Last reading: 0.75 credits · gemini-2.5-pro-vision-preview-long-model-name'), findsOneWidget);
    // Once a proposal is up, the next reading can join it.
    expect(find.text('Add to proposal'), findsOneWidget);
    await _quiet(tester);
  });

  testWidgets('adding it is one undo step; matched stores are linked after the save', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final c = await _panel(tester, fake);
    await tester.tap(find.text('Read with AI'));
    await _steps(tester);
    await tester.tap(find.text('Add to floor'));
    await _steps(tester);

    final lvl = c.read(editorProvider).level!;
    expect(lvl.walls, hasLength(5));
    expect(lvl.openings, hasLength(1));
    expect(lvl.spaces, hasLength(2));
    expect(lvl.outline?.outer, hasLength(4), reason: 'the level had no outline, so the AI one is taken');
    expect(c.read(editorProvider).proposal, isNull);

    final link = fake.writes.where((w) => w.$1 == 'PUT' && w.$2 == '/stores/1/spaces').toList();
    expect(link, hasLength(1));
    expect((link.single.$3 as Map)['spaceKeys'], ['sp-a01', 'ai-sp-1'], reason: "the store's other spaces stay linked");
    expect(c.read(editorProvider).storeLinks.any((l) => l.spaceKey == 'ai-sp-1' && l.storeId == 1), isTrue);

    c.read(editorProvider.notifier).undo();
    final back = c.read(editorProvider).level!;
    expect(back.walls, isEmpty);
    expect(back.spaces, isEmpty);
    expect(back.outline, isNull);
    await _quiet(tester);
  });

  testWidgets('a boxed part sends its fractions', (tester) async {
    final fake = FakeApiAdapter(role: 'mall_admin');
    final c = await _panel(tester, fake);
    // Drawn backwards: still read as the same box.
    c.read(editorProvider.notifier).setCropBox([0.6, 0.5, 0.2, 0.1]);
    await _steps(tester, 2);
    expect(find.text('Reading the boxed part (16% of the plan).'), findsOneWidget);
    await tester.tap(find.text('Read with AI'));
    await _steps(tester);
    final sent = fake.writes.lastWhere((w) => w.$2.endsWith('/convert')).$3 as Map;
    expect(sent['crop'], [0.2, 0.1, 0.6, 0.5]);
    expect(sent['levelId'], 'lv-1');

    // A click without a drag reads nothing.
    c.read(editorProvider.notifier).setCropBox([0.3, 0.3, 0.305, 0.31]);
    expect(c.read(editorProvider).cropBox, isNull);
    await _quiet(tester);
  });

  testWidgets('box mode: a drag on the canvas marks that part of the plan', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _container(FakeApiAdapter(role: 'mall_admin'));
    addTearDown(c.dispose);
    c.read(editorProvider.notifier).loadLocal(_doc());
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: Center(child: SizedBox(width: 600, height: 400, child: MapCanvas())))),
    ));
    await tester.pump();
    final canvas = tester.state<MapCanvasState>(find.byType(MapCanvas));
    canvas.debugPictureSize = const Size(1000, 600);
    Offset at(double x, double z) => tester.getTopLeft(find.byType(MapCanvas)) + canvas.debugOrigin + Offset(x * canvas.debugScale, z * canvas.debugScale);

    c.read(editorProvider.notifier).startCrop();
    await tester.pump();
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.down(at(10, 6));
    await g.moveTo(at(20, 12));
    await g.moveTo(at(30, 18));
    await tester.pump();
    await g.up();
    await tester.pump();
    final box = c.read(editorProvider).cropBox!;
    expect(box[0], closeTo(0.2, 0.01));
    expect(box[1], closeTo(0.2, 0.01));
    expect(box[2], closeTo(0.6, 0.01));
    expect(box[3], closeTo(0.6, 0.01));
    expect(c.read(editorProvider).cropping, isFalse);
    await _steps(tester, 3);
  });

  test('picture pixels and level metres convert both ways, also when turned', () {
    final b = Backdrop(id: _key, cx: 10, cz: 20, mpp: 0.02, rot: 90);
    final p = b.toLevel(150, 40, 400, 300);
    final back = b.toPicture(p, 400, 300);
    expect(back[0], closeTo(150, 1e-6));
    expect(back[1], closeTo(40, 1e-6));
    // Turned 90°: the picture's centre stays put; its x axis now runs down the level.
    expect(b.toLevel(200, 150, 400, 300), [closeTo(10, 1e-9), closeTo(20, 1e-9)]);
    expect(b.toLevel(300, 150, 400, 300), [closeTo(10, 1e-9), closeTo(22, 1e-9)]);
  });

  test('dropping a piece keeps the proposal consistent', () {
    final p = Proposal.fromJson(FakeApiAdapter.aiProposal());
    final noWall = p.without({'ai-w-5'});
    expect(noWall.walls, hasLength(4));
    expect(noWall.openings, isEmpty, reason: 'its door goes with it');
    final noRoom = p.without({'ai-sp-1', 'ai-sp-2'});
    expect(noRoom.storeMatches, isEmpty);
    expect(noRoom.uncertain, isEmpty);
  });

  test('sections merge without doubling what was already read; their costs add up', () {
    final a = Proposal.fromJson(FakeApiAdapter.aiProposal());
    final second = FakeApiAdapter.aiProposal(credits: 0.5);
    final prop = second['proposal'] as Map<String, dynamic>;
    // Same pieces with new ids, plus one new wall further east.
    prop['walls'] = [
      for (final w in prop['walls'] as List) {...(w as Map<String, dynamic>), 'id': '${w['id']}-b'},
      {'id': 'ai-w-new', 'a': [18, 2], 'b': [30, 2], 't': 0.3, 'kind': 'boundary'},
    ];
    prop['openings'] = [];
    prop['spaces'] = [for (final s in prop['spaces'] as List) {...(s as Map<String, dynamic>), 'id': '${s['id']}-b'}];
    prop['storeMatches'] = [];
    prop['uncertain'] = ['ai-sp-2-b'];
    final m = a.merge(Proposal.fromJson(second));
    expect(m.walls, hasLength(6), reason: 'five already proposed, one new');
    expect(m.spaces, hasLength(2));
    expect(m.uncertain, {'ai-sp-2'});
    expect(m.sections, 2);
    expect(m.cost!.credits, 1.25);
  });

  testWidgets('a PDF: pick the page, with a preview', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pdf = _FakePdf();
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.shrink();
      })),
    ));
    final chosen = showDialog<int>(context: ctx, builder: (_) => PdfPagePicker(doc: pdf));
    await _steps(tester, 3);
    expect(find.text('This PDF has 4 pages. The chosen page is turned into a picture and uploaded.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pdf-page-3')));
    await _steps(tester, 3);
    expect(find.text('Use page 3'), findsOneWidget);
    await tester.tap(find.text('Use page 3'));
    await _steps(tester, 3);
    expect(await chosen, 3);
    expect(pdf.rendered, containsAll([1, 3]), reason: 'previews of the pages looked at');
  });

  testWidgets('Settings: the model list comes from the gateway; saving sends the choice', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeApiAdapter(role: 'superadmin');
    final c = await _container(fake, role: 'superadmin');
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const MessageOverlay(child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 560, child: AiSettingsCard()))))),
    ));
    await _steps(tester);
    expect(find.text('AI floor-plan reading'), findsOneWidget);
    expect(find.text('123456.75 credits left · 37.5 of 50 used today'), findsOneWidget);
    expect(find.textContaining('Google: Gemini 2.5 Pro Vision Preview (long label)'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await _steps(tester, 4);
    await tester.tap(find.text('GPT-4o · openai').last);
    await _steps(tester, 4);
    await tester.tap(find.text('Save model'));
    await _steps(tester, 4);
    final put = fake.writes.where((w) => w.$1 == 'PUT' && w.$2 == '/ai/model').toList();
    expect(put, hasLength(1));
    expect(put.single.$3, {'model': 'gpt-4o'});
    await _quiet(tester);
  });

  testWidgets('Settings without the key: it says where the key goes, and that it never reaches the app', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _container(FakeApiAdapter(role: 'superadmin', aiConfigured: false), role: 'superadmin');
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: SingleChildScrollView(child: SizedBox(width: 560, child: AiSettingsCard())))),
    ));
    await _steps(tester);
    expect(find.byKey(const ValueKey('ai-not-configured')), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
  });

  test('the proposal colours come from the theme in both modes', () {
    expect(Pal.light.aiProposal, isNot(Pal.light.aiUnsure));
    expect(Pal.darkPal.aiProposal, isNot(Pal.darkPal.aiUnsure));
  });

  test('a reading reply is read with its cost and matches', () {
    final p = Proposal.fromJson(FakeApiAdapter.aiProposal());
    expect(p.outline!.outer, hasLength(4));
    expect(p.storeMatches.single.storeName, 'Northline Apparel');
    expect(p.cost!.model, 'gemini-2.5-pro-vision-preview-long-model-name');
    expect(p.sections, 1);
    expect(MapsService, isNotNull);
  });
}

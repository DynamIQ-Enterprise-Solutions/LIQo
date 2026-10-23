// The whole app in a test: a phone-sized view, the brand font, a memory store,
// recorded haptics and place actions, a fixed clock, the stand-in shopper server
// with Wi-Fi, and (inside a mall) the sample malls already downloaded.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/app.dart';
import 'package:liqo_mobile/core/clock.dart';
import 'package:liqo_mobile/core/data/blob_store.dart';
import 'package:liqo_mobile/core/data/net.dart';
import 'package:liqo_mobile/core/data/shopper_api.dart';
import 'package:liqo_mobile/core/haptics.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/core/storage/store.dart';
import 'package:liqo_mobile/features/malls/data/sample_server.dart';
import 'package:liqo_mobile/features/places/services/place_actions.dart';

import 'harness.dart';
import 'samples.dart';

bool _fontLoaded = false;

/// Manrope, so text is laid out as on a phone instead of with the wide test font.
Future<void> loadManrope(WidgetTester tester) async {
  if (_fontLoaded) return;
  await tester.runAsync(() async {
    final bytes = File('assets/fonts/Manrope.ttf').readAsBytesSync();
    final loader = FontLoader('Manrope')..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  });
  _fontLoaded = true;
}

/// Records Call, Website and Share instead of opening anything.
class FakePlaceActions extends PlaceActions {
  final calls = <String>[], sites = <String>[], shares = <String>[];
  @override
  Future<bool> call(String phone) async {
    calls.add(phone);
    return true;
  }

  @override
  Future<bool> openWebsite(String url) async {
    sites.add(url);
    return true;
  }

  @override
  Future<void> share(String text, {Rect? origin}) async => shares.add(text);
}

class AppHarness {
  AppHarness(this.tester, this.store, this.haptics, this.actions, this.api, this.blobs, this.net);
  final WidgetTester tester;
  final MemoryStore store;
  final FakeHaptics haptics;
  final FakePlaceActions actions;
  final SampleShopperApi api;
  final MemoryBlobStore blobs;
  final FixedNet net;
  late ProviderContainer c;

  /// Steps the clock; the app's living parts (the walk, fly-tos) never settle on their own.
  Future<void> step([int frames = 30, Duration each = const Duration(milliseconds: 16)]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(each);
    }
  }
}

/// Pumps the app. [onboarded] and [mall] skip the first-launch flow; the splash is waited out.
/// [installed] are the sample malls already on the phone: all of them inside a mall, none on a
/// first launch, unless given. [packages] replace their package bytes (e.g. with long names).
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  bool onboarded = true,
  String? mall = 'bayview',
  List<String>? installed,
  Map<String, Uint8List>? packages,
  ShopperApi? api,
  NetKind net = NetKind.wifi,
  Map<String, String>? prefs,
  Size size = const Size(390, 844),
  double textScale = 1,
  DateTime? now,
  List<Override> overrides = const [],
}) async {
  await loadManrope(tester);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final ids = installed ?? (mall == null ? const <String>[] : allSampleIds), install = sampleInstall(fixedNow, ids);
  final store = MemoryStore({if (onboarded) Keys.onboardingSeen: '1', Keys.mall: ?mall, if (ids.isNotEmpty) ...sampleSavedPrefs(fixedNow, ids), ...?prefs});
  final h = AppHarness(tester, store, FakeHaptics(), FakePlaceActions(), SampleShopperApi(), MemoryBlobStore({...install.blobs, for (final e in (packages ?? const <String, Uint8List>{}).entries) 'packages/${e.key}/1.json': e.value}), FixedNet(net));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      hapticsProvider.overrideWithValue(h.haptics),
      clockProvider.overrideWithValue(() => now ?? fixedNow),
      placeActionsProvider.overrideWithValue(h.actions),
      blobStoreProvider.overrideWithValue(h.blobs),
      shopperApiProvider.overrideWithValue(api ?? h.api),
      netProvider.overrideWithValue(h.net),
      ...overrides,
    ],
    child: const LiqoApp(),
  ));
  h.c = ProviderScope.containerOf(tester.element(find.byType(LiqoApp)));
  // the splash: at least a second
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1100));
  await h.step(10);
  return h;
}

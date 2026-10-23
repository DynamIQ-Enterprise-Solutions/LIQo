// Malls on the phone (owner decisions 2026-10-23): a mall downloads whole and
// then works offline; updates download by themselves on Wi-Fi, wait for a tap on
// mobile data, and wait for a trip to end; a broken or newer-format download
// never replaces the working copy; a mall the server stops offering keeps
// working; deleting a mall keeps its saved places, greyed; a saved store follows
// a move; the server can retire this app version.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/clock.dart';
import 'package:liqo_mobile/core/data/blob_store.dart';
import 'package:liqo_mobile/core/data/net.dart';
import 'package:liqo_mobile/core/data/shopper_api.dart';
import 'package:liqo_mobile/core/storage/store.dart';
import 'package:liqo_mobile/features/malls/data/sample_server.dart';
import 'package:liqo_mobile/features/malls/models/saved_mall.dart';
import 'package:liqo_mobile/features/malls/providers/malls_provider.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';

import '../support/fake_server.dart';
import '../support/harness.dart' show fixedNow;
import '../support/samples.dart';

class Phone {
  Phone({List<String> installed = const [], MemoryStore? store, MemoryBlobStore? blobs, FakeShopperApi? api, NetKind net = NetKind.wifi})
      : api = api ?? FakeShopperApi(),
        net = FixedNet(net),
        store = store ?? MemoryStore({if (installed.isNotEmpty) ...sampleSavedPrefs(fixedNow, installed)}),
        blobs = blobs ?? MemoryBlobStore(sampleInstall(fixedNow, installed).blobs) {
    c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(this.store),
      blobStoreProvider.overrideWithValue(this.blobs),
      shopperApiProvider.overrideWithValue(this.api),
      netProvider.overrideWithValue(this.net),
      clockProvider.overrideWithValue(() => fixedNow),
    ]);
    addTearDown(c.dispose);
  }

  final FakeShopperApi api;
  final FixedNet net;
  final MemoryStore store;
  final MemoryBlobStore blobs;
  late final ProviderContainer c;

  MallsController get malls => c.read(mallsProvider.notifier);
  MallsState get s => c.read(mallsProvider);
  Future<void> boot() => malls.boot();
}

void main() {
  group('the first download', () {
    test('on Wi-Fi: saved whole, works from the phone', () async {
      final ph = Phone();
      await ph.boot();
      expect(await ph.malls.download('spire'), isNull);
      expect(ph.s.isSaved('spire'), isTrue);
      expect(ph.s.saved['spire']!.package.version, 1);
      expect(await ph.blobs.read(SavedMall.key('spire', 1)), isNotNull);
      // read back after a restart, with no connection at all
      final again = Phone(store: ph.store, blobs: ph.blobs, net: NetKind.none);
      await again.boot();
      expect(again.s.venues['spire']!.places, isNotEmpty);
    });

    test('on mobile data it needs a yes first', () async {
      final ph = Phone(net: NetKind.mobile);
      await ph.boot();
      expect(await ph.malls.download('spire'), DownloadFailure.needsMobileOk);
      expect(ph.s.isSaved('spire'), isFalse);
      expect(await ph.malls.download('spire', mobileOk: true), isNull);
      expect(ph.s.isSaved('spire'), isTrue);
    });

    test('offline, or a broken download: nothing is saved', () async {
      final ph = Phone(net: NetKind.none);
      await ph.boot();
      expect(await ph.malls.download('spire'), DownloadFailure.offline);
      ph.net.value = NetKind.wifi;
      ph.api.corrupt.add('spire');
      expect(await ph.malls.download('spire'), DownloadFailure.corrupt);
      expect(ph.s.isSaved('spire'), isFalse);
      expect(await ph.blobs.sizeOf('packages/spire'), 0);
    });
  });

  group('updates', () {
    test('on Wi-Fi they download and switch in by themselves', () async {
      final ph = Phone(installed: ['bayview']);
      await ph.boot();
      final before = ph.s.venues['bayview'];
      ph.api.publish('bayview', 2);
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['bayview']!.package.version, 2);
      expect(identical(ph.s.venues['bayview'], before), isFalse, reason: 'the new map is in use');
      expect(await ph.blobs.read(SavedMall.key('bayview', 1)), isNull, reason: 'the old copy is gone');
    });

    test('on mobile data they wait for a tap', () async {
      final ph = Phone(installed: ['bayview'], net: NetKind.mobile);
      await ph.boot();
      ph.api.publish('bayview', 2);
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['bayview']!.package.version, 1);
      expect(ph.s.saved['bayview']!.offered!.version, 2);
      expect(ph.api.calls.where((x) => x.startsWith('package')), isEmpty, reason: 'nothing downloaded on mobile data');
      expect(await ph.malls.download('bayview'), isNull, reason: 'the tap');
      expect(ph.s.saved['bayview']!.package.version, 2);
      expect(ph.s.saved['bayview']!.offered, isNull);
    });

    test('during a trip in that mall they wait, then switch in; a restart switches them in too', () async {
      final ph = Phone(installed: ['bayview']);
      await ph.boot();
      final before = ph.s.venues['bayview'];
      ph.api.publish('bayview', 2);
      ph.malls.tripIn = 'bayview';
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['bayview']!.package.version, 1);
      expect(ph.s.saved['bayview']!.pending!.version, 2);
      expect(identical(ph.s.venues['bayview'], before), isTrue, reason: 'the route never changes under your feet');
      // the app closed before the trip ended: the next start switches it in
      final again = Phone(store: ph.store, blobs: ph.blobs, api: ph.api);
      await again.boot();
      expect(again.s.saved['bayview']!.package.version, 2);
      expect(again.s.saved['bayview']!.pending, isNull);
      // or the trip ends
      ph.malls.tripIn = null;
      expect(await ph.malls.applyPending('bayview'), isTrue);
      expect(ph.s.saved['bayview']!.package.version, 2);
    });

    test('a newer format, a broken download or no connection never replace the working copy', () async {
      final ph = Phone(installed: ['bayview']);
      await ph.boot();
      ph.api.publish('bayview', 2, format: 99);
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['bayview']!.newerFormat, isTrue);
      expect(ph.s.saved['bayview']!.package.version, 1);
      ph.api.publish('bayview', 3);
      ph.api.corrupt.add('bayview');
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['bayview']!.package.version, 1);
      expect(ph.s.isSaved('bayview'), isTrue);
      ph.api.offline = true;
      await ph.malls.checkForUpdates();
      expect(ph.s.offline, isTrue);
      expect(ph.s.isSaved('bayview'), isTrue);
    });

    test('a mall the server stops offering keeps working, "no longer updated"', () async {
      final ph = Phone(installed: ['meridian']);
      await ph.boot();
      ph.api.switchOff('meridian');
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['meridian']!.retired, isTrue);
      expect(ph.s.isSaved('meridian'), isTrue);
      ph.api.switchOff('meridian', false);
      await ph.malls.checkForUpdates();
      expect(ph.s.saved['meridian']!.retired, isFalse);
    });

    test('the server can retire this app version', () async {
      final ph = Phone(installed: ['spire']);
      await ph.boot();
      ph.api.mustUpdateBelow = '99.0.0';
      await ph.malls.checkForUpdates();
      expect(ph.s.mustUpdate, isTrue);
      expect(versionOlder('1.2.0', '1.10'), isTrue);
      expect(versionOlder('1.10.0', '1.9.9'), isFalse);
      expect(versionOlder('2.0', '2.0.0'), isFalse);
    });
  });

  test('deleting a mall frees its map; its saved places stay, greyed', () async {
    final ph = Phone(installed: ['spire', 'meridian']);
    await ph.boot();
    final place = ph.s.venues['spire']!.places.firstWhere((p) => p.kind == 'store');
    ph.c.read(favouritesProvider.notifier).toggle('spire', place.id);
    await ph.malls.delete('spire');
    expect(ph.s.isSaved('spire'), isFalse);
    expect(await ph.blobs.sizeOf('packages/spire'), 0);
    final fav = ph.c.read(favouritesProvider).single;
    expect((fav.name, fav.mallName), (place.name, 'Skyline Spire'), reason: 'names kept for the greyed row');
    expect(resolveSaved(ph.s, 'spire', place.id).venue, isNull, reason: 'listed greyed: "Download this mall to use it"');
    expect(await ph.malls.download('spire'), isNull);
    expect(resolveSaved(ph.s, 'spire', place.id).place?.id, place.id, reason: 'downloading it again brings it back');
  });

  test('a saved store follows a move to another unit; a place gone from the map is greyed', () async {
    final ph = Phone(installed: ['spire']);
    await ph.boot();
    final stores = ph.s.venues['spire']!.places.where((p) => p.kind == 'store').toList();
    final a = stores[0], b = stores[1], gone = stores[2];
    void storeOn(Map<String, Object?> pkg, String placeId, {String? remove}) {
      for (final p in (pkg['places']! as List).cast<Map<String, Object?>>()) {
        p.remove('storeId');
        if (p['id'] == placeId) p['storeId'] = '77';
      }
      if (remove != null) (pkg['places']! as List).removeWhere((p) => (p as Map)['id'] == remove);
    }

    ph.api.publish('spire', 2, edit: (pkg) => storeOn(pkg, a.id));
    await ph.malls.checkForUpdates();
    final favs = ph.c.read(favouritesProvider.notifier);
    favs.toggle('spire', a.id);
    favs.toggle('spire', gone.id);
    expect(ph.c.read(favouritesProvider).first.storeId, '77');
    // version 3: the store moved from a's unit to b's, and another place left the map
    ph.api.publish('spire', 3, edit: (pkg) => storeOn(pkg, b.id, remove: gone.id));
    await ph.malls.checkForUpdates();
    expect(ph.s.saved['spire']!.package.version, 3);
    final fa = ph.c.read(favouritesProvider).first, fg = ph.c.read(favouritesProvider).last;
    expect(resolveSaved(ph.s, 'spire', fa.placeId, fa.storeId).place?.id, b.id, reason: 'the store is found at its new unit');
    expect(resolveSaved(ph.s, 'spire', fg.placeId, fg.storeId).place, isNull, reason: 'greyed: "No longer on the map"');
  });

  test('a saved package that can no longer be read is dropped at start (it can be downloaded again)', () async {
    final ph = Phone(installed: ['spire']);
    await ph.blobs.write(SavedMall.key('spire', 1), Uint8List.fromList([1, 2, 3]));
    await ph.boot();
    expect(ph.s.isSaved('spire'), isFalse);
    expect(ph.s.saved.containsKey('spire'), isFalse);
  });

  test('the stand-in server serves the samples as checksummed packages', () async {
    final api = SampleShopperApi(), dir = await api.directory();
    expect(dir.branches.map((b) => b.id), allSampleIds);
    for (final b in dir.branches) {
      expect(sha256Hex(await api.package(b.id, 1)), b.package!.checksum);
    }
  });
}

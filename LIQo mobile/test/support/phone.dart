// A phone for the malls tests: the providers in a container, with a memory store and
// blob store, the steerable test server, a fixed connection and a fixed clock.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/clock.dart';
import 'package:liqo_mobile/core/data/blob_store.dart';
import 'package:liqo_mobile/core/data/net.dart';
import 'package:liqo_mobile/core/data/shopper_api.dart';
import 'package:liqo_mobile/core/storage/store.dart';
import 'package:liqo_mobile/features/malls/data/sample_server.dart';
import 'package:liqo_mobile/features/malls/providers/malls_provider.dart';

import 'fake_server.dart';
import 'harness.dart' show fixedNow;
import 'samples.dart';

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
      appBuildProvider.overrideWithValue(Future.value(1)),
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


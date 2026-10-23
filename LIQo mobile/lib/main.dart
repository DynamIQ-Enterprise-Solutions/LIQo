// LIQo: the shopper app. Indoor wayfinding for LIQo malls: a mall downloads
// once from the shopper server and then works offline (owner decisions
// 2026-10-23). The server's address is set at build time (SHOPPER_API, local
// checks) or read from the address file (SHOPPER_CONFIG). Debug builds with
// neither use the stand-in server and its three sample malls; release builds
// never show the samples.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/data/blob_store.dart';
import 'core/data/net.dart';
import 'core/data/server_address.dart';
import 'core/data/shopper_api.dart';
import 'core/storage/store.dart';
import 'features/malls/data/sample_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // nothing before runApp may stop the app from opening: a failure here only costs a nicety
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (e) {
    debugPrint('LIQo: system UI setup failed: $e');
  }
  // Manrope is shipped with the app under the SIL Open Font License
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Manrope'], await rootBundle.loadString('assets/licenses/Manrope-OFL.txt'));
  });
  Store store;
  try {
    store = await PrefsStore.open();
  } catch (e) {
    // the phone's storage is unavailable: keep everything in memory for this session
    debugPrint('LIQo: saved settings unavailable, keeping them in memory: $e');
    store = MemoryStore();
  }
  BlobStore blobs;
  try {
    blobs = await FileBlobStore.open();
  } catch (e) {
    debugPrint('LIQo: phone storage unavailable, malls are kept in memory: $e');
    blobs = MemoryBlobStore();
  }
  final ShopperApi api = shopperApiBase.isNotEmpty
      ? HttpShopperApi(ServerAddress.fixed(shopperApiBase))
      : shopperConfigUrl.isNotEmpty
          ? HttpShopperApi(ServerAddress.fromFile(shopperConfigUrl, store))
          : kDebugMode
              ? SampleShopperApi()
              : HttpShopperApi(ServerAddress.fixed(''));
  runApp(ProviderScope(
    overrides: [
      storeProvider.overrideWithValue(store),
      blobStoreProvider.overrideWithValue(blobs),
      shopperApiProvider.overrideWithValue(api),
      netProvider.overrideWithValue(DeviceNet()),
    ],
    child: const LiqoApp(),
  ));
}

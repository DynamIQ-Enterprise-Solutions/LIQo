// LIQo: the shopper app. Indoor wayfinding for LIQo malls: a mall downloads
// once from the shopper server and then works offline (owner decisions
// 2026-10-23). Debug builds with no server address use the stand-in server and
// its three sample malls; release builds never show the samples.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/data/blob_store.dart';
import 'core/data/net.dart';
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
  final ShopperApi api = shopperApiBase.isEmpty && kDebugMode ? SampleShopperApi() : HttpShopperApi(shopperApiBase);
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

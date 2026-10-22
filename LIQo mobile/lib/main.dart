// LIQo: the shopper app. Indoor wayfinding for LIQo malls; works offline with
// three sample malls until admin-published maps and beacons arrive.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/store.dart';

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
  runApp(ProviderScope(overrides: [storeProvider.overrideWithValue(store)], child: const LiqoApp()));
}

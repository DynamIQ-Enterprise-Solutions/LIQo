import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/favicon_sync.dart';
import 'core/theme_mode.dart';
import 'shared/messaging/messages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The map canvas pans with the right mouse button; the browser menu must not steal pointer-up.
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  usePathUrlStrategy();
  // Restore the session before the first frame so there is no login flash.
  final prefs = await SharedPreferences.getInstance();

  // On the web the browser can hand the tab focus before the first frame is laid
  // out. Flutter's focus pass then trips on widgets that have no size yet and, in
  // debug builds, leaves the overlay un-laid-out. Attach a trivial tree first,
  // let one frame complete, then attach the real app.
  if (kIsWeb) {
    final darkDevice = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    runApp(ColoredBox(color: darkDevice ? Pal.darkPal.shell : Pal.light.bg));
    await WidgetsBinding.instance.endOfFrame;
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const LiqoApp(),
    ),
  );
}

class LiqoApp extends ConsumerWidget {
  const LiqoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'LIQO — Smart Way Forward',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      // Light and dark morph into each other instead of snapping.
      themeAnimationDuration: motionTheme,
      themeAnimationCurve: Curves.easeInOutCubic,
      routerConfig: router,
      builder: (context, child) => FaviconSync(child: MessageOverlay(child: child ?? const SizedBox.shrink())),
    );
  }
}

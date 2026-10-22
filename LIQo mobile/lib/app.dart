import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'features/settings/providers/settings_provider.dart';

/// The app: the look the shopper chose (system, light or dark; high contrast),
/// the text size on top of the phone's own (capped so nothing breaks), Tagalog
/// for Flutter's own strings too, and reduced motion.
class LiqoApp extends ConsumerWidget {
  const LiqoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider), router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'LIQo',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildTheme(dark: false, hc: s.highContrast),
      darkTheme: buildTheme(dark: true, hc: s.highContrast),
      themeMode: switch (s.theme) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
      themeAnimationDuration: s.reduceMotion ? Duration.zero : motionTheme,
      locale: s.lang == 'tl' ? const Locale('fil') : const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('fil')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final mq = MediaQuery.of(context), dark = Theme.of(context).brightness == Brightness.dark;
        final scale = (mq.textScaler.scale(1) * s.textSize).clamp(1.0, 2.0);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Pal.clear),
          child: MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(scale), disableAnimations: mq.disableAnimations || s.reduceMotion),
            child: child!,
          ),
        );
      },
    );
  }
}

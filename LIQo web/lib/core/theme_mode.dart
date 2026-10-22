import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session.dart' show sharedPrefsProvider;

const _prefKey = 'theme_mode';

/// Follows the device setting until the person picks a mode; the pick is
/// remembered in this browser.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.read(sharedPrefsProvider).getString(_prefKey);
    return switch (saved) { 'dark' => ThemeMode.dark, 'light' => ThemeMode.light, _ => ThemeMode.system };
  }

  void setDark(bool dark) {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    ref.read(sharedPrefsProvider).setString(_prefKey, dark ? 'dark' : 'light');
  }

  /// Back to the device setting.
  void followSystem() {
    state = ThemeMode.system;
    ref.read(sharedPrefsProvider).remove(_prefKey);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

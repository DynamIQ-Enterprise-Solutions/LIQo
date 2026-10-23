import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import '../models/app_settings.dart';

/// The shopper's settings, saved whenever they change.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.fromJson(ref.read(storeProvider).json(Keys.settings));

  void _set(AppSettings s) {
    if (s == state) return;
    state = s;
    ref.read(storeProvider).setJson(Keys.settings, s.toJson());
  }

  void setLang(String v) => _set(state.copyWith(lang: v));
  void setTheme(String v) => _set(state.copyWith(theme: v));
  void setTextSize(double v) => _set(state.copyWith(textSize: v));
  void setHighContrast(bool v) => _set(state.copyWith(highContrast: v));
  void setVibration(bool v) => _set(state.copyWith(vibration: v));
  void setReduceMotion(bool v) => _set(state.copyWith(reduceMotion: v));
  void setWheelchair(bool v) => _set(state.copyWith(wheelchair: v));
  void setPace(String v) => _set(state.copyWith(pace: v));
  void setHeadingUp(bool v) => _set(state.copyWith(headingUp: v));
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

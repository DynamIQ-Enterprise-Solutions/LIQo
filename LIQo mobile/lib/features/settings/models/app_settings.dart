// The shopper's settings (More › Settings), from the demo's Settings, trimmed to
// what the owner kept on 2026-10-22. Wording is always plain; cut-throughs are
// always on; avoid stairs / escalators live in the route options.
import 'package:flutter/foundation.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.lang = 'en',
    this.theme = 'system',
    this.textSize = 1,
    this.highContrast = false,
    this.vibration = true,
    this.reduceMotion = false,
    this.wheelchair = false,
    this.pace = 'normal',
    this.headingUp = true,
  });

  /// The version of the saved settings. 2: the map faces the way you walk by default (owner
  /// decision 2026-10-23), so settings saved before it get it switched on once.
  static const version = 2;

  /// en | tl
  final String lang;

  /// system | light | dark
  final String theme;

  /// 1.0, 1.2 or 1.4, on top of the phone's own text size.
  final double textSize;
  final bool highContrast;

  /// Every buzz: turns, wrong way, arrival.
  final bool vibration;

  /// Animations off: confetti, map motion, the theme morph.
  final bool reduceMotion;

  /// Step-free routes (lifts, ramps, wide corridors) and refuge points in an evacuation.
  final bool wheelchair;

  /// slow | relaxed | normal | brisk | fast: the minutes shown, and the simulated walk's speed.
  final String pace;

  /// The map turns to face the way you walk while walking (on by default; kept between launches).
  final bool headingUp;

  /// How much longer than at a normal pace a walk takes: more for a relaxed or slow walker,
  /// less for a brisk (+25% speed) or fast (+50%) one.
  double get paceFactor => switch (pace) { 'slow' => 1.7, 'relaxed' => 1.3, 'brisk' => 1 / 1.25, 'fast' => 1 / 1.5, _ => 1.0 };

  AppSettings copyWith({
    String? lang,
    String? theme,
    double? textSize,
    bool? highContrast,
    bool? vibration,
    bool? reduceMotion,
    bool? wheelchair,
    String? pace,
    bool? headingUp,
  }) =>
      AppSettings(
        lang: lang ?? this.lang,
        theme: theme ?? this.theme,
        textSize: textSize ?? this.textSize,
        highContrast: highContrast ?? this.highContrast,
        vibration: vibration ?? this.vibration,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        wheelchair: wheelchair ?? this.wheelchair,
        pace: pace ?? this.pace,
        headingUp: headingUp ?? this.headingUp,
      );

  Map<String, Object> toJson() => {
        'lang': lang, 'theme': theme, 'textSize': textSize, 'highContrast': highContrast, 'vibration': vibration, 'reduceMotion': reduceMotion,
        'wheelchair': wheelchair, 'pace': pace, 'headingUp': headingUp, 'v': version,
      };

  /// What was saved, with anything unreadable left at its default.
  factory AppSettings.fromJson(Object? json) {
    const d = AppSettings();
    if (json is! Map) return d;
    String str(String k, String def, List<String> ok) => ok.contains(json[k]) ? json[k] as String : def;
    bool b(String k, bool def) => json[k] is bool ? json[k] as bool : def;
    final ts = (json['textSize'] as num?)?.toDouble();
    return AppSettings(
      lang: str('lang', d.lang, const ['en', 'tl']),
      theme: str('theme', d.theme, const ['system', 'light', 'dark']),
      textSize: ts != null && const [1.0, 1.2, 1.4].contains(ts) ? ts : d.textSize,
      highContrast: b('highContrast', d.highContrast),
      vibration: b('vibration', d.vibration),
      reduceMotion: b('reduceMotion', d.reduceMotion),
      wheelchair: b('wheelchair', d.wheelchair),
      pace: str('pace', d.pace, const ['slow', 'relaxed', 'normal', 'brisk', 'fast']),
      headingUp: json['v'] is int && (json['v'] as int) >= 2 ? b('headingUp', d.headingUp) : d.headingUp,
    );
  }

  @override
  bool operator ==(Object other) => other is AppSettings && mapEquals(toJson(), other.toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

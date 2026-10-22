// Vibration cues, with Flutter's own haptics on both platforms (owner decision
// 2026-10-22; the demo used Android-only native patterns). Each cue has its own
// rhythm, so a turn can be told from a ride without looking.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Haptics {
  const Haptics();

  /// About 20 m before a left turn: one tap.
  Future<void> left() => HapticFeedback.mediumImpact();

  /// Before a right turn: two taps.
  Future<void> right() => _taps([HapticFeedback.mediumImpact, HapticFeedback.mediumImpact]);

  /// A lift, escalator or stairs coming up: a long, heavier buzz.
  Future<void> updown() => _taps([HapticFeedback.heavyImpact, HapticFeedback.vibrate]);

  /// Something needs attention (not where the app expected).
  Future<void> alert() => _taps([HapticFeedback.heavyImpact, HapticFeedback.heavyImpact, HapticFeedback.heavyImpact]);

  /// Arrived.
  Future<void> arrive() => _taps([HapticFeedback.heavyImpact, HapticFeedback.lightImpact]);

  /// A named cue: left, right, updown, alert, arrive.
  Future<void> cue(String name) => switch (name) {
        'left' => left(),
        'right' => right(),
        'updown' => updown(),
        'alert' => alert(),
        _ => arrive(),
      };

  static Future<void> _taps(List<Future<void> Function()> taps) async {
    for (var i = 0; i < taps.length; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 120));
      await taps[i]();
    }
  }
}

/// The phone's haptics; tests override it to record the cues.
final hapticsProvider = Provider<Haptics>((ref) => const Haptics());

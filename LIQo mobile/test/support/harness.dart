// A navigation session without screens: the providers in a container, a memory
// store, recorded haptics and a fixed clock.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/clock.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/engine/venue.dart';
import 'package:liqo_mobile/core/haptics.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/core/storage/store.dart';
import 'package:liqo_mobile/features/map/providers/map_provider.dart';
import 'package:liqo_mobile/features/navigation/models/nav_state.dart';
import 'package:liqo_mobile/features/navigation/providers/nav_provider.dart';
import 'package:liqo_mobile/features/navigation/providers/route_options_provider.dart';
import 'package:liqo_mobile/features/navigation/services/nav_text.dart';
import 'package:liqo_mobile/features/settings/providers/settings_provider.dart';

/// Records the vibration cues instead of buzzing.
class FakeHaptics extends Haptics {
  final cues = <String>[];
  @override
  Future<void> cue(String name) async => cues.add(name);
  @override
  Future<void> left() => cue('left');
  @override
  Future<void> right() => cue('right');
  @override
  Future<void> updown() => cue('updown');
  @override
  Future<void> alert() => cue('alert');
  @override
  Future<void> arrive() => cue('arrive');
}

final fixedNow = DateTime(2026, 10, 22, 14, 30);

class Harness {
  Harness({String mall = 'bayview', Map<String, String>? prefs, DateTime? now})
      : store = MemoryStore({Keys.mall: mall, Keys.onboardingSeen: '1', ...?prefs}),
        haptics = FakeHaptics() {
    c = ProviderContainer(overrides: [
      storeProvider.overrideWithValue(store),
      hapticsProvider.overrideWithValue(haptics),
      clockProvider.overrideWithValue(() => now ?? fixedNow),
    ]);
    addTearDown(c.dispose);
  }

  final MemoryStore store;
  final FakeHaptics haptics;
  late final ProviderContainer c;

  NavController get nav => c.read(navProvider.notifier);
  NavState get s => c.read(navProvider);
  MapController get map => c.read(mapProvider.notifier);
  MapView get mv => c.read(mapProvider);
  Venue get v => s.v;
  NavText get text => c.read(navTextProvider);
  SettingsNotifier get settings => c.read(settingsProvider.notifier);
  RouteOptionsNotifier get options => c.read(routeOptionsProvider.notifier);

  /// The shopper says they are at [p] (the nearest walking point on its level).
  void at(Pos p) => nav.refineAt(p.lv, p.x, p.y);

  /// A route from [from] to the place, as Get Directions does.
  void goFrom(Pos from, String placeId) {
    at(from);
    nav.startTo(placeId);
  }

  /// Walks the route to [m] metres the way playback does (a scrub pauses, and a pause never cues).
  void walkTo(double m) {
    final r = s.route!;
    r.progress = m.clamp(0, r.total);
    s.playing = true;
    nav.syncUser();
  }
}

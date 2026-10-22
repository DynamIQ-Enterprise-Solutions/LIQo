// Saved routes and the trip history: what starts a record, how it ends, the cap,
// a trip cut off by closing the app, and switching malls.
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/storage/keys.dart';
import 'package:liqo_mobile/features/navigation/models/route_options.dart';
import 'package:liqo_mobile/features/saved/models/saved_items.dart';
import 'package:liqo_mobile/features/saved/providers/saved_providers.dart';

import '../support/harness.dart';
import '../support/spots.dart';

void main() {
  test('every trip started is recorded: arrived, or stopped (by Stop, by another trip)', () {
    final h = Harness();
    h.goFrom(scenarioStart(h.v), '3-M1');
    var trips = h.c.read(historyProvider);
    expect(trips.single.placeId, '3-M1');
    expect(trips.single.outcome, TripOutcome.inProgress);
    h.nav.startTo('G-EHM'); // a new trip replaces it
    trips = h.c.read(historyProvider);
    expect(trips.first.placeId, 'G-EHM');
    expect(trips[1].outcome, TripOutcome.stopped);
    h.nav.debugScrub(1000);
    h.nav.confirmArrived();
    expect(h.c.read(historyProvider).first.outcome, TripOutcome.arrived);
    h.goFrom(scenarioStart(h.v), 'G-ARENA');
    h.nav.stop();
    expect(h.c.read(historyProvider).first.outcome, TripOutcome.stopped);
    expect(h.c.read(historyProvider), hasLength(3));
  });

  test('the demo trip is recorded; an evacuation is not, and the trip it replaces stops', () {
    final h = Harness()..nav.setMapVisible(true);
    h.nav.locAtFloor(0);
    expect(h.c.read(historyProvider).single.placeId, h.v.tripTarget);
    h.nav.startEmergency();
    expect(h.c.read(historyProvider).single.outcome, TripOutcome.stopped);
    h.nav.stopEmergency();
    expect(h.c.read(historyProvider), hasLength(1));
  });

  test('relocating mid-trip keeps the same record', () {
    final h = Harness();
    h.goFrom(scenarioStart(h.v), '3-M1');
    h.nav.locAtFloor(1);
    expect(h.c.read(historyProvider), hasLength(1));
    expect(h.c.read(historyProvider).single.outcome, TripOutcome.inProgress);
  });

  test('a trip still in progress when the app closed counts as stopped; at most 100 are kept', () {
    final h1 = Harness();
    for (var i = 0; i < 105; i++) {
      h1.goFrom(scenarioStart(h1.v), i.isEven ? '3-M1' : 'G-EHM');
    }
    expect(h1.c.read(historyProvider), hasLength(HistoryNotifier.cap));
    expect(h1.c.read(historyProvider).first.outcome, TripOutcome.inProgress);
    final h2 = Harness(prefs: {Keys.history: h1.store.get(Keys.history)!});
    expect(h2.c.read(historyProvider).first.outcome, TripOutcome.stopped);
    expect(h2.c.read(historyProvider).where((t) => t.outcome == TripOutcome.inProgress), isEmpty);
  });

  test('saved routes: a destination with its options; saving again removes it', () {
    final h = Harness(), routes = h.c.read(savedRoutesProvider.notifier);
    const opts = RouteOptions(metric: 'shortest', avoidStairs: true);
    routes.toggle(mallId: 'bayview', placeId: '3-M1', placeName: 'Opal Comics', options: opts, wheelchair: false);
    routes.toggle(mallId: 'spire', placeId: 'R-GDN', placeName: 'Sky Garden', options: const RouteOptions(), wheelchair: true);
    expect(h.c.read(savedRoutesProvider).map((r) => r.mallId), ['spire', 'bayview']);
    expect(routes.find('bayview', '3-M1', opts, false), isNotNull);
    expect(routes.find('bayview', '3-M1', const RouteOptions(), false), isNull, reason: 'other options are another route');
    routes.toggle(mallId: 'bayview', placeId: '3-M1', placeName: 'Opal Comics', options: opts, wheelchair: false);
    expect(h.c.read(savedRoutesProvider).single.placeId, 'R-GDN');
    // kept between launches
    final h2 = Harness(prefs: {Keys.savedRoutes: h.store.get(Keys.savedRoutes)!});
    expect(h2.c.read(savedRoutesProvider).single.wheelchair, isTrue);
  });
}

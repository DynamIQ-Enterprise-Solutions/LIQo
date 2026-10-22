// Cut-throughs: walking through a department store uses its real doors, only
// when it is clearly shorter, and never for a wheelchair route or an evacuation
// (always allowed since 2026-10-22). Find another way then goes around the
// whole store. From the demo's through_test, re-targeted to Bayview's
// department store, which has doors on both of the Main Mall's spines.
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/engine/util.dart';
import 'package:liqo_mobile/core/engine/venue.dart';

import '../support/harness.dart';
import '../support/spots.dart';

/// Ground floor, from the west end of the north spine to the shop by the department
/// store's south door: round by the West Court, or through the store.
Harness trip({bool wheel = false}) {
  final h = Harness();
  if (wheel) h.settings.setWheelchair(true);
  h.goFrom(spot(h.v, 0, 480, 300), southShop(h).id);
  return h;
}

Place southShop(Harness h) => h.v.places
    .where((p) => p.lv == 0 && p.wing == 'M' && p.kind == 'store' && p.status == 'open' && p.door[1] > 390)
    .reduce((a, b) => hypot(a.door[0] - 480, a.door[1] - 400) < hypot(b.door[0] - 480, b.door[1] - 400) ? a : b);

Iterable<String?> throughs(RouteT r) => r.seg.map((e) => e?.through).where((t) => t != null);

void main() {
  test('clearly shorter: in by one door, across the store, out by the other', () {
    final h = trip(), on = h.s.route!;
    final off = routesTo(h.s.gr, on.placeId, h.s.placeById(on.placeId)!.nodes, spot(h.v, 0, 480, 300), false).first;
    expect(throughs(on).toSet(), {'G-WDS'});
    expect(h.v.placeById('G-WDS')!.name, 'Bayview Department Store');
    expect(throughs(off), isEmpty);
    expect(on.total, lessThan(off.total));
    final step = stepsOf(on).firstWhere((s) => s.through != null);
    expect(h.text.stepText(step), startsWith('Walk through Bayview Department Store'));
    expect(h.text.stepIcon(step), 'g-fashion');
    // the metres shown are the real walk; only the choice is weighted (x1.25 across the floor)
    final gr = h.s.gr;
    final floor = [for (final n in gr.nodes.values) for (final e in gr.adj[n.k]!) if (e.through == 'G-WDS' && n.inner && gr.nodes[e.to]!.inner) (n, e)];
    expect(floor, isNotEmpty);
    final (n, e) = floor.first;
    final m = gr.nodes[e.to]!;
    expect(e.d, closeTo(hypot(n.x - m.x, n.y - m.y) * 1.25, 1e-9));
    expect(e.len, closeTo(hypot(n.x - m.x, n.y - m.y), 1e-9));
  });

  test('never for a wheelchair route, nor in an evacuation', () {
    expect(throughs(trip(wheel: true).s.route!), isEmpty);
    final h = trip();
    h.nav.startEmergency();
    expect(h.s.route, isNotNull);
    expect(throughs(h.s.route!), isEmpty);
  });

  test('Find another way just before a cut-through goes around the whole store', () {
    final h = trip(), r = h.s.route!;
    // stop a few metres before the store's door
    final i = r.seg.indexWhere((e) => e?.through != null);
    h.nav.debugScrub((r.cum[i - 1] - 8) / r.total * 1000);
    h.nav.findAnotherWay();
    final arounds = h.s.reroute!.options.where((o) => o.kind == 'around');
    expect(arounds, isNotEmpty);
    for (final o in arounds) {
      expect(throughs(o.route), isEmpty, reason: 'way around ${o.n}');
    }
  });
}

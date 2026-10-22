// The three offline malls: structure, routing rules and evacuation (from the
// demo's venues_test; the picker and switching flows are in test/app).
import 'package:flutter_test/flutter_test.dart';
import 'package:liqo_mobile/core/engine/graph.dart';
import 'package:liqo_mobile/core/engine/kit/kit_venue.dart';
import 'package:liqo_mobile/core/engine/reroute.dart';
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/features/malls/data/bayview.dart';
import 'package:liqo_mobile/features/malls/data/meridian.dart';
import 'package:liqo_mobile/features/malls/data/spire.dart';

import '../support/spots.dart';

final specs = {'bayview': bayviewSpec, 'meridian': meridianSpec, 'spire': spireSpec};

List<Step> tripSteps(KitVenue v, {bool wheel = false}) {
  final t = v.placeById(v.tripTarget)!;
  final r = routesTo(v.graph, t.id, t.nodes, scenarioStart(v), wheel);
  expect(r, isNotEmpty, reason: '${v.id} default trip (wheel: $wheel)');
  return stepsOf(r.first);
}

Iterable<Edge> hops(RouteT r) => r.seg.whereType<Edge>().where((e) => e.kind == 'hop');

void main() {
  for (final MapEntry(key: id, value: spec) in specs.entries) {
    group(id, () {
      final v = KitVenue(spec);

      test('is generated the same way every time', () {
        final again = KitVenue(spec);
        expect([for (final p in again.places) '${p.id} ${p.name} ${p.status}'], [for (final p in v.places) '${p.id} ${p.name} ${p.status}']);
        expect(again.graph.nodes.keys.toList(), v.graph.nodes.keys.toList());
      });

      test('every place can be reached on foot from the first exit', () {
        final from = firstExit(v);
        final d = dijkstra(v.graph, v.graph.nearestNodeAt(from.lv, from.x, from.y)!).d;
        expect([for (final p in v.places) if (!p.nodes.any(d.containsKey)) p.id], isEmpty);
      });

      test('the wheelchair trip uses only lifts and ramps', () {
        final t = v.placeById(v.tripTarget)!;
        final r = routesTo(v.graph, t.id, t.nodes, firstExit(v), true).first;
        expect(hops(r).map((e) => e.ctype).toSet().difference({'lift', 'ramp'}), isEmpty);
      });

      test('evacuation works from every level: an exit or a refuge, never a lift', () {
        for (var lv = 0; lv < v.levelCount; lv++) {
          final c = v.levelCentre(lv), k = v.graph.nearestNodeAt(lv, c.x, c.y)!, n = v.graph.nodes[k]!;
          final from = Pos(lv, n.x, n.y, n.out);
          for (final wheel in [false, true]) {
            final e = evacuate(v, from, wheel: wheel, banEdges: const {}, banConn: const {}, blockedExits: const {});
            if (e.outside) continue;
            expect(e.route, isNotNull, reason: '${v.levels[lv].short} wheel=$wheel');
            expect(hops(e.route!).where((h) => h.ctype == 'lift'), isEmpty, reason: '${v.levels[lv].short} wheel=$wheel');
          }
        }
      });
    });
  }

  test('Bayview: the trip from the terminal crosses the campus on covered walkways and outdoors', () {
    final steps = tripSteps(KitVenue(bayviewSpec));
    expect(steps.any((s) => s.kind == 'walk' && s.covered), isTrue);
    expect(steps.any((s) => s.kind == 'walk' && s.out && !s.covered), isTrue);
    expect(steps.any((s) => s.kind == 'enter' && s.label!.startsWith('Arena Gate')), isTrue);
  });

  test('Meridian: the trip crosses a bridge; bridges exist on levels 2, 4 and 5 only', () {
    final v = KitVenue(meridianSpec);
    expect(tripSteps(v).any((s) => s.kind == 'bridge' && s.label!.contains('bridge')), isTrue);
    final bridgeLevels = {
      for (final n in v.graph.nodes.values)
        for (final e in v.graph.adj[n.k]!)
          if (e.kind == 'bridge' && e.label!.contains('level')) v.levels[n.lv].short,
    };
    expect(bridgeLevels, {'2', '4', '5'});
  });

  test('Meridian: Fashion Hall level 4 is reached only by its own escalator', () {
    final v = KitVenue(meridianSpec), from = scenarioStart(v);
    final f4 = v.places.firstWhere((p) => p.lv == 5 && p.wing == 'F' && p.kind == 'store');
    expect(routesTo(v.graph, f4.id, f4.nodes, from, true), isEmpty);
    final r = routesTo(v.graph, f4.id, f4.nodes, from, false).first;
    expect(hops(r).last.conn, 'F-E');
  });

  test('Spire: the trip takes an express escalator that skips floors', () {
    final v = KitVenue(spireSpec);
    final express = tripSteps(v).where((s) => s.kind == 'hop' && s.id!.startsWith('EXP'));
    expect(express, isNotEmpty);
    expect(express.first.to - express.first.from, greaterThan(1));
    // and the mezzanines are step-free by ramp
    final m = v.places.firstWhere((p) => p.lv == 4 && p.kind == 'store');
    final r = routesTo(v.graph, m.id, m.nodes, scenarioStart(v), true).first;
    expect(hops(r).any((e) => e.ctype == 'ramp'), isTrue);
  });

  test('Spire: lift banks serve only their floors', () {
    final v = KitVenue(spireSpec);
    final low = v.connectors.firstWhere((c) => c.id == 'L-LOW'), high = v.connectors.firstWhere((c) => c.id == 'L-HIGH');
    expect(low.lvs.contains(12), isFalse);
    expect(high.lvs.contains(5), isFalse);
  });
}

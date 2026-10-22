// Where a test's shopper stands. The app has no fixed start point (owner
// decision 2026-10-22); a test that needs one says where, here or in place.
import 'package:liqo_mobile/core/engine/routing.dart';
import 'package:liqo_mobile/core/engine/venue.dart';

/// Just outside the venue's first exit.
Pos firstExit(Venue v) {
  final n = v.graph.nodes[v.exits.first.node]!;
  return Pos(n.lv, n.x, n.y, n.out);
}

/// The walking point nearest to (x, y) on level [lv].
Pos spot(Venue v, int lv, double x, double y) {
  final n = v.graph.nodes[v.graph.nearestNodeAt(lv, x, y)!]!;
  return Pos(n.lv, n.x, n.y, n.out);
}

/// The scenarios the demo's tests started from, one per mall: Bayview's transport
/// terminal, Meridian's level-5 bridge end, Spire's ground-floor lobby.
Pos scenarioStart(Venue v) => switch (v.id) {
      'bayview' => spot(v, 0, 720, 600),
      'meridian' => spot(v, 4, 200, 118),
      'spire' => spot(v, 0, 110, 150),
      _ => firstExit(v),
    };

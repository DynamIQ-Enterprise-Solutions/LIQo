// Turn-by-turn directions (Android port): a route as the things you do along it,
// each at a landmark ("Turn left at Zen Gifts, in 20 m, Restrooms on your right").
// The route itself (buildRoute / stepsOf) is untouched; this reads it.
import 'dart:math' as math;

import 'util.dart';
import 'graph.dart';
import 'routing.dart';
import 'venue.dart';

/// A landmark counts when its door is this close to the turn (metres).
const landmarkM = 12.0;
/// A shop is "passed" when the way runs this close to its door.
const passingM = 5.0;
/// A bend counts as a turn from this angle (degrees).
const turnDeg = 30.0;
/// Jogs shorter than this (door spurs, kinks) never make a turn.
const minLegM = 3.0;
/// A slight bend is only said where another way leaves the spot and bends at most this much more than
/// the route does (degrees): a fork. A corridor that merely curves is followed without a word.
const forkDeg = 10.0;

class Direction {
  /// turn | hop | enter | bridge | through | arrive
  final String kind;
  /// left | right | slight-left | slight-right | sharp-left | sharp-right (turns only)
  final String? turn;
  /// Route metres where this is done: the turn point, the start of a hop, the door, the end.
  final double atM;
  /// Metres walked to get here from the previous direction.
  final double approach;
  final int lv;
  /// A place by the turn (its id), and which hand it is on.
  final String? landmark, side;
  /// Places passed on the way here (ids), in order (the first two).
  final List<String> passing;
  /// Every place passed on the way here, with the route metres where the way runs past its door.
  final List<(double, String)> checkpoints;
  /// The wing the approach runs along, and whether it is outdoors.
  final String? wing;
  final bool out;
  // hop / enter / bridge / through details, as in Step
  final String? id, type, label, tech, through;
  final int from, to;
  final bool into;
  const Direction({
    required this.kind, this.turn, required this.atM, required this.approach, required this.lv, this.landmark, this.side,
    this.passing = const [], this.checkpoints = const [], this.wing, this.out = false, this.id, this.type, this.label, this.tech, this.through, this.from = 0, this.to = 0, this.into = false,
  });

  bool get isTurn => kind == 'turn';
  bool get isUpDown => kind == 'hop';
  /// The arrow glyph for the card.
  String get glyph => switch (kind) {
        'turn' => 'i-turn-${turn!}',
        'hop' => 'g-${type!}',
        'enter' => 'g-entrance',
        'bridge' => 'i-bridge',
        'arrive' => 'i-flag',
        _ => 'i-straight',
      };
}

double _norm(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a <= -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// Which hand a point is on for someone walking along [h] (screen y points down).
String sideOf(double h, double dx, double dy) => math.cos(h) * dy - math.sin(h) * dx > 0 ? 'right' : 'left';

String? _turnOf(double diff) {
  final deg = diff.abs() * 180 / math.pi;
  if (deg < turnDeg) return null;
  final hand = diff > 0 ? 'right' : 'left';
  return deg < 50 ? 'slight-$hand' : deg < 120 ? hand : 'sharp-$hand';
}

/// Is the bend at [b] (coming from [a], going on to [c], heading [h1]) a fork? True when another
/// walkway leaves [b] that bends at most [forkDeg] more than the route does, so "bear left" tells
/// the two apart. False when the route is plainly the straightest way on, or the only one: the
/// corridor curves and you are already heading that way.
bool isFork(Graph gr, Vert a, Vert b, Vert c, double h1) {
  final k = nk(b.lv, b.x, b.y), edges = gr.adj[k];
  if (edges == null) return true; // not a graph node (should not happen): keep the turn
  final ours = _norm(math.atan2(c.y - b.y, c.x - b.x) - h1).abs(), back = nk(a.lv, a.x, a.y), on = nk(c.lv, c.x, c.y);
  for (final e in edges) {
    if (e.kind == 'hop' || e.through != null || e.to == back || e.to == on) continue;
    final n = gr.nodes[e.to];
    if (n == null || n.lv != b.lv || n.inner) continue;
    final other = _norm(math.atan2(n.y - b.y, n.x - b.x) - h1).abs();
    if (other < ours + forkDeg * math.pi / 180) return true;
  }
  return false;
}

double _segDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
  final t = l2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  return hypot(px - (ax + dx * t), py - (ay + dy * t));
}

List<Direction> directionsOf(RouteT r, Venue v) {
  final verts = r.verts, seg = r.seg, n = verts.length;
  if (n < 2) return const [];
  final dest = r.placeId;
  bool solid(Place p) => p.kind != 'zone' && p.kind != 'car' && p.id != dest && (p.kind != 'store' || p.status == 'open') && !p.exitNode;
  final byLevel = <int, List<Place>>{};
  for (final p in v.places) {
    if (solid(p)) (byLevel[p.lv] ??= []).add(p);
  }

  final out = <Direction>[];
  var lastAt = 0.0; // route metres of the previous direction
  var runStart = 1; // first vertex index of the current approach
  List<(double, String)> passedAll(int from, int to, int lv, Set<String> skip) {
    // places whose door the approach runs past, in path order, with the route metres
    final found = <(double, String)>[];
    for (final p in byLevel[lv] ?? const <Place>[]) {
      if (skip.contains(p.id)) continue;
      for (var i = math.max(1, from); i <= to && i < n; i++) {
        final a = verts[i - 1], b = verts[i];
        if (a.lv != lv || b.lv != lv || isHop(seg[i])) continue;
        if (_segDist(p.door[0], p.door[1], a.x, a.y, b.x, b.y) <= passingM) {
          final dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy;
          final t = l2 == 0 ? 0.0 : (((p.door[0] - a.x) * dx + (p.door[1] - a.y) * dy) / l2).clamp(0.0, 1.0);
          found.add((r.cum[i - 1] + t * (r.cum[i] - r.cum[i - 1]), p.id));
          break;
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return found;
  }

  List<String> passed(int from, int to, int lv, Set<String> skip) => [for (final f in passedAll(from, to, lv, skip).take(2)) f.$2];

  /// Is the walk from vertex [from] to [to] outdoors?
  bool outside(int from, int to) {
    var any = false;
    for (var k = math.max(0, from - 1); k <= to && k < n; k++) {
      if (!verts[k].out) return false;
      any = true;
    }
    return any;
  }

  String? wingAt(int i) {
    final x = verts[i].x, y = verts[i].y, lv = verts[i].lv;
    Place? best;
    var bd = 40.0;
    for (final p in byLevel[lv] ?? const <Place>[]) {
      final d = hypot(p.door[0] - x, p.door[1] - y);
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    return best == null ? null : v.wingNames[best.wing];
  }

  Direction add(Direction d) {
    out.add(d);
    lastAt = d.atM;
    return d;
  }

  var i = 1;
  while (i < n) {
    final s = seg[i], a = verts[i - 1], b = verts[i];
    if (isHop(s)) {
      // one direction for a connector ride, however many floors
      var j = i;
      while (j + 1 < n && isHop(seg[j + 1]) && seg[j + 1]!.conn == s!.conn) {
        j++;
      }
      final skip = <String>{};
      add(Direction(
        kind: 'hop', atM: r.cum[i - 1], approach: r.cum[i - 1] - lastAt, lv: a.lv, id: s!.conn, type: s.ctype, from: a.lv, to: verts[j].lv,
        passing: passed(runStart, i - 1, a.lv, skip), checkpoints: passedAll(runStart, i - 1, a.lv, skip), wing: wingAt(i - 1), out: outside(runStart, i - 1),
      ));
      i = j + 1;
      runStart = i;
      lastAt = r.cum[j]; // the next approach is walked from the top (or bottom) of the ride, not from its foot
      continue;
    }
    if (s != null && (s.kind == 'enter' || s.kind == 'bridge')) {
      add(Direction(
        kind: s.kind, atM: r.cum[i - 1], approach: r.cum[i - 1] - lastAt, lv: a.lv, label: s.label, tech: s.tech, into: a.out && !b.out,
        passing: passed(runStart, i - 1, a.lv, const {}), checkpoints: passedAll(runStart, i - 1, a.lv, const {}), wing: wingAt(i - 1), out: outside(runStart, i - 1),
      ));
      i++;
      runStart = i;
      continue;
    }
    if (s?.through != null && (i == 1 || seg[i - 1]?.through != s!.through)) {
      // a cut-through a store: in by one door, out by another
      var j = i;
      while (j + 1 < n && seg[j + 1]?.through == s!.through) {
        j++;
      }
      add(Direction(kind: 'through', atM: r.cum[i - 1], approach: r.cum[i - 1] - lastAt, lv: a.lv, through: s!.through, passing: passed(runStart, i - 1, a.lv, const {}), checkpoints: passedAll(runStart, i - 1, a.lv, const {}), wing: wingAt(i - 1)));
      i = j + 1;
      runStart = i;
      continue;
    }
    // a bend between this walk and the next, both long enough to count
    if (i + 1 < n && !isHop(seg[i + 1]) && seg[i + 1]?.kind != 'enter' && seg[i + 1]?.kind != 'bridge' && b.lv == verts[i + 1].lv) {
      final c = verts[i + 1];
      final l1 = hypot(b.x - a.x, b.y - a.y), l2 = hypot(c.x - b.x, c.y - b.y);
      if (l1 >= minLegM && l2 >= minLegM) {
        final h1 = math.atan2(b.y - a.y, b.x - a.x), h2 = math.atan2(c.y - b.y, c.x - b.x);
        var turn = _turnOf(_norm(h2 - h1));
        // a slight bend where nothing else leaves the spot is just the corridor curving
        if (turn != null && turn.startsWith('slight') && !isFork(v.graph, a, b, c, h1)) turn = null;
        if (turn != null) {
          Place? mark;
          var bd = landmarkM;
          for (final p in byLevel[b.lv] ?? const <Place>[]) {
            final d = hypot(p.door[0] - b.x, p.door[1] - b.y);
            if (d < bd) {
              bd = d;
              mark = p;
            }
          }
          add(Direction(
            kind: 'turn', turn: turn, atM: r.cum[i], approach: r.cum[i] - lastAt, lv: b.lv,
            landmark: mark?.id, side: mark == null ? null : sideOf(h1, mark.door[0] - b.x, mark.door[1] - b.y),
            passing: passed(runStart, i, b.lv, {?mark?.id}), checkpoints: passedAll(runStart, i, b.lv, {?mark?.id}), wing: wingAt(i - 1), out: outside(runStart, i),
          ));
          runStart = i + 1;
        }
      }
    }
    i++;
  }
  // arriving: which hand the door is on
  final last = verts[n - 1];
  String? side;
  for (var k = n - 1; k > 0; k--) {
    final a = verts[k - 1];
    if (a.lv == last.lv && hypot(last.x - a.x, last.y - a.y) >= 1) {
      final p = v.placeById(dest);
      if (p != null && p.kind != 'car') side = sideOf(math.atan2(last.y - a.y, last.x - a.x), p.at[0] - last.x, p.at[1] - last.y);
      break;
    }
  }
  add(Direction(kind: 'arrive', atM: r.total, approach: r.total - lastAt, lv: last.lv, landmark: dest, side: side, passing: passed(runStart, n - 1, last.lv, const {}), checkpoints: passedAll(runStart, n - 1, last.lv, const {}), wing: wingAt(n - 1), out: outside(runStart, n - 1)));
  return out;
}

/// The direction coming up at [progress] metres, and its index.
(int, Direction)? upcoming(List<Direction> dirs, double progress) {
  for (var i = 0; i < dirs.length; i++) {
    if (dirs[i].atM > progress + 0.01) return (i, dirs[i]);
  }
  return dirs.isEmpty ? null : (dirs.length - 1, dirs.last);
}

/// For the route graph types used above.
typedef RouteVert = Vert;
typedef RouteEdge = Edge;

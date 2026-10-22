// Directions worded like a person giving them, never stated as fact: the dot is
// simulated, so what is around you is an expectation ("You should see Zen Gifts
// on your left; go in through its doors") followed by the real next step.
// Landmark first, "then" between directions that come close together, metres
// only when there is nothing to name. Along a long walk: checkpoints ("You
// should be passing Lumi Salon on your left about now") and closeness cues.
// From the demo's state/narration.dart; the app has no voice (owner decision
// 2026-10-22), so these sentences go to the prompts, the direction card's cue
// line and the screen reader.
import 'dart:math' as math;

import '../../../core/engine/directions.dart';
import '../../../core/engine/routing.dart';
import '../../../core/engine/util.dart';
import '../models/nav_state.dart';
import 'nav_text.dart';

/// The next direction is said in the same breath when it comes this soon after (metres).
const thenM = 25.0;
/// "You should see": places and lifts this close count (metres).
const seeM = 15.0;
/// An approach shorter than this is not worth a clause of its own (metres).
const shortApproachM = 15.0;
/// Checkpoints only on approaches longer than this (metres), at least this far apart, and this far before the turn.
const checkpointFromM = 40.0, checkpointGapM = 22.0, checkpointBeforeTurnM = 25.0, outdoorCheckpointM = 35.0;
/// A landmark named as "next look for" gets its own "coming up" cue this far before it, when the gap allows.
const comingUpM = 20.0, comingUpGapM = 44.0;

/// What to say for one direction, and which later direction it already covered.
class Narration {
  final String text;
  final int? chained;
  const Narration(this.text, this.chained);
}

/// One clause of a sentence; an arrival ("You should see X on your right; go in") stands as its own sentence.
class Clause {
  final String text;
  final bool alone;
  const Clause(this.text, {this.alone = false});
}

/// Something to show at a point along the way: a checkpoint, a "coming up", a closeness cue.
class Cue {
  final double atM;
  final String key, text, line;
  final int staleS;
  const Cue(this.atM, this.key, this.text, this.line, this.staleS);
}

String capFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

extension Narrate on NavText {
  List<Direction> get directions => s.directions;

  /// The sentence for direction [i] of the active route. [chain]: the direction that follows
  /// within [thenM] is said in the same breath; false for a pause check, which should only
  /// say the one next thing.
  Narration narrate(int i, {bool chain = true}) {
    final (clauses, chained) = _clauses(i, chain: chain);
    final b = StringBuffer();
    for (var k = 0; k < clauses.length; k++) {
      final c = clauses[k];
      if (k == 0) {
        b.write(capFirst(c.text));
      } else if (c.alone) {
        b.write('. ${capFirst(c.text)}');
      } else {
        b.write('${tr(', then ')}${c.text}');
      }
    }
    b.write('.');
    return Narration(b.toString(), chained);
  }

  /// The clauses of direction [i]'s sentence, in the current language: the approach (if any), the
  /// action, and the next direction's action when it follows within [thenM].
  List<String> narrationClauses(int i) => [for (final c in _clauses(i).$1) c.text];

  (List<Clause>, int?) _clauses(int i, {bool chain = true}) {
    final dirs = directions, d = dirs[i], target = _targetOf(d), approach = _approach(d, target);
    final out = [if (approach != null) Clause(approach), _action(d, named: approach != null && target != null)];
    int? chained;
    if (chain && d.kind != 'arrive' && i + 1 < dirs.length && dirs[i + 1].atM - d.atM <= thenM) {
      chained = i + 1;
      out.add(_action(dirs[i + 1], named: false));
    }
    return (out, chained);
  }

  /// What the approach heads for, by name.
  String? _targetOf(Direction d) => switch (d.kind) {
        'turn' => d.landmark == null ? null : placeName(d.landmark),
        'hop' => connName(d.id).isEmpty ? tr('the ${hopName[d.type]![0]}') : connName(d.id),
        'enter' || 'bridge' => d.label,
        'through' => placeName(d.through),
        _ => placeName(d.landmark),
      };

  String _passing(Direction d) => d.passing.map(placeName).join(tr(' and '));

  /// "Walk straight towards X" / "Walk past P towards X" / "Walk straight for about 120 m"; null when too short to mention.
  String? _approach(Direction d, String? target) {
    if (d.approach < shortApproachM) return null;
    final p = _passing(d);
    if (target != null) return p.isEmpty ? tr('Walk straight towards $target') : tr('Walk past $p towards $target');
    if (p.isNotEmpty) return tr('Walk straight past $p');
    final about = '${math.max(10, (d.approach / 10).round() * 10)} m';
    return tr('Walk straight for about $about${d.out ? ' outside' : ''}');
  }

  /// The thing to do when you get there. [named]: the approach already named the place, so "take it up" rather than "take the escalator up".
  Clause _action(Direction d, {required bool named}) {
    switch (d.kind) {
      case 'turn':
        final hand = d.turn!.endsWith('left') ? 'left' : 'right';
        final verb = d.turn!.startsWith('slight') ? tr('bear $hand') : d.turn!.startsWith('sharp') ? tr('turn sharp $hand') : tr('turn $hand');
        return Clause(named || d.landmark == null ? verb : tr('$verb at ${placeName(d.landmark)}'));
      case 'hop':
        final up = d.to > d.from;
        if (!named) return Clause(lowerFirst(dirTitle(d)));
        // a lift or escalator is taken; stairs and a ramp are walked up
        if (d.type == 'stairs' || d.type == 'ramp') return Clause(tr('go ${up ? 'up' : 'down'} ${d.type == 'stairs' ? 'them' : 'it'} to ${levelLow(d.to)}'));
        return Clause(tr('take it ${up ? 'up' : 'down'} to ${levelLow(d.to)}'));
      case 'enter':
        return Clause(named ? (d.into ? tr('go in') : tr('go out')) : lowerFirst(dirTitle(d)));
      case 'through':
        return Clause(named ? tr('go through it') : lowerFirst(dirTitle(d)));
      case 'bridge':
        return Clause(named ? tr('cross it') : lowerFirst(dirTitle(d)));
      default:
        return Clause(arrivalClause(d), alone: true);
    }
  }

  /// "You should see Bay IMAX on your left; go in through its doors." An expectation, then the real thing to do.
  String arrivalClause(Direction d) {
    final name = placeName(d.landmark), p = d.landmark == null ? null : s.placeById(d.landmark!);
    final doIt = p != null && p.kind == 'store' ? tr('go in through its doors') : tr('this should be it');
    final see = d.side == null ? tr('You should be right by $name') : tr('You should see $name on your ${d.side}');
    return '$see; $doIt';
  }

  // ----- what is around a spot -----

  /// What is around a spot, nearest first: (name, where) with where = ahead | left | right | behind | near.
  List<(String, String)> surroundings(int lv, double x, double y, double? heading, {String? exclude, String? excludeConn, int max = 3, bool outdoors = false}) {
    final found = <(double, String, String)>[];
    String rel(double dx, double dy, double dist) {
      if (heading == null || dist < 2) return 'near';
      var a = math.atan2(dy, dx) - heading;
      while (a > math.pi) {
        a -= 2 * math.pi;
      }
      while (a <= -math.pi) {
        a += 2 * math.pi;
      }
      final deg = a.abs() * 180 / math.pi;
      return deg < 25 ? 'ahead' : deg > 135 ? 'behind' : sideOf(heading, dx, dy);
    }

    for (final p in v.places) {
      if (p.lv != lv || p.id == exclude || p.kind == 'zone' || p.kind == 'car' || p.exitNode || (p.kind == 'store' && p.status != 'open')) continue;
      final dx = p.door[0] - x, dy = p.door[1] - y, dist = hypot(dx, dy);
      if (dist <= seeM) found.add((dist, p.name, rel(dx, dy, dist)));
    }
    for (final c in v.connectors) {
      if (c.id == excludeConn) continue;
      final k = c.at[lv];
      final n = k == null ? null : s.gr.nodes[k];
      if (n == null) continue;
      final dx = n.x - x, dy = n.y - y, dist = hypot(dx, dy);
      if (dist <= seeM) found.add((dist, c.name, rel(dx, dy, dist)));
    }
    if (outdoors && lv == v.ground) {
      // outside, things are bigger and further apart: the plaza, a car park, a building
      for (final l in v.siteLabels) {
        final dx = l.x - x, dy = l.y - y, dist = hypot(dx, dy);
        if (dist <= 2 * seeM) found.add((dist, l.name, rel(dx, dy, dist)));
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final f in found.take(max)) (f.$2, f.$3)];
  }

  String _seeItem((String, String) it) => switch (it.$2) {
        'ahead' => tr('${it.$1} ahead'),
        'behind' => tr('${it.$1} behind you'),
        'near' => it.$1,
        _ => tr('${it.$1} on your ${it.$2}'),
      };

  String _seeList(List<(String, String)> items) {
    final parts = items.map(_seeItem).toList();
    if (parts.length < 2) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')}${tr(' and ')}${parts.last}';
  }

  /// What the shopper should see where the dot is: around them, by hand. Empty when nothing is near.
  List<(String, String)> seeAround({String? excludeConn, int max = 3}) {
    final u = s.user;
    if (u == null) return const [];
    return surroundings(u.lv, u.x, u.y, s.heading, exclude: s.route?.placeId, excludeConn: excludeConn, max: max, outdoors: u.out);
  }

  /// The card's line for the first metres after a ride: "If you see Wren Crafts on your right, you're in the right place".
  String? seeLine({String? excludeConn}) {
    final items = seeAround(excludeConn: excludeConn, max: 2);
    return items.isEmpty ? null : tr("If you see ${_seeList(items)}, you're in the right place");
  }

  /// The "You should see ..." line, for the first 20 m after a ride.
  String? get afterRideLine {
    final e = s.rideEndAt, r = s.route, u = s.user;
    if (e == null || r == null || u == null || !identical(e.$1, r) || r.progress - e.$2 > 20 || u.lv != e.$3) return null;
    return seeLine(excludeConn: e.$4);
  }

  /// On a landing of stairs or an escalator: "Level 2 · keep going up to level 4".
  String? get landingShown {
    final t = s.transit, lv = s.ridingLv;
    if (t == null || t.ctype == 'lift' || lv == null) return null;
    final hi = s.rideIndex(t);
    if (hi < 0 || lv == directions[hi].to || lv == directions[hi].from) return null;
    return landingLine(hi, lv);
  }

  /// The card's line on a landing: "Level 2 · keep going up to level 4".
  String landingLine(int hop, int lv) {
    final d = directions[hop];
    return tr('${levelName(lv)} · keep going ${d.to > d.from ? 'up' : 'down'} to ${levelLow(d.to)}');
  }

  /// The lift, escalator or stairs the walk stopped at, by name, when the question is about one.
  String? get checkRideName {
    final ride = s.checkRideIndex;
    if (ride == null) return null;
    final d = directions[ride];
    return connName(d.id).isEmpty ? tr('the ${hopName[d.type]![0]}') : connName(d.id);
  }

  /// The pause check: "Are you here? You should be on level 2, with Zen Gifts ahead. If that's right,
  /// walk straight towards the escalator and take it up." Only the nearest landmark and the one
  /// next thing to do. At a lift, escalator or stairs the walk stopped at: "Are you at South
  /// escalators? …, take the escalator up to level 2."
  String checkQuestion() {
    final u = s.user;
    if (u == null) return tr('Are you here?');
    final name = checkRideName, ride = name == null ? null : s.checkRide;
    final items = seeAround(excludeConn: ride == null ? null : directions[ride].id, max: 1);
    final where = '${tr('You should be on ${levelLow(u.lv)}')}${items.isEmpty ? '' : tr(', with ${_seeList(items)}')}.';
    // at a lift, escalator or stairs: just what to do with it (you are standing at it, not walking towards it)
    final idx = ride ?? s.nextDirection?.$1;
    final step = idx == null || idx >= directions.length
        ? null
        : ride != null
            ? '${_action(directions[idx], named: false).text}.'
            : lowerFirst(narrate(idx, chain: false).text);
    final next = step == null ? '' : " ${tr("If that's right, ")}$step";
    return '${name != null ? tr('Are you at $name?') : tr('Are you here?')} $where$next';
  }

  // ----- cues along the way -----

  /// The cues along the approach to direction [i], in route order: checkpoints at landmarks you
  /// pass (or, outdoors, every 35 m), "coming up" before a landmark that was pointed to, and, for
  /// the destination, getting close / almost there / this should be it.
  List<Cue> cuesFor(int i) {
    final r = s.route;
    if (r == null) return const [];
    final d = directions[i], start = d.atM - d.approach, out = <Cue>[];
    // nothing within 25 m of the turn's own cues, nor of the closeness cues at the end
    final clear = d.kind == 'arrive' ? closeFarM + 10 : checkpointBeforeTurnM;
    if (d.approach > checkpointFromM) {
      final marks = [for (final c in d.checkpoints) if (c.$1 >= start + 15 && d.atM - c.$1 >= clear) c];
      if (marks.isNotEmpty) {
        var last = start;
        for (var k = 0; k < marks.length; k++) {
          final (m, id) = marks[k];
          if (m - last < checkpointGapM) continue;
          final next = k + 1 < marks.length ? marks[k + 1] : null;
          if (next != null && next.$1 - m >= comingUpGapM) {
            final line = tr('${placeName(next.$2)} coming up on your ${_sideAt(r, next.$1, next.$2)}');
            out.add(Cue(next.$1 - comingUpM, 'up:${next.$2}', line, line, 4));
          }
          final passing = tr('You should be passing ${placeName(id)} on your ${_sideAt(r, m, id)} about now');
          final tail = next != null
              ? tr('next look for ${placeName(next.$2)} on your ${_sideAt(r, next.$1, next.$2)}')
              : _targetOf(d) != null
                  ? tr('next look for ${_targetOf(d)}')
                  : '';
          out.add(Cue(m, 'cp:$id', '$passing. ${tr('Keep straight')}${tail.isEmpty ? '' : '; $tail'}.', passing, 6));
          last = m;
        }
        out.sort((a, b) => a.atM.compareTo(b.atM));
      } else {
        // nothing to pass by name (outdoors, a long empty corridor): a word every 35 m when there is
        // something to say (what is around, or how far the target is), every 70 m when there is not
        final target = _targetOf(d);
        for (var m = start + outdoorCheckpointM; d.atM - m >= clear; m += outdoorCheckpointM) {
          final at = pointAt(r, m), near = surroundings(at.lv, at.pos[0], at.pos[1], at.heading, exclude: r.placeId, max: 1, outdoors: at.out);
          final rem = fmtM(d.atM - m);
          if (near.isEmpty && target == null && ((m - start) / outdoorCheckpointM).round().isOdd) continue;
          final tail = target != null ? tr('$target should be about $rem ahead') : tr('Keep straight for about $rem more');
          final passing = near.isEmpty
              ? ''
              : '${tr('You should be passing ${near.first.$1}${near.first.$2 == 'near' || near.first.$2 == 'ahead' || near.first.$2 == 'behind' ? '' : ' on your ${near.first.$2}'} about now')}. ';
          final text = target != null ? '$passing${tr('Keep straight')}; $tail.' : '$passing$tail.';
          out.add(Cue(m, 'cp:${m.round()}', text, capFirst(passing.isEmpty ? tail : passing.trim()), 6));
        }
      }
    }
    if (d.kind == 'arrive') {
      final side = d.side == null ? tr('This should be it') : tr('This should be it, on your ${d.side}');
      if (d.approach > 70) out.add(Cue(r.total - closeFarM, 'close', '${tr('Getting close now, about ${fmtM(closeFarM)}')}.', tr('Getting close'), 4));
      if (d.approach > 40) out.add(Cue(r.total - closeNearM, 'almost', '${tr('Almost there.')} ${arrivalClause(d)}.', tr('Almost there'), 4));
      out.add(Cue(r.total - closeHereM, 'here', '$side.', tr('Almost there'), 4));
    }
    out.sort((a, b) => a.atM.compareTo(b.atM));
    return out;
  }

  /// Which hand a place is on for someone walking the route at [m].
  String _sideAt(RouteT r, double m, String id) {
    final p = s.placeById(id), at = pointAt(r, math.max(0, m - 1));
    if (p == null || at.heading == null) return 'left';
    return sideOf(at.heading!, p.door[0] - at.pos[0], p.door[1] - at.pos[1]);
  }

  /// The arrival note while the dot stands at the end: "You should be at Bay IMAX now. Tap I've arrived if you are."
  String atEndSentence() => tr("You should be at ${placeName(s.route?.placeId)} now. Tap I've arrived if you are.");

  /// What a screen reader says for the map.
  String mapSummary(String mode, int level) {
    final u = s.user;
    final parts = <String>[
      tr('Map'),
      mode == 'site' ? tr('Whole site') : mode == 'stack' ? tr('All levels') : tr('Showing ${levelLow(level)}'),
      if (u != null) tr('You are on ${levelLow(u.lv)}${u.out ? ', outside' : ''}'),
    ];
    final r = s.route;
    if (r != null && !s.arrived) {
      parts.add(tr('Route to ${placeName(r.placeId)}, ${fmtM(r.total - r.progress)} to go'));
      final up = s.nextDirection;
      if (up != null) parts.add('${tr('Next: ')}${narrate(up.$1).text.replaceFirst(RegExp(r'\.$'), '')}');
    } else if (s.emergency) {
      parts.add(tr('Emergency evacuation'));
    }
    return '${parts.join('. ')}.';
  }
}

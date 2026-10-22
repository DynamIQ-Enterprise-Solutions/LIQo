// The words the navigation shows: distances and minutes, level and place names,
// step and direction lines (from the demo's AppState helpers). Always plain
// wording, in Tagalog when chosen.
import 'dart:math' as math;

import '../../../core/engine/constants.dart';
import '../../../core/engine/directions.dart';
import '../../../core/engine/routing.dart';
import '../../../core/engine/util.dart';
import '../../../core/engine/venue.dart';
import '../../../core/i18n/words.dart';
import '../models/nav_state.dart';

const statusText = {
  'open': ['Open', 'i-check'],
  'closed': ['Closed', 'i-x'],
  'maintenance': ['Being repaired', 'i-wrench'],
  'comingSoon': ['Opening soon', 'i-clock'],
};

class NavText {
  NavText(this.s, this.w, {this.paceFactor = 1});

  final NavState s;
  final Words w;

  /// Minutes are stretched for a relaxed or slow walker.
  final double paceFactor;

  Venue get v => s.v;
  List<LevelDef> get levels => s.levels;
  String tr(String en) => w.tr(en);

  String fmtM(double m) => '${math.max(1, jsRound(m))} m';
  String fmtEta(double m) {
    final sec = m / walkMps * paceFactor;
    return sec < 60 ? '< 1 min' : '${(sec / 60).ceil()} min';
  }

  String levelName(int lv) => tr(levels[lv].name);
  String levelLow(int lv) => levels[lv].name.toLowerCase();
  String placeName(String? id) => id == null ? '' : (s.placeById(id)?.name ?? id);
  String connName(String? id) => v.connectors.where((c) => c.id == id).map((c) => c.name).firstOrNull ?? '';

  /// "About 120 m to walk"; nothing while the shopper has not said where they are.
  String distTxt(Place p) {
    if (!s.hasPosition) return '';
    final m = s.distOf(p);
    return m == null ? tr('No way there') : tr('About ${fmtM(m)} to walk');
  }

  /// "Level 2, Main Mall"; for a lift or escalator, where it goes.
  String placeSub(Place p) {
    if (p.kind == 'conn') {
      final c = v.connectors.where((c) => 'CONN:${c.id}' == p.id).firstOrNull;
      final span = c == null ? '' : '${levels[c.lvs.first].short} ${tr('to')} ${levels[c.lvs.last].short}';
      return '${tr(hopName[p.cat]?[1] ?? p.cat)} · $span';
    }
    final wing = v.wingNames[p.wing];
    return wing == null || wing.isEmpty ? levelName(p.lv) : '${levelName(p.lv)}, ${tr(wing)}';
  }

  /// "Level 2 · About 85 m to walk" (or just the level, with no position).
  String placeLine(Place p) {
    final d = distTxt(p);
    return d.isEmpty ? placeSub(p) : '${placeSub(p)} · $d';
  }

  String stepIcon(Step st) => st.through != null
      ? 'g-${s.placeById(st.through!)?.cat ?? 'other'}' // a cut-through: the store's own glyph
      : st.kind == 'walk' ? 'i-walk' : st.kind == 'hop' ? 'g-${st.type}' : st.kind == 'bridge' ? 'i-bridge' : 'g-entrance';

  String stepText(Step st) {
    if (st.through != null) return tr('Walk through ${placeName(st.through)} (${fmtM(st.m)})');
    if (st.kind == 'walk' && st.covered) return tr('Walk ${fmtM(st.m)} along the covered walkway');
    if (st.kind == 'walk') return tr('Walk ${fmtM(st.m)}${st.out ? ' outside' : ''}');
    if (st.kind == 'hop') return tr('Take the ${hopName[st.type]![0]}${st.to > st.from ? ' up' : ' down'} to ${levelLow(st.to)}');
    if (st.kind == 'bridge') return tr('Cross ${st.label}');
    return st.into ? tr('Go in through ${st.label}') : tr('Go out through ${st.label}');
  }

  /// The direction card's title: landmark first.
  String dirTitle(Direction d) {
    switch (d.kind) {
      case 'turn':
        // the English verb is composed first, so the Tagalog dictionary sees "Turn left" whole
        final hand = d.turn!.endsWith('left') ? 'left' : 'right';
        final verb = d.turn!.startsWith('slight') ? tr('Bear $hand') : d.turn!.startsWith('sharp') ? tr('Turn sharp $hand') : tr('Turn $hand');
        return d.landmark == null ? verb : tr('$verb at ${placeName(d.landmark)}');
      case 'hop':
        return stepText(Step(kind: 'hop', id: d.id, type: d.type, from: d.from, to: d.to, endAt: 0));
      case 'enter' || 'bridge':
        return stepText(Step(kind: d.kind, label: d.label, tech: d.tech, into: d.into, endAt: 0));
      case 'through':
        return tr('Walk through ${placeName(d.through)}');
      default:
        // an expectation, not a fact: the dot is simulated
        final name = placeName(d.landmark);
        return d.side == null ? tr('Arrive at $name') : tr('$name · should be on your ${d.side}');
    }
  }

  /// Under the title: how far, and what you pass on the way.
  String dirSub(Direction d, double progress) {
    final m = d.atM - progress;
    final parts = <String>[
      if (d.kind == 'hop') connName(d.id),
      if (m >= 3) tr('in ${fmtM(m)}') else if (d.kind != 'arrive') tr('now'),
      if (d.passing.isNotEmpty && m > 15) tr('past ${d.passing.map(placeName).join(' and ')}'),
    ];
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }

  /// The walk up to a direction, for the list: "Walk 120 m along the North wing, past the ATM".
  String? dirApproach(Direction d) {
    if (d.approach < 15) return null;
    final along = d.out ? tr(' outside') : d.wing == null ? '' : tr(' along the ${d.wing}');
    final past = d.passing.isEmpty ? '' : tr(', past ${d.passing.map(placeName).join(' and ')}');
    return tr('Walk ${fmtM(d.approach)}$along$past');
  }

  String status(String st) => tr(statusText[st]![0]);
}

// Panels of the map's sheet: other ways to the destination, the evacuation,
// and the "Find another way" row of the route sheet (from the demo's
// reroute_sheet; reported problems, marking and "This exit is blocked" were left out).
import 'package:flutter/material.dart' hide Step;
import 'package:go_router/go_router.dart';

import '../../../../core/engine/reroute.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import 'location_panel.dart';
import 'map_scope.dart';

Widget _col(List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);

Widget _ttl(Widget tile, Widget body, {Widget? trail}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [tile, const SizedBox(width: 10), Expanded(child: body), if (trail != null) ...[const SizedBox(width: 10), trail]]),
    );

String _more(MapScope sc, double dm) {
  final eta = sc.t.fmtEta(dm);
  return '+${sc.t.fmtM(dm)} · ${eta.startsWith('<') ? sc.tr('under 1 min more') : '+$eta'}';
}

/// "Other ways": the current way, up to three ways around, similar places, tips and help.
/// It asks nothing about why: the shopper just picks.
Widget rerouteBody(BuildContext context) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal, rr = s.reroute!, place = s.placeById(rr.placeId)!;
  final base = rr.options.where((o) => o.kind == 'current').firstOrNull?.stats;
  return _col([
    const Grab(),
    _ttl(
      const Tile('i-detour', size: 48),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sc.tr('Other ways to ${place.name}'), style: ts(18, w: FontWeight.w700, color: p.ink)),
        Text(sc.tr('Pick the way that suits you'), style: ts(12.5, color: p.muted)),
      ]),
      trail: RoundBtn('i-close', label: sc.tr('Close'), onTap: sc.nav.cancelReroute),
    ),
    if (!rr.options.any((o) => o.kind == 'around'))
      iconNote(context, 'warn', 'i-alert', sc.tr('There is no other way there right now. Try somewhere similar below, or ask for help.'), top: 2),
    const SizedBox(height: 4),
    for (var i = 0; i < rr.options.length; i++) _OptionRow(i: i, o: rr.options[i], sel: i == rr.sel, base: base),
    if (rr.nearby.isNotEmpty) ...[
      SectionLabel(sc.tr('Or go somewhere similar'), padding: const EdgeInsets.only(top: 14, bottom: 6)),
      CardX(children: [
        for (var i = 0; i < rr.nearby.length; i++)
          RowX(
            onTap: () => sc.nav.goSimilar(rr.nearby[i].id),
            lead: CatTile(rr.nearby[i].cat),
            title: rr.nearby[i].name,
            sub: sc.t.placeLine(rr.nearby[i]),
            last: i == rr.nearby.length - 1,
          ),
      ]),
    ],
    SectionLabel(sc.tr('Tips'), padding: const EdgeInsets.only(top: 14, bottom: 6)),
    for (final tip in [
      sc.tr('The other ways go around the stretch just ahead of you. Your current way is still here too.'),
      // the current way cuts through a store
      if (rr.savedRoutes.isNotEmpty && rr.savedRoutes[rr.savedIdx.clamp(0, rr.savedRoutes.length - 1)].seg.any((e) => e?.through != null))
        sc.tr("If a store's door is locked or closed, the other ways go around the store."),
      sc.tr('If it is only busy, waiting a few minutes can be quicker than a long way round.'),
      sc.tr('If a lift or escalator has stopped, stairs or another lift are usually close by.'),
      sc.tr('Not sure? Staff at the information desk can help.'),
    ])
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('•  ', style: ts(13.5, color: p.muted)),
          Expanded(child: Text(tip, style: ts(13.5, color: p.ink))),
        ]),
      ),
    btns([
      Btn(sc.tr('Get help'), onTap: sc.nav.help),
      Btn(sc.tr('Go this way'), primary: true, disabled: rr.options.isEmpty, onTap: sc.nav.confirmReroute),
    ], top: 8),
  ]);
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.i, required this.o, required this.sel, required this.base});
  final int i;
  final RouteOption o;
  final bool sel;
  final RouteStats? base;

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), p = context.pal, st = o.stats, t = sc.t;
    final title = o.kind == 'current' ? sc.tr('Your current way') : sc.tr('Way around ${o.n}');
    final b = base;
    final chips = <Widget>[
      if (o.kind == 'around' && b != null) ...[
        if ((st.total - b.total).abs() < 1)
          flChip(context, sc.tr('Same length'))
        else if (st.total > b.total)
          flChip(context, _more(sc, st.total - b.total))
        else
          ChipX(label: '−${t.fmtM(b.total - st.total)}', fg: p.open, bg: p.openBg),
        if (st.levelChanges > b.levelChanges)
          flChip(context, sc.tr('${st.levelChanges - b.levelChanges} more level ${st.levelChanges - b.levelChanges == 1 ? 'change' : 'changes'}')),
        if (st.levelChanges < b.levelChanges)
          flChip(context, sc.tr('${b.levelChanges - st.levelChanges} fewer level ${b.levelChanges - st.levelChanges == 1 ? 'change' : 'changes'}')),
        if (st.outside && !b.outside) flChip(context, sc.tr('Goes outside')),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        selected: sel,
        child: Tap(
          onTap: () => sc.nav.previewOption(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: sel ? p.soft : p.panel,
              border: Border.all(color: sel ? p.brand : p.line, width: p.lineW),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: sel ? p.brand : p.line, width: 2)),
                alignment: Alignment.center,
                child: sel ? Container(width: 8, height: 8, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle)) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: ts(15, w: FontWeight.w600, color: sel ? p.brand2 : p.ink)),
                  Text('${t.fmtM(st.total)} · ${t.fmtEta(st.total)}', style: ts(12.5, color: p.muted)),
                  if (chips.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 6, runSpacing: 4, children: chips)),
                ]),
              ),
              // the chosen option carries its own "Go this way", so it needs no scrolling to the bottom
              if (sel) ...[
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: sc.tr('Go this way'),
                  child: Tap(
                    onTap: sc.nav.confirmReroute,
                    child: Container(
                      key: ValueKey('rrgo-$i'),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: AppIcon('i-check', color: p.onBrand),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The evacuation sheet, when there is no way to walk: no position yet, already outside, no way out, or arrived.
Widget evacBody(BuildContext context) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal, r = s.route;
  final header = Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: p.danger, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      AppIcon('i-alert', color: p.panel),
      const SizedBox(width: 10),
      Expanded(child: Text(sc.tr('Emergency: get out by the nearest exit'), style: ts(15, w: FontWeight.w700, color: p.panel))),
    ]),
  );
  final help = s.evacHelp ? iconNote(context, 'info', 'i-help', sc.tr('Tell any member of staff where you are. Staff are trained to help everyone get out.')) : null;
  final stopRow = btns([Btn(sc.tr('Get help'), onTap: sc.nav.help), Btn(sc.tr('Stop evacuation'), onTap: sc.nav.stopEmergency)]);
  final e = s.evac;
  if (e == null) {
    // no position yet: the way out needs one
    return _col([
      const Grab(), header,
      iconNote(context, 'warn', 'i-pin', sc.tr('Tell us where you are, and the way out will show.')),
      ?help,
      btns([Btn(sc.tr('Where are you?'), primary: true, onTap: sc.nav.openLocation)]),
      stopRow,
    ]);
  }
  if (e.outside) {
    return _col([
      const Grab(), header,
      iconNote(context, 'ok', 'i-check', sc.tr('You are outside. Move away from the building and follow staff.')),
      ?help, stopRow,
    ]);
  }
  if (r == null) {
    return _col([
      const Grab(), header,
      iconNote(context, 'warn', 'i-alert', sc.tr('No way out can be found from here. Stay where you are, keep calm and call for help.')),
      ?help, stopRow,
    ]);
  }
  // on the way out, the red banner and bottom bar take over (nav_bar.dart); the sheet says you made it
  return _col([
    const Grab(),
    header,
    e.refuge
        ? iconNote(context, 'warn', 'i-flag', sc.tr('Wait here at the stairs. Staff will come and help you down.'))
        : iconNote(context, 'ok', 'i-check', sc.tr('You are out. Keep clear of the doors and follow staff.')),
    ?help,
    stopRow,
  ]);
}

/// Under the next step while navigating: "Find another way", and the route options.
Widget findAnotherWayRow(BuildContext context) {
  final sc = MapScope.of(context), p = context.pal;
  Widget pill(String key, String icon, String label, VoidCallback onTap) => Expanded(
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: Tap(
            onTap: onTap,
            child: Container(
              key: ValueKey(key),
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line, width: p.lineW), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(icon, size: 18, color: p.brand2),
                const SizedBox(width: 6),
                Flexible(child: Text(label, style: ts(13.5, w: FontWeight.w700, color: p.brand2), maxLines: 2, textAlign: TextAlign.center)),
              ]),
            ),
          ),
        ),
      );
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(children: [
      pill('reroute', 'i-detour', sc.tr('Find another way'), sc.nav.findAnotherWay),
      const SizedBox(width: 8),
      pill('route-options', 'i-layers', sc.tr('Route options'), () => context.push('/route-options')),
    ]),
  );
}

/// When the route goes to the information desk for help.
Widget helpNote(BuildContext context) {
  final sc = MapScope.of(context);
  return iconNote(context, 'info', 'i-help', sc.tr('Staff at the information desk can help you. Any member of staff in uniform can help too.'));
}

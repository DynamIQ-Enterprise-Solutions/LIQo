// The map's bottom sheet (from the demo's sheet.dart): a place's card, the route
// with its next direction, the nearest places of a kind, and the panels for
// "Where are you?", other ways and the evacuation. The full list of directions
// is its own page (Your Route, /route).
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/clock.dart';
import '../../../../core/engine/directions.dart';
import '../../../../core/engine/graph.dart';
import '../../../../core/engine/routing.dart';
import '../../../../core/engine/venue.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../navigation/models/nav_state.dart';
import '../../../navigation/services/narration.dart';
import '../../../places/models/category.dart';
import '../../../places/services/place_info_catalog.dart';
import '../../../places/services/place_status.dart';
import '../../../saved/providers/saved_providers.dart';
import '../../../settings/providers/settings_provider.dart';
import 'location_panel.dart';
import 'map_scope.dart';
import 'reroute_panel.dart';

/// What the sheet shows, to tell when it changes (a new kind opens at its summary).
String? sheetKind(NavState s) => s.locSheet
    ? 'loc'
    : s.emergency
        ? 'evac'
        : s.reroute != null
            ? 'reroute'
            : s.wcError != null
                ? 'wc'
                : s.route != null
                    ? 'route:${s.place}'
                    : s.near != null
                        ? 'near:${s.near!.type}'
                        : s.place != null
                            ? 'place:${s.place}'
                            : null;

/// The sheet's content; null when it is empty.
Widget? sheetBody(BuildContext context, {FocusNode? locFocus}) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal;
  if (s.locSheet) return LocationPanel(focus: locFocus);
  if (s.emergency) return evacBody(context);
  if (s.reroute != null) return rerouteBody(context);

  if (s.wcError != null) {
    final wp = s.placeById(s.wcPlace ?? '');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Grab(),
      _ttl(CatTile(wp?.cat ?? 'other', size: 48), Text(s.wcError!, style: ts(18, w: FontWeight.w700, color: p.ink))),
      note(
        context,
        'warn',
        Text(s.routeOpts.wheel ? sc.tr('There is no wheelchair route to ${s.wcError}.') : sc.tr('There is no way to ${s.wcError} from here.')),
        top: 2,
      ),
      btns([
        if (s.routeOpts.wheel) Btn(sc.tr('Turn off wheelchair route'), onTap: () => _setWheel(context, false)),
        Btn(sc.tr('Close'), onTap: sc.nav.stop),
      ]),
    ]);
  }
  final r = s.route;
  if (r == null && s.near != null) return _nearBody(context);
  final pl = s.place == null ? null : s.placeById(s.place!);
  if (pl == null) return null;
  if (r == null) return _PlaceCard(place: pl);
  if (s.arrived) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Grab(),
      note(context, 'ok', Row(children: [AppIcon('i-check', color: p.open), const SizedBox(width: 4), Flexible(child: Text(sc.tr('You have arrived at ${pl.name}')))]), top: 0),
      btns([Btn(sc.tr('Done'), onTap: sc.nav.stop, primary: true)]),
    ]);
  }
  return _RouteHead(place: pl, route: r);
}

void _setWheel(BuildContext context, bool on) => ProviderScope.containerOf(context).read(settingsProvider.notifier).setWheelchair(on);

Widget _ttl(Widget tile, Widget body, {Widget? trail}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [tile, const SizedBox(width: 10), Expanded(child: body), if (trail != null) ...[const SizedBox(width: 10), trail]]),
    );

/// A place's card: what it is, whether it is open, and the way there.
class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, pl = place;
    final fav = ref.watch(favouritesProvider).any((f) => f.mallId == sc.mallId && f.placeId == pl.id);
    final info = placeInfoFor(s.v, pl), status = placeStatus(pl, info, ref.watch(clockProvider)(), t.w);
    final u = s.user;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Grab(),
      _ttl(
        CatTile(pl.cat, size: 48),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pl.name, style: ts(18, w: FontWeight.w700, color: p.ink)),
          Text(t.placeLine(pl), style: ts(12.5, color: p.muted)),
        ]),
        trail: Row(mainAxisSize: MainAxisSize.min, children: [
          if (pl.kind != 'conn') ...[
            RoundBtn('i-star', on: fav, label: fav ? sc.tr('Remove from favourites') : sc.tr('Add to favourites'), onTap: () => ref.read(favouritesProvider.notifier).toggle(sc.mallId, pl.id)),
            const SizedBox(width: 8),
          ],
          RoundBtn('i-close', label: sc.tr('Close'), onTap: sc.nav.stop),
        ]),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (pl.kind != 'zone' && pl.kind != 'conn') statusChip(context, status.key, status.line),
        if (u != null && pl.lv != u.lv) flChip(context, sc.tr('On ${t.levelLow(pl.lv)}')),
        if (u != null && u.out) flChip(context, sc.tr('You are outside')),
      ]),
      if (status.blocksRouting) note(context, 'warn', Text(sc.tr('Not open, so you cannot go here yet.')))
      else if (status.key == 'closedNow') note(context, 'warn', Text(status.line)),
      btns([
        if (pl.kind != 'conn') Btn(sc.tr('Details'), onTap: () => context.push('/place/${sc.mallId}/${pl.id}')),
        Btn(sc.tr('Get directions'), primary: true, disabled: status.blocksRouting, onTap: () => sc.nav.startTo(pl.id)),
      ]),
    ]);
  }
}

/// The route's summary: where to, how long, the next direction, start or pause, and other ways.
class _RouteHead extends ConsumerWidget {
  const _RouteHead({required this.place, required this.route});
  final Place place;
  final RouteT route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, r = route, pl = place, m = context.mapPal;
    final rem = r.total - r.progress, next = s.nextDirection, at = pointAt(r, r.progress);
    final fav = ref.watch(favouritesProvider).any((f) => f.mallId == sc.mallId && f.placeId == pl.id);
    final info = placeInfoFor(s.v, pl), status = placeStatus(pl, info, ref.watch(clockProvider)(), t.w);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const Grab(),
      Row(children: [
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${sc.tr('To ${pl.name} · ${s.levels[pl.lv].name}')}\n', style: ts(12.5, w: FontWeight.w500, color: p.muted)),
            TextSpan(text: t.fmtEta(rem), style: ts(22, w: FontWeight.w700, ls: -.2, color: m['route-text'])),
            TextSpan(text: ' (${t.fmtM(rem)})', style: ts(22, w: FontWeight.w500, ls: -.2, color: p.ink)),
          ])),
        ),
        const SizedBox(width: 10),
        if (pl.kind != 'conn') ...[
          RoundBtn('i-star', on: fav, label: fav ? sc.tr('Remove from favourites') : sc.tr('Add to favourites'), onTap: () => ref.read(favouritesProvider.notifier).toggle(sc.mallId, pl.id)),
          const SizedBox(width: 8),
        ],
        RoundBtn('i-up', label: sc.tr('All the steps'), onTap: () => context.push('/route')),
        const SizedBox(width: 8),
        RoundBtn('i-close', label: sc.tr('Close'), onTap: sc.nav.stop),
      ]),
      if (next != null) DirectionCard(i: next.$1, d: next.$2, progress: r.progress, transit: at.transit),
      // start, pause or resume: a pill you cannot miss (at the end the pop-up asks for "I've arrived" instead)
      if (s.prompt != 'end')
        btns([
          s.playing
              ? Btn(sc.tr('Pause'), primary: true, onTap: sc.nav.pause, semantics: sc.tr('Pause the walk'))
              : s.paused
                  ? Btn(sc.tr('Resume'), primary: true, onTap: sc.nav.resume, semantics: sc.tr('Resume the walk'))
                  : Btn(sc.tr('Start'), primary: true, onTap: sc.nav.start, semantics: sc.tr('Start the walk')),
        ], top: 8),
      if (status.key == 'closedNow') note(context, 'warn', Text(status.line)),
      if (s.helpNote) helpNote(context),
      // the shopper avoids stairs or escalators, but nothing else reaches the place
      if (s.needsNote != null)
        note(
          context,
          'warn',
          Text(s.needsNote == 'stairs' ? sc.tr('This way needs stairs: no lift or ramp reaches this floor.') : sc.tr('This way needs an escalator: nothing else reaches this floor.')),
        ),
      findAnotherWayRow(context),
    ]);
  }
}

Widget _nearBody(BuildContext context) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal, n = s.near!, t = sc.t;
  final cat = categoryById(n.type);
  final rows = <Widget>[
    for (var i = 0; i < n.ids.length; i++)
      if (s.placeById(n.ids[i]) case final pl?)
        RowX(
          onTap: () => sc.nav.startTo(pl.id),
          lead: CatTile(pl.cat),
          title: '${pl.name}${i == 0 ? ' · ${sc.tr('closest')}' : ''}',
          sub: [t.placeSub(pl), if (s.distOf(pl) case final d?) t.fmtM(d)].join(' · '),
          last: i == n.ids.length - 1,
        ),
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
    const Grab(),
    _ttl(
      Tile(nearGlyph(n.type), size: 48),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sc.tr('Nearest: ${sc.tr(cat.label)}'), style: ts(18, w: FontWeight.w700, color: p.ink)),
        Text(sc.tr('By walking distance from you'), style: ts(12.5, color: p.muted)),
      ]),
      trail: RoundBtn('i-close', label: sc.tr('Close'), onTap: sc.nav.clearNearest),
    ),
    if (!s.hasPosition) ...[
      iconNote(context, 'info', 'i-pin', sc.tr('Tell us where you are to see what is nearest.'), top: 2),
      btns([Btn(sc.tr('Where are you?'), primary: true, onTap: sc.nav.openLocation)], top: 8),
    ] else
      CardX(children: rows.isEmpty ? [RowX(title: sc.tr('None found'), last: true)] : rows),
  ]);
}

/// The map glyph of a "nearest" type.
String nearGlyph(String type) => switch (type) { 'shops' => 'g-other', 'lift' => 'g-lift', _ => glyphOf(type) };

/// The sheet swiped down to one line. A tap or a swipe up opens it again.
Widget sheetMini(BuildContext context) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal, r = s.route, t = sc.t, m = context.mapPal;
  final pl = s.place == null ? null : s.placeById(s.place!);
  final bold = ts(15, w: FontWeight.w700, color: p.ink), muted = ts(13.5, color: p.muted);
  Widget line(List<InlineSpan> spans, {String? icon, Color? iconColor}) => Row(children: [
        if (icon != null) ...[AppIcon(icon, size: 20, color: iconColor ?? p.brand2), const SizedBox(width: 8)],
        Expanded(child: Text.rich(TextSpan(children: spans), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        AppIcon('i-up', size: 20, color: p.muted),
      ]);
  final Widget body;
  if (s.locSheet) {
    body = line([TextSpan(text: sc.tr('Where are you?'), style: bold)], icon: 'i-pin');
  } else if (s.emergency) {
    final rem = r == null ? null : r.total - r.progress;
    body = line([
      TextSpan(text: sc.tr('Emergency'), style: bold.copyWith(color: p.danger)),
      if (rem != null) TextSpan(text: ' · ${sc.tr('${t.fmtM(rem)} to the exit')}', style: muted),
    ], icon: 'i-alert', iconColor: p.danger);
  } else if (s.reroute != null) {
    body = line([TextSpan(text: sc.tr('Choosing another way'), style: bold)], icon: 'i-detour');
  } else if (r != null && pl != null) {
    final rem = r.total - r.progress;
    body = s.arrived
        ? line([TextSpan(text: sc.tr('You have arrived at ${pl.name}'), style: bold)], icon: 'i-check', iconColor: p.open)
        : line([
            TextSpan(text: t.fmtEta(rem), style: bold.copyWith(color: m['route-text'])),
            TextSpan(text: ' (${t.fmtM(rem)})', style: bold.copyWith(fontWeight: FontWeight.w500)),
            TextSpan(text: ' · ${sc.tr('To ${pl.name}')}', style: muted),
          ]);
  } else if (s.near != null) {
    body = line([TextSpan(text: sc.tr('Nearest: ${sc.tr(categoryById(s.near!.type).label)}'), style: bold)]);
  } else if (pl != null) {
    final d = t.distTxt(pl);
    body = line([TextSpan(text: pl.name, style: bold), if (d.isNotEmpty) TextSpan(text: ' · $d', style: muted)]);
  } else {
    body = line([TextSpan(text: sc.tr('Details'), style: bold)]);
  }
  return Tap(
    onTap: sc.map.sheetUp,
    child: Semantics(
      button: true,
      label: sc.tr('Open the panel'),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Grab(), body]),
    ),
  );
}

/// The next direction: a big arrow, the landmark, the metres counting down (or, just off a lift,
/// escalator or stairs, what you should see, or a passing cue). The screen reader gets the full
/// sentence, without the metres, so it is not re-read at every step.
class DirectionCard extends StatelessWidget {
  const DirectionCard({super.key, required this.i, required this.d, required this.progress, this.transit});
  final int i;
  final Direction d;
  final double progress;
  final Edge? transit;

  @override
  Widget build(BuildContext context) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, tr = transit;
    // riding: the ride's own floor, not the next direction's
    final title = tr != null ? sc.tr('Riding the ${hopName[tr.ctype]![0]} to ${t.levelLow(s.ridingTo ?? d.to)}') : t.dirTitle(d);
    // under the title: a landing while riding, "Paused", the last cue, what to expect after a ride, or the metres
    final sub = tr != null
        ? (t.landingShown ?? '')
        : s.paused
            ? sc.tr('Paused · tap Resume to go on')
            : s.cueShown ?? t.afterRideLine ?? (s.almostThere ? '' : t.dirSub(d, progress));
    final tag = s.paused ? sc.tr('Paused') : s.almostThere ? sc.tr('Almost there') : null;
    final spoken = tr != null ? title : t.narrate(i).text;
    return Semantics(
      liveRegion: true,
      label: tag == null ? spoken : '$tag. $spoken',
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('direction-card'),
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: s.paused ? p.muted : p.brand, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AppIcon(tr != null ? 'g-${tr.ctype}' : d.glyph, size: 28, color: p.onBrand),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: ts(16, w: FontWeight.w700, color: p.ink)),
                if (sub.isNotEmpty) Text(sub, style: ts(13, color: p.muted)),
              ]),
            ),
            if (tag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: s.paused ? p.panel : p.brand,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: s.paused ? p.line : p.brand, width: p.lineW),
                ),
                child: Text(tag, style: ts(12, w: FontWeight.w700, color: s.paused ? p.ink : p.onBrand)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

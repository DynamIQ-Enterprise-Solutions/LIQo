// The map's bottom sheet (from the demo's sheet.dart): a place's card, the
// arrival, the nearest places of a kind, and the panels for "Where are you?",
// other ways and the evacuation. Walking a route has its own banner and bottom
// bar (nav_bar.dart); the full list of directions is its own page (/route).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/clock.dart';
import '../../../../core/engine/venue.dart';
import '../../../../core/theme.dart';
import '../../../../shared/widgets/common.dart';
import '../../../../shared/widgets/glyphs.dart';
import '../../../navigation/models/nav_state.dart';
import '../../../places/models/category.dart';
import '../../../places/services/place_info_catalog.dart';
import '../../../places/services/place_status.dart';
import '../../../saved/providers/saved_providers.dart';
import '../../../settings/providers/settings_provider.dart';
import 'location_panel.dart';
import 'map_scope.dart';
import 'reroute_panel.dart';

/// What the sheet shows, to tell when it changes (a new kind opens at its summary).
String? sheetKind(NavState s) {
  if (s.locSheet) return 'loc';
  if (s.emergency) return 'evac';
  if (s.reroute != null) return 'reroute';
  if (s.wcError != null) return 'wc';
  // a row of the list previewed is still the list
  if (s.near != null && (s.route == null || s.preview)) return 'near:${s.near!.type}';
  if (s.route != null) return 'route:${s.place}';
  if (s.place != null) return 'place:${s.place}';
  return null;
}

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
  // the list stays while one of its rows is previewed
  if (s.near != null && (r == null || s.preview)) return _nearBody(context);
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
  // walking the route: the banner and the bottom bar take over (nav_bar.dart)
  return null;
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
      // not open: the way is still given, the status chip above says why
      if (!status.isOpen && pl.kind != 'zone' && pl.kind != 'conn') note(context, 'warn', Text(sc.tr('You can still get directions.'))),
      btns([
        if (pl.kind != 'conn') Btn(sc.tr('Details'), onTap: () => context.push('/place/${sc.mallId}/${pl.id}')),
        // Google Maps' Directions: the bent-arrow sign
        Btn(sc.tr('Directions'), key: const ValueKey('card-directions'), icon: Icons.directions, primary: true, onTap: () => sc.nav.startTo(pl.id)),
      ]),
    ]);
  }
}

/// The nearest places of a kind. A tap draws a row's way and highlights its place while the list
/// stays to try others; the chosen row's Directions makes it the trip (owner decisions 2026-10-23).
Widget _nearBody(BuildContext context) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal, n = s.near!;
  final cat = categoryById(n.type);
  final rows = <Widget>[
    for (var i = 0; i < n.ids.length; i++)
      if (s.placeById(n.ids[i]) case final pl?) _NearRow(place: pl, closest: i == 0),
  ];
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
    const Grab(),
    _ttl(
      Tile(nearGlyph(n.type), size: 48),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sc.tr('Nearest: ${sc.tr(cat.label)}'), style: ts(18, w: FontWeight.w700, color: p.ink)),
        Text(s.hasPosition && rows.isNotEmpty ? sc.tr('Tap one to see the way there') : sc.tr('By walking distance from you'), style: ts(12.5, color: p.muted)),
      ]),
      trail: RoundBtn('i-close', label: sc.tr('Close'), onTap: sc.nav.clearNearest),
    ),
    if (!s.hasPosition) ...[
      iconNote(context, 'info', 'i-pin', sc.tr('Tell us where you are to see what is nearest.'), top: 2),
      btns([Btn(sc.tr('Where are you?'), primary: true, onTap: sc.nav.openLocation)], top: 8),
    ] else if (rows.isEmpty)
      CardX(children: [RowX(title: sc.tr('None found'), last: true)])
    else
      ...rows,
  ]);
}

/// A row of the nearest list. Its border is its status (green open, red closed, amber being
/// repaired, violet opening soon), with the status written under the name, so nothing crowds a
/// narrow phone. The chosen row is filled, shows the walk's minutes and carries Directions.
class _NearRow extends ConsumerWidget {
  const _NearRow({required this.place, required this.closest});
  final Place place;
  final bool closest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = MapScope.of(context), s = sc.s, t = sc.t, p = context.pal, pl = place;
    final status = placeStatus(pl, placeInfoFor(s.v, pl), ref.watch(clockProvider)(), t.w);
    final chosen = s.preview && s.place == pl.id, r = chosen ? s.route : null, colour = statusColour(p, status.key);
    final sub = [
      t.placeSub(pl),
      if (r != null) '${t.fmtEta(r.total)} · ${t.fmtM(r.total)}' else if (s.distOf(pl) case final d?) t.fmtM(d),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: chosen,
        child: Tap(
          key: ValueKey('near-${pl.id}'),
          onTap: () => sc.nav.previewNearest(pl.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: chosen ? p.soft : p.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colour, width: chosen ? 2.5 : 1.5),
            ),
            child: Row(children: [
              CatTile(pl.cat),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${pl.name}${closest ? ' · ${sc.tr('closest')}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w700, color: p.ink)),
                  Text(sub, style: ts(12.5, color: p.muted)),
                  Text(status.line, style: ts(12.5, w: FontWeight.w700, color: colour)),
                ]),
              ),
              if (chosen) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: sc.tr('Directions to ${pl.name}'),
                  excludeSemantics: true,
                  onTap: sc.nav.confirmPreview,
                  child: Tap(
                    key: ValueKey('near-go-${pl.id}'),
                    onTap: sc.nav.confirmPreview,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle, boxShadow: p.glow),
                      alignment: Alignment.center,
                      child: Icon(Icons.directions, size: 26, color: p.onBrand),
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

/// The map glyph of a "nearest" type.
String nearGlyph(String type) => switch (type) { 'shops' => 'g-other', 'lift' => 'g-lift', _ => glyphOf(type) };

/// The sheet swiped down to one line. A tap or a swipe up opens it again.
Widget sheetMini(BuildContext context) {
  final sc = MapScope.of(context), s = sc.s, p = context.pal, r = s.route, t = sc.t;
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
    body = line([TextSpan(text: sc.tr('Emergency'), style: bold.copyWith(color: p.danger))], icon: 'i-alert', iconColor: p.danger);
  } else if (s.reroute != null) {
    body = line([TextSpan(text: sc.tr('Choosing another way'), style: bold)], icon: 'i-detour');
  } else if (r != null && pl != null && !s.preview) {
    body = line([TextSpan(text: sc.tr('You have arrived at ${pl.name}'), style: bold)], icon: 'i-check', iconColor: p.open);
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

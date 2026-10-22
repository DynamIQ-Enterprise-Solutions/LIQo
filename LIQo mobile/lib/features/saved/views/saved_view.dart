// Saved (the board's Saved / Favorites): Places (starred), Routes (a destination
// and its route options) and History (every trip started: arrived or stopped).
// Everything from every mall in one list, each with its mall; opening one
// switches to that mall (owner decisions 2026-10-22).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/words.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../malls/data/registry.dart';
import '../../malls/providers/mall_provider.dart';
import '../../malls/providers/switch_mall.dart';
import '../../navigation/models/route_options.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../navigation/providers/route_options_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../models/saved_items.dart';
import '../providers/saved_providers.dart';

class SavedView extends ConsumerStatefulWidget {
  const SavedView({super.key, this.tab});

  /// places | routes | history
  final String? tab;
  @override
  ConsumerState<SavedView> createState() => _SavedViewState();
}

class _SavedViewState extends ConsumerState<SavedView> {
  late String _tab = const ['places', 'routes', 'history'].contains(widget.tab) ? widget.tab! : 'places';

  String _mallName(String id) => venueRegistry.any((e) => e.id == id) ? ref.read(venueProvider(id)).name : id;

  void _openPlace(String mallId, String placeId) => context.push('/place/$mallId/$placeId');

  void _goRoute(SavedRoute r) {
    switchMall(ref, r.mallId);
    ref.read(routeOptionsProvider.notifier).set(r.options);
    ref.read(settingsProvider.notifier).setWheelchair(r.wheelchair);
    ref.read(navProvider.notifier).startTo(r.placeId);
    context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider);
    final body = switch (_tab) {
      'routes' => _routes(context, w),
      'history' => _history(context, w),
      _ => _places(context, w),
    };
    return AppPage(
      title: w.tr('Saved'),
      back: false,
      children: [
        Seg<String>(
          key: const ValueKey('saved-tabs'),
          items: [('places', w.tr('Places')), ('routes', w.tr('Routes')), ('history', w.tr('History'))],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 14),
        ...body,
        if (body.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Text(_empty(w), textAlign: TextAlign.center, style: ts(14, color: p.muted))),
      ],
    );
  }

  String _empty(Words w) => switch (_tab) {
        'routes' => w.tr('No saved routes yet. Save one from Your route.'),
        'history' => w.tr('No trips yet. Trips you start appear here.'),
        _ => w.tr('No saved places yet. Tap the heart on a place to save it.'),
      };

  List<Widget> _places(BuildContext context, Words w) {
    final p = context.pal, favs = ref.watch(favouritesProvider);
    final rows = <Widget>[];
    for (final (i, f) in favs.indexed) {
      if (!venueRegistry.any((e) => e.id == f.mallId)) continue;
      final v = ref.watch(venueProvider(f.mallId)), place = v.placeById(f.placeId);
      if (place == null) continue;
      rows.add(_SavedRow(
        key: ValueKey('fav-${f.mallId}-${f.placeId}'),
        lead: InitialsTile(place.name, size: 44),
        title: place.name,
        sub: '${w.tr(v.levels[place.lv].name)} · ${v.name}',
        onTap: () => _openPlace(f.mallId, f.placeId),
        trail: IconButton(
          tooltip: w.tr('Remove from favourites'),
          onPressed: () => ref.read(favouritesProvider.notifier).toggle(f.mallId, f.placeId),
          icon: Icon(Icons.favorite, color: p.brand),
        ),
        last: i == favs.length - 1,
      ));
    }
    return rows.isEmpty ? const [] : [CardX(children: rows)];
  }

  List<Widget> _routes(BuildContext context, Words w) {
    final p = context.pal, routes = ref.watch(savedRoutesProvider);
    if (routes.isEmpty) return const [];
    String how(RouteOptions o, bool wheel) => [
          o.metric == 'shortest' ? w.tr('Shortest') : w.tr('Fastest'),
          if (o.avoidStairs) w.tr('No stairs'),
          if (o.avoidEscalators) w.tr('No escalators'),
          if (wheel) w.tr('Wheelchair route'),
        ].join(' · ');
    return [
      CardX(children: [
        for (final (i, r) in routes.indexed)
          _SavedRow(
            key: ValueKey('route-${r.id}'),
            lead: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.route, color: p.brand2),
            ),
            title: r.placeName,
            sub: '${_mallName(r.mallId)} · ${how(r.options, r.wheelchair)}',
            onTap: () => _goRoute(r),
            trail: IconButton(tooltip: w.tr('Remove this saved route'), onPressed: () => ref.read(savedRoutesProvider.notifier).remove(r.id), icon: Icon(Icons.bookmark, color: p.brand)),
            last: i == routes.length - 1,
          ),
      ]),
      const SizedBox(height: 8),
      Text(w.tr('A saved route starts from wherever you are when you open it.'), style: ts(13, color: p.muted)),
    ];
  }

  List<Widget> _history(BuildContext context, Words w) {
    final p = context.pal, trips = ref.watch(historyProvider);
    if (trips.isEmpty) return const [];
    final loc = MaterialLocalizations.of(context);
    // 12-hour clock (owner decision 2026-10-22)
    String fmt(DateTime d) => '${loc.formatShortMonthDay(d)}, ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
    return [
      CardX(children: [
        for (final (i, tr) in trips.indexed)
          _SavedRow(
            key: ValueKey('trip-${tr.id}'),
            lead: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.history, color: p.muted),
            ),
            title: tr.placeName,
            sub: '${_mallName(tr.mallId)} · ${fmt(tr.startedAt)}',
            onTap: () => _openPlace(tr.mallId, tr.placeId),
            trail: _OutcomeChip(outcome: tr.outcome, w: w),
            last: i == trips.length - 1,
          ),
      ]),
    ];
  }
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.outcome, required this.w});
  final TripOutcome outcome;
  final Words w;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (label, fg, bg) = switch (outcome) {
      TripOutcome.arrived => (w.tr('Arrived'), p.open, p.openBg),
      TripOutcome.stopped => (w.tr('Stopped'), p.muted, p.raised),
      TripOutcome.inProgress => (w.tr('In progress'), p.soon, p.soonBg),
    };
    return ChipX(label: label, fg: fg, bg: bg);
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({super.key, required this.lead, required this.title, required this.sub, required this.onTap, required this.trail, this.last = false});
  final Widget lead, trail;
  final String title, sub;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.line, width: p.lineW))),
        child: Row(children: [
          lead,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w700, color: p.ink)),
              Text(sub, style: ts(12.5, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 6),
          trail,
        ]),
      ),
    );
  }
}

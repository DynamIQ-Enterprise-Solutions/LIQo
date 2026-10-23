// Your Route (the board's Route Guidance): where to, every direction with the
// walk that leads to it, the other way, step-free, Save route, and I've arrived
// or End navigation (the demo's expanded sheet).
import 'package:flutter/material.dart' hide Step;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/engine/directions.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../malls/providers/mall_provider.dart';
import '../../places/models/category.dart';
import '../../saved/providers/saved_providers.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/route_options_provider.dart';

/// The Material icon for a direction (the map uses its line icons).
IconData directionIcon(Direction d) => switch (d.kind) {
      'turn' => switch (d.turn) {
          'left' => Icons.turn_left,
          'right' => Icons.turn_right,
          'slight-left' => Icons.turn_slight_left,
          'slight-right' => Icons.turn_slight_right,
          'sharp-left' => Icons.turn_sharp_left,
          _ => Icons.turn_sharp_right,
        },
      'hop' => iconOfCat(d.type ?? 'lift'),
      'enter' => Icons.door_front_door_outlined,
      'bridge' => Icons.directions_walk,
      'through' => Icons.storefront_outlined,
      'arrive' => Icons.flag_outlined,
      _ => Icons.straight,
    };

class RouteGuidanceView extends ConsumerWidget {
  const RouteGuidanceView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), s = ref.watch(navProvider), t = ref.watch(navTextProvider);
    final nav = ref.read(navProvider.notifier), r = s.route, mallId = ref.watch(mallProvider)!;
    final place = s.place == null ? null : s.placeById(s.place!);
    if (r == null || place == null || s.emergency) {
      return AppPage(title: w.tr('Your route'), children: [
        Text(w.tr('There is no route right now. Pick a place and press Directions.'), style: ts(15, color: p.muted)),
        const SizedBox(height: 16),
        PrimaryButton(label: w.tr('Back to the map'), onPressed: () => context.canPop() ? context.pop() : context.go('/map')),
      ]);
    }
    final dirs = s.directions, next = s.nextDirection, rem = r.total - r.progress;
    final options = ref.watch(routeOptionsProvider), wheel = ref.watch(settingsProvider.select((x) => x.wheelchair));
    final saved = ref.watch(savedRoutesProvider.notifier).find(mallId, place.id, options, wheel) != null;
    ref.watch(savedRoutesProvider);
    return AppPage(
      title: w.tr('Your route'),
      actions: [
        if (place.kind != 'conn')
          IconButton(
            key: const ValueKey('save-route'),
            tooltip: saved ? w.tr('Remove this saved route') : w.tr('Save this route'),
            onPressed: () => ref.read(savedRoutesProvider.notifier).toggle(mallId: mallId, placeId: place.id, placeName: place.name, options: options, wheelchair: wheel),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: saved ? p.brand : p.ink),
          ),
      ],
      bottom: s.arrived
          ? PrimaryButton(label: w.tr('Done'), onPressed: () {
              nav.stop();
              context.pop();
            })
          : Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('arrived'),
                  onPressed: nav.confirmArrived,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder(), side: BorderSide(color: p.line, width: p.lineW), foregroundColor: p.ink),
                  child: Text(w.tr("I've arrived"), textAlign: TextAlign.center, style: ts(15, w: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  key: const ValueKey('end-navigation'),
                  label: w.tr('End navigation'),
                  onPressed: () {
                    nav.stop();
                    context.pop();
                  },
                ),
              ),
            ]),
      children: [
        // where to
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(12)),
            child: Icon(iconOfCat(place.cat), color: p.brand2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(place.name, style: ts(17, w: FontWeight.w800, color: p.ink)),
              Text('${t.levelName(place.lv)} · ${t.fmtM(rem)} · ${t.fmtEta(rem)}', style: ts(13, color: p.muted)),
            ]),
          ),
        ]),
        if (s.arrived) note(context, 'ok', Text(w.tr('You have arrived at ${place.name}'))),
        const SizedBox(height: 14),
        _Step(icon: Icons.my_location, title: w.tr('Start where you are now'), sub: s.user == null ? null : t.levelName(s.user!.lv), done: true),
        for (var i = 0; i < dirs.length; i++)
          _Step(
            icon: directionIcon(dirs[i]),
            title: t.dirTitle(dirs[i]),
            sub: t.dirApproach(dirs[i]),
            current: next != null && i == next.$1 && !s.arrived,
            done: s.arrived || (next != null && i < next.$1),
          ),
        const SizedBox(height: 14),
        if (s.routes.length > 1) ...[
          Text(w.tr('Ways there'), style: ts(14, w: FontWeight.w800, color: p.ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < s.routes.length; i++)
              ChoiceChip(
                key: ValueKey('alt-$i'),
                label: Text(i == 0 ? w.tr('Best way (${t.fmtM(s.routes[i].total)})') : w.tr('Other way $i (${t.fmtM(s.routes[i].total)})')),
                selected: i == s.routeIdx,
                showCheckmark: false,
                onSelected: (_) => nav.chooseAlternative(i),
                selectedColor: p.soft,
                backgroundColor: p.panel,
                labelStyle: ts(13, w: FontWeight.w700, color: i == s.routeIdx ? p.brand2 : p.ink),
                side: BorderSide(color: i == s.routeIdx ? p.brand : p.line, width: p.lineW),
                shape: const StadiumBorder(),
              ),
          ]),
          const SizedBox(height: 6),
          Text(w.tr('The dashed blue line on the map is the other way.'), style: ts(13, color: p.muted)),
        ] else
          Text(w.tr('There is no other way to get there.'), style: ts(13, color: p.muted)),
        const SizedBox(height: 14),
        CardX(children: [
          RowX(
            title: w.tr('Wheelchair route (lifts only)'),
            trail: Sw(on: wheel, label: w.tr('Wheelchair route'), onChanged: ref.read(settingsProvider.notifier).setWheelchair),
          ),
          RowX(
            onTap: () => context.push('/route-options'),
            title: w.tr('Route options'),
            sub: options.metric == 'shortest' ? w.tr('Shortest') : w.tr('Fastest'),
            trail: Icon(Icons.chevron_right, color: p.muted),
            last: true,
          ),
        ]),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, this.sub, this.current = false, this.done = false});
  final IconData icon;
  final String title;
  final String? sub;
  final bool current, done;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Opacity(
      opacity: done && !current ? .55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: current ? p.brand : p.raised, shape: BoxShape.circle),
            child: Icon(icon, size: 20, color: current ? p.onBrand : p.brand2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (sub != null) Text(sub!, style: ts(12.5, color: p.muted)),
              Text(title, style: ts(14.5, w: current ? FontWeight.w800 : FontWeight.w600, color: p.ink)),
            ]),
          ),
        ]),
      ),
    );
  }
}

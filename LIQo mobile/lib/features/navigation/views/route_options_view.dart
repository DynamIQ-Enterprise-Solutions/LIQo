// Route options (the board's screen, without "crowded areas"): Fastest or
// Shortest, and avoid stairs / escalators. Saved as the defaults; applied to the
// trip in progress (owner decisions 2026-10-22).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/engine/routing.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../settings/providers/words_provider.dart';
import '../models/route_options.dart';
import '../providers/route_options_provider.dart';

class RouteOptionsView extends ConsumerStatefulWidget {
  const RouteOptionsView({super.key});
  @override
  ConsumerState<RouteOptionsView> createState() => _RouteOptionsViewState();
}

class _RouteOptionsViewState extends ConsumerState<RouteOptionsView> {
  late RouteOptions _o = ref.read(routeOptionsProvider);

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider);
    Widget metric(String key, String title, String sub, IconData icon) {
      final on = _o.metric == key;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Semantics(
          button: true,
          selected: on,
          label: '$title. $sub',
          excludeSemantics: true,
          onTap: () => setState(() => _o = _o.copyWith(metric: key)),
          child: InkWell(
            key: ValueKey('metric-$key'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _o = _o.copyWith(metric: key)),
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: on ? p.soft : p.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? p.brand : p.line, width: on ? 2 : p.lineW)),
              child: Row(children: [
                Icon(icon, color: on ? p.brand2 : p.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: ts(15.5, w: FontWeight.w800, color: p.ink)),
                    Text(sub, style: ts(13, color: p.muted)),
                  ]),
                ),
                Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: on ? p.brand : p.muted),
              ]),
            ),
          ),
        ),
      );
    }

    return AppPage(
      title: w.tr('Route options'),
      bottom: PrimaryButton(
        key: const ValueKey('apply'),
        label: w.tr('Apply'),
        onPressed: () {
          ref.read(routeOptionsProvider.notifier).set(_o);
          if (context.canPop()) context.pop();
        },
      ),
      children: [
        metric(RouteOpts.fastest, w.tr('Fastest'), w.tr('Recommended · the least time, waits for lifts and escalators included'), Icons.bolt),
        metric(RouteOpts.shortest, w.tr('Shortest'), w.tr('Less walking · rides on lifts and escalators hardly count'), Icons.straighten),
        SectionLabel(w.tr('Avoid')),
        CardX(children: [
          RowX(
            lead: Icon(Icons.stairs_outlined, color: p.brand2),
            title: w.tr('Stairs'),
            trail: Sw(key: const ValueKey('avoid-stairs'), on: _o.avoidStairs, label: w.tr('Avoid stairs'), onChanged: (v) => setState(() => _o = _o.copyWith(avoidStairs: v))),
          ),
          RowX(
            lead: Icon(Icons.escalator, color: p.brand2),
            title: w.tr('Escalators'),
            trail: Sw(key: const ValueKey('avoid-escalators'), on: _o.avoidEscalators, label: w.tr('Avoid escalators'), onChanged: (v) => setState(() => _o = _o.copyWith(avoidEscalators: v))),
            last: true,
          ),
        ]),
        const SizedBox(height: 10),
        Text(w.tr('Stairs and escalators are only used when nothing else reaches a place, and the route says so.'), style: ts(13, color: p.muted)),
      ],
    );
  }
}

// Help & Support: how-to tips only (owner decision 2026-10-22; no contact
// details yet).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/page.dart';
import '../providers/words_provider.dart';

class HelpView extends ConsumerWidget {
  const HelpView({super.key});

  static const tips = [
    (Icons.search, 'Find a place', 'Search for a store, a kind of place or a level, or open a category on Home. Each result shows whether it is open.'),
    (Icons.location_on_outlined, 'Say where you are', 'Until the mall has beacons, tell LIQo where you are: pick a shop near you, or your floor and then tap the map.'),
    (Icons.directions, 'Get directions', 'Open a place and press Directions (or the bent-arrow button on the map), then Start. The walk stops at each lift, escalator or stairs to check you are there.'),
    (Icons.alt_route, 'Find another way', 'While walking, Find another way shows ways around the stretch just ahead, places like the one you are going to, and the way to the information desk.'),
    (Icons.tune, 'Route options', 'Choose Fastest or Shortest, and avoid stairs or escalators. A wheelchair route uses lifts, ramps and wide corridors only.'),
    (Icons.emergency_outlined, 'Emergency evacuation', 'In More, Emergency evacuation shows the way to the nearest exit by stairs, never lifts. Wheelchair users are shown a safe place to wait for staff.'),
    (Icons.bookmark_border, 'Saved', 'Save places with the heart and routes from Your route. History keeps the trips you started.'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return AppPage(
      title: w.tr('Help & Support'),
      children: [
        for (final (icon, title, body) in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: p.brand2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.tr(title), style: ts(15.5, w: FontWeight.w800, color: p.ink)),
                  const SizedBox(height: 2),
                  Text(w.tr(body), style: ts(14, color: p.muted, height: 1.45)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

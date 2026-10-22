// Settings (the demo's Me tab, trimmed on 2026-10-22): language, look (system,
// light, dark; high contrast), text size, vibration, reduce motion, wheelchair
// routes and walking pace. Wording is always plain; cut-throughs are always on;
// stairs and escalators are in Route options.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../providers/settings_provider.dart';
import '../providers/words_provider.dart';

class SettingsView extends ConsumerWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), s = ref.watch(settingsProvider), n = ref.read(settingsProvider.notifier);
    Widget hint(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 6), child: Text(t, style: ts(12.5, color: p.muted)));
    Widget gap() => const SizedBox(height: 12);
    Widget toggle(String key, String title, bool on, ValueChanged<bool> set, {String? sub, bool last = false}) => RowX(
          title: title,
          sub: sub,
          trail: Sw(key: ValueKey(key), on: on, label: title, onChanged: set),
          last: last,
        );
    return AppPage(
      title: w.tr('Settings'),
      children: [
        SectionLabel(w.tr('Language'), padding: const EdgeInsets.only(top: 4, bottom: 8)),
        Seg<String>(key: const ValueKey('set-lang'), items: const [('en', 'English'), ('tl', 'Tagalog')], value: s.lang, onChanged: n.setLang),
        SectionLabel(w.tr('Text and display')),
        hint(w.tr('Look')),
        Seg<String>(key: const ValueKey('set-theme'), items: [('system', w.tr('Phone setting')), ('light', w.tr('Light')), ('dark', w.tr('Dark'))], value: s.theme, onChanged: n.setTheme),
        gap(),
        hint(w.tr('Text size')),
        Seg<double>(key: const ValueKey('set-textsize'), items: [(1.0, w.tr('Normal')), (1.2, w.tr('Larger')), (1.4, w.tr('Largest'))], value: s.textSize, onChanged: n.setTextSize),
        gap(),
        CardX(children: [
          toggle('set-contrast', w.tr('High contrast'), s.highContrast, n.setHighContrast, sub: w.tr('Black and white, with stronger lines')),
          toggle('set-motion', w.tr('Reduce motion'), s.reduceMotion, n.setReduceMotion, sub: w.tr('No confetti, no colour fades, a still map'), last: true),
        ]),
        SectionLabel(w.tr('Alerts')),
        CardX(children: [
          toggle('set-vibration', w.tr('Vibration'), s.vibration, n.setVibration, sub: w.tr('Before each turn, when you may be off the way, and on arrival'), last: true),
        ]),
        SectionLabel(w.tr('Getting around')),
        CardX(children: [
          toggle('set-wheelchair', w.tr('Wheelchair route'), s.wheelchair, n.setWheelchair, sub: w.tr('Lifts, ramps and wide corridors only')),
          RowX(
            onTap: () => context.push('/route-options'),
            title: w.tr('Route options'),
            sub: w.tr('Fastest or shortest; avoid stairs or escalators'),
            trail: Icon(Icons.chevron_right, color: p.muted),
            last: true,
          ),
        ]),
        gap(),
        hint(w.tr('Walking pace (the minutes shown and the walk on the map)')),
        Seg<String>(key: const ValueKey('set-pace'), items: [('slow', w.tr('Slow')), ('relaxed', w.tr('Relaxed')), ('normal', w.tr('Normal')), ('brisk', w.tr('Brisk')), ('fast', w.tr('Fast'))], value: s.pace, onChanged: n.setPace),
      ],
    );
  }
}

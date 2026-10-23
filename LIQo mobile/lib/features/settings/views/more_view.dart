// More (the board's Profile / Settings, without an account yet): sign in
// (optional, look-only for now), Settings, Emergency evacuation, Change mall,
// Help & Support and About LIQo (owner decisions 2026-10-22).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../navigation/providers/nav_provider.dart';
import '../providers/words_provider.dart';

class MoreView extends ConsumerWidget {
  const MoreView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    final emergency = ref.watch(navProvider.select((s) => s.emergency));
    Widget item(String key, IconData icon, String title, VoidCallback onTap, {String? sub, Color? color, bool last = false}) => InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.line, width: p.lineW))),
            child: Row(children: [
              Icon(icon, color: color ?? p.brand2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: ts(15, w: FontWeight.w700, color: color ?? p.ink)),
                  if (sub != null) Text(sub, style: ts(12.5, color: p.muted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: p.muted),
            ]),
          ),
        );
    return AppPage(
      title: w.tr('More'),
      back: false,
      children: [
        // sign in: optional, and not working yet (look-only)
        InkWell(
          key: const ValueKey('more-signin'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/login'),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: p.lineW), boxShadow: p.shadow),
            child: Row(children: [
              CircleAvatar(radius: 24, backgroundColor: p.soft, child: Icon(Icons.person_outline, color: p.brand2)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.tr('Sign in (optional)'), style: ts(16, w: FontWeight.w800, color: p.ink)),
                  Text(w.tr('LIQo works without an account.'), style: ts(12.5, color: p.muted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: p.muted),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        CardX(children: [
          item('more-settings', Icons.settings_outlined, w.tr('Settings'), () => context.push('/more/settings'), sub: w.tr('Language, look, text size, getting around')),
          item('more-mall', Icons.storefront_outlined, w.tr('Change mall'), () => context.push('/malls')),
          item('more-saved-malls', Icons.download_done_outlined, w.tr('Saved malls'), () => context.push('/more/malls'), sub: w.tr('Malls on this phone, updates, storage')),
          item('more-help', Icons.help_outline, w.tr('Help & Support'), () => context.push('/more/help')),
          item('more-about', Icons.info_outline, w.tr('About LIQo'), () => context.push('/more/about'), last: true),
        ]),
        const SizedBox(height: 16),
        CardX(children: [
          item(
            'more-emergency',
            Icons.emergency_outlined,
            emergency ? w.tr('Emergency evacuation is on') : w.tr('Emergency evacuation'),
            () {
              ref.read(navProvider.notifier).startEmergency();
              context.go('/map');
            },
            sub: w.tr('The way out by the nearest exit, stairs only'),
            color: p.danger,
            last: true,
          ),
        ]),
      ],
    );
  }
}

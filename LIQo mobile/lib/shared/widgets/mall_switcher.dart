// The mall dropdown in the header (the board's "Northpoint Mall ∨"), on Home
// and on the map. It lists the malls on the phone; 'More malls' opens the
// picker, where others download.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../features/malls/data/mall_info.dart';
import '../../features/malls/providers/mall_provider.dart';
import '../../features/malls/providers/malls_provider.dart';
import '../../features/malls/providers/switch_mall.dart';
import '../../features/settings/providers/words_provider.dart';

class MallSwitcher extends ConsumerWidget {
  const MallSwitcher({super.key, this.compact = false});

  /// A smaller pill (the map's header).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), venue = ref.watch(currentVenueProvider);
    final name = venue?.name ?? w.tr('Choose a mall');
    return Semantics(
      button: true,
      label: w.tr('Mall: $name. Change mall'),
      excludeSemantics: true,
      onTap: () => pickMall(context, ref),
      child: InkWell(
        key: const ValueKey('mall-switcher'),
        borderRadius: BorderRadius.circular(999),
        onTap: () => pickMall(context, ref),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: EdgeInsets.fromLTRB(compact ? 10 : 12, 4, 6, 4),
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: p.line, width: p.lineW),
            boxShadow: p.shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined, size: compact ? 16 : 18, color: p.brand),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(compact ? 13 : 14, w: FontWeight.w700, color: p.ink),
                ),
              ),
              Icon(Icons.expand_more, size: 20, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The malls on the phone in a bottom sheet; picking one switches to it, 'More malls' opens the picker.
Future<void> pickMall(BuildContext context, WidgetRef ref) async {
  final p = context.pal, w = ref.read(wordsProvider), current = ref.read(mallProvider), saved = ref.read(mallsProvider).venues;
  final id = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            w.tr('Choose a mall'),
            style: ts(18, w: FontWeight.w700, color: p.ink),
          ),
          const SizedBox(height: 8),
          for (final MapEntry(key: id, value: v) in saved.entries)
            ListTile(
              key: ValueKey('switch-$id'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(id == current ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: id == current ? p.brand : p.muted),
              title: Text(v.name, style: ts(15, w: FontWeight.w600, color: p.ink)),
              subtitle: Text(
                mallInfos[id]?.about.of(w.lang) ?? v.tagline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ts(12.5, color: p.muted),
              ),
              onTap: () => Navigator.of(context).pop(id),
            ),
          ListTile(
            key: const ValueKey('switch-more'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_location_alt_outlined, color: p.brand2),
            title: Text(w.tr('More malls'), style: ts(15, w: FontWeight.w700, color: p.brand2)),
            onTap: () => Navigator.of(context).pop(''),
          ),
        ],
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  if (id.isEmpty) {
    context.push('/malls');
  } else {
    switchMall(ref, id);
  }
}

// More › Saved malls: each mall on the phone with its size, when its map was
// last updated, and what is waiting for it (an update offered on mobile data,
// one ready to switch in after the trip, a newer format needing a new LIQo, or
// the mall no longer offered). Delete frees the map's storage; the shopper's
// saved places stay, greyed (owner decisions 2026-10-23).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../../shared/widgets/toast.dart';
import '../../settings/providers/words_provider.dart';
import '../models/saved_mall.dart';
import '../providers/mall_provider.dart';
import '../providers/malls_provider.dart';
import '../providers/switch_mall.dart';

class SavedMallsView extends ConsumerWidget {
  const SavedMallsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), s = ref.watch(mallsProvider);
    final malls = s.saved.values.toList();
    return AppPage(
      title: w.tr('Saved malls'),
      children: [
        Text(w.tr('These malls work without signal. Maps update by themselves on Wi-Fi.'), style: ts(14, color: p.muted)),
        const SizedBox(height: 14),
        if (malls.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(w.tr('No malls on this phone yet.'), textAlign: TextAlign.center, style: ts(14, color: p.muted)))
        else
          CardX(children: [for (final (i, m) in malls.indexed) _MallRow(mall: m, last: i == malls.length - 1, busy: s.downloading.contains(m.id))]),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const ValueKey('saved-malls-add'),
          onPressed: () => context.push('/malls'),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(w.tr('Add a mall')),
        ),
      ],
    );
  }
}

class _MallRow extends ConsumerStatefulWidget {
  const _MallRow({required this.mall, required this.last, required this.busy});
  final SavedMall mall;
  final bool last, busy;
  @override
  ConsumerState<_MallRow> createState() => _MallRowState();
}

class _MallRowState extends ConsumerState<_MallRow> {
  int? _size;

  @override
  void initState() {
    super.initState();
    ref.read(mallsProvider.notifier).sizeOf(widget.mall.id).then((n) {
      if (mounted) setState(() => _size = n);
    });
  }

  Future<void> _update() async {
    final r = await ref.read(mallsProvider.notifier).download(widget.mall.id, mobileOk: true);
    if (!mounted) return;
    final w = ref.read(wordsProvider);
    showToast(context, r == null ? w.tr('Map updated') : downloadFailureText(ref, r));
  }

  Future<void> _delete() async {
    final w = ref.read(wordsProvider), m = widget.mall;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(w.tr('Delete ${m.name}?')),
        content: Text(w.tr('Its map leaves this phone. Your saved places there stay, greyed, and work again when you download it.')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(w.tr('Cancel'))),
          FilledButton(key: const ValueKey('delete-yes'), onPressed: () => Navigator.of(context).pop(true), child: Text(w.tr('Delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (ref.read(mallProvider) == m.id) ref.read(mallProvider.notifier).clear();
    await ref.read(mallsProvider.notifier).delete(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), m = widget.mall, loc = MaterialLocalizations.of(context);
    final note = m.newerFormat
        ? (w.tr('Update LIQo to get this mall\'s new map.'), p.warn)
        : m.retired
            ? (w.tr('No longer updated by LIQo'), p.warn)
            : m.pending != null
                ? (w.tr('Map update ready: it switches in after your trip.'), p.muted)
                : null;
    final facts = [
      if (_size != null) formatSize(_size!),
      w.tr('Updated ${loc.formatShortDate(m.savedAt)}'),
    ].join(' · ');
    return Container(
      key: ValueKey('saved-mall-${m.id}'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(border: widget.last ? null : Border(bottom: BorderSide(color: p.line, width: p.lineW))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.storefront_outlined, color: p.brand2),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.name, style: ts(15, w: FontWeight.w700, color: p.ink)),
            if (m.mallName.isNotEmpty) Text(m.mallName, style: ts(12.5, color: p.muted)),
            Text(facts, style: ts(12.5, color: p.muted)),
            if (note != null) Text(note.$1, style: ts(12.5, w: FontWeight.w600, color: note.$2)),
            if (m.offered != null && !m.newerFormat)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.tonal(
                  key: ValueKey('saved-mall-update-${m.id}'),
                  onPressed: widget.busy ? null : _update,
                  child: Text(widget.busy ? w.tr('Downloading…') : w.tr('Update · ${formatSize(m.offered!.sizeBytes)}')),
                ),
              ),
          ]),
        ),
        IconButton(key: ValueKey('saved-mall-delete-${m.id}'), tooltip: w.tr('Delete'), onPressed: _delete, icon: Icon(Icons.delete_outline, color: p.muted)),
      ]),
    );
  }
}

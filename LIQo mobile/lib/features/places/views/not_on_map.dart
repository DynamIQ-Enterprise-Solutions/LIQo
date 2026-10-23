// Stores the live store info knows but the phone's map doesn't have yet (they
// moved into a unit added after this map was published): listed with "Directions
// come with the next map update" and an "Update now" that downloads the new map
// on any network (owner decision 2026-10-23).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/engine/package/live_info.dart';
import '../../../core/engine/package/package_venue.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../../shared/widgets/toast.dart';
import '../../malls/providers/malls_provider.dart';
import '../../malls/providers/switch_mall.dart';
import '../../settings/providers/words_provider.dart';

/// The stores of [mallId] not on its map yet that [keep] accepts.
List<LiveStore> storesNotOnMap(MallsState s, String mallId, bool Function(LiveStore) keep) {
  final v = s.venues[mallId];
  return v is PackageVenue ? [for (final st in v.storesNotOnMap) if (keep(st)) st] : const [];
}

/// Does a store belong to a category list (shops, food)?
bool storeInCategory(LiveStore st, String category) => switch (category) {
      'shops' => st.category != 'food',
      'food' => st.category == 'food',
      _ => false,
    };

class NotOnMapSection extends ConsumerWidget {
  const NotOnMapSection({super.key, required this.mallId, required this.stores});
  final String mallId;
  final List<LiveStore> stores;

  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final r = await ref.read(mallsProvider.notifier).download(mallId, mobileOk: true);
    if (!context.mounted) return;
    final w = ref.read(wordsProvider);
    showToast(context, r == null ? w.tr('Map updated') : downloadFailureText(ref, r));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stores.isEmpty) return const SizedBox.shrink();
    final p = context.pal, w = ref.watch(wordsProvider), busy = ref.watch(mallsProvider.select((s) => s.downloading.contains(mallId)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(w.tr('Not on the map yet')),
      CardX(children: [
        for (final (i, st) in stores.indexed)
          Container(
            key: ValueKey('not-on-map-${st.storeId}'),
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(border: i == stores.length - 1 ? null : Border(bottom: BorderSide(color: p.line, width: p.lineW))),
            child: Row(children: [
              Opacity(opacity: .6, child: InitialsTile(st.name, size: 40)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(st.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w700, color: p.ink)),
                  Text(w.tr('Directions come with the next map update'), style: ts(12.5, color: p.muted)),
                ]),
              ),
              TextButton(
                key: ValueKey('not-on-map-update-${st.storeId}'),
                onPressed: busy ? null : () => _update(context, ref),
                child: Text(busy ? w.tr('Downloading…') : w.tr('Update now')),
              ),
            ]),
          ),
      ]),
    ]);
  }
}

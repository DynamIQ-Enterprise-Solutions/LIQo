// The slim card at the top of Home for the current mall (owner decisions
// 2026-10-23): a map update waiting on mobile data ("Map update available ·
// 3 MB · Update"), which can be hidden for the day; or a newer map that needs a
// newer LIQo.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clock.dart';
import '../../../core/storage/keys.dart';
import '../../../core/storage/store.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/toast.dart';
import '../../settings/providers/words_provider.dart';
import '../providers/mall_provider.dart';
import '../providers/malls_provider.dart';
import '../providers/switch_mall.dart';

class MallUpdateCard extends ConsumerStatefulWidget {
  const MallUpdateCard({super.key});
  @override
  ConsumerState<MallUpdateCard> createState() => _MallUpdateCardState();
}

class _MallUpdateCardState extends ConsumerState<MallUpdateCard> {
  String _today() {
    final d = ref.read(clockProvider)();
    return '${d.year}-${d.month}-${d.day}';
  }

  bool _hiddenToday(String id) {
    final j = ref.read(storeProvider).json(Keys.updateCardHidden);
    return j is Map && j[id] == _today();
  }

  void _hide(String id) {
    final store = ref.read(storeProvider), j = store.json(Keys.updateCardHidden);
    store.setJson(Keys.updateCardHidden, {if (j is Map) ...j, id: _today()});
    setState(() {});
  }

  Future<void> _update(String id) async {
    final r = await ref.read(mallsProvider.notifier).download(id, mobileOk: true);
    if (!mounted) return;
    final w = ref.read(wordsProvider);
    showToast(context, r == null ? w.tr('Map updated') : downloadFailureText(ref, r));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), id = ref.watch(mallProvider), s = ref.watch(mallsProvider);
    final m = id == null ? null : s.saved[id];
    if (m == null || _hiddenToday(m.id)) return const SizedBox.shrink();
    final String text;
    Widget? action;
    if (m.newerFormat) {
      text = w.tr('A newer map of ${m.name} needs the latest LIQo. Update LIQo from your app store.');
    } else if (m.offered != null && m.pending == null) {
      final busy = s.downloading.contains(m.id);
      text = w.tr('Map update available · ${formatSize(m.offered!.sizeBytes)}');
      action = TextButton(key: const ValueKey('update-card-go'), onPressed: busy ? null : () => _update(m.id), child: Text(busy ? w.tr('Downloading…') : w.tr('Update')));
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        key: const ValueKey('update-card'),
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(color: p.soft, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line, width: p.lineW)),
        child: Row(children: [
          Icon(m.newerFormat ? Icons.system_update_outlined : Icons.map_outlined, color: p.brand2, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: ts(13.5, w: FontWeight.w600, color: p.ink))),
          ?action,
          IconButton(key: const ValueKey('update-card-hide'), tooltip: w.tr('Hide for today'), onPressed: () => _hide(m.id), icon: Icon(Icons.close, size: 18, color: p.muted)),
        ]),
      ),
    );
  }
}

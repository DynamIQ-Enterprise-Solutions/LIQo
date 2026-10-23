// "Choose a mall": on the first launch, and from More › Change mall. The LIQo
// directory's branches, grouped by their mall (owner decision 2026-10-23); a
// branch on the phone has a live thumbnail drawn by the map painter and opens at
// once, any other downloads first. With no directory yet and no connection it is
// the "Connect once" screen, which tries again by itself.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/data/shopper_api.dart';
import '../../../core/engine/venue.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../map/models/cam.dart';
import '../../map/services/map_painter.dart';
import '../../settings/providers/words_provider.dart';
import '../data/mall_info.dart';
import '../models/saved_mall.dart';
import '../providers/mall_provider.dart';
import '../providers/malls_provider.dart';
import '../providers/switch_mall.dart';

/// A row of the picker: a branch from the directory, or a saved one the directory no longer lists.
class _Item {
  const _Item(this.id, this.name, this.mallName, this.address, this.size, {this.retired = false});
  final String id, name, mallName, address;
  final int size;
  final bool retired;
}

class MallPickerView extends ConsumerStatefulWidget {
  const MallPickerView({super.key});

  /// How often the "Connect once" screen tries again by itself.
  static const retryEvery = Duration(seconds: 10);

  @override
  ConsumerState<MallPickerView> createState() => _MallPickerViewState();
}

class _MallPickerViewState extends ConsumerState<MallPickerView> {
  final _q = TextEditingController();
  Timer? _retry;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _retry = Timer.periodic(MallPickerView.retryEvery, (_) {
      final s = ref.read(mallsProvider);
      if (s.directory == null && mounted) _check();
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    await ref.read(mallsProvider.notifier).checkForUpdates();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _open(String id) async {
    if (!await openMall(context, ref, id) || !mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  List<_Item> _items(MallsState s) {
    final out = <_Item>[];
    final seen = <String>{};
    for (final b in s.directory?.branches ?? const <BranchEntry>[]) {
      if (!b.offered) continue;
      seen.add(b.id);
      out.add(_Item(b.id, b.name, b.mallName, b.address, b.package!.sizeBytes));
    }
    for (final m in s.saved.values) {
      if (seen.contains(m.id)) continue;
      out.add(_Item(m.id, m.name, m.mallName, '', m.package.sizeBytes, retired: s.directory != null));
    }
    return out;
  }

  /// Every word typed must appear in the branch's name, its mall, its address or its description.
  bool _matches(_Item it, Venue? v, String lang) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = '${it.name} ${it.mallName} ${it.address} ${mallInfos[it.id]?.about.of(lang) ?? ''} ${v?.keywords ?? ''} ${v == null ? '' : '${v.levelCount} levels ${v.sizeText}'}'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), current = ref.watch(mallProvider), s = ref.watch(mallsProvider);
    final all = _items(s);
    if (all.isEmpty && s.directory == null) return _ConnectOnce(checking: _checking, onRetry: _check);
    final shown = [for (final it in all) if (_matches(it, s.venues[it.id], w.lang)) it];
    final groups = <String, List<_Item>>{};
    for (final it in shown) {
      groups.putIfAbsent(it.mallName, () => []).add(it);
    }
    for (final g in groups.values) {
      g.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    final mallNames = groups.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(children: [
              if (context.canPop()) IconButton(tooltip: w.tr('Back'), onPressed: () => context.pop(), icon: Icon(Icons.arrow_back, color: p.ink)),
              const BrandWordmark(size: 24),
            ]),
            const SizedBox(height: 14),
            Semantics(header: true, child: Text(w.tr('Choose a mall'), style: ts(26, w: FontWeight.w800, ls: -.3, height: 1.2, color: p.ink))),
            const SizedBox(height: 6),
            Text(w.tr('Pick your mall. It downloads once, then works without signal.'), style: ts(13.5, color: p.muted)),
            if (s.offline && s.directory != null) ...[
              const SizedBox(height: 6),
              Text(w.tr('Offline: showing the malls from your last connection.'), key: const ValueKey('picker-offline'), style: ts(12.5, w: FontWeight.w600, color: p.muted)),
            ],
            const SizedBox(height: 14),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line, width: p.lineW), boxShadow: p.shadow),
              child: Row(children: [
                Icon(Icons.search, color: p.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('mall-search'),
                    controller: _q,
                    onChanged: (_) => setState(() {}),
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.search,
                    style: ts(15, color: p.ink),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: w.tr('Search malls by name or place'),
                      hintStyle: ts(15, color: p.muted),
                      hintMaxLines: 1,
                    ),
                  ),
                ),
                if (_q.text.isNotEmpty) IconButton(tooltip: w.tr('Clear the search'), onPressed: () => setState(_q.clear), icon: Icon(Icons.close, color: p.muted)),
              ]),
            ),
            const SizedBox(height: 6),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  _q.text.trim().isEmpty ? w.tr('No malls are on LIQo yet.') : w.tr('No mall matches "${_q.text.trim()}".'),
                  style: ts(14, color: p.muted),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final name in mallNames) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Semantics(header: true, child: Text(name.toUpperCase(), style: ts(12, w: FontWeight.w800, ls: .8, color: p.muted))),
              ),
              for (final it in groups[name]!) ...[
                _MallCard(
                  item: it,
                  venue: s.venues[it.id],
                  saved: s.saved[it.id],
                  current: it.id == current,
                  downloading: s.downloading.contains(it.id),
                  onOpen: () => _open(it.id),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// No mall on the phone and no connection yet.
class _ConnectOnce extends ConsumerWidget {
  const _ConnectOnce({required this.checking, required this.onRetry});
  final bool checking;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return Scaffold(
      key: const ValueKey('connect-once'),
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.wifi_off_rounded, size: 56, color: p.brand2),
              const SizedBox(height: 16),
              Semantics(header: true, child: Text(w.tr('Connect once to download your mall'), textAlign: TextAlign.center, style: ts(22, w: FontWeight.w800, color: p.ink, height: 1.25))),
              const SizedBox(height: 8),
              Text(
                w.tr('LIQo needs the internet once to download a mall\'s map. After that, directions work without signal.'),
                textAlign: TextAlign.center,
                style: ts(14.5, color: p.muted),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('connect-retry'),
                onPressed: checking ? null : onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(checking ? w.tr('Trying…') : w.tr('Try again')),
              ),
              const SizedBox(height: 8),
              Text(w.tr('It also tries again by itself.'), style: ts(12.5, color: p.muted)),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
                TextButton(onPressed: () => context.push('/more/settings'), child: Text(w.tr('Settings'))),
                TextButton(onPressed: () => context.push('/more/help'), child: Text(w.tr('Help & Support'))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MallCard extends ConsumerWidget {
  const _MallCard({required this.item, required this.venue, required this.saved, required this.current, required this.downloading, required this.onOpen});
  final _Item item;
  final Venue? venue;
  final SavedMall? saved;
  final bool current, downloading;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), v = venue;
    Widget chip(String t, {Key? key, Color? fg}) => Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(999)),
          child: Text(t, style: ts(12, w: FontWeight.w600, color: fg ?? p.muted)),
        );
    final String action = downloading
        ? w.tr('Downloading…')
        : v == null
            ? w.tr('Download')
            : current
                ? w.tr('Current')
                : w.tr('Open');
    final about = mallInfos[item.id]?.about.of(w.lang) ?? item.address;
    return Semantics(
      button: true,
      label: '${item.name}, $action',
      excludeSemantics: true,
      onTap: downloading ? null : onOpen,
      child: InkWell(
        key: ValueKey('mall-${item.id}'),
        onTap: downloading ? null : onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(color: p.panel, border: Border.all(color: current ? p.brand : p.line, width: current ? 2 : p.lineW), borderRadius: BorderRadius.circular(16), boxShadow: p.shadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (v != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: Container(
                  height: 170,
                  color: context.mapPal['ground'],
                  child: LayoutBuilder(builder: (context, c) => CustomPaint(painter: MapPainter.preview(v, context.mapPal, w, _fit(v, c.biggest)), size: c.biggest)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(item.name, style: ts(18, w: FontWeight.w700, color: p.ink))),
                  const SizedBox(width: 8),
                  Flexible(child: Text(action, textAlign: TextAlign.end, style: ts(14, w: FontWeight.w700, color: p.brand2))),
                  Icon(v == null && !downloading ? Icons.download_rounded : Icons.chevron_right, color: p.brand2),
                ]),
                if (about.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(about, style: ts(13, color: p.muted)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (v != null) ...[
                    chip(w.tr('On this phone'), key: const ValueKey('chip-saved')),
                    chip(w.tr('${v.levelCount} levels')),
                    chip(v.sizeText),
                  ] else
                    chip(formatSize(item.size)),
                  if (item.retired || (saved?.retired ?? false)) chip(w.tr('No longer updated by LIQo'), fg: p.warn),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// A camera that fits the whole site into the thumbnail.
  static Cam _fit(Venue v, Size size) {
    final sv = v.siteView, r = v.siteRect;
    final ext = (r[2] - r[0], r[3] - r[1], (r[0] + r[2]) / 2, (r[1] + r[3]) / 2);
    final f = math.min(size.width * .92 / (ext.$1 * v.basePx * sv.zoom), size.height * .9 / (ext.$2 * v.basePx * sv.zoom * .82));
    return Cam()
      ..cx = ext.$3
      ..cy = ext.$4
      ..zoom = sv.zoom * f;
  }
}

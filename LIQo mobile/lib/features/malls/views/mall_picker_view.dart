// "Choose a mall": on the first launch, and from More › Change mall. Each card
// has a live thumbnail of the site, drawn by the map painter itself (from the
// demo's picker_screen).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/engine/venue.dart';
import '../../../core/i18n/words.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../map/models/cam.dart';
import '../../map/services/map_painter.dart';
import '../../settings/providers/words_provider.dart';
import '../data/mall_info.dart';
import '../data/registry.dart';
import '../providers/mall_provider.dart';
import '../providers/switch_mall.dart';

class MallPickerView extends ConsumerStatefulWidget {
  const MallPickerView({super.key});
  @override
  ConsumerState<MallPickerView> createState() => _MallPickerViewState();
}

class _MallPickerViewState extends ConsumerState<MallPickerView> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// Every word typed must appear in the mall's name, description or keywords.
  bool _matches(Venue v, Words w) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = '${v.name} ${v.tagline} ${mallInfos[v.id]?.about.of(w.lang) ?? ''} ${v.keywords} ${v.levelCount} levels ${v.sizeText}'.toLowerCase();
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }

  void _open(String id) {
    switchMall(ref, id);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), current = ref.watch(mallProvider);
    final shown = [for (final e in venueRegistry) if (_matches(ref.watch(venueProvider(e.id)), w)) e];
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
            Text(w.tr('Three sample malls to find your way around, until your mall is on LIQo.'), style: ts(13.5, color: p.muted)),
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
                      hintText: w.tr('Search malls, e.g. "tower", "bridge"'),
                      hintStyle: ts(15, color: p.muted),
                      hintMaxLines: 1,
                    ),
                  ),
                ),
                if (_q.text.isNotEmpty) IconButton(tooltip: w.tr('Clear the search'), onPressed: () => setState(_q.clear), icon: Icon(Icons.close, color: p.muted)),
              ]),
            ),
            const SizedBox(height: 14),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(w.tr('No mall matches "${_q.text.trim()}".'), style: ts(14, color: p.muted), textAlign: TextAlign.center),
              ),
            for (final e in shown) ...[
              _MallCard(venue: ref.watch(venueProvider(e.id)), current: e.id == current, onOpen: () => _open(e.id)),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _MallCard extends ConsumerWidget {
  const _MallCard({required this.venue, required this.current, required this.onOpen});
  final Venue venue;
  final bool current;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider), v = venue;
    final stores = v.places.where((x) => x.kind == 'store' || x.kind == 'box').length;
    Widget chip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(999)),
          child: Text(t, style: ts(12, w: FontWeight.w600, color: p.muted)),
        );
    return Semantics(
      button: true,
      label: v.name,
      child: InkWell(
        key: ValueKey('mall-${v.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(color: p.panel, border: Border.all(color: current ? p.brand : p.line, width: current ? 2 : p.lineW), borderRadius: BorderRadius.circular(16), boxShadow: p.shadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                  Expanded(child: Text(v.name, style: ts(18, w: FontWeight.w700, color: p.ink))),
                  Text(current ? w.tr('Current') : w.tr('Open'), style: ts(14, w: FontWeight.w700, color: p.brand2)),
                  Icon(Icons.chevron_right, color: p.brand2),
                ]),
                const SizedBox(height: 2),
                Text(mallInfos[v.id]?.about.of(w.lang) ?? v.tagline, style: ts(13, color: p.muted)),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  chip(w.tr('${v.buildingCount} ${v.buildingCount == 1 ? 'building' : 'buildings'}')),
                  chip(w.tr('${v.levelCount} levels')),
                  chip(w.tr('$stores shops')),
                  chip(v.sizeText),
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

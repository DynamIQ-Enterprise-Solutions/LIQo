// A place's page (the board's Place Details): a drawn picture, the name, how far,
// the level and kind, whether it is open, Get Directions, Call / Website / Share,
// and About. For the offline malls the details are made-up samples, and the page
// says so.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/page.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../malls/providers/mall_provider.dart';
import '../../malls/providers/switch_mall.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../saved/providers/saved_providers.dart';
import '../../search/providers/search_providers.dart';
import '../../settings/providers/words_provider.dart';
import '../services/place_actions.dart';
import '../services/place_info_catalog.dart';
import '../services/place_status.dart';
import 'place_list_view.dart' show catLabels;

class PlaceDetailsView extends ConsumerStatefulWidget {
  const PlaceDetailsView({super.key, required this.mallId, required this.placeId});
  final String mallId, placeId;
  @override
  ConsumerState<PlaceDetailsView> createState() => _PlaceDetailsViewState();
}

class _PlaceDetailsViewState extends ConsumerState<PlaceDetailsView> {
  final _shareKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // opening a place counts as a visit ("Most visited")
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.placeId.startsWith('CONN:')) ref.read(visitsProvider(widget.mallId).notifier).visit(widget.placeId);
    });
  }

  void _directions() {
    switchMall(ref, widget.mallId);
    ref.read(navProvider.notifier).startTo(widget.placeId);
    context.go('/map');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), venue = ref.watch(venueProvider(widget.mallId));
    final sameMall = ref.watch(mallProvider) == widget.mallId;
    final s = sameMall ? ref.watch(navProvider) : null, t = sameMall ? ref.watch(navTextProvider) : null;
    final place = s?.placeById(widget.placeId) ?? venue.placeById(widget.placeId);
    if (place == null) return AppPage(title: w.tr('Place'), children: [Text(w.tr('This place is no longer on the map.'), style: ts(15, color: p.muted))]);
    final info = placeInfoFor(venue, place), status = placeStatus(place, info, ref.watch(clockProvider)(), w);
    final fav = ref.watch(favouritesProvider).any((f) => f.mallId == widget.mallId && f.placeId == place.id);
    final d = s?.distOf(place), level = w.tr(venue.levels[place.lv].name);
    final actions = ref.read(placeActionsProvider);
    final hasStatus = place.kind != 'zone' && place.kind != 'conn';
    return Scaffold(
      backgroundColor: p.bg,
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              DrawnArt(motif: info.art.motif, tone: info.art.tone, seed: info.art.seed, semanticLabel: w.tr('A drawing of ${place.name}')),
              Positioned(left: 12, top: MediaQuery.paddingOf(context).top + 8, child: BackBtn(label: w.tr('Back'), onDark: true)),
              if (place.kind != 'conn')
                Positioned(
                  right: 12,
                  top: MediaQuery.paddingOf(context).top + 8,
                  child: Semantics(
                    button: true,
                    label: fav ? w.tr('Remove from favourites') : w.tr('Add to favourites'),
                    excludeSemantics: true,
                    onTap: () => ref.read(favouritesProvider.notifier).toggle(widget.mallId, place.id),
                    child: Material(
                      color: p.panel.withValues(alpha: .92),
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const ValueKey('fav'),
                        customBorder: const CircleBorder(),
                        onTap: () => ref.read(favouritesProvider.notifier).toggle(widget.mallId, place.id),
                        child: Padding(padding: const EdgeInsets.all(8), child: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? p.brand : p.ink)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
          sliver: SliverList.list(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Semantics(header: true, child: Text(place.name, style: ts(24, w: FontWeight.w800, color: p.ink, height: 1.2)))),
              if (d != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.location_on_outlined, size: 18, color: p.brand),
                Text(t!.fmtM(d), style: ts(14, w: FontWeight.w700, color: p.ink)),
              ],
            ]),
            const SizedBox(height: 4),
            Text('$level · ${w.tr(catLabels[place.cat] ?? place.cat)} · ${venue.name}', style: ts(14, color: p.muted)),
            if (hasStatus) ...[
              const SizedBox(height: 6),
              Text(status.line, key: const ValueKey('status-line'), style: ts(14, w: FontWeight.w700, color: status.isOpen ? p.open : p.closed)),
            ],
            if (status.key == 'closedNow')
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(w.tr('You can still get directions.'), style: ts(13, color: p.muted))),
            const SizedBox(height: 16),
            PrimaryButton(key: const ValueKey('get-directions'), label: w.tr('Get directions'), icon: Icons.directions_walk, onPressed: status.blocksRouting ? null : _directions),
            if (status.blocksRouting) Padding(padding: const EdgeInsets.only(top: 6), child: Text(w.tr('Not open, so you cannot go here yet.'), style: ts(13, color: p.closed))),
            if (info.phone != null || info.website != null) ...[
              const SizedBox(height: 16),
              Row(children: [
                if (info.phone != null) Expanded(child: _ActionBtn(key: const ValueKey('call'), icon: Icons.call_outlined, label: w.tr('Call'), onTap: () => actions.call(info.phone!))),
                if (info.website != null) Expanded(child: _ActionBtn(key: const ValueKey('website'), icon: Icons.language, label: w.tr('Website'), onTap: () => actions.openWebsite(info.website!))),
                Expanded(
                  child: _ActionBtn(
                    key: _shareKey,
                    icon: Icons.ios_share,
                    label: w.tr('Share'),
                    onTap: () {
                      final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
                      final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
                      actions.share(shareText(place.name, venue.levels[place.lv].name, venue.name), origin: origin);
                    },
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            Text(w.tr('About'), style: ts(17, w: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 6),
            Text(info.about.of(w.lang), style: ts(15, color: p.ink, height: 1.5)),
            if (info.phone != null || info.website != null) ...[
              const SizedBox(height: 10),
              if (info.phone != null) Text('${w.tr('Phone')}: ${info.phone}', style: ts(13, color: p.muted)),
              if (info.website != null) Text('${w.tr('Website')}: ${info.website}', style: ts(13, color: p.muted)),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(w.tr('Sample details: the hours, phone and website are made up until the mall adds its own.'), style: ts(13, color: p.muted))),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: p.panel, shape: BoxShape.circle, border: Border.all(color: p.line, width: p.lineW)),
              child: Icon(icon, color: p.brand2),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w600, color: p.ink)),
          ]),
        ),
      ),
    );
  }
}

// A category's places (the board's Store list): filter pills, then one row per
// place with its initials tile, kind and level, distance (once the shopper has
// said where they are) and whether it is open. A row opens the place's page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/engine/venue.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../../shared/widgets/placeholders.dart';
import '../../malls/providers/mall_provider.dart';
import '../../malls/providers/malls_provider.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../settings/providers/words_provider.dart';
import '../models/category.dart';
import '../services/place_info_catalog.dart';
import '../services/place_status.dart';
import 'not_on_map.dart';

/// The words for a place's kind ("Fashion", "Food", "Cinema").
const catLabels = {
  'fashion': 'Fashion',
  'food': 'Food',
  'tech': 'Gadgets and tech',
  'books': 'Books and gifts',
  'services': 'Services',
  'other': 'Other shops',
  'cinema': 'Cinema',
  'arena': 'Arena',
  'garden': 'Garden',
  'restroom': 'Restrooms',
  'atm': 'ATM',
  'info': 'Information desk',
  'exit': 'Entrance',
  'parking': 'Parking',
  'ev': 'EV charging',
  'lift': 'Lift',
  'escalator': 'Escalator',
  'stairs': 'Stairs',
  'ramp': 'Ramp',
};

class PlaceListView extends ConsumerStatefulWidget {
  const PlaceListView({super.key, required this.category});
  final String category;
  @override
  ConsumerState<PlaceListView> createState() => _PlaceListViewState();
}

class _PlaceListViewState extends ConsumerState<PlaceListView> {
  String _filter = 'all';
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), s = ref.watch(navProvider), t = ref.watch(navTextProvider);
    final mallId = ref.watch(mallProvider)!, now = ref.watch(clockProvider)();
    final cat = categoryById(widget.category);
    final all = s.byDistance(cat.placesIn(s));
    // the pills: the kinds of place in this category (Shops: fashion, tech, cinema...)
    final kinds = <String>{for (final x in all) x.cat}.toList();
    final pills = kinds.length > 1 ? ['all', ...kinds] : const <String>[];
    // the search: every word typed must appear in the place's name, kind, level or wing
    final q = _q.text.trim();
    final shown = all.where((x) => (_filter == 'all' || x.cat == _filter) && s.matches(x, q)).toList();
    // stores the map doesn't have yet (they come with the next map update)
    bool hit(String text) => q.isEmpty || q.toLowerCase().split(RegExp(r'\s+')).every(text.toLowerCase().contains);
    final later = storesNotOnMap(ref.watch(mallsProvider), mallId, (st) => storeInCategory(st, widget.category) && (_filter == 'all' || st.category == _filter) && hit(st.name));
    return AppPage(
      title: w.tr(cat.label),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line, width: p.lineW)),
            child: Row(children: [
              Icon(Icons.search, color: p.muted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('list-search'),
                  controller: _q,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  style: ts(15, color: p.ink),
                  decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: w.tr('Search this list'), hintStyle: ts(15, color: p.muted), hintMaxLines: 1),
                ),
              ),
              if (_q.text.isNotEmpty)
                IconButton(tooltip: w.tr('Clear the search'), visualDensity: VisualDensity.compact, onPressed: () => setState(_q.clear), icon: Icon(Icons.close, color: p.muted)),
            ]),
          ),
        ),
        if (pills.isNotEmpty)
          SizedBox(
            height: 46,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  for (final k in pills)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('pill-$k'),
                        label: Text(k == 'all' ? w.tr('All') : w.tr(catLabels[k] ?? k)),
                        selected: _filter == k,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _filter = k),
                        selectedColor: p.brand,
                        backgroundColor: p.panel,
                        labelStyle: ts(13, w: FontWeight.w700, color: _filter == k ? p.onBrand : p.ink),
                        side: BorderSide(color: _filter == k ? p.brand : p.line, width: p.lineW),
                        shape: const StadiumBorder(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (!s.hasPosition)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(w.tr('Tell us where you are on the map to see how far each place is.'), style: ts(13, color: p.muted)),
          ),
        if (shown.isEmpty)
          CardX(children: [RowX(title: q.isEmpty ? w.tr('Nothing here yet') : w.tr('Nothing found'), last: true)])
        else
          CardX(
            children: [
              for (var i = 0; i < shown.length; i++)
                _PlaceRow(
                  place: shown[i],
                  last: i == shown.length - 1,
                  onTap: () => context.push('/place/$mallId/${shown[i].id}'),
                  status: placeStatus(shown[i], placeInfoFor(s.v, shown[i]), now, w),
                  sub: _sub(shown[i], t.levelName(shown[i].lv), s.distOf(shown[i]), t.fmtM, w.tr),
                ),
            ],
          ),
        NotOnMapSection(mallId: mallId, stores: later),
      ],
    );
  }

  String _sub(Place x, String level, double? d, String Function(double) fmtM, String Function(String) tr) => [tr(catLabels[x.cat] ?? x.cat), level, if (d != null) fmtM(d)].join(' · ');
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.last, required this.onTap, required this.status, required this.sub});
  final Place place;
  final bool last;
  final VoidCallback onTap;
  final PlaceStatus status;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final showStatus = place.kind != 'zone' && place.kind != 'conn';
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('row-${place.id}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(
                    bottom: BorderSide(color: p.line, width: p.lineW),
                  ),
          ),
          child: Row(
            children: [
              InitialsTile(place.name, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(15, w: FontWeight.w700, color: p.ink),
                    ),
                    Text(sub, style: ts(12.5, color: p.muted)),
                    if (showStatus && status.known)
                      Text(
                        status.line,
                        style: ts(12.5, w: FontWeight.w600, color: statusColour(p, status.key)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

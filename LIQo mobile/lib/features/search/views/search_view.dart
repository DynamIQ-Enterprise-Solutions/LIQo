// Search (the board's Search screen): type a store, a kind of place or a level.
// Before typing: Recent Searches (places picked here) and Most visited (on this
// phone); the popular places across all shoppers wait for the backend (owner
// decision 2026-10-22). Every result shows whether it is open.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clock.dart';
import '../../../core/engine/venue.dart';
import '../../../core/i18n/words.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/page.dart';
import '../../malls/providers/mall_provider.dart';
import '../../navigation/models/nav_state.dart';
import '../../navigation/providers/nav_provider.dart';
import '../../navigation/services/nav_text.dart';
import '../../places/models/category.dart';
import '../../places/services/place_info_catalog.dart';
import '../../places/services/place_status.dart';
import '../../places/views/place_list_view.dart' show catLabels;
import '../../settings/providers/words_provider.dart';
import '../providers/search_providers.dart';

class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});
  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _q = TextEditingController();
  String _filter = 'all';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _open(String mallId, Place place) {
    ref.read(recentsProvider(mallId).notifier).add(place.id);
    context.push('/place/$mallId/${place.id}');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider), s = ref.watch(navProvider), t = ref.watch(navTextProvider);
    final mallId = ref.watch(mallProvider)!, now = ref.watch(clockProvider)();
    final q = _q.text.trim();
    bool inFilter(Place x) => _filter == 'all' || categoryById(_filter).has(x);
    final rows = <Widget>[];
    Widget row(Place x, {IconData? lead, bool last = false}) => _ResultRow(place: x, s: s, t: t, w: w, now: now, lead: lead, last: last, onTap: () => _open(mallId, x));
    if (q.isEmpty) {
      final recent = [for (final id in ref.watch(recentsProvider(mallId))) ?s.placeById(id)].where(inFilter).toList();
      ref.watch(visitsProvider(mallId));
      final visited = [for (final id in ref.read(visitsProvider(mallId).notifier).top(5)) ?s.placeById(id)].where(inFilter).toList();
      if (recent.isNotEmpty) {
        rows
          ..add(SectionLabel(w.tr('Recent searches')))
          ..add(
            CardX(
              children: [for (var i = 0; i < recent.length; i++) row(recent[i], lead: Icons.history, last: i == recent.length - 1)],
            ),
          );
      }
      if (visited.isNotEmpty) {
        rows
          ..add(SectionLabel(w.tr('Most visited')))
          ..add(CardX(children: [for (var i = 0; i < visited.length; i++) row(visited[i], last: i == visited.length - 1)]));
      }
      if (rows.isEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              w.tr('Search for a store, a kind of place or a level, like "food" or "level 2".'),
              textAlign: TextAlign.center,
              style: ts(14, color: p.muted),
            ),
          ),
        );
      }
    } else {
      final found = s.byDistance(s.v.places.where((x) => !x.exitNode && inFilter(x) && s.matches(x, q))).take(60).toList();
      rows.add(SectionLabel(found.isEmpty ? w.tr('Nothing found') : w.tr('Results')));
      if (found.isNotEmpty) rows.add(CardX(children: [for (var i = 0; i < found.length; i++) row(found[i], last: i == found.length - 1)]));
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  BackBtn(label: w.tr('Back')),
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: p.panel,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.line, width: p.lineW),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: p.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('search-field'),
                              controller: _q,
                              autofocus: true,
                              onChanged: (_) => setState(() {}),
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.search,
                              style: ts(15, color: p.ink),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: w.tr('Search for a store, a category or a place'),
                                hintStyle: ts(15, color: p.muted),
                                hintMaxLines: 1,
                              ),
                            ),
                          ),
                          if (_q.text.isNotEmpty)
                            IconButton(
                              tooltip: w.tr('Clear the search'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(_q.clear),
                              icon: Icon(Icons.close, color: p.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    for (final (id, label) in [('all', 'All'), for (final c in categories) (c.id, c.label)])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: ValueKey('filter-$id'),
                          label: Text(w.tr(label)),
                          selected: _filter == id,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _filter = id),
                          selectedColor: p.brand,
                          backgroundColor: p.panel,
                          labelStyle: ts(13, w: FontWeight.w700, color: _filter == id ? p.onBrand : p.ink),
                          side: BorderSide(color: _filter == id ? p.brand : p.line, width: p.lineW),
                          shape: const StadiumBorder(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: rows),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.place, required this.s, required this.t, required this.w, required this.now, required this.onTap, this.lead, this.last = false});
  final Place place;
  final NavState s;
  final NavText t;
  final Words w;
  final DateTime now;
  final VoidCallback onTap;
  final IconData? lead;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.pal, x = place;
    final d = s.distOf(x);
    final status = placeStatus(x, placeInfoFor(s.v, x), now, w);
    final hasStatus = x.kind != 'zone' && x.kind != 'conn' && x.cat != 'exit';
    final sub = [w.tr(catLabels[x.cat] ?? x.cat), t.levelName(x.lv), if (d != null) t.fmtM(d)].join(' · ');
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('result-${x.id}'),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: lead != null ? p.raised : p.soft, borderRadius: BorderRadius.circular(12)),
                child: Icon(lead ?? iconOfCat(x.cat), color: lead != null ? p.muted : p.brand2, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      x.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(15, w: FontWeight.w700, color: p.ink),
                    ),
                    Text(sub, style: ts(12.5, color: p.muted)),
                    if (hasStatus)
                      Text(
                        status.line,
                        style: ts(12.5, w: FontWeight.w600, color: status.isOpen ? p.open : p.closed),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

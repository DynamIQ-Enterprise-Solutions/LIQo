import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../models/paged.dart';
import '../widgets/common.dart';
import '../widgets/skeleton.dart';

/// One column of a list table.
class ListColumn<T> {
  const ListColumn({required this.label, required this.cell, this.flex = 1, this.hideOnMobile = false});

  final String label;
  final Widget Function(BuildContext context, T item) cell;
  final int flex;
  final bool hideOnMobile;
}

/// A dropdown filter above the table.
class FilterSpec {
  const FilterSpec({required this.name, required this.label, required this.options});

  final String name;
  final String label;

  /// value → label. An empty value means "all".
  final Map<String, String> options;
}

/// Lets the page refresh the list after a save: `controller.refresh()`.
class ListController extends ChangeNotifier {
  void refresh() => notifyListeners();
}

/// Generic server-paged list: search with debounce, filters, pagination, and
/// loading / error / empty states. Pages supply only [fetch] and [columns].
class ListScaffold<T> extends StatefulWidget {
  const ListScaffold({
    super.key,
    required this.fetch,
    required this.columns,
    this.filters = const [],
    this.controller,
    this.searchHint = 'Search…',
    this.emptyText = 'Nothing here yet.',
    this.onRowTap,
    this.pageSize = 20,
  });

  final Future<PagedResult<T>> Function(ListQuery query) fetch;
  final List<ListColumn<T>> columns;
  final List<FilterSpec> filters;
  final ListController? controller;
  final String searchHint;
  final String emptyText;

  /// Rows open a detail panel; a chevron on the right says so.
  final void Function(T item)? onRowTap;
  final int pageSize;

  @override
  State<ListScaffold<T>> createState() => _ListScaffoldState<T>();
}

class _ListScaffoldState<T> extends State<ListScaffold<T>> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _ticket = 0;
  late ListQuery _query = ListQuery(pageSize: widget.pageSize);

  /// A search or one of the visible filters is narrowing the list.
  bool get _filtered => _query.search.isNotEmpty || widget.filters.any((f) => (_query.filters[f.name] ?? '').isNotEmpty);
  PagedResult<T>? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_load);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.fetch(_query);
      // Ignore responses that arrive out of order.
      if (ticket != _ticket || !mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (ticket != _ticket || !mounted) return;
      setState(() => _error = formatApiError(e));
    } finally {
      if (ticket == _ticket && mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = _query.copyWith(search: text.trim(), page: 1);
      _load();
    });
  }

  void _setFilter(String name, String value) {
    _query = _query.copyWith(filters: {..._query.filters, name: value}, page: 1);
    _load();
  }

  void _goPage(int page) {
    _query = _query.copyWith(page: page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    final r = _result;
    final columns = widget.columns.where((c) => !mobile || !c.hideOnMobile).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: mobile ? double.infinity : 260,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    style: ts(13, color: p.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.searchHint,
                      hintStyle: ts(13, color: p.hint),
                      prefixIcon: Icon(Icons.search, size: 18, color: p.muted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.fieldLine)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.fieldLine)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.brand)),
                    ),
                  ),
                ),
                for (final f in widget.filters)
                  AppDropdown<String>(
                    value: _query.filters[f.name] ?? '',
                    items: [
                      for (final e in f.options.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.key.isEmpty ? f.label : e.value)),
                    ],
                    onChanged: (v) => _setFilter(f.name, v ?? ''),
                  ),
                AppButton(label: '', small: true, icon: Icons.refresh, onPressed: _load),
              ],
            ),
          ),
          // Header + body. The table keeps a minimum width so cells never get
          // squeezed below what their content needs; on narrow screens it
          // scrolls sideways instead of overflowing.
          LayoutBuilder(
            builder: (context, constraints) {
              final totalFlex = columns.fold<int>(0, (n, c) => n + c.flex);
              final minWidth = _minFlexUnit * totalFlex + (widget.onRowTap != null ? _chevronWidth : 0) + 32;
              final width = math.max(constraints.maxWidth, minWidth);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: width, child: _table(context, p, columns, r)),
              );
            },
          ),
          // Footer
          if (r != null && r.totalCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${(r.page - 1) * r.pageSize + 1}–${((r.page - 1) * r.pageSize + r.items.length)} of ${r.totalCount}',
                      style: ts(11, color: p.muted),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous page',
                    icon: const Icon(Icons.chevron_left, size: 18),
                    onPressed: r.page > 1 ? () => _goPage(r.page - 1) : null,
                  ),
                  Text('Page ${r.page} of ${r.pageCount}', style: ts(11, color: p.muted)),
                  IconButton(
                    tooltip: 'Next page',
                    icon: const Icon(Icons.chevron_right, size: 18),
                    onPressed: r.page < r.pageCount ? () => _goPage(r.page + 1) : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Narrowest a column may get per flex unit before the table scrolls sideways
/// (a flex-2 column is never under 140 px, enough for a status pill).
const _minFlexUnit = 70.0;
const _chevronWidth = 28.0;

extension<T> on _ListScaffoldState<T> {
  Widget _table(BuildContext context, Pal p, List<ListColumn<T>> columns, PagedResult<T>? r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: p.tableHead,
            border: Border(top: BorderSide(color: p.softLine), bottom: BorderSide(color: p.softLine)),
          ),
          child: Row(
            children: [
              for (final c in columns)
                Expanded(
                  flex: c.flex,
                  child: Text(c.label.toUpperCase(), overflow: TextOverflow.ellipsis, style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 0.8)),
                ),
              if (widget.onRowTap != null) const SizedBox(width: _chevronWidth),
            ],
          ),
        ),
        // Body
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(_error!, textAlign: TextAlign.center, style: ts(12, color: p.warn)),
                const SizedBox(height: 10),
                AppButton(label: 'Try again', primary: true, onPressed: _load),
              ],
            ),
          )
        else if (_loading && r == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Shimmer(child: SkeletonRows(count: 4)),
          )
        else if (r == null || r.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(28),
            child: Center(
              child: Text(
                // With a search or a filter on, "nothing yet" would be wrong (Round 14).
                _filtered ? 'Nothing matches these filters.' : widget.emptyText,
                textAlign: TextAlign.center,
                style: ts(12, color: p.muted),
              ),
            ),
          )
        else
          AnimatedOpacity(
            duration: motionFast,
            opacity: _loading ? 0.6 : 1,
            child: Column(
              children: [
                for (final item in r.items)
                  InkWell(
                    onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(item),
                    hoverColor: p.hover,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.rowLine))),
                      child: Row(
                        children: [
                          for (final c in columns)
                            Expanded(
                              flex: c.flex,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: DefaultTextStyle(
                                  style: ts(12, color: p.ink),
                                  overflow: TextOverflow.ellipsis,
                                  child: c.cell(context, item),
                                ),
                              ),
                            ),
                          if (widget.onRowTap != null)
                            SizedBox(width: _chevronWidth, child: Icon(Icons.chevron_right, size: 18, color: p.hint)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Status pill with icon + label (never colour alone).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.active, this.activeLabel = 'Active', this.inactiveLabel = 'Inactive'});

  final bool active;
  final String activeLabel;
  final String inactiveLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(active ? Icons.check_circle : Icons.pause_circle_outline, size: 12, color: active ? context.pal.green : context.pal.muted),
        const SizedBox(width: 4),
        Pill(active ? activeLabel : inactiveLabel, kind: active ? PillKind.green : PillKind.off),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../models/paged.dart';
import '../services/lookup_service.dart';
import '../widgets/common.dart';

/// Single- or multi-select picker backed by server search. Used for every
/// foreign-key field, no matter how small the table is today.
class LookupPicker extends StatelessWidget {
  const LookupPicker({
    super.key,
    required this.lookup,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    this.parentId,
    this.placeholder = 'Choose…',
    this.enabled = true,
  });

  final String lookup;
  final List<LookupItem> selected;
  final ValueChanged<List<LookupItem>> onChanged;
  final bool multi;
  final int? parentId;
  final String placeholder;
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final result = await showDialog<List<LookupItem>>(
      context: context,
      builder: (_) => _LookupDialog(lookup: lookup, multi: multi, parentId: parentId, initial: selected),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: enabled ? p.panel : p.boxBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: p.fieldLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => _open(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: selected.isEmpty
                    ? Text(placeholder, style: ts(13, color: p.hint))
                    : multi
                        ? Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final s in selected)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: p.soft,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(child: Text(s.label, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w600, color: p.brand2))),
                                      if (enabled) ...[
                                        const SizedBox(width: 4),
                                        InkWell(
                                          onTap: () => onChanged(selected.where((x) => x.id != s.id).toList()),
                                          child: Icon(Icons.close, size: 12, color: p.brand2),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                          )
                        : Text(selected.first.label, style: ts(13, color: p.ink)),
              ),
              Icon(Icons.search, size: 16, color: p.dropText),
            ],
          ),
        ),
      ),
    );
  }
}

class _LookupDialog extends StatefulWidget {
  const _LookupDialog({required this.lookup, required this.multi, required this.parentId, required this.initial});

  final String lookup;
  final bool multi;
  final int? parentId;
  final List<LookupItem> initial;

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _ticket = 0;
  bool _loading = true;
  String? _error;
  PagedResult<LookupItem>? _result;
  late List<LookupItem> _selected = [...widget.initial];
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _fetch();
    });
  }

  Future<void> _fetch() async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await LookupService().search(widget.lookup, query: _search.text, page: _page, parentId: widget.parentId);
      if (ticket != _ticket || !mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (ticket != _ticket || !mounted) return;
      setState(() => _error = formatApiError(e));
    } finally {
      if (ticket == _ticket && mounted) setState(() => _loading = false);
    }
  }

  void _toggle(LookupItem item) {
    if (!widget.multi) {
      Navigator.of(context).pop([item]);
      return;
    }
    setState(() {
      if (_selected.any((s) => s.id == item.id)) {
        _selected = _selected.where((s) => s.id != item.id).toList();
      } else {
        _selected = [..._selected, item];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = _result;
    return Dialog(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onSearch,
                style: ts(13, color: p.ink),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: _error != null
                    ? Center(child: Text(_error!, style: ts(12, color: p.warn)))
                    : _loading && r == null
                        ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                        : (r == null || r.items.isEmpty)
                            ? Center(child: Text('No matches.', style: ts(12, color: p.muted)))
                            : ListView(
                                shrinkWrap: true,
                                children: [
                                  for (final item in r.items)
                                    ListTile(
                                      dense: true,
                                      title: Text(item.label, style: ts(13, color: p.ink)),
                                      leading: widget.multi
                                          ? Checkbox(
                                              value: _selected.any((s) => s.id == item.id),
                                              onChanged: (_) => _toggle(item),
                                            )
                                          : null,
                                      onTap: () => _toggle(item),
                                    ),
                                ],
                              ),
              ),
              if (r != null && r.pageCount > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _page > 1 ? () { _page -= 1; _fetch(); } : null,
                    ),
                    Text('Page $_page of ${r.pageCount}', style: ts(11, color: p.muted)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _page < r.pageCount ? () { _page += 1; _fetch(); } : null,
                    ),
                  ],
                ),
              if (widget.multi) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Done (${_selected.length})',
                      primary: true,
                      onPressed: () => Navigator.of(context).pop(_selected),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

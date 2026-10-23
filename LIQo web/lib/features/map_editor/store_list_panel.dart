import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import 'map_models.dart';
import 'maps_service.dart';

/// One store on a map: its name and the spaces linked to it.
class _StoreEntry {
  _StoreEntry(this.storeId, this.name);

  final int storeId;
  final String name;
  final List<String> spaceKeys = [];
}

/// Beside the map viewer: the stores linked to spaces on this map, with a
/// search. Picking a store highlights its space (and switches to its level).
/// Read-only; links are made by mall admins on the store's page.
class StoreListPanel extends StatefulWidget {
  const StoreListPanel({super.key, required this.links, required this.doc, required this.selectedId, required this.onPick});

  final List<StoreLink> links;
  final LayoutDoc doc;

  /// The selected element's id, to mark the store it belongs to.
  final String? selectedId;
  final ValueChanged<String> onPick;

  static const searchKey = ValueKey('store-search');

  @override
  State<StoreListPanel> createState() => _StoreListPanelState();
}

class _StoreListPanelState extends State<StoreListPanel> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Space id → name of the level it is on, for the spaces drawn in this map.
  Map<String, String> _levelOfSpace() => {
        for (final b in widget.doc.buildings)
          for (final l in b.levels)
            for (final s in l.spaces) s.id: widget.doc.buildings.length > 1 ? '${b.name} · ${l.name}' : l.name,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final where = _levelOfSpace();
    final byStore = <int, _StoreEntry>{};
    for (final l in widget.links) {
      byStore.putIfAbsent(l.storeId, () => _StoreEntry(l.storeId, l.storeName)).spaceKeys.add(l.spaceKey);
    }
    final q = _search.text.trim().toLowerCase();
    final entries = byStore.values.where((e) => q.isEmpty || e.name.toLowerCase().contains(q)).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Container(
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stores on this map', style: ts(13, w: FontWeight.w700, color: p.ink)),
                Text('${byStore.length} linked to a space', style: ts(11, color: p.muted)),
                const SizedBox(height: 10),
                TextField(
                  key: StoreListPanel.searchKey,
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  // No pop-up menu or handles: overlays inside map pages are avoided (see CLAUDE.md).
                  contextMenuBuilder: null,
                  style: ts(12.5, color: p.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search stores…',
                    hintStyle: ts(12.5, color: p.hint),
                    prefixIcon: Icon(Icons.search, size: 16, color: p.muted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.fieldLine)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.fieldLine)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.brand)),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: p.softLine),
          Expanded(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(byStore.isEmpty ? 'No store is linked to a space on this map yet. Mall admins link stores on each store\'s page.' : 'No store matches "${_search.text.trim()}".',
                        style: ts(12, color: p.muted)),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      for (final e in entries) _row(context, e, where),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, _StoreEntry e, Map<String, String> where) {
    final p = context.pal;
    final onMap = e.spaceKeys.where(where.containsKey).toList();
    final selected = widget.selectedId != null && e.spaceKeys.contains(widget.selectedId);
    final levels = {for (final k in onMap) where[k]!}.toList();
    return Material(
      color: selected ? p.soft : Colors.transparent,
      child: InkWell(
        key: ValueKey('store-${e.storeId}'),
        hoverColor: p.hover,
        onTap: onMap.isEmpty ? null : () => widget.onPick(onMap.first),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(Icons.storefront_outlined, size: 16, color: selected ? p.brand : p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.name, overflow: TextOverflow.ellipsis, style: ts(12.5, w: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? p.brand2 : p.ink)),
                    Text(
                      onMap.isEmpty ? 'Linked to a space that is not on this map' : '${levels.join(', ')} · ${onMap.length} space${onMap.length == 1 ? '' : 's'}',
                      overflow: TextOverflow.ellipsis,
                      style: ts(10.5, color: p.muted),
                    ),
                  ],
                ),
              ),
              if (onMap.isEmpty) const Pill('Not on map', kind: PillKind.pending),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'editor_state.dart';
import 'map_canvas.dart';
import 'store_list_panel.dart';

/// Mall owner map viewer: the published map, read-only, one level at a time,
/// with the stores on it. `?branch=12` in the address opens that branch.
class MapViewerView extends ConsumerStatefulWidget {
  const MapViewerView({super.key, this.initialBranchId});

  /// From the address (`?branch=`); the branch page links here.
  final int? initialBranchId;

  @override
  ConsumerState<MapViewerView> createState() => _MapViewerViewState();
}

class _MapViewerViewState extends ConsumerState<MapViewerView> {
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');

  @override
  void initState() {
    super.initState();
    _openFromAddress();
  }

  @override
  void didUpdateWidget(MapViewerView old) {
    super.didUpdateWidget(old);
    if (old.initialBranchId != widget.initialBranchId) _openFromAddress();
  }

  void _openFromAddress() {
    final id = widget.initialBranchId;
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(editorProvider).branchId != id) ref.read(editorProvider.notifier).openPublished(id);
    });
  }

  /// Opens a branch and puts it in the address, so the link can be shared.
  void _pick(int branchId) {
    ref.read(editorProvider.notifier).openPublished(branchId);
    final path = GoRouterState.of(context).uri.path;
    context.go('$path?branch=$branchId');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final st = ref.watch(editorProvider);
    final n = ref.read(editorProvider.notifier);
    final list = ref.watch(mapListProvider);
    final height = (MediaQuery.sizeOf(context).height - 66 - 70).clamp(480.0, 2000.0);
    final sideBySide = !Bp.isTablet(context);

    Widget storePanel() => StoreListPanel(
          links: st.storeLinks,
          doc: st.doc!,
          selectedId: st.selection.isEmpty ? null : st.selection.id,
          onPick: n.selectById,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'Mall owner / Map viewer',
          title: 'Map viewer',
          subtitle: 'Published maps of the branches in your scope, with the stores on them. Viewing only; mall admins edit and publish.',
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Branch:', style: ts(12, color: p.muted)),
              list.when(
                loading: () => const SizedBox(width: 160, child: Shimmer(child: SkeletonBox(height: 30, radius: 8))),
                error: (e, _) => Text(formatApiError(e), style: ts(12, color: p.warn)),
                data: (items) => AppDropdown<int>(
                  value: items.any((m) => m.branchId == st.branchId) ? st.branchId! : 0,
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('Choose a branch…')),
                    for (final m in items)
                      DropdownMenuItem(
                        value: m.branchId,
                        child: Text('${m.mallName} · ${m.branchName}${m.publishedVersion != null ? ' · v${m.publishedVersion}' : ' · not published'}${m.branchActive ? '' : ' · inactive'}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null && v != 0) _pick(v);
                  },
                ),
              ),
              if (st.doc != null && st.publishedVersion != null) Pill('Published v${st.publishedVersion}', kind: PillKind.green),
              if (st.doc != null && st.versions.isNotEmpty)
                Text('Last published ${_fmt.format(st.versions.first.publishedAt)} by ${st.versions.first.publishedByName ?? ''}', style: ts(11, color: p.muted)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (st.error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Notice(bold: 'Note.', text: st.error!)),
        if (st.loading)
          const Shimmer(child: SkeletonCard(child: SkeletonChart(height: 360)))
        else if (st.doc == null && st.error == null)
          AppCard(
            padding: const EdgeInsets.all(28),
            child: st.branchId == null
                ? Text('Choose a branch to view its published map.', style: ts(13, color: p.muted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No published map yet.', style: ts(15, w: FontWeight.w800, color: p.ink)),
                      const SizedBox(height: 6),
                      Text('Its mall admin draws and publishes it from the map editor.', style: ts(12.5, color: p.muted)),
                      const SizedBox(height: 14),
                      AppButton(label: 'Back to branch', small: true, icon: Icons.arrow_back, onPressed: () => context.go('/mall-owner/branches/${st.branchId}')),
                    ],
                  ),
          )
        else if (st.doc == null)
          const SizedBox.shrink()
        else ...[
          SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final b in st.doc!.buildings) ...[
                        Padding(padding: const EdgeInsets.only(right: 6), child: Text(b.name, style: ts(11, w: FontWeight.w800, color: p.sideNote))),
                        for (final l in b.levels)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Material(
                              color: st.levelId == l.id ? p.soft : p.panel,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: st.levelId == l.id ? p.brand : p.line)),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => n.selectLevel(l.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Text(l.name, style: ts(12, w: FontWeight.w700, color: st.levelId == l.id ? p.brand2 : p.slate)),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: AppCard(child: ClipRRect(borderRadius: BorderRadius.all(Radius.circular(14)), child: MapCanvas()))),
                      if (sideBySide) ...[const SizedBox(width: 12), SizedBox(width: 290, child: storePanel())],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('Right/middle drag: pan · Wheel: zoom · Pick a store to highlight its space.', style: ts(10, color: p.sideNote)),
              ],
            ),
          ),
          if (!sideBySide) ...[const SizedBox(height: 12), SizedBox(height: 320, child: storePanel())],
        ],
      ],
    );
  }
}

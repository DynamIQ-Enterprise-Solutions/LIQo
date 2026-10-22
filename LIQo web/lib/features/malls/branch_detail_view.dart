import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../../shared/widgets/logo_image.dart';
import '../map_editor/maps_service.dart';
import '../stores/stores_service.dart';
import 'malls_service.dart';
import 'malls_view.dart';

/// One branch: details (editable), its stores, its map, danger zone.
class BranchDetailView extends ConsumerStatefulWidget {
  const BranchDetailView({super.key, required this.branchId});

  final int branchId;

  @override
  ConsumerState<BranchDetailView> createState() => _BranchDetailViewState();
}

class _BranchDetailViewState extends ConsumerState<BranchDetailView> {
  final _service = MallsService();
  static final _fmt = DateFormat('MMM d, yyyy');
  Branch? _branch;
  List<Store> _stores = const [];
  int _storeCount = 0;
  MapStatus? _map;
  bool _loading = true;
  bool _editing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _branch == null;
      _error = null;
    });
    try {
      final branch = await _service.getBranch(widget.branchId);
      PagedResult<Store>? stores;
      MapStatus? map;
      try {
        stores = await StoresService().list(ListQuery(pageSize: 8, filters: {'branchId': '${widget.branchId}'}));
      } catch (_) {}
      try {
        map = (await MapsService().list()).where((m) => m.branchId == widget.branchId).firstOrNull;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _branch = branch;
        _stores = stores?.items ?? const [];
        _storeCount = stores?.totalCount ?? 0;
        _map = map;
      });
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String text, {bool error = false}) {
    final n = ref.read(messagesProvider.notifier);
    error ? n.showError(text) : n.showSuccess(text);
  }

  Future<void> _setActive(bool active) async {
    final b = _branch!;
    if (active) {
      final ok = await confirmDialog(context, title: 'Reactivate ${b.name}?', message: 'Its stores become visible to their assigned accounts again.', confirmLabel: 'Reactivate');
      if (!ok) return;
    } else {
      final BranchImpact i;
      try {
        i = await _service.branchImpact(b.id);
      } catch (e) {
        _msg(formatApiError(e), error: true);
        return;
      }
      if (!mounted) return;
      final ok = await confirmDangerous(
        context,
        title: 'Deactivate ${b.name}?',
        impact: 'This hides ${countOf(i.stores, 'store', 'stores')}. Access is paused for ${countOf(i.storeOwners, 'store owner', 'store owners')} and ${countOf(i.mallAdmins, 'mall admin', 'mall admins')} '
            'until it is reactivated. Nothing is deleted.',
        name: b.name,
        confirmLabel: 'Deactivate branch',
      );
      if (!ok) return;
    }
    try {
      final updated = await _service.setBranchActive(b.id, active);
      setState(() => _branch = updated);
      _msg(active ? 'Branch reactivated.' : 'Branch deactivated.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _releaseLock() async {
    final b = _branch!;
    final holder = _map?.lockedBy ?? 'Someone';
    final ok = await confirmDangerous(
      context,
      title: 'Release the map lock of ${b.name}?',
      impact: '$holder is shown as editing this map. If their editor is still open, changes from the last few seconds may not save. Use this only when the editor was closed or crashed.',
      name: b.name,
      confirmLabel: 'Release the lock',
    );
    if (!ok) return;
    try {
      await MapsService().forceReleaseLock(b.id);
      _msg('Lock released. Another admin can open the editor now.');
      _load();
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final role = ref.watch(currentUserProvider)?.role ?? '';
    final nav = navForRole(role);
    final isSuper = role == 'superadmin';
    final canToggle = isSuper || role == 'supervisor';
    final b = _branch;
    final map = _map;
    // Opened from a mall page (?fromMall=<id>): Back returns to that mall (Round 14).
    final fromMall = GoRouter.maybeOf(context) == null ? null : int.tryParse(GoRouterState.of(context).uri.queryParameters['fromMall'] ?? '');
    final backPath = fromMall != null
        ? '${nav.prefix}/malls/$fromMall'
        : isSuper
            ? '/superadmin/malls?tab=branches'
            : (role == 'mall_admin' ? '/mall-admin/branch' : '/mall-owner/branches');
    final listLabel = fromMall != null
        ? (b?.mallName ?? 'Mall')
        : isSuper
            ? 'Malls & branches'
            : (role == 'mall_admin' ? 'Branch information' : 'Branches & hours');
    final storesPath = role == 'mall_admin' ? '/mall-admin/stores' : (role == 'supervisor' ? '/mall-owner/stores' : null);

    return DetailScaffold(
      eyebrow: '${nav.name} / $listLabel / ${b?.name ?? 'Branch'}',
      title: b?.name ?? 'Branch',
      subtitle: b == null ? '' : 'Branch of ${b.mallName}',
      backPath: backPath,
      backLabel: listLabel,
      pills: b == null ? const [] : [StatusPill(active: b.isActive)],
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: b == null
          ? const []
          : [
              DetailCard(
                title: 'Details',
                subtitle: isSuper ? 'Name, mall, address, hours and contacts' : 'Address, hours and contacts',
                trailing: _editing ? null : AppButton(label: isSuper ? 'Edit' : 'Edit information', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _editing = true)),
                child: _editing
                    ? AppFormBody(
                        fields: branchFields(full: isSuper),
                        initial: branchInitial(b),
                        onSubmit: (v) async {
                          final updated = await _service.updateBranch(b.id, branchBody(v, b, full: isSuper));
                          setState(() => _branch = updated);
                        },
                        onCancel: () => setState(() => _editing = false),
                        onDone: () {
                          setState(() => _editing = false);
                          _msg('Branch updated.');
                        },
                      )
                    : Column(
                        children: [
                          DetailRow('Mall', b.mallName),
                          DetailRow('Address', b.address),
                          DetailRow('Opening hours', b.openingHours),
                          DetailRow('Phone', b.contactPhone),
                          DetailRow('Email', b.contactEmail),
                          DetailRow('Logo', null, child: _LogoBlock(url: b.logoUrl, name: b.name)),
                        ],
                      ),
              ),
              DetailCard(
                title: 'Stores at this branch',
                subtitle: _storeCount == 0 ? 'None yet' : '${countOf(_storeCount, 'store', 'stores')}${b.isActive ? '' : ' · hidden while inactive'}',
                trailing: storesPath == null ? null : AppButton(label: 'All stores', small: true, icon: Icons.storefront_outlined, onPressed: () => context.go(storesPath)),
                child: _stores.isEmpty
                    ? Text('No store yet.', style: ts(12, color: p.muted))
                    : Column(
                        children: [
                          for (final s in _stores)
                            RecordRow(
                              title: s.name,
                              subtitle: s.categoryName ?? 'No category',
                              chips: [StatusPill(active: s.isActive), Pill('${s.spaceCount} on map', kind: PillKind.off)],
                              onTap: storesPath == null ? null : () => context.go('$storesPath/${s.id}'),
                            ),
                          if (_storeCount > _stores.length) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Showing ${_stores.length} of $_storeCount.', style: ts(11, color: p.muted))),
                        ],
                      ),
              ),
              DetailCard(
                title: 'Map',
                subtitle: (map == null || !map.hasMap ? 'No map yet' : (map.publishedVersion == null ? 'Draft only' : 'Published version ${map.publishedVersion}')) + (b.isActive ? '' : ' · hidden while inactive'),
                trailing: role == 'mall_admin'
                    ? AppButton(label: 'Open in editor', small: true, icon: Icons.architecture, onPressed: () => context.go('/mall-admin/map-editor'))
                    : role == 'supervisor'
                        ? AppButton(label: 'Open viewer', small: true, icon: Icons.map_outlined, onPressed: () => context.go('/mall-owner/maps?branch=${b.id}'))
                        : null,
                child: map == null || !map.hasMap
                    ? Text('The mall admin draws the map in the editor. Shoppers can navigate this branch once a version is published.', style: ts(12, color: p.muted))
                    : Column(
                        children: [
                          DetailRow('State', map.publishedVersion == null ? 'Draft only' : 'Published'),
                          DetailRow('Spaces', '${map.spaceCount}'),
                          if (map.publishedAt != null) DetailRow('Last published', _fmt.format(map.publishedAt!)),
                          if (map.lockedBy != null) DetailRow('Being edited by', map.lockedBy),
                          if (map.lockedBy != null && isSuper)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  Expanded(child: Text('Stuck because an editor was closed or crashed? The lock clears itself within 5 minutes, or release it now.', style: ts(11.5, color: p.muted))),
                                  const SizedBox(width: 12),
                                  DangerButton(key: const ValueKey('release-lock'), label: 'Release the lock', onPressed: _releaseLock),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
              if (canToggle)
                if (b.isActive)
                  DangerZone(actions: [
                    DangerAction(label: 'Deactivate', description: 'Hide this branch and its stores. Store owners and mall admins on it lose access until it is reactivated. Nothing is deleted.', onTap: () => _setActive(false)),
                  ])
                else
                  DetailCard(
                    title: 'Reactivate',
                    subtitle: 'This branch is inactive',
                    trailing: AppButton(label: 'Reactivate', small: true, primary: true, icon: Icons.play_circle_outline, onPressed: () => _setActive(true)),
                    child: Text('Its stores and map are hidden from shoppers, its mall admin and store owners until it is reactivated. You can still view them here.', style: ts(12, color: p.muted)),
                  ),
            ],
    );
  }
}

/// A logo preview with its URL, or a hint when there is none.
class _LogoBlock extends StatelessWidget {
  const _LogoBlock({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final has = url != null && url!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LogoImage(url: url, name: name, size: 64),
        const SizedBox(height: 6),
        has ? SelectableText(url!, style: ts(11, color: p.muted)) : Text('No logo yet. Edit to add one; the initials are shown meanwhile.', style: ts(11, color: p.muted)),
      ],
    );
  }
}

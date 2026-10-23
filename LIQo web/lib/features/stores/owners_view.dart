import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/widgets/common.dart';
import 'store_owner_wizard.dart';
import 'stores_service.dart';

/// Store owner accounts in the mall admin's scope, created through store assignments.
/// Rows open the owner's own page.
class OwnersView extends ConsumerStatefulWidget {
  const OwnersView({super.key});

  @override
  ConsumerState<OwnersView> createState() => _OwnersViewState();
}

class _OwnersViewState extends ConsumerState<OwnersView> {
  final _list = ListController();
  final _service = StoresService();

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final r = await runStoreOwnerWizard(context, service: _service);
    if (r == null) return;
    if (r.created != null) _list.refresh();
    final open = r.openId;
    if (open != null && mounted) context.go('/mall-admin/owners/$open');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final role = ref.watch(currentUserProvider)?.role ?? '';
    final canEdit = role == 'mall_admin' || role == 'superadmin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'Mall admin / Store owners',
          title: 'Store owners',
          subtitle: 'Each owner manages announcements for their assigned stores. Click a row to open it.',
          actions: [if (canEdit) AppButton(label: 'Add store owner', icon: Icons.person_add_alt, primary: true, onPressed: _create)],
        ),
        ListScaffold<StoreOwner>(
          controller: _list,
          fetch: _service.owners,
          searchHint: 'Search name or email…',
          emptyText: 'No store owners yet.',
          filters: const [
            FilterSpec(name: 'status', label: 'All statuses', options: {'': 'All statuses', 'active': 'Active', 'inactive': 'Inactive'})
          ],
          onRowTap: (o) => context.go('/mall-admin/owners/${o.id}'),
          columns: [
            ListColumn(
              label: 'Owner',
              flex: 3,
              cell: (c, o) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(o.fullName, style: ts(12, w: FontWeight.w700, color: p.ink)),
                  Text(o.email, style: ts(11, color: p.muted)),
                ],
              ),
            ),
            ListColumn(label: 'Stores', flex: 4, cell: (c, o) => Text(o.stores.isEmpty ? '—' : o.stores.map((s) => s.name).join(', '), style: ts(11, color: p.muted))),
            ListColumn(
              label: 'Status',
              flex: 2,
              cell: (c, o) => Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  StatusPill(active: o.isActive),
                  if (o.mustChangePassword) const Pill('Temp password', kind: PillKind.pending),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

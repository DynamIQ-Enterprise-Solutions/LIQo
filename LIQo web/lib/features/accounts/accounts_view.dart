import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/common.dart';
import 'accounts_service.dart';
import 'create_account_wizard.dart';

final _fmt = DateFormat('MMM d, yyyy h:mm a');

/// Superadmin: every account, with who reports to whom.
/// Mall owner: only the mall admins that report to them; can create admins.
/// Rows open the account's own page.
class AccountsView extends ConsumerStatefulWidget {
  const AccountsView({super.key});

  @override
  ConsumerState<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends ConsumerState<AccountsView> {
  final _list = ListController();
  final _service = AccountsService();

  /// The status filter in use, so the empty text can name it.
  final _status = ValueNotifier<String>('');

  @override
  void dispose() {
    _list.dispose();
    _status.dispose();
    super.dispose();
  }

  bool get _isSuper => ref.read(currentUserProvider)?.role == 'superadmin';

  Future<PagedResult<Account>> _fetch(ListQuery q) {
    final s = q.filters['status'] ?? '';
    if (_status.value != s) {
      // The list asks during its own build; update the notifier after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _status.value = s;
      });
    }
    return _service.list(q);
  }

  Future<void> _create() async {
    final isSuper = _isSuper;
    final r = await runCreateAccountWizard(context, fixedRole: isSuper ? null : 'mall_admin', service: _service);
    if (r == null) return;
    if (r.created != null) _list.refresh();
    final open = r.openId;
    if (open != null && mounted) context.go(isSuper ? '/superadmin/accounts/$open' : '/mall-owner/admins/$open');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = ref.watch(currentUserProvider);
    final isSuper = me?.role == 'superadmin';
    final base = isSuper ? '/superadmin/accounts' : '/mall-owner/admins';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: isSuper ? 'Superadmin / Accounts' : 'Mall owner / Mall admins',
          title: isSuper ? 'Account management' : 'Mall admins',
          subtitle: isSuper
              ? 'Create mall owner and mall admin accounts, reset passwords, manage access and who reports to whom. Click a row to open it.'
              : 'The mall admins who report to you. Click a row to open it.',
          actions: [
            AppButton(label: isSuper ? 'Create account' : 'Create mall admin', icon: Icons.person_add_alt, primary: true, onPressed: _create),
          ],
        ),
        ValueListenableBuilder<String>(
          valueListenable: _status,
          builder: (context, status, _) => ListScaffold<Account>(
            controller: _list,
            fetch: _fetch,
            searchHint: 'Search name or email…',
            emptyText: switch (status) {
              'unassigned' => 'No unassigned accounts.',
              'no_owner' => 'Every mall admin has an owner.',
              _ => isSuper ? 'No accounts yet.' : 'No mall admins report to you yet. Create one, or ask a superadmin to link one to you.',
            },
            onRowTap: (a) => context.go('$base/${a.id}'),
            filters: [
              if (isSuper)
                const FilterSpec(name: 'role', label: 'All roles', options: {
                  '': 'All roles',
                  'superadmin': 'Superadmin',
                  'supervisor': 'Mall Owner',
                  'mall_admin': 'Mall Admin',
                  'store_owner': 'Store Owner',
                }),
              FilterSpec(name: 'status', label: 'All statuses', options: {
                '': 'All statuses',
                'active': 'Active',
                'inactive': 'Inactive',
                if (isSuper) 'unassigned': 'Unassigned',
                if (isSuper) 'no_owner': 'No owner',
              }),
            ],
            columns: [
              ListColumn(
                label: 'Name',
                flex: 3,
                cell: (c, a) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(a.fullName, style: ts(12, w: FontWeight.w700, color: p.ink)),
                    Text(a.email, style: ts(11, color: p.muted)),
                  ],
                ),
              ),
              if (isSuper) ListColumn(label: 'Role', flex: 2, cell: (c, a) => Text(roleLabels[a.role] ?? a.role)),
              ListColumn(label: 'Access', flex: 3, cell: (c, a) => AccountAccessCell(a, showOwner: isSuper)),
              ListColumn(
                label: 'Status',
                flex: 2,
                cell: (c, a) => Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusPill(active: a.isActive),
                    if (a.mustChangePassword) const Pill('Temp password', kind: PillKind.pending),
                  ],
                ),
              ),
              ListColumn(
                label: 'Last sign-in',
                flex: 2,
                hideOnMobile: true,
                cell: (c, a) => Text(a.lastLoginAt == null ? 'Never' : _fmt.format(a.lastLoginAt!), style: ts(11, color: p.muted)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The Access column: counts per role, who a mall admin reports to, and an
/// amber "Unassigned" pill when an owner or admin has nothing yet.
class AccountAccessCell extends StatelessWidget {
  const AccountAccessCell(this.account, {super.key, this.showOwner = true});

  final Account account;

  /// Show "reports to" / "No owner" for mall admins (superadmin view).
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final a = account.access;
    switch (account.role) {
      case 'superadmin':
        return Text('Platform-wide', style: ts(11, color: p.muted));
      case 'supervisor':
      case 'mall_admin':
        if (a == null) return Text('—', style: ts(11, color: p.muted));
        final parts = <String>[
          if (account.role == 'supervisor' && a.malls > 0) 'Mall-wide ${a.malls}',
          if (a.branches > 0) (account.role == 'mall_admin' ? 'Branch assigned' : 'Branches ${a.branches}'),
        ];
        final owner = account.reportsTo;
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (a.isEmpty) const Pill('Unassigned', kind: PillKind.pending) else Text(parts.join(' · '), style: ts(11, color: p.ink)),
            if (showOwner && account.role == 'mall_admin')
              if (owner == null) const Pill('No owner', kind: PillKind.pending) else Text('reports to ${owner.name}', style: ts(11, color: p.muted)),
          ],
        );
      case 'store_owner':
        return Text('Stores ${a?.stores ?? 0}', style: ts(11, color: p.ink));
      default:
        return Text('—', style: ts(11, color: p.muted));
    }
  }
}

String formatError(Object e) => formatApiError(e);

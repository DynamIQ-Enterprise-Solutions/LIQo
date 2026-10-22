import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../account/profile_service.dart';
import '../stores/stores_service.dart';
import 'accounts_service.dart';
import 'assignments_flow.dart';

const _detailFields = [
  FieldSpec(name: 'fullName', label: 'Full name', required: true, maxLength: 200),
  FieldSpec(name: 'email', label: 'Email address', kind: FieldKind.email, required: true, maxLength: 255),
];

/// One account: details (editable), access, sign-in state, danger zone.
class AccountDetailView extends ConsumerStatefulWidget {
  const AccountDetailView({super.key, required this.accountId});

  final int accountId;

  @override
  ConsumerState<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends ConsumerState<AccountDetailView> {
  final _service = AccountsService();
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');
  Account? _a;
  AccountAssignments _assignments = const AccountAssignments();

  /// Store owners: their stores (the key fact about them).
  List<StoreRef> _stores = const [];

  /// Superadmin view: the person's waiting profile change, if any.
  ProfileRequest? _pendingChange;
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
      _loading = _a == null;
      _error = null;
    });
    try {
      final (a, assignments) = await _service.get(widget.accountId);
      var stores = const <StoreRef>[];
      ProfileRequest? pending;
      if (a.role == 'store_owner') {
        try {
          stores = (await StoresService().getOwner(a.id)).stores;
        } catch (_) {}
      }
      if (ref.read(currentUserProvider)?.role == 'superadmin' && a.role != 'superadmin') {
        try {
          pending = await ProfileService().pendingFor(a.id);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _a = a;
        _assignments = assignments;
        _stores = stores;
        _pendingChange = pending;
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

  Future<void> _run(Future<Account> Function() action, String done) async {
    try {
      final updated = await action();
      setState(() => _a = updated);
      _msg(done);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _assignments_() async {
    final a = _a!;
    final isSuper = ref.read(currentUserProvider)?.role == 'superadmin';
    try {
      final ok = await runAssignmentsFlow(context, _service, a, isSuper: isSuper);
      if (ok) {
        _msg('Assignments saved.');
        _load();
      }
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _reactivate() async {
    final a = _a!;
    final ok = await confirmDialog(context, title: 'Reactivate account?', message: '${a.fullName} will be able to sign in again.', confirmLabel: 'Reactivate');
    if (ok) await _run(() => _service.setActive(a.id, true), 'Account reactivated.');
  }

  Future<void> _deactivate() async {
    final a = _a!;
    final ok = await confirmDangerous(
      context,
      title: 'Deactivate ${a.fullName}?',
      impact: a.role == 'superadmin'
          ? 'They lose all platform access and can no longer sign in. At least one active superadmin always remains. Nothing is deleted.'
          : 'They will no longer be able to sign in. Their assignments are kept, so reactivating restores everything. Nothing is deleted.',
      name: a.fullName,
      confirmLabel: 'Deactivate account',
    );
    if (ok) await _run(() => _service.setActive(a.id, false), 'Account deactivated.');
  }

  Future<void> _reset() async {
    final a = _a!;
    final ok = await confirmDangerous(
      context,
      title: 'Reset the password of ${a.fullName}?',
      impact: '${a.role == 'superadmin' ? 'They keep their platform access but must sign in with the new password. ' : ''}Their current password stops working at once. A new temporary password is shown to you once; they must change it at the next sign-in. This also clears a lockout.',
      name: a.fullName,
      confirmLabel: 'Reset password',
    );
    if (!ok) return;
    try {
      final temp = await _service.resetPassword(a.id);
      _load();
      if (!mounted) return;
      await showOneTimeSecret(context, title: 'Password reset', message: 'Temporary password for ${a.email}:', secret: temp);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = ref.watch(currentUserProvider);
    final role = me?.role ?? '';
    final nav = navForRole(role);
    final isSuper = role == 'superadmin';
    final a = _a;
    final self = a != null && a.id == me?.id;
    final backPath = isSuper ? '/superadmin/accounts' : '/mall-owner/admins';
    final listLabel = isSuper ? 'Account management' : 'Mall admins';
    final isOwnerOrAdmin = a != null && (a.role == 'supervisor' || a.role == 'mall_admin');
    // Another superadmin: deactivate, reactivate and reset only; never edit their details (owner decision).
    final otherSuperadmin = a != null && a.role == 'superadmin' && !self;
    final pendingChange = _pendingChange;

    return DetailScaffold(
      eyebrow: '${nav.name} / $listLabel / ${a?.fullName ?? 'Account'}',
      title: a?.fullName ?? 'Account',
      subtitle: a == null ? '' : '${roleLabels[a.role] ?? a.role} · ${a.email}',
      backPath: backPath,
      backLabel: listLabel,
      pills: a == null
          ? const []
          : [
              StatusPill(active: a.isActive),
              if (a.mustChangePassword) const Pill('Temp password', kind: PillKind.pending),
              if (a.lockedUntil != null) const Pill('Locked', kind: PillKind.pending),
              if (self) const Pill('This is you', kind: PillKind.blue),
            ],
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: a == null
          ? const []
          : [
              DetailCard(
                title: 'Details',
                subtitle: otherSuperadmin ? "Only this superadmin can change their own name and email" : 'Name and email address',
                trailing: _editing || otherSuperadmin ? null : AppButton(label: 'Edit', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _editing = true)),
                child: _editing
                    ? AppFormBody(
                        fields: _detailFields,
                        initial: {'fullName': a.fullName, 'email': a.email},
                        onSubmit: (v) async {
                          final updated = await _service.update(a.id, email: v['email'] as String, fullName: v['fullName'] as String);
                          setState(() => _a = updated);
                        },
                        onCancel: () => setState(() => _editing = false),
                        onDone: () {
                          setState(() => _editing = false);
                          _msg('Account updated.');
                        },
                      )
                    : Column(
                        children: [
                          DetailRow('Full name', a.fullName),
                          DetailRow('Email', a.email),
                          DetailRow('Role', roleLabels[a.role] ?? a.role),
                          DetailRow('Created', a.createdAt == null ? null : _fmt.format(a.createdAt!)),
                        ],
                      ),
              ),
              if (pendingChange != null)
                DetailCard(
                  title: 'Pending profile change',
                  subtitle: 'Sent ${_fmt.format(pendingChange.createdAt)}. Nothing changes until you approve.',
                  trailing: AppButton(label: 'Review', small: true, primary: true, icon: Icons.how_to_reg_outlined, onPressed: () => context.go('/superadmin/profile-requests/${pendingChange.id}')),
                  child: Column(
                    children: [
                      DetailRow('New name', pendingChange.requestedName),
                      DetailRow('New email', pendingChange.requestedEmail),
                    ],
                  ),
                ),
              if (a.role == 'store_owner')
                DetailCard(
                  title: 'Stores',
                  subtitle: _stores.isEmpty ? 'None (the account is deactivated until a store is assigned)' : '${_stores.length} store${_stores.length == 1 ? '' : 's'}',
                  child: _stores.isEmpty
                      ? Text('Mall admins assign stores to store owners.', style: ts(12, color: p.muted))
                      : Column(
                          children: [
                            for (final s in _stores) RecordRow(title: s.name, subtitle: s.branchName, chips: [StatusPill(active: s.isActive)]),
                          ],
                        ),
                ),
              if (isOwnerOrAdmin)
                DetailCard(
                  title: 'Access',
                  subtitle: a.role == 'supervisor' ? 'Malls and branches this owner owns' : 'The branch this admin manages and who they report to',
                  trailing: AppButton(label: 'Change assignments', small: true, icon: Icons.account_tree_outlined, onPressed: _assignments_),
                  child: Column(
                    children: [
                      if (a.role == 'supervisor') ...[
                        DetailRow('Whole malls', _assignments.malls.isEmpty ? null : _assignments.malls.map((m) => m.label).join(', ')),
                        DetailRow('Single branches', _assignments.branches.isEmpty ? null : _assignments.branches.map((b) => b.label).join(', ')),
                      ] else ...[
                        DetailRow('Branch', _assignments.branches.isEmpty ? 'Not assigned yet' : _assignments.branches.first.label),
                        // Set automatically from branch ownership (owner decision 2026-10-22).
                        DetailRow('Reports to', null, child: Align(alignment: Alignment.centerLeft, child: a.reportsTo == null ? const Pill('No owner', kind: PillKind.pending) : Text(a.reportsTo!.name, style: ts(12.5, color: p.ink)))),
                      ],
                    ],
                  ),
                ),
              DetailCard(
                title: 'Sign-in',
                subtitle: 'What the person sees when they sign in',
                child: Column(
                  children: [
                    DetailRow('Last sign-in', a.lastLoginAt == null ? 'Never' : _fmt.format(a.lastLoginAt!)),
                    DetailRow('Password', a.mustChangePassword ? 'Temporary, must be changed at next sign-in' : 'Set by the person'),
                    DetailRow('Lockout', a.lockedUntil == null ? 'None' : 'Locked until ${_fmt.format(DateTime.parse(a.lockedUntil!).toLocal())}'),
                  ],
                ),
              ),
              if (!a.isActive && !self)
                DetailCard(
                  title: 'Reactivate',
                  subtitle: 'This account is inactive',
                  trailing: AppButton(label: 'Reactivate', small: true, primary: true, icon: Icons.play_circle_outline, onPressed: _reactivate),
                  child: Text('The person cannot sign in until the account is reactivated. Assignments are kept.', style: ts(12, color: p.muted)),
                ),
              if (self)
                DetailCard(title: 'Your own account', subtitle: 'Password and profile', child: Text('Change your own password under My account.', style: ts(12, color: p.muted)))
              else
                DangerZone(actions: [
                  DangerAction(label: 'Reset password', description: 'Give a new temporary password. The current one stops working.', onTap: _reset),
                  if (a.isActive) DangerAction(label: 'Deactivate', description: 'Block sign-in. Assignments are kept for a later reactivation.', onTap: _deactivate),
                ]),
            ],
    );
  }
}

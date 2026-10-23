import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../malls/malls_view.dart' show countOf;
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import 'stores_service.dart';

const _detailFields = [
  FieldSpec(name: 'fullName', label: 'Full name', required: true, maxLength: 200),
  FieldSpec(name: 'email', label: 'Email address', kind: FieldKind.email, required: true, maxLength: 255),
];

enum _Edit { none, details, assign }

/// One store owner: details (editable), their stores, danger zone.
class OwnerDetailView extends ConsumerStatefulWidget {
  const OwnerDetailView({super.key, required this.ownerId});

  final int ownerId;

  @override
  ConsumerState<OwnerDetailView> createState() => _OwnerDetailViewState();
}

class _OwnerDetailViewState extends ConsumerState<OwnerDetailView> {
  final _service = StoresService();
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');
  StoreOwner? _o;
  bool _loading = true;
  _Edit _edit = _Edit.none;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _o == null;
      _error = null;
    });
    try {
      final o = await _service.getOwner(widget.ownerId);
      if (mounted) setState(() => _o = o);
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

  Future<void> _run(Future<StoreOwner> Function() action, String done) async {
    try {
      final updated = await action();
      setState(() => _o = updated);
      _msg(done);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _reactivate() async {
    final o = _o!;
    final ok = await confirmDialog(context, title: 'Reactivate ${o.fullName}?', message: 'They will be able to sign in again.', confirmLabel: 'Reactivate');
    if (ok) await _run(() => _service.setOwnerActive(o.id, true), 'Reactivated.');
  }

  Future<void> _deactivate() async {
    final o = _o!;
    final ok = await confirmDangerous(
      context,
      title: 'Deactivate ${o.fullName}?',
      impact: 'They will not be able to sign in. Their stores stay assigned, so reactivating restores everything. Nothing is deleted.',
      name: o.fullName,
      confirmLabel: 'Deactivate owner',
    );
    if (ok) await _run(() => _service.setOwnerActive(o.id, false), 'Deactivated.');
  }

  Future<void> _reset() async {
    final o = _o!;
    final ok = await confirmDangerous(
      context,
      title: 'Reset the password of ${o.fullName}?',
      impact: 'Their current password stops working at once. A new temporary password is shown to you once; they must change it at the next sign-in.',
      name: o.fullName,
      confirmLabel: 'Reset password',
    );
    if (!ok) return;
    try {
      final temp = await _service.resetOwnerPassword(o.id);
      _load();
      if (!mounted) return;
      await showOneTimeSecret(context, title: 'Password reset', message: 'Temporary password for ${o.email}:', secret: temp);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _unassign(StoreRef s) async {
    final o = _o!;
    final last = o.stores.length == 1;
    final ok = await confirmDangerous(
      context,
      title: 'Remove ${s.name} from ${o.fullName}?',
      impact: last
          ? 'This is their last store. The account is deactivated automatically once it has no store; assigning a store later reactivates it.'
          : 'They lose access to this store and keep the others.',
      name: s.name,
      confirmLabel: 'Remove store',
    );
    if (!ok) return;
    try {
      final (updated, deactivated) = await _service.unassignOwner(o.id, s.id);
      setState(() => _o = updated);
      _msg(deactivated ? 'Removed. The owner was deactivated (no stores left).' : 'Removed.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final role = ref.watch(currentUserProvider)?.role ?? '';
    final canEdit = role == 'mall_admin' || role == 'superadmin';
    // Mall owners open store owners from a store page, read-only (Round 14).
    final asOwner = role == 'supervisor';
    final o = _o;

    return DetailScaffold(
      eyebrow: asOwner ? 'Mall owner / Stores / ${o?.fullName ?? 'Owner'}' : 'Mall admin / Store owners / ${o?.fullName ?? 'Owner'}',
      title: o?.fullName ?? 'Store owner',
      subtitle: o == null ? '' : 'Store owner · ${o.email}',
      backPath: asOwner ? '/mall-owner/stores' : '/mall-admin/owners',
      backLabel: asOwner ? 'Stores' : 'Store owners',
      hero: o == null
          ? null
          : RecordHero(
              mark: HeroMark.initials(initialsOf(o.fullName)),
              title: o.fullName,
              sub: o.email,
              pills: [const Pill('Store owner', kind: PillKind.blue), StatusPill(active: o.isActive), if (o.mustChangePassword) const Pill('Temp password', kind: PillKind.pending)],
              line: countOf(o.stores.length, 'store', 'stores'),
            ),
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: o == null
          ? const []
          : [
              DetailColumns(
                facts: [
                  DetailCard(
                    title: 'Details',
                    subtitle: 'Name and email address',
                    trailing: canEdit && _edit == _Edit.none ? AppButton(label: 'Edit', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _edit = _Edit.details)) : null,
                    child: _edit == _Edit.details
                        ? AppFormBody(
                            fields: _detailFields,
                            initial: {'fullName': o.fullName, 'email': o.email},
                            onSubmit: (v) async {
                              final updated = await _service.updateOwner(o.id, email: v['email'] as String, fullName: v['fullName'] as String);
                              setState(() => _o = updated);
                            },
                            onCancel: () => setState(() => _edit = _Edit.none),
                            onDone: () {
                              setState(() => _edit = _Edit.none);
                              _msg('Updated.');
                            },
                          )
                        : Column(
                            children: [
                              DetailRow('Full name', o.fullName),
                              DetailRow('Email', o.email),
                              DetailRow('Last sign-in', o.lastLoginAt == null ? 'Never' : _fmt.format(o.lastLoginAt!)),
                              DetailRow('Password', o.mustChangePassword ? 'Temporary, must be changed at next sign-in' : 'Set by the person'),
                            ],
                          ),
                  ),
                  if (canEdit && !o.isActive)
                    DetailCard(
                      title: 'Reactivate',
                      subtitle: 'This owner is inactive',
                      trailing: AppButton(label: 'Reactivate', small: true, primary: true, icon: Icons.play_circle_outline, onPressed: _reactivate),
                      child: Text('They cannot sign in until the account is reactivated. Stores stay assigned.', style: ts(12, color: p.muted)),
                    ),
                ],
                lists: [
                  DetailCard(
                    title: 'Stores',
                    subtitle: o.stores.isEmpty ? 'None (the account is deactivated until a store is assigned)' : '${o.stores.length} store${o.stores.length == 1 ? '' : 's'}',
                    trailing: canEdit && _edit == _Edit.none
                        ? AppButton(label: 'Assign a store', small: true, icon: Icons.add_business_outlined, onPressed: () => setState(() => _edit = _Edit.assign))
                        : null,
                    child: _edit == _Edit.assign
                        ? AppFormBody(
                            fields: const [
                              FieldSpec(
                                  name: 'store',
                                  label: 'Store',
                                  kind: FieldKind.lookup,
                                  lookup: 'stores',
                                  required: true,
                                  hint: 'Choose a store…',
                                  help: 'An owner can have several stores. A deactivated owner is reactivated when a store is assigned.')
                            ],
                            submitLabel: 'Assign',
                            onSubmit: (v) async {
                              final updated = await _service.assignOwner(o.id, (v['store'] as List<LookupItem>?)!.first.id);
                              setState(() => _o = updated);
                            },
                            onCancel: () => setState(() => _edit = _Edit.none),
                            onDone: () {
                              setState(() => _edit = _Edit.none);
                              _msg('Store assigned.');
                            },
                          )
                        : o.stores.isEmpty
                            ? Text('Assign a store to give this person something to manage.', style: ts(12, color: p.muted))
                            : Column(
                                children: [
                                  for (final s in o.stores)
                                    RecordRow(
                                      title: s.name,
                                      subtitle: s.branchName,
                                      chips: [StatusPill(active: s.isActive)],
                                      actions: [if (canEdit) DangerButton(label: 'Remove', onPressed: () => _unassign(s))],
                                      onTap: canEdit ? () => context.go('/mall-admin/stores/${s.id}') : (asOwner ? () => context.go('/mall-owner/stores/${s.id}') : null),
                                    ),
                                ],
                              ),
                  ),
                ],
                after: [
                  if (canEdit)
                    DangerZone(actions: [
                      DangerAction(label: 'Reset password', description: 'Give a new temporary password. The current one stops working.', onTap: _reset),
                      if (o.isActive) DangerAction(label: 'Deactivate', description: 'Block sign-in. Stores stay assigned for a later reactivation.', onTap: _deactivate),
                    ]),
                ],
              ),
            ],
    );
  }
}

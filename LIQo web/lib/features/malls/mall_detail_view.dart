import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/forms/wizard_dialog.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../../shared/widgets/logo_image.dart';
import '../accounts/accounts_service.dart';
import '../accounts/create_account_wizard.dart';
import 'malls_service.dart';
import 'malls_view.dart';
import 'people_service.dart';

/// One mall: details (editable), its branches, its owners and admins
/// (managed right here, no separate page), danger zone.
class MallDetailView extends ConsumerStatefulWidget {
  const MallDetailView({super.key, required this.mallId});

  final int mallId;

  @override
  ConsumerState<MallDetailView> createState() => _MallDetailViewState();
}

class _MallDetailViewState extends ConsumerState<MallDetailView> {
  final _service = MallsService();
  final _people = PeopleService();
  Mall? _mall;
  List<Branch> _branches = const [];
  MallPeople? _peopleData;

  /// Superadmin or an owner of the whole mall (owners of one branch see it read-only).
  bool _canManage = false;
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
      _loading = _mall == null;
      _error = null;
    });
    try {
      final mall = await _service.getMall(widget.mallId);
      final branches = await _service.listBranches(ListQuery(pageSize: 100, filters: {'mallId': '${widget.mallId}'}));
      MallPeople? people;
      final role = ref.read(currentUserProvider)?.role;
      if (role == 'superadmin' || role == 'supervisor') {
        try {
          people = await _people.get(widget.mallId);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _mall = mall;
        _canManage = mall.canManage ?? false;
        _branches = branches.items;
        _peopleData = people;
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

  LookupItem get _mallItem => LookupItem(id: widget.mallId, label: _mall?.name ?? 'Mall');

  // ---- Status ----

  Future<void> _setActive(bool active) async {
    final m = _mall!;
    if (active) {
      final ok = await confirmDialog(context, title: 'Reactivate ${m.name}?', message: 'Its branches and stores become visible to their assigned accounts again.', confirmLabel: 'Reactivate');
      if (!ok) return;
    } else {
      final MallImpact i;
      try {
        i = await _service.mallImpact(m.id);
      } catch (e) {
        _msg(formatApiError(e), error: true);
        return;
      }
      if (!mounted) return;
      final ok = await confirmDangerous(
        context,
        title: 'Deactivate ${m.name}?',
        impact: 'This hides ${countOf(i.branches, 'branch', 'branches')} and ${countOf(i.stores, 'store', 'stores')} from its mall admins, store owners and shoppers (its owners still see it). '
            'Access is paused for ${countOf(i.mallAdmins, 'mall admin', 'mall admins')} until it is reactivated. Nothing is deleted.',
        name: m.name,
        confirmLabel: 'Deactivate mall',
      );
      if (!ok) return;
    }
    try {
      final updated = await _service.setMallActive(m.id, active);
      setState(() => _mall = updated);
      _msg(active ? 'Mall reactivated.' : 'Mall deactivated.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  // ---- Branches ----

  Future<void> _addBranch() async {
    final ok = await addBranchDialog(context, _service, _mall!);
    if (ok) {
      _msg('Branch created.');
      _load();
    }
  }

  // ---- Owners ----

  Future<void> _addOwner() async {
    final ok = await showAppForm(
      context: context,
      title: 'Add an owner to ${_mall?.name}',
      subtitle: 'The account gets a whole-mall assignment: every branch of this mall, including ones added later.',
      submitLabel: 'Add owner',
      fields: const [FieldSpec(name: 'owner', label: 'Mall owner account', kind: FieldKind.lookup, lookup: 'supervisors', required: true, hint: 'Choose an owner…')],
      onSubmit: (v) => _people.addOwner(widget.mallId, (v['owner'] as List<LookupItem>).first.id),
    );
    if (ok) {
      _msg('Owner added.');
      _load();
    }
  }

  Future<void> _removeOwner(MallOwnerRow o) async {
    final linked = (_peopleData?.admins ?? const <MallAdminRow>[]).where((a) => a.reportsToId == o.id).length;
    final ok = await confirmDangerous(
      context,
      title: 'Remove ${o.fullName} from this mall?',
      impact: 'They lose this mall and its branches. Their account stays. '
          '${linked == 0 ? 'No admin here reports to them.' : '$linked ${linked == 1 ? 'admin' : 'admins'} here report to them; they move to the next owner of their branch or mall, or show "No owner".'}',
      name: o.fullName,
      confirmLabel: 'Remove owner',
    );
    if (!ok) return;
    try {
      final cleared = await _people.removeOwner(widget.mallId, o.id);
      _msg(cleared == 0 ? 'Owner removed.' : 'Owner removed. $cleared ${cleared == 1 ? 'admin moved' : 'admins moved'} to the next owner.');
      _load();
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _newOwnerAccount() async {
    _afterWizard(await runCreateAccountWizard(context, fixedRole: 'supervisor', initialMalls: [_mallItem]));
  }

  /// After a create wizard: reload when something was made, open the account when asked.
  void _afterWizard(WizardOutcome<Account>? r) {
    if (r == null) return;
    if (r.created != null) _load();
    final open = r.openId;
    if (open == null || !mounted) return;
    final role = ref.read(currentUserProvider)?.role;
    context.go(role == 'superadmin' ? '/superadmin/accounts/$open' : '/mall-owner/admins/$open');
  }

  // ---- Admins ----

  Future<void> _addAdmin() async {
    final ok = await showAppForm(
      context: context,
      title: 'Add an admin to ${_mall?.name}',
      subtitle: 'Only admins with no branch yet are offered: a mall admin manages exactly one branch.',
      submitLabel: 'Add admin',
      initial: {'mall': [_mallItem]},
      fields: const [
        FieldSpec(name: 'admin', label: 'Mall admin account', kind: FieldKind.lookup, lookup: 'free_mall_admins', required: true, hint: 'Choose an admin…', help: 'An admin already placed in a mall is not listed. Change their branch from that mall\'s page.'),
        FieldSpec(name: 'mall', label: 'Mall', kind: FieldKind.lookup, lookup: 'malls', required: true, readOnly: true),
        FieldSpec(name: 'branch', label: 'Branch', kind: FieldKind.lookup, lookup: 'branches', lookupParentField: 'mall', required: true, hint: 'Choose the branch…', help: 'They report to the owner of this branch, or else to the mall\'s owner (set automatically).'),
      ],
      onSubmit: (v) async {
        await _people.setAdmin(
          widget.mallId,
          (v['admin'] as List<LookupItem>).first.id,
          branchIds: [(v['branch'] as List<LookupItem>).first.id],
        );
      },
    );
    if (ok) {
      _msg('Admin added.');
      _load();
    }
  }

  Future<void> _editAdmin(MallAdminRow a) async {
    final ok = await showAppForm(
      context: context,
      title: 'Branch for ${a.fullName}',
      subtitle: 'A mall admin manages exactly one branch. Picking another branch replaces it.',
      submitLabel: 'Save',
      initial: {
        'mall': [_mallItem],
        'branch': [for (final b in a.branches.take(1)) LookupItem(id: b.id, label: '${_mall?.name} · ${b.name}')],
      },
      fields: const [
        FieldSpec(name: 'mall', label: 'Mall', kind: FieldKind.lookup, lookup: 'malls', required: true, readOnly: true),
        FieldSpec(name: 'branch', label: 'Branch', kind: FieldKind.lookup, lookup: 'branches', lookupParentField: 'mall', required: true, hint: 'Choose the branch…', help: 'They report to the owner of this branch, or else to the mall\'s owner (set automatically).'),
      ],
      onSubmit: (v) async {
        await _people.setAdmin(
          widget.mallId,
          a.id,
          branchIds: [(v['branch'] as List<LookupItem>).first.id],
        );
      },
    );
    if (ok) {
      _msg('Saved.');
      _load();
    }
  }

  Future<void> _removeAdmin(MallAdminRow a) async {
    final ok = await confirmDangerous(
      context,
      title: 'Remove ${a.fullName} from this mall?',
      impact: 'Their branch in ${_mall?.name} is taken away. The account itself stays.',
      name: a.fullName,
      confirmLabel: 'Remove admin',
    );
    if (!ok) return;
    try {
      await _people.removeAdmin(widget.mallId, a.id);
      _msg('Admin removed from this mall.');
      _load();
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _newAdminAccount() async {
    _afterWizard(await runCreateAccountWizard(context, fixedRole: 'mall_admin', mall: _mallItem));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final role = ref.watch(currentUserProvider)?.role ?? '';
    final nav = navForRole(role);
    final isSuper = role == 'superadmin';
    final me = ref.watch(currentUserProvider)?.id;
    final canToggle = (isSuper || role == 'supervisor') && _canManage;
    final m = _mall;
    final people = _peopleData;
    final hasBranches = _branches.isNotEmpty || (m?.branchCount ?? 0) > 0;

    return DetailScaffold(
      eyebrow: '${nav.name} / ${isSuper ? 'Malls & branches' : 'My malls'} / ${m?.name ?? 'Mall'}',
      title: m?.name ?? 'Mall',
      subtitle: m == null ? '' : 'Mall · ${countOf(m.branchCount ?? _branches.length, 'branch', 'branches')}',
      backPath: '${nav.prefix}/malls',
      backLabel: isSuper ? 'Malls & branches' : 'My malls',
      actions: [
        if (isSuper && m != null) AppButton(label: 'New owner account', icon: Icons.person_add_alt, onPressed: _newOwnerAccount),
        if (isSuper && m != null) AppButton(label: 'New admin account', icon: Icons.person_add_alt, primary: true, onPressed: hasBranches ? _newAdminAccount : () => _msg('Add a branch first: an admin manages a branch.', error: true)),
      ],
      pills: m == null ? const [] : [StatusPill(active: m.isActive), if ((m.branchCount ?? _branches.length) == 0) const Pill('No branches', kind: PillKind.pending)],
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: m == null
          ? const []
          : [
              DetailCard(
                title: 'Details',
                subtitle: 'Name and logo',
                trailing: _editing || !_canManage ? null : AppButton(label: 'Edit', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _editing = true)),
                child: _editing
                    ? AppFormBody(
                        fields: mallFields,
                        initial: {'name': m.name, 'logoUrl': m.logoUrl},
                        onSubmit: (v) async {
                          final updated = await _service.updateMall(m.id, v);
                          setState(() => _mall = updated);
                        },
                        onCancel: () => setState(() => _editing = false),
                        onDone: () {
                          setState(() => _editing = false);
                          _msg('Mall updated.');
                        },
                      )
                    : Column(
                        children: [
                          DetailRow('Name', m.name),
                          DetailRow('Status', null, child: Align(alignment: Alignment.centerLeft, child: StatusPill(active: m.isActive))),
                          DetailRow('Branches', '${m.branchCount ?? _branches.length}'),
                          DetailRow(
                            'Logo',
                            null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LogoImage(url: m.logoUrl, name: m.name, size: 64),
                                const SizedBox(height: 6),
                                (m.logoUrl ?? '').trim().isNotEmpty
                                    ? SelectableText(m.logoUrl!, style: ts(11, color: p.muted))
                                    : Text('No logo yet. Edit to add one; the initials are shown meanwhile.', style: ts(11, color: p.muted)),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
              DetailCard(
                title: 'Branches of this mall',
                subtitle: _branches.isEmpty ? 'None yet' : countOf(_branches.length, 'branch', 'branches'),
                trailing: isSuper ? AppButton(label: 'Add branch', small: true, icon: Icons.add, onPressed: _addBranch) : null,
                child: _branches.isEmpty
                    ? Text('No branch yet. A mall needs at least one branch before a mall admin can be assigned to it.', style: ts(12, color: p.muted))
                    : Column(
                        children: [
                          for (final b in _branches)
                            RecordRow(
                              title: b.name,
                              subtitle: b.address ?? b.openingHours,
                              chips: [StatusPill(active: b.isActive)],
                              onTap: () => context.go('${branchPath(role, b.id)}?fromMall=${widget.mallId}'),
                            ),
                        ],
                      ),
              ),
              if (isSuper || role == 'supervisor') ...[
                DetailCard(
                  title: 'Mall owners',
                  subtitle: 'Whole-mall owners cover every branch, including ones added later. Branch-level owners cover only the branches listed.',
                  trailing: isSuper ? AppButton(label: 'Add owner', small: true, icon: Icons.add, onPressed: _addOwner) : null,
                  child: people == null
                      ? Text('Owners could not be loaded.', style: ts(12, color: p.warn))
                      : people.owners.isEmpty
                          ? Text('No owner yet. Add an existing owner account, or create a new one with "New owner account".', style: ts(12, color: p.muted))
                          : Column(
                              children: [
                                for (final o in people.owners)
                                  RecordRow(
                                    title: o.fullName,
                                    subtitle: o.email,
                                    chips: [
                                      StatusPill(active: o.isActive),
                                      if (o.wholeMall) const Pill('Whole mall', kind: PillKind.blue) else Pill('Branches: ${o.branchNames}', kind: PillKind.off),
                                    ],
                                    actions: [if (isSuper) DangerButton(label: 'Remove', onPressed: () => _removeOwner(o))],
                                  ),
                              ],
                            ),
                ),
                DetailCard(
                  title: 'Mall admins',
                  subtitle: isSuper
                      ? 'One branch per admin. Each reports to the owner of their branch, or else the mall\'s owner; this is set automatically.'
                      : 'Admins on your branches. Each reports to the owner of their branch, or else the mall\'s owner. Yours open from here.',
                  trailing: isSuper && hasBranches ? AppButton(label: 'Add admin', small: true, icon: Icons.add, onPressed: _addAdmin) : null,
                  child: !hasBranches
                      ? Text('This mall has no branches yet, so no admin can be assigned. Add a branch first.', style: ts(12, color: p.warn))
                      : people == null
                          ? Text('Admins could not be loaded.', style: ts(12, color: p.warn))
                          : people.admins.isEmpty
                              ? Text(isSuper ? 'No admin on this mall yet. Add an admin who has no branch, or create a new account with "New admin account".' : 'No admin on your branches of this mall yet.', style: ts(12, color: p.muted))
                              : Column(
                                  children: [
                                    for (final a in people.admins)
                                      RecordRow(
                                        title: a.fullName,
                                        subtitle: a.email,
                                        chips: [
                                          StatusPill(active: a.isActive),
                                          if (a.mustChangePassword) const Pill('Temp password', kind: PillKind.pending),
                                          for (final b in a.branches) Pill(b.name, kind: PillKind.off),
                                          if (a.reportsToId == null) const Pill('No owner', kind: PillKind.pending) else Pill('Reports to ${a.reportsToName}', kind: PillKind.blue),
                                        ],
                                        actions: [
                                          if (isSuper) AppButton(label: 'Edit', small: true, onPressed: () => _editAdmin(a)),
                                          if (isSuper) DangerButton(label: 'Remove', onPressed: () => _removeAdmin(a)),
                                        ],
                                        // An owner opens the admins who report to them.
                                        onTap: !isSuper && a.reportsToId == me ? () => context.go('/mall-owner/admins/${a.id}') : null,
                                      ),
                                  ],
                                ),
                ),
              ],
              if (role == 'supervisor' && !_canManage)
                DetailCard(
                  title: 'Read only',
                  subtitle: 'You own branches of this mall, not the whole mall',
                  child: Text('Only an owner of the whole mall, or a superadmin, can rename, deactivate or reactivate it. You can still manage your own branches.', style: ts(12, color: p.muted)),
                ),
              if (canToggle)
                if (m.isActive)
                  DangerZone(actions: [
                    DangerAction(label: 'Deactivate', description: 'Hide this mall, its branches and stores from everyone except superadmins and its owners. Nothing is deleted.', onTap: () => _setActive(false)),
                  ])
                else
                  DetailCard(
                    title: 'Reactivate',
                    subtitle: 'This mall is inactive',
                    trailing: AppButton(label: 'Reactivate', small: true, primary: true, icon: Icons.play_circle_outline, onPressed: () => _setActive(true)),
                    child: Text('Its branches and stores are hidden from its mall admins, store owners and shoppers until it is reactivated. Its owners still see it.', style: ts(12, color: p.muted)),
                  ),
            ],
    );
  }
}

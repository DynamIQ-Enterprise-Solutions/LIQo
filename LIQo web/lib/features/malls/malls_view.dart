import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/logo_image.dart';
import 'malls_service.dart';

/// "1 branch" / "3 branches".
String countOf(int count, String one, String many) => '$count ${count == 1 ? one : many}';

const mallFields = [
  FieldSpec(name: 'name', label: 'Mall name', required: true, maxLength: 200, hint: 'e.g. SM Prime'),
  FieldSpec(name: 'logoUrl', label: 'Logo URL', maxLength: 500, hint: 'https://…', help: 'Optional. Image upload comes later.'),
];

/// Branch form. Latitude and longitude stay in the API but are hidden from the
/// screens until the shopper app exists (owner decision, 2026-10-21).
List<FieldSpec> branchFields({required bool full, bool lockMall = false, bool create = false}) => [
      if (full) FieldSpec(name: 'mall', label: 'Mall', kind: FieldKind.lookup, lookup: 'malls', required: true, hint: 'Choose a mall…', readOnly: lockMall),
      if (full) const FieldSpec(name: 'name', label: 'Branch name', required: true, maxLength: 200, hint: 'e.g. SM Mall of Asia'),
      const FieldSpec(name: 'address', label: 'Address', kind: FieldKind.multiline, maxLength: 500),
      // Round 21: hours are entered per day under Opening hours; the old text stays as a read-only note.
      if (!create) const FieldSpec(name: 'openingHours', label: 'Old hours note', maxLength: 300, readOnly: true, help: 'Read only. Enter the hours under Opening hours.'),
      const FieldSpec(name: 'contactPhone', label: 'Contact phone', maxLength: 50),
      const FieldSpec(name: 'contactEmail', label: 'Contact email', kind: FieldKind.email, maxLength: 255),
      const FieldSpec(name: 'logoUrl', label: 'Logo URL', maxLength: 500, hint: 'https://…'),
    ];

Map<String, Object?> branchBody(Map<String, Object?> v, Branch? current, {required bool full}) => {
      if (full) 'mallId': (v['mall'] as List<LookupItem>?)?.firstOrNull?.id,
      if (full) 'name': v['name'],
      'address': v['address'],
      // Kept as they are: the screens do not show them for now.
      'latitude': current?.latitude,
      'longitude': current?.longitude,
      'openingHours': v['openingHours'],
      'contactPhone': v['contactPhone'],
      'contactEmail': v['contactEmail'],
      'logoUrl': v['logoUrl'],
    };

Map<String, Object?> branchInitial(Branch b) => {
      'mall': [LookupItem(id: b.mallId, label: b.mallName)],
      'name': b.name,
      'address': b.address,
      'openingHours': b.openingHours,
      'contactPhone': b.contactPhone,
      'contactEmail': b.contactEmail,
      'logoUrl': b.logoUrl,
    };

/// Where a branch page lives for this role.
String branchPath(String role, int id) => role == 'mall_admin' ? '/mall-admin/branch/$id' : '${navForRole(role).prefix}/branches/$id';

/// Malls and branches on one page with a tab switch. Rows open their own page.
/// Superadmin creates; mall owners and mall admins edit inside their scope.
class MallsView extends ConsumerStatefulWidget {
  const MallsView({super.key, this.initialTab = 0, this.branchesOnly = false});

  final int initialTab;

  /// For the mall owner "Branches & hours" and mall admin "Branch information" pages.
  final bool branchesOnly;

  @override
  ConsumerState<MallsView> createState() => _MallsViewState();
}

class _MallsViewState extends ConsumerState<MallsView> {
  final _malls = ListController();
  final _branches = ListController();
  final _service = MallsService();
  // Mall owners get the malls list only here; their branches have their own page (Round 14).
  late int _tab = widget.branchesOnly ? 1 : (ref.read(currentUserProvider)?.role == 'supervisor' ? 0 : widget.initialTab);

  @override
  void dispose() {
    _malls.dispose();
    _branches.dispose();
    super.dispose();
  }

  void _msg(String text, {bool error = false}) {
    final m = ref.read(messagesProvider.notifier);
    error ? m.showError(text) : m.showSuccess(text);
  }

  void _refreshAll() {
    _malls.refresh();
    _branches.refresh();
  }

  /// Register the mall, then offer its first branch right away so a mall
  /// admin can be assigned without a dead end.
  Future<void> _createMall() async {
    Mall? created;
    final ok = await showAppForm(
      context: context,
      title: 'Register mall',
      submitLabel: 'Create',
      fields: mallFields,
      onSubmit: (v) async {
        created = await _service.createMall(v);
      },
    );
    if (!ok) return;
    _malls.refresh();
    _msg('Mall created.');
    final m = created;
    if (m == null || !mounted) return;
    await addBranchDialog(context, _service, m, first: true);
    _refreshAll();
  }

  Future<void> _createBranch() async {
    final ok = await showAppForm(
      context: context,
      title: 'Create branch',
      submitLabel: 'Create',
      fields: branchFields(full: true, create: true),
      onSubmit: (v) => _service.createBranch(branchBody(v, null, full: true)),
    );
    if (ok) {
      _refreshAll();
      _msg('Branch created.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final role = ref.watch(currentUserProvider)?.role ?? '';
    final nav = navForRole(role);
    final isSuper = role == 'superadmin';
    final showMallsTab = !widget.branchesOnly && role != 'supervisor';

    final title = widget.branchesOnly ? (role == 'mall_admin' ? 'Branch information' : 'Branches & hours') : (isSuper ? 'Malls & branches' : 'My malls');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: '${isSuper ? 'Superadmin' : role == 'supervisor' ? 'Mall owner' : 'Mall admin'} / $title',
          title: title,
          subtitle:
              isSuper ? 'Register mall chains and their physical branches. Click a row to open it.' : 'Review and update the information for the locations in your scope. Click a row to open it.',
          actions: [
            if (isSuper && _tab == 0) AppButton(label: 'Register mall', icon: Icons.add, primary: true, onPressed: _createMall),
            if (isSuper && _tab == 1) AppButton(label: 'Create branch', icon: Icons.add, primary: true, onPressed: _createBranch),
          ],
        ),
        if (showMallsTab) ...[
          Row(
            children: [
              _TabChip(label: 'Malls', active: _tab == 0, onTap: () => setState(() => _tab = 0)),
              const SizedBox(width: 8),
              _TabChip(label: 'Branches', active: _tab == 1, onTap: () => setState(() => _tab = 1)),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_tab == 0)
          ListScaffold<Mall>(
            key: const ValueKey('malls'),
            controller: _malls,
            fetch: _service.listMalls,
            searchHint: 'Search malls…',
            emptyText: isSuper ? 'No malls yet. Register the first one.' : 'No malls assigned to you yet.',
            filters: const [
              FilterSpec(name: 'status', label: 'All statuses', options: {'': 'All statuses', 'active': 'Active', 'inactive': 'Inactive'})
            ],
            onRowTap: (m) => context.go('${nav.prefix}/malls/${m.id}'),
            columns: [
              ListColumn(
                label: 'Mall',
                flex: 3,
                cell: (c, m) => Row(
                  children: [
                    LogoImage(url: m.logoUrl, name: m.name, size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text(m.name, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.ink))),
                  ],
                ),
              ),
              ListColumn(
                label: 'Branches',
                flex: 2,
                cell: (c, m) => (m.branchCount ?? 0) == 0 ? const Align(alignment: Alignment.centerLeft, child: Pill('No branches', kind: PillKind.pending)) : Text('${m.branchCount}'),
              ),
              ListColumn(label: 'Status', flex: 2, cell: (c, m) => StatusPill(active: m.isActive)),
            ],
          )
        else
          ListScaffold<Branch>(
            key: const ValueKey('branches'),
            controller: _branches,
            fetch: _service.listBranches,
            searchHint: 'Search branches, malls, addresses…',
            emptyText: isSuper ? 'No branches yet.' : 'No branches assigned to you yet.',
            filters: const [
              FilterSpec(name: 'status', label: 'All statuses', options: {'': 'All statuses', 'active': 'Active', 'inactive': 'Inactive'})
            ],
            onRowTap: (b) => context.go(branchPath(role, b.id)),
            columns: [
              ListColumn(
                label: 'Branch',
                flex: 3,
                cell: (c, b) => Row(
                  children: [
                    LogoImage(url: b.logoUrl, name: b.name, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(b.name, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.ink)),
                          Text(b.mallName, overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ListColumn(label: 'Address', flex: 3, hideOnMobile: true, cell: (c, b) => Text(b.address ?? '—', style: ts(11, color: p.muted))),
              ListColumn(label: 'Hours', flex: 2, hideOnMobile: true, cell: (c, b) => Text(b.openingHours ?? '—', style: ts(11, color: p.muted))),
              ListColumn(label: 'Status', flex: 2, cell: (c, b) => StatusPill(active: b.isActive)),
            ],
          ),
      ],
    );
  }
}

/// Branch form with the mall locked. [first] is the prompt right after a mall is registered.
Future<bool> addBranchDialog(BuildContext context, MallsService service, Mall m, {bool first = false}) {
  return showAppForm(
    context: context,
    title: first ? 'Add the first branch of ${m.name}?' : 'Add branch to ${m.name}',
    subtitle: first ? 'A mall needs at least one branch before a mall admin can be assigned to it. You can also do this later from the mall page.' : '',
    submitLabel: 'Create branch',
    cancelLabel: first ? 'Later' : 'Cancel',
    initial: {
      'mall': [LookupItem(id: m.id, label: m.name)],
    },
    fields: branchFields(full: true, lockMall: true, create: true),
    onSubmit: (v) => service.createBranch(branchBody(v, null, full: true)),
  );
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AnimatedContainer(
      duration: motionFast,
      decoration: BoxDecoration(
        color: active ? p.soft : p.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? p.brand : p.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(label, style: ts(12, w: FontWeight.w700, color: active ? p.brand2 : p.slate)),
          ),
        ),
      ),
    );
  }
}

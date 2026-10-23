import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/forms/lookup_picker.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import 'stores_service.dart';

List<FieldSpec> storeFields({required bool create}) => [
      FieldSpec(name: 'branch', label: 'Branch', kind: FieldKind.lookup, lookup: 'branches', required: true, readOnly: !create, hint: 'Choose a branch…'),
      const FieldSpec(name: 'name', label: 'Store name', required: true, maxLength: 200),
      const FieldSpec(
          name: 'category',
          label: 'Category',
          kind: FieldKind.lookup,
          lookup: 'store_categories',
          lookupParentField: 'branch',
          hint: 'Choose a category…',
          help: 'Categories are managed under Option lists.'),
      const FieldSpec(name: 'description', label: 'Description', kind: FieldKind.multiline, maxLength: 1000),
      const FieldSpec(name: 'openingHours', label: 'Opening hours', maxLength: 300, hint: 'Mon–Sun 10:00 AM – 9:00 PM'),
      const FieldSpec(name: 'contactPhone', label: 'Contact phone', maxLength: 50),
      const FieldSpec(name: 'contactEmail', label: 'Contact email', kind: FieldKind.email, maxLength: 255),
      const FieldSpec(name: 'logoUrl', label: 'Logo URL', maxLength: 500, hint: 'https://…'),
    ];

Map<String, Object?> storeBody(Map<String, Object?> v) => {
      'branchId': (v['branch'] as List<LookupItem>?)?.firstOrNull?.id,
      'name': v['name'],
      'categoryId': (v['category'] as List<LookupItem>?)?.firstOrNull?.id,
      'description': v['description'],
      'openingHours': v['openingHours'],
      'contactPhone': v['contactPhone'],
      'contactEmail': v['contactEmail'],
      'logoUrl': v['logoUrl'],
    };

Map<String, Object?> storeInitial(Store s) => {
      'branch': [LookupItem(id: s.branchId, label: '${s.mallName} · ${s.branchName}')],
      'name': s.name,
      'category': s.categoryId == null ? null : [LookupItem(id: s.categoryId!, label: s.categoryName ?? '')],
      'description': s.description,
      'openingHours': s.openingHours,
      'contactPhone': s.contactPhone,
      'contactEmail': s.contactEmail,
      'logoUrl': s.logoUrl,
    };

/// Mall admin: create and maintain stores. Store owner: "My stores" (read-only).
/// Rows open the store's own page.
class StoresView extends ConsumerStatefulWidget {
  const StoresView({super.key});

  @override
  ConsumerState<StoresView> createState() => _StoresViewState();
}

class _StoresViewState extends ConsumerState<StoresView> {
  final _list = ListController();
  final _service = StoresService();
  List<LookupItem> _branchFilter = const [];

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  void _msg(String text, {bool error = false}) {
    final m = ref.read(messagesProvider.notifier);
    error ? m.showError(text) : m.showSuccess(text);
  }

  Future<void> _create() async {
    final ok = await showAppForm(
      context: context,
      title: 'Create store',
      submitLabel: 'Create',
      initial: {'branch': _branchFilter},
      fields: storeFields(create: true),
      onSubmit: (v) => _service.create(storeBody(v)),
    );
    if (ok) {
      _list.refresh();
      _msg('Store created.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final role = ref.watch(currentUserProvider)?.role ?? '';
    final nav = navForRole(role);
    final canEdit = role == 'mall_admin' || role == 'superadmin';
    final owner = role == 'store_owner';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: owner ? 'Store owner / My stores' : '${role == 'supervisor' ? 'Mall owner' : 'Mall admin'} / Stores',
          title: owner ? 'My stores' : (role == 'supervisor' ? 'Stores' : 'Stores & spaces'),
          subtitle: owner
              ? 'The stores assigned to you. Ask your mall admin to change store details. Click a row to open it.'
              : role == 'supervisor'
                  ? 'Stores in your malls, read-only. Their mall admins manage them. Click a row to open it.'
                  : 'Store records, their map spaces, and their owners. Click a row to open it.',
          actions: [if (canEdit) AppButton(label: 'Create store', icon: Icons.add, primary: true, onPressed: _create)],
        ),
        if (!owner)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text('Branch:', style: ts(12, color: p.muted)),
                const SizedBox(width: 8),
                ShrinkTo(
                  maxWidth: 320,
                  child: LookupPicker(
                    lookup: 'branches',
                    selected: _branchFilter,
                    placeholder: 'All branches in your scope',
                    onChanged: (v) {
                      setState(() => _branchFilter = v);
                      _list.refresh();
                    },
                  ),
                ),
                if (_branchFilter.isNotEmpty)
                  LinkButton('Clear', onPressed: () {
                    setState(() => _branchFilter = const []);
                    _list.refresh();
                  }),
              ],
            ),
          ),
        ListScaffold<Store>(
          controller: _list,
          fetch: (q) => _service.list(q.copyWith(filters: {
            ...q.filters,
            if (_branchFilter.isNotEmpty) 'branchId': '${_branchFilter.first.id}',
          })),
          searchHint: 'Search stores, branches, categories…',
          emptyText: owner ? 'No stores assigned to you yet.' : 'No stores yet.',
          filters: const [
            FilterSpec(name: 'status', label: 'All statuses', options: {'': 'All statuses', 'active': 'Active', 'inactive': 'Inactive'})
          ],
          onRowTap: (s) => context.go('${nav.prefix}/stores/${s.id}'),
          columns: [
            ListColumn(
              label: 'Store',
              flex: 3,
              cell: (c, s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.name, style: ts(12, w: FontWeight.w700, color: p.ink)),
                  Text('${s.mallName} · ${s.branchName}', style: ts(11, color: p.muted)),
                ],
              ),
            ),
            ListColumn(label: 'Category', flex: 2, hideOnMobile: true, cell: (c, s) => Text(s.categoryName ?? '—', style: ts(11, color: p.muted))),
            ListColumn(label: 'Hours', flex: 2, hideOnMobile: true, cell: (c, s) => Text(s.openingHours ?? '—', style: ts(11, color: p.muted))),
            ListColumn(label: 'Spaces', flex: 1, hideOnMobile: true, cell: (c, s) => Text('${s.spaceCount}')),
            ListColumn(label: 'Owners', flex: 1, hideOnMobile: true, cell: (c, s) => Text('${s.ownerCount}')),
            ListColumn(label: 'Status', flex: 2, cell: (c, s) => StatusPill(active: s.isActive)),
          ],
        ),
      ],
    );
  }
}

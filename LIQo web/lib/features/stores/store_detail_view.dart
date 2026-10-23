import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../malls/malls_view.dart' show countOf;
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import 'store_owner_wizard.dart';
import 'stores_service.dart';
import 'stores_view.dart';

enum _Edit { none, details, spaces }

/// One store: details (editable), map spaces, owners, danger zone.
class StoreDetailView extends ConsumerStatefulWidget {
  const StoreDetailView({super.key, required this.storeId});

  final int storeId;

  @override
  ConsumerState<StoreDetailView> createState() => _StoreDetailViewState();
}

class _StoreDetailViewState extends ConsumerState<StoreDetailView> {
  final _service = StoresService();
  Store? _s;
  List<String> _keys = const [];
  List<OwnerRef> _owners = const [];
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
      _loading = _s == null;
      _error = null;
    });
    try {
      final (s, keys, owners) = await _service.get(widget.storeId);
      if (!mounted) return;
      setState(() {
        _s = s;
        _keys = keys;
        _owners = owners;
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
    final s = _s!;
    if (active) {
      final ok = await confirmDialog(context, title: 'Reactivate ${s.name}?', message: 'It shows in the directory again.', confirmLabel: 'Reactivate');
      if (!ok) return;
    } else {
      final ok = await confirmDangerous(
        context,
        title: 'Deactivate ${s.name}?',
        impact: 'The store is hidden from the directory and the shopper app. Its ${_owners.length} owner(s) keep their accounts. Nothing is deleted.',
        name: s.name,
        confirmLabel: 'Deactivate store',
      );
      if (!ok) return;
    }
    try {
      final updated = await _service.setActive(s.id, active);
      setState(() => _s = updated);
      _msg(active ? 'Store reactivated.' : 'Store deactivated.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _addOwner() async {
    final s = _s!;
    final r = await runStoreOwnerWizard(context, store: LookupItem(id: s.id, label: s.name), service: _service);
    if (r == null) return;
    if (r.created != null) await _load();
    final open = r.openId;
    if (open != null && mounted) context.go('/mall-admin/owners/$open');
  }

  Future<void> _removeOwner(OwnerRef o) async {
    final s = _s!;
    final ok = await confirmDangerous(
      context,
      title: 'Remove ${o.fullName} from ${s.name}?',
      impact: 'They lose access to this store. An owner with no stores left is deactivated.',
      name: o.fullName,
      confirmLabel: 'Remove owner',
    );
    if (!ok) return;
    try {
      final (_, deactivated) = await _service.unassignOwner(o.id, s.id);
      _msg(deactivated ? 'Owner removed and deactivated (no stores left).' : 'Owner removed.');
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
    final canEdit = role == 'mall_admin' || role == 'superadmin';
    final isOwner = role == 'store_owner';
    final s = _s;
    final listLabel = isOwner ? 'My stores' : (role == 'supervisor' ? 'Stores' : 'Stores & spaces');

    return DetailScaffold(
      eyebrow: '${nav.name} / $listLabel / ${s?.name ?? 'Store'}',
      title: s?.name ?? 'Store',
      subtitle: s == null ? '' : '${s.mallName} · ${s.branchName}',
      backPath: '${nav.prefix}/stores',
      backLabel: listLabel,
      hero: s == null
          ? null
          : RecordHero(
              mark: HeroMark.logo(logoUrl: s.logoUrl, name: s.name),
              title: s.name,
              sub: '${s.branchName} · ${s.mallName}',
              pills: [StatusPill(active: s.isActive), if (s.categoryName != null) Pill(s.categoryName!, kind: PillKind.off)],
              line: [
                _keys.isEmpty ? 'Not on the map yet' : '${_keys.length} on the map',
                countOf(_owners.length, 'owner', 'owners'),
              ].join(' · '),
            ),
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: s == null
          ? const []
          : [
              DetailColumns(
                facts: [
                  DetailCard(
                    title: 'Details',
                    subtitle: 'Name, category, hours and contacts',
                    trailing: canEdit && _edit == _Edit.none ? AppButton(label: 'Edit', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _edit = _Edit.details)) : null,
                    child: _edit == _Edit.details
                        ? AppFormBody(
                            fields: storeFields(create: false),
                            initial: storeInitial(s),
                            onSubmit: (v) async {
                              final updated = await _service.update(s.id, storeBody(v));
                              setState(() => _s = updated);
                            },
                            onCancel: () => setState(() => _edit = _Edit.none),
                            onDone: () {
                              setState(() => _edit = _Edit.none);
                              _msg('Store updated.');
                            },
                          )
                        : Column(
                            children: [
                              DetailRow('Branch', '${s.mallName} · ${s.branchName}'),
                              DetailRow('Category', s.categoryName),
                              DetailRow('Description', s.description),
                              DetailRow('Opening hours', s.openingHours),
                              DetailRow('Phone', s.contactPhone),
                              DetailRow('Email', s.contactEmail),
                              DetailRow('Logo URL', s.logoUrl),
                            ],
                          ),
                  ),
                  DetailCard(
                    title: 'Map spaces',
                    subtitle: _keys.isEmpty ? 'Not placed on the map yet' : '${_keys.length} space${_keys.length == 1 ? '' : 's'} on the branch map',
                    trailing: canEdit && _edit == _Edit.none ? AppButton(label: 'Edit spaces', small: true, icon: Icons.map_outlined, onPressed: () => setState(() => _edit = _Edit.spaces)) : null,
                    child: _edit == _Edit.spaces
                        ? AppFormBody(
                            fields: const [
                              FieldSpec(
                                  name: 'keys',
                                  label: 'Space ids',
                                  kind: FieldKind.multiline,
                                  hint: 'sp-a01\nsp-a02',
                                  help: 'One space id per line. Space ids come from the branch map. A space may be shared by more than one store.')
                            ],
                            initial: {'keys': _keys.join('\n')},
                            onSubmit: (v) async {
                              final text = (v['keys'] as String?) ?? '';
                              final list = text.split(RegExp(r'[\s,]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                              final saved = await _service.setSpaces(s.id, list);
                              setState(() => _keys = saved);
                            },
                            onCancel: () => setState(() => _edit = _Edit.none),
                            onDone: () {
                              setState(() => _edit = _Edit.none);
                              _msg('Space links saved.');
                            },
                          )
                        : _keys.isEmpty
                            ? Text('Shoppers find this store on the map once it is linked to a space drawn in the map editor.', style: ts(12, color: p.muted))
                            : Wrap(spacing: 6, runSpacing: 6, children: [for (final k in _keys) Pill(k, kind: PillKind.blue)]),
                  ),
                  if (canEdit && !s.isActive)
                    DetailCard(
                      title: 'Reactivate',
                      subtitle: 'This store is inactive',
                      trailing: AppButton(label: 'Reactivate', small: true, primary: true, icon: Icons.play_circle_outline, onPressed: () => _setActive(true)),
                      child: Text('It is hidden from the directory and the shopper app until it is reactivated.', style: ts(12, color: p.muted)),
                    ),
                ],
                lists: [
                  DetailCard(
                    title: 'Owners',
                    subtitle: _owners.isEmpty ? 'No owner yet' : '${_owners.length} owner${_owners.length == 1 ? '' : 's'}',
                    trailing: canEdit ? AppButton(label: 'Add owner', small: true, icon: Icons.person_add_alt, onPressed: _addOwner) : null,
                    child: _owners.isEmpty
                        ? Text('Store owners submit announcements for this store. Add one to create their account.', style: ts(12, color: p.muted))
                        : Column(
                            children: [
                              for (final o in _owners)
                                RecordRow(
                                  title: o.fullName,
                                  subtitle: o.email,
                                  chips: [StatusPill(active: o.isActive)],
                                  actions: [if (canEdit) DangerButton(label: 'Remove', onPressed: () => _removeOwner(o))],
                                  onTap: role == 'mall_admin'
                                      ? () => context.go('/mall-admin/owners/${o.id}')
                                      : role == 'supervisor'
                                          ? () => context.go('/mall-owner/owners/${o.id}')
                                          : null,
                                ),
                            ],
                          ),
                  ),
                ],
                after: [
                  if (canEdit && s.isActive)
                    DangerZone(actions: [
                      DangerAction(label: 'Deactivate', description: 'Hide the store from the directory and the shopper app. Nothing is deleted.', onTap: () => _setActive(false)),
                    ]),
                ],
              ),
            ],
    );
  }
}

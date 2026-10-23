import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import 'options_view.dart';
import 'stores_service.dart';

/// One option value: details (editable), where it is used, danger zone.
class OptionDetailView extends ConsumerStatefulWidget {
  const OptionDetailView({super.key, required this.optionId});

  final int optionId;

  @override
  ConsumerState<OptionDetailView> createState() => _OptionDetailViewState();
}

class _OptionDetailViewState extends ConsumerState<OptionDetailView> {
  final _service = StoresService();
  BranchOption? _o;
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
      _loading = _o == null;
      _error = null;
    });
    try {
      final o = await _service.getOption(widget.optionId);
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

  Future<void> _setActive(bool active) async {
    final o = _o!;
    if (active) {
      final ok = await confirmDialog(context, title: 'Reactivate "${o.name}"?', message: 'It can be chosen again.', confirmLabel: 'Reactivate');
      if (!ok) return;
    } else {
      final ok = await confirmDangerous(
        context,
        title: 'Deactivate "${o.name}"?',
        impact: 'It can no longer be chosen for new records. The ${o.inUse} record(s) that use it keep it. Nothing is deleted.',
        name: o.name,
        confirmLabel: 'Deactivate',
      );
      if (!ok) return;
    }
    try {
      final updated = await _service.setOptionActive(o.id, active);
      setState(() => _o = updated);
      _msg(active ? 'Reactivated.' : 'Deactivated. Existing records keep this value.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _delete() async {
    final o = _o!;
    final ok = await confirmDangerous(
      context,
      title: 'Delete "${o.name}"?',
      impact: 'The value is removed for good. This cannot be undone.',
      name: o.name,
      confirmLabel: 'Delete',
    );
    if (!ok) return;
    try {
      await _service.deleteOption(o.id);
      _msg('Deleted.');
      if (mounted) context.go('/mall-admin/options');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final o = _o;
    final kindLabel = o == null ? 'Option' : (optionKinds[o.kind] ?? o.kind);
    final inUse = (o?.inUse ?? 0) > 0;

    return DetailScaffold(
      eyebrow: 'Mall admin / Option lists / ${o?.name ?? 'Option'}',
      title: o?.name ?? 'Option',
      subtitle: o == null ? '' : '$kindLabel · sort order ${o.sortOrder}',
      backPath: '/mall-admin/options',
      backLabel: 'Option lists',
      hero: o == null
          ? null
          : RecordHero(
              mark: const HeroMark.icon(Icons.list_alt_outlined),
              title: o.name,
              sub: kindLabel,
              pills: [StatusPill(active: o.isActive), Pill(kindLabel, kind: PillKind.off)],
              line: 'Sort order ${o.sortOrder}',
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
                    subtitle: 'Name and sort order',
                    trailing: _editing ? null : AppButton(label: 'Edit', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _editing = true)),
                    child: _editing
                        ? AppFormBody(
                            fields: optionFields,
                            initial: {'name': o.name, 'sortOrder': o.sortOrder},
                            onSubmit: (v) async {
                              final updated = await _service.updateOption(o.id, {'name': v['name'], 'sortOrder': v['sortOrder'] ?? 0});
                              setState(() => _o = updated);
                            },
                            onCancel: () => setState(() => _editing = false),
                            onDone: () {
                              setState(() => _editing = false);
                              _msg('Updated.');
                            },
                          )
                        : Column(
                            children: [
                              DetailRow('List', kindLabel),
                              DetailRow('Name', o.name),
                              DetailRow('Sort order', '${o.sortOrder}'),
                            ],
                          ),
                  ),
                  DetailCard(
                    title: 'Used by',
                    subtitle: o.kind == 'store_category' ? 'Stores with this category' : 'Map spaces that use this value',
                    child: Text(
                      o.kind == 'store_category'
                          ? (o.inUse == 0
                              ? 'No store uses this category yet.'
                              : '${o.inUse} store${o.inUse == 1 ? '' : 's'} use this category. Deactivating keeps it on them; deleting is blocked while it is in use.')
                          : 'Unit types and floor labels are offered in the map editor when a space is described.',
                      style: ts(12, color: p.muted),
                    ),
                  ),
                  if (!o.isActive)
                    DetailCard(
                      title: 'Reactivate',
                      subtitle: 'This value is inactive',
                      trailing: AppButton(label: 'Reactivate', small: true, primary: true, icon: Icons.play_circle_outline, onPressed: () => _setActive(true)),
                      child: Text('It cannot be chosen for new records until it is reactivated.', style: ts(12, color: p.muted)),
                    ),
                ],
                after: [
                  DangerZone(actions: [
                    if (o.isActive) DangerAction(label: 'Deactivate', description: 'Hide it from new records; existing ones keep it.', onTap: () => _setActive(false)),
                    DangerAction(
                      label: 'Delete',
                      description: inUse ? 'Used by ${o.inUse} store(s), so it cannot be deleted. Deactivate it instead.' : 'Remove the value for good.',
                      enabled: !inUse,
                      onTap: _delete,
                    ),
                  ]),
                ],
              ),
            ],
    );
  }
}

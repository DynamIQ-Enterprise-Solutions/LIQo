import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/forms/lookup_picker.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'stores_service.dart';

const optionFields = [
  FieldSpec(name: 'name', label: 'Name', required: true, maxLength: 100),
  FieldSpec(name: 'sortOrder', label: 'Sort order', kind: FieldKind.integer, min: 0, max: 9999, help: 'Lower numbers show first.'),
];

/// Branch option lists: store categories, unit types, floor labels.
/// Values in use can be deactivated but not deleted, so existing records stay valid.
/// Rows open the value's own page.
class OptionsView extends ConsumerStatefulWidget {
  const OptionsView({super.key});

  @override
  ConsumerState<OptionsView> createState() => _OptionsViewState();
}

class _OptionsViewState extends ConsumerState<OptionsView> {
  final _service = StoresService();
  List<LookupItem> _branch = const [];
  String _kind = 'store_category';
  List<BranchOption>? _items;
  bool _loading = false;
  String? _error;

  int? get _branchId => _branch.firstOrNull?.id;

  void _msg(String text, {bool error = false}) {
    final m = ref.read(messagesProvider.notifier);
    error ? m.showError(text) : m.showSuccess(text);
  }

  Future<void> _load() async {
    final id = _branchId;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.options(id, kind: _kind);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final ok = await showAppForm(
      context: context,
      title: 'Add ${optionKinds[_kind]!.toLowerCase().replaceAll(RegExp(r's$'), '')}',
      submitLabel: 'Add',
      fields: optionFields,
      onSubmit: (v) => _service.createOption({'branchId': _branchId, 'kind': _kind, 'name': v['name'], 'sortOrder': v['sortOrder'] ?? 0}),
    );
    if (ok) {
      _msg('Added.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = _items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'Mall admin / Option lists',
          title: 'Option lists',
          subtitle: 'Store categories, unit types and floor labels used by each branch. Click a row to open it.',
          actions: [if (_branchId != null) AppButton(label: 'Add', icon: Icons.add, primary: true, onPressed: _add)],
        ),
        Row(
          children: [
            Text('Branch:', style: ts(12, color: p.muted)),
            const SizedBox(width: 8),
            ShrinkTo(
              maxWidth: 320,
              child: LookupPicker(
                lookup: 'branches',
                selected: _branch,
                placeholder: 'Choose a branch…',
                onChanged: (v) {
                  setState(() {
                    _branch = v;
                    _items = null;
                  });
                  _load();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final e in optionKinds.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _kind == e.key,
                onSelected: (_) {
                  setState(() {
                    _kind = e.key;
                    _items = null;
                  });
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        AppCard(
          child: _branchId == null
              ? Padding(padding: const EdgeInsets.all(28), child: Center(child: Text('Choose a branch to manage its lists.', style: ts(12, color: p.muted))))
              : _error != null
                  ? Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: ts(12, color: p.warn)))
                  : items == null || (_loading && items.isEmpty)
                      ? const Padding(padding: EdgeInsets.all(16), child: Shimmer(child: SkeletonRows(count: 4)))
                      : items.isEmpty
                          ? Padding(padding: const EdgeInsets.all(28), child: Center(child: Text('Nothing here yet. Click Add.', style: ts(12, color: p.muted))))
                          : Column(
                              children: [
                                for (final o in items)
                                  InkWell(
                                    onTap: () => context.go('/mall-admin/options/${o.id}'),
                                    hoverColor: p.hover,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.rowLine))),
                                      child: Row(
                                        children: [
                                          SizedBox(width: 40, child: Text('${o.sortOrder}', style: ts(11, color: p.muted))),
                                          Expanded(child: Text(o.name, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.ink))),
                                          if (o.kind == 'store_category') ShrinkTo(maxWidth: 90, child: Text('${o.inUse} in use', overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted))),
                                          const SizedBox(width: 10),
                                          StatusPill(active: o.isActive),
                                          const SizedBox(width: 6),
                                          Icon(Icons.chevron_right, size: 18, color: p.hint),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
        ),
      ],
    );
  }
}

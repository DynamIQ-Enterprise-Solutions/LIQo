import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/lookup_picker.dart';
import '../../shared/models/paged.dart';
import '../../shared/services/lookup_service.dart';
import '../../shared/widgets/common.dart';
import 'accounts_service.dart';

/// The whole assignment set the dialog hands back. Who a mall admin reports
/// to is not part of it: it follows branch ownership (owner decision 2026-10-22).
class AssignmentChoice {
  const AssignmentChoice({required this.mallIds, required this.branchIds});

  final List<int> mallIds;
  final List<int> branchIds;
}

/// What is picked so far, kept by whoever shows [AssignmentFields] (the
/// Assignments dialog, or the Access step of the create wizard).
class AssignmentDraft {
  const AssignmentDraft({this.malls = const [], this.branches = const [], this.mall});

  /// Mall owners: whole malls.
  final List<LookupItem> malls;
  final List<AssignedBranch> branches;

  /// Mall admins: the mall whose branch is being picked.
  final LookupItem? mall;

  /// The starting point from an account's current assignments.
  factory AssignmentDraft.from(String role, AccountAssignments initial, {LookupItem? initialMall}) {
    if (role == 'supervisor') return AssignmentDraft(malls: [...initial.malls], branches: [...initial.branches]);
    final first = initial.branches.where((b) => b.mallId != null).firstOrNull;
    return AssignmentDraft(
      branches: [...initial.branches],
      mall: first != null ? LookupItem(id: first.mallId!, label: first.mallName) : initialMall,
    );
  }

  bool validFor(String role) => role == 'supervisor' ? (malls.isNotEmpty || branches.isNotEmpty) : branches.isNotEmpty;

  AssignmentChoice toChoice() => AssignmentChoice(
        mallIds: [for (final m in malls) m.id],
        branchIds: [for (final b in branches) b.id],
      );
}

/// Lists the branches of one mall. The app uses the lookup service; tests inject a fake.
typedef BranchSearch = Future<PagedResult<LookupItem>> Function(int mallId, {int pageSize});

/// The real branch search (the lookup service).
Future<PagedResult<LookupItem>> serverBranchSearch(int mallId, {int pageSize = 200}) => LookupService().search('branches', parentId: mallId, pageSize: pageSize);

/// The "Assignments" action on an account page.
/// Returns true when [onSubmit] succeeded; false when the user cancelled.
Future<bool> showAssignmentDialog({
  required BuildContext context,
  required String role,
  required String title,
  required String submitLabel,
  required Future<void> Function(AssignmentChoice choice) onSubmit,
  String subtitle = '',
  AccountAssignments initial = const AccountAssignments(),
  LookupItem? initialMall,
  bool canCreateBranches = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AssignmentDialog(
      role: role,
      title: title,
      subtitle: subtitle,
      submitLabel: submitLabel,
      initial: initial,
      initialMall: initialMall,
      canCreateBranches: canCreateBranches,
      onSubmit: onSubmit,
    ),
  );
  return ok == true;
}

/// Mall owner variant: whole malls and single branches (an owner can own many).
/// Mall admin variant: pick a mall, then the one branch the admin manages.
class AssignmentDialog extends StatefulWidget {
  const AssignmentDialog({
    super.key,
    required this.role,
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    this.subtitle = '',
    this.initial = const AccountAssignments(),
    this.initialMall,
    this.canCreateBranches = true,
    this.branchSearch = serverBranchSearch,
  });

  final String role;
  final String title;
  final String subtitle;
  final String submitLabel;
  final AccountAssignments initial;

  /// Mall admin variant: the mall to start on when there is no branch yet.
  final LookupItem? initialMall;

  /// False for people who cannot add branches (mall owners): the "no branches" hint says whom to ask.
  final bool canCreateBranches;
  final Future<void> Function(AssignmentChoice choice) onSubmit;
  final BranchSearch branchSearch;

  /// Keys for tests: the submit wrapper reports whether it is enabled.
  static const submitKey = ValueKey('assignment-submit');
  static const branchKey = ValueKey('assignment-branch');

  @override
  State<AssignmentDialog> createState() => _AssignmentDialogState();
}

class _AssignmentDialogState extends State<AssignmentDialog> {
  late AssignmentDraft _draft = AssignmentDraft.from(widget.role, widget.initial, initialMall: widget.initialMall);
  bool _busy = false;
  String? _error;

  bool get _canSubmit => _draft.validFor(widget.role) && !_busy;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_draft.toChoice());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Dialog(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: ts(21, w: FontWeight.w800, color: p.ink, height: 1.25)),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(widget.subtitle, style: ts(12, color: p.muted)),
                ],
                const SizedBox(height: 20),
                AssignmentFields(
                  role: widget.role,
                  draft: _draft,
                  canCreateBranches: widget.canCreateBranches,
                  branchSearch: widget.branchSearch,
                  onChanged: (d) => setState(() => _draft = d),
                ),
                const SizedBox(height: 18),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: p.warn),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_error!, style: ts(12, color: p.warn))),
                      ],
                    ),
                  ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    AppButton(label: 'Cancel', onPressed: _busy ? () {} : () => Navigator.of(context).pop(false)),
                    IgnorePointer(
                      key: AssignmentDialog.submitKey,
                      ignoring: !_canSubmit,
                      child: Opacity(
                        opacity: _canSubmit ? 1 : 0.45,
                        child: AppButton(
                          label: _busy ? 'Saving…' : widget.submitLabel,
                          primary: true,
                          onPressed: _submit,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pickers of an assignment, without buttons. Reports every change through
/// [onChanged]; the parent keeps the [AssignmentDraft].
class AssignmentFields extends StatefulWidget {
  const AssignmentFields({
    super.key,
    required this.role,
    required this.draft,
    required this.onChanged,
    this.canCreateBranches = true,
    this.branchSearch = serverBranchSearch,
    this.branchNote,
  });

  final String role;
  final AssignmentDraft draft;
  final ValueChanged<AssignmentDraft> onChanged;

  /// False for mall owners: the "no branches" hint asks them to contact a superadmin.
  final bool canCreateBranches;
  final BranchSearch branchSearch;

  /// Mall admin variant: a line under the branch picker (who is already there).
  final Widget? branchNote;

  @override
  State<AssignmentFields> createState() => _AssignmentFieldsState();
}

class _AssignmentFieldsState extends State<AssignmentFields> {
  /// null = not checked yet; false = the chosen mall has no branches.
  bool? _mallHasBranches;
  String? _error;

  AssignmentDraft get _d => widget.draft;
  bool get _isOwner => widget.role == 'supervisor';

  @override
  void initState() {
    super.initState();
    final mall = _d.mall;
    if (!_isOwner && mall != null) {
      if (_d.branches.isNotEmpty) {
        _mallHasBranches = true; // it has at least the assigned one
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _checkMall(mall));
      }
    }
  }

  void _emit(AssignmentDraft d) => widget.onChanged(d);

  Future<void> _checkMall(LookupItem mall) async {
    try {
      final r = await widget.branchSearch(mall.id, pageSize: 1);
      if (!mounted || _d.mall?.id != mall.id) return;
      setState(() => _mallHasBranches = r.totalCount > 0);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  /// The branch lookup labels rows "Mall · Branch"; inside one mall only the branch part is useful.
  String _branchName(String label, LookupItem mall) {
    final prefix = '${mall.label} · ';
    return label.startsWith(prefix) ? label.substring(prefix.length) : label;
  }

  Future<void> _pickMall(List<LookupItem> v) async {
    final mall = v.firstOrNull;
    setState(() {
      _mallHasBranches = null;
      _error = null;
    });
    // Switching mall drops the branch: an admin has one branch, in one mall.
    _emit(AssignmentDraft(mall: mall));
    if (mall == null) return;
    await _checkMall(mall);
  }

  void _setBranch(List<LookupItem> picked) {
    final mall = _d.mall;
    if (mall == null) return;
    _emit(AssignmentDraft(
      mall: mall,
      branches: [for (final i in picked.take(1)) AssignedBranch(id: i.id, name: _branchName(i.label, mall), mallId: mall.id, mallName: mall.label)],
    ));
  }

  Widget _label(Pal p, String text, {bool required = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: ts(11, w: FontWeight.w700, color: p.ink))),
            if (required) Text(' *', style: ts(11, w: FontWeight.w700, color: p.brand)),
          ],
        ),
      );

  Widget _help(Pal p, String text, {bool warn = false}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: ts(11, color: warn ? p.warn : p.muted)),
      );

  List<Widget> _ownerFields(Pal p) => [
        _label(p, 'Whole malls', required: false),
        LookupPicker(
          lookup: 'malls',
          multi: true,
          selected: _d.malls,
          placeholder: 'Add malls…',
          onChanged: (v) => _emit(AssignmentDraft(malls: v, branches: _d.branches)),
        ),
        const SizedBox(height: 14),
        _label(p, 'Individual branches', required: false),
        LookupPicker(
          lookup: 'branches',
          multi: true,
          selected: [for (final b in _d.branches) LookupItem(id: b.id, label: b.label)],
          placeholder: 'Add branches…',
          onChanged: (v) => _emit(AssignmentDraft(malls: _d.malls, branches: [for (final i in v) AssignedBranch(id: i.id, name: i.label)])),
        ),
        _help(p, 'A whole-mall assignment also covers branches created later. Single branches do not. An owner can own branches in many malls.'),
        if (!_d.validFor(widget.role)) _help(p, 'Choose at least one mall or branch.', warn: true),
      ];

  List<Widget> _mallAdminFields(Pal p) {
    final mall = _d.mall;
    final enabled = mall != null && _mallHasBranches != false;
    return [
      _label(p, 'Mall'),
      LookupPicker(
        lookup: 'malls',
        selected: mall == null ? const [] : [mall],
        placeholder: 'Choose a mall…',
        onChanged: _pickMall,
      ),
      const SizedBox(height: 14),
      _label(p, 'Branch'),
      LookupPicker(
        key: AssignmentDialog.branchKey,
        lookup: 'branches',
        parentId: mall?.id,
        enabled: enabled,
        selected: [for (final b in _d.branches) LookupItem(id: b.id, label: b.name)],
        placeholder: mall == null ? 'Choose a mall first' : 'Choose the branch…',
        onChanged: _setBranch,
      ),
      if (_mallHasBranches == false)
        _help(
          p,
          widget.canCreateBranches ? 'This mall has no branches yet. Create one under Malls & branches first.' : 'This mall has no branches yet. Ask a superadmin to add one.',
          warn: true,
        )
      else
        _help(p, 'A mall admin manages exactly one branch. Picking another branch replaces it.'),
      if (!_d.validFor(widget.role)) _help(p, 'Choose the branch.', warn: true),
      if (widget.branchNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: widget.branchNote),
      _help(p, 'They report to the owner of this branch, or else to the mall\'s owner. This is set automatically.'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isOwner) ..._ownerFields(p) else ..._mallAdminFields(p),
        if (_error != null) _help(p, _error!, warn: true),
      ],
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/forms/wizard_dialog.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/detail_widgets.dart';
import 'account_checks.dart';
import 'accounts_service.dart';
import 'assignment_dialog.dart';

/// "Create account" as a step-by-step dialog (owner decisions 2026-10-22):
/// Role, Details, Access, Review, Done. Superadmins skip Access; a fixed role
/// skips Role. Email and name are checked while typing; the email must be
/// free, a repeated name or an email waiting in a profile change request only
/// warns. The temporary password shows on the last step.
///
/// Used by Account management (superadmin: any role; mall owner: mall admins)
/// and the mall page ("Create new" owner or admin).
Future<WizardOutcome<Account>?> runCreateAccountWizard(
  BuildContext context, {
  String? fixedRole,
  LookupItem? mall,
  List<LookupItem> initialMalls = const [],
  AccountsService? service,
  AccountCheckService? checks,
  BranchSearch? branchSearch,
}) =>
    showDialog<WizardOutcome<Account>>(
      context: context,
      barrierDismissible: false,
      barrierColor: context.pal.scrim,
      builder: (_) => CreateAccountWizard(
        fixedRole: fixedRole,
        mall: mall,
        initialMalls: initialMalls,
        service: service,
        checks: checks,
        branchSearch: branchSearch,
      ),
    );

enum _Step { role, details, access, review, done }

const _roleChoices = [
  ('supervisor', 'Mall owner', 'Owns whole malls or single branches. Manages the mall admins that report to them.'),
  ('mall_admin', 'Mall admin', 'Runs one branch: its stores, store owners, announcements and map.'),
  ('superadmin', 'Superadmin', 'Sees and changes everything, including other accounts. Only for trusted administrators.'),
];

class CreateAccountWizard extends StatefulWidget {
  const CreateAccountWizard({
    super.key,
    this.fixedRole,
    this.mall,
    this.initialMalls = const [],
    this.service,
    this.checks,
    this.branchSearch,
  });

  final String? fixedRole;
  final LookupItem? mall;
  final List<LookupItem> initialMalls;
  final AccountsService? service;
  final AccountCheckService? checks;
  final BranchSearch? branchSearch;

  static ValueKey<String> roleKey(String role) => ValueKey('wizard-role-$role');
  static const nextKey = ValueKey('wizard-next');
  static const backKey = ValueKey('wizard-back');

  @override
  State<CreateAccountWizard> createState() => _CreateAccountWizardState();
}

class _CreateAccountWizardState extends State<CreateAccountWizard> {
  late final AccountsService _service = widget.service ?? AccountsService();
  late final AccountCheckService _checks = widget.checks ?? AccountCheckService();

  late _Step _step = widget.fixedRole == null ? _Step.role : _Step.details;
  late String? _role = widget.fixedRole;
  String _name = '';
  String _email = '';
  AssignmentDraft? _draft;
  bool _touched = false;
  bool _busy = false;
  String? _error;
  String? _nameError;
  String? _emailError;

  /// Mall admin variant: who is already on a branch, by branch id.
  final Map<int, List<AccountMatch>> _branchAdmins = {};

  (Account, String)? _created;

  late final LiveCheck<EmailCheck> _emailCheck = LiveCheck<EmailCheck>(
    (v) async => looksLikeEmail(v) ? _checks.email(v.toLowerCase()) : null,
    _refresh,
  );
  late final LiveCheck<NameCheck> _nameCheck = LiveCheck<NameCheck>(
    (v) async => v.length >= 2 ? _checks.name(v) : null,
    _refresh,
  );

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailCheck.dispose();
    _nameCheck.dispose();
    super.dispose();
  }

  bool get _hasAccess => _role != 'superadmin';

  List<_Step> get _steps => [
        if (widget.fixedRole == null) _Step.role,
        _Step.details,
        if (_hasAccess) _Step.access,
        _Step.review,
        _Step.done,
      ];

  static const _labels = {_Step.role: 'Role', _Step.details: 'Details', _Step.access: 'Access', _Step.review: 'Review', _Step.done: 'Done'};

  AssignmentDraft get _currentDraft => _draft ??= AssignmentDraft.from(
        _role ?? 'mall_admin',
        AccountAssignments(malls: _role == 'supervisor' ? widget.initialMalls : const []),
        initialMall: widget.mall,
      );

  String get _roleLabel => roleLabels[_role] ?? (_role ?? '');

  // ---- moving between steps ----

  void _go(_Step s) => setState(() {
        _step = s;
        _error = null;
      });

  void _back() {
    final i = _steps.indexOf(_step);
    if (i > 0) _go(_steps[i - 1]);
  }

  Future<void> _next() async {
    switch (_step) {
      case _Step.role:
        if (_role != null) _go(_Step.details);
      case _Step.details:
        final nameErr = _nameSpec.validate(_name);
        final emailErr = _emailSpec.validate(_email);
        setState(() {
          _nameError = nameErr;
          _emailError = emailErr;
        });
        if (nameErr != null || emailErr != null) return;
        setState(() => _busy = true);
        await Future.wait([_emailCheck.flush(), _nameCheck.flush()]);
        if (!mounted) return;
        setState(() => _busy = false);
        if (_emailCheck.result?.blocks ?? false) return;
        _go(_hasAccess ? _Step.access : _Step.review);
      case _Step.access:
        if (_currentDraft.validFor(_role!)) _go(_Step.review);
      case _Step.review:
        await _create();
      case _Step.done:
        _finish();
    }
  }

  bool get _nextEnabled => switch (_step) {
        _Step.role => _role != null,
        _Step.details => !_busy && !_emailCheck.pending && !(_emailCheck.result?.blocks ?? false),
        _Step.access => _currentDraft.validFor(_role ?? ''),
        _Step.review => !_busy,
        _Step.done => true,
      };

  Future<void> _create() async {
    final role = _role!;
    if (role == 'superadmin') {
      final sure = await confirmDialog(
        context,
        title: 'Create another superadmin?',
        message: 'A superadmin can see and change everything on the platform, including other accounts. Only do this for a trusted administrator.',
        confirmLabel: 'Yes, create superadmin',
      );
      if (!sure || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = _currentDraft;
      final created = await _service.create(
        email: _email.trim().toLowerCase(),
        fullName: _name.trim(),
        role: role,
        mallIds: _hasAccess ? [for (final m in d.malls) m.id] : const [],
        branchIds: _hasAccess ? [for (final b in d.branches) b.id] : const [],
      );
      if (!mounted) return;
      setState(() {
        _created = created;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = formatApiError(e);
      final status = e is DioException ? e.response?.statusCode : null;
      setState(() {
        if (status == 409) {
          // Taken meanwhile (by someone else, a moment ago): back to the email.
          _emailError = msg;
          _step = _Step.details;
        } else if ((status == 400 || status == 403) && _hasAccess) {
          _step = _Step.access;
          _error = msg;
        } else {
          _error = msg;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- closing ----

  void _finish({bool open = false}) {
    final c = _created;
    Navigator.of(context).pop(WizardOutcome<Account>(created: c?.$1, openId: open ? c?.$1.id : null));
  }

  Future<bool> _confirmDiscard() async {
    if (!_touched) return true;
    return confirmDialog(
      context,
      title: 'Discard this account?',
      message: 'Nothing has been saved yet. What you entered will be lost.',
      confirmLabel: 'Discard',
    );
  }

  Future<void> _close() async {
    if (_step == _Step.done) return _finish();
    if (_busy) return;
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop();
  }

  Future<void> _openExisting(int id) async {
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop(WizardOutcome<Account>(openId: id));
  }

  // ---- steps ----

  static const _nameSpec = FieldSpec(name: 'fullName', label: 'Full name', required: true, maxLength: 200);
  static const _emailSpec = FieldSpec(name: 'email', label: 'Email address', kind: FieldKind.email, required: true, maxLength: 255, hint: 'name@company.com');

  Widget _roleStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (value, title, description) in _roleChoices)
            ChoiceCard(
              key: CreateAccountWizard.roleKey(value),
              title: title,
              description: description,
              caution: value == 'superadmin',
              selected: _role == value,
              onTap: () => setState(() {
                if (_role != value) _draft = null; // access differs per role
                _role = value;
                _touched = true;
              }),
            ),
        ],
      );

  Widget _detailsStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldBuilder(
            spec: _nameSpec,
            value: _name,
            error: _nameError,
            note: nameNote(_nameCheck),
            onChanged: (v) {
              _name = (v as String?) ?? '';
              _touched = true;
              _nameError = null;
              _nameCheck.update(_name);
            },
          ),
          FieldBuilder(
            spec: _emailSpec,
            value: _email,
            error: _emailError,
            note: emailNote(_emailCheck, onOpen: _openExisting),
            onChanged: (v) {
              _email = (v as String?) ?? '';
              _touched = true;
              _emailError = null;
              _emailCheck.update(_email);
            },
          ),
        ],
      );

  Future<void> _loadBranchAdmins(int branchId) async {
    if (_branchAdmins.containsKey(branchId)) return;
    try {
      final list = await _checks.branchAdmins(branchId);
      if (mounted) setState(() => _branchAdmins[branchId] = list);
    } catch (_) {
      // A hint only; the account can still be created.
    }
  }

  Widget? _branchNote() {
    final b = _currentDraft.branches.firstOrNull;
    if (_role != 'mall_admin' || b == null) return null;
    final list = _branchAdmins[b.id];
    if (list == null || list.isEmpty) return null;
    final names = list.map((a) => a.isActive ? a.fullName : '${a.fullName} (inactive)').join(', ');
    return CheckNote(NoteTone.info, 'This branch already has: $names. A branch can have more than one admin.');
  }

  Widget _accessStep() => AssignmentFields(
        key: ValueKey('access-$_role'),
        role: _role!,
        draft: _currentDraft,
        canCreateBranches: widget.fixedRole == null,
        branchSearch: widget.branchSearch ?? serverBranchSearch,
        branchNote: _branchNote(),
        onChanged: (d) {
          setState(() {
            _draft = d;
            _touched = true;
            _error = null;
          });
          final b = d.branches.firstOrNull;
          if (_role == 'mall_admin' && b != null) _loadBranchAdmins(b.id);
        },
      );

  Widget _reviewStep() {
    final p = context.pal;
    final d = _currentDraft;
    final notes = <Widget>[
      if (nameNote(_nameCheck) case final n?) n,
      if (_emailCheck.result?.state == 'pending_request') emailNote(_emailCheck)!,
      if (_branchNote() case final n?) n,
      if (_role == 'superadmin') const CheckNote(NoteTone.block, 'This person will see and change everything on the platform, including other accounts.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: p.boxBg, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              DetailRow('Role', _roleLabel),
              DetailRow('Full name', _name.trim()),
              DetailRow('Email', _email.trim().toLowerCase()),
              if (_role == 'supervisor') ...[
                DetailRow('Whole malls', d.malls.isEmpty ? 'None' : d.malls.map((m) => m.label).join(', ')),
                DetailRow('Branches', d.branches.isEmpty ? 'None' : d.branches.map((b) => b.label).join(', ')),
              ],
              if (_role == 'mall_admin') ...[
                DetailRow('Branch', d.branches.map((b) => b.label).join(', ')),
                const DetailRow('Reports to', 'The branch\'s owner, set automatically'),
              ],
            ],
          ),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 8), child: n),
        ],
      ],
    );
  }

  Widget _doneStep() {
    final c = _created!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckNote(NoteTone.ok, '${c.$1.fullName} can now sign in with ${c.$1.email} and this temporary password. They must change it at first sign-in.'),
        const SizedBox(height: 14),
        OneTimeSecretBox(c.$2),
      ],
    );
  }

  (String, String) get _texts => switch (_step) {
        _Step.role => ('Which kind of account?', 'The role decides what this person can see and change.'),
        _Step.details => ('Who is it for?', 'The email is their sign-in. A temporary password is made at the end.'),
        _Step.access => _role == 'supervisor'
            ? ('Which malls or branches do they own?', 'Pick whole malls, single branches, or both.')
            : ('Which branch do they manage?', 'A mall admin manages exactly one branch.'),
        _Step.review => ('Check and create', 'Nothing is saved until you press Create.'),
        _Step.done => ('Account created', ''),
      };

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final (heading, intro) = _texts;
    final body = switch (_step) {
      _Step.role => _roleStep(),
      _Step.details => _detailsStep(),
      _Step.access => _accessStep(),
      _Step.review => _reviewStep(),
      _Step.done => _doneStep(),
    };
    final first = _step == steps.first;
    final actions = _step == _Step.done
        ? [
            WizardButton(label: 'Open account', onPressed: () => _finish(open: true)),
            WizardButton(key: CreateAccountWizard.nextKey, label: 'Close', primary: true, onPressed: _finish),
          ]
        : [
            WizardButton(label: 'Cancel', onPressed: _close),
            if (!first) WizardButton(key: CreateAccountWizard.backKey, label: 'Back', icon: Icons.arrow_back, enabled: !_busy, onPressed: _back),
            WizardButton(
              key: CreateAccountWizard.nextKey,
              label: _step == _Step.review ? (_busy ? 'Creating…' : 'Create') : (_busy ? 'Checking…' : 'Next'),
              primary: true,
              enabled: _nextEnabled,
              onPressed: _next,
            ),
          ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: WizardFrame(
        title: widget.fixedRole == 'mall_admin'
            ? 'Create mall admin'
            : widget.fixedRole == 'supervisor'
                ? 'Create mall owner'
                : 'Create account',
        steps: [for (final s in steps) _labels[s]!],
        current: steps.indexOf(_step),
        heading: heading,
        intro: intro,
        body: body,
        actions: actions,
        error: _error,
        onClose: _close,
      ),
    );
  }
}

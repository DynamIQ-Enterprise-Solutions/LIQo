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
import '../accounts/account_checks.dart';
import 'stores_service.dart';

/// "Add store owner" as a step-by-step dialog (owner decisions 2026-10-22):
/// Store, Details, Review, Done. On a store's own page the store is known and
/// that step is skipped. The email is checked while typing: an active store
/// owner's email adds the store to them (no new password); an inactive store
/// owner is blocked until reactivated; any other account's email is refused.
Future<WizardOutcome<StoreOwner>?> runStoreOwnerWizard(
  BuildContext context, {
  LookupItem? store,
  StoresService? service,
  AccountCheckService? checks,
}) =>
    showDialog<WizardOutcome<StoreOwner>>(
      context: context,
      barrierDismissible: false,
      barrierColor: context.pal.scrim,
      builder: (_) => StoreOwnerWizard(store: store, service: service, checks: checks),
    );

enum _Step { store, details, review, done }

class StoreOwnerWizard extends StatefulWidget {
  const StoreOwnerWizard({super.key, this.store, this.service, this.checks});

  /// The store, when the wizard starts from that store's page.
  final LookupItem? store;
  final StoresService? service;
  final AccountCheckService? checks;

  static const nextKey = ValueKey('owner-wizard-next');

  @override
  State<StoreOwnerWizard> createState() => _StoreOwnerWizardState();
}

class _StoreOwnerWizardState extends State<StoreOwnerWizard> {
  late final StoresService _service = widget.service ?? StoresService();
  late final AccountCheckService _checks = widget.checks ?? AccountCheckService();

  late _Step _step = widget.store == null ? _Step.store : _Step.details;
  late List<LookupItem> _store = widget.store == null ? const [] : [widget.store!];
  String _name = '';
  String _email = '';
  bool _touched = false;
  bool _busy = false;
  String? _error;
  String? _storeError;
  String? _nameError;
  String? _emailError;
  (StoreOwner, String?)? _result;

  late final LiveCheck<EmailCheck> _emailCheck = LiveCheck<EmailCheck>(
    (v) async => looksLikeEmail(v) ? _checks.email(v.toLowerCase(), purpose: 'store_owner') : null,
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

  /// The email belongs to an active store owner: the store is added to them.
  bool get _existing => _emailCheck.result?.state == 'store_owner';
  String get _existingName => _emailCheck.result?.account?.fullName ?? 'the existing owner';

  List<_Step> get _steps => [if (widget.store == null) _Step.store, _Step.details, _Step.review, _Step.done];

  static const _labels = {_Step.store: 'Store', _Step.details: 'Details', _Step.review: 'Review', _Step.done: 'Done'};

  static const _storeSpec = FieldSpec(name: 'store', label: 'Store', kind: FieldKind.lookup, lookup: 'stores', required: true, hint: 'Choose a store…');
  static const _nameSpec = FieldSpec(name: 'fullName', label: 'Full name', required: true, maxLength: 200);
  static const _emailSpec = FieldSpec(name: 'email', label: 'Email address', kind: FieldKind.email, required: true, maxLength: 255, hint: 'name@company.com');

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
      case _Step.store:
        final err = _storeSpec.validate(_store);
        setState(() => _storeError = err);
        if (err == null) _go(_Step.details);
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
        _go(_Step.review);
      case _Step.review:
        await _save();
      case _Step.done:
        _finish();
    }
  }

  bool get _nextEnabled => switch (_step) {
        _Step.store => true,
        _Step.details => !_busy && !_emailCheck.pending && !(_emailCheck.result?.blocks ?? false),
        _Step.review => !_busy,
        _Step.done => true,
      };

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _service.createOwner(email: _email.trim().toLowerCase(), fullName: _name.trim(), storeId: _store.first.id);
      if (!mounted) return;
      setState(() {
        _result = r;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = formatApiError(e);
      final status = e is DioException ? e.response?.statusCode : null;
      setState(() {
        if (status == 409) {
          _emailError = msg;
          _step = _Step.details;
        } else {
          _error = msg;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish({bool open = false}) {
    final r = _result;
    Navigator.of(context).pop(WizardOutcome<StoreOwner>(created: r?.$1, openId: open ? r?.$1.id : null));
  }

  Future<bool> _confirmDiscard() async {
    if (!_touched) return true;
    return confirmDialog(
      context,
      title: 'Discard this store owner?',
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
    if (await _confirmDiscard() && mounted) Navigator.of(context).pop(WizardOutcome<StoreOwner>(openId: id));
  }

  Widget _storeStep() => FieldBuilder(
        spec: _storeSpec,
        value: _store,
        error: _storeError,
        onChanged: (v) => setState(() {
          _store = (v as List<LookupItem>?) ?? const [];
          _storeError = null;
          _touched = true;
        }),
      );

  Widget _detailsStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldBuilder(
            spec: _nameSpec,
            value: _name,
            error: _nameError,
            note: _existing ? null : nameNote(_nameCheck),
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
            note: emailNote(_emailCheck, storeOwner: true, onOpen: _openExisting),
            onChanged: (v) {
              _email = (v as String?) ?? '';
              _touched = true;
              _emailError = null;
              _emailCheck.update(_email);
            },
          ),
        ],
      );

  Widget _reviewStep() {
    final p = context.pal;
    final notes = <Widget>[
      if (_existing) CheckNote(NoteTone.info, 'This store is added to $_existingName\'s account. No new password is made.'),
      if (!_existing)
        if (nameNote(_nameCheck) case final n?) n,
      if (_emailCheck.result?.state == 'pending_request') emailNote(_emailCheck, storeOwner: true)!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: p.boxBg, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              DetailRow('Store', _store.firstOrNull?.label),
              DetailRow('Owner', _existing ? '$_existingName (existing store owner)' : _name.trim()),
              DetailRow('Email', _email.trim().toLowerCase()),
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
    final (owner, temp) = _result!;
    final store = _store.firstOrNull?.label ?? 'the store';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (temp == null)
          CheckNote(NoteTone.ok, '${owner.fullName} now owns $store too. They keep their current password.')
        else ...[
          CheckNote(NoteTone.ok, '${owner.fullName} can now sign in with ${owner.email} and this temporary password. They must change it at first sign-in.'),
          const SizedBox(height: 14),
          OneTimeSecretBox(temp),
        ],
      ],
    );
  }

  (String, String) get _texts => switch (_step) {
        _Step.store => ('Which store?', 'The owner gets access to this store only. You can add more stores later.'),
        _Step.details => ('Who is the owner?', 'The email is their sign-in. If they already own a store, use the same email.'),
        _Step.review => ('Check and ${_existing ? 'add' : 'create'}', 'Nothing is saved until you press ${_existing ? 'Add store' : 'Create'}.'),
        _Step.done => (_result?.$2 == null ? 'Store added' : 'Store owner created', ''),
      };

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final (heading, intro) = _texts;
    final body = switch (_step) {
      _Step.store => _storeStep(),
      _Step.details => _detailsStep(),
      _Step.review => _reviewStep(),
      _Step.done => _doneStep(),
    };
    final first = _step == steps.first;
    final primary = switch (_step) {
      _Step.review => _busy ? 'Saving…' : (_existing ? 'Add store' : 'Create'),
      _ => _busy ? 'Checking…' : 'Next',
    };
    final actions = _step == _Step.done
        ? [
            WizardButton(label: 'Open store owner', onPressed: () => _finish(open: true)),
            WizardButton(key: StoreOwnerWizard.nextKey, label: 'Close', primary: true, onPressed: _finish),
          ]
        : [
            WizardButton(label: 'Cancel', onPressed: _close),
            if (!first) WizardButton(label: 'Back', icon: Icons.arrow_back, enabled: !_busy, onPressed: _back),
            WizardButton(key: StoreOwnerWizard.nextKey, label: primary, primary: true, enabled: _nextEnabled, onPressed: _next),
          ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: WizardFrame(
        title: widget.store == null ? 'Add store owner' : 'Add an owner to ${widget.store!.label}',
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

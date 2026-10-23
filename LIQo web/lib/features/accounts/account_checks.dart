import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/api_client.dart';
import '../../shared/forms/wizard_dialog.dart';
import 'accounts_service.dart';

/// An account a check matched. Name and role come only when the server shows
/// them (to a superadmin, or a store owner to a mall admin).
class AccountMatch {
  const AccountMatch({required this.id, required this.fullName, required this.role, required this.isActive});

  final int id;
  final String fullName;
  final String role;
  final bool isActive;

  factory AccountMatch.fromJson(Map<String, dynamic> j) => AccountMatch(
        id: j['id'] as int,
        fullName: j['fullName'] as String? ?? '',
        role: j['role'] as String? ?? '',
        isActive: j['isActive'] as bool? ?? true,
      );

  String get roleLabel => roleLabels[role] ?? role;
}

/// `free`, `taken`, `inactive`, `pending_request`, `store_owner` (store-owner
/// wizard: an active store owner, the store is added to them) or `invalid`.
class EmailCheck {
  const EmailCheck({required this.state, this.account, this.canOpen = false});

  final String state;
  final AccountMatch? account;
  final bool canOpen;

  bool get blocks => state == 'taken' || state == 'inactive';

  factory EmailCheck.fromJson(Map<String, dynamic> j) => EmailCheck(
        state: j['state'] as String,
        account: j['account'] == null ? null : AccountMatch.fromJson(j['account'] as Map<String, dynamic>),
        canOpen: j['canOpen'] as bool? ?? false,
      );
}

class NameCheck {
  const NameCheck({required this.count, this.matches = const []});

  final int count;
  final List<AccountMatch> matches;

  factory NameCheck.fromJson(Map<String, dynamic> j) => NameCheck(
        count: j['count'] as int? ?? 0,
        matches: [for (final m in (j['matches'] as List? ?? const [])) AccountMatch.fromJson(m as Map<String, dynamic>)],
      );
}

/// `GET /accounts/check`: the live checks of the create wizards.
class AccountCheckService {
  AccountCheckService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<Map<String, dynamic>> _get(Map<String, Object> q) async => (await _client.dio.get('/accounts/check', queryParameters: q)).data as Map<String, dynamic>;

  Future<EmailCheck> email(String email, {String purpose = 'account'}) async => EmailCheck.fromJson((await _get({'email': email, 'purpose': purpose}))['email'] as Map<String, dynamic>);

  Future<NameCheck> name(String fullName) async => NameCheck.fromJson((await _get({'fullName': fullName}))['name'] as Map<String, dynamic>);

  Future<List<AccountMatch>> branchAdmins(int branchId) async {
    final list = (await _get({'branchId': branchId}))['branchAdmins'] as List? ?? const [];
    return [
      for (final m in list) AccountMatch.fromJson({...(m as Map<String, dynamic>), 'role': 'mall_admin'})
    ];
  }
}

final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool looksLikeEmail(String s) => _emailShape.hasMatch(s.trim());

/// Runs a check about half a second after the value stops changing, keeps
/// only the answer for the latest value, and can be forced with [flush].
class LiveCheck<T> {
  LiveCheck(this._run, this._onUpdate, {this.delay = const Duration(milliseconds: 450)});

  /// Returns null when the value is not worth checking (empty, malformed).
  final Future<T?> Function(String value) _run;
  final VoidCallback _onUpdate;
  final Duration delay;

  Timer? _timer;
  Future<void>? _running;
  int _seq = 0;
  String _value = '';
  bool _disposed = false;

  /// Waiting for the pause or for the server.
  bool pending = false;
  T? result;
  String? error;

  String get value => _value;

  void update(String value) {
    final v = value.trim();
    if (v == _value) return;
    _value = v;
    _timer?.cancel();
    result = null;
    error = null;
    final seq = ++_seq;
    pending = v.isNotEmpty;
    _onUpdate();
    if (v.isEmpty) return;
    _timer = Timer(delay, () => _running = _go(seq));
  }

  /// Runs a waiting check now and waits for the answer.
  Future<void> flush() async {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      _running = _go(_seq);
    }
    final r = _running;
    if (r != null) await r;
  }

  Future<void> _go(int seq) async {
    try {
      final r = await _run(_value);
      if (seq != _seq || _disposed) return;
      result = r;
    } catch (e) {
      if (seq != _seq || _disposed) return;
      error = formatApiError(e);
    } finally {
      if (seq == _seq && !_disposed) {
        pending = false;
        _onUpdate();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// The line under the email field. [storeOwner]: the store-owner wizard.
/// [onOpen] opens the matching account, when the server allows it.
Widget? emailNote(LiveCheck<EmailCheck> c, {bool storeOwner = false, void Function(int id)? onOpen}) {
  if (c.pending) return const CheckNote(NoteTone.checking, 'Checking this email…');
  if (c.error != null) return CheckNote(NoteTone.info, 'Could not check this email now (${c.error}). It is checked again when you create.');
  final r = c.result;
  if (r == null) return null;
  final a = r.account;
  final open = a != null && r.canOpen && onOpen != null ? () => onOpen(a.id) : null;
  final openLabel = storeOwner ? 'Open store owner' : 'Open account';
  switch (r.state) {
    case 'free':
      return const CheckNote(NoteTone.ok, 'Available.');
    case 'taken':
      return a == null
          ? const CheckNote(NoteTone.block, 'This email is already in use.')
          : CheckNote(NoteTone.block, 'Already used by ${a.fullName} (${a.roleLabel}).', actionLabel: openLabel, onAction: open);
    case 'inactive':
      if (a == null) return const CheckNote(NoteTone.block, 'This email belongs to an inactive account.');
      return storeOwner
          ? CheckNote(NoteTone.block, 'This store owner is inactive: ${a.fullName}. Reactivate them from Store owners first, then add the store there.', actionLabel: openLabel, onAction: open)
          : CheckNote(NoteTone.block, 'Belongs to an inactive account: ${a.fullName} (${a.roleLabel}). Reactivate it from its page instead.', actionLabel: openLabel, onAction: open);
    case 'store_owner':
      return CheckNote(
          NoteTone.info, 'Already a store owner: ${a?.fullName ?? 'an existing account'}. Creating adds this store to their account. No new password is made, and the name typed here is not used.');
    case 'pending_request':
      return const CheckNote(NoteTone.warn, "This email is waiting in someone's profile change request. If you continue, that request will fail when it is approved.");
  }
  return null;
}

/// The line under the full-name field: names may repeat, so this only warns.
Widget? nameNote(LiveCheck<NameCheck> c) {
  final r = c.result;
  if (c.pending || r == null || r.count == 0) return null;
  const tail = 'Names may repeat; make sure it is not the same person.';
  if (r.matches.isEmpty) {
    return CheckNote(NoteTone.warn, r.count == 1 ? 'Another account already has this name. $tail' : '${r.count} accounts already have this name. $tail');
  }
  final who = r.matches.map((m) => '${m.fullName} (${m.roleLabel}${m.isActive ? '' : ', inactive'})').join(', ');
  return CheckNote(NoteTone.warn, r.count == 1 ? 'Another account is named $who. $tail' : '${r.count} accounts already have this name: $who${r.count > r.matches.length ? ', …' : ''}. $tail');
}

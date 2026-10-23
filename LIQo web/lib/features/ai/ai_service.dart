import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// The gateway wallet behind AI reading (Round 15). Any number may be missing;
/// [dailyCap] is null when the gateway sets no daily credit cap.
class AiQuota {
  const AiQuota({this.balance, this.usedToday, this.dailyCap, this.full, this.blocked = false, this.reason, this.given, this.free, this.overGiven});

  final double? balance;
  final double? usedToday;
  final double? dailyCap;

  /// The balance right after the last top-up: the credit bar's full mark (Round 18 follow-up).
  final double? full;

  /// Round 19 (superadmin only): credits mall admins hold and have not used,
  /// what is free to give, and how far the wallet is below what was given.
  final double? given;
  final double? free;
  final double? overGiven;

  /// The gateway refuses AI calls right now (empty wallet or cap reached), with its own [reason].
  final bool blocked;
  final String? reason;

  static double? _n(Object? v) => v is num ? v.toDouble() : null;

  factory AiQuota.fromJson(Map<String, dynamic> j) => AiQuota(
        balance: _n(j['balance']),
        usedToday: _n(j['usedToday']),
        dailyCap: _n(j['dailyCap']),
        full: _n(j['full']),
        given: _n(j['given']),
        free: _n(j['free']),
        overGiven: _n(j['overGiven']),
        blocked: j['blocked'] == true,
        reason: j['reason'] as String?,
      );

  bool get isEmpty => balance == null && usedToday == null && dailyCap == null && !blocked;

  /// Share of the last top-up still left, 0–1, when both are known.
  double? get leftShare => balance == null || full == null
      ? null
      : full! <= 0
          ? 0
          : (balance! / full!).clamp(0.0, 1.0);

  /// Share of today's cap already used, 0–1, when both are known.
  double? get usedShare => usedToday == null || dailyCap == null || dailyCap! <= 0 ? null : (usedToday! / dailyCap!).clamp(0.0, 1.0);
}

/// Is AI reading ready: a key on the server and a model chosen by a superadmin;
/// for a mall admin also credits of their own (Round 19).
class AiStatus {
  const AiStatus({required this.configured, this.model, this.quota, this.quotaError, this.mine, this.gatewayBlocked = false});

  final bool configured;
  final String? model;

  /// The gateway wallet (superadmins only; null for mall admins).
  final AiQuota? quota;
  final String? quotaError;

  /// A mall admin's own credits (balance and the last top-up), never the wallet's numbers.
  final AiQuota? mine;

  /// The gateway refuses readings right now (told to mall admins without numbers).
  final bool gatewayBlocked;

  bool get outOfCredits => mine != null && (mine!.balance ?? 0) <= 0;

  bool get ready => configured && model != null && !(quota?.blocked ?? false) && !gatewayBlocked && !outOfCredits;

  /// Why reading is not possible yet, in words, or null when it is.
  String? get blocker => !configured
      ? 'AI reading is not set up yet. A superadmin must add the IQGateway key on the server.'
      : model == null
          ? 'No AI model is chosen yet. A superadmin chooses it in Settings.'
          : gatewayBlocked
              ? 'The AI service is not accepting readings right now. A superadmin has been shown why.'
              : outOfCredits
                  ? 'You have no AI credits left. Ask a superadmin for more.'
                  : null;

  factory AiStatus.fromJson(Map<String, dynamic> j) => AiStatus(
        configured: j['configured'] == true,
        model: (j['model'] as String?)?.trim().isEmpty ?? true ? null : j['model'] as String,
        quota: j['quota'] == null ? null : AiQuota.fromJson(j['quota'] as Map<String, dynamic>),
        quotaError: j['quotaError'] as String?,
        mine: j['mine'] == null ? null : AiQuota.fromJson(j['mine'] as Map<String, dynamic>),
        gatewayBlocked: j['gatewayBlocked'] == true,
      );
}

/// A model that can read plans (the server lists only available chat models).
class AiModel {
  const AiModel({required this.id, String? label, this.provider}) : label = label ?? id;

  final String id;
  final String label;
  final String? provider;

  factory AiModel.fromJson(Map<String, dynamic> j) => AiModel(id: j['id'] as String, label: j['label'] as String?, provider: j['provider'] as String?);
}

/// The browser only talks to our server; the gateway key stays there.
class AiService {
  AiService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<AiStatus> status() async => AiStatus.fromJson((await _client.dio.get('/ai/status')).data as Map<String, dynamic>);

  Future<(List<AiModel>, String?)> models() async {
    final d = (await _client.dio.get('/ai/models')).data as Map<String, dynamic>;
    return ((d['items'] as List<dynamic>).map((e) => AiModel.fromJson(e as Map<String, dynamic>)).toList(), d['current'] as String?);
  }

  Future<void> setModel(String model) async => _client.dio.put('/ai/model', data: {'model': model});
}

final aiStatusProvider = FutureProvider.autoDispose<AiStatus>((ref) => AiService().status());

final aiModelsProvider = FutureProvider.autoDispose<(List<AiModel>, String?)>((ref) => AiService().models());

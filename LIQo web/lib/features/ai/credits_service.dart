import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../shared/models/paged.dart';

// AI credits per mall admin (Round 19, owner decisions 2026-10-23). A balance
// is a share of the IQGateway wallet set aside for one mall admin; giving
// credits moves no money, the wallet only goes down when a reading is paid.

double? _n(Object? v) => v is num ? v.toDouble() : null;
double _d(Object? v) => v is num ? v.toDouble() : 0;
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v');
Map<String, dynamic> _m(Object? v) => v as Map<String, dynamic>;

/// The superadmin's view of the wallet.
class WalletSplit {
  const WalletSplit({this.wallet, required this.given, this.free, required this.used, this.overGiven, this.full});

  /// The gateway balance; null when it could not be read.
  final double? wallet;

  /// What admins hold and have not used.
  final double given;
  final double? free;

  /// Used by readings in the chosen period.
  final double used;

  /// How far the wallet is below what was given (0 when it is not).
  final double? overGiven;

  /// The wallet right after the last top-up (the bar's full width), when known.
  final double? full;

  bool get isOverGiven => (overGiven ?? 0) > 0;

  factory WalletSplit.fromJson(Map<String, dynamic> j) =>
      WalletSplit(wallet: _n(j['wallet']), given: _d(j['given']), free: _n(j['free']), used: _d(j['used']), overGiven: _n(j['overGiven']), full: _n(j['full']));
}

/// A credit request from a mall admin (an amount, no reason).
class CreditRequest {
  const CreditRequest({
    required this.id,
    required this.userId,
    required this.user,
    this.email,
    this.branch,
    required this.balance,
    required this.amount,
    required this.status,
    this.decidedAmount,
    this.decidedBy,
    this.declineReason,
    required this.createdAt,
    this.decidedAt,
    this.userActive = true,
  });

  final int id;
  final int userId;
  final String user;
  final String? email;
  final String? branch;
  final double balance;
  final double amount;
  final String status;
  final double? decidedAmount;
  final String? decidedBy;
  final String? declineReason;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final bool userActive;

  bool get pending => status == 'pending';

  factory CreditRequest.fromJson(Map<String, dynamic> j) => CreditRequest(
        id: j['id'] as int,
        userId: j['userId'] as int,
        user: j['user'] as String? ?? '',
        email: j['email'] as String?,
        branch: j['branch'] as String?,
        balance: _d(j['balance']),
        amount: _d(j['amount']),
        status: j['status'] as String,
        decidedAmount: _n(j['decidedAmount']),
        decidedBy: j['decidedBy'] as String?,
        declineReason: j['declineReason'] as String?,
        createdAt: _t(j['createdAt']) ?? DateTime.now(),
        decidedAt: _t(j['decidedAt']),
        userActive: j['userActive'] != false,
      );
}

/// A request with what the superadmin needs to decide it.
class CreditRequestDetail {
  const CreditRequestDetail({required this.request, this.free, this.overGiven, required this.cap, required this.room});

  final CreditRequest request;
  final double? free;
  final double? overGiven;
  final double cap;

  /// How much more this admin may hold under the cap.
  final double room;

  factory CreditRequestDetail.fromJson(Map<String, dynamic> j) {
    final l = _m(j['limits']);
    return CreditRequestDetail(request: CreditRequest.fromJson(_m(j['request'])), free: _n(l['free']), overGiven: _n(l['overGiven']), cap: _d(l['cap']), room: _d(l['room']));
  }
}

/// A mall admin's credits and use.
class CreditAdmin {
  const CreditAdmin({required this.id, required this.name, this.email, this.branch, required this.balance, this.full, required this.used, required this.readings, this.lastReading});

  final int id;
  final String name;
  final String? email;
  final String? branch;
  final double balance;
  final double? full;
  final double used;
  final int readings;
  final DateTime? lastReading;

  factory CreditAdmin.fromJson(Map<String, dynamic> j) => CreditAdmin(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        email: j['email'] as String?,
        branch: j['branch'] as String?,
        balance: _d(j['balance']),
        full: _n(j['full']),
        used: _d(j['used']),
        readings: (j['readings'] as num?)?.toInt() ?? 0,
        lastReading: _t(j['lastReading']),
      );
}

class UsagePoint {
  const UsagePoint(this.day, this.credits, this.readings);

  final DateTime day;
  final double credits;
  final int readings;
}

/// The Analytics credits section's data.
class CreditsOverview {
  const CreditsOverview({required this.days, required this.cap, this.wallet, required this.admins, required this.usageTotal, required this.series, this.waiting});

  final int days;
  final double cap;

  /// Superadmins only.
  final WalletSplit? wallet;
  final List<CreditAdmin> admins;
  final double usageTotal;
  final List<UsagePoint> series;

  /// Open requests (superadmins only).
  final int? waiting;

  factory CreditsOverview.fromJson(Map<String, dynamic> j) {
    final usage = _m(j['usage']);
    return CreditsOverview(
      days: j['days'] as int,
      cap: _d(j['cap']),
      wallet: j['wallet'] == null ? null : WalletSplit.fromJson(_m(j['wallet'])),
      admins: [for (final a in j['admins'] as List<dynamic>) CreditAdmin.fromJson(_m(a))],
      usageTotal: _d(usage['total']),
      series: [
        for (final p in usage['series'] as List<dynamic>) UsagePoint(_t(_m(p)['day']) ?? DateTime.now(), _d(_m(p)['credits']), (_m(p)['readings'] as num?)?.toInt() ?? 0),
      ],
      waiting: j['requests'] == null ? null : (_m(j['requests'])['waiting'] as num?)?.toInt(),
    );
  }
}

/// One change to someone's credits.
class LedgerEntry {
  const LedgerEntry({required this.id, required this.user, required this.delta, required this.balanceAfter, required this.kind, this.note, this.actor, required this.createdAt});

  final int id;
  final String user;
  final double delta;
  final double balanceAfter;
  final String kind;
  final String? note;
  final String? actor;
  final DateTime createdAt;

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: j['id'] as int,
        user: j['user'] as String? ?? '',
        delta: _d(j['delta']),
        balanceAfter: _d(j['balanceAfter']),
        kind: j['kind'] as String,
        note: j['note'] as String?,
        actor: j['actor'] as String?,
        createdAt: _t(j['createdAt']) ?? DateTime.now(),
      );
}

/// Plain words for a ledger row's kind.
const ledgerKindLabels = {
  'start': 'Starting credits',
  'grant': 'Given',
  'remove': 'Taken back',
  'reading': 'Plan reading',
  'returned': 'Returned (deactivated)',
  'request': 'Request approved',
};

/// The signed-in mall admin's own credits.
class MyCredits {
  const MyCredits({required this.balance, this.full, required this.cap, this.avgCost, this.request});

  final double balance;
  final double? full;
  final double cap;

  /// The average paid reading lately (for the low-balance warning).
  final double? avgCost;
  final CreditRequest? request;

  /// How much more they may ask for under the cap.
  double get room => (cap - (balance > 0 ? balance : 0)).clamp(0, double.infinity).toDouble();

  factory MyCredits.fromJson(Map<String, dynamic> j) => MyCredits(
        balance: _d(j['balance']),
        full: _n(j['full']),
        cap: _d(j['cap']),
        avgCost: _n(j['avgCost']),
        request: j['request'] == null ? null : CreditRequest.fromJson(_m(j['request'])),
      );
}

/// What waits for a superadmin on Requests & reports.
class RequestCounts {
  const RequestCounts({required this.profile, required this.credits, required this.reports, required this.total});

  final int profile;
  final int credits;
  final int reports;
  final int total;

  static const zero = RequestCounts(profile: 0, credits: 0, reports: 0, total: 0);

  factory RequestCounts.fromJson(Map<String, dynamic> j) =>
      RequestCounts(profile: j['profile'] as int? ?? 0, credits: j['credits'] as int? ?? 0, reports: j['reports'] as int? ?? 0, total: j['total'] as int? ?? 0);
}

class CreditsService {
  CreditsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<CreditsOverview> overview(int days) async => CreditsOverview.fromJson(_m((await _client.dio.get('/ai/credits/overview', queryParameters: {'days': days})).data));

  Future<PagedResult<LedgerEntry>> history(ListQuery q) async => PagedResult.fromJson(_m((await _client.dio.get('/ai/credits/history', queryParameters: q.toParams())).data), LedgerEntry.fromJson);

  /// Gives (positive) or takes back (negative) credits. Returns the balance after.
  Future<double> adjust(int userId, double delta, {String? note}) async =>
      _d(_m((await _client.dio.post('/ai/credits/$userId/adjust', data: {'delta': delta, if (note != null && note.trim().isNotEmpty) 'note': note.trim()})).data)['balance']);

  Future<MyCredits> mine() async => MyCredits.fromJson(_m((await _client.dio.get('/ai/credits/mine')).data));

  Future<CreditRequest> request(double amount) async => CreditRequest.fromJson(_m(_m((await _client.dio.post('/ai/credits/requests', data: {'amount': amount})).data)['request']));

  Future<void> cancelRequest() async => _client.dio.delete('/ai/credits/requests/mine');

  Future<PagedResult<CreditRequest>> requests(ListQuery q) async =>
      PagedResult.fromJson(_m((await _client.dio.get('/ai/credits/requests', queryParameters: q.toParams())).data), CreditRequest.fromJson);

  Future<CreditRequestDetail> requestDetail(int id) async => CreditRequestDetail.fromJson(_m((await _client.dio.get('/ai/credits/requests/$id')).data));

  Future<void> approve(int id, double amount) async => _client.dio.post('/ai/credits/requests/$id/approve', data: {'amount': amount});

  Future<void> decline(int id, {String? reason}) async => _client.dio.post('/ai/credits/requests/$id/decline', data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});

  Future<RequestCounts> counts() async => RequestCounts.fromJson(_m((await _client.dio.get('/requests/counts')).data));
}

final myCreditsProvider = FutureProvider.autoDispose<MyCredits>((ref) => CreditsService().mine());

final creditsOverviewProvider = FutureProvider.autoDispose.family<CreditsOverview, int>((ref, days) => CreditsService().overview(days));

/// The superadmin's waiting items, for the sidebar count and the tabs.
/// Invalidate after deciding anything on Requests & reports.
final requestCountsProvider = FutureProvider.autoDispose<RequestCounts>((ref) => CreditsService().counts());

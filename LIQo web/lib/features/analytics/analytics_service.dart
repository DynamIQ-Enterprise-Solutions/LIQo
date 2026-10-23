import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _d(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
Map<String, int> _counts(Map<String, dynamic>? j) => {for (final e in (j ?? {}).entries) e.key: _i(e.value)};

/// One day of the activity chart.
class ActivityDay {
  const ActivityDay({
    required this.date,
    required this.logins,
    required this.submitted,
    required this.published,
    required this.mapPublications,
    required this.mapEdits,
    required this.failedLogins,
    required this.lockouts,
  });

  final String date;
  final int logins;
  final int submitted;
  final int published;
  final int mapPublications;
  final int mapEdits;
  final int failedLogins;
  final int lockouts;

  factory ActivityDay.fromJson(Map<String, dynamic> j) => ActivityDay(
        date: j['date'] as String,
        logins: _i(j['logins']),
        submitted: _i(j['submitted']),
        published: _i(j['published']),
        mapPublications: _i(j['mapPublications']),
        mapEdits: _i(j['mapEdits']),
        failedLogins: _i(j['failedLogins']),
        lockouts: _i(j['lockouts']),
      );
}

class Activity {
  const Activity({required this.days, required this.totals, required this.previous});

  final List<ActivityDay> days;

  /// Totals for the period, keyed like [ActivityDay] fields.
  final Map<String, int> totals;

  /// Totals for the period before it, for comparison.
  final Map<String, int> previous;

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        days: [for (final d in j['days'] as List<dynamic>) ActivityDay.fromJson(d as Map<String, dynamic>)],
        totals: _counts(j['totals'] as Map<String, dynamic>?),
        previous: _counts(j['previous'] as Map<String, dynamic>?),
      );
}

class NamedCount {
  const NamedCount({required this.name, required this.count});

  final String name;
  final int count;
}

class StoreBranchRow {
  const StoreBranchRow({
    required this.branchId,
    required this.branch,
    required this.mall,
    required this.active,
    required this.inactive,
    required this.withOwner,
    required this.linked,
  });

  final int branchId;
  final String branch;
  final String mall;
  final int active;
  final int inactive;
  final int withOwner;
  final int linked;

  factory StoreBranchRow.fromJson(Map<String, dynamic> j) => StoreBranchRow(
        branchId: _i(j['branchId']),
        branch: j['branch'] as String,
        mall: j['mall'] as String,
        active: _i(j['active']),
        inactive: _i(j['inactive']),
        withOwner: _i(j['withOwner']),
        linked: _i(j['linked']),
      );
}

class StoresReport {
  const StoresReport({required this.byCategory, required this.byBranch});

  final List<NamedCount> byCategory;
  final List<StoreBranchRow> byBranch;

  int get total => byBranch.fold(0, (n, b) => n + b.active);

  factory StoresReport.fromJson(Map<String, dynamic> j) => StoresReport(
        byCategory: [for (final c in j['byCategory'] as List<dynamic>) NamedCount(name: c['name'] as String, count: _i(c['count']))],
        byBranch: [for (final b in j['byBranch'] as List<dynamic>) StoreBranchRow.fromJson(b as Map<String, dynamic>)],
      );
}

class RoleRow {
  const RoleRow({
    required this.role,
    required this.total,
    required this.active,
    required this.inactive,
    required this.unassigned,
    required this.tempPassword,
    required this.locked,
  });

  final String role;
  final int total;
  final int active;
  final int inactive;
  final int unassigned;
  final int tempPassword;
  final int locked;

  factory RoleRow.fromJson(Map<String, dynamic> j) => RoleRow(
        role: j['role'] as String,
        total: _i(j['total']),
        active: _i(j['active']),
        inactive: _i(j['inactive']),
        unassigned: _i(j['unassigned']),
        tempPassword: _i(j['tempPassword']),
        locked: _i(j['locked']),
      );
}

class AccountsReport {
  const AccountsReport({required this.byRole});

  final List<RoleRow> byRole;

  factory AccountsReport.fromJson(Map<String, dynamic> j) => AccountsReport(byRole: [for (final r in j['byRole'] as List<dynamic>) RoleRow.fromJson(r as Map<String, dynamic>)]);
}

class PendingItem {
  const PendingItem({
    required this.id,
    required this.title,
    required this.role,
    required this.author,
    this.store,
    this.branches,
    this.createdAt,
    required this.waitingDays,
  });

  final int id;
  final String title;
  final String role;
  final String author;
  final String? store;
  final String? branches;
  final DateTime? createdAt;
  final int waitingDays;

  factory PendingItem.fromJson(Map<String, dynamic> j) => PendingItem(
        id: _i(j['id']),
        title: j['title'] as String,
        role: j['role'] as String,
        author: j['author'] as String? ?? '',
        store: j['store'] as String?,
        branches: j['branches'] as String?,
        createdAt: _d(j['createdAt']),
        waitingDays: _i(j['waitingDays']),
      );
}

class AnnouncementBranchRow {
  const AnnouncementBranchRow({required this.branchId, required this.branch, required this.mall, required this.live, required this.pending, required this.total});

  final int branchId;
  final String branch;
  final String mall;
  final int live;
  final int pending;
  final int total;

  factory AnnouncementBranchRow.fromJson(Map<String, dynamic> j) => AnnouncementBranchRow(
        branchId: _i(j['branchId']),
        branch: j['branch'] as String,
        mall: j['mall'] as String,
        live: _i(j['live']),
        pending: _i(j['pending']),
        total: _i(j['total']),
      );
}

class AnnouncementsReport {
  const AnnouncementsReport({
    required this.byStatus,
    required this.byTimeState,
    required this.bySource,
    required this.byBranch,
    required this.pending,
    required this.decided,
    this.avgDecisionDays,
  });

  final Map<String, int> byStatus;
  final Map<String, int> byTimeState;
  final List<NamedCount> bySource;
  final List<AnnouncementBranchRow> byBranch;
  final List<PendingItem> pending;
  final int decided;
  final double? avgDecisionDays;

  factory AnnouncementsReport.fromJson(Map<String, dynamic> j) => AnnouncementsReport(
        byStatus: _counts(j['byStatus'] as Map<String, dynamic>?),
        byTimeState: _counts(j['byTimeState'] as Map<String, dynamic>?),
        bySource: [for (final s in j['bySource'] as List<dynamic>) NamedCount(name: s['role'] as String, count: _i(s['count']))],
        byBranch: [for (final b in j['byBranch'] as List<dynamic>) AnnouncementBranchRow.fromJson(b as Map<String, dynamic>)],
        pending: [for (final p in j['pending'] as List<dynamic>) PendingItem.fromJson(p as Map<String, dynamic>)],
        decided: _i(j['decided']),
        avgDecisionDays: (j['avgDecisionDays'] as num?)?.toDouble(),
      );
}

class MapBranchRow {
  const MapBranchRow({
    required this.branchId,
    required this.branch,
    required this.mall,
    required this.state,
    required this.versions,
    this.publishedVersion,
    this.publishedAt,
    this.publishedBy,
    this.lastEditedAt,
    required this.spaces,
    required this.named,
    required this.linked,
  });

  final int branchId;
  final String branch;
  final String mall;

  /// 'none', 'draft' or 'published'.
  final String state;
  final int versions;
  final int? publishedVersion;
  final DateTime? publishedAt;
  final String? publishedBy;
  final DateTime? lastEditedAt;
  final int spaces;
  final int named;
  final int linked;

  factory MapBranchRow.fromJson(Map<String, dynamic> j) => MapBranchRow(
        branchId: _i(j['branchId']),
        branch: j['branch'] as String,
        mall: j['mall'] as String,
        state: j['state'] as String,
        versions: _i(j['versions']),
        publishedVersion: (j['publishedVersion'] as num?)?.toInt(),
        publishedAt: _d(j['publishedAt']),
        publishedBy: j['publishedBy'] as String?,
        lastEditedAt: _d(j['lastEditedAt']),
        spaces: _i(j['spaces']),
        named: _i(j['named']),
        linked: _i(j['linked']),
      );
}

class MapsReport {
  const MapsReport({required this.summary, required this.byBranch});

  final Map<String, int> summary;
  final List<MapBranchRow> byBranch;

  factory MapsReport.fromJson(Map<String, dynamic> j) => MapsReport(
        summary: _counts(j['summary'] as Map<String, dynamic>?),
        byBranch: [for (final b in j['byBranch'] as List<dynamic>) MapBranchRow.fromJson(b as Map<String, dynamic>)],
      );
}

class SecurityReport {
  const SecurityReport({required this.topFailures});

  final List<NamedCount> topFailures;

  factory SecurityReport.fromJson(Map<String, dynamic> j) =>
      SecurityReport(topFailures: [for (final t in j['topFailures'] as List<dynamic>) NamedCount(name: t['email'] as String, count: _i(t['count']))]);
}

class AnalyticsReport {
  const AnalyticsReport({
    required this.days,
    required this.activity,
    required this.stores,
    required this.accounts,
    required this.announcements,
    required this.maps,
    this.security,
    this.note,
  });

  final int days;
  final Activity activity;
  final StoresReport stores;
  final AccountsReport accounts;
  final AnnouncementsReport announcements;
  final MapsReport maps;

  /// Superadmin only.
  final SecurityReport? security;
  final String? note;

  factory AnalyticsReport.fromJson(Map<String, dynamic> j) => AnalyticsReport(
        days: _i(j['days']),
        activity: Activity.fromJson(j['activity'] as Map<String, dynamic>),
        stores: StoresReport.fromJson(j['stores'] as Map<String, dynamic>),
        accounts: AccountsReport.fromJson(j['accounts'] as Map<String, dynamic>),
        announcements: AnnouncementsReport.fromJson(j['announcements'] as Map<String, dynamic>),
        maps: MapsReport.fromJson(j['maps'] as Map<String, dynamic>),
        security: j['security'] == null ? null : SecurityReport.fromJson(j['security'] as Map<String, dynamic>),
        note: j['note'] as String?,
      );
}

class AnalyticsService {
  AnalyticsService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<AnalyticsReport> report(int days) async {
    final r = await _client.dio.get('/analytics/report', queryParameters: {'days': days});
    return AnalyticsReport.fromJson(r.data as Map<String, dynamic>);
  }
}

/// One report per period length; switching the period fetches the other one.
final analyticsReportProvider = FutureProvider.autoDispose.family<AnalyticsReport, int>((ref, days) => AnalyticsService().report(days));

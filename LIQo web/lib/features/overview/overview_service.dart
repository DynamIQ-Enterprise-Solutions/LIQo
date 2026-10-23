import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class OverviewCounts {
  const OverviewCounts({
    required this.accounts,
    required this.malls,
    required this.branches,
    required this.stores,
    required this.logins7d,
    this.liveAnnouncements = 0,
    this.pendingAnnouncements = 0,
    this.mapPublications = 0,
  });

  final int accounts;
  final int malls;
  final int branches;
  final int stores;
  final int logins7d;
  final int liveAnnouncements;
  final int pendingAnnouncements;

  /// Published map versions in scope.
  final int mapPublications;

  factory OverviewCounts.fromJson(Map<String, dynamic> j) => OverviewCounts(
        accounts: j['accounts'] as int? ?? 0,
        malls: j['malls'] as int? ?? 0,
        branches: j['branches'] as int? ?? 0,
        stores: j['stores'] as int? ?? 0,
        logins7d: j['logins7d'] as int? ?? 0,
        liveAnnouncements: j['liveAnnouncements'] as int? ?? 0,
        pendingAnnouncements: j['pendingAnnouncements'] as int? ?? 0,
        mapPublications: j['mapPublications'] as int? ?? 0,
      );
}

class RecentActivity {
  const RecentActivity({required this.actorEmail, required this.action, required this.createdAt});

  final String? actorEmail;
  final String action;
  final DateTime createdAt;

  factory RecentActivity.fromJson(Map<String, dynamic> j) => RecentActivity(
        actorEmail: j['actorEmail'] as String?,
        action: j['action'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class OverviewData {
  const OverviewData({required this.counts, required this.recent});

  final OverviewCounts counts;
  final List<RecentActivity> recent;
}

class OverviewService {
  OverviewService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<OverviewData> fetch() async {
    final r = await _client.dio.get('/analytics/overview');
    final data = r.data as Map<String, dynamic>;
    return OverviewData(
      counts: OverviewCounts.fromJson(data['counts'] as Map<String, dynamic>),
      recent: (data['recent'] as List<dynamic>).map((e) => RecentActivity.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

final overviewProvider = FutureProvider.autoDispose<OverviewData>((ref) => OverviewService().fetch());

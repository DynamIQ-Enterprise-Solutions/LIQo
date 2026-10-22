import 'package:intl/intl.dart';

import '../accounts/accounts_service.dart' show roleLabels;
import 'analytics_service.dart';

/// Quotes a cell the way Excel expects: wrap in quotes when it holds a comma,
/// a quote or a line break; double any quotes inside.
String csvCell(Object? value) {
  final s = value == null ? '' : value.toString();
  if (s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

String buildCsv(List<List<Object?>> rows) => rows.map((r) => r.map(csvCell).join(',')).join('\r\n');

String _date(DateTime? d) => d == null ? '' : DateFormat('yyyy-MM-dd').format(d);

const _mapState = {'none': 'No map', 'draft': 'Draft only', 'published': 'Published'};

/// The breakdown tables of the Analytics page as one CSV: blank line and a title row between tables.
String reportCsv(AnalyticsReport r) {
  final rows = <List<Object?>>[
    ['LIQo analytics', 'last ${r.days} days'],
    [],
    ['Activity by day'],
    ['Date', 'Sign-ins', 'Announcements submitted', 'Announcements published', 'Map publications', 'Map editing sessions', 'Failed sign-ins', 'Lockouts'],
    for (final d in r.activity.days) [d.date, d.logins, d.submitted, d.published, d.mapPublications, d.mapEdits, d.failedLogins, d.lockouts],
    [],
    ['Stores by category'],
    ['Category', 'Stores'],
    for (final c in r.stores.byCategory) [c.name, c.count],
    [],
    ['Stores per branch'],
    ['Branch', 'Mall', 'Active', 'Inactive', 'With owner', 'Linked to map', 'Not linked'],
    for (final b in r.stores.byBranch) [b.branch, b.mall, b.active, b.inactive, b.withOwner, b.linked, b.active - b.linked],
    [],
    ['Accounts by role'],
    ['Role', 'Total', 'Active', 'Inactive', 'Unassigned', 'Temp password', 'Locked'],
    for (final a in r.accounts.byRole) [roleLabels[a.role] ?? a.role, a.total, a.active, a.inactive, a.unassigned, a.tempPassword, a.locked],
    [],
    ['Announcements'],
    ['Pending', 'Approved', 'Rejected', 'Live', 'Upcoming', 'Expired', 'Decided in period', 'Average days to decision'],
    [
      r.announcements.byStatus['pending'] ?? 0,
      r.announcements.byStatus['approved'] ?? 0,
      r.announcements.byStatus['rejected'] ?? 0,
      r.announcements.byTimeState['live'] ?? 0,
      r.announcements.byTimeState['upcoming'] ?? 0,
      r.announcements.byTimeState['expired'] ?? 0,
      r.announcements.decided,
      r.announcements.avgDecisionDays ?? '',
    ],
    [],
    ['Announcements per branch'],
    ['Branch', 'Mall', 'Live', 'Pending', 'Total'],
    for (final b in r.announcements.byBranch) [b.branch, b.mall, b.live, b.pending, b.total],
    [],
    ['Pending queue'],
    ['Title', 'From', 'Author', 'Store', 'Branches', 'Submitted', 'Waiting days'],
    for (final p in r.announcements.pending) [p.title, roleLabels[p.role] ?? p.role, p.author, p.store ?? '', p.branches ?? '', _date(p.createdAt), p.waitingDays],
    [],
    ['Map coverage'],
    ['Branch', 'Mall', 'State', 'Versions', 'Published version', 'Published on', 'Published by', 'Spaces', 'Named', 'Linked to a store'],
    for (final m in r.maps.byBranch)
      [m.branch, m.mall, _mapState[m.state] ?? m.state, m.versions, m.publishedVersion ?? '', _date(m.publishedAt), m.publishedBy ?? '', m.spaces, m.named, m.linked],
  ];
  final sec = r.security;
  if (sec != null) {
    rows.addAll([
      [],
      ['Sign-in failures (top accounts)'],
      ['Email', 'Failures'],
      for (final f in sec.topFailures) [f.name, f.count],
    ]);
  }
  return buildCsv(rows);
}

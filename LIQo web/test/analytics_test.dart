// Round 3 (Analytics): charts show an empty state or render with data, the
// period switch asks for the chosen number of days, and the CSV is quoted right.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gabay_admin/core/session.dart';
import 'package:gabay_admin/core/theme.dart';
import 'package:gabay_admin/features/analytics/analytics_service.dart';
import 'package:gabay_admin/features/analytics/analytics_view.dart';
import 'package:gabay_admin/features/analytics/charts.dart';
import 'package:gabay_admin/features/analytics/csv_export.dart';
import 'package:gabay_admin/features/overview/overview_service.dart';

Widget _wrap(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 900, child: child))));

AnalyticsReport _sample(int days) {
  final dayRows = [
    for (var i = 0; i < days; i++)
      {'date': '2026-10-${(i % 28 + 1).toString().padLeft(2, '0')}', 'logins': i % 3, 'submitted': 0, 'published': 1, 'mapPublications': 0, 'mapEdits': 2, 'failedLogins': 0, 'lockouts': 0},
  ];
  return AnalyticsReport.fromJson({
    'days': days,
    'activity': {
      'days': dayRows,
      'totals': {'logins': 5, 'submitted': 0, 'published': days, 'mapPublications': 0, 'mapEdits': 2 * days},
      'previous': {'logins': 2, 'submitted': 1, 'published': 0, 'mapPublications': 0, 'mapEdits': 0},
    },
    'stores': {
      'byCategory': [
        {'name': 'Apparel', 'count': 3},
        {'name': 'No category', 'count': 1},
      ],
      'byBranch': [
        {'branchId': 1, 'branch': 'SM Mall of Asia', 'mall': 'SM Prime', 'active': 4, 'inactive': 1, 'withOwner': 2, 'linked': 1},
      ],
    },
    'accounts': {
      'byRole': [
        {'role': 'mall_admin', 'total': 2, 'active': 2, 'inactive': 0, 'unassigned': 1, 'tempPassword': 1, 'locked': 0},
      ],
    },
    'announcements': {
      'byStatus': {'pending': 1, 'approved': 2, 'rejected': 0},
      'byTimeState': {'live': 1, 'upcoming': 1, 'expired': 0},
      'bySource': [
        {'role': 'store_owner', 'count': 1},
        {'role': 'mall_admin', 'count': 2},
      ],
      'byBranch': [
        {'branchId': 1, 'branch': 'SM Mall of Asia', 'mall': 'SM Prime', 'live': 1, 'pending': 1, 'total': 3},
      ],
      'pending': [
        {'id': 9, 'title': 'Sale', 'role': 'store_owner', 'author': 'Owner One', 'store': 'Northline', 'branches': 'SM Mall of Asia', 'createdAt': '2026-10-20T08:00:00', 'waitingDays': 1},
      ],
      'decided': 2,
      'avgDecisionDays': 0.5,
    },
    'maps': {
      'summary': {'none': 0, 'draft': 0, 'published': 1},
      'byBranch': [
        {'branchId': 1, 'branch': 'SM Mall of Asia', 'mall': 'SM Prime', 'state': 'published', 'versions': 2, 'publishedVersion': 2, 'publishedAt': '2026-10-21T10:00:00', 'publishedBy': 'Mall Admin', 'spaces': 5, 'named': 4, 'linked': 1},
      ],
    },
    'security': {
      'topFailures': [
        {'email': 'x@y.z', 'count': 3},
      ],
    },
    'note': 'No shopper app yet.',
  });
}

void main() {
  testWidgets('donut shows an empty state without data and a pie with data', (tester) async {
    await tester.pumpWidget(_wrap(const DonutChart(slices: [], emptyText: 'No stores yet.')));
    expect(find.text('No stores yet.'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);

    await tester.pumpWidget(_wrap(const DonutChart(slices: [ChartSlice(name: 'A', value: 3, color: Colors.red), ChartSlice(name: 'B', value: 1, color: Colors.blue)])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PieChart), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3 · 75%'), findsOneWidget);
  });

  testWidgets('line chart shows an empty state when every value is zero and renders otherwise', (tester) async {
    await tester.pumpWidget(_wrap(const LineSeriesChart(dates: ['2026-10-01', '2026-10-02'], series: [ChartSeries(name: 'S', values: [0, 0], color: Colors.red)])));
    expect(find.text('No activity in this period.'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);

    await tester.pumpWidget(_wrap(const LineSeriesChart(dates: ['2026-10-01', '2026-10-02', '2026-10-03'], series: [ChartSeries(name: 'S', values: [1, 4, 2], color: Colors.red)])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('the period switch asks the service for the chosen days', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final seen = <int>[];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        overviewProvider.overrideWith((ref) async => const OverviewData(counts: OverviewCounts(accounts: 1, malls: 1, branches: 1, stores: 1, logins7d: 1), recent: [])),
        analyticsReportProvider.overrideWith((ref, days) {
          seen.add(days);
          return _sample(days);
        }),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(child: SizedBox(width: 1300, child: AnalyticsView()))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(seen, [7], reason: '7 days is the default');
    expect(find.text('Activity over time'), findsOneWidget);
    expect(find.text('Sign-in security'), findsOneWidget, reason: 'the sample has a security section');

    await tester.tap(find.byKey(const ValueKey('period-30')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(seen.last, 30);
    expect(find.text('Per day, last 30 days'), findsOneWidget);
  });

  test('CSV cells are quoted when they hold commas, quotes or line breaks', () {
    expect(buildCsv([
      ['plain', 'has, comma', 'has "quote"', 'two\nlines', 7, null],
    ]), 'plain,"has, comma","has ""quote""","two\nlines",7,');
    expect(buildCsv([
      ['a', 'b'],
      ['c', 'd'],
    ]), 'a,b\r\nc,d');
  });

  test('the report CSV has every table and the security block when present', () {
    final csv = reportCsv(_sample(7));
    for (final title in ['Activity by day', 'Stores by category', 'Stores per branch', 'Accounts by role', 'Announcements', 'Pending queue', 'Map coverage', 'Sign-in failures (top accounts)']) {
      expect(csv.contains(title), isTrue, reason: title);
    }
    expect(csv.contains('SM Mall of Asia,SM Prime,4,1,2,1,3'), isTrue, reason: 'not linked = active - linked');
  });
}

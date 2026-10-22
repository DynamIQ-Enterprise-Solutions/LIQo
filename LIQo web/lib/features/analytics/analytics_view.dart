import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/reveal_on_scroll.dart';
import '../../shared/widgets/skeleton.dart';
import '../accounts/accounts_service.dart' show roleLabels;
import '../overview/overview_service.dart';
import 'analytics_service.dart';
import 'charts.dart';
import 'csv_download.dart';
import 'csv_export.dart';

const _periods = [7, 30, 90];
const _mapStateLabel = {'none': 'No map', 'draft': 'Draft only', 'published': 'Published'};

/// Summary cards, then charts and breakdowns per section. Everything is
/// scoped by the server; the period switch drives the time-based parts.
class AnalyticsView extends ConsumerStatefulWidget {
  const AnalyticsView({super.key});

  @override
  ConsumerState<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends ConsumerState<AnalyticsView> {
  int _days = 7;
  static final _date = DateFormat('MMM d, yyyy');

  void _export(AnalyticsReport? r) {
    final m = ref.read(messagesProvider.notifier);
    if (r == null) {
      m.show('Wait for the report to load, then export.');
      return;
    }
    final name = 'liqo-analytics-${r.days}d-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    downloadText(name, reportCsv(r));
    m.showSuccess('Downloaded $name');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final nav = navForRole(ref.watch(currentUserProvider)?.role ?? 'store_owner');
    final overview = ref.watch(overviewProvider);
    final report = ref.watch(analyticsReportProvider(_days));
    final tablet = Bp.isTablet(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: '${nav.name} / Analytics',
          title: nav.role == 'superadmin' ? 'Platform analytics' : 'Analytics',
          subtitle: 'Counts for your scope; deactivated records are left out. Time charts cover the chosen period.',
          actions: [
            _PeriodSwitch(days: _days, onChanged: (d) => setState(() => _days = d)),
            AppButton(label: 'Export CSV', icon: Icons.download_outlined, onPressed: () => _export(report.valueOrNull)),
            AppButton(
              label: 'Refresh',
              icon: Icons.refresh,
              onPressed: () {
                ref.invalidate(overviewProvider);
                ref.invalidate(analyticsReportProvider);
              },
            ),
          ],
        ),
        overview.when(
          loading: () => Shimmer(child: GridRows(columns: tablet ? 2 : 4, spacing: 14, children: List.generate(tablet ? 4 : 8, (_) => const SkeletonStatCard()))),
          error: (e, _) => AppCard(padding: const EdgeInsets.all(20), child: Text(formatApiError(e), style: ts(12, color: p.warn))),
          data: (d) => GridRows(
            columns: tablet ? 2 : 4,
            spacing: 14,
            children: [
              _Tile(label: 'Active malls', value: d.counts.malls, icon: Icons.storefront_outlined),
              _Tile(label: 'Active branches', value: d.counts.branches, icon: Icons.location_on_outlined),
              _Tile(label: 'Active stores', value: d.counts.stores, icon: Icons.category_outlined),
              _Tile(label: 'Active accounts', value: d.counts.accounts, icon: Icons.person_outline),
              _Tile(label: 'Sign-ins, last 7 days', value: d.counts.logins7d, icon: Icons.login),
              _Tile(label: 'Live announcements', value: d.counts.liveAnnouncements, icon: Icons.campaign_outlined),
              _Tile(label: 'Announcements pending review', value: d.counts.pendingAnnouncements, icon: Icons.hourglass_top),
              _Tile(label: 'Map publications', value: d.counts.mapPublications, icon: Icons.layers_outlined),
            ],
          ),
        ),
        const SizedBox(height: 18),
        report.when(
          // Each section keeps its place while the report is on the way.
          loading: () => const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(child: SkeletonChart(height: 220)),
                SizedBox(height: 18),
                _SideBySide(
                  left: SkeletonCard(child: SkeletonRows(count: 3)),
                  right: SkeletonCard(child: SkeletonChart(height: 150)),
                ),
                SizedBox(height: 18),
                SkeletonCard(child: SkeletonRows(count: 4)),
                SizedBox(height: 18),
                SkeletonCard(child: SkeletonRows(count: 4)),
              ],
            ),
          ),
          error: (e, _) => AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not load the report', style: ts(14, w: FontWeight.w700, color: p.ink)),
                const SizedBox(height: 6),
                Text(formatApiError(e), style: ts(12, color: p.muted)),
                const SizedBox(height: 12),
                AppButton(label: 'Try again', primary: true, onPressed: () => ref.invalidate(analyticsReportProvider(_days))),
              ],
            ),
          ),
          data: (r) => _Sections(
            report: r,
            dateFormat: _date,
            announcementsPath: nav.items.where((i) => i.id == 'announcements').firstOrNull?.path,
          ),
        ),
      ],
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.report, required this.dateFormat, this.announcementsPath});

  final AnalyticsReport report;
  final DateFormat dateFormat;

  /// Where pending-review rows open (the role's announcements page), if any.
  final String? announcementsPath;

  Widget _card({required String title, required String subtitle, required Widget child}) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [CardHead(title: title, subtitle: subtitle), CardBody(child: child)],
        ),
      );

  String _d(DateTime? d) => d == null ? '—' : dateFormat.format(d);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = report;
    final c = p.chart;
    Color col(int i) => c[i % c.length];

    // --- Activity ---
    final a = r.activity;
    final dates = [for (final d in a.days) d.date];
    final activitySeries = [
      ChartSeries(name: 'Sign-ins', values: [for (final d in a.days) d.logins], color: col(0)),
      ChartSeries(name: 'Announcements submitted', values: [for (final d in a.days) d.submitted], color: col(1)),
      ChartSeries(name: 'Announcements published', values: [for (final d in a.days) d.published], color: col(2)),
      ChartSeries(name: 'Map publications', values: [for (final d in a.days) d.mapPublications], color: col(3)),
      ChartSeries(name: 'Map editing sessions', values: [for (final d in a.days) d.mapEdits], color: col(4)),
    ];
    const activityKeys = ['logins', 'submitted', 'published', 'mapPublications', 'mapEdits'];

    // --- Stores ---
    final s = r.stores;
    final categorySlices = [for (var i = 0; i < s.byCategory.length; i++) ChartSlice(name: s.byCategory[i].name, value: s.byCategory[i].count, color: col(i))];
    final storeBars = [
      for (final b in s.byBranch)
        HBarItem(label: b.branch, sub: b.mall, segments: [
          ChartSlice(name: 'Active', value: b.active, color: col(0)),
          ChartSlice(name: 'Inactive', value: b.inactive, color: p.faint),
        ]),
    ];

    // --- Accounts ---
    final roleSlices = [for (var i = 0; i < r.accounts.byRole.length; i++) ChartSlice(name: roleLabels[r.accounts.byRole[i].role] ?? r.accounts.byRole[i].role, value: r.accounts.byRole[i].total, color: col(i))];

    // --- Announcements ---
    final an = r.announcements;
    final statusBars = [
      ChartSlice(name: 'Pending', value: an.byStatus['pending'] ?? 0, color: p.warn),
      ChartSlice(name: 'Approved', value: an.byStatus['approved'] ?? 0, color: p.green),
      ChartSlice(name: 'Rejected', value: an.byStatus['rejected'] ?? 0, color: p.faint),
    ];
    final timeBars = [
      ChartSlice(name: 'Live', value: an.byTimeState['live'] ?? 0, color: col(0)),
      ChartSlice(name: 'Upcoming', value: an.byTimeState['upcoming'] ?? 0, color: col(1)),
      ChartSlice(name: 'Expired', value: an.byTimeState['expired'] ?? 0, color: p.faint),
    ];
    final sourceSlices = [for (var i = 0; i < an.bySource.length; i++) ChartSlice(name: roleLabels[an.bySource[i].name] ?? an.bySource[i].name, value: an.bySource[i].count, color: col(i + 1))];

    // --- Maps ---
    final m = r.maps;
    final mapBars = [
      ChartSlice(name: 'Published', value: m.summary['published'] ?? 0, color: p.green),
      ChartSlice(name: 'Draft only', value: m.summary['draft'] ?? 0, color: p.warn),
      ChartSlice(name: 'No map', value: m.summary['none'] ?? 0, color: p.faint),
    ];

    final sec = r.security;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          title: 'Activity over time',
          subtitle: 'Per day, last ${r.days} days',
          child: RevealOnScroll(
            builder: (context, shown) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LineSeriesChart(dates: dates, series: activitySeries, shown: shown),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < activityKeys.length; i++)
                      DeltaStat(
                        label: activitySeries[i].name,
                        value: a.totals[activityKeys[i]] ?? 0,
                        previous: a.previous[activityKeys[i]] ?? 0,
                        color: activitySeries[i].color,
                        shown: shown,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _SideBySide(
          left: _card(
            title: 'Stores per branch',
            subtitle: '${s.total} active stores',
            child: RevealOnScroll(builder: (context, shown) => HBarList(items: storeBars, emptyText: 'No branches in your scope.', shown: shown)),
          ),
          right: _card(
            title: 'Stores by category',
            subtitle: 'Active stores only',
            child: RevealOnScroll(builder: (context, shown) => DonutChart(slices: categorySlices, emptyText: 'No stores yet.', shown: shown)),
          ),
        ),
        const SizedBox(height: 18),
        _card(
          title: 'Store readiness per branch',
          subtitle: 'A store is ready for the shopper app once it has an owner and a place on the map',
          child: BreakdownTable(
            columns: const ['Branch', 'Mall', 'Active', 'Inactive', 'With owner', 'Linked to map', 'Not linked'],
            numericFrom: 2,
            rows: [
              for (final b in s.byBranch) [b.branch, b.mall, '${b.active}', '${b.inactive}', '${b.withOwner}', '${b.linked}', '${b.active - b.linked}'],
            ],
            emptyText: 'No branches in your scope.',
          ),
        ),
        const SizedBox(height: 18),
        _card(
          title: 'Accounts',
          subtitle: 'By role, with what needs attention',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RevealOnScroll(builder: (context, shown) => DonutChart(slices: roleSlices, emptyText: 'No accounts in your scope.', shown: shown)),
              const SizedBox(height: 16),
              BreakdownTable(
                columns: const ['Role', 'Total', 'Active', 'Inactive', 'Unassigned', 'Temp password', 'Locked now'],
                rows: [
                  for (final x in r.accounts.byRole) [roleLabels[x.role] ?? x.role, '${x.total}', '${x.active}', '${x.inactive}', '${x.unassigned}', '${x.tempPassword}', '${x.locked}'],
                ],
                emptyText: 'No accounts in your scope.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SideBySide(
          left: _card(
            title: 'Announcements',
            subtitle: 'All time, in your scope',
            child: RevealOnScroll(
              builder: (context, shown) => Wrap(
                spacing: 24,
                runSpacing: 16,
                children: [
                  SizedBox(width: 260, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('By status', style: ts(11, w: FontWeight.w700, color: p.muted)), const SizedBox(height: 6), CategoryBars(items: statusBars, shown: shown)])),
                  SizedBox(width: 260, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Approved, by time', style: ts(11, w: FontWeight.w700, color: p.muted)), const SizedBox(height: 6), CategoryBars(items: timeBars, shown: shown)])),
                ],
              ),
            ),
          ),
          right: _card(
            title: 'Who posts',
            subtitle: 'Announcements by author role',
            child: RevealOnScroll(builder: (context, shown) => DonutChart(slices: sourceSlices, emptyText: 'No announcements yet.', shown: shown)),
          ),
        ),
        const SizedBox(height: 18),
        _card(
          title: 'Pending review',
          subtitle: an.decided == 0
              ? 'Nothing was decided in the last ${r.days} days'
              : '${an.decided} decided in the last ${r.days} days, average ${an.avgDecisionDays ?? 0} days to a decision',
          child: BreakdownTable(
            columns: const ['Title', 'From', 'Store / branches', 'Submitted', 'Waiting'],
            numericFrom: 4,
            widths: const [220, 200, 200, 110, 80],
            rows: [
              for (final q in an.pending) [q.title, '${roleLabels[q.role] ?? q.role} · ${q.author}', q.store ?? q.branches ?? '—', _d(q.createdAt), '${q.waitingDays} d'],
            ],
            emptyText: 'Nothing is waiting for review.',
            // Each waiting item opens the announcement (Round 14).
            onRowTap: announcementsPath == null ? null : (i) => context.go('$announcementsPath/${an.pending[i].id}'),
          ),
        ),
        const SizedBox(height: 18),
        _card(
          title: 'Announcements per branch',
          subtitle: 'Live now and waiting',
          child: BreakdownTable(
            columns: const ['Branch', 'Mall', 'Live', 'Pending', 'All time'],
            numericFrom: 2,
            rows: [for (final b in an.byBranch) [b.branch, b.mall, '${b.live}', '${b.pending}', '${b.total}']],
            emptyText: 'No branches in your scope.',
          ),
        ),
        const SizedBox(height: 18),
        _card(
          title: 'Map coverage',
          subtitle: 'Which branches shoppers can navigate',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 320, child: RevealOnScroll(builder: (context, shown) => CategoryBars(items: mapBars, emptyText: 'No branches in your scope.', shown: shown))),
              const SizedBox(height: 16),
              BreakdownTable(
                columns: const ['Branch', 'Mall', 'State', 'Versions', 'Published', 'Spaces', 'Named', 'Linked to a store'],
                numericFrom: 3,
                widths: const [200, 120, 100, 80, 260, 80, 80, 130],
                rows: [
                  for (final b in m.byBranch)
                    [
                      b.branch,
                      b.mall,
                      _mapStateLabel[b.state] ?? b.state,
                      '${b.versions}',
                      b.publishedAt == null ? '—' : 'v${b.publishedVersion} · ${_d(b.publishedAt)}${b.publishedBy == null ? '' : ' · ${b.publishedBy}'}',
                      '${b.spaces}',
                      '${b.named}',
                      '${b.linked}',
                    ],
                ],
                emptyText: 'No branches in your scope.',
              ),
            ],
          ),
        ),
        if (sec != null) ...[
          const SizedBox(height: 18),
          _SideBySide(
            left: _card(
              title: 'Sign-in security',
              subtitle: 'Failed sign-ins and lockouts per day',
              child: RevealOnScroll(
                builder: (context, shown) => LineSeriesChart(
                  dates: dates,
                  height: 160,
                  emptyText: 'No failed sign-ins in this period.',
                  shown: shown,
                  series: [
                    ChartSeries(name: 'Failed sign-ins', values: [for (final d in a.days) d.failedLogins], color: p.warn),
                    ChartSeries(name: 'Lockouts', values: [for (final d in a.days) d.lockouts], color: col(5)),
                  ],
                ),
              ),
            ),
            right: _card(
              title: 'Most failures',
              subtitle: 'Accounts with the most failed sign-ins',
              child: BreakdownTable(
                columns: const ['Email', 'Failures'],
                widths: const [240, 90],
                rows: [for (final f in sec.topFailures) [f.name, '${f.count}']],
                emptyText: 'No failed sign-ins in this period.',
              ),
            ),
          ),
        ],
        if (r.note != null) ...[
          const SizedBox(height: 14),
          Text(r.note!, style: ts(11, color: p.muted)),
        ],
      ],
    );
  }
}

/// Two cards side by side on wide screens, stacked on tablets. Unlike the
/// shared TwoCol it does not use IntrinsicHeight, which charts and tables
/// cannot be measured by.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (Bp.isTablet(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 18), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 145, child: left),
        const SizedBox(width: 18),
        Expanded(flex: 100, child: right),
      ],
    );
  }
}

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final d in _periods)
          Padding(
            padding: EdgeInsets.zero,
            child: Material(
              key: ValueKey('period-$d'),
              color: d == days ? p.soft : p.panel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: d == days ? p.brand : p.fieldLine)),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(d),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  child: Text('$d days', style: ts(12, w: FontWeight.w600, color: d == days ? p.brand2 : p.btnText)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: ts(12, color: p.statNote))),
              Icon(icon, size: 18, color: p.brand),
            ],
          ),
          const SizedBox(height: 8),
          Text('$value', style: ts(24, w: FontWeight.w800, color: p.ink, ls: -0.8, height: 1.2)),
        ],
      ),
    );
  }
}

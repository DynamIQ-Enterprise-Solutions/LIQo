import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import '../accounts/accounts_service.dart' show roleLabels;
import '../account/profile_service.dart';
import '../ai/credit_bar.dart';
import '../ai/credits_service.dart';
import '../profile_requests/profile_requests_view.dart';
import '../reports/reports_service.dart';

// Requests & reports (Round 19, owner decisions 2026-10-23): what people ask
// of or tell the superadmin, grouped in tabs with their waiting counts:
// profile changes, AI credit requests and problem reports. Rows open the
// item's own page.

enum RequestsTab { all, profile, credits, reports }

RequestsTab requestsTabFrom(String? q) => RequestsTab.values.firstWhere((t) => t.name == q, orElse: () => RequestsTab.all);

final _when = DateFormat('MMM d, yyyy h:mm a');

/// A credit request's status as a pill.
class CreditRequestPill extends StatelessWidget {
  const CreditRequestPill(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => switch (status) {
        'pending' => const Pill('Waiting', kind: PillKind.pending),
        'approved' => const Pill('Approved', kind: PillKind.green),
        'declined' => const Pill('Declined', kind: PillKind.off),
        _ => const Pill('Cancelled', kind: PillKind.off),
      };
}

/// A problem report's status as a pill.
class ReportStatusPill extends StatelessWidget {
  const ReportStatusPill(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) => switch (status) {
        'new' => const Pill('New', kind: PillKind.pending),
        'in_progress' => const Pill('In progress', kind: PillKind.blue),
        'resolved' => const Pill('Resolved', kind: PillKind.green),
        _ => const Pill('Closed', kind: PillKind.off),
      };
}

class RequestsView extends ConsumerStatefulWidget {
  const RequestsView({super.key, this.initialTab = RequestsTab.all});

  final RequestsTab initialTab;

  @override
  ConsumerState<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends ConsumerState<RequestsView> {
  late RequestsTab _tab = widget.initialTab;

  void _go(RequestsTab t) {
    setState(() => _tab = t);
    // Keep the tab in the address, so Back from a request returns to it.
    context.go('/superadmin/requests?tab=${t.name}');
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(requestCountsProvider).valueOrNull ?? RequestCounts.zero;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHead(
          eyebrow: 'Superadmin / Requests & reports',
          title: 'Requests & reports',
          subtitle: 'What people ask of you or tell you: profile changes, AI credits and problem reports. Click a row to open it.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (t, label, n) in [
              (RequestsTab.all, 'All', counts.total),
              (RequestsTab.profile, 'Profile changes', counts.profile),
              (RequestsTab.credits, 'AI credits', counts.credits),
              (RequestsTab.reports, 'Problem reports', counts.reports),
            ])
              _TabChip(key: ValueKey('requests-tab-${t.name}'), label: label, count: n, active: _tab == t, onTap: () => _go(t)),
          ],
        ),
        const SizedBox(height: 16),
        switch (_tab) {
          RequestsTab.all => const _AllWaiting(),
          RequestsTab.profile => const ProfileRequestsList(),
          RequestsTab.credits => const _CreditRequestsList(),
          RequestsTab.reports => const _ReportsList(),
        },
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({super.key, required this.label, required this.count, required this.active, required this.onTap});

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: active ? p.soft : p.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: active ? p.brand : p.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: active ? p.brand2 : p.slate))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: count > 0 ? p.brand : p.fieldLine, borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: ts(11, w: FontWeight.w800, color: count > 0 ? p.avatarFg : p.muted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything waiting, newest first, across the kinds.
class _AllWaiting extends ConsumerWidget {
  const _AllWaiting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final data = ref.watch(_allWaitingProvider);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardHead(title: 'Waiting for you', subtitle: 'Newest first'),
          CardBody(
            child: data.when(
              loading: () => const Shimmer(child: SkeletonRows(count: 4)),
              error: (e, _) => Text('$e', style: ts(12, color: p.warn)),
              data: (items) => items.isEmpty
                  ? Text('Nothing is waiting. Well done.', key: const ValueKey('requests-all-empty'), style: ts(13, color: p.muted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final it in items)
                          InkWell(
                            key: ValueKey('waiting-${it.path}'),
                            onTap: () => context.go(it.path),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [Pill(it.kind, kind: PillKind.blue), Text(_when.format(it.at), style: ts(11, color: p.sideNote))],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(it.who, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w700, color: p.ink)),
                                        Text(it.what, overflow: TextOverflow.ellipsis, style: ts(11.5, color: p.muted)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, size: 18, color: p.hint),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Waiting {
  const _Waiting(this.kind, this.who, this.what, this.at, this.path);

  final String kind;
  final String who;
  final String what;
  final DateTime at;
  final String path;
}

final _allWaitingProvider = FutureProvider.autoDispose<List<_Waiting>>((ref) async {
  const q = ListQuery(pageSize: 20);
  final results = await Future.wait([
    ProfileService().list(q),
    CreditsService().requests(q),
    ReportsService().list(const ListQuery(pageSize: 20, filters: {'status': 'waiting'})),
  ]);
  final out = <_Waiting>[
    for (final r in (results[0] as PagedResult<ProfileRequest>).items)
      _Waiting('Profile change', r.currentName, 'Asks to change ${[if (r.nameChanged) 'name', if (r.emailChanged) 'email'].join(' and ')}', r.createdAt, '/superadmin/profile-requests/${r.id}'),
    for (final r in (results[1] as PagedResult<CreditRequest>).items)
      _Waiting('AI credits', r.user, 'Asks for ${credits(r.amount)} credits${r.branch == null ? '' : ' · ${r.branch}'}', r.createdAt, '/superadmin/credit-requests/${r.id}'),
    for (final r in (results[2] as PagedResult<ProblemReport>).items)
      _Waiting('Problem report', r.reporter, '${reportTypeLabels[r.type] ?? r.type}: ${r.subject}', r.updatedAt, '/superadmin/reports/${r.id}'),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return out;
});

class _CreditRequestsList extends StatefulWidget {
  const _CreditRequestsList();

  @override
  State<_CreditRequestsList> createState() => _CreditRequestsListState();
}

class _CreditRequestsListState extends State<_CreditRequestsList> {
  final _list = ListController();

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListScaffold<CreditRequest>(
      controller: _list,
      fetch: CreditsService().requests,
      searchHint: 'Search…',
      emptyText: 'No credit requests here.',
      onRowTap: (r) => context.go('/superadmin/credit-requests/${r.id}'),
      filters: const [
        FilterSpec(name: 'status', label: 'Waiting', options: {'': 'Waiting', 'approved': 'Approved', 'declined': 'Declined', 'cancelled': 'Cancelled', 'all': 'All'}),
      ],
      columns: [
        ListColumn(
          label: 'Mall admin',
          flex: 3,
          cell: (c, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.user, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.ink)),
              Text(r.branch ?? 'No branch', overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted)),
            ],
          ),
        ),
        ListColumn(label: 'Asks for', flex: 2, cell: (c, r) => Text('${credits(r.amount)} credits', style: ts(12, w: FontWeight.w700, color: p.ink))),
        ListColumn(label: 'Has now', flex: 2, hideOnMobile: true, cell: (c, r) => Text(credits(r.balance), style: ts(12, color: p.muted))),
        ListColumn(label: 'Sent', flex: 2, hideOnMobile: true, cell: (c, r) => Text(_when.format(r.createdAt), style: ts(11, color: p.muted))),
        ListColumn(label: 'Status', flex: 2, cell: (c, r) => Align(alignment: Alignment.centerLeft, child: CreditRequestPill(r.status))),
      ],
    );
  }
}

class _ReportsList extends StatefulWidget {
  const _ReportsList();

  @override
  State<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends State<_ReportsList> {
  final _list = ListController();

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListScaffold<ProblemReport>(
      controller: _list,
      fetch: ReportsService().list,
      searchHint: 'Search…',
      emptyText: 'No problem reports here.',
      onRowTap: (r) => context.go('/superadmin/reports/${r.id}'),
      filters: const [
        FilterSpec(name: 'status', label: 'Waiting', options: {
          '': 'Waiting for you',
          'open': 'Open',
          'new': 'New',
          'in_progress': 'In progress',
          'resolved': 'Resolved',
          'closed': 'Closed',
          'all': 'All',
        }),
        FilterSpec(name: 'type', label: 'Any kind', options: {'': 'Any kind', ...reportTypeLabels}),
      ],
      columns: [
        ListColumn(
          label: 'Report',
          flex: 4,
          cell: (c, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.subject, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.ink)),
              Text(reportTypeLabels[r.type] ?? r.type, style: ts(11, color: p.muted)),
            ],
          ),
        ),
        ListColumn(
          label: 'From',
          flex: 3,
          cell: (c, r) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.reporter, overflow: TextOverflow.ellipsis, style: ts(12, color: p.ink)),
              Text(roleLabels[r.reporterRole] ?? r.reporterRole ?? '', overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted)),
            ],
          ),
        ),
        ListColumn(label: 'Last activity', flex: 2, hideOnMobile: true, cell: (c, r) => Text(_when.format(r.updatedAt), style: ts(11, color: p.muted))),
        ListColumn(
          label: 'Status',
          flex: 2,
          cell: (c, r) => Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 4, children: [ReportStatusPill(r.status), if (r.waiting && r.status != 'new') const Pill('Reply waiting', kind: PillKind.pending)]),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../../shared/widgets/skeleton.dart';
import '../requests/requests_view.dart' show ReportStatusPill;
import 'reports_service.dart';

/// "Report a problem" (Round 19): mall owners, mall admins and store owners
/// tell the superadmin about a problem. The page they are on goes with it.
Future<bool> showReportProblemDialog(BuildContext context, WidgetRef ref, {required String pagePath}) async {
  final ok = await showAppForm(
    context: context,
    title: 'Report a problem',
    subtitle: 'A superadmin sees it and answers in My account › My reports. The page you are on ($pagePath) is sent with it.',
    submitLabel: 'Send report',
    maxWidth: 520,
    fields: [
      FieldSpec(
        name: 'type',
        label: 'What kind of problem?',
        kind: FieldKind.select,
        required: true,
        options: [for (final e in reportTypeLabels.entries) SelectOption(e.key, e.value)],
      ),
      const FieldSpec(name: 'subject', label: 'Subject', required: true, maxLength: 120, hint: 'e.g. The map does not save'),
      const FieldSpec(name: 'body', label: 'What happened?', kind: FieldKind.multiline, required: true, maxLength: 2000, hint: 'What you did, what you expected, and what happened instead.'),
    ],
    onSubmit: (v) => ReportsService().create(type: v['type'] as String, subject: (v['subject'] as String).trim(), body: (v['body'] as String).trim(), pagePath: pagePath),
  );
  if (ok) {
    ref.invalidate(myReportsProvider);
    ref.read(messagesProvider.notifier).showSuccess('Report sent. You can follow it in My account.');
  }
  return ok;
}

/// My account: the person's latest reports; each opens its own page with the thread.
class MyReportsCard extends ConsumerWidget {
  const MyReportsCard({super.key});

  static final _fmt = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final nav = navForRole(ref.watch(currentUserProvider)?.role ?? 'store_owner');
    return DetailCard(
      title: 'My reports',
      subtitle: 'Problems you told a superadmin about',
      trailing: AppButton(
        key: const ValueKey('my-reports-new'),
        label: 'Report a problem',
        small: true,
        icon: Icons.flag_outlined,
        onPressed: () => showReportProblemDialog(context, ref, pagePath: GoRouterState.of(context).uri.path),
      ),
      child: ref.watch(myReportsProvider).when(
            loading: () => const Shimmer(child: SkeletonRows(count: 2)),
            error: (e, _) => Text(formatApiError(e), style: ts(12, color: p.warn)),
            data: (page) => page.items.isEmpty
                ? Align(alignment: Alignment.centerLeft, child: Text('No reports yet.', key: const ValueKey('my-reports-empty'), style: ts(12, color: p.muted)))
                : Column(
                    children: [
                      for (final r in page.items)
                        RecordRow(
                          key: ValueKey('my-report-${r.id}'),
                          title: r.subject,
                          subtitle:
                              '${reportTypeLabels[r.type] ?? r.type} · ${_fmt.format(r.updatedAt)}${r.messageCount > 0 ? ' · ${r.messageCount} ${r.messageCount == 1 ? 'reply' : 'replies'}' : ''}',
                          chips: [ReportStatusPill(r.status)],
                          onTap: () => context.go('${nav.prefix}/reports/${r.id}'),
                        ),
                      if (page.totalCount > page.items.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(alignment: Alignment.centerLeft, child: Text('Showing the latest ${page.items.length} of ${page.totalCount}.', style: ts(11, color: p.sideNote))),
                        ),
                    ],
                  ),
          ),
    );
  }
}

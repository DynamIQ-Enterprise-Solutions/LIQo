import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_builder.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../accounts/accounts_service.dart' show roleLabels;
import '../ai/credits_service.dart' show requestCountsProvider;
import '../requests/requests_view.dart' show ReportStatusPill;
import 'reports_service.dart';

/// One problem report with its thread (Round 19). The superadmin answers and
/// moves it on (New → In progress → Resolved, or Closed without a fix); the
/// reporter reads the answers and replies while it is open.
class ReportDetailView extends ConsumerStatefulWidget {
  const ReportDetailView({super.key, required this.reportId});

  final int reportId;

  @override
  ConsumerState<ReportDetailView> createState() => _ReportDetailViewState();
}

class _ReportDetailViewState extends ConsumerState<ReportDetailView> {
  final _service = ReportsService();
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');
  ReportThread? _t;
  bool _loading = true;
  String? _error;
  String _reply = '';
  int _replyRev = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _t == null;
      _error = null;
    });
    try {
      final t = await _service.get(widget.reportId);
      if (mounted) setState(() => _t = t);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _reply.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final t = await _service.reply(widget.reportId, text);
      if (!mounted) return;
      setState(() {
        _t = t;
        _reply = '';
        _replyRev++;
      });
      ref.invalidate(requestCountsProvider);
      ref.invalidate(myReportsProvider);
    } catch (e) {
      ref.read(messagesProvider.notifier).showError(formatApiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _status(String to) async {
    final label = reportStatusLabels[to]!.toLowerCase();
    if (to != 'in_progress') {
      final ok = await confirmDialog(
        context,
        title: to == 'resolved' ? 'Mark as resolved?' : 'Close without a fix?',
        message: 'The thread ends: neither side can add messages after this. The reporter sees it as $label.',
        confirmLabel: to == 'resolved' ? 'Resolve' : 'Close',
      );
      if (!ok) return;
    }
    try {
      final t = await _service.setStatus(widget.reportId, to);
      if (!mounted) return;
      setState(() => _t = t);
      ref.invalidate(requestCountsProvider);
      ref.read(messagesProvider.notifier).showSuccess('Marked as $label.');
    } catch (e) {
      ref.read(messagesProvider.notifier).showError(formatApiError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = ref.watch(currentUserProvider);
    final superadmin = me?.role == 'superadmin';
    final nav = navForRole(me?.role ?? 'store_owner');
    final r = _t?.report;
    return DetailScaffold(
      eyebrow: superadmin ? 'Superadmin / Requests & reports / Report' : '${nav.name} / My account / Report',
      title: r?.subject ?? 'Problem report',
      subtitle: r == null ? '' : '${reportTypeLabels[r.type] ?? r.type} · sent ${_fmt.format(r.createdAt)}',
      backPath: superadmin ? '/superadmin/requests?tab=reports' : '${nav.prefix}/account',
      backLabel: superadmin ? 'Requests & reports' : 'My account',
      hero: r == null
          ? null
          : RecordHero(
              mark: const HeroMark.icon(Icons.flag_outlined),
              title: r.subject,
              sub: superadmin ? 'From ${r.reporter}' : 'Your report',
              pills: [Pill(reportTypeLabels[r.type] ?? r.type, kind: PillKind.blue), ReportStatusPill(r.status)],
              line: 'Sent ${_fmt.format(r.createdAt)}${r.pagePath == null ? '' : ' · from ${r.pagePath}'}',
            ),
      actions: [
        if (superadmin && r != null && r.status == 'new') AppButton(key: const ValueKey('report-in-progress'), label: 'Mark in progress', onPressed: () => _status('in_progress')),
        if (superadmin && r != null && r.open) ...[
          AppButton(key: const ValueKey('report-close'), label: 'Close without a fix', onPressed: () => _status('closed')),
          AppButton(key: const ValueKey('report-resolve'), label: 'Resolve', primary: true, icon: Icons.check_circle_outline, onPressed: () => _status('resolved')),
        ],
      ],
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: r == null
          ? const []
          : [
              DetailColumns(
                facts: [
                  DetailCard(
                    title: 'Report',
                    subtitle: superadmin ? 'From ${r.reporter}' : 'What you sent',
                    child: Column(
                      children: [
                        if (superadmin) ...[
                          DetailRow('From', r.reporter),
                          DetailRow('Role', roleLabels[r.reporterRole] ?? r.reporterRole ?? ''),
                          if (r.reporterEmail != null) DetailRow('Email', r.reporterEmail),
                        ],
                        DetailRow('Kind', reportTypeLabels[r.type] ?? r.type),
                        if (r.pagePath != null) DetailRow('Page', r.pagePath),
                        if (r.closedBy != null) DetailRow(r.status == 'resolved' ? 'Resolved by' : 'Closed by', r.closedBy),
                      ],
                    ),
                  ),
                ],
                lists: [
                  DetailCard(
                    title: 'Conversation',
                    subtitle: r.open ? 'Both sides can write until it is resolved or closed' : 'This report is ${reportStatusLabels[r.status]!.toLowerCase()}; the thread has ended',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Bubble(author: r.reporter, role: r.reporterRole, mine: !superadmin, at: r.createdAt, body: r.body),
                        for (final m in _t!.messages) _Bubble(author: m.author, role: m.authorRole, mine: m.authorId == me?.id, at: m.createdAt, body: m.body),
                        if (r.open) ...[
                          const SizedBox(height: 8),
                          FieldBuilder(
                            key: ValueKey('report-reply-$_replyRev'),
                            spec: const FieldSpec(name: 'reply', label: 'Your reply', kind: FieldKind.multiline, maxLength: 2000, hint: 'Write a message…'),
                            value: _reply,
                            onChanged: (v) => setState(() => _reply = '${v ?? ''}'),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: AppButton(
                              key: const ValueKey('report-send'),
                              label: _sending ? 'Sending…' : 'Send',
                              primary: true,
                              icon: Icons.send_outlined,
                              onPressed: _reply.trim().isEmpty || _sending ? () {} : _send,
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(superadmin ? 'Closed reports stay here for the record.' : 'If the problem comes back, send a new report from the top bar.', style: ts(11, color: p.muted)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.author, required this.role, required this.mine, required this.at, required this.body});

  final String author;
  final String? role;
  final bool mine;
  final DateTime at;
  final String body;

  static final _fmt = DateFormat('MMM d, h:mm a');

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.86,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? p.soft : p.boxBg,
            border: Border.all(color: mine ? p.brand : p.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(mine ? 'You' : author, style: ts(12, w: FontWeight.w700, color: p.ink)),
                  if (!mine && role == 'superadmin') Text('Superadmin', style: ts(11, color: p.brand2)),
                  Text(_fmt.format(at), style: ts(11, color: p.sideNote)),
                ],
              ),
              const SizedBox(height: 4),
              Text(body, style: ts(12.5, color: p.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

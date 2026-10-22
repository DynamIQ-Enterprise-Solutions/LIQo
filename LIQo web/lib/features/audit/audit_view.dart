import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/lists/list_scaffold.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/action_label.dart';
import '../../shared/widgets/common.dart';

class AuditEntry {
  const AuditEntry({
    required this.id,
    this.actorEmail,
    required this.action,
    this.entityType,
    this.entityId,
    this.details,
    this.ip,
    required this.createdAt,
  });

  final int id;
  final String? actorEmail;
  final String action;
  final String? entityType;
  final String? entityId;
  final Object? details;
  final String? ip;
  final DateTime createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: j['id'] as int,
        actorEmail: j['actorEmail'] as String?,
        action: j['action'] as String,
        entityType: j['entityType'] as String?,
        entityId: j['entityId'] as String?,
        details: j['details'],
        ip: j['ip'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
}

class AuditService {
  AuditService([ApiClient? client]) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<PagedResult<AuditEntry>> list(ListQuery q) async {
    final r = await _client.dio.get('/audit', queryParameters: q.toParams());
    return PagedResult.fromJson(r.data as Map<String, dynamic>, AuditEntry.fromJson);
  }

  Future<List<String>> actions() async {
    final r = await _client.dio.get('/audit/actions');
    return ((r.data as Map<String, dynamic>)['actions'] as List<dynamic>).cast<String>();
  }
}

final auditActionsProvider = FutureProvider.autoDispose<List<String>>((ref) => AuditService().actions());

class AuditView extends ConsumerStatefulWidget {
  const AuditView({super.key});

  @override
  ConsumerState<AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends ConsumerState<AuditView> {
  final _list = ListController();
  final _service = AuditService();
  String? _from;
  String? _to;
  static final _fmt = DateFormat('MMM d, yyyy h:mm:ss a');

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    final s = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => from ? _from = s : _to = s);
    _list.refresh();
  }

  void _showDetails(AuditEntry e) {
    final p = context.pal;
    final pretty = e.details == null ? '—' : const JsonEncoder.withIndent('  ').convert(e.details);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(actionLabel(e.action), style: ts(15, w: FontWeight.w800, color: p.ink)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText('Code: ${e.action}', style: ts(11, color: p.muted)),
                Text('${e.actorEmail ?? 'unknown'} · ${_fmt.format(e.createdAt)} · ${e.ip ?? ''}', style: ts(11, color: p.muted)),
                if (e.entityType != null) Text('${e.entityType} #${e.entityId ?? ''}', style: ts(11, color: p.muted)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: p.boxBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line)),
                  child: SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
        actions: [AppButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop())],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final actions = ref.watch(auditActionsProvider).valueOrNull ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: 'Superadmin / Audit log',
          title: 'Audit log',
          subtitle: 'Sign-ins, account changes, assignments, and record changes across the platform.',
          actions: [
            AppButton(
              label: 'Export CSV',
              icon: Icons.download_outlined,
              onPressed: () => ref.read(messagesProvider.notifier).show('CSV export is a placeholder in this version.'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Date range:', style: ts(12, color: p.muted)),
              AppButton(label: _from ?? 'From', small: true, icon: Icons.calendar_today_outlined, onPressed: () => _pickDate(true)),
              AppButton(label: _to ?? 'To', small: true, icon: Icons.calendar_today_outlined, onPressed: () => _pickDate(false)),
              if (_from != null || _to != null)
                LinkButton('Clear', onPressed: () {
                  setState(() {
                    _from = null;
                    _to = null;
                  });
                  _list.refresh();
                }),
            ],
          ),
        ),
        ListScaffold<AuditEntry>(
          controller: _list,
          fetch: (q) => _service.list(q.copyWith(filters: {
            ...q.filters,
            if (_from != null) 'from': _from!,
            if (_to != null) 'to': _to!,
          })),
          searchHint: 'Search actor, action, entity…',
          emptyText: 'No audit entries match.',
          filters: [
            FilterSpec(name: 'action', label: 'All actions', options: {'': 'All actions', for (final a in actions) a: actionLabel(a)}),
          ],
          onRowTap: _showDetails,
          columns: [
            ListColumn(label: 'When', flex: 2, cell: (c, e) => Text(_fmt.format(e.createdAt), style: ts(11, color: p.muted))),
            ListColumn(label: 'Actor', flex: 2, cell: (c, e) => Text(e.actorEmail ?? '—')),
            ListColumn(label: 'Action', flex: 2, cell: (c, e) => Text(actionLabel(e.action), style: ts(12, w: FontWeight.w700, color: p.ink))),
            ListColumn(
              label: 'Entity',
              flex: 2,
              hideOnMobile: true,
              cell: (c, e) => Text(e.entityType == null ? '—' : '${e.entityType} #${e.entityId ?? ''}', style: ts(11, color: p.muted)),
            ),
            ListColumn(label: 'IP', flex: 1, hideOnMobile: true, cell: (c, e) => Text(e.ip ?? '—', style: ts(11, color: p.muted))),
          ],
        ),
      ],
    );
  }
}

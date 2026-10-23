import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import 'announcements_service.dart';
import 'announcements_view.dart';

enum _Edit { none, details, reject }

/// One announcement: the message, details (editable), review, danger zone.
class AnnouncementDetailView extends ConsumerStatefulWidget {
  const AnnouncementDetailView({super.key, required this.announcementId});

  final int announcementId;

  @override
  ConsumerState<AnnouncementDetailView> createState() => _AnnouncementDetailViewState();
}

class _AnnouncementDetailViewState extends ConsumerState<AnnouncementDetailView> {
  final _service = AnnouncementsService();
  Announcement? _a;
  bool _loading = true;
  _Edit _edit = _Edit.none;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _a == null;
      _error = null;
    });
    try {
      final a = await _service.get(widget.announcementId);
      if (mounted) setState(() => _a = a);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String text, {bool error = false}) {
    final n = ref.read(messagesProvider.notifier);
    error ? n.showError(text) : n.showSuccess(text);
  }

  Future<void> _approve() async {
    final a = _a!;
    final ok = await confirmDialog(context, title: 'Approve announcement?', message: '"${a.title}" will be published for its dates.', confirmLabel: 'Approve');
    if (!ok) return;
    try {
      final updated = await _service.approve(a.id);
      setState(() => _a = updated);
      _msg('Approved.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _delete(String listPath, {bool detach = false}) async {
    final a = _a!;
    final ok = await confirmDangerous(
      context,
      title: detach ? 'Remove it from your branches?' : 'Delete this announcement?',
      impact: detach
          ? 'It stops showing in your branches. The other branches it targets keep it; its author still manages it there.'
          : 'It is removed for everyone, including the shopper app. This cannot be undone.',
      name: a.title,
      confirmLabel: detach ? 'Remove from my branches' : 'Delete',
    );
    if (!ok) return;
    try {
      final detached = await _service.delete(a.id);
      _msg(detached ? 'Removed from your branches.' : 'Deleted.');
      if (mounted) context.go(listPath);
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final me = ref.watch(currentUserProvider);
    final role = me?.role ?? '';
    final nav = navForRole(role);
    final owner = role == 'store_owner';
    final a = _a;
    final mine = a != null && a.createdBy == me?.id;
    // Managers: what the server allows (owner decision 2026-10-22, "their part only").
    final canEdit = a != null && (owner ? mine : a.canChange);
    final canDelete = a != null && (owner ? (mine && a.status != 'approved') : a.canChange);
    final canDetach = a != null && !owner && a.canDetach;
    // Store-owner submissions are reviewed by mall admins (US-022; owner decision 2026-10-22).
    final reviewer = role == 'mall_admin' || role == 'superadmin';
    final reviewable = a != null && reviewer && a.status == 'pending';
    final waitingForAdmin = a != null && role == 'supervisor' && a.status == 'pending';
    final listPath = '${nav.prefix}/announcements';

    return DetailScaffold(
      eyebrow: '${nav.name} / Announcements / ${a?.title ?? 'Announcement'}',
      title: a?.title ?? 'Announcement',
      subtitle: a == null ? '' : 'By ${a.createdByName}${a.storeName != null ? ' · ${a.storeName}' : ''}',
      backPath: listPath,
      backLabel: 'Announcements',
      hero: a == null
          ? null
          : RecordHero(
              mark: const HeroMark.icon(Icons.campaign_outlined),
              title: a.title,
              sub: 'By ${a.createdByName}${a.storeName != null ? ' · ${a.storeName}' : ''}',
              pills: [StatePill(a.liveState)],
              line: [
                '${a.startsOn} → ${a.endsOn}',
                if (a.branches.isNotEmpty) a.branches.map((b) => b.name).join(', '),
              ].join(' · '),
            ),
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: a == null
          ? const []
          : [
              DetailColumns(
                facts: [
                  DetailCard(
                    title: 'Details',
                    subtitle: 'Dates, targets and review',
                    trailing: canEdit && _edit == _Edit.none ? AppButton(label: 'Edit', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _edit = _Edit.details)) : null,
                    child: _edit == _Edit.details
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (owner && a.status != 'pending') Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Saving sends it back for review.', style: ts(11, color: p.warn))),
                              AppFormBody(
                                fields: announcementFields(owner: owner).where((f) => f.name != 'store').toList(),
                                initial: {
                                  'title': a.title,
                                  'body': a.body,
                                  'startsOn': a.startsOn,
                                  'endsOn': a.endsOn,
                                  'imageUrl': a.imageUrl,
                                  'branches': [for (final b in a.branches) b.toLookup()],
                                },
                                onSubmit: (v) async {
                                  final updated = await _service.update(a.id, announcementBody(v, owner: owner));
                                  setState(() => _a = updated);
                                },
                                onCancel: () => setState(() => _edit = _Edit.none),
                                onDone: () {
                                  setState(() => _edit = _Edit.none);
                                  _msg('Announcement updated.');
                                },
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              DetailRow('Dates', '${a.startsOn} → ${a.endsOn}'),
                              DetailRow('Branches', a.branches.map((b) => b.name).join(', ')),
                              if (a.storeName != null) DetailRow('Store', a.storeName),
                              DetailRow('Posted by', '${a.createdByName} (${roleLabelOf(a.createdRole)})'),
                              DetailRow('Status', reviewStatusLabel(a.status)),
                              if (a.reviewedByName != null) DetailRow('Reviewed by', a.reviewedByName),
                              if (a.rejectReason != null) DetailRow('Reason', a.rejectReason),
                              if (a.imageUrl != null) DetailRow('Image URL', a.imageUrl),
                            ],
                          ),
                  ),
                  if (a.sharedBeyondScope)
                    DetailCard(
                      title: 'Shared with other branches',
                      subtitle: 'Only your branches are listed here',
                      child: Text(
                        a.canChange
                            ? 'It also shows in branches outside your scope.'
                            : 'It also shows in branches outside your scope, so only its author can change it. You can remove it from your branches.',
                        style: ts(12, color: p.muted),
                      ),
                    ),
                ],
                lists: [
                  DetailCard(
                    title: 'Message',
                    subtitle: '${a.startsOn} → ${a.endsOn}',
                    child: SelectableText(a.body, style: ts(13.5, color: p.ink, height: 1.55)),
                  ),
                  if (reviewable)
                    DetailCard(
                      title: 'Review',
                      subtitle: 'Approve to publish it for its dates, or reject it with a reason the store owner will see',
                      trailing: _edit == _Edit.reject ? null : AppButton(label: 'Approve', small: true, primary: true, icon: Icons.check_circle_outline, onPressed: _approve),
                      child: _edit == _Edit.reject
                          ? AppFormBody(
                              fields: const [FieldSpec(name: 'reason', label: 'Reason', kind: FieldKind.multiline, required: true, maxLength: 500, hint: 'Tell the store owner what to change.')],
                              submitLabel: 'Reject',
                              onSubmit: (v) async {
                                final updated = await _service.reject(a.id, v['reason'] as String);
                                setState(() => _a = updated);
                              },
                              onCancel: () => setState(() => _edit = _Edit.none),
                              onDone: () {
                                setState(() => _edit = _Edit.none);
                                _msg('Rejected.');
                              },
                            )
                          : Row(
                              children: [
                                Expanded(child: Text('Waiting for review since ${a.createdAt.toLocal().toString().substring(0, 10)}.', style: ts(12, color: p.muted))),
                                AppButton(label: 'Reject…', small: true, icon: Icons.undo, onPressed: () => setState(() => _edit = _Edit.reject)),
                              ],
                            ),
                    ),
                  if (waitingForAdmin)
                    DetailCard(
                      title: 'Review',
                      subtitle: 'Waiting for a mall admin',
                      child: Text('Mall admins approve or reject store-owner announcements. It goes live for its dates once approved.', style: ts(12, color: p.muted)),
                    ),
                ],
                after: [
                  if (canDelete)
                    DangerZone(actions: [
                      DangerAction(label: 'Delete', description: 'Remove this announcement for good.', onTap: () => _delete(listPath)),
                    ])
                  else if (canDetach)
                    DangerZone(actions: [
                      DangerAction(label: 'Remove from my branches', description: 'Stop showing it in your branches. Other branches keep it.', onTap: () => _delete(listPath, detach: true)),
                    ]),
                ],
              ),
            ],
    );
  }
}

String roleLabelOf(String role) => {'superadmin': 'Superadmin', 'supervisor': 'Mall owner', 'mall_admin': 'Mall admin', 'store_owner': 'Store owner'}[role] ?? role;

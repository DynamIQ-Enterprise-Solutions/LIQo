import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../accounts/accounts_service.dart' show roleLabels;
import '../account/profile_service.dart';
import '../ai/credits_service.dart' show requestCountsProvider;
import 'profile_requests_view.dart';

/// One profile change request: what changes, who asked, and the decision.
class ProfileRequestDetailView extends ConsumerStatefulWidget {
  const ProfileRequestDetailView({super.key, required this.requestId});

  final int requestId;

  @override
  ConsumerState<ProfileRequestDetailView> createState() => _ProfileRequestDetailViewState();
}

class _ProfileRequestDetailViewState extends ConsumerState<ProfileRequestDetailView> {
  final _service = ProfileService();
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');
  ProfileRequest? _r;
  bool _loading = true;
  bool _rejecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _r == null;
      _error = null;
    });
    try {
      final r = await _service.get(widget.requestId);
      if (mounted) setState(() => _r = r);
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
    final r = _r!;
    final ok = await confirmDialog(
      context,
      title: 'Approve this change?',
      message: r.emailChanged ? '${r.currentName} will sign in with ${r.requestedEmail} from now on. Their password stays the same.' : '${r.currentName} will be shown as ${r.requestedName}.',
      confirmLabel: 'Approve',
    );
    if (!ok) return;
    try {
      final updated = await _service.approve(r.id);
      setState(() => _r = updated);
      ref.invalidate(pendingProfileRequestsProvider);
      ref.invalidate(requestCountsProvider);
      _msg('Approved. The account now has the new details.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = _r;

    Widget compareRow(String label, String current, String requested, bool changed) {
      final value = Text(requested, style: ts(12.5, w: changed ? FontWeight.w700 : FontWeight.w400, color: changed ? p.brand2 : p.ink));
      return DetailRow(
        label,
        null,
        child: !r!.pending || !changed
            ? value
            : Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(current, style: ts(12.5, color: p.muted).copyWith(decoration: TextDecoration.lineThrough)),
                  Icon(Icons.east, size: 14, color: p.hint),
                  value,
                ],
              ),
      );
    }

    return DetailScaffold(
      eyebrow: 'Superadmin / Requests & reports / ${r?.currentName ?? 'Request'}',
      title: r == null ? 'Change request' : 'Change request from ${r.currentName}',
      subtitle: r == null ? '' : 'Sent ${_fmt.format(r.createdAt)}',
      backPath: '/superadmin/requests?tab=profile',
      backLabel: 'Requests & reports',
      hero: r == null
          ? null
          : RecordHero(
              mark: HeroMark.initials(initialsOf(r.currentName)),
              title: r.currentName,
              sub: 'Profile change · ${roleLabels[r.role] ?? r.role}',
              pills: [RequestStatusPill(r.status)],
              line: 'Sent ${_fmt.format(r.createdAt)}',
            ),
      loading: _loading,
      error: _error,
      onRetry: _load,
      children: r == null
          ? const []
          : [
              DetailColumns(
                facts: [
                  DetailCard(
                    title: 'Change',
                    subtitle: r.pending ? 'Current details, struck through, and what they asked for' : 'What they asked for',
                    child: Column(
                      children: [
                        compareRow('Full name', r.currentName, r.requestedName, r.nameChanged),
                        compareRow('Email', r.currentEmail, r.requestedEmail, r.emailChanged),
                        if (r.pending && r.emailChanged)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(alignment: Alignment.centerLeft, child: Text('The email is their sign-in. After approval they sign in with the new one.', style: ts(11, color: p.muted))),
                          ),
                      ],
                    ),
                  ),
                  DetailCard(
                    title: 'Person',
                    subtitle: roleLabels[r.role] ?? r.role,
                    trailing: AppButton(label: 'Open account', small: true, icon: Icons.person_outline, onPressed: () => context.go('/superadmin/accounts/${r.userId}')),
                    child: Column(
                      children: [
                        DetailRow('Name', r.currentName),
                        DetailRow('Email', r.currentEmail),
                        DetailRow('Role', roleLabels[r.role] ?? r.role),
                      ],
                    ),
                  ),
                ],
                lists: [
                  DetailCard(
                    title: 'Decision',
                    subtitle: r.pending ? 'Approve to apply the change, or reject it with a reason the person will see' : 'Already decided',
                    trailing: r.pending && !_rejecting ? AppButton(label: 'Approve', small: true, primary: true, icon: Icons.check_circle_outline, onPressed: _approve) : null,
                    child: !r.pending
                        ? Column(
                            children: [
                              DetailRow('Status', null, child: Align(alignment: Alignment.centerLeft, child: RequestStatusPill(r.status))),
                              if (r.reviewedBy != null) DetailRow('Decided by', r.reviewedBy),
                              if (r.reviewedAt != null) DetailRow('On', _fmt.format(r.reviewedAt!)),
                              if (r.reason != null) DetailRow('Reason', r.reason),
                            ],
                          )
                        : _rejecting
                            ? AppFormBody(
                                fields: const [
                                  FieldSpec(name: 'reason', label: 'Reason', kind: FieldKind.multiline, required: true, maxLength: 500, hint: 'Tell them what to change, e.g. "Use your work email."')
                                ],
                                submitLabel: 'Reject',
                                onSubmit: (v) async {
                                  final updated = await _service.reject(r.id, v['reason'] as String);
                                  setState(() => _r = updated);
                                  ref.invalidate(pendingProfileRequestsProvider);
                                  ref.invalidate(requestCountsProvider);
                                },
                                onCancel: () => setState(() => _rejecting = false),
                                onDone: () {
                                  setState(() => _rejecting = false);
                                  _msg('Rejected. The person sees your reason.');
                                },
                              )
                            : Row(
                                children: [
                                  Expanded(child: Text('Nothing about the account changes until you approve.', style: ts(12, color: p.muted))),
                                  const SizedBox(width: 10),
                                  AppButton(label: 'Reject…', small: true, icon: Icons.undo, onPressed: () => setState(() => _rejecting = true)),
                                ],
                              ),
                  ),
                ],
              ),
            ],
    );
  }
}

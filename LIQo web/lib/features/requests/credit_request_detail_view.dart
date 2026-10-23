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
import '../ai/credit_bar.dart';
import '../ai/credits_service.dart';
import 'requests_view.dart';

/// One AI credit request (Round 19): who asks, how much, what they have, and
/// the decision. Approving may give less than asked; the cap and the free
/// part of the wallet still apply. Every decision is audited.
class CreditRequestDetailView extends ConsumerStatefulWidget {
  const CreditRequestDetailView({super.key, required this.requestId});

  final int requestId;

  @override
  ConsumerState<CreditRequestDetailView> createState() => _CreditRequestDetailViewState();
}

class _CreditRequestDetailViewState extends ConsumerState<CreditRequestDetailView> {
  final _service = CreditsService();
  static final _fmt = DateFormat('MMM d, yyyy h:mm a');
  CreditRequestDetail? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _d == null;
      _error = null;
    });
    try {
      final d = await _service.requestDetail(widget.requestId);
      if (mounted) setState(() => _d = d);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _decided(String text) {
    ref.invalidate(requestCountsProvider);
    ref.read(messagesProvider.notifier).showSuccess(text);
    _load();
  }

  /// The most that can be given now: what was asked, the room under the cap, and what is free.
  double _most(CreditRequestDetail d) {
    var most = d.request.amount;
    if (d.room < most) most = d.room;
    if (d.free != null && d.free! < most) most = d.free!;
    return most < 0 ? 0 : most;
  }

  Future<void> _approve(CreditRequestDetail d) async {
    final most = _most(d);
    final ok = await showAppForm(
      context: context,
      title: 'Approve the request',
      subtitle: '${d.request.user} asks for ${credits(d.request.amount)}. Free to give ${d.free == null ? 'unknown' : credits(d.free!)} · room under the cap ${credits(d.room)}. You may give less.',
      submitLabel: 'Give credits',
      initial: {'amount': credits(most)},
      fields: [FieldSpec(name: 'amount', label: 'Credits to give', kind: FieldKind.decimal, required: true, min: 0.01, max: most)],
      onSubmit: (v) => _service.approve(d.request.id, (v['amount'] as num).toDouble()),
    );
    if (ok) _decided('Approved. The credits are theirs now.');
  }

  Future<void> _decline(CreditRequestDetail d) async {
    final ok = await showAppForm(
      context: context,
      title: 'Decline the request',
      subtitle: 'Nothing changes for ${d.request.user}. They can ask again later.',
      submitLabel: 'Decline',
      fields: const [FieldSpec(name: 'reason', label: 'Reason (optional, they see it)', kind: FieldKind.multiline, maxLength: 300)],
      onSubmit: (v) => _service.decline(d.request.id, reason: v['reason'] as String?),
    );
    if (ok) _decided('Declined.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final d = _d;
    final r = d?.request;
    final most = d == null ? 0.0 : _most(d);
    return DetailScaffold(
      eyebrow: 'Superadmin / Requests & reports / ${r?.user ?? 'AI credits'}',
      title: r == null ? 'AI credit request' : 'AI credits for ${r.user}',
      subtitle: r == null ? '' : 'Sent ${_fmt.format(r.createdAt)}',
      backPath: '/superadmin/requests?tab=credits',
      backLabel: 'Requests & reports',
      hero: r == null
          ? null
          : RecordHero(
              mark: HeroMark.initials(initialsOf(r.user)),
              title: r.user,
              sub: r.branch ?? 'No branch',
              pills: [Pill('Asks for ${credits(r.amount)} credits', kind: PillKind.blue), CreditRequestPill(r.status)],
              line: 'Sent ${_fmt.format(r.createdAt)} · has ${credits(r.balance)} now',
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
                    title: 'Request',
                    subtitle: 'An amount only; one open request per admin',
                    trailing: AppButton(label: 'Open account', small: true, icon: Icons.person_outline, onPressed: () => context.go('/superadmin/accounts/${r.userId}')),
                    child: Column(
                      children: [
                        DetailRow('Mall admin', r.user),
                        DetailRow('Branch', r.branch ?? 'No branch'),
                        DetailRow('Asks for', '${credits(r.amount)} credits'),
                        DetailRow('Has now', '${credits(r.balance)} credits'),
                      ],
                    ),
                  ),
                  DetailCard(
                    title: 'Decision',
                    subtitle: r.pending ? 'Approve (you may give less) or decline. Both are in the audit log.' : 'Already decided',
                    trailing: r.pending
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              AppButton(key: const ValueKey('credit-request-decline'), label: 'Decline…', small: true, onPressed: () => _decline(d!)),
                              AppButton(
                                key: const ValueKey('credit-request-approve'),
                                label: 'Approve…',
                                small: true,
                                primary: true,
                                icon: Icons.check_circle_outline,
                                onPressed: most > 0 ? () => _approve(d!) : () {},
                              ),
                            ],
                          )
                        : null,
                    child: r.pending
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DetailRow('Free to give', d!.free == null ? 'The wallet could not be read' : '${credits(d.free!)} credits'),
                              DetailRow('Room under the cap', '${credits(d.room)} of ${credits(d.cap)}'),
                              if (most <= 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    (d.overGiven ?? 0) > 0
                                        ? 'Admins hold more credits than the wallet has. Top up the IQGateway wallet before approving.'
                                        : d.room <= 0
                                            ? 'This admin already holds the most allowed.'
                                            : 'No credits are free to give right now.',
                                    key: const ValueKey('credit-request-blocked'),
                                    style: ts(12, w: FontWeight.w600, color: p.danger),
                                  ),
                                ),
                            ],
                          )
                        : Column(
                            children: [
                              DetailRow('Status', null, child: Align(alignment: Alignment.centerLeft, child: CreditRequestPill(r.status))),
                              if (r.decidedAmount != null) DetailRow('Given', '${credits(r.decidedAmount!)} credits'),
                              if (r.decidedBy != null) DetailRow('Decided by', r.decidedBy),
                              if (r.decidedAt != null) DetailRow('On', _fmt.format(r.decidedAt!)),
                              if (r.declineReason != null) DetailRow('Reason', r.declineReason),
                            ],
                          ),
                  ),
                ],
              ),
            ],
    );
  }
}

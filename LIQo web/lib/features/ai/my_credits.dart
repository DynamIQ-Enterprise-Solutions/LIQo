import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/skeleton.dart';
import 'ai_service.dart';
import 'credit_bar.dart';
import 'credits_service.dart';

// A mall admin's own AI credits (Round 19, owner decisions 2026-10-23): their
// balance against their last top-up, a warning when it runs low (any balance
// above 0 may start a reading, and the true cost may take it a little below 0),
// and asking a superadmin for more (an amount, one request at a time).

/// Asks a superadmin for more credits. Returns true when the request was sent.
Future<bool> showRequestCreditsDialog(BuildContext context, WidgetRef ref, MyCredits mine) async {
  final room = mine.room;
  final ok = await showAppForm(
    context: context,
    title: 'Request AI credits',
    subtitle: 'A superadmin sees your request and may give the amount, or less. You can ask for up to ${credits(room)} (the most per admin is ${credits(mine.cap)}).',
    submitLabel: 'Send request',
    fields: [
      FieldSpec(name: 'amount', label: 'How many credits', kind: FieldKind.decimal, required: true, min: 0.01, max: room, hint: 'e.g. 5'),
    ],
    onSubmit: (v) async => CreditsService().request((v['amount'] as num).toDouble()),
  );
  if (ok) {
    ref.invalidate(myCreditsProvider);
    ref.read(messagesProvider.notifier).showSuccess('Request sent. A superadmin will look at it.');
  }
  return ok;
}

/// The admin's credits with what they can do about them. [compact] is the
/// map editor's version (no headline).
class MyCreditsPanel extends ConsumerWidget {
  const MyCreditsPanel({super.key, this.compact = false});

  final bool compact;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      await CreditsService().cancelRequest();
      ref.invalidate(myCreditsProvider);
      ref.read(messagesProvider.notifier).showSuccess('Request cancelled.');
    } catch (e) {
      ref.read(messagesProvider.notifier).showError(formatApiError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final small = compact ? 11.0 : 12.0;
    return ref.watch(myCreditsProvider).when(
          loading: () => const Shimmer(child: SkeletonLines(widths: [0.6, 1, 0.4], height: 10)),
          error: (e, _) => Text(formatApiError(e), style: ts(small, color: p.warn)),
          data: (m) {
            final pending = m.request?.pending == true ? m.request : null;
            final out = m.balance <= 0;
            final low = !out && m.avgCost != null && m.balance < m.avgCost!;
            return Column(
              key: const ValueKey('my-credits'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                CreditBar(quota: AiQuota(balance: m.balance, full: m.full), compact: compact),
                if (out)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      m.balance < 0
                          ? 'Your last reading cost a little more than you had (${credits(m.balance)}). Ask a superadmin for more credits to read again.'
                          : 'You have no AI credits left. Ask a superadmin for more to read plans.',
                      key: const ValueKey('my-credits-out'),
                      style: ts(small, w: FontWeight.w600, color: p.danger),
                    ),
                  )
                else if (low)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'You have ${credits(m.balance)} credits; a reading usually costs about ${credits(m.avgCost!)}. Your balance may go below 0.',
                      key: const ValueKey('my-credits-low'),
                      style: ts(small, w: FontWeight.w600, color: p.cautionText),
                    ),
                  ),
                const SizedBox(height: 8),
                if (pending != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('You asked for ${credits(pending.amount)} credits; waiting for a superadmin.', key: const ValueKey('my-credits-pending'), style: ts(small, color: p.muted)),
                      AppButton(key: const ValueKey('my-credits-cancel'), label: 'Cancel request', small: true, onPressed: () => _cancel(context, ref)),
                    ],
                  )
                else if (m.room > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: const ValueKey('my-credits-request'),
                      label: 'Request credits',
                      small: true,
                      icon: Icons.add_card_outlined,
                      primary: out,
                      onPressed: () => showRequestCreditsDialog(context, ref, m),
                    ),
                  )
                else
                  Text('You hold the most credits allowed (${credits(m.cap)}).', style: ts(small, color: p.muted)),
                if (!compact && m.request != null && !m.request!.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      switch (m.request!.status) {
                        'approved' => 'Your last request was approved: ${credits(m.request!.decidedAmount ?? m.request!.amount)} credits given.',
                        'declined' => 'Your last request was declined${m.request!.declineReason == null ? '.' : ': ${m.request!.declineReason}'}',
                        _ => 'Your last request was cancelled.',
                      },
                      style: ts(11, color: p.sideNote),
                    ),
                  ),
              ],
            );
          },
        );
  }
}

/// The credit line above "Read with AI" in the map editor: a mall admin sees
/// their own credits (and can ask for more); a superadmin sees the wallet and
/// what is free to give, which their own readings use.
class AiReadingCredits extends StatelessWidget {
  const AiReadingCredits({super.key, required this.status});

  final AiStatus status;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = status;
    if (s.mine != null) return const MyCreditsPanel(compact: true);
    final q = s.quota;
    if (q == null || q.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CreditBar(quota: q, compact: true),
        if (q.free != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              (q.overGiven ?? 0) > 0 ? 'Nothing is free to give: admins hold more than the wallet has.' : 'Free to give: ${credits(q.free!)} (your readings use this part)',
              key: const ValueKey('ai-free-to-give'),
              style: ts(11, color: (q.free ?? 0) <= 0 ? p.danger : p.muted),
            ),
          ),
      ],
    );
  }
}

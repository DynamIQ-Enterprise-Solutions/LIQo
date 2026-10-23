import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/models/paged.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/reveal_on_scroll.dart';
import '../../shared/widgets/skeleton.dart';
import '../ai/ai_service.dart';
import '../ai/credit_bar.dart';
import '../ai/credits_service.dart';
import 'charts.dart';

// AI credits in Analytics (Round 19, owner decisions 2026-10-23). The
// superadmin sees the wallet split, each mall admin's credits and use, credits
// used per day and the history of every change, and gives or takes back
// credits here. A mall owner sees the same for the admins who report to them,
// read only, without the wallet. Requests are decided on Requests & reports.

final _when = DateFormat('MMM d, yyyy h:mm a');

Widget _card({required String title, required String subtitle, Widget? trailing, required Widget child, Key? key}) => AppCard(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [CardHead(title: title, subtitle: subtitle, trailing: trailing), CardBody(child: child)],
      ),
    );

class CreditsSection extends ConsumerWidget {
  const CreditsSection({super.key, required this.days, required this.superadmin});

  final int days;
  final bool superadmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return ref.watch(creditsOverviewProvider(days)).when(
          loading: () => const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(child: SkeletonLines(widths: [0.4, 1, 0.7], height: 10)),
                SizedBox(height: 18),
                SkeletonCard(child: SkeletonRows(count: 3)),
                SizedBox(height: 18),
                SkeletonCard(child: SkeletonChart(height: 180)),
              ],
            ),
          ),
          error: (e, _) => AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI credits could not be loaded', style: ts(14, w: FontWeight.w700, color: p.ink)),
                const SizedBox(height: 6),
                Text(formatApiError(e), style: ts(12, color: p.muted)),
                const SizedBox(height: 12),
                AppButton(label: 'Try again', primary: true, onPressed: () => ref.invalidate(creditsOverviewProvider(days))),
              ],
            ),
          ),
          data: (o) {
            // One bar per day of the period, days without use at 0.
            final today = DateTime.now();
            final start = DateTime(today.year, today.month, today.day).subtract(Duration(days: o.days - 1));
            final byDay = {for (final pt in o.series) DateTime(pt.day.year, pt.day.month, pt.day.day): pt.credits};
            final dayList = [for (var i = 0; i < o.days; i++) start.add(Duration(days: i))];
            return Column(
              key: const ValueKey('credits-section'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (superadmin && o.wallet != null) ...[
                  _card(
                    key: const ValueKey('credits-wallet'),
                    title: 'AI credits',
                    subtitle: 'The IQGateway wallet and what is given to mall admins',
                    trailing: (o.waiting ?? 0) > 0
                        ? AppButton(
                            key: const ValueKey('credits-requests-link'),
                            label: '${o.waiting} ${o.waiting == 1 ? 'request' : 'requests'} waiting',
                            small: true,
                            primary: true,
                            icon: Icons.inbox_outlined,
                            onPressed: () => context.go('/superadmin/requests?tab=credits'),
                          )
                        : null,
                    child: WalletSplitBar(split: o.wallet!, usedLabel: 'Used (${o.days} days)'),
                  ),
                  const SizedBox(height: 18),
                ],
                _card(
                  key: const ValueKey('credits-admins'),
                  title: superadmin ? "Mall admins' credits" : 'Credits of your mall admins',
                  subtitle: 'Balance now; use over the last ${o.days} days. At most ${credits(o.cap)} per admin.',
                  child: _AdminsTable(overview: o, superadmin: superadmin),
                ),
                const SizedBox(height: 18),
                _card(
                  key: const ValueKey('credits-usage'),
                  title: 'Credits used per day',
                  subtitle: '${credits(o.usageTotal)} credits in the last ${o.days} days${superadmin ? '' : ' by your mall admins'}',
                  child: RevealOnScroll(
                    builder: (context, shown) => DailyAmountBars(days: dayList, values: [for (final d in dayList) byDay[d] ?? 0], color: p.chart.first, shown: shown),
                  ),
                ),
                if (superadmin) ...[
                  const SizedBox(height: 18),
                  _card(
                    key: const ValueKey('credits-history'),
                    title: 'History',
                    subtitle: 'Every change to anyone\'s credits, newest first',
                    child: _History(key: ValueKey('history-${o.hashCode}')),
                  ),
                ],
              ],
            );
          },
        );
  }
}

/// Each admin's credits and use; the superadmin can give or take back.
class _AdminsTable extends ConsumerWidget {
  const _AdminsTable({required this.overview, required this.superadmin});

  final CreditsOverview overview;
  final bool superadmin;

  Future<void> _adjust(BuildContext context, WidgetRef ref, CreditAdmin a, {required bool give}) async {
    final w = overview.wallet;
    final room = (overview.cap - (a.balance > 0 ? a.balance : 0)).clamp(0, double.infinity).toDouble();
    final free = w?.free ?? 0;
    final most = give ? (room < free ? room : free) : (a.balance > 0 ? a.balance : 0).toDouble();
    if (most <= 0) {
      ref.read(messagesProvider.notifier).showError(give
          ? (w?.isOverGiven ?? false)
              ? 'Admins hold more credits than the wallet has. Top up the IQGateway wallet first.'
              : room <= 0
                  ? '${a.name} already holds the most allowed (${credits(overview.cap)}).'
                  : 'No credits are free to give right now.'
          : '${a.name} has no credits to take back.');
      return;
    }
    final ok = await showAppForm(
      context: context,
      title: give ? 'Give credits to ${a.name}' : 'Take credits back from ${a.name}',
      subtitle: give
          ? 'Has ${credits(a.balance)}. Free to give ${credits(free)} · room under the cap ${credits(room)}. Giving moves no money; the wallet only drops when a reading is paid.'
          : 'Has ${credits(a.balance)}. Taken-back credits become free to give again.',
      submitLabel: give ? 'Give credits' : 'Take back',
      fields: [
        FieldSpec(name: 'amount', label: 'Credits', kind: FieldKind.decimal, required: true, min: 0.01, max: most, hint: 'At most ${credits(most)}'),
        const FieldSpec(name: 'note', label: 'Note (optional)', maxLength: 200, hint: 'e.g. For the new wing'),
      ],
      onSubmit: (v) async {
        final amount = (v['amount'] as num).toDouble();
        await CreditsService().adjust(a.id, give ? amount : -amount, note: v['note'] as String?);
      },
    );
    if (ok) {
      ref.invalidate(creditsOverviewProvider);
      ref.invalidate(aiStatusProvider);
      ref.read(messagesProvider.notifier).showSuccess(give ? 'Credits given to ${a.name}.' : 'Credits taken back from ${a.name}.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final admins = overview.admins;
    if (admins.isEmpty) return Text(superadmin ? 'No active mall admins yet.' : 'No mall admins report to you yet.', style: ts(12, color: p.muted));
    final widths = [220.0, 110.0, 110.0, 90.0, 160.0, if (superadmin) 210.0];
    final heads = ['Mall admin', 'Balance', 'Used', 'Readings', 'Last reading', if (superadmin) ''];
    Widget cell(int i, Widget child) => SizedBox(width: widths[i], child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: child));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: p.tableHead,
            child: Row(
                mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < heads.length; i++) cell(i, Text(heads[i].toUpperCase(), style: ts(10, w: FontWeight.w700, color: p.muted, ls: 0.3)))]),
          ),
          for (final a in admins)
            Container(
              key: ValueKey('credit-admin-${a.id}'),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.rowLine))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  cell(
                    0,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.name, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: p.ink)),
                        Text(a.branch ?? 'No branch', overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted)),
                      ],
                    ),
                  ),
                  cell(1, _Balance(a)),
                  cell(2, Text(credits(a.used), style: ts(12, color: p.ink))),
                  cell(3, Text('${a.readings}', style: ts(12, color: p.ink))),
                  cell(4, Text(a.lastReading == null ? 'Never' : _when.format(a.lastReading!), overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted))),
                  if (superadmin)
                    cell(
                      5,
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          AppButton(key: ValueKey('credit-give-${a.id}'), label: 'Add', small: true, icon: Icons.add, onPressed: () => _adjust(context, ref, a, give: true)),
                          AppButton(key: ValueKey('credit-take-${a.id}'), label: 'Remove', small: true, icon: Icons.remove, onPressed: () => _adjust(context, ref, a, give: false)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A balance in its level's colour (green, yellow below 25% of the last top-up, red below 10% or at 0).
class _Balance extends StatelessWidget {
  const _Balance(this.a);

  final CreditAdmin a;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final level = walletLevel(AiQuota(balance: a.balance, full: a.full));
    final color = switch (level) {
      WalletLevel.ok => p.green,
      WalletLevel.low => p.cautionText,
      _ => p.danger,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: level == WalletLevel.low ? p.caution : color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(child: Text(credits(a.balance), key: ValueKey('credit-balance-${a.id}'), style: ts(12, w: FontWeight.w700, color: color))),
      ],
    );
  }
}

/// The ledger, newest first, with "Show more".
class _History extends StatefulWidget {
  const _History({super.key});

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  final List<LedgerEntry> _items = [];
  int _total = 0;
  int _page = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await CreditsService().history(ListQuery(page: _page + 1, pageSize: 10));
      if (!mounted) return;
      setState(() {
        _items.addAll(r.items);
        _total = r.totalCount;
        _page = r.page;
      });
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_items.isEmpty && _busy) return const Shimmer(child: SkeletonRows(count: 3));
    if (_error != null && _items.isEmpty) return Text(_error!, style: ts(12, color: p.warn));
    if (_items.isEmpty) return Text('No credit changes yet.', style: ts(12, color: p.muted));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in _items)
          Padding(
            key: ValueKey('ledger-${e.id}'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    '${e.delta > 0 ? '+' : ''}${credits(e.delta)}',
                    style: ts(12.5, w: FontWeight.w800, color: e.delta > 0 ? p.green : p.danger),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${ledgerKindLabels[e.kind] ?? e.kind} · ${e.user}', overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w600, color: p.ink)),
                      Text(
                        '${_when.format(e.createdAt)}${e.actor == null ? '' : ' · by ${e.actor}'} · balance after ${credits(e.balanceAfter)}${e.note == null ? '' : ' · ${e.note}'}',
                        style: ts(11, color: p.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_items.length < _total)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(key: const ValueKey('ledger-more'), label: _busy ? 'Loading…' : 'Show more', small: true, onPressed: _busy ? () {} : _more),
          ),
      ],
    );
  }
}

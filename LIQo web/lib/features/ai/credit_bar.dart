import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'ai_service.dart';
import 'credits_service.dart';

/// Credits in plain numbers: whole when whole, else up to two decimals.
String credits(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final s = v.toStringAsFixed(v.abs() < 0.1 ? 3 : 2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// How full the wallet is (owner decisions 2026-10-23): green, then yellow below
/// 25% of the last top-up, red below 10% and when empty or the gateway refuses.
enum WalletLevel { ok, low, almostOut, out }

WalletLevel walletLevel(AiQuota q) {
  final share = q.leftShare;
  if (q.blocked || (q.balance != null && q.balance! <= 0)) return WalletLevel.out;
  if (share == null) return WalletLevel.ok;
  if (share < 0.10) return WalletLevel.almostOut;
  if (share < 0.25) return WalletLevel.low;
  return WalletLevel.ok;
}

/// The gateway wallet as a status bar: what is left of the last top-up
/// (green, yellow when low, red when almost out), plus today's use
/// against the daily cap when the gateway sets one.
class CreditBar extends StatelessWidget {
  const CreditBar({super.key, required this.quota, this.compact = false});

  final AiQuota quota;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final daily = quota.usedShare;
    final left = quota.leftShare;
    final level = walletLevel(quota);
    final parts = <String>[
      if (quota.balance != null) '${credits(quota.balance!)} credits left',
      if (quota.usedToday != null && quota.dailyCap != null)
        '${credits(quota.usedToday!)} of ${credits(quota.dailyCap!)} used today'
      else if (quota.usedToday != null)
        '${credits(quota.usedToday!)} used today',
    ];
    final capReached = daily != null && daily >= 0.999;
    final stopped = quota.blocked || capReached || level == WalletLevel.out;
    final levelColor = switch (level) {
      WalletLevel.ok => p.green,
      WalletLevel.low => p.caution,
      WalletLevel.almostOut || WalletLevel.out => p.danger,
    };
    final status = switch (level) {
      WalletLevel.ok => null,
      WalletLevel.low => 'Running low',
      WalletLevel.almostOut => 'Almost out',
      WalletLevel.out => 'Out of credits',
    };
    // Yellow words use the darker yellow so they stay readable on a light page.
    final wordColor = level == WalletLevel.low ? p.cautionText : levelColor;
    final small = compact ? 11.0 : 12.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(parts.isEmpty ? 'The gateway did not report a balance.' : parts.join(' · '), style: ts(small, color: stopped ? p.warn : p.muted)),
        if (quota.blocked)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              quota.reason ?? 'The AI gateway is not accepting readings right now.',
              key: const ValueKey('ai-wallet-blocked'),
              style: ts(small, w: FontWeight.w600, color: p.warn),
            ),
          ),
        if (left != null) ...[
          SizedBox(height: compact ? 6 : 8),
          Semantics(
            label: 'AI credits: ${(left * 100).round()} percent of the last top-up left${status == null ? '' : ', $status'}',
            child: _Meter(key: const ValueKey('ai-wallet-meter'), share: left, color: levelColor, height: compact ? 8 : 12),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${(left * 100).round()}% of the last top-up (${credits(quota.full!)}) left',
                key: const ValueKey('ai-wallet-share'),
                style: ts(small, color: p.muted),
              ),
              if (status != null) Text(status, key: const ValueKey('ai-wallet-status'), style: ts(small, w: FontWeight.w800, color: wordColor)),
            ],
          ),
          if (!compact && (level == WalletLevel.low || level == WalletLevel.almostOut))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Top up the IQGateway wallet soon so plans can still be read.', style: ts(11, color: p.sideNote)),
            ),
        ],
        if (daily != null) ...[
          SizedBox(height: compact ? 6 : 10),
          if (!compact) Text("Today's limit", style: ts(11, w: FontWeight.w700, color: p.sideNote)),
          if (!compact) const SizedBox(height: 4),
          _Meter(key: const ValueKey('ai-daily-meter'), share: daily, color: capReached ? p.warn : p.slate, height: compact ? 4 : 5),
          if (capReached && !quota.blocked) Padding(padding: const EdgeInsets.only(top: 4), child: Text("Today's cap is reached; reading resumes tomorrow.", style: ts(11, color: p.warn))),
        ],
      ],
    );
  }
}

/// A rounded bar that fills to [share] (0–1), growing in when it first shows
/// and when the share changes; no movement with reduced motion.
class _Meter extends StatelessWidget {
  const _Meter({super.key, required this.share, required this.color, required this.height});

  final double share;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
          duration: still ? Duration.zero : const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: p.fieldLine),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v,
                child: AnimatedContainer(
                  duration: still ? Duration.zero : const Duration(milliseconds: 450),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The superadmin's wallet once credits are given out (owner decision
/// 2026-10-23): one bar split into what mall admins hold, what is free to give,
/// and (when the last top-up is known) what was used since; with the numbers.
/// Giving never lowers the wallet number: the wallet only drops when a reading is paid.
class WalletSplitBar extends StatelessWidget {
  const WalletSplitBar({super.key, required this.split, this.compact = false, this.usedLabel});

  final WalletSplit split;
  final bool compact;

  /// What "Used" covers, e.g. "Used (30 days)"; null hides it.
  final String? usedLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = split;
    final small = compact ? 11.0 : 12.0;
    if (s.wallet == null) {
      return Text('The wallet could not be read right now, so credits cannot be given.', style: ts(small, color: p.warn));
    }
    final wallet = s.wallet!;
    final whole = [s.full ?? 0, wallet, s.given].reduce((a, b) => a > b ? a : b);
    double share(double v) => whole <= 0 ? 0 : (v / whole).clamp(0.0, 1.0);
    final given = share(s.given);
    final free = share(s.free ?? 0);
    Widget legend(Color c, String label, double v, String key) => Row(
          key: ValueKey(key),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Flexible(child: Text('$label ${credits(v)}', overflow: TextOverflow.ellipsis, style: ts(small, color: p.ink))),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${credits(wallet)} credits in the wallet', key: const ValueKey('wallet-total'), style: ts(compact ? 12 : 13, w: FontWeight.w700, color: p.ink)),
        SizedBox(height: compact ? 6 : 8),
        Semantics(
          label: 'Wallet ${credits(wallet)} credits: ${credits(s.given)} given to mall admins, ${credits(s.free ?? 0)} free to give',
          child: ClipRRect(
            key: const ValueKey('wallet-split-bar'),
            borderRadius: BorderRadius.circular(compact ? 4 : 6),
            child: SizedBox(
              height: compact ? 8 : 12,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: p.fieldLine),
                  FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: (given + free).clamp(0.0, 1.0), child: ColoredBox(color: p.green)),
                  FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: given, child: ColoredBox(color: s.isOverGiven ? p.danger : p.brand)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            legend(s.isOverGiven ? p.danger : p.brand, 'Given to admins', s.given, 'wallet-given'),
            legend(p.green, 'Free to give', s.free ?? 0, 'wallet-free'),
            if (usedLabel != null) legend(p.fieldLine, usedLabel!, s.used, 'wallet-used'),
          ],
        ),
        if (s.isOverGiven)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Admins hold ${credits(s.overGiven!)} more credits than the wallet has. No more can be given until the IQGateway wallet is topped up.',
              key: const ValueKey('wallet-over-given'),
              style: ts(small, w: FontWeight.w600, color: p.danger),
            ),
          ),
      ],
    );
  }
}

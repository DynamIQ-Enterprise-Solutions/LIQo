import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'ai_service.dart';

/// Credits in plain numbers: whole when whole, else up to two decimals.
String credits(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  final s = v.toStringAsFixed(v.abs() < 0.1 ? 3 : 2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// The gateway wallet: balance, and today's use against the daily cap as a bar.
class CreditBar extends StatelessWidget {
  const CreditBar({super.key, required this.quota, this.compact = false});

  final AiQuota quota;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final share = quota.usedShare;
    final parts = <String>[
      if (quota.balance != null) '${credits(quota.balance!)} credits left',
      if (quota.usedToday != null && quota.dailyCap != null)
        '${credits(quota.usedToday!)} of ${credits(quota.dailyCap!)} used today'
      else if (quota.usedToday != null)
        '${credits(quota.usedToday!)} used today',
    ];
    final full = share != null && share >= 0.999;
    final stopped = quota.blocked || full;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(parts.isEmpty ? 'The gateway did not report a balance.' : parts.join(' · '), style: ts(compact ? 11 : 12, color: stopped ? p.warn : p.muted)),
        if (quota.blocked)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              quota.reason ?? 'The AI gateway is not accepting readings right now.',
              key: const ValueKey('ai-wallet-blocked'),
              style: ts(compact ? 11 : 12, w: FontWeight.w600, color: p.warn),
            ),
          ),
        if (share != null) ...[
          SizedBox(height: compact ? 5 : 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: compact ? 5 : 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: p.fieldLine),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share,
                    child: ColoredBox(color: full ? p.warn : p.brand),
                  ),
                ],
              ),
            ),
          ),
          if (full && !quota.blocked) Padding(padding: const EdgeInsets.only(top: 4), child: Text("Today's cap is reached; reading resumes tomorrow.", style: ts(11, color: p.warn))),
        ],
      ],
    );
  }
}

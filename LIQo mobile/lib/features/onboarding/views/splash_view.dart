// The splash: the wordmark and "Smart Way Forward" while the malls are built,
// at least one second (owner decision 2026-10-22).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../malls/data/registry.dart';
import '../../malls/providers/mall_provider.dart';
import '../providers/boot_provider.dart';

class SplashView extends ConsumerStatefulWidget {
  const SplashView({super.key});

  /// The least time it shows.
  static const minimum = Duration(seconds: 1);

  @override
  ConsumerState<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends ConsumerState<SplashView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final started = DateTime.now();
    // after the first frame, so the splash is on screen while the malls are built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final e in venueRegistry) {
        ref.read(venueProvider(e.id));
      }
      final left = SplashView.minimum - DateTime.now().difference(started);
      _timer = Timer(left.isNegative ? Duration.zero : left, () {
        if (mounted) ref.read(bootProvider.notifier).splashDone();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        // a soft orange glow behind the logo, as on the board's splash
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0, -.1), radius: .9, colors: [p.brand.withValues(alpha: p.mix(.10, .22)), p.bg]),
            ),
          ),
        ),
        const Center(child: Padding(padding: EdgeInsets.all(24), child: FittedBox(fit: BoxFit.scaleDown, child: BrandLockup(size: 56, taglineSize: 16)))),
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + 40,
          child: Center(
            child: SizedBox(width: 28, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(2)))),
          ),
        ),
      ]),
    );
  }
}

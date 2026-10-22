import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Loading placeholders that keep a module's shape while its data is on the
/// way. Every size here is relative (fractions, Expanded), never a fixed
/// pixel width, so a skeleton can never overflow a narrow screen.
///
/// Wrap a block of skeleton parts in [Shimmer] once; it sweeps a soft
/// highlight across all of them (and stays still when the device asks for
/// reduced motion).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final t = _c.value;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [p.softLine, p.pick(p.line, p.fieldLine), p.softLine],
            stops: [t - 0.3, t, t + 0.3].map((s) => s.clamp(0.0, 1.0)).toList(),
          ).createShader(bounds);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// One grey block. [widthFactor] is a share of the available width (1 = full).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.widthFactor = 1, this.height = 12, this.radius = 6});

  final double widthFactor;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(height: height, decoration: BoxDecoration(color: p.softLine, borderRadius: BorderRadius.circular(radius))),
      ),
    );
  }
}

/// A few lines of "text" with varied lengths.
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.widths = const [0.9, 0.6, 0.75], this.height = 10, this.gap = 8});

  final List<double> widths;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < widths.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            SkeletonBox(widthFactor: widths[i], height: height),
          ],
        ],
      );
}

/// A stat tile: label, a big number, a note.
class SkeletonStatCard extends StatelessWidget {
  const SkeletonStatCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(widthFactor: 0.55, height: 11),
          SizedBox(height: 16),
          SkeletonBox(widthFactor: 0.4, height: 26, radius: 8),
          SizedBox(height: 10),
          SkeletonBox(widthFactor: 0.7, height: 9),
        ],
      ),
    );
  }
}

/// Table rows: a wide cell, two medium ones, a short one.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < count; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Expanded(flex: 3, child: SkeletonBox(widthFactor: 0.8, height: 11)),
                  SizedBox(width: 16),
                  Expanded(flex: 2, child: SkeletonBox(widthFactor: 0.7, height: 11)),
                  SizedBox(width: 16),
                  Expanded(flex: 2, child: SkeletonBox(widthFactor: 0.5, height: 11)),
                  SizedBox(width: 16),
                  Expanded(flex: 1, child: SkeletonBox(widthFactor: 0.9, height: 18, radius: 9)),
                ],
              ),
            ),
        ],
      );
}

/// A chart area: a few faint bars of different heights on a baseline.
class SkeletonChart extends StatelessWidget {
  const SkeletonChart({super.key, this.height = 200});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const heights = [0.35, 0.6, 0.45, 0.8, 0.55, 0.9, 0.7, 0.5, 0.65, 0.4, 0.75, 0.6];
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in heights)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: FractionallySizedBox(
                  heightFactor: h,
                  child: Container(decoration: BoxDecoration(color: p.softLine, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A card with a title line and [child] under it, in the real card chrome.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child, this.titleFactor = 0.3});

  final Widget child;
  final double titleFactor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SkeletonBox(widthFactor: titleFactor, height: 13), const SizedBox(height: 8), const SkeletonBox(widthFactor: 0.5, height: 9)]),
          ),
          Container(height: 1, color: p.softLine),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }
}

/// A form: labels and fields.
class SkeletonForm extends StatelessWidget {
  const SkeletonForm({super.key, this.fields = 4});

  final int fields;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields; i++) ...[
            const SkeletonBox(widthFactor: 0.3, height: 10),
            const SizedBox(height: 6),
            const SkeletonBox(widthFactor: 1, height: 36, radius: 8),
            const SizedBox(height: 14),
          ],
        ],
      );
}

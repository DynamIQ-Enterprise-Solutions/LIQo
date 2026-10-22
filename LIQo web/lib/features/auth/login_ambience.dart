import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/widgets/common.dart';

/// The login page's living background (owner decisions 2026-10-22): a slow
/// drifting brand glow, plus a faint floor-plan grid where thin routes trace
/// themselves and beacons softly pulse. One repeating clock ([clock], 0..1
/// over its period) drives everything; with reduced motion the clock stands
/// still and this paints one calm frame.
class LoginBackdrop extends StatelessWidget {
  const LoginBackdrop({super.key, required this.clock});

  final Animation<double> clock;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _BackdropPainter(context.pal, clock), size: Size.infinite),
      );
}

/// Routes in fractions of the page, snapped to the grid when painted.
const _routes = <List<Offset>>[
  [Offset(0.60, 0.16), Offset(0.76, 0.16), Offset(0.76, 0.34), Offset(0.90, 0.34)],
  [Offset(0.62, 0.86), Offset(0.62, 0.70), Offset(0.80, 0.70), Offset(0.80, 0.58)],
  [Offset(0.95, 0.52), Offset(0.95, 0.80), Offset(0.86, 0.80)],
  [Offset(0.10, 0.94), Offset(0.30, 0.94), Offset(0.30, 0.86)],
];

/// Where each route starts in the clock's cycle, so they never move together.
const _phases = [0.0, 0.29, 0.53, 0.77];

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.p, this.clock) : super(repaint: clock);

  final Pal p;
  final Animation<double> clock;

  static const _grid = 32.0;

  /// The grid dots for the last size painted (rebuilt only when the size changes).
  Size? _dotsFor;
  List<Offset> _dots = const [];

  Offset _snap(Offset f, Size s) => Offset((f.dx * s.width / _grid).round() * _grid, (f.dy * s.height / _grid).round() * _grid);

  void _bloom(Canvas c, Offset at, double radius, Color color) {
    c.drawCircle(
      at,
      radius,
      Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: radius)),
    );
  }

  @override
  void paint(Canvas c, Size size) {
    if (size.isEmpty) return;
    final t = clock.value;
    final a = 2 * math.pi * t;
    final span = math.max(size.width, size.height);

    // 1. Slow light: two brand blooms and a crimson one, drifting on long loops.
    // Light mode: warmer and a little stronger (peach and rose), so the
    // frosted glass on top has colour to frost.
    final rose = Color.lerp(p.brand, Pal.brandCrimson, 0.45)!;
    _bloom(c, Offset(size.width * (0.22 + 0.06 * math.sin(a)), size.height * (0.28 + 0.05 * math.cos(a))), span * 0.55, p.brand.withValues(alpha: p.mix(0.16, 0.10)));
    _bloom(c, Offset(size.width * (0.82 + 0.05 * math.cos(a + 1.3)), size.height * (0.78 + 0.06 * math.sin(a + 1.3))), span * 0.5,
        p.pick(rose.withValues(alpha: 0.13), Pal.brandCrimson.withValues(alpha: 0.16)));
    _bloom(c, Offset(size.width * (0.70 + 0.07 * math.sin(2 * a + 0.6)), size.height * (0.12 + 0.04 * math.cos(2 * a))), span * 0.3, p.brand.withValues(alpha: p.mix(0.12, 0.06)));
    if (p.darkness < 1) {
      _bloom(c, Offset(size.width * (0.48 + 0.05 * math.cos(a + 2.2)), size.height * (0.55 + 0.05 * math.sin(a + 2.2))), span * 0.35, rose.withValues(alpha: 0.08 * (1 - p.darkness)));
    }

    // 2. The plan grid: faint dots.
    if (_dotsFor != size) {
      _dotsFor = size;
      _dots = [
        for (var x = _grid; x < size.width; x += _grid)
          for (var y = _grid; y < size.height; y += _grid) Offset(x, y),
      ];
    }
    c.drawPoints(
      PointMode.points,
      _dots,
      Paint()
        ..color = p.ink.withValues(alpha: p.mix(0.08, 0.07))
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    // 3. Routes: each traces itself, rests with a pulsing beacon, then fades.
    for (var r = 0; r < _routes.length; r++) {
      final pts = [for (final f in _routes[r]) _snap(f, size)];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final q in pts.skip(1)) {
        path.lineTo(q.dx, q.dy);
      }
      final local = (t * 3 + _phases[r]) % 1; // three cycles per clock period
      final drawn = local < 0.45 ? Curves.easeInOutCubic.transform(local / 0.45) : 1.0;
      final fade = local < 0.8 ? 1.0 : 1 - (local - 0.8) / 0.2;
      if (fade <= 0) continue;
      final metric = path.computeMetrics().first;
      final trail = metric.extractPath(0, metric.length * drawn);
      c.drawPath(
        trail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = p.brand.withValues(alpha: p.mix(0.4, 0.32) * fade),
      );
      c.drawCircle(pts.first, 2.4, Paint()..color = p.brand.withValues(alpha: 0.55 * fade));
      if (local < 0.45) {
        final head = metric.getTangentForOffset(metric.length * drawn)?.position;
        if (head != null) {
          _bloom(c, head, 14, p.brand.withValues(alpha: 0.45 * fade));
          c.drawCircle(head, 2.2, Paint()..color = p.brand.withValues(alpha: 0.95 * fade));
        }
      } else {
        final end = pts.last;
        final pulse = ((local - 0.45) / 0.35).clamp(0.0, 1.0);
        c.drawCircle(
          end,
          4 + 16 * Curves.easeOutCubic.transform(pulse),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = p.brand.withValues(alpha: 0.45 * (1 - pulse) * fade),
        );
        _bloom(c, end, 12, p.brand.withValues(alpha: 0.35 * fade));
        c.drawCircle(end, 3, Paint()..color = p.brand.withValues(alpha: 0.9 * fade));
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.p != p || old.clock != clock;
}

/// The IQ mark, very large and very faint, breathing slowly behind the card.
class IqWatermark extends StatelessWidget {
  const IqWatermark({super.key, required this.clock, required this.height});

  final Animation<double> clock;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final image = ThemedAsset(light: 'assets/brand/iq-light.png', dark: 'assets/brand/iq-dark.png', height: height, alignment: Alignment.center);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: clock,
        child: image,
        builder: (context, child) {
          // Four slow breaths per clock period; never more than a whisper.
          final breath = 0.5 + 0.5 * math.sin(2 * math.pi * clock.value * 4);
          final opacity = p.mix(0.045, 0.035) + 0.02 * breath;
          return Opacity(opacity: opacity, child: Transform.scale(scale: 1 + 0.012 * breath, child: child));
        },
      ),
    );
  }
}

/// A thin light that travels slowly around a rounded card's border.
class EdgeGlowPainter extends CustomPainter {
  EdgeGlowPainter({required this.p, required this.clock, required this.radius}) : super(repaint: clock);

  final Pal p;
  final Animation<double> clock;
  final double radius;

  @override
  void paint(Canvas c, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    // Three laps per clock period.
    final angle = 2 * math.pi * ((clock.value * 3) % 1);
    final sweep = SweepGradient(
      colors: [
        p.brand.withValues(alpha: 0),
        p.brand.withValues(alpha: 0),
        p.brand.withValues(alpha: p.mix(0.6, 0.75)),
        p.brand2.withValues(alpha: 0),
        p.brand.withValues(alpha: 0),
      ],
      stops: const [0, 0.62, 0.74, 0.86, 1],
      transform: GradientRotation(angle),
    ).createShader(rect);
    // A soft halo, then the crisp line.
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..shader = sweep,
    );
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = sweep,
    );
  }

  @override
  bool shouldRepaint(EdgeGlowPainter old) => old.p != p || old.clock != clock || old.radius != radius;
}

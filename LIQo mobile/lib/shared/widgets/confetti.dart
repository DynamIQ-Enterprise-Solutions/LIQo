// Confetti on arrival (about 2.5 s), from the demo's ui/celebration.dart.
// Never shown at the end of an evacuation nor with reduce motion on.
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Confetti over the whole screen, fired by each new [burst] number. It never takes taps.
class Confetti extends StatefulWidget {
  final int burst;
  final List<Color> colors;
  const Confetti({super.key, required this.burst, required this.colors});
  static const duration = Duration(milliseconds: 2500);

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final _ctl = AnimationController(vsync: this, duration: Confetti.duration);
  List<_Piece> _pieces = const [];

  @override
  void didUpdateWidget(Confetti old) {
    super.didUpdateWidget(old);
    if (widget.burst != old.burst) _fire();
  }

  void _fire() {
    final rnd = math.Random(widget.burst);
    // two cannons, low on the left and right edges, aimed up and inwards
    _pieces = [
      for (var i = 0; i < 160; i++)
        _Piece(
          left: i.isEven,
          angle: (62 + rnd.nextDouble() * 22) * math.pi / 180,
          speed: 1.05 + rnd.nextDouble() * .75, // in screen heights per second
          spin: (rnd.nextDouble() - .5) * 14,
          sway: rnd.nextDouble() * math.pi * 2,
          size: 5 + rnd.nextDouble() * 6,
          round: rnd.nextDouble() < .25,
          color: widget.colors[rnd.nextInt(widget.colors.length)],
        ),
    ];
    _ctl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, _) => _ctl.isAnimating ? CustomPaint(painter: _ConfettiPainter(_pieces, _ctl.value), size: Size.infinite) : const SizedBox.shrink(),
        ),
      );
}

class _Piece {
  final bool left, round;
  final double angle, speed, spin, sway, size;
  final Color color;
  const _Piece({required this.left, required this.angle, required this.speed, required this.spin, required this.sway, required this.size, required this.round, required this.color});
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t; // 0..1 over the burst
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final secs = t * Confetti.duration.inMilliseconds / 1000, h = size.height;
    const gravity = 1.6; // screen heights per second squared
    final fade = t < .7 ? 1.0 : 1 - (t - .7) / .3;
    final paint = Paint();
    for (final p in pieces) {
      // a little air drag, so they float down rather than drop
      final drag = (1 - math.exp(-1.6 * secs)) / 1.6;
      final vx = math.cos(p.angle) * p.speed * h, vy = math.sin(p.angle) * p.speed * h;
      final x0 = p.left ? -8.0 : size.width + 8, y0 = h * .78;
      final x = x0 + (p.left ? 1 : -1) * vx * drag * .55 + math.sin(p.sway + secs * 5) * 10;
      final y = y0 - vy * drag + .5 * gravity * h * secs * secs * .55;
      if (y > h + 20) continue;
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * secs);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * .45, paint);
      } else {
        // a strip that seems to flip as it turns
        final flip = math.cos(p.spin * secs * 1.7).abs() * .8 + .2;
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * .5 * flip), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t || old.pieces != pieces;
}

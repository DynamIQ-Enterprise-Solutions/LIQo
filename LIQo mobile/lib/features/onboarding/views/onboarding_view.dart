// Onboarding: three slides on the first launch only (owner decisions 2026-10-22):
// "Find your way inside the mall", "Everything in one place", "Never get lost".
// The pictures are drawn, generic placeholders.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../settings/providers/words_provider.dart';
import '../providers/boot_provider.dart';

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});
  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _pages = PageController();
  int _page = 0;

  static const slides = [
    ('Find your way inside the mall', 'Explore. Discover. Shop. Effortlessly.'),
    ('Everything in one place', 'Browse stores, dining and services by category.'),
    ('Never get lost', 'Clear turn-by-turn guidance across every level.'),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < slides.length - 1) {
      final reduce = MediaQuery.disableAnimationsOf(context);
      if (reduce) {
        _pages.jumpToPage(_page + 1);
      } else {
        _pages.nextPage(duration: motionBase, curve: Curves.easeOut);
      }
    } else {
      ref.read(bootProvider.notifier).onboardingDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              const BrandWordmark(size: 24),
              const Spacer(),
              TextButton(
                key: const ValueKey('onboarding-skip'),
                onPressed: () => ref.read(bootProvider.notifier).onboardingDone(),
                child: Text(w.tr('Skip'), style: ts(14, w: FontWeight.w700, color: p.brand2)),
              ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (i, (title, body)) in slides.indexed)
                  LayoutBuilder(builder: (context, c) {
                    final art = math.min(c.maxHeight * .55, 340.0);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(
                          height: art,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: ExcludeSemantics(child: CustomPaint(painter: OnboardingArt(i, p))),
                          ),
                        ),
                        const SizedBox(height: 28),
                        Semantics(header: true, child: Text(w.tr(title), style: ts(26, w: FontWeight.w800, color: p.ink, height: 1.2, ls: -.3))),
                        const SizedBox(height: 10),
                        Text(w.tr(body), style: ts(15.5, color: p.muted)),
                      ]),
                    );
                  }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(children: [
              // the page dots
              Semantics(
                label: w.tr('Page ${_page + 1} of ${slides.length}'),
                excludeSemantics: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < slides.length; i++)
                    AnimatedContainer(
                      duration: motionFast,
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(color: i == _page ? p.brand : p.line, borderRadius: BorderRadius.circular(4)),
                    ),
                ]),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: _page < slides.length - 1 ? w.tr('Next') : w.tr('Get started'),
                excludeSemantics: true,
                onTap: _next,
                child: Material(
                  color: p.brand,
                  shape: const CircleBorder(),
                  elevation: 0,
                  child: InkWell(
                    key: const ValueKey('onboarding-next'),
                    customBorder: const CircleBorder(),
                    onTap: _next,
                    child: Padding(padding: const EdgeInsets.all(16), child: Icon(_page < slides.length - 1 ? Icons.arrow_forward : Icons.check, color: p.onBrand)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The slides' drawn pictures: a corridor with the route arrow; the category tiles;
/// a route climbing across levels.
class OnboardingArt extends CustomPainter {
  OnboardingArt(this.slide, this.p);
  final int slide;
  final Pal p;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p.raised, p.soft]).createShader(r));
    final line = Paint()
      ..color = p.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final route = Paint()
      ..color = p.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (slide) {
      case 0:
        // a corridor in perspective: shop fronts on both sides, the route up the middle
        final vx = w / 2, vy = h * .32;
        for (final side in [-1.0, 1.0]) {
          for (var k = 0; k < 4; k++) {
            final t0 = .15 + k * .2, t1 = t0 + .16;
            Offset at(double t, double y) => Offset(vx + side * (w * .5) * t, vy + (y - vy) * t);
            final path = Path()
              ..moveTo(at(t0, h).dx, at(t0, h * .9).dy)
              ..lineTo(at(t1, h).dx, at(t1, h * .9).dy)
              ..lineTo(at(t1, h).dx, at(t1, h * .25).dy)
              ..lineTo(at(t0, h).dx, at(t0, h * .25).dy)
              ..close();
            canvas.drawPath(path, Paint()..color = Color.lerp(p.panel, p.brand, .08 + k * .03)!);
            canvas.drawPath(path, line);
          }
        }
        final path = Path()
          ..moveTo(w * .5, h * .98)
          ..cubicTo(w * .42, h * .75, w * .6, h * .55, vx, vy + h * .08);
        canvas.drawPath(path, route);
        final tip = Offset(vx, vy + h * .05);
        canvas.drawPath(Path()..moveTo(tip.dx, tip.dy)..lineTo(tip.dx - 14, tip.dy + 20)..lineTo(tip.dx + 14, tip.dy + 20)..close(), Paint()..color = p.brand);
      case 1:
        // the category tiles
        const cols = 3, rows = 2;
        final gap = w * .05, tw = (w - gap * (cols + 1)) / cols, th = math.min(tw, (h - gap * (rows + 1)) / rows);
        final top = (h - (th * rows + gap * (rows - 1))) / 2;
        for (var i = 0; i < cols * rows; i++) {
          final x = gap + (i % cols) * (tw + gap), y = top + (i ~/ cols) * (th + gap);
          final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, tw, th), const Radius.circular(16));
          canvas.drawRRect(rr, Paint()..color = i == 0 ? p.brand : p.panel);
          canvas.drawRRect(rr, line);
          canvas.drawCircle(Offset(x + tw / 2, y + th * .42), th * .16, Paint()..color = i == 0 ? p.onBrand : p.tiles[i % p.tiles.length]);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + tw / 2, y + th * .75), width: tw * .5, height: 6), const Radius.circular(3)), Paint()..color = i == 0 ? p.onBrand : p.line);
        }
      default:
        // three floors, and the route turning and climbing between them
        for (var k = 0; k < 3; k++) {
          final y = h * (.25 + k * .27);
          final plate = Path()
            ..moveTo(w * .12, y)
            ..lineTo(w * .78, y)
            ..lineTo(w * .88, y + h * .1)
            ..lineTo(w * .22, y + h * .1)
            ..close();
          canvas.drawPath(plate, Paint()..color = p.panel);
          canvas.drawPath(plate, line);
        }
        final path = Path()
          ..moveTo(w * .25, h * .86)
          ..lineTo(w * .62, h * .86)
          ..lineTo(w * .62, h * .59)
          ..lineTo(w * .35, h * .59)
          ..lineTo(w * .35, h * .32)
          ..lineTo(w * .72, h * .32);
        canvas.drawPath(path, route);
        canvas.drawCircle(Offset(w * .25, h * .86), 9, Paint()..color = p.brand);
        canvas.drawCircle(Offset(w * .25, h * .86), 4, Paint()..color = p.onBrand);
        final pin = Offset(w * .72, h * .32);
        canvas.drawCircle(pin.translate(0, -16), 12, Paint()..color = p.brand2);
        canvas.drawCircle(pin.translate(0, -16), 5, Paint()..color = p.panel);
    }
  }

  @override
  bool shouldRepaint(OnboardingArt old) => old.slide != slide || old.p != p;
}

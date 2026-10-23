import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/widgets/common.dart';
import 'glass.dart';

/// The feature showcase beside the sign-in form (owner decisions 2026-10-22):
/// a glass panel (obsidian to deep crimson in dark mode, frosted peach and
/// rose in light mode) where each feature floats as glass UI cards in slight
/// 3D perspective, with a glow beneath. Four features, marketing pictures
/// with generic placeholder content (never live data) that build themselves
/// in on each slide; advancing every 6 s until someone picks a slide; never
/// moving by itself when the device asks for reduced motion.
class FeatureCarousel extends StatefulWidget {
  const FeatureCarousel({super.key, this.compact = false, this.interval = const Duration(seconds: 6), this.ambient});

  /// The narrow-window version: an icon, the text and the controls, no picture.
  final bool compact;
  final Duration interval;

  /// The page's slow clock (0..1, repeating), for the cards' gentle float.
  final Animation<double>? ambient;

  static const nextKey = ValueKey('carousel-next');
  static const prevKey = ValueKey('carousel-prev');
  static ValueKey<String> dotKey(int i) => ValueKey('carousel-dot-$i');

  @override
  State<FeatureCarousel> createState() => _FeatureCarouselState();
}

class _Feature {
  const _Feature(this.eyebrow, this.title, this.text, this.shortText, this.icon, this.art, {this.chip, this.chipDashed = false});

  final String eyebrow;
  final String title;
  final String text;
  final String shortText;
  final IconData icon;

  /// The picture at build-in progress [t] (0 = nothing yet, 1 = complete).
  final Widget Function(Pal p, double t) art;

  /// A small glass label floating in front of the picture.
  final String? chip;
  final bool chipDashed;
}

final _features = <_Feature>[
  _Feature(
    'MAP EDITOR',
    'Draw every level of every branch.',
    'Spaces, doors and routes on one canvas. Publish when it is ready, and roll back to any earlier version.',
    'Spaces, doors and routes on one canvas, with versions you can roll back.',
    Icons.map_outlined,
    (p, t) => _GlassArt(p: p, child: CustomPaint(size: const Size(648, 420), painter: _PlanPainter(p, t))),
    chip: 'Published',
  ),
  _Feature(
    'BLUEPRINTS',
    'Turn a floor plan into a map.',
    'Upload a plan, set its scale with two clicks, and let LIQO trace the walls. You accept what fits.',
    'Upload a plan, set its scale, and let LIQO trace the walls.',
    Icons.architecture_outlined,
    (p, t) => _GlassArt(p: p, child: CustomPaint(size: const Size(648, 380), painter: _BlueprintPainter(p, t))),
    chip: 'Walls detected',
    chipDashed: true,
  ),
  _Feature(
    'STORES & ANNOUNCEMENTS',
    'Keep the directory current.',
    'Link each store to its space on the map. Store owners post announcements, and mall admins approve them before they go live.',
    'Stores linked to their spaces; announcements approved before they go live.',
    Icons.storefront_outlined,
    (p, t) => _StoresArt(p, t),
  ),
  _Feature(
    'INSIGHTS & AUDIT',
    'See what changed, and who changed it.',
    'Charts for each mall and branch, CSV export, and a log of every change made on the platform.',
    'Charts per mall and branch, CSV export, and a log of every change.',
    Icons.insights_outlined,
    (p, t) => _InsightsArt(p, t),
  ),
];

/// A drawn picture on its own glass card.
class _GlassArt extends StatelessWidget {
  const _GlassArt({required this.p, required this.child});

  final Pal p;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: innerGlass(p, radius: 26),
        child: child,
      );
}

class _FeatureCarouselState extends State<FeatureCarousel> {
  int _i = 0;
  Timer? _timer;

  /// Someone picked a slide: no more automatic moves on this visit.
  bool _stopped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _timer?.cancel();
      _timer = null;
    } else if (!_stopped && _timer == null) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (mounted) setState(() => _i = (_i + 1) % _features.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pick(int n) {
    _timer?.cancel();
    _timer = null;
    _stopped = true;
    setState(() => _i = (n + _features.length) % _features.length);
  }

  bool get _still => MediaQuery.disableAnimationsOf(context);

  Widget _switcher(Widget child) => AnimatedSwitcher(
        duration: _still ? Duration.zero : const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(a), child: c),
        ),
        child: KeyedSubtree(key: ValueKey(_i), child: child),
      );

  /// The stage: the picture floats in slight 3D perspective over a soft glow,
  /// turning in from the side as it builds (a parallax entrance), then
  /// drifting gently with the page's clock; a glass chip floats in front.
  Widget _stage(Pal p, _Feature f) => TweenAnimationBuilder<double>(
        key: ValueKey('art-$_i'),
        tween: Tween(begin: _still ? 1 : 0, end: 1),
        duration: _still ? Duration.zero : const Duration(milliseconds: 1400),
        builder: (context, t, _) {
          final turn = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
          Widget scene(double float) {
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0009)
              ..rotateX(0.13)
              ..rotateY(-0.20 - 0.16 * (1 - turn));
            return SizedBox(
              width: 820,
              height: 560,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // The glow the cards float above.
                  Positioned(
                    bottom: 26,
                    child: Transform.scale(
                      scaleY: 0.22,
                      child: Container(
                        width: 620,
                        height: 620,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [
                            p.brand.withValues(alpha: p.mix(0.22, 0.34) * turn),
                            Pal.brandCrimson.withValues(alpha: p.mix(0.08, 0.16) * turn),
                            p.brand.withValues(alpha: 0),
                          ], stops: const [
                            0,
                            0.45,
                            1
                          ]),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(40 * (1 - turn), -6 + float),
                    child: Transform(alignment: Alignment.center, transform: matrix, child: f.art(p, t)),
                  ),
                  if (f.chip != null)
                    Positioned(
                      right: 34,
                      top: 70 - float * 1.6,
                      child: Opacity(
                        opacity: Curves.easeOutCubic.transform(((t - 0.6) / 0.3).clamp(0.0, 1.0)),
                        child: _Chip(p: p, text: f.chip!, dashed: f.chipDashed),
                      ),
                    ),
                ],
              ),
            );
          }

          final ambient = widget.ambient;
          if (ambient == null || _still) return scene(0);
          return AnimatedBuilder(
            animation: ambient,
            builder: (context, _) => scene(5 * math.sin(2 * math.pi * ambient.value * 3)),
          );
        },
      );

  Widget _controls(Pal p) => Row(
        children: [
          for (var n = 0; n < _features.length; n++)
            Semantics(
              button: true,
              selected: n == _i,
              label: 'Show feature ${n + 1} of ${_features.length}',
              excludeSemantics: true,
              child: InkWell(
                key: FeatureCarousel.dotKey(n),
                borderRadius: BorderRadius.circular(8),
                onTap: () => _pick(n),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        width: n == _i ? 26 : 8,
                        height: 6,
                        decoration: BoxDecoration(
                          color: n == _i ? p.brand : p.pick(p.ink.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0.22)),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: n == _i ? [BoxShadow(color: p.brand.withValues(alpha: 0.5), blurRadius: 10)] : const [],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          _ArrowButton(key: FeatureCarousel.prevKey, icon: Icons.chevron_left, label: 'Previous feature', onTap: () => _pick(_i - 1), framed: !widget.compact),
          const SizedBox(width: 8),
          _ArrowButton(key: FeatureCarousel.nextKey, icon: Icons.chevron_right, label: 'Next feature', onTap: () => _pick(_i + 1), framed: !widget.compact),
        ],
      );

  /// Light blooms inside the glass panel: brand light from the top right, crimson depth from the bottom left.
  Widget _blooms(Pal p) => IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -0.75),
                    radius: 0.9,
                    colors: [p.brand.withValues(alpha: p.mix(0.16, 0.20)), p.brand.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.9, 0.95),
                    radius: 1.0,
                    colors: [Pal.brandCrimson.withValues(alpha: p.mix(0.10, 0.32)), Pal.brandCrimson.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final f = _features[_i];

    if (widget.compact) {
      return Semantics(
        container: true,
        label: 'What LIQO does',
        child: GlassSurface(
          radius: 22,
          tint: GlassSurface.showcaseTint(p),
          padding: const EdgeInsets.fromLTRB(18, 18, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _switcher(Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: innerGlass(p, radius: 12),
                    child: Icon(f.icon, size: 20, color: p.brand),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.eyebrow, style: ts(10, w: FontWeight.w800, color: p.brand2, ls: 1.6)),
                        const SizedBox(height: 4),
                        Text(f.title, style: ts(16, w: FontWeight.w800, color: p.ink, height: 1.25)),
                        const SizedBox(height: 4),
                        Text(f.shortText, style: ts(12.5, color: p.muted, height: 1.5)),
                      ],
                    ),
                  ),
                ],
              )),
              const SizedBox(height: 6),
              _controls(p),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'What LIQO does',
      child: GlassSurface(
        radius: 26,
        tint: GlassSurface.showcaseTint(p),
        child: Stack(
          children: [
            Positioned.fill(child: _blooms(p)),
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 38, 44, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Larger wordmark with the tagline under it (Round 14).
                      const BrandLockup(size: 40),
                      const Spacer(),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '0${_i + 1}', style: ts(12, w: FontWeight.w700, color: p.ink, ls: 1)),
                          TextSpan(text: ' / 0${_features.length}', style: ts(12, w: FontWeight.w700, color: p.sideNote, ls: 1)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _switcher(Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: ExcludeSemantics(child: FittedBox(child: _stage(p, f)))),
                        const SizedBox(height: 18),
                        Text(f.eyebrow, style: ts(11, w: FontWeight.w800, color: p.brand2, ls: 1.8)),
                        const SizedBox(height: 10),
                        Text(f.title, style: ts(32, w: FontWeight.w800, color: p.ink, ls: -0.8, height: 1.12)),
                        const SizedBox(height: 10),
                        Text(f.text, style: ts(15, color: p.muted, height: 1.6)),
                      ],
                    )),
                  ),
                  const SizedBox(height: 16),
                  _controls(p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small glass label floating in front of a picture.
class _Chip extends StatelessWidget {
  const _Chip({required this.p, required this.text, this.dashed = false});

  final Pal p;
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: innerGlass(p, radius: 14).copyWith(
          boxShadow: [
            BoxShadow(color: p.pick(Pal.brandCrimson.withValues(alpha: 0.14), Colors.black.withValues(alpha: 0.45)), blurRadius: 26, offset: const Offset(0, 14)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dashed
                ? Row(children: [
                    for (var i = 0; i < 3; i++) Container(width: 5, height: 2.5, margin: const EdgeInsets.only(right: 2), color: p.brand),
                  ])
                : Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: p.green,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: p.green.withValues(alpha: 0.6), blurRadius: 8)],
                    ),
                  ),
            const SizedBox(width: 10),
            Text(text, style: ts(15, w: FontWeight.w800, color: p.ink, height: 1.2)),
          ],
        ),
      );
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({super.key, required this.icon, required this.label, required this.onTap, this.framed = true});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Container(
          decoration: framed ? innerGlass(p, radius: 12).copyWith(boxShadow: const []) : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Icon(icon, size: 20, color: p.btnText)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Illustrations: drawn, not data. Generic placeholders only. Each takes a
// build-in progress t (0..1) so it assembles itself when its slide appears.
// ---------------------------------------------------------------------------

/// Progress of a step that runs from [a] to [b] within t, eased.
double _step(double t, double a, double b) => Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

Color _fade(Color c, double k) => c.withValues(alpha: c.a * k);

/// Dashes along [path], only the first [fraction] of its total length.
void _dashed(Canvas c, Path path, Paint paint, {double on = 1, double off = 8, double fraction = 1}) {
  final metrics = path.computeMetrics().toList();
  var budget = metrics.fold<double>(0, (s, m) => s + m.length) * fraction;
  for (final m in metrics) {
    var d = 0.0;
    while (d < m.length && budget > 0) {
      final len = math.min(math.min(on, m.length - d), budget);
      c.drawPath(m.extractPath(d, d + len), paint);
      budget -= on + off;
      d += on + off;
    }
  }
}

/// The point [fraction] of the way along [path].
Offset? _pointAt(Path path, double fraction) {
  final metrics = path.computeMetrics().toList();
  var at = metrics.fold<double>(0, (s, m) => s + m.length) * fraction;
  for (final m in metrics) {
    if (at <= m.length) return m.getTangentForOffset(at)?.position;
    at -= m.length;
  }
  return null;
}

/// Text whose baseline sits at [at] (like SVG text).
void _label(Canvas c, String s, Offset at, Color color, {double size = 10, bool center = false}) {
  if (color.a == 0) return;
  final tp = TextPainter(
    text: TextSpan(text: s, style: ts(size, w: FontWeight.w700, color: color, ls: 1.2, height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
  final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  tp.paint(c, Offset(center ? at.dx - tp.width / 2 : at.dx, at.dy - base));
}

Paint _stroke(Color c, [double w = 1]) => Paint()
  ..style = PaintingStyle.stroke
  ..color = c
  ..strokeWidth = w;

Paint _fill(Color c) => Paint()..color = c;

/// A soft light around a point (route heads, pins).
void _glow(Canvas c, Offset at, Color color, double radius) {
  c.drawCircle(
    at,
    radius,
    Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: radius)),
  );
}

/// A floor plan; the route from "You are here" to a store draws itself.
class _PlanPainter extends CustomPainter {
  _PlanPainter(this.p, this.t);

  final Pal p;
  final double t;

  @override
  void paint(Canvas c, Size size) {
    final base = _step(t, 0, 0.3);
    final outline = RRect.fromRectAndRadius(const Rect.fromLTWH(4, 4, 640, 412), const Radius.circular(28));
    c.drawRRect(outline, _fill(p.ink.withValues(alpha: 0.015 * base)));
    c.drawRRect(outline, _stroke(p.ink.withValues(alpha: 0.14 * base)));
    const stores = [
      Rect.fromLTWH(24, 24, 120, 146),
      Rect.fromLTWH(152, 24, 138, 70),
      Rect.fromLTWH(152, 102, 138, 68),
      Rect.fromLTWH(360, 24, 150, 146),
      Rect.fromLTWH(518, 24, 106, 146),
      Rect.fromLTWH(24, 250, 90, 146),
      Rect.fromLTWH(122, 250, 168, 146),
      Rect.fromLTWH(360, 250, 120, 70),
      Rect.fromLTWH(360, 328, 120, 68),
    ];
    for (var i = 0; i < stores.length; i++) {
      final k = _step(t, 0.04 + i * 0.03, 0.3 + i * 0.03);
      final rr = RRect.fromRectAndRadius(stores[i], const Radius.circular(8));
      c.drawRRect(rr, _fill(p.ink.withValues(alpha: 0.02 * k)));
      c.drawRRect(rr, _stroke(p.ink.withValues(alpha: 0.11 * k)));
    }
    _dashed(c, Path()..addOval(Rect.fromCircle(center: const Offset(325, 210), radius: 22)), _stroke(p.ink.withValues(alpha: 0.18 * base)), on: 3, off: 5);

    final pin = _step(t, 0.28, 0.42);
    if (pin > 0) {
      _glow(c, const Offset(60, 210), p.brand.withValues(alpha: 0.3 * pin), 22);
      c.drawCircle(const Offset(60, 210), 6 * pin, _fill(p.brand));
    }

    final route = Path()
      ..moveTo(60, 210)
      ..lineTo(556, 210)
      ..lineTo(556, 256);
    final drawn = _step(t, 0.38, 0.86);
    _dashed(c, route, _stroke(p.brand, 2.5)..strokeCap = StrokeCap.round, on: 0.5, off: 8.5, fraction: drawn);
    if (drawn > 0 && drawn < 1) {
      final head = _pointAt(route, drawn);
      if (head != null) _glow(c, head, p.brand.withValues(alpha: 0.55), 12);
    }
    final arrow = _step(t, 0.7, 0.8);
    c.drawPath(
      Path()
        ..moveTo(424, 201)
        ..lineTo(442, 210)
        ..lineTo(424, 219)
        ..lineTo(429, 210)
        ..close(),
      _fill(_fade(p.brand, arrow)),
    );

    final arrive = _step(t, 0.82, 1);
    final dest = RRect.fromRectAndRadius(const Rect.fromLTWH(488, 250, 136, 146), const Radius.circular(8));
    c.drawRRect(dest, _fill(p.brand.withValues(alpha: 0.02 + 0.07 * arrive)));
    c.drawRRect(dest, _stroke(Color.lerp(p.ink.withValues(alpha: 0.11), p.brand, arrive)!, 1 + 0.5 * arrive));
    if (arrive > 0) {
      _glow(c, const Offset(556, 262), p.brand.withValues(alpha: 0.35 * arrive), 18);
      c.drawCircle(const Offset(556, 262), 5 * arrive, _fill(p.brand2));
    }

    final labels = _step(t, 0.45, 0.8);
    _label(c, 'ATRIUM', const Offset(325, 250), _fade(p.sideNote, labels), center: true);
    _label(c, 'FOOD HALL', const Offset(206, 328), _fade(p.sideNote, labels), center: true);
    _label(c, 'CINEMA', const Offset(435, 102), _fade(p.sideNote, labels), center: true);
    _label(c, 'YOU ARE HERE', const Offset(40, 186), _fade(p.brand2, pin));
    _label(c, 'UNIT 214', const Offset(556, 340), _fade(p.brand2, arrive), center: true);
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.p != p || old.t != t;
}

/// A scanned plan; the detector's walls trace themselves, then the scale is set.
class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter(this.p, this.t);

  final Pal p;
  final double t;

  @override
  void paint(Canvas c, Size size) {
    const sheet = Rect.fromLTWH(24, 10, 600, 320);
    final rr = RRect.fromRectAndRadius(sheet, const Radius.circular(16));
    final sheetIn = _step(t, 0, 0.25);
    c.save();
    c.clipRRect(rr);
    final grid = _stroke(p.ink.withValues(alpha: 0.05 * sheetIn));
    for (var x = sheet.left; x < sheet.right; x += 24) {
      c.drawLine(Offset(x, sheet.top), Offset(x, sheet.bottom), grid);
    }
    for (var y = sheet.top; y < sheet.bottom; y += 24) {
      c.drawLine(Offset(sheet.left, y), Offset(sheet.right, y), grid);
    }
    c.restore();
    c.drawRRect(rr, _stroke(p.ink.withValues(alpha: 0.14 * sheetIn)));

    final walls = Path()
      ..addRect(const Rect.fromLTRB(80, 50, 568, 290))
      ..moveTo(80, 160)
      ..lineTo(300, 160)
      ..moveTo(300, 50)
      ..lineTo(300, 230)
      ..moveTo(420, 160)
      ..lineTo(420, 290)
      ..moveTo(420, 160)
      ..lineTo(568, 160)
      ..moveTo(190, 230)
      ..lineTo(420, 230);
    c.drawPath(walls, _stroke(p.faint.withValues(alpha: 0.55 * _step(t, 0.1, 0.38)), 7)..strokeCap = StrokeCap.square);

    final found = Path()
      ..moveTo(80, 50)
      ..lineTo(568, 50)
      ..moveTo(80, 50)
      ..lineTo(80, 290)
      ..moveTo(80, 160)
      ..lineTo(300, 160)
      ..moveTo(300, 50)
      ..lineTo(300, 230);
    final traced = _step(t, 0.36, 0.82);
    _dashed(c, found, _stroke(p.brand, 2)..strokeCap = StrokeCap.round, on: 7, off: 5, fraction: traced);
    if (traced > 0 && traced < 1) {
      final head = _pointAt(found, traced);
      if (head != null) _glow(c, head, p.brand.withValues(alpha: 0.5), 12);
    }

    final scale = _step(t, 0.78, 0.94);
    if (scale > 0) {
      c.drawLine(const Offset(80, 352), Offset(80 + 220 * scale, 352), _stroke(p.brand2, 1.5));
      c.drawCircle(const Offset(80, 352), 5, _fill(p.brand2));
      c.drawCircle(Offset(80 + 220 * scale, 352), 5, _fill(p.brand2));
    }
    _label(c, '12.0 m', const Offset(190, 344), _fade(p.brand2, _step(t, 0.9, 1)), size: 11, center: true);

    final legendIn = _step(t, 0.84, 1);
    if (legendIn > 0) {
      final legend = RRect.fromRectAndRadius(const Rect.fromLTWH(444, 304, 180, 58), const Radius.circular(10));
      c.drawRRect(legend, _fill(_fade(p.panel, legendIn)));
      c.drawRRect(legend, _stroke(_fade(p.line, legendIn)));
      c.drawLine(const Offset(460, 323), const Offset(484, 323), _stroke(p.faint.withValues(alpha: 0.7 * legendIn), 5));
      _label(c, 'PLAN', const Offset(494, 327), _fade(p.muted, legendIn), size: 10.5);
      _dashed(
          c,
          Path()
            ..moveTo(460, 345)
            ..lineTo(484, 345),
          _stroke(_fade(p.brand, legendIn), 2),
          on: 7,
          off: 5);
      _label(c, 'DETECTED WALLS', const Offset(494, 349), _fade(p.muted, legendIn), size: 10.5);
    }
  }

  @override
  bool shouldRepaint(_BlueprintPainter old) => old.p != p || old.t != t;
}

/// Seven bars that grow one after another, and a line that draws over them.
class _ChartPainter extends CustomPainter {
  _ChartPainter(this.p, this.t);

  final Pal p;
  final double t;

  @override
  void paint(Canvas c, Size size) {
    final grid = _stroke(p.ink.withValues(alpha: 0.05));
    for (final y in [40.0, 80.0, 120.0]) {
      c.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const heights = [48.0, 64.0, 40.0, 76.0, 60.0, 32.0, 92.0];
    const days = ['Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed'];
    final line = Path();
    for (var i = 0; i < 7; i++) {
      final x = 30.0 + i * 92;
      final last = i == 6;
      final h = heights[i] * _step(t, 0.12 + i * 0.06, 0.5 + i * 0.06);
      if (h > 0.5) {
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, 120 - h, 44, h), Radius.circular(math.min(6, h / 2))),
          _fill(last ? p.brand : p.brand.withValues(alpha: 0.32)),
        );
      }
      final pt = Offset(x + 22, 120 - heights[i] - 10 - (i.isEven ? 4 : 0));
      i == 0 ? line.moveTo(pt.dx, pt.dy) : line.lineTo(pt.dx, pt.dy);
      _label(c, days[i], Offset(x + 22, 142), last ? p.ink : p.sideNote, size: 10.5, center: true);
    }
    final drawn = _step(t, 0.55, 0.95);
    if (drawn > 0) {
      final partial = Path();
      for (final m in line.computeMetrics()) {
        partial.addPath(m.extractPath(0, m.length * drawn), Offset.zero);
      }
      c.drawPath(partial, _stroke(p.brand2, 2)..strokeJoin = StrokeJoin.round);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.p != p || old.t != t;
}

/// Cards inside the showcase are glass too (the panel already blurs what is behind).
BoxDecoration _artCard(Pal p) => innerGlass(p);

Widget _pill(Pal p, String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(10.5, w: FontWeight.w700, color: fg, height: 1.2)),
    );

/// Fades and lifts [child] in as [k] goes from 0 to 1.
Widget _enter(double k, Widget child, {double dy = 14}) => Opacity(
      opacity: k,
      child: Transform.translate(offset: Offset(0, dy * (1 - k)), child: child),
    );

/// A store directory card and an announcement waiting for review, sliding in.
class _StoresArt extends StatelessWidget {
  const _StoresArt(this.p, this.t);

  final Pal p;
  final double t;

  Widget _row(int i, String initials, String name, String unit, bool onMap) => _enter(
        _step(t, 0.2 + i * 0.1, 0.55 + i * 0.1),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.rowLine))),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: i == 0 ? p.iconBg : p.boxBg, borderRadius: BorderRadius.circular(8)),
                child: Text(initials, style: ts(11, w: FontWeight.w800, color: i == 0 ? p.brand2 : p.slate)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: ts(12.5, w: FontWeight.w700, color: p.ink)),
                    Text(unit, style: ts(11, color: p.muted)),
                  ],
                ),
              ),
              Text(onMap ? 'On map' : 'Not on map', style: ts(10.5, w: FontWeight.w700, color: onMap ? p.green : p.muted)),
            ],
          ),
        ),
        dy: 8,
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 648,
        height: 380,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _enter(
              _step(t, 0, 0.4),
              Container(
                width: 330,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                decoration: _artCard(p),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Store directory', style: ts(13, w: FontWeight.w800, color: p.ink))),
                        _pill(p, 'L2', p.brand2, p.iconBg),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _row(0, 'SA', 'Store A', 'Unit 214', true),
                    _row(1, 'SB', 'Store B', 'Unit 118', true),
                    _row(2, 'SC', 'Store C', 'Unit 305', false),
                  ],
                ),
              ),
              dy: 18,
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: _enter(
                _step(t, 0.35, 0.8),
                Container(
                  width: 290,
                  padding: const EdgeInsets.all(18),
                  decoration: _artCard(p),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ANNOUNCEMENT', style: ts(10, w: FontWeight.w800, color: p.muted, ls: 1.4)),
                      const SizedBox(height: 8),
                      Text('Weekend sale at Store A', style: ts(15, w: FontWeight.w800, color: p.ink, height: 1.3)),
                      const SizedBox(height: 6),
                      Text('Selected items on sale this Saturday and Sunday.', style: ts(12, color: p.muted, height: 1.5)),
                      const SizedBox(height: 6),
                      Text('Sat → Sun', style: ts(11, color: p.sideNote)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.rowLine))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(child: _pill(p, 'Waiting for review', p.warn, p.noticeBg)),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: p.brand,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [BoxShadow(color: p.brand.withValues(alpha: 0.35 * _step(t, 0.75, 1)), blurRadius: 14)],
                              ),
                              child: Text('Approve', style: ts(11, w: FontWeight.w700, color: Colors.white, height: 1.2)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                dy: 22,
              ),
            ),
          ],
        ),
      );
}

/// A chart whose bars grow, and two audit rows that slide in.
class _InsightsArt extends StatelessWidget {
  const _InsightsArt(this.p, this.t);

  final Pal p;
  final double t;

  Widget _audit(int i, Color dot, String who, String what, String time) => _enter(
        _step(t, 0.55 + i * 0.12, 0.85 + i * 0.12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: p.rowLine))),
          child: Row(
            children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$who ', style: ts(12.5, w: FontWeight.w700, color: p.ink)),
                  TextSpan(text: what, style: ts(12.5, color: p.muted)),
                ])),
              ),
              Text(time, style: ts(11, color: p.sideNote)),
            ],
          ),
        ),
        dy: 8,
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 700,
        height: 380,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _enter(
              _step(t, 0, 0.35),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                decoration: _artCard(p),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Sign-ins, last 7 days', style: ts(13, w: FontWeight.w800, color: p.ink))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(border: Border.all(color: p.fieldLine), borderRadius: BorderRadius.circular(8)),
                          child: Text('Export CSV', style: ts(11, w: FontWeight.w700, color: p.btnText, height: 1.2)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    CustomPaint(size: const Size(640, 150), painter: _ChartPainter(p, t)),
                  ],
                ),
              ),
              dy: 16,
            ),
            const SizedBox(height: 14),
            _enter(
              _step(t, 0.45, 0.75),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: _artCard(p),
                child: Column(
                  children: [
                    _audit(0, p.brand, 'Mall owner', 'published a branch map', '10:42'),
                    _audit(1, p.chart[1], 'Mall admin', 'linked Store A to Unit 214', '10:15'),
                  ],
                ),
              ),
              dy: 16,
            ),
          ],
        ),
      );
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Frosted glass for the login page (owner decisions 2026-10-22): the living
/// background behind is blurred (only the area behind this surface), a tint
/// sits on top, then a hairline border and a soft highlight on the top edge.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    required this.tint,
    this.blur = 24,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;

  /// Top-left to bottom-right tint over the blur.
  final List<Color> tint;
  final double blur;
  final EdgeInsetsGeometry padding;

  /// The sign-in card's glass: neutral, readable.
  static List<Color> cardTint(Pal p) => [
        p.pick(Colors.white.withValues(alpha: 0.78), p.panel.withValues(alpha: 0.74)),
        p.pick(Colors.white.withValues(alpha: 0.62), p.panel.withValues(alpha: 0.62)),
      ];

  /// The showcase panel's glass: obsidian to deep crimson in dark mode,
  /// frosted white with a peach-to-rose tint in light mode.
  static List<Color> showcaseTint(Pal p) => [
        p.pick(Colors.white.withValues(alpha: 0.66), p.shell.withValues(alpha: 0.80)),
        p.pick(Color.lerp(Colors.white, p.brand, 0.10)!.withValues(alpha: 0.58), Color.lerp(p.shell, Pal.brandCrimson, 0.28)!.withValues(alpha: 0.74)),
        p.pick(Color.lerp(Colors.white, Pal.brandCrimson, 0.10)!.withValues(alpha: 0.58), Color.lerp(p.shell, Pal.brandCrimson, 0.55)!.withValues(alpha: 0.70)),
      ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: tint),
            border: Border.all(color: Colors.white.withValues(alpha: p.mix(0.85, 0.08))),
          ),
          child: Stack(
            children: [
              // The highlight a curved glass edge catches from above.
              Positioned(
                top: 0,
                left: radius,
                right: radius,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: p.mix(0.9, 0.22)),
                        Colors.white.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass for cards inside an already-blurred surface: tint, hairline and a
/// soft drop shadow, without a second (costly) blur.
BoxDecoration innerGlass(Pal p, {double radius = 18}) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white.withValues(alpha: p.mix(0.88, 0.085)), Colors.white.withValues(alpha: p.mix(0.62, 0.03))],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: p.mix(1, 0.11))),
      boxShadow: [
        BoxShadow(
          color: p.pick(Pal.brandCrimson.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.38)),
          blurRadius: 34,
          offset: const Offset(0, 18),
        ),
      ],
    );

// Drawn placeholders until real store logos and photos exist (owner decision
// 2026-10-22: no images of real brands): an initials tile for a logo, and a
// drawn storefront for a photo.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'glyphs.dart';

int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// "Opal Comics" -> "OC"; "Bayview Department Store" -> "BD".
String initialsOf(String name) {
  final words = name.split(RegExp(r'[\s·&\-]+')).where((w) => w.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(w[0])).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, math.min(2, words.first.length)).toUpperCase();
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

/// A store's logo stand-in: its initials on a tile colour picked from its name.
class InitialsTile extends StatelessWidget {
  const InitialsTile(this.name, {super.key, this.size = 44});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal, bg = p.tiles[_hash(name) % p.tiles.length];
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .24)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.all(size * .12),
            child: Text(initialsOf(name), textScaler: TextScaler.noScaling, style: ts(size * .38, w: FontWeight.w800, color: Pal.brandLight, height: 1)),
          ),
        ),
      ),
    );
  }
}

/// A drawn picture: a storefront with an awning, the category's glyph in the window,
/// in one of the tile colours. Fills its box.
class DrawnArt extends StatelessWidget {
  const DrawnArt({super.key, required this.motif, required this.tone, this.seed = 0, this.semanticLabel});
  final String motif;
  final int tone, seed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final base = p.tiles[tone % p.tiles.length];
    return Semantics(
      image: semanticLabel != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: CustomPaint(painter: _ArtPainter(motif, base, p.pick(Pal.brandLight, Pal.brandDark), seed), size: Size.infinite),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.motif, this.base, this.paper, this.seed);
  final String motif;
  final Color base, paper;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, r = Offset.zero & size;
    // the sky: the tile colour, lighter at the top
    canvas.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(base, paper, .55)!, Color.lerp(base, paper, .25)!]).createShader(r));
    // the shop front
    final front = Rect.fromLTWH(w * .14, h * .30, w * .72, h * .70);
    canvas.drawRect(front, Paint()..color = Color.lerp(base, paper, .82)!);
    // the awning: stripes in the tile colour
    final stripes = 7 + seed % 3, aw = front.width / stripes, top = front.top, ah = h * .12;
    for (var i = 0; i < stripes; i++) {
      final x = front.left + i * aw;
      final path = Path()
        ..moveTo(x, top)
        ..lineTo(x + aw, top)
        ..lineTo(x + aw, top + ah)
        ..arcToPoint(Offset(x, top + ah), radius: Radius.circular(aw / 2))
        ..close();
      canvas.drawPath(path, Paint()..color = i.isEven ? base : paper);
    }
    // the window, with the category's glyph
    final win = Rect.fromLTWH(front.left + front.width * .12, top + ah + h * .08, front.width * .5, front.height * .42);
    canvas.drawRRect(RRect.fromRectAndRadius(win, Radius.circular(w * .02)), Paint()..color = Color.lerp(base, paper, .35)!);
    final g = math.min(win.width, win.height) * .62;
    drawGlyph(canvas, glyphOf(motif), Rect.fromCenter(center: win.center, width: g, height: g), paper, strokeWidth: 1.6);
    // the door
    final door = Rect.fromLTWH(front.left + front.width * .70, top + ah + h * .08, front.width * .2, front.bottom - (top + ah + h * .08));
    canvas.drawRRect(RRect.fromRectAndCorners(door, topLeft: Radius.circular(w * .02), topRight: Radius.circular(w * .02)), Paint()..color = base);
    // the floor line
    canvas.drawRect(Rect.fromLTWH(0, h * .96, w, h * .04), Paint()..color = Color.lerp(base, paper, .1)!);
  }

  @override
  bool shouldRepaint(_ArtPainter o) => o.motif != motif || o.base != base || o.paper != paper || o.seed != seed;
}

// The demo's line icons (24x24, stroked, round caps and joins), used on the map
// and its panels; the other screens use Material icons (owner decision 2026-10-22).
import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../../core/theme.dart';

// Each icon is a list of SVG elements: 'p:<path data>', 'c:cx,cy,r', 'r:x,y,w,h,rx'.
const Map<String, List<String>> _src = {
  'i-search': ['c:11,11,6.5', 'p:M20 20l-4.2-4.2'],
  'i-plus': ['p:M12 5v14M5 12h14'],
  'i-minus': ['p:M5 12h14'],
  'i-close': ['p:M6 6l12 12M18 6L6 18'],
  'i-up': ['p:M6 15l6-6 6 6'],
  'i-down': ['p:M6 9l6 6 6-6'],
  'i-left': ['p:M15 6l-6 6 6 6'],
  'i-nav': ['p:M12 3l7 17-7-4-7 4z'],
  'i-cube': ['p:M12 3l8 4.5v9L12 21l-8-4.5v-9z', 'p:M12 12l8-4.5M12 12v9M12 12L4 7.5'],
  'i-layers': ['p:M12 3l9 5-9 5-9-5z', 'p:M3 12.5l9 5 9-5M3 17l9 5 9-5'],
  'i-site': ['p:M3 21V10l6-3v14M9 21V4l8 3v14M17 21v-7h4v7M2 21h20'],
  'i-map': ['p:M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z', 'p:M9 4v14M15 6v14'],
  'i-pin': ['p:M12 21s-6.5-5.6-6.5-10.5a6.5 6.5 0 0 1 13 0C18.5 15.4 12 21 12 21z', 'c:12,10.5,2.3'],
  'i-user': ['c:12,8,4', 'p:M4 21a8 8 0 0 1 16 0'],
  'i-check': ['p:M5 12.5l4.5 4.5L19 7.5'],
  'i-x': ['p:M7 7l10 10M17 7L7 17'],
  'i-wrench': ['p:M14.5 6.5a4 4 0 0 0 4.9 4.9L20 12 12 20a2.1 2.1 0 0 1-3-3l8-8z'],
  'i-clock': ['c:12,12,8', 'p:M12 7.5V12l3 2'],
  'i-walk': ['c:13,4.5,1.8', 'p:M10 21l2-7-2.5-2.5L11 8l4 2 2 3M12 14l3 2 1 5'],
  'i-bridge': ['p:M3 15h18M5 15v-4a7 7 0 0 1 14 0v4M8 15v3M16 15v3'],
  'g-books': ['p:M5 4h11a2 2 0 0 1 2 2v14H7a2 2 0 0 1-2-2z', 'p:M9 8h6'],
  'g-food': ['p:M5 9h11v4a5 5 0 0 1-5 5h-1a5 5 0 0 1-5-5z', 'p:M16 11h2a2 2 0 0 1 0 4h-2M8 3.5v2M12 3.5v2'],
  'g-fashion': ['p:M12 9V8a2.2 2.2 0 1 0-2.2-2.2', 'p:M12 9L3.5 16.5a1 1 0 0 0 .6 1.8h15.8a1 1 0 0 0 .6-1.8z'],
  'g-services': ['p:M3.5 12.5l9-9H20v7.5l-9 9z', 'c:15.5,8.5,1.2'],
  'g-other': ['p:M6 8h12l1 12H5z', 'p:M9 8a3 3 0 0 1 6 0'],
  'g-tech': ['r:7,3,10,18,2', 'p:M11 18h2'],
  'g-cinema': ['r:3,6,18,12,2', 'p:M8 6v12M16 6v12M3 10h5M16 10h5M3 14h5M16 14h5'],
  'g-restroom': ['c:8,5,1.6', 'p:M8 8.5V15M5.5 21L8 15l2.5 6', 'c:16.5,5,1.6', 'p:M16.5 8.5V21'],
  'g-atm': ['c:12,12,8.5', 'p:M14.5 9.2c-.6-.8-1.4-1.1-2.5-1.1-1.4 0-2.3.7-2.3 1.7 0 2.4 4.8 1 4.8 3.6 0 1-.9 1.8-2.5 1.8-1.1 0-2-.4-2.6-1.2M12 6.5v1.6M12 15.9v1.6'],
  'g-exit': ['p:M4 20V4h9v16M13 12h8M18 8l3 4-3 4'],
  'g-entrance': ['p:M4 20V4h9v16M13 12h8M18 8l3 4-3 4'],
  'g-lift': ['p:M5 3h14v18H5z', 'p:M12 7.5l-2.5 3h5zM12 16.5l-2.5-3h5z'],
  'g-stairs': ['p:M4 20h5v-4h5v-4h5V8h1'],
  'g-escalator': ['p:M3 19h5l8-9h5', 'p:M14 6l3 3-3 3'],
  'g-info': ['c:12,12,8.5', 'p:M12 11v5M12 8v.01'],
  'g-ev': ['p:M13 3L6 13h5l-1 8 7-10h-5z'],
  'g-parking': ['r:4,4,16,16,3', 'p:M10 17V8h3a2.5 2.5 0 0 1 0 5h-3'],
  'g-bus': ['r:5,3.5,14,14,2.5', 'p:M5 11h14M8 20v-2.5M16 20v-2.5'],
  'i-play': ['p:M8 5.5v13l10.5-6.5z'],
  'i-pause': ['p:M8 5.5v13M16 5.5v13'],
  'i-more': ['c:12,5.5,1.4', 'c:12,12,1.4', 'c:12,18.5,1.4'],
  // the map turns to face the way you walk
  // my location (a crosshair) and the floors
  'i-locate': ['c:12,12,6.5', 'c:12,12,2.2', 'p:M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3'],
  'i-floors': ['p:M5 7h14M5 12h14M5 17h14'],
  'i-headup': ['c:12,12,9', 'p:M12 6.5l3.8 9.5-3.8-2.4-3.8 2.4z'],
  // Turn-by-turn arrows (the direction card)
  'i-straight': ['p:M12 20V5M6 11l6-6 6 6'],
  'i-turn-left': ['p:M14 20v-7a3 3 0 0 0-3-3H5M9 6l-4 4 4 4'],
  'i-turn-right': ['p:M10 20v-7a3 3 0 0 1 3-3h6M15 6l4 4-4 4'],
  'i-turn-slight-left': ['p:M14 20v-8L8 6M8 12V6h6'],
  'i-turn-slight-right': ['p:M10 20v-8l6-6M16 12V6h-6'],
  'i-turn-sharp-left': ['p:M15 20V7l-8 6M7 13V8M7 13h5'],
  'i-turn-sharp-right': ['p:M9 20V7l8 6M17 13V8M17 13h-5'],
  'i-star': ['p:M12 3.5l2.6 5.6 6.1.7-4.5 4.2 1.2 6-5.4-3-5.4 3 1.2-6L3.3 9.8l6.1-.7z'],
  // Rerouting and evacuation
  'i-alert': ['p:M12 3.5L2.5 20h19z', 'p:M12 10v4.5M12 17.3v.01'],
  'i-detour': ['p:M6 21v-6a4 4 0 0 1 4-4h9', 'p:M16 7.5l3.5 3.5-3.5 3.5', 'p:M6 9V3'],
  'i-help': ['c:12,12,8.5', 'p:M9.6 9.6a2.5 2.5 0 1 1 3.4 2.3c-.7.3-1 .8-1 1.5v.4M12 16.8v.01'],
  'i-flag': ['p:M6 21V4M6 4h11l-2 4 2 4H6'],
  // New venues
  'g-ramp': ['p:M3 19h18L3 9z', 'p:M8 15.5l4-1'],
  'g-arena': ['p:M3 12c0-3.9 4-7 9-7s9 3.1 9 7-4 7-9 7-9-3.1-9-7z', 'p:M7.5 12c0-1.9 2-3.5 4.5-3.5s4.5 1.6 4.5 3.5-2 3.5-4.5 3.5-4.5-1.6-4.5-3.5z'],
  'g-garden': ['p:M12 21v-8', 'p:M12 13c-4 0-6-3-6-7 4 0 6 3 6 7zM12 13c4 0 6-3 6-7-4 0-6 3-6 7z'],
  'g-train': ['r:6,3,12,14,3', 'p:M6 10h12M9 20l-2 2M15 20l2 2M9 14h.01M15 14h.01'],
};

final Map<String, Path> _cache = {};

Path glyphPath(String id) => _cache.putIfAbsent(id, () {
      final path = Path();
      for (final el in _src[id] ?? const <String>[]) {
        final body = el.substring(2);
        switch (el[0]) {
          case 'p':
            path.addPath(parseSvgPathData(body), Offset.zero);
          case 'c':
            final v = body.split(',').map(double.parse).toList();
            path.addOval(Rect.fromCircle(center: Offset(v[0], v[1]), radius: v[2]));
          case 'r':
            final v = body.split(',').map(double.parse).toList();
            path.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(v[0], v[1], v[2], v[3]), Radius.circular(v[4])));
        }
      }
      return path;
    });

/// The glyph used for a category.
String glyphOf(String c) => c == 'entrance' ? 'g-entrance' : 'g-$c';

/// Draws a glyph into [dest], stroked.
void drawGlyph(Canvas canvas, String id, Rect dest, Color color, {double strokeWidth = 2}) {
  final s = dest.width / 24;
  canvas.save();
  canvas.translate(dest.left, dest.top);
  canvas.scale(s, dest.height / 24);
  canvas.drawPath(
    glyphPath(id),
    Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.restore();
}

/// A line icon.
class AppIcon extends StatelessWidget {
  final String id;
  final double size;
  final Color? color;
  final double strokeWidth;
  const AppIcon(this.id, {super.key, this.size = 22, this.color, this.strokeWidth = 2});

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? context.pal.ink;
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _GlyphPainter(id, c, strokeWidth)));
  }
}

class _GlyphPainter extends CustomPainter {
  final String id;
  final Color color;
  final double sw;
  _GlyphPainter(this.id, this.color, this.sw);
  @override
  void paint(Canvas canvas, Size size) => drawGlyph(canvas, id, Offset.zero & size, color, strokeWidth: sw);
  @override
  bool shouldRepaint(_GlyphPainter o) => o.id != id || o.color != color || o.sw != sw;
}

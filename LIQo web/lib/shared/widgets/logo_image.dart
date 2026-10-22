import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'skeleton.dart';

/// A mall's or branch's logo in a rounded square. Shows the name's initials
/// when there is no logo, or when the image cannot be loaded, so a bad URL
/// is visible at once instead of failing silently.
class LogoImage extends StatelessWidget {
  const LogoImage({super.key, required this.url, required this.name, this.size = 24});

  final String? url;
  final String name;
  final double size;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(size * 0.24);
    final monogram = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.soft, borderRadius: radius, border: Border.all(color: p.line)),
      child: Text(_initials, maxLines: 1, style: ts(size * 0.38, w: FontWeight.w800, color: p.brand2, height: 1)),
    );
    final link = url?.trim() ?? '';
    if (link.isEmpty) return monogram;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.panel, borderRadius: radius, border: Border.all(color: p.line)),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.network(
          link,
          width: size,
          height: size,
          fit: BoxFit.contain,
          // Hosts without CORS headers still render, through a plain <img> element.
          webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          errorBuilder: (_, __, ___) => monogram,
          loadingBuilder: (context, child, progress) => progress == null ? child : SizedBox(width: size, height: size, child: SkeletonBox(height: size, radius: size * 0.24)),
        ),
      ),
    );
  }
}

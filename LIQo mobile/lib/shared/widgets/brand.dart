// The LIQo brand pieces: images with a light and a dark version (cut by
// tool/crop_brand.mjs, never edited by hand), the wordmark, the app tile, the
// IQ mark and the tagline. Built like LIQo web's (shared/widgets/common.dart).
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// An image with a light-mode and a dark-mode version. While the theme morphs,
/// the two cross-fade in step with the colours; otherwise only the current one is drawn.
class ThemedAsset extends StatelessWidget {
  const ThemedAsset({super.key, required this.light, required this.dark, this.width, this.height, this.fit, this.semanticLabel, this.alignment = Alignment.center});

  final String light, dark;
  final double? width, height;
  final BoxFit? fit;
  final String? semanticLabel;
  final AlignmentGeometry alignment;

  Widget _image(String path, {bool label = true}) => Image.asset(
        path,
        width: width,
        height: height,
        fit: fit,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        semanticLabel: label ? semanticLabel : null,
        excludeFromSemantics: !label || semanticLabel == null,
      );

  @override
  Widget build(BuildContext context) {
    final d = context.pal.darkness;
    if (d <= 0) return _image(light);
    if (d >= 1) return _image(dark);
    return Stack(
      alignment: alignment,
      children: [
        Opacity(opacity: 1 - d, child: _image(light, label: d < 0.5)),
        Opacity(opacity: d, child: _image(dark, label: d >= 0.5)),
      ],
    );
  }
}

/// The brand's tagline (as on web, replacing "Navigate Your World").
const brandTagline = 'Smart Way Forward';

/// The LIQO wordmark: white letters in dark mode, brand-dark letters in light mode.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 20});

  /// Height of the wordmark in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) => ThemedAsset(
        light: 'assets/brand/logo-light.png',
        dark: 'assets/brand/logo-dark.png',
        height: size,
        semanticLabel: 'LIQo',
      );
}

/// The app tile: the dark tile in dark mode, the light tile in light mode.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 34});

  /// Its width; the tile is slightly wider than tall.
  final double size;

  /// Height over width of the tile (as cut by tool/crop_brand.mjs).
  static const aspect = 134 / 143;

  @override
  Widget build(BuildContext context) => ThemedAsset(
        light: 'assets/brand/icon-light.png',
        dark: 'assets/brand/icon-dark.png',
        width: size,
        height: size * aspect,
        fit: BoxFit.fill,
        semanticLabel: 'LIQo',
      );
}

/// The IQ mark on its own.
class IqMark extends StatelessWidget {
  const IqMark({super.key, this.size = 32, this.label = true});
  final double size;
  final bool label;

  @override
  Widget build(BuildContext context) => ThemedAsset(
        light: 'assets/brand/iq-light.png',
        dark: 'assets/brand/iq-dark.png',
        height: size,
        semanticLabel: label ? 'LIQo' : null,
      );
}

/// The wordmark with the tagline under it.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.size = 44, this.taglineSize = 14, this.center = true});
  final double size, taglineSize;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandWordmark(size: size),
        SizedBox(height: size * .18),
        Text(brandTagline, textAlign: center ? TextAlign.center : TextAlign.start, style: ts(taglineSize, w: FontWeight.w700, color: p.brand2, ls: .6)),
      ],
    );
  }
}

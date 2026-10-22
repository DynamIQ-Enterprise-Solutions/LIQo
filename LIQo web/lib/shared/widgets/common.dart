import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

// ---------------------------------------------------------------------------
// Brand logo: the LIQO wordmark from the brand board, 1:1, white letters in
// dark mode and brand-dark letters in light mode. The orange IQ mark is the same in both.
// ---------------------------------------------------------------------------

/// An image with a light-mode and a dark-mode version. While the theme
/// morphs, the two cross-fade in step with the colours (owner decision
/// 2026-10-22); otherwise only the current one is drawn.
class ThemedAsset extends StatelessWidget {
  const ThemedAsset({super.key, required this.light, required this.dark, this.width, this.height, this.fit, this.semanticLabel, this.alignment = Alignment.centerLeft});

  final String light;
  final String dark;
  final double? width;
  final double? height;
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

/// The brand's tagline (owner decision 2026-10-22, replacing "Navigate Your World").
const brandTagline = 'Smart Way Forward';

/// The wordmark with the tagline under it (login page, Round 14).
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.size = 40, this.taglineSize = 12.5});

  final double size;
  final double taglineSize;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandWordmark(size: size),
        SizedBox(height: size * 0.12),
        Padding(
          padding: EdgeInsets.only(left: size * 0.06),
          child: Text(brandTagline, style: ts(taglineSize, w: FontWeight.w700, color: p.brand2, ls: 0.6)),
        ),
      ],
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 20});

  /// Height of the wordmark in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) => ThemedAsset(
        light: 'assets/brand/logo-light.png',
        dark: 'assets/brand/logo-dark.png',
        height: size,
        semanticLabel: 'LIQO',
      );
}

/// The app tile from the brand guidelines: dark tile in dark mode, light tile
/// in light mode. [size] is its width; the guidelines' tile is slightly wider
/// than tall, and is drawn at its true proportions.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 34});

  final double size;

  /// Height over width of the tile (143 × 134 px, cut by tool/crop_brand.mjs).
  static const aspect = 134 / 143;

  /// Corner radius over width (27 px on the 143 px tile).
  static const radiusShare = 27 / 143;

  @override
  Widget build(BuildContext context) => ThemedAsset(
        light: 'assets/brand/icon-light.png',
        dark: 'assets/brand/icon-dark.png',
        width: size,
        height: size * aspect,
        fit: BoxFit.fill,
        semanticLabel: 'LIQO',
        alignment: Alignment.center,
      );
}

/// The light/dark switch's icon: the sun and the moon rotate and swap in
/// step with the theme's colour morph (owner decision 2026-10-22). Shows the
/// sun in dark mode (switch to light) and the moon in light mode.
class ThemeToggleIcon extends StatelessWidget {
  const ThemeToggleIcon({super.key, this.size = 16, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = context.pal.darkness;
    final ease = Curves.easeInOutCubic.transform(d);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (d < 1)
            Opacity(
              opacity: 1 - ease,
              child: Transform.rotate(angle: ease * 1.6, child: Transform.scale(scale: 1 - 0.4 * ease, child: Icon(Icons.dark_mode_outlined, size: size, color: color))),
            ),
          if (d > 0)
            Opacity(
              opacity: ease,
              child: Transform.rotate(angle: -(1 - ease) * 1.6, child: Transform.scale(scale: 0.6 + 0.4 * ease, child: Icon(Icons.light_mode_outlined, size: size, color: color))),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.panel,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: p.shadow,
      ),
      child: child,
    );
  }
}

class CardHead extends StatelessWidget {
  const CardHead({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 15 : 20,
        vertical: mobile ? 15 : 18,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.softLine)),
      ),
      child: Builder(builder: (context) {
        final titles = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ts(14, w: FontWeight.w700, color: p.ink)),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle!, style: ts(11, color: p.muted)),
              ),
          ],
        );
        if (trailing == null) return titles;
        // Phones: the control goes under the title instead of fighting it for width.
        if (mobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [titles, const SizedBox(height: 10), trailing!],
          );
        }
        return Row(
          children: [
            Expanded(child: titles),
            const SizedBox(width: 12),
            trailing!,
          ],
        );
      }),
    );
  }
}

class CardBody extends StatelessWidget {
  const CardBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mobile = Bp.isMobile(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 15 : 20,
        vertical: mobile ? 15 : 18,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Pill
// ---------------------------------------------------------------------------

enum PillKind { green, pending, off, blue }

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.kind = PillKind.green});

  final String text;
  final PillKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    // Tinted backgrounds come from the semantic colour itself, so both modes stay in tune.
    final tint = p.mix(28, 46).round();
    late final Color bg;
    late final Color fg;
    switch (kind) {
      case PillKind.green:
        bg = p.green.withAlpha(tint);
        fg = p.green;
        break;
      case PillKind.pending:
        bg = p.warn.withAlpha(tint);
        fg = p.warn;
        break;
      case PillKind.off:
        bg = p.boxBg;
        fg = p.muted;
        break;
      case PillKind.blue:
        bg = p.soft;
        fg = p.brand2;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: ts(10, w: FontWeight.w700, color: fg)),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.small = false,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final radius = BorderRadius.circular(9);
    final fg = primary ? Colors.white : p.btnText;
    final fontSize = small ? 11.0 : 12.0;
    return Material(
      color: primary ? p.brand : p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: primary ? p.brand : p.fieldLine),
      ),
      child: InkWell(
        borderRadius: radius,
        hoverColor: primary ? p.brand2.withAlpha(p.mix(255, 60).round()) : p.hover,
        onTap: onPressed,
        child: Padding(
          padding: small
              ? const EdgeInsets.symmetric(horizontal: 9, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: fontSize + 3, color: fg),
              if (icon != null && label.isNotEmpty) const SizedBox(width: 6),
              if (label.isNotEmpty)
                Flexible(child: Text(label, softWrap: false, overflow: TextOverflow.ellipsis, style: ts(fontSize, w: FontWeight.w600, color: fg))),
            ],
          ),
        ),
      ),
    );
  }
}

class LinkButton extends StatelessWidget {
  const LinkButton(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: p.brand,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: ts(12, w: FontWeight.w700, color: p.brand)),
    );
  }
}

// ---------------------------------------------------------------------------
// Page header
// ---------------------------------------------------------------------------

class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: ts(11, w: FontWeight.w800, color: p.brand, ls: 1.1),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: ts(mobile ? 23 : 27, w: FontWeight.w800, color: p.ink, ls: -0.8, height: 1.2),
        ),
        const SizedBox(height: 7),
        Text(subtitle, style: ts(14, color: p.muted)),
      ],
    );
    final actionWrap = Wrap(
      alignment: mobile ? WrapAlignment.start : WrapAlignment.end,
      spacing: 9,
      runSpacing: 9,
      children: actions,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 15), actionWrap],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleBlock),
                const SizedBox(width: 20),
                // Flexible: the action box gives way instead of overflowing when the page is narrow.
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: actionWrap,
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers (no LayoutBuilder so they are safe inside IntrinsicHeight)
// ---------------------------------------------------------------------------

class GridRows extends StatelessWidget {
  const GridRows({
    super.key,
    required this.columns,
    required this.spacing,
    required this.children,
  });

  final int columns;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns; j++) {
        if (j > 0) cells.add(SizedBox(width: spacing));
        final idx = i + j;
        cells.add(
          Expanded(child: idx < children.length ? children[idx] : const SizedBox.shrink()),
        );
      }
      if (i > 0) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// 1.45fr / 1fr two column grid that stacks at the tablet breakpoint.
class TwoCol extends StatelessWidget {
  const TwoCol({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (Bp.isTablet(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 16), right],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 145, child: left),
          const SizedBox(width: 16),
          Expanded(flex: 100, child: right),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notice, dot, form inputs, dropdown
// ---------------------------------------------------------------------------

class Notice extends StatelessWidget {
  const Notice({super.key, required this.bold, required this.text});

  final String bold;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: p.noticeBg,
        border: Border.all(color: p.noticeLine),
        borderRadius: BorderRadius.circular(10),
      ),
      child: RichText(
        text: TextSpan(
          style: ts(12, color: p.noticeText),
          children: [
            TextSpan(
              text: bold,
              style: ts(12, w: FontWeight.w700, color: p.noticeBold),
            ),
            TextSpan(text: ' $text'),
          ],
        ),
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

OutlineInputBorder _inputBorder(Color c) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: c),
    );

class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, this.initialValue, this.hint});

  final String label;
  final String? initialValue;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final border = _inputBorder(p.pick(p.line, p.fieldLine));
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(11, w: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 6),
          TextFormField(
            initialValue: initialValue,
            style: ts(14, color: p.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: ts(14, color: p.hint),
              contentPadding: const EdgeInsets.all(10),
              border: border,
              enabledBorder: border,
              focusedBorder: _inputBorder(p.brand),
            ),
          ),
        ],
      ),
    );
  }
}

/// A Row child that takes at most [maxWidth] and shrinks on narrow screens
/// instead of overflowing. Use it where a fixed-width control sits in a Row.
class ShrinkTo extends StatelessWidget {
  const ShrinkTo({super.key, required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Flexible(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

/// Shows a short notice instead of [child] when the window is narrower than
/// [minWidth]. For tools that need room (the map editor), not for lists.
class MinWidthGate extends StatelessWidget {
  const MinWidthGate({super.key, required this.minWidth, required this.what, required this.child});

  final double minWidth;
  final String what;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= minWidth) return child;
    final p = context.pal;
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.aspect_ratio, size: 22, color: p.brand),
          const SizedBox(height: 10),
          Text('$what needs a wider window', style: ts(15, w: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 6),
          Text('Make the window at least ${minWidth.toInt()} px wide, or open it on a laptop or desktop.', style: ts(12, color: p.muted)),
        ],
      ),
    );
  }
}

class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.expand = false,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  /// Fill the parent's width. Otherwise the control sizes to its widest item,
  /// capped at [maxNaturalWidth], and long labels are cut with an ellipsis.
  final bool expand;

  static const double maxNaturalWidth = 280;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border.all(color: p.fieldLine),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i.value,
                enabled: i.enabled,
                onTap: i.onTap,
                child: DefaultTextStyle.merge(maxLines: 1, overflow: TextOverflow.ellipsis, child: i.child),
              ),
          ],
          onChanged: onChanged,
          isDense: true,
          isExpanded: true,
          style: ts(12, color: p.dropText),
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: p.dropText),
          dropdownColor: p.panel,
        ),
      ),
    );
    if (expand) return box;
    return IntrinsicWidth(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: maxNaturalWidth), child: box),
    );
  }
}
// ---------------------------------------------------------------------------
// Clipboard helper (kept here so forms do not import services directly)
// ---------------------------------------------------------------------------

Future<void> copyToClipboard(String text) => Clipboard.setData(ClipboardData(text: text));

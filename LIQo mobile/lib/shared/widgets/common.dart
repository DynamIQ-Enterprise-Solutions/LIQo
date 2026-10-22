// Small building blocks shared by the map's panels and the screens (from the
// demo's ui/widgets.dart: .row, .tile, .chip, .seg, .sw, .card, the buttons),
// with callbacks instead of action strings and LIQo's colours.
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'glyphs.dart';

/// A tappable area.
class Tap extends StatelessWidget {
  const Tap({super.key, required this.onTap, required this.child, this.disabled = false});
  final VoidCallback? onTap;
  final Widget child;
  final bool disabled;
  @override
  Widget build(BuildContext context) => GestureDetector(behavior: HitTestBehavior.opaque, onTap: disabled ? null : onTap, child: child);
}

/// A rounded square with a line icon.
class Tile extends StatelessWidget {
  const Tile(this.glyph, {super.key, this.size = 42, this.bg, this.fg});
  final String glyph;
  final double size;
  final Color? bg, fg;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg ?? p.raised, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: AppIcon(glyph, color: fg ?? p.brand2),
    );
  }
}

class CatTile extends StatelessWidget {
  const CatTile(this.cat, {super.key, this.size = 42});
  final String cat;
  final double size;
  @override
  Widget build(BuildContext context) => Tile(glyphOf(cat), size: size);
}

class ChipX extends StatelessWidget {
  const ChipX({super.key, required this.label, this.icon, required this.fg, required this.bg});
  final String label;
  final String? icon;
  final Color fg, bg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[AppIcon(icon!, size: 14, color: fg, strokeWidth: 2.4), const SizedBox(width: 4)],
          Flexible(child: Text(label, style: ts(12, w: FontWeight.w600, color: fg), maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
        ]),
      );
}

/// The status chip: open, closed (by the map or by the hours), being repaired, opening soon.
Widget statusChip(BuildContext context, String key, String label) {
  final p = context.pal;
  final (fg, bg, icon) = switch (key) {
    'open' => (p.open, p.openBg, 'i-check'),
    'closed' || 'closedNow' => (p.closed, p.closedBg, 'i-x'),
    'maintenance' => (p.maint, p.maintBg, 'i-wrench'),
    _ => (p.soon, p.soonBg, 'i-clock'),
  };
  return ChipX(label: label, icon: icon, fg: fg, bg: bg);
}

/// A quiet grey chip (a level, "Other level").
Widget flChip(BuildContext context, String label) {
  final p = context.pal;
  return ChipX(label: label, fg: p.muted, bg: p.raised);
}

/// A row: tile, title + subtitle, trailing widget.
class RowX extends StatelessWidget {
  const RowX({super.key, this.onTap, this.lead, required this.title, this.sub, this.trail, this.last = false});
  final VoidCallback? onTap;
  final Widget? lead;
  final String title;
  final String? sub;
  final Widget? trail;
  final bool last;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.line, width: p.lineW))),
      child: Row(children: [
        if (lead != null) ...[lead!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: ts(15, w: FontWeight.w600, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (sub != null && sub!.isNotEmpty) Text(sub!, style: ts(12.5, color: p.muted)),
          ]),
        ),
        if (trail != null) ...[const SizedBox(width: 12), Flexible(child: trail!)],
      ]),
    );
    return onTap == null ? body : Semantics(button: true, child: Tap(onTap: onTap, child: body));
  }
}

class CardX extends StatelessWidget {
  const CardX({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line, width: p.lineW), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// A segmented control.
class Seg<T> extends StatelessWidget {
  const Seg({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: p.lineW)),
      child: Row(children: [
        for (final (v, l) in items)
          Expanded(
            child: Semantics(
              button: true,
              selected: v == value,
              child: Tap(
                onTap: () => onChanged(v),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  alignment: Alignment.center,
                  decoration: v == value ? BoxDecoration(color: p.panel, borderRadius: BorderRadius.circular(9), boxShadow: p.shadow) : null,
                  child: Text(l, textAlign: TextAlign.center, style: ts(13, w: FontWeight.w600, color: v == value ? p.brand2 : p.muted)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The toggle switch.
class Sw extends StatelessWidget {
  const Sw({super.key, required this.on, required this.onChanged, this.label});
  final bool on;
  final ValueChanged<bool> onChanged;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tap(
      onTap: () => onChanged(!on),
      child: Semantics(
        button: true,
        toggled: on,
        label: label,
        child: AnimatedContainer(
          duration: motionFast,
          width: 44,
          height: 26,
          decoration: BoxDecoration(color: on ? p.brand : p.line, borderRadius: BorderRadius.circular(13)),
          child: AnimatedAlign(
            duration: motionFast,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(3),
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: p.panel, shape: BoxShape.circle, boxShadow: p.shadow),
            ),
          ),
        ),
      ),
    );
  }
}

/// A button: primary (orange) or secondary. Expands in a [btns] row.
class Btn extends StatelessWidget {
  const Btn(this.label, {super.key, required this.onTap, this.primary = false, this.disabled = false, this.height = 48, this.fontSize = 15, this.semantics, this.danger = false});
  final String label;
  final VoidCallback? onTap;
  final bool primary, disabled, danger;
  final double height, fontSize;

  /// What the screen reader says, when the label alone is not enough ("Pause the walk").
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bg = danger ? p.danger : primary ? p.brand : p.raised;
    final fg = danger ? p.panel : primary ? p.onBrand : p.ink;
    return Expanded(
      child: Opacity(
        opacity: disabled ? .45 : 1,
        child: Semantics(
          label: semantics,
          button: true,
          enabled: !disabled,
          excludeSemantics: semantics != null,
          child: Tap(
            onTap: onTap,
            disabled: disabled,
            child: Container(
              constraints: BoxConstraints(minHeight: height), // grows with large text
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
                border: primary || danger ? null : Border.all(color: p.line, width: p.lineW),
                boxShadow: primary && !disabled ? p.glow : null,
              ),
              child: Text(label, textAlign: TextAlign.center, style: ts(fontSize, w: primary ? FontWeight.w700 : FontWeight.w600, color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}

Widget btns(List<Widget> children, {double top = 12}) => Padding(
      padding: EdgeInsets.only(top: top),
      child: Row(children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), children[i]]]),
    );

/// A 40 px round icon button.
class RoundBtn extends StatelessWidget {
  const RoundBtn(this.icon, {super.key, required this.onTap, required this.label, this.on = false});
  final String icon, label;
  final VoidCallback? onTap;
  final bool on;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tap(
      onTap: onTap,
      child: Semantics(
        button: true,
        toggled: on ? true : null,
        label: label,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: on ? p.brand : p.raised, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: AppIcon(icon, color: on ? p.onBrand : p.ink),
        ),
      ),
    );
  }
}

/// A note: warn, ok or info.
Widget note(BuildContext context, String kind, Widget child, {double top = 8}) {
  final p = context.pal;
  final (fg, bg) = switch (kind) { 'warn' => (p.closed, p.closedBg), 'ok' => (p.open, p.openBg), _ => (p.soon, p.soonBg) };
  return Container(
    margin: EdgeInsets.only(top: top),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: DefaultTextStyle.merge(style: ts(13, w: FontWeight.w600, color: fg), child: IconTheme.merge(data: IconThemeData(color: fg), child: child)),
  );
}

/// A note with a line icon in front.
Widget iconNote(BuildContext context, String kind, String icon, String text, {double top = 8}) {
  final p = context.pal;
  final fg = switch (kind) { 'warn' => p.closed, 'ok' => p.open, _ => p.soon };
  return note(
    context,
    kind,
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppIcon(icon, size: 18, color: fg),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ]),
    top: top,
  );
}

/// A section heading in capitals.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.only(top: 18, bottom: 8)});
  final String text;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text.toUpperCase(), style: ts(12, w: FontWeight.w700, ls: .8, color: context.pal.muted)),
      );
}

/// A card's surface: panel, line, rounded, soft shadow.
BoxDecoration cardDeco(Pal p, double radius) => BoxDecoration(
      color: p.panel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.line, width: p.lineW),
      boxShadow: p.shadow,
    );

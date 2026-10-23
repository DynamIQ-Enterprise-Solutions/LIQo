import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'common.dart';
import 'logo_image.dart';
import 'skeleton.dart';

/// The building blocks of a record's page, laid out like the People page:
/// a page head, then one card per section with clear separation, and a red
/// danger zone last. Every destructive action goes through [confirmDangerous].

/// Page frame for one record: head, loading skeletons, error card, or the cards.
class DetailScaffold extends StatelessWidget {
  const DetailScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.backPath,
    this.backLabel = 'Back',
    this.actions = const [],
    this.pills = const [],
    this.hero,
    this.loading = false,
    this.error,
    this.onRetry,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String backPath;
  final String backLabel;
  final List<Widget> actions;
  final List<Widget> pills;

  /// The record's header card (Round 20), shown above the cards once loaded.
  final Widget? hero;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: eyebrow,
          title: title,
          subtitle: subtitle,
          actions: [
            AppButton(label: backLabel, icon: Icons.arrow_back, onPressed: () => context.go(backPath)),
            ...actions,
          ],
        ),
        if (pills.isNotEmpty && hero == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Wrap(spacing: 8, runSpacing: 8, children: pills),
          ),
        if (error != null)
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error!, style: ts(12, color: p.warn)),
                if (onRetry != null) ...[const SizedBox(height: 10), AppButton(label: 'Try again', primary: true, onPressed: onRetry!)],
              ],
            ),
          )
        else if (loading)
          // The page's own shape: the header card, then two columns (Round 20).
          const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroSkeleton(),
                SizedBox(height: 18),
                DetailColumns(
                  facts: [
                    SkeletonCard(child: SkeletonForm(fields: 3)),
                    SkeletonCard(child: SkeletonLines(widths: [0.8, 0.6, 0.4], height: 10))
                  ],
                  lists: [SkeletonCard(child: SkeletonRows(count: 3))],
                ),
              ],
            ),
          )
        else ...[
          if (hero != null) ...[hero!, const SizedBox(height: 18)],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            children[i],
          ],
        ],
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: 120,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
      child: const Row(
        children: [
          Expanded(child: SkeletonBox(height: 72, radius: 36)),
          SizedBox(width: 18),
          Expanded(flex: 9, child: SkeletonLines(widths: [0.45, 0.3, 0.25], height: 12)),
        ],
      ),
    );
  }
}

/// The mark at the start of a [RecordHero]: initials (people), a logo (malls,
/// stores), or an icon (everything else).
class HeroMark extends StatelessWidget {
  const HeroMark.initials(String this.initials, {super.key})
      : logoUrl = null,
        logoName = null,
        icon = null;
  const HeroMark.logo({super.key, required this.logoUrl, required String name})
      : logoName = name,
        initials = null,
        icon = null;
  const HeroMark.icon(IconData this.icon, {super.key})
      : initials = null,
        logoUrl = null,
        logoName = null;

  final String? initials;
  final String? logoUrl;
  final String? logoName;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final size = Bp.isMobile(context) ? 64.0 : 80.0;
    if (logoName != null) return LogoImage(url: logoUrl, name: logoName!, size: size);
    if (icon != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: p.soft, shape: BoxShape.circle, border: Border.all(color: p.line)),
        child: Icon(icon, size: size * 0.42, color: p.brand2),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.brand, Pal.brandCrimson]),
        shape: BoxShape.circle,
        boxShadow: p.darkOnly(p.glow),
      ),
      child: Text(initials ?? '?', style: ts(size * 0.35, w: FontWeight.w800, color: p.avatarFg, ls: -0.5, height: 1.1)),
    );
  }
}

/// A record's header card, as on My account (Round 20): its mark, name, a sub
/// line, pills and one short line of facts.
class RecordHero extends StatelessWidget {
  const RecordHero({super.key, required this.mark, required this.title, this.sub, this.pills = const [], this.line});

  final Widget mark;
  final String title;
  final String? sub;
  final List<Widget> pills;
  final String? line;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, overflow: TextOverflow.ellipsis, maxLines: 2, style: ts(mobile ? 20 : 24, w: FontWeight.w800, color: p.ink, ls: -0.5, height: 1.2)),
        if (sub != null && sub!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(sub!, overflow: TextOverflow.ellipsis, maxLines: 2, style: ts(13, color: p.muted)),
        ],
        if (pills.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: pills),
        ],
        if (line != null && line!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(line!, style: ts(12, color: p.muted)),
        ],
      ],
    );
    return Container(
      key: const ValueKey('record-hero'),
      padding: EdgeInsets.all(mobile ? 18 : 26),
      decoration: BoxDecoration(color: p.panel, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14), boxShadow: p.shadow),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The brand's route line, a thin gradient along the top edge of the card.
          Positioned(
            left: 0,
            right: 0,
            top: mobile ? -18.0 : -26.0,
            child: IgnorePointer(
              child: Container(
                height: 2,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [p.panel, p.brand, Pal.brandCrimson, p.panel], stops: const [0, 0.3, 0.7, 1])),
              ),
            ),
          ),
          mobile
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [mark, const SizedBox(height: 14), who])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [mark, const SizedBox(width: 22), Expanded(child: who)]),
        ],
      ),
    );
  }
}

/// A record page's cards (owner decision 2026-10-23, layout A): the short
/// cards ([facts]: details, map, sign-in, reactivate…) side by side in pairs
/// under the header card, then every list full width ([lists]), then [after]
/// (the danger zone, so it stays last). One column at tablet width and below.
class DetailColumns extends StatelessWidget {
  const DetailColumns({super.key, required this.facts, this.lists = const [], this.after = const []});

  final List<Widget> facts;
  final List<Widget> lists;
  final List<Widget> after;

  static List<Widget> _spaced(List<Widget> cards) => [
        for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 18), cards[i]],
      ];

  @override
  Widget build(BuildContext context) {
    final stacked = Bp.isTablet(context);
    final rows = <Widget>[
      if (stacked)
        ...facts
      else
        for (var i = 0; i < facts.length; i += 2)
          // An odd card out spans the full width rather than leaving a gap.
          i + 1 < facts.length
              ? Row(
                  key: ValueKey('detail-facts-${i ~/ 2}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: facts[i]), const SizedBox(width: 18), Expanded(child: facts[i + 1])],
                )
              : facts[i],
      ...lists,
      ...after,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(rows));
  }
}

/// One section: a card with a head (title, subtitle, one trailing control) and a body.
class DetailCard extends StatelessWidget {
  const DetailCard({super.key, required this.title, this.subtitle, this.trailing, required this.child});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardHead(title: title, subtitle: subtitle, trailing: trailing),
            CardBody(child: child),
          ],
        ),
      );
}

/// One read-only fact: label on the left, value on the right.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.child});

  final String label;
  final String? value;

  /// A widget instead of text (pills, a list).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = (value == null || value!.trim().isEmpty) ? '—' : value!;
    final labelText = Text(label, style: ts(11, w: FontWeight.w700, color: p.muted));
    final valueWidget = child ?? SelectableText(v, style: ts(12.5, color: p.ink));
    // Phones: label above the value, so neither side is squeezed.
    if (Bp.isMobile(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [labelText, const SizedBox(height: 3), valueWidget]),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: labelText),
          const SizedBox(width: 12),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }
}

/// One record inside a card: name and a line under it on the left, chips in
/// the middle, actions on the right. Stacks below the tablet breakpoint.
/// Tapping the row opens it when [onTap] is given.
class RecordRow extends StatelessWidget {
  const RecordRow({super.key, required this.title, this.subtitle, this.chips = const [], this.actions = const [], this.onTap});

  final String title;
  final String? subtitle;
  final List<Widget> chips;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final stacked = Bp.isTablet(context);
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w700, color: p.ink)),
        if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted)),
      ],
    );
    final chipWrap = Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: chips);
    final actionWrap = Wrap(spacing: 6, runSpacing: 6, children: [
      ...actions,
      if (onTap != null) Icon(Icons.chevron_right, size: 18, color: p.hint),
    ]);
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.rowLine))),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                who,
                if (chips.isNotEmpty) ...[const SizedBox(height: 8), chipWrap],
                if (actions.isNotEmpty || onTap != null) ...[const SizedBox(height: 8), actionWrap]
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 220, child: who),
                const SizedBox(width: 14),
                Expanded(child: chipWrap),
                const SizedBox(width: 14),
                actionWrap,
              ],
            ),
    );
    if (onTap == null) return body;
    return InkWell(onTap: onTap, hoverColor: p.hover, child: body);
  }
}

/// One action: full width, an icon, a label and a one-line description.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.description, required this.onTap, this.enabled = true});

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fg = enabled ? p.ink : p.hint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: p.hover,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 18, color: enabled ? p.brand : p.hint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: ts(13, w: FontWeight.w700, color: fg)),
                      Text(description, style: ts(11, color: p.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 18, color: p.hint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One dangerous action: red outlined button with an explanation.
class DangerAction {
  const DangerAction({required this.label, required this.description, required this.onTap, this.enabled = true});

  final String label;
  final String description;
  final VoidCallback onTap;
  final bool enabled;
}

/// The last card of a page: red outline, each action explained, every button
/// leads to a typed confirmation. Renders nothing when there are no actions.
class DangerZone extends StatelessWidget {
  const DangerZone({super.key, required this.actions});

  final List<DangerAction> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: BoxDecoration(
        color: p.dangerBg,
        border: Border.all(color: p.danger),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: p.danger),
              const SizedBox(width: 6),
              Text('DANGER ZONE', style: ts(10, w: FontWeight.w800, color: p.danger, ls: 1.1)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Each of these asks you to type the name before it runs.', style: ts(11, color: p.muted)),
          const SizedBox(height: 12),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text(a.description, style: ts(11.5, color: p.ink))),
                  const SizedBox(width: 12),
                  DangerButton(label: a.label, onPressed: a.onTap, enabled: a.enabled),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed, this.enabled = true, this.filled = false});

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = enabled ? p.danger : p.hint;
    return Material(
      color: filled && enabled ? p.danger : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: BorderSide(color: color)),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Text(label, softWrap: false, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w700, color: filled && enabled ? Colors.white : color)),
        ),
      ),
    );
  }
}

/// Key of the confirm button in the typed confirmation, for tests.
const dangerConfirmKey = ValueKey('danger-confirm');
const dangerInputKey = ValueKey('danger-input');

/// Typed confirmation: explains the impact, Cancel is the default, and the red
/// button stays disabled until [name] is typed exactly (spaces trimmed).
Future<bool> confirmDangerous(
  BuildContext context, {
  required String title,
  required String impact,
  required String name,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: context.pal.scrim,
    builder: (ctx) => _TypedConfirm(title: title, impact: impact, name: name, confirmLabel: confirmLabel),
  );
  return ok == true;
}

class _TypedConfirm extends StatefulWidget {
  const _TypedConfirm({required this.title, required this.impact, required this.name, required this.confirmLabel});

  final String title;
  final String impact;
  final String name;
  final String confirmLabel;

  @override
  State<_TypedConfirm> createState() => _TypedConfirmState();
}

class _TypedConfirmState extends State<_TypedConfirm> {
  final _c = TextEditingController();

  bool get _matches => _c.text.trim() == widget.name.trim();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AlertDialog(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: p.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title, style: ts(16, w: FontWeight.w800, color: p.ink))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.impact, style: ts(13, color: p.ink)),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                style: ts(12, color: p.muted),
                children: [
                  const TextSpan(text: 'Type '),
                  TextSpan(text: widget.name, style: ts(12, w: FontWeight.w800, color: p.ink)),
                  const TextSpan(text: ' to confirm.'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: dangerInputKey,
              controller: _c,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: ts(13, color: p.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.name,
                hintStyle: ts(13, color: p.hint),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.fieldLine)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.fieldLine)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.danger)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
        IgnorePointer(
          key: dangerConfirmKey,
          ignoring: !_matches,
          child: Opacity(
            opacity: _matches ? 1 : 0.45,
            child: DangerButton(label: widget.confirmLabel, filled: true, onPressed: () => Navigator.of(context).pop(true)),
          ),
        ),
      ],
    );
  }
}

/// Up to two initials of a name, for a [HeroMark].
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

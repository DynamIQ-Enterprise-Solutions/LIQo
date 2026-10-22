import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import 'common.dart';
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
        if (pills.isNotEmpty)
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
          const Shimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonCard(child: SkeletonForm(fields: 3)),
                SizedBox(height: 18),
                SkeletonCard(child: SkeletonRows(count: 3)),
              ],
            ),
          )
        else
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 18),
            children[i],
          ],
      ],
    );
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
              children: [who, if (chips.isNotEmpty) ...[const SizedBox(height: 8), chipWrap], if (actions.isNotEmpty || onTap != null) ...[const SizedBox(height: 8), actionWrap]],
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

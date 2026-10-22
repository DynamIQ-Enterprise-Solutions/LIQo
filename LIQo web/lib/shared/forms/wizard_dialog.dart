import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';

/// What a create wizard hands back: what it created, and the record the person
/// asked to open (the new one from the Done step, or an existing one a
/// duplicate check pointed to).
class WizardOutcome<T> {
  const WizardOutcome({this.created, this.openId});

  final T? created;
  final int? openId;
}

/// The frame of a step-by-step dialog: title, close, the step bar, the step's
/// heading, its body (scrolls), an error line and the buttons.
class WizardFrame extends StatelessWidget {
  const WizardFrame({
    super.key,
    required this.title,
    required this.steps,
    required this.current,
    required this.heading,
    required this.body,
    required this.actions,
    required this.onClose,
    this.intro = '',
    this.error,
  });

  final String title;
  final List<String> steps;
  final int current;
  final String heading;
  final String intro;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback onClose;
  final String? error;

  static const closeKey = ValueKey('wizard-close');

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = MediaQuery.sizeOf(context).width < 480;
    final pad = mobile ? 18.0 : 25.0;
    return Dialog(
      backgroundColor: p.panel,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.all(mobile ? 12 : 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad - 6, pad - 12, 0),
              child: Row(
                children: [
                  Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(19, w: FontWeight.w800, color: p.ink, height: 1.25))),
                  IconButton(
                    key: closeKey,
                    onPressed: onClose,
                    icon: Icon(Icons.close, size: 18, color: p.muted),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
              child: WizardStepBar(steps: steps, current: current),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 20, pad, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('STEP ${current + 1} OF ${steps.length}', style: ts(10, w: FontWeight.w800, color: p.brand2, ls: 1.2)),
                    const SizedBox(height: 4),
                    Text(heading, style: ts(15, w: FontWeight.w800, color: p.ink, height: 1.3)),
                    if (intro.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(intro, style: ts(12, color: p.muted, height: 1.45)),
                    ],
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: motionFast,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, if (current != null) current],
                      ),
                      child: KeyedSubtree(key: ValueKey('wizard-step-$heading'), child: body),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: p.warn),
                    const SizedBox(width: 6),
                    Expanded(child: Text(error!, style: ts(12, color: p.warn))),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 14, pad, pad - 4),
              child: Wrap(alignment: WrapAlignment.end, spacing: 9, runSpacing: 9, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

/// Numbered steps joined by a line: done steps are filled, the current one is
/// outlined in the brand colour, later ones are quiet.
class WizardStepBar extends StatelessWidget {
  const WizardStepBar({super.key, required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget line(bool on) => Expanded(child: AnimatedContainer(duration: motionBase, height: 1.5, color: on ? p.brand : p.line));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    i == 0 ? const Spacer() : line(i <= current),
                    AnimatedContainer(
                      duration: motionBase,
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < current ? p.brand : (i == current ? p.soft : p.panel),
                        border: Border.all(color: i <= current ? p.brand : p.line, width: 1.5),
                      ),
                      child: i < current
                          ? const Icon(Icons.check, size: 13, color: Colors.white)
                          : Text('${i + 1}', style: ts(11, w: FontWeight.w800, color: i == current ? p.brand2 : p.muted)),
                    ),
                    i == steps.length - 1 ? const Spacer() : line(i < current),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  steps[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: ts(10.5, w: i == current ? FontWeight.w800 : FontWeight.w600, color: i == current ? p.ink : p.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum NoteTone { checking, ok, info, warn, block }

/// One line under a field or in a review: the result of a live check, with an
/// optional action (for example "Open account").
class CheckNote extends StatelessWidget {
  const CheckNote(this.tone, this.text, {super.key, this.actionLabel, this.onAction});

  final NoteTone tone;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (IconData icon, Color color) = switch (tone) {
      NoteTone.checking => (Icons.hourglass_empty, p.muted),
      NoteTone.ok => (Icons.check_circle_outline, p.green),
      NoteTone.info => (Icons.info_outline, p.muted),
      NoteTone.warn => (Icons.warning_amber_rounded, p.warn),
      NoteTone.block => (Icons.block, p.danger),
    };
    final quiet = tone == NoteTone.info || tone == NoteTone.checking;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(text, style: ts(11.5, color: quiet ? p.muted : color, height: 1.4)),
              if (actionLabel != null && onAction != null) LinkButton(actionLabel!, onPressed: onAction!),
            ],
          ),
        ),
      ],
    );
  }
}

/// A wizard button. A disabled one stays visible, faded, and ignores taps.
class WizardButton extends StatelessWidget {
  const WizardButton({super.key, required this.label, required this.onPressed, this.primary = false, this.enabled = true, this.icon});

  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final bool enabled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !enabled,
        child: AnimatedOpacity(
          duration: motionFast,
          opacity: enabled ? 1 : 0.45,
          child: AppButton(label: label, primary: primary, icon: icon, onPressed: onPressed),
        ),
      );
}

/// A choice shown as a card: a title, a line about it, a radio mark.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.title, required this.description, required this.selected, required this.onTap, this.caution = false});

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  /// Shows the description in the warning colour (powerful choices).
  final bool caution;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? p.soft : p.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? p.brand : p.line, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: selected ? p.brand : p.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ts(13, w: FontWeight.w800, color: p.ink)),
                      const SizedBox(height: 3),
                      Text(description, style: ts(11.5, color: caution ? p.warn : p.muted, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

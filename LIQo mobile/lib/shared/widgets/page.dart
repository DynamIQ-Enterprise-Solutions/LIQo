// The frame of a full-screen page (as on the board): Back and a title on top,
// the content scrolling under it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../features/settings/providers/words_provider.dart';

class AppPage extends ConsumerWidget {
  const AppPage({super.key, required this.title, required this.children, this.actions = const [], this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24), this.bottom, this.back = true});

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final EdgeInsets padding;

  /// Pinned under the scrolling content (a page's main button).
  final Widget? bottom;

  /// Shows Back (a tab's first screen has none).
  final bool back;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(back ? 4 : 16, 6, 8, 2),
            child: Row(children: [
              if (back) BackBtn(label: w.tr('Back')),
              if (back) const SizedBox(width: 2),
              Expanded(child: Semantics(header: true, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(20, w: FontWeight.w800, color: p.ink, ls: -.2)))),
              ...actions,
            ]),
          ),
          Expanded(child: ListView(padding: padding, children: children)),
          if (bottom != null)
            DecoratedBox(
              decoration: BoxDecoration(color: p.panel, border: Border(top: BorderSide(color: p.line, width: p.lineW))),
              child: SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 10), child: bottom)),
            ),
        ]),
      ),
    );
  }
}

/// Back: pops the page, or goes Home when there is nothing to pop.
class BackBtn extends StatelessWidget {
  const BackBtn({super.key, required this.label, this.onDark = false});
  final String label;

  /// On a picture: a round light chip behind the arrow.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    void back() => context.canPop() ? context.pop() : context.go('/home');
    if (onDark) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: back,
        child: Material(
          color: p.panel.withValues(alpha: .92),
          shape: const CircleBorder(),
          child: InkWell(key: const ValueKey('back'), customBorder: const CircleBorder(), onTap: back, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.arrow_back, color: p.ink))),
        ),
      );
    }
    return IconButton(key: const ValueKey('back'), tooltip: label, onPressed: back, icon: Icon(Icons.arrow_back, color: p.ink));
  }
}

/// A primary button that fills its row (the board's orange pill).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), boxShadow: onPressed == null ? null : p.glow),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: p.onBrand,
          disabledBackgroundColor: p.raised,
          disabledForegroundColor: p.muted,
          minimumSize: const Size.fromHeight(50),
          shape: const StadiumBorder(),
          textStyle: ts(15.5, w: FontWeight.w700),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ]),
      ),
    );
  }
}

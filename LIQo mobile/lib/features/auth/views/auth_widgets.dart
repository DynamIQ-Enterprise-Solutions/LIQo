// Pieces of the look-only Sign in and Sign up pages (owner decision 2026-10-22:
// the board's screens, nothing saved or sent; every button says accounts are
// coming soon).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/brand.dart';
import '../../../shared/widgets/page.dart';
import '../../../shared/widgets/toast.dart';
import '../../settings/providers/words_provider.dart';

/// Every action on these pages.
void comingSoon(BuildContext context, WidgetRef ref) => showToast(context, ref.read(wordsProvider).tr('Accounts are coming soon'));

/// The frame: Back, the wordmark with the tagline, the title and subtitle, the form.
class AuthFrame extends ConsumerWidget {
  const AuthFrame({super.key, required this.title, required this.subtitle, required this.children});
  final String title, subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Align(alignment: Alignment.centerLeft, child: BackBtn(label: w.tr('Back'))),
            const SizedBox(height: 8),
            const Center(child: FittedBox(fit: BoxFit.scaleDown, child: BrandLockup(size: 40, taglineSize: 13))),
            const SizedBox(height: 28),
            Semantics(header: true, child: Text(title, style: ts(24, w: FontWeight.w800, color: p.ink))),
            const SizedBox(height: 4),
            Text(subtitle, style: ts(14, color: p.muted)),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A labelled field (it can be typed in; nothing is kept).
class AuthField extends StatefulWidget {
  const AuthField({super.key, required this.label, required this.hint, this.password = false, this.keyboard, required this.showLabel, required this.hideLabel});
  final String label, hint;
  final bool password;
  final TextInputType? keyboard;

  /// What the eye button says.
  final String showLabel, hideLabel;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  late bool _hidden = widget.password;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.label, style: ts(13.5, w: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 6),
        TextField(
          obscureText: _hidden,
          keyboardType: widget.keyboard,
          autocorrect: false,
          enableSuggestions: !widget.password,
          style: ts(15, color: p.ink),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: ts(15, color: p.hint),
            filled: true,
            fillColor: p.panel,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.line, width: p.lineW)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.brand, width: 1.5)),
            suffixIcon: widget.password
                ? IconButton(
                    tooltip: _hidden ? widget.showLabel : widget.hideLabel,
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: p.muted),
                  )
                : null,
          ),
        ),
      ]),
    );
  }
}

/// "or continue with", and three buttons with generic icons (not the companies' logos).
class SocialButtons extends ConsumerWidget {
  const SocialButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    Widget b(String key, IconData icon, String label) => Expanded(
          child: OutlinedButton(
            key: ValueKey(key),
            onPressed: () => comingSoon(context, ref),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              side: BorderSide(color: p.line, width: p.lineW),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              foregroundColor: p.ink,
              backgroundColor: p.panel,
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w600)),
            ]),
          ),
        );
    return Column(children: [
      Row(children: [
        Expanded(child: Divider(color: p.line)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text(w.tr('or continue with'), style: ts(12.5, color: p.muted))),
        Expanded(child: Divider(color: p.line)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        b('social-google', Icons.public, 'Google'),
        const SizedBox(width: 10),
        b('social-apple', Icons.phone_iphone, 'Apple'),
        const SizedBox(width: 10),
        b('social-phone', Icons.sms_outlined, w.tr('Phone')),
      ]),
    ]);
  }
}

/// "Don't have an account? Sign up" and the like.
class SwitchLine extends StatelessWidget {
  const SwitchLine({super.key, required this.text, required this.action, required this.onTap});
  final String text, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(text, style: ts(14, color: p.muted)),
      TextButton(onPressed: onTap, child: Text(action, style: ts(14, w: FontWeight.w800, color: p.brand2))),
    ]);
  }
}

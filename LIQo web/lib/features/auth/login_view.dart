import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/theme_mode.dart';
import '../../shared/widgets/common.dart';
import 'auth_service.dart';
import 'login_ambience.dart';
import 'glass.dart';
import 'login_features.dart';

class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key, this.from});

  /// Where to go after a successful sign-in (deep link preserved by the guard).
  final String? from;

  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  /// Plays once when the page opens: the panel, the card, then the form rise in.
  late final AnimationController _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  /// The slow shared clock of the background, the IQ watermark and the card's edge light.
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void initState() {
    super.initState();
    // Focus after the first frame; `autofocus` on web can fire before the
    // overlay is laid out and trips a framework assertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: everything shows at once and stands still.
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
      _clock.stop();
    } else {
      if (_entrance.value == 0 && !_entrance.isAnimating) _entrance.forward();
      if (!_clock.isAnimating) _clock.repeat();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _clock.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await AuthService().login(_email.text.trim(), _password.text);
      await ref.read(sessionProvider.notifier).signIn(token: result.token, user: result.user);
      // The router guard sends the user to the right dashboard.
      if (mounted && widget.from != null && widget.from!.startsWith('/')) {
        context.go(widget.from!);
      }
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fades [child] in and lifts it [dy] px while the entrance runs from [a] to [b].
  Widget _rise(double a, double b, Widget child, {double dy = 16}) => AnimatedBuilder(
        animation: _entrance,
        child: child,
        builder: (context, c) {
          final v = Interval(a, b, curve: Curves.easeOutCubic).transform(_entrance.value);
          return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, dy * (1 - v)), child: c));
        },
      );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final size = MediaQuery.sizeOf(context);
    // Owner decisions 2026-10-22: the form sits in its own raised card; a
    // feature carousel fills the other panel; narrow windows stack them; a
    // slow living background and a faint IQ mark sit behind (login only).
    final wide = size.width > Bp.tablet;

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          Positioned.fill(child: LoginBackdrop(clock: _clock)),
          wide ? _wideLayout(p, size) : _narrowLayout(p),
        ],
      ),
    );
  }

  /// Owner decision 2026-10-23: on big screens the carousel and the form stay
  /// one block at most this size, centred; the living background fills the rest.
  static const _wideMax = Size(1440, 900);

  /// Side by side. The page keeps a minimum height and scrolls in short windows.
  Widget _wideLayout(Pal p, Size size) {
    final pageHeight = math.max(size.height, 780.0);
    final blockWidth = math.min(size.width, _wideMax.width);
    final blockHeight = math.min(pageHeight, _wideMax.height);
    final carouselWidth = ((blockWidth - 48) * 0.55).clamp(480.0, 820.0);
    return SingleChildScrollView(
      child: SizedBox(
        height: pageHeight,
        child: Center(
          child: SizedBox(
            key: const ValueKey('login-block'),
            width: blockWidth,
            height: blockHeight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: carouselWidth, child: _rise(0, 0.55, FeatureCarousel(ambient: _clock), dy: 12)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 20),
                      child: Column(
                        children: [
                          Align(alignment: Alignment.centerRight, child: _rise(0.3, 0.8, const _ThemeToggle(), dy: 0)),
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRect(
                                    child: Center(child: _rise(0.25, 1, IqWatermark(clock: _clock, height: math.min(440, blockHeight * 0.48)), dy: 0)),
                                  ),
                                ),
                                Center(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: _rise(0.15, 0.7, _formCard(p), dy: 22)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _rise(0.5, 1, _footer(p), dy: 0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Narrow windows: the form first, the compact carousel under it.
  Widget _narrowLayout(Pal p) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rise(
                  0,
                  0.45,
                  const Row(
                    children: [
                      Padding(padding: EdgeInsets.only(left: 4), child: BrandLockup(size: 30, taglineSize: 11.5)),
                      Spacer(),
                      _ThemeToggle(),
                    ],
                  ),
                  dy: 0,
                ),
                const SizedBox(height: 14),
                _rise(0.1, 0.65, _formCard(p, compact: true), dy: 18),
                const SizedBox(height: 14),
                _rise(0.35, 0.9, const FeatureCarousel(compact: true), dy: 14),
                const SizedBox(height: 16),
                _rise(0.5, 1, _footer(p, center: true), dy: 0),
              ],
            ),
          ),
        ),
      );

  Widget _footer(Pal p, {bool center = false}) => Wrap(
        alignment: center ? WrapAlignment.center : WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 6,
        children: [
          Text('LIQO Wayfinding Platform · $brandTagline', style: ts(11.5, color: p.sideNote)),
          Text('Sessions end after a period of inactivity', style: ts(11.5, color: p.sideNote)),
        ],
      );

  /// The sign-in form in its own raised card, with the IQ tile on top and a
  /// thin light travelling slowly around its edge.
  Widget _formCard(Pal p, {bool compact = false}) {
    final expired = ref.watch(sessionProvider.select((s) => s.expiredNotice));
    final pad = compact ? 22.0 : 40.0;
    final radius = compact ? 22.0 : 24.0;
    final tile = compact ? 42.0 : 48.0;
    return CustomPaint(
      foregroundPainter: EdgeGlowPainter(p: p, clock: _clock, radius: radius),
      // Frosted glass over the living background, lifted by a soft shadow.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: p.pick(Pal.brandCrimson.withValues(alpha: 0.07), Colors.black.withValues(alpha: 0.30)),
              blurRadius: 70,
              spreadRadius: -6,
              offset: const Offset(0, 26),
            ),
          ],
        ),
        child: GlassSurface(
          radius: radius,
          tint: GlassSurface.cardTint(p),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, compact ? 24 : 34, pad, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _rise(
                        0.25,
                        0.75,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The IQ tile, with a soft brand glow (kept understated).
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(tile * BrandTile.radiusShare),
                                boxShadow: [BoxShadow(color: p.brand.withValues(alpha: p.mix(0.16, 0.26)), blurRadius: 22, offset: const Offset(0, 6))],
                              ),
                              child: BrandTile(size: tile),
                            ),
                            SizedBox(height: compact ? 16 : 20),
                            Text('ADMIN CONSOLE', style: ts(10.5, w: FontWeight.w800, color: p.brand2, ls: 1.9)),
                            const SizedBox(height: 10),
                            Text('Sign in', style: ts(compact ? 24 : 28, w: FontWeight.w800, color: p.ink, ls: -0.5, height: 1.2)),
                            const SizedBox(height: 8),
                            Text('Use the email and password given to you by your administrator.', style: ts(13.5, color: p.muted, height: 1.55)),
                          ],
                        ),
                        dy: 10,
                      ),
                      SizedBox(height: compact ? 20 : 26),
                      if (expired) ...[
                        const Notice(bold: 'Signed out.', text: 'Your session ended. Please sign in again.'),
                        const SizedBox(height: 16),
                      ],
                      _rise(
                        0.35,
                        0.85,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Field(
                              label: 'Email address',
                              controller: _email,
                              hint: 'name@company.com',
                              keyboardType: TextInputType.emailAddress,
                              focusNode: _emailFocus,
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return 'Email address is required.';
                                if (!t.contains('@')) return 'Enter a valid email address.';
                                return null;
                              },
                              onSubmitted: (_) => _submit(),
                            ),
                            _Field(
                              label: 'Password',
                              controller: _password,
                              hint: 'Your password',
                              obscure: !_showPassword,
                              validator: (v) => (v ?? '').isEmpty ? 'Password is required.' : null,
                              onSubmitted: (_) => _submit(),
                              suffix: IconButton(
                                tooltip: _showPassword ? 'Hide password' : 'Show password',
                                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: p.muted),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                          ],
                        ),
                        dy: 10,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, size: 16, color: p.warn),
                              const SizedBox(width: 6),
                              Expanded(child: Text(_error!, style: ts(12, color: p.warn))),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      _rise(
                        0.45,
                        0.95,
                        SizedBox(
                          height: 50,
                          child: DecoratedBox(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: _busy ? const [] : p.glow),
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: p.brand,
                                disabledBackgroundColor: p.brand.withValues(alpha: 0.6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _busy
                                  ? Text('Signing in…', style: ts(14, w: FontWeight.w700, color: Colors.white))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Sign in', style: ts(14, w: FontWeight.w700, color: Colors.white)),
                                        const SizedBox(width: 10),
                                        const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        dy: 10,
                      ),
                      SizedBox(height: compact ? 18 : 24),
                    ],
                  ),
                ),
                // The footnote spans the card, under a full-width divider.
                Container(
                  padding: EdgeInsets.fromLTRB(pad, compact ? 14 : 18, pad, compact ? 18 : 24),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
                  child: Text(
                    'Forgot your password? Ask your administrator to reset it.',
                    style: ts(12, color: p.sideNote, height: 1.5),
                    textAlign: TextAlign.center,
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

/// Light or dark, remembered in this browser (same setting as the top bar's).
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return Semantics(
      button: true,
      label: p.dark ? 'Switch to light mode' : 'Switch to dark mode',
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: p.pick(p.panel, p.shell),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: p.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => ref.read(themeModeProvider.notifier).setDark(!p.dark),
            child: Center(child: ThemeToggleIcon(size: 18, color: p.muted)),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.focusNode,
    this.validator,
    this.onSubmitted,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: c),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(11, w: FontWeight.w700, color: p.ink)),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            focusNode: focusNode,
            validator: validator,
            onFieldSubmitted: onSubmitted,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: ts(14, color: p.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: ts(14, color: p.hint),
              filled: true,
              fillColor: p.pick(p.panel, p.bg),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              border: border(p.pick(p.line, p.fieldLine)),
              enabledBorder: border(p.pick(p.line, p.fieldLine)),
              focusedBorder: border(p.brand),
              errorStyle: ts(11, color: p.warn),
              suffixIcon: suffix,
            ),
          ),
        ],
      ),
    );
  }
}

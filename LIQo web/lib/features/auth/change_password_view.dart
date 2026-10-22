import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/messaging/messages.dart';
import '../../shared/widgets/common.dart';
import 'auth_service.dart';

/// Shown on first login (temporary password) and after an admin reset.
/// The router keeps the user here until the password is changed.
class ChangePasswordView extends ConsumerStatefulWidget {
  const ChangePasswordView({super.key});

  @override
  ConsumerState<ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends ConsumerState<ChangePasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
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
      final user = await AuthService().changePassword(_current.text, _next.text);
      await ref.read(sessionProvider.notifier).updateUser(user);
      ref.read(messagesProvider.notifier).showSuccess('Password updated.');
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AppCard(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BrandWordmark(size: 22),
                    const SizedBox(height: 18),
                    Text('Set a new password', style: ts(22, w: FontWeight.w800, color: p.ink, ls: -0.5, height: 1.2)),
                    const SizedBox(height: 6),
                    Text(
                      user?.mustChangePassword == true ? 'You are using a temporary password. Choose your own before continuing.' : 'Choose a new password for ${user?.email ?? 'your account'}.',
                      style: ts(13, color: p.muted),
                    ),
                    const SizedBox(height: 20),
                    _PwField(label: 'Current password', controller: _current, validator: (v) => (v ?? '').isEmpty ? 'Current password is required.' : null),
                    _PwField(
                        label: 'New password',
                        controller: _next,
                        validator: (v) {
                          final t = v ?? '';
                          if (t.length < 8) return 'Use at least 8 characters.';
                          if (!RegExp(r'[A-Za-z]').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) {
                            return 'Include at least one letter and one number.';
                          }
                          return null;
                        }),
                    _PwField(label: 'Confirm new password', controller: _confirm, validator: (v) => v != _next.text ? 'Passwords do not match.' : null, onSubmitted: (_) => _submit()),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!, style: ts(12, color: p.warn)),
                      ),
                    SizedBox(
                      height: 40,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.brand,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Save password', style: ts(13, w: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: user?.mustChangePassword == true
                          ? LinkButton('Sign out instead', onPressed: () => ref.read(sessionProvider.notifier).signOut())
                          : LinkButton('Back', onPressed: () => context.go('/')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PwField extends StatelessWidget {
  const _PwField({required this.label, required this.controller, this.validator, this.onSubmitted});

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
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
            obscureText: true,
            validator: validator,
            onFieldSubmitted: onSubmitted,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: ts(14, color: p.ink),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.all(11),
              border: border(p.pick(p.line, p.fieldLine)),
              enabledBorder: border(p.pick(p.line, p.fieldLine)),
              focusedBorder: border(p.brand),
              errorStyle: ts(11, color: p.warn),
            ),
          ),
        ],
      ),
    );
  }
}

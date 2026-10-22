// Sign in (the board's Login screen), look-only: accounts are not built yet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/page.dart';
import '../../settings/providers/words_provider.dart';
import 'auth_widgets.dart';

class LoginView extends ConsumerWidget {
  const LoginView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal, w = ref.watch(wordsProvider);
    return AuthFrame(
      title: w.tr('Welcome back!'),
      subtitle: w.tr('Sign in to continue your journey.'),
      children: [
        AuthField(label: w.tr('Email or username'), hint: 'you@example.com', keyboard: TextInputType.emailAddress, showLabel: w.tr('Show password'), hideLabel: w.tr('Hide password')),
        AuthField(label: w.tr('Password'), hint: w.tr('Enter your password'), password: true, showLabel: w.tr('Show password'), hideLabel: w.tr('Hide password')),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(key: const ValueKey('forgot'), onPressed: () => comingSoon(context, ref), child: Text(w.tr('Forgot password?'), style: ts(13.5, w: FontWeight.w700, color: p.brand2))),
        ),
        const SizedBox(height: 6),
        PrimaryButton(key: const ValueKey('sign-in'), label: w.tr('Sign in'), onPressed: () => comingSoon(context, ref)),
        const SizedBox(height: 20),
        const SocialButtons(),
        const SizedBox(height: 16),
        SwitchLine(text: w.tr("Don't have an account?"), action: w.tr('Sign up'), onTap: () => context.pushReplacement('/signup')),
      ],
    );
  }
}

// Sign up (the board's Sign Up screen), look-only: accounts are not built yet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../shared/widgets/page.dart';
import '../../settings/providers/words_provider.dart';
import 'auth_widgets.dart';

class SignupView extends ConsumerStatefulWidget {
  const SignupView({super.key});
  @override
  ConsumerState<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends ConsumerState<SignupView> {
  bool _agree = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = ref.watch(wordsProvider);
    final show = w.tr('Show password'), hide = w.tr('Hide password');
    return AuthFrame(
      title: w.tr('Create your account'),
      subtitle: w.tr('Start your mall journey today.'),
      children: [
        AuthField(label: w.tr('Full name'), hint: 'Juan Dela Cruz', showLabel: show, hideLabel: hide),
        AuthField(label: w.tr('Email'), hint: 'you@example.com', keyboard: TextInputType.emailAddress, showLabel: show, hideLabel: hide),
        AuthField(label: w.tr('Password'), hint: w.tr('Create a password'), password: true, showLabel: show, hideLabel: hide),
        AuthField(label: w.tr('Confirm password'), hint: w.tr('Confirm your password'), password: true, showLabel: show, hideLabel: hide),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(key: const ValueKey('agree'), value: _agree, activeColor: p.brand, onChanged: (v) => setState(() => _agree = v ?? false)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(w.tr('I agree to the '), style: ts(13.5, color: p.muted)),
                InkWell(key: const ValueKey('terms'), onTap: () => comingSoon(context, ref), child: Text(w.tr('Terms & Conditions'), style: ts(13.5, w: FontWeight.w700, color: p.brand2))),
                Text(w.tr(' and '), style: ts(13.5, color: p.muted)),
                InkWell(key: const ValueKey('privacy'), onTap: () => comingSoon(context, ref), child: Text(w.tr('Privacy Policy'), style: ts(13.5, w: FontWeight.w700, color: p.brand2))),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        PrimaryButton(key: const ValueKey('sign-up'), label: w.tr('Sign up'), onPressed: () => comingSoon(context, ref)),
        const SizedBox(height: 20),
        const SocialButtons(),
        const SizedBox(height: 16),
        SwitchLine(text: w.tr('Already have an account?'), action: w.tr('Sign in'), onTap: () => context.pushReplacement('/login')),
      ],
    );
  }
}

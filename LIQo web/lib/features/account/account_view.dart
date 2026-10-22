import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/theme_mode.dart';
import '../../shared/forms/app_form_dialog.dart';
import '../../shared/forms/field_spec.dart';
import '../../shared/lists/list_scaffold.dart' show StatusPill;
import '../../shared/messaging/messages.dart';
import '../../shared/nav/role_nav.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/detail_widgets.dart';
import '../../shared/widgets/skeleton.dart';
import '../auth/auth_service.dart';
import 'profile_service.dart';

const _detailFields = [
  FieldSpec(name: 'fullName', label: 'Full name', required: true, maxLength: 200),
  FieldSpec(name: 'email', label: 'Email address', kind: FieldKind.email, required: true, maxLength: 255),
];

/// The signed-in person's own page: who they are, their details, their
/// password, how the app looks for them, and signing out.
///
/// Details: a superadmin edits them at once; everyone else sends a change
/// request that a superadmin approves (one waiting request at a time).
class AccountView extends ConsumerStatefulWidget {
  const AccountView({super.key});

  @override
  ConsumerState<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends ConsumerState<AccountView> {
  final _service = ProfileService();
  static final _fmt = DateFormat('MMM d, yyyy');
  ProfileRequest? _request;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Fresh account details (an approved change shows without signing out) and my latest request.
  Future<void> _refresh() async {
    try {
      final me = await AuthService().me();
      if (!mounted) return;
      await ref.read(sessionProvider.notifier).updateUser(me);
    } catch (_) {}
    if (ref.read(currentUserProvider)?.role == 'superadmin') return;
    try {
      final r = await _service.myRequest();
      if (mounted) setState(() => _request = r);
    } catch (_) {}
  }

  void _msg(String text, {bool error = false}) {
    final n = ref.read(messagesProvider.notifier);
    error ? n.showError(text) : n.showSuccess(text);
  }

  Future<void> _cancelRequest() async {
    final ok = await confirmDialog(context, title: 'Cancel your request?', message: 'Nothing about your account changes. You can send a new request afterwards.', confirmLabel: 'Cancel request');
    if (!ok) return;
    try {
      final r = await _service.cancel();
      setState(() => _request = r);
      _msg('Request cancelled.');
    } catch (e) {
      _msg(formatApiError(e), error: true);
    }
  }

  Future<void> _signOut() async {
    try {
      await AuthService().logout();
    } catch (e) {
      // Signing out locally must work even if the server cannot be reached.
      ref.read(messagesProvider.notifier).show(formatApiError(e));
    }
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final user = ref.watch(currentUserProvider);
    final nav = navForRole(user?.role ?? 'store_owner');
    final mode = ref.watch(themeModeProvider);
    final stacked = Bp.isTablet(context);
    final isSuper = user?.role == 'superadmin';
    final waiting = _request?.pending == true ? _request : null;
    final rejected = _request?.status == 'rejected' ? _request : null;

    final profile = DetailCard(
      title: 'Profile',
      subtitle: isSuper ? 'Changes apply at once' : 'Changes are approved by a superadmin',
      trailing: _editing || waiting != null
          ? null
          : AppButton(label: isSuper ? 'Edit' : 'Request a change', small: true, icon: Icons.edit_outlined, onPressed: () => setState(() => _editing = true)),
      child: _editing
          ? AppFormBody(
              fields: _detailFields,
              initial: {'fullName': user?.fullName, 'email': user?.email},
              submitLabel: isSuper ? 'Save' : 'Send request',
              onSubmit: (v) async {
                final name = v['fullName'] as String;
                final email = v['email'] as String;
                if (isSuper) {
                  final updated = await _service.updateOwn(fullName: name, email: email);
                  await ref.read(sessionProvider.notifier).updateUser(updated);
                } else {
                  final r = await _service.requestChange(fullName: name, email: email);
                  setState(() => _request = r);
                }
              },
              onCancel: () => setState(() => _editing = false),
              onDone: () {
                setState(() => _editing = false);
                _msg(isSuper ? 'Your details were updated.' : 'Request sent. A superadmin will review it.');
              },
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rejected != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Notice(bold: 'Your last request was not approved.', text: rejected.reason ?? ''),
                  ),
                DetailRow('Full name', user?.fullName),
                DetailRow('Email', user?.email),
                DetailRow('Role', nav.name),
                DetailRow('Status', null, child: Align(alignment: Alignment.centerLeft, child: StatusPill(active: user?.isActive == true))),
              ],
            ),
    );

    final waitingCard = waiting == null
        ? null
        : DetailCard(
            title: 'Waiting for approval',
            subtitle: 'Sent ${_fmt.format(waiting.createdAt)}. Your account keeps its current details until a superadmin approves.',
            trailing: AppButton(label: 'Cancel request', small: true, onPressed: _cancelRequest),
            child: Column(
              children: [
                DetailRow('New name', waiting.requestedName),
                DetailRow('New email', waiting.requestedEmail),
                if (waiting.emailChanged)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(alignment: Alignment.centerLeft, child: Text('Once approved, sign in with the new email. Your password stays the same.', style: ts(11, color: p.muted))),
                  ),
              ],
            ),
          );

    final security = DetailCard(
      title: 'Security',
      subtitle: 'Keep your sign-in safe',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose a new password at any time. You stay signed in on this browser after changing it.', style: ts(12, color: p.muted)),
          const SizedBox(height: 14),
          AppButton(label: 'Change password', icon: Icons.lock_outline, primary: true, onPressed: () => context.go('/change-password')),
        ],
      ),
    );

    final appearance = DetailCard(
      title: 'Appearance',
      subtitle: 'Remembered on this browser',
      child: _ModeChoice(
        mode: mode,
        onChanged: (m) {
          final n = ref.read(themeModeProvider.notifier);
          switch (m) {
            case ThemeMode.dark:
              n.setDark(true);
            case ThemeMode.light:
              n.setDark(false);
            case ThemeMode.system:
              n.followSystem();
          }
        },
      ),
    );

    final session = DetailCard(
      title: 'Session',
      subtitle: 'This browser',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Signing out ends your session here. Other devices stay signed in until their session expires.', style: ts(12, color: p.muted)),
          const SizedBox(height: 14),
          AppButton(label: 'Sign out', icon: Icons.logout, onPressed: _signOut),
        ],
      ),
    );

    // What this person owns or manages (Round 14).
    final access = ref.watch(myAccessProvider);
    final accessCard = DetailCard(
      title: 'Your access',
      subtitle: 'What you can see and manage',
      child: access.when(
        loading: () => const Shimmer(child: SkeletonLines(widths: [0.7, 0.5, 0.6], height: 12, gap: 12)),
        error: (e, _) => Text(formatApiError(e), style: ts(12, color: p.warn)),
        data: (a) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (a.role) {
            'superadmin' => [const DetailRow('Scope', 'Everything on the platform')],
            'supervisor' => [
                DetailRow('Whole malls', a.malls.isEmpty ? 'None' : a.malls.join(', ')),
                DetailRow('Single branches', a.branches.isEmpty ? 'None' : a.branches.join(', ')),
              ],
            'mall_admin' => [
                DetailRow('Branch', a.branches.isEmpty ? 'Not assigned yet' : a.branches.first),
                DetailRow('Reports to', a.reportsTo ?? 'No owner yet'),
              ],
            _ => [DetailRow('Stores', a.stores.isEmpty ? 'None yet' : a.stores.join(', '))],
          },
        ),
      ),
    );

    final left = [profile, if (waitingCard != null) waitingCard, accessCard, session];
    final right = [security, appearance];
    List<Widget> spaced(List<Widget> cards) => [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 18), cards[i]],
        ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHead(
          eyebrow: '${nav.name} / My account',
          title: 'My account',
          subtitle: 'Your profile, password and how the app looks for you.',
        ),
        _Hero(name: user?.fullName ?? '', email: user?.email ?? '', initials: user?.initials ?? '?', roleName: nav.name, roleLine: nav.subtitle, active: user?.isActive == true),
        const SizedBox(height: 18),
        if (stacked)
          ...spaced([profile, if (waitingCard != null) waitingCard, accessCard, security, appearance, session])
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: spaced(left))),
              const SizedBox(width: 18),
              Expanded(child: Column(children: spaced(right))),
            ],
          ),
      ],
    );
  }
}

/// The person at a glance: a large avatar in the brand gradient, their name,
/// email, role and what the role is for.
class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.email, required this.initials, required this.roleName, required this.roleLine, required this.active});

  final String name;
  final String email;
  final String initials;
  final String roleName;
  final String roleLine;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    final avatar = Container(
      width: mobile ? 64 : 80,
      height: mobile ? 64 : 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.brand, Pal.brandCrimson]),
        shape: BoxShape.circle,
        boxShadow: p.darkOnly(p.glow),
      ),
      child: Text(initials, style: ts(mobile ? 22 : 28, w: FontWeight.w800, color: p.avatarFg, ls: -0.5, height: 1.1)),
    );
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, overflow: TextOverflow.ellipsis, maxLines: 2, style: ts(mobile ? 20 : 24, w: FontWeight.w800, color: p.ink, ls: -0.5, height: 1.2)),
        const SizedBox(height: 3),
        Text(email, overflow: TextOverflow.ellipsis, style: ts(13, color: p.muted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [Pill(roleName, kind: PillKind.blue), StatusPill(active: active)]),
        const SizedBox(height: 12),
        Text(roleLine, style: ts(12, color: p.muted)),
      ],
    );
    return Container(
      padding: EdgeInsets.all(mobile ? 18 : 26),
      decoration: BoxDecoration(
        color: p.panel,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: p.shadow,
      ),
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
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar, const SizedBox(height: 14), who])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar, const SizedBox(width: 22), Expanded(child: who)]),
        ],
      ),
    );
  }
}

/// Three choices in one control: Dark, Light, or follow the device.
class _ModeChoice extends StatelessWidget {
  const _ModeChoice({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static const keys = {
    ThemeMode.dark: ValueKey('mode-dark'),
    ThemeMode.light: ValueKey('mode-light'),
    ThemeMode.system: ValueKey('mode-system'),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget option(ThemeMode m, IconData icon, String label) {
      final selected = mode == m;
      return Expanded(
        child: AnimatedContainer(
          key: keys[m],
          duration: motionFast,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? p.soft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? p.brand : Colors.transparent),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: selected ? p.brand : p.muted),
                    const SizedBox(height: 4),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.brand2 : p.slate)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.boxBg, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(11)),
      child: Row(
        children: [
          option(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
          const SizedBox(width: 4),
          option(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
          const SizedBox(width: 4),
          option(ThemeMode.system, Icons.brightness_auto_outlined, 'Device'),
        ],
      ),
    );
  }
}

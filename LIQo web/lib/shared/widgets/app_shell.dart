import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/theme_mode.dart';
import '../../features/account/profile_service.dart';
import '../../features/auth/auth_service.dart';
import '../nav/role_nav.dart';
import 'common.dart';

/// Top bar + sidebar around every signed-in page. The page itself is [child]
/// from the router's ShellRoute.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Sidebar(),
                // The page navigator gets a real height. Each page scrolls itself
                // (ShellPage), so during a page change the old page keeps its own
                // height instead of being squeezed to the new one.
                Expanded(child: ClipRect(child: child)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The scrolling frame of one page inside the shell, with the page padding.
/// Every shell route wraps its page in this, inside the page transition.
class ShellPage extends StatelessWidget {
  const ShellPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = Bp.isMobile(context);
    final hPad = mobile ? 13.0 : (width * 0.03).clamp(18.0, 38.0);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, mobile ? 22 : 28, hPad, 40),
      child: child,
    );
  }
}

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  Future<void> _signOut(WidgetRef ref) async {
    await AuthService().logout();
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    final user = ref.watch(currentUserProvider);
    final nav = navForRole(user?.role ?? 'store_owner');

    final avatar = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.brand, Pal.brandCrimson]),
        shape: BoxShape.circle,
      ),
      child: Text(user?.initials ?? '?', style: ts(12, w: FontWeight.w800, color: p.avatarFg)),
    );

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 24),
      decoration: BoxDecoration(
        color: p.shell,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const BrandWordmark(size: 26),
              if (!mobile) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: p.fieldLine),
                const SizedBox(width: 12),
                Text('ADMIN', style: ts(10, w: FontWeight.w700, color: p.sideNote, ls: 1.4)),
              ],
              const Spacer(),
              if (!mobile) ...[
                Container(
                  height: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: p.demoBg,
                    border: Border.all(color: p.demoLine),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(nav.name.toUpperCase(), style: ts(10, w: FontWeight.w700, color: p.demoText, ls: 1.2)),
                ),
                const SizedBox(width: 12),
              ],
              Tooltip(
                message: p.dark ? 'Switch to light mode' : 'Switch to dark mode',
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Material(
                    color: p.panel,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: BorderSide(color: p.fieldLine)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => ref.read(themeModeProvider.notifier).setDark(!p.dark),
                      child: Center(child: ThemeToggleIcon(size: 16, color: p.btnText)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                tooltip: 'Account',
                offset: const Offset(0, 44),
                onSelected: (v) {
                  if (v == 'logout') _signOut(ref);
                  if (v == 'account') context.go('${nav.prefix}/account');
                  if (v == 'password') context.go('/change-password');
                  if (v == 'system') ref.read(themeModeProvider.notifier).followSystem();
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(user?.fullName ?? '', style: ts(13, w: FontWeight.w700, color: p.ink)),
                        Text(user?.email ?? '', style: ts(11, color: p.muted)),
                        Text(nav.name, style: ts(11, color: p.brand2)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'account',
                    child: Row(children: [Icon(Icons.person_outline, size: 16), SizedBox(width: 8), Text('My account')]),
                  ),
                  const PopupMenuItem<String>(
                    value: 'password',
                    child: Row(children: [Icon(Icons.lock_outline, size: 16), SizedBox(width: 8), Text('Change password')]),
                  ),
                  const PopupMenuItem<String>(
                    value: 'system',
                    child: Row(children: [Icon(Icons.brightness_auto_outlined, size: 16), SizedBox(width: 8), Text('Follow device theme')]),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [Icon(Icons.logout, size: 16), SizedBox(width: 8), Text('Sign out')],
                    ),
                  ),
                ],
                child: avatar,
              ),
            ],
          ),
          // The brand's route line: a thin orange-to-crimson gradient along the bottom edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [p.shell, p.brand, Pal.brandCrimson, p.shell],
                    stops: const [0, 0.35, 0.72, 1],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key});

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  /// One key per nav item, to measure where the active one sits.
  final Map<String, GlobalKey> _keys = {};
  final _stackKey = GlobalKey();
  double? _indicatorTop;
  double _indicatorHeight = 0;

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// After layout, place the orange indicator on the active item; it then
  /// glides there with an animation instead of jumping.
  void _measure(String? activeId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      final item = activeId == null ? null : _keys[activeId]?.currentContext?.findRenderObject() as RenderBox?;
      double? top;
      double height = 0;
      if (stack != null && item != null && stack.hasSize && item.hasSize) {
        top = item.localToGlobal(Offset.zero, ancestor: stack).dy;
        height = item.size.height;
      }
      if (top != _indicatorTop || height != _indicatorHeight) {
        setState(() {
          _indicatorTop = top;
          _indicatorHeight = height;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mobile = Bp.isMobile(context);
    final user = ref.watch(currentUserProvider);
    final nav = navForRole(user?.role ?? 'store_owner');
    final location = GoRouterState.of(context).uri.path;
    final active = nav.itemForPath(location);
    _measure(active?.id);
    // Waiting profile change requests, shown as a count on their sidebar item.
    final waiting = user?.role == 'superadmin' ? (ref.watch(pendingProfileRequestsProvider).valueOrNull ?? 0) : 0;

    return Container(
      width: mobile ? 68 : 238,
      padding: mobile
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 18)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      decoration: BoxDecoration(
        color: p.shell,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile)
            const Padding(padding: EdgeInsets.only(bottom: 14), child: Center(child: BrandTile(size: 36)))
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text('WORKSPACE', style: ts(10, w: FontWeight.w800, color: p.sideNote, ls: 1.2)),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(5, 0, 5, 23),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.boxBg,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Signed in as', style: ts(11, color: p.muted)),
                  const SizedBox(height: 4),
                  Text(user?.fullName ?? '', style: ts(13, w: FontWeight.w700, color: p.ink), overflow: TextOverflow.ellipsis),
                  Text(nav.name, style: ts(11, color: p.brand2)),
                ],
              ),
            ),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: Stack(
                key: _stackKey,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in nav.items) ...[
                        _NavButton(
                          key: _keyFor(item.id),
                          item: item,
                          active: item.id == active?.id,
                          compact: mobile,
                          badge: item.id == 'profile_requests' ? waiting : 0,
                          onTap: () => context.go(item.path),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                  // The sliding indicator: a short orange bar on the left edge of the active item.
                  if (_indicatorTop != null)
                    AnimatedPositioned(
                      duration: motionBase,
                      curve: Curves.easeOutCubic,
                      left: 0,
                      top: _indicatorTop! + _indicatorHeight * 0.25,
                      height: _indicatorHeight * 0.5,
                      child: IgnorePointer(
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: p.brand,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: p.darkOnly([BoxShadow(color: p.brand.withAlpha(140), blurRadius: 8)]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!mobile)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 17, 10, 0),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line))),
              child: Text('LIQO Wayfinding Platform\n$brandTagline · v${AppConfig.appVersion}', style: ts(11, color: p.sideNote)),
            ),
        ],
      ),
    );
  }
}

/// One sidebar entry. The highlight fades in, the label weight shifts, and on
/// hover the row nudges 3 px to the right: small cues, never a jump.
class _NavButton extends StatefulWidget {
  const _NavButton({super.key, required this.item, required this.active, required this.compact, required this.onTap, this.badge = 0});

  final NavItem item;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  /// A count shown on the item (waiting requests); 0 hides it.
  final int badge;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final item = widget.item;
    final active = widget.active;
    final radius = BorderRadius.circular(9);
    final color = active ? p.brand2 : (_hover ? p.ink : p.slate);
    final nudge = !active && _hover ? 3.0 : 0.0;

    final button = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: motionFast,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(nudge, 0, 0),
        decoration: BoxDecoration(
          color: active ? p.soft : (_hover ? p.hover : Colors.transparent),
          borderRadius: radius,
          boxShadow: active ? p.darkOnly([BoxShadow(color: p.brand.withAlpha(50), blurRadius: 16, offset: const Offset(0, 4))]) : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            hoverColor: Colors.transparent,
            onTap: widget.onTap,
            child: Padding(
              padding: widget.compact
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 12)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: widget.compact
                  ? Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(item.icon, size: 18, color: active ? p.brand : color),
                          if (widget.badge > 0)
                            Positioned(right: -4, top: -3, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle))),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        SizedBox(width: 18, child: Icon(item.icon, size: 16, color: active ? p.brand : color)),
                        const SizedBox(width: 11),
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: motionFast,
                            style: ts(13, w: active ? FontWeight.w700 : FontWeight.w500, color: color),
                            child: Text(item.label, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        if (widget.badge > 0)
                          Container(
                            key: const ValueKey('nav-badge'),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(10)),
                            child: Text(widget.badge > 99 ? '99+' : '${widget.badge}', style: ts(10, w: FontWeight.w800, color: p.avatarFg, height: 1.3)),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    return widget.compact ? Tooltip(message: item.label, child: button) : button;
  }
}

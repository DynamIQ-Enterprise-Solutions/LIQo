import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_view.dart';
import '../features/accounts/accounts_view.dart';
import '../features/announcements/announcements_view.dart';
import '../features/analytics/analytics_view.dart';
import '../features/audit/audit_view.dart';
import '../features/auth/change_password_view.dart';
import '../features/auth/login_view.dart';
import '../features/common/placeholder_view.dart';
import '../features/malls/malls_view.dart';
import '../features/malls/mall_detail_view.dart';
import '../features/malls/branch_detail_view.dart';
import '../features/accounts/account_detail_view.dart';
import '../features/stores/store_detail_view.dart';
import '../features/stores/owner_detail_view.dart';
import '../features/stores/option_detail_view.dart';
import '../features/announcements/announcement_detail_view.dart';
import '../features/profile_requests/profile_request_detail_view.dart';
import '../features/reports/report_detail_view.dart';
import '../features/requests/credit_request_detail_view.dart';
import '../features/requests/requests_view.dart';
import '../features/map_editor/map_editor_view.dart';
import '../features/map_editor/map_viewer_view.dart';
import '../features/overview/overview_view.dart';
import '../features/settings/settings_view.dart';
import '../features/stores/options_view.dart';
import '../features/stores/owners_view.dart';
import '../features/stores/stores_view.dart';
import '../shared/nav/role_nav.dart';
import '../shared/widgets/app_shell.dart';
import '../shared/widgets/common.dart';
import 'session.dart';
import 'theme.dart';

/// Every page inside the shell: the old page leaves at once and the new one
/// fades and rises in (owner decision 2026-10-22: "instant out, soft in"), so
/// two pages are never on screen together. Each page scrolls inside its own
/// [ShellPage].
CustomTransitionPage<void> _pageWithFade({required LocalKey key, required Widget child}) => CustomTransitionPage<void>(
      key: key,
      child: ShellPage(child: child),
      transitionDuration: motionBase,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) => _InstantOutSoftIn(animation: animation, secondaryAnimation: secondaryAnimation, child: child),
    );

/// Hides the page as soon as another page starts covering it, and fades and
/// lifts it in when it is the one arriving.
class _InstantOutSoftIn extends StatefulWidget {
  const _InstantOutSoftIn({required this.animation, required this.secondaryAnimation, required this.child});

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_InstantOutSoftIn> createState() => _InstantOutSoftInState();
}

class _InstantOutSoftInState extends State<_InstantOutSoftIn> {
  late CurvedAnimation _curved = CurvedAnimation(parent: widget.animation, curve: Curves.easeOutCubic);
  static final _riseTween = Tween<Offset>(begin: const Offset(0, 0.012), end: Offset.zero);

  @override
  void didUpdateWidget(_InstantOutSoftIn old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      _curved.dispose();
      _curved = CurvedAnimation(parent: widget.animation, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _curved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.secondaryAnimation,
        child: FadeTransition(opacity: _curved, child: SlideTransition(position: _riseTween.animate(_curved), child: widget.child)),
        // Covered (even a little) by the next page: gone, state kept.
        builder: (context, page) => Visibility(visible: widget.secondaryAnimation.value == 0, maintainState: true, child: page!),
      );
}

/// One page per record. The path tells the role; the id tells the record.
final Map<String, Widget Function(int id)> _detailRoutes = {
  '/superadmin/malls/:id': (id) => MallDetailView(mallId: id),
  '/mall-owner/malls/:id': (id) => MallDetailView(mallId: id),
  '/superadmin/branches/:id': (id) => BranchDetailView(branchId: id),
  '/mall-owner/branches/:id': (id) => BranchDetailView(branchId: id),
  '/mall-admin/branch/:id': (id) => BranchDetailView(branchId: id),
  '/superadmin/accounts/:id': (id) => AccountDetailView(accountId: id),
  '/superadmin/profile-requests/:id': (id) => ProfileRequestDetailView(requestId: id),
  '/superadmin/credit-requests/:id': (id) => CreditRequestDetailView(requestId: id),
  '/superadmin/reports/:id': (id) => ReportDetailView(reportId: id),
  '/mall-owner/reports/:id': (id) => ReportDetailView(reportId: id),
  '/mall-admin/reports/:id': (id) => ReportDetailView(reportId: id),
  '/store-owner/reports/:id': (id) => ReportDetailView(reportId: id),
  '/mall-owner/admins/:id': (id) => AccountDetailView(accountId: id),
  '/mall-admin/stores/:id': (id) => StoreDetailView(storeId: id),
  '/mall-owner/stores/:id': (id) => StoreDetailView(storeId: id),
  '/store-owner/stores/:id': (id) => StoreDetailView(storeId: id),
  '/mall-admin/owners/:id': (id) => OwnerDetailView(ownerId: id),
  '/mall-owner/owners/:id': (id) => OwnerDetailView(ownerId: id),
  '/mall-admin/options/:id': (id) => OptionDetailView(optionId: id),
  '/mall-owner/announcements/:id': (id) => AnnouncementDetailView(announcementId: id),
  '/mall-admin/announcements/:id': (id) => AnnouncementDetailView(announcementId: id),
  '/store-owner/announcements/:id': (id) => AnnouncementDetailView(announcementId: id),
};

/// Lets go_router re-run its redirect whenever the session changes.
class _SessionListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

final _sessionListenableProvider = Provider<_SessionListenable>((ref) {
  final listenable = _SessionListenable();
  ref.listen(sessionProvider, (_, __) => listenable.ping());
  ref.onDispose(listenable.dispose);
  return listenable;
});

/// Which pages a later phase will replace. Everything else gets a placeholder.
Widget _pageFor(NavItem item, RoleNav nav, {Map<String, String> query = const {}}) {
  final tab = query['tab'];
  switch (item.id) {
    case 'overview':
      return const OverviewView();
    case 'accounts':
    case 'admins':
      return const AccountsView();
    case 'malls':
      return MallsView(initialTab: tab == 'branches' ? 1 : 0);
    case 'branches':
    case 'branch':
      return const MallsView(branchesOnly: true);
    case 'analytics':
      return const AnalyticsView();
    case 'audit':
      return const AuditView();
    case 'settings':
      return const SettingsView();
    case 'announcements':
      return const AnnouncementsView();
    case 'stores':
    case 'my_stores':
      return const StoresView();
    case 'owners':
      return const OwnersView();
    case 'options':
      return const OptionsView();
    case 'account':
      return const AccountView();
    case 'requests':
      return RequestsView(initialTab: requestsTabFrom(tab));
    case 'map_editor':
      return const MinWidthGate(minWidth: 900, what: 'The map editor', child: MapEditorView());
    case 'maps':
      return MapViewerView(initialBranchId: int.tryParse(query['branch'] ?? ''));
  }
  const phases = <String, String>{};
  return PlaceholderView(
    eyebrow: '${nav.name} / ${item.label}',
    title: item.label,
    phase: phases[item.id] ?? 'a later phase',
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(_sessionListenableProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.uri.path;
      // The supervisor role is called "Mall owner" now; old links still work.
      if (path == '/supervisor' || path.startsWith('/supervisor/')) {
        return state.uri.toString().replaceFirst('/supervisor', '/mall-owner');
      }
      final signedIn = session.isSignedIn;

      if (!signedIn) {
        if (path == '/login') return null;
        final from = (path == '/' ) ? '' : '?from=${Uri.encodeComponent(state.uri.toString())}';
        return '/login$from';
      }

      final user = session.user!;
      if (user.mustChangePassword) {
        return path == '/change-password' ? null : '/change-password';
      }

      final nav = navForRole(user.role);
      if (path == '/' || path == '/login') return nav.homePath;
      if (path == '/change-password') return null;
      if (path == '/unauthorized') return null;
      if (!path.startsWith(nav.prefix)) return '/unauthorized';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
      GoRoute(
        path: '/login',
        builder: (_, state) => LoginView(from: state.uri.queryParameters['from']),
      ),
      GoRoute(path: '/change-password', builder: (_, __) => const ChangePasswordView()),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/unauthorized', pageBuilder: (_, __) => _pageWithFade(key: const ValueKey('/unauthorized'), child: const UnauthorizedView())),
          for (final e in _detailRoutes.entries)
            GoRoute(
              path: e.key,
              pageBuilder: (_, state) {
                final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                return _pageWithFade(key: ValueKey('${e.key}-$id'), child: e.value(id));
              },
            ),
          // The old People page lives inside the mall page now; keep the link working.
          GoRoute(path: '/superadmin/malls/:id/people', redirect: (_, state) => '/superadmin/malls/${state.pathParameters['id']}'),
          // Round 19: Profile requests became a tab of Requests & reports.
          GoRoute(path: '/superadmin/profile-requests', redirect: (_, __) => '/superadmin/requests?tab=profile'),
          for (final nav in roleNavs.values)
            for (final item in nav.items)
              GoRoute(
                path: item.path,
                pageBuilder: (_, state) => _pageWithFade(
                  key: ValueKey(item.path),
                  child: _pageFor(item, nav, query: state.uri.queryParameters),
                ),
              ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri.path}')),
    ),
  );
});

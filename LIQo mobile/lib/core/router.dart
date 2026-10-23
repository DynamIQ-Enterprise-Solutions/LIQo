// The routes. First launch: splash -> onboarding -> pick a mall -> Home. Later
// launches: splash -> Home. The bottom nav (Home / Map / Saved / More) is a
// shell; full-screen pages (search, a place, your route, route options, a post,
// sign in, settings, help, about) cover it, as on the board. Page transitions
// are the platform's own (owner decision 2026-10-22).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/views/login_view.dart';
import '../features/auth/views/signup_view.dart';
import '../features/home/views/home_view.dart';
import '../features/home/views/post_view.dart';
import '../features/malls/providers/mall_provider.dart';
import '../features/malls/views/mall_picker_view.dart';
import '../features/map/views/map_screen.dart';
import '../features/navigation/views/route_guidance_view.dart';
import '../features/navigation/views/route_options_view.dart';
import '../features/onboarding/providers/boot_provider.dart';
import '../features/onboarding/views/onboarding_view.dart';
import '../features/onboarding/views/splash_view.dart';
import '../features/places/views/place_details_view.dart';
import '../features/places/views/place_list_view.dart';
import '../features/saved/views/saved_view.dart';
import '../features/search/views/search_view.dart';
import '../features/settings/views/about_view.dart';
import '../features/settings/views/help_view.dart';
import '../features/settings/views/more_view.dart';
import '../features/settings/views/settings_view.dart';
import '../shared/widgets/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Where the first-launch flow sends someone, or null to stay.
String? bootRedirect(Boot boot, String? mall, String loc) {
  if (!boot.splashDone) return loc == '/splash' ? null : '/splash';
  if (!boot.onboardingSeen) return loc == '/onboarding' ? null : '/onboarding';
  if (mall == null) return loc == '/malls' ? null : '/malls';
  if (loc == '/splash' || loc == '/onboarding') return '/home';
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(bootProvider, (_, _) => refresh.value++);
  ref.listen(mallProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => bootRedirect(ref.read(bootProvider), ref.read(mallProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashView()),
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingView()),
      GoRoute(path: '/malls', builder: (context, state) => const MallPickerView()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeView(),
              routes: [GoRoute(path: 'category/:cat', builder: (context, state) => PlaceListView(category: state.pathParameters['cat']!))],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (context, state) => const MapScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/saved', builder: (context, state) => SavedView(tab: state.uri.queryParameters['tab'])),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (context, state) => const MoreView())]),
        ],
      ),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/search', builder: (context, state) => SearchView(go: state.uri.queryParameters['go'] == '1')),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/place/:mall/:place',
        builder: (context, state) => PlaceDetailsView(mallId: state.pathParameters['mall']!, placeId: state.pathParameters['place']!),
      ),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/route', builder: (context, state) => const RouteGuidanceView()),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/route-options', builder: (context, state) => const RouteOptionsView()),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/post/:id', builder: (context, state) => PostView(postId: state.pathParameters['id']!)),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/login', builder: (context, state) => const LoginView()),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/signup', builder: (context, state) => const SignupView()),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/more/settings', builder: (context, state) => const SettingsView()),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/more/help', builder: (context, state) => const HelpView()),
      GoRoute(parentNavigatorKey: rootNavigatorKey, path: '/more/about', builder: (context, state) => const AboutView()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

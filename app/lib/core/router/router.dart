import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/favorites/presentation/favorites_screen.dart';
import 'package:lunaway/features/map/presentation/map_screen.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/shared/adaptive_shell.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'router.g.dart';

// keepAlive: the router lives as long as the app; rebuilding it would drop
// the navigation stack of every branch.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.map,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              // `/map?place=<id>` opens a place: a link to share, a web page
              // to bookmark.
              GoRoute(
                path: AppRoutes.map,
                builder: (_, state) => MapScreen(placeId: state.uri.queryParameters['place']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: AppRoutes.favorites, builder: (_, _) => const FavoritesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.profile, builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

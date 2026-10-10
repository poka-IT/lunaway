import 'package:go_router/go_router.dart';
import 'package:lunaway/core/router/popup_routes.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/presentation/account_pages.dart';
import 'package:lunaway/features/account/presentation/contributions_screen.dart';
import 'package:lunaway/features/account/presentation/recovery_screens.dart';
import 'package:lunaway/features/favorites/presentation/favorites_screen.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';
import 'package:lunaway/features/map/presentation/map_screen.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/offline/presentation/offline_maps_screen.dart';
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
    // Counts the dialogs, sheets and menus of every navigator, and gives
    // those over the map an entry of the tab's history: go_router hands the
    // root observers what the branches' navigators push too
    // (`notifyRootObserver`, on by default).
    observers: [ref.watch(popupObserverProvider)],
    onEnter: keepGuidance(ref),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AdaptiveShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              // `/map?place=<id>` opens a place, `/map?poi=<id>` a shop or a
              // service: a link to share, a web page to bookmark. One route
              // for every selection (MapLink): the map's page stays the same
              // page, its map is never made again by a selection.
              GoRoute(
                path: AppRoutes.map,
                builder: (_, state) => MapScreen(link: MapLink.of(state.uri)),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: AppRoutes.favorites, builder: (_, _) => const FavoritesScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (_, _) => const ProfileScreen(),
                routes: [
                  GoRoute(path: 'recovery-card', builder: (_, _) => const RecoveryCardScreen()),
                  GoRoute(path: 'recover', builder: (_, _) => const RecoverScreen()),
                  GoRoute(path: 'contributions', builder: (_, _) => const ContributionsScreen()),
                  GoRoute(path: 'muted', builder: (_, _) => const MutedAuthorsScreen()),
                  GoRoute(path: 'devices', builder: (_, _) => const DevicesScreen()),
                  GoRoute(path: 'delete-account', builder: (_, _) => const DeleteAccountScreen()),
                  GoRoute(path: 'offline-maps', builder: (_, _) => const OfflineMapsScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
      // The route preview and the guidance take the whole window.
      ...navigationRoutes(),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

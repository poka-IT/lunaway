import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/icons/luna_icons.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The frame around the top-level destinations: a bottom bar on a phone, a
/// rail on a tablet, an extended rail on a desktop or a wide browser window.
class AdaptiveShell extends StatelessWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  // Tapping the current destination again returns to its first page.
  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final destinations = [
      (icon: AppIcons.map, selected: AppIcons.mapSelected, label: t.nav.map),
      (icon: AppIcons.favorite, selected: AppIcons.favoriteSelected, label: t.nav.favorites),
      (icon: AppIcons.profile, selected: AppIcons.profileSelected, label: t.nav.profile),
    ];
    final size = WindowSize.of(context);

    if (size == .compact) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = size == .expanded;
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            extended: extended,
            minExtendedWidth: 220,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.fromLTRB(Space.s, Space.m, Space.s, Space.xl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primary,
                    child: LunaIcon(
                      LunaIcons.moonStar,
                      size: 24,
                      color: theme.colorScheme.tertiaryContainer,
                    ),
                  ),
                  if (extended) ...[
                    const SizedBox(width: Space.m),
                    Text(
                      t.appTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                  padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

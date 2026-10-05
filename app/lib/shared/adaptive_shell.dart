import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/i18n/strings.g.dart';

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
      (icon: Icons.map_outlined, selected: Icons.map, label: t.nav.map),
      (icon: Icons.favorite_border, selected: Icons.favorite, label: t.nav.favorites),
      (icon: Icons.person_outline, selected: Icons.person, label: t.nav.profile),
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
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            extended: extended,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// A page under a destination (the profile's account pages): a back button
/// and a title, the content in one readable column, and room at the foot
/// for the dock and the system's gesture area, so the last line is never
/// under them.
class SubPage extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = WindowSize.of(context) == .compact;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? Space.l : Space.xxl,
                Space.s,
                compact ? Space.l : Space.xxl,
                bottom + Space.xxl,
              ),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      icon: const Icon(AppIcons.back),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                const SizedBox(height: Space.l),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded group of rows, as the profile draws its sections.
class SectionCard extends StatelessWidget {
  const new({required this.child, this.padding = EdgeInsets.zero, super.key});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

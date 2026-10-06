import 'package:flutter/material.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// Opens a form or a short choice the way the window calls for: a sheet
/// from the bottom on a phone, where the thumb is, and a centred dialog on
/// a tablet or a desktop, where a sheet across the whole width would read
/// badly. Above the dock and the panels either way.
Future<T?> showFormSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController? scroll)
  builder,
  bool tall = true,
}) {
  if (WindowSize.of(context) == .compact) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => tall
          ? DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.96,
              builder: builder,
            )
          : builder(context, null),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(Space.xxl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * (tall ? 0.88 : 0.7),
        ),
        child: builder(context, null),
      ),
    ),
  );
}

/// The frame of a form: its title with a close button, the fields
/// scrolling, and one primary action fixed at the foot, above the keyboard
/// and the system's gesture area. [footnote] sits above the action (a
/// licence, what happens next).
class FormSheetFrame extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.scrollController,
    this.action,
    this.footnote,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final ScrollController? scrollController;

  /// The primary action, a [FilledButton]; null for a sheet of choices.
  final Widget? action;
  final Widget? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final compact = WindowSize.of(context) == .compact;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        Space.xl,
        compact ? 0 : Space.l,
        Space.s,
        Space.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineSmall),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xxs),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: context.t.common.close,
            icon: const Icon(AppIcons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
    final foot = action == null && footnote == null
        ? null
        : DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Space.xl,
                Space.m,
                Space.xl,
                Space.m + (keyboard > 0 ? 0 : media.padding.bottom),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (footnote != null) ...[
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: footnote!,
                    ),
                    if (action != null) const SizedBox(height: Space.s),
                  ],
                  ?action,
                ],
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Flexible(
            child: ListView(
              controller: scrollController,
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                Space.xl,
                Space.xs,
                Space.xl,
                foot == null ? Space.xl + media.padding.bottom : Space.xl,
              ),
              children: children,
            ),
          ),
          ?foot,
        ],
      ),
    );
  }
}

/// A large tappable choice of a sheet: an icon, a label and a hint, 64 dp
/// high at least, for a thumb in a moving van.
class ChoiceTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.selected = false,
    this.tone,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback? onTap;
  final bool selected;

  /// The icon's colour; the scheme's on-surface variant when null.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LunaTokens.radiusL),
            side: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LunaTokens.radiusL),
            ),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.l,
                  vertical: Space.m,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: tone ?? scheme.onSurfaceVariant,
                      size: 26,
                    ),
                    const SizedBox(width: Space.l),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: theme.textTheme.titleMedium),
                          if (hint != null)
                            Text(
                              hint!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(AppIcons.checkCircle, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

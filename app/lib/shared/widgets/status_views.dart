import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// An empty or failed state: an icon, a sentence that says what happened, a
/// hint of what to do, and at most one action. Empty and error read
/// differently on purpose; an empty list is not a failure.
class MessageView extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.onAction,
    this.error = false,
    this.compact = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;
  final bool error;

  /// For a pane beside the map: smaller icon, left-aligned.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = error ? scheme.error : scheme.primary;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Container(
          width: compact ? 48 : 72,
          height: compact ? 48 : 72,
          decoration: BoxDecoration(
            color: (error ? scheme.errorContainer : scheme.secondaryContainer).withValues(
              alpha: 0.7,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: compact ? 26 : 36, color: accent),
        ),
        SizedBox(height: compact ? 12 : 20),
        Text(
          title,
          textAlign: compact ? TextAlign.start : TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        if (hint != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            hint!,
            textAlign: compact ? TextAlign.start : TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (action != null && onAction != null) ...[
          const SizedBox(height: Space.xl),
          if (error)
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(AppIcons.retry),
              label: Text(action!),
            )
          else
            FilledButton.tonal(onPressed: onAction, child: Text(action!)),
        ],
      ],
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xxl),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: content),
      ),
    );
  }
}

/// A grey block standing for content that is loading, at the size the
/// content will take, so nothing jumps when it arrives. Pulses gently.
class Skeleton extends StatefulWidget {
  const new({this.width, this.height = 16, this.radius = 8, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.pulse)
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.55,
        end: 1,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// The skeleton of a list row: avatar, title, subtitle.
class SkeletonTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.ml),
    child: Row(
      children: [
        Skeleton(width: 44, height: 44, radius: 22),
        SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 180),
              SizedBox(height: Space.s),
              Skeleton(width: 120, height: 12),
            ],
          ),
        ),
      ],
    ),
  );
}

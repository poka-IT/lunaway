import 'package:flutter/material.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';

/// An empty, offline or failed state: a small night landscape, a sentence
/// that says what happened, a hint of what to do, and at most one action.
/// Empty and error read differently on purpose; an empty list is not a
/// failure.
class MessageView extends StatelessWidget {
  const new({
    required this.title,
    this.mood = SceneMood.empty,
    this.hint,
    this.action,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final SceneMood mood;
  final String title;
  final String? hint;
  final String? action;
  final VoidCallback? onAction;

  /// For a pane beside the map or a sheet: a smaller scene, left-aligned.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = mood == SceneMood.error || mood == SceneMood.offline;
    final align = compact ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = compact ? TextAlign.start : TextAlign.center;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        NightScene(mood: mood, width: compact ? 132 : 176),
        SizedBox(height: compact ? Space.l : Space.xxl),
        Text(
          title,
          textAlign: textAlign,
          style: compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall,
        ),
        if (hint != null) ...[
          const SizedBox(height: Space.s),
          Text(
            hint!,
            textAlign: textAlign,
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (action != null && onAction != null) ...[
          const SizedBox(height: Space.xl),
          if (failed)
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(AppIcons.retry),
              label: Text(action!),
            )
          else
            FilledButton(onPressed: onAction, child: Text(action!)),
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

/// A tinted block standing for content that is loading, at the size the
/// content will take, so nothing jumps when it arrives. Pulses gently, and
/// stays still when the user asked for less motion.
class Skeleton extends StatefulWidget {
  const new({this.width, this.height = 16, this.radius = 8, super.key});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.5,
        end: 1,
      ).animate(CurvedAnimation(parent: _pulse, curve: Motion.standard)),
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
        Skeleton(width: 44, height: 44, radius: 14),
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

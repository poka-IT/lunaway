import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/places/presentation/coordinates_card.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// A point the user long-pressed on the map: its coordinates to copy, and the
/// way there.
class PointDetails extends ConsumerWidget {
  const new({required this.position, this.scrollController, this.onClose, super.key});

  final LatLng position;
  final ScrollController? scrollController;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.xxs, Space.xl, Space.huge),
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(AppIcons.point, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: Space.ml),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(t.map.pointTitle, style: theme.textTheme.headlineSmall),
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: t.common.close,
                icon: const Icon(AppIcons.close),
                onPressed: onClose,
              ),
          ],
        ),
        const SizedBox(height: Space.l),
        CoordinatesCard(position: position),
        const SizedBox(height: Space.l),
        FilledButton.icon(
          onPressed: () => openDirections(context, ref, position),
          icon: const Icon(AppIcons.directions),
          label: Text(t.place.directions),
        ),
      ],
    );
  }
}

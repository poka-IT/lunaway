import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

/// Replaces the stops of the route to [target] with [next] and says so, with
/// the way back: every change of the stops can be undone.
void changeStops(
  BuildContext context,
  WidgetRef ref,
  RouteTarget target,
  List<RouteStop> next,
  String message,
) {
  final controller = ref.read(routeStopsControllerProvider(target).notifier);
  final before = ref.read(routeStopsControllerProvider(target));
  controller.set(next);
  showMessage(
    ScaffoldMessenger.maybeOf(context),
    message,
    action: SnackBarAction(label: context.t.common.undo, onPressed: () => controller.set(before)),
  );
}

/// The stops of the preview's route, a short list: drag to reorder, swipe
/// or the cross to remove. The route and its totals follow each change.
class StopsStrip extends ConsumerWidget {
  const new({required this.target, super.key});

  final RouteTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final stops = ref.watch(routeStopsControllerProvider(target));
    if (stops.isEmpty) return const SizedBox.shrink();
    void remove(int i) =>
        changeStops(context, ref, target, [...stops]..removeAt(i), t.navigation.stops.removed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.navigation.stops.title, style: theme.textTheme.titleMedium),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: stops.length,
          onReorderItem: (from, to) {
            final next = [...stops];
            next.insert(to, next.removeAt(from));
            changeStops(context, ref, target, next, t.navigation.stops.moved);
          },
          itemBuilder: (context, i) => Dismissible(
            key: ValueKey('stop-$i-${stops[i].hashCode}'),
            onDismissed: (_) => remove(i),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 52,
              leading: ReorderableDragStartListener(
                index: i,
                child: Tooltip(
                  message: t.navigation.stops.reorder,
                  child: const SizedBox.square(dimension: 48, child: Icon(AppIcons.reorder)),
                ),
              ),
              title: Text(
                stops[i].label ?? t.navigation.stops.point,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: t.navigation.stops.remove,
                icon: const Icon(AppIcons.close),
                onPressed: () => remove(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

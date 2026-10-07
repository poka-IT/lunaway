import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/coordinate_format.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/application/route_extras.dart';
import 'package:lunaway/features/navigation/domain/route_stops.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';

/// Replaces the stops of the route to [target] with [next] and says so, with
/// the way back: every change of the stops can be undone. The preview is the
/// only place they change, so the way back is the list before.
void changeStops(BuildContext context, RouteTarget target, List<RouteStop> next, String message) =>
    changeStopsIn(
      ProviderScope.containerOf(context, listen: false),
      ScaffoldMessenger.maybeOf(context),
      context.t,
      target,
      next,
      message,
    );

/// [changeStops] once the widget that asked may be gone (a card closed
/// after the screen turned).
void changeStopsIn(
  ProviderContainer container,
  ScaffoldMessengerState? messenger,
  Translations t,
  RouteTarget target,
  List<RouteStop> next,
  String message,
) {
  final controller = container.read(routeStopsControllerProvider(target).notifier);
  final before = container.read(routeStopsControllerProvider(target));
  controller.set(next);
  showMessage(
    messenger,
    message,
    action: SnackBarAction(label: t.common.undo, onPressed: () => controller.set(before)),
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
        changeStops(context, target, [...stops]..removeAt(i), t.navigation.stops.removed);
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
            changeStops(context, target, next, t.navigation.stops.moved);
          },
          itemBuilder: (context, i) => Dismissible(
            key: ValueKey('stop-$i-${stops[i].hashCode}'),
            onDismissed: (_) => remove(i),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 52,
              // The list's own handles carry the grab cursor; this one,
              // drawn by the app, sets it as they do.
              leading: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: ReorderableDragStartListener(
                  index: i,
                  child: Tooltip(
                    message: t.navigation.stops.reorder,
                    child: const SizedBox.square(dimension: 48, child: Icon(AppIcons.reorder)),
                  ),
                ),
              ),
              title: Text(
                stops[i].label ?? t.navigation.stops.point,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // A bare point has no name: its coordinates tell two apart.
              subtitle: stops[i].label == null
                  ? Text(CoordinateFormat.decimal.format(stops[i].position))
                  : null,
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

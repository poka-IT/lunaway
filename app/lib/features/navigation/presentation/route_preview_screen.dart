import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/layout/window_size.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/locate_flow.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/widgets/avoid_chips.dart';
import 'package:lunaway/features/navigation/presentation/widgets/preview_parts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/route_option_card.dart';
import 'package:lunaway/features/navigation/presentation/widgets/warning_tile.dart';
import 'package:lunaway/features/places/presentation/directions.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/messages.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The route to a place or a point, before setting off: the route on the
/// map with its alternatives, its time and length, what it uses, the limits
/// to watch along it, the vehicle it was computed for (editable in place),
/// the options to avoid, the data's date and the disclaimer. On a phone,
/// "Démarrer" starts the guidance; on a desktop or the web the preview is
/// the whole of it.
class RoutePreviewScreen extends ConsumerStatefulWidget {
  const new({required this.target, super.key});

  /// Null when the link held no valid point.
  final RouteTarget? target;

  @override
  ConsumerState<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends ConsumerState<RoutePreviewScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The router writes its instructions in the app's language.
    final code = context.t.$meta.locale.languageCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(routeLanguageCodeProvider.notifier).set(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final target = widget.target;
    if (target == null) {
      return Scaffold(
        appBar: AppBar(),
        body: MessageView(
          title: t.navigation.states.refusedTitle,
          hint: t.navigation.states.refusedHint,
          mood: SceneMood.error,
        ),
      );
    }
    final size = WindowSize.of(context);
    final preview = ref.watch(routePreviewControllerProvider(target));
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final panel = _Panel(target: target, preview: preview, units: units);
    final action = _ActionBar(target: target, preview: preview.value);
    if (size == WindowSize.compact) {
      return Scaffold(
        body: LayoutBuilder(
          builder: (context, box) {
            const sheet = 0.48;
            final bottom = box.maxHeight * sheet;
            return Stack(
              children: [
                Positioned.fill(
                  child: _PreviewMap(
                    target: target,
                    preview: preview.value,
                    padding: EdgeInsets.only(
                      bottom: bottom,
                      top: MediaQuery.paddingOf(context).top,
                    ),
                  ),
                ),
                DraggableScrollableSheet(
                  initialChildSize: sheet,
                  minChildSize: 0.22,
                  maxChildSize: 0.94,
                  snap: true,
                  snapSizes: const [sheet],
                  builder: (context, scroll) => _SheetFrame(
                    child: CustomScrollView(
                      controller: scroll,
                      slivers: [
                        const SliverToBoxAdapter(child: _Handle()),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.huge),
                          sliver: panel,
                        ),
                      ],
                    ),
                  ),
                ),
                const Positioned(top: 0, left: 0, child: SafeArea(child: _BackButton())),
              ],
            );
          },
        ),
        bottomNavigationBar: action,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: size == WindowSize.expanded ? 440 : 380,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                right: false,
                child: Column(
                  children: [
                    const Align(alignment: Alignment.centerLeft, child: _BackButton()),
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
                            sliver: panel,
                          ),
                        ],
                      ),
                    ),
                    action,
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _PreviewMap(target: target, preview: preview.value, padding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(Space.s),
      child: IconButton.filledTonal(
        tooltip: context.t.navigation.preview.back,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLowest,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 48),
        ),
        onPressed: () => context.canPop() ? context.pop() : context.go('/map'),
        icon: const Icon(AppIcons.back),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 5,
      margin: const EdgeInsets.symmetric(vertical: Space.m),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(LunaTokens.radiusPill),
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
        boxShadow: LunaTokens.of(context).sheetShadow,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// The map of the preview: the routes, the limits along the chosen one,
/// the start and the destination.
class _PreviewMap extends ConsumerWidget {
  const new({required this.target, required this.preview, required this.padding});

  final RouteTarget target;
  final RoutePreview? preview;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(
      basemapStyleProvider(dark: dark, language: Localizations.localeOf(context).languageCode),
    );
    final p = preview;
    final plan = p?.plan;
    final selected = p?.route;
    final lines = [
      for (final r in plan?.routes ?? const <RouteOption>[])
        RouteMapLine(index: r.index, points: r.line, selected: r.index == p?.selected),
    ];
    final marks = [
      if (p?.origin != null) RouteMapMark(position: p!.origin!, kind: RouteMarkKind.origin),
      RouteMapMark(position: target.destination, kind: RouteMarkKind.destination),
      for (final w in selected?.warnings ?? const <RouteWarning>[])
        RouteMapMark(position: w.position, kind: RouteMarkKind.warning),
      for (final b in plan?.blockers ?? const <RouteWarning>[])
        RouteMapMark(position: b.position, kind: RouteMarkKind.blocker),
    ];
    final bounds =
        selected?.bounds ??
        GeoBounds.around([
          target.destination,
          ?p?.origin,
          for (final b in plan?.blockers ?? const <RouteWarning>[]) b.position,
        ]);
    return ref.watch(routeMapBuilderProvider)(
      context,
      RouteMapProps(
        style: style,
        dark: dark,
        lines: lines,
        marks: marks,
        camera: FitCamera(_atLeast(bounds!)),
        padding: padding,
        onLineTap: (i) => ref.read(routePreviewControllerProvider(target).notifier).select(i),
      ),
    );
  }

  /// A box around one point (the destination alone, before a route) is
  /// widened to a few streets, so the camera does not zoom to the maximum.
  static GeoBounds _atLeast(GeoBounds b) {
    const half = 0.004;
    if (b.north - b.south >= half && b.east - b.west >= half) return b;
    final c = b.center;
    return GeoBounds(
      south: c.lat - half,
      west: c.lon - half,
      north: c.lat + half,
      east: c.lon + half,
    );
  }
}

/// The panel's content, one sliver list, the same on a phone's sheet and in
/// a tablet's side panel.
class _Panel extends ConsumerWidget {
  const new({required this.target, required this.preview, required this.units});

  final RouteTarget target;
  final AsyncValue<RoutePreview> preview;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final label = target.label;
    final title = label == null
        ? t.navigation.preview.titlePoint
        : t.navigation.preview.titleTo(name: label);
    void retry() => ref.invalidate(routePreviewControllerProvider(target));
    final body = switch (preview) {
      AsyncData(:final value) => _body(context, ref, value),
      AsyncError(:final error) => [_Failure(error: error, onRetry: retry)],
      _ => [const _Computing()],
    };
    return SliverList.list(
      children: [
        Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
        const SizedBox(height: Space.m),
        ...body,
      ],
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, RoutePreview p) {
    final t = context.t;
    if (!p.vehicle.ready) {
      final missing = p.vehicle.missing;
      final out = p.vehicle.outOfBounds;
      return [
        _Prompt(
          title: t.navigation.states.vehicleTitle,
          body: [
            t.navigation.states.vehicleHint,
            if (missing.isNotEmpty && missing.length < 4)
              t.navigation.states.vehicleMissing(list: t.dimensionList(missing)),
            if (out.isNotEmpty) t.navigation.states.vehicleOutOfBounds(list: t.dimensionList(out)),
          ],
          action: t.navigation.states.describeVehicle,
          onAction: () => showVehicleEditor(context),
        ),
      ];
    }
    if (p.origin == null) {
      return [
        _Prompt(
          title: t.navigation.states.originTitle,
          body: [t.navigation.states.originHint],
          action: t.navigation.states.locate,
          onAction: () async {
            if (await ensureLocationAccess(context, ref)) {
              await ref.read(previewOriginProvider.notifier).refresh();
            }
          },
        ),
      ];
    }
    final plan = p.plan!;
    final avoid = AvoidSection(
      onChanged: (a) => ref.read(routeSettingsControllerProvider.notifier).setAvoid(a),
    );
    return switch (plan.status) {
      RouteStatus.ok => [
        _Routes(plan: plan, selected: p.selected, target: target, units: units),
        const SizedBox(height: Space.l),
        _Warnings(route: p.route, units: units, target: target),
        const SizedBox(height: Space.l),
        const VehicleLine(),
        const SizedBox(height: Space.m),
        avoid,
        if (p.route != null) ...[
          const SizedBox(height: Space.s),
          Roadbook(steps: p.route!.steps, units: units),
        ],
        const SizedBox(height: Space.l),
        RouteDataNote(graph: plan.graph),
      ],
      RouteStatus.noSafeRoute => [
        _NoSafeRoute(plan: plan, units: units),
        const SizedBox(height: Space.l),
        const VehicleLine(),
        const SizedBox(height: Space.m),
        avoid,
        const SizedBox(height: Space.l),
        RouteDataNote(graph: plan.graph),
      ],
      RouteStatus.noRoute || RouteStatus.offNetwork => [
        _Prompt(
          title: plan.status == RouteStatus.noRoute
              ? t.navigation.states.noRouteTitle
              : t.navigation.states.offNetworkTitle,
          body: [
            if (plan.status == RouteStatus.noRoute)
              t.navigation.states.noRouteHint
            else
              t.navigation.states.offNetworkHint,
            if (plan.applied.avoid.unpaved) t.navigation.states.allowUnpaved,
          ],
        ),
        const SizedBox(height: Space.m),
        avoid,
      ],
    };
  }
}

/// The avoid options, read and written in the route settings: a change
/// computes the route again.
class AvoidSection extends ConsumerWidget {
  const new({required this.onChanged, super.key});

  final ValueChanged<AvoidOptions> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avoid = ref.watch(routeSettingsControllerProvider).value?.avoid ?? const AvoidOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t.navigation.preview.avoid, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Space.s),
        AvoidChips(value: avoid, onChanged: onChanged),
      ],
    );
  }
}

class _Routes extends ConsumerWidget {
  const new({
    required this.plan,
    required this.selected,
    required this.target,
    required this.units,
  });

  final RoutePlan plan;
  final int selected;
  final RouteTarget target;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, r) in plan.routes.indexed) ...[
        if (i > 0) const SizedBox(height: Space.s),
        RouteOptionCard(
          route: r,
          ordinal: i,
          selected: r.index == selected,
          units: units,
          onTap: () => ref.read(routePreviewControllerProvider(target).notifier).select(r.index),
        ),
      ],
    ],
  );
}

class _Warnings extends StatelessWidget {
  const new({required this.route, required this.units, required this.target});

  final RouteOption? route;
  final DistanceUnits units;
  final RouteTarget target;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final warnings = route?.warnings ?? const <RouteWarning>[];
    if (warnings.isEmpty) {
      return Row(
        children: [
          Icon(AppIcons.checkCircle, color: theme.colorScheme.secondary),
          const SizedBox(width: Space.s),
          Expanded(child: Text(t.navigation.preview.noWarnings, style: theme.textTheme.bodyMedium)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.navigation.preview.warnings(n: warnings.length), style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        for (final w in warnings) WarningTile(warning: w, units: units),
      ],
    );
  }
}

/// No safe route: what stopped every route, the vehicle's figures, and
/// what the user can change.
class _NoSafeRoute extends StatelessWidget {
  const new({required this.plan, required this.units});

  final RoutePlan plan;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = plan.applied.vehicle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(AppIcons.error, color: scheme.error),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(t.navigation.states.noSafeTitle, style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(t.navigation.states.noSafeHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: Space.xs),
        for (final b in plan.blockers) WarningTile(warning: b, units: units),
        const SizedBox(height: Space.m),
        Text(t.navigation.states.whatToDo, style: theme.textTheme.titleMedium),
        const SizedBox(height: Space.xs),
        _Bullet(
          t.navigation.states.checkVehicle(
            height: t.metres(v.heightM),
            weight: t.tonnes(v.weightT),
          ),
        ),
        _Bullet(t.navigation.states.pickOtherPoint),
        if (plan.applied.avoid.unpaved) _Bullet(t.navigation.states.allowUnpaved),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Icon(AppIcons.chevron, size: 18, color: theme.colorScheme.secondary),
          ),
          const SizedBox(width: Space.s),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const new({required this.title, required this.body, this.action, this.onAction});

  final String title;
  final List<String> body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.xs),
        for (final line in body)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(line, style: theme.textTheme.bodyMedium),
          ),
        if (action != null && onAction != null) ...[
          const SizedBox(height: Space.s),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    );
  }
}

class _Computing extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.t.navigation.preview.computing, style: theme.textTheme.bodyLarge),
        const SizedBox(height: Space.m),
        const LinearProgressIndicator(),
        const SizedBox(height: Space.l),
        // The size of a route card, so nothing jumps when it arrives.
        const Skeleton(height: 104, radius: LunaTokens.radiusL),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const new({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final failure = error is RouteFailure ? error as RouteFailure : null;
    final (title, hint) = switch (failure?.kind) {
      RouteFailureKind.offline => (
        t.navigation.states.offlineTitle,
        t.navigation.states.offlineHint,
      ),
      RouteFailureKind.rateLimited => (
        t.navigation.states.rateLimitedTitle,
        t.navigation.states.rateLimitedHint(seconds: '${failure?.retryAfter?.inSeconds ?? 60}'),
      ),
      RouteFailureKind.refused => (
        t.navigation.states.refusedTitle,
        t.navigation.states.refusedHint,
      ),
      _ => (t.navigation.states.unavailableTitle, t.navigation.states.unavailableHint),
    };
    return MessageView(
      title: title,
      hint: hint,
      mood: failure?.kind == RouteFailureKind.offline ? SceneMood.offline : SceneMood.error,
      action: context.t.common.retry,
      onAction: onRetry,
      compact: true,
    );
  }
}

/// The foot of the preview: "Démarrer" where the device guides; elsewhere
/// the note that guidance starts from a phone, and the other apps.
class _ActionBar extends ConsumerWidget {
  const new({required this.target, required this.preview});

  final RouteTarget target;
  final RoutePreview? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final engine = ref.watch(guidanceEngineProvider).value;
    final plan = preview?.plan;
    final ready = plan != null && plan.status == RouteStatus.ok && plan.osrmJson != null;
    final others = TextButton(
      onPressed: () => openDirections(
        context,
        ref,
        target.destination,
        label: target.label,
        placeId: target.placeId,
        choose: true,
      ),
      child: Text(t.navigation.preview.otherApps),
    );
    return LiftsMessages(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (engine != null)
                  FilledButton.icon(
                    onPressed: ready ? () => _start(context, ref, plan) : null,
                    icon: const Icon(AppIcons.directions),
                    label: Text(t.navigation.preview.start),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                  )
                else
                  Text(
                    t.navigation.preview.phoneOnly,
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                others,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref, RoutePlan plan) async {
    final t = context.t;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.of(context);
    final settings = ref.read(routeSettingsControllerProvider).value ?? const NavigationSettings();
    if (settings.acceptedDisclaimer != plan.disclaimerKey) {
      final accepted = await showDisclaimer(context);
      if (!accepted || !context.mounted) return;
      await ref.read(routeSettingsControllerProvider.notifier).acceptDisclaimer(plan.disclaimerKey);
      if (!context.mounted) return;
    }
    if (!await ensureLocationAccess(context, ref) || !context.mounted) return;
    final started = await ref
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: preview!.selected,
          target: target,
          words: TranslatedWording(t, settings.units),
        );
    if (!started) {
      showMessage(messenger, t.navigation.guidance.unavailable);
      return;
    }
    unawaited(router.pushReplacement<void>(NavigationRoutes.guidance));
  }
}

/// The disclaimer before the first guidance; true once the user read it.
Future<bool> showDisclaimer(BuildContext context) async {
  final t = context.t;
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(AppIcons.inAppNavigation, size: 36, color: theme.colorScheme.secondary),
              const SizedBox(height: Space.m),
              Text(t.navigation.guidance.firstTitle, style: theme.textTheme.headlineSmall),
              const SizedBox(height: Space.s),
              Text(t.navigation.preview.disclaimer, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Space.xl),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.navigation.guidance.firstAccept),
              ),
            ],
          ),
        ),
      );
    },
  );
  return accepted ?? false;
}

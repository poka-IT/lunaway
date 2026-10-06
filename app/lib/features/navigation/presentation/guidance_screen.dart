import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/widgets/lanes_row.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/features/navigation/presentation/widgets/warning_tile.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/night_scene.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// The guidance, full screen: the next maneuver large at the top, with its
/// lanes; the restrictions coming up; a calm map that follows the vehicle
/// along its route; the arrival time, the time and distance left and the
/// speed at the bottom. Off the route, or when a road event closes it
/// ahead, a new route comes by itself and the banner says why.
class GuidanceScreen extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(guidanceControllerProvider);
    if (session == null) return const _NoGuidance();
    return PopScope(
      canPop: session.phase == GuidancePhase.arrived,
      onPopInvokedWithResult: (popped, _) async {
        if (!popped && await _confirmEnd(context) && context.mounted) _end(context, ref);
      },
      child: Scaffold(
        body: OrientationBuilder(
          builder: (context, orientation) => orientation == Orientation.landscape
              ? _Landscape(session: session)
              : _Portrait(session: session),
        ),
      ),
    );
  }
}

/// Ends the guidance and goes back to the map.
void _end(BuildContext context, WidgetRef ref) {
  ref.read(guidanceControllerProvider.notifier).stop();
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/map');
  }
}

Future<bool> _confirmEnd(BuildContext context) async {
  final t = context.t;
  final end = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.navigation.guidance.endTitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.navigation.guidance.endKeep),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.navigation.guidance.endConfirm),
        ),
      ],
    ),
  );
  return end ?? false;
}

class _NoGuidance extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: MessageView(title: context.t.navigation.guidance.unavailable, mood: SceneMood.error),
  );
}

class _Portrait extends StatelessWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context) {
    final arrived = session.phase == GuidancePhase.arrived;
    return Stack(
      children: [
        Positioned.fill(
          child: _GuidanceMap(
            session: session,
            padding: const EdgeInsets.only(top: 220, bottom: 140),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!arrived) _ManeuverBanner(session: session),
                  _Notices(session: session),
                ],
              ),
            ),
          ),
        ),
        if (!arrived)
          Positioned(
            right: Space.s,
            bottom: 150,
            child: _MapButtons(session: session),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: arrived ? _ArrivalCard(session: session) : _BottomBar(session: session),
        ),
      ],
    );
  }
}

class _Landscape extends StatelessWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context) {
    final arrived = session.phase == GuidancePhase.arrived;
    return Row(
      children: [
        SizedBox(
          width: 380,
          child: SafeArea(
            right: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!arrived) _ManeuverBanner(session: session),
                  Expanded(
                    child: SingleChildScrollView(child: _Notices(session: session)),
                  ),
                  if (arrived) _ArrivalCard(session: session) else _BottomBar(session: session),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _GuidanceMap(session: session, padding: EdgeInsets.zero),
              ),
              if (!arrived)
                Positioned(
                  right: Space.s,
                  bottom: Space.l,
                  child: _MapButtons(session: session),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The map: the route ahead, its restrictions, the vehicle; turned with
/// the road and tilted, or the whole route in the overview.
class _GuidanceMap extends ConsumerWidget {
  const new({required this.session, required this.padding});

  final GuidanceSession session;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = ref.watch(
      basemapStyleProvider(dark: dark, language: Localizations.localeOf(context).languageCode),
    );
    final route = session.route;
    final snap = session.snapshot;
    final vehicle = snap == null
        ? null
        : VehiclePuck(
            position: snap.offRoute ? session.lastFix!.position : snap.position,
            course: snap.courseDeg ?? session.lastFix?.courseDeg,
          );
    final whole =
        route.bounds ?? GeoBounds.around([session.target.destination, ?session.lastFix?.position])!;
    final camera = session.overview || vehicle == null
        ? FitCamera(whole)
        : FollowCamera(position: vehicle.position, course: vehicle.course);
    return ref.watch(routeMapBuilderProvider)(
      context,
      RouteMapProps(
        style: style,
        dark: dark,
        lines: [RouteMapLine(index: route.index, points: route.line, selected: true)],
        marks: [
          RouteMapMark(position: session.target.destination, kind: RouteMarkKind.destination),
          for (final w in route.warnings)
            RouteMapMark(position: w.position, kind: RouteMarkKind.warning),
          for (final e in session.eventAlerts)
            RouteMapMark(position: e.hit.at, kind: RouteMarkKind.event),
        ],
        vehicle: vehicle,
        camera: camera,
        padding: padding,
      ),
    );
  }
}

/// The colours of the guidance's banner and bar: the brand's navy by day
/// (the dock's), a deep navy at night where a cream panel would glare.
({Color surface, Color text}) _panelColors(BuildContext context) {
  final tokens = LunaTokens.of(context);
  final scheme = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.light
      ? (surface: tokens.dockSurface, text: tokens.dockForeground)
      : (surface: tokens.floatingSurface, text: scheme.onSurface);
}

/// The next maneuver: its arrow, the distance to it, the road to take, the
/// lanes, and the one after when it follows closely.
class _ManeuverBanner extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final colors = _panelColors(context);
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final snap = session.snapshot;
    final banner = snap?.banner;
    final steps = session.route.steps;
    final index = snap?.stepIndex ?? 0;
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final after = index + 2 < steps.length ? steps[index + 2] : null;
    final type = banner?.maneuverType ?? next?.maneuverType;
    final modifier = banner?.modifier ?? next?.modifier;
    final lanes = banner?.lanes.isNotEmpty ?? false
        ? banner!.lanes
        : session.step?.lanes ?? const [];
    final road = banner?.primary ?? next?.roadName ?? next?.instruction ?? '';
    final distance = snap == null ? null : t.routeDistance(snap.distanceToManeuverM, units);
    final thenClose = after != null && next != null && next.distanceM < 150;
    // Off the route, the maneuver is that of a road the vehicle left: it
    // fades until the new route replaces it, the notice below says why.
    final stale =
        session.phase == GuidancePhase.offRoute || session.phase == GuidancePhase.rerouting;
    return Semantics(
      liveRegion: true,
      label: [?distance, road].join(', '),
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
        elevation: 4,
        child: AnimatedOpacity(
          opacity: stale ? 0.4 : 1,
          duration: Motion.of(context, Motion.medium),
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ManeuverIcon(
                      type: type,
                      modifier: modifier,
                      roundaboutExitDegrees: banner?.roundaboutExitDegrees,
                      size: 76,
                      color: colors.text,
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (distance != null)
                            Text(
                              distance,
                              style: theme.textTheme.displaySmall?.copyWith(color: colors.text),
                            ),
                          Text(
                            road,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(color: colors.text),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (lanes.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Center(
                    child: LanesRow(lanes: lanes, color: colors.text),
                  ),
                ],
                if (thenClose) ...[
                  const SizedBox(height: Space.s),
                  Row(
                    children: [
                      Text(
                        t.navigation.guidance.then,
                        style: theme.textTheme.titleSmall?.copyWith(color: colors.text),
                      ),
                      const SizedBox(width: Space.s),
                      ManeuverIcon(
                        type: after.maneuverType,
                        modifier: after.modifier,
                        size: 28,
                        color: colors.text,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the driver should know besides the next maneuver: a new route and
/// why, a closure ahead, off the route, the restriction coming up, the
/// voice that is missing.
class _Notices extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final alert = session.alert;
    final notices = <Widget>[
      if (session.positionLost)
        _Notice(icon: AppIcons.error, text: t.navigation.guidance.positionLost, strong: true),
      if (alert != null)
        _Notice(
          icon: switch (alert) {
            ReroutedAlert() => AppIcons.sync,
            _ => AppIcons.error,
          },
          text: switch (alert) {
            ReroutedAlert(:final extra) =>
              extra != null && extra.inMinutes >= 1
                  ? t.navigation.guidance.reroutedLonger(minutes: '${extra.inMinutes}')
                  : t.navigation.guidance.rerouted,
            ClosureAheadAlert(:final finding) => t.navigation.guidance.closureAhead(
              distance: t.routeDistance(finding.aheadM, units),
            ),
            NoDetourAlert(:final finding) => t.navigation.guidance.noDetour(
              distance: t.routeDistance(finding.aheadM, units),
            ),
            RerouteFailedAlert(:final failure) =>
              failure?.kind == RouteFailureKind.offline
                  ? t.navigation.guidance.rerouteOffline
                  : t.navigation.guidance.rerouteFailed,
          },
          strong: alert is! ReroutedAlert,
        )
      else if (session.phase == GuidancePhase.rerouting)
        _Notice(icon: AppIcons.sync, text: t.navigation.guidance.rerouting)
      else if (session.phase == GuidancePhase.offRoute)
        _Notice(icon: AppIcons.error, text: t.navigation.guidance.offRoute, strong: true),
      if (session.ahead.isNotEmpty) _WarningAhead(ahead: session.ahead.first, units: units),
      for (final e in session.eventAlerts.take(1))
        _Notice(
          icon: AppIcons.error,
          text: [
            t.navigation.guidance.eventAhead(distance: t.routeDistance(e.aheadM, units)),
            if (session.eventsAsOf != null)
              t.navigation.guidance.eventsAsOf(time: t.clockTime(session.eventsAsOf!.toLocal())),
          ].join('\n'),
        ),
      if (session.voiceOn && session.voice != VoiceReadiness.ready) _VoiceNotice(session: session),
    ];
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notices)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: n,
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const new({required this.icon, required this.text, this.strong = false, this.action});

  final IconData icon;
  final String text;
  final bool strong;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = strong ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = strong ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
          child: Row(
            children: [
              Icon(icon, color: fg),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
              ),
              ?action,
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningAhead extends StatelessWidget {
  const new({required this.ahead, required this.units});

  final WarningAhead ahead;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(LunaTokens.radiusL),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xxs),
        child: WarningTile(warning: ahead.warning, units: units, aheadM: ahead.aheadM),
      ),
    );
  }
}

class _VoiceNotice extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final language = session.plan.applied.language == RouteLanguage.fr
        ? t.languages.fr
        : t.languages.en;
    final missing = session.voice == VoiceReadiness.missingData;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return _Notice(
      icon: AppIcons.offline,
      text: [
        if (missing)
          t.navigation.guidance.missingVoice(language: language)
        else
          t.navigation.guidance.noVoice(language: language),
        if (ios) t.navigation.guidance.voiceSettingsIos,
      ].join(' '),
      action: missing && !ios
          ? TextButton(
              onPressed: () => ref.read(guidanceControllerProvider.notifier).installVoices(),
              child: Text(t.navigation.guidance.installVoice),
            )
          : null,
    );
  }
}

class _MapButtons extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(guidanceControllerProvider.notifier);
    final style = IconButton.styleFrom(
      backgroundColor: scheme.surfaceContainerLowest,
      foregroundColor: scheme.onSurface,
      minimumSize: const Size(56, 56),
      elevation: 3,
    );
    return Column(
      children: [
        IconButton(
          tooltip: session.voiceOn ? t.navigation.guidance.voiceOff : t.navigation.guidance.voiceOn,
          style: style,
          onPressed: () => controller.setVoice(on: !session.voiceOn),
          icon: Icon(session.voiceOn ? AppIcons.voiceOn : AppIcons.voiceOff),
        ),
        const SizedBox(height: Space.s),
        IconButton(
          tooltip: session.overview
              ? t.navigation.guidance.recenter
              : t.navigation.guidance.overview,
          style: style,
          onPressed: () => controller.setOverview(on: !session.overview),
          icon: Icon(session.overview ? AppIcons.locateActive : AppIcons.map),
        ),
      ],
    );
  }
}

/// The arrival time, the time and distance left, the speed and its limit,
/// and the way out.
class _BottomBar extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final colors = _panelColors(context);
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final now = ref.watch(clockProvider)();
    final snap = session.snapshot;
    final left = snap?.durationRemainingS ?? session.route.durationS;
    final eta = (session.lastFix?.at ?? now).add(Duration(seconds: left.round())).toLocal();
    final remaining = snap?.distanceRemainingM ?? session.route.distanceM;
    final speed = session.lastFix?.speedMps;
    return Material(
      color: colors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusXl)),
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
          child: Row(
            children: [
              _Speed(
                speedMps: speed,
                limitKmh: snap?.speedLimitKmh,
                units: units,
                color: colors.text,
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Semantics(
                  container: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.navigation.guidance.arrival(time: t.clockTime(eta)),
                        style: theme.textTheme.headlineSmall?.copyWith(color: colors.text),
                      ),
                      Text(
                        '${t.routeDuration(left)} · ${t.routeDistance(remaining, units)}',
                        style: theme.textTheme.titleMedium?.copyWith(color: colors.text),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: t.navigation.guidance.end,
                iconSize: 28,
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  foregroundColor: colors.text,
                ),
                onPressed: () async {
                  if (await _confirmEnd(context) && context.mounted) _end(context, ref);
                },
                icon: const Icon(AppIcons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The speed, and the limit beside it in a road sign's red ring when the
/// map knows it.
class _Speed extends StatelessWidget {
  const new({
    required this.speedMps,
    required this.limitKmh,
    required this.units,
    required this.color,
  });

  final double? speedMps;
  final double? limitKmh;
  final DistanceUnits units;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metric = units == DistanceUnits.metric;
    final factor = metric ? 3.6 : 2.236936;
    final speed = speedMps == null ? null : (speedMps! * factor).round();
    final limit = limitKmh == null ? null : (metric ? limitKmh! : limitKmh! / 1.609344).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${t.navigation.guidance.speed} ${speed ?? ''}',
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                speed == null ? '' : '$speed',
                style: theme.textTheme.headlineMedium?.copyWith(color: color),
              ),
              Text(
                metric ? t.navigation.units.kmh : t.navigation.units.mph,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
        if (limit != null) ...[
          const SizedBox(width: Space.s),
          Semantics(
            label: '${t.navigation.guidance.limit} $limit',
            excludeSemantics: true,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.error, width: 5),
              ),
              child: Text(
                '$limit',
                style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The arrival: the place reached, what the app may ask about it (when a
/// contribution flow registered), and the way back to the map.
class _ArrivalCard extends ConsumerWidget {
  const new({required this.session});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final confirmation = ref.watch(arrivalConfirmationProvider);
    final placeId = session.target.placeId;
    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(LunaTokens.radiusSheet)),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ManeuverIcon(type: 'arrive', modifier: null, size: 44, color: scheme.secondary),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            t.navigation.guidance.arrivedTitle,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        if (session.target.label != null)
                          Text(session.target.label!, style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
              if (confirmation != null && placeId != null) ...[
                OutlinedButton(
                  onPressed: () => unawaited(confirmation.confirm(placeId)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                  child: Text(confirmation.label(t.$meta.locale.languageCode)),
                ),
                const SizedBox(height: Space.s),
              ],
              FilledButton(
                onPressed: () => _end(context, ref),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                child: Text(t.navigation.guidance.done),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

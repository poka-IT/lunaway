import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/lanes_row.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/motion.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The next maneuver at the top of the guidance, laid out as drivers know
/// it from the big navigation apps: its arrow on the left; the distance to
/// it over the road to take, the exit's number on a motorway; the lanes on
/// a deeper band under it when the map has them; the maneuver after it on
/// a "Puis" tab when it follows closely.
class ManeuverPanel extends ConsumerWidget {
  const new({required this.session, super.key});

  final GuidanceSession session;

  /// The maneuver after the next shows on the "Puis" tab when it comes
  /// this soon after it, metres: two turns a street apart are read as one.
  static const thenWithinM = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final tokens = LunaTokens.of(context);
    final text = tokens.onGuidanceBanner;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    final snap = session.snapshot;
    final banner = snap?.banner;
    final steps = session.route.steps;
    final index = snap?.stepIndex ?? 0;
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final after = index + 2 < steps.length ? steps[index + 2] : null;
    final maneuver = bannerManeuver(banner: banner, steps: steps, stepIndex: index);
    final lanes = banner?.lanes.isNotEmpty ?? false
        ? banner!.lanes
        : session.step?.lanes ?? const <LaneHint>[];
    final road = banner?.primary ?? next?.roadName ?? next?.instruction ?? '';
    final distance = snap == null ? null : t.routeDistance(snap.distanceToManeuverM, units);
    final exit = next?.exitRef;
    final thenClose = after != null && next != null && next.distanceM < thenWithinM;
    // Off the route, the maneuver is that of a road the vehicle left: it
    // fades until the new route replaces it, the notice below says why.
    final stale =
        session.phase == GuidancePhase.offRoute || session.phase == GuidancePhase.rerouting;
    const radius = Radius.circular(LunaTokens.radiusL);
    return Semantics(
      liveRegion: true,
      // The arrow is a picture: the instruction says the turn in words.
      label: [?distance, next?.instruction ?? road].join(', '),
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: stale ? 0.4 : 1,
        duration: Motion.of(context, Motion.medium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: tokens.guidanceBanner,
              borderRadius: BorderRadius.only(
                topLeft: radius,
                topRight: radius,
                bottomRight: radius,
                // The "Puis" tab hangs from this corner.
                bottomLeft: thenClose ? Radius.zero : radius,
              ),
              clipBehavior: Clip.antiAlias,
              elevation: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.l, Space.m),
                    child: Row(
                      children: [
                        ManeuverIcon(maneuver: maneuver, size: 68, color: text),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (distance != null || exit != null)
                                Wrap(
                                  spacing: Space.s,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (distance != null)
                                      Text(
                                        distance,
                                        style: theme.textTheme.headlineMedium?.copyWith(
                                          color: text,
                                        ),
                                      ),
                                    if (exit != null)
                                      ExitBadge(label: t.navigation.guidance.exit(ref: exit)),
                                  ],
                                ),
                              Text(
                                road,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (lanes.isNotEmpty)
                    ColoredBox(
                      color: tokens.guidanceBannerDeep,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.s),
                        child: Center(
                          child: LanesRow(
                            lanes: lanes,
                            color: text,
                            size: 34,
                            leftHandTraffic: maneuver.leftHandTraffic,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (thenClose)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Material(
                  color: tokens.guidanceBannerDeep,
                  borderRadius: const BorderRadius.vertical(bottom: radius),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.navigation.guidance.then,
                          style: theme.textTheme.titleLarge?.copyWith(color: text),
                        ),
                        const SizedBox(width: Space.s),
                        ManeuverIcon(maneuver: after.maneuver, size: 32, color: text),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A motorway exit's number as its sign shows it: light on the banner's
/// deep colour, as the white plate of an exit stands out of a blue or
/// green sign.
class ExitBadge extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = LunaTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.onGuidanceBanner,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.hair),
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: tokens.guidanceBanner, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// The road the vehicle is on, on a pill under it at the foot of the map:
/// a motorway's number, another road's name, else its number; nothing on
/// a road with neither, or off the route.
class RoadNamePill extends StatelessWidget {
  const new({required this.session, super.key});

  final GuidanceSession session;

  /// The name shown for [session]; null when none.
  static String? roadOf(GuidanceSession session) {
    final snap = session.snapshot;
    if (snap == null || snap.offRoute) return null;
    final step = session.step;
    if (step == null) return null;
    // A motorway by its number, as its signs give it ("A 41; E 712": the
    // first).
    final ref = step.roadRef?.split(';').first.trim();
    if (step.motorway && ref != null && ref.isNotEmpty) return ref;
    return step.roadName ?? ref;
  }

  @override
  Widget build(BuildContext context) {
    final road = roadOf(session);
    if (road == null) return const SizedBox.shrink();
    final tokens = LunaTokens.of(context);
    return Semantics(
      label: context.t.navigation.guidance.currentRoad(road: road),
      excludeSemantics: true,
      child: Material(
        color: tokens.floatingSurface,
        shape: const StadiumBorder(),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
          child: Text(
            road,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: tokens.guidanceTime, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

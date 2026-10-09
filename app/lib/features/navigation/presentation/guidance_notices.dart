/// The guidance's notices, by the app's rule (`shared/notices.dart`).
///
/// Passing, from the guidance's alerts and its phase ([alertNotice],
/// [searchingNotice], [avoidedNotice]) and from every message of the app
/// while the guidance is up: a new route and why, a closure met, a stop
/// added or removed, a report sent. Standing, while their state holds
/// ([GuidanceNotices]): the route left, the position lost or old, a danger
/// zone, a restriction or a road event ahead, a community report just
/// passed, the voice missing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/route_service.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/road_reports.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/road_report_sheet.dart';
import 'package:lunaway/features/navigation/presentation/widgets/enforcement_notice.dart';
import 'package:lunaway/features/navigation/presentation/widgets/warning_tile.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/notice_views.dart';

/// The passing notice of [alert]. Its id stays the same when the guidance
/// adds the stops it moved under it: the notice is told again with them.
PassingNotice alertNotice(Translations t, DistanceUnits units, GuidanceAlert alert) {
  final text = [
    switch (alert) {
      // Rounded as the voice rounds them: 90 seconds are 2 minutes.
      ReroutedAlert(:final extra) => switch (extra == null ? 0 : (extra.inSeconds / 60).round()) {
        final minutes when minutes >= 1 => t.navigation.guidance.reroutedLonger(
          minutes: '$minutes',
        ),
        _ => t.navigation.guidance.rerouted,
      },
      ClosureAheadAlert(:final finding) => t.navigation.guidance.closureAhead(
        distance: t.routeDistance(finding.aheadM, units),
      ),
      NoDetourAlert(:final finding) => t.navigation.guidance.noDetour(
        distance: t.routeDistance(finding.aheadM, units),
      ),
      RerouteFailedAlert(:final failure, :final cause?) =>
        failure?.kind == RouteFailureKind.offline
            ? t.navigation.guidance.closureOffline(distance: t.routeDistance(cause.aheadM, units))
            : t.navigation.guidance.closureFailed(distance: t.routeDistance(cause.aheadM, units)),
      RerouteFailedAlert(:final failure) =>
        failure?.kind == RouteFailureKind.offline
            ? t.navigation.guidance.rerouteOffline
            : t.navigation.guidance.rerouteFailed,
    },
    // The stops the route in use moved, under whichever message tells of it.
    for (final m in alert.moved) t.movedStop(m, lastStop: alert.lastStop, units: units),
  ].join('\n');
  return PassingNotice(
    id: ('alert', alert.runtimeType, alert.until),
    text: text,
    icon: alert is ReroutedAlert ? AppIcons.sync : AppIcons.error,
    strong: alert is! ReroutedAlert,
    priority: switch (alert) {
      // What the road ahead holds, and the way round it.
      ReroutedAlert(reason: RerouteReason.roadEvent) ||
      ClosureAheadAlert() ||
      NoDetourAlert() ||
      RerouteFailedAlert(cause: _?) => NoticePriority.urgent,
      // After the user's own change, the notice of that change says it;
      // a stop moved by the new route is news all the same.
      ReroutedAlert(reason: RerouteReason.stops || RerouteReason.destination, :final moved)
          when moved.isEmpty =>
        NoticePriority.quiet,
      _ => NoticePriority.normal,
    },
    about: switch (alert) {
      ClosureAheadAlert(:final finding) || NoDetourAlert(:final finding) => finding.event.id,
      RerouteFailedAlert(:final cause?) => cause.event.id,
      _ => null,
    },
  );
}

/// The id of [searchingNotice], to take it back once the search is over.
const searchingNoticeId = 'searching a new route';

/// "Recherche d'un nouvel itinéraire": the least of the notices, its
/// outcome follows.
PassingNotice searchingNotice(Translations t) => PassingNotice(
  id: searchingNoticeId,
  text: t.navigation.guidance.rerouting,
  icon: AppIcons.sync,
  priority: NoticePriority.quiet,
);

/// The closures [plan] goes round, with their sources; null when none.
PassingNotice? avoidedNotice(Translations t, RoutePlan plan, DateTime now) {
  final avoided = plan.avoidedRoadEvents;
  if (avoided.isEmpty) return null;
  return PassingNotice(
    id: ('avoided', identityHashCode(plan)),
    icon: AppIcons.roadEvent(RoadEventClass.closure),
    priority: NoticePriority.quiet,
    text: [
      t.navigation.guidance.avoidedClosures(n: avoided.length),
      for (final id in {for (final e in avoided) e.source})
        eventSource(t, plan.sourceOf(id), id, now),
    ].join('\n'),
  );
}

/// Where a road event comes from and how recent its data is: the source's
/// credit line (shorter than its full name), else its name, else its id, so
/// the origin always shows; the day as well when the data is not of today.
/// Every road event notice and the route preview name a source this way.
String eventSource(Translations t, RoadEventSourceStatus? source, String id, DateTime now) =>
    t.roadDataSource(
      source?.attribution ?? source?.name ?? id,
      source?.dataAt ?? source?.lastReadAt,
      now,
    );

/// How far past a community report the guidance asks about it, metres:
/// once the road was seen, while it is still in mind.
const _askPassedWithinM = 600.0;

/// The community report of the route just passed, within
/// [_askPassedWithinM] behind the vehicle: only someone who has seen the
/// road answers whether it is still there, and the answers move other
/// people's routes. The route's own events only: one that appeared during
/// the guidance has no place along this route to be passed.
RouteRoadEvent? passedCommunityReport(RouteOption route, double along) =>
    route.roadEvents.where((e) {
      final behind = along - (e.distanceFromStartM + e.lengthM);
      return e.event.source == communityRoadSource && behind >= 0 && behind <= _askPassedWithinM;
    }).lastOrNull;

/// How near something ahead is, as a level of its notice: 1 beyond the
/// first call of the voice, then one more at each ([warningCallsM]). A
/// notice folded far away opens again when the voice next speaks of it.
int _nearness(double aheadM) => 1 + warningCallsM.where((d) => aheadM <= d).length;

/// The standing notices of the guidance, under the maneuver, with the
/// passing notice under them ([NoticeColumn]).
class GuidanceNotices extends ConsumerWidget {
  const new({required this.session, super.key});

  final GuidanceSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final units = ref.watch(routeSettingsControllerProvider).value?.units ?? DistanceUnits.metric;
    // The road event a passing notice speaks of is not repeated below it.
    final told = NoticeScope.of(context).current?.about;
    final now = ref.watch(clockProvider)().toLocal();
    // Turns over each minute: how old the last position is.
    final wall = ref.watch(minuteClockProvider).value ?? ref.read(clockProvider)();
    final along = session.snapshot?.distanceAlongM ?? 0;
    // The page's context: an answer outlives a turn of the phone that
    // builds this notice again in the other layout.
    final page = Navigator.of(context, rootNavigator: true).context;
    final standing = <StandingNotice>[
      if (ref.watch(demoDriveProvider))
        StandingNotice(
          id: 'demo',
          icon: AppIcons.inAppNavigation,
          text: t.navigation.guidance.demoDrive,
        ),
      if (session.aids.alert case final aid?)
        StandingNotice(
          id: ('aid', aid.id),
          icon: aid.kind == EnforcementKind.camera ? AppIcons.camera : AppIcons.warning,
          text: enforcementText(t, aid, units),
          strong: true,
          // In the zone is graver than ahead of it.
          level: aid.inside ? 2 : 1,
          look: EnforcementNotice(alert: aid, units: units),
        ),
      if (session.positionLost)
        StandingNotice(
          id: 'position',
          icon: AppIcons.error,
          text: t.navigation.guidance.positionLost,
          strong: true,
          level: 2,
        )
      // Arrived, the position is no longer asked for: its age says nothing.
      else if (session.phase != GuidancePhase.arrived &&
          session.lastFixAt != null &&
          wall.difference(session.lastFixAt!) >= positionStaleAfter)
        StandingNotice(
          id: 'position',
          icon: AppIcons.error,
          text: t.navigation.guidance.positionStale(
            minutes: '${wall.difference(session.lastFixAt!).inMinutes}',
          ),
        ),
      if (session.phase == GuidancePhase.offRoute)
        StandingNotice(
          id: 'off route',
          icon: AppIcons.error,
          text: t.navigation.guidance.offRoute,
          strong: true,
        ),
      if (session.ahead.firstOrNull case final ahead?)
        StandingNotice(
          id: ('warning', ahead.warning.externalId, ahead.warning.distanceFromStartM),
          icon: warningIcon(ahead.warning.kind),
          text: t.warningTitle(ahead.warning),
          strong: ahead.warning.severity == WarningSeverity.blocking,
          level: _nearness(ahead.aheadM),
          look: _WarningAhead(ahead: ahead, units: units),
        ),
      for (final e in session.eventAlerts.where((e) => e.event.id != told).take(1))
        StandingNotice(
          id: ('event', e.event.id),
          icon: AppIcons.error,
          strong: e.event.eventClass == RoadEventClass.closure,
          level: _nearness(e.aheadM),
          text: [
            switch (e.event.eventClass) {
              RoadEventClass.closure => t.navigation.guidance.eventClosure(
                distance: t.routeDistance(e.aheadM, units),
              ),
              RoadEventClass.vehicleLimit => t.navigation.guidance.eventLimit(
                distance: t.routeDistance(e.aheadM, units),
              ),
              _ => t.navigation.guidance.eventAhead(distance: t.routeDistance(e.aheadM, units)),
            },
            eventSource(t, e.source, e.event.source, now),
          ].join('\n'),
        ),
      // The road events of the route itself (lanes closed ahead), each with
      // its source and the age of its data.
      for (final ahead in roadEventsAhead(
        session.route,
        along,
      ).where((a) => !session.eventAlerts.any((e) => e.event.id == a.event.event.id)).take(1))
        StandingNotice(
          id: ('road event', ahead.event.event.id),
          icon: AppIcons.roadEvent(ahead.event.event.eventClass),
          level: _nearness(ahead.aheadM),
          text: [
            t.navigation.guidance.roadEventAhead(
              what: [
                ?ahead.event.event.road,
                t.roadEventWhat(ahead.event.event.eventClass),
              ].join(' · '),
              distance: t.routeDistance(ahead.aheadM, units),
            ),
            if (session.plan.sourceOf(ahead.event.event.source) case final source)
              t.roadDataSource(
                source?.attribution ?? source?.name ?? ahead.event.event.source,
                ahead.event.dataAt ?? source?.dataAt ?? source?.lastReadAt,
                now,
              ),
          ].join('\n'),
        ),
      // A community report just passed: still there, or over?
      if (passedCommunityReport(session.route, along) case final passed?)
        StandingNotice(
          id: ('passed', passed.event.id),
          icon: AppIcons.roadEvent(passed.event.eventClass),
          text: t.roadReport.passed(
            what: [?passed.event.road, t.roadEventWhat(passed.event.eventClass)].join(' · '),
          ),
          below: CommunityReportActions(
            onStillThere: () =>
                unawaited(confirmRoadReport(page, passed.event, at: passed.position)),
            onOver: () => unawaited(clearRoadReport(page, passed.event)),
          ),
        ),
      if (session.voiceOn && session.voice != VoiceReadiness.ready && !session.voiceNoticeClosed)
        _voiceNotice(context, ref),
    ];
    return NoticeColumn(standing: standing);
  }

  /// The voice missing for the language: said once, then closed for the
  /// trip by its cross, or folded as any other.
  StandingNotice _voiceNotice(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final language = t.languageName(session.plan.applied.language.name);
    final missing = session.voice == VoiceReadiness.missingData;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return StandingNotice(
      id: 'voice',
      icon: AppIcons.offline,
      text: [
        if (missing)
          t.navigation.guidance.missingVoice(language: language)
        else
          t.navigation.guidance.noVoice(language: language),
        if (ios) t.navigation.guidance.voiceSettingsIos,
      ].join(' '),
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (missing && !ios)
            TextButton(
              onPressed: () => ref.read(guidanceControllerProvider.notifier).installVoices(),
              child: Text(t.navigation.guidance.installVoice),
            ),
          IconButton(
            tooltip: t.common.close,
            onPressed: () => ref.read(guidanceControllerProvider.notifier).closeVoiceNotice(),
            icon: const Icon(AppIcons.close),
          ),
        ],
      ),
    );
  }
}

/// A restriction ahead, as its tile shows it in the preview.
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

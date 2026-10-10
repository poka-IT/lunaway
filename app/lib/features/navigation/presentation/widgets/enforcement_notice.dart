import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/notices.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/first_that_fits.dart';

/// What [alert] says, in one sentence: the notice's words for a screen
/// reader and its folded chip ("Radar fixe dans 800 m, limite 90 km/h,
/// au-dessus de la limite.", "Zone de danger, encore 1,2 km.").
String enforcementText(Translations t, EnforcementAlert alert, DistanceUnits units) {
  final inside = alert.within;
  final what = t.alertKind(alert);
  final limit = alert.limitKmh;
  final speed = limit == null ? null : t.speedLimit(limit, units);
  final average = alert.averageKmh;
  final parts = [
    if (alert.atHand)
      what
    else if (inside) ...[
      what,
      t.navigation.enforcement.remaining(distance: t.routeDistance(alert.remainingM, units)),
    ] else
      t.navigation.enforcement.ahead(what: what, distance: t.routeDistance(alert.aheadM, units)),
    if (speed != null && alert.isSection && alert.cameraLimit)
      t.navigation.enforcement.averageLimit(limit: speed)
    else if (speed != null)
      t.navigation.enforcement.limit(limit: speed),
    if (average != null && inside)
      t.navigation.enforcement.yourAverage(speed: t.speedLimit(average.round(), units)),
    if (alert.over) t.navigation.guidance.overLimit,
  ];
  return '${parts.join(', ')}.';
}

/// How grave [alert] is, as the level of its standing notice: ahead, then
/// inside, then over its limit. A notice folded opens again, and a screen
/// reader hears it again, when it grows graver; a figure that changes
/// within a level is not told again.
int enforcementLevel(EnforcementAlert alert) => alert.over
    ? 3
    : alert.within
    ? 2
    : 1;

/// The id of [alertExitNotice] for [exit], to take it back when another
/// alert takes the screen before its time is over.
Object alertExitNoticeId(AlertExit exit) => ('aid exit', exit.id);

/// The end of a zone or a section just left, as a passing notice: calm,
/// never said aloud.
PassingNotice alertExitNotice(Translations t, AlertExit exit) => PassingNotice(
  id: alertExitNoticeId(exit),
  text: exit.section ? t.navigation.enforcement.sectionEnd : t.navigation.enforcement.zoneEnd,
  icon: AppIcons.check,
  priority: NoticePriority.quiet,
);

/// The rule of the country just entered, as a passing notice: "Suisse :
/// pas d'alerte radar".
PassingNotice ruleChangeNotice(Translations t, RuleChange change) => PassingNotice(
  id: ('aid rule', change.country, change.mode),
  text: t.ruleChange(change),
  icon: AppIcons.about,
);

/// The look of the standing notice of a camera, a section or a danger zone
/// coming or around the vehicle: its pictogram, its kind, the distance in
/// large, the limit's sign, the lists under them. Over the limit, the error
/// colours and the words say so. A danger zone shows a warning sign, never
/// a camera. Its words join the notice's node ([enforcementText]), which a
/// screen reader hears once per level, not at each new distance.
class EnforcementNotice extends StatelessWidget {
  const new({required this.alert, required this.units, required this.now, super.key});

  final EnforcementAlert alert;
  final DistanceUnits units;

  /// The app's time, for the year of a list's date.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final camera = alert.kind == EnforcementKind.camera;
    final inside = alert.within;
    final background = alert.over ? scheme.error : scheme.errorContainer;
    final ink = alert.over ? scheme.onError : scheme.onErrorContainer;
    final limit = alert.limitKmh;
    final average = alert.averageKmh;
    // Nearer than [atHandM], no figure: the kind above says it all.
    final distance = alert.atHand
        ? null
        : inside
        ? t.navigation.enforcement.remaining(distance: t.routeDistance(alert.remainingM, units))
        : t.routeDistance(alert.aheadM, units);
    return Semantics(
      label: enforcementText(t, alert, units),
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Space.xxs),
                child: camera
                    ? const RouteBadgeView(RouteBadge.camera, scale: 1.3)
                    : const _DangerSign(),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.alertKind(alert),
                      style: theme.textTheme.titleSmall?.copyWith(color: ink),
                    ),
                    // The sign beside the distance while there is room,
                    // under it on a narrow banner with large text.
                    Wrap(
                      spacing: Space.m,
                      runSpacing: Space.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (distance != null)
                          Text(
                            distance,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (limit != null)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (alert.isSection && alert.cameraLimit)
                                Text(
                                  t.navigation.enforcement.averageLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(color: ink),
                                ),
                              LimitSign(
                                value: t.speedIn(limit, units),
                                estimated: alert.limitEstimated,
                                size: 52,
                                outline: alert.over ? ink : null,
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (average != null && inside)
                      Text(
                        t.navigation.enforcement.yourAverage(
                          speed: t.speedLimit(average.round(), units),
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(color: ink),
                      ),
                    if (alert.over)
                      Text(
                        t.navigation.guidance.overLimit,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (alert.sources.isNotEmpty)
                      _ListsCited(
                        sources: alert.sources,
                        now: now,
                        style: theme.textTheme.bodySmall?.copyWith(color: ink),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lists an alert cites, in small text under its figures: on one line
/// when they all fit, else a line each, two at most, the second holding
/// the lists after the first. Three lines of them took a fifth of a phone's
/// screen; one line cut the second list's name in two ("Délégation à
/// la…"). A line too short for its dates names its lists alone, and drops
/// the last ones whole before it cuts a name (a camera of the French map,
/// of the yearly file and of OpenStreetMap cites three): "Délégation à la
/// sécurité routière…" stands for that list, its date and any list after
/// it. Only a name longer than the whole line is cut, at its end. Each
/// list is named in full, with its date, on the camera's card, the preview
/// and the credits.
class _ListsCited extends StatelessWidget {
  const new({required this.sources, required this.now, required this.style});

  final List<EnforcementSource> sources;
  final DateTime now;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Text text(String data) =>
        Text(data, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    String dated(Iterable<EnforcementSource> lists) =>
        [for (final s in lists) t.enforcementSource(s, now: now)].join(' · ');
    String named(Iterable<EnforcementSource> lists) =>
        [for (final s in lists) t.listName(s)].join(' · ');
    Widget line(List<EnforcementSource> lists) => FirstThatFits(
      children: [
        text(dated(lists)),
        for (var n = lists.length; n > 0; n--)
          text(t.navigation.guidance.enforcementSourceUndated(source: named(lists.take(n)))),
        text(named(lists.take(1))),
      ],
    );
    if (sources.length == 1) return line(sources);
    return FirstThatFits(
      children: [
        text(dated(sources)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [line(sources.sublist(0, 1)), line(sources.sublist(1))],
        ),
      ],
    );
  }
}

/// The danger sign of a zone: a white triangle in a red rim with its mark,
/// as the road shows it. Never a camera: a zone does not say where one is.
class _DangerSign extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: RouteBadge.camera.extent * 1.3,
    child: const CustomPaint(painter: _DangerSignPainter()),
  );
}

class _DangerSignPainter extends CustomPainter {
  const new();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rim = w * 0.1;
    final triangle = Path()
      ..moveTo(w / 2, h * 0.1)
      ..lineTo(w * 0.94, h * 0.86)
      ..lineTo(w * 0.06, h * 0.86)
      ..close();
    canvas
      ..drawPath(
        triangle,
        Paint()
          ..color = Palette.minuit.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = rim + 1.5
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(triangle, Paint()..color = Palette.white)
      ..drawPath(
        triangle,
        Paint()
          ..color = Palette.corail700
          ..style = PaintingStyle.stroke
          ..strokeWidth = rim
          ..strokeJoin = StrokeJoin.round,
      );
    final mark = Paint()..color = Palette.minuit;
    final x = w / 2;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x - w * 0.045, h * 0.38, x + w * 0.045, h * 0.64),
          Radius.circular(w * 0.04),
        ),
        mark,
      )
      ..drawCircle(Offset(x, h * 0.73), w * 0.05, mark);
  }

  @override
  bool shouldRepaint(_DangerSignPainter old) => false;
}

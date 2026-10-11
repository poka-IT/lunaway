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
import 'package:lunaway/shared/widgets/notice_views.dart';

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

/// The standing notice of [alert], beside the speed ([EnforcementChip]):
/// folded by a tap, open again when it grows graver ([enforcementLevel]).
StandingNotice enforcementNotice(Translations t, EnforcementAlert alert, DistanceUnits units) =>
    StandingNotice(
      id: ('aid', alert.id),
      icon: alert.kind == EnforcementKind.camera ? AppIcons.camera : AppIcons.warning,
      text: enforcementText(t, alert, units),
      // Folded, the chip keeps the error's colours over the limit only.
      strong: alert.over,
      level: enforcementLevel(alert),
      look: EnforcementChip(alert: alert, units: units),
    );

/// The id of [alertExitNotice] for [exit], to take it back when another
/// alert takes the screen before its time is over.
Object alertExitNoticeId(AlertExit exit) => ('aid exit', exit.id);

/// The end of a zone or a section just left, as a passing notice where its
/// chip stood: calm, never said aloud.
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

/// A camera, a section or a danger zone coming or around the vehicle, as a
/// small pill beside the speed and its limit, in the spirit of the driving
/// apps: the pictogram of the map's mark (the camera's badge, a danger
/// sign for a zone, never a camera there), the distance, and the sign of
/// the limit that matters when one is known ("moyenne" above a section's).
/// Inside a section, the vehicle's average under the distance. Sober
/// colours; the error's only over that limit. Its kind, the lists it comes
/// from and the words "au-dessus de la limite" go to a screen reader in one
/// sentence ([enforcementText]), heard once per level; the lists, with
/// their date, are on the camera's card, the preview and the credits.
class EnforcementChip extends StatelessWidget {
  const new({required this.alert, required this.units, super.key});

  final EnforcementAlert alert;
  final DistanceUnits units;

  /// The pictogram's height and the limit's sign: the pill stays a touch
  /// target high (48) with its padding, no taller.
  static const double _sign = 36;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final camera = alert.kind == EnforcementKind.camera;
    final over = alert.over;
    final background = over ? scheme.error : scheme.surfaceContainerLowest;
    final ink = over ? scheme.onError : scheme.onSurface;
    final limit = alert.limitKmh;
    final average = alert.averageKmh;
    // Nearer than [atHandM], no figure: the pictogram says it all.
    final distance = alert.atHand
        ? null
        : alert.within
        ? t.navigation.enforcement.remaining(distance: t.routeDistance(alert.remainingM, units))
        : t.routeDistance(alert.aheadM, units);
    return Semantics(
      label: enforcementText(t, alert, units),
      excludeSemantics: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (camera)
                    const RouteBadgeView(RouteBadge.camera)
                  else
                    const _DangerSign(size: _sign),
                  // One line, made smaller rather than broken where large
                  // text leaves it too little room beside the sign.
                  if (distance != null) ...[
                    const SizedBox(width: Space.s),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          distance,
                          maxLines: 1,
                          // The theme's figures are of one width: the pill
                          // keeps its width as the distance counts down.
                          style: theme.textTheme.titleMedium?.copyWith(color: ink),
                        ),
                      ),
                    ),
                  ],
                  if (limit != null) ...[
                    const SizedBox(width: Space.s),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (alert.isSection && alert.cameraLimit)
                          SizedBox(
                            width: _sign + Space.s,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                t.navigation.enforcement.averageLabel,
                                maxLines: 1,
                                style: theme.textTheme.labelSmall?.copyWith(color: ink),
                              ),
                            ),
                          ),
                        LimitSign(
                          value: t.speedIn(limit, units),
                          estimated: alert.limitEstimated,
                          size: _sign,
                          outline: over ? ink : null,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              if (average != null && alert.within)
                Text(
                  t.navigation.enforcement.yourAverage(speed: t.speedLimit(average.round(), units)),
                  style: theme.textTheme.labelMedium?.copyWith(color: ink),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The danger sign of a zone: a white triangle in a red rim with its mark,
/// as the road shows it. Never a camera: a zone does not say where one is.
class _DangerSign extends StatelessWidget {
  const new({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
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

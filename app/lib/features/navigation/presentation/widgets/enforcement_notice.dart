import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/driving_aids.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/route_badges.dart';
import 'package:lunaway/features/navigation/presentation/widgets/speed_sign.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The banner of the speed cameras during guidance, one thing at a time
/// ([DrivingAids.banner]): the camera, the section or the danger zone
/// coming or around the vehicle, the end of the one just left, or the rule
/// of the country just entered. The guidance decides what the rules allow;
/// a danger zone shows a warning sign, never a camera.
class EnforcementNotice extends StatelessWidget {
  const new({required this.banner, required this.units, super.key});

  final AidsBanner banner;
  final DistanceUnits units;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return switch (banner) {
      final EnforcementAlert alert => _AlertBanner(alert: alert, units: units),
      AlertExit(:final section) => _QuietBanner(
        icon: AppIcons.check,
        text: section ? t.navigation.enforcement.sectionEnd : t.navigation.enforcement.zoneEnd,
      ),
      final RuleChange change => _QuietBanner(icon: AppIcons.about, text: t.ruleChange(change)),
    };
  }
}

/// A zone, a camera or a section: its pictogram, its kind, the distance in
/// large, the limit's sign, the lists under them. Over the limit, the
/// error colours and the words say so.
class _AlertBanner extends StatefulWidget {
  const new({required this.alert, required this.units});

  final EnforcementAlert alert;
  final DistanceUnits units;

  @override
  State<_AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<_AlertBanner> {
  /// What the screen reader is told, made anew only when the alert comes,
  /// is entered, goes over its limit or back, or its average shows: a live
  /// region told at every fix would read the distance every second.
  String? _toldFor;
  String _told = '';

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final alert = widget.alert;
    final units = widget.units;
    final camera = alert.kind == EnforcementKind.camera;
    final stretch = !camera || alert.isSection;
    final inside = alert.inside && stretch;
    final background = alert.over ? scheme.error : scheme.errorContainer;
    final ink = alert.over ? scheme.onError : scheme.onErrorContainer;
    final limit = alert.limitKmh;
    final average = alert.averageKmh;
    final distance = inside
        ? t.navigation.enforcement.remaining(distance: t.routeDistance(alert.remainingM, units))
        : t.routeDistance(alert.aheadM, units);
    final phase = '${alert.id} $inside ${alert.over} ${average != null}';
    if (phase != _toldFor) {
      _toldFor = phase;
      _told = _sentence(t, alert, units, inside: inside);
    }
    return Semantics(
      liveRegion: true,
      container: true,
      label: _told,
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
                    for (final s in alert.sources)
                      Text(
                        t.enforcementSource(s),
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

  /// One sentence for the screen reader: "Radar fixe dans 800 m, limite
  /// 90 km/h, au-dessus de la limite."
  static String _sentence(
    Translations t,
    EnforcementAlert alert,
    DistanceUnits units, {
    required bool inside,
  }) {
    final what = t.alertKind(alert);
    final limit = alert.limitKmh;
    final speed = limit == null ? null : t.speedLimit(limit, units);
    final average = alert.averageKmh;
    final parts = [
      if (inside) ...[
        what,
        t.navigation.enforcement.remaining(distance: t.routeDistance(alert.remainingM, units)),
      ] else if (alert.aheadM > 0)
        t.navigation.enforcement.ahead(what: what, distance: t.routeDistance(alert.aheadM, units))
      else
        what,
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
}

/// The end of a zone or a section, or the rule of a country: calm, in the
/// colours of the guidance's other news.
class _QuietBanner extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(LunaTokens.radiusL),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.sm),
          child: Row(
            children: [
              Icon(icon, color: scheme.onSecondaryContainer),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSecondaryContainer),
                ),
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

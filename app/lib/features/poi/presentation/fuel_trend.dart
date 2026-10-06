import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/features/poi/application/fuel_feed_providers.dart';
import 'package:lunaway/features/poi/data/fuel_feed.dart';
import 'package:lunaway/features/poi/presentation/poi_labels.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/status_views.dart';

/// How the price of [fuel] at the station [poiId] moved over 7 and 30
/// days, as Lunaway saw it: the lowest and highest, the change, and a bar
/// for each day seen. A day the feed did not give stays empty; nothing is
/// drawn between two days seen.
class FuelTrendCard extends ConsumerWidget {
  const new({required this.poiId, required this.fuel, super.key});

  final String poiId;

  /// The feed's name of the fuel (`FuelKind`).
  final String fuel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final trend = ref.watch(fuelTrendProvider(poiId, fuel));
    final body = switch (trend) {
      AsyncData(value: final FuelTrend trend) when trend.days.isNotEmpty => _Trend(trend: trend),
      AsyncData() => Text(t.poi.trend.none, style: muted),
      AsyncError() => Text(t.poi.trend.failed, style: muted),
      _ => const Skeleton(height: 72, radius: LunaTokens.radiusL),
    };
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LunaTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              t.poi.trend.title(fuel: t.fuelName(fuel)),
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: Space.s),
          body,
        ],
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  const new({required this.trend});

  final FuelTrend trend;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final first = trend.days.first.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trend.last7 case final span?) _SpanLine(label: t.poi.trend.week, span: span),
        // The month says more than the week only once it holds more days.
        if (trend.last30 case final span? when span.daysKnown > (trend.last7?.daysKnown ?? 0))
          _SpanLine(label: t.poi.trend.month, span: span),
        const SizedBox(height: Space.m),
        ExcludeSemantics(
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(
              painter: _DaysPainter(
                days: trend.days,
                color: scheme.primary,
                baseline: scheme.outlineVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          t.poi.trend.since(
            date: DateFormat.MMMMd(t.$meta.locale.languageCode).format(first),
            n: trend.days.length,
          ),
          style: muted,
        ),
      ],
    );
  }
}

/// "7 derniers jours : de 2,199 à 2,250 €/L, en baisse de 0,020 €/L".
class _SpanLine extends StatelessWidget {
  const new({required this.label, required this.span});

  final String label;
  final FuelPriceSpan span;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final change = span.changeEur;
    final range = span.highEur - span.lowEur < 0.0005
        ? t.pricePerLitre(span.lowEur)
        : t.poi.trend.range(low: t.pricePerLitre(span.lowEur), high: t.pricePerLitre(span.highEur));
    final move = switch (change) {
      null => t.poi.trend.oneDay,
      final c when c.abs() < 0.0005 => t.poi.trend.steady,
      final c when c < 0 => t.poi.trend.down(amount: t.pricePerLitre(-c)),
      final c => t.poi.trend.up(amount: t.pricePerLitre(c)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: label, style: theme.textTheme.titleSmall),
            const TextSpan(text: ' '),
            TextSpan(
              text: t.poi.trend.span(range: range, move: move),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar per day seen, from its lowest to its highest price, on the scale
/// of the 30 days; a day not seen leaves its place empty.
class _DaysPainter extends CustomPainter {
  new({required this.days, required this.color, required this.baseline});

  final List<FuelPriceDay> days;
  final Color color;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final last = days.last.day;
    final low = days.map((d) => d.lowEur).reduce(math.min);
    final high = days.map((d) => d.highEur).reduce(math.max);
    final spread = math.max(high - low, 0.01);
    const slots = 30;
    final slot = size.width / slots;
    final bar = math.max<double>(2, slot * 0.6);
    double y(double price) => size.height - 4 - (price - low) / spread * (size.height - 8);
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = bar;
    for (final d in days) {
      final age = last.difference(d.day).inDays;
      if (age < 0 || age >= slots) continue;
      final x = size.width - (age + 0.5) * slot;
      final top = y(d.highEur);
      final bottom = y(d.lowEur);
      canvas.drawLine(Offset(x, top), Offset(x, math.max(bottom, top + 0.1)), paint);
    }
  }

  @override
  bool shouldRepaint(_DaysPainter old) =>
      old.days != days || old.color != color || old.baseline != baseline;
}

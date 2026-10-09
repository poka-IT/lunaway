import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/community/presentation/contribute.dart';
import 'package:lunaway/features/navigation/application/driving_aids.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/road_reports.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/passenger_check.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/app_icons.dart';
import 'package:lunaway/shared/theme/tokens.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

/// Above this speed, metres per second (about 10 km/h), the vehicle is
/// driving: a report then waits for the user to say a passenger makes it.
const reportMovingMps = 2.8;

/// Lets a report through while the vehicle stands still; while it moves,
/// only once the user says a passenger makes it. One large tap either way:
/// the driver is told to stop rather than given a form.
Future<bool> clearedToReport(BuildContext context, {required bool moving}) => clearedWhileDriving(
  context,
  moving: moving,
  title: context.t.roadReport.movingTitle,
  body: context.t.roadReport.movingBody,
);

/// Asks what is seen on the road at [position] (taken when the user first
/// tapped, the vehicle going on meanwhile), then sends it through the
/// outbox: at once with the network, later without. Where the server takes
/// no report, it says so and where it does, rather than a form the server
/// would refuse.
Future<void> reportOnRoad(
  BuildContext context, {
  required LatLng position,
  double? headingDeg,
  bool moving = false,
}) async {
  // A second tap while the first one is under way opens nothing more.
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_reporting[navigator] ?? false) return;
  _reporting[navigator] = true;
  try {
    await _reportOnRoad(context, position: position, headingDeg: headingDeg, moving: moving);
  } finally {
    _reporting[navigator] = null;
  }
}

/// The app's navigators with a report under way.
final _reporting = Expando<bool>('road report under way');

Future<void> _reportOnRoad(
  BuildContext context, {
  required LatLng position,
  required double? headingDeg,
  required bool moving,
}) async {
  // The page's context outlives the sheet, for the message after it.
  final page = Navigator.of(context, rootNavigator: true).context;
  final accepted = await _reportCountriesIfOutside(
    ProviderScope.containerOf(context, listen: false),
    position,
  );
  if (!context.mounted) return;
  if (accepted != null) {
    // A list of countries to read: a dialog, which stays until it is read.
    final t = context.t;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.roadReport.notHereTitle),
        content: Text(t.roadReport.notHere(countries: t.countryList(accepted))),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            child: Text(t.common.ok),
          ),
        ],
      ),
    );
    return;
  }
  if (!await clearedToReport(context, moving: moving) || !page.mounted) return;
  final report = await showFormSheet<RoadReport>(
    page,
    tall: false,
    builder: (context, scroll) =>
        _ReportSheet(position: position, headingDeg: headingDeg, scrollController: scroll),
  );
  if (report == null || !page.mounted) return;
  await submitContribution(
    page,
    ContributionKind.reportRoadEvent,
    payload: {'input': report.toInput()},
    sentText: page.t.roadReport.sent,
  );
}

/// The countries road reports are accepted in, when [position] lies outside
/// them for sure; null when it may be reported there, or when the device
/// cannot tell in time: the server then decides.
Future<List<String>?> _reportCountriesIfOutside(
  ProviderContainer container,
  LatLng position,
) async {
  try {
    final info = await container.read(routeServiceProvider).info().timeout(reportCheckWait);
    final locator = await container.read(countryLocatorProvider.future);
    return reportCountriesIfOutside(info, locator, position);
  } on Object {
    return null;
  }
}

/// "Still there" about a community report: the same report again, which
/// keeps it alive and may confirm it.
Future<void> confirmRoadReport(
  BuildContext context,
  RoadEvent event, {
  LatLng? at,
  bool moving = false,
}) async {
  final report = RoadReport.stillThere(event, at: at);
  if (report == null || !await clearedToReport(context, moving: moving) || !context.mounted) {
    return;
  }
  await submitContribution(
    context,
    ContributionKind.reportRoadEvent,
    payload: {'input': report.toInput()},
    sentText: context.t.roadReport.overSent,
  );
}

/// "It is over" about a community report.
Future<void> clearRoadReport(BuildContext context, RoadEvent event, {bool moving = false}) async {
  if (!await clearedToReport(context, moving: moving) || !context.mounted) return;
  await submitContribution(
    context,
    ContributionKind.clearRoadEvent,
    payload: {'eventId': event.id},
    sentText: context.t.roadReport.overSent,
  );
}

/// The two answers about a community road report, in reach of a thumb.
class CommunityReportActions extends StatelessWidget {
  const new({required this.onStillThere, required this.onOver, super.key});

  final VoidCallback onStillThere;
  final VoidCallback onOver;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final style = OutlinedButton.styleFrom(minimumSize: const Size(0, 48));
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onStillThere,
            style: style,
            child: Text(t.roadReport.stillThere),
          ),
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: OutlinedButton(onPressed: onOver, style: style, child: Text(t.roadReport.over)),
        ),
      ],
    );
  }
}

class _ReportSheet extends StatefulWidget {
  const new({required this.position, this.headingDeg, this.scrollController});

  final LatLng position;
  final double? headingDeg;
  final ScrollController? scrollController;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  RoadReportKind? _kind;
  double? _value;

  void _choose(RoadReportKind kind) => setState(() {
    _kind = kind;
    // Only a low clearance needs its figure; a narrow passage goes without.
    _value = kind == RoadReportKind.lowClearance ? kind.figure!.start : null;
  });

  void _step(double by) {
    final figure = _kind?.figure;
    if (figure == null || _value == null) return;
    setState(() {
      _value = ((_value! + by) * 10).roundToDouble() / 10;
      _value = math.min(figure.max, math.max(figure.min, _value!));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final kind = _kind;
    return FormSheetFrame(
      title: t.roadReport.title,
      scrollController: widget.scrollController,
      action: FilledButton.icon(
        onPressed: kind == null
            ? null
            : () => Navigator.of(context).pop(
                RoadReport(
                  kind: kind,
                  position: widget.position,
                  headingDeg: widget.headingDeg,
                  valueM: _value,
                ),
              ),
        icon: const Icon(AppIcons.report),
        label: Text(t.roadReport.send),
      ),
      children: [
        Text(
          t.roadReport.intro,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: Space.l),
        // Two by two, each as tall as its label needs at the user's text
        // size, never under 88 dp: a target found without looking long.
        for (final pair in [RoadReportKind.values.take(2), RoadReportKind.values.skip(2)]) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, k) in pair.indexed) ...[
                  if (i > 0) const SizedBox(width: Space.s),
                  Expanded(
                    child: _KindTile(kind: k, selected: k == kind, onTap: () => _choose(k)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.s),
        ],
        if (kind == RoadReportKind.lowClearance && _value != null) ...[
          const SizedBox(height: Space.l),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: t.roadReport.lower,
                onPressed: () => _step(-0.1),
                style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                icon: const Icon(AppIcons.zoomOut),
              ),
              Expanded(
                child: Text(
                  t.roadReport.height(value: t.metres(_value!)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton.filledTonal(
                tooltip: t.roadReport.higher,
                onPressed: () => _step(0.1),
                style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
                icon: const Icon(AppIcons.zoomIn),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _KindTile extends StatelessWidget {
  const new({required this.kind, required this.selected, required this.onTap});

  final RoadReportKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (kind) {
      RoadReportKind.closure => AppIcons.roadEvent(RoadEventClass.closure),
      RoadReportKind.works => AppIcons.roadEvent(RoadEventClass.works),
      RoadReportKind.narrowPassage ||
      RoadReportKind.lowClearance => AppIcons.roadEvent(RoadEventClass.vehicleLimit),
    };
    final label = context.t.roadReportKind(kind);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          borderRadius: BorderRadius.circular(LunaTokens.radiusL),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(Space.m),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // A narrow passage: the arrows of a limit, turned to a width.
                  RotatedBox(
                    quarterTurns: kind == RoadReportKind.narrowPassage ? 1 : 0,
                    child: Icon(
                      icon,
                      size: 28,
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

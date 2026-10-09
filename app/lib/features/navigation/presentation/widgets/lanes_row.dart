import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/maneuver.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The lanes at the next maneuver, the ones that lead on the route bright,
/// the others muted like the roads a pictogram does not take: a heavy
/// vehicle changes lane early.
class LanesRow extends StatelessWidget {
  const new({required this.lanes, required this.color, this.size = 30, super.key});

  final List<LaneHint> lanes;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    // A divider of whole device pixels, about 1.5 logical ones: a
    // fraction of a pixel smears into a grey band.
    final divider = (1.5 * ratio).roundToDouble() / ratio;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, lane) in lanes.indexed) ...[
          if (i > 0)
            Container(
              width: divider,
              height: size * 0.8,
              margin: const EdgeInsets.symmetric(horizontal: Space.xxs),
              color: color.withValues(alpha: maneuverMutedAlpha),
            ),
          ManeuverIcon(
            maneuver: Maneuver(
              type: 'turn',
              modifier: lane.active && lane.follows != null
                  ? lane.follows
                  : _modifier(lane.directions),
            ),
            size: size,
            color: lane.active ? color : color.withValues(alpha: maneuverMutedAlpha),
          ),
        ],
      ],
    );
  }

  /// The arrow of a lane the route does not take: the turn it allows
  /// besides going on, or its only direction.
  static String _modifier(List<String> directions) {
    if (directions.isEmpty) return 'straight';
    if (directions.contains('straight') && directions.length > 1) {
      return directions.firstWhere((d) => d != 'straight');
    }
    return directions.first == 'none' ? 'straight' : directions.first;
  }
}

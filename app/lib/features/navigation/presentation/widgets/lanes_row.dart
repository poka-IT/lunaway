import 'package:flutter/material.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/presentation/widgets/maneuver_icon.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The lanes at the next maneuver, the ones that lead on the route bright,
/// the others faint: a heavy vehicle changes lane early.
class LanesRow extends StatelessWidget {
  const new({required this.lanes, required this.color, this.size = 30, super.key});

  final List<LaneHint> lanes;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, lane) in lanes.indexed) ...[
        if (i > 0)
          Container(
            width: 1.5,
            height: size * 0.8,
            margin: const EdgeInsets.symmetric(horizontal: Space.xxs),
            color: color.withValues(alpha: 0.35),
          ),
        Opacity(
          opacity: lane.active ? 1 : 0.3,
          child: ManeuverIcon(
            type: 'turn',
            modifier: lane.active && lane.follows != null
                ? lane.follows
                : _modifier(lane.directions),
            size: size,
            color: color,
          ),
        ),
      ],
    ],
  );

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

import 'package:meta/meta.dart';

/// A maneuver as its pictogram draws it: what the router says of a turn, a
/// roundabout or an arrival, and the side of the road traffic keeps to,
/// which sets the way round a roundabout and the side of a U-turn.
@immutable
final class Maneuver {
  const new({
    required this.type,
    this.modifier,
    this.exitDegrees,
    this.exitNumber,
    this.leftHandTraffic = false,
    this.ferry = false,
  });

  /// The OSRM maneuver type (`turn`, `roundabout`, `arrive`...).
  final String? type;

  /// Its direction (`left`, `slight right`, `uturn`...). On a roundabout
  /// it is the turn into the ring, not the exit: [exitDegrees] says where
  /// the exit is.
  final String? modifier;

  /// How far round a roundabout the exit lies, degrees from the entry in
  /// the direction of traffic: 90 is a quarter turn, 180 straight across.
  final int? exitDegrees;

  /// The exit of a roundabout, counted from the entry (1 is the first).
  final int? exitNumber;

  /// Traffic keeps left (United Kingdom, Ireland, Malta, Cyprus):
  /// roundabouts turn clockwise, a U-turn goes round to the right.
  final bool leftHandTraffic;

  /// The road after the maneuver is a ferry crossing.
  final bool ferry;

  /// A roundabout or a rotary, entered or left.
  bool get isRoundabout => switch (type) {
    'roundabout' || 'rotary' || 'roundabout turn' || 'exit roundabout' || 'exit rotary' => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is Maneuver &&
      other.type == type &&
      other.modifier == modifier &&
      other.exitDegrees == exitDegrees &&
      other.exitNumber == exitNumber &&
      other.leftHandTraffic == leftHandTraffic &&
      other.ferry == ferry;

  @override
  int get hashCode => Object.hash(type, modifier, exitDegrees, exitNumber, leftHandTraffic, ferry);

  @override
  String toString() =>
      'Maneuver($type, $modifier, exit $exitNumber at $exitDegrees°${leftHandTraffic ? ', left-hand' : ''}${ferry ? ', ferry' : ''})';
}

/// How far round a roundabout its exit lies, degrees in the direction of
/// traffic (see [Maneuver.exitDegrees]), from the heading before the ring
/// and the heading on the exit road, both degrees from north. The router's
/// own rule (Valhalla, `calc_roundabout_turn_degrees`): a road that leaves
/// in the heading it came in is 180 degrees round.
int roundaboutExitDegrees({
  required num headingIn,
  required num headingOut,
  required bool leftHandTraffic,
}) {
  final keepRight = ((headingIn - headingOut - 180) % 360 + 360) % 360;
  return (leftHandTraffic ? 360 - keepRight : keepRight).round() % 360;
}

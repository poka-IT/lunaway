import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:meta/meta.dart';

/// What a user reports on the road (`RoadEventReportKind`). Police checks
/// are not among them: French law forbids passing on where they are
/// (Code de la route, L130-11).
enum RoadReportKind {
  closure('CLOSURE'),
  works('WORKS'),
  narrowPassage('NARROW_PASSAGE'),
  lowClearance('LOW_CLEARANCE');

  new(this.wire);

  final String wire;

  /// The figure it takes, metres, as the server accepts it: a height for a
  /// low clearance (required), a width for a narrow passage (optional).
  ({double min, double max, double start})? get figure => switch (this) {
    lowClearance => (min: 1.5, max: 6, start: 3),
    narrowPassage => (min: 1.5, max: 5, start: 2.5),
    _ => null,
  };

  bool get figureRequired => this == lowClearance;
}

/// The id of the source of the community's road events.
const communityRoadSource = 'community';

/// A report ready to send: `RoadEventReportInput`.
@immutable
final class RoadReport {
  const new({required this.kind, required this.position, this.headingDeg, this.valueM});

  final RoadReportKind kind;
  final LatLng position;

  /// The vehicle's course when it moves: the report concerns that way.
  final double? headingDeg;
  final double? valueM;

  /// The mutation's `input`.
  Map<String, Object?> toInput() => {
    'kind': kind.wire,
    'lat': position.lat,
    'lon': position.lon,
    if (headingDeg case final h?) 'headingDeg': h.round() % 360,
    if (valueM case final v?) 'valueM': (v * 10).roundToDouble() / 10,
  };

  /// "Still there" about the community's [event]: the same kind and figure,
  /// at its spot and in its direction. Null for an event this app could not
  /// report again (no point, or a kind the community does not report).
  static RoadReport? stillThere(RoadEvent event, {LatLng? at}) {
    final where = event.position ?? at;
    if (where == null) return null;
    final (kind, value) = switch (event.eventClass) {
      RoadEventClass.closure => (RoadReportKind.closure, null),
      RoadEventClass.works => (RoadReportKind.works, null),
      RoadEventClass.laneRestriction => (RoadReportKind.narrowPassage, null),
      RoadEventClass.vehicleLimit when event.maxHeightM != null => (
        RoadReportKind.lowClearance,
        event.maxHeightM,
      ),
      RoadEventClass.vehicleLimit when event.maxWidthM != null => (
        RoadReportKind.narrowPassage,
        event.maxWidthM,
      ),
      _ => (null, null),
    };
    if (kind == null) return null;
    return RoadReport(kind: kind, position: where, headingDeg: event.headingDeg, valueM: value);
  }
}

/// What a report did: the event it supports and how far it is believed.
@immutable
final class RoadReportResult {
  const new({required this.eventId, required this.confirmed, this.expiresAt});

  final String eventId;

  /// Two accounts of level 1 or more agree: it now blocks routes.
  final bool confirmed;
  final DateTime? expiresAt;
}

RoadReportResult roadReportResultFromJson(Map<String, dynamic> json) => RoadReportResult(
  eventId: '${json['eventId']}',
  confirmed: json['confidence'] == 'CONFIRMED',
  expiresAt: DateTime.tryParse('${json['expiresAt']}'),
);

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/navigation/domain/road_reports.dart';

RoadEvent _event(RoadEventClass c, {double? height, double? width, LatLng? at}) => RoadEvent(
  id: 'e',
  eventClass: c,
  placement: RoadEventPlacement.point,
  source: communityRoadSource,
  position: at,
  maxHeightM: height,
  maxWidthM: width,
  headingDeg: 90,
);

void main() {
  test('a report sends a whole course within a turn and its figure to the decimetre', () {
    const report = RoadReport(
      kind: RoadReportKind.lowClearance,
      position: LatLng(45, 5),
      headingDeg: 359.7,
      valueM: 3.149,
    );
    expect(report.toInput(), {
      'kind': 'LOW_CLEARANCE',
      'lat': 45.0,
      'lon': 5.0,
      'headingDeg': 0,
      'valueM': 3.1,
    });
  });

  test('"still there" reports the community event again as it was reported', () {
    const at = LatLng(45.1, 5.2);
    final low = RoadReport.stillThere(_event(RoadEventClass.vehicleLimit, height: 3.4, at: at))!;
    expect(
      (low.kind, low.valueM, low.position, low.headingDeg),
      (RoadReportKind.lowClearance, 3.4, at, 90.0),
    );
    final narrow = RoadReport.stillThere(_event(RoadEventClass.vehicleLimit, width: 2.2, at: at))!;
    expect((narrow.kind, narrow.valueM), (RoadReportKind.narrowPassage, 2.2));
    expect(
      RoadReport.stillThere(_event(RoadEventClass.laneRestriction, at: at))!.kind,
      RoadReportKind.narrowPassage,
    );
    // Without a point of its own, where the route meets it.
    expect(RoadReport.stillThere(_event(RoadEventClass.closure), at: at)!.position, at);
    expect(RoadReport.stillThere(_event(RoadEventClass.detour, at: at)), isNull);
  });
}

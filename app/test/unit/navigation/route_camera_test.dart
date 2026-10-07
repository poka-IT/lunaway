import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/free_map.dart';
import 'package:lunaway/features/navigation/presentation/route_map.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';

void main() {
  const follow = FollowCamera(position: LatLng(45.84, 1.28), course: 90, speedMps: 10);
  const nextFix = FollowCamera(position: LatLng(45.841, 1.28), course: 90, speedMps: 10);
  const free = FreeCamera();
  const whole = FitCamera(GeoBounds(south: 45.8, west: 1.2, north: 45.9, east: 1.3));

  group('what the engine does with the camera asked', () {
    test('into following from another view, then each fix while following', () {
      expect(cameraStep(sent: null, next: follow, heldByUser: false), CameraStep.enterFollow);
      expect(cameraStep(sent: free, next: follow, heldByUser: false), CameraStep.enterFollow);
      expect(cameraStep(sent: whole, next: follow, heldByUser: false), CameraStep.enterFollow);
      expect(cameraStep(sent: follow, next: nextFix, heldByUser: false), CameraStep.follow);
      expect(cameraStep(sent: follow, next: follow, heldByUser: false), CameraStep.none);
    });

    test("a gesture keeps the user's view while the screen still says follow", () {
      expect(cameraStep(sent: follow, next: nextFix, heldByUser: true), CameraStep.none);
      expect(cameraStep(sent: free, next: follow, heldByUser: true), CameraStep.none);
    });

    test('free stops following once; the whole route is flat after a driving view', () {
      expect(cameraStep(sent: follow, next: free, heldByUser: true), CameraStep.free);
      expect(cameraStep(sent: free, next: const FreeCamera(), heldByUser: false), CameraStep.none);
      expect(cameraStep(sent: follow, next: whole, heldByUser: false), CameraStep.overview);
      expect(cameraStep(sent: free, next: whole, heldByUser: true), CameraStep.overview);
      expect(cameraStep(sent: null, next: whole, heldByUser: false), CameraStep.fit);
      expect(cameraStep(sent: whole, next: whole, heldByUser: false), CameraStep.none);
    });

    test('a request to follow in the same frame as the gesture still follows', () {
      // The magnet answered a nudge before the screen built the free map:
      // the engine sees one following camera after another.
      const snapped = FollowCamera(
        position: LatLng(45.841, 1.28),
        course: 90,
        speedMps: 10,
        request: 1,
      );
      expect(heldAfter(held: true, before: follow, after: snapped), isFalse);
      expect(cameraStep(sent: follow, next: snapped, heldByUser: false), CameraStep.enterFollow);
      // Later fixes of that same request only follow on.
      const later = FollowCamera(position: LatLng(45.842, 1.28), course: 90, request: 1);
      expect(heldAfter(held: true, before: snapped, after: later), isTrue);
      expect(cameraStep(sent: snapped, next: later, heldByUser: false), CameraStep.follow);
    });

    test('a new request to follow lets a gesture go; a gesture after it holds again', () {
      // "Recentrer" after the screen freed the map.
      expect(heldAfter(held: true, before: free, after: follow), isFalse);
      // A new fix while the screen has not freed the map yet.
      expect(heldAfter(held: true, before: follow, after: nextFix), isTrue);
      expect(heldAfter(held: true, before: follow, after: free), isTrue);
      expect(heldAfter(held: false, before: free, after: follow), isFalse);
    });
  });

  test("reads the page's report of a rest", () {
    final view = freeViewOfPage(const {
      'type': 'rest',
      'x': 200.5,
      'y': 530,
      'lat': 45.84,
      'lon': 1.28,
      'zoom': 16.2,
      'bearing': 30,
      'pitch': 50,
      'width': 412,
      'height': 915,
    }, size: const Size(1, 1));
    expect(view.vehicle, const Offset(200.5, 530));
    expect(view.center, const LatLng(45.84, 1.28));
    expect((view.zoom, view.bearing, view.tilt), (16.2, 30, 50));
    expect(view.size, const Size(412, 915));
    final bare = freeViewOfPage(const {'type': 'rest'}, size: const Size(400, 800));
    expect(bare.vehicle, isNull, reason: 'no vehicle drawn yet');
    expect(bare.center, isNull);
    expect(bare.size, const Size(400, 800), reason: "the map's own size");
  });

  group('a map made anew', () {
    RouteMapProps props(RouteCamera camera, {VehiclePuck? vehicle}) => RouteMapProps(
      style: '{}',
      dark: false,
      lines: const [
        RouteMapLine(index: 0, points: [LatLng(45, 1), LatLng(46, 2)], selected: true),
      ],
      camera: camera,
      vehicle: vehicle,
    );

    test('opens free where the user left it, the phone turned', () {
      const rest = FreeView(
        size: Size(400, 800),
        vehicle: null,
        center: LatLng(45.9, 1.4),
        zoom: 13.5,
        bearing: 40,
        tilt: 20,
      );
      final start = initialCamera(props(const FreeCamera(view: rest)));
      expect(start.target, const LatLng(45.9, 1.4));
      expect((start.zoom, start.bearing, start.tilt), (13.5, 40, 20));
    });

    test('free with no rest yet: behind the vehicle, else on the route, never elsewhere', () {
      final atVehicle = initialCamera(
        props(free, vehicle: const VehiclePuck(position: LatLng(45.5, 1.5), course: 30)),
      );
      expect(atVehicle.target, const LatLng(45.5, 1.5));
      expect(atVehicle.tilt, followTiltDeg);
      expect(atVehicle.bearing, 30);
      expect(initialCamera(props(free)).target, const LatLng(45.5, 1.5));
    });

    test('following opens behind the vehicle, tilted, turned to its course', () {
      final start = initialCamera(props(follow));
      expect(start.target, follow.position);
      expect((start.zoom, start.tilt, start.bearing), (follow.zoom, followTiltDeg, 90));
    });
  });
}

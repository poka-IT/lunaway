import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';
import 'package:lunaway/features/navigation/presentation/vehicle_motion.dart';

void main() {
  group('the drawn vehicle', () {
    const a = LatLng(45.8, 1.2);
    const b = LatLng(45.8001, 1.2);

    test('the first fix is drawn where it is', () {
      final m = VehicleMotion()..retarget(a, 10, Duration.zero);
      expect(m.at(Duration.zero), (a, 10.0));
      expect(m.movingAt(Duration.zero), isFalse);
    });

    test('it glides to the next fix over the time that fix took to come', () {
      final m = VehicleMotion()
        ..retarget(a, 0, Duration.zero)
        ..retarget(b, 0, const Duration(seconds: 1));
      final (half, _) = m.at(const Duration(milliseconds: 1500));
      expect(half!.lat, closeTo(45.80005, 1e-7));
      expect(m.movingAt(const Duration(milliseconds: 1500)), isTrue);
      expect(m.at(const Duration(seconds: 2)).$1, b);
      expect(m.movingAt(const Duration(seconds: 2)), isFalse);
    });

    test('a new fix mid-glide starts from where the vehicle is drawn, not jumps back', () {
      final m = VehicleMotion()
        ..retarget(a, 0, Duration.zero)
        ..retarget(b, 0, const Duration(seconds: 1))
        ..retarget(const LatLng(45.8002, 1.2), 0, const Duration(milliseconds: 1500));
      expect(m.at(const Duration(milliseconds: 1500)).$1!.lat, closeTo(45.80005, 1e-7));
    });

    test('it turns the short way round, through north', () {
      final m = VehicleMotion()
        ..retarget(a, 350, Duration.zero)
        ..retarget(b, 10, const Duration(seconds: 1));
      expect(m.at(const Duration(milliseconds: 1500)).$2, closeTo(0, 1e-9));
    });

    test('a late fix is reached in at most a second and a half', () {
      final m = VehicleMotion()
        ..retarget(a, 0, Duration.zero)
        ..retarget(b, 0, const Duration(seconds: 6));
      expect(m.movingAt(const Duration(milliseconds: 7400)), isTrue);
      expect(m.movingAt(const Duration(milliseconds: 7600)), isFalse);
    });

    test('a jump is drawn at once', () {
      final m = VehicleMotion()
        ..retarget(a, 0, Duration.zero)
        ..retarget(b, 0, const Duration(seconds: 1), jump: true);
      expect(m.at(const Duration(seconds: 1)).$1, b);
    });
  });

  test('the camera looks further ahead the faster the vehicle goes', () {
    expect(followZoom(null), 17);
    expect(followZoom(8), 17, reason: '29 km/h in town');
    expect(followZoom(130 / 3.6), 15.2);
    final mid = followZoom(75 / 3.6);
    expect(mid, lessThan(17));
    expect(mid, greaterThan(15.2));
  });

  test('the zoom eases toward the one asked for, a little each frame', () {
    final z = easeZoom(17, 15, const Duration(milliseconds: 100));
    expect(z, closeTo(16.9, 1e-9));
    expect(easeZoom(17, 15, const Duration(seconds: 5)), 15);
  });

  group('a browser fix without speed or course', () {
    final t0 = DateTime.utc(2026, 10, 7, 9);
    Fix fix(LatLng p, int ms, {double? speed, double? course}) => Fix(
      position: p,
      accuracyM: 8,
      at: t0.add(Duration(milliseconds: ms)),
      speedMps: speed,
      courseDeg: course,
    );

    test('gets them from the fix before it', () {
      // About 11.1 m north in one second.
      final next = withMotion(
        fix(const LatLng(45.8001, 1.2), 1000),
        fix(const LatLng(45.8, 1.2), 0),
      );
      expect(next.speedMps, closeTo(11.1, 0.1));
      expect(next.courseDeg, closeTo(0, 0.5));
    });

    test('standing still gives a speed and no course', () {
      final next = withMotion(
        fix(const LatLng(45.80001, 1.2), 1000),
        fix(const LatLng(45.8, 1.2), 0),
      );
      expect(next.speedMps, closeTo(1.1, 0.1));
      expect(next.courseDeg, isNull, reason: 'a move under the fixes uncertainty is noise');
    });

    test('keeps what the device gave and ignores a stale previous fix', () {
      final own = fix(const LatLng(45.8001, 1.2), 1000, speed: 3, course: 90);
      expect(withMotion(own, fix(const LatLng(45.8, 1.2), 0)), same(own));
      final late = fix(const LatLng(45.81, 1.2), 60000);
      expect(withMotion(late, fix(const LatLng(45.8, 1.2), 0)).speedMps, isNull);
    });
  });

  group('the browser voice', () {
    test('a voice of the device in the exact language comes first', () {
      final i = pickBrowserVoice(
        [
          (lang: 'fr-CA', local: true, isDefault: false),
          (lang: 'fr-FR', local: false, isDefault: false),
          (lang: 'fr-FR', local: true, isDefault: false),
          (lang: 'en-GB', local: true, isDefault: true),
        ],
        language: 'fr',
        preferred: 'fr-FR',
      );
      expect(i, 2);
    });

    test('a voice that speaks through its vendor is never picked', () {
      final i = pickBrowserVoice(
        [(lang: 'fr-FR', local: false, isDefault: true)],
        language: 'fr',
        preferred: 'fr-FR',
      );
      expect(i, isNull);
    });

    test('another region of the language serves when it is the only one', () {
      expect(
        pickBrowserVoice(
          [(lang: 'en_US', local: true, isDefault: false)],
          language: 'en',
          preferred: 'en-GB',
        ),
        0,
      );
    });
  });
}

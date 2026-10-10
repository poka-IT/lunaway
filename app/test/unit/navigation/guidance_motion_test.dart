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

    test('the same fix again leaves the glide as it was', () {
      final m = VehicleMotion()
        ..retarget(a, 0, Duration.zero)
        ..retarget(b, 0, const Duration(seconds: 1))
        // The screen rebuilt 100 ms later for another reason.
        ..retarget(b, 0, const Duration(milliseconds: 1100));
      expect(m.at(const Duration(milliseconds: 1500)).$1!.lat, closeTo(45.80005, 1e-7));
      expect(m.movingAt(const Duration(milliseconds: 1900)), isTrue);
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

    test('a jump gives no speed nor course rather than a false one', () {
      // 9 km in 3 s, out of a tunnel: 3 000 m/s.
      final jump = withMotion(
        fix(const LatLng(45.881, 1.2), 3000),
        fix(const LatLng(45.8, 1.2), 0),
      );
      expect(jump.speedMps, isNull);
      expect(jump.courseDeg, isNull);
      // 60 m/s, 216 km/h: still believed.
      final fast = withMotion(
        fix(const LatLng(45.80054, 1.2), 1000),
        fix(const LatLng(45.8, 1.2), 0),
      );
      expect(fast.speedMps, closeTo(60, 1));
    });

    test('fixes placed by the network give no speed', () {
      Fix vague(LatLng p, int ms) => Fix(
        position: p,
        accuracyM: 350,
        at: t0.add(Duration(milliseconds: ms)),
      );
      final next = withMotion(
        vague(const LatLng(45.8003, 1.2), 1000),
        vague(const LatLng(45.8, 1.2), 0),
      );
      expect(next.speedMps, isNull, reason: 'a 33 m drift of a 350 m circle is no motion');
      expect(next.courseDeg, isNull);
    });

    test('keeps what the device gave and ignores a stale previous fix', () {
      final own = fix(const LatLng(45.8001, 1.2), 1000, speed: 3, course: 90);
      expect(withMotion(own, fix(const LatLng(45.8, 1.2), 0)), same(own));
      final late = fix(const LatLng(45.81, 1.2), 60000);
      expect(withMotion(late, fix(const LatLng(45.8, 1.2), 0)).speedMps, isNull);
    });

    test('a speed of 0 while the position moves is an unknown one', () {
      // 20 m north in one second, "0 m/s" given with it: more than the two
      // fixes' uncertainty.
      final moving = withMotion(
        fix(const LatLng(45.80018, 1.2), 1000, speed: 0),
        fix(const LatLng(45.8, 1.2), 0, speed: 0),
      );
      expect(moving.speedMps, closeTo(20, 0.2));
      // Standing still, 0 stays 0.
      final still = withMotion(
        fix(const LatLng(45.80001, 1.2), 1000, speed: 0),
        fix(const LatLng(45.8, 1.2), 0, speed: 0),
      );
      expect(still.speedMps, 0);
    });
  });

  group('the time of a browser fix', () {
    final came = DateTime.utc(2026, 10, 10, 1, 12, 52, 300);

    test("is the browser's own within a minute of the page's clock", () {
      final own = came.subtract(const Duration(milliseconds: 1400));
      expect(browserFixTime(own.millisecondsSinceEpoch, came), own);
    });

    test("is the page's clock when the browser counts in microseconds or a day ahead", () {
      // Playwright's WebKit 26.6 and Firefox 155, measured on 2026-10-10.
      expect(browserFixTime(came.millisecondsSinceEpoch * 1000, came), came);
      expect(browserFixTime(came.add(const Duration(days: 1)).millisecondsSinceEpoch, came), came);
      expect(browserFixTime(double.nan, came), came);
    });

    test('two WebKit fixes a second apart give the speed driven between them', () {
      // What WebKit's watchPosition gave for two positions 13.9 m apart.
      final first = Fix(
        position: const LatLng(44.48, 4.68),
        accuracyM: 0,
        at: browserFixTime(1791596145277000, came),
      );
      final second = withMotion(
        Fix(
          position: const LatLng(44.480125, 4.68),
          accuracyM: 0,
          at: browserFixTime(1791596146695000, came.add(const Duration(seconds: 1))),
        ),
        first,
      );
      expect(second.speedMps, closeTo(13.9, 0.2));
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

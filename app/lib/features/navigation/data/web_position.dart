import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/guidance.dart';

/// The browser's position; only the web build has one (see
/// `web_position_web.dart`).
Future<({LatLng position, double accuracyM})?> webPosition(Duration timeout) async => null;

/// The browser's fixes while guiding; only the web build has them.
Stream<Fix> webFixes() => const Stream.empty();

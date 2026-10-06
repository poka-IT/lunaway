import 'package:lunaway/core/geo/geo.dart';

/// The browser's position; only the web build has one (see
/// `web_position_web.dart`).
Future<({LatLng position, double accuracyM})?> webPosition(Duration timeout) async => null;

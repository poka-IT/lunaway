import 'package:lunaway/core/geo/geo.dart';

/// No first map outside the browser.
({LatLng center, double zoom})? premapCamera({double? x, double? y}) => null;

void premapHandOver() {}

void premapRemember(String json) {}

void premapRememberFrame(String json) {}

/// No first map, so no place clicked on it.
({Map<Object?, Object?> properties, List<Object?> coordinates})? premapTakePlace() => null;

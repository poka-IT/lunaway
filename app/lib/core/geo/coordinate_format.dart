import 'package:lunaway/core/geo/geo.dart';

/// The ways a position can be copied. [decimal] is the default: latitude
/// first, six decimals (about 10 cm), a point as decimal separator whatever
/// the locale, then a comma and a space. It is what map and GPS apps accept
/// when pasted.
enum CoordinateFormat {
  decimal,
  dms,
  geoUri,
  googleMaps,
  openStreetMap;

  String format(LatLng p) => switch (this) {
    decimal => '${_fixed(p.lat)}, ${_fixed(p.lon)}',
    dms => '${_dms(p.lat, 'N', 'S')} ${_dms(p.lon, 'E', 'W')}',
    geoUri => 'geo:${_fixed(p.lat)},${_fixed(p.lon)}',
    googleMaps =>
      'https://www.google.com/maps/search/?api=1&query=${_fixed(p.lat)},${_fixed(p.lon)}',
    openStreetMap =>
      'https://www.openstreetmap.org/?mlat=${_fixed(p.lat)}&mlon=${_fixed(p.lon)}'
          '#map=17/${_fixed(p.lat)}/${_fixed(p.lon)}',
  };
}

/// Six decimals with a point, independent of the locale. A value that rounds
/// to zero prints without a minus sign.
String _fixed(double v) {
  final s = v.toStringAsFixed(6);
  return s == '-0.000000' ? '0.000000' : s;
}

/// Degrees, minutes and seconds with one decimal: `45°45'46.4"N`,
/// `4°50'01.7"E`. The seconds always take two digits, so that a reader
/// does not take 1.7 seconds for 17. Rounding is done on
/// tenths of a second first, so 59.96 seconds carries into the minute
/// instead of printing 60.0.
String _dms(double v, String positive, String negative) {
  final tenths = (v.abs() * 36000).round();
  final degrees = tenths ~/ 36000;
  final minutes = (tenths % 36000) ~/ 600;
  final seconds = ((tenths % 600) / 10).toStringAsFixed(1).padLeft(4, '0');
  final hemisphere = tenths == 0 || v >= 0 ? positive : negative;
  return "$degrees°$minutes'$seconds\"$hemisphere";
}

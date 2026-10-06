import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';

/// Colours with a meaning the Material scheme has no role for: the four kind
/// families and the overnight statuses. Pins keep one saturated tone in both
/// themes (they sit on the basemap, not on a surface); text and chips use the
/// tone tuned for the current theme.
@immutable
final class LunaColors extends ThemeExtension<LunaColors> {
  const new({
    required this.stopovers,
    required this.campsites,
    required this.nature,
    required this.services,
    required this.allowed,
    required this.tolerated,
    required this.dayOnly,
    required this.forbidden,
    required this.unknown,
  });

  /// Saturated tones shared by the map pins of both themes.
  static const pinStopovers = Color(0xFF2F6BD8);
  static const pinCampsites = Color(0xFFE0782F);
  static const pinNature = Color(0xFF23955A);
  static const pinServices = Color(0xFF8257E6);
  static const pinAllowed = Color(0xFF1C9A5E);
  static const pinTolerated = Color(0xFFE09A12);
  static const pinDayOnly = Color(0xFF5E6E86);
  static const pinForbidden = Color(0xFFD43F3F);

  /// The white ring and glyph of a pin, and its soft shadow on the basemap.
  static const pinRim = Color(0xFFFFFFFF);
  static const pinGlyph = Color(0xFFFFFFFF);
  static const pinShadow = Color(0x55000000);

  /// The marker on a point the user long-pressed: the lantern amber of the
  /// selection halo.
  static const pinPoint = Color(0xFFF2A33A);

  static const light = LunaColors(
    stopovers: Color(0xFF235BC4),
    campsites: Color(0xFFB85A14),
    nature: Color(0xFF1B7A49),
    services: Color(0xFF6B41CF),
    allowed: Color(0xFF15804D),
    tolerated: Color(0xFF9A6200),
    dayOnly: Color(0xFF4F5D73),
    forbidden: Color(0xFFB92F2F),
    unknown: Color(0xFF666B75),
  );

  static const dark = LunaColors(
    stopovers: Color(0xFF8DB2FF),
    campsites: Color(0xFFFFB37A),
    nature: Color(0xFF79D7A2),
    services: Color(0xFFC2A8FF),
    allowed: Color(0xFF6FDCA2),
    tolerated: Color(0xFFFFC95C),
    dayOnly: Color(0xFFB2BED1),
    forbidden: Color(0xFFFF8F8F),
    unknown: Color(0xFFB9BDC6),
  );

  final Color stopovers;
  final Color campsites;
  final Color nature;
  final Color services;
  final Color allowed;
  final Color tolerated;
  final Color dayOnly;
  final Color forbidden;
  final Color unknown;

  static LunaColors of(BuildContext context) => Theme.of(context).extension<LunaColors>()!;

  Color family(KindFamily family) => switch (family) {
    .stopovers => stopovers,
    .campsites => campsites,
    .nature => nature,
    .services => services,
  };

  Color overnight(OvernightStatus status) => switch (status) {
    .allowed => allowed,
    .tolerated => tolerated,
    .dayOnly => dayOnly,
    .forbidden => forbidden,
    .unknown => unknown,
  };

  static Color pinFamily(KindFamily family) => switch (family) {
    .stopovers => pinStopovers,
    .campsites => pinCampsites,
    .nature => pinNature,
    .services => pinServices,
  };

  static Color? pinOvernight(OvernightStatus status) => switch (status) {
    .allowed => pinAllowed,
    .tolerated => pinTolerated,
    .dayOnly => pinDayOnly,
    .forbidden => pinForbidden,
    .unknown => null,
  };

  @override
  LunaColors copyWith() => this;

  @override
  LunaColors lerp(LunaColors? other, double t) {
    if (other == null) return this;
    return LunaColors(
      stopovers: Color.lerp(stopovers, other.stopovers, t)!,
      campsites: Color.lerp(campsites, other.campsites, t)!,
      nature: Color.lerp(nature, other.nature, t)!,
      services: Color.lerp(services, other.services, t)!,
      allowed: Color.lerp(allowed, other.allowed, t)!,
      tolerated: Color.lerp(tolerated, other.tolerated, t)!,
      dayOnly: Color.lerp(dayOnly, other.dayOnly, t)!,
      forbidden: Color.lerp(forbidden, other.forbidden, t)!,
      unknown: Color.lerp(unknown, other.unknown, t)!,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/palette.dart';

/// The spacing scale every layout reads, in logical pixels: a design pass
/// retunes it here, not in the screens.
abstract final class Space {
  static const double hair = 2;
  static const double xxs = 4;
  static const double xs = 6;
  static const double s = 8;
  static const double sm = 10;
  static const double m = 12;
  static const double ml = 14;
  static const double l = 16;
  static const double lx = 18;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 28;
  static const double huge = 32;
  static const double giant = 48;
}

/// A control's height under the theme's density: [touch] where fingers
/// aim, 8 less with a mouse and a keyboard (the compact visual density of
/// the desktop look). For the controls the app draws itself (the search
/// pill, the chips, the rail); Material's own follow the density already.
double controlHeight(BuildContext context, double touch) =>
    touch + Theme.of(context).visualDensity.baseSizeAdjustment.dy;

/// How an overnight status is drawn: the moon phase on its disc, and the
/// tone of its label.
@immutable
final class NightTone {
  const new({required this.disc, required this.glyph, required this.label, this.ring});

  /// The badge's disc; transparent for the unknown status, drawn as a
  /// dotted ring instead.
  final Color disc;
  final Color glyph;

  /// The label next to the badge.
  final Color label;

  /// A ring around the disc where it would vanish into its surface.
  final Color? ring;

  NightTone lerp(NightTone other, double t) => NightTone(
    disc: Color.lerp(disc, other.disc, t)!,
    glyph: Color.lerp(glyph, other.glyph, t)!,
    label: Color.lerp(label, other.label, t)!,
    ring: Color.lerp(ring, other.ring, t),
  );
}

/// Shapes, shadows and the colours with no Material role, per theme.
/// Widgets read them with `LunaTokens.of(context)`; nothing in a feature
/// spells a radius, a shadow or a colour itself.
@immutable
final class LunaTokens extends ThemeExtension<LunaTokens> {
  const new({
    required this.familyText,
    required this.night,
    required this.link,
    required this.floatingSurface,
    required this.floatingShadow,
    required this.sheetShadow,
    required this.mapScrim,
    required this.dockSurface,
    required this.dockForeground,
    required this.dockSelected,
    required this.dockOnSelected,
    required this.photoBackdrop,
    required this.onPhotoBackdrop,
    required this.onPhotoBackdropMuted,
    required this.illustrationSky,
    required this.illustrationMoon,
    required this.illustrationFarHills,
    required this.illustrationNearHills,
    required this.illustrationRoad,
  });

  static const radiusXs = 6.0;
  static const radiusS = 10.0;
  static const radiusM = 14.0;
  static const radiusL = 18.0;
  static const radiusXl = 24.0;
  static const radiusSheet = 28.0;
  static const radiusPill = 999.0;

  /// The tones of the pins: one per family, the same in both themes since
  /// they sit on the basemap, under a cream rim.
  static Color familyFill(KindFamily family) => switch (family) {
    .stopovers => Palette.familyStopovers,
    .campsites => Palette.familyCampsites,
    .nature => Palette.familyNature,
    .services => Palette.familyServices,
  };

  /// The glyph and rim of a pin.
  static const Color pinGlyph = Palette.creme;
  static const Color pinRim = Palette.creme;

  /// The point a long press marks, and the halo of a selection: the amber
  /// that means "this one".
  static const Color selection = Palette.lanterne;

  static const aube = LunaTokens(
    familyText: {
      KindFamily.stopovers: Palette.stopoversOnLight,
      KindFamily.campsites: Palette.campsitesOnLight,
      KindFamily.nature: Palette.natureOnLight,
      KindFamily.services: Palette.servicesOnLight,
    },
    night: {
      OvernightStatus.allowed: NightTone(
        disc: Palette.minuit,
        glyph: Palette.creme,
        label: Palette.minuit,
      ),
      OvernightStatus.tolerated: NightTone(
        disc: Palette.minuit,
        glyph: Palette.creme,
        label: Palette.minuit,
      ),
      OvernightStatus.dayOnly: NightTone(
        disc: Palette.lanterne100,
        glyph: Palette.lanterne800,
        label: Palette.lanterne800,
        ring: Palette.lanterne200,
      ),
      OvernightStatus.forbidden: NightTone(
        disc: Palette.corail700,
        glyph: Palette.creme,
        label: Palette.corail800,
      ),
      OvernightStatus.unknown: NightTone(
        disc: Colors.transparent,
        glyph: Palette.minuit500,
        label: Palette.minuit500,
      ),
    },
    link: Palette.minuit,
    floatingSurface: Palette.creme50,
    floatingShadow: [
      BoxShadow(color: Color(0x24061F43), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x14061F43), blurRadius: 3, offset: Offset(0, 1)),
    ],
    sheetShadow: [BoxShadow(color: Color(0x2E061F43), blurRadius: 32, offset: Offset(0, -4))],
    mapScrim: Color(0xF0FFF7EA),
    dockSurface: Palette.minuit,
    dockForeground: Palette.creme,
    dockSelected: Palette.lanterne,
    dockOnSelected: Palette.minuit,
    photoBackdrop: Palette.minuit950,
    onPhotoBackdrop: Palette.creme,
    onPhotoBackdropMuted: Color(0x99FDF1DB),
    illustrationSky: Palette.creme300,
    illustrationMoon: Palette.lanterne,
    illustrationFarHills: Palette.sarcelle,
    illustrationNearHills: Palette.sarcelleProfonde,
    illustrationRoad: Palette.creme50,
  );

  static const minuitTheme = LunaTokens(
    familyText: {
      KindFamily.stopovers: Palette.stopoversOnDark,
      KindFamily.campsites: Palette.campsitesOnDark,
      KindFamily.nature: Palette.natureOnDark,
      KindFamily.services: Palette.servicesOnDark,
    },
    night: {
      // The moon stays light on a night sky: a disc a step above the
      // surface, ringed so it never sinks into it.
      OvernightStatus.allowed: NightTone(
        disc: Palette.minuit700,
        glyph: Palette.creme,
        label: Palette.creme,
        ring: Palette.minuit500,
      ),
      OvernightStatus.tolerated: NightTone(
        disc: Palette.minuit700,
        glyph: Palette.creme,
        label: Palette.creme,
        ring: Palette.minuit500,
      ),
      OvernightStatus.dayOnly: NightTone(
        disc: Palette.lanterne900,
        glyph: Palette.lanterne200,
        label: Palette.lanterne200,
      ),
      OvernightStatus.forbidden: NightTone(
        disc: Palette.corail300,
        glyph: Palette.minuit,
        label: Palette.corail300,
      ),
      OvernightStatus.unknown: NightTone(
        disc: Colors.transparent,
        glyph: Palette.cremeMuted,
        label: Palette.cremeMuted,
      ),
    },
    link: Palette.lanterne,
    floatingSurface: Palette.minuit800,
    floatingShadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
    sheetShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, -4))],
    mapScrim: Color(0xF0081A33),
    dockSurface: Palette.creme,
    dockForeground: Palette.minuit,
    dockSelected: Palette.lanterne,
    dockOnSelected: Palette.minuit,
    photoBackdrop: Palette.minuit950,
    onPhotoBackdrop: Palette.creme,
    onPhotoBackdropMuted: Color(0x99FDF1DB),
    illustrationSky: Palette.minuit800,
    illustrationMoon: Palette.creme,
    illustrationFarHills: Palette.sarcelle800,
    illustrationNearHills: Palette.sarcelleProfonde,
    illustrationRoad: Palette.minuit400,
  );

  /// Family tones for text and icons on this theme's surfaces.
  final Map<KindFamily, Color> familyText;

  /// How each overnight status is drawn on this theme.
  final Map<OvernightStatus, NightTone> night;

  /// Links and text buttons: navy by day (amber text would not reach the
  /// contrast of body text on cream), amber by night.
  final Color link;

  /// What floats over the map (search pill, chips, buttons).
  final Color floatingSurface;
  final List<BoxShadow> floatingShadow;
  final List<BoxShadow> sheetShadow;

  /// The soft fade at the top of the map, so map labels never touch the
  /// status bar's clock.
  final Color mapScrim;

  /// The floating navigation pill of a phone.
  final Color dockSurface;
  final Color dockForeground;
  final Color dockSelected;
  final Color dockOnSelected;

  /// The full-screen photo viewer.
  final Color photoBackdrop;
  final Color onPhotoBackdrop;
  final Color onPhotoBackdropMuted;

  /// The night landscapes of the empty, offline and error states.
  final Color illustrationSky;
  final Color illustrationMoon;
  final Color illustrationFarHills;
  final Color illustrationNearHills;
  final Color illustrationRoad;

  NightTone nightTone(OvernightStatus status) => night[status]!;

  static LunaTokens of(BuildContext context) => Theme.of(context).extension<LunaTokens>()!;

  @override
  LunaTokens copyWith() => this;

  @override
  LunaTokens lerp(LunaTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return LunaTokens(
      familyText: {for (final f in KindFamily.values) f: c(familyText[f]!, other.familyText[f]!)},
      night: {for (final o in OvernightStatus.values) o: night[o]!.lerp(other.night[o]!, t)},
      link: c(link, other.link),
      floatingSurface: c(floatingSurface, other.floatingSurface),
      floatingShadow: BoxShadow.lerpList(floatingShadow, other.floatingShadow, t)!,
      sheetShadow: BoxShadow.lerpList(sheetShadow, other.sheetShadow, t)!,
      mapScrim: c(mapScrim, other.mapScrim),
      dockSurface: c(dockSurface, other.dockSurface),
      dockForeground: c(dockForeground, other.dockForeground),
      dockSelected: c(dockSelected, other.dockSelected),
      dockOnSelected: c(dockOnSelected, other.dockOnSelected),
      photoBackdrop: c(photoBackdrop, other.photoBackdrop),
      onPhotoBackdrop: c(onPhotoBackdrop, other.onPhotoBackdrop),
      onPhotoBackdropMuted: c(onPhotoBackdropMuted, other.onPhotoBackdropMuted),
      illustrationSky: c(illustrationSky, other.illustrationSky),
      illustrationMoon: c(illustrationMoon, other.illustrationMoon),
      illustrationFarHills: c(illustrationFarHills, other.illustrationFarHills),
      illustrationNearHills: c(illustrationNearHills, other.illustrationNearHills),
      illustrationRoad: c(illustrationRoad, other.illustrationRoad),
    );
  }
}

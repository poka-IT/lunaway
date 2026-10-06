import 'dart:ui';

/// The "Nuit douce" palette: the colours of the logo (brand/README.md) and
/// the tonal ramps derived from them. Screens never read these directly;
/// they read the roles of the colour scheme and of `LunaTokens`, which pick
/// from here per theme.
abstract final class Palette {
  // Minuit: the night sky of the mark. Text on light surfaces; the dark
  // theme's surfaces are its deeper tones.
  static const minuit = Color(0xFF061F43);
  static const minuit950 = Color(0xFF040F22);
  static const minuit925 = Color(0xFF06142A);
  static const minuit900 = Color(0xFF081A33);
  static const minuit850 = Color(0xFF0C213D);
  static const minuit800 = Color(0xFF112845);
  static const minuit750 = Color(0xFF16304F);
  static const minuit700 = Color(0xFF1C385A);
  static const minuit600 = Color(0xFF2B4A70);
  static const minuit500 = Color(0xFF44587A);
  static const minuit400 = Color(0xFF6E7F99);
  static const minuit300 = Color(0xFF97A4B8);
  static const minuit200 = Color(0xFFC3CAD6);

  // Clair de lune: the crescent. Light surfaces derive from it; text on dark.
  static const creme = Color(0xFFFDF1DB);
  static const creme50 = Color(0xFFFFFBF4);
  static const creme100 = Color(0xFFFFF7EA);
  static const creme200 = Color(0xFFFCF1DE);
  static const creme300 = Color(0xFFF8EAD1);
  static const creme400 = Color(0xFFF2E1C3);
  static const creme500 = Color(0xFFEAD6B4);
  static const creme600 = Color(0xFFDCC8A4);
  static const cremeMuted = Color(0xFFCEC8BA);

  // Sarcelle: the hills. Water, services, the secondary accent.
  static const sarcelle = Color(0xFF409FA7);
  static const sarcelleProfonde = Color(0xFF15576D);
  static const sarcelle100 = Color(0xFFD5ECEC);
  static const sarcelle200 = Color(0xFFAED8DA);
  static const sarcelle300 = Color(0xFF7CC2C7);
  static const sarcelle800 = Color(0xFF0F4558);
  static const sarcelle900 = Color(0xFF0A3343);

  // Lanterne: the warm light of a van window at night. The action and the
  // selection, and nothing else, so it always means "this".
  static const lanterne = Color(0xFFF2A541);
  static const lanterne100 = Color(0xFFFDEBD0);
  static const lanterne200 = Color(0xFFFAD8A6);
  static const lanterne700 = Color(0xFF8F5300);
  static const lanterne800 = Color(0xFF6A3D00);
  static const lanterne900 = Color(0xFF4A2B04);

  // Corail: alerts, a forbidden night, a failure.
  static const corail = Color(0xFFE5675A);
  static const corail100 = Color(0xFFFCDDD8);
  static const corail300 = Color(0xFFF2998F);
  static const corail700 = Color(0xFFB23A2E);

  /// Coral dark enough for text on the darkest cream (4.6:1).
  static const corail800 = Color(0xFFA8352A);
  static const corail900 = Color(0xFF5C150E);

  // Family tones of the map pins: four hues apart from the amber of the
  // selection and the coral of the alerts, each dark enough for a cream
  // glyph and light enough to stand on the night basemap.
  static const familyStopovers = Color(0xFF2D5DA8);
  static const familyCampsites = Color(0xFF8A4B82);
  static const familyNature = Color(0xFF4A8A43);
  static const familyServices = Color(0xFF237F89);

  // The same families as text and icon tones on each theme's surfaces.
  static const stopoversOnLight = Color(0xFF244E91);
  static const campsitesOnLight = Color(0xFF7A3F73);
  static const natureOnLight = Color(0xFF356B30);
  static const servicesOnLight = Color(0xFF15606B);
  static const stopoversOnDark = Color(0xFF9DBBEE);
  static const campsitesOnDark = Color(0xFFDDAAD6);
  static const natureOnDark = Color(0xFFA4D39A);
  static const servicesOnDark = Color(0xFF8ED3D9);

  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
}

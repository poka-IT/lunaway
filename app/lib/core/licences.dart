import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licences of what ships inside the app without a package of its own: the
/// typefaces, the icons, the desktop map library and the basemap styles. Package licences reach
/// the licence page by themselves.
void registerBundledLicences() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Atkinson Hyperlegible Next',
    ], await rootBundle.loadString('assets/fonts/atkinson-next-lunaway/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Fraunces',
    ], await rootBundle.loadString('assets/fonts/fraunces/OFL.txt'));
    yield LicenseEntryWithLineBreaks([
      'Phosphor Icons',
    ], await rootBundle.loadString('assets/fonts/phosphor/LICENSE.txt'));
    yield LicenseEntryWithLineBreaks([
      'MapLibre GL JS',
    ], await rootBundle.loadString('assets/map/LICENSE-maplibre-gl.txt'));
    // The Aube and Minuit styles are generated from Protomaps basemaps.
    yield LicenseEntryWithLineBreaks([
      'Protomaps basemaps',
    ], await rootBundle.loadString('assets/map/styles/LICENSE-protomaps-basemaps.md'));
  });
}

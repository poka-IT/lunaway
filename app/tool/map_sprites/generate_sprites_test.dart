// Renders the map pins into app/assets/map/pins/<ratio>x/<id>.png, for every
// pixel ratio the app ships, with the same painter the app's own widgets
// use. Both map engines (maplibre_gl and the desktop web view) load these
// files, so the pins look the same everywhere.
//
// It runs on the Flutter test engine, the one renderer that draws the
// app's fonts and paths exactly as the app does:
//
//   fvm flutter test tool/map_sprites/generate_sprites_test.dart   # from app/
//
// Outside test/, so `flutter test` alone never rewrites the assets.
//
// With LUNAWAY_SPRITE_SHEET_DIR set, it also packs the same pins into a
// MapLibre sprite set (pins.json, pins.png, pins@2x.json, pins@2x.png) in
// that directory, for the tile host (infra/deploy-basemap-assets.sh sprites
// lunaway-pins DIR): a web page can then draw Lunaway's pins by name.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/map/domain/map_geojson.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/features/poi/presentation/poi_map_style.dart';
import 'package:lunaway/shared/map/pin_painter.dart';
import 'package:lunaway/shared/map/sprites.dart';

Future<void> _loadIconFonts() async {
  for (final (family, file) in [
    ('PhosphorFill', 'Phosphor-Fill'),
    ('PhosphorRegular', 'Phosphor-Regular'),
  ]) {
    final loader = FontLoader(family)..addFont(rootBundle.load('assets/fonts/phosphor/$file.ttf'));
    await loader.load();
  }
}

Future<List<int>> _render(Size logical, double ratio, void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio);
  paint(canvas);
  final image = await recorder.endRecording().toImage(
    (logical.width * ratio).round(),
    (logical.height * ratio).round(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

/// Every image: its id, logical size and painter.
List<(String, Size, void Function(Canvas))> _images() => [
  (markedPointImageId, pointMarkerSize, paintPointMarker),
  for (final selected in [false, true])
    for (final kind in PlaceKind.values)
      for (final overnight in OvernightStatus.values)
        (
          pinImageId(kind, overnight, selected: selected),
          PinGeometry(selected: selected).canvas,
          (c) => paintPin(c, kind: kind, overnight: overnight, selected: selected),
        ),
  for (final kind in PoiKind.values)
    for (final (quiet, selected) in [(false, false), (true, false), (false, true)])
      (
        PoiMapStyle.imageId(kind, quiet: quiet, selected: selected),
        PoiPinGeometry(quiet: quiet, selected: selected).canvas,
        (c) => paintPoiPin(c, kind, quiet: quiet, selected: selected),
      ),
  for (final category in PoiCategory.values)
    (PoiMapStyle.dotImageId(category), poiDotSize, (c) => paintPoiDot(c, category)),
  for (final kind in PoiKind.vendingChoices)
    (PoiMapStyle.vendingDotImageId(kind), poiDotSize, (c) => paintPoiVendingDot(c, kind)),
];

/// Packs every image in rows on one sheet at [ratio]; returns the PNG and
/// the MapLibre sprite index.
Future<(List<int>, Map<String, Object>)> _sheet(int ratio) async {
  const rowWidth = 640.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio.toDouble());
  final index = <String, Object>{};
  var x = 0.0;
  var y = 0.0;
  var rowHeight = 0.0;
  for (final (id, size, paint) in _images()) {
    if (x + size.width > rowWidth) {
      x = 0;
      y += rowHeight;
      rowHeight = 0;
    }
    canvas
      ..save()
      ..translate(x, y);
    paint(canvas);
    canvas.restore();
    index[id] = {
      'x': (x * ratio).round(),
      'y': (y * ratio).round(),
      'width': (size.width * ratio).round(),
      'height': (size.height * ratio).round(),
      'pixelRatio': ratio,
    };
    x += size.width;
    if (size.height > rowHeight) rowHeight = size.height;
  }
  final image = await recorder.endRecording().toImage(
    (rowWidth * ratio).round(),
    ((y + rowHeight) * ratio).round(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return (png!.buffer.asUint8List(), index);
}

void main() {
  final sheetDir = Platform.environment['LUNAWAY_SPRITE_SHEET_DIR'];

  testWidgets('packs the pins into a sprite set for the tile host', skip: sheetDir == null, (
    tester,
  ) async {
    await tester.runAsync(() async {
      await _loadIconFonts();
      final dir = Directory(sheetDir!)..createSync(recursive: true);
      for (final (ratio, suffix) in [(1, ''), (2, '@2x')]) {
        final (png, index) = await _sheet(ratio);
        File('${dir.path}/pins$suffix.png').writeAsBytesSync(png);
        File('${dir.path}/pins$suffix.json')
            .writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(index)}\n');
      }
    });
    expect(File('$sheetDir/pins@2x.json').existsSync(), isTrue);
  });

  testWidgets('renders every pin at every pixel ratio', (tester) async {
    await tester.runAsync(() async {
      await _loadIconFonts();
      for (final ratio in PinSprites.ratios) {
        final dir = Directory('assets/map/pins/${ratio}x')..createSync(recursive: true);
        Future<void> write(String id, Size size, void Function(Canvas) paint) async =>
            File('${dir.path}/$id.png')
                .writeAsBytesSync(await _render(size, ratio.toDouble(), paint));

        for (final (id, size, paint) in _images()) {
          await write(id, size, paint);
        }
      }
    });
    expect(
      Directory('assets/map/pins/3x').listSync(),
      hasLength(allPinImageIds().length + PoiMapStyle.allImageIds().length),
    );
  });
}

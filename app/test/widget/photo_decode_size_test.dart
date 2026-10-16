import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/presentation/photo_flow.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/images/cover_sized_image.dart';

/// A photo the user just took decodes at the size it is shown, never at
/// the 2 560 pixels it is sent with (`plan/research/139-memoire-android.md`):
/// whole, it held 19 MB for a thumbnail of 96 by 72 points.

/// A JPEG of [width] by [height] pixels, made once outside the tests' clock.
Uint8List _jpeg(int width, int height) => img.encodeJpg(img.Image(width: width, height: height));

/// The pixels the screen's [Image] of [finder] holds, once decoded.
Future<Size> _decoded(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final raw = tester.widget<RawImage>(
      find.descendant(of: finder, matching: find.byType(RawImage)),
    );
    final image = raw.image;
    if (image != null) return Size(image.width.toDouble(), image.height.toDouble());
  }
  throw StateError('the image never decoded');
}

void main() {
  late Uint8List landscape;
  late Uint8List portrait;

  setUpAll(() {
    landscape = _jpeg(2560, 1920);
    portrait = _jpeg(1920, 2560);
  });

  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('the size that covers a box', () {
    test('a landscape photo meets the box by both sides when they share its shape', () {
      final size = coverSize(2560, 1920, width: 252, height: 189);
      expect((size.width, size.height), (252, 189));
    });

    test('a portrait photo meets the box by its width and overflows it in height', () {
      final size = coverSize(1920, 2560, width: 252, height: 189);
      expect((size.width, size.height), (252, 336));
    });

    test('a photo smaller than the box keeps its own size', () {
      final size = coverSize(200, 150, width: 400, height: 300);
      expect((size.width, size.height), (200, 150));
    });
  });

  testWidgets('a thumbnail of a large photo holds the pixels of its box', (tester) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const box = Size(96, 72);
    await tester.pumpWidget(
      Center(
        child: Image(
          key: const Key('thumb'),
          image: CoverSizedImage.forBox(MemoryImage(portrait), box, 2.625),
          width: box.width,
          height: box.height,
          fit: BoxFit.cover,
        ),
      ),
    );
    final size = await _decoded(tester, find.byKey(const Key('thumb')));
    // 96 points are 252 pixels: the portrait's width against the box, its
    // height overflowing what the box clips.
    expect(size, const Size(252, 336));
  });

  testWidgets("the photo's preview before it is sent decodes at the width it is shown", (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 2.625
      ..physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: PhotoPreview(photo: PreparedPhoto(jpeg: landscape, width: 2560, height: 1920)),
          ),
        ),
      ),
    );
    final shown = tester.getSize(find.byType(AspectRatio).first);
    final size = await _decoded(tester, find.byType(PhotoPreview));
    // To the pixel the box's width rounds to.
    expect(size.width, closeTo(shown.width * 2.625, 1));
    expect(size.width, lessThan(2560));
  });
}

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/contribution_sheets.dart';
import 'package:lunaway/features/community/presentation/photo_flow.dart';
import 'package:lunaway/features/favorites/application/favorites_providers.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/features/profile/application/settings_controller.dart';
import 'package:lunaway/features/profile/data/settings_repository.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/main.dart' as app;
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/widgets/form_sheet.dart';

import 'fixtures/listened.dart';

/// A walk through the community screens of the real app against a real
/// API, for screenshots and as an end-to-end check: the first contribution
/// makes the account, the recovery card, the contributions, the gates of
/// the levels, and at the end the deletion of the account, so the tour
/// leaves nothing behind on the server. Run through
/// `tool/screens/capture.py --test integration_test/community_tour_test.dart`.
///
/// With `LUNAWAY_TOUR_RECOVERY_CODE` (an account of level 2 on a
/// development server) the tour recovers that account instead, shows the
/// forms the levels open (a review, a photo, a new place) and keeps the
/// account.
const _locale = String.fromEnvironment('LUNAWAY_TOUR_LOCALE', defaultValue: 'fr');
const _theme = String.fromEnvironment('LUNAWAY_TOUR_THEME', defaultValue: 'light');
const _tag = String.fromEnvironment('LUNAWAY_TOUR_TAG', defaultValue: 'community');
const _recoveryCode = String.fromEnvironment('LUNAWAY_TOUR_RECOVERY_CODE');

/// With a recovery code: delete the recovered account at the end too (the
/// last run on a development server), not only what the tour sent.
const _deleteRecovered = bool.fromEnvironment('LUNAWAY_TOUR_DELETE_ACCOUNT');
const _area = LatLng(45.90, 6.13);

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Awaits [work] while pumping frames.
Future<T?> pumping<T>(WidgetTester tester, Future<T> work, {int seconds = 30}) async {
  var done = false;
  T? result;
  unawaited(() async {
    try {
      result = await work;
    } on Object catch (e) {
      debugPrint('TOUR work failed: $e');
    } finally {
      done = true;
    }
  }());
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return result;
}

/// Deletes what the account sent (confirmations, problems, reviews, photos,
/// proposed places), then the account, so the tour leaves nothing on the
/// server: a confirmation or a problem outlives its author, anonymised.
Future<void> _deleteAccount(ProviderContainer container) async {
  if (container.read(accountControllerProvider) is! SignedIn) return;
  await _deleteContributions(container);
  await container.read(accountControllerProvider.notifier).delete();
  await container.read(outboxStoreProvider).clear();
  debugPrint('TOUR account deleted');
}

Future<void> _deleteContributions(ProviderContainer container) async {
  final api = container.read(communityApiProvider);
  final mine = await api.recent(first: 50);
  final targets = <(ContributionKind, String)>[
    for (final c in mine.confirmations) (ContributionKind.deleteConfirmation, c.id),
    for (final i in mine.issues) (ContributionKind.deleteIssueReport, i.id),
    for (final r in mine.reviews) (ContributionKind.deleteReview, r.id),
    for (final p in mine.photos) (ContributionKind.deletePhoto, p.id),
    for (final s in mine.submissions) (ContributionKind.deletePlaceSubmission, s.id),
  ];
  for (final (kind, id) in targets) {
    await api.send(kind, {'id': id});
    debugPrint('TOUR deleted ${kind.name} $id');
  }
}

/// Waits until the account read from the device's storage is known.
Future<void> _accountKnown(WidgetTester tester, ProviderContainer container) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (container.read(accountControllerProvider) is AccountLoading &&
      DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> shot(WidgetTester tester, String name) async {
  await settle(tester, const Duration(milliseconds: 1500));
  debugPrint('SHOT $_tag-$name');
  await settle(tester, const Duration(milliseconds: 2500));
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).hitTestable();
  if (finder.evaluate().isEmpty) {
    debugPrint('TOUR no "$text" to tap');
    return;
  }
  await tester.tap(finder.first);
  await settle(tester, const Duration(milliseconds: 800));
}

/// Closes the sheet or dialog on top, as the back gesture does.
Future<void> back(WidgetTester tester) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  await navigator.maybePop();
  await settle(tester, const Duration(milliseconds: 800));
}

/// A landscape drawn here, as the bytes a camera would give.
Future<Uint8List> _picture() async {
  const size = ui.Size(1600, 1200);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      Offset.zero & size,
      ui.Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 1200), [
          const ui.Color(0xFF9CC9E8),
          const ui.Color(0xFFF5D9A8),
        ]),
    )
    ..drawCircle(const Offset(1150, 330), 110, ui.Paint()..color = const ui.Color(0xFFFFF3C4));
  final ground = ui.Path()..moveTo(0, 1200);
  for (var x = 0.0; x <= 1600; x += 40) {
    ground.lineTo(x, 820 - 60 * (x / 1600 - 0.5).abs() * 4);
  }
  ground
    ..lineTo(1600, 1200)
    ..close();
  canvas.drawPath(ground, ui.Paint()..color = const ui.Color(0xFF3F6B4F));
  final image = await recorder.endRecording().toImage(1600, 1200);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('community tour', (tester) async {
    await app.main();
    await settle(tester, const Duration(seconds: 1));
    final container = ProviderScope.containerOf(tester.element(find.byType(LunawayApp)));
    final settings = container.read(settingsProvider.notifier);
    await settings.setLocale(AppLocaleUtils.parse(_locale));
    await settings.setTheme(_theme == 'dark' ? ThemePreference.dark : ThemePreference.light);
    await settings.setFilter(PlaceFilter.none);
    final t = AppLocaleUtils.parse(_locale).buildSync();
    final router = container.read(routerProvider);

    // A device that kept an account from an earlier tour starts without it.
    await _accountKnown(tester, container);
    // A tour that stops half way still cleans up: `flutter test` uninstalls
    // the app afterwards, and the device key with it. After a full tour the
    // container is gone by then, and there is nothing left to do.
    var cleaned = false;
    addTearDown(() async {
      if (cleaned) return;
      try {
        await (_recoveryCode.isEmpty || _deleteRecovered
                ? _deleteAccount(container)
                : _deleteContributions(container))
            .timeout(const Duration(seconds: 60));
      } on Object catch (e) {
        debugPrint('TOUR cleanup failed: $e');
      }
    });
    if (_recoveryCode.isEmpty) {
      await pumping(tester, _deleteAccount(container), seconds: 60);
    }
    if (_recoveryCode.isNotEmpty && container.read(accountControllerProvider) is! SignedIn) {
      await pumping(
        tester,
        container
            .read(accountControllerProvider.notifier)
            .recover(_recoveryCode, revokeOthers: false),
      );
    }

    final ready = DateTime.now().add(const Duration(minutes: 4));
    while (container.read(syncStateProvider).value?.completedAt == null &&
        DateTime.now().isBefore(ready)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    // A map whose style cannot load (a basemap host this machine does not
    // reach) never reports a camera: the tour goes on without moving it.
    final camera = DateTime.now().add(const Duration(seconds: 30));
    while (container.read(viewportProvider) == null && DateTime.now().isBefore(camera)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    final map = container.read(mapControllerProvider);
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'map-france');

    // A place with a name near Annecy.
    final places = await listened(container, mapPlacesProvider.future);
    final near =
        places.where((p) => p.name != null && p.position.distanceTo(_area) < 20000).toList()..sort(
          (a, b) => (b.kind == PlaceKind.motorhomeArea ? 1 : 0).compareTo(
            a.kind == PlaceKind.motorhomeArea ? 1 : 0,
          ),
        );
    final place = near.first;
    container.read(mapFlowProvider.notifier).select(PlaceSelection(place.id));
    if (map != null) await pumping(tester, map.moveTo(place.position, zoom: 13.5));
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'place');

    // "Still there?": two taps; the first contribution makes the account.
    await tapText(tester, t.contribute.stillThere);
    await shot(tester, 'confirm-sheet');
    if (_recoveryCode.isEmpty) {
      await tapText(tester, t.confirmSheet.stillOk);
      await settle(tester, const Duration(seconds: 4));
      await shot(tester, 'welcome');
      await tapText(tester, t.common.later);
    } else {
      await back(tester);
    }

    // The community part of the place: the rating in one tap.
    await tester.dragUntilVisible(
      find.text(t.contribute.yourRating),
      find.byType(PlaceDetailsBody).first,
      const Offset(0, -300),
    );
    await settle(tester, const Duration(milliseconds: 800));
    final star = find.byTooltip(t.contribute.rateStar(n: 4)).first;
    await tester.ensureVisible(star);
    await settle(tester, const Duration(milliseconds: 800));
    await tester.tap(star);
    await settle(tester, const Duration(seconds: 4));
    await shot(tester, 'place-rated');

    // Writing a review: the gate at level 0, the form from level 1.
    await tapText(tester, t.contribute.writeReview);
    await shot(tester, _recoveryCode.isEmpty ? 'gate-review' : 'review-sheet');
    if (_recoveryCode.isNotEmpty) {
      final text = find.byType(TextField).last;
      await tester.ensureVisible(text);
      await settle(tester, const Duration(milliseconds: 500));
      await tester.tap(text);
      await settle(tester, const Duration(milliseconds: 500));
      await tester.enterText(
        text,
        _locale == 'fr'
            ? 'Aire calme au bord du lac, sol plat et bornes propres. Arrivés tard, place trouvée sans peine.'
            : 'A quiet area by the lake, level ground and clean service points. We arrived late and found room.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester, const Duration(seconds: 1));
      // Back to the top of the sheet: the stars and the text together.
      await tester.drag(text, const Offset(0, 600));
      await settle(tester, const Duration(seconds: 1));
      await shot(tester, 'review-sheet-filled');
      await tapText(tester, t.reviewSheet.publish);
      await settle(tester, const Duration(seconds: 4));
      await shot(tester, 'place-reviewed');
    } else {
      await back(tester);
    }

    // A photo: its preview with what publishing it means, then its upload.
    final photo = await pumping(
      tester,
      _picture().then((bytes) => container.read(photoPreparerProvider).prepare(bytes)),
    );
    if (photo != null) {
      final context = tester.element(find.byType(PlaceDetailsBody).first);
      unawaited(
        showFormSheet<bool>(
          context,
          builder: (context, scroll) => PhotoPreview(photo: photo, scrollController: scroll),
        ),
      );
      await shot(tester, 'photo-preview');
      await back(tester);
    }

    // A problem, and a report to the moderators: the sheets, not sent.
    unawaited(
      showIssueSheet(tester.element(find.byType(PlaceDetailsBody).first), placeId: place.id),
    );
    await settle(tester, const Duration(seconds: 1));
    await tapText(tester, t.issueSheet.kind.serviceBroken);
    await shot(tester, 'issue-sheet');
    await back(tester);

    // Adding a place: the point, then the gate or the form.
    final point = LatLng(place.lat + 0.004, place.lon + 0.006);
    container.read(mapFlowProvider.notifier).select(PointSelection(point));
    if (map != null) await pumping(tester, map.moveTo(point));
    await shot(tester, 'point-add');
    await tapText(tester, t.contribute.addPlaceHere);
    await shot(tester, _recoveryCode.isEmpty ? 'gate-add-place' : 'place-form');
    if (_recoveryCode.isNotEmpty) {
      await tapText(tester, t.kind(PlaceKind.parking));
      // The form's own list, held by its element: the heading it is found
      // from scrolls away and is disposed.
      final list = find
          .ancestor(of: find.text(t.placeForm.kind), matching: find.byType(Scrollable))
          .evaluate()
          .first;
      final sheet = find.byElementPredicate((e) => identical(e, list));
      final name = find.widgetWithText(TextFormField, t.placeForm.name);
      // The form is a lazy list: the field is built once scrolled to.
      await tester.scrollUntilVisible(name, 200, scrollable: sheet);
      await tester.ensureVisible(name);
      await settle(tester, const Duration(milliseconds: 500));
      await tester.tap(name);
      await settle(tester, const Duration(milliseconds: 500));
      await tester.enterText(name, 'Parking du belvédère (test)');
      FocusManager.instance.primaryFocus?.unfocus();
      final night = find.text(t.overnightShort(OvernightStatus.tolerated));
      await tester.scrollUntilVisible(night, 200, scrollable: sheet);
      await tester.ensureVisible(night);
      await settle(tester, const Duration(milliseconds: 500));
      await tapText(tester, t.overnightShort(OvernightStatus.tolerated));
      // Back up to the kind and the name for the picture.
      await tester.scrollUntilVisible(name, -200, scrollable: sheet);
      await settle(tester, const Duration(seconds: 1));
      await shot(tester, 'place-form-filled');
    }
    await back(tester);
    container.read(mapFlowProvider.notifier).select(null);
    await settle(tester, const Duration(seconds: 1));

    // The profile with the account, the recovery card, the contributions.
    router.go(AppRoutes.profile);
    await shot(tester, 'profile-account');
    router.go(AppRoutes.recoveryCard);
    await shot(tester, 'recovery-intro');
    if (_recoveryCode.isEmpty) {
      await tapText(tester, t.recovery.make);
      await settle(tester, const Duration(seconds: 4));
      await shot(tester, 'recovery-card');
      final leave = container.read(accountControllerProvider);
      if (leave is SignedIn) router.go(AppRoutes.profile);
      await settle(tester, const Duration(seconds: 1));
      await tapText(tester, t.recovery.done);
    }
    router.go(AppRoutes.contributions);
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'contributions');
    router.go(AppRoutes.devices);
    await settle(tester, const Duration(seconds: 3));
    await shot(tester, 'devices');
    router.go(AppRoutes.muted);
    await shot(tester, 'muted');

    // Favourites follow the account.
    await container.read(favoritesRepositoryProvider).addToDefault(place);
    router.go(AppRoutes.favorites);
    await settle(tester, const Duration(seconds: 6));
    await shot(tester, 'favorites-synced');

    if (_recoveryCode.isEmpty) {
      // The deletion, in two steps, then the profile without an account.
      // The contributions go first, so nothing stays on the server.
      await pumping(tester, _deleteContributions(container), seconds: 60);
      router.go(AppRoutes.deleteAccount);
      await shot(tester, 'delete-account');
      await tester.dragUntilVisible(
        find.text(t.common.next),
        find.byType(Scrollable).last,
        const Offset(0, -300),
      );
      await tapText(tester, t.common.next);
      await shot(tester, 'delete-confirm');
      await tester.tap(find.byType(Checkbox).last);
      await settle(tester, const Duration(milliseconds: 500));
      await tapText(tester, t.deletion.confirm);
      await settle(tester, const Duration(seconds: 5));
      await shot(tester, 'profile-no-account');
      router.go(AppRoutes.recover);
      await settle(tester, const Duration(seconds: 2));
      await tester.enterText(find.byType(TextField).first, '3N9Y Z609 GB9Y');
      await shot(tester, 'recover');
    }
    if (_recoveryCode.isNotEmpty) {
      // The kept account leaves nothing of the tour behind it.
      await pumping(
        tester,
        _deleteRecovered ? _deleteAccount(container) : _deleteContributions(container),
        seconds: 60,
      );
    }
    cleaned = true;
    debugPrint('TOUR DONE');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/presentation/point_details.dart';
import 'package:lunaway/features/places/presentation/place_actions.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/messages.dart';

import '../helpers/pump.dart';
import '../helpers/samples.dart';

/// The surface of the message on screen, without the margins around it.
Rect messageRect(WidgetTester tester) => tester.getRect(
  find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
);

void main() {
  testWidgets('a phone width gets the dock at the bottom, all three tabs in a row', (tester) async {
    await pumpLunaway(tester);
    final map = tester.getCenter(find.text('Carte'));
    final favourites = tester.getCenter(find.text('Favoris'));
    final profile = tester.getCenter(find.text('Profil'));
    expect(map.dy, greaterThan(phone.height * 0.85));
    expect(favourites.dy, map.dy);
    expect(profile.dy, map.dy);
    expect(map.dx < favourites.dx && favourites.dx < profile.dx, isTrue);
    expect(find.text('Lunaway'), findsNothing, reason: 'no brand rail on a phone');
  });

  testWidgets('on a phone the dock gives way to the actions of an open place', (tester) async {
    final app = await pumpLunaway(tester);
    app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(campsite.id));
    await settleShort(tester);
    expect(find.text('Favoris').hitTestable(), findsNothing);
    expect(find.text('Itinéraire').hitTestable(), findsOneWidget);
    app.container(tester).read(mapFlowProvider.notifier).select(null);
    await settleShort(tester);
    expect(find.text('Favoris').hitTestable(), findsOneWidget);
  });

  testWidgets('a message floats above the dock, never over it', (tester) async {
    await pumpLunaway(tester);
    final context = tester.element(find.text('Carte'));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message')));
    await settleShort(tester);
    expect(
      tester.getRect(find.byType(SnackBar)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Carte')).top),
    );
  });

  group("a message never covers the place's actions", () {
    // A narrow phone and large text stack the actions on two rows, the
    // tallest bar; the tablet and the desktop put them at a panel's foot.
    for (final (name, size, scale) in [
      ('phone', phone, 1.0),
      ('narrow phone', const Size(320, 700), 1.0),
      ('phone, large text', phone, 1.6),
      ('tablet', tablet, 1.0),
      ('desktop', desktop, 1.0),
    ]) {
      testWidgets(name, (tester) async {
        final app = await pumpLunaway(tester, size: size, textScale: scale);
        app.container(tester).read(mapFlowProvider.notifier).select(PlaceSelection(campsite.id));
        await settleShort(tester);
        await tester.tap(find.text('Enregistrer').hitTestable());
        await settleShort(tester);
        expect(find.text('Ajouté à Mes favoris'), findsOneWidget);
        final message = messageRect(tester);
        final bar = tester.getRect(find.byType(PlaceActionBar));
        expect(message.bottom, lessThanOrEqualTo(bar.top), reason: '$message over $bar');
        for (final label in ['Itinéraire', 'Enregistré', 'Partager', 'Copier']) {
          final action = tester.getRect(find.text(label).hitTestable());
          expect(message.overlaps(action), isFalse, reason: '$label: $action under $message');
        }
      });
    }

    for (final (name, size) in [('phone', phone), ('tablet', tablet)]) {
      testWidgets('nor those of a long-pressed point, $name', (tester) async {
        // The clipboard answers, as a device's would.
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final app = await pumpLunaway(tester, size: size);
        app
            .container(tester)
            .read(mapFlowProvider.notifier)
            .select(const PointSelection(LatLng(45.8992, 6.1294)));
        await settleShort(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(PointActionBar),
            matching: find.text('Copier les coordonnées'),
          ),
        );
        await settleShort(tester);
        expect(find.byType(SnackBar), findsOneWidget);
        final message = messageRect(tester);
        final bar = tester.getRect(find.byType(PointActionBar));
        expect(message.bottom, lessThanOrEqualTo(bar.top), reason: '$message over $bar');
      });
    }

    testWidgets('a place left open on the map does not lift the messages of another tab', (
      tester,
    ) async {
      final app = await pumpLunaway(tester, size: tablet);
      final selection = app.container(tester).read(mapFlowProvider.notifier);
      Future<double> messageBottom() async {
        showMessage(ScaffoldMessenger.of(tester.element(find.text('Favoris').first)), 'Message');
        await settleShort(tester);
        final bottom = messageRect(tester).bottom;
        ScaffoldMessenger.of(tester.element(find.text('Favoris').first)).clearSnackBars();
        await settleShort(tester);
        return bottom;
      }

      await tester.tap(find.text('Favoris').first);
      await settleShort(tester);
      final withoutPlace = await messageBottom();
      await tester.tap(find.text('Carte').first);
      selection.select(PlaceSelection(campsite.id));
      await settleShort(tester);
      expect(find.byType(PlaceActionBar), findsOneWidget);
      await tester.tap(find.text('Favoris').first);
      await settleShort(tester);
      expect(await messageBottom(), withoutPlace);
    });

    testWidgets('and comes back down once the place is closed', (tester) async {
      final app = await pumpLunaway(tester);
      final selection = app.container(tester).read(mapFlowProvider.notifier)
        ..select(PlaceSelection(campsite.id));
      await settleShort(tester);
      final context = tester.element(find.text('Itinéraire'));
      showMessage(ScaffoldMessenger.of(context), 'Message');
      await settleShort(tester);
      final raised = messageRect(tester).bottom;
      selection.select(null);
      await settleShort(tester);
      final lowered = messageRect(tester).bottom;
      expect(lowered, greaterThan(raised));
      expect(lowered, lessThanOrEqualTo(tester.getRect(find.text('Carte')).top));
    });
  });

  testWidgets('a message with an action leaves by itself', (tester) async {
    await pumpLunaway(tester);
    final context = tester.element(find.text('Carte'));
    showMessage(
      ScaffoldMessenger.of(context),
      'Retiré',
      action: SnackBarAction(label: 'Annuler', onPressed: () {}),
    );
    await settleShort(tester);
    expect(find.text('Annuler'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await settleShort(tester);
    expect(find.text('Retiré'), findsNothing);
  });

  testWidgets('with a screen reader it stays until closed, so the action stays in reach', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      accessibleNavigation: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpLunaway(tester);
    final context = tester.element(find.text('Carte'));
    showMessage(
      ScaffoldMessenger.of(context),
      'Retiré',
      action: SnackBarAction(label: 'Annuler', onPressed: () {}),
    );
    await settleShort(tester);
    await tester.pump(const Duration(seconds: 30));
    await settleShort(tester);
    expect(find.text('Retiré'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await settleShort(tester);
    expect(find.text('Retiré'), findsNothing);
  });

  testWidgets('a tablet width gets a rail on the left with labels', (tester) async {
    await pumpLunaway(tester, size: tablet);
    final map = tester.getCenter(find.text('Carte'));
    final favourites = tester.getCenter(find.text('Favoris'));
    expect(map.dx, lessThan(120));
    expect(favourites.dx, map.dx);
    expect(favourites.dy, greaterThan(map.dy), reason: 'one under the other');
  });

  testWidgets("on its side, the rail grows by the camera cut-out and keeps its labels' room", (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(left: 48);
    await pumpLunaway(tester, size: tablet);
    expect(tester.getCenter(find.text('Carte')).dx, closeTo(48 + 92 / 2, 1));
  });

  testWidgets('a desktop width gets the wide rail with the brand', (tester) async {
    await pumpLunaway(tester, size: desktop);
    expect(find.text('Lunaway'), findsOneWidget);
    expect(tester.getCenter(find.text('Carte')).dx, lessThan(240));
  });

  testWidgets('a screen reader switches tabs from the dock', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLunaway(tester);
    tester.semantics.tap(find.semantics.byLabel('Favoris'));
    await settleShort(tester);
    expect(find.text('Nouvelle liste'), findsOneWidget, reason: 'the favourites are shown');
    semantics.dispose();
  });

  testWidgets('a screen reader switches tabs from the rail', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpLunaway(tester, size: tablet);
    tester.semantics.tap(find.semantics.byLabel('Favoris'));
    await settleShort(tester);
    expect(find.text('Nouvelle liste'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the system back on another tab returns to the map, not out of the app', (
    tester,
  ) async {
    final exits = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'SystemNavigator.pop') exits.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpLunaway(tester);
    await tester.tap(find.text('Favoris'));
    await settleShort(tester);
    expect(find.text('Nouvelle liste'), findsOneWidget);
    final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (_) {},
    );
    await settleShort(tester);
    expect(find.text('Nouvelle liste'), findsNothing);
    expect(find.text('5 lieux ici'), findsOneWidget, reason: 'back on the map');
    expect(exits, isEmpty);
  });

  testWidgets('tapping the current tab again brings its page back to the top', (tester) async {
    await pumpLunaway(tester);
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    final list = find
        .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
        .first;
    double offset() => tester.state<ScrollableState>(list).position.pixels;
    await tester.drag(list, const Offset(0, -600));
    await settleShort(tester);
    expect(offset(), greaterThan(300), reason: 'scrolled down');
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    expect(offset(), 0);
  });

  testWidgets('the destinations are named in the app language', (tester) async {
    await pumpLunaway(tester, locale: AppLocale.en);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}

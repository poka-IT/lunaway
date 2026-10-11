import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/providers.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/presentation/place_placement.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/domain/luna_map.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/poi/presentation/add_vending.dart';
import 'package:lunaway/features/profile/presentation/profile_screen.dart';
import 'package:lunaway/features/vehicle/application/vehicle_providers.dart';
import 'package:lunaway/features/vehicle/data/vehicle_repository.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/features/vehicle/presentation/vehicle_editor.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/widgets/app_form.dart';
import 'package:lunaway/shared/widgets/busy_button.dart';

import '../helpers/fake_api.dart';
import '../helpers/pump.dart';

final Translations t = AppLocale.fr.buildSync();

/// The vehicle's store over the real one, which can fail or keep the
/// user waiting, and counts the saves asked of it.
final class _Store implements VehicleRepository {
  new(this._inner);

  final VehicleRepository _inner;
  bool failing = false;
  Completer<void>? gate;
  int saves = 0;

  @override
  Stream<Vehicle?> watch() => _inner.watch();

  @override
  Future<void> save(Vehicle vehicle) async {
    saves++;
    if (gate case final gate?) await gate.future;
    if (failing) throw StateError('disk full');
    await _inner.save(vehicle);
  }

  @override
  Future<void> clear() => _inner.clear();
}

/// The vehicle editor opened from the profile on a phone, over `store`.
Future<(TestApp, _Store)> _openEditor(WidgetTester tester) async {
  late _Store store;
  final app = await pumpLunaway(
    tester,
    overrides: [
      vehicleRepositoryProvider.overrideWith(
        (ref) => store = _Store(DriftVehicleRepository(ref.watch(userDatabaseProvider))),
      ),
    ],
  );
  await tester.tap(find.text(t.nav.profile).last);
  await settleShort(tester);
  final open = find.text(t.vehicle.add);
  await tester.scrollUntilVisible(
    open,
    200,
    scrollable: find
        .descendant(of: find.byType(ProfileScreen), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await settleShort(tester);
  expect(find.byType(VehicleEditor), findsOneWidget);
  return (app, store);
}

Finder _editorList() =>
    find.descendant(of: find.byType(VehicleEditor), matching: find.byType(Scrollable)).first;

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// Whether the text field labelled [label] has the keyboard's focus.
bool _focused(WidgetTester tester, String label) => tester
    .widget<EditableText>(find.descendant(of: _field(label), matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

Finder _inButton(String label, Finder what) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
  matching: what,
);

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('a form', () {
    testWidgets('Save leads to the first wrong field, sums them up by the button and tells '
        'the screen reader', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        supportsAnnounce: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final (app, _) = await _openEditor(tester);
      final list = _editorList();
      await tester.scrollUntilVisible(_field(t.vehicle.height), 200, scrollable: list);
      await tester.enterText(_field(t.vehicle.height), '29');
      await tester.enterText(_field(t.vehicle.width), '9');
      // Down to the fuel, the height far above.
      await tester.drag(list, const Offset(0, -2000));
      await settleShort(tester);
      expect(_field(t.vehicle.height).hitTestable(), findsNothing, reason: 'out of sight');
      tester.takeAnnouncements();

      await tester.tap(find.text(t.vehicle.save).last);
      await settleShort(tester);

      expect(find.text('2 champs à corriger'), findsOneWidget, reason: 'by the button');
      expect(find.text('Entre 1,20 et 4,50 m'), findsOneWidget, reason: 'under the height');
      expect(find.text('Entre 1,50 et 2,60 m'), findsOneWidget, reason: 'under the width');
      expect(_field(t.vehicle.height).hitTestable(), findsOneWidget, reason: 'scrolled to it');
      expect(_focused(tester, t.vehicle.height), isTrue, reason: 'the first wrong field');
      expect(_focused(tester, t.vehicle.width), isFalse);
      expect(
        tester.takeAnnouncements().map((a) => a.message),
        contains('2 champs à corriger. Hauteur : Entre 1,20 et 4,50 m'),
      );
      expect(app.container(tester).read(vehicleProvider).value, isNull, reason: 'nothing saved');

      // Fixed, each error leaves at the keystroke, and the count with it.
      await tester.enterText(_field(t.vehicle.height), '2,9');
      await tester.pump();
      expect(find.text('Entre 1,20 et 4,50 m'), findsNothing);
      await settleShort(tester);
      expect(find.text('1 champ à corriger'), findsOneWidget);
    });

    testWidgets('a field says nothing until it is left, then its error goes at the keystroke '
        'that fixes it, a point as good as a comma', (tester) async {
      final app = await pumpLunaway(tester);
      await tester.ensureVisible(find.text('Mon véhicule passe'));
      await tester.tap(find.text('Mon véhicule passe'));
      await settleShort(tester);
      final height = _field(t.vehicle.height);
      final weight = _field(t.vehicleHeight.weight);
      expect(find.text(t.vehicleHeight.needed), findsNothing, reason: 'untouched, no error');

      // Into the height and out of it without typing: still nothing.
      await tester.tap(height);
      await tester.pump();
      await tester.tap(weight);
      await tester.pump();
      expect(find.text(t.vehicleHeight.needed), findsNothing);

      await tester.enterText(height, '29');
      await tester.pump();
      expect(find.textContaining('Entre'), findsNothing, reason: 'not while it is typed');
      await tester.tap(weight);
      await tester.pump();
      expect(find.text('Entre 1,20 et 4,50 m'), findsOneWidget, reason: 'left wrong');

      await tester.enterText(height, '2.9');
      await tester.pump();
      expect(find.textContaining('Entre'), findsNothing, reason: 'right at this keystroke');
      await tester.tap(find.text(t.vehicleHeight.apply));
      await settleShort(tester);
      expect(app.container(tester).read(vehicleProvider).value?.heightM, 2.9);
    });

    testWidgets('a failed save keeps what was typed and tries again from the same place', (
      tester,
    ) async {
      final (app, store) = await _openEditor(tester);
      store.failing = true;
      await tester.scrollUntilVisible(_field(t.vehicle.height), 200, scrollable: _editorList());
      await tester.enterText(_field(t.vehicle.height), '3,10');
      await tester.tap(find.text(t.vehicle.save).last);
      await settleShort(tester);
      expect(find.text(t.forms.failed), findsOneWidget);
      expect(find.byType(VehicleEditor), findsOneWidget, reason: 'still open');
      expect(
        tester.widget<TextFormField>(_field(t.vehicle.height)).controller!.text,
        '3,10',
        reason: 'what was typed is kept',
      );

      store.failing = false;
      await tester.tap(find.text(t.common.retry));
      await settleShort(tester);
      expect(find.byType(VehicleEditor), findsNothing, reason: 'saved, it closes');
      expect(find.text(t.vehicle.saved), findsOneWidget, reason: 'and says so');
      expect(app.container(tester).read(vehicleProvider).value?.heightM, 3.1);
    });

    testWidgets('a wrong field folded away opens its fold and takes the focus', (tester) async {
      const at = LatLng(45.91, 6.12);
      final api = FakeApi(level: 2);
      final app = await pumpLunaway(tester, size: const Size(1280, 2400), api: api, signedIn: true);
      app.container(tester).read(mapFlowProvider.notifier).select(const PointSelection(at));
      await settleShort(tester);
      app.map.viewport = MapViewport(
        bounds: GeoBounds(
          south: at.lat - 0.002,
          west: at.lon - 0.003,
          north: at.lat + 0.002,
          east: at.lon + 0.003,
        ),
        center: at,
        zoom: placementZoom,
      );
      await tester.tap(find.text(t.contribute.addPlaceHere));
      await settleShort(tester);
      await tester.tap(find.text(t.placement.confirm));
      await settleShort(tester);

      Future<void> tapShown(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.pump();
        await tester.tap(finder);
        await settleShort(tester);
      }

      await tapShown(find.text(t.kind(PlaceKind.parking)));
      await tester.enterText(_field(t.placeForm.name), 'Parking du lac');
      await tapShown(find.text(t.placeForm.details));
      await tester.ensureVisible(_field(t.placeForm.website));
      await tester.enterText(_field(t.placeForm.website), 'lac.fr');
      await tapShown(find.text(t.placeForm.details));
      expect(_field(t.placeForm.website).hitTestable(), findsNothing, reason: 'folded');

      await tester.tap(find.text(t.placeForm.submitAdd));
      await settleShort(tester);
      expect(find.text(t.placeForm.invalidWebsite), findsOneWidget);
      expect(_field(t.placeForm.website).hitTestable(), findsOneWidget, reason: 'unfolded');
      expect(_focused(tester, t.placeForm.website), isTrue);
      expect(find.text('1 champ à corriger'), findsOneWidget);
      expect(api.operations, isNot(contains('AddPlace')));
    });

    testWidgets('a report without its kind says which choice is missing, and sends nothing', (
      tester,
    ) async {
      final api = FakeApi();
      final app = await pumpLunaway(tester, size: const Size(1280, 2400), api: api);
      app
          .container(tester)
          .read(mapFlowProvider.notifier)
          .select(const PointSelection(LatLng(45.91, 6.12)));
      await settleShort(tester);
      await tester.tap(find.text(t.roadReport.fromMap));
      await settleShort(tester);
      await tester.tap(find.text(t.roadReport.send).last);
      await settleShort(tester);
      expect(find.text(t.roadReport.kindRequired), findsOneWidget);
      expect(find.text('1 champ à corriger'), findsOneWidget);
      expect(await app.container(tester).read(outboxStoreProvider).all(), isEmpty);
    });
  });

  group('a dialog that asks the server', () {
    Future<FakeApi> openPseudonym(WidgetTester tester) async {
      final api = FakeApi();
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      app.container(tester).read(routerProvider).go(AppRoutes.profile);
      await settleShort(tester);
      final edit = find.byTooltip(t.account.editPseudonym);
      await tester.scrollUntilVisible(edit, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(edit);
      await tester.pump();
      await tester.tap(edit);
      await settleShort(tester);
      return api;
    }

    testWidgets('a pseudonym the server refuses is said on the field, kept, and goes once '
        'changed', (tester) async {
      final api = await openPseudonym(tester);
      api.refusedPseudonyms.add('Lien www');
      await tester.enterText(find.byType(TextField), 'Lien www');
      await tester.tap(find.text(t.common.save));
      await settleShort(tester);
      expect(find.text(t.account.pseudonymRefused), findsOneWidget, reason: 'under the field');
      expect(find.text('1 champ à corriger'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'still open');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Lien www');

      await tester.enterText(find.byType(TextField), 'Loutre du Morvan');
      // The error fades into the hint.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(t.account.pseudonymRefused), findsNothing, reason: 'a new name');
      await tester.tap(find.text(t.common.save));
      await settleShort(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(t.account.pseudonymSaved), findsOneWidget);
      expect(api.last('UpdateProfile'), {'pseudonym': 'Loutre du Morvan'});
    });

    testWidgets('while the server is asked, the dialog stays and closes only itself', (
      tester,
    ) async {
      final api = await openPseudonym(tester);
      final hold = api.hold = Completer<void>();
      api.held = {'UpdateProfile'};
      await tester.enterText(find.byType(TextField), 'Loutre du Morvan');
      await tester.tap(find.text(t.common.save));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_inButton(t.common.save, find.byType(CircularProgressIndicator)), findsOneWidget);
      await tester.tap(find.text(t.common.cancel));
      await tester.pump();
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'neither cancel nor the barrier');
      hold.complete();
      await settleShort(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(t.account.title), findsOneWidget, reason: 'the profile is still there');
    });
  });

  testWidgets('the cruise speed, titled by its heading alone, is still named to a screen reader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _openEditor(tester);
    final dropdown = find.byType(DropdownButton<int?>);
    await tester.scrollUntilVisible(dropdown, 200, scrollable: _editorList());
    // The field shows no label of its own: the name comes with the value
    // and the tap, on the one node a screen reader stops on.
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.label.contains(t.vehicle.cruiseTitle) &&
            node.label.contains(t.vehicle.cruiseNone) &&
            node.getSemanticsData().hasAction(SemanticsAction.tap),
      ),
      findsOne,
    );
    semantics.dispose();
  });

  group('a button that waits', () {
    testWidgets('the vehicle saved turns its button within a frame and takes one tap', (
      tester,
    ) async {
      final (_, store) = await _openEditor(tester);
      final gate = store.gate = Completer<void>();
      await tester.tap(find.text(t.vehicle.save).last);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_inButton(t.vehicle.save, find.byType(CircularProgressIndicator)), findsOneWidget);
      await tester.tap(find.text(t.vehicle.save).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(store.saves, 1, reason: 'the second tap does nothing');
      gate.complete();
      await settleShort(tester);
      expect(find.byType(VehicleEditor), findsNothing);
    });

    testWidgets('a vending machine added turns its button and is sent once', (tester) async {
      final api = FakeApi(level: 1);
      final app = await pumpLunaway(tester, size: const Size(1280, 2400), api: api, signedIn: true);
      app
          .container(tester)
          .read(mapFlowProvider.notifier)
          .select(const PointSelection(LatLng(45.91, 6.12)));
      await settleShort(tester);
      final hold = api.hold = Completer<void>();
      api.held = {'AddVendingMachine'};
      final pizza = find.text(t.poi.add.pizza);
      await tester.ensureVisible(pizza);
      await tester.pump();
      await tester.tap(pizza);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(
          of: find.ancestor(of: pizza, matching: find.byType(OutlinedButton)),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(pizza, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(t.outbox.sending), findsOneWidget, reason: 'the wait is said');
      hold.complete();
      await settleShort(tester, const Duration(seconds: 4));
      expect(
        api.operations.where((o) => o == 'AddVendingMachine'),
        hasLength(1),
        reason: 'one machine for two taps',
      );
      expect(find.byType(VendingQuickAdd), findsNothing, reason: 'sent, the point closes');
    });

    testWidgets('a retry after a failed load turns until the answer comes', (tester) async {
      final api = FakeApi()..offline = true;
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      app.container(tester).read(routerProvider).go(AppRoutes.devices);
      await settleShort(tester);
      final retry = find.text(t.common.retry);
      expect(retry, findsOneWidget, reason: 'the list could not be read');
      api
        ..offline = false
        ..held = {'MyDevices'};
      final hold = api.hold = Completer<void>();
      await tester.tap(retry);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.descendant(
          of: find.ancestor(of: retry, matching: find.byType(OutlinedButton)),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason: 'the tap shows at once, and while the list is asked again',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'still asked');
      hold.complete();
      await settleShort(tester);
      expect(retry, findsNothing);
      expect(find.text(t.devices.thisDevice), findsOneWidget);
    });

    testWidgets('past ten seconds the button says the wait goes on', (tester) async {
      final done = Completer<void>();
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: BusyButton(onPressed: () => done.future, label: const Text('Envoyer')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Envoyer'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(t.busy.slow), findsNothing);
      await tester.pump(slowWait);
      expect(find.text(t.busy.slow), findsOneWidget);
      done.complete();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(t.busy.slow), findsNothing);
    });
  });

  group('a car', () {
    testWidgets("is offered first, with a car's typical size, and is saved as a car", (
      tester,
    ) async {
      final (app, _) = await _openEditor(tester);
      final car = find.text(t.vehicle.types.car);
      expect(car, findsOneWidget);
      expect(find.text(t.vehicle.carHint), findsOneWidget, reason: 'what it covers');
      expect(
        tester.getTopLeft(car).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text(t.vehicle.types.van)).dy),
        reason: 'the types go by size, the car first',
      );
      await tester.tap(car);
      await tester.pump();
      String text(String label) => tester.widget<TextFormField>(_field(label)).controller!.text;
      await tester.scrollUntilVisible(_field(t.vehicle.weight), 200, scrollable: _editorList());
      expect(
        (
          text(t.vehicle.height),
          text(t.vehicle.width),
          text(t.vehicle.length),
          text(t.vehicle.weight),
        ),
        ('1,55', '1,85', '4,6', '1,8'),
      );
      await tester.tap(find.text(t.vehicle.save).last);
      await settleShort(tester);
      final saved = app.container(tester).read(vehicleProvider).value!;
      expect(saved.type, VehicleType.car);
      expect((saved.heightM, saved.widthM, saved.lengthM, saved.weightT), (1.55, 1.85, 4.6, 1.8));
      expect(find.text(t.vehicleType(VehicleType.car)), findsWidgets, reason: 'in the profile');
    });
  });

  testWidgets('a caravan is towed under the trailer, which says so, and the profile reads it', (
    tester,
  ) async {
    final (app, _) = await _openEditor(tester);
    final option = find.text('Une remorque ou une caravane');
    await tester.scrollUntilVisible(option, 200, scrollable: _editorList());
    await tester.tap(option);
    await tester.pump();
    await tester.tap(find.text(t.vehicle.save).last);
    await settleShort(tester);
    expect(app.container(tester).read(vehicleProvider).value!.towing, Towing.trailer);
    expect(
      find.textContaining('Une remorque ou une caravane'),
      findsWidgets,
      reason: 'in the profile',
    );
  });

  test('every form field of the shared kit reads a comma and a point alike', () {
    expect(parseDecimal('2,90'), 2.9);
    expect(parseDecimal('2.90'), 2.9);
    expect(parseDecimal(' 2 , 9 '), 2.9);
    expect(parseDecimal(''), isNull);
    expect(parseDecimal('2,,9'), isNull);
  });
}

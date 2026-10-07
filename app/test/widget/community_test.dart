import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/core/router/routes.dart';
import 'package:lunaway/features/account/application/account_providers.dart';
import 'package:lunaway/features/account/presentation/recovery_screens.dart';
import 'package:lunaway/features/community/application/community_providers.dart';
import 'package:lunaway/features/community/data/photo_prepare.dart';
import 'package:lunaway/features/community/data/picture_picker.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/community/domain/contribution.dart';
import 'package:lunaway/features/community/presentation/community_labels.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/places/application/places_providers.dart';
import 'package:lunaway/features/places/data/graphql/operations.dart';
import 'package:lunaway/features/places/data/graphql/place_json.dart';
import 'package:lunaway/features/places/data/sync/sync_service.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/places/presentation/place_details.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

import '../helpers/fake_api.dart';
import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/samples.dart';

final Translations t = AppLocale.fr.buildSync();

/// Opens [place] in the details pane of a tall desktop window, where the
/// whole sheet fits without scrolling, with [api] behind the app.
Future<TestApp> openPlace(
  WidgetTester tester,
  Place place,
  FakeApi api, {
  bool signedIn = false,
  FakeExtrasSource? extras,
  List<Override> overrides = const [],
}) async {
  final app = await pumpLunaway(
    tester,
    size: const Size(1280, 3000),
    api: api,
    signedIn: signedIn,
    extras: extras,
    overrides: overrides,
  );
  app.container(tester).read(selectionProvider.notifier).select(PlaceSelection(place.id));
  await settleShort(tester);
  return app;
}

Finder inDetails(Finder finder) =>
    find.descendant(of: find.byType(PlaceDetailsBody), matching: finder);

/// Taps [finder] and lets the request, its answer and the message pass;
/// the community's follow-up sync waits three seconds.
Future<void> tapAndSend(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await settleShort(tester, const Duration(seconds: 4));
}

void main() {
  testWidgets('the first contribution makes the account with a signed sign-in, then welcomes it', (
    tester,
  ) async {
    final api = FakeApi();
    await openPlace(tester, lakeArea, api);
    expect(api.calls, isEmpty, reason: 'browsing makes no account');

    await tester.tap(inDetails(find.text(t.contribute.stillThere)));
    await settleShort(tester);
    expect(find.text(t.confirmSheet.body), findsOneWidget);
    await tapAndSend(tester, find.text(t.confirmSheet.stillOk));

    // The fake API refuses a signature that does not verify against the
    // key sent: reaching Confirm means the device signed its challenge.
    expect(api.operations.take(3), ['AuthChallenge', 'SignIn', 'Confirm']);
    expect(api.last('SignIn')!['locale'], 'fr');
    // The outbox entry's id as the idempotency key: a replay gets the
    // first answer back.
    expect(api.last('Confirm'), {
      'placeId': lakeArea.id,
      'status': 'STILL_OK',
      'idempotencyKey': isA<String>(),
    });
    expect(api.last('SignIn')!['createIfUnknown'], isTrue, reason: 'the first one may make it');
    expect(api.calls.firstWhere((c) => c.operation == 'Confirm').token, isNotNull);

    expect(find.text(t.account.welcomeTitle), findsOneWidget);
    expect(find.textContaining('Martre du Vercors'), findsWidgets);
  });

  testWidgets('without a network the contribution waits, and leaves when the network is back', (
    tester,
  ) async {
    final api = FakeApi()..offline = true;
    final app = await openPlace(tester, lakeArea, api, signedIn: true);

    await tester.tap(inDetails(find.text(t.contribute.stillThere)));
    await settleShort(tester);
    await tapAndSend(tester, find.text(t.confirmSheet.stillOk));
    expect(find.text(t.outbox.queued), findsOneWidget);
    expect(api.operations, isNot(contains('Confirm')));

    api.offline = false;
    await app.container(tester).read(outboxRunnerProvider.notifier).kick(now: true);
    await settleShort(tester, const Duration(seconds: 4));
    expect(api.operations, contains('Confirm'));
    expect(await app.container(tester).read(outboxStoreProvider).all(), isEmpty);
  });

  testWidgets('a rating is one tap, and a rating alone is removed as a rating', (tester) async {
    final api = FakeApi();
    await openPlace(tester, lakeArea, api, signedIn: true);

    await tapAndSend(tester, inDetails(find.byTooltip(t.contribute.rateStar(n: 4))));
    expect(api.last('Rate'), {'placeId': lakeArea.id, 'stars': 4});

    await tester.tap(inDetails(find.text(t.contribute.deleteRating)));
    await settleShort(tester);
    expect(find.text(t.contribute.deleteRatingTitle), findsOneWidget);
    await tapAndSend(tester, find.text(t.common.delete));
    expect(api.operations, contains('DeleteReview'));
    expect(api.reviews, isEmpty);
  });

  testWidgets('a rating removed while it is being sent is deleted once it lands', (tester) async {
    final api = FakeApi()
      ..hold = Completer<void>()
      ..held = {'Rate'};
    await openPlace(tester, lakeArea, api, signedIn: true, extras: FakeExtrasSource());

    await tester.tap(inDetails(find.byTooltip(t.contribute.rateStar(n: 3))));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(inDetails(find.text(t.contribute.deleteRating)));
    await settleShort(tester);
    await tester.tap(find.text(t.common.delete));
    await settleShort(tester);
    expect(inDetails(find.text(t.contribute.deleteRating)), findsNothing);

    api.hold!.complete();
    await settleShort(tester, const Duration(seconds: 4));
    expect(api.operations, containsAllInOrder(['Rate', 'DeleteReview']));
    expect(api.reviews, isEmpty);
    expect(api.last('Rate'), {'placeId': lakeArea.id, 'stars': 3}, reason: 'no mark sent');
  });

  testWidgets('at level 0 a written review shows its gate first, never the form', (tester) async {
    final api = FakeApi();
    await openPlace(tester, lakeArea, api, signedIn: true);

    await tester.tap(inDetails(find.text(t.contribute.writeReview)));
    await settleShort(tester);
    expect(find.text(t.gate.review), findsOneWidget);
    expect(find.text(t.gate.yourLevel(level: '0')), findsOneWidget);
    expect(find.text(t.account.nextLevel(level: '1')), findsOneWidget);
    expect(find.text(t.reviewSheet.publish), findsNothing);
  });

  testWidgets('from level 1 a review is written, checked for length, and sent with its licence', (
    tester,
  ) async {
    final api = FakeApi(level: 1);
    await openPlace(tester, lakeArea, api, signedIn: true, extras: FakeExtrasSource());
    expect(inDetails(find.text(t.place.noReviews)), findsOneWidget);

    await tester.tap(inDetails(find.text(t.contribute.writeReview)));
    await settleShort(tester);
    expect(find.text(t.reviewSheet.licence), findsOneWidget);
    await tester.tap(find.byTooltip(t.contribute.rateStar(n: 5)).last);
    await tester.enterText(find.byType(TextField).last, 'Calme');
    await tester.tap(find.text(t.reviewSheet.publish));
    await settleShort(tester);
    expect(find.text(t.reviewSheet.tooShort(n: 5)), findsOneWidget);
    expect(api.operations, isNot(contains('WriteReview')));

    await tester.enterText(find.byType(TextField).last, 'Calme et plat, bornes propres.');
    await tapAndSend(tester, find.text(t.reviewSheet.publish));
    final sent = api.last('WriteReview')!;
    expect(sent['placeId'], lakeArea.id);
    expect(sent['stars'], 5);
    expect(sent['text'], 'Calme et plat, bornes propres.');
    expect(sent['lang'], 'fr');
    expect(inDetails(find.text('Calme et plat, bornes propres.')), findsOneWidget);
    expect(inDetails(find.text(t.place.noOtherReviews)), findsOneWidget);
  });

  testWidgets('a problem is reported by its kind, with no position', (tester) async {
    final api = FakeApi();
    await openPlace(tester, lakeArea, api, signedIn: true);

    await tester.tap(inDetails(find.byTooltip(t.contribute.more)).first);
    await settleShort(tester);
    await tester.tap(find.text(t.contribute.reportIssue).last);
    await settleShort(tester);
    await tester.tap(find.text(t.issueSheet.kind.serviceBroken));
    await tester.pump();
    await tapAndSend(tester, find.text(t.issueSheet.send));
    expect(api.last('ReportIssue'), {
      'placeId': lakeArea.id,
      'kind': 'SERVICE_BROKEN',
      'idempotencyKey': isA<String>(),
    });
  });

  group('the account in the profile', () {
    Future<(TestApp, GoRouter)> openProfile(
      WidgetTester tester,
      FakeApi api,
      String route, {
      SyncService? syncService,
      DateTime? recoveryCardAt,
    }) async {
      final app = await pumpLunaway(
        tester,
        api: api,
        signedIn: true,
        syncService: syncService,
        recoveryCardAt: recoveryCardAt,
      );
      final router = app.container(tester).read(routerProvider)..go(route);
      await settleShort(tester);
      return (app, router);
    }

    Future<void> tapVisible(WidgetTester tester, Finder finder) async {
      // The pages are lazy lists: what is far below is not built yet.
      await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await settleShort(tester);
    }

    testWidgets('shows the pseudonym, the level and what the next level needs', (tester) async {
      final api = FakeApi()..confirmations.add({'id': 'x'});
      await openProfile(tester, api, AppRoutes.profile);
      expect(find.text('Martre du Vercors'), findsOneWidget);
      expect(find.text(t.account.level(level: '0')), findsOneWidget);
      expect(find.text(t.account.levelOpens.l0), findsOneWidget);
      expect(find.text(t.account.nextLevel(level: '1')), findsOneWidget);
      expect(find.textContaining("Un compte d'au moins 3 jours"), findsOneWidget);
    });

    testWidgets('a pseudonym is checked on the device, then sent', (tester) async {
      final api = FakeApi();
      await openProfile(tester, api, AppRoutes.profile);
      await tapVisible(tester, find.byTooltip(t.account.editPseudonym));
      await tester.enterText(find.byType(TextField), 'X');
      await tester.tap(find.text(t.common.save));
      await tester.pump();
      expect(find.text(t.account.pseudonymInvalid), findsOneWidget);
      expect(api.operations, isNot(contains('UpdateProfile')));

      await tester.enterText(find.byType(TextField), '  Loutre   du Morvan ');
      await tester.tap(find.text(t.common.save));
      await settleShort(tester);
      expect(api.last('UpdateProfile'), {'pseudonym': 'Loutre du Morvan'});
      expect(find.text('Loutre du Morvan'), findsOneWidget);
    });

    testWidgets('the recovery card asks a fresh sign-in, shows the code once, in groups', (
      tester,
    ) async {
      final api = FakeApi();
      final (app, _) = await openProfile(tester, api, AppRoutes.recoveryCard);
      await tapVisible(tester, find.text(t.recovery.make));
      // The seeded session is an hour old: the server wants a younger one
      // for this action, so the app signs in again first.
      expect(api.operations, containsAllInOrder(['AuthChallenge', 'SignIn', 'CreateRecoveryCode']));
      for (final group in FakeApi.recoveryCode.split('-')) {
        expect(find.text(group), findsOneWidget);
      }
      expect(find.text(t.recovery.shownOnce), findsOneWidget);
      // The server holds the new code from now on, the old one stopped
      // working: the device knows a card exists, whichever way the user
      // leaves the page (the rail, on a desktop).
      final kept = await app.secrets.read('recovery_card');
      expect(kept, testNow.toUtc().toIso8601String());
      expect(
        kept!.contains(FakeApi.recoveryCode.substring(0, 4)),
        isFalse,
        reason: 'the device keeps the date of the card, never its code',
      );

      await tapVisible(tester, find.widgetWithText(OutlinedButton, t.recovery.done));
      expect(find.text(t.recovery.doneBody), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, t.recovery.done));
      await settleShort(tester);
      expect(find.text(t.account.recoveryMade(date: '6 oct. 2026')), findsOneWidget);
    });

    testWidgets('a card left by another way than its button still shows in the profile', (
      tester,
    ) async {
      final api = FakeApi();
      final (_, router) = await openProfile(tester, api, AppRoutes.recoveryCard);
      await tapVisible(tester, find.text(t.recovery.make));
      expect(find.text(t.recovery.shownOnce), findsOneWidget);
      // The rail of a desktop, or a link: the page goes without its button.
      router.go(AppRoutes.profile);
      await settleShort(tester);
      await tester.scrollUntilVisible(
        find.text(t.recovery.title),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(t.account.recoveryMade(date: '6 oct. 2026')), findsOneWidget);
      expect(find.text(t.account.recoveryNone), findsNothing);
    });

    group('the date of the card comes from the server', () {
      Future<void> seeCard(WidgetTester tester) => tester.scrollUntilVisible(
        find.text(t.recovery.title),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      testWidgets('a card made on another device shows here with its date, and is kept', (
        tester,
      ) async {
        final api = FakeApi()..recoveryCodeCreatedAt = DateTime.utc(2026, 9, 1, 12);
        final (app, _) = await openProfile(tester, api, AppRoutes.profile);
        await seeCard(tester);
        expect(find.text(t.account.recoveryMade(date: '1 sept. 2026')), findsOneWidget);
        expect(
          await app.secrets.read('recovery_card'),
          DateTime.utc(2026, 9, 1, 12).toIso8601String(),
          reason: 'offline later, the device still knows the card',
        );
      });

      testWidgets('the server corrects the date this device kept', (tester) async {
        final api = FakeApi()..recoveryCodeCreatedAt = DateTime.utc(2026, 9, 1, 12);
        await openProfile(
          tester,
          api,
          AppRoutes.profile,
          recoveryCardAt: DateTime.utc(2026, 10, 2, 12),
        );
        await seeCard(tester);
        expect(find.text(t.account.recoveryMade(date: '1 sept. 2026')), findsOneWidget);
      });

      testWidgets('an account without a code says so for the account, not for the device', (
        tester,
      ) async {
        await openProfile(tester, FakeApi(), AppRoutes.profile);
        await tester.scrollUntilVisible(
          find.text(t.account.recoveryNoneAccount),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(t.account.recoveryNone), findsNothing);
      });

      testWidgets('a read sent before a new card does not bring back the old card date', (
        tester,
      ) async {
        final old = DateTime.utc(2026, 9, 1, 12);
        final api = FakeApi()..recoveryCodeCreatedAt = old;
        final (app, _) = await openProfile(tester, api, AppRoutes.profile);
        final service = app.container(tester).read(accountServiceProvider);
        api
          ..hold = Completer<void>()
          ..held = {'MyAccount'};
        final reading = service.refresh();
        await tester.pump();
        await service.createRecoveryCode();
        // The read was answered before the new card, with the old date.
        api.recoveryCodeCreatedAt = old;
        api.hold!.complete();
        final read = await reading;
        expect(read.recoveryCode, isNull, reason: 'the answer predates the new card');
        expect(await app.secrets.read('recovery_card'), testNow.toUtc().toIso8601String());
      });

      testWidgets('offline, the date this device kept shows', (tester) async {
        final api = FakeApi()
          ..offline = true
          ..recoveryCodeCreatedAt = DateTime.utc(2026, 9, 1, 12);
        await openProfile(
          tester,
          api,
          AppRoutes.profile,
          recoveryCardAt: DateTime.utc(2026, 10, 2, 12),
        );
        await seeCard(tester);
        expect(find.text(t.account.recoveryMade(date: '2 oct. 2026')), findsOneWidget);
        expect(api.operations, isNot(contains('MyAccount')), reason: 'nothing reached the API');
      });

      testWidgets('an API older than the date is asked without it, and the device date holds', (
        tester,
      ) async {
        final api = FakeApi()
          ..older = true
          ..recoveryCodeCreatedAt = DateTime.utc(2026, 9, 1, 12);
        await openProfile(
          tester,
          api,
          AppRoutes.profile,
          recoveryCardAt: DateTime.utc(2026, 10, 2, 12),
        );
        await seeCard(tester);
        expect(api.olderRefusals, contains('MyAccount'));
        expect(api.operations, contains('MyAccount'), reason: 'its older form went through');
        expect(find.text(t.account.recoveryMade(date: '2 oct. 2026')), findsOneWidget);
      });
    });

    testWidgets('a new card first says it replaces the one made before, whose code stops working', (
      tester,
    ) async {
      final api = FakeApi();
      final (app, _) = await openProfile(
        tester,
        api,
        AppRoutes.recoveryCard,
        recoveryCardAt: DateTime.utc(2026, 9, 1, 12),
      );
      await tapVisible(tester, find.text(t.recovery.make));
      expect(find.text(t.recovery.replaceTitle(date: '1 septembre 2026')), findsOneWidget);
      expect(find.text(t.recovery.replaceBody(date: '1 septembre 2026')), findsOneWidget);
      await tester.tap(find.text(t.recovery.replaceKeep));
      await settleShort(tester);
      expect(api.operations, isNot(contains('CreateRecoveryCode')), reason: 'the old card holds');
      expect(
        await app.secrets.read('recovery_card'),
        DateTime.utc(2026, 9, 1, 12).toIso8601String(),
      );

      await tapVisible(tester, find.text(t.recovery.make));
      await tester.tap(find.text(t.recovery.replaceConfirm));
      await settleShort(tester);
      expect(api.operations, contains('CreateRecoveryCode'));
      expect(await app.secrets.read('recovery_card'), testNow.toUtc().toIso8601String());
    });

    testWidgets('a recovery code is checked as it is typed, then brings the account back', (
      tester,
    ) async {
      final api = FakeApi();
      final app = await pumpLunaway(tester, api: api);
      app.container(tester).read(routerProvider).go(AppRoutes.recover);
      await settleShort(tester);
      final field = find.byType(TextField).first;

      await tester.enterText(field, '2w3y 9gfa');
      await tester.pump();
      expect(find.text(t.recover.remaining(n: 19)), findsOneWidget);

      // One symbol wrong: the check symbol says so before anything is sent.
      await tester.enterText(field, '2W3Y-9GFA-J1DR-1DGC-WVE0-7C88-CF2');
      await tester.pump();
      expect(find.text(t.recover.invalid), findsOneWidget);

      // Lower case, spaces and an O for a zero are read as the card means.
      await tester.enterText(field, '2w3y 9gfa j1dr 1dgc wveo 7c88 cf1');
      await tester.pump();
      expect(find.text(t.recover.valid), findsOneWidget);
      final submit = find.widgetWithText(FilledButton, t.recover.submit);
      await tester.ensureVisible(submit);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      // The keyboard's go key sends it, as the button would.
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('RecoverAccount')!['code'], FakeApi.recoveryCode);
      expect(api.last('RecoverAccount')!['revokeOtherDevices'], isFalse);
      expect(app.container(tester).read(accountControllerProvider), isA<SignedIn>());
      expect(find.text(t.recover.done(name: 'Martre du Vercors')), findsOneWidget);
    });

    testWidgets('deleting the account takes two deliberate steps, then forgets the key', (
      tester,
    ) async {
      final api = FakeApi();
      final feed = FakeChangesSource([]);
      final (app, _) = await openProfile(
        tester,
        api,
        AppRoutes.deleteAccount,
        syncService: SyncService(source: feed, store: _FeedStore()),
      );
      expect(find.text(t.deletion.kept), findsOneWidget);
      await tapVisible(tester, find.text(t.common.next));
      expect(find.text(t.deletion.confirmBody(name: 'Martre du Vercors')), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, t.deletion.confirm);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(confirm);
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.operations, contains('DeleteAccount'));
      expect(api.hasAccount, isFalse);
      expect(app.container(tester).read(accountControllerProvider), isA<NoAccount>());
      expect(await app.secrets.read('device_key'), isNull);
      expect(await app.secrets.read('session'), isNull);
      expect(find.text(t.deletion.done), findsOneWidget);
      // Its ratings, photos and reports leave the places: the feed says how.
      await settleShort(tester, SyncController.afterContribution);
      expect(feed.requests, 1);
    });

    testWidgets('the devices list this one, and another can be removed', (tester) async {
      final api = FakeApi()..addSession('other', 'other-key');
      await openProfile(tester, api, AppRoutes.devices);
      expect(find.text(t.devices.thisDevice), findsOneWidget);
      expect(find.text(t.devices.other), findsOneWidget);
      await tapVisible(tester, find.text(t.devices.revoke));
      await tester.tap(find.widgetWithText(FilledButton, t.devices.revoke));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.operations, contains('RevokeDevice'));
      expect(find.text(t.devices.other), findsNothing);
      expect(find.text(t.devices.revoked), findsOneWidget);
    });

    testWidgets('a muted author comes back in one tap', (tester) async {
      final api = FakeApi()
        ..muted.add((id: '00000000-0000-7000-8000-00000000abcd', pseudonym: 'Grive'));
      final (app, _) = await openProfile(tester, api, AppRoutes.profile);
      await app.container(tester).read(accountControllerProvider.notifier).refresh();
      app.container(tester).read(routerProvider).go(AppRoutes.muted);
      await settleShort(tester);
      expect(find.text('Grive'), findsOneWidget);
      await tester.tap(find.text(t.muted.unmute));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('UnmuteAuthor'), {'id': '00000000-0000-7000-8000-00000000abcd'});
      expect(find.text('Grive'), findsNothing);
      expect(find.text(t.muted.empty), findsOneWidget);
    });

    testWidgets('a device removed from another one forgets the account, and makes no other', (
      tester,
    ) async {
      final api = FakeApi();
      final (app, _) = await openProfile(tester, api, AppRoutes.profile);
      expect(find.text('Martre du Vercors'), findsOneWidget);

      // Removed from another device: its key and session stop working.
      api.revokeAll();
      await app.container(tester).read(accountControllerProvider.notifier).refresh();
      await settleShort(tester, const Duration(seconds: 2));
      // The app signed in without letting the server make an account for a
      // key it no longer knew: nothing was made, nothing had to be deleted.
      expect(api.last('SignIn')!['createIfUnknown'], isFalse);
      expect(api.strangersDeleted, 0);
      expect(api.operations, isNot(contains('DeleteAccount')));
      final state = app.container(tester).read(accountControllerProvider);
      expect(state, isA<NoAccount>().having((s) => s.lost, 'lost', isTrue));
      expect(await app.secrets.read('device_key'), isNull);
      expect(find.text(t.account.lost), findsOneWidget);
      expect(find.text(t.account.recover), findsWidgets);
      // The message leads to the recovery card's screen.
      await tester.tap(
        find.descendant(of: find.byType(SnackBar), matching: find.text(t.account.lostAction)),
      );
      await settleShort(tester);
      expect(find.byType(RecoverScreen), findsOneWidget);
    });

    testWidgets('signing out says what waits, drops it, and creates no account after', (
      tester,
    ) async {
      final api = FakeApi()..offline = true;
      final (app, _) = await openProfile(tester, api, AppRoutes.profile);
      final runner = app.container(tester).read(outboxRunnerProvider.notifier);
      await runner.enqueue(
        ContributionKind.confirm,
        payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
        placeId: lakeArea.id,
      );
      await settleShort(tester);
      final signOut = find.text(t.account.signOut);
      await tester.scrollUntilVisible(signOut, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(signOut);
      await tester.pump();
      await tester.tap(signOut);
      await settleShort(tester);
      expect(find.text(t.account.signOutPending(n: 1)), findsOneWidget);
      api.offline = false;
      await tester.tap(find.widgetWithText(FilledButton, t.account.signOut));
      await settleShort(tester, const Duration(seconds: 2));
      await runner.kick(now: true);
      await settleShort(tester, const Duration(seconds: 2));
      expect(await app.container(tester).read(outboxStoreProvider).all(), isEmpty);
      expect(api.operations, isNot(contains('AuthChallenge')));
      expect(api.operations, isNot(contains('Confirm')));
    });

    testWidgets('a second contribution made while a send is under way is settled when told', (
      tester,
    ) async {
      final api = FakeApi()..hold = Completer<void>();
      final (app, _) = await openProfile(tester, api, AppRoutes.profile);
      final runner = app.container(tester).read(outboxRunnerProvider.notifier);
      // The first one leaves and waits on a slow network.
      await runner.enqueue(
        ContributionKind.confirm,
        payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
        placeId: lakeArea.id,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await runner.enqueue(
        ContributionKind.confirm,
        payload: {'placeId': campsite.id, 'status': 'STILL_OK'},
        placeId: campsite.id,
      );
      int? sentWhenSettled;
      unawaited(
        runner.kick().then(
          (_) => sentWhenSettled = api.operations.where((o) => o == 'Confirm').length,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(sentWhenSettled, isNull);

      api.hold!.complete();
      await settleShort(tester, const Duration(seconds: 4));
      // What `kick` waited for includes the second one: the message the user
      // reads ("sent" or "waiting for the network") says what happened to it.
      expect(sentWhenSettled, 2);
      expect(api.last('Confirm'), {
        'placeId': campsite.id,
        'status': 'STILL_OK',
        'idempotencyKey': isA<String>(),
      });
      expect(await app.container(tester).read(outboxStoreProvider).all(), isEmpty);
    });

    testWidgets('contributions sent together bring one sync, then one follow-up', (tester) async {
      final api = FakeApi()..offline = true;
      final feed = FakeChangesSource([]);
      final (app, _) = await openProfile(
        tester,
        api,
        AppRoutes.profile,
        syncService: SyncService(source: feed, store: _FeedStore()),
      );
      final runner = app.container(tester).read(outboxRunnerProvider.notifier);
      for (final place in [lakeArea, campsite]) {
        await runner.enqueue(
          ContributionKind.confirm,
          payload: {'placeId': place.id, 'status': 'STILL_OK'},
          placeId: place.id,
        );
      }
      await runner.enqueue(
        ContributionKind.reportIssue,
        payload: {'placeId': lakeArea.id, 'kind': 'SERVICE_BROKEN'},
        placeId: lakeArea.id,
      );
      await settleShort(tester);
      expect(feed.requests, 0, reason: 'nothing reached the server');

      api.offline = false;
      await runner.kick(now: true);
      expect(api.operations.where((o) => o == 'Confirm' || o == 'ReportIssue'), hasLength(3));
      await settleShort(tester, SyncController.afterContribution);
      expect(feed.requests, 1);
      await settleShort(tester, SyncController.followUp);
      expect(feed.requests, 2);
      await settleShort(tester, const Duration(minutes: 1));
      expect(feed.requests, 2);
    });

    testWidgets('a contribution waiting for the network is counted in the profile', (tester) async {
      final api = FakeApi()..offline = true;
      final (app, router) = await openProfile(tester, api, AppRoutes.profile);
      await app
          .container(tester)
          .read(outboxRunnerProvider.notifier)
          .enqueue(
            ContributionKind.confirm,
            payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
            placeId: lakeArea.id,
          );
      await settleShort(tester);
      expect(find.text(t.account.pending(n: 1)), findsOneWidget);
      router.go(AppRoutes.contributions);
      await settleShort(tester);
      expect(find.textContaining(t.outbox.waiting), findsOneWidget);
    });
  });
  group('photos', () {
    late _FakePicker picker;
    late List<Override> overrides;
    setUp(() {
      picker = _FakePicker();
      overrides = [
        picturePickerProvider.overrideWithValue(picker),
        photoPreparerProvider.overrideWithValue(const _FakePreparer()),
      ];
    });

    testWidgets('below level 1 the gate shows before any picker', (tester) async {
      final api = FakeApi();
      await openPlace(
        tester,
        lakeArea,
        api,
        signedIn: true,
        extras: FakeExtrasSource(),
        overrides: overrides,
      );
      await tester.tap(inDetails(find.text(t.contribute.firstPhoto)));
      await settleShort(tester);
      expect(find.text(t.gate.photo), findsOneWidget);
      expect(picker.picks, 0);
    });

    testWidgets('a photo is looked at, with its licence and what is removed, then uploaded', (
      tester,
    ) async {
      final api = FakeApi(level: 1);
      await openPlace(
        tester,
        lakeArea,
        api,
        signedIn: true,
        extras: FakeExtrasSource(),
        overrides: overrides,
      );
      await tester.tap(inDetails(find.text(t.contribute.firstPhoto)));
      await settleShort(tester);
      expect(picker.picks, 1, reason: 'no camera offered: straight to the files');
      expect(find.text(t.photoFlow.licence), findsOneWidget);
      expect(find.text(t.photoFlow.stripped), findsOneWidget);
      expect(api.uploads, isEmpty, reason: 'nothing leaves before the user sends it');

      await tapAndSend(tester, find.text(t.photoFlow.send));
      expect(api.uploads, hasLength(1));
      expect(api.uploads.single, _FakePreparer.jpeg);
      expect(api.last('upload'), {'placeId': lakeArea.id});
    });
  });

  group('adding a place', () {
    const point = LatLng(45.91, 6.12);

    Future<TestApp> openPoint(WidgetTester tester, FakeApi api) async {
      final app = await pumpLunaway(tester, size: const Size(1280, 2400), api: api, signedIn: true);
      app.container(tester).read(selectionProvider.notifier).select(const PointSelection(point));
      await settleShort(tester);
      await tester.tap(find.text(t.contribute.addPlaceHere));
      await settleShort(tester);
      return app;
    }

    testWidgets('below level 2 the gate says which level opens it', (tester) async {
      await openPoint(tester, FakeApi(level: 1));
      expect(find.text(t.gate.addPlace), findsOneWidget);
      expect(find.text(t.placeForm.submitAdd), findsNothing);
    });

    testWidgets('from level 2 the form sends the kind, the point and the name', (tester) async {
      final api = FakeApi(level: 2);
      await openPoint(tester, api);
      expect(find.text(t.placeForm.toVerify), findsOneWidget);
      await tester.tap(find.text(t.placeForm.submitAdd));
      await tester.pump();
      expect(find.text(t.placeForm.kindRequired), findsOneWidget);

      await tester.tap(find.text(t.kind(PlaceKind.parking)));
      final name = find.widgetWithText(TextFormField, t.placeForm.name);
      await tester.ensureVisible(name);
      await tester.pump();
      await tester.tap(name);
      await tester.pump();
      await tester.enterText(name, 'Parking du belvédère');
      await tapAndSend(tester, find.text(t.placeForm.submitAdd));
      final input = api.last('AddPlace')!['input']! as Map<String, Object?>;
      expect(input['kind'], 'PARKING');
      expect(input['lat'], point.lat);
      expect(input['lon'], point.lon);
      expect((input['details']! as Map<String, Object?>)['name'], 'Parking du belvédère');
      expect(find.text(t.placeForm.added), findsOneWidget);
    });
  });

  group('reviews by others', () {
    final byGrive = Review(
      id: '00000000-0000-7000-8000-0000000000aa',
      sourceId: communitySourceId,
      rating: 2,
      text: 'Bruyant la nuit, camions dès cinq heures.',
      lang: 'fr',
      authorName: 'Grive',
      authorId: '00000000-0000-7000-8000-0000000000bb',
      createdAt: DateTime.utc(2026, 9, 2),
    );

    testWidgets('a review is reported to the moderators with a reason', (tester) async {
      final api = FakeApi();
      await openPlace(
        tester,
        lakeArea,
        api,
        signedIn: true,
        extras: FakeExtrasSource(reviews: [byGrive]),
      );
      await tester.tap(inDetails(find.byTooltip(t.contribute.more)).last);
      await settleShort(tester);
      await tester.tap(find.text(t.reportSheet.review));
      await settleShort(tester);
      await tester.tap(find.text(t.reportReason(ReportReason.offensive)));
      await tester.pump();
      await tapAndSend(tester, find.text(t.common.send));
      expect(api.last('ReportContent'), {
        'target': 'REVIEW',
        'id': byGrive.id,
        'reason': 'OFFENSIVE',
      });
      expect(find.text(t.reportSheet.sent), findsOneWidget);
    });

    testWidgets('muting an author hides their review at once', (tester) async {
      final api = FakeApi()..authors[byGrive.authorId!] = 'Grive';
      await openPlace(
        tester,
        lakeArea,
        api,
        signedIn: true,
        extras: FakeExtrasSource(reviews: [byGrive]),
      );
      expect(inDetails(find.text(byGrive.text!)), findsOneWidget);
      await tester.tap(inDetails(find.byTooltip(t.contribute.more)).last);
      await settleShort(tester);
      await tester.tap(find.text(t.reportSheet.mute(name: 'Grive')));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, t.reportSheet.muteAuthor));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('MuteAuthor'), {'id': byGrive.authorId});
      expect(inDetails(find.text(byGrive.text!)), findsNothing);
    });
  });
  group('more of the account', () {
    testWidgets('my contributions list what the account sent, and one can be deleted', (
      tester,
    ) async {
      final api = FakeApi();
      api.confirmations.add({
        'id': '00000000-0000-7000-8000-0000000000c1',
        'placeId': lakeArea.id,
        'status': 'STILL_OK',
        'createdAt': '2026-10-05T18:00:00Z',
      });
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      app.container(tester).read(routerProvider).go(AppRoutes.contributions);
      await settleShort(tester);
      expect(find.text(t.mine.confirmations), findsOneWidget);
      expect(find.text(lakeArea.name!), findsOneWidget);

      await tester.tap(find.byTooltip(t.common.delete));
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, t.common.delete));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('DeleteConfirmation'), {'id': '00000000-0000-7000-8000-0000000000c1'});
      expect(find.text(t.mine.empty), findsOneWidget);
    });

    testWidgets('my answers about shops and services are listed, named, and deletable', (
      tester,
    ) async {
      final api = FakeApi();
      api.poiConfirmations
        ..add({
          'id': '00000000-0000-7000-8000-0000000000a1',
          'poiId': '00000000-0000-7000-8000-0000000000b1',
          'stillThere': true,
          'createdAt': '2026-10-05T18:00:00Z',
        })
        ..add({
          'id': '00000000-0000-7000-8000-0000000000a2',
          'poiId': '00000000-0000-7000-8000-0000000000b2',
          'stillThere': false,
          'createdAt': '2026-10-05T19:00:00Z',
        });
      api.poiDetails['00000000-0000-7000-8000-0000000000b1'] = {
        'name': 'Boulangerie du Lac',
        'kind': 'BAKERY',
      };
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      app.container(tester).read(routerProvider).go(AppRoutes.contributions);
      await settleShort(tester);
      expect(find.text(t.mine.poiConfirmations), findsOneWidget);
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
      expect(find.textContaining(t.poi.stillThere), findsOneWidget);
      // The point is gone since: the answer stays, named generically.
      expect(find.text(t.mine.aPoi), findsOneWidget);
      expect(find.textContaining(t.poi.gone), findsOneWidget);

      await tester.tap(find.byTooltip(t.common.delete).first);
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, t.common.delete));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('DeletePoiConfirmation'), {'id': '00000000-0000-7000-8000-0000000000a2'});
      expect(find.text(t.mine.aPoi), findsNothing);
      expect(find.text('Boulangerie du Lac'), findsOneWidget);
    });

    testWidgets('deleting a confirmation drops the waiting request that may have made it', (
      tester,
    ) async {
      final api = FakeApi();
      api.confirmations.add({
        'id': '00000000-0000-7000-8000-0000000000c2',
        'placeId': lakeArea.id,
        'status': 'STILL_OK',
        'createdAt': testNow.toUtc().toIso8601String(),
      });
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      // The request that made it: its answer was lost, it waits to go again.
      final outbox = app.container(tester).read(outboxStoreProvider);
      final entry = await outbox.add(
        ContributionKind.confirm,
        placeId: lakeArea.id,
        payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
      );
      await outbox.markSending(entry!.id);
      await outbox.retryAt(entry.id, testNow.add(const Duration(hours: 1)), uncertain: true);

      app.container(tester).read(routerProvider).go(AppRoutes.contributions);
      await settleShort(tester);
      await tester.tap(find.byTooltip(t.common.delete).first);
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, t.common.delete));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.last('DeleteConfirmation'), {'id': '00000000-0000-7000-8000-0000000000c2'});
      expect(await outbox.all(), isEmpty, reason: 'sent again, it would make it anew');
      expect(api.operations, isNot(contains('Confirm')));
    });

    testWidgets('deleting a confirmation brings the place back unconfirmed from the feed', (
      tester,
    ) async {
      Place confirmed(DateTime? at) => placeFromJson(
        jsonDecode(jsonEncode({...placeToJson(lakeArea), 'lastConfirmedAt': at?.toIso8601String()}))
            as Map<String, dynamic>,
      );
      final api = FakeApi();
      api.confirmations.add({
        'id': '00000000-0000-7000-8000-0000000000c4',
        'placeId': lakeArea.id,
        'status': 'STILL_OK',
        'createdAt': testNow.toUtc().toIso8601String(),
      });
      // What the server's worker wrote once the confirmation was gone.
      final feed = FakeChangesSource([confirmed(null)]);
      final store = _FeedStore();
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 3000),
        api: api,
        signedIn: true,
        places: [
          for (final p in samplePlaces)
            if (p.id == lakeArea.id) confirmed(testNow) else p,
        ],
        syncService: SyncService(source: feed, store: store),
      );
      store.places = app.places;
      final container = app.container(tester);
      container.read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(inDetails(find.text(t.freshness.unconfirmed)), findsNothing);

      container.read(routerProvider).go(AppRoutes.contributions);
      await settleShort(tester);
      await tester.tap(find.byTooltip(t.common.delete).first);
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, t.common.delete));
      await settleShort(tester, const Duration(seconds: 1) + SyncController.afterContribution);
      expect(api.last('DeleteConfirmation'), {'id': '00000000-0000-7000-8000-0000000000c4'});
      expect(app.places.all.firstWhere((p) => p.id == lakeArea.id).lastConfirmedAt, isNull);

      container.read(routerProvider).go(AppRoutes.map);
      container.read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(inDetails(find.text(t.freshness.unconfirmed)), findsOneWidget);
    });

    testWidgets('online, a place read from the API is read again after a contribution to it', (
      tester,
    ) async {
      Place confirmed(DateTime? at) => placeFromJson(
        jsonDecode(jsonEncode({...placeToJson(lakeArea), 'lastConfirmedAt': at?.toIso8601String()}))
            as Map<String, dynamic>,
      );
      final api = FakeApi();
      api.confirmations.add({
        'id': '00000000-0000-7000-8000-0000000000c5',
        'placeId': lakeArea.id,
        'status': 'STILL_OK',
        'createdAt': testNow.toUtc().toIso8601String(),
      });
      // The web: no place on the device, every page read from the API.
      final online = FakeOnlinePlaces([confirmed(testNow)]);
      final app = await pumpLunaway(
        tester,
        size: const Size(1280, 3000),
        api: api,
        signedIn: true,
        places: const [],
        online: online,
      );
      final container = app.container(tester);
      container.read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(inDetails(find.text(t.freshness.unconfirmed)), findsNothing);

      container.read(routerProvider).go(AppRoutes.contributions);
      await settleShort(tester);
      await tester.tap(find.byTooltip(t.common.delete).first);
      await settleShort(tester);
      // What the server's worker writes once the confirmation is gone.
      online.put(confirmed(null));
      await tester.tap(find.widgetWithText(FilledButton, t.common.delete));
      await settleShort(tester, const Duration(seconds: 1) + SyncController.afterContribution);
      expect(api.last('DeleteConfirmation'), {'id': '00000000-0000-7000-8000-0000000000c5'});

      container.read(routerProvider).go(AppRoutes.map);
      container.read(selectionProvider.notifier).select(PlaceSelection(lakeArea.id));
      await settleShort(tester);
      expect(
        inDetails(find.text(t.freshness.unconfirmed)),
        findsOneWidget,
        reason: 'the copy read before the contribution is not shown again',
      );
    });

    testWidgets('a deletion keeps a waiting request when another one is known to have made it', (
      tester,
    ) async {
      final api = FakeApi();
      api.confirmations.add({
        'id': '00000000-0000-7000-8000-0000000000c3',
        'placeId': lakeArea.id,
        'status': 'STILL_OK',
        'createdAt': testNow.toUtc().toIso8601String(),
      });
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      final outbox = app.container(tester).read(outboxStoreProvider);
      final entry = await outbox.add(
        ContributionKind.confirm,
        placeId: lakeArea.id,
        payload: {'placeId': lakeArea.id, 'status': 'STILL_OK'},
      );
      await outbox.markSending(entry!.id);
      await outbox.retryAt(entry.id, testNow.add(const Duration(hours: 1)), uncertain: true);
      // Accepted for an entry that went before: this one did not make it.
      await outbox.claim('00000000-0000-7000-8000-0000000000c3');

      app.container(tester).read(routerProvider).go(AppRoutes.contributions);
      await settleShort(tester);
      await tester.tap(find.byTooltip(t.common.delete).first);
      await settleShort(tester);
      await tester.tap(find.widgetWithText(FilledButton, t.common.delete));
      await settleShort(tester, const Duration(seconds: 2));
      expect((await outbox.all()).map((e) => e.id), [entry.id]);
    });

    testWidgets('signing out without a recovery card warns that the account would be lost', (
      tester,
    ) async {
      final api = FakeApi();
      final app = await pumpLunaway(tester, api: api, signedIn: true);
      app.container(tester).read(routerProvider).go(AppRoutes.profile);
      await settleShort(tester);
      final signOut = find.text(t.account.signOut);
      await tester.scrollUntilVisible(signOut, 200, scrollable: find.byType(Scrollable).first);
      // Brought to the top: at the foot of the list it would sit under the dock.
      await tester.ensureVisible(signOut);
      await tester.pump();
      await tester.tap(signOut);
      await settleShort(tester);
      expect(find.text(t.account.signOutNoCard), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, t.account.signOut));
      await settleShort(tester, const Duration(seconds: 2));
      expect(api.operations, contains('SignOut'));
      expect(app.container(tester).read(accountControllerProvider), isA<NoAccount>());
      expect(await app.secrets.read('device_key'), isNull);
    });

    testWidgets('below level 3 an edit of a place is a proposal for a moderator', (tester) async {
      final api = FakeApi(level: 1);
      await openPlace(tester, lakeArea, api, signedIn: true);
      await tester.tap(inDetails(find.byTooltip(t.contribute.more)).first);
      await settleShort(tester);
      await tester.tap(find.text(t.contribute.proposeEdit).last);
      await settleShort(tester);
      expect(find.text(t.placeForm.proposal), findsOneWidget);
      final name = find.widgetWithText(TextFormField, t.placeForm.name);
      await tester.ensureVisible(name);
      await tester.pump();
      await tester.tap(name);
      await tester.pump();
      await tester.enterText(name, 'Aire du Lac Bleu, entrée nord');
      await tester.ensureVisible(find.text(t.placeForm.submitPropose));
      await tapAndSend(tester, find.text(t.placeForm.submitPropose));
      final sent = api.last('EditPlace')!;
      expect(sent['placeId'], lakeArea.id);
      expect((sent['patch']! as Map<String, Object?>)['name'], 'Aire du Lac Bleu, entrée nord');
      expect(find.text(t.placeForm.proposed), findsOneWidget);
    });

    testWidgets('an emptied phone is cleared, not left as it was', (tester) async {
      final api = FakeApi(level: 1);
      await openPlace(tester, lakeArea, api, signedIn: true);
      await tester.tap(inDetails(find.byTooltip(t.contribute.more)).first);
      await settleShort(tester);
      await tester.tap(find.text(t.contribute.proposeEdit).last);
      await settleShort(tester);
      // The contact fields sit in the folded details.
      if (find.widgetWithText(TextFormField, t.placeForm.phone).evaluate().isEmpty) {
        await tester.ensureVisible(find.text(t.placeForm.details));
        await tester.tap(find.text(t.placeForm.details));
        await settleShort(tester);
      }
      final phone = find.widgetWithText(TextFormField, t.placeForm.phone);
      await tester.ensureVisible(phone);
      await tester.pump();
      await tester.enterText(phone, '');
      await tester.ensureVisible(find.text(t.placeForm.submitPropose));
      await tapAndSend(tester, find.text(t.placeForm.submitPropose));
      final patch = api.last('EditPlace')!['patch']! as Map<String, Object?>;
      expect(patch['clear'], ['PHONE']);
      expect(patch.containsKey('phone'), isFalse);
    });

    testWidgets('favourites kept on the device are synced once the user asks', (tester) async {
      final api = FakeApi();
      final app = await pumpLunaway(tester, api: api);
      app.container(tester).read(routerProvider).go(AppRoutes.favorites);
      await settleShort(tester);
      expect(find.text(t.favoritesSync.local), findsOneWidget);
      await tester.tap(find.text(t.favoritesSync.action));
      await settleShort(tester);
      expect(find.text(t.favoritesSync.body), findsOneWidget);
      await tester.tap(find.text(t.favoritesSync.confirm));
      await settleShort(tester, const Duration(seconds: 4));
      expect(api.operations, containsAllInOrder(['AuthChallenge', 'SignIn']));
      expect(app.container(tester).read(accountControllerProvider), isA<SignedIn>());
      expect(find.textContaining('Gardés avec votre compte'), findsOneWidget);
    });
  });
}

/// A picker with no camera that hands over the same picture each time.
final class _FakePicker implements PicturePicker {
  int picks = 0;

  @override
  bool offers(PictureSource source) => source == PictureSource.gallery;

  @override
  Future<Uint8List?> pick(PictureSource source) async {
    picks++;
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

/// A preparer that returns a fixed small JPEG at once.
final class _FakePreparer implements PhotoPreparer {
  const new();

  static final Uint8List jpeg = img.encodeJpg(img.Image(width: 8, height: 6));

  @override
  Future<PreparedPhoto> prepare(Uint8List original) async =>
      PreparedPhoto(jpeg: jpeg, width: 8, height: 6);
}

/// A sync store that writes what the feed brings into the places the
/// screens read, as the drift store does; its last run ended an hour ago.
final class _FeedStore implements SyncStore {
  FakePlacesRepository? places;
  final _state = MemorySyncStore()
    ..state = SyncState(cursor: '0', completedAt: testNow.subtract(const Duration(hours: 1)));

  @override
  Future<SyncState> stateOf(String region) => _state.stateOf(region);

  @override
  Future<void> beginFullSync(String region) => _state.beginFullSync(region);

  @override
  Future<void> beginDeltaSync(String region) => _state.beginDeltaSync(region);

  @override
  Future<void> applyPage(String region, ChangeSet page) async {
    final into = places;
    if (into != null) page.places.forEach(into.put);
    await _state.applyPage(region, page);
  }

  @override
  Future<int> completeRun(String region, GeoBounds bounds, DateTime at) =>
      _state.completeRun(region, bounds, at);

  @override
  Future<void> reset(String region, GeoBounds bounds) => _state.reset(region, bounds);
}

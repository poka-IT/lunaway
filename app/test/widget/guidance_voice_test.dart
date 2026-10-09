import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/router/router.dart';
import 'package:lunaway/features/navigation/application/guidance_controller.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/data/voice_output.dart';
import 'package:lunaway/features/navigation/domain/route_plan.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/features/navigation/presentation/widgets/voice_mode_icon.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/navigation.dart';
import '../helpers/pump.dart';
import 'navigation_test.dart' show driveFixes, utrillo;

const _full = 'Voix complète';
const _alerts = 'Voix : alertes seulement';
const _muted = 'Voix coupée';

void main() {
  late FakeLocationFeed feed;
  late RecordingVoice voice;
  late MemoryRouteSettings settings;

  /// Fixes along [route] to [toM] metres, a fix every 10 m.
  Future<void> drive(WidgetTester tester, RouteOption route, {required double toM}) async {
    for (final f in driveFixes(route, toM: toM)) {
      feed.send(f);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await settleShort(tester);
  }

  /// The guidance of the drive on a window of [size], driven 100 m.
  Future<TestApp> guide(
    WidgetTester tester, {
    Size size = phone,
    VoiceMode mode = VoiceMode.full,
    VoiceReadiness readiness = VoiceReadiness.ready,
  }) async {
    final plan = routeFixture('limoges_drive');
    feed = FakeLocationFeed(position: plan.routes.first.line.first);
    voice = RecordingVoice(readiness: readiness);
    settings = MemoryRouteSettings(NavigationSettings(voiceMode: mode));
    final app = await pumpLunaway(
      tester,
      size: size,
      overrides: navigationOverrides(
        routes: FakeRouteService([plan]),
        feed: feed,
        engine: LineEngine([plan]),
        voice: voice,
        settings: settings,
      ),
    );
    final container = app.container(tester);
    await container.read(routeSettingsControllerProvider.future);
    await container
        .read(guidanceControllerProvider.notifier)
        .start(
          plan: plan,
          routeIndex: plan.routes.first.index,
          target: utrillo,
          words: TranslatedWording(await AppLocale.fr.build(), DistanceUnits.metric),
        );
    unawaited(container.read(routerProvider).push(NavigationRoutes.guidance));
    await settleShort(tester);
    await drive(tester, plan.routes.first, toM: 100);
    return app;
  }

  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  /// The mode the voice button shows.
  VoiceMode shown(WidgetTester tester) =>
      tester.widget<VoiceModeIcon>(find.byType(VoiceModeIcon)).mode;

  group('the voice button', () {
    testWidgets('each tap moves to the next mode, its icon, its name and what it does read '
        'aloud, with nothing else to open', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await guide(tester);
      GuidanceSession session() => app.container(tester).read(guidanceControllerProvider)!;
      expect(shown(tester), VoiceMode.full);
      expect(find.byTooltip(_full), findsOneWidget);
      expect(tester.takeAnnouncements(), isEmpty);
      for (final (mode, tip, said) in [
        (
          VoiceMode.alerts,
          _alerts,
          'Alertes seulement : la voix ne parle que pour les radars, les dangers et les '
              "changements d'itinéraire.",
        ),
        (VoiceMode.muted, _muted, "Voix coupée : tout s'affiche à l'écran, sans aucun son."),
        (VoiceMode.full, _full, 'Voix complète : toutes les instructions et les alertes.'),
      ]) {
        await tester.tap(find.byType(VoiceModeIcon));
        await tester.pump();
        expect(shown(tester), mode);
        expect(find.byTooltip(tip), findsOneWidget);
        expect(session().voiceMode, mode);
        expect(tester.takeAnnouncements().map((a) => a.message), [said]);
        await settleShort(tester);
        expect(settings.value.voiceMode, mode, reason: 'kept for the next guidance');
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
      }
      semantics.dispose();
    });

    testWidgets('a screen reader hears the mode as the name and the next one as the hint', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await guide(tester, mode: VoiceMode.alerts);
      expect(
        tester.getSemantics(find.byType(VoiceModeIcon)),
        matchesSemantics(
          tooltip: _alerts,
          hint: 'Couper la voix',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a guidance starts in the mode chosen last', (tester) async {
      await guide(tester, mode: VoiceMode.muted);
      expect(shown(tester), VoiceMode.muted);
      expect(find.byTooltip(_muted), findsOneWidget);
      await drive(tester, routeFixture('limoges_drive').routes.first, toM: 900);
      expect(voice.calls, isEmpty);
    });

    for (final (name, size) in [
      ('a phone', phone),
      ('a phone on its side', const Size(860, 400)),
      ('a tablet', tablet),
      ('a computer', desktop),
    ]) {
      testWidgets('on $name it shows whole, on the map, at the head of its column', (tester) async {
        await guide(tester, size: size, mode: VoiceMode.alerts);
        expect(tester.takeException(), isNull, reason: 'no overflow');
        final button = tester.getRect(find.byTooltip(_alerts));
        expect(button.width, greaterThanOrEqualTo(48));
        expect(button.height, greaterThanOrEqualTo(48));
        expect((Offset.zero & size).contains(button.topLeft), isTrue);
        expect((Offset.zero & size).contains(button.bottomRight), isTrue);
        for (final other in ['Lieux sur la carte', 'Tout le trajet']) {
          final rect = tester.getRect(find.byTooltip(other));
          expect(rect.top, greaterThan(button.bottom), reason: 'under the voice: $other');
        }
        await tester.tap(find.byTooltip(_alerts));
        await settleShort(tester);
        expect(find.byTooltip(_muted).hitTestable(), findsOneWidget);
      });
    }
  });

  group('the notice of a missing voice', () {
    testWidgets('shows in alerts only, the voice being wanted', (tester) async {
      await guide(tester, mode: VoiceMode.alerts, readiness: VoiceReadiness.none);
      expect(find.textContaining('Aucune voix en français'), findsOneWidget);
    });

    testWidgets('goes once the voice is muted', (tester) async {
      await guide(tester, mode: VoiceMode.alerts, readiness: VoiceReadiness.none);
      await tester.tap(find.byTooltip(_alerts));
      await settleShort(tester);
      expect(find.textContaining('Aucune voix en français'), findsNothing);
    });
  });

  testWidgets('the profile offers the three modes and says what the one chosen does', (
    tester,
  ) async {
    final store = MemoryRouteSettings();
    await pumpLunaway(
      tester,
      size: const Size(1280, 2400),
      overrides: navigationOverrides(routes: FakeRouteService(const []), settings: store),
    );
    await tester.tap(find.text('Profil').last);
    await settleShort(tester);
    expect(find.text('Voix du guidage'), findsOneWidget);
    for (final label in ['Complète', 'Alertes', 'Coupée']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    const fullHint = "Les instructions et les alertes, avec la voix de l'appareil.";
    expect(find.text(fullHint), findsOneWidget);
    for (final (label, mode, hint) in [
      (
        'Alertes',
        VoiceMode.alerts,
        'Seulement les radars et zones de danger, les fermetures, travaux et gabarits '
            "limités qui approchent, et les changements d'itinéraire, après un court signal.",
      ),
      (
        'Coupée',
        VoiceMode.muted,
        "Aucun son : les instructions et les alertes s'affichent à l'écran.",
      ),
      ('Complète', VoiceMode.full, fullHint),
    ]) {
      await tester.tap(find.text(label));
      await settleShort(tester);
      expect(store.value.voiceMode, mode);
      expect(find.text(hint), findsOneWidget, reason: label);
    }
  });
}

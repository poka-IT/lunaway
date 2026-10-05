import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/app.dart';
import 'package:lunaway/i18n/strings.g.dart';

Future<void> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(child: TranslationProvider(child: const LunawayApp())));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.en));

  testWidgets('a phone width gets the bottom navigation bar', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a desktop width gets the extended rail', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
  });

  testWidgets('switching to French from the profile translates the navigation', (tester) async {
    await pumpApp(tester, const Size(400, 800));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(find.text('Carte'), findsOneWidget);
    expect(find.text('Profil'), findsWidgets);
  });
}

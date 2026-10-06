import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/i18n/strings.g.dart';

import '../helpers/pump.dart';

void main() {
  testWidgets('a phone width gets the bottom navigation bar', (tester) async {
    await pumpLunaway(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('a tablet width gets a rail with labels', (tester) async {
    await pumpLunaway(tester, size: tablet);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isFalse);
    expect(rail.labelType, NavigationRailLabelType.all);
  });

  testWidgets('a desktop width gets the extended rail with the brand', (tester) async {
    await pumpLunaway(tester, size: desktop);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
    expect(find.text('Lunaway'), findsOneWidget);
  });

  testWidgets('the destinations are named in the app language', (tester) async {
    await pumpLunaway(tester, locale: AppLocale.en);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });
}

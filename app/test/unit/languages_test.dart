import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/plural_rules.dart';
import 'package:lunaway/features/navigation/domain/route_settings.dart';
import 'package:lunaway/features/navigation/presentation/navigation_texts.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// What each of the app's six languages needs beyond its translations.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app speaks six languages, each with the router language of its own', () {
    expect(AppLocale.values.map((l) => l.languageCode).toSet(), {
      'fr',
      'en',
      'de',
      'es',
      'it',
      'nl',
    });
    for (final locale in AppLocale.values) {
      final route = RouteLanguage.of(locale.languageCode);
      expect(
        route.name,
        locale.languageCode,
        reason: 'instructions in the language of the screens',
      );
      expect(route.speechTag, startsWith('${locale.languageCode}-'));
      expect(RouteLanguage.fromWire(route.name.toUpperCase()), route);
    }
  });

  test('every offline map and every French region is named in each language, '
      "never in the server's French or English", () {
    final ids = (jsonDecode(File('assets/map/offline/regions.json').readAsStringSync()) as Map).keys
        .cast<String>();
    expect(ids, contains('fr-bre'));
    for (final locale in AppLocale.values) {
      final t = locale.buildSync();
      for (final id in ids) {
        expect(t.areaName(id, fallback: '?'), isNot('?'), reason: '$id in ${locale.languageCode}');
      }
      // The sync regions name Corsica by its INSEE code.
      expect(t.areaName('FR-20R', fallback: '?'), t.areas.cor);
    }
  });

  test("a list of countries reads in the order of the reader's alphabet", () {
    final de = AppLocale.de.buildSync();
    final list = de.countryList(['NL', 'AT', 'BE']);
    // Österreich among the O, not after the Z.
    expect(
      list,
      [de.countries.be, de.countries.nl, de.countries.at].join(', '),
      reason: 'Belgien, Niederlande, Österreich',
    );
    expect(sortKey('Österreich'), 'osterreich');
    expect(sortKey('Île-de-France'), 'ile-de-france');
  });

  test('iOS and macOS declare each language and give every permission reason in it', () {
    for (final platform in ['ios', 'macos']) {
      final plist = File('$platform/Runner/Info.plist').readAsStringSync();
      final project = File('$platform/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final reasons = RegExp(r'<key>(NS\w+UsageDescription)</key>')
          .allMatches(plist)
          .map((m) => m.group(1)!)
          .toSet();
      expect(reasons, isNotEmpty);
      for (final locale in AppLocale.values) {
        final code = locale.languageCode;
        expect(
          plist,
          contains('<string>$code</string>'),
          reason: '$platform CFBundleLocalizations',
        );
        expect(project, contains('path = $code.lproj/InfoPlist.strings;'), reason: platform);
        final strings = File('$platform/Runner/$code.lproj/InfoPlist.strings').readAsStringSync();
        for (final key in reasons) {
          expect(strings, contains('"$key" = "'), reason: '$platform $code $key');
        }
      }
    }
  });

  test('Dutch plurals follow the Dutch rule, without slang guessing', () async {
    final printed = <String>[];
    await runZoned(() async {
      await registerPluralRules();
      await LocaleSettings.setLocale(AppLocale.nl);
      final nl = LocaleSettings.instance.currentTranslations;
      expect(nl.favorites.count(n: 1), isNot(nl.favorites.count(n: 2)));
      expect(nl.favorites.count(n: 1), contains('1'));
      expect(nl.navigation.voice.kilometres(count: 1.5, n: '1,5'), contains('1,5'));
    }, zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)));
    expect(printed, isEmpty, reason: 'slang prints an error for a language without a rule');
    expect(dutchCardinal(1, one: 'one', other: 'other'), 'one');
    expect(dutchCardinal(1.5, one: 'one', other: 'other'), 'other');
    expect(dutchCardinal(0, zero: 'zero', one: 'one', other: 'other'), 'zero');
    expect(dutchCardinal(0, one: 'one', other: 'other'), 'other');
    await LocaleSettings.setLocale(AppLocale.fr);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/config/app_config.dart';
import 'package:lunaway/i18n/strings.g.dart';

void main() {
  test('every language of the app opens the site in its own language, French at the root', () {
    expect(
      AppConfig.sitePage('fr', 'privacy').toString(),
      'https://lunaway.net/privacy',
    );
    expect(AppConfig.sitePage('fr', '').toString(), 'https://lunaway.net/');
    for (final locale in AppLocale.values.where(
      (l) => l.languageCode != 'fr',
    )) {
      final code = locale.languageCode;
      expect(
        AppConfig.sitePage(code, 'account/delete').toString(),
        'https://lunaway.net/$code/account/delete',
      );
      expect(
        AppConfig.sitePage(code, '').toString(),
        'https://lunaway.net/$code/',
      );
    }
  });

  test('the deletion address the app shows is the page it opens', () {
    for (final locale in AppLocale.values) {
      final shown = locale.buildSync().deletion.webLink;
      final opened = AppConfig.sitePage(locale.languageCode, 'account/delete');
      expect('https://$shown', opened.toString(), reason: locale.languageCode);
    }
  });
}

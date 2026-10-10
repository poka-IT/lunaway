import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/places/domain/place_content.dart';

LocalizedText _in(String lang) => LocalizedText(lang: lang, text: 'text $lang', sourceId: 'extcom');

void main() {
  group('the languages of a description', () {
    test("the reader's first, then the app's in their order, then the others by code", () {
      final texts = [_in('pt'), _in('nl'), _in('fr'), _in('de'), _in('ca'), _in('en')];
      expect(descriptionLanguages(texts, 'de'), ['de', 'fr', 'en', 'nl', 'ca', 'pt']);
      expect(descriptionLanguages(texts, 'fr'), ['fr', 'en', 'de', 'nl', 'ca', 'pt']);
    });

    test('each once, and none for a text of unknown language', () {
      final texts = [
        _in('en'),
        const LocalizedText(lang: 'en', text: 'another source', sourceId: 'osm'),
        _in('und'),
        _in(''),
      ];
      expect(descriptionLanguages(texts, 'fr'), ['en']);
    });
  });

  group('the description shown', () {
    final texts = [_in('de'), _in('en'), _in('fr')];

    test("the reader's language until another is picked", () {
      expect(descriptionPicked(texts, 'fr', null)!.text.lang, 'fr');
      final picked = descriptionPicked(texts, 'fr', 'de')!;
      expect(picked.text.lang, 'de');
      expect(picked.inUserLanguage, isFalse);
    });

    test('a language no source wrote falls back to the usual choice', () {
      expect(descriptionPicked(texts, 'it', 'es')!.text.lang, 'en');
      expect(descriptionPicked(const [], 'fr', 'de'), isNull);
    });
  });
}

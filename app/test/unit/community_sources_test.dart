import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/source_names.dart';

void main() {
  final t = AppLocale.fr.buildSync();

  test("both of Lunaway's sources are its users': the places' and the reviews' and photos'", () {
    expect(isLunawayCommunity('community'), isTrue);
    expect(isLunawayCommunity('community-cc-by'), isTrue);
    expect(isLunawayCommunity('osm'), isFalse);
    expect(isLunawayCommunity('communityx'), isFalse);
  });

  test('a review or a photo of Lunaway users names its CC BY 4.0 licence, a place source not', () {
    expect(sourceName(t, 'community-cc-by'), 'Lunaway');
    expect(itemSourceLabel(t, 'community-cc-by'), 'Lunaway · CC BY 4.0');
    expect(itemSourceLabel(t, 'community'), 'Lunaway');
    expect(itemSourceLabel(t, 'osm'), 'OpenStreetMap');
  });

  test('an edit that empties fields sends them to clear, and counts as a change', () {
    const edit = PlaceDetails(clear: {PlaceField.website, PlaceField.phone});
    expect(edit.isEmpty, isFalse);
    expect(edit.toInput(), {
      'clear': ['WEBSITE', 'PHONE'],
    });
    expect(const PlaceDetails().toInput(), isEmpty, reason: 'nothing to clear, no key');
  });
}

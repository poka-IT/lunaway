import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/favorites/domain/saved_point.dart';
import 'package:lunaway/features/favorites/presentation/point_saving.dart';
import 'package:lunaway/features/places/domain/address_match.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/i18n/strings.g.dart';

const _segur = AddressMatch(
  kind: AddressKind.houseNumber,
  name: '20 Avenue de Ségur',
  postcode: '75007',
  city: 'Paris',
  context: '75, Paris, Île-de-France',
  position: LatLng(48.850699, 2.308628),
  sourceId: 'ban',
  attribution: 'Base Adresse Nationale, IGN Géoplateforme',
);

SavedPoint _point({String name = 'Chez Paul', String? note}) => SavedPoint.normalized(
  id: savedPointIdAt(const LatLng(45, 6)),
  kind: SavedPointKind.point,
  name: name,
  fallback: 'Point',
  position: const LatLng(45, 6),
  note: note,
);

void main() {
  setUp(() => LocaleSettings.setLocale(AppLocale.fr));

  group('the id of a saved point', () {
    test('is the same for the same position on every device, and a UUID the API takes', () {
      final a = savedPointIdAt(const LatLng(48.850699, 2.308628));
      expect(a, savedPointIdAt(const LatLng(48.8506994, 2.3086281)), reason: 'to the micro-degree');
      expect(a, isNot(savedPointIdAt(const LatLng(48.850698, 2.308628))));
      expect(
        a,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
        reason: 'version 8, RFC variant',
      );
    });

    test("a shop's is its own, apart from a point at its position", () {
      expect(savedPoiPointId('poi-1'), savedPoiPointId('poi-1'));
      expect(savedPoiPointId('poi-1'), isNot(savedPoiPointId('poi-2')));
      expect(savedPoiPointId('poi-1'), isNot(savedPointIdAt(const LatLng(45, 6))));
    });
  });

  group('a point is folded as the server keeps it', () {
    test('a name on one line, its spaces folded, cut at 120 characters', () {
      expect(_point(name: '  Chez\n  Paul \t le  pêcheur ').name, 'Chez Paul le pêcheur');
      expect(_point(name: 'é' * 121).name, 'é' * 120);
      expect(_point(name: '😀' * 121).name.runes.length, 120, reason: 'whole characters');
    });

    test('an empty name takes the one proposed', () {
      expect(_point(name: '   ').name, 'Point');
    });

    test('a note keeps its line breaks, loses its stray ends and controls', () {
      expect(_point(note: '  Portail vert\r\ncode 1234 \u0007').note, 'Portail vert\ncode 1234');
      expect(_point(note: '  ').note, isNull);
      expect(_point(note: 'a' * 281).note, 'a' * 280);
    });

    test('the marks that turn the text around are dropped', () {
      expect(_point(name: 'Chez\u202ePaul').name, 'Chez Paul');
    });

    test('a shop without its point of interest is a bare point', () {
      final p = SavedPoint.normalized(
        id: 'x',
        kind: SavedPointKind.poi,
        name: 'Boulangerie',
        fallback: 'Boulangerie',
        position: const LatLng(45, 6),
      );
      expect(p.kind, SavedPointKind.point);
    });

    test('a rename keeps the id and folds the same way; an empty name keeps the old one', () {
      final p = _point();
      final renamed = p.renamed('  Aire  du lac ', ' Calme ');
      expect((renamed.id, renamed.name, renamed.note), (p.id, 'Aire du lac', 'Calme'));
      expect(p.renamed('', null).name, 'Chez Paul');
      expect(renamed.fingerprint, isNot(p.fingerprint));
      expect(p.renamed('Chez Paul', null), p, reason: 'nothing changed');
    });
  });

  group('what a card proposes to save', () {
    final t = AppLocale.fr.buildSync();

    test('an address: its name, its line, its kind', () {
      final p = pointDraft(t, _segur.position, now: DateTime(2026, 10, 10), address: _segur);
      expect(p.kind, SavedPointKind.address);
      expect(p.name, '20 Avenue de Ségur');
      expect(p.address, '20 Avenue de Ségur, 75007 Paris, 75, Paris, Île-de-France');
      expect(p.id, savedPointIdAt(_segur.position));
    });

    test('a town: its name, and its postcode as the line', () {
      const annecy = AddressMatch(
        kind: AddressKind.town,
        name: 'Annecy',
        postcode: '74000',
        position: LatLng(45.9, 6.12),
        sourceId: 'ban',
        attribution: 'BAN',
      );
      final p = pointDraft(t, annecy.position, now: DateTime(2026, 10, 10), address: annecy);
      expect((p.kind, p.name, p.address), (SavedPointKind.town, 'Annecy', '74000'));
    });

    test('a bare point: the day it is saved, in the language', () {
      final p = pointDraft(t, const LatLng(45, 6), now: DateTime(2026, 10, 10, 9));
      expect((p.kind, p.name, p.address), (SavedPointKind.point, 'Point du 10 oct.', null));
      final en = pointDraft(
        AppLocale.en.buildSync(),
        const LatLng(45, 6),
        now: DateTime(2026, 10, 10, 9),
      );
      expect(en.name, 'Point from Oct 10');
    });

    test('a shop: its name, else its kind, with its point of interest', () {
      const bakery = PoiFeature(
        id: 'poi-1',
        kind: PoiKind.bakery,
        position: LatLng(45.1, 6.1),
        name: 'Boulangerie du Lac',
      );
      final p = poiDraft(t, bakery);
      expect(
        (p.kind, p.name, p.poiId, p.poiKind),
        (SavedPointKind.poi, 'Boulangerie du Lac', 'poi-1', PoiKind.bakery),
      );
      expect(p.id, savedPoiPointId('poi-1'));
      const unnamed = PoiFeature(id: 'poi-2', kind: PoiKind.bakery, position: LatLng(45, 6));
      expect(poiDraft(t, unnamed).name, 'Boulangerie');
    });
  });
}

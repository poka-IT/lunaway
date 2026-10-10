import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/map/application/map_flow.dart';
import 'package:lunaway/features/map/application/map_history.dart';
import 'package:lunaway/features/map/application/map_state.dart';
import 'package:lunaway/features/map/application/selection_trail.dart';
import 'package:lunaway/features/poi/domain/poi.dart';

/// A tab's history that records what it was asked, the map shown at
/// [address] in a browser unless said.
final class _History implements MapHistory {
  bool browser = true;
  @override
  bool mapShown = true;
  @override
  MapLink address = MapLink.none;
  @override
  bool onOwnEntry = true;

  final writes = <String>[];

  @override
  bool get writesAddresses => browser && mapShown;

  @override
  bool get onBareMap => !browser || (mapShown && address.isNone);

  @override
  void whenSettled(VoidCallback then) => then();

  @override
  void pushMap(MapLink link) {
    writes.add('push $link');
    address = link;
  }

  @override
  void replaceMap(MapLink link) {
    writes.add('replace $link');
    address = link;
  }

  @override
  void back(int steps) => writes.add('back $steps');

  @override
  void goToMap(MapLink link) => writes.add('go $link');

  @override
  void pushPage(String location, {Object? extra}) => writes.add('page $location');

  @override
  void replacePage(String location, {Object? extra}) => writes.add('replace page $location');

  @override
  void leavePage() => writes.add('leave page');

  @override
  void popupOpened(Route<dynamic> popup) {}

  @override
  void popupClosed(Route<dynamic> popup) {}
}

const _place = PlaceSelection('place-a');
const _other = PlaceSelection('place-b');
const _point = PointSelection(LatLng(45.9, 6.12));

void main() {
  late _History history;
  late ProviderContainer container;

  MapFlow flow() => container.read(mapFlowProvider.notifier);
  MapSelection? open() => container.read(selectionProvider);
  int revision() => container.read(mapFlowProvider).revision;

  setUp(() {
    history = _History();
    container = ProviderContainer.test(overrides: [mapHistoryProvider.overrideWithValue(history)]);
  });

  group('a choice on the map screen', () {
    test('the first takes an entry over the bare map, the next takes its place', () {
      flow().select(_place);
      flow().select(_other);
      expect(open(), _other);
      expect(history.writes, ['push /map?place=place-a', 'replace /map?place=place-b']);
    });

    test('a close goes back to the bare map through the entries the map wrote', () {
      flow().select(_place);
      flow().select(null);
      expect(open(), isNull);
      expect(history.writes.last, 'back 1');
    });

    test('a close from an entry the map did not write takes a new one, the way back from it', () {
      flow().select(_place);
      history.onOwnEntry = false;
      flow().select(null);
      expect(history.writes.last, 'push /map');
      expect(container.read(mapFlowProvider).trail.entries, isEmpty);
    });

    test("a shop of a place's surroundings is a step further; back reopens the place", () {
      flow().select(_place);
      final shop = PoiSelection(
        const PoiFeature(id: 'shop', kind: PoiKind.bakery, position: LatLng(45.9, 6.12)),
        from: _place.id,
      );
      flow().select(shop);
      expect(history.writes.last, 'push /map?poi=shop&from=place-a');
      expect(flow().back(), isTrue);
      expect(open(), _place);
      expect(history.writes.last, 'back 1');
    });

    test('the same chosen again keeps its step, with what the newer choice knew of it', () {
      final hint = PlaceSelection(_place.id);
      flow().select(_place);
      final reselections = container.read(reselectionsProvider);
      flow().select(hint);
      expect(container.read(reselectionsProvider), reselections + 1, reason: 'its page to its top');
      expect(identical(open(), hint), isTrue);
      expect(history.writes, ['push /map?place=place-a']);
    });

    test('nothing is written while a page covers the map', () {
      history.mapShown = false;
      flow().select(_place);
      expect(open(), _place);
      expect(history.writes, isEmpty);
    });

    test('the apps keep the way back and write no address', () {
      history.browser = false;
      flow().select(_place);
      flow().select(null);
      expect(history.writes, isEmpty);
      expect(open(), isNull);
    });
  });

  group('a choice that comes late', () {
    test('one that began before the last change is dropped and writes nothing', () {
      final pressed = revision();
      flow().select(_point);
      final written = [...history.writes];
      expect(flow().select(null, since: pressed), isFalse, reason: 'a tap on the map of before');
      expect(open(), _point, reason: 'the address the search just opened stays open');
      expect(history.writes, written);
    });

    test('one that began after it acts', () {
      flow().select(_point);
      final pressed = revision();
      expect(flow().select(null, since: pressed), isTrue);
      expect(open(), isNull);
    });

    test('the search opened or closed is a change of its own', () {
      final pressed = revision();
      container.read(searchQueryProvider.notifier).change('Annecy');
      expect(revision(), greaterThan(pressed));
      expect(flow().select(_point, since: pressed), isFalse);
      expect(open(), isNull);
    });

    test('a page opened over the map, or left, is a change', () {
      flow().select(_place);
      final pressed = revision();
      flow().openPage('/route?lat=45.9&lon=6.12');
      expect(
        flow().select(null, since: pressed),
        isFalse,
        reason: 'the card stays under the preview',
      );
      final again = revision();
      flow().leavePage();
      expect(revision(), greaterThan(again));
      expect(history.writes.sublist(1), ['page /route?lat=45.9&lon=6.12', 'leave page']);
    });

    test('a link read meanwhile stands only while nothing changed', () {
      final opened = flow().adopt(_place);
      expect(flow().stands(opened), isTrue);
      flow().select(_other);
      expect(flow().stands(opened), isFalse);
    });
  });

  group('the system back', () {
    test('reopens the selection under, closes, then closes the search, then lets go', () {
      history.browser = false;
      flow().select(_place);
      container.read(searchQueryProvider.notifier).change('lac');
      expect(flow().back(), isTrue);
      expect(open(), isNull);
      expect(flow().back(), isTrue);
      expect(container.read(searchQueryProvider), isEmpty);
      expect(flow().back(), isFalse);
    });
  });

  group('the browser at an address', () {
    test('the address of what is open changes nothing', () {
      flow().select(_place);
      final before = revision();
      expect(flow().arrived(const MapLink(place: 'place-a')), isNull);
      expect(revision(), before);
    });

    test('a step of the way back reopens; the bare map closes', () {
      flow().select(_place);
      expect(flow().arrived(MapLink.none), isNull);
      expect(open(), isNull);
      expect(flow().arrived(const MapLink(place: 'place-a')), isNull, reason: 'its forward');
      expect(open(), _place);
    });

    test('an address the way back does not hold is handed to the screen to read', () {
      expect(flow().arrived(const MapLink(place: 'elsewhere')), const MapLink(place: 'elsewhere'));
      expect(open(), isNull);
    });

    test('a point it cannot name again is forgotten, and the bare map takes its address', () {
      history.address = const MapLink(point: true);
      expect(flow().arrived(const MapLink(point: true)), isNull);
      expect(open(), isNull);
      expect(history.writes.last, 'replace /map');
    });

    test('a favourite opens the map at its own address, on a new entry', () {
      history.mapShown = false;
      flow().openFromElsewhere(_place);
      expect(open(), _place);
      expect(history.writes, ['go /map?place=place-a']);
    });
  });
}

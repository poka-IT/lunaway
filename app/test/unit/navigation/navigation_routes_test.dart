import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/application/navigation_providers.dart';
import 'package:lunaway/features/navigation/presentation/navigation_routes.dart';

void main() {
  test('a preview link gives back its target', () {
    const sent = RouteTarget(
      destination: LatLng(45.84509, 1.286339),
      label: 'Rue Maurice Utrillo',
      placeId: 'p-1',
    );
    final target = NavigationRoutes.targetOf(Uri.parse(NavigationRoutes.previewOf(sent)));
    expect(target?.destination.lat, closeTo(45.84509, 1e-6));
    expect(target?.label, 'Rue Maurice Utrillo');
    expect(target?.placeId, 'p-1');
  });

  test('the target the app opened with stays exact beside its rounded link', () {
    // More decimals than any link holds.
    const exact = RouteTarget(destination: LatLng(44.48463312, 4.68060648));
    final linked = NavigationRoutes.targetOf(Uri.parse(NavigationRoutes.previewOf(exact)));
    expect(linked?.destination, isNot(exact.destination), reason: 'the link rounds');
    expect(NavigationRoutes.exactOf(exact, linked), same(exact));
    // Another point, or nothing beside the link (reloaded, typed): the link.
    const other = RouteTarget(destination: LatLng(45, 1));
    expect(NavigationRoutes.exactOf(other, linked), same(linked));
    expect(NavigationRoutes.exactOf(null, linked), same(linked));
    expect(NavigationRoutes.exactOf('extra', linked), same(linked));
  });

  test("the route home's link names the home without its point", () {
    const home = RouteTarget(destination: LatLng(45.9, 6.12), label: 'Domicile', home: true);
    final link = Uri.parse(NavigationRoutes.previewOf(home));
    expect(
      link.toString(),
      '/route?to=home',
      reason: "a browser's history keeps the link: the home's point stays out of it",
    );
    expect(NavigationRoutes.homeOf(link), isTrue);
    expect(
      NavigationRoutes.homeOf(
        Uri.parse(NavigationRoutes.previewOf(const RouteTarget(destination: LatLng(45.9, 6.12)))),
      ),
      isFalse,
    );
  });

  test('a link without a valid point gives none', () {
    for (final query in ['lat=NaN&lon=1', 'lat=45&lon=Infinity', 'lat=91&lon=1', 'lat=45']) {
      expect(NavigationRoutes.targetOf(Uri.parse('/route?$query')), isNull, reason: query);
    }
  });
}

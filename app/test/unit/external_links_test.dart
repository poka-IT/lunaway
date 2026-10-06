import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunaway/core/external_actions.dart';
import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/core/navigation_apps.dart';
import 'package:lunaway/features/map/domain/map_page_policy.dart';

void main() {
  group('links from the data open only as web pages', () {
    test('a website without scheme gets https; anything but http(s) with a host is refused', () {
      expect(webLink('example.org/aire').toString(), 'https://example.org/aire');
      expect(webLink(' http://x.fr ').toString(), 'http://x.fr');
      for (final bad in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'intent://x#Intent;end',
        'ms-settings:privacy',
        'smb://host/share',
        'http://',
        'https:///path',
        '',
        null,
        'ht tp://bad url',
      ]) {
        expect(webLink(bad), isNull, reason: '$bad');
      }
    });

    test('the platform actions refuse a non-web URL before any launcher sees it', () async {
      const actions = PlatformExternalActions();
      expect(PlatformExternalActions.isWebPage(Uri.parse('https://lunaway.net')), isTrue);
      for (final bad in [
        'file:///C:/Windows/System32/calc.exe',
        'ms-calculator:',
        'tel:112',
        'geo:0,0',
      ]) {
        expect(await actions.openUrl(Uri.parse(bad)), isFalse, reason: bad);
      }
    });

    test('a phone field holding several numbers gives each, dialable', () {
      expect(phoneNumbers('+33 4 50 00 00 00; 06.12.34.56.78'), ['+33450000000', '0612345678']);
      expect(phoneNumbers(' ; n/a ;'), isEmpty);
      expect(phoneNumbers(null), isEmpty);
    });
  });

  group('directions hand a route, not a pin', () {
    const to = LatLng(45.7629, 4.831697);

    test('each phone offers the usual navigation apps, the web its links', () {
      expect(NavigationApp.offeredOn(TargetPlatform.android, web: false), [
        NavigationApp.googleMaps,
        NavigationApp.waze,
        NavigationApp.osmAnd,
        NavigationApp.organicMaps,
        NavigationApp.magicEarth,
      ]);
      expect(
        NavigationApp.offeredOn(TargetPlatform.iOS, web: false).first,
        NavigationApp.appleMaps,
      );
      expect(NavigationApp.offeredOn(TargetPlatform.android, web: true), [
        NavigationApp.googleMaps,
        NavigationApp.waze,
        NavigationApp.openStreetMap,
      ]);
    });

    test('Google Maps starts turn by turn on Android, a driving route elsewhere', () {
      expect(
        NavigationApp.googleMaps
            .routeTo(to, platform: TargetPlatform.android, web: false)
            .toString(),
        'google.navigation:q=45.762900,4.831697&mode=d',
      );
      final web = NavigationApp.googleMaps.routeTo(to, platform: TargetPlatform.android, web: true);
      expect(web.host, 'www.google.com');
      expect(web.queryParameters, {
        'api': '1',
        'destination': '45.762900,4.831697',
        'travelmode': 'driving',
        'dir_action': 'navigate',
      });
    });

    test('OsmAnd on Android navigates by car at once', () {
      final uri = NavigationApp.osmAnd.routeTo(to, platform: TargetPlatform.android, web: false);
      expect(uri.scheme, 'osmand.api');
      expect(uri.queryParameters, {
        'dest_lat': '45.762900',
        'dest_lon': '4.831697',
        'profile': 'car',
        'force': 'true',
      });
    });

    test('Organic Maps gets a route from the position when known, the point otherwise', () {
      final route = NavigationApp.organicMaps.routeTo(
        to,
        platform: TargetPlatform.android,
        web: false,
        from: const LatLng(45.9, 6.1),
      );
      expect(
        (route.host, route.queryParameters['sll'], route.queryParameters['type']),
        ('route', '45.900000,6.100000', 'vehicle'),
      );
      final point = NavigationApp.organicMaps.routeTo(
        to,
        platform: TargetPlatform.android,
        web: false,
      );
      expect(point.host, 'map');
    });

    test('Apple Plans uses the unified directions URL', () {
      final uri = NavigationApp.appleMaps.routeTo(to, platform: TargetPlatform.iOS, web: false);
      expect('${uri.host}${uri.path}', 'maps.apple.com/directions');
      expect(uri.queryParameters['mode'], 'driving');
    });

    test('an app is offered when its own scheme answers; a web link needs no check', () {
      expect(
        NavigationApp.waze.installCheck(platform: TargetPlatform.android, web: false).toString(),
        'waze://',
      );
      expect(NavigationApp.waze.installCheck(platform: TargetPlatform.android, web: true), isNull);
      expect(
        NavigationApp.appleMaps.installCheck(platform: TargetPlatform.iOS, web: false),
        isNull,
      );
      expect(NavigationApp.fromId('osmand'), NavigationApp.osmAnd);
      expect(NavigationApp.fromId('gone'), isNull);
    });
  });

  group('the desktop map web view holds the map page only', () {
    final page = Uri.parse('file:///Applications/Lunaway.app/flutter_assets/assets/map/map.html');

    test('the shipped page loads, then only that very page', () {
      expect(decideMapNavigation(page, mapPage: null), MapPageNavigation.allow);
      expect(
        decideMapNavigation(page.replace(fragment: 'x'), mapPage: page),
        MapPageNavigation.allow,
      );
      expect(
        decideMapNavigation(Uri.parse('file:///tmp/assets/map/map.html'), mapPage: page),
        MapPageNavigation.block,
        reason: 'another file with the same name',
      );
    });

    test('a web link (the attribution) leaves for the browser; anything else is blocked', () {
      expect(
        decideMapNavigation(Uri.parse('https://www.openstreetmap.org/copyright'), mapPage: page),
        MapPageNavigation.openExternally,
      );
      expect(
        decideMapNavigation(Uri.parse('https://evil.example/assets/map/map.html'), mapPage: null),
        MapPageNavigation.openExternally,
        reason: 'a remote page is never the map page',
      );
      for (final bad in [
        'file:///etc/passwd',
        'javascript:alert(1)',
        'about:blank',
        'data:text/html,x',
      ]) {
        expect(
          decideMapNavigation(Uri.parse(bad), mapPage: page),
          MapPageNavigation.block,
          reason: bad,
        );
      }
      expect(decideMapNavigation(null, mapPage: page), MapPageNavigation.block);
    });
  });
}

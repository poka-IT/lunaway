import 'package:lunaway/core/geo/geo.dart';
import 'package:lunaway/features/navigation/domain/enforcement.dart';
import 'package:lunaway_nav/lunaway_nav.dart' as nav;

/// The countries at a position and within a kilometre of it, from the
/// boundaries the server reads, on the device: no position leaves it.
abstract interface class CountryLocator {
  /// The country [p] lies in (null at sea) and every country within a
  /// kilometre of it, that one included.
  ({String? at, List<String> near}) around(LatLng p);

  /// The rules table the app was built with: what applies before the API
  /// sent its own.
  EnforcementRules get builtIn;
}

/// [CountryLocator] through the guidance library (`lunaway_domain::region`
/// and its embedded boundaries), loaded with the guidance engine.
final class BridgeCountryLocator implements CountryLocator {
  const new();

  @override
  ({String? at, List<String> near}) around(LatLng p) {
    final c = nav.countriesAround(lat: p.lat, lon: p.lon);
    return (at: c.at, near: c.near);
  }

  @override
  EnforcementRules get builtIn {
    final r = nav.embeddedRules();
    return EnforcementRules(
      version: r.version,
      reviewedOn: r.reviewedOn,
      countries: {for (final c in r.countries) c.country: EnforcementMode.fromWire(c.mode)},
    );
  }
}

/// Where the guidance library is not loaded: no country is known, so
/// every rule reads as off and nothing of a camera shows.
final class NoCountryLocator implements CountryLocator {
  const new();

  @override
  ({String? at, List<String> near}) around(LatLng p) => (at: null, near: const []);

  @override
  EnforcementRules get builtIn => EnforcementRules.none;
}

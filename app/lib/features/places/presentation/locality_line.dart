import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lunaway/features/places/data/places_repository.dart';
import 'package:lunaway/features/places/domain/french_departments.dart';
import 'package:lunaway/features/places/domain/locality.dart';
import 'package:lunaway/features/regions/application/region_providers.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';

/// The user's country, which a result needs not name: the country of the
/// device's settings, France when it says none (the app's first country).
String homeCountry(WidgetRef ref) => ref.watch(deviceCountryProvider)?.toUpperCase() ?? 'FR';

/// Where [locality] lies, short, for the line under a result of the
/// search, its page and the history:
///
/// - in France, the town and its department's number ("Annecy (74)"), the
///   arrondissement of Paris, Lyon and Marseille ("Lyon 3e"), the
///   department's name without a town ("Drôme");
/// - elsewhere, the town and its region when the data names one ("München
///   · Bayern");
/// - then the country, when it is not the user's own ([home]): "München ·
///   Allemagne" to a French user.
///
/// Null when the data says nothing: the line then leaves it out rather
/// than guess.
String? localityLine(Translations t, Locality? locality, {required String home}) {
  if (locality == null || locality.isEmpty) return null;
  final country = locality.countryCode;
  final french =
      frenchCountries.contains(country) || (country == null && locality.department != null);
  // France overseas is no country abroad to a French user.
  final abroad =
      country != null &&
      country != home.toUpperCase() &&
      !(french && frenchCountries.contains(home.toUpperCase()));
  final town = locality.town;
  final department = locality.department;
  final String? here;
  if (french) {
    here = switch ((town, department, arrondissementOf(town, locality.postcode))) {
      (final town?, _, final n?) => t.search.arrondissement(town: town, n: n),
      (final town?, final department?, null) => t.search.townInDepartment(
        town: town,
        department: department,
      ),
      (final town?, null, null) => town,
      (null, final department?, _) => frenchDepartments[department] ?? department,
      (null, null, _) => null,
    };
  } else {
    here = [?town, if (!abroad) ?locality.region].join(' · ');
  }
  final parts = [if (here != null && here.isNotEmpty) here, if (abroad) t.countryName(country)];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Where a town of the search lies, after what it is: its department in
/// France ("Commune · Drôme"), its postcode elsewhere, which tells two
/// homonyms of one country apart, and its country when it is not the
/// user's own ([home]): "Commune · 67433 · Allemagne".
String townWhere(Translations t, Municipality town, {required String home}) {
  final country = town.countryCode;
  final french = country == null || frenchCountries.contains(country);
  final department = french
      ? frenchDepartments[town.department ?? departmentOfPostcode(town.postcode)]
      : null;
  return [
    t.search.addressKind.town,
    department ?? town.postcode,
    if (country != null &&
        country != home.toUpperCase() &&
        !(french && frenchCountries.contains(home.toUpperCase())))
      t.countryName(country),
  ].nonNulls.join(' · ');
}

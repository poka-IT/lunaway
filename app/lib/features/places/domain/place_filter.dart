import 'package:collection/collection.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// A need the filters offer, wider than one service: a dump station is a grey
/// water or a black water point, whichever the place has.
enum Amenity {
  water({Service.drinkingWater}),
  dumpStation({Service.greyWater, Service.blackWater}),
  electricity({Service.electricity}),
  toilets({Service.toilets});

  new(this.services);

  /// A place offers the amenity when it has any of these.
  final Set<Service> services;

  int get mask => Service.maskOf(services);

  bool offeredBy(Set<Service> placeServices) => placeServices.any(services.contains);
}

/// The few filters the app offers. Every field narrows the result; the empty
/// filter keeps everything.
@immutable
final class PlaceFilter {
  const new({
    this.families = const {},
    this.nightOk = false,
    this.amenities = const {},
    this.vehicleHeightM,
  });

  static const none = PlaceFilter();

  /// The filter a new user starts with: only places where a night is allowed
  /// or tolerated, the first question a traveller asks.
  static const initial = PlaceFilter(nightOk: true);

  /// Empty means every family.
  final Set<KindFamily> families;

  /// Keep only places where a night is allowed or tolerated.
  final bool nightOk;

  /// The place must offer all of them.
  final Set<Amenity> amenities;

  /// Excludes places whose known maximum height is lower. Unknown heights
  /// stay: hiding them would hide most of the map.
  final double? vehicleHeightM;

  bool get isEmpty => families.isEmpty && !nightOk && amenities.isEmpty && vehicleHeightM == null;

  /// How many criteria are active, for the badge on the filter button.
  int get activeCount =>
      families.length + (nightOk ? 1 : 0) + amenities.length + (vehicleHeightM == null ? 0 : 1);

  bool matches(PlaceSummary place, {double? maxHeightM}) {
    if (families.isNotEmpty && !families.contains(place.kind.family)) return false;
    if (nightOk && !place.overnight.nightOk) return false;
    if (!amenities.every((a) => a.offeredBy(place.services))) return false;
    final height = vehicleHeightM;
    if (height != null && maxHeightM != null && maxHeightM < height) return false;
    return true;
  }

  PlaceFilter copyWith({
    Set<KindFamily>? families,
    bool? nightOk,
    Set<Amenity>? amenities,
    double? Function()? vehicleHeightM,
  }) => PlaceFilter(
    families: families ?? this.families,
    nightOk: nightOk ?? this.nightOk,
    amenities: amenities ?? this.amenities,
    vehicleHeightM: vehicleHeightM == null ? this.vehicleHeightM : vehicleHeightM(),
  );

  PlaceFilter toggleAmenity(Amenity amenity) => copyWith(amenities: _toggle(amenities, amenity));

  PlaceFilter toggleFamily(KindFamily family) => copyWith(families: _toggle(families, family));

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  bool operator ==(Object other) =>
      other is PlaceFilter &&
      const SetEquality<KindFamily>().equals(other.families, families) &&
      other.nightOk == nightOk &&
      const SetEquality<Amenity>().equals(other.amenities, amenities) &&
      other.vehicleHeightM == vehicleHeightM;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(families),
    nightOk,
    Object.hashAllUnordered(amenities),
    vehicleHeightM,
  );
}

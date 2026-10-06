import 'package:collection/collection.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:meta/meta.dart';

/// A need the filters offer, sometimes wider than one service: a dump
/// station is a grey water or a black water point, whichever the place has.
enum Amenity {
  water({Service.drinkingWater}),
  dumpStation({Service.greyWater, Service.blackWater}),
  electricity({Service.electricity}),
  toilets({Service.toilets}),
  showers({Service.showers}),
  wasteBin({Service.wasteBin}),
  laundry({Service.laundry}),
  wifi({Service.wifi}),
  lpg({Service.lpg});

  new(this.services);

  /// A place offers the amenity when it has any of these.
  final Set<Service> services;

  /// The ones the filters offer. LPG stays out: the places' sources do not
  /// carry it, and the stations selling it are on the fuel layer with their
  /// prices.
  static const List<Amenity> offered = [
    water,
    dumpStation,
    electricity,
    toilets,
    showers,
    wasteBin,
    laundry,
    wifi,
  ];

  int get mask => Service.maskOf(services);

  bool offeredBy(Set<Service> placeServices) => placeServices.any(services.contains);
}

/// The overnight statuses where a night can be spent: what the "night
/// possible" shortcut keeps.
const Set<OvernightStatus> nightPossible = {OvernightStatus.allowed, OvernightStatus.tolerated};

/// The filters the app offers. Every field narrows the result; the empty
/// filter keeps everything.
@immutable
final class PlaceFilter {
  const new({
    this.families = const {},
    this.overnight = const {},
    this.amenities = const {},
    this.fitsMyVehicle = false,
    this.freeOnly = false,
    this.vehicleHeightM,
  });

  /// No filter: what a new user starts with, so service points (which
  /// rarely allow a night) show from the first launch.
  static const none = PlaceFilter();

  /// Empty means every family.
  final Set<KindFamily> families;

  /// The overnight statuses kept; empty means every status.
  final Set<OvernightStatus> overnight;

  /// The place must offer all of them.
  final Set<Amenity> amenities;

  /// Keep only places the user's vehicle fits, using its stored size. The
  /// screens resolve it into [vehicleHeightM] before querying.
  final bool fitsMyVehicle;

  /// Keep only the places whose night is known to be free: an unknown
  /// price is not a free one.
  final bool freeOnly;

  /// Excludes places whose known maximum height is lower. Unknown heights
  /// stay: hiding them would hide most of the map. Set from the vehicle
  /// profile when [fitsMyVehicle] is on; never stored on its own.
  final double? vehicleHeightM;

  bool get isEmpty =>
      families.isEmpty && overnight.isEmpty && amenities.isEmpty && !fitsMyVehicle && !freeOnly;

  /// The "night possible" shortcut is on.
  bool get nightOk => const SetEquality<OvernightStatus>().equals(overnight, nightPossible);

  /// How many criteria are active, for the badge on the filter button.
  int get activeCount =>
      families.length +
      (overnight.isEmpty ? 0 : 1) +
      amenities.length +
      (fitsMyVehicle ? 1 : 0) +
      (freeOnly ? 1 : 0);

  bool matches(PlaceSummary place, {double? maxHeightM}) {
    if (families.isNotEmpty && !families.contains(place.kind.family)) return false;
    if (overnight.isNotEmpty && !overnight.contains(place.overnight)) return false;
    if (!amenities.every((a) => a.offeredBy(place.services))) return false;
    if (freeOnly && place.priceParkingEur != 0) return false;
    final height = vehicleHeightM;
    if (height != null && maxHeightM != null && maxHeightM < height) return false;
    return true;
  }

  PlaceFilter copyWith({
    Set<KindFamily>? families,
    Set<OvernightStatus>? overnight,
    Set<Amenity>? amenities,
    bool? fitsMyVehicle,
    bool? freeOnly,
    double? Function()? vehicleHeightM,
  }) => PlaceFilter(
    families: families ?? this.families,
    overnight: overnight ?? this.overnight,
    amenities: amenities ?? this.amenities,
    fitsMyVehicle: fitsMyVehicle ?? this.fitsMyVehicle,
    freeOnly: freeOnly ?? this.freeOnly,
    vehicleHeightM: vehicleHeightM == null ? this.vehicleHeightM : vehicleHeightM(),
  );

  PlaceFilter toggleAmenity(Amenity amenity) => copyWith(amenities: _toggle(amenities, amenity));

  PlaceFilter toggleFamily(KindFamily family) => copyWith(families: _toggle(families, family));

  PlaceFilter toggleOvernight(OvernightStatus status) =>
      copyWith(overnight: _toggle(overnight, status));

  /// Turns the "night possible" shortcut on, or every status back on.
  PlaceFilter withNightOk({required bool on}) => copyWith(overnight: on ? nightPossible : const {});

  /// The filter to query with: [fitsMyVehicle] turned into the height of
  /// the stored vehicle, or into nothing while no height is known.
  PlaceFilter resolve({double? vehicleHeightM}) =>
      copyWith(vehicleHeightM: () => fitsMyVehicle ? vehicleHeightM : null);

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  bool operator ==(Object other) =>
      other is PlaceFilter &&
      const SetEquality<KindFamily>().equals(other.families, families) &&
      const SetEquality<OvernightStatus>().equals(other.overnight, overnight) &&
      const SetEquality<Amenity>().equals(other.amenities, amenities) &&
      other.fitsMyVehicle == fitsMyVehicle &&
      other.freeOnly == freeOnly &&
      other.vehicleHeightM == vehicleHeightM;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(families),
    Object.hashAllUnordered(overnight),
    Object.hashAllUnordered(amenities),
    fitsMyVehicle,
    freeOnly,
    vehicleHeightM,
  );
}

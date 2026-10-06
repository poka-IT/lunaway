import 'package:intl/intl.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// Labels of the taxonomy and formatting of the values a place shows, in the
/// current language. Numbers follow the locale (a decimal comma in French),
/// except coordinates, which `CoordinateFormat` keeps with a point.
extension Labels on Translations {
  // Read through a name, so the translation gate sees every key used.
  Translations get _t => this;

  String kind(PlaceKind k) => switch (k) {
    .motorhomeArea => _t.kinds.motorhomeArea,
    .serviceArea => _t.kinds.serviceArea,
    .campsite => _t.kinds.campsite,
    .parking => _t.kinds.parking,
    .nature => _t.kinds.nature,
    .restArea => _t.kinds.restArea,
    .picnicArea => _t.kinds.picnicArea,
    .farm => _t.kinds.farm,
    .homestay => _t.kinds.homestay,
    .offRoad => _t.kinds.offRoad,
    .extraService => _t.kinds.extraService,
  };

  String family(KindFamily f) => switch (f) {
    .stopovers => _t.families.stopovers,
    .campsites => _t.families.campsites,
    .nature => _t.families.nature,
    .services => _t.families.services,
  };

  String service(Service s) => switch (s) {
    .drinkingWater => _t.services.drinkingWater,
    .greyWater => _t.services.greyWater,
    .blackWater => _t.services.blackWater,
    .wasteBin => _t.services.wasteBin,
    .toilets => _t.services.toilets,
    .showers => _t.services.showers,
    .electricity => _t.services.electricity,
    .wifi => _t.services.wifi,
    .laundry => _t.services.laundry,
    .lpg => _t.services.lpg,
    .gasBottles => _t.services.gasBottles,
    .vehicleWash => _t.services.vehicleWash,
    .bakery => _t.services.bakery,
    .swimmingPool => _t.services.swimmingPool,
    .petsAllowed => _t.services.petsAllowed,
    .mobileData => _t.services.mobileData,
    .winterCaravanning => _t.services.winterCaravanning,
  };

  String activity(Activity a) => switch (a) {
    .monuments => _t.activities.monuments,
    .windsurfKitesurf => _t.activities.windsurfKitesurf,
    .mountainBiking => _t.activities.mountainBiking,
    .hiking => _t.activities.hiking,
    .climbing => _t.activities.climbing,
    .canoeKayak => _t.activities.canoeKayak,
    .fishing => _t.activities.fishing,
    .shoreFishing => _t.activities.shoreFishing,
    .swimming => _t.activities.swimming,
    .motorcycling => _t.activities.motorcycling,
    .viewpoint => _t.activities.viewpoint,
    .playground => _t.activities.playground,
  };

  String amenity(Amenity a) => switch (a) {
    .water => _t.amenities.water,
    .dumpStation => _t.amenities.dumpStation,
    .electricity => _t.amenities.electricity,
    .toilets => _t.amenities.toilets,
  };

  String overnightLabel(OvernightStatus o) => switch (o) {
    .allowed => _t.overnight.allowed,
    .tolerated => _t.overnight.tolerated,
    .dayOnly => _t.overnight.dayOnly,
    .forbidden => _t.overnight.forbidden,
    .unknown => _t.overnight.unknown,
  };

  String overnightHint(OvernightStatus o) => switch (o) {
    .allowed => _t.overnight.allowedHint,
    .tolerated => _t.overnight.toleratedHint,
    .dayOnly => _t.overnight.dayOnlyHint,
    .forbidden => _t.overnight.forbiddenHint,
    .unknown => _t.overnight.unknownHint,
  };

  /// The name, or "Car park in Annecy" when the place has none.
  String placeTitle({required String? name, required PlaceKind kind, String? city}) {
    if (name != null && name.isNotEmpty) return name;
    if (city != null && city.isNotEmpty) {
      return _t.place.unnamedIn(kind: this.kind(kind), town: city);
    }
    return this.kind(kind);
  }

  String summaryTitle(PlaceSummary p) => placeTitle(name: p.name, kind: p.kind, city: p.city);

  /// "yesterday", "3 months ago": how old [date] is at [now].
  String ago(DateTime date, DateTime now) {
    final days = now.difference(date).inDays;
    if (days <= 0) return _t.freshness.today;
    if (days < 31) return _t.freshness.daysAgo(n: days);
    if (days < 365) return _t.freshness.monthsAgo(n: days ~/ 30);
    return _t.freshness.yearsAgo(n: days ~/ 365);
  }

  /// "Open, closes at 19:00", "Closed, opens Monday at 08:00": [state] read
  /// in the device's local time at [now].
  String opening(OpeningState state, DateTime now) {
    final local = now.toLocal();
    switch (state) {
      case OpenThroughWindow():
        return _t.hours.open;
      case ClosedThroughWindow():
        return _t.hours.closedWindow;
      case OpenUntil(:final closesAt):
        final minutes = closesAt.difference(now).inMinutes;
        if (minutes <= 60) return _t.hours.closesIn(n: minutes < 1 ? 1 : minutes);
        final (day, time) = _dayAndTime(closesAt.toLocal(), local, endOfSpan: true);
        return day == null
            ? _t.hours.openUntil(time: time)
            : _t.hours.openUntilDay(day: day, time: time);
      case ClosedUntil(:final opensAt):
        final minutes = opensAt.difference(now).inMinutes;
        if (minutes <= 60) return _t.hours.opensIn(n: minutes < 1 ? 1 : minutes);
        final (day, time) = _dayAndTime(opensAt.toLocal(), local, endOfSpan: false);
        return day == null
            ? _t.hours.closedUntil(time: time)
            : _t.hours.closedUntilDay(day: day, time: time);
    }
  }

  /// The day (null for today) and the time of [at]. A span ending at
  /// midnight ends "at midnight" today, not "tomorrow at 00:00".
  (String?, String) _dayAndTime(DateTime at, DateTime now, {required bool endOfSpan}) {
    final today = DateTime(now.year, now.month, now.day);
    var day = DateTime(at.year, at.month, at.day);
    var time = DateFormat.jm(_locale).format(at);
    if (endOfSpan && at.hour == 0 && at.minute == 0) {
      day = DateTime(day.year, day.month, day.day - 1);
      time = _t.hours.midnight;
    }
    final days = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (days <= 0) return (null, time);
    if (days == 1) return (_t.hours.tomorrow, time);
    if (days < 7) return (DateFormat.EEEE(_locale).format(day), time);
    return (_t.hours.onDate(date: DateFormat.MMMd(_locale).format(day)), time);
  }

  /// The name of a language code, or the code itself for an unknown one.
  String languageName(String code) => switch (code) {
    'fr' => _t.languages.fr,
    'en' => _t.languages.en,
    'de' => _t.languages.de,
    'es' => _t.languages.es,
    'it' => _t.languages.it,
    'nl' => _t.languages.nl,
    _ => code,
  };

  /// "4.3" or "4,3".
  String ratingValue(double average) => NumberFormat('0.0', _locale).format(average);

  String get _locale => $meta.locale.languageCode;

  /// "350 m", "3.2 km" or "3,2 km", "48 km".
  String distance(double metres) {
    if (metres < 1000) return '${(metres / 10).round() * 10} m';
    final km = metres / 1000;
    final format = NumberFormat(km < 10 ? '0.0' : '0', _locale);
    return '${format.format(km)} km';
  }

  /// "12 €" or "€12"; cents only when there are some.
  String euros(double value) {
    final whole = value == value.roundToDouble();
    return NumberFormat.simpleCurrency(
      locale: _locale,
      name: 'EUR',
      decimalDigits: whole ? 0 : 2,
    ).format(value);
  }

  /// "2.20 m" or "2,20 m".
  String metres(double value) => '${NumberFormat('0.00', _locale).format(value)} m';

  String fileSize(int bytes) {
    final format = NumberFormat('0.0', _locale);
    if (bytes < 1024 * 1024) return _t.units.kilobytes(n: format.format(bytes / 1024));
    return _t.units.megabytes(n: format.format(bytes / (1024 * 1024)));
  }
}

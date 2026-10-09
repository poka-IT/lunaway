import 'package:intl/intl.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/places/domain/opening.dart';
import 'package:lunaway/features/places/domain/place.dart';
import 'package:lunaway/features/places/domain/place_content.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/season.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/features/vehicle/domain/vehicle.dart';
import 'package:lunaway/i18n/strings.g.dart';

/// Labels of the taxonomy and formatting of the values the app shows, in the
/// current language. Numbers follow the locale (a decimal comma and a narrow
/// space between thousands in French), except coordinates, which
/// `CoordinateFormat` keeps with a point.
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

  String familyHint(KindFamily f) => switch (f) {
    .stopovers => _t.families.stopoversHint,
    .campsites => _t.families.campsitesHint,
    .nature => _t.families.natureHint,
    .services => _t.families.servicesHint,
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

  /// What a night's price includes, in a list that follows "Includes:".
  String priceInclusion(PriceInclusion i) => switch (i) {
    .services => _t.place.inclusions.services,
    .touristTax => _t.place.inclusions.touristTax,
    .electricity => _t.place.inclusions.electricity,
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
    .showers => _t.amenities.showers,
    .wasteBin => _t.amenities.wasteBin,
    .laundry => _t.amenities.laundry,
    .wifi => _t.amenities.wifi,
    .lpg => _t.amenities.lpg,
  };

  /// The status as a short label, for rows, chips and badges.
  String overnightShort(OvernightStatus o) => switch (o) {
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

  String vehicleType(VehicleType v) => switch (v) {
    .van => _t.vehicle.types.van,
    .campervan => _t.vehicle.types.campervan,
    .lowProfile => _t.vehicle.types.lowProfile,
    .overcab => _t.vehicle.types.overcab,
    .integrated => _t.vehicle.types.integrated,
  };

  String reviewVehicle(ReviewVehicle v) => switch (v) {
    .van => _t.place.reviewVehicle.van,
    .campervan => _t.place.reviewVehicle.campervan,
    .motorhome => _t.place.reviewVehicle.motorhome,
    .caravan => _t.place.reviewVehicle.caravan,
    .other => _t.place.reviewVehicle.other,
  };

  String fuelType(FuelType f) => switch (f) {
    .diesel => _t.poi.fuel.diesel,
    .e10 => _t.poi.fuel.e10,
    .sp95 => _t.poi.fuel.sp95,
    .sp98 => _t.poi.fuel.sp98,
    .e85 => _t.poi.fuel.e85,
    .lpg => _t.poi.fuel.lpg,
  };

  String towing(Towing w) => switch (w) {
    .none => _t.vehicle.towing.none,
    .car => _t.vehicle.towing.car,
    .trailer => _t.vehicle.towing.trailer,
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
  /// at [now], on the wall clock of the place's [zone].
  String opening(OpeningState state, DateTime now, {required PlaceZone zone}) {
    final local = zone.wallClock(now);
    switch (state) {
      case OpenThroughWindow():
        return _t.hours.open;
      case ClosedThroughWindow():
        return _t.hours.closedWindow;
      case OpenUntil(:final closesAt):
        final minutes = closesAt.difference(now).inMinutes;
        if (minutes <= 60) return _t.hours.closesIn(n: minutes < 1 ? 1 : minutes);
        final (day, time) = _dayAndTime(zone.wallClock(closesAt), local, endOfSpan: true);
        return day == null
            ? _t.hours.openUntil(time: time)
            : _t.hours.openUntilDay(day: day, time: time);
      case ClosedUntil(:final opensAt):
        final minutes = opensAt.difference(now).inMinutes;
        if (minutes <= 60) return _t.hours.opensIn(n: minutes < 1 ? 1 : minutes);
        final (day, time) = _dayAndTime(zone.wallClock(opensAt), local, endOfSpan: false);
        return day == null
            ? _t.hours.closedUntil(time: time)
            : _t.hours.closedUntilDay(day: day, time: time);
    }
  }

  /// "Open all year", "Open until October 31", "Closed, opens April 1":
  /// the season's [state].
  String season(SeasonState state) => switch (state) {
    SeasonAllYear() => _t.hours.seasonAllYear,
    SeasonOpenUntil(:final lastDay) => _t.hours.seasonOpenUntil(
      date: _date(DateFormat.MMMMd(_locale), dateOfDay(lastDay)),
    ),
    SeasonClosedUntil(:final firstDay) => _t.hours.seasonClosedUntil(
      date: _date(DateFormat.MMMMd(_locale), dateOfDay(firstDay)),
    ),
  };

  /// [day] as [format] writes it, the first of a month as French says it
  /// ("1er avril", "1er oct.").
  String _date(DateFormat format, DateTime day) {
    final text = format.format(day);
    return day.day == 1 && _locale == 'fr' && text.startsWith('1')
        ? '1er${text.substring(1)}'
        : text;
  }

  /// The dates of a stay: "Du 12 au 15 oct." or "Oct 12 to 15", the
  /// month said once when both dates share it; "Le 12 oct." for one day.
  String stay(DateTime arrival, DateTime departure) {
    final date = DateFormat.MMMd(_locale);
    if (arrival.year == departure.year &&
        arrival.month == departure.month &&
        arrival.day == departure.day) {
      return _t.filters.openingStayDay(date: _date(date, arrival));
    }
    if (arrival.year != departure.year || arrival.month != departure.month) {
      return _t.filters.openingStay(from: _date(date, arrival), to: _date(date, departure));
    }
    // The month goes where the language puts it: after the day in French
    // ("12 oct."), before it in English ("Oct 12").
    final day = DateFormat.d(_locale);
    return date.pattern!.trimLeft().startsWith('d')
        ? _t.filters.openingStay(from: _date(day, arrival), to: _date(date, departure))
        : _t.filters.openingStay(from: _date(date, arrival), to: _date(day, departure));
  }

  /// The day (null for today) and the time of [at], both wall clock times
  /// of the place. A span ending at midnight ends "at midnight" today, not
  /// "tomorrow at 00:00".
  (String?, String) _dayAndTime(DateTime at, DateTime now, {required bool endOfSpan}) {
    final today = DateTime.utc(now.year, now.month, now.day);
    var day = DateTime.utc(at.year, at.month, at.day);
    var time = DateFormat.jm(_locale).format(at);
    if (endOfSpan && at.hour == 0 && at.minute == 0) {
      day = DateTime.utc(day.year, day.month, day.day - 1);
      time = _t.hours.midnight;
    }
    final days = day.difference(today).inDays;
    if (days <= 0) return (null, time);
    if (days == 1) return (_t.hours.tomorrow, time);
    // "el lunes", "am Montag": the article some languages set before a day.
    if (days < 7) return (_t.hours.onWeekday(day: DateFormat.EEEE(_locale).format(day)), time);
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

  /// A country's name from its ISO 3166-1 alpha-2 code; the code itself
  /// for one this app has no name for.
  String countryName(String code) => switch (code.toUpperCase()) {
    'AD' => _t.countries.ad,
    'AT' => _t.countries.at,
    'AX' => _t.countries.ax,
    'BE' => _t.countries.be,
    'CH' => _t.countries.ch,
    'CZ' => _t.countries.cz,
    'DE' => _t.countries.de,
    'DK' => _t.countries.dk,
    'EH' => _t.countries.eh,
    'ES' => _t.countries.es,
    'FI' => _t.countries.fi,
    'FR' => _t.countries.fr,
    'GB' => _t.countries.gb,
    'GI' => _t.countries.gi,
    'GR' => _t.countries.gr,
    'HR' => _t.countries.hr,
    'IE' => _t.countries.ie,
    'IT' => _t.countries.it,
    'LI' => _t.countries.li,
    'LU' => _t.countries.lu,
    'MA' => _t.countries.ma,
    'MC' => _t.countries.mc,
    'NL' => _t.countries.nl,
    'NO' => _t.countries.no,
    'PL' => _t.countries.pl,
    'PT' => _t.countries.pt,
    'SE' => _t.countries.se,
    'SI' => _t.countries.si,
    'SJ' => _t.countries.sj,
    'SM' => _t.countries.sm,
    'VA' => _t.countries.va,
    final other => other,
  };

  /// The name of an area the app downloads, by its code (`FR-BRE`,
  /// `fr-20r`, `ES`), in the reader's language: a French region or overseas
  /// department, else a country, from the translations; [fallback], the
  /// name the server gave, for a code they do not know. The server names
  /// its areas in French and English only.
  String areaName(String code, {required String fallback}) {
    final upper = code.toUpperCase();
    final area = switch (upper) {
      'FR-ARA' => _t.areas.ara,
      'FR-BFC' => _t.areas.bfc,
      'FR-BRE' => _t.areas.bre,
      'FR-CVL' => _t.areas.cvl,
      'FR-20R' => _t.areas.cor,
      'FR-GES' => _t.areas.ges,
      'FR-HDF' => _t.areas.hdf,
      'FR-IDF' => _t.areas.idf,
      'FR-NOR' => _t.areas.nor,
      'FR-NAQ' => _t.areas.naq,
      'FR-OCC' => _t.areas.occ,
      'FR-PDL' => _t.areas.pdl,
      'FR-PAC' => _t.areas.pac,
      'FR-971' => _t.areas.gp,
      'FR-972' => _t.areas.mq,
      'FR-973' => _t.areas.gf,
      'FR-974' => _t.areas.re,
      'FR-976' => _t.areas.yt,
      _ => null,
    };
    if (area != null) return area;
    final country = countryName(upper);
    return country == upper ? fallback : country;
  }

  /// "Automatically translated from German": one sentence per language,
  /// French elides its article ("de l'allemand", "du néerlandais").
  String translatedFrom(String code) => switch (code) {
    'fr' => _t.translation.from.fr,
    'en' => _t.translation.from.en,
    'de' => _t.translation.from.de,
    'es' => _t.translation.from.es,
    'it' => _t.translation.from.it,
    'nl' => _t.translation.from.nl,
    _ => _t.translation.from.unknown(language: code),
  };

  String get _locale => $meta.locale.languageCode;

  /// "15 256" or "15,256".
  String number(int value) => NumberFormat.decimalPattern(_locale).format(value);

  /// "4.3" or "4,3".
  String ratingValue(double average) => NumberFormat('0.0', _locale).format(average);

  /// A step of the minimum rating filter: "4", "4.5" or "4,5".
  String ratingStep(double step) => NumberFormat('0.#', _locale).format(step);

  /// "350 m", "3.2 km" or "3,2 km", "48 km". Metres round to tens; a distance
  /// that rounds to 1000 m reads "1.0 km".
  String distance(double metres) {
    final tens = (metres / 10).round() * 10;
    if (tens < 1000) return '$tens m';
    final km = metres / 1000;
    final format = NumberFormat(km < 9.95 ? '0.0' : '0', _locale);
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

  /// "2.90 m" or "2,90 m".
  String metres(double value) => '${NumberFormat('0.00', _locale).format(value)} m';

  /// "3.5 t" or "3,5 t".
  String tonnes(double value) => '${NumberFormat('0.0', _locale).format(value)} t';

  /// "850 KB", "3.3 MB", "120 MB": one decimal only under ten.
  String fileSize(int bytes) {
    const kb = 1024;
    const mb = 1024 * 1024;
    if (bytes < 1000 * kb) {
      return _t.units.kilobytes(n: NumberFormat('0', _locale).format((bytes / kb).ceil()));
    }
    final value = bytes / mb;
    return _t.units.megabytes(n: NumberFormat(value < 9.95 ? '0.0' : '0', _locale).format(value));
  }
}

/// A name as an index reads it, case and accents aside: "Île-de-France"
/// among the I, "Österreich" among the O, "Åland" among the A.
String sortKey(String name) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final out = StringBuffer();
  for (final c in name.toLowerCase().split('')) {
    final i = from.indexOf(c);
    out.write(c == 'ß' ? 'ss' : (i < 0 ? c : to[i]));
  }
  return out.toString();
}

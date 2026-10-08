// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cache_database.dart';

// ignore_for_file: type=lint
class Places extends Table with TableInfo<Places, PlaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  Places(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ridMeta = const VerificationMeta('rid');
  late final GeneratedColumn<int> rid = GeneratedColumn<int>(
    'rid',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL PRIMARY KEY AUTOINCREMENT',
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL UNIQUE',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _familyMeta = const VerificationMeta('family');
  late final GeneratedColumn<int> family = GeneratedColumn<int>(
    'family',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _overnightMeta = const VerificationMeta(
    'overnight',
  );
  late final GeneratedColumn<String> overnight = GeneratedColumn<String>(
    'overnight',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _servicesMeta = const VerificationMeta(
    'services',
  );
  late final GeneratedColumn<int> services = GeneratedColumn<int>(
    'services',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _activitiesMeta = const VerificationMeta(
    'activities',
  );
  late final GeneratedColumn<int> activities = GeneratedColumn<int>(
    'activities',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _streetMeta = const VerificationMeta('street');
  late final GeneratedColumn<String> street = GeneratedColumn<String>(
    'street',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _postcodeMeta = const VerificationMeta(
    'postcode',
  );
  late final GeneratedColumn<String> postcode = GeneratedColumn<String>(
    'postcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
    'city',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _countryCodeMeta = const VerificationMeta(
    'countryCode',
  );
  late final GeneratedColumn<String> countryCode = GeneratedColumn<String>(
    'country_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _priceParkingMeta = const VerificationMeta(
    'priceParking',
  );
  late final GeneratedColumn<double> priceParking = GeneratedColumn<double>(
    'price_parking',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _priceServicesMeta = const VerificationMeta(
    'priceServices',
  );
  late final GeneratedColumn<double> priceServices = GeneratedColumn<double>(
    'price_services',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _maxHeightMeta = const VerificationMeta(
    'maxHeight',
  );
  late final GeneratedColumn<double> maxHeight = GeneratedColumn<double>(
    'max_height',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _capacityMeta = const VerificationMeta(
    'capacity',
  );
  late final GeneratedColumn<int> capacity = GeneratedColumn<int>(
    'capacity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _openingHoursMeta = const VerificationMeta(
    'openingHours',
  );
  late final GeneratedColumn<String> openingHours = GeneratedColumn<String>(
    'opening_hours',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _openingHoursParsedMeta =
      const VerificationMeta('openingHoursParsed');
  late final GeneratedColumn<bool> openingHoursParsed = GeneratedColumn<bool>(
    'opening_hours_parsed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _openingIntervalsJsonMeta =
      const VerificationMeta('openingIntervalsJson');
  late final GeneratedColumn<String> openingIntervalsJson =
      GeneratedColumn<String>(
        'opening_intervals_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: '',
      );
  static const VerificationMeta _openingValidUntilMeta = const VerificationMeta(
    'openingValidUntil',
  );
  late final GeneratedColumn<int> openingValidUntil = GeneratedColumn<int>(
    'opening_valid_until',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _starsMeta = const VerificationMeta('stars');
  late final GeneratedColumn<int> stars = GeneratedColumn<int>(
    'stars',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _syncGenMeta = const VerificationMeta(
    'syncGen',
  );
  late final GeneratedColumn<int> syncGen = GeneratedColumn<int>(
    'sync_gen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _websiteMeta = const VerificationMeta(
    'website',
  );
  late final GeneratedColumn<String> website = GeneratedColumn<String>(
    'website',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lastConfirmedAtMeta = const VerificationMeta(
    'lastConfirmedAt',
  );
  late final GeneratedColumn<int> lastConfirmedAt = GeneratedColumn<int>(
    'last_confirmed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _sourcesJsonMeta = const VerificationMeta(
    'sourcesJson',
  );
  late final GeneratedColumn<String> sourcesJson = GeneratedColumn<String>(
    'sources_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _provenanceJsonMeta = const VerificationMeta(
    'provenanceJson',
  );
  late final GeneratedColumn<String> provenanceJson = GeneratedColumn<String>(
    'provenance_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _descriptionsJsonMeta = const VerificationMeta(
    'descriptionsJson',
  );
  late final GeneratedColumn<String> descriptionsJson = GeneratedColumn<String>(
    'descriptions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _ratingsJsonMeta = const VerificationMeta(
    'ratingsJson',
  );
  late final GeneratedColumn<String> ratingsJson = GeneratedColumn<String>(
    'ratings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _linksJsonMeta = const VerificationMeta(
    'linksJson',
  );
  late final GeneratedColumn<String> linksJson = GeneratedColumn<String>(
    'links_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _ratingAvgMeta = const VerificationMeta(
    'ratingAvg',
  );
  late final GeneratedColumn<double> ratingAvg = GeneratedColumn<double>(
    'rating_avg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _ratingCountMeta = const VerificationMeta(
    'ratingCount',
  );
  late final GeneratedColumn<int> ratingCount = GeneratedColumn<int>(
    'rating_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _verificationMeta = const VerificationMeta(
    'verification',
  );
  late final GeneratedColumn<String> verification = GeneratedColumn<String>(
    'verification',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'VERIFIED\'',
    defaultValue: const CustomExpression('\'VERIFIED\''),
  );
  static const VerificationMeta _reviewCountMeta = const VerificationMeta(
    'reviewCount',
  );
  late final GeneratedColumn<int> reviewCount = GeneratedColumn<int>(
    'review_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _photoCountMeta = const VerificationMeta(
    'photoCount',
  );
  late final GeneratedColumn<int> photoCount = GeneratedColumn<int>(
    'photo_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _coverPhotosJsonMeta = const VerificationMeta(
    'coverPhotosJson',
  );
  late final GeneratedColumn<String> coverPhotosJson = GeneratedColumn<String>(
    'cover_photos_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _issuesJsonMeta = const VerificationMeta(
    'issuesJson',
  );
  late final GeneratedColumn<String> issuesJson = GeneratedColumn<String>(
    'issues_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _filterRatingMeta = const VerificationMeta(
    'filterRating',
  );
  late final GeneratedColumn<double> filterRating = GeneratedColumn<double>(
    'filter_rating',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _priceServicesIncludedMeta =
      const VerificationMeta('priceServicesIncluded');
  late final GeneratedColumn<bool> priceServicesIncluded =
      GeneratedColumn<bool>(
        'price_services_included',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        $customConstraints: 'NOT NULL DEFAULT FALSE',
        defaultValue: const CustomExpression('FALSE'),
      );
  static const VerificationMeta _priceParkingIncludesMeta =
      const VerificationMeta('priceParkingIncludes');
  late final GeneratedColumn<String> priceParkingIncludes =
      GeneratedColumn<String>(
        'price_parking_includes',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        $customConstraints: 'NOT NULL DEFAULT \'[]\'',
        defaultValue: const CustomExpression('\'[]\''),
      );
  @override
  List<GeneratedColumn> get $columns => [
    rid,
    id,
    name,
    kind,
    family,
    lat,
    lon,
    overnight,
    services,
    activities,
    description,
    street,
    postcode,
    city,
    countryCode,
    priceParking,
    priceServices,
    maxHeight,
    capacity,
    openingHours,
    openingHoursParsed,
    openingIntervalsJson,
    openingValidUntil,
    stars,
    syncGen,
    website,
    phone,
    lastConfirmedAt,
    updatedAt,
    sourcesJson,
    provenanceJson,
    descriptionsJson,
    ratingsJson,
    linksJson,
    ratingAvg,
    ratingCount,
    verification,
    reviewCount,
    photoCount,
    coverPhotosJson,
    issuesJson,
    region,
    filterRating,
    priceServicesIncluded,
    priceParkingIncludes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'places';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rid')) {
      context.handle(
        _ridMeta,
        rid.isAcceptableOrUnknown(data['rid']!, _ridMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('family')) {
      context.handle(
        _familyMeta,
        family.isAcceptableOrUnknown(data['family']!, _familyMeta),
      );
    } else if (isInserting) {
      context.missing(_familyMeta);
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    } else if (isInserting) {
      context.missing(_lonMeta);
    }
    if (data.containsKey('overnight')) {
      context.handle(
        _overnightMeta,
        overnight.isAcceptableOrUnknown(data['overnight']!, _overnightMeta),
      );
    } else if (isInserting) {
      context.missing(_overnightMeta);
    }
    if (data.containsKey('services')) {
      context.handle(
        _servicesMeta,
        services.isAcceptableOrUnknown(data['services']!, _servicesMeta),
      );
    }
    if (data.containsKey('activities')) {
      context.handle(
        _activitiesMeta,
        activities.isAcceptableOrUnknown(data['activities']!, _activitiesMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('street')) {
      context.handle(
        _streetMeta,
        street.isAcceptableOrUnknown(data['street']!, _streetMeta),
      );
    }
    if (data.containsKey('postcode')) {
      context.handle(
        _postcodeMeta,
        postcode.isAcceptableOrUnknown(data['postcode']!, _postcodeMeta),
      );
    }
    if (data.containsKey('city')) {
      context.handle(
        _cityMeta,
        city.isAcceptableOrUnknown(data['city']!, _cityMeta),
      );
    }
    if (data.containsKey('country_code')) {
      context.handle(
        _countryCodeMeta,
        countryCode.isAcceptableOrUnknown(
          data['country_code']!,
          _countryCodeMeta,
        ),
      );
    }
    if (data.containsKey('price_parking')) {
      context.handle(
        _priceParkingMeta,
        priceParking.isAcceptableOrUnknown(
          data['price_parking']!,
          _priceParkingMeta,
        ),
      );
    }
    if (data.containsKey('price_services')) {
      context.handle(
        _priceServicesMeta,
        priceServices.isAcceptableOrUnknown(
          data['price_services']!,
          _priceServicesMeta,
        ),
      );
    }
    if (data.containsKey('max_height')) {
      context.handle(
        _maxHeightMeta,
        maxHeight.isAcceptableOrUnknown(data['max_height']!, _maxHeightMeta),
      );
    }
    if (data.containsKey('capacity')) {
      context.handle(
        _capacityMeta,
        capacity.isAcceptableOrUnknown(data['capacity']!, _capacityMeta),
      );
    }
    if (data.containsKey('opening_hours')) {
      context.handle(
        _openingHoursMeta,
        openingHours.isAcceptableOrUnknown(
          data['opening_hours']!,
          _openingHoursMeta,
        ),
      );
    }
    if (data.containsKey('opening_hours_parsed')) {
      context.handle(
        _openingHoursParsedMeta,
        openingHoursParsed.isAcceptableOrUnknown(
          data['opening_hours_parsed']!,
          _openingHoursParsedMeta,
        ),
      );
    }
    if (data.containsKey('opening_intervals_json')) {
      context.handle(
        _openingIntervalsJsonMeta,
        openingIntervalsJson.isAcceptableOrUnknown(
          data['opening_intervals_json']!,
          _openingIntervalsJsonMeta,
        ),
      );
    }
    if (data.containsKey('opening_valid_until')) {
      context.handle(
        _openingValidUntilMeta,
        openingValidUntil.isAcceptableOrUnknown(
          data['opening_valid_until']!,
          _openingValidUntilMeta,
        ),
      );
    }
    if (data.containsKey('stars')) {
      context.handle(
        _starsMeta,
        stars.isAcceptableOrUnknown(data['stars']!, _starsMeta),
      );
    }
    if (data.containsKey('sync_gen')) {
      context.handle(
        _syncGenMeta,
        syncGen.isAcceptableOrUnknown(data['sync_gen']!, _syncGenMeta),
      );
    }
    if (data.containsKey('website')) {
      context.handle(
        _websiteMeta,
        website.isAcceptableOrUnknown(data['website']!, _websiteMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('last_confirmed_at')) {
      context.handle(
        _lastConfirmedAtMeta,
        lastConfirmedAt.isAcceptableOrUnknown(
          data['last_confirmed_at']!,
          _lastConfirmedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sources_json')) {
      context.handle(
        _sourcesJsonMeta,
        sourcesJson.isAcceptableOrUnknown(
          data['sources_json']!,
          _sourcesJsonMeta,
        ),
      );
    }
    if (data.containsKey('provenance_json')) {
      context.handle(
        _provenanceJsonMeta,
        provenanceJson.isAcceptableOrUnknown(
          data['provenance_json']!,
          _provenanceJsonMeta,
        ),
      );
    }
    if (data.containsKey('descriptions_json')) {
      context.handle(
        _descriptionsJsonMeta,
        descriptionsJson.isAcceptableOrUnknown(
          data['descriptions_json']!,
          _descriptionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('ratings_json')) {
      context.handle(
        _ratingsJsonMeta,
        ratingsJson.isAcceptableOrUnknown(
          data['ratings_json']!,
          _ratingsJsonMeta,
        ),
      );
    }
    if (data.containsKey('links_json')) {
      context.handle(
        _linksJsonMeta,
        linksJson.isAcceptableOrUnknown(data['links_json']!, _linksJsonMeta),
      );
    }
    if (data.containsKey('rating_avg')) {
      context.handle(
        _ratingAvgMeta,
        ratingAvg.isAcceptableOrUnknown(data['rating_avg']!, _ratingAvgMeta),
      );
    }
    if (data.containsKey('rating_count')) {
      context.handle(
        _ratingCountMeta,
        ratingCount.isAcceptableOrUnknown(
          data['rating_count']!,
          _ratingCountMeta,
        ),
      );
    }
    if (data.containsKey('verification')) {
      context.handle(
        _verificationMeta,
        verification.isAcceptableOrUnknown(
          data['verification']!,
          _verificationMeta,
        ),
      );
    }
    if (data.containsKey('review_count')) {
      context.handle(
        _reviewCountMeta,
        reviewCount.isAcceptableOrUnknown(
          data['review_count']!,
          _reviewCountMeta,
        ),
      );
    }
    if (data.containsKey('photo_count')) {
      context.handle(
        _photoCountMeta,
        photoCount.isAcceptableOrUnknown(data['photo_count']!, _photoCountMeta),
      );
    }
    if (data.containsKey('cover_photos_json')) {
      context.handle(
        _coverPhotosJsonMeta,
        coverPhotosJson.isAcceptableOrUnknown(
          data['cover_photos_json']!,
          _coverPhotosJsonMeta,
        ),
      );
    }
    if (data.containsKey('issues_json')) {
      context.handle(
        _issuesJsonMeta,
        issuesJson.isAcceptableOrUnknown(data['issues_json']!, _issuesJsonMeta),
      );
    }
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    }
    if (data.containsKey('filter_rating')) {
      context.handle(
        _filterRatingMeta,
        filterRating.isAcceptableOrUnknown(
          data['filter_rating']!,
          _filterRatingMeta,
        ),
      );
    }
    if (data.containsKey('price_services_included')) {
      context.handle(
        _priceServicesIncludedMeta,
        priceServicesIncluded.isAcceptableOrUnknown(
          data['price_services_included']!,
          _priceServicesIncludedMeta,
        ),
      );
    }
    if (data.containsKey('price_parking_includes')) {
      context.handle(
        _priceParkingIncludesMeta,
        priceParkingIncludes.isAcceptableOrUnknown(
          data['price_parking_includes']!,
          _priceParkingIncludesMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rid};
  @override
  PlaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaceRow(
      rid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rid'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      family: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}family'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      )!,
      overnight: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}overnight'],
      )!,
      services: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}services'],
      )!,
      activities: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}activities'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      street: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}street'],
      ),
      postcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}postcode'],
      ),
      city: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city'],
      ),
      countryCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country_code'],
      ),
      priceParking: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price_parking'],
      ),
      priceServices: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price_services'],
      ),
      maxHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_height'],
      ),
      capacity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capacity'],
      ),
      openingHours: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opening_hours'],
      ),
      openingHoursParsed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}opening_hours_parsed'],
      )!,
      openingIntervalsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opening_intervals_json'],
      ),
      openingValidUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opening_valid_until'],
      ),
      stars: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}stars'],
      ),
      syncGen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_gen'],
      )!,
      website: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}website'],
      ),
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      lastConfirmedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_confirmed_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      sourcesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sources_json'],
      )!,
      provenanceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance_json'],
      )!,
      descriptionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}descriptions_json'],
      )!,
      ratingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ratings_json'],
      )!,
      linksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}links_json'],
      )!,
      ratingAvg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rating_avg'],
      ),
      ratingCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating_count'],
      )!,
      verification: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification'],
      )!,
      reviewCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}review_count'],
      )!,
      photoCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}photo_count'],
      )!,
      coverPhotosJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_photos_json'],
      )!,
      issuesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issues_json'],
      )!,
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      ),
      filterRating: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}filter_rating'],
      ),
      priceServicesIncluded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}price_services_included'],
      )!,
      priceParkingIncludes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}price_parking_includes'],
      )!,
    );
  }

  @override
  Places createAlias(String alias) {
    return Places(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PlaceRow extends DataClass implements Insertable<PlaceRow> {
  /// The integer key the R*Tree and FTS5 indexes need; the API id stays the
  /// identity every caller uses.
  final int rid;
  final String id;
  final String? name;
  final String kind;

  /// KindFamily index, so a family filter is an integer IN list.
  final int family;
  final double lat;
  final double lon;
  final String overnight;

  /// Bit masks of Service and Activity (taxonomy.dart, pinned bits).
  final int services;
  final int activities;
  final String? description;
  final String? street;
  final String? postcode;
  final String? city;
  final String? countryCode;
  final double? priceParking;
  final double? priceServices;
  final double? maxHeight;
  final int? capacity;
  final String? openingHours;
  final bool openingHoursParsed;

  /// JSON list of {start, end} in UTC; null when the server sent none.
  final String? openingIntervalsJson;

  /// End of the window the intervals cover, as the server sent it.
  final int? openingValidUntil;

  /// Official classification, 1 to 5.
  final int? stars;

  /// The full sync generation that last wrote the place: when a full sync
  /// ends, the places of its region it did not write are gone from the
  /// server. A counter, not a time, so a clock change cannot sweep the
  /// wrong places.
  final int syncGen;
  final String? website;
  final String? phone;
  final int? lastConfirmedAt;
  final int updatedAt;
  final String sourcesJson;
  final String provenanceJson;
  final String descriptionsJson;
  final String ratingsJson;
  final String linksJson;

  /// The ratings combined across sources, for the list rows without JSON.
  final double? ratingAvg;
  final int ratingCount;

  /// What the community says of the place (added in version 2): whether it
  /// waits for confirmations, its counts, its latest photos (with their
  /// authors, for the mutes) and the issues reported over 30 days.
  final String verification;
  final int reviewCount;
  final int photoCount;
  final String coverPhotosJson;
  final String issuesJson;

  /// The sync region the place came with (`FR-BRE`, `ES`; added in
  /// version 4): a region's full sync sweeps its own places, and removing a
  /// region removes them. Null for a place of the sync by box of earlier
  /// versions, until the region syncs it again.
  final String? region;

  /// The rating the minimum rating filter compares (added in version 6):
  /// the server's `ratingForFilters`, Lunaway users' average or else the
  /// other sources'; null when nobody rated the place.
  final double? filterRating;

  /// What the prices include (added in version 7): whether the services
  /// come with the night, and the JSON list of what the night's price
  /// includes (PriceInclusion wires).
  final bool priceServicesIncluded;
  final String priceParkingIncludes;
  const PlaceRow({
    required this.rid,
    required this.id,
    this.name,
    required this.kind,
    required this.family,
    required this.lat,
    required this.lon,
    required this.overnight,
    required this.services,
    required this.activities,
    this.description,
    this.street,
    this.postcode,
    this.city,
    this.countryCode,
    this.priceParking,
    this.priceServices,
    this.maxHeight,
    this.capacity,
    this.openingHours,
    required this.openingHoursParsed,
    this.openingIntervalsJson,
    this.openingValidUntil,
    this.stars,
    required this.syncGen,
    this.website,
    this.phone,
    this.lastConfirmedAt,
    required this.updatedAt,
    required this.sourcesJson,
    required this.provenanceJson,
    required this.descriptionsJson,
    required this.ratingsJson,
    required this.linksJson,
    this.ratingAvg,
    required this.ratingCount,
    required this.verification,
    required this.reviewCount,
    required this.photoCount,
    required this.coverPhotosJson,
    required this.issuesJson,
    this.region,
    this.filterRating,
    required this.priceServicesIncluded,
    required this.priceParkingIncludes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rid'] = Variable<int>(rid);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['kind'] = Variable<String>(kind);
    map['family'] = Variable<int>(family);
    map['lat'] = Variable<double>(lat);
    map['lon'] = Variable<double>(lon);
    map['overnight'] = Variable<String>(overnight);
    map['services'] = Variable<int>(services);
    map['activities'] = Variable<int>(activities);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || street != null) {
      map['street'] = Variable<String>(street);
    }
    if (!nullToAbsent || postcode != null) {
      map['postcode'] = Variable<String>(postcode);
    }
    if (!nullToAbsent || city != null) {
      map['city'] = Variable<String>(city);
    }
    if (!nullToAbsent || countryCode != null) {
      map['country_code'] = Variable<String>(countryCode);
    }
    if (!nullToAbsent || priceParking != null) {
      map['price_parking'] = Variable<double>(priceParking);
    }
    if (!nullToAbsent || priceServices != null) {
      map['price_services'] = Variable<double>(priceServices);
    }
    if (!nullToAbsent || maxHeight != null) {
      map['max_height'] = Variable<double>(maxHeight);
    }
    if (!nullToAbsent || capacity != null) {
      map['capacity'] = Variable<int>(capacity);
    }
    if (!nullToAbsent || openingHours != null) {
      map['opening_hours'] = Variable<String>(openingHours);
    }
    map['opening_hours_parsed'] = Variable<bool>(openingHoursParsed);
    if (!nullToAbsent || openingIntervalsJson != null) {
      map['opening_intervals_json'] = Variable<String>(openingIntervalsJson);
    }
    if (!nullToAbsent || openingValidUntil != null) {
      map['opening_valid_until'] = Variable<int>(openingValidUntil);
    }
    if (!nullToAbsent || stars != null) {
      map['stars'] = Variable<int>(stars);
    }
    map['sync_gen'] = Variable<int>(syncGen);
    if (!nullToAbsent || website != null) {
      map['website'] = Variable<String>(website);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || lastConfirmedAt != null) {
      map['last_confirmed_at'] = Variable<int>(lastConfirmedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['sources_json'] = Variable<String>(sourcesJson);
    map['provenance_json'] = Variable<String>(provenanceJson);
    map['descriptions_json'] = Variable<String>(descriptionsJson);
    map['ratings_json'] = Variable<String>(ratingsJson);
    map['links_json'] = Variable<String>(linksJson);
    if (!nullToAbsent || ratingAvg != null) {
      map['rating_avg'] = Variable<double>(ratingAvg);
    }
    map['rating_count'] = Variable<int>(ratingCount);
    map['verification'] = Variable<String>(verification);
    map['review_count'] = Variable<int>(reviewCount);
    map['photo_count'] = Variable<int>(photoCount);
    map['cover_photos_json'] = Variable<String>(coverPhotosJson);
    map['issues_json'] = Variable<String>(issuesJson);
    if (!nullToAbsent || region != null) {
      map['region'] = Variable<String>(region);
    }
    if (!nullToAbsent || filterRating != null) {
      map['filter_rating'] = Variable<double>(filterRating);
    }
    map['price_services_included'] = Variable<bool>(priceServicesIncluded);
    map['price_parking_includes'] = Variable<String>(priceParkingIncludes);
    return map;
  }

  PlacesCompanion toCompanion(bool nullToAbsent) {
    return PlacesCompanion(
      rid: Value(rid),
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      kind: Value(kind),
      family: Value(family),
      lat: Value(lat),
      lon: Value(lon),
      overnight: Value(overnight),
      services: Value(services),
      activities: Value(activities),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      street: street == null && nullToAbsent
          ? const Value.absent()
          : Value(street),
      postcode: postcode == null && nullToAbsent
          ? const Value.absent()
          : Value(postcode),
      city: city == null && nullToAbsent ? const Value.absent() : Value(city),
      countryCode: countryCode == null && nullToAbsent
          ? const Value.absent()
          : Value(countryCode),
      priceParking: priceParking == null && nullToAbsent
          ? const Value.absent()
          : Value(priceParking),
      priceServices: priceServices == null && nullToAbsent
          ? const Value.absent()
          : Value(priceServices),
      maxHeight: maxHeight == null && nullToAbsent
          ? const Value.absent()
          : Value(maxHeight),
      capacity: capacity == null && nullToAbsent
          ? const Value.absent()
          : Value(capacity),
      openingHours: openingHours == null && nullToAbsent
          ? const Value.absent()
          : Value(openingHours),
      openingHoursParsed: Value(openingHoursParsed),
      openingIntervalsJson: openingIntervalsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(openingIntervalsJson),
      openingValidUntil: openingValidUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(openingValidUntil),
      stars: stars == null && nullToAbsent
          ? const Value.absent()
          : Value(stars),
      syncGen: Value(syncGen),
      website: website == null && nullToAbsent
          ? const Value.absent()
          : Value(website),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      lastConfirmedAt: lastConfirmedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConfirmedAt),
      updatedAt: Value(updatedAt),
      sourcesJson: Value(sourcesJson),
      provenanceJson: Value(provenanceJson),
      descriptionsJson: Value(descriptionsJson),
      ratingsJson: Value(ratingsJson),
      linksJson: Value(linksJson),
      ratingAvg: ratingAvg == null && nullToAbsent
          ? const Value.absent()
          : Value(ratingAvg),
      ratingCount: Value(ratingCount),
      verification: Value(verification),
      reviewCount: Value(reviewCount),
      photoCount: Value(photoCount),
      coverPhotosJson: Value(coverPhotosJson),
      issuesJson: Value(issuesJson),
      region: region == null && nullToAbsent
          ? const Value.absent()
          : Value(region),
      filterRating: filterRating == null && nullToAbsent
          ? const Value.absent()
          : Value(filterRating),
      priceServicesIncluded: Value(priceServicesIncluded),
      priceParkingIncludes: Value(priceParkingIncludes),
    );
  }

  factory PlaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaceRow(
      rid: serializer.fromJson<int>(json['rid']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      family: serializer.fromJson<int>(json['family']),
      lat: serializer.fromJson<double>(json['lat']),
      lon: serializer.fromJson<double>(json['lon']),
      overnight: serializer.fromJson<String>(json['overnight']),
      services: serializer.fromJson<int>(json['services']),
      activities: serializer.fromJson<int>(json['activities']),
      description: serializer.fromJson<String?>(json['description']),
      street: serializer.fromJson<String?>(json['street']),
      postcode: serializer.fromJson<String?>(json['postcode']),
      city: serializer.fromJson<String?>(json['city']),
      countryCode: serializer.fromJson<String?>(json['country_code']),
      priceParking: serializer.fromJson<double?>(json['price_parking']),
      priceServices: serializer.fromJson<double?>(json['price_services']),
      maxHeight: serializer.fromJson<double?>(json['max_height']),
      capacity: serializer.fromJson<int?>(json['capacity']),
      openingHours: serializer.fromJson<String?>(json['opening_hours']),
      openingHoursParsed: serializer.fromJson<bool>(
        json['opening_hours_parsed'],
      ),
      openingIntervalsJson: serializer.fromJson<String?>(
        json['opening_intervals_json'],
      ),
      openingValidUntil: serializer.fromJson<int?>(json['opening_valid_until']),
      stars: serializer.fromJson<int?>(json['stars']),
      syncGen: serializer.fromJson<int>(json['sync_gen']),
      website: serializer.fromJson<String?>(json['website']),
      phone: serializer.fromJson<String?>(json['phone']),
      lastConfirmedAt: serializer.fromJson<int?>(json['last_confirmed_at']),
      updatedAt: serializer.fromJson<int>(json['updated_at']),
      sourcesJson: serializer.fromJson<String>(json['sources_json']),
      provenanceJson: serializer.fromJson<String>(json['provenance_json']),
      descriptionsJson: serializer.fromJson<String>(json['descriptions_json']),
      ratingsJson: serializer.fromJson<String>(json['ratings_json']),
      linksJson: serializer.fromJson<String>(json['links_json']),
      ratingAvg: serializer.fromJson<double?>(json['rating_avg']),
      ratingCount: serializer.fromJson<int>(json['rating_count']),
      verification: serializer.fromJson<String>(json['verification']),
      reviewCount: serializer.fromJson<int>(json['review_count']),
      photoCount: serializer.fromJson<int>(json['photo_count']),
      coverPhotosJson: serializer.fromJson<String>(json['cover_photos_json']),
      issuesJson: serializer.fromJson<String>(json['issues_json']),
      region: serializer.fromJson<String?>(json['region']),
      filterRating: serializer.fromJson<double?>(json['filter_rating']),
      priceServicesIncluded: serializer.fromJson<bool>(
        json['price_services_included'],
      ),
      priceParkingIncludes: serializer.fromJson<String>(
        json['price_parking_includes'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rid': serializer.toJson<int>(rid),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String?>(name),
      'kind': serializer.toJson<String>(kind),
      'family': serializer.toJson<int>(family),
      'lat': serializer.toJson<double>(lat),
      'lon': serializer.toJson<double>(lon),
      'overnight': serializer.toJson<String>(overnight),
      'services': serializer.toJson<int>(services),
      'activities': serializer.toJson<int>(activities),
      'description': serializer.toJson<String?>(description),
      'street': serializer.toJson<String?>(street),
      'postcode': serializer.toJson<String?>(postcode),
      'city': serializer.toJson<String?>(city),
      'country_code': serializer.toJson<String?>(countryCode),
      'price_parking': serializer.toJson<double?>(priceParking),
      'price_services': serializer.toJson<double?>(priceServices),
      'max_height': serializer.toJson<double?>(maxHeight),
      'capacity': serializer.toJson<int?>(capacity),
      'opening_hours': serializer.toJson<String?>(openingHours),
      'opening_hours_parsed': serializer.toJson<bool>(openingHoursParsed),
      'opening_intervals_json': serializer.toJson<String?>(
        openingIntervalsJson,
      ),
      'opening_valid_until': serializer.toJson<int?>(openingValidUntil),
      'stars': serializer.toJson<int?>(stars),
      'sync_gen': serializer.toJson<int>(syncGen),
      'website': serializer.toJson<String?>(website),
      'phone': serializer.toJson<String?>(phone),
      'last_confirmed_at': serializer.toJson<int?>(lastConfirmedAt),
      'updated_at': serializer.toJson<int>(updatedAt),
      'sources_json': serializer.toJson<String>(sourcesJson),
      'provenance_json': serializer.toJson<String>(provenanceJson),
      'descriptions_json': serializer.toJson<String>(descriptionsJson),
      'ratings_json': serializer.toJson<String>(ratingsJson),
      'links_json': serializer.toJson<String>(linksJson),
      'rating_avg': serializer.toJson<double?>(ratingAvg),
      'rating_count': serializer.toJson<int>(ratingCount),
      'verification': serializer.toJson<String>(verification),
      'review_count': serializer.toJson<int>(reviewCount),
      'photo_count': serializer.toJson<int>(photoCount),
      'cover_photos_json': serializer.toJson<String>(coverPhotosJson),
      'issues_json': serializer.toJson<String>(issuesJson),
      'region': serializer.toJson<String?>(region),
      'filter_rating': serializer.toJson<double?>(filterRating),
      'price_services_included': serializer.toJson<bool>(priceServicesIncluded),
      'price_parking_includes': serializer.toJson<String>(priceParkingIncludes),
    };
  }

  PlaceRow copyWith({
    int? rid,
    String? id,
    Value<String?> name = const Value.absent(),
    String? kind,
    int? family,
    double? lat,
    double? lon,
    String? overnight,
    int? services,
    int? activities,
    Value<String?> description = const Value.absent(),
    Value<String?> street = const Value.absent(),
    Value<String?> postcode = const Value.absent(),
    Value<String?> city = const Value.absent(),
    Value<String?> countryCode = const Value.absent(),
    Value<double?> priceParking = const Value.absent(),
    Value<double?> priceServices = const Value.absent(),
    Value<double?> maxHeight = const Value.absent(),
    Value<int?> capacity = const Value.absent(),
    Value<String?> openingHours = const Value.absent(),
    bool? openingHoursParsed,
    Value<String?> openingIntervalsJson = const Value.absent(),
    Value<int?> openingValidUntil = const Value.absent(),
    Value<int?> stars = const Value.absent(),
    int? syncGen,
    Value<String?> website = const Value.absent(),
    Value<String?> phone = const Value.absent(),
    Value<int?> lastConfirmedAt = const Value.absent(),
    int? updatedAt,
    String? sourcesJson,
    String? provenanceJson,
    String? descriptionsJson,
    String? ratingsJson,
    String? linksJson,
    Value<double?> ratingAvg = const Value.absent(),
    int? ratingCount,
    String? verification,
    int? reviewCount,
    int? photoCount,
    String? coverPhotosJson,
    String? issuesJson,
    Value<String?> region = const Value.absent(),
    Value<double?> filterRating = const Value.absent(),
    bool? priceServicesIncluded,
    String? priceParkingIncludes,
  }) => PlaceRow(
    rid: rid ?? this.rid,
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    kind: kind ?? this.kind,
    family: family ?? this.family,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
    overnight: overnight ?? this.overnight,
    services: services ?? this.services,
    activities: activities ?? this.activities,
    description: description.present ? description.value : this.description,
    street: street.present ? street.value : this.street,
    postcode: postcode.present ? postcode.value : this.postcode,
    city: city.present ? city.value : this.city,
    countryCode: countryCode.present ? countryCode.value : this.countryCode,
    priceParking: priceParking.present ? priceParking.value : this.priceParking,
    priceServices: priceServices.present
        ? priceServices.value
        : this.priceServices,
    maxHeight: maxHeight.present ? maxHeight.value : this.maxHeight,
    capacity: capacity.present ? capacity.value : this.capacity,
    openingHours: openingHours.present ? openingHours.value : this.openingHours,
    openingHoursParsed: openingHoursParsed ?? this.openingHoursParsed,
    openingIntervalsJson: openingIntervalsJson.present
        ? openingIntervalsJson.value
        : this.openingIntervalsJson,
    openingValidUntil: openingValidUntil.present
        ? openingValidUntil.value
        : this.openingValidUntil,
    stars: stars.present ? stars.value : this.stars,
    syncGen: syncGen ?? this.syncGen,
    website: website.present ? website.value : this.website,
    phone: phone.present ? phone.value : this.phone,
    lastConfirmedAt: lastConfirmedAt.present
        ? lastConfirmedAt.value
        : this.lastConfirmedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    sourcesJson: sourcesJson ?? this.sourcesJson,
    provenanceJson: provenanceJson ?? this.provenanceJson,
    descriptionsJson: descriptionsJson ?? this.descriptionsJson,
    ratingsJson: ratingsJson ?? this.ratingsJson,
    linksJson: linksJson ?? this.linksJson,
    ratingAvg: ratingAvg.present ? ratingAvg.value : this.ratingAvg,
    ratingCount: ratingCount ?? this.ratingCount,
    verification: verification ?? this.verification,
    reviewCount: reviewCount ?? this.reviewCount,
    photoCount: photoCount ?? this.photoCount,
    coverPhotosJson: coverPhotosJson ?? this.coverPhotosJson,
    issuesJson: issuesJson ?? this.issuesJson,
    region: region.present ? region.value : this.region,
    filterRating: filterRating.present ? filterRating.value : this.filterRating,
    priceServicesIncluded: priceServicesIncluded ?? this.priceServicesIncluded,
    priceParkingIncludes: priceParkingIncludes ?? this.priceParkingIncludes,
  );
  PlaceRow copyWithCompanion(PlacesCompanion data) {
    return PlaceRow(
      rid: data.rid.present ? data.rid.value : this.rid,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      family: data.family.present ? data.family.value : this.family,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      overnight: data.overnight.present ? data.overnight.value : this.overnight,
      services: data.services.present ? data.services.value : this.services,
      activities: data.activities.present
          ? data.activities.value
          : this.activities,
      description: data.description.present
          ? data.description.value
          : this.description,
      street: data.street.present ? data.street.value : this.street,
      postcode: data.postcode.present ? data.postcode.value : this.postcode,
      city: data.city.present ? data.city.value : this.city,
      countryCode: data.countryCode.present
          ? data.countryCode.value
          : this.countryCode,
      priceParking: data.priceParking.present
          ? data.priceParking.value
          : this.priceParking,
      priceServices: data.priceServices.present
          ? data.priceServices.value
          : this.priceServices,
      maxHeight: data.maxHeight.present ? data.maxHeight.value : this.maxHeight,
      capacity: data.capacity.present ? data.capacity.value : this.capacity,
      openingHours: data.openingHours.present
          ? data.openingHours.value
          : this.openingHours,
      openingHoursParsed: data.openingHoursParsed.present
          ? data.openingHoursParsed.value
          : this.openingHoursParsed,
      openingIntervalsJson: data.openingIntervalsJson.present
          ? data.openingIntervalsJson.value
          : this.openingIntervalsJson,
      openingValidUntil: data.openingValidUntil.present
          ? data.openingValidUntil.value
          : this.openingValidUntil,
      stars: data.stars.present ? data.stars.value : this.stars,
      syncGen: data.syncGen.present ? data.syncGen.value : this.syncGen,
      website: data.website.present ? data.website.value : this.website,
      phone: data.phone.present ? data.phone.value : this.phone,
      lastConfirmedAt: data.lastConfirmedAt.present
          ? data.lastConfirmedAt.value
          : this.lastConfirmedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sourcesJson: data.sourcesJson.present
          ? data.sourcesJson.value
          : this.sourcesJson,
      provenanceJson: data.provenanceJson.present
          ? data.provenanceJson.value
          : this.provenanceJson,
      descriptionsJson: data.descriptionsJson.present
          ? data.descriptionsJson.value
          : this.descriptionsJson,
      ratingsJson: data.ratingsJson.present
          ? data.ratingsJson.value
          : this.ratingsJson,
      linksJson: data.linksJson.present ? data.linksJson.value : this.linksJson,
      ratingAvg: data.ratingAvg.present ? data.ratingAvg.value : this.ratingAvg,
      ratingCount: data.ratingCount.present
          ? data.ratingCount.value
          : this.ratingCount,
      verification: data.verification.present
          ? data.verification.value
          : this.verification,
      reviewCount: data.reviewCount.present
          ? data.reviewCount.value
          : this.reviewCount,
      photoCount: data.photoCount.present
          ? data.photoCount.value
          : this.photoCount,
      coverPhotosJson: data.coverPhotosJson.present
          ? data.coverPhotosJson.value
          : this.coverPhotosJson,
      issuesJson: data.issuesJson.present
          ? data.issuesJson.value
          : this.issuesJson,
      region: data.region.present ? data.region.value : this.region,
      filterRating: data.filterRating.present
          ? data.filterRating.value
          : this.filterRating,
      priceServicesIncluded: data.priceServicesIncluded.present
          ? data.priceServicesIncluded.value
          : this.priceServicesIncluded,
      priceParkingIncludes: data.priceParkingIncludes.present
          ? data.priceParkingIncludes.value
          : this.priceParkingIncludes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaceRow(')
          ..write('rid: $rid, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('family: $family, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('overnight: $overnight, ')
          ..write('services: $services, ')
          ..write('activities: $activities, ')
          ..write('description: $description, ')
          ..write('street: $street, ')
          ..write('postcode: $postcode, ')
          ..write('city: $city, ')
          ..write('countryCode: $countryCode, ')
          ..write('priceParking: $priceParking, ')
          ..write('priceServices: $priceServices, ')
          ..write('maxHeight: $maxHeight, ')
          ..write('capacity: $capacity, ')
          ..write('openingHours: $openingHours, ')
          ..write('openingHoursParsed: $openingHoursParsed, ')
          ..write('openingIntervalsJson: $openingIntervalsJson, ')
          ..write('openingValidUntil: $openingValidUntil, ')
          ..write('stars: $stars, ')
          ..write('syncGen: $syncGen, ')
          ..write('website: $website, ')
          ..write('phone: $phone, ')
          ..write('lastConfirmedAt: $lastConfirmedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('provenanceJson: $provenanceJson, ')
          ..write('descriptionsJson: $descriptionsJson, ')
          ..write('ratingsJson: $ratingsJson, ')
          ..write('linksJson: $linksJson, ')
          ..write('ratingAvg: $ratingAvg, ')
          ..write('ratingCount: $ratingCount, ')
          ..write('verification: $verification, ')
          ..write('reviewCount: $reviewCount, ')
          ..write('photoCount: $photoCount, ')
          ..write('coverPhotosJson: $coverPhotosJson, ')
          ..write('issuesJson: $issuesJson, ')
          ..write('region: $region, ')
          ..write('filterRating: $filterRating, ')
          ..write('priceServicesIncluded: $priceServicesIncluded, ')
          ..write('priceParkingIncludes: $priceParkingIncludes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    rid,
    id,
    name,
    kind,
    family,
    lat,
    lon,
    overnight,
    services,
    activities,
    description,
    street,
    postcode,
    city,
    countryCode,
    priceParking,
    priceServices,
    maxHeight,
    capacity,
    openingHours,
    openingHoursParsed,
    openingIntervalsJson,
    openingValidUntil,
    stars,
    syncGen,
    website,
    phone,
    lastConfirmedAt,
    updatedAt,
    sourcesJson,
    provenanceJson,
    descriptionsJson,
    ratingsJson,
    linksJson,
    ratingAvg,
    ratingCount,
    verification,
    reviewCount,
    photoCount,
    coverPhotosJson,
    issuesJson,
    region,
    filterRating,
    priceServicesIncluded,
    priceParkingIncludes,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaceRow &&
          other.rid == this.rid &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.family == this.family &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.overnight == this.overnight &&
          other.services == this.services &&
          other.activities == this.activities &&
          other.description == this.description &&
          other.street == this.street &&
          other.postcode == this.postcode &&
          other.city == this.city &&
          other.countryCode == this.countryCode &&
          other.priceParking == this.priceParking &&
          other.priceServices == this.priceServices &&
          other.maxHeight == this.maxHeight &&
          other.capacity == this.capacity &&
          other.openingHours == this.openingHours &&
          other.openingHoursParsed == this.openingHoursParsed &&
          other.openingIntervalsJson == this.openingIntervalsJson &&
          other.openingValidUntil == this.openingValidUntil &&
          other.stars == this.stars &&
          other.syncGen == this.syncGen &&
          other.website == this.website &&
          other.phone == this.phone &&
          other.lastConfirmedAt == this.lastConfirmedAt &&
          other.updatedAt == this.updatedAt &&
          other.sourcesJson == this.sourcesJson &&
          other.provenanceJson == this.provenanceJson &&
          other.descriptionsJson == this.descriptionsJson &&
          other.ratingsJson == this.ratingsJson &&
          other.linksJson == this.linksJson &&
          other.ratingAvg == this.ratingAvg &&
          other.ratingCount == this.ratingCount &&
          other.verification == this.verification &&
          other.reviewCount == this.reviewCount &&
          other.photoCount == this.photoCount &&
          other.coverPhotosJson == this.coverPhotosJson &&
          other.issuesJson == this.issuesJson &&
          other.region == this.region &&
          other.filterRating == this.filterRating &&
          other.priceServicesIncluded == this.priceServicesIncluded &&
          other.priceParkingIncludes == this.priceParkingIncludes);
}

class PlacesCompanion extends UpdateCompanion<PlaceRow> {
  final Value<int> rid;
  final Value<String> id;
  final Value<String?> name;
  final Value<String> kind;
  final Value<int> family;
  final Value<double> lat;
  final Value<double> lon;
  final Value<String> overnight;
  final Value<int> services;
  final Value<int> activities;
  final Value<String?> description;
  final Value<String?> street;
  final Value<String?> postcode;
  final Value<String?> city;
  final Value<String?> countryCode;
  final Value<double?> priceParking;
  final Value<double?> priceServices;
  final Value<double?> maxHeight;
  final Value<int?> capacity;
  final Value<String?> openingHours;
  final Value<bool> openingHoursParsed;
  final Value<String?> openingIntervalsJson;
  final Value<int?> openingValidUntil;
  final Value<int?> stars;
  final Value<int> syncGen;
  final Value<String?> website;
  final Value<String?> phone;
  final Value<int?> lastConfirmedAt;
  final Value<int> updatedAt;
  final Value<String> sourcesJson;
  final Value<String> provenanceJson;
  final Value<String> descriptionsJson;
  final Value<String> ratingsJson;
  final Value<String> linksJson;
  final Value<double?> ratingAvg;
  final Value<int> ratingCount;
  final Value<String> verification;
  final Value<int> reviewCount;
  final Value<int> photoCount;
  final Value<String> coverPhotosJson;
  final Value<String> issuesJson;
  final Value<String?> region;
  final Value<double?> filterRating;
  final Value<bool> priceServicesIncluded;
  final Value<String> priceParkingIncludes;
  const PlacesCompanion({
    this.rid = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.family = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.overnight = const Value.absent(),
    this.services = const Value.absent(),
    this.activities = const Value.absent(),
    this.description = const Value.absent(),
    this.street = const Value.absent(),
    this.postcode = const Value.absent(),
    this.city = const Value.absent(),
    this.countryCode = const Value.absent(),
    this.priceParking = const Value.absent(),
    this.priceServices = const Value.absent(),
    this.maxHeight = const Value.absent(),
    this.capacity = const Value.absent(),
    this.openingHours = const Value.absent(),
    this.openingHoursParsed = const Value.absent(),
    this.openingIntervalsJson = const Value.absent(),
    this.openingValidUntil = const Value.absent(),
    this.stars = const Value.absent(),
    this.syncGen = const Value.absent(),
    this.website = const Value.absent(),
    this.phone = const Value.absent(),
    this.lastConfirmedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.provenanceJson = const Value.absent(),
    this.descriptionsJson = const Value.absent(),
    this.ratingsJson = const Value.absent(),
    this.linksJson = const Value.absent(),
    this.ratingAvg = const Value.absent(),
    this.ratingCount = const Value.absent(),
    this.verification = const Value.absent(),
    this.reviewCount = const Value.absent(),
    this.photoCount = const Value.absent(),
    this.coverPhotosJson = const Value.absent(),
    this.issuesJson = const Value.absent(),
    this.region = const Value.absent(),
    this.filterRating = const Value.absent(),
    this.priceServicesIncluded = const Value.absent(),
    this.priceParkingIncludes = const Value.absent(),
  });
  PlacesCompanion.insert({
    this.rid = const Value.absent(),
    required String id,
    this.name = const Value.absent(),
    required String kind,
    required int family,
    required double lat,
    required double lon,
    required String overnight,
    this.services = const Value.absent(),
    this.activities = const Value.absent(),
    this.description = const Value.absent(),
    this.street = const Value.absent(),
    this.postcode = const Value.absent(),
    this.city = const Value.absent(),
    this.countryCode = const Value.absent(),
    this.priceParking = const Value.absent(),
    this.priceServices = const Value.absent(),
    this.maxHeight = const Value.absent(),
    this.capacity = const Value.absent(),
    this.openingHours = const Value.absent(),
    this.openingHoursParsed = const Value.absent(),
    this.openingIntervalsJson = const Value.absent(),
    this.openingValidUntil = const Value.absent(),
    this.stars = const Value.absent(),
    this.syncGen = const Value.absent(),
    this.website = const Value.absent(),
    this.phone = const Value.absent(),
    this.lastConfirmedAt = const Value.absent(),
    required int updatedAt,
    this.sourcesJson = const Value.absent(),
    this.provenanceJson = const Value.absent(),
    this.descriptionsJson = const Value.absent(),
    this.ratingsJson = const Value.absent(),
    this.linksJson = const Value.absent(),
    this.ratingAvg = const Value.absent(),
    this.ratingCount = const Value.absent(),
    this.verification = const Value.absent(),
    this.reviewCount = const Value.absent(),
    this.photoCount = const Value.absent(),
    this.coverPhotosJson = const Value.absent(),
    this.issuesJson = const Value.absent(),
    this.region = const Value.absent(),
    this.filterRating = const Value.absent(),
    this.priceServicesIncluded = const Value.absent(),
    this.priceParkingIncludes = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       family = Value(family),
       lat = Value(lat),
       lon = Value(lon),
       overnight = Value(overnight),
       updatedAt = Value(updatedAt);
  static Insertable<PlaceRow> custom({
    Expression<int>? rid,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<int>? family,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<String>? overnight,
    Expression<int>? services,
    Expression<int>? activities,
    Expression<String>? description,
    Expression<String>? street,
    Expression<String>? postcode,
    Expression<String>? city,
    Expression<String>? countryCode,
    Expression<double>? priceParking,
    Expression<double>? priceServices,
    Expression<double>? maxHeight,
    Expression<int>? capacity,
    Expression<String>? openingHours,
    Expression<bool>? openingHoursParsed,
    Expression<String>? openingIntervalsJson,
    Expression<int>? openingValidUntil,
    Expression<int>? stars,
    Expression<int>? syncGen,
    Expression<String>? website,
    Expression<String>? phone,
    Expression<int>? lastConfirmedAt,
    Expression<int>? updatedAt,
    Expression<String>? sourcesJson,
    Expression<String>? provenanceJson,
    Expression<String>? descriptionsJson,
    Expression<String>? ratingsJson,
    Expression<String>? linksJson,
    Expression<double>? ratingAvg,
    Expression<int>? ratingCount,
    Expression<String>? verification,
    Expression<int>? reviewCount,
    Expression<int>? photoCount,
    Expression<String>? coverPhotosJson,
    Expression<String>? issuesJson,
    Expression<String>? region,
    Expression<double>? filterRating,
    Expression<bool>? priceServicesIncluded,
    Expression<String>? priceParkingIncludes,
  }) {
    return RawValuesInsertable({
      if (rid != null) 'rid': rid,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (family != null) 'family': family,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (overnight != null) 'overnight': overnight,
      if (services != null) 'services': services,
      if (activities != null) 'activities': activities,
      if (description != null) 'description': description,
      if (street != null) 'street': street,
      if (postcode != null) 'postcode': postcode,
      if (city != null) 'city': city,
      if (countryCode != null) 'country_code': countryCode,
      if (priceParking != null) 'price_parking': priceParking,
      if (priceServices != null) 'price_services': priceServices,
      if (maxHeight != null) 'max_height': maxHeight,
      if (capacity != null) 'capacity': capacity,
      if (openingHours != null) 'opening_hours': openingHours,
      if (openingHoursParsed != null)
        'opening_hours_parsed': openingHoursParsed,
      if (openingIntervalsJson != null)
        'opening_intervals_json': openingIntervalsJson,
      if (openingValidUntil != null) 'opening_valid_until': openingValidUntil,
      if (stars != null) 'stars': stars,
      if (syncGen != null) 'sync_gen': syncGen,
      if (website != null) 'website': website,
      if (phone != null) 'phone': phone,
      if (lastConfirmedAt != null) 'last_confirmed_at': lastConfirmedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sourcesJson != null) 'sources_json': sourcesJson,
      if (provenanceJson != null) 'provenance_json': provenanceJson,
      if (descriptionsJson != null) 'descriptions_json': descriptionsJson,
      if (ratingsJson != null) 'ratings_json': ratingsJson,
      if (linksJson != null) 'links_json': linksJson,
      if (ratingAvg != null) 'rating_avg': ratingAvg,
      if (ratingCount != null) 'rating_count': ratingCount,
      if (verification != null) 'verification': verification,
      if (reviewCount != null) 'review_count': reviewCount,
      if (photoCount != null) 'photo_count': photoCount,
      if (coverPhotosJson != null) 'cover_photos_json': coverPhotosJson,
      if (issuesJson != null) 'issues_json': issuesJson,
      if (region != null) 'region': region,
      if (filterRating != null) 'filter_rating': filterRating,
      if (priceServicesIncluded != null)
        'price_services_included': priceServicesIncluded,
      if (priceParkingIncludes != null)
        'price_parking_includes': priceParkingIncludes,
    });
  }

  PlacesCompanion copyWith({
    Value<int>? rid,
    Value<String>? id,
    Value<String?>? name,
    Value<String>? kind,
    Value<int>? family,
    Value<double>? lat,
    Value<double>? lon,
    Value<String>? overnight,
    Value<int>? services,
    Value<int>? activities,
    Value<String?>? description,
    Value<String?>? street,
    Value<String?>? postcode,
    Value<String?>? city,
    Value<String?>? countryCode,
    Value<double?>? priceParking,
    Value<double?>? priceServices,
    Value<double?>? maxHeight,
    Value<int?>? capacity,
    Value<String?>? openingHours,
    Value<bool>? openingHoursParsed,
    Value<String?>? openingIntervalsJson,
    Value<int?>? openingValidUntil,
    Value<int?>? stars,
    Value<int>? syncGen,
    Value<String?>? website,
    Value<String?>? phone,
    Value<int?>? lastConfirmedAt,
    Value<int>? updatedAt,
    Value<String>? sourcesJson,
    Value<String>? provenanceJson,
    Value<String>? descriptionsJson,
    Value<String>? ratingsJson,
    Value<String>? linksJson,
    Value<double?>? ratingAvg,
    Value<int>? ratingCount,
    Value<String>? verification,
    Value<int>? reviewCount,
    Value<int>? photoCount,
    Value<String>? coverPhotosJson,
    Value<String>? issuesJson,
    Value<String?>? region,
    Value<double?>? filterRating,
    Value<bool>? priceServicesIncluded,
    Value<String>? priceParkingIncludes,
  }) {
    return PlacesCompanion(
      rid: rid ?? this.rid,
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      family: family ?? this.family,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      overnight: overnight ?? this.overnight,
      services: services ?? this.services,
      activities: activities ?? this.activities,
      description: description ?? this.description,
      street: street ?? this.street,
      postcode: postcode ?? this.postcode,
      city: city ?? this.city,
      countryCode: countryCode ?? this.countryCode,
      priceParking: priceParking ?? this.priceParking,
      priceServices: priceServices ?? this.priceServices,
      maxHeight: maxHeight ?? this.maxHeight,
      capacity: capacity ?? this.capacity,
      openingHours: openingHours ?? this.openingHours,
      openingHoursParsed: openingHoursParsed ?? this.openingHoursParsed,
      openingIntervalsJson: openingIntervalsJson ?? this.openingIntervalsJson,
      openingValidUntil: openingValidUntil ?? this.openingValidUntil,
      stars: stars ?? this.stars,
      syncGen: syncGen ?? this.syncGen,
      website: website ?? this.website,
      phone: phone ?? this.phone,
      lastConfirmedAt: lastConfirmedAt ?? this.lastConfirmedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourcesJson: sourcesJson ?? this.sourcesJson,
      provenanceJson: provenanceJson ?? this.provenanceJson,
      descriptionsJson: descriptionsJson ?? this.descriptionsJson,
      ratingsJson: ratingsJson ?? this.ratingsJson,
      linksJson: linksJson ?? this.linksJson,
      ratingAvg: ratingAvg ?? this.ratingAvg,
      ratingCount: ratingCount ?? this.ratingCount,
      verification: verification ?? this.verification,
      reviewCount: reviewCount ?? this.reviewCount,
      photoCount: photoCount ?? this.photoCount,
      coverPhotosJson: coverPhotosJson ?? this.coverPhotosJson,
      issuesJson: issuesJson ?? this.issuesJson,
      region: region ?? this.region,
      filterRating: filterRating ?? this.filterRating,
      priceServicesIncluded:
          priceServicesIncluded ?? this.priceServicesIncluded,
      priceParkingIncludes: priceParkingIncludes ?? this.priceParkingIncludes,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rid.present) {
      map['rid'] = Variable<int>(rid.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (family.present) {
      map['family'] = Variable<int>(family.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (overnight.present) {
      map['overnight'] = Variable<String>(overnight.value);
    }
    if (services.present) {
      map['services'] = Variable<int>(services.value);
    }
    if (activities.present) {
      map['activities'] = Variable<int>(activities.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (street.present) {
      map['street'] = Variable<String>(street.value);
    }
    if (postcode.present) {
      map['postcode'] = Variable<String>(postcode.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (countryCode.present) {
      map['country_code'] = Variable<String>(countryCode.value);
    }
    if (priceParking.present) {
      map['price_parking'] = Variable<double>(priceParking.value);
    }
    if (priceServices.present) {
      map['price_services'] = Variable<double>(priceServices.value);
    }
    if (maxHeight.present) {
      map['max_height'] = Variable<double>(maxHeight.value);
    }
    if (capacity.present) {
      map['capacity'] = Variable<int>(capacity.value);
    }
    if (openingHours.present) {
      map['opening_hours'] = Variable<String>(openingHours.value);
    }
    if (openingHoursParsed.present) {
      map['opening_hours_parsed'] = Variable<bool>(openingHoursParsed.value);
    }
    if (openingIntervalsJson.present) {
      map['opening_intervals_json'] = Variable<String>(
        openingIntervalsJson.value,
      );
    }
    if (openingValidUntil.present) {
      map['opening_valid_until'] = Variable<int>(openingValidUntil.value);
    }
    if (stars.present) {
      map['stars'] = Variable<int>(stars.value);
    }
    if (syncGen.present) {
      map['sync_gen'] = Variable<int>(syncGen.value);
    }
    if (website.present) {
      map['website'] = Variable<String>(website.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (lastConfirmedAt.present) {
      map['last_confirmed_at'] = Variable<int>(lastConfirmedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (sourcesJson.present) {
      map['sources_json'] = Variable<String>(sourcesJson.value);
    }
    if (provenanceJson.present) {
      map['provenance_json'] = Variable<String>(provenanceJson.value);
    }
    if (descriptionsJson.present) {
      map['descriptions_json'] = Variable<String>(descriptionsJson.value);
    }
    if (ratingsJson.present) {
      map['ratings_json'] = Variable<String>(ratingsJson.value);
    }
    if (linksJson.present) {
      map['links_json'] = Variable<String>(linksJson.value);
    }
    if (ratingAvg.present) {
      map['rating_avg'] = Variable<double>(ratingAvg.value);
    }
    if (ratingCount.present) {
      map['rating_count'] = Variable<int>(ratingCount.value);
    }
    if (verification.present) {
      map['verification'] = Variable<String>(verification.value);
    }
    if (reviewCount.present) {
      map['review_count'] = Variable<int>(reviewCount.value);
    }
    if (photoCount.present) {
      map['photo_count'] = Variable<int>(photoCount.value);
    }
    if (coverPhotosJson.present) {
      map['cover_photos_json'] = Variable<String>(coverPhotosJson.value);
    }
    if (issuesJson.present) {
      map['issues_json'] = Variable<String>(issuesJson.value);
    }
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (filterRating.present) {
      map['filter_rating'] = Variable<double>(filterRating.value);
    }
    if (priceServicesIncluded.present) {
      map['price_services_included'] = Variable<bool>(
        priceServicesIncluded.value,
      );
    }
    if (priceParkingIncludes.present) {
      map['price_parking_includes'] = Variable<String>(
        priceParkingIncludes.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlacesCompanion(')
          ..write('rid: $rid, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('family: $family, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('overnight: $overnight, ')
          ..write('services: $services, ')
          ..write('activities: $activities, ')
          ..write('description: $description, ')
          ..write('street: $street, ')
          ..write('postcode: $postcode, ')
          ..write('city: $city, ')
          ..write('countryCode: $countryCode, ')
          ..write('priceParking: $priceParking, ')
          ..write('priceServices: $priceServices, ')
          ..write('maxHeight: $maxHeight, ')
          ..write('capacity: $capacity, ')
          ..write('openingHours: $openingHours, ')
          ..write('openingHoursParsed: $openingHoursParsed, ')
          ..write('openingIntervalsJson: $openingIntervalsJson, ')
          ..write('openingValidUntil: $openingValidUntil, ')
          ..write('stars: $stars, ')
          ..write('syncGen: $syncGen, ')
          ..write('website: $website, ')
          ..write('phone: $phone, ')
          ..write('lastConfirmedAt: $lastConfirmedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('provenanceJson: $provenanceJson, ')
          ..write('descriptionsJson: $descriptionsJson, ')
          ..write('ratingsJson: $ratingsJson, ')
          ..write('linksJson: $linksJson, ')
          ..write('ratingAvg: $ratingAvg, ')
          ..write('ratingCount: $ratingCount, ')
          ..write('verification: $verification, ')
          ..write('reviewCount: $reviewCount, ')
          ..write('photoCount: $photoCount, ')
          ..write('coverPhotosJson: $coverPhotosJson, ')
          ..write('issuesJson: $issuesJson, ')
          ..write('region: $region, ')
          ..write('filterRating: $filterRating, ')
          ..write('priceServicesIncluded: $priceServicesIncluded, ')
          ..write('priceParkingIncludes: $priceParkingIncludes')
          ..write(')'))
        .toString();
  }
}

class PlaceBounds extends Table
    with
        TableInfo<PlaceBounds, PlaceBound>,
        VirtualTableInfo<PlaceBounds, PlaceBound> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PlaceBounds(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ridMeta = const VerificationMeta('rid');
  late final GeneratedColumn<int> rid = GeneratedColumn<int>(
    'rid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _minLatMeta = const VerificationMeta('minLat');
  late final GeneratedColumn<double> minLat = GeneratedColumn<double>(
    'min_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _maxLatMeta = const VerificationMeta('maxLat');
  late final GeneratedColumn<double> maxLat = GeneratedColumn<double>(
    'max_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _minLonMeta = const VerificationMeta('minLon');
  late final GeneratedColumn<double> minLon = GeneratedColumn<double>(
    'min_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _maxLonMeta = const VerificationMeta('maxLon');
  late final GeneratedColumn<double> maxLon = GeneratedColumn<double>(
    'max_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [rid, minLat, maxLat, minLon, maxLon];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'place_bounds';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaceBound> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('rid')) {
      context.handle(
        _ridMeta,
        rid.isAcceptableOrUnknown(data['rid']!, _ridMeta),
      );
    } else if (isInserting) {
      context.missing(_ridMeta);
    }
    if (data.containsKey('min_lat')) {
      context.handle(
        _minLatMeta,
        minLat.isAcceptableOrUnknown(data['min_lat']!, _minLatMeta),
      );
    } else if (isInserting) {
      context.missing(_minLatMeta);
    }
    if (data.containsKey('max_lat')) {
      context.handle(
        _maxLatMeta,
        maxLat.isAcceptableOrUnknown(data['max_lat']!, _maxLatMeta),
      );
    } else if (isInserting) {
      context.missing(_maxLatMeta);
    }
    if (data.containsKey('min_lon')) {
      context.handle(
        _minLonMeta,
        minLon.isAcceptableOrUnknown(data['min_lon']!, _minLonMeta),
      );
    } else if (isInserting) {
      context.missing(_minLonMeta);
    }
    if (data.containsKey('max_lon')) {
      context.handle(
        _maxLonMeta,
        maxLon.isAcceptableOrUnknown(data['max_lon']!, _maxLonMeta),
      );
    } else if (isInserting) {
      context.missing(_maxLonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  PlaceBound map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaceBound(
      rid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rid'],
      )!,
      minLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_lat'],
      )!,
      maxLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_lat'],
      )!,
      minLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}min_lon'],
      )!,
      maxLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}max_lon'],
      )!,
    );
  }

  @override
  PlaceBounds createAlias(String alias) {
    return PlaceBounds(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs => 'rtree(rid, min_lat, max_lat, min_lon, max_lon)';
}

class PlaceBound extends DataClass implements Insertable<PlaceBound> {
  final int rid;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  const PlaceBound({
    required this.rid,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['rid'] = Variable<int>(rid);
    map['min_lat'] = Variable<double>(minLat);
    map['max_lat'] = Variable<double>(maxLat);
    map['min_lon'] = Variable<double>(minLon);
    map['max_lon'] = Variable<double>(maxLon);
    return map;
  }

  PlaceBoundsCompanion toCompanion(bool nullToAbsent) {
    return PlaceBoundsCompanion(
      rid: Value(rid),
      minLat: Value(minLat),
      maxLat: Value(maxLat),
      minLon: Value(minLon),
      maxLon: Value(maxLon),
    );
  }

  factory PlaceBound.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaceBound(
      rid: serializer.fromJson<int>(json['rid']),
      minLat: serializer.fromJson<double>(json['min_lat']),
      maxLat: serializer.fromJson<double>(json['max_lat']),
      minLon: serializer.fromJson<double>(json['min_lon']),
      maxLon: serializer.fromJson<double>(json['max_lon']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rid': serializer.toJson<int>(rid),
      'min_lat': serializer.toJson<double>(minLat),
      'max_lat': serializer.toJson<double>(maxLat),
      'min_lon': serializer.toJson<double>(minLon),
      'max_lon': serializer.toJson<double>(maxLon),
    };
  }

  PlaceBound copyWith({
    int? rid,
    double? minLat,
    double? maxLat,
    double? minLon,
    double? maxLon,
  }) => PlaceBound(
    rid: rid ?? this.rid,
    minLat: minLat ?? this.minLat,
    maxLat: maxLat ?? this.maxLat,
    minLon: minLon ?? this.minLon,
    maxLon: maxLon ?? this.maxLon,
  );
  PlaceBound copyWithCompanion(PlaceBoundsCompanion data) {
    return PlaceBound(
      rid: data.rid.present ? data.rid.value : this.rid,
      minLat: data.minLat.present ? data.minLat.value : this.minLat,
      maxLat: data.maxLat.present ? data.maxLat.value : this.maxLat,
      minLon: data.minLon.present ? data.minLon.value : this.minLon,
      maxLon: data.maxLon.present ? data.maxLon.value : this.maxLon,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaceBound(')
          ..write('rid: $rid, ')
          ..write('minLat: $minLat, ')
          ..write('maxLat: $maxLat, ')
          ..write('minLon: $minLon, ')
          ..write('maxLon: $maxLon')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(rid, minLat, maxLat, minLon, maxLon);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaceBound &&
          other.rid == this.rid &&
          other.minLat == this.minLat &&
          other.maxLat == this.maxLat &&
          other.minLon == this.minLon &&
          other.maxLon == this.maxLon);
}

class PlaceBoundsCompanion extends UpdateCompanion<PlaceBound> {
  final Value<int> rid;
  final Value<double> minLat;
  final Value<double> maxLat;
  final Value<double> minLon;
  final Value<double> maxLon;
  final Value<int> rowid;
  const PlaceBoundsCompanion({
    this.rid = const Value.absent(),
    this.minLat = const Value.absent(),
    this.maxLat = const Value.absent(),
    this.minLon = const Value.absent(),
    this.maxLon = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaceBoundsCompanion.insert({
    required int rid,
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    this.rowid = const Value.absent(),
  }) : rid = Value(rid),
       minLat = Value(minLat),
       maxLat = Value(maxLat),
       minLon = Value(minLon),
       maxLon = Value(maxLon);
  static Insertable<PlaceBound> custom({
    Expression<int>? rid,
    Expression<double>? minLat,
    Expression<double>? maxLat,
    Expression<double>? minLon,
    Expression<double>? maxLon,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (rid != null) 'rid': rid,
      if (minLat != null) 'min_lat': minLat,
      if (maxLat != null) 'max_lat': maxLat,
      if (minLon != null) 'min_lon': minLon,
      if (maxLon != null) 'max_lon': maxLon,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaceBoundsCompanion copyWith({
    Value<int>? rid,
    Value<double>? minLat,
    Value<double>? maxLat,
    Value<double>? minLon,
    Value<double>? maxLon,
    Value<int>? rowid,
  }) {
    return PlaceBoundsCompanion(
      rid: rid ?? this.rid,
      minLat: minLat ?? this.minLat,
      maxLat: maxLat ?? this.maxLat,
      minLon: minLon ?? this.minLon,
      maxLon: maxLon ?? this.maxLon,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rid.present) {
      map['rid'] = Variable<int>(rid.value);
    }
    if (minLat.present) {
      map['min_lat'] = Variable<double>(minLat.value);
    }
    if (maxLat.present) {
      map['max_lat'] = Variable<double>(maxLat.value);
    }
    if (minLon.present) {
      map['min_lon'] = Variable<double>(minLon.value);
    }
    if (maxLon.present) {
      map['max_lon'] = Variable<double>(maxLon.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaceBoundsCompanion(')
          ..write('rid: $rid, ')
          ..write('minLat: $minLat, ')
          ..write('maxLat: $maxLat, ')
          ..write('minLon: $minLon, ')
          ..write('maxLon: $maxLon, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PlaceSearch extends Table
    with
        TableInfo<PlaceSearch, PlaceSearchData>,
        VirtualTableInfo<PlaceSearch, PlaceSearchData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PlaceSearch(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _cityMeta = const VerificationMeta('city');
  late final GeneratedColumn<String> city = GeneratedColumn<String>(
    'city',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _postcodeMeta = const VerificationMeta(
    'postcode',
  );
  late final GeneratedColumn<String> postcode = GeneratedColumn<String>(
    'postcode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [name, city, postcode];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'place_search';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaceSearchData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('city')) {
      context.handle(
        _cityMeta,
        city.isAcceptableOrUnknown(data['city']!, _cityMeta),
      );
    } else if (isInserting) {
      context.missing(_cityMeta);
    }
    if (data.containsKey('postcode')) {
      context.handle(
        _postcodeMeta,
        postcode.isAcceptableOrUnknown(data['postcode']!, _postcodeMeta),
      );
    } else if (isInserting) {
      context.missing(_postcodeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  PlaceSearchData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaceSearchData(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      city: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city'],
      )!,
      postcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}postcode'],
      )!,
    );
  }

  @override
  PlaceSearch createAlias(String alias) {
    return PlaceSearch(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs =>
      'fts5(name, city, postcode, content = \'places\', content_rowid = \'rid\', tokenize = \'unicode61 remove_diacritics 2\')';
}

class PlaceSearchData extends DataClass implements Insertable<PlaceSearchData> {
  final String name;
  final String city;
  final String postcode;
  const PlaceSearchData({
    required this.name,
    required this.city,
    required this.postcode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['city'] = Variable<String>(city);
    map['postcode'] = Variable<String>(postcode);
    return map;
  }

  PlaceSearchCompanion toCompanion(bool nullToAbsent) {
    return PlaceSearchCompanion(
      name: Value(name),
      city: Value(city),
      postcode: Value(postcode),
    );
  }

  factory PlaceSearchData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaceSearchData(
      name: serializer.fromJson<String>(json['name']),
      city: serializer.fromJson<String>(json['city']),
      postcode: serializer.fromJson<String>(json['postcode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'city': serializer.toJson<String>(city),
      'postcode': serializer.toJson<String>(postcode),
    };
  }

  PlaceSearchData copyWith({String? name, String? city, String? postcode}) =>
      PlaceSearchData(
        name: name ?? this.name,
        city: city ?? this.city,
        postcode: postcode ?? this.postcode,
      );
  PlaceSearchData copyWithCompanion(PlaceSearchCompanion data) {
    return PlaceSearchData(
      name: data.name.present ? data.name.value : this.name,
      city: data.city.present ? data.city.value : this.city,
      postcode: data.postcode.present ? data.postcode.value : this.postcode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaceSearchData(')
          ..write('name: $name, ')
          ..write('city: $city, ')
          ..write('postcode: $postcode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, city, postcode);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaceSearchData &&
          other.name == this.name &&
          other.city == this.city &&
          other.postcode == this.postcode);
}

class PlaceSearchCompanion extends UpdateCompanion<PlaceSearchData> {
  final Value<String> name;
  final Value<String> city;
  final Value<String> postcode;
  final Value<int> rowid;
  const PlaceSearchCompanion({
    this.name = const Value.absent(),
    this.city = const Value.absent(),
    this.postcode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaceSearchCompanion.insert({
    required String name,
    required String city,
    required String postcode,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       city = Value(city),
       postcode = Value(postcode);
  static Insertable<PlaceSearchData> custom({
    Expression<String>? name,
    Expression<String>? city,
    Expression<String>? postcode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (city != null) 'city': city,
      if (postcode != null) 'postcode': postcode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaceSearchCompanion copyWith({
    Value<String>? name,
    Value<String>? city,
    Value<String>? postcode,
    Value<int>? rowid,
  }) {
    return PlaceSearchCompanion(
      name: name ?? this.name,
      city: city ?? this.city,
      postcode: postcode ?? this.postcode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (city.present) {
      map['city'] = Variable<String>(city.value);
    }
    if (postcode.present) {
      map['postcode'] = Variable<String>(postcode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaceSearchCompanion(')
          ..write('name: $name, ')
          ..write('city: $city, ')
          ..write('postcode: $postcode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class RegionSyncs extends Table with TableInfo<RegionSyncs, SyncStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  RegionSyncs(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _regionMeta = const VerificationMeta('region');
  late final GeneratedColumn<String> region = GeneratedColumn<String>(
    'region',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT 0',
    defaultValue: const CustomExpression('0'),
  );
  static const VerificationMeta _fullSyncMeta = const VerificationMeta(
    'fullSync',
  );
  late final GeneratedColumn<bool> fullSync = GeneratedColumn<bool>(
    'full_sync',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _runningMeta = const VerificationMeta(
    'running',
  );
  late final GeneratedColumn<bool> running = GeneratedColumn<bool>(
    'running',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT FALSE',
    defaultValue: const CustomExpression('FALSE'),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  late final GeneratedColumn<int> completedAt = GeneratedColumn<int>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [
    region,
    cursor,
    generation,
    fullSync,
    running,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'region_syncs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('region')) {
      context.handle(
        _regionMeta,
        region.isAcceptableOrUnknown(data['region']!, _regionMeta),
      );
    } else if (isInserting) {
      context.missing(_regionMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    }
    if (data.containsKey('full_sync')) {
      context.handle(
        _fullSyncMeta,
        fullSync.isAcceptableOrUnknown(data['full_sync']!, _fullSyncMeta),
      );
    }
    if (data.containsKey('running')) {
      context.handle(
        _runningMeta,
        running.isAcceptableOrUnknown(data['running']!, _runningMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {region};
  @override
  SyncStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateRow(
      region: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      ),
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      fullSync: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}full_sync'],
      )!,
      running: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}running'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  RegionSyncs createAlias(String alias) {
    return RegionSyncs(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class SyncStateRow extends DataClass implements Insertable<SyncStateRow> {
  final String region;

  /// The opaque cursor of the last applied page; null before the first page
  /// of a full sync.
  final String? cursor;

  /// Generation of the current or last full sync (see places.sync_gen).
  final int generation;

  /// A full sync is under way: its end sweeps what it did not write.
  final bool fullSync;

  /// A run started and has not reached its last page yet.
  final bool running;

  /// When a run last reached its last page; null until the first full sync
  /// completes.
  final int? completedAt;
  const SyncStateRow({
    required this.region,
    this.cursor,
    required this.generation,
    required this.fullSync,
    required this.running,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['region'] = Variable<String>(region);
    if (!nullToAbsent || cursor != null) {
      map['cursor'] = Variable<String>(cursor);
    }
    map['generation'] = Variable<int>(generation);
    map['full_sync'] = Variable<bool>(fullSync);
    map['running'] = Variable<bool>(running);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<int>(completedAt);
    }
    return map;
  }

  RegionSyncsCompanion toCompanion(bool nullToAbsent) {
    return RegionSyncsCompanion(
      region: Value(region),
      cursor: cursor == null && nullToAbsent
          ? const Value.absent()
          : Value(cursor),
      generation: Value(generation),
      fullSync: Value(fullSync),
      running: Value(running),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory SyncStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateRow(
      region: serializer.fromJson<String>(json['region']),
      cursor: serializer.fromJson<String?>(json['cursor']),
      generation: serializer.fromJson<int>(json['generation']),
      fullSync: serializer.fromJson<bool>(json['full_sync']),
      running: serializer.fromJson<bool>(json['running']),
      completedAt: serializer.fromJson<int?>(json['completed_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'region': serializer.toJson<String>(region),
      'cursor': serializer.toJson<String?>(cursor),
      'generation': serializer.toJson<int>(generation),
      'full_sync': serializer.toJson<bool>(fullSync),
      'running': serializer.toJson<bool>(running),
      'completed_at': serializer.toJson<int?>(completedAt),
    };
  }

  SyncStateRow copyWith({
    String? region,
    Value<String?> cursor = const Value.absent(),
    int? generation,
    bool? fullSync,
    bool? running,
    Value<int?> completedAt = const Value.absent(),
  }) => SyncStateRow(
    region: region ?? this.region,
    cursor: cursor.present ? cursor.value : this.cursor,
    generation: generation ?? this.generation,
    fullSync: fullSync ?? this.fullSync,
    running: running ?? this.running,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  SyncStateRow copyWithCompanion(RegionSyncsCompanion data) {
    return SyncStateRow(
      region: data.region.present ? data.region.value : this.region,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      fullSync: data.fullSync.present ? data.fullSync.value : this.fullSync,
      running: data.running.present ? data.running.value : this.running,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateRow(')
          ..write('region: $region, ')
          ..write('cursor: $cursor, ')
          ..write('generation: $generation, ')
          ..write('fullSync: $fullSync, ')
          ..write('running: $running, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(region, cursor, generation, fullSync, running, completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateRow &&
          other.region == this.region &&
          other.cursor == this.cursor &&
          other.generation == this.generation &&
          other.fullSync == this.fullSync &&
          other.running == this.running &&
          other.completedAt == this.completedAt);
}

class RegionSyncsCompanion extends UpdateCompanion<SyncStateRow> {
  final Value<String> region;
  final Value<String?> cursor;
  final Value<int> generation;
  final Value<bool> fullSync;
  final Value<bool> running;
  final Value<int?> completedAt;
  final Value<int> rowid;
  const RegionSyncsCompanion({
    this.region = const Value.absent(),
    this.cursor = const Value.absent(),
    this.generation = const Value.absent(),
    this.fullSync = const Value.absent(),
    this.running = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RegionSyncsCompanion.insert({
    required String region,
    this.cursor = const Value.absent(),
    this.generation = const Value.absent(),
    this.fullSync = const Value.absent(),
    this.running = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : region = Value(region);
  static Insertable<SyncStateRow> custom({
    Expression<String>? region,
    Expression<String>? cursor,
    Expression<int>? generation,
    Expression<bool>? fullSync,
    Expression<bool>? running,
    Expression<int>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (region != null) 'region': region,
      if (cursor != null) 'cursor': cursor,
      if (generation != null) 'generation': generation,
      if (fullSync != null) 'full_sync': fullSync,
      if (running != null) 'running': running,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RegionSyncsCompanion copyWith({
    Value<String>? region,
    Value<String?>? cursor,
    Value<int>? generation,
    Value<bool>? fullSync,
    Value<bool>? running,
    Value<int?>? completedAt,
    Value<int>? rowid,
  }) {
    return RegionSyncsCompanion(
      region: region ?? this.region,
      cursor: cursor ?? this.cursor,
      generation: generation ?? this.generation,
      fullSync: fullSync ?? this.fullSync,
      running: running ?? this.running,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (region.present) {
      map['region'] = Variable<String>(region.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (fullSync.present) {
      map['full_sync'] = Variable<bool>(fullSync.value);
    }
    if (running.present) {
      map['running'] = Variable<bool>(running.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<int>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RegionSyncsCompanion(')
          ..write('region: $region, ')
          ..write('cursor: $cursor, ')
          ..write('generation: $generation, ')
          ..write('fullSync: $fullSync, ')
          ..write('running: $running, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PlaceExtrasCache extends Table
    with TableInfo<PlaceExtrasCache, PlaceExtrasCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PlaceExtrasCache(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _placeIdMeta = const VerificationMeta(
    'placeId',
  );
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
    'place_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [placeId, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'place_extras_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaceExtrasCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('place_id')) {
      context.handle(
        _placeIdMeta,
        placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_placeIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {placeId};
  @override
  PlaceExtrasCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaceExtrasCacheRow(
      placeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  PlaceExtrasCache createAlias(String alias) {
    return PlaceExtrasCache(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PlaceExtrasCacheRow extends DataClass
    implements Insertable<PlaceExtrasCacheRow> {
  final String placeId;
  final String json;
  final int fetchedAt;
  const PlaceExtrasCacheRow({
    required this.placeId,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['place_id'] = Variable<String>(placeId);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  PlaceExtrasCacheCompanion toCompanion(bool nullToAbsent) {
    return PlaceExtrasCacheCompanion(
      placeId: Value(placeId),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory PlaceExtrasCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaceExtrasCacheRow(
      placeId: serializer.fromJson<String>(json['place_id']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'place_id': serializer.toJson<String>(placeId),
      'json': serializer.toJson<String>(json),
      'fetched_at': serializer.toJson<int>(fetchedAt),
    };
  }

  PlaceExtrasCacheRow copyWith({
    String? placeId,
    String? json,
    int? fetchedAt,
  }) => PlaceExtrasCacheRow(
    placeId: placeId ?? this.placeId,
    json: json ?? this.json,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  PlaceExtrasCacheRow copyWithCompanion(PlaceExtrasCacheCompanion data) {
    return PlaceExtrasCacheRow(
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaceExtrasCacheRow(')
          ..write('placeId: $placeId, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(placeId, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaceExtrasCacheRow &&
          other.placeId == this.placeId &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class PlaceExtrasCacheCompanion extends UpdateCompanion<PlaceExtrasCacheRow> {
  final Value<String> placeId;
  final Value<String> json;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const PlaceExtrasCacheCompanion({
    this.placeId = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaceExtrasCacheCompanion.insert({
    required String placeId,
    required String json,
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : placeId = Value(placeId),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<PlaceExtrasCacheRow> custom({
    Expression<String>? placeId,
    Expression<String>? json,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (placeId != null) 'place_id': placeId,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaceExtrasCacheCompanion copyWith({
    Value<String>? placeId,
    Value<String>? json,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return PlaceExtrasCacheCompanion(
      placeId: placeId ?? this.placeId,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaceExtrasCacheCompanion(')
          ..write('placeId: $placeId, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PlaceCache extends Table with TableInfo<PlaceCache, PlaceCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PlaceCache(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _placeIdMeta = const VerificationMeta(
    'placeId',
  );
  late final GeneratedColumn<String> placeId = GeneratedColumn<String>(
    'place_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [placeId, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'place_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaceCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('place_id')) {
      context.handle(
        _placeIdMeta,
        placeId.isAcceptableOrUnknown(data['place_id']!, _placeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_placeIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {placeId};
  @override
  PlaceCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaceCacheRow(
      placeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  PlaceCache createAlias(String alias) {
    return PlaceCache(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PlaceCacheRow extends DataClass implements Insertable<PlaceCacheRow> {
  final String placeId;
  final String json;
  final int fetchedAt;
  const PlaceCacheRow({
    required this.placeId,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['place_id'] = Variable<String>(placeId);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  PlaceCacheCompanion toCompanion(bool nullToAbsent) {
    return PlaceCacheCompanion(
      placeId: Value(placeId),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory PlaceCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaceCacheRow(
      placeId: serializer.fromJson<String>(json['place_id']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'place_id': serializer.toJson<String>(placeId),
      'json': serializer.toJson<String>(json),
      'fetched_at': serializer.toJson<int>(fetchedAt),
    };
  }

  PlaceCacheRow copyWith({String? placeId, String? json, int? fetchedAt}) =>
      PlaceCacheRow(
        placeId: placeId ?? this.placeId,
        json: json ?? this.json,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  PlaceCacheRow copyWithCompanion(PlaceCacheCompanion data) {
    return PlaceCacheRow(
      placeId: data.placeId.present ? data.placeId.value : this.placeId,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaceCacheRow(')
          ..write('placeId: $placeId, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(placeId, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaceCacheRow &&
          other.placeId == this.placeId &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class PlaceCacheCompanion extends UpdateCompanion<PlaceCacheRow> {
  final Value<String> placeId;
  final Value<String> json;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const PlaceCacheCompanion({
    this.placeId = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaceCacheCompanion.insert({
    required String placeId,
    required String json,
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : placeId = Value(placeId),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<PlaceCacheRow> custom({
    Expression<String>? placeId,
    Expression<String>? json,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (placeId != null) 'place_id': placeId,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaceCacheCompanion copyWith({
    Value<String>? placeId,
    Value<String>? json,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return PlaceCacheCompanion(
      placeId: placeId ?? this.placeId,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (placeId.present) {
      map['place_id'] = Variable<String>(placeId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaceCacheCompanion(')
          ..write('placeId: $placeId, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class DeviceState extends Table with TableInfo<DeviceState, DeviceStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  DeviceState(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeviceStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceStateRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  DeviceState createAlias(String alias) {
    return DeviceState(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class DeviceStateRow extends DataClass implements Insertable<DeviceStateRow> {
  final String id;
  final String value;
  const DeviceStateRow({required this.id, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['value'] = Variable<String>(value);
    return map;
  }

  DeviceStateCompanion toCompanion(bool nullToAbsent) {
    return DeviceStateCompanion(id: Value(id), value: Value(value));
  }

  factory DeviceStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceStateRow(
      id: serializer.fromJson<String>(json['id']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'value': serializer.toJson<String>(value),
    };
  }

  DeviceStateRow copyWith({String? id, String? value}) =>
      DeviceStateRow(id: id ?? this.id, value: value ?? this.value);
  DeviceStateRow copyWithCompanion(DeviceStateCompanion data) {
    return DeviceStateRow(
      id: data.id.present ? data.id.value : this.id,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceStateRow(')
          ..write('id: $id, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceStateRow &&
          other.id == this.id &&
          other.value == this.value);
}

class DeviceStateCompanion extends UpdateCompanion<DeviceStateRow> {
  final Value<String> id;
  final Value<String> value;
  final Value<int> rowid;
  const DeviceStateCompanion({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceStateCompanion.insert({
    required String id,
    required String value,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       value = Value(value);
  static Insertable<DeviceStateRow> custom({
    Expression<String>? id,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceStateCompanion copyWith({
    Value<String>? id,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return DeviceStateCompanion(
      id: id ?? this.id,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceStateCompanion(')
          ..write('id: $id, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PoiCache extends Table with TableInfo<PoiCache, PoiCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PoiCache(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [cacheKey, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'poi_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<PoiCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  PoiCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PoiCacheRow(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  PoiCache createAlias(String alias) {
    return PoiCache(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class PoiCacheRow extends DataClass implements Insertable<PoiCacheRow> {
  final String cacheKey;
  final String json;
  final int fetchedAt;
  const PoiCacheRow({
    required this.cacheKey,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<int>(fetchedAt);
    return map;
  }

  PoiCacheCompanion toCompanion(bool nullToAbsent) {
    return PoiCacheCompanion(
      cacheKey: Value(cacheKey),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory PoiCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PoiCacheRow(
      cacheKey: serializer.fromJson<String>(json['cache_key']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<int>(json['fetched_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cache_key': serializer.toJson<String>(cacheKey),
      'json': serializer.toJson<String>(json),
      'fetched_at': serializer.toJson<int>(fetchedAt),
    };
  }

  PoiCacheRow copyWith({String? cacheKey, String? json, int? fetchedAt}) =>
      PoiCacheRow(
        cacheKey: cacheKey ?? this.cacheKey,
        json: json ?? this.json,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  PoiCacheRow copyWithCompanion(PoiCacheCompanion data) {
    return PoiCacheRow(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PoiCacheRow(')
          ..write('cacheKey: $cacheKey, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cacheKey, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PoiCacheRow &&
          other.cacheKey == this.cacheKey &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class PoiCacheCompanion extends UpdateCompanion<PoiCacheRow> {
  final Value<String> cacheKey;
  final Value<String> json;
  final Value<int> fetchedAt;
  final Value<int> rowid;
  const PoiCacheCompanion({
    this.cacheKey = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PoiCacheCompanion.insert({
    required String cacheKey,
    required String json,
    required int fetchedAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<PoiCacheRow> custom({
    Expression<String>? cacheKey,
    Expression<String>? json,
    Expression<int>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PoiCacheCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? json,
    Value<int>? fetchedAt,
    Value<int>? rowid,
  }) {
    return PoiCacheCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PoiCacheCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class EnforcementItems extends Table
    with TableInfo<EnforcementItems, EnforcementItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  EnforcementItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _countryMeta = const VerificationMeta(
    'country',
  );
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
    'country',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _lineMeta = const VerificationMeta('line');
  late final GeneratedColumn<String> line = GeneratedColumn<String>(
    'line',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _lonMeta = const VerificationMeta('lon');
  late final GeneratedColumn<double> lon = GeneratedColumn<double>(
    'lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _bearingDegMeta = const VerificationMeta(
    'bearingDeg',
  );
  late final GeneratedColumn<double> bearingDeg = GeneratedColumn<double>(
    'bearing_deg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _limitKmhMeta = const VerificationMeta(
    'limitKmh',
  );
  late final GeneratedColumn<int> limitKmh = GeneratedColumn<int>(
    'limit_kmh',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _sourceIdsMeta = const VerificationMeta(
    'sourceIds',
  );
  late final GeneratedColumn<String> sourceIds = GeneratedColumn<String>(
    'source_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: 'NOT NULL DEFAULT \'[]\'',
    defaultValue: const CustomExpression('\'[]\''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    category,
    country,
    line,
    lat,
    lon,
    bearingDeg,
    limitKmh,
    sourceIds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'enforcement_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<EnforcementItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('country')) {
      context.handle(
        _countryMeta,
        country.isAcceptableOrUnknown(data['country']!, _countryMeta),
      );
    } else if (isInserting) {
      context.missing(_countryMeta);
    }
    if (data.containsKey('line')) {
      context.handle(
        _lineMeta,
        line.isAcceptableOrUnknown(data['line']!, _lineMeta),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lon')) {
      context.handle(
        _lonMeta,
        lon.isAcceptableOrUnknown(data['lon']!, _lonMeta),
      );
    }
    if (data.containsKey('bearing_deg')) {
      context.handle(
        _bearingDegMeta,
        bearingDeg.isAcceptableOrUnknown(data['bearing_deg']!, _bearingDegMeta),
      );
    }
    if (data.containsKey('limit_kmh')) {
      context.handle(
        _limitKmhMeta,
        limitKmh.isAcceptableOrUnknown(data['limit_kmh']!, _limitKmhMeta),
      );
    }
    if (data.containsKey('source_ids')) {
      context.handle(
        _sourceIdsMeta,
        sourceIds.isAcceptableOrUnknown(data['source_ids']!, _sourceIdsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EnforcementItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EnforcementItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      country: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country'],
      )!,
      line: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lon'],
      ),
      bearingDeg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bearing_deg'],
      ),
      limitKmh: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}limit_kmh'],
      ),
      sourceIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_ids'],
      )!,
    );
  }

  @override
  EnforcementItems createAlias(String alias) {
    return EnforcementItems(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class EnforcementItemRow extends DataClass
    implements Insertable<EnforcementItemRow> {
  final String id;

  /// ZONE or CAMERA.
  final String kind;
  final String category;

  /// ISO 3166-1 alpha-2 of the country whose rule it follows.
  final String country;

  /// The road of a zone (or of an average speed section), polyline6.
  final String? line;
  final double? lat;
  final double? lon;
  final double? bearingDeg;
  final int? limitKmh;

  /// JSON array of the lists it comes from.
  final String sourceIds;
  const EnforcementItemRow({
    required this.id,
    required this.kind,
    required this.category,
    required this.country,
    this.line,
    this.lat,
    this.lon,
    this.bearingDeg,
    this.limitKmh,
    required this.sourceIds,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['category'] = Variable<String>(category);
    map['country'] = Variable<String>(country);
    if (!nullToAbsent || line != null) {
      map['line'] = Variable<String>(line);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lon != null) {
      map['lon'] = Variable<double>(lon);
    }
    if (!nullToAbsent || bearingDeg != null) {
      map['bearing_deg'] = Variable<double>(bearingDeg);
    }
    if (!nullToAbsent || limitKmh != null) {
      map['limit_kmh'] = Variable<int>(limitKmh);
    }
    map['source_ids'] = Variable<String>(sourceIds);
    return map;
  }

  EnforcementItemsCompanion toCompanion(bool nullToAbsent) {
    return EnforcementItemsCompanion(
      id: Value(id),
      kind: Value(kind),
      category: Value(category),
      country: Value(country),
      line: line == null && nullToAbsent ? const Value.absent() : Value(line),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lon: lon == null && nullToAbsent ? const Value.absent() : Value(lon),
      bearingDeg: bearingDeg == null && nullToAbsent
          ? const Value.absent()
          : Value(bearingDeg),
      limitKmh: limitKmh == null && nullToAbsent
          ? const Value.absent()
          : Value(limitKmh),
      sourceIds: Value(sourceIds),
    );
  }

  factory EnforcementItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EnforcementItemRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      category: serializer.fromJson<String>(json['category']),
      country: serializer.fromJson<String>(json['country']),
      line: serializer.fromJson<String?>(json['line']),
      lat: serializer.fromJson<double?>(json['lat']),
      lon: serializer.fromJson<double?>(json['lon']),
      bearingDeg: serializer.fromJson<double?>(json['bearing_deg']),
      limitKmh: serializer.fromJson<int?>(json['limit_kmh']),
      sourceIds: serializer.fromJson<String>(json['source_ids']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'category': serializer.toJson<String>(category),
      'country': serializer.toJson<String>(country),
      'line': serializer.toJson<String?>(line),
      'lat': serializer.toJson<double?>(lat),
      'lon': serializer.toJson<double?>(lon),
      'bearing_deg': serializer.toJson<double?>(bearingDeg),
      'limit_kmh': serializer.toJson<int?>(limitKmh),
      'source_ids': serializer.toJson<String>(sourceIds),
    };
  }

  EnforcementItemRow copyWith({
    String? id,
    String? kind,
    String? category,
    String? country,
    Value<String?> line = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lon = const Value.absent(),
    Value<double?> bearingDeg = const Value.absent(),
    Value<int?> limitKmh = const Value.absent(),
    String? sourceIds,
  }) => EnforcementItemRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    category: category ?? this.category,
    country: country ?? this.country,
    line: line.present ? line.value : this.line,
    lat: lat.present ? lat.value : this.lat,
    lon: lon.present ? lon.value : this.lon,
    bearingDeg: bearingDeg.present ? bearingDeg.value : this.bearingDeg,
    limitKmh: limitKmh.present ? limitKmh.value : this.limitKmh,
    sourceIds: sourceIds ?? this.sourceIds,
  );
  EnforcementItemRow copyWithCompanion(EnforcementItemsCompanion data) {
    return EnforcementItemRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      category: data.category.present ? data.category.value : this.category,
      country: data.country.present ? data.country.value : this.country,
      line: data.line.present ? data.line.value : this.line,
      lat: data.lat.present ? data.lat.value : this.lat,
      lon: data.lon.present ? data.lon.value : this.lon,
      bearingDeg: data.bearingDeg.present
          ? data.bearingDeg.value
          : this.bearingDeg,
      limitKmh: data.limitKmh.present ? data.limitKmh.value : this.limitKmh,
      sourceIds: data.sourceIds.present ? data.sourceIds.value : this.sourceIds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EnforcementItemRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('category: $category, ')
          ..write('country: $country, ')
          ..write('line: $line, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('bearingDeg: $bearingDeg, ')
          ..write('limitKmh: $limitKmh, ')
          ..write('sourceIds: $sourceIds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    category,
    country,
    line,
    lat,
    lon,
    bearingDeg,
    limitKmh,
    sourceIds,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EnforcementItemRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.category == this.category &&
          other.country == this.country &&
          other.line == this.line &&
          other.lat == this.lat &&
          other.lon == this.lon &&
          other.bearingDeg == this.bearingDeg &&
          other.limitKmh == this.limitKmh &&
          other.sourceIds == this.sourceIds);
}

class EnforcementItemsCompanion extends UpdateCompanion<EnforcementItemRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> category;
  final Value<String> country;
  final Value<String?> line;
  final Value<double?> lat;
  final Value<double?> lon;
  final Value<double?> bearingDeg;
  final Value<int?> limitKmh;
  final Value<String> sourceIds;
  final Value<int> rowid;
  const EnforcementItemsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.category = const Value.absent(),
    this.country = const Value.absent(),
    this.line = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.bearingDeg = const Value.absent(),
    this.limitKmh = const Value.absent(),
    this.sourceIds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EnforcementItemsCompanion.insert({
    required String id,
    required String kind,
    required String category,
    required String country,
    this.line = const Value.absent(),
    this.lat = const Value.absent(),
    this.lon = const Value.absent(),
    this.bearingDeg = const Value.absent(),
    this.limitKmh = const Value.absent(),
    this.sourceIds = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       category = Value(category),
       country = Value(country);
  static Insertable<EnforcementItemRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? category,
    Expression<String>? country,
    Expression<String>? line,
    Expression<double>? lat,
    Expression<double>? lon,
    Expression<double>? bearingDeg,
    Expression<int>? limitKmh,
    Expression<String>? sourceIds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (category != null) 'category': category,
      if (country != null) 'country': country,
      if (line != null) 'line': line,
      if (lat != null) 'lat': lat,
      if (lon != null) 'lon': lon,
      if (bearingDeg != null) 'bearing_deg': bearingDeg,
      if (limitKmh != null) 'limit_kmh': limitKmh,
      if (sourceIds != null) 'source_ids': sourceIds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EnforcementItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? category,
    Value<String>? country,
    Value<String?>? line,
    Value<double?>? lat,
    Value<double?>? lon,
    Value<double?>? bearingDeg,
    Value<int?>? limitKmh,
    Value<String>? sourceIds,
    Value<int>? rowid,
  }) {
    return EnforcementItemsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      category: category ?? this.category,
      country: country ?? this.country,
      line: line ?? this.line,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      bearingDeg: bearingDeg ?? this.bearingDeg,
      limitKmh: limitKmh ?? this.limitKmh,
      sourceIds: sourceIds ?? this.sourceIds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (line.present) {
      map['line'] = Variable<String>(line.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lon.present) {
      map['lon'] = Variable<double>(lon.value);
    }
    if (bearingDeg.present) {
      map['bearing_deg'] = Variable<double>(bearingDeg.value);
    }
    if (limitKmh.present) {
      map['limit_kmh'] = Variable<int>(limitKmh.value);
    }
    if (sourceIds.present) {
      map['source_ids'] = Variable<String>(sourceIds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EnforcementItemsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('category: $category, ')
          ..write('country: $country, ')
          ..write('line: $line, ')
          ..write('lat: $lat, ')
          ..write('lon: $lon, ')
          ..write('bearingDeg: $bearingDeg, ')
          ..write('limitKmh: $limitKmh, ')
          ..write('sourceIds: $sourceIds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CacheDatabase extends GeneratedDatabase {
  _$CacheDatabase(QueryExecutor e) : super(e);
  late final Places places = Places(this);
  late final Index placesRegion = Index(
    'places_region',
    'CREATE INDEX places_region ON places (region)',
  );
  late final PlaceBounds placeBounds = PlaceBounds(this);
  late final PlaceSearch placeSearch = PlaceSearch(this);
  late final Trigger placesAfterInsert = Trigger(
    'CREATE TRIGGER places_after_insert AFTER INSERT ON places BEGIN INSERT INTO place_bounds (rid, min_lat, max_lat, min_lon, max_lon) VALUES (new.rid, new.lat, new.lat, new.lon, new.lon);INSERT INTO place_search ("rowid", name, city, postcode) VALUES (new.rid, new.name, new.city, new.postcode);END',
    'places_after_insert',
  );
  late final Trigger placesAfterDelete = Trigger(
    'CREATE TRIGGER places_after_delete AFTER DELETE ON places BEGIN DELETE FROM place_bounds WHERE rid = old.rid;INSERT INTO place_search (place_search, "rowid", name, city, postcode) VALUES (\'delete\', old.rid, old.name, old.city, old.postcode);END',
    'places_after_delete',
  );
  late final Trigger placesAfterUpdate = Trigger(
    'CREATE TRIGGER places_after_update AFTER UPDATE ON places BEGIN UPDATE place_bounds SET min_lat = new.lat, max_lat = new.lat, min_lon = new.lon, max_lon = new.lon WHERE rid = new.rid;INSERT INTO place_search (place_search, "rowid", name, city, postcode) VALUES (\'delete\', old.rid, old.name, old.city, old.postcode);INSERT INTO place_search ("rowid", name, city, postcode) VALUES (new.rid, new.name, new.city, new.postcode);END',
    'places_after_update',
  );
  late final RegionSyncs regionSyncs = RegionSyncs(this);
  late final PlaceExtrasCache placeExtrasCache = PlaceExtrasCache(this);
  late final PlaceCache placeCache = PlaceCache(this);
  late final DeviceState deviceState = DeviceState(this);
  late final PoiCache poiCache = PoiCache(this);
  late final EnforcementItems enforcementItems = EnforcementItems(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    places,
    placesRegion,
    placeBounds,
    placeSearch,
    placesAfterInsert,
    placesAfterDelete,
    placesAfterUpdate,
    regionSyncs,
    placeExtrasCache,
    placeCache,
    deviceState,
    poiCache,
    enforcementItems,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'places',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [
        TableUpdate('place_bounds', kind: UpdateKind.insert),
        TableUpdate('place_search', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'places',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('place_bounds', kind: UpdateKind.delete),
        TableUpdate('place_search', kind: UpdateKind.insert),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'places',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [
        TableUpdate('place_bounds', kind: UpdateKind.update),
        TableUpdate('place_search', kind: UpdateKind.insert),
      ],
    ),
  ]);
}

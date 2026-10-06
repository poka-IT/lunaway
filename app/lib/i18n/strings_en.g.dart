///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <en>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	dynamic operator[](String key) => _meta.getTranslation(key);

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations

	/// en: 'Lunaway'
	String get appTitle => 'Lunaway';

	late final Translations$nav$en nav = Translations$nav$en.internal(_root);
	late final Translations$common$en common = Translations$common$en.internal(_root);
	late final Translations$kinds$en kinds = Translations$kinds$en.internal(_root);
	late final Translations$families$en families = Translations$families$en.internal(_root);
	late final Translations$services$en services = Translations$services$en.internal(_root);
	late final Translations$activities$en activities = Translations$activities$en.internal(_root);
	late final Translations$amenities$en amenities = Translations$amenities$en.internal(_root);
	late final Translations$overnight$en overnight = Translations$overnight$en.internal(_root);
	late final Translations$freshness$en freshness = Translations$freshness$en.internal(_root);
	late final Translations$map$en map = Translations$map$en.internal(_root);
	late final Translations$search$en search = Translations$search$en.internal(_root);
	late final Translations$filters$en filters = Translations$filters$en.internal(_root);
	late final Translations$place$en place = Translations$place$en.internal(_root);
	late final Translations$hours$en hours = Translations$hours$en.internal(_root);
	late final Translations$directions$en directions = Translations$directions$en.internal(_root);
	late final Translations$list$en list = Translations$list$en.internal(_root);
	late final Translations$favorites$en favorites = Translations$favorites$en.internal(_root);
	late final Translations$profile$en profile = Translations$profile$en.internal(_root);
	late final Translations$units$en units = Translations$units$en.internal(_root);
	late final Translations$languages$en languages = Translations$languages$en.internal(_root);
	late final Translations$locale$en locale = Translations$locale$en.internal(_root);
}

// Path: nav
class Translations$nav$en {
	Translations$nav$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Map'
	String get map => 'Map';

	/// en: 'Favourites'
	String get favorites => 'Favourites';

	/// en: 'Profile'
	String get profile => 'Profile';
}

// Path: common
class Translations$common$en {
	Translations$common$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Try again'
	String get retry => 'Try again';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Undo'
	String get undo => 'Undo';

	/// en: 'More options'
	String get more => 'More options';
}

// Path: kinds
class Translations$kinds$en {
	Translations$kinds$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Motorhome area'
	String get motorhomeArea => 'Motorhome area';

	/// en: 'Service point'
	String get serviceArea => 'Service point';

	/// en: 'Campsite'
	String get campsite => 'Campsite';

	/// en: 'Car park'
	String get parking => 'Car park';

	/// en: 'Spot in nature'
	String get nature => 'Spot in nature';

	/// en: 'Rest area'
	String get restArea => 'Rest area';

	/// en: 'Picnic area'
	String get picnicArea => 'Picnic area';

	/// en: 'Farm stay'
	String get farm => 'Farm stay';

	/// en: 'Private host'
	String get homestay => 'Private host';

	/// en: 'Off-road spot'
	String get offRoad => 'Off-road spot';

	/// en: 'Useful stop'
	String get extraService => 'Useful stop';
}

// Path: families
class Translations$families$en {
	Translations$families$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Areas and car parks'
	String get stopovers => 'Areas and car parks';

	/// en: 'Campsites and hosts'
	String get campsites => 'Campsites and hosts';

	/// en: 'Nature'
	String get nature => 'Nature';

	/// en: 'Service points'
	String get services => 'Service points';
}

// Path: services
class Translations$services$en {
	Translations$services$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Drinking water'
	String get drinkingWater => 'Drinking water';

	/// en: 'Grey water drain'
	String get greyWater => 'Grey water drain';

	/// en: 'Toilet cassette'
	String get blackWater => 'Toilet cassette';

	/// en: 'Bins'
	String get wasteBin => 'Bins';

	/// en: 'Toilets'
	String get toilets => 'Toilets';

	/// en: 'Showers'
	String get showers => 'Showers';

	/// en: 'Electricity'
	String get electricity => 'Electricity';

	/// en: 'Wi-Fi'
	String get wifi => 'Wi-Fi';

	/// en: 'Laundry'
	String get laundry => 'Laundry';

	/// en: 'LPG'
	String get lpg => 'LPG';

	/// en: 'Gas bottles'
	String get gasBottles => 'Gas bottles';

	/// en: 'Vehicle wash'
	String get vehicleWash => 'Vehicle wash';

	/// en: 'Bakery'
	String get bakery => 'Bakery';

	/// en: 'Swimming pool'
	String get swimmingPool => 'Swimming pool';

	/// en: 'Pets welcome'
	String get petsAllowed => 'Pets welcome';

	/// en: 'Mobile data'
	String get mobileData => 'Mobile data';

	/// en: 'Winter stays'
	String get winterCaravanning => 'Winter stays';
}

// Path: activities
class Translations$activities$en {
	Translations$activities$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Sights'
	String get monuments => 'Sights';

	/// en: 'Windsurf, kitesurf'
	String get windsurfKitesurf => 'Windsurf, kitesurf';

	/// en: 'Mountain biking'
	String get mountainBiking => 'Mountain biking';

	/// en: 'Hiking'
	String get hiking => 'Hiking';

	/// en: 'Climbing'
	String get climbing => 'Climbing';

	/// en: 'Canoe, kayak'
	String get canoeKayak => 'Canoe, kayak';

	/// en: 'Fishing'
	String get fishing => 'Fishing';

	/// en: 'Shore fishing'
	String get shoreFishing => 'Shore fishing';

	/// en: 'Swimming'
	String get swimming => 'Swimming';

	/// en: 'Motorcycling'
	String get motorcycling => 'Motorcycling';

	/// en: 'Viewpoint'
	String get viewpoint => 'Viewpoint';

	/// en: 'Playground'
	String get playground => 'Playground';
}

// Path: amenities
class Translations$amenities$en {
	Translations$amenities$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Water'
	String get water => 'Water';

	/// en: 'Dump station'
	String get dumpStation => 'Dump station';

	/// en: 'Electricity'
	String get electricity => 'Electricity';

	/// en: 'Toilets'
	String get toilets => 'Toilets';
}

// Path: overnight
class Translations$overnight$en {
	Translations$overnight$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Night allowed'
	String get allowed => 'Night allowed';

	/// en: 'Night tolerated'
	String get tolerated => 'Night tolerated';

	/// en: 'Daytime only'
	String get dayOnly => 'Daytime only';

	/// en: 'No overnight stay'
	String get forbidden => 'No overnight stay';

	/// en: 'Night: not known'
	String get unknown => 'Night: not known';

	/// en: 'You can spend the night here.'
	String get allowedHint => 'You can spend the night here.';

	/// en: 'A night is usually accepted. Stay discreet and leave no trace.'
	String get toleratedHint => 'A night is usually accepted. Stay discreet and leave no trace.';

	/// en: 'Parking by day only. Find another spot for the night.'
	String get dayOnlyHint => 'Parking by day only. Find another spot for the night.';

	/// en: 'Spending the night here is banned.'
	String get forbiddenHint => 'Spending the night here is banned.';

	/// en: 'Nobody has told us yet whether a night is allowed.'
	String get unknownHint => 'Nobody has told us yet whether a night is allowed.';
}

// Path: freshness
class Translations$freshness$en {
	Translations$freshness$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Confirmed $when'
	String confirmed({required Object when}) => 'Confirmed ${when}';

	/// en: 'Updated $when'
	String updated({required Object when}) => 'Updated ${when}';

	/// en: 'Not confirmed for more than a year'
	String get stale => 'Not confirmed for more than a year';

	/// en: 'today'
	String get today => 'today';

	/// en: '(one) {yesterday} (other) {$n days ago}'
	String daysAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'yesterday',
		other: '${n} days ago',
	);

	/// en: '(one) {a month ago} (other) {$n months ago}'
	String monthsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'a month ago',
		other: '${n} months ago',
	);

	/// en: '(one) {a year ago} (other) {$n years ago}'
	String yearsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'a year ago',
		other: '${n} years ago',
	);
}

// Path: map
class Translations$map$en {
	Translations$map$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search a place or a town'
	String get searchHint => 'Search a place or a town';

	/// en: 'Clear the search'
	String get clearSearch => 'Clear the search';

	/// en: 'Show my position'
	String get locateMe => 'Show my position';

	/// en: 'Your position is not available. Check that location access is allowed.'
	String get locationUnavailable => 'Your position is not available. Check that location access is allowed.';

	/// en: 'Filters'
	String get filters => 'Filters';

	/// en: 'Show the list'
	String get showList => 'Show the list';

	/// en: 'Show the map'
	String get showMap => 'Show the map';

	/// en: '(one) {1 place here} (other) {$n places here}'
	String placesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 place here',
		other: '${n} places here',
	);

	/// en: 'The $n nearest places'
	String nearestPlaces({required Object n}) => 'The ${n} nearest places';

	/// en: 'Selected point'
	String get pointTitle => 'Selected point';

	/// en: 'Downloading the places of France'
	String get downloading => 'Downloading the places of France';

	/// en: '(one) {1 place received} (other) {$n places received}'
	String downloadingCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 place received',
		other: '${n} places received',
	);

	/// en: 'No place on this device yet'
	String get noData => 'No place on this device yet';

	/// en: 'Download the places once; the map then works without network.'
	String get noDataHint => 'Download the places once; the map then works without network.';

	/// en: 'Download the places'
	String get download => 'Download the places';

	/// en: 'The download failed. Check the connection and try again.'
	String get downloadFailed => 'The download failed. Check the connection and try again.';

	/// en: 'Demo: invented places'
	String get demoBanner => 'Demo: invented places';

	/// en: 'The map is not available on this system. Use the web app.'
	String get unsupported => 'The map is not available on this system. Use the web app.';
}

// Path: search
class Translations$search$en {
	Translations$search$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Towns'
	String get towns => 'Towns';

	/// en: 'Places'
	String get places => 'Places';

	/// en: 'No place or town matches “$query”.'
	String noResult({required Object query}) => 'No place or town matches “${query}”.';

	/// en: '(one) {1 place} (other) {$n places}'
	String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 place',
		other: '${n} places',
	);
}

// Path: filters
class Translations$filters$en {
	Translations$filters$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Filters'
	String get title => 'Filters';

	/// en: 'Type of place'
	String get families => 'Type of place';

	/// en: 'Night allowed'
	String get night => 'Night allowed';

	/// en: 'Allowed or tolerated'
	String get nightHint => 'Allowed or tolerated';

	/// en: 'Services'
	String get amenities => 'Services';

	/// en: 'Vehicle height'
	String get height => 'Vehicle height';

	/// en: 'Any height'
	String get heightAny => 'Any height';

	/// en: 'Hides places with a lower height barrier. Places whose barrier is unknown stay visible.'
	String get heightHint => 'Hides places with a lower height barrier. Places whose barrier is unknown stay visible.';

	/// en: 'Reset'
	String get reset => 'Reset';

	/// en: '(zero) {No place matches} (one) {Show 1 place} (other) {Show $n places}'
	String show({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		zero: 'No place matches',
		one: 'Show 1 place',
		other: 'Show ${n} places',
	);

	/// en: '(one) {1 filter on} (other) {$n filters on}'
	String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 filter on',
		other: '${n} filters on',
	);
}

// Path: place
class Translations$place$en {
	Translations$place$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$kind in $town'
	String unnamedIn({required Object kind, required Object town}) => '${kind} in ${town}';

	/// en: 'Directions'
	String get directions => 'Directions';

	/// en: 'Share'
	String get share => 'Share';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'Save to a list'
	String get saveTo => 'Save to a list';

	/// en: 'Saved in your favourites'
	String get savedToast => 'Saved in your favourites';

	/// en: 'Removed from your favourites'
	String get removedToast => 'Removed from your favourites';

	/// en: 'Good to know'
	String get facts => 'Good to know';

	/// en: 'Per night'
	String get pricePerNight => 'Per night';

	/// en: 'Free'
	String get priceFree => 'Free';

	/// en: 'Not known'
	String get priceUnknown => 'Not known';

	/// en: 'Services'
	String get priceServices => 'Services';

	/// en: 'Height limit'
	String get maxHeight => 'Height limit';

	/// en: 'Pitches'
	String get capacity => 'Pitches';

	/// en: 'Classification'
	String get classification => 'Classification';

	/// en: '(one) {$n star} (other) {$n stars}'
	String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} star',
		other: '${n} stars',
	);

	/// en: 'Opening hours'
	String get hours => 'Opening hours';

	/// en: 'Services'
	String get services => 'Services';

	/// en: 'No service listed.'
	String get noServices => 'No service listed.';

	/// en: 'Nearby'
	String get activities => 'Nearby';

	/// en: 'Description'
	String get description => 'Description';

	/// en: 'Contact'
	String get contact => 'Contact';

	/// en: 'Website'
	String get website => 'Website';

	/// en: 'Call'
	String get call => 'Call';

	/// en: 'Coordinates'
	String get coordinates => 'Coordinates';

	/// en: 'Copy the coordinates'
	String get copy => 'Copy the coordinates';

	/// en: 'Copied: $text'
	String copied({required Object text}) => 'Copied: ${text}';

	/// en: 'Other formats'
	String get otherFormats => 'Other formats';

	/// en: 'Decimal degrees'
	String get formatDecimal => 'Decimal degrees';

	/// en: 'Degrees, minutes, seconds'
	String get formatDms => 'Degrees, minutes, seconds';

	/// en: 'geo: link'
	String get formatGeo => 'geo: link';

	/// en: 'Google Maps link'
	String get formatGoogle => 'Google Maps link';

	/// en: 'OpenStreetMap link'
	String get formatOsm => 'OpenStreetMap link';

	/// en: 'Sources'
	String get sources => 'Sources';

	/// en: 'Read $when'
	String fetched({required Object when}) => 'Read ${when}';

	/// en: 'Match $score %'
	String matchScore({required Object score}) => 'Match ${score} %';

	/// en: 'View at the source'
	String get viewSource => 'View at the source';

	/// en: 'This place is no longer in the data.'
	String get gone => 'This place is no longer in the data.';

	/// en: 'This place could not be read.'
	String get loadError => 'This place could not be read.';

	/// en: 'No app could open this link.'
	String get openFailed => 'No app could open this link.';

	/// en: 'Photos'
	String get photos => 'Photos';

	/// en: 'Photos and reviews need a connection.'
	String get extrasOffline => 'Photos and reviews need a connection.';

	/// en: 'Reviews'
	String get reviewsTitle => 'Reviews';

	/// en: '(one) {1 review} (other) {$n reviews}'
	String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 review',
		other: '${n} reviews',
	);

	/// en: 'No review yet.'
	String get noReviews => 'No review yet.';

	/// en: 'More reviews'
	String get moreReviews => 'More reviews';

	/// en: 'More reviews could not load. Tap to try again.'
	String get moreReviewsFailed => 'More reviews could not load. Tap to try again.';

	/// en: '$rating out of 5'
	String stars({required Object rating}) => '${rating} out of 5';

	/// en: 'Original text in $language'
	String originalLanguage({required Object language}) => 'Original text in ${language}';

	/// en: 'Photo $index of $count'
	String photoPosition({required Object index, required Object count}) => 'Photo ${index} of ${count}';

	/// en: 'Elsewhere'
	String get links => 'Elsewhere';
}

// Path: hours
class Translations$hours$en {
	Translations$hours$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Open now'
	String get open => 'Open now';

	/// en: 'Open, closes at $time'
	String openUntil({required Object time}) => 'Open, closes at ${time}';

	/// en: 'Open, closes $day at $time'
	String openUntilDay({required Object day, required Object time}) => 'Open, closes ${day} at ${time}';

	/// en: '(one) {Open, closes in 1 minute} (other) {Open, closes in $n minutes}'
	String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Open, closes in 1 minute',
		other: 'Open, closes in ${n} minutes',
	);

	/// en: 'Closed, opens at $time'
	String closedUntil({required Object time}) => 'Closed, opens at ${time}';

	/// en: 'Closed, opens $day at $time'
	String closedUntilDay({required Object day, required Object time}) => 'Closed, opens ${day} at ${time}';

	/// en: '(one) {Closed, opens in 1 minute} (other) {Closed, opens in $n minutes}'
	String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Closed, opens in 1 minute',
		other: 'Closed, opens in ${n} minutes',
	);

	/// en: 'Closed for the next two weeks'
	String get closedWindow => 'Closed for the next two weeks';

	/// en: 'tomorrow'
	String get tomorrow => 'tomorrow';

	/// en: 'on $date'
	String onDate({required Object date}) => 'on ${date}';

	/// en: 'midnight'
	String get midnight => 'midnight';

	/// en: 'Open or closed unknown: the data needs an update'
	String get stale => 'Open or closed unknown: the data needs an update';
}

// Path: directions
class Translations$directions$en {
	Translations$directions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Navigate with'
	String get title => 'Navigate with';

	/// en: 'Apple Maps'
	String get appleMaps => 'Apple Maps';

	/// en: 'Google Maps'
	String get googleMaps => 'Google Maps';

	/// en: 'Waze'
	String get waze => 'Waze';

	/// en: 'OpenStreetMap'
	String get osm => 'OpenStreetMap';

	/// en: 'A navigation app'
	String get system => 'A navigation app';
}

// Path: list
class Translations$list$en {
	Translations$list$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Places around'
	String get title => 'Places around';

	/// en: 'No place in this area with these filters.'
	String get empty => 'No place in this area with these filters.';

	/// en: 'Move the map, zoom out or loosen the filters.'
	String get emptyHint => 'Move the map, zoom out or loosen the filters.';

	/// en: 'The list could not be read.'
	String get error => 'The list could not be read.';
}

// Path: favorites
class Translations$favorites$en {
	Translations$favorites$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Favourites'
	String get title => 'Favourites';

	/// en: 'My favourites'
	String get defaultList => 'My favourites';

	/// en: 'Your saved places will appear here.'
	String get empty => 'Your saved places will appear here.';

	/// en: 'Tap Save on a place to keep it, even offline.'
	String get emptyHint => 'Tap Save on a place to keep it, even offline.';

	/// en: 'New list'
	String get newList => 'New list';

	/// en: 'Name of the list'
	String get listName => 'Name of the list';

	/// en: 'Rename the list'
	String get renameList => 'Rename the list';

	/// en: 'Delete the list'
	String get deleteList => 'Delete the list';

	/// en: 'Delete “$name”? The places stay on the map.'
	String deleteListConfirm({required Object name}) => 'Delete “${name}”? The places stay on the map.';

	/// en: 'Removed from the list'
	String get removed => 'Removed from the list';

	/// en: '(zero) {Empty} (one) {1 place} (other) {$n places}'
	String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		zero: 'Empty',
		one: '1 place',
		other: '${n} places',
	);

	/// en: 'Your favourites could not be read.'
	String get error => 'Your favourites could not be read.';
}

// Path: profile
class Translations$profile$en {
	Translations$profile$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Profile'
	String get title => 'Profile';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'Device'
	String get languageSystem => 'Device';

	/// en: 'No account needed. No ads, no trackers: the map and your favourites stay on this device.'
	String get noAccountNeeded => 'No account needed. No ads, no trackers: the map and your favourites stay on this device.';

	/// en: 'Offline data'
	String get offline => 'Offline data';

	/// en: '(zero) {No place on this device} (one) {1 place on this device} (other) {$n places on this device}'
	String offlinePlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		zero: 'No place on this device',
		one: '1 place on this device',
		other: '${n} places on this device',
	);

	/// en: 'Storage used: $size'
	String offlineSize({required Object size}) => 'Storage used: ${size}';

	/// en: 'Last update $when'
	String lastSync({required Object when}) => 'Last update ${when}';

	/// en: 'Never downloaded'
	String get neverSynced => 'Never downloaded';

	/// en: 'Update now'
	String get syncNow => 'Update now';

	/// en: 'Updating'
	String get syncing => 'Updating';

	/// en: 'The places are up to date.'
	String get syncDone => 'The places are up to date.';

	/// en: 'The update failed. The places on this device still work.'
	String get syncFailed => 'The update failed. The places on this device still work.';

	/// en: 'About'
	String get about => 'About';

	/// en: 'Version $version'
	String version({required Object version}) => 'Version ${version}';

	/// en: 'Website'
	String get website => 'Website';

	/// en: 'Privacy policy'
	String get privacy => 'Privacy policy';

	/// en: 'Source code'
	String get sourceCode => 'Source code';

	/// en: 'Licences'
	String get licences => 'Licences';

	/// en: 'Data and map'
	String get attributions => 'Data and map';

	/// en: 'Places and map data © OpenStreetMap contributors, under the Open Database License (ODbL).'
	String get attributionOsm => 'Places and map data © OpenStreetMap contributors, under the Open Database License (ODbL).';

	/// en: 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).'
	String get attributionAtout => 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).';

	/// en: 'Map by OpenFreeMap, © OpenMapTiles, data © OpenStreetMap contributors.'
	String get attributionTiles => 'Map by OpenFreeMap, © OpenMapTiles, data © OpenStreetMap contributors.';

	/// en: 'Atkinson Hyperlegible Next typeface, SIL Open Font License 1.1.'
	String get attributionFont => 'Atkinson Hyperlegible Next typeface, SIL Open Font License 1.1.';

	/// en: 'Lunaway is free software under the GNU AGPL 3.0 or later.'
	String get appLicence => 'Lunaway is free software under the GNU AGPL 3.0 or later.';
}

// Path: units
class Translations$units$en {
	Translations$units$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$n kB'
	String kilobytes({required Object n}) => '${n} kB';

	/// en: '$n MB'
	String megabytes({required Object n}) => '${n} MB';
}

// Path: languages
class Translations$languages$en {
	Translations$languages$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'French'
	String get fr => 'French';

	/// en: 'English'
	String get en => 'English';

	/// en: 'German'
	String get de => 'German';

	/// en: 'Spanish'
	String get es => 'Spanish';

	/// en: 'Italian'
	String get it => 'Italian';

	/// en: 'Dutch'
	String get nl => 'Dutch';
}

// Path: locale
class Translations$locale$en {
	Translations$locale$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'English'
	String get en => 'English';

	/// en: 'Français'
	String get fr => 'Français';
}

/// The flat map containing all translations for locale <en>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on Translations {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Map',
			'nav.favorites' => 'Favourites',
			'nav.profile' => 'Profile',
			'common.close' => 'Close',
			'common.cancel' => 'Cancel',
			'common.retry' => 'Try again',
			'common.save' => 'Save',
			'common.delete' => 'Delete',
			'common.undo' => 'Undo',
			'common.more' => 'More options',
			'kinds.motorhomeArea' => 'Motorhome area',
			'kinds.serviceArea' => 'Service point',
			'kinds.campsite' => 'Campsite',
			'kinds.parking' => 'Car park',
			'kinds.nature' => 'Spot in nature',
			'kinds.restArea' => 'Rest area',
			'kinds.picnicArea' => 'Picnic area',
			'kinds.farm' => 'Farm stay',
			'kinds.homestay' => 'Private host',
			'kinds.offRoad' => 'Off-road spot',
			'kinds.extraService' => 'Useful stop',
			'families.stopovers' => 'Areas and car parks',
			'families.campsites' => 'Campsites and hosts',
			'families.nature' => 'Nature',
			'families.services' => 'Service points',
			'services.drinkingWater' => 'Drinking water',
			'services.greyWater' => 'Grey water drain',
			'services.blackWater' => 'Toilet cassette',
			'services.wasteBin' => 'Bins',
			'services.toilets' => 'Toilets',
			'services.showers' => 'Showers',
			'services.electricity' => 'Electricity',
			'services.wifi' => 'Wi-Fi',
			'services.laundry' => 'Laundry',
			'services.lpg' => 'LPG',
			'services.gasBottles' => 'Gas bottles',
			'services.vehicleWash' => 'Vehicle wash',
			'services.bakery' => 'Bakery',
			'services.swimmingPool' => 'Swimming pool',
			'services.petsAllowed' => 'Pets welcome',
			'services.mobileData' => 'Mobile data',
			'services.winterCaravanning' => 'Winter stays',
			'activities.monuments' => 'Sights',
			'activities.windsurfKitesurf' => 'Windsurf, kitesurf',
			'activities.mountainBiking' => 'Mountain biking',
			'activities.hiking' => 'Hiking',
			'activities.climbing' => 'Climbing',
			'activities.canoeKayak' => 'Canoe, kayak',
			'activities.fishing' => 'Fishing',
			'activities.shoreFishing' => 'Shore fishing',
			'activities.swimming' => 'Swimming',
			'activities.motorcycling' => 'Motorcycling',
			'activities.viewpoint' => 'Viewpoint',
			'activities.playground' => 'Playground',
			'amenities.water' => 'Water',
			'amenities.dumpStation' => 'Dump station',
			'amenities.electricity' => 'Electricity',
			'amenities.toilets' => 'Toilets',
			'overnight.allowed' => 'Night allowed',
			'overnight.tolerated' => 'Night tolerated',
			'overnight.dayOnly' => 'Daytime only',
			'overnight.forbidden' => 'No overnight stay',
			'overnight.unknown' => 'Night: not known',
			'overnight.allowedHint' => 'You can spend the night here.',
			'overnight.toleratedHint' => 'A night is usually accepted. Stay discreet and leave no trace.',
			'overnight.dayOnlyHint' => 'Parking by day only. Find another spot for the night.',
			'overnight.forbiddenHint' => 'Spending the night here is banned.',
			'overnight.unknownHint' => 'Nobody has told us yet whether a night is allowed.',
			'freshness.confirmed' => ({required Object when}) => 'Confirmed ${when}',
			'freshness.updated' => ({required Object when}) => 'Updated ${when}',
			'freshness.stale' => 'Not confirmed for more than a year',
			'freshness.today' => 'today',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'yesterday', other: '${n} days ago', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'a month ago', other: '${n} months ago', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'a year ago', other: '${n} years ago', ), 
			'map.searchHint' => 'Search a place or a town',
			'map.clearSearch' => 'Clear the search',
			'map.locateMe' => 'Show my position',
			'map.locationUnavailable' => 'Your position is not available. Check that location access is allowed.',
			'map.filters' => 'Filters',
			'map.showList' => 'Show the list',
			'map.showMap' => 'Show the map',
			'map.placesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 place here', other: '${n} places here', ), 
			'map.nearestPlaces' => ({required Object n}) => 'The ${n} nearest places',
			'map.pointTitle' => 'Selected point',
			'map.downloading' => 'Downloading the places of France',
			'map.downloadingCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 place received', other: '${n} places received', ), 
			'map.noData' => 'No place on this device yet',
			'map.noDataHint' => 'Download the places once; the map then works without network.',
			'map.download' => 'Download the places',
			'map.downloadFailed' => 'The download failed. Check the connection and try again.',
			'map.demoBanner' => 'Demo: invented places',
			'map.unsupported' => 'The map is not available on this system. Use the web app.',
			'search.towns' => 'Towns',
			'search.places' => 'Places',
			'search.noResult' => ({required Object query}) => 'No place or town matches “${query}”.',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 place', other: '${n} places', ), 
			'filters.title' => 'Filters',
			'filters.families' => 'Type of place',
			'filters.night' => 'Night allowed',
			'filters.nightHint' => 'Allowed or tolerated',
			'filters.amenities' => 'Services',
			'filters.height' => 'Vehicle height',
			'filters.heightAny' => 'Any height',
			'filters.heightHint' => 'Hides places with a lower height barrier. Places whose barrier is unknown stay visible.',
			'filters.reset' => 'Reset',
			'filters.show' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, zero: 'No place matches', one: 'Show 1 place', other: 'Show ${n} places', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 filter on', other: '${n} filters on', ), 
			'place.unnamedIn' => ({required Object kind, required Object town}) => '${kind} in ${town}',
			'place.directions' => 'Directions',
			'place.share' => 'Share',
			'place.save' => 'Save',
			'place.saved' => 'Saved',
			'place.saveTo' => 'Save to a list',
			'place.savedToast' => 'Saved in your favourites',
			'place.removedToast' => 'Removed from your favourites',
			'place.facts' => 'Good to know',
			'place.pricePerNight' => 'Per night',
			'place.priceFree' => 'Free',
			'place.priceUnknown' => 'Not known',
			'place.priceServices' => 'Services',
			'place.maxHeight' => 'Height limit',
			'place.capacity' => 'Pitches',
			'place.classification' => 'Classification',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} star', other: '${n} stars', ), 
			'place.hours' => 'Opening hours',
			'place.services' => 'Services',
			'place.noServices' => 'No service listed.',
			'place.activities' => 'Nearby',
			'place.description' => 'Description',
			'place.contact' => 'Contact',
			'place.website' => 'Website',
			'place.call' => 'Call',
			'place.coordinates' => 'Coordinates',
			'place.copy' => 'Copy the coordinates',
			'place.copied' => ({required Object text}) => 'Copied: ${text}',
			'place.otherFormats' => 'Other formats',
			'place.formatDecimal' => 'Decimal degrees',
			'place.formatDms' => 'Degrees, minutes, seconds',
			'place.formatGeo' => 'geo: link',
			'place.formatGoogle' => 'Google Maps link',
			'place.formatOsm' => 'OpenStreetMap link',
			'place.sources' => 'Sources',
			'place.fetched' => ({required Object when}) => 'Read ${when}',
			'place.matchScore' => ({required Object score}) => 'Match ${score} %',
			'place.viewSource' => 'View at the source',
			'place.gone' => 'This place is no longer in the data.',
			'place.loadError' => 'This place could not be read.',
			'place.openFailed' => 'No app could open this link.',
			'place.photos' => 'Photos',
			'place.extrasOffline' => 'Photos and reviews need a connection.',
			'place.reviewsTitle' => 'Reviews',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 review', other: '${n} reviews', ), 
			'place.noReviews' => 'No review yet.',
			'place.moreReviews' => 'More reviews',
			'place.moreReviewsFailed' => 'More reviews could not load. Tap to try again.',
			'place.stars' => ({required Object rating}) => '${rating} out of 5',
			'place.originalLanguage' => ({required Object language}) => 'Original text in ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Photo ${index} of ${count}',
			'place.links' => 'Elsewhere',
			'hours.open' => 'Open now',
			'hours.openUntil' => ({required Object time}) => 'Open, closes at ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Open, closes ${day} at ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Open, closes in 1 minute', other: 'Open, closes in ${n} minutes', ), 
			'hours.closedUntil' => ({required Object time}) => 'Closed, opens at ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Closed, opens ${day} at ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Closed, opens in 1 minute', other: 'Closed, opens in ${n} minutes', ), 
			'hours.closedWindow' => 'Closed for the next two weeks',
			'hours.tomorrow' => 'tomorrow',
			'hours.onDate' => ({required Object date}) => 'on ${date}',
			'hours.midnight' => 'midnight',
			'hours.stale' => 'Open or closed unknown: the data needs an update',
			'directions.title' => 'Navigate with',
			'directions.appleMaps' => 'Apple Maps',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osm' => 'OpenStreetMap',
			'directions.system' => 'A navigation app',
			'list.title' => 'Places around',
			'list.empty' => 'No place in this area with these filters.',
			'list.emptyHint' => 'Move the map, zoom out or loosen the filters.',
			'list.error' => 'The list could not be read.',
			'favorites.title' => 'Favourites',
			'favorites.defaultList' => 'My favourites',
			'favorites.empty' => 'Your saved places will appear here.',
			'favorites.emptyHint' => 'Tap Save on a place to keep it, even offline.',
			'favorites.newList' => 'New list',
			'favorites.listName' => 'Name of the list',
			'favorites.renameList' => 'Rename the list',
			'favorites.deleteList' => 'Delete the list',
			'favorites.deleteListConfirm' => ({required Object name}) => 'Delete “${name}”? The places stay on the map.',
			'favorites.removed' => 'Removed from the list',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, zero: 'Empty', one: '1 place', other: '${n} places', ), 
			'favorites.error' => 'Your favourites could not be read.',
			'profile.title' => 'Profile',
			'profile.language' => 'Language',
			'profile.languageSystem' => 'Device',
			'profile.noAccountNeeded' => 'No account needed. No ads, no trackers: the map and your favourites stay on this device.',
			'profile.offline' => 'Offline data',
			'profile.offlinePlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, zero: 'No place on this device', one: '1 place on this device', other: '${n} places on this device', ), 
			'profile.offlineSize' => ({required Object size}) => 'Storage used: ${size}',
			'profile.lastSync' => ({required Object when}) => 'Last update ${when}',
			'profile.neverSynced' => 'Never downloaded',
			'profile.syncNow' => 'Update now',
			'profile.syncing' => 'Updating',
			'profile.syncDone' => 'The places are up to date.',
			'profile.syncFailed' => 'The update failed. The places on this device still work.',
			'profile.about' => 'About',
			'profile.version' => ({required Object version}) => 'Version ${version}',
			'profile.website' => 'Website',
			'profile.privacy' => 'Privacy policy',
			'profile.sourceCode' => 'Source code',
			'profile.licences' => 'Licences',
			'profile.attributions' => 'Data and map',
			'profile.attributionOsm' => 'Places and map data © OpenStreetMap contributors, under the Open Database License (ODbL).',
			'profile.attributionAtout' => 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).',
			'profile.attributionTiles' => 'Map by OpenFreeMap, © OpenMapTiles, data © OpenStreetMap contributors.',
			'profile.attributionFont' => 'Atkinson Hyperlegible Next typeface, SIL Open Font License 1.1.',
			'profile.appLicence' => 'Lunaway is free software under the GNU AGPL 3.0 or later.',
			'units.kilobytes' => ({required Object n}) => '${n} kB',
			'units.megabytes' => ({required Object n}) => '${n} MB',
			'languages.fr' => 'French',
			'languages.en' => 'English',
			'languages.de' => 'German',
			'languages.es' => 'Spanish',
			'languages.it' => 'Italian',
			'languages.nl' => 'Dutch',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			_ => null,
		};
	}
}

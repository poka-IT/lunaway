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
	late final Translations$sync$en sync = Translations$sync$en.internal(_root);
	late final Translations$location$en location = Translations$location$en.internal(_root);
	late final Translations$search$en search = Translations$search$en.internal(_root);
	late final Translations$filters$en filters = Translations$filters$en.internal(_root);
	late final Translations$place$en place = Translations$place$en.internal(_root);
	late final Translations$hours$en hours = Translations$hours$en.internal(_root);
	late final Translations$directions$en directions = Translations$directions$en.internal(_root);
	late final Translations$navigation$en navigation = Translations$navigation$en.internal(_root);
	late final Translations$list$en list = Translations$list$en.internal(_root);
	late final Translations$favorites$en favorites = Translations$favorites$en.internal(_root);
	late final Translations$vehicle$en vehicle = Translations$vehicle$en.internal(_root);
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

	/// en: 'Got it'
	String get ok => 'Got it';

	/// en: 'The change could not be saved.'
	String get saveFailed => 'The change could not be saved.';
}

// Path: kinds
class Translations$kinds$en {
	Translations$kinds$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Motorhome area'
	String get motorhomeArea => 'Motorhome area';

	/// en: 'Service area'
	String get serviceArea => 'Service area';

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

	/// en: 'Handy stop'
	String get extraService => 'Handy stop';
}

// Path: families
class Translations$families$en {
	Translations$families$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Areas and car parks'
	String get stopovers => 'Areas and car parks';

	/// en: 'Motorhome areas, car parks, rest areas'
	String get stopoversHint => 'Motorhome areas, car parks, rest areas';

	/// en: 'Campsites and hosts'
	String get campsites => 'Campsites and hosts';

	/// en: 'Campsites, farms, private hosts'
	String get campsitesHint => 'Campsites, farms, private hosts';

	/// en: 'Nature'
	String get nature => 'Nature';

	/// en: 'Spots in nature, tracks'
	String get natureHint => 'Spots in nature, tracks';

	/// en: 'Services'
	String get services => 'Services';

	/// en: 'Water and dump points, no night'
	String get servicesHint => 'Water and dump points, no night';
}

// Path: services
class Translations$services$en {
	Translations$services$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Drinking water'
	String get drinkingWater => 'Drinking water';

	/// en: 'Grey water dump'
	String get greyWater => 'Grey water dump';

	/// en: 'Cassette dump'
	String get blackWater => 'Cassette dump';

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

	/// en: 'Mobile signal'
	String get mobileData => 'Mobile signal';

	/// en: 'Open in winter'
	String get winterCaravanning => 'Open in winter';
}

// Path: activities
class Translations$activities$en {
	Translations$activities$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Sights'
	String get monuments => 'Sights';

	/// en: 'Windsurfing, kitesurfing'
	String get windsurfKitesurf => 'Windsurfing, kitesurfing';

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

	/// en: 'Motorcycle rides'
	String get motorcycling => 'Motorcycle rides';

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

	/// en: 'Dump point'
	String get dumpStation => 'Dump point';

	/// en: 'Electricity'
	String get electricity => 'Electricity';

	/// en: 'Toilets'
	String get toilets => 'Toilets';

	/// en: 'Showers'
	String get showers => 'Showers';

	/// en: 'Bins'
	String get wasteBin => 'Bins';

	/// en: 'Laundry'
	String get laundry => 'Laundry';

	/// en: 'Wi-Fi'
	String get wifi => 'Wi-Fi';

	/// en: 'LPG'
	String get lpg => 'LPG';
}

// Path: overnight
class Translations$overnight$en {
	Translations$overnight$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Overnight allowed'
	String get allowed => 'Overnight allowed';

	/// en: 'Overnight tolerated'
	String get tolerated => 'Overnight tolerated';

	/// en: 'Daytime only'
	String get dayOnly => 'Daytime only';

	/// en: 'No overnight'
	String get forbidden => 'No overnight';

	/// en: 'Overnight not reported'
	String get unknown => 'Overnight not reported';

	/// en: 'You may spend the night here.'
	String get allowedHint => 'You may spend the night here.';

	/// en: 'A night is usually accepted. Stay discreet and leave no trace.'
	String get toleratedHint => 'A night is usually accepted. Stay discreet and leave no trace.';

	/// en: 'Daytime parking only. Look for another place for the night.'
	String get dayOnlyHint => 'Daytime parking only. Look for another place for the night.';

	/// en: 'Spending the night here is forbidden.'
	String get forbiddenHint => 'Spending the night here is forbidden.';

	/// en: 'Nobody has said yet. Ask on site.'
	String get unknownHint => 'Nobody has said yet. Ask on site.';
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

	/// en: 'Not confirmed for over a year'
	String get stale => 'Not confirmed for over a year';

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

	/// en: 'A place, a town'
	String get searchHint => 'A place, a town';

	/// en: 'Clear the search'
	String get clearSearch => 'Clear the search';

	/// en: 'Show my position'
	String get locateMe => 'Show my position';

	/// en: 'Zoom in'
	String get zoomIn => 'Zoom in';

	/// en: 'Zoom out'
	String get zoomOut => 'Zoom out';

	/// en: 'Filters'
	String get filters => 'Filters';

	/// en: '© OpenStreetMap · Protomaps'
	String get credit => '© OpenStreetMap · Protomaps';

	/// en: 'Map credits: © OpenStreetMap contributors, Protomaps style. Opens the OpenStreetMap copyright page.'
	String get creditLabel => 'Map credits: © OpenStreetMap contributors, Protomaps style. Opens the OpenStreetMap copyright page.';

	/// en: 'List'
	String get showList => 'List';

	/// en: '(one) {List ($n)} (other) {List ($n)}'
	String showListCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'List (${n})',
		other: 'List (${n})',
	);

	/// en: '(one) {place here} (other) {places here}'
	String placesHereLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'place here',
		other: 'places here',
	);

	/// en: '(one) {nearest place} (other) {nearest places}'
	String nearestPlacesLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'nearest place',
		other: 'nearest places',
	);

	/// en: 'Chosen point'
	String get pointTitle => 'Chosen point';

	/// en: 'Its coordinates and the way there'
	String get pointHint => 'Its coordinates and the way there';

	/// en: 'Downloading the places of France'
	String get downloading => 'Downloading the places of France';

	/// en: '(one) {$count place received} (other) {$count places received}'
	String downloadingCount({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${count} place received',
		other: '${count} places received',
	);

	/// en: 'No places on this device yet'
	String get noData => 'No places on this device yet';

	/// en: 'Download the places once: the map then works without a network.'
	String get noDataHint => 'Download the places once: the map then works without a network.';

	/// en: 'Download the places'
	String get download => 'Download the places';

	/// en: 'The download stopped'
	String get downloadFailed => 'The download stopped';

	/// en: 'Demo: invented places'
	String get demoBanner => 'Demo: invented places';

	/// en: 'The map is not available on this system. Use the web app.'
	String get unsupported => 'The map is not available on this system. Use the web app.';
}

// Path: sync
class Translations$sync$en {
	Translations$sync$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No connection for now.'
	String get failedOffline => 'No connection for now.';

	/// en: 'The server is very busy.'
	String get failedBusy => 'The server is very busy.';

	/// en: 'The server has a problem for now.'
	String get failedServer => 'The server has a problem for now.';

	/// en: 'The update did not go through.'
	String get failedOther => 'The update did not go through.';

	/// en: 'The server refused the update. A newer version of the app may be needed.'
	String get failedRefused => 'The server refused the update. A newer version of the app may be needed.';

	/// en: 'Lunaway will try again by itself.'
	String get willRetry => 'Lunaway will try again by itself.';

	/// en: 'Download incomplete: $count places so far'
	String incomplete({required Object count}) => 'Download incomplete: ${count} places so far';

	/// en: 'Download incomplete'
	String get incompleteShort => 'Download incomplete';

	/// en: 'Downloading: $count places'
	String resuming({required Object count}) => 'Downloading: ${count} places';

	/// en: 'Resume'
	String get resume => 'Resume';
}

// Path: location
class Translations$location$en {
	Translations$location$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Show your position?'
	String get rationaleTitle => 'Show your position?';

	/// en: 'Lunaway uses it to centre the map on you and sort places by distance. Your position stays on the device.'
	String get rationale => 'Lunaway uses it to centre the map on you and sort places by distance. Your position stays on the device.';

	/// en: 'Continue'
	String get allow => 'Continue';

	/// en: 'Not now'
	String get notNow => 'Not now';

	/// en: 'Position turned off for Lunaway'
	String get deniedTitle => 'Position turned off for Lunaway';

	/// en: 'You refused access to your position. To use it, allow it in the device settings.'
	String get denied => 'You refused access to your position. To use it, allow it in the device settings.';

	/// en: 'Open settings'
	String get openSettings => 'Open settings';

	/// en: 'Location is off'
	String get serviceOffTitle => 'Location is off';

	/// en: 'Location is turned off on this device. Turn it on in the quick settings, then try again.'
	String get serviceOff => 'Location is turned off on this device. Turn it on in the quick settings, then try again.';

	/// en: 'Position not allowed. The map works without it.'
	String get notAllowed => 'Position not allowed. The map works without it.';

	/// en: 'Your position is not coming through. Try in the open, or in a moment.'
	String get noFix => 'Your position is not coming through. Try in the open, or in a moment.';

	/// en: 'This device does not give its position.'
	String get unsupported => 'This device does not give its position.';
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

	/// en: 'No place or town matches "$query".'
	String noResult({required Object query}) => 'No place or town matches "${query}".';

	/// en: '(one) {$n place} (other) {$n places}'
	String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} place',
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

	/// en: 'Kind of place'
	String get families => 'Kind of place';

	/// en: 'None chosen: every kind'
	String get familiesHint => 'None chosen: every kind';

	/// en: 'The night'
	String get night => 'The night';

	/// en: 'None chosen: every place'
	String get nightHint => 'None chosen: every place';

	/// en: 'Night possible'
	String get nightPossible => 'Night possible';

	/// en: 'Services'
	String get amenities => 'Services';

	/// en: 'The place must have all of them'
	String get amenitiesHint => 'The place must have all of them';

	/// en: 'My vehicle'
	String get vehicle => 'My vehicle';

	/// en: 'My vehicle fits'
	String get myVehicleFits => 'My vehicle fits';

	/// en: 'Fits $height'
	String myVehicleFitsHeight({required Object height}) => 'Fits ${height}';

	/// en: 'Hides places limited below $height. Unknown heights stay.'
	String myVehicleHint({required Object height}) => 'Hides places limited below ${height}. Unknown heights stay.';

	/// en: 'Give your vehicle's height to use it.'
	String get myVehicleUnknown => 'Give your vehicle\'s height to use it.';

	/// en: 'Clear all'
	String get reset => 'Clear all';

	/// en: 'Apply'
	String get apply => 'Apply';

	/// en: '(zero) {No place matches} (one) {Show $count place} (other) {Show $count places}'
	String show({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		zero: 'No place matches',
		one: 'Show ${count} place',
		other: 'Show ${count} places',
	);

	/// en: '(one) {$n filter on} (other) {$n filters on}'
	String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} filter on',
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

	/// en: '$distance away'
	String away({required Object distance}) => '${distance} away';

	/// en: 'Directions'
	String get directions => 'Directions';

	/// en: 'Share'
	String get share => 'Share';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Saved'
	String get saved => 'Saved';

	/// en: 'In My favourites. Long press to choose lists.'
	String get saveHint => 'In My favourites. Long press to choose lists.';

	/// en: 'Save to a list'
	String get saveTo => 'Save to a list';

	/// en: 'Lists'
	String get chooseLists => 'Lists';

	/// en: 'Added to My favourites'
	String get savedToast => 'Added to My favourites';

	/// en: 'Removed from My favourites'
	String get removedToast => 'Removed from My favourites';

	/// en: 'Per night'
	String get pricePerNight => 'Per night';

	/// en: 'Free'
	String get priceFree => 'Free';

	/// en: 'Unknown'
	String get priceUnknown => 'Unknown';

	/// en: 'Services'
	String get priceServices => 'Services';

	/// en: 'Max. height'
	String get maxHeight => 'Max. height';

	/// en: 'Pitches'
	String get capacity => 'Pitches';

	/// en: 'Rating'
	String get classification => 'Rating';

	/// en: '(one) {$n star} (other) {$n stars}'
	String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} star',
		other: '${n} stars',
	);

	/// en: 'Opening hours'
	String get hours => 'Opening hours';

	/// en: 'Services'
	String get services => 'Services';

	/// en: 'No services listed.'
	String get noServices => 'No services listed.';

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

	/// en: 'Copy'
	String get copyShort => 'Copy';

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

	/// en: 'This place is no longer in the data'
	String get gone => 'This place is no longer in the data';

	/// en: 'It was removed or merged with another since the last update.'
	String get goneHint => 'It was removed or merged with another since the last update.';

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

	/// en: '(one) {$n review} (other) {$n reviews}'
	String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} review',
		other: '${n} reviews',
	);

	/// en: 'No reviews yet.'
	String get noReviews => 'No reviews yet.';

	/// en: 'More reviews'
	String get moreReviews => 'More reviews';

	/// en: 'More reviews could not load. Tap to try again.'
	String get moreReviewsFailed => 'More reviews could not load. Tap to try again.';

	/// en: '$rating out of 5'
	String stars({required Object rating}) => '${rating} out of 5';

	/// en: 'Deleted account'
	String get deletedAccount => 'Deleted account';

	late final Translations$place$reviewVehicle$en reviewVehicle = Translations$place$reviewVehicle$en.internal(_root);

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

	/// en: '(one) {Open, closes in $n minute} (other) {Open, closes in $n minutes}'
	String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Open, closes in ${n} minute',
		other: 'Open, closes in ${n} minutes',
	);

	/// en: 'Closed, opens at $time'
	String closedUntil({required Object time}) => 'Closed, opens at ${time}';

	/// en: 'Closed, opens $day at $time'
	String closedUntilDay({required Object day, required Object time}) => 'Closed, opens ${day} at ${time}';

	/// en: '(one) {Closed, opens in $n minute} (other) {Closed, opens in $n minutes}'
	String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Closed, opens in ${n} minute',
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

	/// en: 'Opening unknown: data to update'
	String get stale => 'Opening unknown: data to update';

	/// en: 'Local time of the place'
	String get localTime => 'Local time of the place';
}

// Path: directions
class Translations$directions$en {
	Translations$directions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Directions with'
	String get title => 'Directions with';

	/// en: 'Choose who guides you. Only Lunaway's guidance knows your vehicle's size.'
	String get hint => 'Choose who guides you. Only Lunaway\'s guidance knows your vehicle\'s size.';

	/// en: 'Always use this app'
	String get remember => 'Always use this app';

	/// en: 'You can change it in Profile'
	String get rememberHint => 'You can change it in Profile';

	/// en: 'Directions'
	String get settingTitle => 'Directions';

	/// en: 'Who guides you when you tap Directions'
	String get settingHint => 'Who guides you when you tap Directions';

	/// en: 'Ask each time'
	String get askEachTime => 'Ask each time';

	/// en: 'Apple Maps'
	String get appleMaps => 'Apple Maps';

	/// en: 'Google Maps'
	String get googleMaps => 'Google Maps';

	/// en: 'Waze'
	String get waze => 'Waze';

	/// en: 'OsmAnd'
	String get osmAnd => 'OsmAnd';

	/// en: 'Organic Maps'
	String get organicMaps => 'Organic Maps';

	/// en: 'Magic Earth'
	String get magicEarth => 'Magic Earth';

	/// en: 'OpenStreetMap (browser)'
	String get openStreetMap => 'OpenStreetMap (browser)';
}

// Path: navigation
class Translations$navigation$en {
	Translations$navigation$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$navigation$entry$en entry = Translations$navigation$entry$en.internal(_root);
	late final Translations$navigation$preview$en preview = Translations$navigation$preview$en.internal(_root);
	late final Translations$navigation$states$en states = Translations$navigation$states$en.internal(_root);
	late final Translations$navigation$warning$en warning = Translations$navigation$warning$en.internal(_root);
	late final Translations$navigation$guidance$en guidance = Translations$navigation$guidance$en.internal(_root);
	late final Translations$navigation$voice$en voice = Translations$navigation$voice$en.internal(_root);
	late final Translations$navigation$units$en units = Translations$navigation$units$en.internal(_root);
	late final Translations$navigation$settings$en settings = Translations$navigation$settings$en.internal(_root);
}

// Path: list
class Translations$list$en {
	Translations$list$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Places around'
	String get title => 'Places around';

	/// en: 'No places around here with these filters'
	String get empty => 'No places around here with these filters';

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

	/// en: 'Nothing saved here yet'
	String get empty => 'Nothing saved here yet';

	/// en: 'Tap Save on a place to keep it, even offline.'
	String get emptyHint => 'Tap Save on a place to keep it, even offline.';

	/// en: 'New list'
	String get newList => 'New list';

	/// en: 'List name'
	String get listName => 'List name';

	/// en: 'Rename the list'
	String get renameList => 'Rename the list';

	/// en: 'Delete the list'
	String get deleteList => 'Delete the list';

	/// en: 'Delete "$name"? The places stay on the map.'
	String deleteListConfirm({required Object name}) => 'Delete "${name}"? The places stay on the map.';

	/// en: 'List options'
	String get listActions => 'List options';

	/// en: 'Place options'
	String get placeActions => 'Place options';

	/// en: 'See on the map'
	String get openOnMap => 'See on the map';

	/// en: 'Remove from the list'
	String get remove => 'Remove from the list';

	/// en: 'Removed from the list'
	String get removed => 'Removed from the list';

	/// en: '(zero) {Empty} (one) {$n place} (other) {$n places}'
	String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		zero: 'Empty',
		one: '${n} place',
		other: '${n} places',
	);

	/// en: 'Your favourites could not be read.'
	String get error => 'Your favourites could not be read.';
}

// Path: vehicle
class Translations$vehicle$en {
	Translations$vehicle$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'My vehicle'
	String get title => 'My vehicle';

	/// en: 'Its size filters out the places it does not fit. It stays on this device.'
	String get why => 'Its size filters out the places it does not fit. It stays on this device.';

	/// en: 'To keep only the places it fits, give at least its height. It stays on this device.'
	String get whyHeight => 'To keep only the places it fits, give at least its height. It stays on this device.';

	/// en: 'Describe your vehicle to hide the places it does not fit.'
	String get none => 'Describe your vehicle to hide the places it does not fit.';

	/// en: 'Describe my vehicle'
	String get add => 'Describe my vehicle';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'Type'
	String get type => 'Type';

	late final Translations$vehicle$types$en types = Translations$vehicle$types$en.internal(_root);

	/// en: 'It tows'
	String get towingTitle => 'It tows';

	late final Translations$vehicle$towing$en towing = Translations$vehicle$towing$en.internal(_root);

	/// en: 'Dimensions'
	String get size => 'Dimensions';

	/// en: 'Typical values for the type chosen: correct them with your registration papers.'
	String get sizeHint => 'Typical values for the type chosen: correct them with your registration papers.';

	/// en: 'Height'
	String get height => 'Height';

	/// en: 'Width'
	String get width => 'Width';

	/// en: 'Total length, towing included'
	String get length => 'Total length, towing included';

	/// en: 'Gross vehicle weight'
	String get weight => 'Gross vehicle weight';

	/// en: 'H $value'
	String heightShort({required Object value}) => 'H ${value}';

	/// en: 'W $value'
	String widthShort({required Object value}) => 'W ${value}';

	/// en: 'L $value'
	String lengthShort({required Object value}) => 'L ${value}';

	/// en: 'A number, for example 2.90'
	String get notANumber => 'A number, for example 2.90';

	/// en: 'Between $min and $max $unit'
	String outOfRange({required Object min, required Object max, required Object unit}) => 'Between ${min} and ${max} ${unit}';

	/// en: 'Lunaway's guidance takes all these dimensions into account.'
	String get navigationLater => 'Lunaway\'s guidance takes all these dimensions into account.';

	/// en: 'Save'
	String get save => 'Save';

	/// en: 'Clear'
	String get clear => 'Clear';
}

// Path: profile
class Translations$profile$en {
	Translations$profile$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Profile'
	String get title => 'Profile';

	/// en: 'No account, no ads, no trackers: everything stays on this device.'
	String get noAccountNeeded => 'No account, no ads, no trackers: everything stays on this device.';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'Device'
	String get languageSystem => 'Device';

	/// en: 'Appearance'
	String get appearance => 'Appearance';

	/// en: 'Auto'
	String get themeAuto => 'Auto';

	/// en: 'Light'
	String get themeLight => 'Light';

	/// en: 'Dark'
	String get themeDark => 'Dark';

	/// en: 'Light by day, dark after sunset where you are.'
	String get themeAutoHint => 'Light by day, dark after sunset where you are.';

	/// en: 'Always light, day and night.'
	String get themeLightHint => 'Always light, day and night.';

	/// en: 'Always dark, easy on the eyes at night.'
	String get themeDarkHint => 'Always dark, easy on the eyes at night.';

	/// en: 'Offline data'
	String get offline => 'Offline data';

	/// en: '(one) {place on this device} (other) {places on this device}'
	String placesOnDevice({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'place on this device',
		other: 'places on this device',
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

	/// en: 'Lunaway is free software under the GNU AGPL 3.0 or later.'
	String get appLicence => 'Lunaway is free software under the GNU AGPL 3.0 or later.';

	/// en: 'Sources and credits'
	String get attributions => 'Sources and credits';

	/// en: 'Places and map data © OpenStreetMap contributors.'
	String get attributionOsm => 'Places and map data © OpenStreetMap contributors.';

	/// en: 'OpenStreetMap data under the Open Database License (ODbL).'
	String get attributionOdbl => 'OpenStreetMap data under the Open Database License (ODbL).';

	/// en: 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).'
	String get attributionAtout => 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).';

	/// en: 'Place communes: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), under the ODbL.'
	String get attributionCommunes => 'Place communes: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), under the ODbL.';

	/// en: 'Basemap served by Lunaway, styles derived from Protomaps (BSD-3-Clause), data © OpenStreetMap contributors.'
	String get attributionTiles => 'Basemap served by Lunaway, styles derived from Protomaps (BSD-3-Clause), data © OpenStreetMap contributors.';

	/// en: 'Fraunces and Atkinson Hyperlegible Next typefaces, SIL Open Font License 1.1.'
	String get attributionFonts => 'Fraunces and Atkinson Hyperlegible Next typefaces, SIL Open Font License 1.1.';

	/// en: 'Phosphor icons, MIT licence.'
	String get attributionIcons => 'Phosphor icons, MIT licence.';
}

// Path: units
class Translations$units$en {
	Translations$units$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$n KB'
	String kilobytes({required Object n}) => '${n} KB';

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

// Path: place.reviewVehicle
class Translations$place$reviewVehicle$en {
	Translations$place$reviewVehicle$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Van'
	String get van => 'Van';

	/// en: 'Campervan'
	String get campervan => 'Campervan';

	/// en: 'Motorhome'
	String get motorhome => 'Motorhome';

	/// en: 'Caravan'
	String get caravan => 'Caravan';

	/// en: 'Other vehicle'
	String get other => 'Other vehicle';
}

// Path: navigation.entry
class Translations$navigation$entry$en {
	Translations$navigation$entry$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Lunaway guidance'
	String get lunaway => 'Lunaway guidance';

	/// en: 'A route computed for your vehicle's size'
	String get lunawayHint => 'A route computed for your vehicle\'s size';

	/// en: 'Describe your vehicle first: the route avoids bridges too low and streets too narrow for it.'
	String get vehicleMissing => 'Describe your vehicle first: the route avoids bridges too low and streets too narrow for it.';

	/// en: 'Other apps'
	String get others => 'Other apps';
}

// Path: navigation.preview
class Translations$navigation$preview$en {
	Translations$navigation$preview$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'To $name'
	String titleTo({required Object name}) => 'To ${name}';

	/// en: 'To this point'
	String get titlePoint => 'To this point';

	/// en: 'Computing a route for your vehicle'
	String get computing => 'Computing a route for your vehicle';

	/// en: 'Start'
	String get start => 'Start';

	/// en: 'Turn-by-turn guidance starts from a phone.'
	String get phoneOnly => 'Turn-by-turn guidance starts from a phone.';

	/// en: 'Recommended'
	String get recommended => 'Recommended';

	/// en: 'Alternative $n'
	String alternative({required Object n}) => 'Alternative ${n}';

	/// en: 'Toll'
	String get toll => 'Toll';

	/// en: 'Ferry'
	String get ferry => 'Ferry';

	/// en: 'Motorway'
	String get motorway => 'Motorway';

	/// en: 'No limit close to your vehicle's size on this route.'
	String get noWarnings => 'No limit close to your vehicle\'s size on this route.';

	/// en: '(one) {1 limit to watch} (other) {$n limits to watch}'
	String warnings({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '1 limit to watch',
		other: '${n} limits to watch',
	);

	/// en: 'Your vehicle'
	String get vehicle => 'Your vehicle';

	/// en: '$vehicle, towing'
	String vehicleTowing({required Object vehicle}) => '${vehicle}, towing';

	/// en: 'Edit'
	String get editVehicle => 'Edit';

	/// en: 'Avoid'
	String get avoid => 'Avoid';

	/// en: 'Tolls'
	String get avoidTolls => 'Tolls';

	/// en: 'Motorways'
	String get avoidMotorways => 'Motorways';

	/// en: 'Ferries'
	String get avoidFerries => 'Ferries';

	/// en: 'Unpaved'
	String get avoidUnpaved => 'Unpaved';

	/// en: 'Turn by turn'
	String get roadbook => 'Turn by turn';

	/// en: 'Show the turns'
	String get roadbookShow => 'Show the turns';

	/// en: 'Hide the turns'
	String get roadbookHide => 'Hide the turns';

	/// en: 'Road data of $date'
	String dataOf({required Object date}) => 'Road data of ${date}';

	/// en: '© OpenStreetMap contributors'
	String get attributionOsm => '© OpenStreetMap contributors';

	/// en: 'IGN, BD TOPO, edition of $date'
	String attributionIgn({required Object date}) => 'IGN, BD TOPO, edition of ${date}';

	/// en: 'Lunaway computes the route with your vehicle's dimensions and open data (OpenStreetMap, IGN) that may be incomplete or wrong. Road signs and the highway code always come first. You alone are responsible for your driving.'
	String get disclaimer => 'Lunaway computes the route with your vehicle\'s dimensions and open data (OpenStreetMap, IGN) that may be incomplete or wrong. Road signs and the highway code always come first. You alone are responsible for your driving.';

	/// en: 'Open in another app'
	String get otherApps => 'Open in another app';

	/// en: 'Back'
	String get back => 'Back';
}

// Path: navigation.states
class Translations$navigation$states$en {
	Translations$navigation$states$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'What do you drive?'
	String get vehicleTitle => 'What do you drive?';

	/// en: 'The route avoids bridges too low, streets too narrow and roads closed to your size. Give its height, width, length and weight.'
	String get vehicleHint => 'The route avoids bridges too low, streets too narrow and roads closed to your size. Give its height, width, length and weight.';

	/// en: 'Missing: $list'
	String vehicleMissing({required Object list}) => 'Missing: ${list}';

	/// en: 'Out of the accepted range: $list'
	String vehicleOutOfBounds({required Object list}) => 'Out of the accepted range: ${list}';

	late final Translations$navigation$states$dimension$en dimension = Translations$navigation$states$dimension$en.internal(_root);

	/// en: 'Describe my vehicle'
	String get describeVehicle => 'Describe my vehicle';

	/// en: 'Where are you?'
	String get originTitle => 'Where are you?';

	/// en: 'Lunaway needs your position to compute the route.'
	String get originHint => 'Lunaway needs your position to compute the route.';

	/// en: 'Locate me'
	String get locate => 'Locate me';

	/// en: 'No connection'
	String get offlineTitle => 'No connection';

	/// en: 'Routes are computed on Lunaway's server. Try again once connected.'
	String get offlineHint => 'Routes are computed on Lunaway\'s server. Try again once connected.';

	/// en: 'Too many routes asked'
	String get rateLimitedTitle => 'Too many routes asked';

	/// en: 'Try again in $seconds s.'
	String rateLimitedHint({required Object seconds}) => 'Try again in ${seconds} s.';

	/// en: 'Routing is down'
	String get unavailableTitle => 'Routing is down';

	/// en: 'The route service is stopped for now. Try again later.'
	String get unavailableHint => 'The route service is stopped for now. Try again later.';

	/// en: 'No route here'
	String get refusedTitle => 'No route here';

	/// en: 'Routes cover France for now.'
	String get refusedHint => 'Routes cover France for now.';

	/// en: 'No safe route for your vehicle'
	String get noSafeTitle => 'No safe route for your vehicle';

	/// en: 'Every possible road meets a limit your vehicle exceeds:'
	String get noSafeHint => 'Every possible road meets a limit your vehicle exceeds:';

	/// en: 'What you can do'
	String get whatToDo => 'What you can do';

	/// en: 'Check the figures you gave: $height high, $weight.'
	String checkVehicle({required Object height, required Object weight}) => 'Check the figures you gave: ${height} high, ${weight}.';

	/// en: 'Pick a destination before the obstacle: long-press the map.'
	String get pickOtherPoint => 'Pick a destination before the obstacle: long-press the map.';

	/// en: 'No road leads there'
	String get noRouteTitle => 'No road leads there';

	/// en: 'The point may be on a private road, or on an island without a ferry.'
	String get noRouteHint => 'The point may be on a private road, or on an island without a ferry.';

	/// en: 'Unpaved roads are avoided: allow them if the destination is on a track.'
	String get allowUnpaved => 'Unpaved roads are avoided: allow them if the destination is on a track.';

	/// en: 'Too far from a road'
	String get offNetworkTitle => 'Too far from a road';

	/// en: 'Pick a destination on a road.'
	String get offNetworkHint => 'Pick a destination on a road.';
}

// Path: navigation.warning
class Translations$navigation$warning$en {
	Translations$navigation$warning$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$navigation$warning$lowClearance$en lowClearance = Translations$navigation$warning$lowClearance$en.internal(_root);

	/// en: 'Low clearance, height unknown'
	String get unknownClearance => 'Low clearance, height unknown';

	/// en: 'Narrow passage $limit'
	String narrow({required Object limit}) => 'Narrow passage ${limit}';

	/// en: 'Length limit $limit'
	String tooLong({required Object limit}) => 'Length limit ${limit}';

	/// en: 'Weight limit $limit'
	String tooHeavy({required Object limit}) => 'Weight limit ${limit}';

	/// en: 'Axle load limit $limit'
	String axleLoad({required Object limit}) => 'Axle load limit ${limit}';

	/// en: 'No motorhomes'
	String get motorhomeBan => 'No motorhomes';

	/// en: 'No trailers'
	String get trailerBan => 'No trailers';

	/// en: 'Goods vehicle weight limit $limit'
	String goodsVehicleWeight({required Object limit}) => 'Goods vehicle weight limit ${limit}';

	/// en: 'your vehicle: $value'
	String yours({required Object value}) => 'your vehicle: ${value}';

	/// en: '$distance from the start'
	String fromStart({required Object distance}) => '${distance} from the start';

	/// en: 'in $distance'
	String ahead({required Object distance}) => 'in ${distance}';

	/// en: 'sources disagree, the lower figure applies'
	String get disputed => 'sources disagree, the lower figure applies';

	/// en: 'for heavy goods vehicles, check the signs'
	String get goodsOnly => 'for heavy goods vehicles, check the signs';

	/// en: 'OpenStreetMap'
	String get osm => 'OpenStreetMap';

	/// en: 'IGN BD TOPO'
	String get ign => 'IGN BD TOPO';

	/// en: 'Lunaway report'
	String get community => 'Lunaway report';

	/// en: 'Traffic order (DiaLog)'
	String get dialog => 'Traffic order (DiaLog)';
}

// Path: navigation.guidance
class Translations$navigation$guidance$en {
	Translations$navigation$guidance$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Then'
	String get then => 'Then';

	/// en: 'Arrive $time'
	String arrival({required Object time}) => 'Arrive ${time}';

	/// en: 'Off the route'
	String get offRoute => 'Off the route';

	/// en: 'Finding a new route'
	String get rerouting => 'Finding a new route';

	/// en: 'New route'
	String get rerouted => 'New route';

	/// en: 'New route, $minutes min longer'
	String reroutedLonger({required Object minutes}) => 'New route, ${minutes} min longer';

	/// en: 'No network for a new route: head back to the route'
	String get rerouteOffline => 'No network for a new route: head back to the route';

	/// en: 'No new route found: head back to the route'
	String get rerouteFailed => 'No new route found: head back to the route';

	/// en: 'Road closed in $distance: finding another way'
	String closureAhead({required Object distance}) => 'Road closed in ${distance}: finding another way';

	/// en: 'Road closed in $distance: no other way'
	String noDetour({required Object distance}) => 'Road closed in ${distance}: no other way';

	/// en: 'Works in $distance'
	String eventAhead({required Object distance}) => 'Works in ${distance}';

	/// en: 'Road works: data of $time'
	String eventsAsOf({required Object time}) => 'Road works: data of ${time}';

	/// en: 'Turn the voice on'
	String get voiceOn => 'Turn the voice on';

	/// en: 'Turn the voice off'
	String get voiceOff => 'Turn the voice off';

	/// en: 'Whole route'
	String get overview => 'Whole route';

	/// en: 'Back to the vehicle'
	String get recenter => 'Back to the vehicle';

	/// en: 'End'
	String get end => 'End';

	/// en: 'End the guidance?'
	String get endTitle => 'End the guidance?';

	/// en: 'End'
	String get endConfirm => 'End';

	/// en: 'Keep going'
	String get endKeep => 'Keep going';

	/// en: 'You have arrived'
	String get arrivedTitle => 'You have arrived';

	/// en: 'Done'
	String get done => 'Done';

	/// en: 'Speed'
	String get speed => 'Speed';

	/// en: 'Limit'
	String get limit => 'Limit';

	/// en: 'No $language voice on this device: instructions on screen only.'
	String noVoice({required Object language}) => 'No ${language} voice on this device: instructions on screen only.';

	/// en: 'The $language voice is not downloaded yet.'
	String missingVoice({required Object language}) => 'The ${language} voice is not downloaded yet.';

	/// en: 'Install'
	String get installVoice => 'Install';

	/// en: 'Settings, Accessibility, Spoken Content, Voices'
	String get voiceSettingsIos => 'Settings, Accessibility, Spoken Content, Voices';

	/// en: 'Lunaway is guiding you'
	String get notificationTitle => 'Lunaway is guiding you';

	/// en: 'Guidance goes on with the screen off.'
	String get notificationText => 'Guidance goes on with the screen off.';

	/// en: 'Guidance'
	String get notificationChannel => 'Guidance';

	/// en: 'Guidance could not start on this device.'
	String get unavailable => 'Guidance could not start on this device.';

	/// en: 'Position unavailable: check that the device's location is on for Lunaway.'
	String get positionLost => 'Position unavailable: check that the device\'s location is on for Lunaway.';

	/// en: 'Before you set off'
	String get firstTitle => 'Before you set off';

	/// en: 'I understand'
	String get firstAccept => 'I understand';
}

// Path: navigation.voice
class Translations$navigation$voice$en {
	Translations$navigation$voice$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recalculating.'
	String get rerouting => 'Recalculating.';

	/// en: 'New route.'
	String get rerouted => 'New route.';

	/// en: '(one) {New route, one minute longer.} (other) {New route, $minutes minutes longer.}'
	String reroutedLonger({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(minutes,
		one: 'New route, one minute longer.',
		other: 'New route, ${minutes} minutes longer.',
	);

	/// en: 'Road closed in $distance. Finding another way.'
	String closureAhead({required Object distance}) => 'Road closed in ${distance}. Finding another way.';

	/// en: 'Road closed in $distance. There is no other way.'
	String noDetour({required Object distance}) => 'Road closed in ${distance}. There is no other way.';

	/// en: 'Caution, low clearance of $height in $distance.'
	String clearance({required Object height, required Object distance}) => 'Caution, low clearance of ${height} in ${distance}.';

	/// en: 'Caution, low clearance of unknown height in $distance.'
	String unknownClearance({required Object distance}) => 'Caution, low clearance of unknown height in ${distance}.';

	/// en: 'Caution, narrow passage of $width in $distance.'
	String narrow({required Object width, required Object distance}) => 'Caution, narrow passage of ${width} in ${distance}.';

	/// en: 'Caution, $what in $distance.'
	String limit({required Object what, required Object distance}) => 'Caution, ${what} in ${distance}.';

	/// en: 'You have arrived.'
	String get arrived => 'You have arrived.';

	/// en: '$n metres'
	String metres({required Object n}) => '${n} metres';

	/// en: '(one) {$n kilometre} (other) {$n kilometres}'
	String kilometres({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '${n} kilometre',
		other: '${n} kilometres',
	);

	/// en: '$n feet'
	String feet({required Object n}) => '${n} feet';

	/// en: '(one) {$n mile} (other) {$n miles}'
	String miles({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '${n} mile',
		other: '${n} miles',
	);

	/// en: '$metres.$cm metres'
	String size({required Object metres, required Object cm}) => '${metres}.${cm} metres';

	/// en: '$metres metres'
	String sizeWhole({required Object metres}) => '${metres} metres';
}

// Path: navigation.units
class Translations$navigation$units$en {
	Translations$navigation$units$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$n ft'
	String ft({required Object n}) => '${n} ft';

	/// en: '$n mi'
	String mi({required Object n}) => '${n} mi';

	/// en: 'km/h'
	String get kmh => 'km/h';

	/// en: 'mph'
	String get mph => 'mph';

	/// en: '$h h $m min'
	String hoursMinutes({required Object h, required Object m}) => '${h} h ${m} min';

	/// en: '$m min'
	String minutes({required Object m}) => '${m} min';
}

// Path: navigation.settings
class Translations$navigation$settings$en {
	Translations$navigation$settings$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Guidance'
	String get title => 'Guidance';

	/// en: 'Avoid by default'
	String get avoidTitle => 'Avoid by default';

	/// en: 'Spoken instructions'
	String get voice => 'Spoken instructions';

	/// en: 'With the phone's own voice'
	String get voiceHint => 'With the phone\'s own voice';

	/// en: 'Distances'
	String get units => 'Distances';

	/// en: 'Kilometres'
	String get metric => 'Kilometres';

	/// en: 'Miles'
	String get imperial => 'Miles';
}

// Path: vehicle.types
class Translations$vehicle$types$en {
	Translations$vehicle$types$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Van'
	String get van => 'Van';

	/// en: 'Campervan'
	String get campervan => 'Campervan';

	/// en: 'Low-profile'
	String get lowProfile => 'Low-profile';

	/// en: 'Over-cab'
	String get overcab => 'Over-cab';

	/// en: 'A-class'
	String get integrated => 'A-class';
}

// Path: vehicle.towing
class Translations$vehicle$towing$en {
	Translations$vehicle$towing$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Nothing'
	String get none => 'Nothing';

	/// en: 'A car'
	String get car => 'A car';

	/// en: 'A trailer'
	String get trailer => 'A trailer';
}

// Path: navigation.states.dimension
class Translations$navigation$states$dimension$en {
	Translations$navigation$states$dimension$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'height'
	String get height => 'height';

	/// en: 'width'
	String get width => 'width';

	/// en: 'length'
	String get length => 'length';

	/// en: 'weight'
	String get weight => 'weight';
}

// Path: navigation.warning.lowClearance
class Translations$navigation$warning$lowClearance$en {
	Translations$navigation$warning$lowClearance$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Low bridge $limit'
	String underpass({required Object limit}) => 'Low bridge ${limit}';

	/// en: 'Tunnel $limit'
	String tunnel({required Object limit}) => 'Tunnel ${limit}';

	/// en: 'Archway $limit'
	String buildingPassage({required Object limit}) => 'Archway ${limit}';

	/// en: 'Bridge $limit'
	String bridge({required Object limit}) => 'Bridge ${limit}';

	/// en: 'Height bar $limit'
	String barrier({required Object limit}) => 'Height bar ${limit}';

	/// en: 'Height limit $limit'
	String road({required Object limit}) => 'Height limit ${limit}';
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
			'common.ok' => 'Got it',
			'common.saveFailed' => 'The change could not be saved.',
			'kinds.motorhomeArea' => 'Motorhome area',
			'kinds.serviceArea' => 'Service area',
			'kinds.campsite' => 'Campsite',
			'kinds.parking' => 'Car park',
			'kinds.nature' => 'Spot in nature',
			'kinds.restArea' => 'Rest area',
			'kinds.picnicArea' => 'Picnic area',
			'kinds.farm' => 'Farm stay',
			'kinds.homestay' => 'Private host',
			'kinds.offRoad' => 'Off-road spot',
			'kinds.extraService' => 'Handy stop',
			'families.stopovers' => 'Areas and car parks',
			'families.stopoversHint' => 'Motorhome areas, car parks, rest areas',
			'families.campsites' => 'Campsites and hosts',
			'families.campsitesHint' => 'Campsites, farms, private hosts',
			'families.nature' => 'Nature',
			'families.natureHint' => 'Spots in nature, tracks',
			'families.services' => 'Services',
			'families.servicesHint' => 'Water and dump points, no night',
			'services.drinkingWater' => 'Drinking water',
			'services.greyWater' => 'Grey water dump',
			'services.blackWater' => 'Cassette dump',
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
			'services.mobileData' => 'Mobile signal',
			'services.winterCaravanning' => 'Open in winter',
			'activities.monuments' => 'Sights',
			'activities.windsurfKitesurf' => 'Windsurfing, kitesurfing',
			'activities.mountainBiking' => 'Mountain biking',
			'activities.hiking' => 'Hiking',
			'activities.climbing' => 'Climbing',
			'activities.canoeKayak' => 'Canoe, kayak',
			'activities.fishing' => 'Fishing',
			'activities.shoreFishing' => 'Shore fishing',
			'activities.swimming' => 'Swimming',
			'activities.motorcycling' => 'Motorcycle rides',
			'activities.viewpoint' => 'Viewpoint',
			'activities.playground' => 'Playground',
			'amenities.water' => 'Water',
			'amenities.dumpStation' => 'Dump point',
			'amenities.electricity' => 'Electricity',
			'amenities.toilets' => 'Toilets',
			'amenities.showers' => 'Showers',
			'amenities.wasteBin' => 'Bins',
			'amenities.laundry' => 'Laundry',
			'amenities.wifi' => 'Wi-Fi',
			'amenities.lpg' => 'LPG',
			'overnight.allowed' => 'Overnight allowed',
			'overnight.tolerated' => 'Overnight tolerated',
			'overnight.dayOnly' => 'Daytime only',
			'overnight.forbidden' => 'No overnight',
			'overnight.unknown' => 'Overnight not reported',
			'overnight.allowedHint' => 'You may spend the night here.',
			'overnight.toleratedHint' => 'A night is usually accepted. Stay discreet and leave no trace.',
			'overnight.dayOnlyHint' => 'Daytime parking only. Look for another place for the night.',
			'overnight.forbiddenHint' => 'Spending the night here is forbidden.',
			'overnight.unknownHint' => 'Nobody has said yet. Ask on site.',
			'freshness.confirmed' => ({required Object when}) => 'Confirmed ${when}',
			'freshness.updated' => ({required Object when}) => 'Updated ${when}',
			'freshness.stale' => 'Not confirmed for over a year',
			'freshness.today' => 'today',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'yesterday', other: '${n} days ago', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'a month ago', other: '${n} months ago', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'a year ago', other: '${n} years ago', ), 
			'map.searchHint' => 'A place, a town',
			'map.clearSearch' => 'Clear the search',
			'map.locateMe' => 'Show my position',
			'map.zoomIn' => 'Zoom in',
			'map.zoomOut' => 'Zoom out',
			'map.filters' => 'Filters',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Map credits: © OpenStreetMap contributors, Protomaps style. Opens the OpenStreetMap copyright page.',
			'map.showList' => 'List',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'List (${n})', other: 'List (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'place here', other: 'places here', ), 
			'map.nearestPlacesLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'nearest place', other: 'nearest places', ), 
			'map.pointTitle' => 'Chosen point',
			'map.pointHint' => 'Its coordinates and the way there',
			'map.downloading' => 'Downloading the places of France',
			'map.downloadingCount' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${count} place received', other: '${count} places received', ), 
			'map.noData' => 'No places on this device yet',
			'map.noDataHint' => 'Download the places once: the map then works without a network.',
			'map.download' => 'Download the places',
			'map.downloadFailed' => 'The download stopped',
			'map.demoBanner' => 'Demo: invented places',
			'map.unsupported' => 'The map is not available on this system. Use the web app.',
			'sync.failedOffline' => 'No connection for now.',
			'sync.failedBusy' => 'The server is very busy.',
			'sync.failedServer' => 'The server has a problem for now.',
			'sync.failedOther' => 'The update did not go through.',
			'sync.failedRefused' => 'The server refused the update. A newer version of the app may be needed.',
			'sync.willRetry' => 'Lunaway will try again by itself.',
			'sync.incomplete' => ({required Object count}) => 'Download incomplete: ${count} places so far',
			'sync.incompleteShort' => 'Download incomplete',
			'sync.resuming' => ({required Object count}) => 'Downloading: ${count} places',
			'sync.resume' => 'Resume',
			'location.rationaleTitle' => 'Show your position?',
			'location.rationale' => 'Lunaway uses it to centre the map on you and sort places by distance. Your position stays on the device.',
			'location.allow' => 'Continue',
			'location.notNow' => 'Not now',
			'location.deniedTitle' => 'Position turned off for Lunaway',
			'location.denied' => 'You refused access to your position. To use it, allow it in the device settings.',
			'location.openSettings' => 'Open settings',
			'location.serviceOffTitle' => 'Location is off',
			'location.serviceOff' => 'Location is turned off on this device. Turn it on in the quick settings, then try again.',
			'location.notAllowed' => 'Position not allowed. The map works without it.',
			'location.noFix' => 'Your position is not coming through. Try in the open, or in a moment.',
			'location.unsupported' => 'This device does not give its position.',
			'search.towns' => 'Towns',
			'search.places' => 'Places',
			'search.noResult' => ({required Object query}) => 'No place or town matches "${query}".',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} place', other: '${n} places', ), 
			'filters.title' => 'Filters',
			'filters.families' => 'Kind of place',
			'filters.familiesHint' => 'None chosen: every kind',
			'filters.night' => 'The night',
			'filters.nightHint' => 'None chosen: every place',
			'filters.nightPossible' => 'Night possible',
			'filters.amenities' => 'Services',
			'filters.amenitiesHint' => 'The place must have all of them',
			'filters.vehicle' => 'My vehicle',
			'filters.myVehicleFits' => 'My vehicle fits',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Fits ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Hides places limited below ${height}. Unknown heights stay.',
			'filters.myVehicleUnknown' => 'Give your vehicle\'s height to use it.',
			'filters.reset' => 'Clear all',
			'filters.apply' => 'Apply',
			'filters.show' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, zero: 'No place matches', one: 'Show ${count} place', other: 'Show ${count} places', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} filter on', other: '${n} filters on', ), 
			'place.unnamedIn' => ({required Object kind, required Object town}) => '${kind} in ${town}',
			'place.away' => ({required Object distance}) => '${distance} away',
			'place.directions' => 'Directions',
			'place.share' => 'Share',
			'place.save' => 'Save',
			'place.saved' => 'Saved',
			'place.saveHint' => 'In My favourites. Long press to choose lists.',
			'place.saveTo' => 'Save to a list',
			'place.chooseLists' => 'Lists',
			'place.savedToast' => 'Added to My favourites',
			'place.removedToast' => 'Removed from My favourites',
			'place.pricePerNight' => 'Per night',
			'place.priceFree' => 'Free',
			'place.priceUnknown' => 'Unknown',
			'place.priceServices' => 'Services',
			'place.maxHeight' => 'Max. height',
			'place.capacity' => 'Pitches',
			'place.classification' => 'Rating',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} star', other: '${n} stars', ), 
			'place.hours' => 'Opening hours',
			'place.services' => 'Services',
			'place.noServices' => 'No services listed.',
			'place.activities' => 'Nearby',
			'place.description' => 'Description',
			'place.contact' => 'Contact',
			'place.website' => 'Website',
			'place.call' => 'Call',
			'place.coordinates' => 'Coordinates',
			'place.copy' => 'Copy the coordinates',
			'place.copyShort' => 'Copy',
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
			'place.gone' => 'This place is no longer in the data',
			'place.goneHint' => 'It was removed or merged with another since the last update.',
			'place.loadError' => 'This place could not be read.',
			'place.openFailed' => 'No app could open this link.',
			'place.photos' => 'Photos',
			'place.extrasOffline' => 'Photos and reviews need a connection.',
			'place.reviewsTitle' => 'Reviews',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} review', other: '${n} reviews', ), 
			'place.noReviews' => 'No reviews yet.',
			'place.moreReviews' => 'More reviews',
			'place.moreReviewsFailed' => 'More reviews could not load. Tap to try again.',
			'place.stars' => ({required Object rating}) => '${rating} out of 5',
			'place.deletedAccount' => 'Deleted account',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Campervan',
			'place.reviewVehicle.motorhome' => 'Motorhome',
			'place.reviewVehicle.caravan' => 'Caravan',
			'place.reviewVehicle.other' => 'Other vehicle',
			'place.originalLanguage' => ({required Object language}) => 'Original text in ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Photo ${index} of ${count}',
			'place.links' => 'Elsewhere',
			'hours.open' => 'Open now',
			'hours.openUntil' => ({required Object time}) => 'Open, closes at ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Open, closes ${day} at ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Open, closes in ${n} minute', other: 'Open, closes in ${n} minutes', ), 
			'hours.closedUntil' => ({required Object time}) => 'Closed, opens at ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Closed, opens ${day} at ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Closed, opens in ${n} minute', other: 'Closed, opens in ${n} minutes', ), 
			'hours.closedWindow' => 'Closed for the next two weeks',
			'hours.tomorrow' => 'tomorrow',
			'hours.onDate' => ({required Object date}) => 'on ${date}',
			'hours.midnight' => 'midnight',
			'hours.stale' => 'Opening unknown: data to update',
			'hours.localTime' => 'Local time of the place',
			'directions.title' => 'Directions with',
			'directions.hint' => 'Choose who guides you. Only Lunaway\'s guidance knows your vehicle\'s size.',
			'directions.remember' => 'Always use this app',
			'directions.rememberHint' => 'You can change it in Profile',
			'directions.settingTitle' => 'Directions',
			'directions.settingHint' => 'Who guides you when you tap Directions',
			'directions.askEachTime' => 'Ask each time',
			'directions.appleMaps' => 'Apple Maps',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (browser)',
			'navigation.entry.lunaway' => 'Lunaway guidance',
			'navigation.entry.lunawayHint' => 'A route computed for your vehicle\'s size',
			'navigation.entry.vehicleMissing' => 'Describe your vehicle first: the route avoids bridges too low and streets too narrow for it.',
			'navigation.entry.others' => 'Other apps',
			'navigation.preview.titleTo' => ({required Object name}) => 'To ${name}',
			'navigation.preview.titlePoint' => 'To this point',
			'navigation.preview.computing' => 'Computing a route for your vehicle',
			'navigation.preview.start' => 'Start',
			'navigation.preview.phoneOnly' => 'Turn-by-turn guidance starts from a phone.',
			'navigation.preview.recommended' => 'Recommended',
			'navigation.preview.alternative' => ({required Object n}) => 'Alternative ${n}',
			'navigation.preview.toll' => 'Toll',
			'navigation.preview.ferry' => 'Ferry',
			'navigation.preview.motorway' => 'Motorway',
			'navigation.preview.noWarnings' => 'No limit close to your vehicle\'s size on this route.',
			'navigation.preview.warnings' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '1 limit to watch', other: '${n} limits to watch', ), 
			'navigation.preview.vehicle' => 'Your vehicle',
			'navigation.preview.vehicleTowing' => ({required Object vehicle}) => '${vehicle}, towing',
			'navigation.preview.editVehicle' => 'Edit',
			'navigation.preview.avoid' => 'Avoid',
			'navigation.preview.avoidTolls' => 'Tolls',
			'navigation.preview.avoidMotorways' => 'Motorways',
			'navigation.preview.avoidFerries' => 'Ferries',
			'navigation.preview.avoidUnpaved' => 'Unpaved',
			'navigation.preview.roadbook' => 'Turn by turn',
			'navigation.preview.roadbookShow' => 'Show the turns',
			'navigation.preview.roadbookHide' => 'Hide the turns',
			'navigation.preview.dataOf' => ({required Object date}) => 'Road data of ${date}',
			'navigation.preview.attributionOsm' => '© OpenStreetMap contributors',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, edition of ${date}',
			'navigation.preview.disclaimer' => 'Lunaway computes the route with your vehicle\'s dimensions and open data (OpenStreetMap, IGN) that may be incomplete or wrong. Road signs and the highway code always come first. You alone are responsible for your driving.',
			'navigation.preview.otherApps' => 'Open in another app',
			'navigation.preview.back' => 'Back',
			'navigation.states.vehicleTitle' => 'What do you drive?',
			'navigation.states.vehicleHint' => 'The route avoids bridges too low, streets too narrow and roads closed to your size. Give its height, width, length and weight.',
			'navigation.states.vehicleMissing' => ({required Object list}) => 'Missing: ${list}',
			'navigation.states.vehicleOutOfBounds' => ({required Object list}) => 'Out of the accepted range: ${list}',
			'navigation.states.dimension.height' => 'height',
			'navigation.states.dimension.width' => 'width',
			'navigation.states.dimension.length' => 'length',
			'navigation.states.dimension.weight' => 'weight',
			'navigation.states.describeVehicle' => 'Describe my vehicle',
			'navigation.states.originTitle' => 'Where are you?',
			'navigation.states.originHint' => 'Lunaway needs your position to compute the route.',
			'navigation.states.locate' => 'Locate me',
			'navigation.states.offlineTitle' => 'No connection',
			'navigation.states.offlineHint' => 'Routes are computed on Lunaway\'s server. Try again once connected.',
			'navigation.states.rateLimitedTitle' => 'Too many routes asked',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Try again in ${seconds} s.',
			'navigation.states.unavailableTitle' => 'Routing is down',
			'navigation.states.unavailableHint' => 'The route service is stopped for now. Try again later.',
			'navigation.states.refusedTitle' => 'No route here',
			'navigation.states.refusedHint' => 'Routes cover France for now.',
			'navigation.states.noSafeTitle' => 'No safe route for your vehicle',
			'navigation.states.noSafeHint' => 'Every possible road meets a limit your vehicle exceeds:',
			'navigation.states.whatToDo' => 'What you can do',
			'navigation.states.checkVehicle' => ({required Object height, required Object weight}) => 'Check the figures you gave: ${height} high, ${weight}.',
			'navigation.states.pickOtherPoint' => 'Pick a destination before the obstacle: long-press the map.',
			'navigation.states.noRouteTitle' => 'No road leads there',
			'navigation.states.noRouteHint' => 'The point may be on a private road, or on an island without a ferry.',
			'navigation.states.allowUnpaved' => 'Unpaved roads are avoided: allow them if the destination is on a track.',
			'navigation.states.offNetworkTitle' => 'Too far from a road',
			'navigation.states.offNetworkHint' => 'Pick a destination on a road.',
			'navigation.warning.lowClearance.underpass' => ({required Object limit}) => 'Low bridge ${limit}',
			'navigation.warning.lowClearance.tunnel' => ({required Object limit}) => 'Tunnel ${limit}',
			'navigation.warning.lowClearance.buildingPassage' => ({required Object limit}) => 'Archway ${limit}',
			'navigation.warning.lowClearance.bridge' => ({required Object limit}) => 'Bridge ${limit}',
			'navigation.warning.lowClearance.barrier' => ({required Object limit}) => 'Height bar ${limit}',
			'navigation.warning.lowClearance.road' => ({required Object limit}) => 'Height limit ${limit}',
			'navigation.warning.unknownClearance' => 'Low clearance, height unknown',
			'navigation.warning.narrow' => ({required Object limit}) => 'Narrow passage ${limit}',
			'navigation.warning.tooLong' => ({required Object limit}) => 'Length limit ${limit}',
			'navigation.warning.tooHeavy' => ({required Object limit}) => 'Weight limit ${limit}',
			'navigation.warning.axleLoad' => ({required Object limit}) => 'Axle load limit ${limit}',
			'navigation.warning.motorhomeBan' => 'No motorhomes',
			'navigation.warning.trailerBan' => 'No trailers',
			'navigation.warning.goodsVehicleWeight' => ({required Object limit}) => 'Goods vehicle weight limit ${limit}',
			'navigation.warning.yours' => ({required Object value}) => 'your vehicle: ${value}',
			'navigation.warning.fromStart' => ({required Object distance}) => '${distance} from the start',
			'navigation.warning.ahead' => ({required Object distance}) => 'in ${distance}',
			'navigation.warning.disputed' => 'sources disagree, the lower figure applies',
			'navigation.warning.goodsOnly' => 'for heavy goods vehicles, check the signs',
			'navigation.warning.osm' => 'OpenStreetMap',
			'navigation.warning.ign' => 'IGN BD TOPO',
			'navigation.warning.community' => 'Lunaway report',
			'navigation.warning.dialog' => 'Traffic order (DiaLog)',
			'navigation.guidance.then' => 'Then',
			'navigation.guidance.arrival' => ({required Object time}) => 'Arrive ${time}',
			'navigation.guidance.offRoute' => 'Off the route',
			'navigation.guidance.rerouting' => 'Finding a new route',
			'navigation.guidance.rerouted' => 'New route',
			'navigation.guidance.reroutedLonger' => ({required Object minutes}) => 'New route, ${minutes} min longer',
			'navigation.guidance.rerouteOffline' => 'No network for a new route: head back to the route',
			'navigation.guidance.rerouteFailed' => 'No new route found: head back to the route',
			'navigation.guidance.closureAhead' => ({required Object distance}) => 'Road closed in ${distance}: finding another way',
			'navigation.guidance.noDetour' => ({required Object distance}) => 'Road closed in ${distance}: no other way',
			'navigation.guidance.eventAhead' => ({required Object distance}) => 'Works in ${distance}',
			'navigation.guidance.eventsAsOf' => ({required Object time}) => 'Road works: data of ${time}',
			'navigation.guidance.voiceOn' => 'Turn the voice on',
			'navigation.guidance.voiceOff' => 'Turn the voice off',
			'navigation.guidance.overview' => 'Whole route',
			'navigation.guidance.recenter' => 'Back to the vehicle',
			'navigation.guidance.end' => 'End',
			'navigation.guidance.endTitle' => 'End the guidance?',
			'navigation.guidance.endConfirm' => 'End',
			'navigation.guidance.endKeep' => 'Keep going',
			'navigation.guidance.arrivedTitle' => 'You have arrived',
			'navigation.guidance.done' => 'Done',
			'navigation.guidance.speed' => 'Speed',
			'navigation.guidance.limit' => 'Limit',
			'navigation.guidance.noVoice' => ({required Object language}) => 'No ${language} voice on this device: instructions on screen only.',
			'navigation.guidance.missingVoice' => ({required Object language}) => 'The ${language} voice is not downloaded yet.',
			'navigation.guidance.installVoice' => 'Install',
			'navigation.guidance.voiceSettingsIos' => 'Settings, Accessibility, Spoken Content, Voices',
			'navigation.guidance.notificationTitle' => 'Lunaway is guiding you',
			'navigation.guidance.notificationText' => 'Guidance goes on with the screen off.',
			'navigation.guidance.notificationChannel' => 'Guidance',
			'navigation.guidance.unavailable' => 'Guidance could not start on this device.',
			'navigation.guidance.positionLost' => 'Position unavailable: check that the device\'s location is on for Lunaway.',
			'navigation.guidance.firstTitle' => 'Before you set off',
			'navigation.guidance.firstAccept' => 'I understand',
			'navigation.voice.rerouting' => 'Recalculating.',
			'navigation.voice.rerouted' => 'New route.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(minutes, one: 'New route, one minute longer.', other: 'New route, ${minutes} minutes longer.', ), 
			'navigation.voice.closureAhead' => ({required Object distance}) => 'Road closed in ${distance}. Finding another way.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'Road closed in ${distance}. There is no other way.',
			'navigation.voice.clearance' => ({required Object height, required Object distance}) => 'Caution, low clearance of ${height} in ${distance}.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Caution, low clearance of unknown height in ${distance}.',
			'navigation.voice.narrow' => ({required Object width, required Object distance}) => 'Caution, narrow passage of ${width} in ${distance}.',
			'navigation.voice.limit' => ({required Object what, required Object distance}) => 'Caution, ${what} in ${distance}.',
			'navigation.voice.arrived' => 'You have arrived.',
			'navigation.voice.metres' => ({required Object n}) => '${n} metres',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '${n} kilometre', other: '${n} kilometres', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} feet',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '${n} mile', other: '${n} miles', ), 
			'navigation.voice.size' => ({required Object metres, required Object cm}) => '${metres}.${cm} metres',
			'navigation.voice.sizeWhole' => ({required Object metres}) => '${metres} metres',
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} h ${m} min',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Guidance',
			'navigation.settings.avoidTitle' => 'Avoid by default',
			'navigation.settings.voice' => 'Spoken instructions',
			'navigation.settings.voiceHint' => 'With the phone\'s own voice',
			'navigation.settings.units' => 'Distances',
			'navigation.settings.metric' => 'Kilometres',
			'navigation.settings.imperial' => 'Miles',
			'list.title' => 'Places around',
			'list.empty' => 'No places around here with these filters',
			'list.emptyHint' => 'Move the map, zoom out or loosen the filters.',
			'list.error' => 'The list could not be read.',
			'favorites.title' => 'Favourites',
			'favorites.defaultList' => 'My favourites',
			'favorites.empty' => 'Nothing saved here yet',
			'favorites.emptyHint' => 'Tap Save on a place to keep it, even offline.',
			'favorites.newList' => 'New list',
			'favorites.listName' => 'List name',
			'favorites.renameList' => 'Rename the list',
			'favorites.deleteList' => 'Delete the list',
			'favorites.deleteListConfirm' => ({required Object name}) => 'Delete "${name}"? The places stay on the map.',
			'favorites.listActions' => 'List options',
			'favorites.placeActions' => 'Place options',
			'favorites.openOnMap' => 'See on the map',
			'favorites.remove' => 'Remove from the list',
			'favorites.removed' => 'Removed from the list',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, zero: 'Empty', one: '${n} place', other: '${n} places', ), 
			'favorites.error' => 'Your favourites could not be read.',
			'vehicle.title' => 'My vehicle',
			'vehicle.why' => 'Its size filters out the places it does not fit. It stays on this device.',
			'vehicle.whyHeight' => 'To keep only the places it fits, give at least its height. It stays on this device.',
			'vehicle.none' => 'Describe your vehicle to hide the places it does not fit.',
			'vehicle.add' => 'Describe my vehicle',
			'vehicle.edit' => 'Edit',
			'vehicle.type' => 'Type',
			'vehicle.types.van' => 'Van',
			'vehicle.types.campervan' => 'Campervan',
			'vehicle.types.lowProfile' => 'Low-profile',
			'vehicle.types.overcab' => 'Over-cab',
			'vehicle.types.integrated' => 'A-class',
			'vehicle.towingTitle' => 'It tows',
			'vehicle.towing.none' => 'Nothing',
			'vehicle.towing.car' => 'A car',
			'vehicle.towing.trailer' => 'A trailer',
			'vehicle.size' => 'Dimensions',
			'vehicle.sizeHint' => 'Typical values for the type chosen: correct them with your registration papers.',
			'vehicle.height' => 'Height',
			'vehicle.width' => 'Width',
			'vehicle.length' => 'Total length, towing included',
			'vehicle.weight' => 'Gross vehicle weight',
			'vehicle.heightShort' => ({required Object value}) => 'H ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'W ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'L ${value}',
			'vehicle.notANumber' => 'A number, for example 2.90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Between ${min} and ${max} ${unit}',
			'vehicle.navigationLater' => 'Lunaway\'s guidance takes all these dimensions into account.',
			'vehicle.save' => 'Save',
			'vehicle.clear' => 'Clear',
			'profile.title' => 'Profile',
			'profile.noAccountNeeded' => 'No account, no ads, no trackers: everything stays on this device.',
			'profile.language' => 'Language',
			'profile.languageSystem' => 'Device',
			'profile.appearance' => 'Appearance',
			'profile.themeAuto' => 'Auto',
			'profile.themeLight' => 'Light',
			'profile.themeDark' => 'Dark',
			'profile.themeAutoHint' => 'Light by day, dark after sunset where you are.',
			'profile.themeLightHint' => 'Always light, day and night.',
			'profile.themeDarkHint' => 'Always dark, easy on the eyes at night.',
			'profile.offline' => 'Offline data',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'place on this device', other: 'places on this device', ), 
			'profile.offlineSize' => ({required Object size}) => 'Storage used: ${size}',
			'profile.lastSync' => ({required Object when}) => 'Last update ${when}',
			'profile.neverSynced' => 'Never downloaded',
			'profile.syncNow' => 'Update now',
			'profile.syncing' => 'Updating',
			'profile.about' => 'About',
			'profile.version' => ({required Object version}) => 'Version ${version}',
			'profile.website' => 'Website',
			'profile.privacy' => 'Privacy policy',
			'profile.sourceCode' => 'Source code',
			'profile.licences' => 'Licences',
			'profile.appLicence' => 'Lunaway is free software under the GNU AGPL 3.0 or later.',
			'profile.attributions' => 'Sources and credits',
			'profile.attributionOsm' => 'Places and map data © OpenStreetMap contributors.',
			'profile.attributionOdbl' => 'OpenStreetMap data under the Open Database License (ODbL).',
			'profile.attributionAtout' => 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Place communes: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), under the ODbL.',
			'profile.attributionTiles' => 'Basemap served by Lunaway, styles derived from Protomaps (BSD-3-Clause), data © OpenStreetMap contributors.',
			'profile.attributionFonts' => 'Fraunces and Atkinson Hyperlegible Next typefaces, SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Phosphor icons, MIT licence.',
			'units.kilobytes' => ({required Object n}) => '${n} KB',
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

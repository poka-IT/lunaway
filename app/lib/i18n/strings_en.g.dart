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
	late final Translations$list$en list = Translations$list$en.internal(_root);
	late final Translations$favorites$en favorites = Translations$favorites$en.internal(_root);
	late final Translations$vehicle$en vehicle = Translations$vehicle$en.internal(_root);
	late final Translations$profile$en profile = Translations$profile$en.internal(_root);
	late final Translations$units$en units = Translations$units$en.internal(_root);
	late final Translations$languages$en languages = Translations$languages$en.internal(_root);
	late final Translations$locale$en locale = Translations$locale$en.internal(_root);
	late final Translations$account$en account = Translations$account$en.internal(_root);
	late final Translations$recovery$en recovery = Translations$recovery$en.internal(_root);
	late final Translations$recover$en recover = Translations$recover$en.internal(_root);
	late final Translations$deletion$en deletion = Translations$deletion$en.internal(_root);
	late final Translations$devices$en devices = Translations$devices$en.internal(_root);
	late final Translations$muted$en muted = Translations$muted$en.internal(_root);
	late final Translations$mine$en mine = Translations$mine$en.internal(_root);
	late final Translations$outbox$en outbox = Translations$outbox$en.internal(_root);
	late final Translations$contribute$en contribute = Translations$contribute$en.internal(_root);
	late final Translations$confirmSheet$en confirmSheet = Translations$confirmSheet$en.internal(_root);
	late final Translations$issueSheet$en issueSheet = Translations$issueSheet$en.internal(_root);
	late final Translations$reportSheet$en reportSheet = Translations$reportSheet$en.internal(_root);
	late final Translations$reviewSheet$en reviewSheet = Translations$reviewSheet$en.internal(_root);
	late final Translations$gate$en gate = Translations$gate$en.internal(_root);
	late final Translations$photoFlow$en photoFlow = Translations$photoFlow$en.internal(_root);
	late final Translations$placeForm$en placeForm = Translations$placeForm$en.internal(_root);
	late final Translations$favoritesSync$en favoritesSync = Translations$favoritesSync$en.internal(_root);
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

	/// en: 'Send'
	String get send => 'Send';

	/// en: 'Later'
	String get later => 'Later';

	/// en: 'Continue'
	String get next => 'Continue';

	/// en: 'That did not go through. Try again in a moment.'
	String get failed => 'That did not go through. Try again in a moment.';

	/// en: 'No network right now. Try again once the connection is back.'
	String get offline => 'No network right now. Try again once the connection is back.';
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

	/// en: 'This place comes with the download of the places'
	String get arriving => 'This place comes with the download of the places';

	/// en: 'The places of France are downloading so the map works without a network. The page opens as soon as this one is here.'
	String get arrivingHint => 'The places of France are downloading so the map works without a network. The page opens as soon as this one is here.';

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

	/// en: 'No other reviews yet.'
	String get noOtherReviews => 'No other reviews yet.';

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

	/// en: 'Lunaway hands the trip to your navigation app.'
	String get hint => 'Lunaway hands the trip to your navigation app.';

	/// en: 'Always use this app'
	String get remember => 'Always use this app';

	/// en: 'You can change it in Profile'
	String get rememberHint => 'You can change it in Profile';

	/// en: 'No navigation app is installed.'
	String get noApp => 'No navigation app is installed.';

	/// en: 'Directions'
	String get settingTitle => 'Directions';

	/// en: 'The app your trips go to'
	String get settingHint => 'The app your trips go to';

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

	/// en: 'The built-in route planner, coming later, will take all these dimensions into account.'
	String get navigationLater => 'The built-in route planner, coming later, will take all these dimensions into account.';

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

	/// en: 'No ads, no tracker. Your account knows neither your e-mail nor your phone number.'
	String get noTracking => 'No ads, no tracker. Your account knows neither your e-mail nor your phone number.';
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

// Path: account
class Translations$account$en {
	Translations$account$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your account'
	String get title => 'Your account';

	/// en: 'No account yet'
	String get noneTitle => 'No account yet';

	/// en: 'The map, search and favourites work without an account. One is made for you at your first contribution (a rating, a confirmation, a photo), with no e-mail and no password. Your favourite lists then join it.'
	String get noneBody => 'The map, search and favourites work without an account. One is made for you at your first contribution (a rating, a confirmation, a photo), with no e-mail and no password. Your favourite lists then join it.';

	/// en: 'Recover my account'
	String get recover => 'Recover my account';

	/// en: 'Member since $date'
	String memberSince({required Object date}) => 'Member since ${date}';

	/// en: 'Change the pseudonym'
	String get editPseudonym => 'Change the pseudonym';

	/// en: 'Your pseudonym'
	String get pseudonymTitle => 'Your pseudonym';

	/// en: 'Public: it goes with your reviews and photos. 3 to 32 characters.'
	String get pseudonymHint => 'Public: it goes with your reviews and photos. 3 to 32 characters.';

	/// en: '3 to 32 characters, at least two of them letters.'
	String get pseudonymInvalid => '3 to 32 characters, at least two of them letters.';

	/// en: 'This pseudonym is not accepted: no link, no contact detail, no insult, no name that passes the account off as the team.'
	String get pseudonymRefused => 'This pseudonym is not accepted: no link, no contact detail, no insult, no name that passes the account off as the team.';

	/// en: 'Pseudonym saved'
	String get pseudonymSaved => 'Pseudonym saved';

	/// en: 'Trust level $level'
	String level({required Object level}) => 'Trust level ${level}';

	late final Translations$account$levelOpens$en levelOpens = Translations$account$levelOpens$en.internal(_root);

	/// en: 'For level $level'
	String nextLevel({required Object level}) => 'For level ${level}';

	/// en: 'You are at the highest level.'
	String get levelTop => 'You are at the highest level.';

	late final Translations$account$requirement$en requirement = Translations$account$requirement$en.internal(_root);

	/// en: 'Or instead: $requirement'
	String orInstead({required Object requirement}) => 'Or instead: ${requirement}';

	/// en: 'No recovery card yet. Without one, this account stays on this phone: lose the phone, and the account goes with it.'
	String get recoveryNone => 'No recovery card yet. Without one, this account stays on this phone: lose the phone, and the account goes with it.';

	/// en: 'Make my recovery card'
	String get recoveryCreate => 'Make my recovery card';

	/// en: 'Recovery card made on $date'
	String recoveryMade({required Object date}) => 'Recovery card made on ${date}';

	/// en: 'Make a new card'
	String get recoveryRemake => 'Make a new card';

	/// en: 'My contributions'
	String get contributions => 'My contributions';

	/// en: '(one) {$n contribution waiting to be sent} (other) {$n contributions waiting to be sent}'
	String pending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} contribution waiting to be sent',
		other: '${n} contributions waiting to be sent',
	);

	/// en: 'Hidden authors'
	String get mutedAuthors => 'Hidden authors';

	/// en: 'Devices'
	String get devices => 'Devices';

	/// en: 'Sign out'
	String get signOut => 'Sign out';

	/// en: 'Delete my account'
	String get delete => 'Delete my account';

	/// en: 'Sign out of this device?'
	String get signOutTitle => 'Sign out of this device?';

	/// en: 'The account's key leaves this device. To come back, you will need your recovery card. Your favourites stay here.'
	String get signOutBody => 'The account\'s key leaves this device. To come back, you will need your recovery card. Your favourites stay here.';

	/// en: 'You have not made a recovery card on this device. Without one, this account will be lost for good.'
	String get signOutNoCard => 'You have not made a recovery card on this device. Without one, this account will be lost for good.';

	/// en: '(one) {One contribution waiting to be sent will not be sent.} (other) {$n contributions waiting to be sent will not be sent.}'
	String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'One contribution waiting to be sent will not be sent.',
		other: '${n} contributions waiting to be sent will not be sent.',
	);

	/// en: 'Signed out. Your favourites stay on this device.'
	String get signedOut => 'Signed out. Your favourites stay on this device.';

	/// en: 'This account no longer opens on this device. Your recovery card brings it back.'
	String get lost => 'This account no longer opens on this device. Your recovery card brings it back.';

	/// en: 'Thank you for your first contribution'
	String get welcomeTitle => 'Thank you for your first contribution';

	/// en: 'It made your account, under the pseudonym “$name”. No e-mail and no password: a key kept on this device. You can change the pseudonym in your profile.'
	String welcomeBody({required Object name}) => 'It made your account, under the pseudonym “${name}”. No e-mail and no password: a key kept on this device. You can change the pseudonym in your profile.';

	/// en: 'Make your recovery card to find this account on another device.'
	String get welcomeCard => 'Make your recovery card to find this account on another device.';

	/// en: 'Your favourite lists are now kept with your account.'
	String get welcomeFavorites => 'Your favourite lists are now kept with your account.';
}

// Path: recovery
class Translations$recovery$en {
	Translations$recovery$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recovery card'
	String get title => 'Recovery card';

	/// en: 'A code that brings your account to a new device. Lunaway keeps only a fingerprint of it: nobody can give it back to you.'
	String get intro => 'A code that brings your account to a new device. Lunaway keeps only a fingerprint of it: nobody can give it back to you.';

	/// en: 'A new card replaces the previous one, which stops working.'
	String get replaces => 'A new card replaces the previous one, which stops working.';

	/// en: 'Make the card'
	String get make => 'Make the card';

	/// en: 'Your recovery code'
	String get codeLabel => 'Your recovery code';

	/// en: 'This code shows only once. Write it down, or save the image, before closing.'
	String get shownOnce => 'This code shows only once. Write it down, or save the image, before closing.';

	/// en: 'Save the image'
	String get saveImage => 'Save the image';

	/// en: 'I have it'
	String get done => 'I have it';

	/// en: 'Did you keep the code?'
	String get doneTitle => 'Did you keep the code?';

	/// en: 'Once this page is closed, it will not show again.'
	String get doneBody => 'Once this page is closed, it will not show again.';

	/// en: 'Stay on the page'
	String get keep => 'Stay on the page';

	/// en: 'Lunaway recovery card'
	String get cardHeading => 'Lunaway recovery card';

	/// en: 'Account: $name'
	String cardAccount({required Object name}) => 'Account: ${name}';

	/// en: 'To recover the account: Profile, Recover my account, then type or read this code.'
	String get cardHow => 'To recover the account: Profile, Recover my account, then type or read this code.';

	/// en: 'Made on $date'
	String cardMade({required Object date}) => 'Made on ${date}';

	/// en: 'This code opens the account: entrust it to nobody.'
	String get cardWarning => 'This code opens the account: entrust it to nobody.';

	/// en: 'The card could not be made. A connection is needed.'
	String get failed => 'The card could not be made. A connection is needed.';

	/// en: 'lunaway-recovery-card'
	String get fileName => 'lunaway-recovery-card';

	/// en: 'Make the card: the code shows only once.'
	String get step1 => 'Make the card: the code shows only once.';

	/// en: 'Save the image, print it, or copy the code by hand.'
	String get step2 => 'Save the image, print it, or copy the code by hand.';

	/// en: 'Keep it in the glovebox, with the vehicle's papers.'
	String get step3 => 'Keep it in the glovebox, with the vehicle\'s papers.';
}

// Path: recover
class Translations$recover$en {
	Translations$recover$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Recover my account'
	String get title => 'Recover my account';

	/// en: 'Type the code of your recovery card, or read it from a photo of the card.'
	String get intro => 'Type the code of your recovery card, or read it from a photo of the card.';

	/// en: 'Recovery code'
	String get field => 'Recovery code';

	/// en: '27 characters, in groups of four'
	String get fieldHint => '27 characters, in groups of four';

	/// en: '(one) {$n more character} (other) {$n more characters}'
	String remaining({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} more character',
		other: '${n} more characters',
	);

	/// en: 'This code matches no card: check each character.'
	String get invalid => 'This code matches no card: check each character.';

	/// en: 'Code complete'
	String get valid => 'Code complete';

	/// en: 'Read the card from a photo'
	String get scan => 'Read the card from a photo';

	/// en: 'Choose the card's image'
	String get scanFile => 'Choose the card\'s image';

	/// en: 'Reading the card'
	String get reading => 'Reading the card';

	/// en: 'No readable code in this picture. Try a sharper photo, with the card held flat.'
	String get scanFailed => 'No readable code in this picture. Try a sharper photo, with the card held flat.';

	/// en: 'My old device is lost or stolen: sign it out'
	String get revoke => 'My old device is lost or stolen: sign it out';

	/// en: 'Every other key of the account will be removed.'
	String get revokeHint => 'Every other key of the account will be removed.';

	/// en: 'Recover the account'
	String get submit => 'Recover the account';

	/// en: 'No account has this code. Check the card, or make a new one from a signed-in device.'
	String get notFound => 'No account has this code. Check the card, or make a new one from a signed-in device.';

	/// en: 'Too many attempts for now. Try again in an hour.'
	String get tooMany => 'Too many attempts for now. Try again in an hour.';

	/// en: 'Account recovered: $name'
	String done({required Object name}) => 'Account recovered: ${name}';
}

// Path: deletion
class Translations$deletion$en {
	Translations$deletion$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete my account'
	String get title => 'Delete my account';

	/// en: 'Deletion is immediate and final.'
	String get intro => 'Deletion is immediate and final.';

	/// en: 'What goes'
	String get goneTitle => 'What goes';

	late final Translations$deletion$gone$en gone = Translations$deletion$gone$en.internal(_root);

	/// en: 'What stays, without your name'
	String get keptTitle => 'What stays, without your name';

	/// en: 'Your published written reviews, your confirmations and your applied place edits stay, without author: they are part of other travellers' map.'
	String get kept => 'Your published written reviews, your confirmations and your applied place edits stay, without author: they are part of other travellers\' map.';

	/// en: 'The server's backups are cleared within 30 days.'
	String get backups => 'The server\'s backups are cleared within 30 days.';

	/// en: 'On this device, your favourites stay; the account's key is erased.'
	String get device => 'On this device, your favourites stay; the account\'s key is erased.';

	/// en: 'You can also delete it on lunaway.net with your recovery code.'
	String get web => 'You can also delete it on lunaway.net with your recovery code.';

	/// en: 'lunaway.net/account/delete'
	String get webLink => 'lunaway.net/account/delete';

	/// en: 'Delete for good?'
	String get confirmTitle => 'Delete for good?';

	/// en: 'The account “$name” and everything listed go now. Nobody can bring it back.'
	String confirmBody({required Object name}) => 'The account “${name}” and everything listed go now. Nobody can bring it back.';

	/// en: 'I understand this is final'
	String get confirmCheck => 'I understand this is final';

	/// en: 'Delete the account'
	String get confirm => 'Delete the account';

	/// en: 'Account deleted'
	String get done => 'Account deleted';

	/// en: 'The account could not be deleted. A connection is needed.'
	String get failed => 'The account could not be deleted. A connection is needed.';
}

// Path: devices
class Translations$devices$en {
	Translations$devices$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Devices'
	String get title => 'Devices';

	/// en: 'Each device has its own key. Remove a lost device, or one you no longer use.'
	String get intro => 'Each device has its own key. Remove a lost device, or one you no longer use.';

	/// en: 'This device'
	String get thisDevice => 'This device';

	/// en: 'Other device'
	String get other => 'Other device';

	/// en: 'Added on $date'
	String added({required Object date}) => 'Added on ${date}';

	/// en: 'Last used $when'
	String lastUsed({required Object when}) => 'Last used ${when}';

	/// en: 'Remove'
	String get revoke => 'Remove';

	/// en: 'Remove this device?'
	String get revokeTitle => 'Remove this device?';

	/// en: 'It will be signed out and can no longer use the account.'
	String get revokeBody => 'It will be signed out and can no longer use the account.';

	/// en: 'Device removed'
	String get revoked => 'Device removed';

	/// en: 'Sign out every other device'
	String get signOutOthers => 'Sign out every other device';

	/// en: '(zero) {No other session open} (one) {$n session closed} (other) {$n sessions closed}'
	String signedOutOthers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		zero: 'No other session open',
		one: '${n} session closed',
		other: '${n} sessions closed',
	);

	/// en: 'The devices could not be read. A connection is needed.'
	String get error => 'The devices could not be read. A connection is needed.';
}

// Path: muted
class Translations$muted$en {
	Translations$muted$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Hidden authors'
	String get title => 'Hidden authors';

	/// en: 'Nobody is hidden'
	String get empty => 'Nobody is hidden';

	/// en: 'From a review or a photo, the menu hides everything its author posts, for you only.'
	String get emptyHint => 'From a review or a photo, the menu hides everything its author posts, for you only.';

	/// en: 'Show again'
	String get unmute => 'Show again';

	/// en: 'Contributions by $name will show again'
	String unmuted({required Object name}) => 'Contributions by ${name} will show again';
}

// Path: mine
class Translations$mine$en {
	Translations$mine$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'My contributions'
	String get title => 'My contributions';

	/// en: 'Waiting to be sent'
	String get pending => 'Waiting to be sent';

	/// en: 'They leave as soon as the network is back.'
	String get pendingHint => 'They leave as soon as the network is back.';

	/// en: 'Send now'
	String get sendNow => 'Send now';

	/// en: 'Try again'
	String get retry => 'Try again';

	/// en: 'Give up'
	String get discard => 'Give up';

	/// en: 'Give up this contribution?'
	String get discardTitle => 'Give up this contribution?';

	/// en: 'It will not be sent.'
	String get discardBody => 'It will not be sent.';

	/// en: 'Reviews and ratings'
	String get reviews => 'Reviews and ratings';

	/// en: 'Photos'
	String get photos => 'Photos';

	/// en: 'Confirmations'
	String get confirmations => 'Confirmations';

	/// en: 'Problems reported'
	String get issues => 'Problems reported';

	/// en: 'Places added and edits'
	String get places => 'Places added and edits';

	/// en: 'Nothing yet'
	String get empty => 'Nothing yet';

	/// en: 'Rating a place or confirming it is still there already counts as a contribution.'
	String get emptyHint => 'Rating a place or confirming it is still there already counts as a contribution.';

	/// en: 'The latest $shown of $total'
	String latest({required Object shown, required Object total}) => 'The latest ${shown} of ${total}';

	/// en: 'Your contributions could not be read. A connection is needed.'
	String get error => 'Your contributions could not be read. A connection is needed.';

	/// en: 'Delete this contribution?'
	String get deleteTitle => 'Delete this contribution?';

	/// en: 'It goes from Lunaway.'
	String get deleteBody => 'It goes from Lunaway.';

	/// en: 'This place is already part of the map: it stays there, without your name.'
	String get deleteApplied => 'This place is already part of the map: it stays there, without your name.';

	/// en: 'Contribution deleted'
	String get deleted => 'Contribution deleted';

	/// en: 'Rating only'
	String get ratingOnly => 'Rating only';

	late final Translations$mine$status$en status = Translations$mine$status$en.internal(_root);
	late final Translations$mine$submission$en submission = Translations$mine$submission$en.internal(_root);

	/// en: 'New place'
	String get newPlace => 'New place';

	/// en: 'Edit'
	String get edit => 'Edit';

	/// en: 'A place'
	String get aPlace => 'A place';
}

// Path: outbox
class Translations$outbox$en {
	Translations$outbox$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$outbox$kind$en kind = Translations$outbox$kind$en.internal(_root);

	/// en: 'Waiting for the network'
	String get waiting => 'Waiting for the network';

	/// en: 'Sending'
	String get sending => 'Sending';

	late final Translations$outbox$error$en error = Translations$outbox$error$en.internal(_root);

	/// en: 'Thank you, it is sent'
	String get sent => 'Thank you, it is sent';

	/// en: 'No network: it leaves as soon as it is back'
	String get queued => 'No network: it leaves as soon as it is back';

	/// en: 'Not sent. $reason'
	String refused({required Object reason}) => 'Not sent. ${reason}';
}

// Path: contribute
class Translations$contribute$en {
	Translations$contribute$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your rating'
	String get yourRating => 'Your rating';

	/// en: 'Tap a star to rate'
	String get rateHint => 'Tap a star to rate';

	/// en: '(one) {Rate $n star} (other) {Rate $n stars}'
	String rateStar({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Rate ${n} star',
		other: 'Rate ${n} stars',
	);

	/// en: 'Write a review'
	String get writeReview => 'Write a review';

	/// en: 'Edit your review'
	String get editReview => 'Edit your review';

	/// en: 'Delete your review'
	String get deleteReview => 'Delete your review';

	/// en: 'Delete your review?'
	String get deleteReviewTitle => 'Delete your review?';

	/// en: 'The text and the rating go from the page.'
	String get deleteReviewBody => 'The text and the rating go from the page.';

	/// en: 'Remove your rating'
	String get deleteRating => 'Remove your rating';

	/// en: 'Remove your rating?'
	String get deleteRatingTitle => 'Remove your rating?';

	/// en: 'Your rating leaves the place's page.'
	String get deleteRatingBody => 'Your rating leaves the place\'s page.';

	/// en: 'Waiting to be sent'
	String get pendingSend => 'Waiting to be sent';

	/// en: 'Under review: visible to you only for now'
	String get statusPending => 'Under review: visible to you only for now';

	/// en: 'Hidden after reports, waiting for a moderator'
	String get statusHidden => 'Hidden after reports, waiting for a moderator';

	/// en: 'Removed by moderation'
	String get statusRemoved => 'Removed by moderation';

	/// en: 'Add a photo'
	String get addPhoto => 'Add a photo';

	/// en: 'Add the first photo'
	String get firstPhoto => 'Add the first photo';

	/// en: 'Still there?'
	String get stillThere => 'Still there?';

	/// en: 'More actions'
	String get more => 'More actions';

	/// en: 'Report a problem'
	String get reportIssue => 'Report a problem';

	/// en: 'Suggest a change'
	String get proposeEdit => 'Suggest a change';

	/// en: 'Edit the place'
	String get editPlace => 'Edit the place';

	/// en: 'Report this place to the moderators'
	String get reportPlace => 'Report this place to the moderators';

	/// en: 'To verify'
	String get toVerifyTitle => 'To verify';

	/// en: 'Added by the community, waiting for two confirmations. Been there? Say so.'
	String get toVerifyBody => 'Added by the community, waiting for two confirmations. Been there? Say so.';

	/// en: 'Reported over the last 30 days'
	String get issuesTitle => 'Reported over the last 30 days';

	/// en: '$kind ($count)'
	String issueCount({required Object kind, required Object count}) => '${kind} (${count})';

	/// en: 'Add a place'
	String get addPlace => 'Add a place';

	/// en: 'Add a place here'
	String get addPlaceHere => 'Add a place here';

	/// en: 'A long press on the map moves the point.'
	String get addPlaceHint => 'A long press on the map moves the point.';
}

// Path: confirmSheet
class Translations$confirmSheet$en {
	Translations$confirmSheet$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Still there?'
	String get title => 'Still there?';

	/// en: 'Been there recently? Your answer dates the page for the next travellers. No position is sent.'
	String get body => 'Been there recently? Your answer dates the page for the next travellers. No position is sent.';

	/// en: 'Yes, as described'
	String get stillOk => 'Yes, as described';

	/// en: 'Closed'
	String get closed => 'Closed';

	/// en: 'Changed'
	String get changed => 'Changed';

	/// en: 'No longer takes visitors'
	String get closedHint => 'No longer takes visitors';

	/// en: 'Still there, but something changed'
	String get changedHint => 'Still there, but something changed';

	/// en: 'A note for the moderators (optional)'
	String get note => 'A note for the moderators (optional)';

	/// en: 'For instance: a height barrier put up, a service point moved'
	String get noteHint => 'For instance: a height barrier put up, a service point moved';

	late final Translations$confirmSheet$status$en status = Translations$confirmSheet$status$en.internal(_root);
}

// Path: issueSheet
class Translations$issueSheet$en {
	Translations$issueSheet$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Report a problem'
	String get title => 'Report a problem';

	/// en: 'Your report counts in the warning shown on the page. Your note goes to the moderators only.'
	String get body => 'Your report counts in the warning shown on the page. Your note goes to the moderators only.';

	late final Translations$issueSheet$kind$en kind = Translations$issueSheet$kind$en.internal(_root);
	late final Translations$issueSheet$hint$en hint = Translations$issueSheet$hint$en.internal(_root);

	/// en: 'A note (optional)'
	String get note => 'A note (optional)';

	/// en: 'Report'
	String get send => 'Report';
}

// Path: reportSheet
class Translations$reportSheet$en {
	Translations$reportSheet$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Report this review'
	String get review => 'Report this review';

	/// en: 'Report this photo'
	String get photo => 'Report this photo';

	/// en: 'Report this place'
	String get place => 'Report this place';

	/// en: 'The moderators will read it. The author will not know who reported it.'
	String get body => 'The moderators will read it. The author will not know who reported it.';

	late final Translations$reportSheet$reason$en reason = Translations$reportSheet$reason$en.internal(_root);

	/// en: 'Tell more (optional)'
	String get note => 'Tell more (optional)';

	/// en: 'Say what is wrong'
	String get noteOther => 'Say what is wrong';

	/// en: 'Thank you, the moderators will look'
	String get sent => 'Thank you, the moderators will look';

	/// en: 'Hide reviews and photos by $name'
	String mute({required Object name}) => 'Hide reviews and photos by ${name}';

	/// en: 'Hide this author'
	String get muteAuthor => 'Hide this author';

	/// en: 'Hide $name?'
	String muteTitle({required Object name}) => 'Hide ${name}?';

	/// en: 'Their reviews and photos will no longer show for you. You can change your mind in your profile.'
	String get muteBody => 'Their reviews and photos will no longer show for you. You can change your mind in your profile.';

	/// en: '$name is hidden'
	String muted({required Object name}) => '${name} is hidden';

	/// en: 'Delete my photo'
	String get deletePhoto => 'Delete my photo';

	/// en: 'Delete this photo?'
	String get deletePhotoTitle => 'Delete this photo?';

	/// en: 'It goes from the page and from our servers.'
	String get deletePhotoBody => 'It goes from the page and from our servers.';
}

// Path: reviewSheet
class Translations$reviewSheet$en {
	Translations$reviewSheet$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your review'
	String get titleNew => 'Your review';

	/// en: 'Edit your review'
	String get titleEdit => 'Edit your review';

	/// en: 'Choose a rating from 1 to 5'
	String get starsRequired => 'Choose a rating from 1 to 5';

	/// en: 'Your review'
	String get text => 'Your review';

	/// en: 'The quiet, the welcome, the room to manoeuvre, what was useful'
	String get textHint => 'The quiet, the welcome, the room to manoeuvre, what was useful';

	/// en: '(one) {At least $n more character} (other) {At least $n more characters}'
	String tooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'At least ${n} more character',
		other: 'At least ${n} more characters',
	);

	/// en: 'Date of the stay'
	String get visited => 'Date of the stay';

	/// en: 'Not given'
	String get visitedNone => 'Not given';

	/// en: 'Your vehicle'
	String get vehicle => 'Your vehicle';

	/// en: 'Do not say'
	String get vehicleNone => 'Do not say';

	/// en: 'Published under CC BY 4.0, with your pseudonym. Put together, your reviews and their dates can show where you went: the date of the stay is optional.'
	String get licence => 'Published under CC BY 4.0, with your pseudonym. Put together, your reviews and their dates can show where you went: the date of the stay is optional.';

	/// en: 'Publish the review'
	String get publish => 'Publish the review';
}

// Path: gate
class Translations$gate$en {
	Translations$gate$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Written reviews open at level 1'
	String get review => 'Written reviews open at level 1';

	/// en: 'Photos open at level 1'
	String get photo => 'Photos open at level 1';

	/// en: 'Adding places opens at level 2'
	String get addPlace => 'Adding places opens at level 2';

	/// en: 'Suggesting changes opens at level 1'
	String get edit => 'Suggesting changes opens at level 1';

	/// en: 'Levels keep abuse off the map. They come with time and contributions, with nothing to buy.'
	String get why => 'Levels keep abuse off the map. They come with time and contributions, with nothing to buy.';

	/// en: 'Your level: $level'
	String yourLevel({required Object level}) => 'Your level: ${level}';

	/// en: 'No account yet: an account starts at level 0.'
	String get noAccount => 'No account yet: an account starts at level 0.';

	/// en: 'Level $level comes after the previous ones, with time and published contributions.'
	String later({required Object level}) => 'Level ${level} comes after the previous ones, with time and published contributions.';

	/// en: 'Meanwhile, you can rate this place, confirm it is still there or report a problem.'
	String get meanwhile => 'Meanwhile, you can rate this place, confirm it is still there or report a problem.';
}

// Path: photoFlow
class Translations$photoFlow$en {
	Translations$photoFlow$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add a photo'
	String get title => 'Add a photo';

	/// en: 'Take a photo'
	String get camera => 'Take a photo';

	/// en: 'Choose from the gallery'
	String get gallery => 'Choose from the gallery';

	/// en: 'Preparing the photo'
	String get preparing => 'Preparing the photo';

	/// en: 'Published under CC BY 4.0, with your pseudonym. Avoid faces and number plates.'
	String get licence => 'Published under CC BY 4.0, with your pseudonym. Avoid faces and number plates.';

	/// en: 'The position and the device's data are removed before sending.'
	String get stripped => 'The position and the device\'s data are removed before sending.';

	/// en: 'Send the photo'
	String get send => 'Send the photo';

	/// en: 'This picture cannot be read on this device. Try a JPEG or PNG photo.'
	String get unreadable => 'This picture cannot be read on this device. Try a JPEG or PNG photo.';

	/// en: 'Sending $percent %'
	String sending({required Object percent}) => 'Sending ${percent} %';

	/// en: 'Photo waiting to be sent'
	String get pending => 'Photo waiting to be sent';
}

// Path: placeForm
class Translations$placeForm$en {
	Translations$placeForm$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Add a place'
	String get addTitle => 'Add a place';

	/// en: 'Edit the place'
	String get editTitle => 'Edit the place';

	/// en: 'Suggest a change'
	String get proposeTitle => 'Suggest a change';

	/// en: 'Location'
	String get position => 'Location';

	/// en: 'Kind of place'
	String get kind => 'Kind of place';

	/// en: 'Choose a kind of place'
	String get kindRequired => 'Choose a kind of place';

	/// en: 'Name'
	String get name => 'Name';

	/// en: 'The name shown on site, or a short description'
	String get nameHint => 'The name shown on site, or a short description';

	/// en: '2 to 120 characters'
	String get nameInvalid => '2 to 120 characters';

	/// en: 'The night'
	String get night => 'The night';

	/// en: 'Services on site'
	String get services => 'Services on site';

	/// en: 'Description'
	String get description => 'Description';

	/// en: 'What helps to find and choose the place'
	String get descriptionHint => 'What helps to find and choose the place';

	/// en: 'Details'
	String get details => 'Details';

	/// en: 'Price of a night (€)'
	String get priceNight => 'Price of a night (€)';

	/// en: 'Price of the services (€)'
	String get priceServices => 'Price of the services (€)';

	/// en: 'Maximum height (m)'
	String get maxHeight => 'Maximum height (m)';

	/// en: 'Pitches'
	String get capacity => 'Pitches';

	/// en: 'Website'
	String get website => 'Website';

	/// en: 'Phone'
	String get phone => 'Phone';

	/// en: 'Photo (optional)'
	String get photo => 'Photo (optional)';

	/// en: 'Photo ready'
	String get photoReady => 'Photo ready';

	/// en: 'Remove the photo'
	String get removePhoto => 'Remove the photo';

	/// en: 'The place will show as “to verify” until two other travellers confirm it.'
	String get toVerify => 'The place will show as “to verify” until two other travellers confirm it.';

	/// en: 'Places are published under the ODbL, credited to the Lunaway contributors.'
	String get licence => 'Places are published under the ODbL, credited to the Lunaway contributors.';

	/// en: 'A website or a phone number goes through a moderator before it is published.'
	String get moderated => 'A website or a phone number goes through a moderator before it is published.';

	/// en: 'Your level applies the change at once.'
	String get direct => 'Your level applies the change at once.';

	/// en: 'A moderator will review your suggestion before it applies.'
	String get proposal => 'A moderator will review your suggestion before it applies.';

	/// en: 'Add the place'
	String get submitAdd => 'Add the place';

	/// en: 'Save the change'
	String get submitEdit => 'Save the change';

	/// en: 'Send the suggestion'
	String get submitPropose => 'Send the suggestion';

	/// en: 'Nothing has changed'
	String get nothingChanged => 'Nothing has changed';

	/// en: 'A number, please'
	String get invalidNumber => 'A number, please';

	/// en: 'An address starting with http:// or https://'
	String get invalidWebsite => 'An address starting with http:// or https://';

	/// en: 'Thank you: the place reaches the map in a moment'
	String get added => 'Thank you: the place reaches the map in a moment';

	/// en: 'Thank you: your suggestion goes to review'
	String get proposed => 'Thank you: your suggestion goes to review';
}

// Path: favoritesSync
class Translations$favoritesSync$en {
	Translations$favoritesSync$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'On this device only'
	String get local => 'On this device only';

	/// en: 'Sync'
	String get action => 'Sync';

	/// en: 'Syncing'
	String get syncing => 'Syncing';

	/// en: 'Kept with your account, synced $when'
	String synced({required Object when}) => 'Kept with your account, synced ${when}';

	/// en: 'Cannot sync right now'
	String get failed => 'Cannot sync right now';

	/// en: 'Sync your favourites?'
	String get title => 'Sync your favourites?';

	/// en: 'Your lists will be kept with a Lunaway account, with no e-mail and no password, to find them on another device. The account is made now.'
	String get body => 'Your lists will be kept with a Lunaway account, with no e-mail and no password, to find them on another device. The account is made now.';

	/// en: 'Make the account and sync'
	String get confirm => 'Make the account and sync';
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

// Path: account.levelOpens
class Translations$account$levelOpens$en {
	Translations$account$levelOpens$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'You can rate places, confirm they are still there, report a problem and sync your favourites.'
	String get l0 => 'You can rate places, confirm they are still there, report a problem and sync your favourites.';

	/// en: 'You can also write reviews, add photos and suggest changes to places.'
	String get l1 => 'You can also write reviews, add photos and suggest changes to places.';

	/// en: 'You can also add places.'
	String get l2 => 'You can also add places.';

	/// en: 'Your edits of places apply without review.'
	String get l3 => 'Your edits of places apply without review.';

	/// en: 'You take part in moderation.'
	String get l4 => 'You take part in moderation.';
}

// Path: account.requirement
class Translations$account$requirement$en {
	Translations$account$requirement$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'An account at least $needed days old ($current so far)'
	String age({required Object needed, required Object current}) => 'An account at least ${needed} days old (${current} so far)';

	/// en: '$needed confirmations of different places ($current so far)'
	String confirmations({required Object needed, required Object current}) => '${needed} confirmations of different places (${current} so far)';

	/// en: '$needed published contributions ($current so far)'
	String contributions({required Object needed, required Object current}) => '${needed} published contributions (${current} so far)';

	/// en: '$needed days of activity ($current so far)'
	String activeDays({required Object needed, required Object current}) => '${needed} days of activity (${current} so far)';

	/// en: 'No contribution removed by moderation'
	String get noRemoval => 'No contribution removed by moderation';

	/// en: 'A sponsor at level 2'
	String get sponsor => 'A sponsor at level 2';

	/// en: 'A nomination by a moderator'
	String get nomination => 'A nomination by a moderator';

	/// en: 'An appointment by the Lunaway team'
	String get administration => 'An appointment by the Lunaway team';
}

// Path: deletion.gone
class Translations$deletion$gone$en {
	Translations$deletion$gone$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your pseudonym and the keys of your devices'
	String get identity => 'Your pseudonym and the keys of your devices';

	/// en: 'Your sessions and your recovery code'
	String get sessions => 'Your sessions and your recovery code';

	/// en: 'Your synced favourite lists and your hidden authors'
	String get lists => 'Your synced favourite lists and your hidden authors';

	/// en: 'Your photos, your ratings without text and your reports'
	String get photos => 'Your photos, your ratings without text and your reports';

	/// en: 'Your proposals waiting for review'
	String get pending => 'Your proposals waiting for review';
}

// Path: mine.status
class Translations$mine$status$en {
	Translations$mine$status$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Published'
	String get published => 'Published';

	/// en: 'Under review'
	String get pending => 'Under review';

	/// en: 'Hidden after reports'
	String get hidden => 'Hidden after reports';

	/// en: 'Removed by moderation'
	String get removed => 'Removed by moderation';
}

// Path: mine.submission
class Translations$mine$submission$en {
	Translations$mine$submission$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Waiting for review'
	String get proposed => 'Waiting for review';

	/// en: 'Accepted'
	String get accepted => 'Accepted';

	/// en: 'On the map'
	String get applied => 'On the map';

	/// en: 'Refused'
	String get rejected => 'Refused';

	/// en: 'Withdrawn'
	String get withdrawn => 'Withdrawn';
}

// Path: outbox.kind
class Translations$outbox$kind$en {
	Translations$outbox$kind$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Rating of $stars out of 5'
	String rate({required Object stars}) => 'Rating of ${stars} out of 5';

	/// en: 'Review'
	String get review => 'Review';

	/// en: 'Deleting a review'
	String get deleteReview => 'Deleting a review';

	/// en: 'Still there? $status'
	String confirm({required Object status}) => 'Still there? ${status}';

	/// en: 'Deleting a confirmation'
	String get deleteConfirmation => 'Deleting a confirmation';

	/// en: 'Problem reported: $kind'
	String reportIssue({required Object kind}) => 'Problem reported: ${kind}';

	/// en: 'Deleting a report'
	String get deleteIssueReport => 'Deleting a report';

	/// en: 'Report to the moderators'
	String get reportContent => 'Report to the moderators';

	/// en: 'New place: $name'
	String addPlace({required Object name}) => 'New place: ${name}';

	/// en: 'Edit of a place'
	String get editPlace => 'Edit of a place';

	/// en: 'Withdrawing a proposed place'
	String get deletePlaceSubmission => 'Withdrawing a proposed place';

	/// en: 'Photo'
	String get photo => 'Photo';

	/// en: 'Deleting a photo'
	String get deletePhoto => 'Deleting a photo';

	/// en: 'Hiding an author'
	String get mute => 'Hiding an author';

	/// en: 'Showing an author again'
	String get unmute => 'Showing an author again';
}

// Path: outbox.error
class Translations$outbox$error$en {
	Translations$outbox$error$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Refused: your level does not allow it yet.'
	String get forbidden => 'Refused: your level does not allow it yet.';

	/// en: 'Refused: the place or the content no longer exists.'
	String get notFound => 'Refused: the place or the content no longer exists.';

	/// en: 'Refused: check the text (length, links, contact details).'
	String get invalid => 'Refused: check the text (length, links, contact details).';

	/// en: 'Photo refused: unreadable, or already sent.'
	String get unreadablePhoto => 'Photo refused: unreadable, or already sent.';

	/// en: 'Photo refused: too large.'
	String get photoTooLarge => 'Photo refused: too large.';

	/// en: 'The new place of this photo was refused.'
	String get placeRefused => 'The new place of this photo was refused.';

	/// en: 'The photo is no longer on the device.'
	String get fileLost => 'The photo is no longer on the device.';

	/// en: 'Made for another account: it will not be sent.'
	String get otherAccount => 'Made for another account: it will not be sent.';

	/// en: 'Refused by the server.'
	String get other => 'Refused by the server.';
}

// Path: confirmSheet.status
class Translations$confirmSheet$status$en {
	Translations$confirmSheet$status$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'still there'
	String get stillOk => 'still there';

	/// en: 'closed'
	String get closed => 'closed';

	/// en: 'changed'
	String get changed => 'changed';
}

// Path: issueSheet.kind
class Translations$issueSheet$kind$en {
	Translations$issueSheet$kind$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Nights now forbidden'
	String get nightBan => 'Nights now forbidden';

	/// en: 'Service out of order'
	String get serviceBroken => 'Service out of order';

	/// en: 'No access'
	String get noAccess => 'No access';

	/// en: 'Danger'
	String get danger => 'Danger';
}

// Path: issueSheet.hint
class Translations$issueSheet$hint$en {
	Translations$issueSheet$hint$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'A sign, a by-law, a police visit'
	String get nightBan => 'A sign, a by-law, a police visit';

	/// en: 'Service point, water, dump or power out of order'
	String get serviceBroken => 'Service point, water, dump or power out of order';

	/// en: 'A barrier, roadworks, a closed road'
	String get noAccess => 'A barrier, roadworks, a closed road';

	/// en: 'Theft, assault, unstable ground'
	String get danger => 'Theft, assault, unstable ground';
}

// Path: reportSheet.reason
class Translations$reportSheet$reason$en {
	Translations$reportSheet$reason$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Advertising or repetition'
	String get spam => 'Advertising or repetition';

	/// en: 'Insulting, hateful or shocking'
	String get offensive => 'Insulting, hateful or shocking';

	/// en: 'False or misleading'
	String get wrong => 'False or misleading';

	/// en: 'Shows or names a person, a plate, a private address'
	String get privacy => 'Shows or names a person, a plate, a private address';

	/// en: 'Another reason'
	String get other => 'Another reason';
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
			'common.send' => 'Send',
			'common.later' => 'Later',
			'common.next' => 'Continue',
			'common.failed' => 'That did not go through. Try again in a moment.',
			'common.offline' => 'No network right now. Try again once the connection is back.',
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
			'place.arriving' => 'This place comes with the download of the places',
			'place.arrivingHint' => 'The places of France are downloading so the map works without a network. The page opens as soon as this one is here.',
			'place.loadError' => 'This place could not be read.',
			'place.openFailed' => 'No app could open this link.',
			'place.photos' => 'Photos',
			'place.extrasOffline' => 'Photos and reviews need a connection.',
			'place.reviewsTitle' => 'Reviews',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} review', other: '${n} reviews', ), 
			'place.noReviews' => 'No reviews yet.',
			'place.noOtherReviews' => 'No other reviews yet.',
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
			'directions.hint' => 'Lunaway hands the trip to your navigation app.',
			'directions.remember' => 'Always use this app',
			'directions.rememberHint' => 'You can change it in Profile',
			'directions.noApp' => 'No navigation app is installed.',
			'directions.settingTitle' => 'Directions',
			'directions.settingHint' => 'The app your trips go to',
			'directions.askEachTime' => 'Ask each time',
			'directions.appleMaps' => 'Apple Maps',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (browser)',
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
			'vehicle.navigationLater' => 'The built-in route planner, coming later, will take all these dimensions into account.',
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
			'profile.noTracking' => 'No ads, no tracker. Your account knows neither your e-mail nor your phone number.',
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
			'account.title' => 'Your account',
			'account.noneTitle' => 'No account yet',
			'account.noneBody' => 'The map, search and favourites work without an account. One is made for you at your first contribution (a rating, a confirmation, a photo), with no e-mail and no password. Your favourite lists then join it.',
			'account.recover' => 'Recover my account',
			'account.memberSince' => ({required Object date}) => 'Member since ${date}',
			'account.editPseudonym' => 'Change the pseudonym',
			'account.pseudonymTitle' => 'Your pseudonym',
			'account.pseudonymHint' => 'Public: it goes with your reviews and photos. 3 to 32 characters.',
			'account.pseudonymInvalid' => '3 to 32 characters, at least two of them letters.',
			'account.pseudonymRefused' => 'This pseudonym is not accepted: no link, no contact detail, no insult, no name that passes the account off as the team.',
			'account.pseudonymSaved' => 'Pseudonym saved',
			'account.level' => ({required Object level}) => 'Trust level ${level}',
			'account.levelOpens.l0' => 'You can rate places, confirm they are still there, report a problem and sync your favourites.',
			'account.levelOpens.l1' => 'You can also write reviews, add photos and suggest changes to places.',
			'account.levelOpens.l2' => 'You can also add places.',
			'account.levelOpens.l3' => 'Your edits of places apply without review.',
			'account.levelOpens.l4' => 'You take part in moderation.',
			'account.nextLevel' => ({required Object level}) => 'For level ${level}',
			'account.levelTop' => 'You are at the highest level.',
			'account.requirement.age' => ({required Object needed, required Object current}) => 'An account at least ${needed} days old (${current} so far)',
			'account.requirement.confirmations' => ({required Object needed, required Object current}) => '${needed} confirmations of different places (${current} so far)',
			'account.requirement.contributions' => ({required Object needed, required Object current}) => '${needed} published contributions (${current} so far)',
			'account.requirement.activeDays' => ({required Object needed, required Object current}) => '${needed} days of activity (${current} so far)',
			'account.requirement.noRemoval' => 'No contribution removed by moderation',
			'account.requirement.sponsor' => 'A sponsor at level 2',
			'account.requirement.nomination' => 'A nomination by a moderator',
			'account.requirement.administration' => 'An appointment by the Lunaway team',
			'account.orInstead' => ({required Object requirement}) => 'Or instead: ${requirement}',
			'account.recoveryNone' => 'No recovery card yet. Without one, this account stays on this phone: lose the phone, and the account goes with it.',
			'account.recoveryCreate' => 'Make my recovery card',
			'account.recoveryMade' => ({required Object date}) => 'Recovery card made on ${date}',
			'account.recoveryRemake' => 'Make a new card',
			'account.contributions' => 'My contributions',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} contribution waiting to be sent', other: '${n} contributions waiting to be sent', ), 
			'account.mutedAuthors' => 'Hidden authors',
			'account.devices' => 'Devices',
			'account.signOut' => 'Sign out',
			'account.delete' => 'Delete my account',
			'account.signOutTitle' => 'Sign out of this device?',
			'account.signOutBody' => 'The account\'s key leaves this device. To come back, you will need your recovery card. Your favourites stay here.',
			'account.signOutNoCard' => 'You have not made a recovery card on this device. Without one, this account will be lost for good.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'One contribution waiting to be sent will not be sent.', other: '${n} contributions waiting to be sent will not be sent.', ), 
			'account.signedOut' => 'Signed out. Your favourites stay on this device.',
			'account.lost' => 'This account no longer opens on this device. Your recovery card brings it back.',
			'account.welcomeTitle' => 'Thank you for your first contribution',
			'account.welcomeBody' => ({required Object name}) => 'It made your account, under the pseudonym “${name}”. No e-mail and no password: a key kept on this device. You can change the pseudonym in your profile.',
			'account.welcomeCard' => 'Make your recovery card to find this account on another device.',
			'account.welcomeFavorites' => 'Your favourite lists are now kept with your account.',
			'recovery.title' => 'Recovery card',
			'recovery.intro' => 'A code that brings your account to a new device. Lunaway keeps only a fingerprint of it: nobody can give it back to you.',
			'recovery.replaces' => 'A new card replaces the previous one, which stops working.',
			'recovery.make' => 'Make the card',
			'recovery.codeLabel' => 'Your recovery code',
			'recovery.shownOnce' => 'This code shows only once. Write it down, or save the image, before closing.',
			'recovery.saveImage' => 'Save the image',
			'recovery.done' => 'I have it',
			'recovery.doneTitle' => 'Did you keep the code?',
			'recovery.doneBody' => 'Once this page is closed, it will not show again.',
			'recovery.keep' => 'Stay on the page',
			'recovery.cardHeading' => 'Lunaway recovery card',
			'recovery.cardAccount' => ({required Object name}) => 'Account: ${name}',
			'recovery.cardHow' => 'To recover the account: Profile, Recover my account, then type or read this code.',
			'recovery.cardMade' => ({required Object date}) => 'Made on ${date}',
			'recovery.cardWarning' => 'This code opens the account: entrust it to nobody.',
			'recovery.failed' => 'The card could not be made. A connection is needed.',
			'recovery.fileName' => 'lunaway-recovery-card',
			'recovery.step1' => 'Make the card: the code shows only once.',
			'recovery.step2' => 'Save the image, print it, or copy the code by hand.',
			'recovery.step3' => 'Keep it in the glovebox, with the vehicle\'s papers.',
			'recover.title' => 'Recover my account',
			'recover.intro' => 'Type the code of your recovery card, or read it from a photo of the card.',
			'recover.field' => 'Recovery code',
			'recover.fieldHint' => '27 characters, in groups of four',
			'recover.remaining' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} more character', other: '${n} more characters', ), 
			'recover.invalid' => 'This code matches no card: check each character.',
			'recover.valid' => 'Code complete',
			'recover.scan' => 'Read the card from a photo',
			'recover.scanFile' => 'Choose the card\'s image',
			'recover.reading' => 'Reading the card',
			'recover.scanFailed' => 'No readable code in this picture. Try a sharper photo, with the card held flat.',
			'recover.revoke' => 'My old device is lost or stolen: sign it out',
			'recover.revokeHint' => 'Every other key of the account will be removed.',
			'recover.submit' => 'Recover the account',
			'recover.notFound' => 'No account has this code. Check the card, or make a new one from a signed-in device.',
			'recover.tooMany' => 'Too many attempts for now. Try again in an hour.',
			'recover.done' => ({required Object name}) => 'Account recovered: ${name}',
			'deletion.title' => 'Delete my account',
			'deletion.intro' => 'Deletion is immediate and final.',
			'deletion.goneTitle' => 'What goes',
			'deletion.gone.identity' => 'Your pseudonym and the keys of your devices',
			'deletion.gone.sessions' => 'Your sessions and your recovery code',
			'deletion.gone.lists' => 'Your synced favourite lists and your hidden authors',
			'deletion.gone.photos' => 'Your photos, your ratings without text and your reports',
			'deletion.gone.pending' => 'Your proposals waiting for review',
			'deletion.keptTitle' => 'What stays, without your name',
			'deletion.kept' => 'Your published written reviews, your confirmations and your applied place edits stay, without author: they are part of other travellers\' map.',
			'deletion.backups' => 'The server\'s backups are cleared within 30 days.',
			'deletion.device' => 'On this device, your favourites stay; the account\'s key is erased.',
			'deletion.web' => 'You can also delete it on lunaway.net with your recovery code.',
			'deletion.webLink' => 'lunaway.net/account/delete',
			'deletion.confirmTitle' => 'Delete for good?',
			'deletion.confirmBody' => ({required Object name}) => 'The account “${name}” and everything listed go now. Nobody can bring it back.',
			'deletion.confirmCheck' => 'I understand this is final',
			'deletion.confirm' => 'Delete the account',
			'deletion.done' => 'Account deleted',
			'deletion.failed' => 'The account could not be deleted. A connection is needed.',
			'devices.title' => 'Devices',
			'devices.intro' => 'Each device has its own key. Remove a lost device, or one you no longer use.',
			'devices.thisDevice' => 'This device',
			'devices.other' => 'Other device',
			'devices.added' => ({required Object date}) => 'Added on ${date}',
			'devices.lastUsed' => ({required Object when}) => 'Last used ${when}',
			'devices.revoke' => 'Remove',
			'devices.revokeTitle' => 'Remove this device?',
			'devices.revokeBody' => 'It will be signed out and can no longer use the account.',
			'devices.revoked' => 'Device removed',
			'devices.signOutOthers' => 'Sign out every other device',
			'devices.signedOutOthers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, zero: 'No other session open', one: '${n} session closed', other: '${n} sessions closed', ), 
			'devices.error' => 'The devices could not be read. A connection is needed.',
			'muted.title' => 'Hidden authors',
			'muted.empty' => 'Nobody is hidden',
			'muted.emptyHint' => 'From a review or a photo, the menu hides everything its author posts, for you only.',
			'muted.unmute' => 'Show again',
			'muted.unmuted' => ({required Object name}) => 'Contributions by ${name} will show again',
			'mine.title' => 'My contributions',
			'mine.pending' => 'Waiting to be sent',
			'mine.pendingHint' => 'They leave as soon as the network is back.',
			'mine.sendNow' => 'Send now',
			'mine.retry' => 'Try again',
			'mine.discard' => 'Give up',
			'mine.discardTitle' => 'Give up this contribution?',
			'mine.discardBody' => 'It will not be sent.',
			'mine.reviews' => 'Reviews and ratings',
			'mine.photos' => 'Photos',
			'mine.confirmations' => 'Confirmations',
			'mine.issues' => 'Problems reported',
			'mine.places' => 'Places added and edits',
			'mine.empty' => 'Nothing yet',
			'mine.emptyHint' => 'Rating a place or confirming it is still there already counts as a contribution.',
			'mine.latest' => ({required Object shown, required Object total}) => 'The latest ${shown} of ${total}',
			'mine.error' => 'Your contributions could not be read. A connection is needed.',
			'mine.deleteTitle' => 'Delete this contribution?',
			'mine.deleteBody' => 'It goes from Lunaway.',
			'mine.deleteApplied' => 'This place is already part of the map: it stays there, without your name.',
			'mine.deleted' => 'Contribution deleted',
			'mine.ratingOnly' => 'Rating only',
			'mine.status.published' => 'Published',
			'mine.status.pending' => 'Under review',
			'mine.status.hidden' => 'Hidden after reports',
			'mine.status.removed' => 'Removed by moderation',
			'mine.submission.proposed' => 'Waiting for review',
			'mine.submission.accepted' => 'Accepted',
			'mine.submission.applied' => 'On the map',
			'mine.submission.rejected' => 'Refused',
			'mine.submission.withdrawn' => 'Withdrawn',
			'mine.newPlace' => 'New place',
			'mine.edit' => 'Edit',
			'mine.aPlace' => 'A place',
			'outbox.kind.rate' => ({required Object stars}) => 'Rating of ${stars} out of 5',
			'outbox.kind.review' => 'Review',
			'outbox.kind.deleteReview' => 'Deleting a review',
			'outbox.kind.confirm' => ({required Object status}) => 'Still there? ${status}',
			'outbox.kind.deleteConfirmation' => 'Deleting a confirmation',
			'outbox.kind.reportIssue' => ({required Object kind}) => 'Problem reported: ${kind}',
			'outbox.kind.deleteIssueReport' => 'Deleting a report',
			'outbox.kind.reportContent' => 'Report to the moderators',
			'outbox.kind.addPlace' => ({required Object name}) => 'New place: ${name}',
			'outbox.kind.editPlace' => 'Edit of a place',
			'outbox.kind.deletePlaceSubmission' => 'Withdrawing a proposed place',
			_ => null,
		} ?? switch (path) {
			'outbox.kind.photo' => 'Photo',
			'outbox.kind.deletePhoto' => 'Deleting a photo',
			'outbox.kind.mute' => 'Hiding an author',
			'outbox.kind.unmute' => 'Showing an author again',
			'outbox.waiting' => 'Waiting for the network',
			'outbox.sending' => 'Sending',
			'outbox.error.forbidden' => 'Refused: your level does not allow it yet.',
			'outbox.error.notFound' => 'Refused: the place or the content no longer exists.',
			'outbox.error.invalid' => 'Refused: check the text (length, links, contact details).',
			'outbox.error.unreadablePhoto' => 'Photo refused: unreadable, or already sent.',
			'outbox.error.photoTooLarge' => 'Photo refused: too large.',
			'outbox.error.placeRefused' => 'The new place of this photo was refused.',
			'outbox.error.fileLost' => 'The photo is no longer on the device.',
			'outbox.error.otherAccount' => 'Made for another account: it will not be sent.',
			'outbox.error.other' => 'Refused by the server.',
			'outbox.sent' => 'Thank you, it is sent',
			'outbox.queued' => 'No network: it leaves as soon as it is back',
			'outbox.refused' => ({required Object reason}) => 'Not sent. ${reason}',
			'contribute.yourRating' => 'Your rating',
			'contribute.rateHint' => 'Tap a star to rate',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Rate ${n} star', other: 'Rate ${n} stars', ), 
			'contribute.writeReview' => 'Write a review',
			'contribute.editReview' => 'Edit your review',
			'contribute.deleteReview' => 'Delete your review',
			'contribute.deleteReviewTitle' => 'Delete your review?',
			'contribute.deleteReviewBody' => 'The text and the rating go from the page.',
			'contribute.deleteRating' => 'Remove your rating',
			'contribute.deleteRatingTitle' => 'Remove your rating?',
			'contribute.deleteRatingBody' => 'Your rating leaves the place\'s page.',
			'contribute.pendingSend' => 'Waiting to be sent',
			'contribute.statusPending' => 'Under review: visible to you only for now',
			'contribute.statusHidden' => 'Hidden after reports, waiting for a moderator',
			'contribute.statusRemoved' => 'Removed by moderation',
			'contribute.addPhoto' => 'Add a photo',
			'contribute.firstPhoto' => 'Add the first photo',
			'contribute.stillThere' => 'Still there?',
			'contribute.more' => 'More actions',
			'contribute.reportIssue' => 'Report a problem',
			'contribute.proposeEdit' => 'Suggest a change',
			'contribute.editPlace' => 'Edit the place',
			'contribute.reportPlace' => 'Report this place to the moderators',
			'contribute.toVerifyTitle' => 'To verify',
			'contribute.toVerifyBody' => 'Added by the community, waiting for two confirmations. Been there? Say so.',
			'contribute.issuesTitle' => 'Reported over the last 30 days',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlace' => 'Add a place',
			'contribute.addPlaceHere' => 'Add a place here',
			'contribute.addPlaceHint' => 'A long press on the map moves the point.',
			'confirmSheet.title' => 'Still there?',
			'confirmSheet.body' => 'Been there recently? Your answer dates the page for the next travellers. No position is sent.',
			'confirmSheet.stillOk' => 'Yes, as described',
			'confirmSheet.closed' => 'Closed',
			'confirmSheet.changed' => 'Changed',
			'confirmSheet.closedHint' => 'No longer takes visitors',
			'confirmSheet.changedHint' => 'Still there, but something changed',
			'confirmSheet.note' => 'A note for the moderators (optional)',
			'confirmSheet.noteHint' => 'For instance: a height barrier put up, a service point moved',
			'confirmSheet.status.stillOk' => 'still there',
			'confirmSheet.status.closed' => 'closed',
			'confirmSheet.status.changed' => 'changed',
			'issueSheet.title' => 'Report a problem',
			'issueSheet.body' => 'Your report counts in the warning shown on the page. Your note goes to the moderators only.',
			'issueSheet.kind.nightBan' => 'Nights now forbidden',
			'issueSheet.kind.serviceBroken' => 'Service out of order',
			'issueSheet.kind.noAccess' => 'No access',
			'issueSheet.kind.danger' => 'Danger',
			'issueSheet.hint.nightBan' => 'A sign, a by-law, a police visit',
			'issueSheet.hint.serviceBroken' => 'Service point, water, dump or power out of order',
			'issueSheet.hint.noAccess' => 'A barrier, roadworks, a closed road',
			'issueSheet.hint.danger' => 'Theft, assault, unstable ground',
			'issueSheet.note' => 'A note (optional)',
			'issueSheet.send' => 'Report',
			'reportSheet.review' => 'Report this review',
			'reportSheet.photo' => 'Report this photo',
			'reportSheet.place' => 'Report this place',
			'reportSheet.body' => 'The moderators will read it. The author will not know who reported it.',
			'reportSheet.reason.spam' => 'Advertising or repetition',
			'reportSheet.reason.offensive' => 'Insulting, hateful or shocking',
			'reportSheet.reason.wrong' => 'False or misleading',
			'reportSheet.reason.privacy' => 'Shows or names a person, a plate, a private address',
			'reportSheet.reason.other' => 'Another reason',
			'reportSheet.note' => 'Tell more (optional)',
			'reportSheet.noteOther' => 'Say what is wrong',
			'reportSheet.sent' => 'Thank you, the moderators will look',
			'reportSheet.mute' => ({required Object name}) => 'Hide reviews and photos by ${name}',
			'reportSheet.muteAuthor' => 'Hide this author',
			'reportSheet.muteTitle' => ({required Object name}) => 'Hide ${name}?',
			'reportSheet.muteBody' => 'Their reviews and photos will no longer show for you. You can change your mind in your profile.',
			'reportSheet.muted' => ({required Object name}) => '${name} is hidden',
			'reportSheet.deletePhoto' => 'Delete my photo',
			'reportSheet.deletePhotoTitle' => 'Delete this photo?',
			'reportSheet.deletePhotoBody' => 'It goes from the page and from our servers.',
			'reviewSheet.titleNew' => 'Your review',
			'reviewSheet.titleEdit' => 'Edit your review',
			'reviewSheet.starsRequired' => 'Choose a rating from 1 to 5',
			'reviewSheet.text' => 'Your review',
			'reviewSheet.textHint' => 'The quiet, the welcome, the room to manoeuvre, what was useful',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'At least ${n} more character', other: 'At least ${n} more characters', ), 
			'reviewSheet.visited' => 'Date of the stay',
			'reviewSheet.visitedNone' => 'Not given',
			'reviewSheet.vehicle' => 'Your vehicle',
			'reviewSheet.vehicleNone' => 'Do not say',
			'reviewSheet.licence' => 'Published under CC BY 4.0, with your pseudonym. Put together, your reviews and their dates can show where you went: the date of the stay is optional.',
			'reviewSheet.publish' => 'Publish the review',
			'gate.review' => 'Written reviews open at level 1',
			'gate.photo' => 'Photos open at level 1',
			'gate.addPlace' => 'Adding places opens at level 2',
			'gate.edit' => 'Suggesting changes opens at level 1',
			'gate.why' => 'Levels keep abuse off the map. They come with time and contributions, with nothing to buy.',
			'gate.yourLevel' => ({required Object level}) => 'Your level: ${level}',
			'gate.noAccount' => 'No account yet: an account starts at level 0.',
			'gate.later' => ({required Object level}) => 'Level ${level} comes after the previous ones, with time and published contributions.',
			'gate.meanwhile' => 'Meanwhile, you can rate this place, confirm it is still there or report a problem.',
			'photoFlow.title' => 'Add a photo',
			'photoFlow.camera' => 'Take a photo',
			'photoFlow.gallery' => 'Choose from the gallery',
			'photoFlow.preparing' => 'Preparing the photo',
			'photoFlow.licence' => 'Published under CC BY 4.0, with your pseudonym. Avoid faces and number plates.',
			'photoFlow.stripped' => 'The position and the device\'s data are removed before sending.',
			'photoFlow.send' => 'Send the photo',
			'photoFlow.unreadable' => 'This picture cannot be read on this device. Try a JPEG or PNG photo.',
			'photoFlow.sending' => ({required Object percent}) => 'Sending ${percent} %',
			'photoFlow.pending' => 'Photo waiting to be sent',
			'placeForm.addTitle' => 'Add a place',
			'placeForm.editTitle' => 'Edit the place',
			'placeForm.proposeTitle' => 'Suggest a change',
			'placeForm.position' => 'Location',
			'placeForm.kind' => 'Kind of place',
			'placeForm.kindRequired' => 'Choose a kind of place',
			'placeForm.name' => 'Name',
			'placeForm.nameHint' => 'The name shown on site, or a short description',
			'placeForm.nameInvalid' => '2 to 120 characters',
			'placeForm.night' => 'The night',
			'placeForm.services' => 'Services on site',
			'placeForm.description' => 'Description',
			'placeForm.descriptionHint' => 'What helps to find and choose the place',
			'placeForm.details' => 'Details',
			'placeForm.priceNight' => 'Price of a night (€)',
			'placeForm.priceServices' => 'Price of the services (€)',
			'placeForm.maxHeight' => 'Maximum height (m)',
			'placeForm.capacity' => 'Pitches',
			'placeForm.website' => 'Website',
			'placeForm.phone' => 'Phone',
			'placeForm.photo' => 'Photo (optional)',
			'placeForm.photoReady' => 'Photo ready',
			'placeForm.removePhoto' => 'Remove the photo',
			'placeForm.toVerify' => 'The place will show as “to verify” until two other travellers confirm it.',
			'placeForm.licence' => 'Places are published under the ODbL, credited to the Lunaway contributors.',
			'placeForm.moderated' => 'A website or a phone number goes through a moderator before it is published.',
			'placeForm.direct' => 'Your level applies the change at once.',
			'placeForm.proposal' => 'A moderator will review your suggestion before it applies.',
			'placeForm.submitAdd' => 'Add the place',
			'placeForm.submitEdit' => 'Save the change',
			'placeForm.submitPropose' => 'Send the suggestion',
			'placeForm.nothingChanged' => 'Nothing has changed',
			'placeForm.invalidNumber' => 'A number, please',
			'placeForm.invalidWebsite' => 'An address starting with http:// or https://',
			'placeForm.added' => 'Thank you: the place reaches the map in a moment',
			'placeForm.proposed' => 'Thank you: your suggestion goes to review',
			'favoritesSync.local' => 'On this device only',
			'favoritesSync.action' => 'Sync',
			'favoritesSync.syncing' => 'Syncing',
			'favoritesSync.synced' => ({required Object when}) => 'Kept with your account, synced ${when}',
			'favoritesSync.failed' => 'Cannot sync right now',
			'favoritesSync.title' => 'Sync your favourites?',
			'favoritesSync.body' => 'Your lists will be kept with a Lunaway account, with no e-mail and no password, to find them on another device. The account is made now.',
			'favoritesSync.confirm' => 'Make the account and sync',
			_ => null,
		};
	}
}

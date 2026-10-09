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
	late final Translations$notices$en notices = Translations$notices$en.internal(_root);
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
	late final Translations$sources$en sources = Translations$sources$en.internal(_root);
	late final Translations$hours$en hours = Translations$hours$en.internal(_root);
	late final Translations$directions$en directions = Translations$directions$en.internal(_root);
	late final Translations$navigation$en navigation = Translations$navigation$en.internal(_root);
	late final Translations$list$en list = Translations$list$en.internal(_root);
	late final Translations$favorites$en favorites = Translations$favorites$en.internal(_root);
	late final Translations$vehicle$en vehicle = Translations$vehicle$en.internal(_root);
	late final Translations$vehicleHeight$en vehicleHeight = Translations$vehicleHeight$en.internal(_root);
	late final Translations$profile$en profile = Translations$profile$en.internal(_root);
	late final Translations$units$en units = Translations$units$en.internal(_root);
	late final Translations$languages$en languages = Translations$languages$en.internal(_root);
	late final Translations$translation$en translation = Translations$translation$en.internal(_root);
	late final Translations$locale$en locale = Translations$locale$en.internal(_root);
	late final Translations$account$en account = Translations$account$en.internal(_root);
	late final Translations$recovery$en recovery = Translations$recovery$en.internal(_root);
	late final Translations$recover$en recover = Translations$recover$en.internal(_root);
	late final Translations$deletion$en deletion = Translations$deletion$en.internal(_root);
	late final Translations$devices$en devices = Translations$devices$en.internal(_root);
	late final Translations$muted$en muted = Translations$muted$en.internal(_root);
	late final Translations$mine$en mine = Translations$mine$en.internal(_root);
	late final Translations$outbox$en outbox = Translations$outbox$en.internal(_root);
	late final Translations$placement$en placement = Translations$placement$en.internal(_root);
	late final Translations$contribute$en contribute = Translations$contribute$en.internal(_root);
	late final Translations$confirmSheet$en confirmSheet = Translations$confirmSheet$en.internal(_root);
	late final Translations$issueSheet$en issueSheet = Translations$issueSheet$en.internal(_root);
	late final Translations$reportSheet$en reportSheet = Translations$reportSheet$en.internal(_root);
	late final Translations$reviewSheet$en reviewSheet = Translations$reviewSheet$en.internal(_root);
	late final Translations$gate$en gate = Translations$gate$en.internal(_root);
	late final Translations$photoFlow$en photoFlow = Translations$photoFlow$en.internal(_root);
	late final Translations$placeForm$en placeForm = Translations$placeForm$en.internal(_root);
	late final Translations$favoritesSync$en favoritesSync = Translations$favoritesSync$en.internal(_root);
	late final Translations$poi$en poi = Translations$poi$en.internal(_root);
	late final Translations$offlineMaps$en offlineMaps = Translations$offlineMaps$en.internal(_root);
	late final Translations$regions$en regions = Translations$regions$en.internal(_root);
	late final Translations$roadReport$en roadReport = Translations$roadReport$en.internal(_root);
	late final Translations$countries$en countries = Translations$countries$en.internal(_root);
	late final Translations$areas$en areas = Translations$areas$en.internal(_root);
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

	/// en: 'Fold the menu'
	String get fold => 'Fold the menu';

	/// en: 'Unfold the menu'
	String get unfold => 'Unfold the menu';
}

// Path: common
class Translations$common$en {
	Translations$common$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Done'
	String get done => 'Done';

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

	/// en: 'That did not work. Try again in a moment.'
	String get failed => 'That did not work. Try again in a moment.';

	/// en: 'No connection right now. Try again once you are back online.'
	String get offline => 'No connection right now. Try again once you are back online.';
}

// Path: notices
class Translations$notices$en {
	Translations$notices$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Close the notice'
	String get close => 'Close the notice';

	/// en: 'Fold the notice'
	String get fold => 'Fold the notice';

	/// en: 'Show the notice'
	String get unfold => 'Show the notice';
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

	/// en: 'Water and dump points, no overnight stay'
	String get servicesHint => 'Water and dump points, no overnight stay';
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

	/// en: 'Confirmed by a traveller $when'
	String confirmed({required Object when}) => 'Confirmed by a traveller ${when}';

	/// en: 'Not yet confirmed by a traveller'
	String get unconfirmed => 'Not yet confirmed by a traveller';

	/// en: 'Last confirmed over a year ago'
	String get stale => 'Last confirmed over a year ago';

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

	/// en: 'Show places near me'
	String get aroundMe => 'Show places near me';

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

	/// en: '(one) {place nearest to you} (other) {places nearest to you}'
	String nearestYouLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'place nearest to you',
		other: 'places nearest to you',
	);

	/// en: '(one) {place nearest the centre} (other) {places nearest the centre}'
	String nearestCentreLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'place nearest the centre',
		other: 'places nearest the centre',
	);

	/// en: 'Here'
	String get pointTitle => 'Here';

	/// en: 'Point on the map'
	String get pointHint => 'Point on the map';

	/// en: 'Directions here'
	String get directionsHere => 'Directions here';

	/// en: 'Start from here'
	String get startHere => 'Start from here';

	/// en: 'Start chosen: now open the destination and its route.'
	String get departureChosen => 'Start chosen: now open the destination and its route.';

	/// en: 'Copy coordinates'
	String get copyCoordinates => 'Copy coordinates';

	/// en: 'Tap the map to go there or add a place'
	String get freeTapHint => 'Tap the map to go there or add a place';

	/// en: 'Click the map to go there or add a place'
	String get freeTapHintClick => 'Click the map to go there or add a place';

	/// en: 'Add a place at the centre of the map'
	String get addPlaceAtCenter => 'Add a place at the centre of the map';

	/// en: 'Source: $attribution'
	String addressSource({required Object attribution}) => 'Source: ${attribution}';

	/// en: 'Places around'
	String get placesAround => 'Places around';

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

	/// en: 'Lunaway uses it to centre the map on you, sort places by distance and guide you. For a route, your position is sent to Lunaway's server, which does not keep it. For the cheapest fuel around you, only a position rounded to about 5 km is sent. A road report goes with the spot where you make it.'
	String get rationale => 'Lunaway uses it to centre the map on you, sort places by distance and guide you. For a route, your position is sent to Lunaway\'s server, which does not keep it. For the cheapest fuel around you, only a position rounded to about 5 km is sent. A road report goes with the spot where you make it.';

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

	/// en: 'Your position cannot be found yet. Try again in the open or in a moment.'
	String get noFix => 'Your position cannot be found yet. Try again in the open or in a moment.';

	/// en: 'This device does not give its position.'
	String get unsupported => 'This device does not give its position.';

	/// en: 'The browser blocks your position'
	String get browserDeniedTitle => 'The browser blocks your position';

	/// en: 'The browser refuses your position to Lunaway. To allow it, click the icon left of the site's address (a padlock or sliders), set Location to Allow, then click the position button again.'
	String get browserDenied => 'The browser refuses your position to Lunaway. To allow it, click the icon left of the site\'s address (a padlock or sliders), set Location to Allow, then click the position button again.';

	/// en: 'The browser gave no position. Try again in a moment; on a computer, Wi-Fi helps find it.'
	String get browserNoFix => 'The browser gave no position. Try again in a moment; on a computer, Wi-Fi helps find it.';
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

	/// en: 'Addresses'
	String get addresses => 'Addresses';

	/// en: 'Looking for addresses'
	String get addressesSearching => 'Looking for addresses';

	/// en: 'Addresses could not be searched just now.'
	String get addressesFailed => 'Addresses could not be searched just now.';

	/// en: 'Addresses: $sources'
	String addressSources({required Object sources}) => 'Addresses: ${sources}';

	/// en: 'No connection: the search needs the network.'
	String get offline => 'No connection: the search needs the network.';

	late final Translations$search$addressKind$en addressKind = Translations$search$addressKind$en.internal(_root);
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

	/// en: 'Only these kinds'
	String get familiesChosenHint => 'Only these kinds';

	/// en: 'Overnight'
	String get night => 'Overnight';

	/// en: 'None chosen: every place'
	String get nightHint => 'None chosen: every place';

	/// en: 'Only the places with these statuses'
	String get nightChosenHint => 'Only the places with these statuses';

	/// en: 'Night possible'
	String get nightPossible => 'Night possible';

	/// en: 'Services'
	String get amenities => 'Services';

	/// en: 'The place must have all of them'
	String get amenitiesHint => 'The place must have all of them';

	/// en: 'Minimum rating'
	String get rating => 'Minimum rating';

	/// en: 'Lunaway visitors' rating, or the other sources' when they have not rated the place. A place without a rating is hidden.'
	String get ratingHint => 'Lunaway visitors\' rating, or the other sources\' when they have not rated the place. A place without a rating is hidden.';

	/// en: '$rating and up'
	String ratingAtLeast({required Object rating}) => '${rating} and up';

	/// en: 'Opening'
	String get opening => 'Opening';

	/// en: 'Places whose opening is not known stay shown.'
	String get openingHint => 'Places whose opening is not known stay shown.';

	/// en: 'All year'
	String get openingAllYear => 'All year';

	/// en: 'My dates'
	String get openingDates => 'My dates';

	/// en: 'Clear the dates'
	String get openingClearDates => 'Clear the dates';

	/// en: '$from to $to'
	String openingStay({required Object from, required Object to}) => '${from} to ${to}';

	/// en: 'On $date'
	String openingStayDay({required Object date}) => 'On ${date}';

	/// en: 'Dates of your stay'
	String get openingStayTitle => 'Dates of your stay';

	/// en: 'Arrival'
	String get openingArrival => 'Arrival';

	/// en: 'Departure'
	String get openingDeparture => 'Departure';

	/// en: 'Price of the night'
	String get price => 'Price of the night';

	/// en: 'Free'
	String get freeOnly => 'Free';

	/// en: 'Only places whose night is free according to their sources'
	String get freeHint => 'Only places whose night is free according to their sources';

	/// en: 'Show the next filters'
	String get scrollNext => 'Show the next filters';

	/// en: 'Show the previous filters'
	String get scrollPrevious => 'Show the previous filters';

	/// en: 'My vehicle'
	String get vehicle => 'My vehicle';

	/// en: 'My vehicle fits'
	String get myVehicleFits => 'My vehicle fits';

	/// en: 'Fits $height'
	String myVehicleFitsHeight({required Object height}) => 'Fits ${height}';

	/// en: 'Hides places limited below $height. Places with no known limit stay on the map.'
	String myVehicleHint({required Object height}) => 'Hides places limited below ${height}. Places with no known limit stay on the map.';

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

	/// en: 'Not given'
	String get priceUnknown => 'Not given';

	/// en: 'Services'
	String get priceServices => 'Services';

	/// en: 'Included'
	String get priceIncluded => 'Included';

	/// en: 'The price of a night includes: $items'
	String priceIncludes({required Object items}) => 'The price of a night includes: ${items}';

	late final Translations$place$inclusions$en inclusions = Translations$place$inclusions$en.internal(_root);

	/// en: 'Max. height'
	String get maxHeight => 'Max. height';

	/// en: 'Pitches'
	String get capacity => 'Pitches';

	/// en: 'Star rating'
	String get classification => 'Star rating';

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

	/// en: 'Copy as $format'
	String copyAs({required Object format}) => 'Copy as ${format}';

	/// en: '"Copy" copies: $format'
	String copiesAs({required Object format}) => '"Copy" copies: ${format}';

	/// en: 'Copied: $text'
	String copied({required Object text}) => 'Copied: ${text}';

	/// en: 'Choose the format to copy'
	String get otherFormats => 'Choose the format to copy';

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

	/// en: 'Retrieved $when'
	String fetched({required Object when}) => 'Retrieved ${when}';

	/// en: 'View at the source'
	String get viewSource => 'View at the source';

	/// en: 'This place is no longer on the map'
	String get gone => 'This place is no longer on the map';

	/// en: 'It was removed or merged with another since the last update.'
	String get goneHint => 'It was removed or merged with another since the last update.';

	/// en: 'This place is still downloading'
	String get arriving => 'This place is still downloading';

	/// en: 'The places of France are downloading so the map works without a network. The page opens as soon as this one is here.'
	String get arrivingHint => 'The places of France are downloading so the map works without a network. The page opens as soon as this one is here.';

	/// en: 'This place could not be loaded.'
	String get loadError => 'This place could not be loaded.';

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

	/// en: '(one) {external review} (other) {external reviews}'
	String externalRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'external review',
		other: 'external reviews',
	);

	/// en: 'Deleted account'
	String get deletedAccount => 'Deleted account';

	late final Translations$place$reviewVehicle$en reviewVehicle = Translations$place$reviewVehicle$en.internal(_root);

	/// en: 'Original text in $language'
	String originalLanguage({required Object language}) => 'Original text in ${language}';

	/// en: 'Photo $index of $count'
	String photoPosition({required Object index, required Object count}) => 'Photo ${index} of ${count}';

	/// en: 'Previous photo'
	String get previousPhoto => 'Previous photo';

	/// en: 'Next photo'
	String get nextPhoto => 'Next photo';

	/// en: 'On other sites'
	String get links => 'On other sites';

	/// en: '$source · $licence'
	String sourceWithLicence({required Object source, required Object licence}) => '${source} · ${licence}';

	/// en: 'CC BY 4.0'
	String get licenceCcBy => 'CC BY 4.0';

	/// en: '$source · $author'
	String photoCredit({required Object source, required Object author}) => '${source} · ${author}';

	/// en: 'Street view'
	String get photoStreetView => 'Street view';

	/// en: 'Surroundings'
	String get photoSurroundings => 'Surroundings';

	/// en: 'From $source: $text'
	String excerptFrom({required Object source, required Object text}) => 'From ${source}: ${text}';

	/// en: 'Read more'
	String get readMore => 'Read more';

	/// en: 'updated $date'
	String updatedOn({required Object date}) => 'updated ${date}';

	/// en: 'From other sources'
	String get otherSources => 'From other sources';
}

// Path: sources
class Translations$sources$en {
	Translations$sources$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$sources$extcom$en extcom = Translations$sources$extcom$en.internal(_root);
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

	/// en: '$day'
	String onWeekday({required Object day}) => '${day}';

	/// en: 'midnight'
	String get midnight => 'midnight';

	/// en: 'Open or closed? Update the places in Profile.'
	String get stale => 'Open or closed? Update the places in Profile.';

	/// en: 'Times are local to the place'
	String get localTime => 'Times are local to the place';

	late final Translations$hours$codes$en codes = Translations$hours$codes$en.internal(_root);
	late final Translations$hours$months$en months = Translations$hours$months$en.internal(_root);

	/// en: '$month $day'
	String dayOfMonth({required Object month, required Object day}) => '${month} ${day}';

	/// en: '$month $day, $year'
	String dayOfYear({required Object month, required Object day, required Object year}) => '${month} ${day}, ${year}';

	/// en: '24/7'
	String get allWeek => '24/7';

	/// en: 'all year'
	String get allYear => 'all year';

	/// en: 'Open all year'
	String get seasonAllYear => 'Open all year';

	/// en: 'Open until $date'
	String seasonOpenUntil({required Object date}) => 'Open until ${date}';

	/// en: 'Closed, opens $date'
	String seasonClosedUntil({required Object date}) => 'Closed, opens ${date}';
}

// Path: directions
class Translations$directions$en {
	Translations$directions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Open in'
	String get title => 'Open in';

	/// en: 'These apps do not know your vehicle's size.'
	String get hint => 'These apps do not know your vehicle\'s size.';

	/// en: 'Always use this app'
	String get remember => 'Always use this app';

	/// en: 'You can change it in Profile'
	String get rememberHint => 'You can change it in Profile';

	/// en: 'Open in another app'
	String get settingTitle => 'Open in another app';

	/// en: 'The app that "Open in" starts from a route'
	String get settingHint => 'The app that "Open in" starts from a route';

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

	/// en: 'No navigation app found on this device.'
	String get none => 'No navigation app found on this device.';
}

// Path: navigation
class Translations$navigation$en {
	Translations$navigation$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$navigation$preview$en preview = Translations$navigation$preview$en.internal(_root);
	late final Translations$navigation$stops$en stops = Translations$navigation$stops$en.internal(_root);
	late final Translations$navigation$legs$en legs = Translations$navigation$legs$en.internal(_root);
	late final Translations$navigation$fuel$en fuel = Translations$navigation$fuel$en.internal(_root);
	late final Translations$navigation$onTheWay$en onTheWay = Translations$navigation$onTheWay$en.internal(_root);
	late final Translations$navigation$states$en states = Translations$navigation$states$en.internal(_root);
	late final Translations$navigation$noRoute$en noRoute = Translations$navigation$noRoute$en.internal(_root);
	late final Translations$navigation$ferry$en ferry = Translations$navigation$ferry$en.internal(_root);
	late final Translations$navigation$warning$en warning = Translations$navigation$warning$en.internal(_root);
	late final Translations$navigation$roadEvents$en roadEvents = Translations$navigation$roadEvents$en.internal(_root);
	late final Translations$navigation$marks$en marks = Translations$navigation$marks$en.internal(_root);
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

	/// en: 'Places nearby'
	String get title => 'Places nearby';

	/// en: 'No places around here with these filters'
	String get empty => 'No places around here with these filters';

	/// en: 'Move the map, zoom out or loosen the filters.'
	String get emptyHint => 'Move the map, zoom out or loosen the filters.';

	/// en: 'Places are on their way'
	String get downloading => 'Places are on their way';

	/// en: 'The list fills in while they download.'
	String get downloadingHint => 'The list fills in while they download.';

	/// en: 'The list could not be loaded.'
	String get error => 'The list could not be loaded.';

	/// en: 'No connection: the list needs the network.'
	String get offline => 'No connection: the list needs the network.';

	/// en: 'More places could not be loaded. Try again'
	String get moreFailed => 'More places could not be loaded. Try again';

	/// en: 'Distance'
	String get sortDistance => 'Distance';

	/// en: 'Rating'
	String get sortRating => 'Rating';

	/// en: 'Recently added'
	String get sortNewest => 'Recently added';

	/// en: 'List sorted by: $sort'
	String sortedBy({required Object sort}) => 'List sorted by: ${sort}';

	/// en: 'Ranked among the $n places nearest you'
	String rankedAmongNearestYou({required Object n}) => 'Ranked among the ${n} places nearest you';

	/// en: 'Ranked among the $n places nearest the centre of the map'
	String rankedAmongNearestCentre({required Object n}) => 'Ranked among the ${n} places nearest the centre of the map';

	/// en: 'No connection'
	String get offlineTitle => 'No connection';

	/// en: 'Nothing of this area on this device.'
	String get offlineNotHere => 'Nothing of this area on this device.';
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

	/// en: 'Your favourites could not be loaded.'
	String get error => 'Your favourites could not be loaded.';
}

// Path: vehicle
class Translations$vehicle$en {
	Translations$vehicle$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'My vehicle'
	String get title => 'My vehicle';

	/// en: 'Its dimensions hide the places it cannot get into. They are sent with each route request and not kept.'
	String get why => 'Its dimensions hide the places it cannot get into. They are sent with each route request and not kept.';

	/// en: 'Describe your vehicle to hide the places it cannot get into.'
	String get none => 'Describe your vehicle to hide the places it cannot get into.';

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

	/// en: 'Fuel'
	String get fuelTitle => 'Fuel';

	/// en: 'The price of your fuel shows on the stations of the map, and the cheapest come first.'
	String get fuelHint => 'The price of your fuel shows on the stations of the map, and the cheapest come first.';

	/// en: 'Consumption'
	String get consumption => 'Consumption';

	/// en: 'L/100 km'
	String get consumptionUnit => 'L/100 km';

	/// en: 'Heating on LPG'
	String get lpgHeating => 'Heating on LPG';

	/// en: 'LPG prices also show on the stations.'
	String get lpgHeatingHint => 'LPG prices also show on the stations.';

	/// en: 'Top cruising speed'
	String get cruiseTitle => 'Top cruising speed';

	/// en: 'Travel times assume you never drive faster, even where the road allows it. The speed limits announced while driving stay the road's.'
	String get cruiseHint => 'Travel times assume you never drive faster, even where the road allows it. The speed limits announced while driving stay the road\'s.';

	/// en: 'No limit'
	String get cruiseNone => 'No limit';
}

// Path: vehicleHeight
class Translations$vehicleHeight$en {
	Translations$vehicleHeight$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your vehicle's height'
	String get title => 'Your vehicle\'s height';

	/// en: 'Places limited lower will be hidden. Places with no known limit stay on the map.'
	String get why => 'Places limited lower will be hidden. Places with no known limit stay on the map.';

	/// en: 'Give the height, for example 2.90'
	String get needed => 'Give the height, for example 2.90';

	/// en: 'Gross vehicle weight (optional)'
	String get weightOptional => 'Gross vehicle weight (optional)';

	/// en: 'Filter with this height'
	String get apply => 'Filter with this height';

	/// en: 'The rest of the vehicle is described in Profile, My vehicle.'
	String get later => 'The rest of the vehicle is described in Profile, My vehicle.';
}

// Path: profile
class Translations$profile$en {
	Translations$profile$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Profile'
	String get title => 'Profile';

	/// en: 'No account, no ads, no trackers. Your favourites stay on this device.'
	String get noAccountNeeded => 'No account, no ads, no trackers. Your favourites stay on this device.';

	/// en: 'Language'
	String get language => 'Language';

	/// en: 'Same as device'
	String get languageSystem => 'Same as device';

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

	/// en: 'Offline'
	String get offline => 'Offline';

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

	/// en: 'Routes are computed on open data that may be incomplete: road signs and the highway code come first.'
	String get routeData => 'Routes are computed on open data that may be incomplete: road signs and the highway code come first.';

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

	/// en: 'No ads, no trackers. Your account knows neither your e-mail nor your phone number.'
	String get noTracking => 'No ads, no trackers. Your account knows neither your e-mail nor your phone number.';

	/// en: 'Height, width, length and weight limits of the roads, and campsites placed by their name: IGN BD TOPO, through the Géoplateforme, under the Licence Ouverte 2.0.'
	String get attributionBdTopo => 'Height, width, length and weight limits of the roads, and campsites placed by their name: IGN BD TOPO, through the Géoplateforme, under the Licence Ouverte 2.0.';

	/// en: 'Addresses of the search in France: the Base Adresse Nationale, through IGN's Géoplateforme, under the Licence Ouverte 2.0.'
	String get attributionAddresses => 'Addresses of the search in France: the Base Adresse Nationale, through IGN\'s Géoplateforme, under the Licence Ouverte 2.0.';

	/// en: 'Addresses of the search elsewhere: OpenStreetMap, through Photon, under the ODbL.'
	String get attributionAddressesOsm => 'Addresses of the search elsewhere: OpenStreetMap, through Photon, under the ODbL.';

	/// en: 'Shops and services: OpenStreetMap, and La Poste's opening calendar, under the ODbL.'
	String get attributionPoiOdbl => 'Shops and services: OpenStreetMap, and La Poste\'s opening calendar, under the ODbL.';

	/// en: 'Fuel prices (French Ministry of the Economy) and the FINESS health establishments, under the Licence Ouverte 2.0 (Etalab).'
	String get attributionPoiLo => 'Fuel prices (French Ministry of the Economy) and the FINESS health establishments, under the Licence Ouverte 2.0 (Etalab).';

	/// en: 'Outlines of the offline maps: Contours administratifs, data.gouv.fr (ODbL), and Natural Earth (public domain).'
	String get attributionPacks => 'Outlines of the offline maps: Contours administratifs, data.gouv.fr (ODbL), and Natural Earth (public domain).';

	/// en: 'Offline map labels and icons: Noto Sans glyphs (SIL Open Font License 1.1) and Protomaps sprites derived from tangrams/icons (MIT).'
	String get attributionOfflineLabels => 'Offline map labels and icons: Noto Sans glyphs (SIL Open Font License 1.1) and Protomaps sprites derived from tangrams/icons (MIT).';

	/// en: 'Places, reviews, ratings and photos, under a written agreement with this source.'
	String get attributionExtcom => 'Places, reviews, ratings and photos, under a written agreement with this source.';

	/// en: 'Places'
	String get creditsPlaces => 'Places';

	/// en: 'Photos, texts and reviews'
	String get creditsContent => 'Photos, texts and reviews';

	/// en: 'Routes and guidance'
	String get creditsRoutes => 'Routes and guidance';

	/// en: 'Search'
	String get creditsSearch => 'Search';

	/// en: 'Basemap'
	String get creditsMap => 'Basemap';

	/// en: 'App'
	String get creditsApp => 'App';

	/// en: 'Places, descriptions and photos of the tourist offices: DATAtourisme, under the Licence Ouverte 2.0; each text and photo names its office, its author and the date of its last update.'
	String get attributionDatatourisme => 'Places, descriptions and photos of the tourist offices: DATAtourisme, under the Licence Ouverte 2.0; each text and photo names its office, its author and the date of its last update.';

	/// en: 'Reviews, ratings and photos by Lunaway's travellers, under CC BY 4.0, with their author's pseudonym.'
	String get attributionCommunity => 'Reviews, ratings and photos by Lunaway\'s travellers, under CC BY 4.0, with their author\'s pseudonym.';

	/// en: 'Photos from Wikimedia Commons, each under its own licence (CC0, CC BY or CC BY-SA), with its author and a link to its page.'
	String get attributionCommons => 'Photos from Wikimedia Commons, each under its own licence (CC0, CC BY or CC BY-SA), with its author and a link to its page.';

	/// en: 'Street views from Panoramax: the OpenStreetMap France instance under CC BY-SA 4.0, IGN's under the Licence Ouverte 2.0.'
	String get attributionPanoramax => 'Street views from Panoramax: the OpenStreetMap France instance under CC BY-SA 4.0, IGN\'s under the Licence Ouverte 2.0.';

	/// en: 'Extracts of Wikipedia articles, under CC BY-SA 4.0, with a link to the article.'
	String get attributionWikipedia => 'Extracts of Wikipedia articles, under CC BY-SA 4.0, with a link to the article.';

	/// en: 'Reviews from Mangrove Reviews, under CC BY 4.0 or the licence the review states, with a link to the review.'
	String get attributionMangrove => 'Reviews from Mangrove Reviews, under CC BY 4.0 or the licence the review states, with a link to the review.';

	/// en: 'Road works and closures in France: DIR and Bison Futé, DiaLog traffic orders (DGITM), cities and départements (Lyon, Toulouse, Bordeaux, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d'Armor, Sarthe), under the Licence Ouverte 2.0; Rennes Métropole and the reports of Lunaway's travellers, under the ODbL.'
	String get attributionRoadEvents => 'Road works and closures in France: DIR and Bison Futé, DiaLog traffic orders (DGITM), cities and départements (Lyon, Toulouse, Bordeaux, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d\'Armor, Sarthe), under the Licence Ouverte 2.0; Rennes Métropole and the reports of Lunaway\'s travellers, under the ODbL.';

	/// en: 'Road works and closures in the Netherlands: NDW, Nationaal Dataportaal Wegverkeer (open data); in Spain: DGT, Dirección General de Tráfico (CC BY).'
	String get attributionRoadEventsAbroad => 'Road works and closures in the Netherlands: NDW, Nationaal Dataportaal Wegverkeer (open data); in Spain: DGT, Dirección General de Tráfico (CC BY).';

	/// en: 'Danger zones: the official speed camera lists (Sécurité routière in France, reused under the French Code des relations entre le public et l'administration; Poland and Luxembourg, CC0; Catalonia, the Generalitat's open licence; Norway, NLOD) and OpenStreetMap (ODbL).'
	String get attributionDangerZones => 'Danger zones: the official speed camera lists (Sécurité routière in France, reused under the French Code des relations entre le public et l\'administration; Poland and Luxembourg, CC0; Catalonia, the Generalitat\'s open licence; Norway, NLOD) and OpenStreetMap (ODbL).';
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

// Path: translation
class Translations$translation$en {
	Translations$translation$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Translate'
	String get translate => 'Translate';

	/// en: 'Translating'
	String get translating => 'Translating';

	/// en: 'Show original'
	String get showOriginal => 'Show original';

	/// en: 'Show translation'
	String get showTranslation => 'Show translation';

	late final Translations$translation$from$en from = Translations$translation$from$en.internal(_root);

	/// en: 'Translation needs a network connection.'
	String get offline => 'Translation needs a network connection.';

	/// en: 'No connection: the text could not be translated.'
	String get failedOffline => 'No connection: the text could not be translated.';

	/// en: 'The translation service is busy. Try again later.'
	String get busy => 'The translation service is busy. Try again later.';

	/// en: 'Translation is not available right now.'
	String get unavailable => 'Translation is not available right now.';

	/// en: 'This text is no longer available.'
	String get gone => 'This text is no longer available.';

	/// en: 'No translation is available for this language.'
	String get unsupported => 'No translation is available for this language.';

	/// en: 'Translate reviews automatically'
	String get autoReviews => 'Translate reviews automatically';

	/// en: 'Reviews in another language are translated by Lunaway's own server, without any third-party service.'
	String get autoReviewsHint => 'Reviews in another language are translated by Lunaway\'s own server, without any third-party service.';
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

	/// en: 'Deutsch'
	String get de => 'Deutsch';

	/// en: 'Español'
	String get es => 'Español';

	/// en: 'Italiano'
	String get it => 'Italiano';

	/// en: 'Nederlands'
	String get nl => 'Nederlands';
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

	/// en: 'The map, search and favourites work without an account. One is created at your first contribution (a rating, a confirmation, a photo), with no e-mail and no password. Your favourite lists are then linked to it.'
	String get noneBody => 'The map, search and favourites work without an account. One is created at your first contribution (a rating, a confirmation, a photo), with no e-mail and no password. Your favourite lists are then linked to it.';

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

	/// en: 'Or $requirement'
	String orInstead({required Object requirement}) => 'Or ${requirement}';

	/// en: 'No recovery card made on this device. Without one, this account stays on this device: lose it, and the account goes with it.'
	String get recoveryNone => 'No recovery card made on this device. Without one, this account stays on this device: lose it, and the account goes with it.';

	/// en: 'No recovery card for this account yet. Without one, this account stays on this device: lose it, and the account goes with it.'
	String get recoveryNoneAccount => 'No recovery card for this account yet. Without one, this account stays on this device: lose it, and the account goes with it.';

	/// en: 'Make my recovery card'
	String get recoveryCreate => 'Make my recovery card';

	/// en: 'Made on $date'
	String recoveryMade({required Object date}) => 'Made on ${date}';

	/// en: 'Make again'
	String get recoveryRemake => 'Make again';

	/// en: 'Make a new recovery card'
	String get recoveryRemakeHint => 'Make a new recovery card';

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

	/// en: 'The account's key is removed from this device. To come back, you will need your recovery card. Your favourites stay here.'
	String get signOutBody => 'The account\'s key is removed from this device. To come back, you will need your recovery card. Your favourites stay here.';

	/// en: 'You have not made a recovery card on this device. Without one, this account will be lost for good.'
	String get signOutNoCard => 'You have not made a recovery card on this device. Without one, this account will be lost for good.';

	/// en: '(one) {One contribution waiting to be sent will not be sent.} (other) {$n contributions waiting to be sent will not be sent.}'
	String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'One contribution waiting to be sent will not be sent.',
		other: '${n} contributions waiting to be sent will not be sent.',
	);

	/// en: 'Signed out. Your favourites stay on this device.'
	String get signedOut => 'Signed out. Your favourites stay on this device.';

	/// en: 'This account no longer opens on this device. Recover it with your recovery card: Profile, Recover my account.'
	String get lost => 'This account no longer opens on this device. Recover it with your recovery card: Profile, Recover my account.';

	/// en: 'Recover'
	String get lostAction => 'Recover';

	/// en: 'Thank you for your first contribution'
	String get welcomeTitle => 'Thank you for your first contribution';

	/// en: 'Your account is created, under the pseudonym “$name”. No e-mail and no password: a key kept on this device. You can change the pseudonym in your profile.'
	String welcomeBody({required Object name}) => 'Your account is created, under the pseudonym “${name}”. No e-mail and no password: a key kept on this device. You can change the pseudonym in your profile.';

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

	/// en: 'A code that brings your account to a new device. Lunaway keeps only a fingerprint of it, enough to check it: the code itself can never be shown again, and each new card has a different code.'
	String get intro => 'A code that brings your account to a new device. Lunaway keeps only a fingerprint of it, enough to check it: the code itself can never be shown again, and each new card has a different code.';

	/// en: 'A new card replaces the previous one: the old code will stop working.'
	String get replaces => 'A new card replaces the previous one: the old code will stop working.';

	/// en: 'Replace the card of $date?'
	String replaceTitle({required Object date}) => 'Replace the card of ${date}?';

	/// en: 'The new card will have another code. The code of the card of $date stops working right now. It cannot be shown again: Lunaway kept only a fingerprint of it.'
	String replaceBody({required Object date}) => 'The new card will have another code. The code of the card of ${date} stops working right now. It cannot be shown again: Lunaway kept only a fingerprint of it.';

	/// en: 'Keep the old one'
	String get replaceKeep => 'Keep the old one';

	/// en: 'Make a new card'
	String get replaceConfirm => 'Make a new card';

	/// en: 'Make the card'
	String get make => 'Make the card';

	/// en: 'Your recovery code'
	String get codeLabel => 'Your recovery code';

	/// en: 'This code shows only once. Write it down, or save the image, before closing.'
	String get shownOnce => 'This code shows only once. Write it down, or save the image, before closing.';

	/// en: 'Save the image'
	String get saveImage => 'Save the image';

	/// en: 'I have noted the code'
	String get done => 'I have noted the code';

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

	/// en: 'To recover the account: Profile, Recover my account, then type this code or scan the card.'
	String get cardHow => 'To recover the account: Profile, Recover my account, then type this code or scan the card.';

	/// en: 'Made on $date'
	String cardMade({required Object date}) => 'Made on ${date}';

	/// en: 'This code opens the account: never share it.'
	String get cardWarning => 'This code opens the account: never share it.';

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

	/// en: 'All your other devices will be signed out.'
	String get revokeHint => 'All your other devices will be signed out.';

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

	/// en: 'What is deleted'
	String get goneTitle => 'What is deleted';

	late final Translations$deletion$gone$en gone = Translations$deletion$gone$en.internal(_root);

	/// en: 'What stays, without your name'
	String get keptTitle => 'What stays, without your name';

	/// en: 'Your published written reviews, your confirmations and your applied place edits stay, without author: they are part of other travellers' map.'
	String get kept => 'Your published written reviews, your confirmations and your applied place edits stay, without author: they are part of other travellers\' map.';

	/// en: 'The server's backups are cleared in about 30 days.'
	String get backups => 'The server\'s backups are cleared in about 30 days.';

	/// en: 'On this device, your favourites stay; the account's key is erased.'
	String get device => 'On this device, your favourites stay; the account\'s key is erased.';

	/// en: 'You can also delete it on lunaway.net with your recovery code.'
	String get web => 'You can also delete it on lunaway.net with your recovery code.';

	/// en: 'lunaway.net/account/delete'
	String get webLink => 'lunaway.net/account/delete';

	/// en: 'Delete for good?'
	String get confirmTitle => 'Delete for good?';

	/// en: 'The account “$name” and everything listed are deleted now. Nobody can bring it back.'
	String confirmBody({required Object name}) => 'The account “${name}” and everything listed are deleted now. Nobody can bring it back.';

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

	/// en: 'The devices could not be loaded. A connection is needed.'
	String get error => 'The devices could not be loaded. A connection is needed.';
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

	/// en: 'To hide someone, open the menu of one of their reviews or photos. Hiding applies to you only.'
	String get emptyHint => 'To hide someone, open the menu of one of their reviews or photos. Hiding applies to you only.';

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

	/// en: 'Discard'
	String get discard => 'Discard';

	/// en: 'Discard this contribution?'
	String get discardTitle => 'Discard this contribution?';

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

	/// en: 'Your contributions could not be loaded. A connection is needed.'
	String get error => 'Your contributions could not be loaded. A connection is needed.';

	/// en: 'Delete this contribution?'
	String get deleteTitle => 'Delete this contribution?';

	/// en: 'It is removed from Lunaway.'
	String get deleteBody => 'It is removed from Lunaway.';

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

	/// en: 'New vending machine'
	String get newVendingMachine => 'New vending machine';

	/// en: 'Shops and services confirmed'
	String get poiConfirmations => 'Shops and services confirmed';

	/// en: 'A shop or service'
	String get aPoi => 'A shop or service';
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

	/// en: 'No connection: it will be sent once you are back online'
	String get queued => 'No connection: it will be sent once you are back online';

	/// en: 'Not sent. $reason'
	String refused({required Object reason}) => 'Not sent. ${reason}';
}

// Path: placement
class Translations$placement$en {
	Translations$placement$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Place the spot'
	String get title => 'Place the spot';

	/// en: 'Move the map: the crosshair marks the exact spot.'
	String get hint => 'Move the map: the crosshair marks the exact spot.';

	/// en: 'Use this spot'
	String get confirm => 'Use this spot';

	/// en: '“$name” is already $distance away: is it the same spot?'
	String duplicate({required Object name, required Object distance}) => '“${name}” is already ${distance} away: is it the same spot?';

	/// en: 'Yes, open its page'
	String get same => 'Yes, open its page';

	/// en: 'No, it is another place'
	String get notSame => 'No, it is another place';
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

	/// en: 'The text and the rating are removed from the page.'
	String get deleteReviewBody => 'The text and the rating are removed from the page.';

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

	/// en: 'Added by the community, waiting for two confirmations. Know it? Confirm it.'
	String get toVerifyBody => 'Added by the community, waiting for two confirmations. Know it? Confirm it.';

	/// en: 'Reports from the last 30 days'
	String get issuesTitle => 'Reports from the last 30 days';

	/// en: '$kind ($count)'
	String issueCount({required Object kind, required Object count}) => '${kind} (${count})';

	/// en: 'Create a place here'
	String get addPlaceHere => 'Create a place here';

	/// en: 'The spot set under the crosshair.'
	String get addPlaceHint => 'The spot set under the crosshair.';
}

// Path: confirmSheet
class Translations$confirmSheet$en {
	Translations$confirmSheet$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Still there?'
	String get title => 'Still there?';

	/// en: 'Been there recently? Your answer tells the next travellers the page is up to date. No position is sent.'
	String get body => 'Been there recently? Your answer tells the next travellers the page is up to date. No position is sent.';

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

	/// en: 'Anything to add? (optional)'
	String get note => 'Anything to add? (optional)';

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

	/// en: 'Anything to add? (optional)'
	String get note => 'Anything to add? (optional)';

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

	/// en: 'Thank you, the moderators will take a look'
	String get sent => 'Thank you, the moderators will take a look';

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

	/// en: 'It is removed from the page and from our servers.'
	String get deletePhotoBody => 'It is removed from the page and from our servers.';
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

	/// en: 'Prefer not to say'
	String get vehicleNone => 'Prefer not to say';

	/// en: 'Published under CC BY 4.0, with your pseudonym. The date of the stay is optional: put together, the dates of your reviews can reveal your route.'
	String get licence => 'Published under CC BY 4.0, with your pseudonym. The date of the stay is optional: put together, the dates of your reviews can reveal your route.';

	/// en: 'Publish the review'
	String get publish => 'Publish the review';
}

// Path: gate
class Translations$gate$en {
	Translations$gate$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Written reviews: from level 1'
	String get review => 'Written reviews: from level 1';

	/// en: 'Photos: from level 1'
	String get photo => 'Photos: from level 1';

	/// en: 'Adding places: from level 2'
	String get addPlace => 'Adding places: from level 2';

	/// en: 'Suggesting changes: from level 1'
	String get edit => 'Suggesting changes: from level 1';

	/// en: 'Levels protect the map from abuse. They come with time and contributions, with nothing to buy.'
	String get why => 'Levels protect the map from abuse. They come with time and contributions, with nothing to buy.';

	/// en: 'Your level: $level'
	String yourLevel({required Object level}) => 'Your level: ${level}';

	/// en: 'No account yet: an account starts at level 0.'
	String get noAccount => 'No account yet: an account starts at level 0.';

	/// en: 'Level $level comes after the previous ones, with time and published contributions.'
	String later({required Object level}) => 'Level ${level} comes after the previous ones, with time and published contributions.';

	/// en: 'Meanwhile, you can rate places, confirm they are still there or report a problem.'
	String get meanwhile => 'Meanwhile, you can rate places, confirm they are still there or report a problem.';
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

	/// en: 'Position on the map'
	String get position => 'Position on the map';

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

	/// en: 'Overnight'
	String get night => 'Overnight';

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

// Path: poi
class Translations$poi$en {
	Translations$poi$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$poi$category$en category = Translations$poi$category$en.internal(_root);
	late final Translations$poi$kind$en kind = Translations$poi$kind$en.internal(_root);

	/// en: 'Shops and services around'
	String get chipsLabel => 'Shops and services around';

	/// en: 'Open now'
	String get openNow => 'Open now';

	late final Translations$poi$vendingSells$en vendingSells = Translations$poi$vendingSells$en.internal(_root);

	/// en: 'All food vending machines'
	String get vendingAll => 'All food vending machines';

	/// en: 'What the machines sell'
	String get vendingMenu => 'What the machines sell';

	late final Translations$poi$vendingChip$en vendingChip = Translations$poi$vendingChip$en.internal(_root);

	/// en: 'Open day and night'
	String get alwaysOpen => 'Open day and night';

	/// en: 'Opening hours unknown'
	String get hoursUnknown => 'Opening hours unknown';

	/// en: 'Closed according to the official register of health facilities (FINESS).'
	String get maybeClosed => 'Closed according to the official register of health facilities (FINESS).';

	/// en: 'Listed as closed by FINESS since $date: it may have shut for good.'
	String maybeClosedSince({required Object date}) => 'Listed as closed by FINESS since ${date}: it may have shut for good.';

	/// en: 'Seasonal: it may be shut in winter.'
	String get seasonal => 'Seasonal: it may be shut in winter.';

	/// en: 'Fee'
	String get fee => 'Fee';

	/// en: 'Free'
	String get free => 'Free';

	/// en: 'Still there?'
	String get stillThereTitle => 'Still there?';

	/// en: 'Seen it lately? Your answer helps the next travellers. No position is sent.'
	String get stillThereHint => 'Seen it lately? Your answer helps the next travellers. No position is sent.';

	/// en: 'Still there'
	String get stillThere => 'Still there';

	/// en: 'Gone'
	String get gone => 'Gone';

	/// en: 'Confirmed there $when'
	String lastConfirmed({required Object when}) => 'Confirmed there ${when}';

	/// en: 'Checked on the spot on $date'
	String checkedOn({required Object date}) => 'Checked on the spot on ${date}';

	/// en: 'Thank you, noted: still there.'
	String get thanksThere => 'Thank you, noted: still there.';

	/// en: 'Thank you, noted: gone.'
	String get thanksGone => 'Thank you, noted: gone.';

	/// en: 'Fuel prices'
	String get fuelPrices => 'Fuel prices';

	/// en: '$price/L'
	String perLitre({required Object price}) => '${price}/L';

	/// en: 'Price updated $when'
	String priceUpdated({required Object when}) => 'Price updated ${when}';

	/// en: 'Prices checked $when'
	String feedRead({required Object when}) => 'Prices checked ${when}';

	/// en: 'Out of stock for now'
	String get shortageTemporary => 'Out of stock for now';

	/// en: 'No longer sold'
	String get shortageDefinitive => 'No longer sold';

	/// en: 'Pay at pump 24/7'
	String get selfService24h => 'Pay at pump 24/7';

	/// en: 'On a motorway'
	String get highway => 'On a motorway';

	/// en: 'Sells LPG'
	String get lpgYes => 'Sells LPG';

	late final Translations$poi$fuel$en fuel = Translations$poi$fuel$en.internal(_root);

	/// en: 'Sells'
	String get products => 'Sells';

	/// en: 'Payment'
	String get paymentTitle => 'Payment';

	late final Translations$poi$product$en product = Translations$poi$product$en.internal(_root);
	late final Translations$poi$payment$en payment = Translations$poi$payment$en.internal(_root);

	/// en: 'just now'
	String get justNow => 'just now';

	/// en: '(one) {$n minute ago} (other) {$n minutes ago}'
	String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} minute ago',
		other: '${n} minutes ago',
	);

	/// en: '(one) {$n hour ago} (other) {$n hours ago}'
	String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} hour ago',
		other: '${n} hours ago',
	);

	/// en: 'Checked $when: no connection to refresh it'
	String readOffline({required Object when}) => 'Checked ${when}: no connection to refresh it';

	/// en: 'Checked $when: it could not be refreshed just now.'
	String readStale({required Object when}) => 'Checked ${when}: it could not be refreshed just now.';

	/// en: 'This point is no longer on the map'
	String get goneTitle => 'This point is no longer on the map';

	/// en: 'Travellers said it is gone, or the last update removed it.'
	String get goneHint => 'Travellers said it is gone, or the last update removed it.';

	/// en: 'The details could not be loaded. What the map knows is above.'
	String get loadError => 'The details could not be loaded. What the map knows is above.';

	/// en: 'Around this place'
	String get around => 'Around this place';

	/// en: 'No shop or service known around here.'
	String get aroundEmpty => 'No shop or service known around here.';

	/// en: 'The shops and services nearby could not be loaded.'
	String get aroundError => 'The shops and services nearby could not be loaded.';

	/// en: 'No connection: the shops and services nearby will show once you are online.'
	String get aroundOffline => 'No connection: the shops and services nearby will show once you are online.';

	/// en: 'On site'
	String get onSite => 'On site';

	/// en: 'Back to $name'
	String backTo({required Object name}) => 'Back to ${name}';

	/// en: 'Back to the place'
	String get backToPlace => 'Back to the place';

	/// en: 'This shop or service could not be opened: no network, or it is no longer on the map.'
	String get linkError => 'This shop or service could not be opened: no network, or it is no longer on the map.';

	/// en: 'Shops and services'
	String get searchSection => 'Shops and services';

	/// en: 'Looking for shops and services'
	String get searching => 'Looking for shops and services';

	/// en: 'Shops and services are searched online: no network now.'
	String get searchOffline => 'Shops and services are searched online: no network now.';

	late final Translations$poi$add$en add = Translations$poi$add$en.internal(_root);
	late final Translations$poi$cheapest$en cheapest = Translations$poi$cheapest$en.internal(_root);
	late final Translations$poi$trend$en trend = Translations$poi$trend$en.internal(_root);

	/// en: 'Market days'
	String get marketDays => 'Market days';

	late final Translations$poi$vehicles$en vehicles = Translations$poi$vehicles$en.internal(_root);
}

// Path: offlineMaps
class Translations$offlineMaps$en {
	Translations$offlineMaps$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Offline maps'
	String get title => 'Offline maps';

	/// en: 'Before you leave, keep a region on the device: its places to search and choose, its map to see the streets without network.'
	String get intro => 'Before you leave, keep a region on the device: its places to search and choose, its map to see the streets without network.';

	/// en: 'Offline maps are in the app'
	String get webTitle => 'Offline maps are in the app';

	/// en: 'The Android and iOS apps keep regions for the road. In a browser, the map needs the network.'
	String get web => 'The Android and iOS apps keep regions for the road. In a browser, the map needs the network.';

	/// en: 'Offline maps are on the phone'
	String get desktopTitle => 'Offline maps are on the phone';

	/// en: 'The Android and iOS apps keep regions for the road. On a computer, the map needs the network.'
	String get desktop => 'The Android and iOS apps keep regions for the road. On a computer, the map needs the network.';

	/// en: 'The offline maps of this device could not be loaded.'
	String get unreadable => 'The offline maps of this device could not be loaded.';

	/// en: 'No region on this device yet.'
	String get none => 'No region on this device yet.';

	/// en: 'Space used: $size'
	String used({required Object size}) => 'Space used: ${size}';

	/// en: 'Downloading'
	String get downloads => 'Downloading';

	/// en: 'On this device'
	String get installed => 'On this device';

	/// en: 'Suggested'
	String get suggested => 'Suggested';

	/// en: 'Where you are'
	String get here => 'Where you are';

	/// en: '(one) {$n favourite here} (other) {$n favourites here}'
	String favoritesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} favourite here',
		other: '${n} favourites here',
	);

	/// en: 'France'
	String get france => 'France';

	/// en: 'Overseas France'
	String get overseas => 'Overseas France';

	/// en: 'Countries'
	String get countries => 'Countries';

	/// en: 'Download $name, $size'
	String downloadNamed({required Object name, required Object size}) => 'Download ${name}, ${size}';

	/// en: 'Pause'
	String get pause => 'Pause';

	/// en: 'Resume'
	String get resume => 'Resume';

	/// en: 'Stop and remove the download'
	String get cancel => 'Stop and remove the download';

	/// en: 'Waiting for its turn'
	String get waiting => 'Waiting for its turn';

	/// en: '$done of $total'
	String progress({required Object done, required Object total}) => '${done} of ${total}';

	/// en: 'Paused at $done of $total'
	String paused({required Object done, required Object total}) => 'Paused at ${done} of ${total}';

	/// en: 'Checking the file'
	String get verifying => 'Checking the file';

	/// en: 'Stopped: no network. It resumes where it stopped once the network is back.'
	String get failedNetwork => 'Stopped: no network. It resumes where it stopped once the network is back.';

	/// en: 'The server sent something other than the map. Try again later.'
	String get failedServer => 'The server sent something other than the map. Try again later.';

	/// en: 'The file arrived damaged and was removed. Try again.'
	String get failedCorrupt => 'The file arrived damaged and was removed. Try again.';

	/// en: 'Not enough room left on the device. Free some space, then try again.'
	String get failedStorage => 'Not enough room left on the device. Free some space, then try again.';

	/// en: 'Keep the app open while it downloads: it stops when the app goes to the background and resumes when you come back.'
	String get keepOpen => 'Keep the app open while it downloads: it stops when the app goes to the background and resumes when you come back.';

	/// en: 'data from $date'
	String dataOf({required Object date}) => 'data from ${date}';

	/// en: 'Update, $size'
	String update({required Object size}) => 'Update, ${size}';

	/// en: 'Delete $name'
	String deleteNamed({required Object name}) => 'Delete ${name}';

	/// en: 'Delete $name from this device?'
	String deleteTitle({required Object name}) => 'Delete ${name} from this device?';

	/// en: 'It will no longer show without network. You can download it again.'
	String get deleteBody => 'It will no longer show without network. You can download it again.';

	/// en: 'The list of regions needs the network.'
	String get listOffline => 'The list of regions needs the network.';

	/// en: 'List kept from the last connection.'
	String get listCopy => 'List kept from the last connection.';

	/// en: 'To travel without network'
	String get entryHint => 'To travel without network';

	/// en: '(one) {Maps: $n region, $size} (other) {Maps: $n regions, $size}'
	String entryCount({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Maps: ${n} region, ${size}',
		other: 'Maps: ${n} regions, ${size}',
	);

	/// en: 'Offline: downloaded map, $name'
	String noticePack({required Object name}) => 'Offline: downloaded map, ${name}';

	/// en: 'Offline: this area is not downloaded'
	String get noticeOutside => 'Offline: this area is not downloaded';

	/// en: 'Offline: places on the device, the map of this area to download'
	String get noticePlacesOnly => 'Offline: places on the device, the map of this area to download';

	/// en: 'Offline: download a region for next time'
	String get noticeNone => 'Offline: download a region for next time';

	/// en: 'Offline: the map needs the network'
	String get noticeOnline => 'Offline: the map needs the network';

	/// en: 'Places'
	String get placesTitle => 'Places';

	/// en: 'A few megabytes per region: the list, the search, the place pages and the filters work without network.'
	String get placesHint => 'A few megabytes per region: the list, the search, the place pages and the filters work without network.';

	/// en: 'Maps'
	String get mapsTitle => 'Maps';

	/// en: 'Every street, a few hundred megabytes per region: the map shows without network.'
	String get mapsHint => 'Every street, a few hundred megabytes per region: the map shows without network.';

	/// en: 'Places: $names'
	String entryPlaces({required Object names}) => 'Places: ${names}';

	/// en: '(one) {Places: $n region} (other) {Places: $n regions}'
	String entryPlacesCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Places: ${n} region',
		other: 'Places: ${n} regions',
	);
}

// Path: regions
class Translations$regions$en {
	Translations$regions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Which places to keep on this device?'
	String get pickerTitle => 'Which places to keep on this device?';

	/// en: 'Each region downloads once, then updates in small pieces. You can add or remove regions later in Offline maps.'
	String get pickerIntro => 'Each region downloads once, then updates in small pieces. You can add or remove regions later in Offline maps.';

	/// en: 'Near you: $name'
	String nearYou({required Object name}) => 'Near you: ${name}';

	/// en: 'Find my region'
	String get findMine => 'Find my region';

	/// en: 'Looking for your region'
	String get locating => 'Looking for your region';

	/// en: 'No Lunaway region around you yet'
	String get notCovered => 'No Lunaway region around you yet';

	/// en: 'All of France'
	String get wholeFrance => 'All of France';

	/// en: 'Show the regions of France'
	String get showFrance => 'Show the regions of France';

	/// en: 'Hide the regions of France'
	String get hideFrance => 'Hide the regions of France';

	/// en: '(one) {$count place, $size} (other) {$count places, $size}'
	String packInfo({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${count} place, ${size}',
		other: '${count} places, ${size}',
	);

	/// en: 'No pack: places come with the updates, size unknown'
	String get noPack => 'No pack: places come with the updates, size unknown';

	/// en: 'Download, $size'
	String download({required Object size}) => 'Download, ${size}';

	/// en: 'The server does not offer regions yet: Lunaway keeps all of France.'
	String get unavailable => 'The server does not offer regions yet: Lunaway keeps all of France.';

	/// en: 'The list of regions needs the network.'
	String get listFailed => 'The list of regions needs the network.';

	/// en: 'Choose the regions'
	String get choose => 'Choose the regions';

	/// en: 'No region kept: the map has no places offline.'
	String get noneKept => 'No region kept: the map has no places offline.';

	/// en: 'Add or remove regions'
	String get change => 'Add or remove regions';

	/// en: 'Remove $name'
	String removeNamed({required Object name}) => 'Remove ${name}';

	/// en: '$name: places removed from this device'
	String removed({required Object name}) => '${name}: places removed from this device';

	/// en: 'Downloading, $done of $total'
	String downloading({required Object done, required Object total}) => 'Downloading, ${done} of ${total}';

	/// en: '(one) {Updating, $count place} (other) {Updating, $count places}'
	String updating({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Updating, ${count} place',
		other: 'Updating, ${count} places',
	);

	/// en: 'waiting for its download'
	String get waiting => 'waiting for its download';

	/// en: 'Downloading the places: $name'
	String downloadingNamed({required Object name}) => 'Downloading the places: ${name}';

	/// en: 'updated $when'
	String updated({required Object when}) => 'updated ${when}';

	/// en: '$name: keep its places offline?'
	String offerTitle({required Object name}) => '${name}: keep its places offline?';

	/// en: 'Download this region'
	String get downloadThis => 'Download this region';

	/// en: '$name is not on this device'
	String notHere({required Object name}) => '${name} is not on this device';

	/// en: 'Update over mobile data'
	String get updatesOnMobile => 'Update over mobile data';

	/// en: 'Otherwise the regions already downloaded update on Wi-Fi. A new download goes over any network.'
	String get updatesOnMobileHint => 'Otherwise the regions already downloaded update on Wi-Fi. A new download goes over any network.';
}

// Path: roadReport
class Translations$roadReport$en {
	Translations$roadReport$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Report a problem on the road'
	String get actionHint => 'Report a problem on the road';

	/// en: 'What do you see on the road?'
	String get title => 'What do you see on the road?';

	/// en: 'Your report warns other travellers. When two trusted accounts report the same thing, routes avoid it. Police checks are not reported.'
	String get intro => 'Your report warns other travellers. When two trusted accounts report the same thing, routes avoid it. Police checks are not reported.';

	late final Translations$roadReport$kinds$en kinds = Translations$roadReport$kinds$en.internal(_root);

	/// en: 'Signed height: $value'
	String height({required Object value}) => 'Signed height: ${value}';

	/// en: 'Report'
	String get send => 'Report';

	/// en: 'Thank you: other travellers are warned.'
	String get sent => 'Thank you: other travellers are warned.';

	/// en: 'Still there'
	String get stillThere => 'Still there';

	/// en: 'It's over'
	String get over => 'It\'s over';

	/// en: 'Thank you: noted.'
	String get overSent => 'Thank you: noted.';

	/// en: 'Report a problem here'
	String get fromMap => 'Report a problem here';

	/// en: 'No report here'
	String get notHereTitle => 'No report here';

	/// en: '10 cm lower'
	String get lower => '10 cm lower';

	/// en: '10 cm higher'
	String get higher => '10 cm higher';

	/// en: 'You just passed: $what. Still there?'
	String passed({required Object what}) => 'You just passed: ${what}. Still there?';

	/// en: 'Lunaway takes reports where an official feed cross-checks them: $countries.'
	String notHere({required Object countries}) => 'Lunaway takes reports where an official feed cross-checks them: ${countries}.';
}

// Path: countries
class Translations$countries$en {
	Translations$countries$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Andorra'
	String get ad => 'Andorra';

	/// en: 'Austria'
	String get at => 'Austria';

	/// en: 'Åland'
	String get ax => 'Åland';

	/// en: 'Belgium'
	String get be => 'Belgium';

	/// en: 'Switzerland'
	String get ch => 'Switzerland';

	/// en: 'Czechia'
	String get cz => 'Czechia';

	/// en: 'Germany'
	String get de => 'Germany';

	/// en: 'Denmark'
	String get dk => 'Denmark';

	/// en: 'Western Sahara'
	String get eh => 'Western Sahara';

	/// en: 'Spain'
	String get es => 'Spain';

	/// en: 'Finland'
	String get fi => 'Finland';

	/// en: 'France'
	String get fr => 'France';

	/// en: 'United Kingdom'
	String get gb => 'United Kingdom';

	/// en: 'Gibraltar'
	String get gi => 'Gibraltar';

	/// en: 'Greece'
	String get gr => 'Greece';

	/// en: 'Croatia'
	String get hr => 'Croatia';

	/// en: 'Ireland'
	String get ie => 'Ireland';

	/// en: 'Italy'
	String get it => 'Italy';

	/// en: 'Liechtenstein'
	String get li => 'Liechtenstein';

	/// en: 'Luxembourg'
	String get lu => 'Luxembourg';

	/// en: 'Morocco'
	String get ma => 'Morocco';

	/// en: 'Monaco'
	String get mc => 'Monaco';

	/// en: 'Netherlands'
	String get nl => 'Netherlands';

	/// en: 'Norway'
	String get no => 'Norway';

	/// en: 'Poland'
	String get pl => 'Poland';

	/// en: 'Portugal'
	String get pt => 'Portugal';

	/// en: 'Sweden'
	String get se => 'Sweden';

	/// en: 'Slovenia'
	String get si => 'Slovenia';

	/// en: 'Svalbard'
	String get sj => 'Svalbard';

	/// en: 'San Marino'
	String get sm => 'San Marino';

	/// en: 'Vatican City'
	String get va => 'Vatican City';
}

// Path: areas
class Translations$areas$en {
	Translations$areas$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Auvergne-Rhône-Alpes'
	String get ara => 'Auvergne-Rhône-Alpes';

	/// en: 'Bourgogne-Franche-Comté'
	String get bfc => 'Bourgogne-Franche-Comté';

	/// en: 'Brittany'
	String get bre => 'Brittany';

	/// en: 'Centre-Val de Loire'
	String get cvl => 'Centre-Val de Loire';

	/// en: 'Corsica'
	String get cor => 'Corsica';

	/// en: 'Grand Est'
	String get ges => 'Grand Est';

	/// en: 'Hauts-de-France'
	String get hdf => 'Hauts-de-France';

	/// en: 'Île-de-France'
	String get idf => 'Île-de-France';

	/// en: 'Normandy'
	String get nor => 'Normandy';

	/// en: 'Nouvelle-Aquitaine'
	String get naq => 'Nouvelle-Aquitaine';

	/// en: 'Occitania'
	String get occ => 'Occitania';

	/// en: 'Pays de la Loire'
	String get pdl => 'Pays de la Loire';

	/// en: 'Provence-Alpes-Côte d'Azur'
	String get pac => 'Provence-Alpes-Côte d\'Azur';

	/// en: 'Guadeloupe'
	String get gp => 'Guadeloupe';

	/// en: 'Martinique'
	String get mq => 'Martinique';

	/// en: 'French Guiana'
	String get gf => 'French Guiana';

	/// en: 'Réunion'
	String get re => 'Réunion';

	/// en: 'Mayotte'
	String get yt => 'Mayotte';

	/// en: 'France, outside any commune'
	String get franceRest => 'France, outside any commune';
}

// Path: search.addressKind
class Translations$search$addressKind$en {
	Translations$search$addressKind$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Address'
	String get houseNumber => 'Address';

	/// en: 'Street'
	String get street => 'Street';

	/// en: 'Locality'
	String get locality => 'Locality';

	/// en: 'Town'
	String get town => 'Town';

	/// en: 'Postcode'
	String get postcode => 'Postcode';

	/// en: 'Region'
	String get region => 'Region';
}

// Path: place.inclusions
class Translations$place$inclusions$en {
	Translations$place$inclusions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'services'
	String get services => 'services';

	/// en: 'tourist tax'
	String get touristTax => 'tourist tax';

	/// en: 'electricity'
	String get electricity => 'electricity';
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

// Path: sources.extcom
class Translations$sources$extcom$en {
	Translations$sources$extcom$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'External community source'
	String get label => 'External community source';

	/// en: 'External'
	String get short => 'External';
}

// Path: hours.codes
class Translations$hours$codes$en {
	Translations$hours$codes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Mon'
	String get mo => 'Mon';

	/// en: 'Tue'
	String get tu => 'Tue';

	/// en: 'Wed'
	String get we => 'Wed';

	/// en: 'Thu'
	String get th => 'Thu';

	/// en: 'Fri'
	String get fr => 'Fri';

	/// en: 'Sat'
	String get sa => 'Sat';

	/// en: 'Sun'
	String get su => 'Sun';

	/// en: 'public holidays'
	String get ph => 'public holidays';

	/// en: 'school holidays'
	String get sh => 'school holidays';

	/// en: 'closed'
	String get off => 'closed';

	/// en: 'closed'
	String get closed => 'closed';

	/// en: 'sunrise'
	String get sunrise => 'sunrise';

	/// en: 'sunset'
	String get sunset => 'sunset';
}

// Path: hours.months
class Translations$hours$months$en {
	Translations$hours$months$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Jan'
	String get jan => 'Jan';

	/// en: 'Feb'
	String get feb => 'Feb';

	/// en: 'Mar'
	String get mar => 'Mar';

	/// en: 'Apr'
	String get apr => 'Apr';

	/// en: 'May'
	String get may => 'May';

	/// en: 'Jun'
	String get jun => 'Jun';

	/// en: 'Jul'
	String get jul => 'Jul';

	/// en: 'Aug'
	String get aug => 'Aug';

	/// en: 'Sep'
	String get sep => 'Sep';

	/// en: 'Oct'
	String get oct => 'Oct';

	/// en: 'Nov'
	String get nov => 'Nov';

	/// en: 'Dec'
	String get dec => 'Dec';
}

// Path: navigation.preview
class Translations$navigation$preview$en {
	Translations$navigation$preview$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'To $name'
	String titleTo({required Object name}) => 'To ${name}';

	/// en: 'Point on the map'
	String get titlePoint => 'Point on the map';

	late final Translations$navigation$preview$departure$en departure = Translations$navigation$preview$departure$en.internal(_root);

	/// en: 'Computing a route for your vehicle'
	String get computing => 'Computing a route for your vehicle';

	/// en: 'Let's go!'
	String get start => 'Let\'s go!';

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

	/// en: 'Timed at $speed max'
	String cruise({required Object speed}) => 'Timed at ${speed} max';

	/// en: 'Avoid'
	String get avoid => 'Avoid';

	/// en: 'Tolls'
	String get avoidTolls => 'Tolls';

	/// en: 'Motorways'
	String get avoidMotorways => 'Motorways';

	/// en: 'Ferries'
	String get avoidFerries => 'Ferries';

	/// en: 'Unpaved roads'
	String get avoidUnpaved => 'Unpaved roads';

	/// en: 'Turn by turn'
	String get roadbook => 'Turn by turn';

	/// en: 'Show the directions'
	String get roadbookShow => 'Show the directions';

	/// en: 'Hide the directions'
	String get roadbookHide => 'Hide the directions';

	/// en: 'Road data from $date'
	String dataOf({required Object date}) => 'Road data from ${date}';

	/// en: '© OpenStreetMap contributors'
	String get attributionOsm => '© OpenStreetMap contributors';

	/// en: 'IGN, BD TOPO, $date edition'
	String attributionIgn({required Object date}) => 'IGN, BD TOPO, ${date} edition';

	/// en: 'Open in…'
	String get otherApps => 'Open in…';

	/// en: 'Back'
	String get back => 'Back';

	late final Translations$navigation$preview$moved$en moved = Translations$navigation$preview$moved$en.internal(_root);
}

// Path: navigation.stops
class Translations$navigation$stops$en {
	Translations$navigation$stops$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Stops'
	String get title => 'Stops';

	/// en: 'Add as a stop'
	String get add => 'Add as a stop';

	/// en: 'Add as a stop · +$minutes min'
	String addCost({required Object minutes}) => 'Add as a stop · +${minutes} min';

	/// en: 'Add as a stop · no detour'
	String get addFree => 'Add as a stop · no detour';

	/// en: 'Add as a stop · working out the detour'
	String get quoting => 'Add as a stop · working out the detour';

	/// en: 'No route through this point for your vehicle.'
	String get noRoute => 'No route through this point for your vehicle.';

	/// en: 'Five stops at most.'
	String get full => 'Five stops at most.';

	/// en: 'Go there directly'
	String get goDirectly => 'Go there directly';

	/// en: 'See the details'
	String get openCard => 'See the details';

	/// en: 'Point on the map'
	String get point => 'Point on the map';

	/// en: 'Remove the stop'
	String get remove => 'Remove the stop';

	/// en: 'Drag to change the order'
	String get reorder => 'Drag to change the order';

	/// en: 'Stop added'
	String get added => 'Stop added';

	/// en: 'Stop removed'
	String get removed => 'Stop removed';

	/// en: 'Stops reordered'
	String get moved => 'Stops reordered';

	/// en: 'New destination'
	String get destinationChanged => 'New destination';

	/// en: 'The route could not be changed.'
	String get failed => 'The route could not be changed.';

	/// en: 'The detour could not be worked out.'
	String get noQuote => 'The detour could not be worked out.';

	/// en: 'No network to work out the detour.'
	String get offline => 'No network to work out the detour.';
}

// Path: navigation.legs
class Translations$navigation$legs$en {
	Translations$navigation$legs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'All'
	String get all => 'All';

	/// en: '$name · $time · $distance'
	String stop({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}';

	/// en: 'Stop $number: $name, around $time, in $distance'
	String stopSaid({required Object number, required Object name, required Object time, required Object distance}) => 'Stop ${number}: ${name}, around ${time}, in ${distance}';

	/// en: 'Destination · $name · $time'
	String arrival({required Object name, required Object time}) => 'Destination · ${name} · ${time}';

	/// en: 'Destination: $name, around $time'
	String arrivalSaid({required Object name, required Object time}) => 'Destination: ${name}, around ${time}';

	/// en: 'Remove stop $number, $name'
	String remove({required Object number, required Object name}) => 'Remove stop ${number}, ${name}';
}

// Path: navigation.fuel
class Translations$navigation$fuel$en {
	Translations$navigation$fuel$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$price €/L'
	String price({required Object price}) => '${price} €/L';

	/// en: '$price €/L including the detour'
	String withDetour({required Object price}) => '${price} €/L including the detour';

	/// en: '+$distance · +$minutes min'
	String detour({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min';

	/// en: 'on the route'
	String get onRoute => 'on the route';

	/// en: 'Open'
	String get open => 'Open';

	/// en: 'Closed'
	String get closed => 'Closed';

	/// en: 'Hours unknown'
	String get unknownHours => 'Hours unknown';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Fuel station'
	String get station => 'Fuel station';

	/// en: 'No station selling this fuel near the route.'
	String get empty => 'No station selling this fuel near the route.';

	/// en: 'The stations could not be loaded.'
	String get failed => 'The stations could not be loaded.';

	/// en: 'Detours estimated from the distance to the route.'
	String get estimated => 'Detours estimated from the distance to the route.';

	/// en: 'Prices: French Ministry of the Economy (data.economie.gouv.fr)'
	String get attribution => 'Prices: French Ministry of the Economy (data.economie.gouv.fr)';

	/// en: '$n min ago'
	String minutesAgo({required Object n}) => '${n} min ago';

	/// en: '$n h ago'
	String hoursAgo({required Object n}) => '${n} h ago';

	/// en: '$n d ago'
	String daysAgo({required Object n}) => '${n} d ago';
}

// Path: navigation.onTheWay
class Translations$navigation$onTheWay$en {
	Translations$navigation$onTheWay$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'On the way'
	String get title => 'On the way';

	late final Translations$navigation$onTheWay$categories$en categories = Translations$navigation$onTheWay$categories$en.internal(_root);

	/// en: '$fuel, from your vehicle'
	String fuelOfVehicle({required Object fuel}) => '${fuel}, from your vehicle';

	/// en: 'Another fuel'
	String get otherFuel => 'Another fuel';

	/// en: 'Keep as my fuel'
	String get keepFuel => 'Keep as my fuel';

	/// en: '$fuel kept for your vehicle.'
	String fuelKept({required Object fuel}) => '${fuel} kept for your vehicle.';

	/// en: 'The fuel could not be kept.'
	String get keepFuelFailed => 'The fuel could not be kept.';

	/// en: 'Searching along the route'
	String get loading => 'Searching along the route';

	/// en: 'Nothing found on this route'
	String get empty => 'Nothing found on this route';

	/// en: 'Try another kind, or open the list again further along the road.'
	String get emptyHint => 'Try another kind, or open the list again further along the road.';

	/// en: 'The list could not be loaded.'
	String get failed => 'The list could not be loaded.';

	/// en: 'No network: the list will come back with the connection.'
	String get offline => 'No network: the list will come back with the connection.';

	/// en: 'Many searches in a row: try again in a few minutes.'
	String get rateLimited => 'Many searches in a row: try again in a few minutes.';

	/// en: 'Nothing in the next $distance.'
	String nearNone({required Object distance}) => 'Nothing in the next ${distance}.';

	/// en: 'Further on ($n)'
	String further({required Object n}) => 'Further on (${n})';

	/// en: 'Show more'
	String get more => 'Show more';

	/// en: 'The rest could not be loaded.'
	String get moreFailed => 'The rest could not be loaded.';

	/// en: 'in $distance'
	String ahead({required Object distance}) => 'in ${distance}';

	/// en: '$distance from the route'
	String offRoute({required Object distance}) => '${distance} from the route';

	/// en: 'by the road'
	String get byTheRoad => 'by the road';

	/// en: 'Add · +$minutes min'
	String addCost({required Object minutes}) => 'Add · +${minutes} min';

	/// en: 'Add · no detour'
	String get addFree => 'Add · no detour';

	/// en: 'Open when you pass, around $time'
	String openAt({required Object time}) => 'Open when you pass, around ${time}';

	/// en: 'Closed when you pass, around $time'
	String closedAt({required Object time}) => 'Closed when you pass, around ${time}';

	/// en: 'Closed when you pass around $time, opens at $opens'
	String closedOpensAt({required Object time, required Object opens}) => 'Closed when you pass around ${time}, opens at ${opens}';

	/// en: '$price a night'
	String perNight({required Object price}) => '${price} a night';

	/// en: 'Photo: $source'
	String photoFrom({required Object source}) => 'Photo: ${source}';

	/// en: 'Services: $list'
	String servicesList({required Object list}) => 'Services: ${list}';

	/// en: 'Places: Lunaway and the sources named on each place page'
	String get placesCredit => 'Places: Lunaway and the sources named on each place page';
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

	/// en: 'Routes are computed on Lunaway's server. Without network, "Open in…" hands the trip to a navigation app that keeps its own maps.'
	String get offlineHint => 'Routes are computed on Lunaway\'s server. Without network, "Open in…" hands the trip to a navigation app that keeps its own maps.';

	/// en: 'Too many route requests'
	String get rateLimitedTitle => 'Too many route requests';

	/// en: 'Try again in $seconds s.'
	String rateLimitedHint({required Object seconds}) => 'Try again in ${seconds} s.';

	/// en: 'Routing is down'
	String get unavailableTitle => 'Routing is down';

	/// en: 'The route service is stopped for now. Try again later.'
	String get unavailableHint => 'The route service is stopped for now. Try again later.';

	/// en: 'No route here'
	String get refusedTitle => 'No route here';

	/// en: 'Lunaway could not compute a route for this request: check the destination, the length of the trip and the vehicle's figures.'
	String get refusedHint => 'Lunaway could not compute a route for this request: check the destination, the length of the trip and the vehicle\'s figures.';

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

// Path: navigation.noRoute
class Translations$navigation$noRoute$en {
	Translations$navigation$noRoute$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Your vehicle cannot leave from here'
	String get originUnreachable => 'Your vehicle cannot leave from here';

	/// en: 'Your vehicle cannot leave from here: $limit'
	String originUnreachableBy({required Object limit}) => 'Your vehicle cannot leave from here: ${limit}';

	/// en: 'Destination out of reach for your vehicle'
	String get destinationUnreachable => 'Destination out of reach for your vehicle';

	/// en: 'Destination out of reach for your vehicle: $limit'
	String destinationUnreachableBy({required Object limit}) => 'Destination out of reach for your vehicle: ${limit}';

	/// en: 'Stop $n out of reach for your vehicle'
	String waypointUnreachable({required Object n}) => 'Stop ${n} out of reach for your vehicle';

	/// en: 'Stop $n out of reach for your vehicle: $limit'
	String waypointUnreachableBy({required Object n, required Object limit}) => 'Stop ${n} out of reach for your vehicle: ${limit}';

	/// en: 'No way through for your vehicle between the stops'
	String get blockedOnTheWay => 'No way through for your vehicle between the stops';

	/// en: 'No way through for your vehicle between the stops: $limit'
	String blockedOnTheWayBy({required Object limit}) => 'No way through for your vehicle between the stops: ${limit}';

	/// en: 'Each stop can be reached, but every road between them passes a limit your vehicle exceeds.'
	String get blockedHint => 'Each stop can be reached, but every road between them passes a limit your vehicle exceeds.';

	/// en: 'No road leads away from your position'
	String get notConnectedOrigin => 'No road leads away from your position';

	/// en: 'No road leads to the destination'
	String get notConnectedDestination => 'No road leads to the destination';

	/// en: 'No road leads to stop $n'
	String notConnectedWaypoint({required Object n}) => 'No road leads to stop ${n}';

	/// en: 'No road joins your stops'
	String get notConnectedTrip => 'No road joins your stops';

	/// en: 'Whatever the vehicle: an island without a car ferry, or a way closed to traffic.'
	String get notConnectedHint => 'Whatever the vehicle: an island without a car ferry, or a way closed to traffic.';

	/// en: 'Your position is outside the area routes cover'
	String get outsideOrigin => 'Your position is outside the area routes cover';

	/// en: 'Destination outside the area routes cover'
	String get outsideDestination => 'Destination outside the area routes cover';

	/// en: 'Stop $n outside the area routes cover'
	String outsideWaypoint({required Object n}) => 'Stop ${n} outside the area routes cover';

	/// en: 'Lunaway computes routes in these countries: $countries.'
	String outsideHint({required Object countries}) => 'Lunaway computes routes in these countries: ${countries}.';

	/// en: 'Lunaway does not compute routes in this country yet.'
	String get outsideHintUnknown => 'Lunaway does not compute routes in this country yet.';

	/// en: 'Your position is too far from a road'
	String get noRoadOrigin => 'Your position is too far from a road';

	/// en: 'Destination too far from a road'
	String get noRoadDestination => 'Destination too far from a road';

	/// en: 'Stop $n too far from a road'
	String noRoadWaypoint({required Object n}) => 'Stop ${n} too far from a road';

	/// en: 'No road your vehicle may take within 5 km of this point.'
	String get noRoadHint => 'No road your vehicle may take within 5 km of this point.';

	/// en: 'Trip too long'
	String get tooLong => 'Trip too long';

	/// en: '$trip in a straight line from stop to stop: Lunaway computes trips of $max at most.'
	String tooLongHint({required Object trip, required Object max}) => '${trip} in a straight line from stop to stop: Lunaway computes trips of ${max} at most.';

	/// en: 'Your vehicle: $value'
	String vehicleValue({required Object value}) => 'Your vehicle: ${value}';

	late final Translations$navigation$noRoute$limit$en limit = Translations$navigation$noRoute$limit$en.internal(_root);

	/// en: 'Edit the vehicle'
	String get editVehicle => 'Edit the vehicle';

	/// en: 'Allow unpaved roads'
	String get allowUnpaved => 'Allow unpaved roads';

	/// en: 'Remove stop $n'
	String removeStop({required Object n}) => 'Remove stop ${n}';

	/// en: 'Remove the stop "$name"'
	String removeStopNamed({required Object name}) => 'Remove the stop "${name}"';

	/// en: 'See the places around the destination'
	String get placesAround => 'See the places around the destination';

	/// en: 'Or pick another arrival: long press on the map, then "Go there directly".'
	String get moveDestination => 'Or pick another arrival: long press on the map, then "Go there directly".';

	/// en: 'For another stop: tap the map close up, or long press, then "Add as a stop".'
	String get moveStop => 'For another stop: tap the map close up, or long press, then "Add as a stop".';

	/// en: 'The start is your position: get to a road your vehicle may take, then try again.'
	String get moveOrigin => 'The start is your position: get to a road your vehicle may take, then try again.';

	/// en: 'Pick a destination in one of these countries.'
	String get pickInside => 'Pick a destination in one of these countries.';

	/// en: 'Pick a closer destination, or make the trip in several legs.'
	String get shorter => 'Pick a closer destination, or make the trip in several legs.';
}

// Path: navigation.ferry
class Translations$navigation$ferry$en {
	Translations$navigation$ferry$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '(one) {Ferry crossing} (other) {$n ferry crossings}'
	String title({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Ferry crossing',
		other: '${n} ferry crossings',
	);

	/// en: 'Ferry'
	String get unnamed => 'Ferry';

	/// en: 'Ferry $name'
	String named({required Object name}) => 'Ferry ${name}';

	/// en: 'Ports: $ports'
	String ports({required Object ports}) => 'Ports: ${ports}';

	/// en: 'Boarding: $from · Landing: $to'
	String countries({required Object from, required Object to}) => 'Boarding: ${from} · Landing: ${to}';

	/// en: 'Country: $country'
	String country({required Object country}) => 'Country: ${country}';

	/// en: '$distance from the start · $sea at sea, about $duration'
	String where({required Object distance, required Object sea, required Object duration}) => '${distance} from the start · ${sea} at sea, about ${duration}';

	/// en: 'The destination cannot be reached without a ferry: the route takes one, even though you avoid ferries.'
	String get needed => 'The destination cannot be reached without a ferry: the route takes one, even though you avoid ferries.';
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

	late final Translations$navigation$warning$localAccess$en localAccess = Translations$navigation$warning$localAccess$en.internal(_root);
}

// Path: navigation.roadEvents
class Translations$navigation$roadEvents$en {
	Translations$navigation$roadEvents$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Works and closures'
	String get title => 'Works and closures';

	/// en: 'No works or closures known on this route.'
	String get none => 'No works or closures known on this route.';

	/// en: 'Works and closures: the sources have not been read recently.'
	String get stale => 'Works and closures: the sources have not been read recently.';

	/// en: '(one) {Route planned around a closure: $names} (other) {Route planned around $n closures: $names}'
	String avoided({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Route planned around a closure: ${names}',
		other: 'Route planned around ${n} closures: ${names}',
	);

	/// en: '$distance from the start'
	String atDistance({required Object distance}) => '${distance} from the start';

	/// en: '(one) {And $n more on the route} (other) {And $n more on the route}'
	String more({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'And ${n} more on the route',
		other: 'And ${n} more on the route',
	);

	/// en: 'Road closed'
	String get classClosure => 'Road closed';

	/// en: 'Works'
	String get classWorks => 'Works';

	/// en: 'Lanes closed'
	String get classLaneRestriction => 'Lanes closed';

	/// en: 'Size limit'
	String get classVehicleLimit => 'Size limit';

	/// en: 'Detour signposted'
	String get classDetour => 'Detour signposted';

	/// en: 'uncertain position, maybe on the route'
	String get reasonUnmatched => 'uncertain position, maybe on the route';

	/// en: 'source not read recently'
	String get reasonStale => 'source not read recently';

	/// en: 'outside its assumed hours'
	String get reasonOutsideHours => 'outside its assumed hours';

	/// en: 'for heavy goods vehicles'
	String get reasonGoodsVehicles => 'for heavy goods vehicles';

	/// en: 'reported by a single traveller'
	String get reasonUnconfirmed => 'reported by a single traveller';

	/// en: 'old report'
	String get reasonAged => 'old report';

	/// en: 'the route starts or ends inside it'
	String get reasonInside => 'the route starts or ends inside it';

	/// en: 'with little margin'
	String get reasonNearLimit => 'with little margin';

	/// en: 'over your vehicle's limit'
	String get reasonOverLimit => 'over your vehicle\'s limit';
}

// Path: navigation.marks
class Translations$navigation$marks$en {
	Translations$navigation$marks$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Legend'
	String get legend => 'Legend';

	/// en: 'Fold the legend'
	String get legendHide => 'Fold the legend';

	/// en: 'Start'
	String get kindOrigin => 'Start';

	/// en: 'Destination'
	String get kindDestination => 'Destination';

	/// en: 'Stop'
	String get kindStop => 'Stop';

	/// en: 'Road closed'
	String get kindClosure => 'Road closed';

	/// en: 'Works'
	String get kindWorks => 'Works';

	/// en: 'Lanes closed'
	String get kindLanes => 'Lanes closed';

	/// en: 'Height limit'
	String get kindClearance => 'Height limit';

	/// en: 'Weight limit'
	String get kindWeight => 'Weight limit';

	/// en: 'Other limit (width, length, ban)'
	String get kindLimit => 'Other limit (width, length, ban)';

	/// en: 'Fuel station'
	String get kindFuel => 'Fuel station';

	/// en: 'Place near the route'
	String get kindPlace => 'Place near the route';

	/// en: 'Marks close together, grouped'
	String get groupLegend => 'Marks close together, grouped';

	/// en: 'Danger zone'
	String get zoneLegend => 'Danger zone';

	/// en: 'Danger zones: $source, list of $date'
	String zonesFrom({required Object source, required Object date}) => 'Danger zones: ${source}, list of ${date}';

	/// en: '(one) {$n mark} (other) {$n marks}'
	String group({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} mark',
		other: '${n} marks',
	);

	/// en: 'Zoom in to see each one'
	String get groupHint => 'Zoom in to see each one';

	/// en: '$kind: $n'
	String count({required Object kind, required Object n}) => '${kind}: ${n}';

	/// en: 'Stop $n'
	String stop({required Object n}) => 'Stop ${n}';

	/// en: 'Starting point'
	String get origin => 'Starting point';

	/// en: 'Near the route'
	String get nearRoute => 'Near the route';

	/// en: 'The route goes around it'
	String get avoided => 'The route goes around it';

	/// en: 'Stops every route'
	String get blocking => 'Stops every route';

	/// en: 'See it in the list'
	String get showInList => 'See it in the list';

	/// en: 'Show all'
	String get showAll => 'Show all';

	/// en: 'show on the map'
	String get onMap => 'show on the map';

	/// en: '$price €'
	String price({required Object price}) => '${price} €';
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

	/// en: 'Road closed in $distance'
	String eventClosure({required Object distance}) => 'Road closed in ${distance}';

	/// en: 'Size limited by roadworks in $distance'
	String eventLimit({required Object distance}) => 'Size limited by roadworks in ${distance}';

	/// en: '$source, as of $time'
	String eventSource({required Object source, required Object time}) => '${source}, as of ${time}';

	/// en: '$source, as of $day at $time'
	String eventSourceOn({required Object source, required Object day, required Object time}) => '${source}, as of ${day} at ${time}';

	/// en: '(one) {Route planned around a closure} (other) {Route planned around $n closures}'
	String avoidedClosures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: 'Route planned around a closure',
		other: 'Route planned around ${n} closures',
	);

	/// en: '$what in $distance'
	String roadEventAhead({required Object what, required Object distance}) => '${what} in ${distance}';

	/// en: 'Road closed in $distance: no network to look for another way'
	String closureOffline({required Object distance}) => 'Road closed in ${distance}: no network to look for another way';

	/// en: 'Road closed in $distance: no other way yet'
	String closureFailed({required Object distance}) => 'Road closed in ${distance}: no other way yet';

	/// en: 'Turn the voice on'
	String get voiceOn => 'Turn the voice on';

	/// en: 'Turn the voice off'
	String get voiceOff => 'Turn the voice off';

	/// en: 'Whole route'
	String get overview => 'Whole route';

	/// en: 'Recenter'
	String get recenter => 'Recenter';

	/// en: 'End'
	String get end => 'End';

	/// en: 'End the guidance?'
	String get endTitle => 'End the guidance?';

	/// en: 'End'
	String get endConfirm => 'End';

	/// en: 'Keep going'
	String get endKeep => 'Keep going';

	/// en: 'Stop the guidance?'
	String get stopTitle => 'Stop the guidance?';

	/// en: 'Stop'
	String get stopConfirm => 'Stop';

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

	late final Translations$navigation$guidance$notificationWhy$en notificationWhy = Translations$navigation$guidance$notificationWhy$en.internal(_root);

	/// en: 'Position unavailable: check that the device's location is on for Lunaway.'
	String get positionLost => 'Position unavailable: check that the device\'s location is on for Lunaway.';

	/// en: 'Last position received $minutes min ago: the arrival time rests on it.'
	String positionStale({required Object minutes}) => 'Last position received ${minutes} min ago: the arrival time rests on it.';

	/// en: 'Danger zone in $distance'
	String dangerZone({required Object distance}) => 'Danger zone in ${distance}';

	/// en: 'Danger zone, $distance left'
	String inDangerZone({required Object distance}) => 'Danger zone, ${distance} left';

	/// en: 'Speed camera in $distance'
	String cameraAhead({required Object distance}) => 'Speed camera in ${distance}';

	/// en: 'Speed camera in $distance, $limit'
	String cameraLimit({required Object distance, required Object limit}) => 'Speed camera in ${distance}, ${limit}';

	/// en: 'Estimated limit'
	String get limitEstimated => 'Estimated limit';

	/// en: 'over the limit'
	String get overLimit => 'over the limit';

	/// en: '$source, list of $date'
	String enforcementSource({required Object source, required Object date}) => '${source}, list of ${date}';

	/// en: 'Simulated drive: a demonstration without GPS'
	String get demoDrive => 'Simulated drive: a demonstration without GPS';

	late final Translations$navigation$guidance$places$en places = Translations$navigation$guidance$places$en.internal(_root);
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

	late final Translations$navigation$voice$moved$en moved = Translations$navigation$voice$moved$en.internal(_root);

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

	/// en: '(one) {$metres.$cm metres} (other) {$metres.$cm metres}'
	String size({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '${metres}.${cm} metres',
		other: '${metres}.${cm} metres',
	);

	/// en: '(one) {$metres metre} (other) {$metres metres}'
	String sizeWhole({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '${metres} metre',
		other: '${metres} metres',
	);

	/// en: 'Speed limit $limit.'
	String overSpeed({required Object limit}) => 'Speed limit ${limit}.';

	/// en: 'Danger zone in $distance.'
	String dangerZone({required Object distance}) => 'Danger zone in ${distance}.';

	/// en: 'Danger zone.'
	String get inDangerZone => 'Danger zone.';

	/// en: 'Speed camera in $distance.'
	String camera({required Object distance}) => 'Speed camera in ${distance}.';

	late final Translations$navigation$voice$localAccess$en localAccess = Translations$navigation$voice$localAccess$en.internal(_root);

	/// en: '(one) {$n tonne} (other) {$n tonnes}'
	String tonnes({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count,
		one: '${n} tonne',
		other: '${n} tonnes',
	);
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

	/// en: 'With the device's own voice'
	String get voiceHint => 'With the device\'s own voice';

	/// en: 'Distances'
	String get units => 'Distances';

	/// en: 'Kilometres'
	String get metric => 'Kilometres';

	/// en: 'Miles'
	String get imperial => 'Miles';

	/// en: 'Speed limit'
	String get speedLimit => 'Speed limit';

	/// en: 'The limit for your vehicle beside the speed during guidance; an estimate shows in grey.'
	String get speedLimitHint => 'The limit for your vehicle beside the speed during guidance; an estimate shows in grey.';

	/// en: 'Spoken speed alerts'
	String get speedSound => 'Spoken speed alerts';

	/// en: 'A word when you drive over the limit, and before a danger zone where the country allows them. Off: the sign and the banners only.'
	String get speedSoundHint => 'A word when you drive over the limit, and before a danger zone where the country allows them. Off: the sign and the banners only.';
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

// Path: translation.from
class Translations$translation$from$en {
	Translations$translation$from$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Automatically translated from French'
	String get fr => 'Automatically translated from French';

	/// en: 'Automatically translated from English'
	String get en => 'Automatically translated from English';

	/// en: 'Automatically translated from German'
	String get de => 'Automatically translated from German';

	/// en: 'Automatically translated from Spanish'
	String get es => 'Automatically translated from Spanish';

	/// en: 'Automatically translated from Italian'
	String get it => 'Automatically translated from Italian';

	/// en: 'Automatically translated from Dutch'
	String get nl => 'Automatically translated from Dutch';

	/// en: 'Automatically translated (original language: $language)'
	String unknown({required Object language}) => 'Automatically translated (original language: ${language})';
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

	/// en: 'Still there: a shop or service'
	String get poiThere => 'Still there: a shop or service';

	/// en: 'Gone: a shop or service'
	String get poiGone => 'Gone: a shop or service';

	/// en: 'New vending machine'
	String get addVendingMachine => 'New vending machine';

	/// en: 'Deletion of an answer about a shop or service'
	String get deletePoiConfirmation => 'Deletion of an answer about a shop or service';

	/// en: 'Road report: $kind'
	String reportRoadEvent({required Object kind}) => 'Road report: ${kind}';

	/// en: 'A road report said over'
	String get clearRoadEvent => 'A road report said over';
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

	/// en: 'Refused: the same machine is already listed within 25 m.'
	String get duplicate => 'Refused: the same machine is already listed within 25 m.';
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

// Path: poi.category
class Translations$poi$category$en {
	Translations$poi$category$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Groceries'
	String get groceries => 'Groceries';

	/// en: 'Food vending machines'
	String get vending => 'Food vending machines';

	/// en: 'Water and dump'
	String get water => 'Water and dump';

	/// en: 'Fuel and energy'
	String get fuel => 'Fuel and energy';

	/// en: 'Health'
	String get health => 'Health';

	/// en: 'Services'
	String get services => 'Services';

	/// en: 'Restaurants and cafés'
	String get food => 'Restaurants and cafés';

	/// en: 'Sights'
	String get sights => 'Sights';
}

// Path: poi.kind
class Translations$poi$kind$en {
	Translations$poi$kind$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Supermarket'
	String get supermarket => 'Supermarket';

	/// en: 'Convenience store'
	String get convenience => 'Convenience store';

	/// en: 'Bakery'
	String get bakery => 'Bakery';

	/// en: 'Butcher'
	String get butcher => 'Butcher';

	/// en: 'Greengrocer'
	String get greengrocer => 'Greengrocer';

	/// en: 'Farm shop'
	String get farmShop => 'Farm shop';

	/// en: 'Market'
	String get marketplace => 'Market';

	/// en: 'Pizza vending machine'
	String get vendingPizza => 'Pizza vending machine';

	/// en: 'Bread vending machine'
	String get vendingBread => 'Bread vending machine';

	/// en: 'Farm produce machine'
	String get vendingFarmProducts => 'Farm produce machine';

	/// en: 'Eggs or milk machine'
	String get vendingEggsMilk => 'Eggs or milk machine';

	/// en: 'Ice machine'
	String get vendingIce => 'Ice machine';

	/// en: 'Food vending machine'
	String get vendingOther => 'Food vending machine';

	/// en: 'Drinking water'
	String get drinkingWater => 'Drinking water';

	/// en: 'Water point'
	String get waterPoint => 'Water point';

	/// en: 'Dump station'
	String get dumpStation => 'Dump station';

	/// en: 'Toilets'
	String get toilets => 'Toilets';

	/// en: 'Showers'
	String get shower => 'Showers';

	/// en: 'Fuel station'
	String get fuelStation => 'Fuel station';

	/// en: 'Charging station'
	String get evCharging => 'Charging station';

	/// en: 'Gas bottles'
	String get gasBottles => 'Gas bottles';

	/// en: 'Pharmacy'
	String get pharmacy => 'Pharmacy';

	/// en: 'Doctor'
	String get doctor => 'Doctor';

	/// en: 'Hospital'
	String get hospital => 'Hospital';

	/// en: 'Vet'
	String get veterinary => 'Vet';

	/// en: 'Laundry'
	String get laundry => 'Laundry';

	/// en: 'Cash machine'
	String get atm => 'Cash machine';

	/// en: 'Post office'
	String get postOffice => 'Post office';

	/// en: 'Tourist office'
	String get touristOffice => 'Tourist office';

	/// en: 'Recycling centre'
	String get recyclingCentre => 'Recycling centre';

	/// en: 'Garage'
	String get carRepair => 'Garage';

	/// en: 'Vehicle wash'
	String get carWash => 'Vehicle wash';

	/// en: 'Motorhome dealer and workshop'
	String get motorhomeShop => 'Motorhome dealer and workshop';

	/// en: 'Camping and outdoor shop'
	String get outdoorShop => 'Camping and outdoor shop';

	/// en: 'Restaurant'
	String get restaurant => 'Restaurant';

	/// en: 'Café'
	String get cafe => 'Café';

	/// en: 'Fast food'
	String get fastFood => 'Fast food';

	/// en: 'Viewpoint'
	String get viewpoint => 'Viewpoint';

	/// en: 'Attraction'
	String get attraction => 'Attraction';

	/// en: 'Museum'
	String get museum => 'Museum';
}

// Path: poi.vendingSells
class Translations$poi$vendingSells$en {
	Translations$poi$vendingSells$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pizza'
	String get pizza => 'Pizza';

	/// en: 'Bread'
	String get bread => 'Bread';

	/// en: 'Farm produce'
	String get farmProducts => 'Farm produce';

	/// en: 'Eggs and milk'
	String get eggsMilk => 'Eggs and milk';

	/// en: 'Ice'
	String get ice => 'Ice';
}

// Path: poi.vendingChip
class Translations$poi$vendingChip$en {
	Translations$poi$vendingChip$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pizza vending machines'
	String get pizza => 'Pizza vending machines';

	/// en: 'Bread vending machines'
	String get bread => 'Bread vending machines';

	/// en: 'Farm produce vending machines'
	String get farmProducts => 'Farm produce vending machines';

	/// en: 'Egg and milk vending machines'
	String get eggsMilk => 'Egg and milk vending machines';

	/// en: 'Ice vending machines'
	String get ice => 'Ice vending machines';
}

// Path: poi.fuel
class Translations$poi$fuel$en {
	Translations$poi$fuel$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Diesel'
	String get diesel => 'Diesel';

	/// en: 'Unleaded 95'
	String get sp95 => 'Unleaded 95';

	/// en: 'E10'
	String get e10 => 'E10';

	/// en: 'Unleaded 98'
	String get sp98 => 'Unleaded 98';

	/// en: 'E85'
	String get e85 => 'E85';

	/// en: 'LPG'
	String get lpg => 'LPG';
}

// Path: poi.product
class Translations$poi$product$en {
	Translations$poi$product$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pizza'
	String get pizza => 'Pizza';

	/// en: 'Bread'
	String get bread => 'Bread';

	/// en: 'Eggs'
	String get eggs => 'Eggs';

	/// en: 'Milk'
	String get milk => 'Milk';

	/// en: 'Cheese'
	String get cheese => 'Cheese';

	/// en: 'Meat'
	String get meat => 'Meat';

	/// en: 'Vegetables'
	String get vegetables => 'Vegetables';

	/// en: 'Fruit'
	String get fruit => 'Fruit';

	/// en: 'Honey'
	String get honey => 'Honey';

	/// en: 'Ice'
	String get ice => 'Ice';

	/// en: 'Potatoes'
	String get potatoes => 'Potatoes';

	/// en: 'Food'
	String get food => 'Food';
}

// Path: poi.payment
class Translations$poi$payment$en {
	Translations$poi$payment$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cash'
	String get cash => 'Cash';

	/// en: 'Coins'
	String get coins => 'Coins';

	/// en: 'Notes'
	String get notes => 'Notes';

	/// en: 'Card'
	String get cards => 'Card';

	/// en: 'Contactless'
	String get contactless => 'Contactless';

	/// en: 'Phone app'
	String get app => 'Phone app';
}

// Path: poi.add
class Translations$poi$add$en {
	Translations$poi$add$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'A vending machine here?'
	String get title => 'A vending machine here?';

	/// en: 'Pick what it sells: it goes on the map for every traveller.'
	String get hint => 'Pick what it sells: it goes on the map for every traveller.';

	/// en: 'Pizza'
	String get pizza => 'Pizza';

	/// en: 'Bread'
	String get bread => 'Bread';

	/// en: 'Other food'
	String get other => 'Other food';

	/// en: 'Adding a vending machine'
	String get gate => 'Adding a vending machine';

	/// en: 'Thank you: the machine shows on the map within a few minutes.'
	String get sent => 'Thank you: the machine shows on the map within a few minutes.';

	/// en: 'Already on the map'
	String get duplicateTitle => 'Already on the map';

	/// en: 'A machine of the same kind is already listed within 25 m. Is it still there?'
	String get duplicateBody => 'A machine of the same kind is already listed within 25 m. Is it still there?';

	/// en: 'Yes, still there'
	String get duplicateThere => 'Yes, still there';

	/// en: 'No, it is gone'
	String get duplicateGone => 'No, it is gone';
}

// Path: poi.cheapest
class Translations$poi$cheapest$en {
	Translations$poi$cheapest$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cheapest around me'
	String get title => 'Cheapest around me';

	/// en: 'Cheapest around'
	String get show => 'Cheapest around';

	/// en: 'Zoom in to compare the stations' prices.'
	String get zoomIn => 'Zoom in to compare the stations\' prices.';

	/// en: 'No station on the map sells this fuel.'
	String get none => 'No station on the map sells this fuel.';

	/// en: 'Move the map or pick another fuel.'
	String get noneHint => 'Move the map or pick another fuel.';

	/// en: 'The stations' prices could not be loaded.'
	String get error => 'The stations\' prices could not be loaded.';
}

// Path: poi.trend
class Translations$poi$trend$en {
	Translations$poi$trend$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: '$fuel: prices of the last days'
	String title({required Object fuel}) => '${fuel}: prices of the last days';

	/// en: 'Lunaway has not seen a price of this fuel here yet.'
	String get none => 'Lunaway has not seen a price of this fuel here yet.';

	/// en: 'The prices of the last days could not be read now.'
	String get failed => 'The prices of the last days could not be read now.';

	/// en: 'Last 7 days:'
	String get week => 'Last 7 days:';

	/// en: 'Last 30 days:'
	String get month => 'Last 30 days:';

	/// en: 'from $low to $high'
	String range({required Object low, required Object high}) => 'from ${low} to ${high}';

	/// en: '$range, $move'
	String span({required Object range, required Object move}) => '${range}, ${move}';

	/// en: 'one day seen'
	String get oneDay => 'one day seen';

	/// en: 'unchanged'
	String get steady => 'unchanged';

	/// en: 'down $amount'
	String down({required Object amount}) => 'down ${amount}';

	/// en: 'up $amount'
	String up({required Object amount}) => 'up ${amount}';

	/// en: '(one) {$n day seen since $date, as Lunaway reads the feed; a day not seen stays empty} (other) {$n days seen since $date, as Lunaway reads the feed; a day not seen stays empty}'
	String since({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n,
		one: '${n} day seen since ${date}, as Lunaway reads the feed; a day not seen stays empty',
		other: '${n} days seen since ${date}, as Lunaway reads the feed; a day not seen stays empty',
	);
}

// Path: poi.vehicles
class Translations$poi$vehicles$en {
	Translations$poi$vehicles$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Takes motorhomes'
	String get motorhomeYes => 'Takes motorhomes';

	/// en: 'No motorhomes'
	String get motorhomeNo => 'No motorhomes';

	/// en: 'Takes heavy goods vehicles'
	String get hgvYes => 'Takes heavy goods vehicles';

	/// en: 'No heavy goods vehicles'
	String get hgvNo => 'No heavy goods vehicles';

	/// en: 'Height limit: $height'
	String maxHeight({required Object height}) => 'Height limit: ${height}';
}

// Path: roadReport.kinds
class Translations$roadReport$kinds$en {
	Translations$roadReport$kinds$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Road closed'
	String get closure => 'Road closed';

	/// en: 'Roadworks'
	String get works => 'Roadworks';

	/// en: 'Narrow passage'
	String get narrowPassage => 'Narrow passage';

	/// en: 'Low clearance'
	String get lowClearance => 'Low clearance';

	/// en: 'Road problem'
	String get other => 'Road problem';
}

// Path: navigation.preview.departure
class Translations$navigation$preview$departure$en {
	Translations$navigation$preview$departure$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Start'
	String get title => 'Start';

	/// en: 'From: $name'
	String from({required Object name}) => 'From: ${name}';

	/// en: 'my position'
	String get myPosition => 'my position';

	/// en: 'My position'
	String get myPositionChoice => 'My position';

	/// en: 'Change'
	String get change => 'Change';

	/// en: 'Choose a start'
	String get choose => 'Choose a start';

	/// en: 'A place, a town, an address'
	String get searchHint => 'A place, a town, an address';

	/// en: 'Guidance starts from your position, not from a chosen start.'
	String get guidanceFromPosition => 'Guidance starts from your position, not from a chosen start.';

	/// en: 'Start from my position'
	String get fromMyPosition => 'Start from my position';
}

// Path: navigation.preview.moved
class Translations$navigation$preview$moved$en {
	Translations$navigation$preview$moved$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Start moved $distance to the nearest street your vehicle can reach'
	String origin({required Object distance}) => 'Start moved ${distance} to the nearest street your vehicle can reach';

	/// en: 'Destination moved $distance to the nearest street your vehicle can reach'
	String destination({required Object distance}) => 'Destination moved ${distance} to the nearest street your vehicle can reach';

	/// en: 'Stop $n moved $distance to the nearest street your vehicle can reach'
	String stop({required Object n, required Object distance}) => 'Stop ${n} moved ${distance} to the nearest street your vehicle can reach';
}

// Path: navigation.onTheWay.categories
class Translations$navigation$onTheWay$categories$en {
	Translations$navigation$onTheWay$categories$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Fuel'
	String get fuel => 'Fuel';

	/// en: 'Sleep'
	String get sleep => 'Sleep';

	/// en: 'Water and dump'
	String get water => 'Water and dump';

	/// en: 'Groceries'
	String get groceries => 'Groceries';

	/// en: 'Bakeries'
	String get bakeries => 'Bakeries';

	/// en: 'Toilets, showers'
	String get toilets => 'Toilets, showers';

	/// en: 'Health'
	String get health => 'Health';

	/// en: 'Services'
	String get services => 'Services';

	/// en: 'EV charging'
	String get charging => 'EV charging';

	/// en: 'Garages and gear'
	String get garages => 'Garages and gear';
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

// Path: navigation.noRoute.limit
class Translations$navigation$noRoute$limit$en {
	Translations$navigation$noRoute$limit$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'low bridge at $limit'
	String underpass({required Object limit}) => 'low bridge at ${limit}';

	/// en: 'tunnel at $limit'
	String tunnel({required Object limit}) => 'tunnel at ${limit}';

	/// en: 'archway at $limit'
	String buildingPassage({required Object limit}) => 'archway at ${limit}';

	/// en: 'bridge at $limit'
	String bridge({required Object limit}) => 'bridge at ${limit}';

	/// en: 'height bar at $limit'
	String barrier({required Object limit}) => 'height bar at ${limit}';

	/// en: 'height limit $limit'
	String height({required Object limit}) => 'height limit ${limit}';

	/// en: 'height limit'
	String get heightUnknown => 'height limit';

	/// en: 'narrow passage of $limit'
	String width({required Object limit}) => 'narrow passage of ${limit}';

	/// en: 'narrow passage'
	String get widthUnknown => 'narrow passage';

	/// en: 'length limit $limit'
	String length({required Object limit}) => 'length limit ${limit}';

	/// en: 'length limit'
	String get lengthUnknown => 'length limit';

	/// en: 'weight limit $limit'
	String weight({required Object limit}) => 'weight limit ${limit}';

	/// en: 'weight limit'
	String get weightUnknown => 'weight limit';

	/// en: 'unpaved road'
	String get unpaved => 'unpaved road';

	/// en: 'weight limit $limit, local access only'
	String weightLocalAccess({required Object limit}) => 'weight limit ${limit}, local access only';

	/// en: 'narrow passage of $limit, local access only'
	String widthLocalAccess({required Object limit}) => 'narrow passage of ${limit}, local access only';

	/// en: 'length limit $limit, local access only'
	String lengthLocalAccess({required Object limit}) => 'length limit ${limit}, local access only';
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

// Path: navigation.warning.localAccess
class Translations$navigation$warning$localAccess$en {
	Translations$navigation$warning$localAccess$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Local access only: no vehicles over $limit except to reach your destination'
	String weight({required Object limit}) => 'Local access only: no vehicles over ${limit} except to reach your destination';

	/// en: 'Local access only: no vehicles over $limit per axle except to reach your destination'
	String axleLoad({required Object limit}) => 'Local access only: no vehicles over ${limit} per axle except to reach your destination';

	/// en: 'Local access only: no vehicles wider than $limit except to reach your destination'
	String width({required Object limit}) => 'Local access only: no vehicles wider than ${limit} except to reach your destination';

	/// en: 'Local access only: no vehicles longer than $limit except to reach your destination'
	String length({required Object limit}) => 'Local access only: no vehicles longer than ${limit} except to reach your destination';
}

// Path: navigation.guidance.notificationWhy
class Translations$navigation$guidance$notificationWhy$en {
	Translations$navigation$guidance$notificationWhy$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Guidance notification'
	String get title => 'Guidance notification';

	/// en: 'While guiding, a notification keeps the position and the voice going with the screen off, and tapping it brings the guidance back. Android will ask whether Lunaway may show it.'
	String get body => 'While guiding, a notification keeps the position and the voice going with the screen off, and tapping it brings the guidance back. Android will ask whether Lunaway may show it.';

	/// en: 'Continue'
	String get ask => 'Continue';

	/// en: 'Not now'
	String get later => 'Not now';
}

// Path: navigation.guidance.places
class Translations$navigation$guidance$places$en {
	Translations$navigation$guidance$places$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Places on the map'
	String get button => 'Places on the map';

	/// en: 'Places on the map: hidden'
	String get buttonHidden => 'Places on the map: hidden';

	/// en: 'Places on the map'
	String get title => 'Places on the map';

	/// en: 'For the night'
	String get sleep => 'For the night';

	/// en: 'Fill up'
	String get fill => 'Fill up';

	/// en: 'Food'
	String get groceries => 'Food';

	/// en: 'All'
	String get all => 'All';

	/// en: 'All places'
	String get everyPlace => 'All places';

	/// en: 'None'
	String get none => 'None';

	/// en: 'Customise'
	String get customize => 'Customise';

	/// en: 'Display'
	String get look => 'Display';

	/// en: 'Photos'
	String get photos => 'Photos';

	/// en: 'Icons'
	String get pictograms => 'Icons';

	/// en: 'Small pins'
	String get dots => 'Small pins';

	/// en: 'The places that matter most, as a photo. Never on the road ahead or under the buttons.'
	String get photosHint => 'The places that matter most, as a photo. Never on the road ahead or under the buttons.';

	/// en: 'The places that matter most, larger, with their price, rating or overnight stay.'
	String get pictogramsHint => 'The places that matter most, larger, with their price, rating or overnight stay.';

	/// en: 'Every place as a small pin, as on the map.'
	String get dotsHint => 'Every place as a small pin, as on the map.';

	/// en: 'Free'
	String get free => 'Free';

	/// en: 'Overnight'
	String get nightOk => 'Overnight';
}

// Path: navigation.voice.moved
class Translations$navigation$voice$moved$en {
	Translations$navigation$voice$moved$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Destination moved $distance to the nearest street your vehicle can reach.'
	String destination({required Object distance}) => 'Destination moved ${distance} to the nearest street your vehicle can reach.';

	/// en: 'Stop $n moved $distance to the nearest street your vehicle can reach.'
	String stop({required Object n, required Object distance}) => 'Stop ${n} moved ${distance} to the nearest street your vehicle can reach.';
}

// Path: navigation.voice.localAccess
class Translations$navigation$voice$localAccess$en {
	Translations$navigation$voice$localAccess$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Caution, in $distance, local access only above $limit.'
	String weight({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only above ${limit}.';

	/// en: 'Caution, in $distance, local access only above $limit per axle.'
	String axleLoad({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only above ${limit} per axle.';

	/// en: 'Caution, in $distance, local access only for vehicles wider than $limit.'
	String width({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only for vehicles wider than ${limit}.';

	/// en: 'Caution, in $distance, local access only for vehicles longer than $limit.'
	String length({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only for vehicles longer than ${limit}.';
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
			'nav.fold' => 'Fold the menu',
			'nav.unfold' => 'Unfold the menu',
			'common.close' => 'Close',
			'common.done' => 'Done',
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
			'common.failed' => 'That did not work. Try again in a moment.',
			'common.offline' => 'No connection right now. Try again once you are back online.',
			'notices.close' => 'Close the notice',
			'notices.fold' => 'Fold the notice',
			'notices.unfold' => 'Show the notice',
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
			'families.servicesHint' => 'Water and dump points, no overnight stay',
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
			'freshness.confirmed' => ({required Object when}) => 'Confirmed by a traveller ${when}',
			'freshness.unconfirmed' => 'Not yet confirmed by a traveller',
			'freshness.stale' => 'Last confirmed over a year ago',
			'freshness.today' => 'today',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'yesterday', other: '${n} days ago', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'a month ago', other: '${n} months ago', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'a year ago', other: '${n} years ago', ), 
			'map.searchHint' => 'A place, a town',
			'map.clearSearch' => 'Clear the search',
			'map.locateMe' => 'Show my position',
			'map.aroundMe' => 'Show places near me',
			'map.zoomIn' => 'Zoom in',
			'map.zoomOut' => 'Zoom out',
			'map.filters' => 'Filters',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Map credits: © OpenStreetMap contributors, Protomaps style. Opens the OpenStreetMap copyright page.',
			'map.showList' => 'List',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'List (${n})', other: 'List (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'place here', other: 'places here', ), 
			'map.nearestYouLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'place nearest to you', other: 'places nearest to you', ), 
			'map.nearestCentreLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'place nearest the centre', other: 'places nearest the centre', ), 
			'map.pointTitle' => 'Here',
			'map.pointHint' => 'Point on the map',
			'map.directionsHere' => 'Directions here',
			'map.startHere' => 'Start from here',
			'map.departureChosen' => 'Start chosen: now open the destination and its route.',
			'map.copyCoordinates' => 'Copy coordinates',
			'map.freeTapHint' => 'Tap the map to go there or add a place',
			'map.freeTapHintClick' => 'Click the map to go there or add a place',
			'map.addPlaceAtCenter' => 'Add a place at the centre of the map',
			'map.addressSource' => ({required Object attribution}) => 'Source: ${attribution}',
			'map.placesAround' => 'Places around',
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
			'location.rationale' => 'Lunaway uses it to centre the map on you, sort places by distance and guide you. For a route, your position is sent to Lunaway\'s server, which does not keep it. For the cheapest fuel around you, only a position rounded to about 5 km is sent. A road report goes with the spot where you make it.',
			'location.allow' => 'Continue',
			'location.notNow' => 'Not now',
			'location.deniedTitle' => 'Position turned off for Lunaway',
			'location.denied' => 'You refused access to your position. To use it, allow it in the device settings.',
			'location.openSettings' => 'Open settings',
			'location.serviceOffTitle' => 'Location is off',
			'location.serviceOff' => 'Location is turned off on this device. Turn it on in the quick settings, then try again.',
			'location.notAllowed' => 'Position not allowed. The map works without it.',
			'location.noFix' => 'Your position cannot be found yet. Try again in the open or in a moment.',
			'location.unsupported' => 'This device does not give its position.',
			'location.browserDeniedTitle' => 'The browser blocks your position',
			'location.browserDenied' => 'The browser refuses your position to Lunaway. To allow it, click the icon left of the site\'s address (a padlock or sliders), set Location to Allow, then click the position button again.',
			'location.browserNoFix' => 'The browser gave no position. Try again in a moment; on a computer, Wi-Fi helps find it.',
			'search.towns' => 'Towns',
			'search.places' => 'Places',
			'search.noResult' => ({required Object query}) => 'No place or town matches "${query}".',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} place', other: '${n} places', ), 
			'search.addresses' => 'Addresses',
			'search.addressesSearching' => 'Looking for addresses',
			'search.addressesFailed' => 'Addresses could not be searched just now.',
			'search.addressSources' => ({required Object sources}) => 'Addresses: ${sources}',
			'search.offline' => 'No connection: the search needs the network.',
			'search.addressKind.houseNumber' => 'Address',
			'search.addressKind.street' => 'Street',
			'search.addressKind.locality' => 'Locality',
			'search.addressKind.town' => 'Town',
			'search.addressKind.postcode' => 'Postcode',
			'search.addressKind.region' => 'Region',
			'filters.title' => 'Filters',
			'filters.families' => 'Kind of place',
			'filters.familiesHint' => 'None chosen: every kind',
			'filters.familiesChosenHint' => 'Only these kinds',
			'filters.night' => 'Overnight',
			'filters.nightHint' => 'None chosen: every place',
			'filters.nightChosenHint' => 'Only the places with these statuses',
			'filters.nightPossible' => 'Night possible',
			'filters.amenities' => 'Services',
			'filters.amenitiesHint' => 'The place must have all of them',
			'filters.rating' => 'Minimum rating',
			'filters.ratingHint' => 'Lunaway visitors\' rating, or the other sources\' when they have not rated the place. A place without a rating is hidden.',
			'filters.ratingAtLeast' => ({required Object rating}) => '${rating} and up',
			'filters.opening' => 'Opening',
			'filters.openingHint' => 'Places whose opening is not known stay shown.',
			'filters.openingAllYear' => 'All year',
			'filters.openingDates' => 'My dates',
			'filters.openingClearDates' => 'Clear the dates',
			'filters.openingStay' => ({required Object from, required Object to}) => '${from} to ${to}',
			'filters.openingStayDay' => ({required Object date}) => 'On ${date}',
			'filters.openingStayTitle' => 'Dates of your stay',
			'filters.openingArrival' => 'Arrival',
			'filters.openingDeparture' => 'Departure',
			'filters.price' => 'Price of the night',
			'filters.freeOnly' => 'Free',
			'filters.freeHint' => 'Only places whose night is free according to their sources',
			'filters.scrollNext' => 'Show the next filters',
			'filters.scrollPrevious' => 'Show the previous filters',
			'filters.vehicle' => 'My vehicle',
			'filters.myVehicleFits' => 'My vehicle fits',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Fits ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Hides places limited below ${height}. Places with no known limit stay on the map.',
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
			'place.priceUnknown' => 'Not given',
			'place.priceServices' => 'Services',
			'place.priceIncluded' => 'Included',
			'place.priceIncludes' => ({required Object items}) => 'The price of a night includes: ${items}',
			'place.inclusions.services' => 'services',
			'place.inclusions.touristTax' => 'tourist tax',
			'place.inclusions.electricity' => 'electricity',
			'place.maxHeight' => 'Max. height',
			'place.capacity' => 'Pitches',
			'place.classification' => 'Star rating',
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
			'place.copyAs' => ({required Object format}) => 'Copy as ${format}',
			'place.copiesAs' => ({required Object format}) => '"Copy" copies: ${format}',
			'place.copied' => ({required Object text}) => 'Copied: ${text}',
			'place.otherFormats' => 'Choose the format to copy',
			'place.formatDecimal' => 'Decimal degrees',
			'place.formatDms' => 'Degrees, minutes, seconds',
			'place.formatGeo' => 'geo: link',
			'place.formatGoogle' => 'Google Maps link',
			'place.formatOsm' => 'OpenStreetMap link',
			'place.sources' => 'Sources',
			'place.fetched' => ({required Object when}) => 'Retrieved ${when}',
			'place.viewSource' => 'View at the source',
			'place.gone' => 'This place is no longer on the map',
			'place.goneHint' => 'It was removed or merged with another since the last update.',
			'place.arriving' => 'This place is still downloading',
			'place.arrivingHint' => 'The places of France are downloading so the map works without a network. The page opens as soon as this one is here.',
			'place.loadError' => 'This place could not be loaded.',
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
			'place.externalRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'external review', other: 'external reviews', ), 
			'place.deletedAccount' => 'Deleted account',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Campervan',
			'place.reviewVehicle.motorhome' => 'Motorhome',
			'place.reviewVehicle.caravan' => 'Caravan',
			'place.reviewVehicle.other' => 'Other vehicle',
			'place.originalLanguage' => ({required Object language}) => 'Original text in ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Photo ${index} of ${count}',
			'place.previousPhoto' => 'Previous photo',
			'place.nextPhoto' => 'Next photo',
			'place.links' => 'On other sites',
			'place.sourceWithLicence' => ({required Object source, required Object licence}) => '${source} · ${licence}',
			'place.licenceCcBy' => 'CC BY 4.0',
			'place.photoCredit' => ({required Object source, required Object author}) => '${source} · ${author}',
			'place.photoStreetView' => 'Street view',
			'place.photoSurroundings' => 'Surroundings',
			'place.excerptFrom' => ({required Object source, required Object text}) => 'From ${source}: ${text}',
			'place.readMore' => 'Read more',
			'place.updatedOn' => ({required Object date}) => 'updated ${date}',
			'place.otherSources' => 'From other sources',
			'sources.extcom.label' => 'External community source',
			'sources.extcom.short' => 'External',
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
			'hours.onWeekday' => ({required Object day}) => '${day}',
			'hours.midnight' => 'midnight',
			'hours.stale' => 'Open or closed? Update the places in Profile.',
			'hours.localTime' => 'Times are local to the place',
			'hours.codes.mo' => 'Mon',
			'hours.codes.tu' => 'Tue',
			'hours.codes.we' => 'Wed',
			'hours.codes.th' => 'Thu',
			'hours.codes.fr' => 'Fri',
			'hours.codes.sa' => 'Sat',
			'hours.codes.su' => 'Sun',
			'hours.codes.ph' => 'public holidays',
			'hours.codes.sh' => 'school holidays',
			'hours.codes.off' => 'closed',
			'hours.codes.closed' => 'closed',
			'hours.codes.sunrise' => 'sunrise',
			'hours.codes.sunset' => 'sunset',
			'hours.months.jan' => 'Jan',
			'hours.months.feb' => 'Feb',
			'hours.months.mar' => 'Mar',
			'hours.months.apr' => 'Apr',
			'hours.months.may' => 'May',
			'hours.months.jun' => 'Jun',
			'hours.months.jul' => 'Jul',
			'hours.months.aug' => 'Aug',
			'hours.months.sep' => 'Sep',
			'hours.months.oct' => 'Oct',
			'hours.months.nov' => 'Nov',
			'hours.months.dec' => 'Dec',
			'hours.dayOfMonth' => ({required Object month, required Object day}) => '${month} ${day}',
			'hours.dayOfYear' => ({required Object month, required Object day, required Object year}) => '${month} ${day}, ${year}',
			'hours.allWeek' => '24/7',
			'hours.allYear' => 'all year',
			'hours.seasonAllYear' => 'Open all year',
			'hours.seasonOpenUntil' => ({required Object date}) => 'Open until ${date}',
			'hours.seasonClosedUntil' => ({required Object date}) => 'Closed, opens ${date}',
			'directions.title' => 'Open in',
			'directions.hint' => 'These apps do not know your vehicle\'s size.',
			'directions.remember' => 'Always use this app',
			'directions.rememberHint' => 'You can change it in Profile',
			'directions.settingTitle' => 'Open in another app',
			'directions.settingHint' => 'The app that "Open in" starts from a route',
			'directions.askEachTime' => 'Ask each time',
			'directions.appleMaps' => 'Apple Maps',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (browser)',
			'directions.none' => 'No navigation app found on this device.',
			'navigation.preview.titleTo' => ({required Object name}) => 'To ${name}',
			'navigation.preview.titlePoint' => 'Point on the map',
			'navigation.preview.departure.title' => 'Start',
			'navigation.preview.departure.from' => ({required Object name}) => 'From: ${name}',
			'navigation.preview.departure.myPosition' => 'my position',
			'navigation.preview.departure.myPositionChoice' => 'My position',
			'navigation.preview.departure.change' => 'Change',
			'navigation.preview.departure.choose' => 'Choose a start',
			'navigation.preview.departure.searchHint' => 'A place, a town, an address',
			'navigation.preview.departure.guidanceFromPosition' => 'Guidance starts from your position, not from a chosen start.',
			'navigation.preview.departure.fromMyPosition' => 'Start from my position',
			'navigation.preview.computing' => 'Computing a route for your vehicle',
			'navigation.preview.start' => 'Let\'s go!',
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
			'navigation.preview.cruise' => ({required Object speed}) => 'Timed at ${speed} max',
			'navigation.preview.avoid' => 'Avoid',
			'navigation.preview.avoidTolls' => 'Tolls',
			'navigation.preview.avoidMotorways' => 'Motorways',
			'navigation.preview.avoidFerries' => 'Ferries',
			'navigation.preview.avoidUnpaved' => 'Unpaved roads',
			'navigation.preview.roadbook' => 'Turn by turn',
			'navigation.preview.roadbookShow' => 'Show the directions',
			'navigation.preview.roadbookHide' => 'Hide the directions',
			'navigation.preview.dataOf' => ({required Object date}) => 'Road data from ${date}',
			'navigation.preview.attributionOsm' => '© OpenStreetMap contributors',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, ${date} edition',
			'navigation.preview.otherApps' => 'Open in…',
			'navigation.preview.back' => 'Back',
			'navigation.preview.moved.origin' => ({required Object distance}) => 'Start moved ${distance} to the nearest street your vehicle can reach',
			'navigation.preview.moved.destination' => ({required Object distance}) => 'Destination moved ${distance} to the nearest street your vehicle can reach',
			'navigation.preview.moved.stop' => ({required Object n, required Object distance}) => 'Stop ${n} moved ${distance} to the nearest street your vehicle can reach',
			'navigation.stops.title' => 'Stops',
			'navigation.stops.add' => 'Add as a stop',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Add as a stop · +${minutes} min',
			'navigation.stops.addFree' => 'Add as a stop · no detour',
			'navigation.stops.quoting' => 'Add as a stop · working out the detour',
			'navigation.stops.noRoute' => 'No route through this point for your vehicle.',
			'navigation.stops.full' => 'Five stops at most.',
			'navigation.stops.goDirectly' => 'Go there directly',
			'navigation.stops.openCard' => 'See the details',
			'navigation.stops.point' => 'Point on the map',
			'navigation.stops.remove' => 'Remove the stop',
			'navigation.stops.reorder' => 'Drag to change the order',
			'navigation.stops.added' => 'Stop added',
			'navigation.stops.removed' => 'Stop removed',
			'navigation.stops.moved' => 'Stops reordered',
			'navigation.stops.destinationChanged' => 'New destination',
			'navigation.stops.failed' => 'The route could not be changed.',
			'navigation.stops.noQuote' => 'The detour could not be worked out.',
			'navigation.stops.offline' => 'No network to work out the detour.',
			'navigation.legs.all' => 'All',
			'navigation.legs.stop' => ({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}',
			'navigation.legs.stopSaid' => ({required Object number, required Object name, required Object time, required Object distance}) => 'Stop ${number}: ${name}, around ${time}, in ${distance}',
			'navigation.legs.arrival' => ({required Object name, required Object time}) => 'Destination · ${name} · ${time}',
			'navigation.legs.arrivalSaid' => ({required Object name, required Object time}) => 'Destination: ${name}, around ${time}',
			'navigation.legs.remove' => ({required Object number, required Object name}) => 'Remove stop ${number}, ${name}',
			'navigation.fuel.price' => ({required Object price}) => '${price} €/L',
			'navigation.fuel.withDetour' => ({required Object price}) => '${price} €/L including the detour',
			'navigation.fuel.detour' => ({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min',
			'navigation.fuel.onRoute' => 'on the route',
			'navigation.fuel.open' => 'Open',
			'navigation.fuel.closed' => 'Closed',
			'navigation.fuel.unknownHours' => 'Hours unknown',
			'navigation.fuel.add' => 'Add',
			'navigation.fuel.station' => 'Fuel station',
			'navigation.fuel.empty' => 'No station selling this fuel near the route.',
			'navigation.fuel.failed' => 'The stations could not be loaded.',
			'navigation.fuel.estimated' => 'Detours estimated from the distance to the route.',
			'navigation.fuel.attribution' => 'Prices: French Ministry of the Economy (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => '${n} min ago',
			'navigation.fuel.hoursAgo' => ({required Object n}) => '${n} h ago',
			'navigation.fuel.daysAgo' => ({required Object n}) => '${n} d ago',
			'navigation.onTheWay.title' => 'On the way',
			'navigation.onTheWay.categories.fuel' => 'Fuel',
			'navigation.onTheWay.categories.sleep' => 'Sleep',
			'navigation.onTheWay.categories.water' => 'Water and dump',
			'navigation.onTheWay.categories.groceries' => 'Groceries',
			'navigation.onTheWay.categories.bakeries' => 'Bakeries',
			'navigation.onTheWay.categories.toilets' => 'Toilets, showers',
			'navigation.onTheWay.categories.health' => 'Health',
			'navigation.onTheWay.categories.services' => 'Services',
			'navigation.onTheWay.categories.charging' => 'EV charging',
			'navigation.onTheWay.categories.garages' => 'Garages and gear',
			'navigation.onTheWay.fuelOfVehicle' => ({required Object fuel}) => '${fuel}, from your vehicle',
			'navigation.onTheWay.otherFuel' => 'Another fuel',
			'navigation.onTheWay.keepFuel' => 'Keep as my fuel',
			'navigation.onTheWay.fuelKept' => ({required Object fuel}) => '${fuel} kept for your vehicle.',
			'navigation.onTheWay.keepFuelFailed' => 'The fuel could not be kept.',
			'navigation.onTheWay.loading' => 'Searching along the route',
			'navigation.onTheWay.empty' => 'Nothing found on this route',
			'navigation.onTheWay.emptyHint' => 'Try another kind, or open the list again further along the road.',
			'navigation.onTheWay.failed' => 'The list could not be loaded.',
			'navigation.onTheWay.offline' => 'No network: the list will come back with the connection.',
			'navigation.onTheWay.rateLimited' => 'Many searches in a row: try again in a few minutes.',
			'navigation.onTheWay.nearNone' => ({required Object distance}) => 'Nothing in the next ${distance}.',
			'navigation.onTheWay.further' => ({required Object n}) => 'Further on (${n})',
			'navigation.onTheWay.more' => 'Show more',
			'navigation.onTheWay.moreFailed' => 'The rest could not be loaded.',
			'navigation.onTheWay.ahead' => ({required Object distance}) => 'in ${distance}',
			'navigation.onTheWay.offRoute' => ({required Object distance}) => '${distance} from the route',
			'navigation.onTheWay.byTheRoad' => 'by the road',
			'navigation.onTheWay.addCost' => ({required Object minutes}) => 'Add · +${minutes} min',
			'navigation.onTheWay.addFree' => 'Add · no detour',
			'navigation.onTheWay.openAt' => ({required Object time}) => 'Open when you pass, around ${time}',
			'navigation.onTheWay.closedAt' => ({required Object time}) => 'Closed when you pass, around ${time}',
			'navigation.onTheWay.closedOpensAt' => ({required Object time, required Object opens}) => 'Closed when you pass around ${time}, opens at ${opens}',
			'navigation.onTheWay.perNight' => ({required Object price}) => '${price} a night',
			'navigation.onTheWay.photoFrom' => ({required Object source}) => 'Photo: ${source}',
			'navigation.onTheWay.servicesList' => ({required Object list}) => 'Services: ${list}',
			'navigation.onTheWay.placesCredit' => 'Places: Lunaway and the sources named on each place page',
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
			'navigation.states.offlineHint' => 'Routes are computed on Lunaway\'s server. Without network, "Open in…" hands the trip to a navigation app that keeps its own maps.',
			'navigation.states.rateLimitedTitle' => 'Too many route requests',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Try again in ${seconds} s.',
			'navigation.states.unavailableTitle' => 'Routing is down',
			'navigation.states.unavailableHint' => 'The route service is stopped for now. Try again later.',
			'navigation.states.refusedTitle' => 'No route here',
			'navigation.states.refusedHint' => 'Lunaway could not compute a route for this request: check the destination, the length of the trip and the vehicle\'s figures.',
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
			'navigation.noRoute.originUnreachable' => 'Your vehicle cannot leave from here',
			'navigation.noRoute.originUnreachableBy' => ({required Object limit}) => 'Your vehicle cannot leave from here: ${limit}',
			'navigation.noRoute.destinationUnreachable' => 'Destination out of reach for your vehicle',
			'navigation.noRoute.destinationUnreachableBy' => ({required Object limit}) => 'Destination out of reach for your vehicle: ${limit}',
			'navigation.noRoute.waypointUnreachable' => ({required Object n}) => 'Stop ${n} out of reach for your vehicle',
			'navigation.noRoute.waypointUnreachableBy' => ({required Object n, required Object limit}) => 'Stop ${n} out of reach for your vehicle: ${limit}',
			'navigation.noRoute.blockedOnTheWay' => 'No way through for your vehicle between the stops',
			'navigation.noRoute.blockedOnTheWayBy' => ({required Object limit}) => 'No way through for your vehicle between the stops: ${limit}',
			'navigation.noRoute.blockedHint' => 'Each stop can be reached, but every road between them passes a limit your vehicle exceeds.',
			'navigation.noRoute.notConnectedOrigin' => 'No road leads away from your position',
			'navigation.noRoute.notConnectedDestination' => 'No road leads to the destination',
			_ => null,
		} ?? switch (path) {
			'navigation.noRoute.notConnectedWaypoint' => ({required Object n}) => 'No road leads to stop ${n}',
			'navigation.noRoute.notConnectedTrip' => 'No road joins your stops',
			'navigation.noRoute.notConnectedHint' => 'Whatever the vehicle: an island without a car ferry, or a way closed to traffic.',
			'navigation.noRoute.outsideOrigin' => 'Your position is outside the area routes cover',
			'navigation.noRoute.outsideDestination' => 'Destination outside the area routes cover',
			'navigation.noRoute.outsideWaypoint' => ({required Object n}) => 'Stop ${n} outside the area routes cover',
			'navigation.noRoute.outsideHint' => ({required Object countries}) => 'Lunaway computes routes in these countries: ${countries}.',
			'navigation.noRoute.outsideHintUnknown' => 'Lunaway does not compute routes in this country yet.',
			'navigation.noRoute.noRoadOrigin' => 'Your position is too far from a road',
			'navigation.noRoute.noRoadDestination' => 'Destination too far from a road',
			'navigation.noRoute.noRoadWaypoint' => ({required Object n}) => 'Stop ${n} too far from a road',
			'navigation.noRoute.noRoadHint' => 'No road your vehicle may take within 5 km of this point.',
			'navigation.noRoute.tooLong' => 'Trip too long',
			'navigation.noRoute.tooLongHint' => ({required Object trip, required Object max}) => '${trip} in a straight line from stop to stop: Lunaway computes trips of ${max} at most.',
			'navigation.noRoute.vehicleValue' => ({required Object value}) => 'Your vehicle: ${value}',
			'navigation.noRoute.limit.underpass' => ({required Object limit}) => 'low bridge at ${limit}',
			'navigation.noRoute.limit.tunnel' => ({required Object limit}) => 'tunnel at ${limit}',
			'navigation.noRoute.limit.buildingPassage' => ({required Object limit}) => 'archway at ${limit}',
			'navigation.noRoute.limit.bridge' => ({required Object limit}) => 'bridge at ${limit}',
			'navigation.noRoute.limit.barrier' => ({required Object limit}) => 'height bar at ${limit}',
			'navigation.noRoute.limit.height' => ({required Object limit}) => 'height limit ${limit}',
			'navigation.noRoute.limit.heightUnknown' => 'height limit',
			'navigation.noRoute.limit.width' => ({required Object limit}) => 'narrow passage of ${limit}',
			'navigation.noRoute.limit.widthUnknown' => 'narrow passage',
			'navigation.noRoute.limit.length' => ({required Object limit}) => 'length limit ${limit}',
			'navigation.noRoute.limit.lengthUnknown' => 'length limit',
			'navigation.noRoute.limit.weight' => ({required Object limit}) => 'weight limit ${limit}',
			'navigation.noRoute.limit.weightUnknown' => 'weight limit',
			'navigation.noRoute.limit.unpaved' => 'unpaved road',
			'navigation.noRoute.limit.weightLocalAccess' => ({required Object limit}) => 'weight limit ${limit}, local access only',
			'navigation.noRoute.limit.widthLocalAccess' => ({required Object limit}) => 'narrow passage of ${limit}, local access only',
			'navigation.noRoute.limit.lengthLocalAccess' => ({required Object limit}) => 'length limit ${limit}, local access only',
			'navigation.noRoute.editVehicle' => 'Edit the vehicle',
			'navigation.noRoute.allowUnpaved' => 'Allow unpaved roads',
			'navigation.noRoute.removeStop' => ({required Object n}) => 'Remove stop ${n}',
			'navigation.noRoute.removeStopNamed' => ({required Object name}) => 'Remove the stop "${name}"',
			'navigation.noRoute.placesAround' => 'See the places around the destination',
			'navigation.noRoute.moveDestination' => 'Or pick another arrival: long press on the map, then "Go there directly".',
			'navigation.noRoute.moveStop' => 'For another stop: tap the map close up, or long press, then "Add as a stop".',
			'navigation.noRoute.moveOrigin' => 'The start is your position: get to a road your vehicle may take, then try again.',
			'navigation.noRoute.pickInside' => 'Pick a destination in one of these countries.',
			'navigation.noRoute.shorter' => 'Pick a closer destination, or make the trip in several legs.',
			'navigation.ferry.title' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Ferry crossing', other: '${n} ferry crossings', ), 
			'navigation.ferry.unnamed' => 'Ferry',
			'navigation.ferry.named' => ({required Object name}) => 'Ferry ${name}',
			'navigation.ferry.ports' => ({required Object ports}) => 'Ports: ${ports}',
			'navigation.ferry.countries' => ({required Object from, required Object to}) => 'Boarding: ${from} · Landing: ${to}',
			'navigation.ferry.country' => ({required Object country}) => 'Country: ${country}',
			'navigation.ferry.where' => ({required Object distance, required Object sea, required Object duration}) => '${distance} from the start · ${sea} at sea, about ${duration}',
			'navigation.ferry.needed' => 'The destination cannot be reached without a ferry: the route takes one, even though you avoid ferries.',
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
			'navigation.warning.localAccess.weight' => ({required Object limit}) => 'Local access only: no vehicles over ${limit} except to reach your destination',
			'navigation.warning.localAccess.axleLoad' => ({required Object limit}) => 'Local access only: no vehicles over ${limit} per axle except to reach your destination',
			'navigation.warning.localAccess.width' => ({required Object limit}) => 'Local access only: no vehicles wider than ${limit} except to reach your destination',
			'navigation.warning.localAccess.length' => ({required Object limit}) => 'Local access only: no vehicles longer than ${limit} except to reach your destination',
			'navigation.roadEvents.title' => 'Works and closures',
			'navigation.roadEvents.none' => 'No works or closures known on this route.',
			'navigation.roadEvents.stale' => 'Works and closures: the sources have not been read recently.',
			'navigation.roadEvents.avoided' => ({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Route planned around a closure: ${names}', other: 'Route planned around ${n} closures: ${names}', ), 
			'navigation.roadEvents.atDistance' => ({required Object distance}) => '${distance} from the start',
			'navigation.roadEvents.more' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'And ${n} more on the route', other: 'And ${n} more on the route', ), 
			'navigation.roadEvents.classClosure' => 'Road closed',
			'navigation.roadEvents.classWorks' => 'Works',
			'navigation.roadEvents.classLaneRestriction' => 'Lanes closed',
			'navigation.roadEvents.classVehicleLimit' => 'Size limit',
			'navigation.roadEvents.classDetour' => 'Detour signposted',
			'navigation.roadEvents.reasonUnmatched' => 'uncertain position, maybe on the route',
			'navigation.roadEvents.reasonStale' => 'source not read recently',
			'navigation.roadEvents.reasonOutsideHours' => 'outside its assumed hours',
			'navigation.roadEvents.reasonGoodsVehicles' => 'for heavy goods vehicles',
			'navigation.roadEvents.reasonUnconfirmed' => 'reported by a single traveller',
			'navigation.roadEvents.reasonAged' => 'old report',
			'navigation.roadEvents.reasonInside' => 'the route starts or ends inside it',
			'navigation.roadEvents.reasonNearLimit' => 'with little margin',
			'navigation.roadEvents.reasonOverLimit' => 'over your vehicle\'s limit',
			'navigation.marks.legend' => 'Legend',
			'navigation.marks.legendHide' => 'Fold the legend',
			'navigation.marks.kindOrigin' => 'Start',
			'navigation.marks.kindDestination' => 'Destination',
			'navigation.marks.kindStop' => 'Stop',
			'navigation.marks.kindClosure' => 'Road closed',
			'navigation.marks.kindWorks' => 'Works',
			'navigation.marks.kindLanes' => 'Lanes closed',
			'navigation.marks.kindClearance' => 'Height limit',
			'navigation.marks.kindWeight' => 'Weight limit',
			'navigation.marks.kindLimit' => 'Other limit (width, length, ban)',
			'navigation.marks.kindFuel' => 'Fuel station',
			'navigation.marks.kindPlace' => 'Place near the route',
			'navigation.marks.groupLegend' => 'Marks close together, grouped',
			'navigation.marks.zoneLegend' => 'Danger zone',
			'navigation.marks.zonesFrom' => ({required Object source, required Object date}) => 'Danger zones: ${source}, list of ${date}',
			'navigation.marks.group' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} mark', other: '${n} marks', ), 
			'navigation.marks.groupHint' => 'Zoom in to see each one',
			'navigation.marks.count' => ({required Object kind, required Object n}) => '${kind}: ${n}',
			'navigation.marks.stop' => ({required Object n}) => 'Stop ${n}',
			'navigation.marks.origin' => 'Starting point',
			'navigation.marks.nearRoute' => 'Near the route',
			'navigation.marks.avoided' => 'The route goes around it',
			'navigation.marks.blocking' => 'Stops every route',
			'navigation.marks.showInList' => 'See it in the list',
			'navigation.marks.showAll' => 'Show all',
			'navigation.marks.onMap' => 'show on the map',
			'navigation.marks.price' => ({required Object price}) => '${price} €',
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
			'navigation.guidance.eventClosure' => ({required Object distance}) => 'Road closed in ${distance}',
			'navigation.guidance.eventLimit' => ({required Object distance}) => 'Size limited by roadworks in ${distance}',
			'navigation.guidance.eventSource' => ({required Object source, required Object time}) => '${source}, as of ${time}',
			'navigation.guidance.eventSourceOn' => ({required Object source, required Object day, required Object time}) => '${source}, as of ${day} at ${time}',
			'navigation.guidance.avoidedClosures' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Route planned around a closure', other: 'Route planned around ${n} closures', ), 
			'navigation.guidance.roadEventAhead' => ({required Object what, required Object distance}) => '${what} in ${distance}',
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Road closed in ${distance}: no network to look for another way',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Road closed in ${distance}: no other way yet',
			'navigation.guidance.voiceOn' => 'Turn the voice on',
			'navigation.guidance.voiceOff' => 'Turn the voice off',
			'navigation.guidance.overview' => 'Whole route',
			'navigation.guidance.recenter' => 'Recenter',
			'navigation.guidance.end' => 'End',
			'navigation.guidance.endTitle' => 'End the guidance?',
			'navigation.guidance.endConfirm' => 'End',
			'navigation.guidance.endKeep' => 'Keep going',
			'navigation.guidance.stopTitle' => 'Stop the guidance?',
			'navigation.guidance.stopConfirm' => 'Stop',
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
			'navigation.guidance.notificationWhy.title' => 'Guidance notification',
			'navigation.guidance.notificationWhy.body' => 'While guiding, a notification keeps the position and the voice going with the screen off, and tapping it brings the guidance back. Android will ask whether Lunaway may show it.',
			'navigation.guidance.notificationWhy.ask' => 'Continue',
			'navigation.guidance.notificationWhy.later' => 'Not now',
			'navigation.guidance.positionLost' => 'Position unavailable: check that the device\'s location is on for Lunaway.',
			'navigation.guidance.positionStale' => ({required Object minutes}) => 'Last position received ${minutes} min ago: the arrival time rests on it.',
			'navigation.guidance.dangerZone' => ({required Object distance}) => 'Danger zone in ${distance}',
			'navigation.guidance.inDangerZone' => ({required Object distance}) => 'Danger zone, ${distance} left',
			'navigation.guidance.cameraAhead' => ({required Object distance}) => 'Speed camera in ${distance}',
			'navigation.guidance.cameraLimit' => ({required Object distance, required Object limit}) => 'Speed camera in ${distance}, ${limit}',
			'navigation.guidance.limitEstimated' => 'Estimated limit',
			'navigation.guidance.overLimit' => 'over the limit',
			'navigation.guidance.enforcementSource' => ({required Object source, required Object date}) => '${source}, list of ${date}',
			'navigation.guidance.demoDrive' => 'Simulated drive: a demonstration without GPS',
			'navigation.guidance.places.button' => 'Places on the map',
			'navigation.guidance.places.buttonHidden' => 'Places on the map: hidden',
			'navigation.guidance.places.title' => 'Places on the map',
			'navigation.guidance.places.sleep' => 'For the night',
			'navigation.guidance.places.fill' => 'Fill up',
			'navigation.guidance.places.groceries' => 'Food',
			'navigation.guidance.places.all' => 'All',
			'navigation.guidance.places.everyPlace' => 'All places',
			'navigation.guidance.places.none' => 'None',
			'navigation.guidance.places.customize' => 'Customise',
			'navigation.guidance.places.look' => 'Display',
			'navigation.guidance.places.photos' => 'Photos',
			'navigation.guidance.places.pictograms' => 'Icons',
			'navigation.guidance.places.dots' => 'Small pins',
			'navigation.guidance.places.photosHint' => 'The places that matter most, as a photo. Never on the road ahead or under the buttons.',
			'navigation.guidance.places.pictogramsHint' => 'The places that matter most, larger, with their price, rating or overnight stay.',
			'navigation.guidance.places.dotsHint' => 'Every place as a small pin, as on the map.',
			'navigation.guidance.places.free' => 'Free',
			'navigation.guidance.places.nightOk' => 'Overnight',
			'navigation.voice.rerouting' => 'Recalculating.',
			'navigation.voice.rerouted' => 'New route.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(minutes, one: 'New route, one minute longer.', other: 'New route, ${minutes} minutes longer.', ), 
			'navigation.voice.moved.destination' => ({required Object distance}) => 'Destination moved ${distance} to the nearest street your vehicle can reach.',
			'navigation.voice.moved.stop' => ({required Object n, required Object distance}) => 'Stop ${n} moved ${distance} to the nearest street your vehicle can reach.',
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
			'navigation.voice.size' => ({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '${metres}.${cm} metres', other: '${metres}.${cm} metres', ), 
			'navigation.voice.sizeWhole' => ({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '${metres} metre', other: '${metres} metres', ), 
			'navigation.voice.overSpeed' => ({required Object limit}) => 'Speed limit ${limit}.',
			'navigation.voice.dangerZone' => ({required Object distance}) => 'Danger zone in ${distance}.',
			'navigation.voice.inDangerZone' => 'Danger zone.',
			'navigation.voice.camera' => ({required Object distance}) => 'Speed camera in ${distance}.',
			'navigation.voice.localAccess.weight' => ({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only above ${limit}.',
			'navigation.voice.localAccess.axleLoad' => ({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only above ${limit} per axle.',
			'navigation.voice.localAccess.width' => ({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only for vehicles wider than ${limit}.',
			'navigation.voice.localAccess.length' => ({required Object distance, required Object limit}) => 'Caution, in ${distance}, local access only for vehicles longer than ${limit}.',
			'navigation.voice.tonnes' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(count, one: '${n} tonne', other: '${n} tonnes', ), 
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} h ${m} min',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Guidance',
			'navigation.settings.avoidTitle' => 'Avoid by default',
			'navigation.settings.voice' => 'Spoken instructions',
			'navigation.settings.voiceHint' => 'With the device\'s own voice',
			'navigation.settings.units' => 'Distances',
			'navigation.settings.metric' => 'Kilometres',
			'navigation.settings.imperial' => 'Miles',
			'navigation.settings.speedLimit' => 'Speed limit',
			'navigation.settings.speedLimitHint' => 'The limit for your vehicle beside the speed during guidance; an estimate shows in grey.',
			'navigation.settings.speedSound' => 'Spoken speed alerts',
			'navigation.settings.speedSoundHint' => 'A word when you drive over the limit, and before a danger zone where the country allows them. Off: the sign and the banners only.',
			'list.title' => 'Places nearby',
			'list.empty' => 'No places around here with these filters',
			'list.emptyHint' => 'Move the map, zoom out or loosen the filters.',
			'list.downloading' => 'Places are on their way',
			'list.downloadingHint' => 'The list fills in while they download.',
			'list.error' => 'The list could not be loaded.',
			'list.offline' => 'No connection: the list needs the network.',
			'list.moreFailed' => 'More places could not be loaded. Try again',
			'list.sortDistance' => 'Distance',
			'list.sortRating' => 'Rating',
			'list.sortNewest' => 'Recently added',
			'list.sortedBy' => ({required Object sort}) => 'List sorted by: ${sort}',
			'list.rankedAmongNearestYou' => ({required Object n}) => 'Ranked among the ${n} places nearest you',
			'list.rankedAmongNearestCentre' => ({required Object n}) => 'Ranked among the ${n} places nearest the centre of the map',
			'list.offlineTitle' => 'No connection',
			'list.offlineNotHere' => 'Nothing of this area on this device.',
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
			'favorites.error' => 'Your favourites could not be loaded.',
			'vehicle.title' => 'My vehicle',
			'vehicle.why' => 'Its dimensions hide the places it cannot get into. They are sent with each route request and not kept.',
			'vehicle.none' => 'Describe your vehicle to hide the places it cannot get into.',
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
			'vehicle.fuelTitle' => 'Fuel',
			'vehicle.fuelHint' => 'The price of your fuel shows on the stations of the map, and the cheapest come first.',
			'vehicle.consumption' => 'Consumption',
			'vehicle.consumptionUnit' => 'L/100 km',
			'vehicle.lpgHeating' => 'Heating on LPG',
			'vehicle.lpgHeatingHint' => 'LPG prices also show on the stations.',
			'vehicle.cruiseTitle' => 'Top cruising speed',
			'vehicle.cruiseHint' => 'Travel times assume you never drive faster, even where the road allows it. The speed limits announced while driving stay the road\'s.',
			'vehicle.cruiseNone' => 'No limit',
			'vehicleHeight.title' => 'Your vehicle\'s height',
			'vehicleHeight.why' => 'Places limited lower will be hidden. Places with no known limit stay on the map.',
			'vehicleHeight.needed' => 'Give the height, for example 2.90',
			'vehicleHeight.weightOptional' => 'Gross vehicle weight (optional)',
			'vehicleHeight.apply' => 'Filter with this height',
			'vehicleHeight.later' => 'The rest of the vehicle is described in Profile, My vehicle.',
			'profile.title' => 'Profile',
			'profile.noAccountNeeded' => 'No account, no ads, no trackers. Your favourites stay on this device.',
			'profile.language' => 'Language',
			'profile.languageSystem' => 'Same as device',
			'profile.appearance' => 'Appearance',
			'profile.themeAuto' => 'Auto',
			'profile.themeLight' => 'Light',
			'profile.themeDark' => 'Dark',
			'profile.themeAutoHint' => 'Light by day, dark after sunset where you are.',
			'profile.themeLightHint' => 'Always light, day and night.',
			'profile.themeDarkHint' => 'Always dark, easy on the eyes at night.',
			'profile.offline' => 'Offline',
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
			'profile.routeData' => 'Routes are computed on open data that may be incomplete: road signs and the highway code come first.',
			'profile.attributions' => 'Sources and credits',
			'profile.attributionOsm' => 'Places and map data © OpenStreetMap contributors.',
			'profile.attributionOdbl' => 'OpenStreetMap data under the Open Database License (ODbL).',
			'profile.attributionAtout' => 'Classified campsites from Atout France, under the Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Place communes: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), under the ODbL.',
			'profile.attributionTiles' => 'Basemap served by Lunaway, styles derived from Protomaps (BSD-3-Clause), data © OpenStreetMap contributors.',
			'profile.attributionFonts' => 'Fraunces and Atkinson Hyperlegible Next typefaces, SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Phosphor icons, MIT licence.',
			'profile.noTracking' => 'No ads, no trackers. Your account knows neither your e-mail nor your phone number.',
			'profile.attributionBdTopo' => 'Height, width, length and weight limits of the roads, and campsites placed by their name: IGN BD TOPO, through the Géoplateforme, under the Licence Ouverte 2.0.',
			'profile.attributionAddresses' => 'Addresses of the search in France: the Base Adresse Nationale, through IGN\'s Géoplateforme, under the Licence Ouverte 2.0.',
			'profile.attributionAddressesOsm' => 'Addresses of the search elsewhere: OpenStreetMap, through Photon, under the ODbL.',
			'profile.attributionPoiOdbl' => 'Shops and services: OpenStreetMap, and La Poste\'s opening calendar, under the ODbL.',
			'profile.attributionPoiLo' => 'Fuel prices (French Ministry of the Economy) and the FINESS health establishments, under the Licence Ouverte 2.0 (Etalab).',
			'profile.attributionPacks' => 'Outlines of the offline maps: Contours administratifs, data.gouv.fr (ODbL), and Natural Earth (public domain).',
			'profile.attributionOfflineLabels' => 'Offline map labels and icons: Noto Sans glyphs (SIL Open Font License 1.1) and Protomaps sprites derived from tangrams/icons (MIT).',
			'profile.attributionExtcom' => 'Places, reviews, ratings and photos, under a written agreement with this source.',
			'profile.creditsPlaces' => 'Places',
			'profile.creditsContent' => 'Photos, texts and reviews',
			'profile.creditsRoutes' => 'Routes and guidance',
			'profile.creditsSearch' => 'Search',
			'profile.creditsMap' => 'Basemap',
			'profile.creditsApp' => 'App',
			'profile.attributionDatatourisme' => 'Places, descriptions and photos of the tourist offices: DATAtourisme, under the Licence Ouverte 2.0; each text and photo names its office, its author and the date of its last update.',
			'profile.attributionCommunity' => 'Reviews, ratings and photos by Lunaway\'s travellers, under CC BY 4.0, with their author\'s pseudonym.',
			'profile.attributionCommons' => 'Photos from Wikimedia Commons, each under its own licence (CC0, CC BY or CC BY-SA), with its author and a link to its page.',
			'profile.attributionPanoramax' => 'Street views from Panoramax: the OpenStreetMap France instance under CC BY-SA 4.0, IGN\'s under the Licence Ouverte 2.0.',
			'profile.attributionWikipedia' => 'Extracts of Wikipedia articles, under CC BY-SA 4.0, with a link to the article.',
			'profile.attributionMangrove' => 'Reviews from Mangrove Reviews, under CC BY 4.0 or the licence the review states, with a link to the review.',
			'profile.attributionRoadEvents' => 'Road works and closures in France: DIR and Bison Futé, DiaLog traffic orders (DGITM), cities and départements (Lyon, Toulouse, Bordeaux, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d\'Armor, Sarthe), under the Licence Ouverte 2.0; Rennes Métropole and the reports of Lunaway\'s travellers, under the ODbL.',
			'profile.attributionRoadEventsAbroad' => 'Road works and closures in the Netherlands: NDW, Nationaal Dataportaal Wegverkeer (open data); in Spain: DGT, Dirección General de Tráfico (CC BY).',
			'profile.attributionDangerZones' => 'Danger zones: the official speed camera lists (Sécurité routière in France, reused under the French Code des relations entre le public et l\'administration; Poland and Luxembourg, CC0; Catalonia, the Generalitat\'s open licence; Norway, NLOD) and OpenStreetMap (ODbL).',
			'units.kilobytes' => ({required Object n}) => '${n} KB',
			'units.megabytes' => ({required Object n}) => '${n} MB',
			'languages.fr' => 'French',
			'languages.en' => 'English',
			'languages.de' => 'German',
			'languages.es' => 'Spanish',
			'languages.it' => 'Italian',
			'languages.nl' => 'Dutch',
			'translation.translate' => 'Translate',
			'translation.translating' => 'Translating',
			'translation.showOriginal' => 'Show original',
			'translation.showTranslation' => 'Show translation',
			'translation.from.fr' => 'Automatically translated from French',
			'translation.from.en' => 'Automatically translated from English',
			'translation.from.de' => 'Automatically translated from German',
			'translation.from.es' => 'Automatically translated from Spanish',
			'translation.from.it' => 'Automatically translated from Italian',
			'translation.from.nl' => 'Automatically translated from Dutch',
			'translation.from.unknown' => ({required Object language}) => 'Automatically translated (original language: ${language})',
			'translation.offline' => 'Translation needs a network connection.',
			'translation.failedOffline' => 'No connection: the text could not be translated.',
			'translation.busy' => 'The translation service is busy. Try again later.',
			'translation.unavailable' => 'Translation is not available right now.',
			'translation.gone' => 'This text is no longer available.',
			'translation.unsupported' => 'No translation is available for this language.',
			'translation.autoReviews' => 'Translate reviews automatically',
			'translation.autoReviewsHint' => 'Reviews in another language are translated by Lunaway\'s own server, without any third-party service.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			'locale.de' => 'Deutsch',
			'locale.es' => 'Español',
			'locale.it' => 'Italiano',
			'locale.nl' => 'Nederlands',
			'account.title' => 'Your account',
			'account.noneTitle' => 'No account yet',
			'account.noneBody' => 'The map, search and favourites work without an account. One is created at your first contribution (a rating, a confirmation, a photo), with no e-mail and no password. Your favourite lists are then linked to it.',
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
			'account.orInstead' => ({required Object requirement}) => 'Or ${requirement}',
			'account.recoveryNone' => 'No recovery card made on this device. Without one, this account stays on this device: lose it, and the account goes with it.',
			'account.recoveryNoneAccount' => 'No recovery card for this account yet. Without one, this account stays on this device: lose it, and the account goes with it.',
			'account.recoveryCreate' => 'Make my recovery card',
			'account.recoveryMade' => ({required Object date}) => 'Made on ${date}',
			'account.recoveryRemake' => 'Make again',
			'account.recoveryRemakeHint' => 'Make a new recovery card',
			'account.contributions' => 'My contributions',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} contribution waiting to be sent', other: '${n} contributions waiting to be sent', ), 
			'account.mutedAuthors' => 'Hidden authors',
			'account.devices' => 'Devices',
			'account.signOut' => 'Sign out',
			'account.delete' => 'Delete my account',
			'account.signOutTitle' => 'Sign out of this device?',
			'account.signOutBody' => 'The account\'s key is removed from this device. To come back, you will need your recovery card. Your favourites stay here.',
			'account.signOutNoCard' => 'You have not made a recovery card on this device. Without one, this account will be lost for good.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'One contribution waiting to be sent will not be sent.', other: '${n} contributions waiting to be sent will not be sent.', ), 
			'account.signedOut' => 'Signed out. Your favourites stay on this device.',
			'account.lost' => 'This account no longer opens on this device. Recover it with your recovery card: Profile, Recover my account.',
			'account.lostAction' => 'Recover',
			'account.welcomeTitle' => 'Thank you for your first contribution',
			'account.welcomeBody' => ({required Object name}) => 'Your account is created, under the pseudonym “${name}”. No e-mail and no password: a key kept on this device. You can change the pseudonym in your profile.',
			'account.welcomeCard' => 'Make your recovery card to find this account on another device.',
			'account.welcomeFavorites' => 'Your favourite lists are now kept with your account.',
			'recovery.title' => 'Recovery card',
			'recovery.intro' => 'A code that brings your account to a new device. Lunaway keeps only a fingerprint of it, enough to check it: the code itself can never be shown again, and each new card has a different code.',
			'recovery.replaces' => 'A new card replaces the previous one: the old code will stop working.',
			'recovery.replaceTitle' => ({required Object date}) => 'Replace the card of ${date}?',
			'recovery.replaceBody' => ({required Object date}) => 'The new card will have another code. The code of the card of ${date} stops working right now. It cannot be shown again: Lunaway kept only a fingerprint of it.',
			'recovery.replaceKeep' => 'Keep the old one',
			'recovery.replaceConfirm' => 'Make a new card',
			'recovery.make' => 'Make the card',
			'recovery.codeLabel' => 'Your recovery code',
			'recovery.shownOnce' => 'This code shows only once. Write it down, or save the image, before closing.',
			'recovery.saveImage' => 'Save the image',
			'recovery.done' => 'I have noted the code',
			'recovery.doneTitle' => 'Did you keep the code?',
			'recovery.doneBody' => 'Once this page is closed, it will not show again.',
			'recovery.keep' => 'Stay on the page',
			'recovery.cardHeading' => 'Lunaway recovery card',
			'recovery.cardAccount' => ({required Object name}) => 'Account: ${name}',
			'recovery.cardHow' => 'To recover the account: Profile, Recover my account, then type this code or scan the card.',
			'recovery.cardMade' => ({required Object date}) => 'Made on ${date}',
			'recovery.cardWarning' => 'This code opens the account: never share it.',
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
			'recover.revokeHint' => 'All your other devices will be signed out.',
			'recover.submit' => 'Recover the account',
			'recover.notFound' => 'No account has this code. Check the card, or make a new one from a signed-in device.',
			'recover.tooMany' => 'Too many attempts for now. Try again in an hour.',
			'recover.done' => ({required Object name}) => 'Account recovered: ${name}',
			'deletion.title' => 'Delete my account',
			'deletion.intro' => 'Deletion is immediate and final.',
			'deletion.goneTitle' => 'What is deleted',
			'deletion.gone.identity' => 'Your pseudonym and the keys of your devices',
			'deletion.gone.sessions' => 'Your sessions and your recovery code',
			'deletion.gone.lists' => 'Your synced favourite lists and your hidden authors',
			'deletion.gone.photos' => 'Your photos, your ratings without text and your reports',
			'deletion.gone.pending' => 'Your proposals waiting for review',
			'deletion.keptTitle' => 'What stays, without your name',
			_ => null,
		} ?? switch (path) {
			'deletion.kept' => 'Your published written reviews, your confirmations and your applied place edits stay, without author: they are part of other travellers\' map.',
			'deletion.backups' => 'The server\'s backups are cleared in about 30 days.',
			'deletion.device' => 'On this device, your favourites stay; the account\'s key is erased.',
			'deletion.web' => 'You can also delete it on lunaway.net with your recovery code.',
			'deletion.webLink' => 'lunaway.net/account/delete',
			'deletion.confirmTitle' => 'Delete for good?',
			'deletion.confirmBody' => ({required Object name}) => 'The account “${name}” and everything listed are deleted now. Nobody can bring it back.',
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
			'devices.error' => 'The devices could not be loaded. A connection is needed.',
			'muted.title' => 'Hidden authors',
			'muted.empty' => 'Nobody is hidden',
			'muted.emptyHint' => 'To hide someone, open the menu of one of their reviews or photos. Hiding applies to you only.',
			'muted.unmute' => 'Show again',
			'muted.unmuted' => ({required Object name}) => 'Contributions by ${name} will show again',
			'mine.title' => 'My contributions',
			'mine.pending' => 'Waiting to be sent',
			'mine.pendingHint' => 'They leave as soon as the network is back.',
			'mine.sendNow' => 'Send now',
			'mine.retry' => 'Try again',
			'mine.discard' => 'Discard',
			'mine.discardTitle' => 'Discard this contribution?',
			'mine.discardBody' => 'It will not be sent.',
			'mine.reviews' => 'Reviews and ratings',
			'mine.photos' => 'Photos',
			'mine.confirmations' => 'Confirmations',
			'mine.issues' => 'Problems reported',
			'mine.places' => 'Places added and edits',
			'mine.empty' => 'Nothing yet',
			'mine.emptyHint' => 'Rating a place or confirming it is still there already counts as a contribution.',
			'mine.latest' => ({required Object shown, required Object total}) => 'The latest ${shown} of ${total}',
			'mine.error' => 'Your contributions could not be loaded. A connection is needed.',
			'mine.deleteTitle' => 'Delete this contribution?',
			'mine.deleteBody' => 'It is removed from Lunaway.',
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
			'mine.newVendingMachine' => 'New vending machine',
			'mine.poiConfirmations' => 'Shops and services confirmed',
			'mine.aPoi' => 'A shop or service',
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
			'outbox.kind.photo' => 'Photo',
			'outbox.kind.deletePhoto' => 'Deleting a photo',
			'outbox.kind.mute' => 'Hiding an author',
			'outbox.kind.unmute' => 'Showing an author again',
			'outbox.kind.poiThere' => 'Still there: a shop or service',
			'outbox.kind.poiGone' => 'Gone: a shop or service',
			'outbox.kind.addVendingMachine' => 'New vending machine',
			'outbox.kind.deletePoiConfirmation' => 'Deletion of an answer about a shop or service',
			'outbox.kind.reportRoadEvent' => ({required Object kind}) => 'Road report: ${kind}',
			'outbox.kind.clearRoadEvent' => 'A road report said over',
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
			'outbox.error.duplicate' => 'Refused: the same machine is already listed within 25 m.',
			'outbox.sent' => 'Thank you, it is sent',
			'outbox.queued' => 'No connection: it will be sent once you are back online',
			'outbox.refused' => ({required Object reason}) => 'Not sent. ${reason}',
			'placement.title' => 'Place the spot',
			'placement.hint' => 'Move the map: the crosshair marks the exact spot.',
			'placement.confirm' => 'Use this spot',
			'placement.duplicate' => ({required Object name, required Object distance}) => '“${name}” is already ${distance} away: is it the same spot?',
			'placement.same' => 'Yes, open its page',
			'placement.notSame' => 'No, it is another place',
			'contribute.yourRating' => 'Your rating',
			'contribute.rateHint' => 'Tap a star to rate',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Rate ${n} star', other: 'Rate ${n} stars', ), 
			'contribute.writeReview' => 'Write a review',
			'contribute.editReview' => 'Edit your review',
			'contribute.deleteReview' => 'Delete your review',
			'contribute.deleteReviewTitle' => 'Delete your review?',
			'contribute.deleteReviewBody' => 'The text and the rating are removed from the page.',
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
			'contribute.toVerifyBody' => 'Added by the community, waiting for two confirmations. Know it? Confirm it.',
			'contribute.issuesTitle' => 'Reports from the last 30 days',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlaceHere' => 'Create a place here',
			'contribute.addPlaceHint' => 'The spot set under the crosshair.',
			'confirmSheet.title' => 'Still there?',
			'confirmSheet.body' => 'Been there recently? Your answer tells the next travellers the page is up to date. No position is sent.',
			'confirmSheet.stillOk' => 'Yes, as described',
			'confirmSheet.closed' => 'Closed',
			'confirmSheet.changed' => 'Changed',
			'confirmSheet.closedHint' => 'No longer takes visitors',
			'confirmSheet.changedHint' => 'Still there, but something changed',
			'confirmSheet.note' => 'Anything to add? (optional)',
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
			'issueSheet.note' => 'Anything to add? (optional)',
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
			'reportSheet.sent' => 'Thank you, the moderators will take a look',
			'reportSheet.mute' => ({required Object name}) => 'Hide reviews and photos by ${name}',
			'reportSheet.muteAuthor' => 'Hide this author',
			'reportSheet.muteTitle' => ({required Object name}) => 'Hide ${name}?',
			'reportSheet.muteBody' => 'Their reviews and photos will no longer show for you. You can change your mind in your profile.',
			'reportSheet.muted' => ({required Object name}) => '${name} is hidden',
			'reportSheet.deletePhoto' => 'Delete my photo',
			'reportSheet.deletePhotoTitle' => 'Delete this photo?',
			'reportSheet.deletePhotoBody' => 'It is removed from the page and from our servers.',
			'reviewSheet.titleNew' => 'Your review',
			'reviewSheet.titleEdit' => 'Edit your review',
			'reviewSheet.starsRequired' => 'Choose a rating from 1 to 5',
			'reviewSheet.text' => 'Your review',
			'reviewSheet.textHint' => 'The quiet, the welcome, the room to manoeuvre, what was useful',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'At least ${n} more character', other: 'At least ${n} more characters', ), 
			'reviewSheet.visited' => 'Date of the stay',
			'reviewSheet.visitedNone' => 'Not given',
			'reviewSheet.vehicle' => 'Your vehicle',
			'reviewSheet.vehicleNone' => 'Prefer not to say',
			'reviewSheet.licence' => 'Published under CC BY 4.0, with your pseudonym. The date of the stay is optional: put together, the dates of your reviews can reveal your route.',
			'reviewSheet.publish' => 'Publish the review',
			'gate.review' => 'Written reviews: from level 1',
			'gate.photo' => 'Photos: from level 1',
			'gate.addPlace' => 'Adding places: from level 2',
			'gate.edit' => 'Suggesting changes: from level 1',
			'gate.why' => 'Levels protect the map from abuse. They come with time and contributions, with nothing to buy.',
			'gate.yourLevel' => ({required Object level}) => 'Your level: ${level}',
			'gate.noAccount' => 'No account yet: an account starts at level 0.',
			'gate.later' => ({required Object level}) => 'Level ${level} comes after the previous ones, with time and published contributions.',
			'gate.meanwhile' => 'Meanwhile, you can rate places, confirm they are still there or report a problem.',
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
			'placeForm.position' => 'Position on the map',
			'placeForm.kind' => 'Kind of place',
			'placeForm.kindRequired' => 'Choose a kind of place',
			'placeForm.name' => 'Name',
			'placeForm.nameHint' => 'The name shown on site, or a short description',
			'placeForm.nameInvalid' => '2 to 120 characters',
			'placeForm.night' => 'Overnight',
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
			'poi.category.groceries' => 'Groceries',
			'poi.category.vending' => 'Food vending machines',
			'poi.category.water' => 'Water and dump',
			'poi.category.fuel' => 'Fuel and energy',
			'poi.category.health' => 'Health',
			'poi.category.services' => 'Services',
			'poi.category.food' => 'Restaurants and cafés',
			'poi.category.sights' => 'Sights',
			'poi.kind.supermarket' => 'Supermarket',
			'poi.kind.convenience' => 'Convenience store',
			'poi.kind.bakery' => 'Bakery',
			'poi.kind.butcher' => 'Butcher',
			'poi.kind.greengrocer' => 'Greengrocer',
			'poi.kind.farmShop' => 'Farm shop',
			'poi.kind.marketplace' => 'Market',
			'poi.kind.vendingPizza' => 'Pizza vending machine',
			'poi.kind.vendingBread' => 'Bread vending machine',
			'poi.kind.vendingFarmProducts' => 'Farm produce machine',
			'poi.kind.vendingEggsMilk' => 'Eggs or milk machine',
			'poi.kind.vendingIce' => 'Ice machine',
			'poi.kind.vendingOther' => 'Food vending machine',
			'poi.kind.drinkingWater' => 'Drinking water',
			'poi.kind.waterPoint' => 'Water point',
			'poi.kind.dumpStation' => 'Dump station',
			'poi.kind.toilets' => 'Toilets',
			'poi.kind.shower' => 'Showers',
			'poi.kind.fuelStation' => 'Fuel station',
			'poi.kind.evCharging' => 'Charging station',
			'poi.kind.gasBottles' => 'Gas bottles',
			'poi.kind.pharmacy' => 'Pharmacy',
			'poi.kind.doctor' => 'Doctor',
			'poi.kind.hospital' => 'Hospital',
			'poi.kind.veterinary' => 'Vet',
			'poi.kind.laundry' => 'Laundry',
			'poi.kind.atm' => 'Cash machine',
			'poi.kind.postOffice' => 'Post office',
			'poi.kind.touristOffice' => 'Tourist office',
			'poi.kind.recyclingCentre' => 'Recycling centre',
			'poi.kind.carRepair' => 'Garage',
			'poi.kind.carWash' => 'Vehicle wash',
			'poi.kind.motorhomeShop' => 'Motorhome dealer and workshop',
			'poi.kind.outdoorShop' => 'Camping and outdoor shop',
			'poi.kind.restaurant' => 'Restaurant',
			'poi.kind.cafe' => 'Café',
			'poi.kind.fastFood' => 'Fast food',
			'poi.kind.viewpoint' => 'Viewpoint',
			'poi.kind.attraction' => 'Attraction',
			'poi.kind.museum' => 'Museum',
			'poi.chipsLabel' => 'Shops and services around',
			'poi.openNow' => 'Open now',
			'poi.vendingSells.pizza' => 'Pizza',
			'poi.vendingSells.bread' => 'Bread',
			'poi.vendingSells.farmProducts' => 'Farm produce',
			'poi.vendingSells.eggsMilk' => 'Eggs and milk',
			'poi.vendingSells.ice' => 'Ice',
			'poi.vendingAll' => 'All food vending machines',
			'poi.vendingMenu' => 'What the machines sell',
			'poi.vendingChip.pizza' => 'Pizza vending machines',
			'poi.vendingChip.bread' => 'Bread vending machines',
			'poi.vendingChip.farmProducts' => 'Farm produce vending machines',
			'poi.vendingChip.eggsMilk' => 'Egg and milk vending machines',
			'poi.vendingChip.ice' => 'Ice vending machines',
			'poi.alwaysOpen' => 'Open day and night',
			'poi.hoursUnknown' => 'Opening hours unknown',
			'poi.maybeClosed' => 'Closed according to the official register of health facilities (FINESS).',
			'poi.maybeClosedSince' => ({required Object date}) => 'Listed as closed by FINESS since ${date}: it may have shut for good.',
			'poi.seasonal' => 'Seasonal: it may be shut in winter.',
			'poi.fee' => 'Fee',
			'poi.free' => 'Free',
			'poi.stillThereTitle' => 'Still there?',
			'poi.stillThereHint' => 'Seen it lately? Your answer helps the next travellers. No position is sent.',
			'poi.stillThere' => 'Still there',
			'poi.gone' => 'Gone',
			'poi.lastConfirmed' => ({required Object when}) => 'Confirmed there ${when}',
			'poi.checkedOn' => ({required Object date}) => 'Checked on the spot on ${date}',
			'poi.thanksThere' => 'Thank you, noted: still there.',
			'poi.thanksGone' => 'Thank you, noted: gone.',
			'poi.fuelPrices' => 'Fuel prices',
			'poi.perLitre' => ({required Object price}) => '${price}/L',
			'poi.priceUpdated' => ({required Object when}) => 'Price updated ${when}',
			'poi.feedRead' => ({required Object when}) => 'Prices checked ${when}',
			'poi.shortageTemporary' => 'Out of stock for now',
			'poi.shortageDefinitive' => 'No longer sold',
			'poi.selfService24h' => 'Pay at pump 24/7',
			'poi.highway' => 'On a motorway',
			'poi.lpgYes' => 'Sells LPG',
			'poi.fuel.diesel' => 'Diesel',
			'poi.fuel.sp95' => 'Unleaded 95',
			'poi.fuel.e10' => 'E10',
			'poi.fuel.sp98' => 'Unleaded 98',
			'poi.fuel.e85' => 'E85',
			'poi.fuel.lpg' => 'LPG',
			'poi.products' => 'Sells',
			'poi.paymentTitle' => 'Payment',
			'poi.product.pizza' => 'Pizza',
			'poi.product.bread' => 'Bread',
			'poi.product.eggs' => 'Eggs',
			'poi.product.milk' => 'Milk',
			'poi.product.cheese' => 'Cheese',
			'poi.product.meat' => 'Meat',
			'poi.product.vegetables' => 'Vegetables',
			'poi.product.fruit' => 'Fruit',
			'poi.product.honey' => 'Honey',
			'poi.product.ice' => 'Ice',
			'poi.product.potatoes' => 'Potatoes',
			'poi.product.food' => 'Food',
			'poi.payment.cash' => 'Cash',
			'poi.payment.coins' => 'Coins',
			'poi.payment.notes' => 'Notes',
			'poi.payment.cards' => 'Card',
			'poi.payment.contactless' => 'Contactless',
			'poi.payment.app' => 'Phone app',
			'poi.justNow' => 'just now',
			'poi.minutesAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} minute ago', other: '${n} minutes ago', ), 
			'poi.hoursAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} hour ago', other: '${n} hours ago', ), 
			'poi.readOffline' => ({required Object when}) => 'Checked ${when}: no connection to refresh it',
			'poi.readStale' => ({required Object when}) => 'Checked ${when}: it could not be refreshed just now.',
			'poi.goneTitle' => 'This point is no longer on the map',
			'poi.goneHint' => 'Travellers said it is gone, or the last update removed it.',
			'poi.loadError' => 'The details could not be loaded. What the map knows is above.',
			'poi.around' => 'Around this place',
			'poi.aroundEmpty' => 'No shop or service known around here.',
			'poi.aroundError' => 'The shops and services nearby could not be loaded.',
			'poi.aroundOffline' => 'No connection: the shops and services nearby will show once you are online.',
			'poi.onSite' => 'On site',
			'poi.backTo' => ({required Object name}) => 'Back to ${name}',
			'poi.backToPlace' => 'Back to the place',
			'poi.linkError' => 'This shop or service could not be opened: no network, or it is no longer on the map.',
			'poi.searchSection' => 'Shops and services',
			'poi.searching' => 'Looking for shops and services',
			'poi.searchOffline' => 'Shops and services are searched online: no network now.',
			'poi.add.title' => 'A vending machine here?',
			'poi.add.hint' => 'Pick what it sells: it goes on the map for every traveller.',
			'poi.add.pizza' => 'Pizza',
			'poi.add.bread' => 'Bread',
			'poi.add.other' => 'Other food',
			'poi.add.gate' => 'Adding a vending machine',
			'poi.add.sent' => 'Thank you: the machine shows on the map within a few minutes.',
			'poi.add.duplicateTitle' => 'Already on the map',
			'poi.add.duplicateBody' => 'A machine of the same kind is already listed within 25 m. Is it still there?',
			'poi.add.duplicateThere' => 'Yes, still there',
			'poi.add.duplicateGone' => 'No, it is gone',
			'poi.cheapest.title' => 'Cheapest around me',
			'poi.cheapest.show' => 'Cheapest around',
			'poi.cheapest.zoomIn' => 'Zoom in to compare the stations\' prices.',
			'poi.cheapest.none' => 'No station on the map sells this fuel.',
			'poi.cheapest.noneHint' => 'Move the map or pick another fuel.',
			'poi.cheapest.error' => 'The stations\' prices could not be loaded.',
			'poi.trend.title' => ({required Object fuel}) => '${fuel}: prices of the last days',
			'poi.trend.none' => 'Lunaway has not seen a price of this fuel here yet.',
			'poi.trend.failed' => 'The prices of the last days could not be read now.',
			'poi.trend.week' => 'Last 7 days:',
			'poi.trend.month' => 'Last 30 days:',
			'poi.trend.range' => ({required Object low, required Object high}) => 'from ${low} to ${high}',
			'poi.trend.span' => ({required Object range, required Object move}) => '${range}, ${move}',
			'poi.trend.oneDay' => 'one day seen',
			'poi.trend.steady' => 'unchanged',
			'poi.trend.down' => ({required Object amount}) => 'down ${amount}',
			'poi.trend.up' => ({required Object amount}) => 'up ${amount}',
			'poi.trend.since' => ({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} day seen since ${date}, as Lunaway reads the feed; a day not seen stays empty', other: '${n} days seen since ${date}, as Lunaway reads the feed; a day not seen stays empty', ), 
			'poi.marketDays' => 'Market days',
			'poi.vehicles.motorhomeYes' => 'Takes motorhomes',
			'poi.vehicles.motorhomeNo' => 'No motorhomes',
			'poi.vehicles.hgvYes' => 'Takes heavy goods vehicles',
			'poi.vehicles.hgvNo' => 'No heavy goods vehicles',
			'poi.vehicles.maxHeight' => ({required Object height}) => 'Height limit: ${height}',
			'offlineMaps.title' => 'Offline maps',
			'offlineMaps.intro' => 'Before you leave, keep a region on the device: its places to search and choose, its map to see the streets without network.',
			'offlineMaps.webTitle' => 'Offline maps are in the app',
			'offlineMaps.web' => 'The Android and iOS apps keep regions for the road. In a browser, the map needs the network.',
			'offlineMaps.desktopTitle' => 'Offline maps are on the phone',
			'offlineMaps.desktop' => 'The Android and iOS apps keep regions for the road. On a computer, the map needs the network.',
			'offlineMaps.unreadable' => 'The offline maps of this device could not be loaded.',
			'offlineMaps.none' => 'No region on this device yet.',
			'offlineMaps.used' => ({required Object size}) => 'Space used: ${size}',
			'offlineMaps.downloads' => 'Downloading',
			'offlineMaps.installed' => 'On this device',
			'offlineMaps.suggested' => 'Suggested',
			'offlineMaps.here' => 'Where you are',
			'offlineMaps.favoritesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${n} favourite here', other: '${n} favourites here', ), 
			'offlineMaps.france' => 'France',
			'offlineMaps.overseas' => 'Overseas France',
			'offlineMaps.countries' => 'Countries',
			'offlineMaps.downloadNamed' => ({required Object name, required Object size}) => 'Download ${name}, ${size}',
			'offlineMaps.pause' => 'Pause',
			'offlineMaps.resume' => 'Resume',
			'offlineMaps.cancel' => 'Stop and remove the download',
			'offlineMaps.waiting' => 'Waiting for its turn',
			'offlineMaps.progress' => ({required Object done, required Object total}) => '${done} of ${total}',
			'offlineMaps.paused' => ({required Object done, required Object total}) => 'Paused at ${done} of ${total}',
			'offlineMaps.verifying' => 'Checking the file',
			'offlineMaps.failedNetwork' => 'Stopped: no network. It resumes where it stopped once the network is back.',
			'offlineMaps.failedServer' => 'The server sent something other than the map. Try again later.',
			'offlineMaps.failedCorrupt' => 'The file arrived damaged and was removed. Try again.',
			'offlineMaps.failedStorage' => 'Not enough room left on the device. Free some space, then try again.',
			'offlineMaps.keepOpen' => 'Keep the app open while it downloads: it stops when the app goes to the background and resumes when you come back.',
			'offlineMaps.dataOf' => ({required Object date}) => 'data from ${date}',
			'offlineMaps.update' => ({required Object size}) => 'Update, ${size}',
			'offlineMaps.deleteNamed' => ({required Object name}) => 'Delete ${name}',
			'offlineMaps.deleteTitle' => ({required Object name}) => 'Delete ${name} from this device?',
			'offlineMaps.deleteBody' => 'It will no longer show without network. You can download it again.',
			'offlineMaps.listOffline' => 'The list of regions needs the network.',
			'offlineMaps.listCopy' => 'List kept from the last connection.',
			'offlineMaps.entryHint' => 'To travel without network',
			'offlineMaps.entryCount' => ({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Maps: ${n} region, ${size}', other: 'Maps: ${n} regions, ${size}', ), 
			'offlineMaps.noticePack' => ({required Object name}) => 'Offline: downloaded map, ${name}',
			'offlineMaps.noticeOutside' => 'Offline: this area is not downloaded',
			'offlineMaps.noticePlacesOnly' => 'Offline: places on the device, the map of this area to download',
			'offlineMaps.noticeNone' => 'Offline: download a region for next time',
			'offlineMaps.noticeOnline' => 'Offline: the map needs the network',
			'offlineMaps.placesTitle' => 'Places',
			'offlineMaps.placesHint' => 'A few megabytes per region: the list, the search, the place pages and the filters work without network.',
			'offlineMaps.mapsTitle' => 'Maps',
			'offlineMaps.mapsHint' => 'Every street, a few hundred megabytes per region: the map shows without network.',
			'offlineMaps.entryPlaces' => ({required Object names}) => 'Places: ${names}',
			'offlineMaps.entryPlacesCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Places: ${n} region', other: 'Places: ${n} regions', ), 
			'regions.pickerTitle' => 'Which places to keep on this device?',
			'regions.pickerIntro' => 'Each region downloads once, then updates in small pieces. You can add or remove regions later in Offline maps.',
			'regions.nearYou' => ({required Object name}) => 'Near you: ${name}',
			'regions.findMine' => 'Find my region',
			'regions.locating' => 'Looking for your region',
			'regions.notCovered' => 'No Lunaway region around you yet',
			'regions.wholeFrance' => 'All of France',
			'regions.showFrance' => 'Show the regions of France',
			'regions.hideFrance' => 'Hide the regions of France',
			'regions.packInfo' => ({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: '${count} place, ${size}', other: '${count} places, ${size}', ), 
			'regions.noPack' => 'No pack: places come with the updates, size unknown',
			'regions.download' => ({required Object size}) => 'Download, ${size}',
			'regions.unavailable' => 'The server does not offer regions yet: Lunaway keeps all of France.',
			'regions.listFailed' => 'The list of regions needs the network.',
			'regions.choose' => 'Choose the regions',
			'regions.noneKept' => 'No region kept: the map has no places offline.',
			'regions.change' => 'Add or remove regions',
			'regions.removeNamed' => ({required Object name}) => 'Remove ${name}',
			'regions.removed' => ({required Object name}) => '${name}: places removed from this device',
			'regions.downloading' => ({required Object done, required Object total}) => 'Downloading, ${done} of ${total}',
			'regions.updating' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('en'))(n, one: 'Updating, ${count} place', other: 'Updating, ${count} places', ), 
			'regions.waiting' => 'waiting for its download',
			'regions.downloadingNamed' => ({required Object name}) => 'Downloading the places: ${name}',
			'regions.updated' => ({required Object when}) => 'updated ${when}',
			'regions.offerTitle' => ({required Object name}) => '${name}: keep its places offline?',
			'regions.downloadThis' => 'Download this region',
			'regions.notHere' => ({required Object name}) => '${name} is not on this device',
			'regions.updatesOnMobile' => 'Update over mobile data',
			'regions.updatesOnMobileHint' => 'Otherwise the regions already downloaded update on Wi-Fi. A new download goes over any network.',
			'roadReport.actionHint' => 'Report a problem on the road',
			'roadReport.title' => 'What do you see on the road?',
			'roadReport.intro' => 'Your report warns other travellers. When two trusted accounts report the same thing, routes avoid it. Police checks are not reported.',
			'roadReport.kinds.closure' => 'Road closed',
			'roadReport.kinds.works' => 'Roadworks',
			'roadReport.kinds.narrowPassage' => 'Narrow passage',
			'roadReport.kinds.lowClearance' => 'Low clearance',
			'roadReport.kinds.other' => 'Road problem',
			'roadReport.height' => ({required Object value}) => 'Signed height: ${value}',
			'roadReport.send' => 'Report',
			'roadReport.sent' => 'Thank you: other travellers are warned.',
			_ => null,
		} ?? switch (path) {
			'roadReport.stillThere' => 'Still there',
			'roadReport.over' => 'It\'s over',
			'roadReport.overSent' => 'Thank you: noted.',
			'roadReport.fromMap' => 'Report a problem here',
			'roadReport.notHereTitle' => 'No report here',
			'roadReport.lower' => '10 cm lower',
			'roadReport.higher' => '10 cm higher',
			'roadReport.passed' => ({required Object what}) => 'You just passed: ${what}. Still there?',
			'roadReport.notHere' => ({required Object countries}) => 'Lunaway takes reports where an official feed cross-checks them: ${countries}.',
			'countries.ad' => 'Andorra',
			'countries.at' => 'Austria',
			'countries.ax' => 'Åland',
			'countries.be' => 'Belgium',
			'countries.ch' => 'Switzerland',
			'countries.cz' => 'Czechia',
			'countries.de' => 'Germany',
			'countries.dk' => 'Denmark',
			'countries.eh' => 'Western Sahara',
			'countries.es' => 'Spain',
			'countries.fi' => 'Finland',
			'countries.fr' => 'France',
			'countries.gb' => 'United Kingdom',
			'countries.gi' => 'Gibraltar',
			'countries.gr' => 'Greece',
			'countries.hr' => 'Croatia',
			'countries.ie' => 'Ireland',
			'countries.it' => 'Italy',
			'countries.li' => 'Liechtenstein',
			'countries.lu' => 'Luxembourg',
			'countries.ma' => 'Morocco',
			'countries.mc' => 'Monaco',
			'countries.nl' => 'Netherlands',
			'countries.no' => 'Norway',
			'countries.pl' => 'Poland',
			'countries.pt' => 'Portugal',
			'countries.se' => 'Sweden',
			'countries.si' => 'Slovenia',
			'countries.sj' => 'Svalbard',
			'countries.sm' => 'San Marino',
			'countries.va' => 'Vatican City',
			'areas.ara' => 'Auvergne-Rhône-Alpes',
			'areas.bfc' => 'Bourgogne-Franche-Comté',
			'areas.bre' => 'Brittany',
			'areas.cvl' => 'Centre-Val de Loire',
			'areas.cor' => 'Corsica',
			'areas.ges' => 'Grand Est',
			'areas.hdf' => 'Hauts-de-France',
			'areas.idf' => 'Île-de-France',
			'areas.nor' => 'Normandy',
			'areas.naq' => 'Nouvelle-Aquitaine',
			'areas.occ' => 'Occitania',
			'areas.pdl' => 'Pays de la Loire',
			'areas.pac' => 'Provence-Alpes-Côte d\'Azur',
			'areas.gp' => 'Guadeloupe',
			'areas.mq' => 'Martinique',
			'areas.gf' => 'French Guiana',
			'areas.re' => 'Réunion',
			'areas.yt' => 'Mayotte',
			'areas.franceRest' => 'France, outside any commune',
			_ => null,
		};
	}
}

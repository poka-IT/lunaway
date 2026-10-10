///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsDe extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsDe({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.de,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <de>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsDe _root = this; // ignore: unused_field

	@override 
	TranslationsDe $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsDe(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => 'Lunaway';
	@override late final _Translations$nav$de nav = _Translations$nav$de._(_root);
	@override late final _Translations$common$de common = _Translations$common$de._(_root);
	@override late final _Translations$notices$de notices = _Translations$notices$de._(_root);
	@override late final _Translations$kinds$de kinds = _Translations$kinds$de._(_root);
	@override late final _Translations$families$de families = _Translations$families$de._(_root);
	@override late final _Translations$services$de services = _Translations$services$de._(_root);
	@override late final _Translations$activities$de activities = _Translations$activities$de._(_root);
	@override late final _Translations$amenities$de amenities = _Translations$amenities$de._(_root);
	@override late final _Translations$overnight$de overnight = _Translations$overnight$de._(_root);
	@override late final _Translations$freshness$de freshness = _Translations$freshness$de._(_root);
	@override late final _Translations$map$de map = _Translations$map$de._(_root);
	@override late final _Translations$sync$de sync = _Translations$sync$de._(_root);
	@override late final _Translations$location$de location = _Translations$location$de._(_root);
	@override late final _Translations$search$de search = _Translations$search$de._(_root);
	@override late final _Translations$filters$de filters = _Translations$filters$de._(_root);
	@override late final _Translations$place$de place = _Translations$place$de._(_root);
	@override late final _Translations$sources$de sources = _Translations$sources$de._(_root);
	@override late final _Translations$hours$de hours = _Translations$hours$de._(_root);
	@override late final _Translations$directions$de directions = _Translations$directions$de._(_root);
	@override late final _Translations$navigation$de navigation = _Translations$navigation$de._(_root);
	@override late final _Translations$list$de list = _Translations$list$de._(_root);
	@override late final _Translations$favorites$de favorites = _Translations$favorites$de._(_root);
	@override late final _Translations$vehicle$de vehicle = _Translations$vehicle$de._(_root);
	@override late final _Translations$vehicleHeight$de vehicleHeight = _Translations$vehicleHeight$de._(_root);
	@override late final _Translations$profile$de profile = _Translations$profile$de._(_root);
	@override late final _Translations$units$de units = _Translations$units$de._(_root);
	@override late final _Translations$languages$de languages = _Translations$languages$de._(_root);
	@override late final _Translations$translation$de translation = _Translations$translation$de._(_root);
	@override late final _Translations$locale$de locale = _Translations$locale$de._(_root);
	@override late final _Translations$account$de account = _Translations$account$de._(_root);
	@override late final _Translations$recovery$de recovery = _Translations$recovery$de._(_root);
	@override late final _Translations$recover$de recover = _Translations$recover$de._(_root);
	@override late final _Translations$deletion$de deletion = _Translations$deletion$de._(_root);
	@override late final _Translations$devices$de devices = _Translations$devices$de._(_root);
	@override late final _Translations$muted$de muted = _Translations$muted$de._(_root);
	@override late final _Translations$mine$de mine = _Translations$mine$de._(_root);
	@override late final _Translations$outbox$de outbox = _Translations$outbox$de._(_root);
	@override late final _Translations$placement$de placement = _Translations$placement$de._(_root);
	@override late final _Translations$contribute$de contribute = _Translations$contribute$de._(_root);
	@override late final _Translations$confirmSheet$de confirmSheet = _Translations$confirmSheet$de._(_root);
	@override late final _Translations$issueSheet$de issueSheet = _Translations$issueSheet$de._(_root);
	@override late final _Translations$reportSheet$de reportSheet = _Translations$reportSheet$de._(_root);
	@override late final _Translations$reviewSheet$de reviewSheet = _Translations$reviewSheet$de._(_root);
	@override late final _Translations$gate$de gate = _Translations$gate$de._(_root);
	@override late final _Translations$photoFlow$de photoFlow = _Translations$photoFlow$de._(_root);
	@override late final _Translations$placeForm$de placeForm = _Translations$placeForm$de._(_root);
	@override late final _Translations$favoritesSync$de favoritesSync = _Translations$favoritesSync$de._(_root);
	@override late final _Translations$poi$de poi = _Translations$poi$de._(_root);
	@override late final _Translations$offlineMaps$de offlineMaps = _Translations$offlineMaps$de._(_root);
	@override late final _Translations$regions$de regions = _Translations$regions$de._(_root);
	@override late final _Translations$roadReport$de roadReport = _Translations$roadReport$de._(_root);
	@override late final _Translations$countries$de countries = _Translations$countries$de._(_root);
	@override late final _Translations$areas$de areas = _Translations$areas$de._(_root);
}

// Path: nav
class _Translations$nav$de extends Translations$nav$en {
	_Translations$nav$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get map => 'Karte';
	@override String get favorites => 'Favoriten';
	@override String get profile => 'Profil';
	@override String get fold => 'Menü einklappen';
	@override String get unfold => 'Menü ausklappen';
}

// Path: common
class _Translations$common$de extends Translations$common$en {
	_Translations$common$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get close => 'Schließen';
	@override String get done => 'Fertig';
	@override String get cancel => 'Abbrechen';
	@override String get retry => 'Erneut versuchen';
	@override String get save => 'Speichern';
	@override String get delete => 'Löschen';
	@override String get undo => 'Rückgängig';
	@override String get ok => 'Verstanden';
	@override String get saveFailed => 'Die Änderung konnte nicht gespeichert werden.';
	@override String get send => 'Senden';
	@override String get later => 'Später';
	@override String get next => 'Weiter';
	@override String get failed => 'Das hat nicht geklappt. Versuchen Sie es gleich noch einmal.';
	@override String get offline => 'Zurzeit keine Verbindung. Versuchen Sie es erneut, sobald Sie wieder online sind.';
}

// Path: notices
class _Translations$notices$de extends Translations$notices$en {
	_Translations$notices$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get close => 'Hinweis schließen';
	@override String get fold => 'Hinweis einklappen';
	@override String get unfold => 'Hinweis anzeigen';
}

// Path: kinds
class _Translations$kinds$de extends Translations$kinds$en {
	_Translations$kinds$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get motorhomeArea => 'Wohnmobil-Stellplatz';
	@override String get serviceArea => 'Ver- und Entsorgungsstation';
	@override String get campsite => 'Campingplatz';
	@override String get parking => 'Parkplatz';
	@override String get nature => 'Platz in freier Natur';
	@override String get restArea => 'Rastplatz';
	@override String get picnicArea => 'Picknickplatz';
	@override String get farm => 'Stellplatz auf dem Bauernhof';
	@override String get homestay => 'Stellplatz bei Privatleuten';
	@override String get offRoad => 'Offroad-Platz';
	@override String get extraService => 'Servicestopp';
}

// Path: families
class _Translations$families$de extends Translations$families$en {
	_Translations$families$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get stopovers => 'Stell- und Parkplätze';
	@override String get stopoversHint => 'Stellplätze, Parkplätze, Rastplätze';
	@override String get campsites => 'Camping und Gastgeber';
	@override String get campsitesHint => 'Campingplätze, Bauernhöfe, Privatleute';
	@override String get nature => 'Natur';
	@override String get natureHint => 'Plätze in freier Natur, Offroad-Pisten';
	@override String get services => 'Ver- und Entsorgung';
	@override String get servicesHint => 'Wasser und Entsorgung, keine Übernachtung';
}

// Path: services
class _Translations$services$de extends Translations$services$en {
	_Translations$services$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get drinkingWater => 'Trinkwasser';
	@override String get greyWater => 'Grauwasserentsorgung';
	@override String get blackWater => 'Kassettenentleerung';
	@override String get wasteBin => 'Mülleimer';
	@override String get toilets => 'Toiletten';
	@override String get showers => 'Duschen';
	@override String get electricity => 'Strom';
	@override String get wifi => 'WLAN';
	@override String get laundry => 'Waschmaschine';
	@override String get lpg => 'Autogas (LPG)';
	@override String get gasBottles => 'Gasflaschen';
	@override String get vehicleWash => 'Fahrzeugwäsche';
	@override String get bakery => 'Bäckerei';
	@override String get swimmingPool => 'Schwimmbad';
	@override String get petsAllowed => 'Haustiere willkommen';
	@override String get mobileData => 'Mobiles Internet';
	@override String get winterCaravanning => 'Im Winter geöffnet';
}

// Path: activities
class _Translations$activities$de extends Translations$activities$en {
	_Translations$activities$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get monuments => 'Sehenswürdigkeiten';
	@override String get windsurfKitesurf => 'Windsurfen, Kitesurfen';
	@override String get mountainBiking => 'Mountainbiken';
	@override String get hiking => 'Wandern';
	@override String get climbing => 'Klettern';
	@override String get canoeKayak => 'Kanu, Kajak';
	@override String get fishing => 'Angeln';
	@override String get shoreFishing => 'Muscheln sammeln bei Ebbe';
	@override String get swimming => 'Baden';
	@override String get motorcycling => 'Motorradtouren';
	@override String get viewpoint => 'Aussichtspunkt';
	@override String get playground => 'Spielplatz';
}

// Path: amenities
class _Translations$amenities$de extends Translations$amenities$en {
	_Translations$amenities$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get water => 'Wasser';
	@override String get dumpStation => 'Entsorgung';
	@override String get electricity => 'Strom';
	@override String get toilets => 'Toiletten';
	@override String get showers => 'Duschen';
	@override String get wasteBin => 'Mülleimer';
	@override String get laundry => 'Waschmaschine';
	@override String get wifi => 'WLAN';
	@override String get lpg => 'Autogas (LPG)';
}

// Path: overnight
class _Translations$overnight$de extends Translations$overnight$en {
	_Translations$overnight$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Übernachten erlaubt';
	@override String get tolerated => 'Übernachten geduldet';
	@override String get dayOnly => 'Nur tagsüber';
	@override String get forbidden => 'Übernachten verboten';
	@override String get unknown => 'Übernachten: keine Angabe';
	@override String get allowedHint => 'Sie dürfen hier übernachten.';
	@override String get toleratedHint => 'Eine Nacht wird meist geduldet. Bleiben Sie unauffällig und hinterlassen Sie keine Spuren.';
	@override String get dayOnlyHint => 'Parken nur tagsüber. Suchen Sie sich für die Nacht einen anderen Platz.';
	@override String get forbiddenHint => 'Übernachten ist hier verboten.';
	@override String get unknownHint => 'Dazu gibt es noch keine Angabe. Fragen Sie vor Ort nach.';
}

// Path: freshness
class _Translations$freshness$de extends Translations$freshness$en {
	_Translations$freshness$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String confirmed({required Object when}) => 'Zuletzt von Reisenden bestätigt: ${when}';
	@override String get unconfirmed => 'Noch nicht von Reisenden bestätigt';
	@override String get stale => 'Zuletzt vor über einem Jahr bestätigt';
	@override String get today => 'heute';
	@override String daysAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'gestern',
		other: 'vor ${n} Tagen',
	);
	@override String monthsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'vor einem Monat',
		other: 'vor ${n} Monaten',
	);
	@override String yearsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'vor einem Jahr',
		other: 'vor ${n} Jahren',
	);
}

// Path: map
class _Translations$map$de extends Translations$map$en {
	_Translations$map$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get searchHint => 'Platz oder Ort';
	@override String get clearSearch => 'Suche löschen';
	@override String get locateMe => 'Meinen Standort anzeigen';
	@override String get aroundMe => 'Plätze in meiner Nähe anzeigen';
	@override String get zoomIn => 'Vergrößern';
	@override String get zoomOut => 'Verkleinern';
	@override String get filters => 'Filter';
	@override String get credit => '© OpenStreetMap · Protomaps';
	@override String get creditLabel => 'Kartennachweis: © OpenStreetMap-Mitwirkende, Kartenstil Protomaps. Öffnet die Urheberrechtsseite von OpenStreetMap.';
	@override String get creditPhotos => 'Fotos: Externe Community-Quelle';
	@override String get creditPhotosLabel => 'Kartennachweis: © OpenStreetMap-Mitwirkende, Kartenstil Protomaps; Fotos: Externe Community-Quelle. Öffnet die Urheberrechtsseite von OpenStreetMap.';
	@override String get showList => 'Liste';
	@override String showListCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Liste (${n})',
		other: 'Liste (${n})',
	);
	@override String placesHereLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Platz hier',
		other: 'Plätze hier',
	);
	@override String nearestYouLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Platz in Ihrer Nähe',
		other: 'Plätze in Ihrer Nähe',
	);
	@override String nearestCentreLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Platz nahe der Kartenmitte',
		other: 'Plätze nahe der Kartenmitte',
	);
	@override String get pointTitle => 'Hier';
	@override String get pointHint => 'Punkt auf der Karte';
	@override String get directionsHere => 'Route hierher';
	@override String get startHere => 'Von hier starten';
	@override String get departureChosen => 'Start gewählt. Öffnen Sie jetzt das Ziel und seine Route.';
	@override String get copyCoordinates => 'Koordinaten kopieren';
	@override String get freeTapHint => 'Tippen Sie auf die Karte, um dorthin zu fahren oder dort einen Platz hinzuzufügen';
	@override String get freeTapHintClick => 'Klicken Sie auf die Karte, um dorthin zu fahren oder dort einen Platz hinzuzufügen';
	@override String get addPlaceAtCenter => 'Platz in der Kartenmitte hinzufügen';
	@override String addressSource({required Object attribution}) => 'Quelle: ${attribution}';
	@override String get placesAround => 'Plätze in der Umgebung';
	@override String get downloading => 'Plätze in Frankreich werden heruntergeladen';
	@override String downloadingCount({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${count} Platz geladen',
		other: '${count} Plätze geladen',
	);
	@override String get noData => 'Noch keine Plätze auf diesem Gerät';
	@override String get noDataHint => 'Laden Sie die Plätze einmal herunter: Danach funktioniert die Karte ohne Netz.';
	@override String get download => 'Plätze herunterladen';
	@override String get downloadFailed => 'Der Download wurde unterbrochen';
	@override String get demoBanner => 'Demo: erfundene Plätze';
	@override String get unsupported => 'Die Karte ist auf diesem System nicht verfügbar. Nutzen Sie die Web-App.';
}

// Path: sync
class _Translations$sync$de extends Translations$sync$en {
	_Translations$sync$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get failedOffline => 'Zurzeit keine Verbindung.';
	@override String get failedBusy => 'Der Server ist stark ausgelastet.';
	@override String get failedServer => 'Der Server hat gerade ein Problem.';
	@override String get failedOther => 'Die Aktualisierung ist fehlgeschlagen.';
	@override String get failedRefused => 'Der Server hat die Aktualisierung abgelehnt. Möglicherweise ist eine neuere Version der App nötig.';
	@override String get willRetry => 'Lunaway versucht es automatisch erneut.';
	@override String incomplete({required Object count}) => 'Download unvollständig: bisher ${count} Plätze';
	@override String get incompleteShort => 'Download unvollständig';
	@override String resuming({required Object count}) => 'Download läuft: ${count} Plätze';
	@override String get resume => 'Fortsetzen';
}

// Path: location
class _Translations$location$de extends Translations$location$en {
	_Translations$location$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get rationaleTitle => 'Ihren Standort anzeigen?';
	@override String get rationale => 'Lunaway nutzt ihn, um die Karte auf Sie zu zentrieren, Plätze nach Entfernung zu sortieren und Sie zu navigieren. Für eine Route wird Ihr Standort an den Server von Lunaway gesendet, der ihn nicht speichert. Für den günstigsten Kraftstoff in Ihrer Umgebung wird nur ein auf etwa 5 km gerundeter Standort gesendet. Eine Straßenmeldung wird mit dem Ort gesendet, an dem Sie sie abgeben.';
	@override String get allow => 'Weiter';
	@override String get notNow => 'Nicht jetzt';
	@override String get deniedTitle => 'Standort für Lunaway ausgeschaltet';
	@override String get denied => 'Sie haben den Zugriff auf Ihren Standort abgelehnt. Um ihn zu nutzen, erlauben Sie den Zugriff in den Geräteeinstellungen.';
	@override String get openSettings => 'Einstellungen öffnen';
	@override String get serviceOffTitle => 'Standort ist ausgeschaltet';
	@override String get serviceOff => 'Der Standort ist auf diesem Gerät ausgeschaltet. Schalten Sie ihn in den Schnelleinstellungen ein und versuchen Sie es dann erneut.';
	@override String get notAllowed => 'Kein Zugriff auf Ihren Standort. Die Karte funktioniert auch ohne.';
	@override String get noFix => 'Ihr Standort lässt sich noch nicht bestimmen. Versuchen Sie es unter freiem Himmel oder gleich noch einmal.';
	@override String get unsupported => 'Dieses Gerät kann seinen Standort nicht bestimmen.';
	@override String get browserDeniedTitle => 'Der Browser blockiert Ihren Standort';
	@override String get browserDenied => 'Der Browser gibt Ihren Standort nicht an Lunaway weiter. Öffnen Sie links in der Adressleiste das Symbol (Schloss oder Regler), stellen Sie „Standort“ auf „Zulassen“ und fragen Sie Ihren Standort dann erneut über seine Schaltfläche ab.';
	@override String get browserNoFix => 'Der Browser hat keinen Standort geliefert. Versuchen Sie es gleich noch einmal; an einem Computer hilft WLAN bei der Ortung.';
}

// Path: search
class _Translations$search$de extends Translations$search$en {
	_Translations$search$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get towns => 'Orte';
	@override String get places => 'Plätze';
	@override String noResult({required Object query}) => 'Kein Platz und kein Ort passt zu „${query}“.';
	@override String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Platz',
		other: '${n} Plätze',
	);
	@override String get addresses => 'Adressen';
	@override String get addressesSearching => 'Adressen werden gesucht';
	@override String get addressesFailed => 'Adressen können gerade nicht gesucht werden.';
	@override String addressSources({required Object sources}) => 'Adressen: ${sources}';
	@override String get offline => 'Keine Verbindung: Die Suche braucht das Netz.';
	@override late final _Translations$search$addressKind$de addressKind = _Translations$search$addressKind$de._(_root);
	@override String get deviceOnly => 'Der Server antwortet nicht: Die Suche beschränkt sich auf die heruntergeladenen Regionen.';
}

// Path: filters
class _Translations$filters$de extends Translations$filters$en {
	_Translations$filters$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filter';
	@override String get families => 'Art des Platzes';
	@override String get familiesHint => 'Keine Auswahl: alle Arten';
	@override String get familiesChosenHint => 'Nur diese Arten';
	@override String get night => 'Übernachtung';
	@override String get nightHint => 'Keine Auswahl: alle Plätze';
	@override String get nightChosenHint => 'Nur Plätze mit diesem Status';
	@override String get nightPossible => 'Übernachten möglich';
	@override String get amenities => 'Ausstattung';
	@override String get amenitiesHint => 'Der Platz muss alles davon bieten';
	@override String get rating => 'Mindestbewertung';
	@override String get ratingHint => 'Die Bewertung der Lunaway-Reisenden oder, falls diese den Platz nicht bewertet haben, die der anderen Quellen. Plätze ohne Bewertung werden ausgeblendet.';
	@override String ratingAtLeast({required Object rating}) => 'ab ${rating}';
	@override String get opening => 'Öffnungszeiten';
	@override String get openingHint => 'Orte, deren Öffnungszeiten nicht bekannt sind, werden weiter angezeigt.';
	@override String get openingAllYear => 'Ganzjährig';
	@override String get openingDates => 'Meine Reisedaten';
	@override String get openingClearDates => 'Reisedaten löschen';
	@override String openingStay({required Object from, required Object to}) => '${from} bis ${to}';
	@override String openingStayDay({required Object date}) => 'Am ${date}';
	@override String get openingStayTitle => 'Daten Ihres Aufenthalts';
	@override String get openingArrival => 'Ankunft';
	@override String get openingDeparture => 'Abreise';
	@override String get price => 'Preis pro Nacht';
	@override String get freeOnly => 'Kostenlos';
	@override String get freeHint => 'Nur Plätze, an denen die Übernachtung laut Quellen kostenlos ist';
	@override String get scrollNext => 'Nächste Filter anzeigen';
	@override String get scrollPrevious => 'Vorherige Filter anzeigen';
	@override String get vehicle => 'Mein Fahrzeug';
	@override String get myVehicleFits => 'Mein Fahrzeug passt';
	@override String myVehicleFitsHeight({required Object height}) => 'Passt für ${height}';
	@override String myVehicleHint({required Object height}) => 'Blendet Plätze mit einer Höhenbegrenzung unter ${height} aus. Plätze ohne bekannte Begrenzung bleiben auf der Karte.';
	@override String get reset => 'Zurücksetzen';
	@override String get apply => 'Anwenden';
	@override String show({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		zero: 'Kein passender Platz',
		one: '${count} Platz anzeigen',
		other: '${count} Plätze anzeigen',
	);
	@override String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Filter aktiv',
		other: '${n} Filter aktiv',
	);
}

// Path: place
class _Translations$place$de extends Translations$place$en {
	_Translations$place$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String unnamedTitle({required Object kind, required Object where}) => '${kind} · ${where}';
	@override String away({required Object distance}) => '${distance} entfernt';
	@override String get directions => 'Route';
	@override String get share => 'Teilen';
	@override String get save => 'Speichern';
	@override String get saved => 'Gespeichert';
	@override String get saveHint => 'In „Meine Favoriten“. Lange drücken, um Listen auszuwählen.';
	@override String get saveHintClick => 'In „Meine Favoriten“. Rechtsklick, um Listen auszuwählen.';
	@override String get saveTo => 'In einer Liste speichern';
	@override String get chooseLists => 'Listen';
	@override String get savedToast => 'Zu „Meine Favoriten“ hinzugefügt';
	@override String get removedToast => 'Aus „Meine Favoriten“ entfernt';
	@override String get pricePerNight => 'Preis pro Nacht';
	@override String get priceFree => 'Kostenlos';
	@override String get priceUnknown => 'Keine Angabe';
	@override String get priceServices => 'Ver- und Entsorgung';
	@override String get priceIncluded => 'Im Preis enthalten';
	@override String priceIncludes({required Object items}) => 'Im Übernachtungspreis enthalten: ${items}';
	@override late final _Translations$place$inclusions$de inclusions = _Translations$place$inclusions$de._(_root);
	@override String get maxHeight => 'Max. Höhe';
	@override String get capacity => 'Anzahl Stellplätze';
	@override String get classification => 'Klassifizierung';
	@override String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Stern',
		other: '${n} Sterne',
	);
	@override String get hours => 'Öffnungszeiten';
	@override String get services => 'Ausstattung';
	@override String get noServices => 'Keine Ausstattung angegeben.';
	@override String get activities => 'In der Nähe';
	@override String get description => 'Beschreibung';
	@override String get contact => 'Kontakt';
	@override String get website => 'Website';
	@override String get call => 'Anrufen';
	@override String get coordinates => 'Koordinaten';
	@override String get address => 'Adresse';
	@override String get copyAddress => 'Adresse kopieren';
	@override String addressSource({required Object source}) => 'Quelle: ${source}';
	@override String get copyShort => 'Kopieren';
	@override String get copy => 'Koordinaten kopieren';
	@override String copyAs({required Object format}) => 'Als ${format} kopieren';
	@override String copiesAs({required Object format}) => '„Kopieren“ verwendet: ${format}';
	@override String copied({required Object text}) => 'Kopiert: ${text}';
	@override String get otherFormats => 'Format zum Kopieren wählen';
	@override String get formatDecimal => 'Dezimalgrad';
	@override String get formatDms => 'Grad, Minuten, Sekunden';
	@override String get formatGeo => 'geo:-Link';
	@override String get formatGoogle => 'Google-Maps-Link';
	@override String get formatOsm => 'OpenStreetMap-Link';
	@override String get sources => 'Quellen';
	@override String fetched({required Object when}) => 'Stand: ${when}';
	@override String get viewSource => 'Bei der Quelle ansehen';
	@override String get gone => 'Dieser Platz ist nicht mehr auf der Karte';
	@override String get goneHint => 'Er wurde seit der letzten Aktualisierung entfernt oder mit einem anderen zusammengeführt.';
	@override String get arriving => 'Dieser Platz wird noch heruntergeladen';
	@override String get arrivingHint => 'Die Plätze in Frankreich werden heruntergeladen, damit die Karte ohne Netz funktioniert. Die Platzseite öffnet sich, sobald dieser Platz da ist.';
	@override String get loadError => 'Dieser Platz konnte nicht geladen werden.';
	@override String get openFailed => 'Keine App konnte diesen Link öffnen.';
	@override String get photos => 'Fotos';
	@override String get extrasOffline => 'Keine Verbindung: Fotos und Rezensionen erscheinen, sobald das Netz zurück ist.';
	@override String get offlineRest => 'Keine Verbindung: Der Rest der Platzseite erscheint, sobald das Netz zurück ist.';
	@override String get reviewsTitle => 'Rezensionen';
	@override String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Rezension',
		other: '${n} Rezensionen',
	);
	@override String get noReviews => 'Noch keine Rezensionen.';
	@override String get noOtherReviews => 'Noch keine weiteren Rezensionen.';
	@override String get moreReviews => 'Weitere Rezensionen';
	@override String get moreReviewsFailed => 'Weitere Rezensionen konnten nicht geladen werden. Erneut versuchen';
	@override String stars({required Object rating}) => '${rating} von 5';
	@override String externalRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'externe Bewertung',
		other: 'externe Bewertungen',
	);
	@override String lunawayRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Lunaway-Bewertung',
		other: 'Lunaway-Bewertungen',
	);
	@override String get deletedAccount => 'Gelöschtes Konto';
	@override late final _Translations$place$reviewVehicle$de reviewVehicle = _Translations$place$reviewVehicle$de._(_root);
	@override String originalLanguage({required Object language}) => 'Originaltext auf ${language}';
	@override String descriptionIn({required Object language}) => 'Beschreibung auf ${language}';
	@override String photoPosition({required Object index, required Object count}) => 'Foto ${index} von ${count}';
	@override String get previousPhoto => 'Vorheriges Foto';
	@override String get nextPhoto => 'Nächstes Foto';
	@override String get links => 'Auf anderen Websites';
	@override String sourceWithLicence({required Object source, required Object licence}) => '${source} · ${licence}';
	@override String get licenceCcBy => 'CC BY 4.0';
	@override String photoCredit({required Object source, required Object author}) => '${source} · ${author}';
	@override String get photoStreetView => 'Straßenansicht';
	@override String get photoSurroundings => 'Umgebung';
	@override String excerptFrom({required Object source, required Object text}) => 'Laut ${source}: ${text}';
	@override String get readMore => 'Weiterlesen';
	@override String updatedOn({required Object date}) => 'aktualisiert am ${date}';
	@override String get otherSources => 'Aus anderen Quellen';
}

// Path: sources
class _Translations$sources$de extends Translations$sources$en {
	_Translations$sources$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override late final _Translations$sources$extcom$de extcom = _Translations$sources$extcom$de._(_root);
}

// Path: hours
class _Translations$hours$de extends Translations$hours$en {
	_Translations$hours$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get open => 'Jetzt geöffnet';
	@override String openUntil({required Object time}) => 'Geöffnet, schließt um ${time}';
	@override String openUntilDay({required Object day, required Object time}) => 'Geöffnet, schließt ${day} um ${time}';
	@override String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Geöffnet, schließt in ${n} Minute',
		other: 'Geöffnet, schließt in ${n} Minuten',
	);
	@override String closedUntil({required Object time}) => 'Geschlossen, öffnet um ${time}';
	@override String closedUntilDay({required Object day, required Object time}) => 'Geschlossen, öffnet ${day} um ${time}';
	@override String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Geschlossen, öffnet in ${n} Minute',
		other: 'Geschlossen, öffnet in ${n} Minuten',
	);
	@override String get closedWindow => 'In den nächsten zwei Wochen geschlossen';
	@override String get tomorrow => 'morgen';
	@override String onDate({required Object date}) => 'am ${date}';
	@override String onWeekday({required Object day}) => 'am ${day}';
	@override String get midnight => 'Mitternacht';
	@override String get stale => 'Öffnungszeiten eventuell veraltet. Aktualisieren Sie die Plätze im Profil.';
	@override String get localTime => 'Zeiten in der Ortszeit des Platzes';
	@override late final _Translations$hours$codes$de codes = _Translations$hours$codes$de._(_root);
	@override late final _Translations$hours$months$de months = _Translations$hours$months$de._(_root);
	@override String dayOfMonth({required Object day, required Object month}) => '${day}. ${month}';
	@override String dayOfYear({required Object day, required Object month, required Object year}) => '${day}. ${month} ${year}';
	@override String get allWeek => 'Rund um die Uhr';
	@override String get allYear => 'ganzjährig';
	@override String get seasonAllYear => 'Ganzjährig geöffnet';
	@override String seasonOpenUntil({required Object date}) => 'Geöffnet bis ${date}';
	@override String seasonClosedUntil({required Object date}) => 'Geschlossen, öffnet am ${date}';
}

// Path: directions
class _Translations$directions$de extends Translations$directions$en {
	_Translations$directions$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Öffnen in';
	@override String get hint => 'Diese Apps kennen die Maße Ihres Fahrzeugs nicht.';
	@override String get remember => 'Immer diese App verwenden';
	@override String get rememberHint => 'Im Profil änderbar';
	@override String get settingTitle => 'In einer anderen App öffnen';
	@override String get settingHint => 'Welche App „Öffnen in“ bei einer Route startet';
	@override String get askEachTime => 'Jedes Mal fragen';
	@override String get appleMaps => 'Apple Karten';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osmAnd => 'OsmAnd';
	@override String get organicMaps => 'Organic Maps';
	@override String get magicEarth => 'Magic Earth';
	@override String get openStreetMap => 'OpenStreetMap (Browser)';
	@override String get none => 'Keine Navigations-App auf diesem Gerät gefunden.';
}

// Path: navigation
class _Translations$navigation$de extends Translations$navigation$en {
	_Translations$navigation$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$preview$de preview = _Translations$navigation$preview$de._(_root);
	@override late final _Translations$navigation$stops$de stops = _Translations$navigation$stops$de._(_root);
	@override late final _Translations$navigation$legs$de legs = _Translations$navigation$legs$de._(_root);
	@override late final _Translations$navigation$fuel$de fuel = _Translations$navigation$fuel$de._(_root);
	@override late final _Translations$navigation$onTheWay$de onTheWay = _Translations$navigation$onTheWay$de._(_root);
	@override late final _Translations$navigation$states$de states = _Translations$navigation$states$de._(_root);
	@override late final _Translations$navigation$noRoute$de noRoute = _Translations$navigation$noRoute$de._(_root);
	@override late final _Translations$navigation$ferry$de ferry = _Translations$navigation$ferry$de._(_root);
	@override late final _Translations$navigation$warning$de warning = _Translations$navigation$warning$de._(_root);
	@override late final _Translations$navigation$roadEvents$de roadEvents = _Translations$navigation$roadEvents$de._(_root);
	@override late final _Translations$navigation$marks$de marks = _Translations$navigation$marks$de._(_root);
	@override late final _Translations$navigation$guidance$de guidance = _Translations$navigation$guidance$de._(_root);
	@override late final _Translations$navigation$voice$de voice = _Translations$navigation$voice$de._(_root);
	@override late final _Translations$navigation$units$de units = _Translations$navigation$units$de._(_root);
	@override late final _Translations$navigation$settings$de settings = _Translations$navigation$settings$de._(_root);
	@override late final _Translations$navigation$enforcement$de enforcement = _Translations$navigation$enforcement$de._(_root);
}

// Path: list
class _Translations$list$de extends Translations$list$en {
	_Translations$list$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Plätze in der Nähe';
	@override String get empty => 'Mit diesen Filtern gibt es hier keine Plätze';
	@override String get emptyHint => 'Verschieben Sie die Karte, zoomen Sie heraus oder lockern Sie die Filter.';
	@override String get downloading => 'Plätze werden geladen';
	@override String get downloadingHint => 'Die Liste füllt sich während des Downloads.';
	@override String get error => 'Die Liste konnte nicht geladen werden.';
	@override String get offline => 'Keine Verbindung: Die Liste braucht das Netz.';
	@override String get moreFailed => 'Weitere Plätze konnten nicht geladen werden. Erneut versuchen';
	@override String get sortDistance => 'Entfernung';
	@override String get sortRating => 'Bewertung';
	@override String get sortNewest => 'Neu hinzugefügt';
	@override String sortedBy({required Object sort}) => 'Liste sortiert nach: ${sort}';
	@override String rankedAmongNearestYou({required Object n}) => 'Sortiert innerhalb der ${n} Plätze, die Ihnen am nächsten liegen';
	@override String rankedAmongNearestCentre({required Object n}) => 'Sortiert innerhalb der ${n} Plätze, die der Kartenmitte am nächsten liegen';
	@override String get offlineTitle => 'Keine Verbindung';
	@override String get offlineNotHere => 'Nichts aus diesem Gebiet auf diesem Gerät.';
}

// Path: favorites
class _Translations$favorites$de extends Translations$favorites$en {
	_Translations$favorites$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Favoriten';
	@override String get defaultList => 'Meine Favoriten';
	@override String get empty => 'Hier ist noch nichts gespeichert';
	@override String get emptyHint => 'Speichern Sie einen Platz, eine Adresse oder einen Punkt der Karte: So haben Sie alles auch offline griffbereit.';
	@override String get newList => 'Neue Liste';
	@override String get listName => 'Name der Liste';
	@override String get renameList => 'Liste umbenennen';
	@override String get deleteList => 'Liste löschen';
	@override String deleteListConfirm({required Object name}) => '„${name}“ löschen? Die Plätze bleiben auf der Karte.';
	@override String get listActions => 'Listenoptionen';
	@override String get placeActions => 'Optionen für diesen Platz';
	@override String get openOnMap => 'Auf der Karte ansehen';
	@override String get remove => 'Aus der Liste entfernen';
	@override String get removed => 'Aus der Liste entfernt';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		zero: 'Leer',
		one: '${n} Favorit',
		other: '${n} Favoriten',
	);
	@override String get error => 'Ihre Favoriten konnten nicht geladen werden.';
	@override String pointNamed({required Object date}) => 'Punkt vom ${date}';
	@override String get name => 'Name';
	@override String get note => 'Notiz (optional)';
	@override String get edit => 'Bearbeiten';
	@override String get rename => 'Umbenennen';
	@override String get removeEverywhere => 'Aus den Favoriten entfernen';
	@override String get removedEverywhere => 'Aus den Favoriten entfernt';
	@override String get inFavorites => 'In Ihren Favoriten';
	@override String inFavoritesAs({required Object name}) => 'In Ihren Favoriten als „${name}“';
	@override String get pointActions => 'Optionen für diesen Punkt';
	@override late final _Translations$favorites$pointKind$de pointKind = _Translations$favorites$pointKind$de._(_root);
	@override String deleteListPoints({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Der in dieser Liste gespeicherte Punkt wird mit ihr gelöscht.',
		other: 'Die ${n} in dieser Liste gespeicherten Punkte werden mit ihr gelöscht.',
	);
}

// Path: vehicle
class _Translations$vehicle$de extends Translations$vehicle$en {
	_Translations$vehicle$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mein Fahrzeug';
	@override String get why => 'Anhand der Maße Ihres Fahrzeugs werden Plätze ausgeblendet, auf die es nicht passt. Die Maße werden mit jeder Routenanfrage gesendet und nicht gespeichert.';
	@override String get none => 'Beschreiben Sie Ihr Fahrzeug, um Plätze auszublenden, auf die es nicht passt.';
	@override String get add => 'Mein Fahrzeug beschreiben';
	@override String get edit => 'Bearbeiten';
	@override String get type => 'Typ';
	@override late final _Translations$vehicle$types$de types = _Translations$vehicle$types$de._(_root);
	@override String get towingTitle => 'Im Schlepptau';
	@override late final _Translations$vehicle$towing$de towing = _Translations$vehicle$towing$de._(_root);
	@override String get size => 'Maße';
	@override String get sizeHint => 'Typische Werte für den gewählten Typ: Korrigieren Sie sie anhand Ihres Fahrzeugscheins.';
	@override String get height => 'Höhe';
	@override String get width => 'Breite';
	@override String get length => 'Gesamtlänge inkl. Anhänger';
	@override String get weight => 'Zulässiges Gesamtgewicht (zGG)';
	@override String heightShort({required Object value}) => 'H ${value}';
	@override String widthShort({required Object value}) => 'B ${value}';
	@override String lengthShort({required Object value}) => 'L ${value}';
	@override String get notANumber => 'Bitte eine Zahl eingeben, z. B. 2,90';
	@override String outOfRange({required Object min, required Object max, required Object unit}) => 'Zwischen ${min} und ${max} ${unit}';
	@override String get navigationLater => 'Die Navigation von Lunaway berücksichtigt alle diese Maße.';
	@override String get save => 'Speichern';
	@override String get clear => 'Löschen';
	@override String get fuelTitle => 'Kraftstoff';
	@override String get fuelHint => 'Der Preis Ihres Kraftstoffs erscheint an den Tankstellen auf der Karte, die günstigsten zuerst.';
	@override String get consumption => 'Verbrauch';
	@override String get consumptionUnit => 'l/100 km';
	@override String get lpgHeating => 'Heizung mit Autogas (LPG)';
	@override String get lpgHeatingHint => 'Auch die Autogaspreise erscheinen an den Tankstellen.';
	@override String get cruiseTitle => 'Maximale Reisegeschwindigkeit';
	@override String get cruiseHint => 'Die Fahrzeiten setzen voraus, dass Sie nie schneller fahren, auch wo die Straße es erlaubt. Angesagt werden weiterhin die Tempolimits der Straße.';
	@override String get cruiseNone => 'Keine Begrenzung';
}

// Path: vehicleHeight
class _Translations$vehicleHeight$de extends Translations$vehicleHeight$en {
	_Translations$vehicleHeight$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Höhe Ihres Fahrzeugs';
	@override String get why => 'Plätze mit einer niedrigeren Höhenbegrenzung werden ausgeblendet. Plätze ohne bekannte Begrenzung bleiben auf der Karte.';
	@override String get needed => 'Geben Sie die Höhe an, zum Beispiel 2,90';
	@override String get optional => 'Optional';
	@override String get weight => 'Zulässiges Gesamtgewicht';
	@override String get apply => 'Mit dieser Höhe filtern';
	@override String get later => 'Weitere Fahrzeugdaten geben Sie im Profil unter „Mein Fahrzeug“ ein.';
}

// Path: profile
class _Translations$profile$de extends Translations$profile$en {
	_Translations$profile$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profil';
	@override String get noAccountNeeded => 'Ohne Konto, ohne Werbung, ohne Tracker. Ihre Favoriten bleiben auf diesem Gerät.';
	@override String get language => 'Sprache';
	@override String get languageSystem => 'Gerätesprache';
	@override String get appearance => 'Darstellung';
	@override String get themeAuto => 'Automatisch';
	@override String get themeLight => 'Hell';
	@override String get themeDark => 'Dunkel';
	@override String get themeAutoHint => 'Tagsüber hell, nach Sonnenuntergang an Ihrem Standort dunkel.';
	@override String get themeLightHint => 'Immer hell, bei Tag und Nacht.';
	@override String get themeDarkHint => 'Immer dunkel, schont nachts die Augen.';
	@override String get offline => 'Offline';
	@override String placesOnDevice({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Platz auf diesem Gerät',
		other: 'Plätze auf diesem Gerät',
	);
	@override String offlineSize({required Object size}) => 'Belegter Speicher: ${size}';
	@override String lastSync({required Object when}) => 'Letzte Aktualisierung: ${when}';
	@override String get neverSynced => 'Noch nie heruntergeladen';
	@override String get syncNow => 'Jetzt aktualisieren';
	@override String get syncing => 'Wird aktualisiert';
	@override String get about => 'Über die App';
	@override String version({required Object version}) => 'Version ${version}';
	@override String get website => 'Website';
	@override String get privacy => 'Datenschutzerklärung';
	@override String get sourceCode => 'Quellcode';
	@override String get licences => 'Lizenzen';
	@override String get appLicence => 'Lunaway ist freie Software unter der GNU AGPL 3.0 oder einer späteren Version.';
	@override String get routeData => 'Routen beruhen auf offenen Daten, die unvollständig sein können: Verkehrszeichen und Straßenverkehrsordnung haben Vorrang.';
	@override String get attributions => 'Quellen und Nachweise';
	@override String get attributionOsm => 'Plätze und Kartendaten © OpenStreetMap-Mitwirkende.';
	@override String get attributionOdbl => 'OpenStreetMap-Daten unter der Open Database License (ODbL).';
	@override String get attributionAtout => 'Klassifizierte Campingplätze von Atout France, verortet über die Base Adresse Nationale und die BD TOPO des IGN, unter der Licence Ouverte 2.0 (Etalab).';
	@override String get attributionCommunes => 'Gemeinden der Plätze: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), unter der ODbL.';
	@override String get attributionCommunityPlaces => 'Von den Reisenden von Lunaway hinzugefügte und geänderte Plätze, unter der ODbL, mit der Nennung „Lunaway contributors“.';
	@override String get attributionTiles => 'Grundkarte bereitgestellt von Lunaway, Stile abgeleitet von Protomaps (BSD-3-Clause), Daten © OpenStreetMap-Mitwirkende.';
	@override String get attributionFonts => 'Schriftarten Fraunces und Atkinson Hyperlegible Next, SIL Open Font License 1.1.';
	@override String get attributionIcons => 'Phosphor-Symbole, MIT-Lizenz.';
	@override String get noTracking => 'Ohne Werbung, ohne Tracker. Ihr Konto kennt weder Ihre E-Mail-Adresse noch Ihre Telefonnummer.';
	@override String get attributionBdTopo => 'Beschränkungen von Höhe, Breite, Länge und Gewicht auf den Straßen sowie anhand ihres Namens verortete Campingplätze: IGN BD TOPO, über die Géoplateforme, unter der Licence Ouverte 2.0.';
	@override String get attributionAddresses => 'Adressen der Suche in Frankreich: Base Adresse Nationale, über die Géoplateforme des IGN, unter der Licence Ouverte 2.0.';
	@override String get attributionAddressesOsm => 'Adressen der Suche außerhalb Frankreichs: OpenStreetMap, über Photon, unter der ODbL.';
	@override String get attributionPoiOdbl => 'Geschäfte und Dienstleistungen: OpenStreetMap und die Öffnungszeiten der Postfilialen (La Poste), unter der ODbL.';
	@override String get attributionPoiLo => 'Kraftstoffpreise (französisches Wirtschaftsministerium) und die Einrichtungen des Gesundheitswesens aus FINESS (Agence du numérique en santé), unter der Licence Ouverte 2.0 (Etalab).';
	@override String get attributionPacks => 'Umrisse der Offline-Karten: Contours administratifs, data.gouv.fr (ODbL), und Natural Earth (gemeinfrei).';
	@override String get attributionOfflineLabels => 'Beschriftungen und Symbole der Offline-Karten: Noto-Sans-Glyphen (SIL Open Font License 1.1) und Protomaps-Sprites, abgeleitet von tangrams/icons (MIT).';
	@override String get attributionExtcom => 'Plätze, Rezensionen, Bewertungen und Fotos, gemäß schriftlicher Vereinbarung mit dieser Quelle.';
	@override String get creditsPlaces => 'Plätze';
	@override String get creditsContent => 'Fotos, Texte und Rezensionen';
	@override String get creditsRoutes => 'Routen und Navigation';
	@override String get creditsSearch => 'Suche';
	@override String get creditsMap => 'Grundkarte';
	@override String get creditsApp => 'App';
	@override String get attributionDatatourisme => 'Plätze, Beschreibungen und Fotos der Touristeninformationen: DATAtourisme, unter der Licence Ouverte 2.0; jeder Text und jedes Foto nennt seine Touristeninformation, seinen Urheber und das Datum der letzten Aktualisierung.';
	@override String get attributionCommunity => 'Rezensionen, Bewertungen und Fotos der Reisenden von Lunaway, unter CC BY 4.0, mit dem Pseudonym ihrer Urheber.';
	@override String get attributionCommons => 'Fotos von Wikimedia Commons, jeweils unter ihrer eigenen Lizenz (CC0, gemeinfrei, CC BY oder CC BY-SA), mit Urheber und Link zur jeweiligen Seite.';
	@override String get attributionPanoramax => 'Straßenansichten von Panoramax: die Instanz von OpenStreetMap France unter CC BY-SA 4.0, die des IGN unter der Licence Ouverte 2.0.';
	@override String get attributionWikipedia => 'Auszüge aus Wikipedia-Artikeln, unter CC BY-SA 4.0, mit Link zum Artikel.';
	@override String get attributionMangrove => 'Rezensionen von Mangrove Reviews, unter CC BY 4.0 oder der in der Rezension angegebenen Lizenz, mit Link zur Rezension.';
	@override String get attributionTranslation => 'Automatische Übersetzungen: OPUS-MT-Modelle der Universität Helsinki, unter CC BY 4.0, ausgeführt auf den Servern von Lunaway.';
	@override String get attributionRoadEvents => 'Baustellen und Sperrungen in Frankreich: DIR und Bison Futé, Verkehrsanordnungen aus DiaLog (DGITM), Städte und Départements (Lyon, Toulouse, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Sarthe), unter der Licence Ouverte 2.0; Bordeaux Métropole und das Département Côtes-d\'Armor, unter der Licence Ouverte; Ville de Paris, Rennes Métropole und die Meldungen der Reisenden von Lunaway, unter der ODbL.';
	@override String get attributionRoadEventsAbroad => 'Baustellen und Sperrungen in den Niederlanden: NDW, Nationaal Dataportaal Wegverkeer (offene Daten); in Spanien: DGT, Dirección General de Tráfico (CC BY).';
	@override String get attributionDangerZones => 'Blitzer und Gefahrenzonen: in Frankreich die Karte der Sécurité routière, weiterverwendet nach dem französischen Code des relations entre le public et l\'administration, und die Liste der festen Blitzer des Innenministeriums, Délégation à la sécurité routière (data.gouv.fr), unter der Licence Ouverte 2.0; in Polen Główny Inspektorat Transportu Drogowego (CANARD, dane.gov.pl), in Luxemburg die Administration des ponts et chaussées (data.public.lu), in Brüssel Bruxelles Mobilité (data.mobility.brussels), unter CC0; in Norwegen „Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.“; in Irland die Kontrollzonen von An Garda Síochána, Irish Public Sector Information, CC BY, Verläufe von Lunaway angepasst; OpenStreetMap (ODbL).';
	@override String attributionCameraSource({required Object attribution}) => 'Blitzer und Gefahrenzonen: ${attribution}';
	@override String get attributionOverture => 'Geschäfte, Dienstleistungen, Unterkünfte und Freizeitangebote der Overture Maps Foundation (overturemaps.org): Daten von Meta, PinMeTo und DAC unter der Lizenz CDLA Permissive 2.0 und von AllThePlaces unter CC0 1.0.';
}

// Path: units
class _Translations$units$de extends Translations$units$en {
	_Translations$units$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String kilobytes({required Object n}) => '${n} KB';
	@override String megabytes({required Object n}) => '${n} MB';
}

// Path: languages
class _Translations$languages$de extends Translations$languages$en {
	_Translations$languages$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Französisch';
	@override String get en => 'Englisch';
	@override String get de => 'Deutsch';
	@override String get es => 'Spanisch';
	@override String get it => 'Italienisch';
	@override String get nl => 'Niederländisch';
}

// Path: translation
class _Translations$translation$de extends Translations$translation$en {
	_Translations$translation$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get translate => 'Übersetzen';
	@override String get translating => 'Wird übersetzt';
	@override String get showOriginal => 'Original anzeigen';
	@override String get showTranslation => 'Übersetzung anzeigen';
	@override late final _Translations$translation$from$de from = _Translations$translation$from$de._(_root);
	@override String get offline => 'Für die Übersetzung ist eine Internetverbindung nötig.';
	@override String get failedOffline => 'Keine Internetverbindung: Der Text konnte nicht übersetzt werden.';
	@override String get busy => 'Der Übersetzungsdienst ist ausgelastet. Versuchen Sie es später erneut.';
	@override String get unavailable => 'Die Übersetzung ist derzeit nicht verfügbar.';
	@override String get gone => 'Dieser Text ist nicht mehr verfügbar.';
	@override String get unsupported => 'Diese Sprache kann nicht übersetzt werden.';
	@override String get autoReviews => 'Rezensionen automatisch übersetzen';
	@override String get autoReviewsHint => 'Lunaway übersetzt Rezensionen in anderen Sprachen auf seinem eigenen Server, ohne Dienste von Drittanbietern.';
}

// Path: locale
class _Translations$locale$de extends Translations$locale$en {
	_Translations$locale$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
	@override String get de => 'Deutsch';
	@override String get es => 'Español';
	@override String get it => 'Italiano';
	@override String get nl => 'Nederlands';
}

// Path: account
class _Translations$account$de extends Translations$account$en {
	_Translations$account$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ihr Konto';
	@override String get noneTitle => 'Noch kein Konto';
	@override String get noneBody => 'Karte, Suche und Favoriten funktionieren ohne Konto. Es wird bei Ihrem ersten Beitrag (eine Bewertung, eine Bestätigung, ein Foto) automatisch angelegt, ohne E-Mail und ohne Passwort. Ihre Favoritenlisten werden dann damit verknüpft, mit den darin gespeicherten Adressen, Punkten und Notizen.';
	@override String get recover => 'Mein Konto wiederherstellen';
	@override String memberSince({required Object date}) => 'Mitglied seit ${date}';
	@override String get editPseudonym => 'Pseudonym ändern';
	@override String get pseudonymTitle => 'Ihr Pseudonym';
	@override String get pseudonymHint => 'Öffentlich: Es erscheint bei Ihren Rezensionen und Fotos. 3 bis 32 Zeichen.';
	@override String get pseudonymInvalid => '3 bis 32 Zeichen, davon mindestens zwei Buchstaben.';
	@override String get pseudonymRefused => 'Dieses Pseudonym ist nicht zulässig: keine Links, keine Kontaktdaten, keine Beleidigungen und kein Name, mit dem sich das Konto als Lunaway-Team ausgibt.';
	@override String get pseudonymSaved => 'Pseudonym gespeichert';
	@override String level({required Object level}) => 'Vertrauensstufe ${level}';
	@override late final _Translations$account$levelOpens$de levelOpens = _Translations$account$levelOpens$de._(_root);
	@override String nextLevel({required Object level}) => 'Für Stufe ${level}';
	@override String get levelTop => 'Sie haben die höchste Stufe erreicht.';
	@override late final _Translations$account$requirement$de requirement = _Translations$account$requirement$de._(_root);
	@override String orInstead({required Object requirement}) => 'Oder ${requirement}';
	@override String get recoveryNone => 'Auf diesem Gerät wurde keine Sicherungskarte erstellt. Ohne sie bleibt dieses Konto an dieses Gerät gebunden: Geht das Gerät verloren, ist auch das Konto verloren.';
	@override String get recoveryNoneAccount => 'Für dieses Konto gibt es noch keine Sicherungskarte. Ohne sie bleibt dieses Konto an dieses Gerät gebunden: Geht das Gerät verloren, ist auch das Konto verloren.';
	@override String get recoveryCreate => 'Meine Sicherungskarte erstellen';
	@override String recoveryMade({required Object date}) => 'Erstellt am ${date}';
	@override String get recoveryRemake => 'Neu erstellen';
	@override String get recoveryRemakeHint => 'Neue Sicherungskarte erstellen';
	@override String get contributions => 'Meine Beiträge';
	@override String pending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Beitrag wartet auf Versand',
		other: '${n} Beiträge warten auf Versand',
	);
	@override String get mutedAuthors => 'Ausgeblendete Autoren';
	@override String get devices => 'Geräte';
	@override String get signOut => 'Abmelden';
	@override String get delete => 'Mein Konto löschen';
	@override String get signOutTitle => 'Auf diesem Gerät abmelden?';
	@override String get signOutBody => 'Der Schlüssel des Kontos wird von diesem Gerät gelöscht. Um zurückzukehren, brauchen Sie Ihre Sicherungskarte. Ihre Favoriten bleiben hier.';
	@override String get signOutNoCard => 'Sie haben auf diesem Gerät keine Sicherungskarte erstellt. Ohne sie ist dieses Konto endgültig verloren.';
	@override String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Ein Beitrag, der auf Versand wartet, wird nicht gesendet.',
		other: '${n} Beiträge, die auf Versand warten, werden nicht gesendet.',
	);
	@override String get signedOut => 'Abgemeldet. Ihre Favoriten bleiben auf diesem Gerät.';
	@override String get lost => 'Dieses Konto lässt sich auf diesem Gerät nicht mehr öffnen. Stellen Sie es mit Ihrer Sicherungskarte wieder her: Profil, Mein Konto wiederherstellen.';
	@override String get lostAction => 'Wiederherstellen';
	@override String get welcomeTitle => 'Danke für Ihren ersten Beitrag';
	@override String welcomeBody({required Object name}) => 'Ihr Konto wurde unter dem Pseudonym „${name}“ angelegt. Statt E-Mail und Passwort nutzt es einen Schlüssel, der auf diesem Gerät gespeichert ist. Das Pseudonym können Sie im Profil ändern.';
	@override String get welcomeCard => 'Erstellen Sie Ihre Sicherungskarte, um dieses Konto auf einem anderen Gerät wiederzufinden.';
	@override String get welcomeFavorites => 'Ihre Favoritenlisten werden jetzt samt Adressen und Notizen mit Ihrem Konto gespeichert.';
}

// Path: recovery
class _Translations$recovery$de extends Translations$recovery$en {
	_Translations$recovery$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sicherungskarte';
	@override String get intro => 'Ein Code, der Ihr Konto auf ein neues Gerät bringt. Lunaway speichert davon nur einen Fingerabdruck, mit dem er sich prüfen lässt: Der Code selbst kann nie wieder angezeigt werden, und jede neue Karte hat einen anderen Code.';
	@override String get replaces => 'Eine neue Karte ersetzt die vorherige: Der alte Code funktioniert dann nicht mehr.';
	@override String replaceTitle({required Object date}) => 'Karte vom ${date} ersetzen?';
	@override String replaceBody({required Object date}) => 'Die neue Karte bekommt einen anderen Code. Der Code der Karte vom ${date} funktioniert ab sofort nicht mehr. Er kann nicht erneut angezeigt werden: Lunaway hat davon nur einen Fingerabdruck gespeichert.';
	@override String get replaceKeep => 'Die alte behalten';
	@override String get replaceConfirm => 'Neue Karte erstellen';
	@override String get make => 'Karte erstellen';
	@override String get codeLabel => 'Ihr Sicherungscode';
	@override String get shownOnce => 'Dieser Code wird nur einmal angezeigt. Notieren Sie ihn oder speichern Sie das Bild, bevor Sie schließen.';
	@override String get saveImage => 'Bild speichern';
	@override String get done => 'Ich habe den Code notiert';
	@override String get doneTitle => 'Haben Sie den Code notiert oder gespeichert?';
	@override String get doneBody => 'Sobald diese Seite geschlossen ist, wird er nicht mehr angezeigt.';
	@override String get keep => 'Auf der Seite bleiben';
	@override String get cardHeading => 'Lunaway-Sicherungskarte';
	@override String cardAccount({required Object name}) => 'Konto: ${name}';
	@override String get cardHow => 'So stellen Sie das Konto wieder her: Profil, Mein Konto wiederherstellen, dann diesen Code eingeben oder die Karte fotografieren.';
	@override String cardMade({required Object date}) => 'Erstellt am ${date}';
	@override String get cardWarning => 'Dieser Code öffnet das Konto: Geben Sie ihn niemals weiter.';
	@override String get failed => 'Die Karte konnte nicht erstellt werden. Eine Verbindung ist nötig.';
	@override String get fileName => 'lunaway-sicherungskarte';
	@override String get step1 => 'Erstellen Sie die Karte: Der Code wird nur einmal angezeigt.';
	@override String get step2 => 'Speichern Sie das Bild, drucken Sie es aus oder schreiben Sie den Code von Hand ab.';
	@override String get step3 => 'Bewahren Sie die Karte im Handschuhfach auf, bei den Fahrzeugpapieren.';
}

// Path: recover
class _Translations$recover$de extends Translations$recover$en {
	_Translations$recover$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mein Konto wiederherstellen';
	@override String get intro => 'Geben Sie den Code Ihrer Sicherungskarte ein oder lesen Sie ihn von einem Foto der Karte ein.';
	@override String get field => 'Sicherungscode';
	@override String get fieldHint => '27 Zeichen, in Vierergruppen';
	@override String remaining({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Noch ${n} Zeichen',
		other: 'Noch ${n} Zeichen',
	);
	@override String get invalid => 'Dieser Code passt zu keiner Karte: Prüfen Sie jedes Zeichen.';
	@override String get valid => 'Code vollständig';
	@override String get scan => 'Karte von einem Foto einlesen';
	@override String get scanFile => 'Bild der Karte auswählen';
	@override String get reading => 'Karte wird gelesen';
	@override String get scanFailed => 'Auf diesem Bild ist kein lesbarer Code. Versuchen Sie es mit einem schärferen Foto, auf dem die Karte flach liegt.';
	@override String get revoke => 'Altes Gerät verloren oder gestohlen: dort abmelden';
	@override String get revokeHint => 'Alle Ihre anderen Geräte werden abgemeldet.';
	@override String get submit => 'Konto wiederherstellen';
	@override String get notFound => 'Zu diesem Code gibt es kein Konto. Prüfen Sie die Karte oder erstellen Sie auf einem angemeldeten Gerät eine neue.';
	@override String get tooMany => 'Vorerst zu viele Versuche. Versuchen Sie es in einer Stunde erneut.';
	@override String done({required Object name}) => 'Konto wiederhergestellt: ${name}';
}

// Path: deletion
class _Translations$deletion$de extends Translations$deletion$en {
	_Translations$deletion$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mein Konto löschen';
	@override String get intro => 'Die Löschung erfolgt sofort und endgültig.';
	@override String get goneTitle => 'Was gelöscht wird';
	@override late final _Translations$deletion$gone$de gone = _Translations$deletion$gone$de._(_root);
	@override String get keptTitle => 'Was ohne Ihren Namen bleibt';
	@override String get kept => 'Ihre veröffentlichten Rezensionen mit Text, Ihre Bestätigungen und Ihre bereits übernommenen Änderungen an Plätzen bleiben ohne Urheber erhalten, denn sie gehören zur Karte der anderen Reisenden.';
	@override String get backups => 'Die Sicherungen des Servers werden nach etwa 30 Tagen gelöscht.';
	@override String get device => 'Auf diesem Gerät bleiben Ihre Favoriten erhalten; der Schlüssel des Kontos wird gelöscht.';
	@override String get web => 'Sie können das Konto auch auf lunaway.net mit Ihrem Sicherungscode löschen.';
	@override String get webLink => 'lunaway.net/de/account/delete';
	@override String get confirmTitle => 'Endgültig löschen?';
	@override String confirmBody({required Object name}) => 'Das Konto „${name}“ und alles oben Aufgeführte werden jetzt gelöscht. Niemand kann es wiederherstellen.';
	@override String get confirmCheck => 'Ich verstehe, dass dies endgültig ist';
	@override String get confirm => 'Konto löschen';
	@override String get done => 'Konto gelöscht';
	@override String get failed => 'Das Konto konnte nicht gelöscht werden. Eine Verbindung ist nötig.';
}

// Path: devices
class _Translations$devices$de extends Translations$devices$en {
	_Translations$devices$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Geräte';
	@override String get intro => 'Jedes Gerät hat seinen eigenen Schlüssel. Entfernen Sie ein verlorenes Gerät oder eines, das Sie nicht mehr nutzen.';
	@override String get thisDevice => 'Dieses Gerät';
	@override String get other => 'Anderes Gerät';
	@override String added({required Object date}) => 'Hinzugefügt am ${date}';
	@override String lastUsed({required Object when}) => 'Zuletzt genutzt: ${when}';
	@override String get revoke => 'Entfernen';
	@override String get revokeTitle => 'Dieses Gerät entfernen?';
	@override String get revokeBody => 'Es wird abgemeldet und kann das Konto nicht mehr nutzen.';
	@override String get revoked => 'Gerät entfernt';
	@override String get signOutOthers => 'Alle anderen Geräte abmelden';
	@override String signedOutOthers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		zero: 'Keine andere Sitzung offen',
		one: '${n} Sitzung beendet',
		other: '${n} Sitzungen beendet',
	);
	@override String get error => 'Die Geräte konnten nicht geladen werden. Eine Verbindung ist nötig.';
}

// Path: muted
class _Translations$muted$de extends Translations$muted$en {
	_Translations$muted$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ausgeblendete Autoren';
	@override String get empty => 'Niemand ist ausgeblendet';
	@override String get emptyHint => 'Um jemanden auszublenden, öffnen Sie das Menü einer seiner Rezensionen oder eines seiner Fotos. Das Ausblenden gilt nur für Sie.';
	@override String get unmute => 'Wieder anzeigen';
	@override String unmuted({required Object name}) => 'Beiträge von ${name} werden wieder angezeigt';
}

// Path: mine
class _Translations$mine$de extends Translations$mine$en {
	_Translations$mine$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Meine Beiträge';
	@override String get pending => 'Warten auf Versand';
	@override String get pendingHint => 'Werden gesendet, sobald Sie wieder online sind.';
	@override String get sendNow => 'Jetzt senden';
	@override String get retry => 'Erneut versuchen';
	@override String get discard => 'Verwerfen';
	@override String get discardTitle => 'Diesen Beitrag verwerfen?';
	@override String get discardBody => 'Er wird nicht gesendet.';
	@override String get reviews => 'Rezensionen und Bewertungen';
	@override String get photos => 'Fotos';
	@override String get confirmations => 'Bestätigungen';
	@override String get issues => 'Gemeldete Probleme';
	@override String get places => 'Hinzugefügte Plätze und Änderungen';
	@override String get empty => 'Noch nichts';
	@override String get emptyHint => 'Einen Platz zu bewerten oder zu bestätigen, dass es ihn noch gibt, zählt schon als Beitrag.';
	@override String latest({required Object shown, required Object total}) => 'Die neuesten ${shown} von ${total}';
	@override String get error => 'Ihre Beiträge konnten nicht geladen werden. Eine Verbindung ist nötig.';
	@override String get deleteTitle => 'Diesen Beitrag löschen?';
	@override String get deleteBody => 'Er wird aus Lunaway entfernt.';
	@override String get deleteApplied => 'Dieser Platz ist bereits Teil der Karte: Er bleibt dort, ohne Ihren Namen.';
	@override String get deleted => 'Beitrag gelöscht';
	@override String get ratingOnly => 'Nur Bewertung';
	@override late final _Translations$mine$status$de status = _Translations$mine$status$de._(_root);
	@override late final _Translations$mine$submission$de submission = _Translations$mine$submission$de._(_root);
	@override String get newPlace => 'Neuer Platz';
	@override String get edit => 'Änderung';
	@override String get aPlace => 'Ein Platz';
	@override String get newVendingMachine => 'Neuer Automat';
	@override String get poiConfirmations => 'Bestätigte Geschäfte und Dienstleistungen';
	@override String get aPoi => 'Ein Geschäft oder eine Dienstleistung';
}

// Path: outbox
class _Translations$outbox$de extends Translations$outbox$en {
	_Translations$outbox$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override late final _Translations$outbox$kind$de kind = _Translations$outbox$kind$de._(_root);
	@override String get waiting => 'Wartet auf das Netz';
	@override String get sending => 'Wird gesendet';
	@override late final _Translations$outbox$error$de error = _Translations$outbox$error$de._(_root);
	@override String get sent => 'Danke, gesendet';
	@override String get queued => 'Keine Verbindung: wird gesendet, sobald Sie wieder online sind';
	@override String refused({required Object reason}) => 'Nicht gesendet. ${reason}';
}

// Path: placement
class _Translations$placement$de extends Translations$placement$en {
	_Translations$placement$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Stelle festlegen';
	@override String get hint => 'Verschieben Sie die Karte: Das Fadenkreuz markiert die genaue Stelle.';
	@override String get confirm => 'Diese Stelle verwenden';
	@override String duplicate({required Object name, required Object distance}) => '„${name}“ liegt nur ${distance} entfernt: Ist das derselbe Platz?';
	@override String get same => 'Ja, Platzseite öffnen';
	@override String get notSame => 'Nein, das ist ein anderer Platz';
}

// Path: contribute
class _Translations$contribute$de extends Translations$contribute$en {
	_Translations$contribute$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get yourRating => 'Ihre Bewertung';
	@override String get rateHint => 'Wählen Sie 1 bis 5 Sterne';
	@override String rateStar({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Mit ${n} Stern bewerten',
		other: 'Mit ${n} Sternen bewerten',
	);
	@override String get writeReview => 'Rezension schreiben';
	@override String get editReview => 'Ihre Rezension bearbeiten';
	@override String get deleteReview => 'Ihre Rezension löschen';
	@override String get deleteReviewTitle => 'Ihre Rezension löschen?';
	@override String get deleteReviewBody => 'Text und Bewertung werden von der Platzseite entfernt.';
	@override String get deleteRating => 'Ihre Bewertung entfernen';
	@override String get deleteRatingTitle => 'Ihre Bewertung entfernen?';
	@override String get deleteRatingBody => 'Ihre Bewertung wird von der Platzseite entfernt.';
	@override String get pendingSend => 'Wartet auf Versand';
	@override String get statusPending => 'In Prüfung: vorerst nur für Sie sichtbar';
	@override String get statusHidden => 'Nach Meldungen ausgeblendet, wartet auf die Moderation';
	@override String get statusRemoved => 'Von der Moderation entfernt';
	@override String get addPhoto => 'Foto hinzufügen';
	@override String get firstPhoto => 'Erstes Foto hinzufügen';
	@override String get stillThere => 'Noch da?';
	@override String get more => 'Weitere Aktionen';
	@override String get reportIssue => 'Problem melden';
	@override String get proposeEdit => 'Änderung vorschlagen';
	@override String get editPlace => 'Platz bearbeiten';
	@override String get reportPlace => 'Diesen Platz der Moderation melden';
	@override String get toVerifyTitle => 'Zu prüfen';
	@override String get toVerifyBody => 'Von der Community hinzugefügt, wartet auf zwei Bestätigungen. Kennen Sie den Platz? Dann bestätigen Sie ihn.';
	@override String get issuesTitle => 'Meldungen der letzten 30 Tage';
	@override String issueCount({required Object kind, required Object count}) => '${kind} (${count})';
	@override String get addPlaceHere => 'Hier einen Platz hinzufügen';
	@override String get addPlaceHint => 'Die Stelle unter dem Fadenkreuz.';
}

// Path: confirmSheet
class _Translations$confirmSheet$de extends Translations$confirmSheet$en {
	_Translations$confirmSheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Noch da?';
	@override String get body => 'Waren Sie kürzlich dort? Ihre Antwort zeigt den nächsten Reisenden, dass die Platzseite aktuell ist. Es wird kein Standort gesendet.';
	@override String get stillOk => 'Ja, wie beschrieben';
	@override String get closed => 'Geschlossen';
	@override String get changed => 'Verändert';
	@override String get closedHint => 'Nimmt keine Reisenden mehr auf';
	@override String get changedHint => 'Noch da, aber etwas hat sich geändert';
	@override String get note => 'Etwas hinzuzufügen? (optional)';
	@override String get noteHint => 'Zum Beispiel: Höhenbegrenzung angebracht, V/E-Säule versetzt';
	@override late final _Translations$confirmSheet$status$de status = _Translations$confirmSheet$status$de._(_root);
}

// Path: issueSheet
class _Translations$issueSheet$de extends Translations$issueSheet$en {
	_Translations$issueSheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Problem melden';
	@override String get body => 'Ihre Meldung fließt in die Warnung auf der Platzseite ein. Ihre Anmerkung sieht nur die Moderation.';
	@override late final _Translations$issueSheet$kind$de kind = _Translations$issueSheet$kind$de._(_root);
	@override late final _Translations$issueSheet$hint$de hint = _Translations$issueSheet$hint$de._(_root);
	@override String get note => 'Etwas hinzuzufügen? (optional)';
	@override String get send => 'Melden';
}

// Path: reportSheet
class _Translations$reportSheet$de extends Translations$reportSheet$en {
	_Translations$reportSheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get review => 'Diese Rezension melden';
	@override String get photo => 'Dieses Foto melden';
	@override String get place => 'Diesen Platz melden';
	@override String get body => 'Die Moderation sieht sich das an. Der Autor erfährt nicht, wer es gemeldet hat.';
	@override late final _Translations$reportSheet$reason$de reason = _Translations$reportSheet$reason$de._(_root);
	@override String get note => 'Mehr dazu (optional)';
	@override String get noteOther => 'Beschreiben Sie, was nicht stimmt';
	@override String get sent => 'Danke, die Moderation sieht es sich an';
	@override String mute({required Object name}) => 'Rezensionen und Fotos von ${name} ausblenden';
	@override String get muteAuthor => 'Diesen Autor ausblenden';
	@override String muteTitle({required Object name}) => '${name} ausblenden?';
	@override String get muteBody => 'Die Rezensionen und Fotos dieser Person werden Ihnen nicht mehr angezeigt. Sie können das im Profil rückgängig machen.';
	@override String muted({required Object name}) => '${name} ist ausgeblendet';
	@override String get deletePhoto => 'Mein Foto löschen';
	@override String get deletePhotoTitle => 'Dieses Foto löschen?';
	@override String get deletePhotoBody => 'Es wird von der Platzseite und von unseren Servern entfernt.';
}

// Path: reviewSheet
class _Translations$reviewSheet$de extends Translations$reviewSheet$en {
	_Translations$reviewSheet$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get titleNew => 'Ihre Rezension';
	@override String get titleEdit => 'Ihre Rezension bearbeiten';
	@override String get starsRequired => 'Wählen Sie eine Bewertung von 1 bis 5';
	@override String get text => 'Ihre Rezension';
	@override String get textHint => 'Die Ruhe, der Empfang, der Platz zum Rangieren, was Ihnen geholfen hat';
	@override String tooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Noch mindestens ${n} Zeichen',
		other: 'Noch mindestens ${n} Zeichen',
	);
	@override String get visited => 'Datum des Aufenthalts';
	@override String get visitedNone => 'Keine Angabe';
	@override String get vehicle => 'Ihr Fahrzeug';
	@override String get vehicleNone => 'Keine Angabe';
	@override String get licence => 'Veröffentlicht unter CC BY 4.0, mit Ihrem Pseudonym. Das Datum des Aufenthalts ist optional: Zusammengenommen können die Daten Ihrer Rezensionen Ihre Reiseroute verraten.';
	@override String get publish => 'Rezension veröffentlichen';
}

// Path: gate
class _Translations$gate$de extends Translations$gate$en {
	_Translations$gate$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get review => 'Rezensionen mit Text: ab Stufe 1';
	@override String get photo => 'Fotos: ab Stufe 1';
	@override String get addPlace => 'Plätze hinzufügen: ab Stufe 2';
	@override String get edit => 'Änderungen vorschlagen: ab Stufe 1';
	@override String get why => 'Die Stufen schützen die Karte vor Missbrauch. Höhere Stufen erreichen Sie mit der Zeit und durch Beiträge, kaufen lassen sie sich nicht.';
	@override String yourLevel({required Object level}) => 'Ihre Stufe: ${level}';
	@override String get noAccount => 'Noch kein Konto: Ein Konto beginnt mit Stufe 0.';
	@override String later({required Object level}) => 'Stufe ${level} erreichen Sie nach den vorherigen Stufen, mit der Zeit und durch veröffentlichte Beiträge.';
	@override String get meanwhile => 'Bis dahin können Sie Plätze bewerten, bestätigen, dass es sie noch gibt, oder ein Problem melden.';
}

// Path: photoFlow
class _Translations$photoFlow$de extends Translations$photoFlow$en {
	_Translations$photoFlow$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Foto hinzufügen';
	@override String get camera => 'Foto aufnehmen';
	@override String get gallery => 'Aus der Galerie wählen';
	@override String get preparing => 'Foto wird vorbereitet';
	@override String get licence => 'Veröffentlicht unter CC BY 4.0, mit Ihrem Pseudonym. Vermeiden Sie Gesichter und Kennzeichen.';
	@override String get stripped => 'Standort- und Gerätedaten werden vor dem Senden entfernt.';
	@override String get send => 'Foto senden';
	@override String get unreadable => 'Dieses Bild kann auf diesem Gerät nicht gelesen werden. Versuchen Sie es mit einem JPEG- oder PNG-Foto.';
	@override String sending({required Object percent}) => 'Wird gesendet: ${percent} %';
	@override String get pending => 'Foto wartet auf Versand';
}

// Path: placeForm
class _Translations$placeForm$de extends Translations$placeForm$en {
	_Translations$placeForm$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get addTitle => 'Platz hinzufügen';
	@override String get editTitle => 'Platz bearbeiten';
	@override String get proposeTitle => 'Änderung vorschlagen';
	@override String get position => 'Position auf der Karte';
	@override String get kind => 'Art des Platzes';
	@override String get kindRequired => 'Wählen Sie eine Art';
	@override String get name => 'Name';
	@override String get nameHint => 'Der Name vor Ort oder eine kurze Beschreibung';
	@override String get nameInvalid => '2 bis 120 Zeichen';
	@override String get night => 'Übernachtung';
	@override String get services => 'Ausstattung vor Ort';
	@override String get description => 'Beschreibung';
	@override String get descriptionHint => 'Was hilft, den Platz zu finden und auszuwählen';
	@override String get details => 'Details';
	@override String get priceNight => 'Preis pro Nacht (€)';
	@override String get priceServices => 'Preis für Ver- und Entsorgung (€)';
	@override String get maxHeight => 'Maximale Höhe (m)';
	@override String get capacity => 'Anzahl Stellplätze';
	@override String get website => 'Website';
	@override String get phone => 'Telefon';
	@override String get photo => 'Foto (optional)';
	@override String get photoReady => 'Foto bereit';
	@override String get removePhoto => 'Foto entfernen';
	@override String get toVerify => 'Der Platz erscheint als „zu prüfen“, bis zwei andere Reisende ihn bestätigen.';
	@override String get licence => 'Plätze werden unter der ODbL veröffentlicht, mit Nennung der Lunaway-Mitwirkenden.';
	@override String get moderated => 'Eine Website oder Telefonnummer wird vor der Veröffentlichung von der Moderation geprüft.';
	@override String get direct => 'Mit Ihrer Stufe gilt die Änderung sofort.';
	@override String get proposal => 'Die Moderation prüft Ihren Vorschlag, bevor er übernommen wird.';
	@override String get submitAdd => 'Platz hinzufügen';
	@override String get submitEdit => 'Änderung speichern';
	@override String get submitPropose => 'Vorschlag senden';
	@override String get nothingChanged => 'Nichts geändert';
	@override String get invalidNumber => 'Bitte eine Zahl eingeben';
	@override String get invalidWebsite => 'Eine Adresse, die mit http:// oder https:// beginnt';
	@override String get added => 'Danke: Der Platz erscheint gleich auf der Karte';
	@override String get proposed => 'Danke: Ihr Vorschlag geht in die Prüfung';
}

// Path: favoritesSync
class _Translations$favoritesSync$de extends Translations$favoritesSync$en {
	_Translations$favoritesSync$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get local => 'Nur auf diesem Gerät';
	@override String get action => 'Synchronisieren';
	@override String get syncing => 'Wird synchronisiert';
	@override String synced({required Object when}) => 'Mit Ihrem Konto gespeichert, zuletzt synchronisiert ${when}';
	@override String get failed => 'Synchronisierung gerade nicht möglich';
	@override String get title => 'Ihre Favoriten synchronisieren?';
	@override String get body => 'Ihre Listen werden samt den darin gespeicherten Adressen und Notizen mit einem Lunaway-Konto gespeichert, ohne E-Mail und ohne Passwort, damit Sie sie auf einem anderen Gerät wiederfinden. Das Konto wird jetzt angelegt.';
	@override String get confirm => 'Konto anlegen und synchronisieren';
}

// Path: poi
class _Translations$poi$de extends Translations$poi$en {
	_Translations$poi$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override late final _Translations$poi$category$de category = _Translations$poi$category$de._(_root);
	@override late final _Translations$poi$kind$de kind = _Translations$poi$kind$de._(_root);
	@override String get chipsLabel => 'Geschäfte und Dienstleistungen in der Nähe';
	@override String get openNow => 'Jetzt geöffnet';
	@override late final _Translations$poi$vendingSells$de vendingSells = _Translations$poi$vendingSells$de._(_root);
	@override String get vendingAll => 'Alle Lebensmittelautomaten';
	@override String get vendingMenu => 'Was die Automaten verkaufen';
	@override late final _Translations$poi$vendingChip$de vendingChip = _Translations$poi$vendingChip$de._(_root);
	@override String get alwaysOpen => 'Tag und Nacht geöffnet';
	@override String get hoursUnknown => 'Öffnungszeiten unbekannt';
	@override String get maybeClosed => 'Laut dem offiziellen Verzeichnis der Einrichtungen des Gesundheitswesens (FINESS) geschlossen.';
	@override String maybeClosedSince({required Object date}) => 'Bei FINESS seit ${date} als geschlossen geführt: Möglicherweise ist die Einrichtung endgültig geschlossen.';
	@override String get seasonal => 'Saisonal: im Winter möglicherweise geschlossen.';
	@override String get fee => 'Kostenpflichtig';
	@override String get free => 'Kostenlos';
	@override String get stillThereTitle => 'Noch da?';
	@override String get stillThereHint => 'Kürzlich gesehen? Ihre Antwort hilft den nächsten Reisenden. Es wird kein Standort gesendet.';
	@override String get stillThere => 'Noch da';
	@override String get gone => 'Nicht mehr da';
	@override String lastConfirmed({required Object when}) => 'Als vorhanden bestätigt: ${when}';
	@override String checkedOn({required Object date}) => 'Vor Ort geprüft am ${date}';
	@override String get thanksThere => 'Danke, notiert: noch da.';
	@override String get thanksGone => 'Danke, notiert: nicht mehr da.';
	@override String get fuelPrices => 'Kraftstoffpreise';
	@override String perLitre({required Object price}) => '${price}/l';
	@override String priceUpdated({required Object when}) => 'Preis aktualisiert: ${when}';
	@override String feedRead({required Object when}) => 'Preise abgerufen: ${when}';
	@override String get shortageTemporary => 'Vorübergehend nicht verfügbar';
	@override String get shortageDefinitive => 'Nicht mehr im Angebot';
	@override String get selfService24h => '24-Stunden-Tankautomat';
	@override String get highway => 'An der Autobahn';
	@override String get lpgYes => 'Autogas (LPG) erhältlich';
	@override late final _Translations$poi$fuel$de fuel = _Translations$poi$fuel$de._(_root);
	@override String get products => 'Angebot';
	@override String get paymentTitle => 'Bezahlung';
	@override late final _Translations$poi$product$de product = _Translations$poi$product$de._(_root);
	@override late final _Translations$poi$payment$de payment = _Translations$poi$payment$de._(_root);
	@override String get justNow => 'gerade eben';
	@override String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'vor ${n} Minute',
		other: 'vor ${n} Minuten',
	);
	@override String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'vor ${n} Stunde',
		other: 'vor ${n} Stunden',
	);
	@override String readOffline({required Object when}) => 'Stand ${when}: kein Netz zum Aktualisieren';
	@override String readStale({required Object when}) => 'Stand ${when}: Die Aktualisierung hat gerade nicht geklappt.';
	@override String get goneTitle => 'Dieser Punkt ist nicht mehr auf der Karte';
	@override String get goneHint => 'Reisende haben gemeldet, dass es ihn nicht mehr gibt, oder die letzte Aktualisierung hat ihn entfernt.';
	@override String get loadError => 'Die Details konnten nicht geladen werden. Was die Karte darüber weiß, steht oben.';
	@override String get around => 'Rund um diesen Platz';
	@override String get aroundEmpty => 'Keine Geschäfte oder Dienstleistungen in der Nähe bekannt.';
	@override String get aroundError => 'Die Geschäfte und Dienstleistungen in der Nähe konnten nicht geladen werden.';
	@override String get aroundOffline => 'Keine Verbindung: Die Geschäfte und Dienstleistungen in der Nähe erscheinen, sobald Sie online sind.';
	@override String get onSite => 'Vor Ort';
	@override String backTo({required Object name}) => 'Zurück zu ${name}';
	@override String get backToPlace => 'Zurück zum Platz';
	@override String get linkError => 'Dieser Eintrag ließ sich nicht öffnen: kein Netz, oder er ist nicht mehr auf der Karte.';
	@override String get searchSection => 'Geschäfte und Dienstleistungen';
	@override String get searching => 'Geschäfte und Dienstleistungen werden gesucht';
	@override String get searchOffline => 'Geschäfte und Dienstleistungen werden online gesucht: Gerade gibt es kein Netz.';
	@override late final _Translations$poi$add$de add = _Translations$poi$add$de._(_root);
	@override late final _Translations$poi$cheapest$de cheapest = _Translations$poi$cheapest$de._(_root);
	@override late final _Translations$poi$trend$de trend = _Translations$poi$trend$de._(_root);
	@override String get marketDays => 'Markttage';
	@override late final _Translations$poi$vehicles$de vehicles = _Translations$poi$vehicles$de._(_root);
	@override String searchKindNear({required Object what}) => '${what} in der Nähe';
	@override String searchKindIn({required Object what, required Object town}) => '${what} in ${town}';
	@override late final _Translations$poi$cuisine$de cuisine = _Translations$poi$cuisine$de._(_root);
	@override late final _Translations$poi$details$de details = _Translations$poi$details$de._(_root);
	@override late final _Translations$poi$diet$de diet = _Translations$poi$diet$de._(_root);
	@override late final _Translations$poi$reservation$de reservation = _Translations$poi$reservation$de._(_root);
	@override late final _Translations$poi$vehicleService$de vehicleService = _Translations$poi$vehicleService$de._(_root);
}

// Path: offlineMaps
class _Translations$offlineMaps$de extends Translations$offlineMaps$en {
	_Translations$offlineMaps$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Offline-Karten';
	@override String get intro => 'Speichern Sie vor der Abreise eine Region auf dem Gerät: ihre Plätze zum Suchen und Auswählen, ihre Karte für die Straßen ohne Netz.';
	@override String get webTitle => 'Offline-Karten gibt es in der App';
	@override String get web => 'Die Apps für Android und iOS speichern Regionen für unterwegs. Im Browser braucht die Karte das Netz.';
	@override String get desktopTitle => 'Offline-Karten gibt es auf dem Smartphone';
	@override String get desktop => 'Die Apps für Android und iOS speichern Regionen für unterwegs. Am Computer braucht die Karte das Netz.';
	@override String get unreadable => 'Die Offline-Karten dieses Geräts konnten nicht geladen werden.';
	@override String get none => 'Noch keine Region auf diesem Gerät.';
	@override String used({required Object size}) => 'Belegter Speicher: ${size}';
	@override String get downloads => 'Downloads';
	@override String get installed => 'Auf diesem Gerät';
	@override String get suggested => 'Vorschläge';
	@override String get here => 'Wo Sie gerade sind';
	@override String favoritesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Favorit in dieser Region',
		other: '${n} Favoriten in dieser Region',
	);
	@override String get france => 'Frankreich';
	@override String get overseas => 'Überseegebiete';
	@override String get countries => 'Länder';
	@override String downloadNamed({required Object name, required Object size}) => '${name} herunterladen, ${size}';
	@override String get pause => 'Pausieren';
	@override String get resume => 'Fortsetzen';
	@override String get cancel => 'Download abbrechen und löschen';
	@override String get waiting => 'In der Warteschlange';
	@override String progress({required Object done, required Object total}) => '${done} von ${total}';
	@override String paused({required Object done, required Object total}) => 'Pausiert bei ${done} von ${total}';
	@override String get verifying => 'Datei wird geprüft';
	@override String get failedNetwork => 'Unterbrochen: kein Netz. Der Download wird an derselben Stelle fortgesetzt, sobald das Netz wieder da ist.';
	@override String get failedServer => 'Der Server hat etwas anderes als die Karte gesendet. Versuchen Sie es später erneut.';
	@override String get failedCorrupt => 'Die Datei kam beschädigt an und wurde gelöscht. Versuchen Sie es erneut.';
	@override String get failedStorage => 'Nicht mehr genug Speicherplatz auf dem Gerät. Geben Sie Speicher frei und versuchen Sie es dann erneut.';
	@override String get keepOpen => 'Lassen Sie die App während des Downloads geöffnet: Er wird unterbrochen, wenn die App in den Hintergrund geht, und fortgesetzt, wenn Sie zurückkehren.';
	@override String dataOf({required Object date}) => 'Daten vom ${date}';
	@override String update({required Object size}) => 'Aktualisieren, ${size}';
	@override String deleteNamed({required Object name}) => '${name} löschen';
	@override String deleteTitle({required Object name}) => '${name} von diesem Gerät löschen?';
	@override String get deleteBody => 'Die Karte erscheint dann nicht mehr ohne Netz. Sie können sie erneut herunterladen.';
	@override String get listOffline => 'Die Liste der Regionen braucht das Netz.';
	@override String get listCopy => 'Zuletzt geladene Liste.';
	@override String get entryHint => 'Zum Reisen ohne Netz';
	@override String entryCount({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Karten: ${n} Region, ${size}',
		other: 'Karten: ${n} Regionen, ${size}',
	);
	@override String noticePack({required Object name}) => 'Offline: heruntergeladene Karte, ${name}';
	@override String get noticeOutside => 'Offline: Dieses Gebiet ist nicht heruntergeladen';
	@override String get noticePlacesOnly => 'Offline: Plätze auf dem Gerät, Karte dieses Gebiets nicht heruntergeladen';
	@override String get noticeNone => 'Offline: Laden Sie für das nächste Mal eine Region herunter';
	@override String get noticeOnline => 'Offline: Die Karte braucht das Netz';
	@override String get placesTitle => 'Plätze';
	@override String get placesHint => 'Wenige Megabyte pro Region: Liste, Suche, Platzseiten und Filter funktionieren ohne Netz.';
	@override String get mapsTitle => 'Karten';
	@override String get mapsHint => 'Alle Straßen, einige hundert Megabyte pro Region: Die Karte erscheint ohne Netz.';
	@override String entryPlaces({required Object names}) => 'Plätze: ${names}';
	@override String entryPlacesCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Plätze: ${n} Region',
		other: 'Plätze: ${n} Regionen',
	);
}

// Path: regions
class _Translations$regions$de extends Translations$regions$en {
	_Translations$regions$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get pickerTitle => 'Welche Plätze sollen auf diesem Gerät bleiben?';
	@override String get pickerIntro => 'Jede Region wird einmal heruntergeladen und danach in kleinen Schritten aktualisiert. Sie können später unter Offline-Karten Regionen hinzufügen oder entfernen.';
	@override String nearYou({required Object name}) => 'In Ihrer Nähe: ${name}';
	@override String get findMine => 'Meine Region finden';
	@override String get locating => 'Ihre Region wird gesucht';
	@override String get notCovered => 'Noch keine Lunaway-Region in Ihrer Nähe';
	@override String get wholeFrance => 'Ganz Frankreich';
	@override String get showFrance => 'Regionen Frankreichs anzeigen';
	@override String get hideFrance => 'Regionen Frankreichs ausblenden';
	@override String packInfo({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${count} Platz, ${size}',
		other: '${count} Plätze, ${size}',
	);
	@override String get noPack => 'Kein Paket: Plätze kommen mit den Updates, Größe unbekannt';
	@override String download({required Object size}) => 'Herunterladen, ${size}';
	@override String get unavailable => 'Der Server bietet noch keine Regionen an: Lunaway behält ganz Frankreich.';
	@override String get listFailed => 'Die Liste der Regionen braucht das Netz.';
	@override String get choose => 'Regionen wählen';
	@override String get noneKept => 'Keine Region gespeichert: Die Karte hat offline keine Plätze.';
	@override String get change => 'Regionen hinzufügen oder entfernen';
	@override String removeNamed({required Object name}) => '${name} entfernen';
	@override String removed({required Object name}) => '${name}: Plätze von diesem Gerät entfernt';
	@override String downloading({required Object done, required Object total}) => 'Download, ${done} von ${total}';
	@override String updating({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Aktualisierung, ${count} Platz',
		other: 'Aktualisierung, ${count} Plätze',
	);
	@override String get waiting => 'wartet auf den Download';
	@override String downloadingNamed({required Object name}) => 'Plätze werden heruntergeladen: ${name}';
	@override String updated({required Object when}) => 'aktualisiert ${when}';
	@override String offerTitle({required Object name}) => '${name}: Plätze offline speichern?';
	@override String get downloadThis => 'Diese Region herunterladen';
	@override String notHere({required Object name}) => '${name} ist nicht auf diesem Gerät';
	@override String get updatesOnMobile => 'Auch über mobile Daten aktualisieren';
	@override String get updatesOnMobileHint => 'Sonst werden bereits heruntergeladene Regionen über WLAN aktualisiert. Ein neuer Download nutzt jedes Netz.';
}

// Path: roadReport
class _Translations$roadReport$de extends Translations$roadReport$en {
	_Translations$roadReport$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get actionHint => 'Ein Problem auf der Straße melden';
	@override String get title => 'Was sehen Sie auf der Straße?';
	@override String get intro => 'Ihre Meldung warnt andere Reisende. Wenn zwei vertrauenswürdige Konten dasselbe melden, umgehen die Routen die Stelle. Polizeikontrollen können nicht gemeldet werden.';
	@override late final _Translations$roadReport$kinds$de kinds = _Translations$roadReport$kinds$de._(_root);
	@override String height({required Object value}) => 'Ausgeschilderte Höhe: ${value}';
	@override String get send => 'Melden';
	@override String get sent => 'Danke: Andere Reisende sind gewarnt.';
	@override String get stillThere => 'Noch da';
	@override String get over => 'Ist vorbei';
	@override String get overSent => 'Danke: notiert.';
	@override String get fromMap => 'Hier ein Problem melden';
	@override String get notHereTitle => 'Hier keine Meldung möglich';
	@override String get lower => '10 cm niedriger';
	@override String get higher => '10 cm höher';
	@override String passed({required Object what}) => 'Gerade passiert: ${what}. Noch da?';
	@override String notHere({required Object countries}) => 'Lunaway nimmt Meldungen dort an, wo ein offizieller Datenfeed sie abgleicht: ${countries}.';
}

// Path: countries
class _Translations$countries$de extends Translations$countries$en {
	_Translations$countries$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get ad => 'Andorra';
	@override String get at => 'Österreich';
	@override String get ax => 'Åland';
	@override String get be => 'Belgien';
	@override String get ch => 'Schweiz';
	@override String get cz => 'Tschechien';
	@override String get de => 'Deutschland';
	@override String get dk => 'Dänemark';
	@override String get eh => 'Westsahara';
	@override String get es => 'Spanien';
	@override String get fi => 'Finnland';
	@override String get fr => 'Frankreich';
	@override String get gb => 'Vereinigtes Königreich';
	@override String get gi => 'Gibraltar';
	@override String get gr => 'Griechenland';
	@override String get hr => 'Kroatien';
	@override String get ie => 'Irland';
	@override String get it => 'Italien';
	@override String get li => 'Liechtenstein';
	@override String get lu => 'Luxemburg';
	@override String get ma => 'Marokko';
	@override String get mc => 'Monaco';
	@override String get nl => 'Niederlande';
	@override String get no => 'Norwegen';
	@override String get pl => 'Polen';
	@override String get pt => 'Portugal';
	@override String get se => 'Schweden';
	@override String get si => 'Slowenien';
	@override String get sj => 'Spitzbergen';
	@override String get sm => 'San Marino';
	@override String get va => 'Vatikanstadt';
}

// Path: areas
class _Translations$areas$de extends Translations$areas$en {
	_Translations$areas$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get ara => 'Auvergne-Rhône-Alpes';
	@override String get bfc => 'Bourgogne-Franche-Comté';
	@override String get bre => 'Bretagne';
	@override String get cvl => 'Centre-Val de Loire';
	@override String get cor => 'Korsika';
	@override String get ges => 'Grand Est';
	@override String get hdf => 'Hauts-de-France';
	@override String get idf => 'Île-de-France';
	@override String get nor => 'Normandie';
	@override String get naq => 'Nouvelle-Aquitaine';
	@override String get occ => 'Okzitanien';
	@override String get pdl => 'Pays de la Loire';
	@override String get pac => 'Provence-Alpes-Côte d\'Azur';
	@override String get gp => 'Guadeloupe';
	@override String get mq => 'Martinique';
	@override String get gf => 'Französisch-Guayana';
	@override String get re => 'Réunion';
	@override String get yt => 'Mayotte';
	@override String get franceRest => 'Frankreich, ohne Gemeindezuordnung';
}

// Path: search.addressKind
class _Translations$search$addressKind$de extends Translations$search$addressKind$en {
	_Translations$search$addressKind$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get houseNumber => 'Adresse';
	@override String get street => 'Straße';
	@override String get locality => 'Ortsteil';
	@override String get town => 'Gemeinde';
	@override String get postcode => 'Postleitzahl';
	@override String get region => 'Region';
}

// Path: place.inclusions
class _Translations$place$inclusions$de extends Translations$place$inclusions$en {
	_Translations$place$inclusions$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get services => 'Ver- und Entsorgung';
	@override String get touristTax => 'Kurtaxe';
	@override String get electricity => 'Strom';
}

// Path: place.reviewVehicle
class _Translations$place$reviewVehicle$de extends Translations$place$reviewVehicle$en {
	_Translations$place$reviewVehicle$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Kastenwagen';
	@override String get motorhome => 'Wohnmobil';
	@override String get caravan => 'Wohnwagen';
	@override String get other => 'Anderes Fahrzeug';
}

// Path: sources.extcom
class _Translations$sources$extcom$de extends Translations$sources$extcom$en {
	_Translations$sources$extcom$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get label => 'Externe Community-Quelle';
	@override String get short => 'Extern';
}

// Path: hours.codes
class _Translations$hours$codes$de extends Translations$hours$codes$en {
	_Translations$hours$codes$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get mo => 'Mo.';
	@override String get tu => 'Di.';
	@override String get we => 'Mi.';
	@override String get th => 'Do.';
	@override String get fr => 'Fr.';
	@override String get sa => 'Sa.';
	@override String get su => 'So.';
	@override String get ph => 'Feiertage';
	@override String get sh => 'Schulferien';
	@override String get off => 'geschlossen';
	@override String get closed => 'geschlossen';
	@override String get sunrise => 'Sonnenaufgang';
	@override String get sunset => 'Sonnenuntergang';
}

// Path: hours.months
class _Translations$hours$months$de extends Translations$hours$months$en {
	_Translations$hours$months$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get jan => 'Jan.';
	@override String get feb => 'Feb.';
	@override String get mar => 'März';
	@override String get apr => 'Apr.';
	@override String get may => 'Mai';
	@override String get jun => 'Juni';
	@override String get jul => 'Juli';
	@override String get aug => 'Aug.';
	@override String get sep => 'Sept.';
	@override String get oct => 'Okt.';
	@override String get nov => 'Nov.';
	@override String get dec => 'Dez.';
}

// Path: navigation.preview
class _Translations$navigation$preview$de extends Translations$navigation$preview$en {
	_Translations$navigation$preview$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String titleTo({required Object name}) => 'Ziel: ${name}';
	@override String get titlePoint => 'Punkt auf der Karte';
	@override late final _Translations$navigation$preview$departure$de departure = _Translations$navigation$preview$departure$de._(_root);
	@override String get computing => 'Route für Ihr Fahrzeug wird berechnet';
	@override String get start => 'Starten';
	@override String get recommended => 'Empfohlen';
	@override String alternative({required Object n}) => 'Alternative ${n}';
	@override String get toll => 'Maut';
	@override String get ferry => 'Fähre';
	@override String get motorway => 'Autobahn';
	@override String get noWarnings => 'Auf dieser Route wird keine Beschränkung für Ihr Fahrzeug knapp.';
	@override String warnings({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '1 Beschränkung zu beachten',
		other: '${n} Beschränkungen zu beachten',
	);
	@override String get vehicle => 'Ihr Fahrzeug';
	@override String vehicleTowing({required Object vehicle}) => '${vehicle}, als Gespann';
	@override String get editVehicle => 'Bearbeiten';
	@override String cruise({required Object speed}) => 'Berechnet mit max. ${speed}';
	@override String slowStretch({required Object duration, required Object distance}) => 'Davon ${duration} für ${distance} sehr langsame Strecke';
	@override String get avoid => 'Vermeiden';
	@override String get avoidTolls => 'Mautstraßen';
	@override String get avoidMotorways => 'Autobahnen';
	@override String get avoidFerries => 'Fähren';
	@override String get avoidUnpaved => 'Unbefestigte Straßen';
	@override String get roadbook => 'Wegbeschreibung';
	@override String get roadbookShow => 'Anweisungen anzeigen';
	@override String get roadbookHide => 'Anweisungen ausblenden';
	@override String dataOf({required Object date}) => 'Straßendaten vom ${date}';
	@override String get attributionOsm => '© OpenStreetMap-Mitwirkende';
	@override String attributionIgn({required Object date}) => 'IGN, BD TOPO, Ausgabe vom ${date}';
	@override String get otherApps => 'Öffnen in …';
	@override String get back => 'Zurück';
	@override late final _Translations$navigation$preview$moved$de moved = _Translations$navigation$preview$moved$de._(_root);
}

// Path: navigation.stops
class _Translations$navigation$stops$de extends Translations$navigation$stops$en {
	_Translations$navigation$stops$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Zwischenstopps';
	@override String get add => 'Als Stopp hinzufügen';
	@override String addCost({required Object minutes}) => 'Als Stopp hinzufügen · +${minutes} Min.';
	@override String get addFree => 'Als Stopp hinzufügen · ohne Umweg';
	@override String get quoting => 'Als Stopp hinzufügen · Umweg wird berechnet';
	@override String get noRoute => 'Keine Route über diesen Punkt für Ihr Fahrzeug.';
	@override String get full => 'Höchstens fünf Zwischenstopps.';
	@override String get goDirectly => 'Direkt hinfahren';
	@override String get openCard => 'Details ansehen';
	@override String get point => 'Punkt auf der Karte';
	@override String get remove => 'Zwischenstopp entfernen';
	@override String get reorder => 'Ziehen, um die Reihenfolge zu ändern';
	@override String get added => 'Zwischenstopp hinzugefügt';
	@override String get removed => 'Zwischenstopp entfernt';
	@override String get moved => 'Reihenfolge geändert';
	@override String get destinationChanged => 'Neues Ziel';
	@override String get failed => 'Die Route konnte nicht geändert werden.';
	@override String get noQuote => 'Der Umweg konnte nicht berechnet werden.';
	@override String get offline => 'Keine Verbindung, um den Umweg zu berechnen.';
}

// Path: navigation.legs
class _Translations$navigation$legs$de extends Translations$navigation$legs$en {
	_Translations$navigation$legs$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get all => 'Alle';
	@override String stop({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}';
	@override String stopSaid({required Object number, required Object name, required Object time, required Object distance}) => 'Zwischenstopp ${number}: ${name}, gegen ${time}, in ${distance}';
	@override String arrival({required Object name, required Object time}) => 'Ziel · ${name} · ${time}';
	@override String arrivalSaid({required Object name, required Object time}) => 'Ziel: ${name}, gegen ${time}';
	@override String remove({required Object number, required Object name}) => 'Zwischenstopp ${number} entfernen, ${name}';
}

// Path: navigation.fuel
class _Translations$navigation$fuel$de extends Translations$navigation$fuel$en {
	_Translations$navigation$fuel$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String price({required Object price}) => '${price} €/l';
	@override String withDetour({required Object price}) => '${price} €/l inkl. Umweg';
	@override String detour({required Object distance, required Object minutes}) => '+${distance} · +${minutes} Min.';
	@override String get onRoute => 'an der Route';
	@override String get open => 'Geöffnet';
	@override String get closed => 'Geschlossen';
	@override String get unknownHours => 'Öffnungszeiten unbekannt';
	@override String get add => 'Hinzufügen';
	@override String get station => 'Tankstelle';
	@override String get empty => 'Keine Tankstelle mit einem Preis für diesen Kraftstoff nahe der Route.';
	@override String get emptyHint => 'Die Preise stammen vom französischen Wirtschaftsministerium und sind nur für Frankreich bekannt.';
	@override String get failed => 'Die Tankstellen konnten nicht geladen werden.';
	@override String get estimated => 'Umwege anhand der Entfernung zur Route geschätzt.';
	@override String get attribution => 'Preise: französisches Wirtschaftsministerium (data.economie.gouv.fr)';
	@override String minutesAgo({required Object n}) => 'vor ${n} Min.';
	@override String hoursAgo({required Object n}) => 'vor ${n} Std.';
	@override String daysAgo({required Object n}) => 'vor ${n} Tagen';
}

// Path: navigation.onTheWay
class _Translations$navigation$onTheWay$de extends Translations$navigation$onTheWay$en {
	_Translations$navigation$onTheWay$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Unterwegs';
	@override late final _Translations$navigation$onTheWay$categories$de categories = _Translations$navigation$onTheWay$categories$de._(_root);
	@override String fuelOfVehicle({required Object fuel}) => '${fuel}, laut Ihrem Fahrzeug';
	@override String get otherFuel => 'Anderer Kraftstoff';
	@override String get keepFuel => 'Als meinen Kraftstoff speichern';
	@override String fuelKept({required Object fuel}) => '${fuel} für Ihr Fahrzeug gespeichert.';
	@override String get keepFuelFailed => 'Der Kraftstoff konnte nicht gespeichert werden.';
	@override String get loading => 'Suche entlang der Route';
	@override String get empty => 'Keine Treffer auf dieser Route';
	@override String get emptyHint => 'Versuchen Sie eine andere Kategorie, oder öffnen Sie die Liste weiter vorne auf der Strecke erneut.';
	@override String get failed => 'Die Liste konnte nicht geladen werden.';
	@override String get offline => 'Keine Verbindung: Die Liste kommt mit der Verbindung zurück.';
	@override String get rateLimited => 'Viele Suchen hintereinander: Versuchen Sie es in einigen Minuten erneut.';
	@override String nearNone({required Object distance}) => 'Nichts auf den nächsten ${distance}.';
	@override String further({required Object n}) => 'Weiter entfernt (${n})';
	@override String get more => 'Mehr anzeigen';
	@override String get moreFailed => 'Der Rest konnte nicht geladen werden.';
	@override String ahead({required Object distance}) => 'in ${distance}';
	@override String offRoute({required Object distance}) => '${distance} von der Route';
	@override String get byTheRoad => 'direkt an der Straße';
	@override String addCost({required Object minutes}) => 'Hinzufügen · +${minutes} Min.';
	@override String get addFree => 'Hinzufügen · ohne Umweg';
	@override String openAt({required Object time}) => 'Geöffnet, wenn Sie vorbeikommen (gegen ${time})';
	@override String closedAt({required Object time}) => 'Geschlossen, wenn Sie vorbeikommen (gegen ${time})';
	@override String closedOpensAt({required Object time, required Object opens}) => 'Geschlossen, wenn Sie gegen ${time} vorbeikommen, öffnet um ${opens}';
	@override String perNight({required Object price}) => '${price} pro Nacht';
	@override String photoFrom({required Object source}) => 'Foto: ${source}';
	@override String servicesList({required Object list}) => 'Ausstattung: ${list}';
	@override String get placesCredit => 'Plätze: Lunaway und die auf jeder Platzseite genannten Quellen';
}

// Path: navigation.states
class _Translations$navigation$states$de extends Translations$navigation$states$en {
	_Translations$navigation$states$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get vehicleTitle => 'Was fahren Sie?';
	@override String get vehicleHint => 'Die Route meidet zu niedrige Brücken, zu enge Straßen und Straßen, die für Ihre Fahrzeugmaße gesperrt sind. Geben Sie Höhe, Breite, Länge und Gewicht an.';
	@override String vehicleMissing({required Object list}) => 'Fehlende Angaben: ${list}';
	@override String vehicleOutOfBounds({required Object list}) => 'Außerhalb des zulässigen Bereichs: ${list}';
	@override late final _Translations$navigation$states$dimension$de dimension = _Translations$navigation$states$dimension$de._(_root);
	@override String get describeVehicle => 'Mein Fahrzeug beschreiben';
	@override String get originTitle => 'Wo sind Sie?';
	@override String get originHint => 'Lunaway braucht Ihren Standort, um die Route zu berechnen.';
	@override String get locate => 'Mich orten';
	@override String get offlineTitle => 'Keine Verbindung';
	@override String get offlineHint => 'Routen werden auf dem Server von Lunaway berechnet. Ohne Netz übergibt „Öffnen in …“ die Fahrt an eine Navigations-App mit eigenen Karten.';
	@override String get rateLimitedTitle => 'Zu viele Routenanfragen';
	@override String rateLimitedHint({required Object seconds}) => 'Versuchen Sie es in ${seconds} s erneut.';
	@override String get unavailableTitle => 'Routenberechnung nicht verfügbar';
	@override String get unavailableHint => 'Der Routendienst ist vorübergehend nicht verfügbar. Versuchen Sie es später erneut.';
	@override String get refusedTitle => 'Keine Route möglich';
	@override String get refusedHint => 'Lunaway konnte für diese Anfrage keine Route berechnen: Prüfen Sie das Ziel, die Länge der Strecke und die Angaben zum Fahrzeug.';
	@override String get noSafeTitle => 'Keine sichere Route für Ihr Fahrzeug';
	@override String get noSafeHint => 'Jede mögliche Strecke führt über eine Beschränkung, die Ihr Fahrzeug überschreitet:';
	@override String get whatToDo => 'Was Sie tun können';
	@override String checkVehicle({required Object height, required Object weight}) => 'Prüfen Sie Ihre Angaben: ${height} hoch, ${weight}.';
	@override String get pickOtherPoint => 'Wählen Sie ein Ziel vor dem Hindernis: Halten Sie dazu einen Punkt auf der Karte gedrückt.';
	@override String get pickOtherPointClick => 'Wählen Sie ein Ziel vor dem Hindernis: Klicken Sie dazu mit der rechten Maustaste auf die Karte.';
	@override String get noRouteTitle => 'Keine Straße führt dorthin';
	@override String get noRouteHint => 'Der Punkt liegt vielleicht an einem Privatweg oder auf einer Insel ohne Fähre.';
	@override String get allowUnpaved => 'Unbefestigte Straßen werden gemieden: Erlauben Sie sie, wenn das Ziel an einem Feldweg liegt.';
	@override String get offNetworkTitle => 'Zu weit von einer Straße entfernt';
	@override String get offNetworkHint => 'Wählen Sie ein Ziel an einer Straße.';
}

// Path: navigation.noRoute
class _Translations$navigation$noRoute$de extends Translations$navigation$noRoute$en {
	_Translations$navigation$noRoute$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get originUnreachable => 'Vom Startpunkt kein Durchkommen für Ihr Fahrzeug';
	@override String originUnreachableBy({required Object limit}) => 'Vom Startpunkt kein Durchkommen für Ihr Fahrzeug: ${limit}';
	@override String get destinationUnreachable => 'Ziel für Ihr Fahrzeug nicht erreichbar';
	@override String destinationUnreachableBy({required Object limit}) => 'Ziel für Ihr Fahrzeug nicht erreichbar: ${limit}';
	@override String waypointUnreachable({required Object n}) => 'Zwischenstopp ${n} für Ihr Fahrzeug nicht erreichbar';
	@override String waypointUnreachableBy({required Object n, required Object limit}) => 'Zwischenstopp ${n} für Ihr Fahrzeug nicht erreichbar: ${limit}';
	@override String get blockedOnTheWay => 'Zwischen den Stopps kein Durchkommen für Ihr Fahrzeug';
	@override String blockedOnTheWayBy({required Object limit}) => 'Zwischen den Stopps kein Durchkommen für Ihr Fahrzeug: ${limit}';
	@override String get blockedHint => 'Jeder Stopp ist erreichbar, aber jede Straße dazwischen führt über eine Beschränkung, die Ihr Fahrzeug überschreitet.';
	@override String get notConnectedOrigin => 'Von Ihrem Standort führt keine Straße weg';
	@override String get notConnectedDestination => 'Keine Straße führt zum Ziel';
	@override String notConnectedWaypoint({required Object n}) => 'Keine Straße führt zu Zwischenstopp ${n}';
	@override String get notConnectedTrip => 'Keine Straße verbindet Ihre Stopps';
	@override String get notConnectedHint => 'Unabhängig vom Fahrzeug: eine Insel ohne Autofähre oder ein für den Verkehr gesperrter Weg.';
	@override String get outsideOrigin => 'Ihr Standort liegt außerhalb des Navigationsgebiets';
	@override String get outsideDestination => 'Ziel außerhalb des Navigationsgebiets';
	@override String outsideWaypoint({required Object n}) => 'Zwischenstopp ${n} außerhalb des Navigationsgebiets';
	@override String outsideHint({required Object countries}) => 'Lunaway berechnet Routen in diesen Ländern: ${countries}.';
	@override String get outsideHintUnknown => 'Lunaway berechnet in diesem Land noch keine Routen.';
	@override String get noRoadOrigin => 'Ihr Standort ist zu weit von einer Straße entfernt';
	@override String get noRoadDestination => 'Ziel zu weit von einer Straße entfernt';
	@override String noRoadWaypoint({required Object n}) => 'Zwischenstopp ${n} zu weit von einer Straße entfernt';
	@override String get noRoadHint => 'Im Umkreis von 5 km um diesen Punkt gibt es keine Straße, die Ihr Fahrzeug befahren darf.';
	@override String get tooLong => 'Strecke zu lang';
	@override String tooLongHint({required Object trip, required Object max}) => '${trip} Luftlinie von Stopp zu Stopp: Lunaway berechnet Strecken bis höchstens ${max}.';
	@override String vehicleValue({required Object value}) => 'Ihr Fahrzeug: ${value}';
	@override late final _Translations$navigation$noRoute$limit$de limit = _Translations$navigation$noRoute$limit$de._(_root);
	@override String get editVehicle => 'Fahrzeug bearbeiten';
	@override String get allowUnpaved => 'Unbefestigte Straßen erlauben';
	@override String removeStop({required Object n}) => 'Zwischenstopp ${n} entfernen';
	@override String removeStopNamed({required Object name}) => 'Zwischenstopp „${name}“ entfernen';
	@override String get placesAround => 'Plätze rund um das Ziel ansehen';
	@override String get moveDestination => 'Oder wählen Sie ein anderes Ziel: Halten Sie einen Punkt auf der Karte gedrückt und tippen Sie auf „Direkt hinfahren“.';
	@override String get moveDestinationClick => 'Oder wählen Sie ein anderes Ziel: Klicken Sie mit der rechten Maustaste auf die Karte und dann auf „Direkt hinfahren“.';
	@override String get moveStop => 'Für einen anderen Stopp: Zoomen Sie heran, tippen Sie auf die Karte oder halten Sie sie gedrückt, dann „Als Stopp hinzufügen“.';
	@override String get moveStopClick => 'Für einen anderen Stopp: Zoomen Sie heran, klicken Sie auf die Karte oder klicken Sie mit der rechten Maustaste, dann „Als Stopp hinzufügen“.';
	@override String get moveOrigin => 'Der Start ist Ihr Standort: Fahren Sie zu einer Straße, die Ihr Fahrzeug befahren darf, und versuchen Sie es dann erneut.';
	@override String get pickInside => 'Wählen Sie ein Ziel in einem dieser Länder.';
	@override String get shorter => 'Wählen Sie ein näheres Ziel oder fahren Sie die Strecke in mehreren Etappen.';
}

// Path: navigation.ferry
class _Translations$navigation$ferry$de extends Translations$navigation$ferry$en {
	_Translations$navigation$ferry$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String title({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Fährüberfahrt',
		other: '${n} Fährüberfahrten',
	);
	@override String get unnamed => 'Fähre';
	@override String named({required Object name}) => 'Fähre ${name}';
	@override String ports({required Object ports}) => 'Häfen: ${ports}';
	@override String countries({required Object from, required Object to}) => 'Abfahrt: ${from} · Ankunft: ${to}';
	@override String country({required Object country}) => 'Land: ${country}';
	@override String where({required Object distance, required Object sea, required Object duration}) => '${distance} nach dem Start · ${sea} auf See, etwa ${duration}';
	@override String get needed => 'Das Ziel ist ohne Fähre nicht erreichbar: Die Route nutzt eine, obwohl Sie Fähren meiden.';
}

// Path: navigation.warning
class _Translations$navigation$warning$de extends Translations$navigation$warning$en {
	_Translations$navigation$warning$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$warning$lowClearance$de lowClearance = _Translations$navigation$warning$lowClearance$de._(_root);
	@override String get unknownClearance => 'Niedrige Durchfahrt, Höhe unbekannt';
	@override String narrow({required Object limit}) => 'Engstelle ${limit}';
	@override String tooLong({required Object limit}) => 'Längenbeschränkung ${limit}';
	@override String tooHeavy({required Object limit}) => 'Gewichtsbeschränkung ${limit}';
	@override String axleLoad({required Object limit}) => 'Achslastbeschränkung ${limit}';
	@override String get motorhomeBan => 'Verbot für Wohnmobile';
	@override String get trailerBan => 'Verbot für Anhänger';
	@override String goodsVehicleWeight({required Object limit}) => 'Gewichtsbeschränkung für Lkw ${limit}';
	@override String yours({required Object value}) => 'Ihr Fahrzeug: ${value}';
	@override String fromStart({required Object distance}) => '${distance} nach dem Start';
	@override String ahead({required Object distance}) => 'In ${distance}';
	@override String get disputed => 'Quellen widersprechen sich, der niedrigere Wert gilt';
	@override String get goodsOnly => 'gilt für Lkw, beachten Sie die Schilder';
	@override String get osm => 'OpenStreetMap';
	@override String get ign => 'IGN BD TOPO';
	@override String get community => 'Lunaway-Meldung';
	@override String get dialog => 'Verkehrsanordnung (DiaLog)';
	@override late final _Translations$navigation$warning$localAccess$de localAccess = _Translations$navigation$warning$localAccess$de._(_root);
}

// Path: navigation.roadEvents
class _Translations$navigation$roadEvents$de extends Translations$navigation$roadEvents$en {
	_Translations$navigation$roadEvents$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Baustellen und Sperrungen';
	@override String get none => 'Keine Baustellen oder Sperrungen auf dieser Route bekannt.';
	@override String get stale => 'Baustellen und Sperrungen: Die Quellen wurden länger nicht abgefragt.';
	@override String avoided({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Route um eine Sperrung herum geplant: ${names}',
		other: 'Route um ${n} Sperrungen herum geplant: ${names}',
	);
	@override String atDistance({required Object distance}) => '${distance} nach dem Start';
	@override String more({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Und ${n} weitere auf der Route',
		other: 'Und ${n} weitere auf der Route',
	);
	@override String get classClosure => 'Straße gesperrt';
	@override String get classWorks => 'Baustelle';
	@override String get classLaneRestriction => 'Fahrbahnverengung';
	@override String get classVehicleLimit => 'Durchfahrtsbeschränkung';
	@override String get classDetour => 'Umleitung ausgeschildert';
	@override String get reasonUnmatched => 'Lage unsicher, vielleicht auf der Route';
	@override String get reasonStale => 'Quelle länger nicht abgefragt';
	@override String get reasonOutsideHours => 'außerhalb der vermuteten Zeiten';
	@override String get reasonGoodsVehicles => 'für Lkw';
	@override String get reasonUnconfirmed => 'von nur einem Reisenden gemeldet';
	@override String get reasonAged => 'ältere Meldung';
	@override String get reasonInside => 'die Route beginnt oder endet darin';
	@override String get reasonNearLimit => 'mit knappem Spielraum';
	@override String get reasonOverLimit => 'Ihr Fahrzeug überschreitet den Grenzwert';
}

// Path: navigation.marks
class _Translations$navigation$marks$de extends Translations$navigation$marks$en {
	_Translations$navigation$marks$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get legend => 'Legende';
	@override String get legendHide => 'Legende einklappen';
	@override String get kindOrigin => 'Start';
	@override String get kindDestination => 'Ziel';
	@override String get kindStop => 'Zwischenstopp';
	@override String get kindClosure => 'Straße gesperrt';
	@override String get kindWorks => 'Baustelle';
	@override String get kindLanes => 'Fahrbahnverengung';
	@override String get kindClearance => 'Höhenbeschränkung';
	@override String get kindWeight => 'Gewichtsbeschränkung';
	@override String get kindLimit => 'Andere Beschränkung (Breite, Länge, Verbot)';
	@override String get kindFuel => 'Tankstelle';
	@override String get kindPlace => 'Platz nahe der Route';
	@override String get groupLegend => 'Nahe beieinanderliegende Markierungen, zusammengefasst';
	@override String get zoneLegend => 'Gefahrenzone';
	@override String zonesFrom({required Object source, required Object date}) => 'Gefahrenzonen: ${source}, Liste vom ${date}';
	@override String group({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Markierung',
		other: '${n} Markierungen',
	);
	@override String get groupHint => 'Heranzoomen, um sie einzeln zu sehen';
	@override String count({required Object kind, required Object n}) => '${kind}: ${n}';
	@override String stop({required Object n}) => 'Zwischenstopp ${n}';
	@override String get origin => 'Startpunkt';
	@override String get nearRoute => 'Nahe der Route';
	@override String get avoided => 'Die Route führt daran vorbei';
	@override String get blocking => 'Blockiert jede Route';
	@override String get showInList => 'In der Liste ansehen';
	@override String get showAll => 'Alle anzeigen';
	@override String get onMap => 'auf der Karte zeigen';
	@override String price({required Object price}) => '${price} €';
	@override String get kindCamera => 'Blitzer';
	@override String cameras({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Blitzer',
		other: '${n} Blitzer',
	);
	@override String camerasFrom({required Object source, required Object date}) => 'Blitzer: ${source}, Liste vom ${date}';
	@override String bothFrom({required Object source, required Object date}) => 'Blitzer und Gefahrenzonen: ${source}, Liste vom ${date}';
	@override String sectionLength({required Object distance}) => 'Abschnitt von ${distance}';
	@override String get cameraDirection => 'Misst in Ihrer Fahrtrichtung';
}

// Path: navigation.guidance
class _Translations$navigation$guidance$de extends Translations$navigation$guidance$en {
	_Translations$navigation$guidance$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get then => 'Dann';
	@override String arrival({required Object time}) => 'Ankunft ${time}';
	@override String get offRoute => 'Abseits der Route';
	@override String get rerouting => 'Neue Route wird gesucht';
	@override String get rerouted => 'Neue Route';
	@override String reroutedLonger({required Object minutes}) => 'Neue Route, ${minutes} Min. länger';
	@override String get rerouteOffline => 'Kein Netz für eine neue Route: Kehren Sie zur Route zurück';
	@override String get rerouteFailed => 'Keine neue Route gefunden: Kehren Sie zur Route zurück';
	@override String closureAhead({required Object distance}) => 'Straßensperrung in ${distance}: Eine andere Strecke wird gesucht';
	@override String noDetour({required Object distance}) => 'Straßensperrung in ${distance}: keine andere Strecke';
	@override String eventAhead({required Object distance}) => 'Baustelle in ${distance}';
	@override String eventClosure({required Object distance}) => 'Straßensperrung in ${distance}';
	@override String eventLimit({required Object distance}) => 'Durchfahrtsbeschränkung wegen Baustelle in ${distance}';
	@override String eventSource({required Object source, required Object time}) => '${source}, Stand ${time}';
	@override String eventSourceOn({required Object source, required Object day, required Object time}) => '${source}, Stand ${day}, ${time}';
	@override String avoidedClosures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: 'Route um eine Sperrung herum geplant',
		other: 'Route um ${n} Sperrungen herum geplant',
	);
	@override String roadEventAhead({required Object what, required Object distance}) => '${what} in ${distance}';
	@override String closureOffline({required Object distance}) => 'Straßensperrung in ${distance}: keine Verbindung, um eine andere Strecke zu suchen';
	@override String closureFailed({required Object distance}) => 'Straßensperrung in ${distance}: noch keine andere Strecke';
	@override late final _Translations$navigation$guidance$voiceMode$de voiceMode = _Translations$navigation$guidance$voiceMode$de._(_root);
	@override String get overview => 'Ganze Route';
	@override String get recenter => 'Zentrieren';
	@override String get end => 'Navigation beenden';
	@override String get endKeep => 'Weiterfahren';
	@override String get stopTitle => 'Navigation beenden?';
	@override String get stopConfirm => 'Beenden';
	@override String get arrivedTitle => 'Sie sind angekommen';
	@override String get done => 'Fertig';
	@override String get speed => 'Geschwindigkeit';
	@override String get limit => 'Tempolimit';
	@override String noVoice({required Object language}) => 'Keine Stimme für ${language} auf diesem Gerät: Anweisungen nur auf dem Bildschirm.';
	@override String missingVoice({required Object language}) => 'Die Stimme für ${language} ist noch nicht heruntergeladen.';
	@override String get installVoice => 'Installieren';
	@override String get voiceSettingsIos => 'Einstellungen, Bedienungshilfen, Gesprochene Inhalte, Stimmen';
	@override String get notificationTitle => 'Navigation mit Lunaway aktiv';
	@override String get notificationText => 'Die Navigation läuft auch bei ausgeschaltetem Bildschirm weiter.';
	@override String get notificationChannel => 'Navigation';
	@override String get unavailable => 'Die Navigation konnte auf diesem Gerät nicht starten.';
	@override late final _Translations$navigation$guidance$notificationWhy$de notificationWhy = _Translations$navigation$guidance$notificationWhy$de._(_root);
	@override String get positionLost => 'Standort nicht verfügbar: Prüfen Sie, ob die Ortung des Geräts für Lunaway eingeschaltet ist.';
	@override String positionStale({required Object minutes}) => 'Letzter Standort vor ${minutes} Min. empfangen: Die Ankunftszeit beruht darauf.';
	@override String get limitEstimated => 'Geschätztes Tempolimit';
	@override String get overLimit => 'über dem Tempolimit';
	@override String enforcementSource({required Object source, required Object date}) => '${source}, Liste vom ${date}';
	@override String get demoDrive => 'Simulierte Fahrt: Vorführung ohne GPS';
	@override late final _Translations$navigation$guidance$places$de places = _Translations$navigation$guidance$places$de._(_root);
}

// Path: navigation.voice
class _Translations$navigation$voice$de extends Translations$navigation$voice$en {
	_Translations$navigation$voice$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get rerouting => 'Route wird neu berechnet.';
	@override String get rerouted => 'Neue Route.';
	@override String reroutedLonger({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(minutes,
		one: 'Neue Route, eine Minute länger.',
		other: 'Neue Route, ${minutes} Minuten länger.',
	);
	@override late final _Translations$navigation$voice$moved$de moved = _Translations$navigation$voice$moved$de._(_root);
	@override String closureAhead({required Object distance}) => 'In ${distance} ist die Straße gesperrt. Eine andere Strecke wird gesucht.';
	@override String noDetour({required Object distance}) => 'In ${distance} ist die Straße gesperrt. Es gibt keine Umfahrung.';
	@override String clearance({required Object distance, required Object height}) => 'Achtung, in ${distance} niedrige Durchfahrt, ${height} hoch.';
	@override String unknownClearance({required Object distance}) => 'Achtung, in ${distance} niedrige Durchfahrt, Höhe unbekannt.';
	@override String narrow({required Object distance, required Object width}) => 'Achtung, in ${distance} Engstelle, ${width} breit.';
	@override String limit({required Object distance, required Object what}) => 'Achtung, in ${distance} ${what}.';
	@override String get arrived => 'Ziel erreicht.';
	@override String metres({required Object n}) => '${n} Metern';
	@override String kilometres({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count,
		one: 'einem Kilometer',
		other: '${n} Kilometern',
	);
	@override String feet({required Object n}) => '${n} Fuß';
	@override String miles({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count,
		one: 'einer Meile',
		other: '${n} Meilen',
	);
	@override String size({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count,
		one: '${metres} Meter ${cm}',
		other: '${metres} Meter ${cm}',
	);
	@override String sizeWhole({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count,
		one: '${metres} Meter',
		other: '${metres} Meter',
	);
	@override String overSpeed({required Object limit}) => 'Tempolimit ${limit}.';
	@override String dangerZone({required Object distance}) => 'In ${distance} Gefahrenzone.';
	@override String get inDangerZone => 'Gefahrenzone.';
	@override late final _Translations$navigation$voice$localAccess$de localAccess = _Translations$navigation$voice$localAccess$de._(_root);
	@override late final _Translations$navigation$voice$roadEvent$de roadEvent = _Translations$navigation$voice$roadEvent$de._(_root);
	@override String get positionLost => 'Standort nicht verfügbar. Ortung des Geräts prüfen.';
	@override String tonnes({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count,
		one: '${n} Tonne',
		other: '${n} Tonnen',
	);
	@override late final _Translations$navigation$voice$camera$de camera = _Translations$navigation$voice$camera$de._(_root);
}

// Path: navigation.units
class _Translations$navigation$units$de extends Translations$navigation$units$en {
	_Translations$navigation$units$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String ft({required Object n}) => '${n} ft';
	@override String mi({required Object n}) => '${n} mi';
	@override String get kmh => 'km/h';
	@override String get mph => 'mph';
	@override String hoursMinutes({required Object h, required Object m}) => '${h}:${m} Std.';
	@override String minutes({required Object m}) => '${m} Min.';
}

// Path: navigation.settings
class _Translations$navigation$settings$de extends Translations$navigation$settings$en {
	_Translations$navigation$settings$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Navigation';
	@override String get avoidTitle => 'Standardmäßig vermeiden';
	@override String get voice => 'Sprachansagen';
	@override String get voiceFull => 'Alle';
	@override String get voiceAlerts => 'Warnungen';
	@override String get voiceMuted => 'Aus';
	@override String get voiceFullHint => 'Abbiegehinweise und Warnungen, mit der Stimme des Geräts.';
	@override String get voiceAlertsHint => 'Nur Blitzer und Gefahrenzonen, Sperrungen, Baustellen und Durchfahrtsbeschränkungen auf der Strecke sowie Routenänderungen, nach einem kurzen Signalton.';
	@override String get voiceMutedHint => 'Kein Ton: Abbiegehinweise und Warnungen nur auf dem Bildschirm.';
	@override String get units => 'Entfernungen';
	@override String get metric => 'Kilometer';
	@override String get imperial => 'Meilen';
	@override String get speedLimit => 'Tempolimit';
	@override String get speedLimitHint => 'Zeigt während der Navigation das Tempolimit für Ihr Fahrzeug neben Ihrer Geschwindigkeit. Geschätzte Werte erscheinen grau.';
	@override String get speedSound => 'Gesprochener Tempolimit-Hinweis';
	@override String get speedSoundHint => 'Ein kurzer Hinweis, wenn Sie das Tempolimit überschreiten, bei allen Sprachansagen. Blitzer und Gefahrenzonen folgen den Sprachansagen.';
	@override String get exactFrance => 'Genaue Blitzerstandorte in Frankreich';
	@override String get exactFranceHint => 'In Frankreich wird der Besitz eines Geräts, das die Position von Blitzern meldet, mit 1.500 € Bußgeld und 6 Punkten bestraft (Code de la route, Art. R413-15).';
}

// Path: navigation.enforcement
class _Translations$navigation$enforcement$de extends Translations$navigation$enforcement$en {
	_Translations$navigation$enforcement$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get fixed => 'Fester Blitzer';
	@override String get redLight => 'Rotlichtblitzer';
	@override String get levelCrossing => 'Blitzer am Bahnübergang';
	@override String get section => 'Abschnittskontrolle';
	@override String get zone => 'Gefahrenzone';
	@override String average({required Object limit}) => 'Schnitt ${limit}';
	@override String get averageLabel => 'Schnitt';
	@override String remaining({required Object distance}) => 'noch ${distance}';
	@override String yourAverage({required Object speed}) => 'Ihr Schnitt ${speed}';
	@override String get zoneEnd => 'Ende der Gefahrenzone';
	@override String get sectionEnd => 'Ende der Abschnittskontrolle';
	@override String ruleOff({required Object country}) => '${country}: keine Blitzerwarnungen';
	@override String ruleZones({required Object country}) => '${country}: Gefahrenzonen';
	@override String ruleExact({required Object country}) => '${country}: Blitzer';
	@override String ahead({required Object what, required Object distance}) => '${what} in ${distance}';
	@override String limit({required Object limit}) => 'Tempolimit ${limit}';
	@override String averageLimit({required Object limit}) => 'Schnitt höchstens ${limit}';
	@override String get listSecuriteRoutiere => 'Sécurité routière';
	@override String get listDsr => 'Délégation à la sécurité routière';
	@override String get listGitd => 'GITD';
	@override String get listPontsEtChaussees => 'Ponts et chaussées';
	@override String get listBrusselsMobility => 'Bruxelles Mobilité';
	@override String get listStatensVegvesen => 'Statens vegvesen';
	@override String get listGarda => 'An Garda Síochána';
	@override String get listOsm => 'OpenStreetMap';
}

// Path: favorites.pointKind
class _Translations$favorites$pointKind$de extends Translations$favorites$pointKind$en {
	_Translations$favorites$pointKind$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get address => 'Adresse';
	@override String get town => 'Gemeinde';
	@override String get point => 'Punkt auf der Karte';
	@override String get poi => 'Geschäft oder Dienstleistung';
}

// Path: vehicle.types
class _Translations$vehicle$types$de extends Translations$vehicle$types$en {
	_Translations$vehicle$types$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Kastenwagen';
	@override String get lowProfile => 'Teilintegriert';
	@override String get overcab => 'Alkoven';
	@override String get integrated => 'Vollintegriert';
}

// Path: vehicle.towing
class _Translations$vehicle$towing$de extends Translations$vehicle$towing$en {
	_Translations$vehicle$towing$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get none => 'Nichts';
	@override String get car => 'Ein Auto';
	@override String get trailer => 'Ein Anhänger';
}

// Path: translation.from
class _Translations$translation$from$de extends Translations$translation$from$en {
	_Translations$translation$from$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Automatisch aus dem Französischen übersetzt';
	@override String get en => 'Automatisch aus dem Englischen übersetzt';
	@override String get de => 'Automatisch aus dem Deutschen übersetzt';
	@override String get es => 'Automatisch aus dem Spanischen übersetzt';
	@override String get it => 'Automatisch aus dem Italienischen übersetzt';
	@override String get nl => 'Automatisch aus dem Niederländischen übersetzt';
	@override String unknown({required Object language}) => 'Automatisch übersetzt (Originalsprache: ${language})';
}

// Path: account.levelOpens
class _Translations$account$levelOpens$de extends Translations$account$levelOpens$en {
	_Translations$account$levelOpens$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get l0 => 'Sie können Plätze bewerten, bestätigen, dass es sie noch gibt, ein Problem melden und Ihre Favoriten synchronisieren.';
	@override String get l1 => 'Sie können außerdem Rezensionen schreiben, Fotos hinzufügen und Änderungen an Plätzen vorschlagen.';
	@override String get l2 => 'Sie können außerdem Plätze hinzufügen.';
	@override String get l3 => 'Ihre Änderungen an Plätzen gelten ohne Prüfung.';
	@override String get l4 => 'Sie wirken an der Moderation mit.';
}

// Path: account.requirement
class _Translations$account$requirement$de extends Translations$account$requirement$en {
	_Translations$account$requirement$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String age({required Object needed, required Object current}) => 'Ein Konto, das mindestens ${needed} Tage alt ist (bisher ${current})';
	@override String confirmations({required Object needed, required Object current}) => '${needed} Bestätigungen verschiedener Plätze (bisher ${current})';
	@override String contributions({required Object needed, required Object current}) => '${needed} veröffentlichte Beiträge (bisher ${current})';
	@override String activeDays({required Object needed, required Object current}) => '${needed} aktive Tage (bisher ${current})';
	@override String get noRemoval => 'Kein Beitrag von der Moderation entfernt';
	@override String get sponsor => 'Eine Empfehlung durch ein Mitglied der Stufe 2';
	@override String get nomination => 'Eine Ernennung durch die Moderation';
	@override String get administration => 'Eine Ernennung durch das Lunaway-Team';
}

// Path: deletion.gone
class _Translations$deletion$gone$de extends Translations$deletion$gone$en {
	_Translations$deletion$gone$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get identity => 'Ihr Pseudonym und die Schlüssel Ihrer Geräte';
	@override String get sessions => 'Ihre Sitzungen und Ihr Sicherungscode';
	@override String get lists => 'Ihre synchronisierten Favoritenlisten und Ihre ausgeblendeten Autoren';
	@override String get photos => 'Ihre Fotos, Ihre Bewertungen ohne Text und Ihre Meldungen';
	@override String get pending => 'Ihre Vorschläge, die noch auf Prüfung warten';
}

// Path: mine.status
class _Translations$mine$status$de extends Translations$mine$status$en {
	_Translations$mine$status$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get published => 'Veröffentlicht';
	@override String get pending => 'In Prüfung';
	@override String get hidden => 'Nach Meldungen ausgeblendet';
	@override String get removed => 'Von der Moderation entfernt';
}

// Path: mine.submission
class _Translations$mine$submission$de extends Translations$mine$submission$en {
	_Translations$mine$submission$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get proposed => 'Wartet auf Prüfung';
	@override String get accepted => 'Angenommen';
	@override String get applied => 'Auf der Karte';
	@override String get rejected => 'Abgelehnt';
	@override String get withdrawn => 'Zurückgezogen';
}

// Path: outbox.kind
class _Translations$outbox$kind$de extends Translations$outbox$kind$en {
	_Translations$outbox$kind$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String rate({required Object stars}) => 'Bewertung: ${stars} von 5 Sternen';
	@override String get review => 'Rezension';
	@override String get deleteReview => 'Löschen einer Rezension';
	@override String confirm({required Object status}) => 'Noch da? ${status}';
	@override String get deleteConfirmation => 'Löschen einer Bestätigung';
	@override String reportIssue({required Object kind}) => 'Gemeldetes Problem: ${kind}';
	@override String get deleteIssueReport => 'Löschen einer Meldung';
	@override String get reportContent => 'Meldung an die Moderation';
	@override String addPlace({required Object name}) => 'Neuer Platz: ${name}';
	@override String get editPlace => 'Änderung an einem Platz';
	@override String get deletePlaceSubmission => 'Zurückziehen eines vorgeschlagenen Platzes';
	@override String get photo => 'Foto';
	@override String get deletePhoto => 'Löschen eines Fotos';
	@override String get mute => 'Autor ausblenden';
	@override String get unmute => 'Autor wieder anzeigen';
	@override String get poiThere => 'Noch da: ein Geschäft oder eine Dienstleistung';
	@override String get poiGone => 'Nicht mehr da: ein Geschäft oder eine Dienstleistung';
	@override String get addVendingMachine => 'Neuer Automat';
	@override String get deletePoiConfirmation => 'Löschen einer Antwort zu einem Geschäft oder einer Dienstleistung';
	@override String reportRoadEvent({required Object kind}) => 'Straßenmeldung: ${kind}';
	@override String get clearRoadEvent => 'Ende einer Straßenmeldung';
}

// Path: outbox.error
class _Translations$outbox$error$de extends Translations$outbox$error$en {
	_Translations$outbox$error$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get forbidden => 'Abgelehnt: Ihre Stufe erlaubt das noch nicht.';
	@override String get notFound => 'Abgelehnt: Der Platz oder der Inhalt existiert nicht mehr.';
	@override String get invalid => 'Abgelehnt: Prüfen Sie den Text (Länge, Links, Kontaktdaten).';
	@override String get unreadablePhoto => 'Foto abgelehnt: unlesbar oder schon gesendet.';
	@override String get photoTooLarge => 'Foto abgelehnt: zu groß.';
	@override String get placeRefused => 'Der neue Platz zu diesem Foto wurde abgelehnt.';
	@override String get fileLost => 'Das Foto ist nicht mehr auf dem Gerät.';
	@override String get otherAccount => 'Für ein anderes Konto vorbereitet: wird nicht gesendet.';
	@override String get other => 'Vom Server abgelehnt.';
	@override String get duplicate => 'Abgelehnt: Derselbe Automat ist schon im Umkreis von 25 m eingetragen.';
}

// Path: confirmSheet.status
class _Translations$confirmSheet$status$de extends Translations$confirmSheet$status$en {
	_Translations$confirmSheet$status$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get stillOk => 'Noch da';
	@override String get closed => 'Geschlossen';
	@override String get changed => 'Verändert';
}

// Path: issueSheet.kind
class _Translations$issueSheet$kind$de extends Translations$issueSheet$kind$en {
	_Translations$issueSheet$kind$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Übernachten jetzt verboten';
	@override String get serviceBroken => 'Ausstattung defekt';
	@override String get noAccess => 'Keine Zufahrt';
	@override String get danger => 'Gefahr';
}

// Path: issueSheet.hint
class _Translations$issueSheet$hint$de extends Translations$issueSheet$hint$en {
	_Translations$issueSheet$hint$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Ein Schild, eine Gemeindeverordnung, eine Polizeikontrolle';
	@override String get serviceBroken => 'V/E-Säule, Wasser, Entsorgung oder Strom außer Betrieb';
	@override String get noAccess => 'Eine Schranke, eine Baustelle, eine gesperrte Straße';
	@override String get danger => 'Diebstahl, Überfall, instabiler Untergrund';
}

// Path: reportSheet.reason
class _Translations$reportSheet$reason$de extends Translations$reportSheet$reason$en {
	_Translations$reportSheet$reason$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get spam => 'Werbung oder Spam';
	@override String get offensive => 'Beleidigend, hasserfüllt oder anstößig';
	@override String get wrong => 'Falsch oder irreführend';
	@override String get privacy => 'Zeigt oder nennt eine Person, ein Kennzeichen, eine Privatadresse';
	@override String get other => 'Anderer Grund';
}

// Path: poi.category
class _Translations$poi$category$de extends Translations$poi$category$en {
	_Translations$poi$category$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get groceries => 'Einkaufen';
	@override String get vending => 'Lebensmittelautomaten';
	@override String get water => 'Wasser und Entsorgung';
	@override String get fuel => 'Kraftstoff und Energie';
	@override String get health => 'Gesundheit';
	@override String get services => 'Dienstleistungen';
	@override String get food => 'Restaurants und Cafés';
	@override String get sights => 'Sehenswertes';
	@override String get shopping => 'Geschäfte';
	@override String get lodging => 'Unterkünfte';
	@override String get leisure => 'Freizeit';
}

// Path: poi.kind
class _Translations$poi$kind$de extends Translations$poi$kind$en {
	_Translations$poi$kind$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get supermarket => 'Supermarkt';
	@override String get convenience => 'Lebensmittelladen';
	@override String get bakery => 'Bäckerei';
	@override String get butcher => 'Metzgerei';
	@override String get greengrocer => 'Obst und Gemüse';
	@override String get farmShop => 'Hofladen';
	@override String get marketplace => 'Markt';
	@override String get vendingPizza => 'Pizzaautomat';
	@override String get vendingBread => 'Brotautomat';
	@override String get vendingFarmProducts => 'Automat mit Hofprodukten';
	@override String get vendingEggsMilk => 'Eier- oder Milchautomat';
	@override String get vendingIce => 'Eiswürfelautomat';
	@override String get vendingOther => 'Lebensmittelautomat';
	@override String get drinkingWater => 'Trinkwasser';
	@override String get waterPoint => 'Wasserstelle';
	@override String get dumpStation => 'Entsorgungsstation';
	@override String get toilets => 'Toiletten';
	@override String get shower => 'Duschen';
	@override String get fuelStation => 'Tankstelle';
	@override String get evCharging => 'Ladestation';
	@override String get gasBottles => 'Gasflaschen';
	@override String get pharmacy => 'Apotheke';
	@override String get doctor => 'Arzt';
	@override String get hospital => 'Krankenhaus';
	@override String get veterinary => 'Tierarzt';
	@override String get laundry => 'Waschsalon';
	@override String get atm => 'Geldautomat';
	@override String get postOffice => 'Postfiliale';
	@override String get touristOffice => 'Touristeninformation';
	@override String get recyclingCentre => 'Wertstoffhof';
	@override String get carRepair => 'Autowerkstatt';
	@override String get carWash => 'Waschanlage';
	@override String get motorhomeShop => 'Wohnmobilhändler und Werkstatt';
	@override String get outdoorShop => 'Camping- und Outdoorladen';
	@override String get restaurant => 'Restaurant';
	@override String get cafe => 'Café';
	@override String get fastFood => 'Imbiss';
	@override String get viewpoint => 'Aussichtspunkt';
	@override String get attraction => 'Sehenswürdigkeit';
	@override String get museum => 'Museum';
	@override String get bar => 'Bar';
	@override String get pub => 'Kneipe';
	@override String get iceCream => 'Eisdiele';
	@override String get deli => 'Feinkost';
	@override String get cheese => 'Käseladen';
	@override String get seafood => 'Fischgeschäft';
	@override String get pastry => 'Konditorei';
	@override String get confectionery => 'Süßwaren';
	@override String get wineShop => 'Weinhandlung';
	@override String get beverages => 'Getränkemarkt';
	@override String get teaCoffee => 'Tee und Kaffee';
	@override String get organicShop => 'Bioladen';
	@override String get frozenFood => 'Tiefkühlkost';
	@override String get winery => 'Weingut';
	@override String get brewery => 'Brauerei';
	@override String get distillery => 'Brennerei';
	@override String get beekeeper => 'Imkerei';
	@override String get dentist => 'Zahnarzt';
	@override String get clinic => 'Klinik';
	@override String get physiotherapist => 'Physiotherapie';
	@override String get laboratory => 'Labor';
	@override String get nurse => 'Pflegedienst';
	@override String get midwife => 'Hebamme';
	@override String get podiatrist => 'Podologie';
	@override String get psychologist => 'Psychotherapie';
	@override String get speechTherapist => 'Logopädie';
	@override String get alternativeMedicine => 'Osteopathie, Naturheilkunde';
	@override String get optician => 'Optiker';
	@override String get hearingAids => 'Hörakustik';
	@override String get medicalSupply => 'Sanitätshaus';
	@override String get hairdresser => 'Friseur';
	@override String get beauty => 'Kosmetikstudio';
	@override String get massage => 'Massage';
	@override String get tattoo => 'Tattoostudio';
	@override String get bank => 'Bank';
	@override String get moneyExchange => 'Wechselstube';
	@override String get carRental => 'Autovermietung';
	@override String get bicycleRental => 'Fahrradverleih';
	@override String get boatRental => 'Bootsverleih';
	@override String get vehicleInspection => 'TÜV, Prüfstelle';
	@override String get drivingSchool => 'Fahrschule';
	@override String get dryCleaning => 'Reinigung';
	@override String get tailor => 'Schneiderei';
	@override String get shoeRepair => 'Schuhmacher';
	@override String get locksmith => 'Schlüsseldienst';
	@override String get copyshop => 'Copyshop';
	@override String get photographer => 'Fotograf';
	@override String get travelAgency => 'Reisebüro';
	@override String get estateAgent => 'Immobilienmakler';
	@override String get insurance => 'Versicherung';
	@override String get funeralDirectors => 'Bestattungen';
	@override String get petGrooming => 'Hundesalon';
	@override String get tyres => 'Reifenhandel';
	@override String get carParts => 'Autoteile';
	@override String get carDealer => 'Autohaus';
	@override String get motorcycleShop => 'Motorradhändler';
	@override String get repairShop => 'Reparaturdienst';
	@override String get internetCafe => 'Internetcafé';
	@override String get coworking => 'Coworking-Space';
	@override String get townhall => 'Rathaus';
	@override String get police => 'Polizei';
	@override String get library => 'Bibliothek';
	@override String get rental => 'Verleih';
	@override String get storageRental => 'Lagerraum';
	@override String get animalBoarding => 'Tierpension';
	@override String get ferryTerminal => 'Fähranleger';
	@override String get clothes => 'Bekleidung';
	@override String get shoes => 'Schuhe';
	@override String get accessories => 'Lederwaren, Accessoires';
	@override String get jewellery => 'Schmuck';
	@override String get books => 'Buchhandlung';
	@override String get newsagent => 'Zeitschriften, Kiosk';
	@override String get tobacco => 'Tabakwaren';
	@override String get stationery => 'Schreibwaren';
	@override String get gift => 'Geschenke, Souvenirs';
	@override String get toys => 'Spielwaren';
	@override String get sports => 'Sportgeschäft';
	@override String get fishingHunting => 'Angeln und Jagd';
	@override String get bicycleShop => 'Fahrradladen';
	@override String get boatShop => 'Bootshandel';
	@override String get florist => 'Blumenladen';
	@override String get gardenCentre => 'Gartencenter';
	@override String get hardware => 'Baumarkt';
	@override String get home => 'Einrichtung, Möbel';
	@override String get electronics => 'Elektronik, Handys';
	@override String get cosmetics => 'Drogerie, Parfümerie';
	@override String get departmentStore => 'Kaufhaus, Einkaufszentrum';
	@override String get varietyStore => 'Sonderpostenmarkt';
	@override String get secondHand => 'Second Hand, Antiquitäten';
	@override String get artShop => 'Kunst und Basteln';
	@override String get musicShop => 'Musikgeschäft';
	@override String get petShop => 'Zoohandlung';
	@override String get babyGoods => 'Babyausstattung';
	@override String get fabric => 'Stoffe, Kurzwaren';
	@override String get craft => 'Handwerk';
	@override String get shop => 'Geschäft';
	@override String get hotel => 'Hotel';
	@override String get guestHouse => 'Pension';
	@override String get hostel => 'Hostel';
	@override String get holidayRental => 'Ferienwohnung';
	@override String get mountainHut => 'Berghütte';
	@override String get cinema => 'Kino';
	@override String get theatre => 'Theater';
	@override String get eventsVenue => 'Veranstaltungsort';
	@override String get artsCentre => 'Kulturzentrum';
	@override String get nightclub => 'Diskothek';
	@override String get casino => 'Spielbank';
	@override String get sportsCentre => 'Sportzentrum';
	@override String get fitnessCentre => 'Fitnessstudio';
	@override String get swimmingPool => 'Schwimmbad';
	@override String get waterPark => 'Erlebnisbad';
	@override String get golfCourse => 'Golfplatz';
	@override String get miniatureGolf => 'Minigolf';
	@override String get marina => 'Jachthafen';
	@override String get horseRiding => 'Reitstall';
	@override String get bowlingAlley => 'Bowling';
	@override String get escapeGame => 'Escape Room';
	@override String get amusementArcade => 'Spielhalle';
	@override String get iceRink => 'Eisbahn';
	@override String get spa => 'Sauna, Therme';
	@override String get dance => 'Tanzschule';
	@override String get park => 'Park';
	@override String get natureReserve => 'Naturschutzgebiet';
	@override String get gallery => 'Galerie';
	@override String get zoo => 'Zoo, Aquarium';
	@override String get themePark => 'Freizeitpark';
}

// Path: poi.vendingSells
class _Translations$poi$vendingSells$de extends Translations$poi$vendingSells$en {
	_Translations$poi$vendingSells$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Brot';
	@override String get farmProducts => 'Hofprodukte';
	@override String get eggsMilk => 'Eier und Milch';
	@override String get ice => 'Eiswürfel';
}

// Path: poi.vendingChip
class _Translations$poi$vendingChip$de extends Translations$poi$vendingChip$en {
	_Translations$poi$vendingChip$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizzaautomaten';
	@override String get bread => 'Brotautomaten';
	@override String get farmProducts => 'Automaten mit Hofprodukten';
	@override String get eggsMilk => 'Eier- und Milchautomaten';
	@override String get ice => 'Eiswürfelautomaten';
}

// Path: poi.fuel
class _Translations$poi$fuel$de extends Translations$poi$fuel$en {
	_Translations$poi$fuel$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get diesel => 'Diesel';
	@override String get sp95 => 'Super 95';
	@override String get e10 => 'Super E10';
	@override String get sp98 => 'Super Plus 98';
	@override String get e85 => 'E85';
	@override String get lpg => 'Autogas (LPG)';
}

// Path: poi.product
class _Translations$poi$product$de extends Translations$poi$product$en {
	_Translations$poi$product$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Brot';
	@override String get eggs => 'Eier';
	@override String get milk => 'Milch';
	@override String get cheese => 'Käse';
	@override String get meat => 'Fleisch';
	@override String get vegetables => 'Gemüse';
	@override String get fruit => 'Obst';
	@override String get honey => 'Honig';
	@override String get ice => 'Eiswürfel';
	@override String get potatoes => 'Kartoffeln';
	@override String get food => 'Lebensmittel';
}

// Path: poi.payment
class _Translations$poi$payment$de extends Translations$poi$payment$en {
	_Translations$poi$payment$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get cash => 'Bargeld';
	@override String get coins => 'Münzen';
	@override String get notes => 'Scheine';
	@override String get cards => 'Karte';
	@override String get contactless => 'Kontaktlos';
	@override String get app => 'Handy-App';
}

// Path: poi.add
class _Translations$poi$add$de extends Translations$poi$add$en {
	_Translations$poi$add$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Hier ein Automat?';
	@override String get hint => 'Wählen Sie, was er verkauft: Er erscheint dann für alle Reisenden auf der Karte.';
	@override String get pizza => 'Pizza';
	@override String get bread => 'Brot';
	@override String get other => 'Andere Lebensmittel';
	@override String get gate => 'Automaten hinzufügen';
	@override String get sent => 'Danke: Der Automat erscheint in wenigen Minuten auf der Karte.';
	@override String get duplicateTitle => 'Schon auf der Karte';
	@override String get duplicateBody => 'Ein Automat derselben Art ist schon im Umkreis von 25 m eingetragen. Ist er noch da?';
	@override String get duplicateThere => 'Ja, noch da';
	@override String get duplicateGone => 'Nein, nicht mehr da';
}

// Path: poi.cheapest
class _Translations$poi$cheapest$de extends Translations$poi$cheapest$en {
	_Translations$poi$cheapest$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Am günstigsten in meiner Nähe';
	@override String get show => 'Günstigste Preise';
	@override String get zoomIn => 'Zoomen Sie heran, um die Preise der Tankstellen zu vergleichen.';
	@override String get none => 'Keine Tankstelle auf der Karte verkauft diesen Kraftstoff.';
	@override String get noneHint => 'Verschieben Sie die Karte oder wählen Sie einen anderen Kraftstoff.';
	@override String get error => 'Die Preise der Tankstellen konnten nicht geladen werden.';
}

// Path: poi.trend
class _Translations$poi$trend$de extends Translations$poi$trend$en {
	_Translations$poi$trend$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String title({required Object fuel}) => '${fuel}: Preise der letzten Tage';
	@override String get none => 'Lunaway hat hier noch keinen Preis für diesen Kraftstoff gesehen.';
	@override String get failed => 'Die Preise der letzten Tage konnten gerade nicht geladen werden.';
	@override String get week => 'Letzte 7 Tage:';
	@override String get month => 'Letzte 30 Tage:';
	@override String range({required Object low, required Object high}) => 'von ${low} bis ${high}';
	@override String span({required Object range, required Object move}) => '${range}, ${move}';
	@override String get oneDay => 'nur ein Tag erfasst';
	@override String get steady => 'unverändert';
	@override String down({required Object amount}) => 'um ${amount} gesunken';
	@override String up({required Object amount}) => 'um ${amount} gestiegen';
	@override String since({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Tag erfasst seit dem ${date} (laut Datenfeed); Tage ohne Erfassung bleiben leer',
		other: '${n} Tage erfasst seit dem ${date} (laut Datenfeed); Tage ohne Erfassung bleiben leer',
	);
}

// Path: poi.vehicles
class _Translations$poi$vehicles$de extends Translations$poi$vehicles$en {
	_Translations$poi$vehicles$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get motorhomeYes => 'Für Wohnmobile';
	@override String get motorhomeNo => 'Keine Wohnmobile';
	@override String get hgvYes => 'Für Lkw';
	@override String get hgvNo => 'Keine Lkw';
	@override String maxHeight({required Object height}) => 'Maximale Höhe: ${height}';
}

// Path: poi.cuisine
class _Translations$poi$cuisine$de extends Translations$poi$cuisine$en {
	_Translations$poi$cuisine$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get italian => 'Italienisch';
	@override String get french => 'Französisch';
	@override String get regional => 'Regional';
	@override String get local => 'Lokal';
	@override String get burger => 'Burger';
	@override String get kebab => 'Döner';
	@override String get chinese => 'Chinesisch';
	@override String get japanese => 'Japanisch';
	@override String get sushi => 'Sushi';
	@override String get asian => 'Asiatisch';
	@override String get indian => 'Indisch';
	@override String get thai => 'Thailändisch';
	@override String get vietnamese => 'Vietnamesisch';
	@override String get korean => 'Koreanisch';
	@override String get mexican => 'Mexikanisch';
	@override String get lebanese => 'Libanesisch';
	@override String get greek => 'Griechisch';
	@override String get turkish => 'Türkisch';
	@override String get moroccan => 'Marokkanisch';
	@override String get middleEastern => 'Orientalisch';
	@override String get arab => 'Arabisch';
	@override String get african => 'Afrikanisch';
	@override String get american => 'Amerikanisch';
	@override String get spanish => 'Spanisch';
	@override String get tapas => 'Tapas';
	@override String get portuguese => 'Portugiesisch';
	@override String get german => 'Deutsch';
	@override String get mediterranean => 'Mediterran';
	@override String get international => 'International';
	@override String get seafood => 'Meeresfrüchte';
	@override String get fish => 'Fisch';
	@override String get fishAndChips => 'Fish and Chips';
	@override String get steakHouse => 'Steakhaus';
	@override String get grill => 'Grill';
	@override String get barbecue => 'Barbecue';
	@override String get chicken => 'Hähnchen';
	@override String get crepe => 'Crêpes';
	@override String get pasta => 'Pasta';
	@override String get noodle => 'Nudeln';
	@override String get ramen => 'Ramen';
	@override String get couscous => 'Couscous';
	@override String get sandwich => 'Sandwiches';
	@override String get bagel => 'Bagels';
	@override String get hotDog => 'Hotdogs';
	@override String get friture => 'Pommes frites';
	@override String get salad => 'Salate';
	@override String get vegetarian => 'Vegetarisch';
	@override String get vegan => 'Vegan';
	@override String get breakfast => 'Frühstück';
	@override String get brunch => 'Brunch';
	@override String get coffeeShop => 'Kaffeebar';
	@override String get tea => 'Tee';
	@override String get bubbleTea => 'Bubble Tea';
	@override String get juice => 'Säfte';
	@override String get iceCream => 'Eis';
	@override String get cake => 'Kuchen';
	@override String get donut => 'Donuts';
	@override String get savoy => 'Savoyisch';
	@override String get swiss => 'Schweizerisch';
	@override String get belgian => 'Belgisch';
	@override String get austrian => 'Österreichisch';
	@override String get british => 'Britisch';
	@override String get dutch => 'Niederländisch';
}

// Path: poi.details
class _Translations$poi$details$de extends Translations$poi$details$en {
	_Translations$poi$details$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get cuisineTitle => 'Küche';
	@override String get dietsTitle => 'Ernährung';
	@override String get facilitiesTitle => 'Vor Ort';
	@override String get vehicleServicesTitle => 'Leistungen';
	@override String get takeaway => 'Zum Mitnehmen';
	@override String get noTakeaway => 'Nicht zum Mitnehmen';
	@override String get delivery => 'Lieferservice';
	@override String get noDelivery => 'Kein Lieferservice';
	@override String get outdoorSeating => 'Außenbereich';
	@override String get noOutdoorSeating => 'Kein Außenbereich';
	@override String get wifi => 'WLAN für Gäste';
	@override String get noWifi => 'Kein WLAN';
	@override String get emergency => 'Notaufnahme';
	@override String get noEmergency => 'Keine Notaufnahme';
	@override String get wheelchairYes => 'Rollstuhlgerecht';
	@override String get wheelchairLimited => 'Eingeschränkt rollstuhlgerecht';
	@override String get wheelchairNo => 'Nicht rollstuhlgerecht';
	@override String get googleMaps => 'Rezensionen auf Google Maps ansehen';
	@override String get googleMapsHint => 'Öffnet sich außerhalb von Lunaway, mit Name und Position dieses Ortes.';
	@override String get reviewsError => 'Die Rezensionen konnten nicht angezeigt werden.';
	@override String photoOf({required Object name}) => 'Foto von ${name}';
	@override String stars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n,
		one: '${n} Stern',
		other: '${n} Sterne',
	);
	@override String get reviewsOffline => 'Rezensionen brauchen eine Verbindung.';
}

// Path: poi.diet
class _Translations$poi$diet$de extends Translations$poi$diet$en {
	_Translations$poi$diet$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get vegetarian => 'Vegetarisch';
	@override String get vegan => 'Vegan';
	@override String get glutenFree => 'Glutenfrei';
	@override String get halal => 'Halal';
	@override String get kosher => 'Koscher';
	@override String get lactoseFree => 'Laktosefrei';
}

// Path: poi.reservation
class _Translations$poi$reservation$de extends Translations$poi$reservation$en {
	_Translations$poi$reservation$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get yes => 'Reservierung möglich';
	@override String get no => 'Keine Reservierung';
	@override String get required => 'Reservierung erforderlich';
	@override String get recommended => 'Reservierung empfohlen';
	@override String get only => 'Nur mit Reservierung';
}

// Path: poi.vehicleService
class _Translations$poi$vehicleService$de extends Translations$poi$vehicleService$en {
	_Translations$poi$vehicleService$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get tyres => 'Reifen';
	@override String get brakes => 'Bremsen';
	@override String get oilChange => 'Ölwechsel';
	@override String get glass => 'Autoglas';
	@override String get airConditioning => 'Klimaanlage';
	@override String get bodyRepair => 'Karosserie';
	@override String get painting => 'Lackierung';
	@override String get electrical => 'Elektrik';
	@override String get diagnostics => 'Diagnose';
	@override String get batteries => 'Batterien';
	@override String get engine => 'Motor';
	@override String get exhaust => 'Auspuff';
	@override String get clutch => 'Kupplung';
	@override String get transmission => 'Getriebe';
	@override String get suspension => 'Fahrwerk';
	@override String get carParts => 'Ersatzteile';
	@override String get newCarSales => 'Neuwagen';
	@override String get usedCarSales => 'Gebrauchtwagen';
}

// Path: roadReport.kinds
class _Translations$roadReport$kinds$de extends Translations$roadReport$kinds$en {
	_Translations$roadReport$kinds$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get closure => 'Straße gesperrt';
	@override String get works => 'Baustelle';
	@override String get narrowPassage => 'Engstelle';
	@override String get lowClearance => 'Höhenbeschränkung';
	@override String get other => 'Problem auf der Straße';
}

// Path: navigation.preview.departure
class _Translations$navigation$preview$departure$de extends Translations$navigation$preview$departure$en {
	_Translations$navigation$preview$departure$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Start';
	@override String from({required Object name}) => 'Start: ${name}';
	@override String get myPosition => 'mein Standort';
	@override String get myPositionChoice => 'Mein Standort';
	@override String get change => 'Ändern';
	@override String get choose => 'Start wählen';
	@override String get searchHint => 'Platz, Ort oder Adresse';
	@override String get guidanceFromPosition => 'Die Navigation beginnt an Ihrem Standort, nicht an einem gewählten Start.';
	@override String get fromMyPosition => 'Von meinem Standort starten';
}

// Path: navigation.preview.moved
class _Translations$navigation$preview$moved$de extends Translations$navigation$preview$moved$en {
	_Translations$navigation$preview$moved$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String origin({required Object distance}) => 'Start um ${distance} an die nächste für Ihr Fahrzeug erreichbare Straße verlegt';
	@override String destination({required Object distance}) => 'Ziel um ${distance} an die nächste für Ihr Fahrzeug erreichbare Straße verlegt';
	@override String stop({required Object n, required Object distance}) => 'Zwischenstopp ${n} um ${distance} an die nächste für Ihr Fahrzeug erreichbare Straße verlegt';
}

// Path: navigation.onTheWay.categories
class _Translations$navigation$onTheWay$categories$de extends Translations$navigation$onTheWay$categories$en {
	_Translations$navigation$onTheWay$categories$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get fuel => 'Tanken';
	@override String get sleep => 'Übernachten';
	@override String get water => 'Wasser und Entsorgung';
	@override String get groceries => 'Einkaufen';
	@override String get bakeries => 'Bäckereien';
	@override String get toilets => 'WC, Duschen';
	@override String get health => 'Gesundheit';
	@override String get services => 'Dienstleistungen';
	@override String get charging => 'Ladestationen';
	@override String get garages => 'Werkstätten und Zubehör';
}

// Path: navigation.states.dimension
class _Translations$navigation$states$dimension$de extends Translations$navigation$states$dimension$en {
	_Translations$navigation$states$dimension$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get height => 'Höhe';
	@override String get width => 'Breite';
	@override String get length => 'Länge';
	@override String get weight => 'Gewicht';
}

// Path: navigation.noRoute.limit
class _Translations$navigation$noRoute$limit$de extends Translations$navigation$noRoute$limit$en {
	_Translations$navigation$noRoute$limit$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'niedrige Brücke mit ${limit}';
	@override String tunnel({required Object limit}) => 'Tunnel mit ${limit}';
	@override String buildingPassage({required Object limit}) => 'Tordurchfahrt mit ${limit}';
	@override String bridge({required Object limit}) => 'Brücke mit ${limit}';
	@override String barrier({required Object limit}) => 'Höhenbegrenzung auf ${limit}';
	@override String height({required Object limit}) => 'Höhenbeschränkung auf ${limit}';
	@override String get heightUnknown => 'Höhenbeschränkung';
	@override String width({required Object limit}) => 'Engstelle mit ${limit}';
	@override String get widthUnknown => 'Engstelle';
	@override String length({required Object limit}) => 'Längenbeschränkung auf ${limit}';
	@override String get lengthUnknown => 'Längenbeschränkung';
	@override String weight({required Object limit}) => 'Gewichtsbeschränkung auf ${limit}';
	@override String get weightUnknown => 'Gewichtsbeschränkung';
	@override String get unpaved => 'unbefestigte Straße';
	@override String weightLocalAccess({required Object limit}) => 'Gewichtsbeschränkung auf ${limit}, Anlieger frei';
	@override String widthLocalAccess({required Object limit}) => 'Engstelle mit ${limit}, Anlieger frei';
	@override String lengthLocalAccess({required Object limit}) => 'Längenbeschränkung auf ${limit}, Anlieger frei';
}

// Path: navigation.warning.lowClearance
class _Translations$navigation$warning$lowClearance$de extends Translations$navigation$warning$lowClearance$en {
	_Translations$navigation$warning$lowClearance$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'Niedrige Brücke ${limit}';
	@override String tunnel({required Object limit}) => 'Tunnel ${limit}';
	@override String buildingPassage({required Object limit}) => 'Tordurchfahrt ${limit}';
	@override String bridge({required Object limit}) => 'Brücke ${limit}';
	@override String barrier({required Object limit}) => 'Höhenbegrenzung ${limit}';
	@override String road({required Object limit}) => 'Höhenbeschränkung ${limit}';
}

// Path: navigation.warning.localAccess
class _Translations$navigation$warning$localAccess$de extends Translations$navigation$warning$localAccess$en {
	_Translations$navigation$warning$localAccess$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String weight({required Object limit}) => 'Anlieger frei: Fahrzeuge über ${limit} verboten, außer zur Zufahrt zu Ihrem Ziel';
	@override String axleLoad({required Object limit}) => 'Anlieger frei: Fahrzeuge über ${limit} Achslast verboten, außer zur Zufahrt zu Ihrem Ziel';
	@override String width({required Object limit}) => 'Anlieger frei: Fahrzeuge breiter als ${limit} verboten, außer zur Zufahrt zu Ihrem Ziel';
	@override String length({required Object limit}) => 'Anlieger frei: Fahrzeuge länger als ${limit} verboten, außer zur Zufahrt zu Ihrem Ziel';
}

// Path: navigation.guidance.voiceMode
class _Translations$navigation$guidance$voiceMode$de extends Translations$navigation$guidance$voiceMode$en {
	_Translations$navigation$guidance$voiceMode$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get full => 'Alle Sprachansagen';
	@override String get alerts => 'Sprachansagen: nur Warnungen';
	@override String get muted => 'Sprachansagen aus';
	@override String get toFull => 'Wieder alle Sprachansagen';
	@override String get toAlerts => 'Nur Warnungen ansagen';
	@override String get toMuted => 'Sprachansagen ausschalten';
	@override String get saysFull => 'Alle Sprachansagen: Abbiegehinweise und Warnungen.';
	@override String get saysAlerts => 'Nur Warnungen: Die Stimme meldet sich nur bei Blitzern, Gefahren und Routenänderungen.';
	@override String get saysMuted => 'Sprachansagen aus: Alles erscheint auf dem Bildschirm, ohne Ton.';
}

// Path: navigation.guidance.notificationWhy
class _Translations$navigation$guidance$notificationWhy$de extends Translations$navigation$guidance$notificationWhy$en {
	_Translations$navigation$guidance$notificationWhy$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get title => 'Benachrichtigung zur Navigation';
	@override String get body => 'Während der Navigation hält eine Benachrichtigung Standort und Sprachansagen bei ausgeschaltetem Bildschirm aktiv. Tippen Sie darauf, um zur Navigation zurückzukehren. Android fragt gleich, ob Lunaway sie anzeigen darf.';
	@override String get ask => 'Weiter';
	@override String get later => 'Nicht jetzt';
}

// Path: navigation.guidance.places
class _Translations$navigation$guidance$places$de extends Translations$navigation$guidance$places$en {
	_Translations$navigation$guidance$places$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get button => 'Plätze auf der Karte';
	@override String get buttonHidden => 'Plätze auf der Karte: ausgeblendet';
	@override String get title => 'Plätze auf der Karte';
	@override String get sleep => 'Übernachten';
	@override String get fill => 'Auffüllen';
	@override String get groceries => 'Essen';
	@override String get all => 'Alles';
	@override String get everyPlace => 'Alle Plätze';
	@override String get none => 'Nichts';
	@override String get customize => 'Anpassen';
	@override String get look => 'Darstellung';
	@override String get photos => 'Fotos';
	@override String get pictograms => 'Symbole';
	@override String get dots => 'Kleine Markierungen';
	@override String get photosHint => 'Die wichtigsten Plätze als Foto. Nie auf der Straße vor Ihnen und nie unter den Schaltflächen.';
	@override String get pictogramsHint => 'Die wichtigsten Plätze größer, mit Preis, Bewertung oder Übernachtung.';
	@override String get dotsHint => 'Alle Plätze als kleine Markierungen, wie auf der Karte.';
	@override String get free => 'Kostenlos';
	@override String get nightOk => 'Übernachten';
}

// Path: navigation.voice.moved
class _Translations$navigation$voice$moved$de extends Translations$navigation$voice$moved$en {
	_Translations$navigation$voice$moved$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String destination({required Object distance}) => 'Das Ziel wurde zur nächsten befahrbaren Straße verlegt, in ${distance} Entfernung.';
	@override String stop({required Object n, required Object distance}) => 'Zwischenstopp ${n} wurde zur nächsten befahrbaren Straße verlegt, in ${distance} Entfernung.';
}

// Path: navigation.voice.localAccess
class _Translations$navigation$voice$localAccess$de extends Translations$navigation$voice$localAccess$en {
	_Translations$navigation$voice$localAccess$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String weight({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge über ${limit}, Anlieger frei.';
	@override String axleLoad({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge über ${limit} Achslast, Anlieger frei.';
	@override String width({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge breiter als ${limit}, Anlieger frei.';
	@override String length({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge länger als ${limit}, Anlieger frei.';
}

// Path: navigation.voice.roadEvent
class _Translations$navigation$voice$roadEvent$de extends Translations$navigation$voice$roadEvent$en {
	_Translations$navigation$voice$roadEvent$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String works({required Object distance}) => 'In ${distance} Baustelle.';
	@override String lanes({required Object distance}) => 'In ${distance} Fahrbahnverengung.';
	@override String vehicleLimit({required Object distance}) => 'Achtung, in ${distance} Durchfahrtsbeschränkung wegen Baustelle.';
	@override String closure({required Object distance}) => 'In ${distance} ist die Straße möglicherweise gesperrt.';
	@override String detour({required Object distance}) => 'In ${distance} Umleitung ausgeschildert.';
}

// Path: navigation.voice.camera
class _Translations$navigation$voice$camera$de extends Translations$navigation$voice$camera$en {
	_Translations$navigation$voice$camera$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$voice$camera$kind$de kind = _Translations$navigation$voice$camera$kind$de._(_root);
	@override String radar({required Object distance, required Object what}) => 'In ${distance} ${what}.';
	@override String radarLimit({required Object distance, required Object what, required Object limit}) => 'In ${distance} ${what}, Tempolimit ${limit}.';
	@override String sectionLimit({required Object distance, required Object what, required Object limit}) => 'In ${distance} ${what}, im Schnitt höchstens ${limit}.';
	@override String get inSection => 'Abschnittskontrolle.';
	@override String slowDownRadar({required Object limit}) => 'Bitte langsamer, Blitzer bei Tempo ${limit}.';
	@override String slowDownRoad({required Object limit}) => 'Bitte langsamer, Tempolimit ${limit}.';
}

// Path: navigation.voice.camera.kind
class _Translations$navigation$voice$camera$kind$de extends Translations$navigation$voice$camera$kind$en {
	_Translations$navigation$voice$camera$kind$de._(TranslationsDe root) : this._root = root, super.internal(root);

	final TranslationsDe _root; // ignore: unused_field

	// Translations
	@override String get fixed => 'fester Blitzer';
	@override String get redLight => 'Rotlichtblitzer';
	@override String get levelCrossing => 'Blitzer am Bahnübergang';
	@override String get section => 'Abschnittskontrolle';
	@override String get other => 'Blitzer';
}

/// The flat map containing all translations for locale <de>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsDe {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Karte',
			'nav.favorites' => 'Favoriten',
			'nav.profile' => 'Profil',
			'nav.fold' => 'Menü einklappen',
			'nav.unfold' => 'Menü ausklappen',
			'common.close' => 'Schließen',
			'common.done' => 'Fertig',
			'common.cancel' => 'Abbrechen',
			'common.retry' => 'Erneut versuchen',
			'common.save' => 'Speichern',
			'common.delete' => 'Löschen',
			'common.undo' => 'Rückgängig',
			'common.ok' => 'Verstanden',
			'common.saveFailed' => 'Die Änderung konnte nicht gespeichert werden.',
			'common.send' => 'Senden',
			'common.later' => 'Später',
			'common.next' => 'Weiter',
			'common.failed' => 'Das hat nicht geklappt. Versuchen Sie es gleich noch einmal.',
			'common.offline' => 'Zurzeit keine Verbindung. Versuchen Sie es erneut, sobald Sie wieder online sind.',
			'notices.close' => 'Hinweis schließen',
			'notices.fold' => 'Hinweis einklappen',
			'notices.unfold' => 'Hinweis anzeigen',
			'kinds.motorhomeArea' => 'Wohnmobil-Stellplatz',
			'kinds.serviceArea' => 'Ver- und Entsorgungsstation',
			'kinds.campsite' => 'Campingplatz',
			'kinds.parking' => 'Parkplatz',
			'kinds.nature' => 'Platz in freier Natur',
			'kinds.restArea' => 'Rastplatz',
			'kinds.picnicArea' => 'Picknickplatz',
			'kinds.farm' => 'Stellplatz auf dem Bauernhof',
			'kinds.homestay' => 'Stellplatz bei Privatleuten',
			'kinds.offRoad' => 'Offroad-Platz',
			'kinds.extraService' => 'Servicestopp',
			'families.stopovers' => 'Stell- und Parkplätze',
			'families.stopoversHint' => 'Stellplätze, Parkplätze, Rastplätze',
			'families.campsites' => 'Camping und Gastgeber',
			'families.campsitesHint' => 'Campingplätze, Bauernhöfe, Privatleute',
			'families.nature' => 'Natur',
			'families.natureHint' => 'Plätze in freier Natur, Offroad-Pisten',
			'families.services' => 'Ver- und Entsorgung',
			'families.servicesHint' => 'Wasser und Entsorgung, keine Übernachtung',
			'services.drinkingWater' => 'Trinkwasser',
			'services.greyWater' => 'Grauwasserentsorgung',
			'services.blackWater' => 'Kassettenentleerung',
			'services.wasteBin' => 'Mülleimer',
			'services.toilets' => 'Toiletten',
			'services.showers' => 'Duschen',
			'services.electricity' => 'Strom',
			'services.wifi' => 'WLAN',
			'services.laundry' => 'Waschmaschine',
			'services.lpg' => 'Autogas (LPG)',
			'services.gasBottles' => 'Gasflaschen',
			'services.vehicleWash' => 'Fahrzeugwäsche',
			'services.bakery' => 'Bäckerei',
			'services.swimmingPool' => 'Schwimmbad',
			'services.petsAllowed' => 'Haustiere willkommen',
			'services.mobileData' => 'Mobiles Internet',
			'services.winterCaravanning' => 'Im Winter geöffnet',
			'activities.monuments' => 'Sehenswürdigkeiten',
			'activities.windsurfKitesurf' => 'Windsurfen, Kitesurfen',
			'activities.mountainBiking' => 'Mountainbiken',
			'activities.hiking' => 'Wandern',
			'activities.climbing' => 'Klettern',
			'activities.canoeKayak' => 'Kanu, Kajak',
			'activities.fishing' => 'Angeln',
			'activities.shoreFishing' => 'Muscheln sammeln bei Ebbe',
			'activities.swimming' => 'Baden',
			'activities.motorcycling' => 'Motorradtouren',
			'activities.viewpoint' => 'Aussichtspunkt',
			'activities.playground' => 'Spielplatz',
			'amenities.water' => 'Wasser',
			'amenities.dumpStation' => 'Entsorgung',
			'amenities.electricity' => 'Strom',
			'amenities.toilets' => 'Toiletten',
			'amenities.showers' => 'Duschen',
			'amenities.wasteBin' => 'Mülleimer',
			'amenities.laundry' => 'Waschmaschine',
			'amenities.wifi' => 'WLAN',
			'amenities.lpg' => 'Autogas (LPG)',
			'overnight.allowed' => 'Übernachten erlaubt',
			'overnight.tolerated' => 'Übernachten geduldet',
			'overnight.dayOnly' => 'Nur tagsüber',
			'overnight.forbidden' => 'Übernachten verboten',
			'overnight.unknown' => 'Übernachten: keine Angabe',
			'overnight.allowedHint' => 'Sie dürfen hier übernachten.',
			'overnight.toleratedHint' => 'Eine Nacht wird meist geduldet. Bleiben Sie unauffällig und hinterlassen Sie keine Spuren.',
			'overnight.dayOnlyHint' => 'Parken nur tagsüber. Suchen Sie sich für die Nacht einen anderen Platz.',
			'overnight.forbiddenHint' => 'Übernachten ist hier verboten.',
			'overnight.unknownHint' => 'Dazu gibt es noch keine Angabe. Fragen Sie vor Ort nach.',
			'freshness.confirmed' => ({required Object when}) => 'Zuletzt von Reisenden bestätigt: ${when}',
			'freshness.unconfirmed' => 'Noch nicht von Reisenden bestätigt',
			'freshness.stale' => 'Zuletzt vor über einem Jahr bestätigt',
			'freshness.today' => 'heute',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'gestern', other: 'vor ${n} Tagen', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'vor einem Monat', other: 'vor ${n} Monaten', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'vor einem Jahr', other: 'vor ${n} Jahren', ), 
			'map.searchHint' => 'Platz oder Ort',
			'map.clearSearch' => 'Suche löschen',
			'map.locateMe' => 'Meinen Standort anzeigen',
			'map.aroundMe' => 'Plätze in meiner Nähe anzeigen',
			'map.zoomIn' => 'Vergrößern',
			'map.zoomOut' => 'Verkleinern',
			'map.filters' => 'Filter',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Kartennachweis: © OpenStreetMap-Mitwirkende, Kartenstil Protomaps. Öffnet die Urheberrechtsseite von OpenStreetMap.',
			'map.creditPhotos' => 'Fotos: Externe Community-Quelle',
			'map.creditPhotosLabel' => 'Kartennachweis: © OpenStreetMap-Mitwirkende, Kartenstil Protomaps; Fotos: Externe Community-Quelle. Öffnet die Urheberrechtsseite von OpenStreetMap.',
			'map.showList' => 'Liste',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Liste (${n})', other: 'Liste (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Platz hier', other: 'Plätze hier', ), 
			'map.nearestYouLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Platz in Ihrer Nähe', other: 'Plätze in Ihrer Nähe', ), 
			'map.nearestCentreLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Platz nahe der Kartenmitte', other: 'Plätze nahe der Kartenmitte', ), 
			'map.pointTitle' => 'Hier',
			'map.pointHint' => 'Punkt auf der Karte',
			'map.directionsHere' => 'Route hierher',
			'map.startHere' => 'Von hier starten',
			'map.departureChosen' => 'Start gewählt. Öffnen Sie jetzt das Ziel und seine Route.',
			'map.copyCoordinates' => 'Koordinaten kopieren',
			'map.freeTapHint' => 'Tippen Sie auf die Karte, um dorthin zu fahren oder dort einen Platz hinzuzufügen',
			'map.freeTapHintClick' => 'Klicken Sie auf die Karte, um dorthin zu fahren oder dort einen Platz hinzuzufügen',
			'map.addPlaceAtCenter' => 'Platz in der Kartenmitte hinzufügen',
			'map.addressSource' => ({required Object attribution}) => 'Quelle: ${attribution}',
			'map.placesAround' => 'Plätze in der Umgebung',
			'map.downloading' => 'Plätze in Frankreich werden heruntergeladen',
			'map.downloadingCount' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${count} Platz geladen', other: '${count} Plätze geladen', ), 
			'map.noData' => 'Noch keine Plätze auf diesem Gerät',
			'map.noDataHint' => 'Laden Sie die Plätze einmal herunter: Danach funktioniert die Karte ohne Netz.',
			'map.download' => 'Plätze herunterladen',
			'map.downloadFailed' => 'Der Download wurde unterbrochen',
			'map.demoBanner' => 'Demo: erfundene Plätze',
			'map.unsupported' => 'Die Karte ist auf diesem System nicht verfügbar. Nutzen Sie die Web-App.',
			'sync.failedOffline' => 'Zurzeit keine Verbindung.',
			'sync.failedBusy' => 'Der Server ist stark ausgelastet.',
			'sync.failedServer' => 'Der Server hat gerade ein Problem.',
			'sync.failedOther' => 'Die Aktualisierung ist fehlgeschlagen.',
			'sync.failedRefused' => 'Der Server hat die Aktualisierung abgelehnt. Möglicherweise ist eine neuere Version der App nötig.',
			'sync.willRetry' => 'Lunaway versucht es automatisch erneut.',
			'sync.incomplete' => ({required Object count}) => 'Download unvollständig: bisher ${count} Plätze',
			'sync.incompleteShort' => 'Download unvollständig',
			'sync.resuming' => ({required Object count}) => 'Download läuft: ${count} Plätze',
			'sync.resume' => 'Fortsetzen',
			'location.rationaleTitle' => 'Ihren Standort anzeigen?',
			'location.rationale' => 'Lunaway nutzt ihn, um die Karte auf Sie zu zentrieren, Plätze nach Entfernung zu sortieren und Sie zu navigieren. Für eine Route wird Ihr Standort an den Server von Lunaway gesendet, der ihn nicht speichert. Für den günstigsten Kraftstoff in Ihrer Umgebung wird nur ein auf etwa 5 km gerundeter Standort gesendet. Eine Straßenmeldung wird mit dem Ort gesendet, an dem Sie sie abgeben.',
			'location.allow' => 'Weiter',
			'location.notNow' => 'Nicht jetzt',
			'location.deniedTitle' => 'Standort für Lunaway ausgeschaltet',
			'location.denied' => 'Sie haben den Zugriff auf Ihren Standort abgelehnt. Um ihn zu nutzen, erlauben Sie den Zugriff in den Geräteeinstellungen.',
			'location.openSettings' => 'Einstellungen öffnen',
			'location.serviceOffTitle' => 'Standort ist ausgeschaltet',
			'location.serviceOff' => 'Der Standort ist auf diesem Gerät ausgeschaltet. Schalten Sie ihn in den Schnelleinstellungen ein und versuchen Sie es dann erneut.',
			'location.notAllowed' => 'Kein Zugriff auf Ihren Standort. Die Karte funktioniert auch ohne.',
			'location.noFix' => 'Ihr Standort lässt sich noch nicht bestimmen. Versuchen Sie es unter freiem Himmel oder gleich noch einmal.',
			'location.unsupported' => 'Dieses Gerät kann seinen Standort nicht bestimmen.',
			'location.browserDeniedTitle' => 'Der Browser blockiert Ihren Standort',
			'location.browserDenied' => 'Der Browser gibt Ihren Standort nicht an Lunaway weiter. Öffnen Sie links in der Adressleiste das Symbol (Schloss oder Regler), stellen Sie „Standort“ auf „Zulassen“ und fragen Sie Ihren Standort dann erneut über seine Schaltfläche ab.',
			'location.browserNoFix' => 'Der Browser hat keinen Standort geliefert. Versuchen Sie es gleich noch einmal; an einem Computer hilft WLAN bei der Ortung.',
			'search.towns' => 'Orte',
			'search.places' => 'Plätze',
			'search.noResult' => ({required Object query}) => 'Kein Platz und kein Ort passt zu „${query}“.',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Platz', other: '${n} Plätze', ), 
			'search.addresses' => 'Adressen',
			'search.addressesSearching' => 'Adressen werden gesucht',
			'search.addressesFailed' => 'Adressen können gerade nicht gesucht werden.',
			'search.addressSources' => ({required Object sources}) => 'Adressen: ${sources}',
			'search.offline' => 'Keine Verbindung: Die Suche braucht das Netz.',
			'search.addressKind.houseNumber' => 'Adresse',
			'search.addressKind.street' => 'Straße',
			'search.addressKind.locality' => 'Ortsteil',
			'search.addressKind.town' => 'Gemeinde',
			'search.addressKind.postcode' => 'Postleitzahl',
			'search.addressKind.region' => 'Region',
			'search.deviceOnly' => 'Der Server antwortet nicht: Die Suche beschränkt sich auf die heruntergeladenen Regionen.',
			'filters.title' => 'Filter',
			'filters.families' => 'Art des Platzes',
			'filters.familiesHint' => 'Keine Auswahl: alle Arten',
			'filters.familiesChosenHint' => 'Nur diese Arten',
			'filters.night' => 'Übernachtung',
			'filters.nightHint' => 'Keine Auswahl: alle Plätze',
			'filters.nightChosenHint' => 'Nur Plätze mit diesem Status',
			'filters.nightPossible' => 'Übernachten möglich',
			'filters.amenities' => 'Ausstattung',
			'filters.amenitiesHint' => 'Der Platz muss alles davon bieten',
			'filters.rating' => 'Mindestbewertung',
			'filters.ratingHint' => 'Die Bewertung der Lunaway-Reisenden oder, falls diese den Platz nicht bewertet haben, die der anderen Quellen. Plätze ohne Bewertung werden ausgeblendet.',
			'filters.ratingAtLeast' => ({required Object rating}) => 'ab ${rating}',
			'filters.opening' => 'Öffnungszeiten',
			'filters.openingHint' => 'Orte, deren Öffnungszeiten nicht bekannt sind, werden weiter angezeigt.',
			'filters.openingAllYear' => 'Ganzjährig',
			'filters.openingDates' => 'Meine Reisedaten',
			'filters.openingClearDates' => 'Reisedaten löschen',
			'filters.openingStay' => ({required Object from, required Object to}) => '${from} bis ${to}',
			'filters.openingStayDay' => ({required Object date}) => 'Am ${date}',
			'filters.openingStayTitle' => 'Daten Ihres Aufenthalts',
			'filters.openingArrival' => 'Ankunft',
			'filters.openingDeparture' => 'Abreise',
			'filters.price' => 'Preis pro Nacht',
			'filters.freeOnly' => 'Kostenlos',
			'filters.freeHint' => 'Nur Plätze, an denen die Übernachtung laut Quellen kostenlos ist',
			'filters.scrollNext' => 'Nächste Filter anzeigen',
			'filters.scrollPrevious' => 'Vorherige Filter anzeigen',
			'filters.vehicle' => 'Mein Fahrzeug',
			'filters.myVehicleFits' => 'Mein Fahrzeug passt',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Passt für ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Blendet Plätze mit einer Höhenbegrenzung unter ${height} aus. Plätze ohne bekannte Begrenzung bleiben auf der Karte.',
			'filters.reset' => 'Zurücksetzen',
			'filters.apply' => 'Anwenden',
			'filters.show' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, zero: 'Kein passender Platz', one: '${count} Platz anzeigen', other: '${count} Plätze anzeigen', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Filter aktiv', other: '${n} Filter aktiv', ), 
			'place.unnamedTitle' => ({required Object kind, required Object where}) => '${kind} · ${where}',
			'place.away' => ({required Object distance}) => '${distance} entfernt',
			'place.directions' => 'Route',
			'place.share' => 'Teilen',
			'place.save' => 'Speichern',
			'place.saved' => 'Gespeichert',
			'place.saveHint' => 'In „Meine Favoriten“. Lange drücken, um Listen auszuwählen.',
			'place.saveHintClick' => 'In „Meine Favoriten“. Rechtsklick, um Listen auszuwählen.',
			'place.saveTo' => 'In einer Liste speichern',
			'place.chooseLists' => 'Listen',
			'place.savedToast' => 'Zu „Meine Favoriten“ hinzugefügt',
			'place.removedToast' => 'Aus „Meine Favoriten“ entfernt',
			'place.pricePerNight' => 'Preis pro Nacht',
			'place.priceFree' => 'Kostenlos',
			'place.priceUnknown' => 'Keine Angabe',
			'place.priceServices' => 'Ver- und Entsorgung',
			'place.priceIncluded' => 'Im Preis enthalten',
			'place.priceIncludes' => ({required Object items}) => 'Im Übernachtungspreis enthalten: ${items}',
			'place.inclusions.services' => 'Ver- und Entsorgung',
			'place.inclusions.touristTax' => 'Kurtaxe',
			'place.inclusions.electricity' => 'Strom',
			'place.maxHeight' => 'Max. Höhe',
			'place.capacity' => 'Anzahl Stellplätze',
			'place.classification' => 'Klassifizierung',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Stern', other: '${n} Sterne', ), 
			'place.hours' => 'Öffnungszeiten',
			'place.services' => 'Ausstattung',
			'place.noServices' => 'Keine Ausstattung angegeben.',
			'place.activities' => 'In der Nähe',
			'place.description' => 'Beschreibung',
			'place.contact' => 'Kontakt',
			'place.website' => 'Website',
			'place.call' => 'Anrufen',
			'place.coordinates' => 'Koordinaten',
			'place.address' => 'Adresse',
			'place.copyAddress' => 'Adresse kopieren',
			'place.addressSource' => ({required Object source}) => 'Quelle: ${source}',
			'place.copyShort' => 'Kopieren',
			'place.copy' => 'Koordinaten kopieren',
			'place.copyAs' => ({required Object format}) => 'Als ${format} kopieren',
			'place.copiesAs' => ({required Object format}) => '„Kopieren“ verwendet: ${format}',
			'place.copied' => ({required Object text}) => 'Kopiert: ${text}',
			'place.otherFormats' => 'Format zum Kopieren wählen',
			'place.formatDecimal' => 'Dezimalgrad',
			'place.formatDms' => 'Grad, Minuten, Sekunden',
			'place.formatGeo' => 'geo:-Link',
			'place.formatGoogle' => 'Google-Maps-Link',
			'place.formatOsm' => 'OpenStreetMap-Link',
			'place.sources' => 'Quellen',
			'place.fetched' => ({required Object when}) => 'Stand: ${when}',
			'place.viewSource' => 'Bei der Quelle ansehen',
			'place.gone' => 'Dieser Platz ist nicht mehr auf der Karte',
			'place.goneHint' => 'Er wurde seit der letzten Aktualisierung entfernt oder mit einem anderen zusammengeführt.',
			'place.arriving' => 'Dieser Platz wird noch heruntergeladen',
			'place.arrivingHint' => 'Die Plätze in Frankreich werden heruntergeladen, damit die Karte ohne Netz funktioniert. Die Platzseite öffnet sich, sobald dieser Platz da ist.',
			'place.loadError' => 'Dieser Platz konnte nicht geladen werden.',
			'place.openFailed' => 'Keine App konnte diesen Link öffnen.',
			'place.photos' => 'Fotos',
			'place.extrasOffline' => 'Keine Verbindung: Fotos und Rezensionen erscheinen, sobald das Netz zurück ist.',
			'place.offlineRest' => 'Keine Verbindung: Der Rest der Platzseite erscheint, sobald das Netz zurück ist.',
			'place.reviewsTitle' => 'Rezensionen',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Rezension', other: '${n} Rezensionen', ), 
			'place.noReviews' => 'Noch keine Rezensionen.',
			'place.noOtherReviews' => 'Noch keine weiteren Rezensionen.',
			'place.moreReviews' => 'Weitere Rezensionen',
			'place.moreReviewsFailed' => 'Weitere Rezensionen konnten nicht geladen werden. Erneut versuchen',
			'place.stars' => ({required Object rating}) => '${rating} von 5',
			'place.externalRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'externe Bewertung', other: 'externe Bewertungen', ), 
			'place.lunawayRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Lunaway-Bewertung', other: 'Lunaway-Bewertungen', ), 
			'place.deletedAccount' => 'Gelöschtes Konto',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Kastenwagen',
			'place.reviewVehicle.motorhome' => 'Wohnmobil',
			'place.reviewVehicle.caravan' => 'Wohnwagen',
			'place.reviewVehicle.other' => 'Anderes Fahrzeug',
			'place.originalLanguage' => ({required Object language}) => 'Originaltext auf ${language}',
			'place.descriptionIn' => ({required Object language}) => 'Beschreibung auf ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Foto ${index} von ${count}',
			'place.previousPhoto' => 'Vorheriges Foto',
			'place.nextPhoto' => 'Nächstes Foto',
			'place.links' => 'Auf anderen Websites',
			'place.sourceWithLicence' => ({required Object source, required Object licence}) => '${source} · ${licence}',
			'place.licenceCcBy' => 'CC BY 4.0',
			'place.photoCredit' => ({required Object source, required Object author}) => '${source} · ${author}',
			'place.photoStreetView' => 'Straßenansicht',
			'place.photoSurroundings' => 'Umgebung',
			'place.excerptFrom' => ({required Object source, required Object text}) => 'Laut ${source}: ${text}',
			'place.readMore' => 'Weiterlesen',
			'place.updatedOn' => ({required Object date}) => 'aktualisiert am ${date}',
			'place.otherSources' => 'Aus anderen Quellen',
			'sources.extcom.label' => 'Externe Community-Quelle',
			'sources.extcom.short' => 'Extern',
			'hours.open' => 'Jetzt geöffnet',
			'hours.openUntil' => ({required Object time}) => 'Geöffnet, schließt um ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Geöffnet, schließt ${day} um ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Geöffnet, schließt in ${n} Minute', other: 'Geöffnet, schließt in ${n} Minuten', ), 
			'hours.closedUntil' => ({required Object time}) => 'Geschlossen, öffnet um ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Geschlossen, öffnet ${day} um ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Geschlossen, öffnet in ${n} Minute', other: 'Geschlossen, öffnet in ${n} Minuten', ), 
			'hours.closedWindow' => 'In den nächsten zwei Wochen geschlossen',
			'hours.tomorrow' => 'morgen',
			'hours.onDate' => ({required Object date}) => 'am ${date}',
			'hours.onWeekday' => ({required Object day}) => 'am ${day}',
			'hours.midnight' => 'Mitternacht',
			'hours.stale' => 'Öffnungszeiten eventuell veraltet. Aktualisieren Sie die Plätze im Profil.',
			'hours.localTime' => 'Zeiten in der Ortszeit des Platzes',
			'hours.codes.mo' => 'Mo.',
			'hours.codes.tu' => 'Di.',
			'hours.codes.we' => 'Mi.',
			'hours.codes.th' => 'Do.',
			'hours.codes.fr' => 'Fr.',
			'hours.codes.sa' => 'Sa.',
			'hours.codes.su' => 'So.',
			'hours.codes.ph' => 'Feiertage',
			'hours.codes.sh' => 'Schulferien',
			'hours.codes.off' => 'geschlossen',
			'hours.codes.closed' => 'geschlossen',
			'hours.codes.sunrise' => 'Sonnenaufgang',
			'hours.codes.sunset' => 'Sonnenuntergang',
			'hours.months.jan' => 'Jan.',
			'hours.months.feb' => 'Feb.',
			'hours.months.mar' => 'März',
			'hours.months.apr' => 'Apr.',
			'hours.months.may' => 'Mai',
			'hours.months.jun' => 'Juni',
			'hours.months.jul' => 'Juli',
			'hours.months.aug' => 'Aug.',
			'hours.months.sep' => 'Sept.',
			'hours.months.oct' => 'Okt.',
			'hours.months.nov' => 'Nov.',
			'hours.months.dec' => 'Dez.',
			'hours.dayOfMonth' => ({required Object day, required Object month}) => '${day}. ${month}',
			'hours.dayOfYear' => ({required Object day, required Object month, required Object year}) => '${day}. ${month} ${year}',
			'hours.allWeek' => 'Rund um die Uhr',
			'hours.allYear' => 'ganzjährig',
			'hours.seasonAllYear' => 'Ganzjährig geöffnet',
			'hours.seasonOpenUntil' => ({required Object date}) => 'Geöffnet bis ${date}',
			'hours.seasonClosedUntil' => ({required Object date}) => 'Geschlossen, öffnet am ${date}',
			'directions.title' => 'Öffnen in',
			'directions.hint' => 'Diese Apps kennen die Maße Ihres Fahrzeugs nicht.',
			'directions.remember' => 'Immer diese App verwenden',
			'directions.rememberHint' => 'Im Profil änderbar',
			'directions.settingTitle' => 'In einer anderen App öffnen',
			'directions.settingHint' => 'Welche App „Öffnen in“ bei einer Route startet',
			'directions.askEachTime' => 'Jedes Mal fragen',
			'directions.appleMaps' => 'Apple Karten',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (Browser)',
			'directions.none' => 'Keine Navigations-App auf diesem Gerät gefunden.',
			'navigation.preview.titleTo' => ({required Object name}) => 'Ziel: ${name}',
			'navigation.preview.titlePoint' => 'Punkt auf der Karte',
			'navigation.preview.departure.title' => 'Start',
			'navigation.preview.departure.from' => ({required Object name}) => 'Start: ${name}',
			'navigation.preview.departure.myPosition' => 'mein Standort',
			'navigation.preview.departure.myPositionChoice' => 'Mein Standort',
			'navigation.preview.departure.change' => 'Ändern',
			'navigation.preview.departure.choose' => 'Start wählen',
			'navigation.preview.departure.searchHint' => 'Platz, Ort oder Adresse',
			'navigation.preview.departure.guidanceFromPosition' => 'Die Navigation beginnt an Ihrem Standort, nicht an einem gewählten Start.',
			'navigation.preview.departure.fromMyPosition' => 'Von meinem Standort starten',
			'navigation.preview.computing' => 'Route für Ihr Fahrzeug wird berechnet',
			'navigation.preview.start' => 'Starten',
			'navigation.preview.recommended' => 'Empfohlen',
			'navigation.preview.alternative' => ({required Object n}) => 'Alternative ${n}',
			'navigation.preview.toll' => 'Maut',
			'navigation.preview.ferry' => 'Fähre',
			'navigation.preview.motorway' => 'Autobahn',
			'navigation.preview.noWarnings' => 'Auf dieser Route wird keine Beschränkung für Ihr Fahrzeug knapp.',
			'navigation.preview.warnings' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '1 Beschränkung zu beachten', other: '${n} Beschränkungen zu beachten', ), 
			'navigation.preview.vehicle' => 'Ihr Fahrzeug',
			'navigation.preview.vehicleTowing' => ({required Object vehicle}) => '${vehicle}, als Gespann',
			'navigation.preview.editVehicle' => 'Bearbeiten',
			'navigation.preview.cruise' => ({required Object speed}) => 'Berechnet mit max. ${speed}',
			'navigation.preview.slowStretch' => ({required Object duration, required Object distance}) => 'Davon ${duration} für ${distance} sehr langsame Strecke',
			'navigation.preview.avoid' => 'Vermeiden',
			'navigation.preview.avoidTolls' => 'Mautstraßen',
			'navigation.preview.avoidMotorways' => 'Autobahnen',
			'navigation.preview.avoidFerries' => 'Fähren',
			'navigation.preview.avoidUnpaved' => 'Unbefestigte Straßen',
			'navigation.preview.roadbook' => 'Wegbeschreibung',
			'navigation.preview.roadbookShow' => 'Anweisungen anzeigen',
			'navigation.preview.roadbookHide' => 'Anweisungen ausblenden',
			'navigation.preview.dataOf' => ({required Object date}) => 'Straßendaten vom ${date}',
			'navigation.preview.attributionOsm' => '© OpenStreetMap-Mitwirkende',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, Ausgabe vom ${date}',
			'navigation.preview.otherApps' => 'Öffnen in …',
			'navigation.preview.back' => 'Zurück',
			'navigation.preview.moved.origin' => ({required Object distance}) => 'Start um ${distance} an die nächste für Ihr Fahrzeug erreichbare Straße verlegt',
			'navigation.preview.moved.destination' => ({required Object distance}) => 'Ziel um ${distance} an die nächste für Ihr Fahrzeug erreichbare Straße verlegt',
			'navigation.preview.moved.stop' => ({required Object n, required Object distance}) => 'Zwischenstopp ${n} um ${distance} an die nächste für Ihr Fahrzeug erreichbare Straße verlegt',
			'navigation.stops.title' => 'Zwischenstopps',
			'navigation.stops.add' => 'Als Stopp hinzufügen',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Als Stopp hinzufügen · +${minutes} Min.',
			'navigation.stops.addFree' => 'Als Stopp hinzufügen · ohne Umweg',
			'navigation.stops.quoting' => 'Als Stopp hinzufügen · Umweg wird berechnet',
			'navigation.stops.noRoute' => 'Keine Route über diesen Punkt für Ihr Fahrzeug.',
			'navigation.stops.full' => 'Höchstens fünf Zwischenstopps.',
			'navigation.stops.goDirectly' => 'Direkt hinfahren',
			'navigation.stops.openCard' => 'Details ansehen',
			'navigation.stops.point' => 'Punkt auf der Karte',
			'navigation.stops.remove' => 'Zwischenstopp entfernen',
			'navigation.stops.reorder' => 'Ziehen, um die Reihenfolge zu ändern',
			'navigation.stops.added' => 'Zwischenstopp hinzugefügt',
			'navigation.stops.removed' => 'Zwischenstopp entfernt',
			'navigation.stops.moved' => 'Reihenfolge geändert',
			'navigation.stops.destinationChanged' => 'Neues Ziel',
			'navigation.stops.failed' => 'Die Route konnte nicht geändert werden.',
			'navigation.stops.noQuote' => 'Der Umweg konnte nicht berechnet werden.',
			'navigation.stops.offline' => 'Keine Verbindung, um den Umweg zu berechnen.',
			'navigation.legs.all' => 'Alle',
			'navigation.legs.stop' => ({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}',
			'navigation.legs.stopSaid' => ({required Object number, required Object name, required Object time, required Object distance}) => 'Zwischenstopp ${number}: ${name}, gegen ${time}, in ${distance}',
			'navigation.legs.arrival' => ({required Object name, required Object time}) => 'Ziel · ${name} · ${time}',
			'navigation.legs.arrivalSaid' => ({required Object name, required Object time}) => 'Ziel: ${name}, gegen ${time}',
			'navigation.legs.remove' => ({required Object number, required Object name}) => 'Zwischenstopp ${number} entfernen, ${name}',
			'navigation.fuel.price' => ({required Object price}) => '${price} €/l',
			'navigation.fuel.withDetour' => ({required Object price}) => '${price} €/l inkl. Umweg',
			'navigation.fuel.detour' => ({required Object distance, required Object minutes}) => '+${distance} · +${minutes} Min.',
			'navigation.fuel.onRoute' => 'an der Route',
			'navigation.fuel.open' => 'Geöffnet',
			'navigation.fuel.closed' => 'Geschlossen',
			'navigation.fuel.unknownHours' => 'Öffnungszeiten unbekannt',
			'navigation.fuel.add' => 'Hinzufügen',
			'navigation.fuel.station' => 'Tankstelle',
			'navigation.fuel.empty' => 'Keine Tankstelle mit einem Preis für diesen Kraftstoff nahe der Route.',
			'navigation.fuel.emptyHint' => 'Die Preise stammen vom französischen Wirtschaftsministerium und sind nur für Frankreich bekannt.',
			'navigation.fuel.failed' => 'Die Tankstellen konnten nicht geladen werden.',
			'navigation.fuel.estimated' => 'Umwege anhand der Entfernung zur Route geschätzt.',
			'navigation.fuel.attribution' => 'Preise: französisches Wirtschaftsministerium (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => 'vor ${n} Min.',
			'navigation.fuel.hoursAgo' => ({required Object n}) => 'vor ${n} Std.',
			'navigation.fuel.daysAgo' => ({required Object n}) => 'vor ${n} Tagen',
			'navigation.onTheWay.title' => 'Unterwegs',
			'navigation.onTheWay.categories.fuel' => 'Tanken',
			'navigation.onTheWay.categories.sleep' => 'Übernachten',
			'navigation.onTheWay.categories.water' => 'Wasser und Entsorgung',
			'navigation.onTheWay.categories.groceries' => 'Einkaufen',
			'navigation.onTheWay.categories.bakeries' => 'Bäckereien',
			'navigation.onTheWay.categories.toilets' => 'WC, Duschen',
			'navigation.onTheWay.categories.health' => 'Gesundheit',
			'navigation.onTheWay.categories.services' => 'Dienstleistungen',
			'navigation.onTheWay.categories.charging' => 'Ladestationen',
			'navigation.onTheWay.categories.garages' => 'Werkstätten und Zubehör',
			'navigation.onTheWay.fuelOfVehicle' => ({required Object fuel}) => '${fuel}, laut Ihrem Fahrzeug',
			'navigation.onTheWay.otherFuel' => 'Anderer Kraftstoff',
			'navigation.onTheWay.keepFuel' => 'Als meinen Kraftstoff speichern',
			'navigation.onTheWay.fuelKept' => ({required Object fuel}) => '${fuel} für Ihr Fahrzeug gespeichert.',
			'navigation.onTheWay.keepFuelFailed' => 'Der Kraftstoff konnte nicht gespeichert werden.',
			'navigation.onTheWay.loading' => 'Suche entlang der Route',
			'navigation.onTheWay.empty' => 'Keine Treffer auf dieser Route',
			'navigation.onTheWay.emptyHint' => 'Versuchen Sie eine andere Kategorie, oder öffnen Sie die Liste weiter vorne auf der Strecke erneut.',
			'navigation.onTheWay.failed' => 'Die Liste konnte nicht geladen werden.',
			'navigation.onTheWay.offline' => 'Keine Verbindung: Die Liste kommt mit der Verbindung zurück.',
			'navigation.onTheWay.rateLimited' => 'Viele Suchen hintereinander: Versuchen Sie es in einigen Minuten erneut.',
			'navigation.onTheWay.nearNone' => ({required Object distance}) => 'Nichts auf den nächsten ${distance}.',
			'navigation.onTheWay.further' => ({required Object n}) => 'Weiter entfernt (${n})',
			'navigation.onTheWay.more' => 'Mehr anzeigen',
			'navigation.onTheWay.moreFailed' => 'Der Rest konnte nicht geladen werden.',
			'navigation.onTheWay.ahead' => ({required Object distance}) => 'in ${distance}',
			'navigation.onTheWay.offRoute' => ({required Object distance}) => '${distance} von der Route',
			'navigation.onTheWay.byTheRoad' => 'direkt an der Straße',
			'navigation.onTheWay.addCost' => ({required Object minutes}) => 'Hinzufügen · +${minutes} Min.',
			'navigation.onTheWay.addFree' => 'Hinzufügen · ohne Umweg',
			'navigation.onTheWay.openAt' => ({required Object time}) => 'Geöffnet, wenn Sie vorbeikommen (gegen ${time})',
			'navigation.onTheWay.closedAt' => ({required Object time}) => 'Geschlossen, wenn Sie vorbeikommen (gegen ${time})',
			'navigation.onTheWay.closedOpensAt' => ({required Object time, required Object opens}) => 'Geschlossen, wenn Sie gegen ${time} vorbeikommen, öffnet um ${opens}',
			'navigation.onTheWay.perNight' => ({required Object price}) => '${price} pro Nacht',
			'navigation.onTheWay.photoFrom' => ({required Object source}) => 'Foto: ${source}',
			'navigation.onTheWay.servicesList' => ({required Object list}) => 'Ausstattung: ${list}',
			'navigation.onTheWay.placesCredit' => 'Plätze: Lunaway und die auf jeder Platzseite genannten Quellen',
			'navigation.states.vehicleTitle' => 'Was fahren Sie?',
			'navigation.states.vehicleHint' => 'Die Route meidet zu niedrige Brücken, zu enge Straßen und Straßen, die für Ihre Fahrzeugmaße gesperrt sind. Geben Sie Höhe, Breite, Länge und Gewicht an.',
			'navigation.states.vehicleMissing' => ({required Object list}) => 'Fehlende Angaben: ${list}',
			'navigation.states.vehicleOutOfBounds' => ({required Object list}) => 'Außerhalb des zulässigen Bereichs: ${list}',
			'navigation.states.dimension.height' => 'Höhe',
			'navigation.states.dimension.width' => 'Breite',
			'navigation.states.dimension.length' => 'Länge',
			'navigation.states.dimension.weight' => 'Gewicht',
			'navigation.states.describeVehicle' => 'Mein Fahrzeug beschreiben',
			'navigation.states.originTitle' => 'Wo sind Sie?',
			'navigation.states.originHint' => 'Lunaway braucht Ihren Standort, um die Route zu berechnen.',
			'navigation.states.locate' => 'Mich orten',
			'navigation.states.offlineTitle' => 'Keine Verbindung',
			'navigation.states.offlineHint' => 'Routen werden auf dem Server von Lunaway berechnet. Ohne Netz übergibt „Öffnen in …“ die Fahrt an eine Navigations-App mit eigenen Karten.',
			'navigation.states.rateLimitedTitle' => 'Zu viele Routenanfragen',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Versuchen Sie es in ${seconds} s erneut.',
			'navigation.states.unavailableTitle' => 'Routenberechnung nicht verfügbar',
			'navigation.states.unavailableHint' => 'Der Routendienst ist vorübergehend nicht verfügbar. Versuchen Sie es später erneut.',
			'navigation.states.refusedTitle' => 'Keine Route möglich',
			'navigation.states.refusedHint' => 'Lunaway konnte für diese Anfrage keine Route berechnen: Prüfen Sie das Ziel, die Länge der Strecke und die Angaben zum Fahrzeug.',
			'navigation.states.noSafeTitle' => 'Keine sichere Route für Ihr Fahrzeug',
			'navigation.states.noSafeHint' => 'Jede mögliche Strecke führt über eine Beschränkung, die Ihr Fahrzeug überschreitet:',
			'navigation.states.whatToDo' => 'Was Sie tun können',
			'navigation.states.checkVehicle' => ({required Object height, required Object weight}) => 'Prüfen Sie Ihre Angaben: ${height} hoch, ${weight}.',
			'navigation.states.pickOtherPoint' => 'Wählen Sie ein Ziel vor dem Hindernis: Halten Sie dazu einen Punkt auf der Karte gedrückt.',
			'navigation.states.pickOtherPointClick' => 'Wählen Sie ein Ziel vor dem Hindernis: Klicken Sie dazu mit der rechten Maustaste auf die Karte.',
			'navigation.states.noRouteTitle' => 'Keine Straße führt dorthin',
			'navigation.states.noRouteHint' => 'Der Punkt liegt vielleicht an einem Privatweg oder auf einer Insel ohne Fähre.',
			'navigation.states.allowUnpaved' => 'Unbefestigte Straßen werden gemieden: Erlauben Sie sie, wenn das Ziel an einem Feldweg liegt.',
			_ => null,
		} ?? switch (path) {
			'navigation.states.offNetworkTitle' => 'Zu weit von einer Straße entfernt',
			'navigation.states.offNetworkHint' => 'Wählen Sie ein Ziel an einer Straße.',
			'navigation.noRoute.originUnreachable' => 'Vom Startpunkt kein Durchkommen für Ihr Fahrzeug',
			'navigation.noRoute.originUnreachableBy' => ({required Object limit}) => 'Vom Startpunkt kein Durchkommen für Ihr Fahrzeug: ${limit}',
			'navigation.noRoute.destinationUnreachable' => 'Ziel für Ihr Fahrzeug nicht erreichbar',
			'navigation.noRoute.destinationUnreachableBy' => ({required Object limit}) => 'Ziel für Ihr Fahrzeug nicht erreichbar: ${limit}',
			'navigation.noRoute.waypointUnreachable' => ({required Object n}) => 'Zwischenstopp ${n} für Ihr Fahrzeug nicht erreichbar',
			'navigation.noRoute.waypointUnreachableBy' => ({required Object n, required Object limit}) => 'Zwischenstopp ${n} für Ihr Fahrzeug nicht erreichbar: ${limit}',
			'navigation.noRoute.blockedOnTheWay' => 'Zwischen den Stopps kein Durchkommen für Ihr Fahrzeug',
			'navigation.noRoute.blockedOnTheWayBy' => ({required Object limit}) => 'Zwischen den Stopps kein Durchkommen für Ihr Fahrzeug: ${limit}',
			'navigation.noRoute.blockedHint' => 'Jeder Stopp ist erreichbar, aber jede Straße dazwischen führt über eine Beschränkung, die Ihr Fahrzeug überschreitet.',
			'navigation.noRoute.notConnectedOrigin' => 'Von Ihrem Standort führt keine Straße weg',
			'navigation.noRoute.notConnectedDestination' => 'Keine Straße führt zum Ziel',
			'navigation.noRoute.notConnectedWaypoint' => ({required Object n}) => 'Keine Straße führt zu Zwischenstopp ${n}',
			'navigation.noRoute.notConnectedTrip' => 'Keine Straße verbindet Ihre Stopps',
			'navigation.noRoute.notConnectedHint' => 'Unabhängig vom Fahrzeug: eine Insel ohne Autofähre oder ein für den Verkehr gesperrter Weg.',
			'navigation.noRoute.outsideOrigin' => 'Ihr Standort liegt außerhalb des Navigationsgebiets',
			'navigation.noRoute.outsideDestination' => 'Ziel außerhalb des Navigationsgebiets',
			'navigation.noRoute.outsideWaypoint' => ({required Object n}) => 'Zwischenstopp ${n} außerhalb des Navigationsgebiets',
			'navigation.noRoute.outsideHint' => ({required Object countries}) => 'Lunaway berechnet Routen in diesen Ländern: ${countries}.',
			'navigation.noRoute.outsideHintUnknown' => 'Lunaway berechnet in diesem Land noch keine Routen.',
			'navigation.noRoute.noRoadOrigin' => 'Ihr Standort ist zu weit von einer Straße entfernt',
			'navigation.noRoute.noRoadDestination' => 'Ziel zu weit von einer Straße entfernt',
			'navigation.noRoute.noRoadWaypoint' => ({required Object n}) => 'Zwischenstopp ${n} zu weit von einer Straße entfernt',
			'navigation.noRoute.noRoadHint' => 'Im Umkreis von 5 km um diesen Punkt gibt es keine Straße, die Ihr Fahrzeug befahren darf.',
			'navigation.noRoute.tooLong' => 'Strecke zu lang',
			'navigation.noRoute.tooLongHint' => ({required Object trip, required Object max}) => '${trip} Luftlinie von Stopp zu Stopp: Lunaway berechnet Strecken bis höchstens ${max}.',
			'navigation.noRoute.vehicleValue' => ({required Object value}) => 'Ihr Fahrzeug: ${value}',
			'navigation.noRoute.limit.underpass' => ({required Object limit}) => 'niedrige Brücke mit ${limit}',
			'navigation.noRoute.limit.tunnel' => ({required Object limit}) => 'Tunnel mit ${limit}',
			'navigation.noRoute.limit.buildingPassage' => ({required Object limit}) => 'Tordurchfahrt mit ${limit}',
			'navigation.noRoute.limit.bridge' => ({required Object limit}) => 'Brücke mit ${limit}',
			'navigation.noRoute.limit.barrier' => ({required Object limit}) => 'Höhenbegrenzung auf ${limit}',
			'navigation.noRoute.limit.height' => ({required Object limit}) => 'Höhenbeschränkung auf ${limit}',
			'navigation.noRoute.limit.heightUnknown' => 'Höhenbeschränkung',
			'navigation.noRoute.limit.width' => ({required Object limit}) => 'Engstelle mit ${limit}',
			'navigation.noRoute.limit.widthUnknown' => 'Engstelle',
			'navigation.noRoute.limit.length' => ({required Object limit}) => 'Längenbeschränkung auf ${limit}',
			'navigation.noRoute.limit.lengthUnknown' => 'Längenbeschränkung',
			'navigation.noRoute.limit.weight' => ({required Object limit}) => 'Gewichtsbeschränkung auf ${limit}',
			'navigation.noRoute.limit.weightUnknown' => 'Gewichtsbeschränkung',
			'navigation.noRoute.limit.unpaved' => 'unbefestigte Straße',
			'navigation.noRoute.limit.weightLocalAccess' => ({required Object limit}) => 'Gewichtsbeschränkung auf ${limit}, Anlieger frei',
			'navigation.noRoute.limit.widthLocalAccess' => ({required Object limit}) => 'Engstelle mit ${limit}, Anlieger frei',
			'navigation.noRoute.limit.lengthLocalAccess' => ({required Object limit}) => 'Längenbeschränkung auf ${limit}, Anlieger frei',
			'navigation.noRoute.editVehicle' => 'Fahrzeug bearbeiten',
			'navigation.noRoute.allowUnpaved' => 'Unbefestigte Straßen erlauben',
			'navigation.noRoute.removeStop' => ({required Object n}) => 'Zwischenstopp ${n} entfernen',
			'navigation.noRoute.removeStopNamed' => ({required Object name}) => 'Zwischenstopp „${name}“ entfernen',
			'navigation.noRoute.placesAround' => 'Plätze rund um das Ziel ansehen',
			'navigation.noRoute.moveDestination' => 'Oder wählen Sie ein anderes Ziel: Halten Sie einen Punkt auf der Karte gedrückt und tippen Sie auf „Direkt hinfahren“.',
			'navigation.noRoute.moveDestinationClick' => 'Oder wählen Sie ein anderes Ziel: Klicken Sie mit der rechten Maustaste auf die Karte und dann auf „Direkt hinfahren“.',
			'navigation.noRoute.moveStop' => 'Für einen anderen Stopp: Zoomen Sie heran, tippen Sie auf die Karte oder halten Sie sie gedrückt, dann „Als Stopp hinzufügen“.',
			'navigation.noRoute.moveStopClick' => 'Für einen anderen Stopp: Zoomen Sie heran, klicken Sie auf die Karte oder klicken Sie mit der rechten Maustaste, dann „Als Stopp hinzufügen“.',
			'navigation.noRoute.moveOrigin' => 'Der Start ist Ihr Standort: Fahren Sie zu einer Straße, die Ihr Fahrzeug befahren darf, und versuchen Sie es dann erneut.',
			'navigation.noRoute.pickInside' => 'Wählen Sie ein Ziel in einem dieser Länder.',
			'navigation.noRoute.shorter' => 'Wählen Sie ein näheres Ziel oder fahren Sie die Strecke in mehreren Etappen.',
			'navigation.ferry.title' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Fährüberfahrt', other: '${n} Fährüberfahrten', ), 
			'navigation.ferry.unnamed' => 'Fähre',
			'navigation.ferry.named' => ({required Object name}) => 'Fähre ${name}',
			'navigation.ferry.ports' => ({required Object ports}) => 'Häfen: ${ports}',
			'navigation.ferry.countries' => ({required Object from, required Object to}) => 'Abfahrt: ${from} · Ankunft: ${to}',
			'navigation.ferry.country' => ({required Object country}) => 'Land: ${country}',
			'navigation.ferry.where' => ({required Object distance, required Object sea, required Object duration}) => '${distance} nach dem Start · ${sea} auf See, etwa ${duration}',
			'navigation.ferry.needed' => 'Das Ziel ist ohne Fähre nicht erreichbar: Die Route nutzt eine, obwohl Sie Fähren meiden.',
			'navigation.warning.lowClearance.underpass' => ({required Object limit}) => 'Niedrige Brücke ${limit}',
			'navigation.warning.lowClearance.tunnel' => ({required Object limit}) => 'Tunnel ${limit}',
			'navigation.warning.lowClearance.buildingPassage' => ({required Object limit}) => 'Tordurchfahrt ${limit}',
			'navigation.warning.lowClearance.bridge' => ({required Object limit}) => 'Brücke ${limit}',
			'navigation.warning.lowClearance.barrier' => ({required Object limit}) => 'Höhenbegrenzung ${limit}',
			'navigation.warning.lowClearance.road' => ({required Object limit}) => 'Höhenbeschränkung ${limit}',
			'navigation.warning.unknownClearance' => 'Niedrige Durchfahrt, Höhe unbekannt',
			'navigation.warning.narrow' => ({required Object limit}) => 'Engstelle ${limit}',
			'navigation.warning.tooLong' => ({required Object limit}) => 'Längenbeschränkung ${limit}',
			'navigation.warning.tooHeavy' => ({required Object limit}) => 'Gewichtsbeschränkung ${limit}',
			'navigation.warning.axleLoad' => ({required Object limit}) => 'Achslastbeschränkung ${limit}',
			'navigation.warning.motorhomeBan' => 'Verbot für Wohnmobile',
			'navigation.warning.trailerBan' => 'Verbot für Anhänger',
			'navigation.warning.goodsVehicleWeight' => ({required Object limit}) => 'Gewichtsbeschränkung für Lkw ${limit}',
			'navigation.warning.yours' => ({required Object value}) => 'Ihr Fahrzeug: ${value}',
			'navigation.warning.fromStart' => ({required Object distance}) => '${distance} nach dem Start',
			'navigation.warning.ahead' => ({required Object distance}) => 'In ${distance}',
			'navigation.warning.disputed' => 'Quellen widersprechen sich, der niedrigere Wert gilt',
			'navigation.warning.goodsOnly' => 'gilt für Lkw, beachten Sie die Schilder',
			'navigation.warning.osm' => 'OpenStreetMap',
			'navigation.warning.ign' => 'IGN BD TOPO',
			'navigation.warning.community' => 'Lunaway-Meldung',
			'navigation.warning.dialog' => 'Verkehrsanordnung (DiaLog)',
			'navigation.warning.localAccess.weight' => ({required Object limit}) => 'Anlieger frei: Fahrzeuge über ${limit} verboten, außer zur Zufahrt zu Ihrem Ziel',
			'navigation.warning.localAccess.axleLoad' => ({required Object limit}) => 'Anlieger frei: Fahrzeuge über ${limit} Achslast verboten, außer zur Zufahrt zu Ihrem Ziel',
			'navigation.warning.localAccess.width' => ({required Object limit}) => 'Anlieger frei: Fahrzeuge breiter als ${limit} verboten, außer zur Zufahrt zu Ihrem Ziel',
			'navigation.warning.localAccess.length' => ({required Object limit}) => 'Anlieger frei: Fahrzeuge länger als ${limit} verboten, außer zur Zufahrt zu Ihrem Ziel',
			'navigation.roadEvents.title' => 'Baustellen und Sperrungen',
			'navigation.roadEvents.none' => 'Keine Baustellen oder Sperrungen auf dieser Route bekannt.',
			'navigation.roadEvents.stale' => 'Baustellen und Sperrungen: Die Quellen wurden länger nicht abgefragt.',
			'navigation.roadEvents.avoided' => ({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Route um eine Sperrung herum geplant: ${names}', other: 'Route um ${n} Sperrungen herum geplant: ${names}', ), 
			'navigation.roadEvents.atDistance' => ({required Object distance}) => '${distance} nach dem Start',
			'navigation.roadEvents.more' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Und ${n} weitere auf der Route', other: 'Und ${n} weitere auf der Route', ), 
			'navigation.roadEvents.classClosure' => 'Straße gesperrt',
			'navigation.roadEvents.classWorks' => 'Baustelle',
			'navigation.roadEvents.classLaneRestriction' => 'Fahrbahnverengung',
			'navigation.roadEvents.classVehicleLimit' => 'Durchfahrtsbeschränkung',
			'navigation.roadEvents.classDetour' => 'Umleitung ausgeschildert',
			'navigation.roadEvents.reasonUnmatched' => 'Lage unsicher, vielleicht auf der Route',
			'navigation.roadEvents.reasonStale' => 'Quelle länger nicht abgefragt',
			'navigation.roadEvents.reasonOutsideHours' => 'außerhalb der vermuteten Zeiten',
			'navigation.roadEvents.reasonGoodsVehicles' => 'für Lkw',
			'navigation.roadEvents.reasonUnconfirmed' => 'von nur einem Reisenden gemeldet',
			'navigation.roadEvents.reasonAged' => 'ältere Meldung',
			'navigation.roadEvents.reasonInside' => 'die Route beginnt oder endet darin',
			'navigation.roadEvents.reasonNearLimit' => 'mit knappem Spielraum',
			'navigation.roadEvents.reasonOverLimit' => 'Ihr Fahrzeug überschreitet den Grenzwert',
			'navigation.marks.legend' => 'Legende',
			'navigation.marks.legendHide' => 'Legende einklappen',
			'navigation.marks.kindOrigin' => 'Start',
			'navigation.marks.kindDestination' => 'Ziel',
			'navigation.marks.kindStop' => 'Zwischenstopp',
			'navigation.marks.kindClosure' => 'Straße gesperrt',
			'navigation.marks.kindWorks' => 'Baustelle',
			'navigation.marks.kindLanes' => 'Fahrbahnverengung',
			'navigation.marks.kindClearance' => 'Höhenbeschränkung',
			'navigation.marks.kindWeight' => 'Gewichtsbeschränkung',
			'navigation.marks.kindLimit' => 'Andere Beschränkung (Breite, Länge, Verbot)',
			'navigation.marks.kindFuel' => 'Tankstelle',
			'navigation.marks.kindPlace' => 'Platz nahe der Route',
			'navigation.marks.groupLegend' => 'Nahe beieinanderliegende Markierungen, zusammengefasst',
			'navigation.marks.zoneLegend' => 'Gefahrenzone',
			'navigation.marks.zonesFrom' => ({required Object source, required Object date}) => 'Gefahrenzonen: ${source}, Liste vom ${date}',
			'navigation.marks.group' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Markierung', other: '${n} Markierungen', ), 
			'navigation.marks.groupHint' => 'Heranzoomen, um sie einzeln zu sehen',
			'navigation.marks.count' => ({required Object kind, required Object n}) => '${kind}: ${n}',
			'navigation.marks.stop' => ({required Object n}) => 'Zwischenstopp ${n}',
			'navigation.marks.origin' => 'Startpunkt',
			'navigation.marks.nearRoute' => 'Nahe der Route',
			'navigation.marks.avoided' => 'Die Route führt daran vorbei',
			'navigation.marks.blocking' => 'Blockiert jede Route',
			'navigation.marks.showInList' => 'In der Liste ansehen',
			'navigation.marks.showAll' => 'Alle anzeigen',
			'navigation.marks.onMap' => 'auf der Karte zeigen',
			'navigation.marks.price' => ({required Object price}) => '${price} €',
			'navigation.marks.kindCamera' => 'Blitzer',
			'navigation.marks.cameras' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Blitzer', other: '${n} Blitzer', ), 
			'navigation.marks.camerasFrom' => ({required Object source, required Object date}) => 'Blitzer: ${source}, Liste vom ${date}',
			'navigation.marks.bothFrom' => ({required Object source, required Object date}) => 'Blitzer und Gefahrenzonen: ${source}, Liste vom ${date}',
			'navigation.marks.sectionLength' => ({required Object distance}) => 'Abschnitt von ${distance}',
			'navigation.marks.cameraDirection' => 'Misst in Ihrer Fahrtrichtung',
			'navigation.guidance.then' => 'Dann',
			'navigation.guidance.arrival' => ({required Object time}) => 'Ankunft ${time}',
			'navigation.guidance.offRoute' => 'Abseits der Route',
			'navigation.guidance.rerouting' => 'Neue Route wird gesucht',
			'navigation.guidance.rerouted' => 'Neue Route',
			'navigation.guidance.reroutedLonger' => ({required Object minutes}) => 'Neue Route, ${minutes} Min. länger',
			'navigation.guidance.rerouteOffline' => 'Kein Netz für eine neue Route: Kehren Sie zur Route zurück',
			'navigation.guidance.rerouteFailed' => 'Keine neue Route gefunden: Kehren Sie zur Route zurück',
			'navigation.guidance.closureAhead' => ({required Object distance}) => 'Straßensperrung in ${distance}: Eine andere Strecke wird gesucht',
			'navigation.guidance.noDetour' => ({required Object distance}) => 'Straßensperrung in ${distance}: keine andere Strecke',
			'navigation.guidance.eventAhead' => ({required Object distance}) => 'Baustelle in ${distance}',
			'navigation.guidance.eventClosure' => ({required Object distance}) => 'Straßensperrung in ${distance}',
			'navigation.guidance.eventLimit' => ({required Object distance}) => 'Durchfahrtsbeschränkung wegen Baustelle in ${distance}',
			'navigation.guidance.eventSource' => ({required Object source, required Object time}) => '${source}, Stand ${time}',
			'navigation.guidance.eventSourceOn' => ({required Object source, required Object day, required Object time}) => '${source}, Stand ${day}, ${time}',
			'navigation.guidance.avoidedClosures' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Route um eine Sperrung herum geplant', other: 'Route um ${n} Sperrungen herum geplant', ), 
			'navigation.guidance.roadEventAhead' => ({required Object what, required Object distance}) => '${what} in ${distance}',
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Straßensperrung in ${distance}: keine Verbindung, um eine andere Strecke zu suchen',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Straßensperrung in ${distance}: noch keine andere Strecke',
			'navigation.guidance.voiceMode.full' => 'Alle Sprachansagen',
			'navigation.guidance.voiceMode.alerts' => 'Sprachansagen: nur Warnungen',
			'navigation.guidance.voiceMode.muted' => 'Sprachansagen aus',
			'navigation.guidance.voiceMode.toFull' => 'Wieder alle Sprachansagen',
			'navigation.guidance.voiceMode.toAlerts' => 'Nur Warnungen ansagen',
			'navigation.guidance.voiceMode.toMuted' => 'Sprachansagen ausschalten',
			'navigation.guidance.voiceMode.saysFull' => 'Alle Sprachansagen: Abbiegehinweise und Warnungen.',
			'navigation.guidance.voiceMode.saysAlerts' => 'Nur Warnungen: Die Stimme meldet sich nur bei Blitzern, Gefahren und Routenänderungen.',
			'navigation.guidance.voiceMode.saysMuted' => 'Sprachansagen aus: Alles erscheint auf dem Bildschirm, ohne Ton.',
			'navigation.guidance.overview' => 'Ganze Route',
			'navigation.guidance.recenter' => 'Zentrieren',
			'navigation.guidance.end' => 'Navigation beenden',
			'navigation.guidance.endKeep' => 'Weiterfahren',
			'navigation.guidance.stopTitle' => 'Navigation beenden?',
			'navigation.guidance.stopConfirm' => 'Beenden',
			'navigation.guidance.arrivedTitle' => 'Sie sind angekommen',
			'navigation.guidance.done' => 'Fertig',
			'navigation.guidance.speed' => 'Geschwindigkeit',
			'navigation.guidance.limit' => 'Tempolimit',
			'navigation.guidance.noVoice' => ({required Object language}) => 'Keine Stimme für ${language} auf diesem Gerät: Anweisungen nur auf dem Bildschirm.',
			'navigation.guidance.missingVoice' => ({required Object language}) => 'Die Stimme für ${language} ist noch nicht heruntergeladen.',
			'navigation.guidance.installVoice' => 'Installieren',
			'navigation.guidance.voiceSettingsIos' => 'Einstellungen, Bedienungshilfen, Gesprochene Inhalte, Stimmen',
			'navigation.guidance.notificationTitle' => 'Navigation mit Lunaway aktiv',
			'navigation.guidance.notificationText' => 'Die Navigation läuft auch bei ausgeschaltetem Bildschirm weiter.',
			'navigation.guidance.notificationChannel' => 'Navigation',
			'navigation.guidance.unavailable' => 'Die Navigation konnte auf diesem Gerät nicht starten.',
			'navigation.guidance.notificationWhy.title' => 'Benachrichtigung zur Navigation',
			'navigation.guidance.notificationWhy.body' => 'Während der Navigation hält eine Benachrichtigung Standort und Sprachansagen bei ausgeschaltetem Bildschirm aktiv. Tippen Sie darauf, um zur Navigation zurückzukehren. Android fragt gleich, ob Lunaway sie anzeigen darf.',
			'navigation.guidance.notificationWhy.ask' => 'Weiter',
			'navigation.guidance.notificationWhy.later' => 'Nicht jetzt',
			'navigation.guidance.positionLost' => 'Standort nicht verfügbar: Prüfen Sie, ob die Ortung des Geräts für Lunaway eingeschaltet ist.',
			'navigation.guidance.positionStale' => ({required Object minutes}) => 'Letzter Standort vor ${minutes} Min. empfangen: Die Ankunftszeit beruht darauf.',
			'navigation.guidance.limitEstimated' => 'Geschätztes Tempolimit',
			'navigation.guidance.overLimit' => 'über dem Tempolimit',
			'navigation.guidance.enforcementSource' => ({required Object source, required Object date}) => '${source}, Liste vom ${date}',
			'navigation.guidance.demoDrive' => 'Simulierte Fahrt: Vorführung ohne GPS',
			'navigation.guidance.places.button' => 'Plätze auf der Karte',
			'navigation.guidance.places.buttonHidden' => 'Plätze auf der Karte: ausgeblendet',
			'navigation.guidance.places.title' => 'Plätze auf der Karte',
			'navigation.guidance.places.sleep' => 'Übernachten',
			'navigation.guidance.places.fill' => 'Auffüllen',
			'navigation.guidance.places.groceries' => 'Essen',
			'navigation.guidance.places.all' => 'Alles',
			'navigation.guidance.places.everyPlace' => 'Alle Plätze',
			'navigation.guidance.places.none' => 'Nichts',
			'navigation.guidance.places.customize' => 'Anpassen',
			'navigation.guidance.places.look' => 'Darstellung',
			'navigation.guidance.places.photos' => 'Fotos',
			'navigation.guidance.places.pictograms' => 'Symbole',
			'navigation.guidance.places.dots' => 'Kleine Markierungen',
			'navigation.guidance.places.photosHint' => 'Die wichtigsten Plätze als Foto. Nie auf der Straße vor Ihnen und nie unter den Schaltflächen.',
			'navigation.guidance.places.pictogramsHint' => 'Die wichtigsten Plätze größer, mit Preis, Bewertung oder Übernachtung.',
			'navigation.guidance.places.dotsHint' => 'Alle Plätze als kleine Markierungen, wie auf der Karte.',
			'navigation.guidance.places.free' => 'Kostenlos',
			'navigation.guidance.places.nightOk' => 'Übernachten',
			'navigation.voice.rerouting' => 'Route wird neu berechnet.',
			'navigation.voice.rerouted' => 'Neue Route.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(minutes, one: 'Neue Route, eine Minute länger.', other: 'Neue Route, ${minutes} Minuten länger.', ), 
			'navigation.voice.moved.destination' => ({required Object distance}) => 'Das Ziel wurde zur nächsten befahrbaren Straße verlegt, in ${distance} Entfernung.',
			'navigation.voice.moved.stop' => ({required Object n, required Object distance}) => 'Zwischenstopp ${n} wurde zur nächsten befahrbaren Straße verlegt, in ${distance} Entfernung.',
			'navigation.voice.closureAhead' => ({required Object distance}) => 'In ${distance} ist die Straße gesperrt. Eine andere Strecke wird gesucht.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'In ${distance} ist die Straße gesperrt. Es gibt keine Umfahrung.',
			'navigation.voice.clearance' => ({required Object distance, required Object height}) => 'Achtung, in ${distance} niedrige Durchfahrt, ${height} hoch.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Achtung, in ${distance} niedrige Durchfahrt, Höhe unbekannt.',
			'navigation.voice.narrow' => ({required Object distance, required Object width}) => 'Achtung, in ${distance} Engstelle, ${width} breit.',
			'navigation.voice.limit' => ({required Object distance, required Object what}) => 'Achtung, in ${distance} ${what}.',
			'navigation.voice.arrived' => 'Ziel erreicht.',
			'navigation.voice.metres' => ({required Object n}) => '${n} Metern',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count, one: 'einem Kilometer', other: '${n} Kilometern', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} Fuß',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count, one: 'einer Meile', other: '${n} Meilen', ), 
			'navigation.voice.size' => ({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count, one: '${metres} Meter ${cm}', other: '${metres} Meter ${cm}', ), 
			'navigation.voice.sizeWhole' => ({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count, one: '${metres} Meter', other: '${metres} Meter', ), 
			'navigation.voice.overSpeed' => ({required Object limit}) => 'Tempolimit ${limit}.',
			'navigation.voice.dangerZone' => ({required Object distance}) => 'In ${distance} Gefahrenzone.',
			'navigation.voice.inDangerZone' => 'Gefahrenzone.',
			'navigation.voice.localAccess.weight' => ({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge über ${limit}, Anlieger frei.',
			'navigation.voice.localAccess.axleLoad' => ({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge über ${limit} Achslast, Anlieger frei.',
			'navigation.voice.localAccess.width' => ({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge breiter als ${limit}, Anlieger frei.',
			'navigation.voice.localAccess.length' => ({required Object distance, required Object limit}) => 'Achtung, in ${distance} Verbot für Fahrzeuge länger als ${limit}, Anlieger frei.',
			'navigation.voice.roadEvent.works' => ({required Object distance}) => 'In ${distance} Baustelle.',
			'navigation.voice.roadEvent.lanes' => ({required Object distance}) => 'In ${distance} Fahrbahnverengung.',
			'navigation.voice.roadEvent.vehicleLimit' => ({required Object distance}) => 'Achtung, in ${distance} Durchfahrtsbeschränkung wegen Baustelle.',
			'navigation.voice.roadEvent.closure' => ({required Object distance}) => 'In ${distance} ist die Straße möglicherweise gesperrt.',
			'navigation.voice.roadEvent.detour' => ({required Object distance}) => 'In ${distance} Umleitung ausgeschildert.',
			'navigation.voice.positionLost' => 'Standort nicht verfügbar. Ortung des Geräts prüfen.',
			'navigation.voice.tonnes' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(count, one: '${n} Tonne', other: '${n} Tonnen', ), 
			'navigation.voice.camera.kind.fixed' => 'fester Blitzer',
			'navigation.voice.camera.kind.redLight' => 'Rotlichtblitzer',
			'navigation.voice.camera.kind.levelCrossing' => 'Blitzer am Bahnübergang',
			'navigation.voice.camera.kind.section' => 'Abschnittskontrolle',
			'navigation.voice.camera.kind.other' => 'Blitzer',
			'navigation.voice.camera.radar' => ({required Object distance, required Object what}) => 'In ${distance} ${what}.',
			'navigation.voice.camera.radarLimit' => ({required Object distance, required Object what, required Object limit}) => 'In ${distance} ${what}, Tempolimit ${limit}.',
			'navigation.voice.camera.sectionLimit' => ({required Object distance, required Object what, required Object limit}) => 'In ${distance} ${what}, im Schnitt höchstens ${limit}.',
			'navigation.voice.camera.inSection' => 'Abschnittskontrolle.',
			'navigation.voice.camera.slowDownRadar' => ({required Object limit}) => 'Bitte langsamer, Blitzer bei Tempo ${limit}.',
			'navigation.voice.camera.slowDownRoad' => ({required Object limit}) => 'Bitte langsamer, Tempolimit ${limit}.',
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h}:${m} Std.',
			'navigation.units.minutes' => ({required Object m}) => '${m} Min.',
			'navigation.settings.title' => 'Navigation',
			'navigation.settings.avoidTitle' => 'Standardmäßig vermeiden',
			'navigation.settings.voice' => 'Sprachansagen',
			'navigation.settings.voiceFull' => 'Alle',
			'navigation.settings.voiceAlerts' => 'Warnungen',
			'navigation.settings.voiceMuted' => 'Aus',
			'navigation.settings.voiceFullHint' => 'Abbiegehinweise und Warnungen, mit der Stimme des Geräts.',
			'navigation.settings.voiceAlertsHint' => 'Nur Blitzer und Gefahrenzonen, Sperrungen, Baustellen und Durchfahrtsbeschränkungen auf der Strecke sowie Routenänderungen, nach einem kurzen Signalton.',
			'navigation.settings.voiceMutedHint' => 'Kein Ton: Abbiegehinweise und Warnungen nur auf dem Bildschirm.',
			'navigation.settings.units' => 'Entfernungen',
			'navigation.settings.metric' => 'Kilometer',
			'navigation.settings.imperial' => 'Meilen',
			'navigation.settings.speedLimit' => 'Tempolimit',
			'navigation.settings.speedLimitHint' => 'Zeigt während der Navigation das Tempolimit für Ihr Fahrzeug neben Ihrer Geschwindigkeit. Geschätzte Werte erscheinen grau.',
			'navigation.settings.speedSound' => 'Gesprochener Tempolimit-Hinweis',
			'navigation.settings.speedSoundHint' => 'Ein kurzer Hinweis, wenn Sie das Tempolimit überschreiten, bei allen Sprachansagen. Blitzer und Gefahrenzonen folgen den Sprachansagen.',
			'navigation.settings.exactFrance' => 'Genaue Blitzerstandorte in Frankreich',
			'navigation.settings.exactFranceHint' => 'In Frankreich wird der Besitz eines Geräts, das die Position von Blitzern meldet, mit 1.500 € Bußgeld und 6 Punkten bestraft (Code de la route, Art. R413-15).',
			'navigation.enforcement.fixed' => 'Fester Blitzer',
			'navigation.enforcement.redLight' => 'Rotlichtblitzer',
			'navigation.enforcement.levelCrossing' => 'Blitzer am Bahnübergang',
			'navigation.enforcement.section' => 'Abschnittskontrolle',
			'navigation.enforcement.zone' => 'Gefahrenzone',
			'navigation.enforcement.average' => ({required Object limit}) => 'Schnitt ${limit}',
			'navigation.enforcement.averageLabel' => 'Schnitt',
			'navigation.enforcement.remaining' => ({required Object distance}) => 'noch ${distance}',
			'navigation.enforcement.yourAverage' => ({required Object speed}) => 'Ihr Schnitt ${speed}',
			'navigation.enforcement.zoneEnd' => 'Ende der Gefahrenzone',
			'navigation.enforcement.sectionEnd' => 'Ende der Abschnittskontrolle',
			'navigation.enforcement.ruleOff' => ({required Object country}) => '${country}: keine Blitzerwarnungen',
			'navigation.enforcement.ruleZones' => ({required Object country}) => '${country}: Gefahrenzonen',
			'navigation.enforcement.ruleExact' => ({required Object country}) => '${country}: Blitzer',
			'navigation.enforcement.ahead' => ({required Object what, required Object distance}) => '${what} in ${distance}',
			'navigation.enforcement.limit' => ({required Object limit}) => 'Tempolimit ${limit}',
			'navigation.enforcement.averageLimit' => ({required Object limit}) => 'Schnitt höchstens ${limit}',
			'navigation.enforcement.listSecuriteRoutiere' => 'Sécurité routière',
			'navigation.enforcement.listDsr' => 'Délégation à la sécurité routière',
			'navigation.enforcement.listGitd' => 'GITD',
			'navigation.enforcement.listPontsEtChaussees' => 'Ponts et chaussées',
			'navigation.enforcement.listBrusselsMobility' => 'Bruxelles Mobilité',
			'navigation.enforcement.listStatensVegvesen' => 'Statens vegvesen',
			'navigation.enforcement.listGarda' => 'An Garda Síochána',
			'navigation.enforcement.listOsm' => 'OpenStreetMap',
			'list.title' => 'Plätze in der Nähe',
			'list.empty' => 'Mit diesen Filtern gibt es hier keine Plätze',
			'list.emptyHint' => 'Verschieben Sie die Karte, zoomen Sie heraus oder lockern Sie die Filter.',
			'list.downloading' => 'Plätze werden geladen',
			'list.downloadingHint' => 'Die Liste füllt sich während des Downloads.',
			'list.error' => 'Die Liste konnte nicht geladen werden.',
			'list.offline' => 'Keine Verbindung: Die Liste braucht das Netz.',
			'list.moreFailed' => 'Weitere Plätze konnten nicht geladen werden. Erneut versuchen',
			'list.sortDistance' => 'Entfernung',
			'list.sortRating' => 'Bewertung',
			'list.sortNewest' => 'Neu hinzugefügt',
			'list.sortedBy' => ({required Object sort}) => 'Liste sortiert nach: ${sort}',
			'list.rankedAmongNearestYou' => ({required Object n}) => 'Sortiert innerhalb der ${n} Plätze, die Ihnen am nächsten liegen',
			'list.rankedAmongNearestCentre' => ({required Object n}) => 'Sortiert innerhalb der ${n} Plätze, die der Kartenmitte am nächsten liegen',
			'list.offlineTitle' => 'Keine Verbindung',
			'list.offlineNotHere' => 'Nichts aus diesem Gebiet auf diesem Gerät.',
			'favorites.title' => 'Favoriten',
			'favorites.defaultList' => 'Meine Favoriten',
			'favorites.empty' => 'Hier ist noch nichts gespeichert',
			'favorites.emptyHint' => 'Speichern Sie einen Platz, eine Adresse oder einen Punkt der Karte: So haben Sie alles auch offline griffbereit.',
			'favorites.newList' => 'Neue Liste',
			'favorites.listName' => 'Name der Liste',
			'favorites.renameList' => 'Liste umbenennen',
			'favorites.deleteList' => 'Liste löschen',
			'favorites.deleteListConfirm' => ({required Object name}) => '„${name}“ löschen? Die Plätze bleiben auf der Karte.',
			'favorites.listActions' => 'Listenoptionen',
			'favorites.placeActions' => 'Optionen für diesen Platz',
			'favorites.openOnMap' => 'Auf der Karte ansehen',
			'favorites.remove' => 'Aus der Liste entfernen',
			'favorites.removed' => 'Aus der Liste entfernt',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, zero: 'Leer', one: '${n} Favorit', other: '${n} Favoriten', ), 
			'favorites.error' => 'Ihre Favoriten konnten nicht geladen werden.',
			'favorites.pointNamed' => ({required Object date}) => 'Punkt vom ${date}',
			'favorites.name' => 'Name',
			'favorites.note' => 'Notiz (optional)',
			'favorites.edit' => 'Bearbeiten',
			'favorites.rename' => 'Umbenennen',
			'favorites.removeEverywhere' => 'Aus den Favoriten entfernen',
			'favorites.removedEverywhere' => 'Aus den Favoriten entfernt',
			'favorites.inFavorites' => 'In Ihren Favoriten',
			'favorites.inFavoritesAs' => ({required Object name}) => 'In Ihren Favoriten als „${name}“',
			'favorites.pointActions' => 'Optionen für diesen Punkt',
			'favorites.pointKind.address' => 'Adresse',
			'favorites.pointKind.town' => 'Gemeinde',
			'favorites.pointKind.point' => 'Punkt auf der Karte',
			'favorites.pointKind.poi' => 'Geschäft oder Dienstleistung',
			'favorites.deleteListPoints' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Der in dieser Liste gespeicherte Punkt wird mit ihr gelöscht.', other: 'Die ${n} in dieser Liste gespeicherten Punkte werden mit ihr gelöscht.', ), 
			'vehicle.title' => 'Mein Fahrzeug',
			'vehicle.why' => 'Anhand der Maße Ihres Fahrzeugs werden Plätze ausgeblendet, auf die es nicht passt. Die Maße werden mit jeder Routenanfrage gesendet und nicht gespeichert.',
			'vehicle.none' => 'Beschreiben Sie Ihr Fahrzeug, um Plätze auszublenden, auf die es nicht passt.',
			'vehicle.add' => 'Mein Fahrzeug beschreiben',
			'vehicle.edit' => 'Bearbeiten',
			'vehicle.type' => 'Typ',
			'vehicle.types.van' => 'Van',
			'vehicle.types.campervan' => 'Kastenwagen',
			'vehicle.types.lowProfile' => 'Teilintegriert',
			'vehicle.types.overcab' => 'Alkoven',
			'vehicle.types.integrated' => 'Vollintegriert',
			'vehicle.towingTitle' => 'Im Schlepptau',
			'vehicle.towing.none' => 'Nichts',
			'vehicle.towing.car' => 'Ein Auto',
			'vehicle.towing.trailer' => 'Ein Anhänger',
			'vehicle.size' => 'Maße',
			'vehicle.sizeHint' => 'Typische Werte für den gewählten Typ: Korrigieren Sie sie anhand Ihres Fahrzeugscheins.',
			'vehicle.height' => 'Höhe',
			'vehicle.width' => 'Breite',
			'vehicle.length' => 'Gesamtlänge inkl. Anhänger',
			'vehicle.weight' => 'Zulässiges Gesamtgewicht (zGG)',
			'vehicle.heightShort' => ({required Object value}) => 'H ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'B ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'L ${value}',
			'vehicle.notANumber' => 'Bitte eine Zahl eingeben, z. B. 2,90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Zwischen ${min} und ${max} ${unit}',
			'vehicle.navigationLater' => 'Die Navigation von Lunaway berücksichtigt alle diese Maße.',
			'vehicle.save' => 'Speichern',
			'vehicle.clear' => 'Löschen',
			'vehicle.fuelTitle' => 'Kraftstoff',
			'vehicle.fuelHint' => 'Der Preis Ihres Kraftstoffs erscheint an den Tankstellen auf der Karte, die günstigsten zuerst.',
			'vehicle.consumption' => 'Verbrauch',
			'vehicle.consumptionUnit' => 'l/100 km',
			'vehicle.lpgHeating' => 'Heizung mit Autogas (LPG)',
			'vehicle.lpgHeatingHint' => 'Auch die Autogaspreise erscheinen an den Tankstellen.',
			'vehicle.cruiseTitle' => 'Maximale Reisegeschwindigkeit',
			'vehicle.cruiseHint' => 'Die Fahrzeiten setzen voraus, dass Sie nie schneller fahren, auch wo die Straße es erlaubt. Angesagt werden weiterhin die Tempolimits der Straße.',
			'vehicle.cruiseNone' => 'Keine Begrenzung',
			'vehicleHeight.title' => 'Höhe Ihres Fahrzeugs',
			'vehicleHeight.why' => 'Plätze mit einer niedrigeren Höhenbegrenzung werden ausgeblendet. Plätze ohne bekannte Begrenzung bleiben auf der Karte.',
			'vehicleHeight.needed' => 'Geben Sie die Höhe an, zum Beispiel 2,90',
			'vehicleHeight.optional' => 'Optional',
			'vehicleHeight.weight' => 'Zulässiges Gesamtgewicht',
			'vehicleHeight.apply' => 'Mit dieser Höhe filtern',
			'vehicleHeight.later' => 'Weitere Fahrzeugdaten geben Sie im Profil unter „Mein Fahrzeug“ ein.',
			'profile.title' => 'Profil',
			'profile.noAccountNeeded' => 'Ohne Konto, ohne Werbung, ohne Tracker. Ihre Favoriten bleiben auf diesem Gerät.',
			'profile.language' => 'Sprache',
			'profile.languageSystem' => 'Gerätesprache',
			'profile.appearance' => 'Darstellung',
			'profile.themeAuto' => 'Automatisch',
			'profile.themeLight' => 'Hell',
			'profile.themeDark' => 'Dunkel',
			'profile.themeAutoHint' => 'Tagsüber hell, nach Sonnenuntergang an Ihrem Standort dunkel.',
			'profile.themeLightHint' => 'Immer hell, bei Tag und Nacht.',
			'profile.themeDarkHint' => 'Immer dunkel, schont nachts die Augen.',
			'profile.offline' => 'Offline',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Platz auf diesem Gerät', other: 'Plätze auf diesem Gerät', ), 
			'profile.offlineSize' => ({required Object size}) => 'Belegter Speicher: ${size}',
			'profile.lastSync' => ({required Object when}) => 'Letzte Aktualisierung: ${when}',
			'profile.neverSynced' => 'Noch nie heruntergeladen',
			'profile.syncNow' => 'Jetzt aktualisieren',
			'profile.syncing' => 'Wird aktualisiert',
			'profile.about' => 'Über die App',
			'profile.version' => ({required Object version}) => 'Version ${version}',
			'profile.website' => 'Website',
			'profile.privacy' => 'Datenschutzerklärung',
			'profile.sourceCode' => 'Quellcode',
			'profile.licences' => 'Lizenzen',
			'profile.appLicence' => 'Lunaway ist freie Software unter der GNU AGPL 3.0 oder einer späteren Version.',
			'profile.routeData' => 'Routen beruhen auf offenen Daten, die unvollständig sein können: Verkehrszeichen und Straßenverkehrsordnung haben Vorrang.',
			'profile.attributions' => 'Quellen und Nachweise',
			'profile.attributionOsm' => 'Plätze und Kartendaten © OpenStreetMap-Mitwirkende.',
			'profile.attributionOdbl' => 'OpenStreetMap-Daten unter der Open Database License (ODbL).',
			'profile.attributionAtout' => 'Klassifizierte Campingplätze von Atout France, verortet über die Base Adresse Nationale und die BD TOPO des IGN, unter der Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Gemeinden der Plätze: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), unter der ODbL.',
			'profile.attributionCommunityPlaces' => 'Von den Reisenden von Lunaway hinzugefügte und geänderte Plätze, unter der ODbL, mit der Nennung „Lunaway contributors“.',
			'profile.attributionTiles' => 'Grundkarte bereitgestellt von Lunaway, Stile abgeleitet von Protomaps (BSD-3-Clause), Daten © OpenStreetMap-Mitwirkende.',
			'profile.attributionFonts' => 'Schriftarten Fraunces und Atkinson Hyperlegible Next, SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Phosphor-Symbole, MIT-Lizenz.',
			'profile.noTracking' => 'Ohne Werbung, ohne Tracker. Ihr Konto kennt weder Ihre E-Mail-Adresse noch Ihre Telefonnummer.',
			'profile.attributionBdTopo' => 'Beschränkungen von Höhe, Breite, Länge und Gewicht auf den Straßen sowie anhand ihres Namens verortete Campingplätze: IGN BD TOPO, über die Géoplateforme, unter der Licence Ouverte 2.0.',
			'profile.attributionAddresses' => 'Adressen der Suche in Frankreich: Base Adresse Nationale, über die Géoplateforme des IGN, unter der Licence Ouverte 2.0.',
			'profile.attributionAddressesOsm' => 'Adressen der Suche außerhalb Frankreichs: OpenStreetMap, über Photon, unter der ODbL.',
			'profile.attributionPoiOdbl' => 'Geschäfte und Dienstleistungen: OpenStreetMap und die Öffnungszeiten der Postfilialen (La Poste), unter der ODbL.',
			'profile.attributionPoiLo' => 'Kraftstoffpreise (französisches Wirtschaftsministerium) und die Einrichtungen des Gesundheitswesens aus FINESS (Agence du numérique en santé), unter der Licence Ouverte 2.0 (Etalab).',
			'profile.attributionPacks' => 'Umrisse der Offline-Karten: Contours administratifs, data.gouv.fr (ODbL), und Natural Earth (gemeinfrei).',
			'profile.attributionOfflineLabels' => 'Beschriftungen und Symbole der Offline-Karten: Noto-Sans-Glyphen (SIL Open Font License 1.1) und Protomaps-Sprites, abgeleitet von tangrams/icons (MIT).',
			'profile.attributionExtcom' => 'Plätze, Rezensionen, Bewertungen und Fotos, gemäß schriftlicher Vereinbarung mit dieser Quelle.',
			'profile.creditsPlaces' => 'Plätze',
			'profile.creditsContent' => 'Fotos, Texte und Rezensionen',
			'profile.creditsRoutes' => 'Routen und Navigation',
			'profile.creditsSearch' => 'Suche',
			'profile.creditsMap' => 'Grundkarte',
			'profile.creditsApp' => 'App',
			'profile.attributionDatatourisme' => 'Plätze, Beschreibungen und Fotos der Touristeninformationen: DATAtourisme, unter der Licence Ouverte 2.0; jeder Text und jedes Foto nennt seine Touristeninformation, seinen Urheber und das Datum der letzten Aktualisierung.',
			'profile.attributionCommunity' => 'Rezensionen, Bewertungen und Fotos der Reisenden von Lunaway, unter CC BY 4.0, mit dem Pseudonym ihrer Urheber.',
			'profile.attributionCommons' => 'Fotos von Wikimedia Commons, jeweils unter ihrer eigenen Lizenz (CC0, gemeinfrei, CC BY oder CC BY-SA), mit Urheber und Link zur jeweiligen Seite.',
			'profile.attributionPanoramax' => 'Straßenansichten von Panoramax: die Instanz von OpenStreetMap France unter CC BY-SA 4.0, die des IGN unter der Licence Ouverte 2.0.',
			'profile.attributionWikipedia' => 'Auszüge aus Wikipedia-Artikeln, unter CC BY-SA 4.0, mit Link zum Artikel.',
			'profile.attributionMangrove' => 'Rezensionen von Mangrove Reviews, unter CC BY 4.0 oder der in der Rezension angegebenen Lizenz, mit Link zur Rezension.',
			'profile.attributionTranslation' => 'Automatische Übersetzungen: OPUS-MT-Modelle der Universität Helsinki, unter CC BY 4.0, ausgeführt auf den Servern von Lunaway.',
			'profile.attributionRoadEvents' => 'Baustellen und Sperrungen in Frankreich: DIR und Bison Futé, Verkehrsanordnungen aus DiaLog (DGITM), Städte und Départements (Lyon, Toulouse, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Sarthe), unter der Licence Ouverte 2.0; Bordeaux Métropole und das Département Côtes-d\'Armor, unter der Licence Ouverte; Ville de Paris, Rennes Métropole und die Meldungen der Reisenden von Lunaway, unter der ODbL.',
			'profile.attributionRoadEventsAbroad' => 'Baustellen und Sperrungen in den Niederlanden: NDW, Nationaal Dataportaal Wegverkeer (offene Daten); in Spanien: DGT, Dirección General de Tráfico (CC BY).',
			'profile.attributionDangerZones' => 'Blitzer und Gefahrenzonen: in Frankreich die Karte der Sécurité routière, weiterverwendet nach dem französischen Code des relations entre le public et l\'administration, und die Liste der festen Blitzer des Innenministeriums, Délégation à la sécurité routière (data.gouv.fr), unter der Licence Ouverte 2.0; in Polen Główny Inspektorat Transportu Drogowego (CANARD, dane.gov.pl), in Luxemburg die Administration des ponts et chaussées (data.public.lu), in Brüssel Bruxelles Mobilité (data.mobility.brussels), unter CC0; in Norwegen „Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.“; in Irland die Kontrollzonen von An Garda Síochána, Irish Public Sector Information, CC BY, Verläufe von Lunaway angepasst; OpenStreetMap (ODbL).',
			'profile.attributionCameraSource' => ({required Object attribution}) => 'Blitzer und Gefahrenzonen: ${attribution}',
			'profile.attributionOverture' => 'Geschäfte, Dienstleistungen, Unterkünfte und Freizeitangebote der Overture Maps Foundation (overturemaps.org): Daten von Meta, PinMeTo und DAC unter der Lizenz CDLA Permissive 2.0 und von AllThePlaces unter CC0 1.0.',
			'units.kilobytes' => ({required Object n}) => '${n} KB',
			'units.megabytes' => ({required Object n}) => '${n} MB',
			'languages.fr' => 'Französisch',
			'languages.en' => 'Englisch',
			'languages.de' => 'Deutsch',
			'languages.es' => 'Spanisch',
			'languages.it' => 'Italienisch',
			'languages.nl' => 'Niederländisch',
			'translation.translate' => 'Übersetzen',
			'translation.translating' => 'Wird übersetzt',
			'translation.showOriginal' => 'Original anzeigen',
			'translation.showTranslation' => 'Übersetzung anzeigen',
			'translation.from.fr' => 'Automatisch aus dem Französischen übersetzt',
			'translation.from.en' => 'Automatisch aus dem Englischen übersetzt',
			'translation.from.de' => 'Automatisch aus dem Deutschen übersetzt',
			'translation.from.es' => 'Automatisch aus dem Spanischen übersetzt',
			'translation.from.it' => 'Automatisch aus dem Italienischen übersetzt',
			'translation.from.nl' => 'Automatisch aus dem Niederländischen übersetzt',
			'translation.from.unknown' => ({required Object language}) => 'Automatisch übersetzt (Originalsprache: ${language})',
			'translation.offline' => 'Für die Übersetzung ist eine Internetverbindung nötig.',
			'translation.failedOffline' => 'Keine Internetverbindung: Der Text konnte nicht übersetzt werden.',
			'translation.busy' => 'Der Übersetzungsdienst ist ausgelastet. Versuchen Sie es später erneut.',
			'translation.unavailable' => 'Die Übersetzung ist derzeit nicht verfügbar.',
			'translation.gone' => 'Dieser Text ist nicht mehr verfügbar.',
			'translation.unsupported' => 'Diese Sprache kann nicht übersetzt werden.',
			'translation.autoReviews' => 'Rezensionen automatisch übersetzen',
			'translation.autoReviewsHint' => 'Lunaway übersetzt Rezensionen in anderen Sprachen auf seinem eigenen Server, ohne Dienste von Drittanbietern.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			'locale.de' => 'Deutsch',
			'locale.es' => 'Español',
			'locale.it' => 'Italiano',
			'locale.nl' => 'Nederlands',
			'account.title' => 'Ihr Konto',
			'account.noneTitle' => 'Noch kein Konto',
			'account.noneBody' => 'Karte, Suche und Favoriten funktionieren ohne Konto. Es wird bei Ihrem ersten Beitrag (eine Bewertung, eine Bestätigung, ein Foto) automatisch angelegt, ohne E-Mail und ohne Passwort. Ihre Favoritenlisten werden dann damit verknüpft, mit den darin gespeicherten Adressen, Punkten und Notizen.',
			'account.recover' => 'Mein Konto wiederherstellen',
			'account.memberSince' => ({required Object date}) => 'Mitglied seit ${date}',
			'account.editPseudonym' => 'Pseudonym ändern',
			'account.pseudonymTitle' => 'Ihr Pseudonym',
			'account.pseudonymHint' => 'Öffentlich: Es erscheint bei Ihren Rezensionen und Fotos. 3 bis 32 Zeichen.',
			'account.pseudonymInvalid' => '3 bis 32 Zeichen, davon mindestens zwei Buchstaben.',
			'account.pseudonymRefused' => 'Dieses Pseudonym ist nicht zulässig: keine Links, keine Kontaktdaten, keine Beleidigungen und kein Name, mit dem sich das Konto als Lunaway-Team ausgibt.',
			'account.pseudonymSaved' => 'Pseudonym gespeichert',
			'account.level' => ({required Object level}) => 'Vertrauensstufe ${level}',
			_ => null,
		} ?? switch (path) {
			'account.levelOpens.l0' => 'Sie können Plätze bewerten, bestätigen, dass es sie noch gibt, ein Problem melden und Ihre Favoriten synchronisieren.',
			'account.levelOpens.l1' => 'Sie können außerdem Rezensionen schreiben, Fotos hinzufügen und Änderungen an Plätzen vorschlagen.',
			'account.levelOpens.l2' => 'Sie können außerdem Plätze hinzufügen.',
			'account.levelOpens.l3' => 'Ihre Änderungen an Plätzen gelten ohne Prüfung.',
			'account.levelOpens.l4' => 'Sie wirken an der Moderation mit.',
			'account.nextLevel' => ({required Object level}) => 'Für Stufe ${level}',
			'account.levelTop' => 'Sie haben die höchste Stufe erreicht.',
			'account.requirement.age' => ({required Object needed, required Object current}) => 'Ein Konto, das mindestens ${needed} Tage alt ist (bisher ${current})',
			'account.requirement.confirmations' => ({required Object needed, required Object current}) => '${needed} Bestätigungen verschiedener Plätze (bisher ${current})',
			'account.requirement.contributions' => ({required Object needed, required Object current}) => '${needed} veröffentlichte Beiträge (bisher ${current})',
			'account.requirement.activeDays' => ({required Object needed, required Object current}) => '${needed} aktive Tage (bisher ${current})',
			'account.requirement.noRemoval' => 'Kein Beitrag von der Moderation entfernt',
			'account.requirement.sponsor' => 'Eine Empfehlung durch ein Mitglied der Stufe 2',
			'account.requirement.nomination' => 'Eine Ernennung durch die Moderation',
			'account.requirement.administration' => 'Eine Ernennung durch das Lunaway-Team',
			'account.orInstead' => ({required Object requirement}) => 'Oder ${requirement}',
			'account.recoveryNone' => 'Auf diesem Gerät wurde keine Sicherungskarte erstellt. Ohne sie bleibt dieses Konto an dieses Gerät gebunden: Geht das Gerät verloren, ist auch das Konto verloren.',
			'account.recoveryNoneAccount' => 'Für dieses Konto gibt es noch keine Sicherungskarte. Ohne sie bleibt dieses Konto an dieses Gerät gebunden: Geht das Gerät verloren, ist auch das Konto verloren.',
			'account.recoveryCreate' => 'Meine Sicherungskarte erstellen',
			'account.recoveryMade' => ({required Object date}) => 'Erstellt am ${date}',
			'account.recoveryRemake' => 'Neu erstellen',
			'account.recoveryRemakeHint' => 'Neue Sicherungskarte erstellen',
			'account.contributions' => 'Meine Beiträge',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Beitrag wartet auf Versand', other: '${n} Beiträge warten auf Versand', ), 
			'account.mutedAuthors' => 'Ausgeblendete Autoren',
			'account.devices' => 'Geräte',
			'account.signOut' => 'Abmelden',
			'account.delete' => 'Mein Konto löschen',
			'account.signOutTitle' => 'Auf diesem Gerät abmelden?',
			'account.signOutBody' => 'Der Schlüssel des Kontos wird von diesem Gerät gelöscht. Um zurückzukehren, brauchen Sie Ihre Sicherungskarte. Ihre Favoriten bleiben hier.',
			'account.signOutNoCard' => 'Sie haben auf diesem Gerät keine Sicherungskarte erstellt. Ohne sie ist dieses Konto endgültig verloren.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Ein Beitrag, der auf Versand wartet, wird nicht gesendet.', other: '${n} Beiträge, die auf Versand warten, werden nicht gesendet.', ), 
			'account.signedOut' => 'Abgemeldet. Ihre Favoriten bleiben auf diesem Gerät.',
			'account.lost' => 'Dieses Konto lässt sich auf diesem Gerät nicht mehr öffnen. Stellen Sie es mit Ihrer Sicherungskarte wieder her: Profil, Mein Konto wiederherstellen.',
			'account.lostAction' => 'Wiederherstellen',
			'account.welcomeTitle' => 'Danke für Ihren ersten Beitrag',
			'account.welcomeBody' => ({required Object name}) => 'Ihr Konto wurde unter dem Pseudonym „${name}“ angelegt. Statt E-Mail und Passwort nutzt es einen Schlüssel, der auf diesem Gerät gespeichert ist. Das Pseudonym können Sie im Profil ändern.',
			'account.welcomeCard' => 'Erstellen Sie Ihre Sicherungskarte, um dieses Konto auf einem anderen Gerät wiederzufinden.',
			'account.welcomeFavorites' => 'Ihre Favoritenlisten werden jetzt samt Adressen und Notizen mit Ihrem Konto gespeichert.',
			'recovery.title' => 'Sicherungskarte',
			'recovery.intro' => 'Ein Code, der Ihr Konto auf ein neues Gerät bringt. Lunaway speichert davon nur einen Fingerabdruck, mit dem er sich prüfen lässt: Der Code selbst kann nie wieder angezeigt werden, und jede neue Karte hat einen anderen Code.',
			'recovery.replaces' => 'Eine neue Karte ersetzt die vorherige: Der alte Code funktioniert dann nicht mehr.',
			'recovery.replaceTitle' => ({required Object date}) => 'Karte vom ${date} ersetzen?',
			'recovery.replaceBody' => ({required Object date}) => 'Die neue Karte bekommt einen anderen Code. Der Code der Karte vom ${date} funktioniert ab sofort nicht mehr. Er kann nicht erneut angezeigt werden: Lunaway hat davon nur einen Fingerabdruck gespeichert.',
			'recovery.replaceKeep' => 'Die alte behalten',
			'recovery.replaceConfirm' => 'Neue Karte erstellen',
			'recovery.make' => 'Karte erstellen',
			'recovery.codeLabel' => 'Ihr Sicherungscode',
			'recovery.shownOnce' => 'Dieser Code wird nur einmal angezeigt. Notieren Sie ihn oder speichern Sie das Bild, bevor Sie schließen.',
			'recovery.saveImage' => 'Bild speichern',
			'recovery.done' => 'Ich habe den Code notiert',
			'recovery.doneTitle' => 'Haben Sie den Code notiert oder gespeichert?',
			'recovery.doneBody' => 'Sobald diese Seite geschlossen ist, wird er nicht mehr angezeigt.',
			'recovery.keep' => 'Auf der Seite bleiben',
			'recovery.cardHeading' => 'Lunaway-Sicherungskarte',
			'recovery.cardAccount' => ({required Object name}) => 'Konto: ${name}',
			'recovery.cardHow' => 'So stellen Sie das Konto wieder her: Profil, Mein Konto wiederherstellen, dann diesen Code eingeben oder die Karte fotografieren.',
			'recovery.cardMade' => ({required Object date}) => 'Erstellt am ${date}',
			'recovery.cardWarning' => 'Dieser Code öffnet das Konto: Geben Sie ihn niemals weiter.',
			'recovery.failed' => 'Die Karte konnte nicht erstellt werden. Eine Verbindung ist nötig.',
			'recovery.fileName' => 'lunaway-sicherungskarte',
			'recovery.step1' => 'Erstellen Sie die Karte: Der Code wird nur einmal angezeigt.',
			'recovery.step2' => 'Speichern Sie das Bild, drucken Sie es aus oder schreiben Sie den Code von Hand ab.',
			'recovery.step3' => 'Bewahren Sie die Karte im Handschuhfach auf, bei den Fahrzeugpapieren.',
			'recover.title' => 'Mein Konto wiederherstellen',
			'recover.intro' => 'Geben Sie den Code Ihrer Sicherungskarte ein oder lesen Sie ihn von einem Foto der Karte ein.',
			'recover.field' => 'Sicherungscode',
			'recover.fieldHint' => '27 Zeichen, in Vierergruppen',
			'recover.remaining' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Noch ${n} Zeichen', other: 'Noch ${n} Zeichen', ), 
			'recover.invalid' => 'Dieser Code passt zu keiner Karte: Prüfen Sie jedes Zeichen.',
			'recover.valid' => 'Code vollständig',
			'recover.scan' => 'Karte von einem Foto einlesen',
			'recover.scanFile' => 'Bild der Karte auswählen',
			'recover.reading' => 'Karte wird gelesen',
			'recover.scanFailed' => 'Auf diesem Bild ist kein lesbarer Code. Versuchen Sie es mit einem schärferen Foto, auf dem die Karte flach liegt.',
			'recover.revoke' => 'Altes Gerät verloren oder gestohlen: dort abmelden',
			'recover.revokeHint' => 'Alle Ihre anderen Geräte werden abgemeldet.',
			'recover.submit' => 'Konto wiederherstellen',
			'recover.notFound' => 'Zu diesem Code gibt es kein Konto. Prüfen Sie die Karte oder erstellen Sie auf einem angemeldeten Gerät eine neue.',
			'recover.tooMany' => 'Vorerst zu viele Versuche. Versuchen Sie es in einer Stunde erneut.',
			'recover.done' => ({required Object name}) => 'Konto wiederhergestellt: ${name}',
			'deletion.title' => 'Mein Konto löschen',
			'deletion.intro' => 'Die Löschung erfolgt sofort und endgültig.',
			'deletion.goneTitle' => 'Was gelöscht wird',
			'deletion.gone.identity' => 'Ihr Pseudonym und die Schlüssel Ihrer Geräte',
			'deletion.gone.sessions' => 'Ihre Sitzungen und Ihr Sicherungscode',
			'deletion.gone.lists' => 'Ihre synchronisierten Favoritenlisten und Ihre ausgeblendeten Autoren',
			'deletion.gone.photos' => 'Ihre Fotos, Ihre Bewertungen ohne Text und Ihre Meldungen',
			'deletion.gone.pending' => 'Ihre Vorschläge, die noch auf Prüfung warten',
			'deletion.keptTitle' => 'Was ohne Ihren Namen bleibt',
			'deletion.kept' => 'Ihre veröffentlichten Rezensionen mit Text, Ihre Bestätigungen und Ihre bereits übernommenen Änderungen an Plätzen bleiben ohne Urheber erhalten, denn sie gehören zur Karte der anderen Reisenden.',
			'deletion.backups' => 'Die Sicherungen des Servers werden nach etwa 30 Tagen gelöscht.',
			'deletion.device' => 'Auf diesem Gerät bleiben Ihre Favoriten erhalten; der Schlüssel des Kontos wird gelöscht.',
			'deletion.web' => 'Sie können das Konto auch auf lunaway.net mit Ihrem Sicherungscode löschen.',
			'deletion.webLink' => 'lunaway.net/de/account/delete',
			'deletion.confirmTitle' => 'Endgültig löschen?',
			'deletion.confirmBody' => ({required Object name}) => 'Das Konto „${name}“ und alles oben Aufgeführte werden jetzt gelöscht. Niemand kann es wiederherstellen.',
			'deletion.confirmCheck' => 'Ich verstehe, dass dies endgültig ist',
			'deletion.confirm' => 'Konto löschen',
			'deletion.done' => 'Konto gelöscht',
			'deletion.failed' => 'Das Konto konnte nicht gelöscht werden. Eine Verbindung ist nötig.',
			'devices.title' => 'Geräte',
			'devices.intro' => 'Jedes Gerät hat seinen eigenen Schlüssel. Entfernen Sie ein verlorenes Gerät oder eines, das Sie nicht mehr nutzen.',
			'devices.thisDevice' => 'Dieses Gerät',
			'devices.other' => 'Anderes Gerät',
			'devices.added' => ({required Object date}) => 'Hinzugefügt am ${date}',
			'devices.lastUsed' => ({required Object when}) => 'Zuletzt genutzt: ${when}',
			'devices.revoke' => 'Entfernen',
			'devices.revokeTitle' => 'Dieses Gerät entfernen?',
			'devices.revokeBody' => 'Es wird abgemeldet und kann das Konto nicht mehr nutzen.',
			'devices.revoked' => 'Gerät entfernt',
			'devices.signOutOthers' => 'Alle anderen Geräte abmelden',
			'devices.signedOutOthers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, zero: 'Keine andere Sitzung offen', one: '${n} Sitzung beendet', other: '${n} Sitzungen beendet', ), 
			'devices.error' => 'Die Geräte konnten nicht geladen werden. Eine Verbindung ist nötig.',
			'muted.title' => 'Ausgeblendete Autoren',
			'muted.empty' => 'Niemand ist ausgeblendet',
			'muted.emptyHint' => 'Um jemanden auszublenden, öffnen Sie das Menü einer seiner Rezensionen oder eines seiner Fotos. Das Ausblenden gilt nur für Sie.',
			'muted.unmute' => 'Wieder anzeigen',
			'muted.unmuted' => ({required Object name}) => 'Beiträge von ${name} werden wieder angezeigt',
			'mine.title' => 'Meine Beiträge',
			'mine.pending' => 'Warten auf Versand',
			'mine.pendingHint' => 'Werden gesendet, sobald Sie wieder online sind.',
			'mine.sendNow' => 'Jetzt senden',
			'mine.retry' => 'Erneut versuchen',
			'mine.discard' => 'Verwerfen',
			'mine.discardTitle' => 'Diesen Beitrag verwerfen?',
			'mine.discardBody' => 'Er wird nicht gesendet.',
			'mine.reviews' => 'Rezensionen und Bewertungen',
			'mine.photos' => 'Fotos',
			'mine.confirmations' => 'Bestätigungen',
			'mine.issues' => 'Gemeldete Probleme',
			'mine.places' => 'Hinzugefügte Plätze und Änderungen',
			'mine.empty' => 'Noch nichts',
			'mine.emptyHint' => 'Einen Platz zu bewerten oder zu bestätigen, dass es ihn noch gibt, zählt schon als Beitrag.',
			'mine.latest' => ({required Object shown, required Object total}) => 'Die neuesten ${shown} von ${total}',
			'mine.error' => 'Ihre Beiträge konnten nicht geladen werden. Eine Verbindung ist nötig.',
			'mine.deleteTitle' => 'Diesen Beitrag löschen?',
			'mine.deleteBody' => 'Er wird aus Lunaway entfernt.',
			'mine.deleteApplied' => 'Dieser Platz ist bereits Teil der Karte: Er bleibt dort, ohne Ihren Namen.',
			'mine.deleted' => 'Beitrag gelöscht',
			'mine.ratingOnly' => 'Nur Bewertung',
			'mine.status.published' => 'Veröffentlicht',
			'mine.status.pending' => 'In Prüfung',
			'mine.status.hidden' => 'Nach Meldungen ausgeblendet',
			'mine.status.removed' => 'Von der Moderation entfernt',
			'mine.submission.proposed' => 'Wartet auf Prüfung',
			'mine.submission.accepted' => 'Angenommen',
			'mine.submission.applied' => 'Auf der Karte',
			'mine.submission.rejected' => 'Abgelehnt',
			'mine.submission.withdrawn' => 'Zurückgezogen',
			'mine.newPlace' => 'Neuer Platz',
			'mine.edit' => 'Änderung',
			'mine.aPlace' => 'Ein Platz',
			'mine.newVendingMachine' => 'Neuer Automat',
			'mine.poiConfirmations' => 'Bestätigte Geschäfte und Dienstleistungen',
			'mine.aPoi' => 'Ein Geschäft oder eine Dienstleistung',
			'outbox.kind.rate' => ({required Object stars}) => 'Bewertung: ${stars} von 5 Sternen',
			'outbox.kind.review' => 'Rezension',
			'outbox.kind.deleteReview' => 'Löschen einer Rezension',
			'outbox.kind.confirm' => ({required Object status}) => 'Noch da? ${status}',
			'outbox.kind.deleteConfirmation' => 'Löschen einer Bestätigung',
			'outbox.kind.reportIssue' => ({required Object kind}) => 'Gemeldetes Problem: ${kind}',
			'outbox.kind.deleteIssueReport' => 'Löschen einer Meldung',
			'outbox.kind.reportContent' => 'Meldung an die Moderation',
			'outbox.kind.addPlace' => ({required Object name}) => 'Neuer Platz: ${name}',
			'outbox.kind.editPlace' => 'Änderung an einem Platz',
			'outbox.kind.deletePlaceSubmission' => 'Zurückziehen eines vorgeschlagenen Platzes',
			'outbox.kind.photo' => 'Foto',
			'outbox.kind.deletePhoto' => 'Löschen eines Fotos',
			'outbox.kind.mute' => 'Autor ausblenden',
			'outbox.kind.unmute' => 'Autor wieder anzeigen',
			'outbox.kind.poiThere' => 'Noch da: ein Geschäft oder eine Dienstleistung',
			'outbox.kind.poiGone' => 'Nicht mehr da: ein Geschäft oder eine Dienstleistung',
			'outbox.kind.addVendingMachine' => 'Neuer Automat',
			'outbox.kind.deletePoiConfirmation' => 'Löschen einer Antwort zu einem Geschäft oder einer Dienstleistung',
			'outbox.kind.reportRoadEvent' => ({required Object kind}) => 'Straßenmeldung: ${kind}',
			'outbox.kind.clearRoadEvent' => 'Ende einer Straßenmeldung',
			'outbox.waiting' => 'Wartet auf das Netz',
			'outbox.sending' => 'Wird gesendet',
			'outbox.error.forbidden' => 'Abgelehnt: Ihre Stufe erlaubt das noch nicht.',
			'outbox.error.notFound' => 'Abgelehnt: Der Platz oder der Inhalt existiert nicht mehr.',
			'outbox.error.invalid' => 'Abgelehnt: Prüfen Sie den Text (Länge, Links, Kontaktdaten).',
			'outbox.error.unreadablePhoto' => 'Foto abgelehnt: unlesbar oder schon gesendet.',
			'outbox.error.photoTooLarge' => 'Foto abgelehnt: zu groß.',
			'outbox.error.placeRefused' => 'Der neue Platz zu diesem Foto wurde abgelehnt.',
			'outbox.error.fileLost' => 'Das Foto ist nicht mehr auf dem Gerät.',
			'outbox.error.otherAccount' => 'Für ein anderes Konto vorbereitet: wird nicht gesendet.',
			'outbox.error.other' => 'Vom Server abgelehnt.',
			'outbox.error.duplicate' => 'Abgelehnt: Derselbe Automat ist schon im Umkreis von 25 m eingetragen.',
			'outbox.sent' => 'Danke, gesendet',
			'outbox.queued' => 'Keine Verbindung: wird gesendet, sobald Sie wieder online sind',
			'outbox.refused' => ({required Object reason}) => 'Nicht gesendet. ${reason}',
			'placement.title' => 'Stelle festlegen',
			'placement.hint' => 'Verschieben Sie die Karte: Das Fadenkreuz markiert die genaue Stelle.',
			'placement.confirm' => 'Diese Stelle verwenden',
			'placement.duplicate' => ({required Object name, required Object distance}) => '„${name}“ liegt nur ${distance} entfernt: Ist das derselbe Platz?',
			'placement.same' => 'Ja, Platzseite öffnen',
			'placement.notSame' => 'Nein, das ist ein anderer Platz',
			'contribute.yourRating' => 'Ihre Bewertung',
			'contribute.rateHint' => 'Wählen Sie 1 bis 5 Sterne',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Mit ${n} Stern bewerten', other: 'Mit ${n} Sternen bewerten', ), 
			'contribute.writeReview' => 'Rezension schreiben',
			'contribute.editReview' => 'Ihre Rezension bearbeiten',
			'contribute.deleteReview' => 'Ihre Rezension löschen',
			'contribute.deleteReviewTitle' => 'Ihre Rezension löschen?',
			'contribute.deleteReviewBody' => 'Text und Bewertung werden von der Platzseite entfernt.',
			'contribute.deleteRating' => 'Ihre Bewertung entfernen',
			'contribute.deleteRatingTitle' => 'Ihre Bewertung entfernen?',
			'contribute.deleteRatingBody' => 'Ihre Bewertung wird von der Platzseite entfernt.',
			'contribute.pendingSend' => 'Wartet auf Versand',
			'contribute.statusPending' => 'In Prüfung: vorerst nur für Sie sichtbar',
			'contribute.statusHidden' => 'Nach Meldungen ausgeblendet, wartet auf die Moderation',
			'contribute.statusRemoved' => 'Von der Moderation entfernt',
			'contribute.addPhoto' => 'Foto hinzufügen',
			'contribute.firstPhoto' => 'Erstes Foto hinzufügen',
			'contribute.stillThere' => 'Noch da?',
			'contribute.more' => 'Weitere Aktionen',
			'contribute.reportIssue' => 'Problem melden',
			'contribute.proposeEdit' => 'Änderung vorschlagen',
			'contribute.editPlace' => 'Platz bearbeiten',
			'contribute.reportPlace' => 'Diesen Platz der Moderation melden',
			'contribute.toVerifyTitle' => 'Zu prüfen',
			'contribute.toVerifyBody' => 'Von der Community hinzugefügt, wartet auf zwei Bestätigungen. Kennen Sie den Platz? Dann bestätigen Sie ihn.',
			'contribute.issuesTitle' => 'Meldungen der letzten 30 Tage',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlaceHere' => 'Hier einen Platz hinzufügen',
			'contribute.addPlaceHint' => 'Die Stelle unter dem Fadenkreuz.',
			'confirmSheet.title' => 'Noch da?',
			'confirmSheet.body' => 'Waren Sie kürzlich dort? Ihre Antwort zeigt den nächsten Reisenden, dass die Platzseite aktuell ist. Es wird kein Standort gesendet.',
			'confirmSheet.stillOk' => 'Ja, wie beschrieben',
			'confirmSheet.closed' => 'Geschlossen',
			'confirmSheet.changed' => 'Verändert',
			'confirmSheet.closedHint' => 'Nimmt keine Reisenden mehr auf',
			'confirmSheet.changedHint' => 'Noch da, aber etwas hat sich geändert',
			'confirmSheet.note' => 'Etwas hinzuzufügen? (optional)',
			'confirmSheet.noteHint' => 'Zum Beispiel: Höhenbegrenzung angebracht, V/E-Säule versetzt',
			'confirmSheet.status.stillOk' => 'Noch da',
			'confirmSheet.status.closed' => 'Geschlossen',
			'confirmSheet.status.changed' => 'Verändert',
			'issueSheet.title' => 'Problem melden',
			'issueSheet.body' => 'Ihre Meldung fließt in die Warnung auf der Platzseite ein. Ihre Anmerkung sieht nur die Moderation.',
			'issueSheet.kind.nightBan' => 'Übernachten jetzt verboten',
			'issueSheet.kind.serviceBroken' => 'Ausstattung defekt',
			'issueSheet.kind.noAccess' => 'Keine Zufahrt',
			'issueSheet.kind.danger' => 'Gefahr',
			'issueSheet.hint.nightBan' => 'Ein Schild, eine Gemeindeverordnung, eine Polizeikontrolle',
			'issueSheet.hint.serviceBroken' => 'V/E-Säule, Wasser, Entsorgung oder Strom außer Betrieb',
			'issueSheet.hint.noAccess' => 'Eine Schranke, eine Baustelle, eine gesperrte Straße',
			'issueSheet.hint.danger' => 'Diebstahl, Überfall, instabiler Untergrund',
			'issueSheet.note' => 'Etwas hinzuzufügen? (optional)',
			'issueSheet.send' => 'Melden',
			'reportSheet.review' => 'Diese Rezension melden',
			'reportSheet.photo' => 'Dieses Foto melden',
			'reportSheet.place' => 'Diesen Platz melden',
			'reportSheet.body' => 'Die Moderation sieht sich das an. Der Autor erfährt nicht, wer es gemeldet hat.',
			'reportSheet.reason.spam' => 'Werbung oder Spam',
			'reportSheet.reason.offensive' => 'Beleidigend, hasserfüllt oder anstößig',
			'reportSheet.reason.wrong' => 'Falsch oder irreführend',
			'reportSheet.reason.privacy' => 'Zeigt oder nennt eine Person, ein Kennzeichen, eine Privatadresse',
			'reportSheet.reason.other' => 'Anderer Grund',
			'reportSheet.note' => 'Mehr dazu (optional)',
			'reportSheet.noteOther' => 'Beschreiben Sie, was nicht stimmt',
			'reportSheet.sent' => 'Danke, die Moderation sieht es sich an',
			'reportSheet.mute' => ({required Object name}) => 'Rezensionen und Fotos von ${name} ausblenden',
			'reportSheet.muteAuthor' => 'Diesen Autor ausblenden',
			'reportSheet.muteTitle' => ({required Object name}) => '${name} ausblenden?',
			'reportSheet.muteBody' => 'Die Rezensionen und Fotos dieser Person werden Ihnen nicht mehr angezeigt. Sie können das im Profil rückgängig machen.',
			'reportSheet.muted' => ({required Object name}) => '${name} ist ausgeblendet',
			'reportSheet.deletePhoto' => 'Mein Foto löschen',
			'reportSheet.deletePhotoTitle' => 'Dieses Foto löschen?',
			'reportSheet.deletePhotoBody' => 'Es wird von der Platzseite und von unseren Servern entfernt.',
			'reviewSheet.titleNew' => 'Ihre Rezension',
			'reviewSheet.titleEdit' => 'Ihre Rezension bearbeiten',
			'reviewSheet.starsRequired' => 'Wählen Sie eine Bewertung von 1 bis 5',
			'reviewSheet.text' => 'Ihre Rezension',
			'reviewSheet.textHint' => 'Die Ruhe, der Empfang, der Platz zum Rangieren, was Ihnen geholfen hat',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Noch mindestens ${n} Zeichen', other: 'Noch mindestens ${n} Zeichen', ), 
			'reviewSheet.visited' => 'Datum des Aufenthalts',
			'reviewSheet.visitedNone' => 'Keine Angabe',
			'reviewSheet.vehicle' => 'Ihr Fahrzeug',
			'reviewSheet.vehicleNone' => 'Keine Angabe',
			'reviewSheet.licence' => 'Veröffentlicht unter CC BY 4.0, mit Ihrem Pseudonym. Das Datum des Aufenthalts ist optional: Zusammengenommen können die Daten Ihrer Rezensionen Ihre Reiseroute verraten.',
			'reviewSheet.publish' => 'Rezension veröffentlichen',
			'gate.review' => 'Rezensionen mit Text: ab Stufe 1',
			'gate.photo' => 'Fotos: ab Stufe 1',
			'gate.addPlace' => 'Plätze hinzufügen: ab Stufe 2',
			'gate.edit' => 'Änderungen vorschlagen: ab Stufe 1',
			'gate.why' => 'Die Stufen schützen die Karte vor Missbrauch. Höhere Stufen erreichen Sie mit der Zeit und durch Beiträge, kaufen lassen sie sich nicht.',
			'gate.yourLevel' => ({required Object level}) => 'Ihre Stufe: ${level}',
			'gate.noAccount' => 'Noch kein Konto: Ein Konto beginnt mit Stufe 0.',
			'gate.later' => ({required Object level}) => 'Stufe ${level} erreichen Sie nach den vorherigen Stufen, mit der Zeit und durch veröffentlichte Beiträge.',
			'gate.meanwhile' => 'Bis dahin können Sie Plätze bewerten, bestätigen, dass es sie noch gibt, oder ein Problem melden.',
			'photoFlow.title' => 'Foto hinzufügen',
			'photoFlow.camera' => 'Foto aufnehmen',
			'photoFlow.gallery' => 'Aus der Galerie wählen',
			'photoFlow.preparing' => 'Foto wird vorbereitet',
			'photoFlow.licence' => 'Veröffentlicht unter CC BY 4.0, mit Ihrem Pseudonym. Vermeiden Sie Gesichter und Kennzeichen.',
			'photoFlow.stripped' => 'Standort- und Gerätedaten werden vor dem Senden entfernt.',
			'photoFlow.send' => 'Foto senden',
			'photoFlow.unreadable' => 'Dieses Bild kann auf diesem Gerät nicht gelesen werden. Versuchen Sie es mit einem JPEG- oder PNG-Foto.',
			'photoFlow.sending' => ({required Object percent}) => 'Wird gesendet: ${percent} %',
			'photoFlow.pending' => 'Foto wartet auf Versand',
			'placeForm.addTitle' => 'Platz hinzufügen',
			'placeForm.editTitle' => 'Platz bearbeiten',
			'placeForm.proposeTitle' => 'Änderung vorschlagen',
			'placeForm.position' => 'Position auf der Karte',
			'placeForm.kind' => 'Art des Platzes',
			'placeForm.kindRequired' => 'Wählen Sie eine Art',
			'placeForm.name' => 'Name',
			'placeForm.nameHint' => 'Der Name vor Ort oder eine kurze Beschreibung',
			'placeForm.nameInvalid' => '2 bis 120 Zeichen',
			'placeForm.night' => 'Übernachtung',
			'placeForm.services' => 'Ausstattung vor Ort',
			'placeForm.description' => 'Beschreibung',
			'placeForm.descriptionHint' => 'Was hilft, den Platz zu finden und auszuwählen',
			'placeForm.details' => 'Details',
			'placeForm.priceNight' => 'Preis pro Nacht (€)',
			'placeForm.priceServices' => 'Preis für Ver- und Entsorgung (€)',
			'placeForm.maxHeight' => 'Maximale Höhe (m)',
			'placeForm.capacity' => 'Anzahl Stellplätze',
			'placeForm.website' => 'Website',
			'placeForm.phone' => 'Telefon',
			'placeForm.photo' => 'Foto (optional)',
			'placeForm.photoReady' => 'Foto bereit',
			'placeForm.removePhoto' => 'Foto entfernen',
			'placeForm.toVerify' => 'Der Platz erscheint als „zu prüfen“, bis zwei andere Reisende ihn bestätigen.',
			'placeForm.licence' => 'Plätze werden unter der ODbL veröffentlicht, mit Nennung der Lunaway-Mitwirkenden.',
			'placeForm.moderated' => 'Eine Website oder Telefonnummer wird vor der Veröffentlichung von der Moderation geprüft.',
			'placeForm.direct' => 'Mit Ihrer Stufe gilt die Änderung sofort.',
			'placeForm.proposal' => 'Die Moderation prüft Ihren Vorschlag, bevor er übernommen wird.',
			'placeForm.submitAdd' => 'Platz hinzufügen',
			'placeForm.submitEdit' => 'Änderung speichern',
			'placeForm.submitPropose' => 'Vorschlag senden',
			'placeForm.nothingChanged' => 'Nichts geändert',
			'placeForm.invalidNumber' => 'Bitte eine Zahl eingeben',
			'placeForm.invalidWebsite' => 'Eine Adresse, die mit http:// oder https:// beginnt',
			'placeForm.added' => 'Danke: Der Platz erscheint gleich auf der Karte',
			'placeForm.proposed' => 'Danke: Ihr Vorschlag geht in die Prüfung',
			'favoritesSync.local' => 'Nur auf diesem Gerät',
			'favoritesSync.action' => 'Synchronisieren',
			'favoritesSync.syncing' => 'Wird synchronisiert',
			'favoritesSync.synced' => ({required Object when}) => 'Mit Ihrem Konto gespeichert, zuletzt synchronisiert ${when}',
			'favoritesSync.failed' => 'Synchronisierung gerade nicht möglich',
			'favoritesSync.title' => 'Ihre Favoriten synchronisieren?',
			'favoritesSync.body' => 'Ihre Listen werden samt den darin gespeicherten Adressen und Notizen mit einem Lunaway-Konto gespeichert, ohne E-Mail und ohne Passwort, damit Sie sie auf einem anderen Gerät wiederfinden. Das Konto wird jetzt angelegt.',
			'favoritesSync.confirm' => 'Konto anlegen und synchronisieren',
			'poi.category.groceries' => 'Einkaufen',
			'poi.category.vending' => 'Lebensmittelautomaten',
			'poi.category.water' => 'Wasser und Entsorgung',
			'poi.category.fuel' => 'Kraftstoff und Energie',
			'poi.category.health' => 'Gesundheit',
			'poi.category.services' => 'Dienstleistungen',
			'poi.category.food' => 'Restaurants und Cafés',
			'poi.category.sights' => 'Sehenswertes',
			'poi.category.shopping' => 'Geschäfte',
			'poi.category.lodging' => 'Unterkünfte',
			'poi.category.leisure' => 'Freizeit',
			'poi.kind.supermarket' => 'Supermarkt',
			'poi.kind.convenience' => 'Lebensmittelladen',
			'poi.kind.bakery' => 'Bäckerei',
			'poi.kind.butcher' => 'Metzgerei',
			'poi.kind.greengrocer' => 'Obst und Gemüse',
			'poi.kind.farmShop' => 'Hofladen',
			'poi.kind.marketplace' => 'Markt',
			'poi.kind.vendingPizza' => 'Pizzaautomat',
			'poi.kind.vendingBread' => 'Brotautomat',
			'poi.kind.vendingFarmProducts' => 'Automat mit Hofprodukten',
			'poi.kind.vendingEggsMilk' => 'Eier- oder Milchautomat',
			'poi.kind.vendingIce' => 'Eiswürfelautomat',
			'poi.kind.vendingOther' => 'Lebensmittelautomat',
			'poi.kind.drinkingWater' => 'Trinkwasser',
			'poi.kind.waterPoint' => 'Wasserstelle',
			'poi.kind.dumpStation' => 'Entsorgungsstation',
			'poi.kind.toilets' => 'Toiletten',
			'poi.kind.shower' => 'Duschen',
			'poi.kind.fuelStation' => 'Tankstelle',
			'poi.kind.evCharging' => 'Ladestation',
			'poi.kind.gasBottles' => 'Gasflaschen',
			'poi.kind.pharmacy' => 'Apotheke',
			'poi.kind.doctor' => 'Arzt',
			'poi.kind.hospital' => 'Krankenhaus',
			'poi.kind.veterinary' => 'Tierarzt',
			'poi.kind.laundry' => 'Waschsalon',
			'poi.kind.atm' => 'Geldautomat',
			'poi.kind.postOffice' => 'Postfiliale',
			'poi.kind.touristOffice' => 'Touristeninformation',
			'poi.kind.recyclingCentre' => 'Wertstoffhof',
			'poi.kind.carRepair' => 'Autowerkstatt',
			'poi.kind.carWash' => 'Waschanlage',
			'poi.kind.motorhomeShop' => 'Wohnmobilhändler und Werkstatt',
			'poi.kind.outdoorShop' => 'Camping- und Outdoorladen',
			'poi.kind.restaurant' => 'Restaurant',
			'poi.kind.cafe' => 'Café',
			'poi.kind.fastFood' => 'Imbiss',
			'poi.kind.viewpoint' => 'Aussichtspunkt',
			'poi.kind.attraction' => 'Sehenswürdigkeit',
			'poi.kind.museum' => 'Museum',
			'poi.kind.bar' => 'Bar',
			'poi.kind.pub' => 'Kneipe',
			'poi.kind.iceCream' => 'Eisdiele',
			'poi.kind.deli' => 'Feinkost',
			'poi.kind.cheese' => 'Käseladen',
			'poi.kind.seafood' => 'Fischgeschäft',
			'poi.kind.pastry' => 'Konditorei',
			'poi.kind.confectionery' => 'Süßwaren',
			'poi.kind.wineShop' => 'Weinhandlung',
			'poi.kind.beverages' => 'Getränkemarkt',
			'poi.kind.teaCoffee' => 'Tee und Kaffee',
			'poi.kind.organicShop' => 'Bioladen',
			'poi.kind.frozenFood' => 'Tiefkühlkost',
			'poi.kind.winery' => 'Weingut',
			'poi.kind.brewery' => 'Brauerei',
			'poi.kind.distillery' => 'Brennerei',
			'poi.kind.beekeeper' => 'Imkerei',
			'poi.kind.dentist' => 'Zahnarzt',
			'poi.kind.clinic' => 'Klinik',
			'poi.kind.physiotherapist' => 'Physiotherapie',
			'poi.kind.laboratory' => 'Labor',
			'poi.kind.nurse' => 'Pflegedienst',
			'poi.kind.midwife' => 'Hebamme',
			'poi.kind.podiatrist' => 'Podologie',
			'poi.kind.psychologist' => 'Psychotherapie',
			'poi.kind.speechTherapist' => 'Logopädie',
			'poi.kind.alternativeMedicine' => 'Osteopathie, Naturheilkunde',
			'poi.kind.optician' => 'Optiker',
			'poi.kind.hearingAids' => 'Hörakustik',
			'poi.kind.medicalSupply' => 'Sanitätshaus',
			'poi.kind.hairdresser' => 'Friseur',
			'poi.kind.beauty' => 'Kosmetikstudio',
			'poi.kind.massage' => 'Massage',
			'poi.kind.tattoo' => 'Tattoostudio',
			'poi.kind.bank' => 'Bank',
			'poi.kind.moneyExchange' => 'Wechselstube',
			'poi.kind.carRental' => 'Autovermietung',
			'poi.kind.bicycleRental' => 'Fahrradverleih',
			'poi.kind.boatRental' => 'Bootsverleih',
			'poi.kind.vehicleInspection' => 'TÜV, Prüfstelle',
			'poi.kind.drivingSchool' => 'Fahrschule',
			'poi.kind.dryCleaning' => 'Reinigung',
			'poi.kind.tailor' => 'Schneiderei',
			'poi.kind.shoeRepair' => 'Schuhmacher',
			'poi.kind.locksmith' => 'Schlüsseldienst',
			'poi.kind.copyshop' => 'Copyshop',
			'poi.kind.photographer' => 'Fotograf',
			'poi.kind.travelAgency' => 'Reisebüro',
			'poi.kind.estateAgent' => 'Immobilienmakler',
			'poi.kind.insurance' => 'Versicherung',
			'poi.kind.funeralDirectors' => 'Bestattungen',
			'poi.kind.petGrooming' => 'Hundesalon',
			'poi.kind.tyres' => 'Reifenhandel',
			'poi.kind.carParts' => 'Autoteile',
			'poi.kind.carDealer' => 'Autohaus',
			'poi.kind.motorcycleShop' => 'Motorradhändler',
			'poi.kind.repairShop' => 'Reparaturdienst',
			'poi.kind.internetCafe' => 'Internetcafé',
			'poi.kind.coworking' => 'Coworking-Space',
			'poi.kind.townhall' => 'Rathaus',
			'poi.kind.police' => 'Polizei',
			'poi.kind.library' => 'Bibliothek',
			'poi.kind.rental' => 'Verleih',
			'poi.kind.storageRental' => 'Lagerraum',
			'poi.kind.animalBoarding' => 'Tierpension',
			'poi.kind.ferryTerminal' => 'Fähranleger',
			'poi.kind.clothes' => 'Bekleidung',
			'poi.kind.shoes' => 'Schuhe',
			'poi.kind.accessories' => 'Lederwaren, Accessoires',
			'poi.kind.jewellery' => 'Schmuck',
			'poi.kind.books' => 'Buchhandlung',
			'poi.kind.newsagent' => 'Zeitschriften, Kiosk',
			'poi.kind.tobacco' => 'Tabakwaren',
			'poi.kind.stationery' => 'Schreibwaren',
			'poi.kind.gift' => 'Geschenke, Souvenirs',
			'poi.kind.toys' => 'Spielwaren',
			'poi.kind.sports' => 'Sportgeschäft',
			'poi.kind.fishingHunting' => 'Angeln und Jagd',
			'poi.kind.bicycleShop' => 'Fahrradladen',
			'poi.kind.boatShop' => 'Bootshandel',
			'poi.kind.florist' => 'Blumenladen',
			'poi.kind.gardenCentre' => 'Gartencenter',
			'poi.kind.hardware' => 'Baumarkt',
			'poi.kind.home' => 'Einrichtung, Möbel',
			'poi.kind.electronics' => 'Elektronik, Handys',
			'poi.kind.cosmetics' => 'Drogerie, Parfümerie',
			'poi.kind.departmentStore' => 'Kaufhaus, Einkaufszentrum',
			'poi.kind.varietyStore' => 'Sonderpostenmarkt',
			'poi.kind.secondHand' => 'Second Hand, Antiquitäten',
			'poi.kind.artShop' => 'Kunst und Basteln',
			'poi.kind.musicShop' => 'Musikgeschäft',
			'poi.kind.petShop' => 'Zoohandlung',
			'poi.kind.babyGoods' => 'Babyausstattung',
			'poi.kind.fabric' => 'Stoffe, Kurzwaren',
			'poi.kind.craft' => 'Handwerk',
			'poi.kind.shop' => 'Geschäft',
			'poi.kind.hotel' => 'Hotel',
			'poi.kind.guestHouse' => 'Pension',
			'poi.kind.hostel' => 'Hostel',
			'poi.kind.holidayRental' => 'Ferienwohnung',
			'poi.kind.mountainHut' => 'Berghütte',
			'poi.kind.cinema' => 'Kino',
			'poi.kind.theatre' => 'Theater',
			'poi.kind.eventsVenue' => 'Veranstaltungsort',
			'poi.kind.artsCentre' => 'Kulturzentrum',
			'poi.kind.nightclub' => 'Diskothek',
			'poi.kind.casino' => 'Spielbank',
			'poi.kind.sportsCentre' => 'Sportzentrum',
			'poi.kind.fitnessCentre' => 'Fitnessstudio',
			'poi.kind.swimmingPool' => 'Schwimmbad',
			'poi.kind.waterPark' => 'Erlebnisbad',
			'poi.kind.golfCourse' => 'Golfplatz',
			'poi.kind.miniatureGolf' => 'Minigolf',
			'poi.kind.marina' => 'Jachthafen',
			'poi.kind.horseRiding' => 'Reitstall',
			_ => null,
		} ?? switch (path) {
			'poi.kind.bowlingAlley' => 'Bowling',
			'poi.kind.escapeGame' => 'Escape Room',
			'poi.kind.amusementArcade' => 'Spielhalle',
			'poi.kind.iceRink' => 'Eisbahn',
			'poi.kind.spa' => 'Sauna, Therme',
			'poi.kind.dance' => 'Tanzschule',
			'poi.kind.park' => 'Park',
			'poi.kind.natureReserve' => 'Naturschutzgebiet',
			'poi.kind.gallery' => 'Galerie',
			'poi.kind.zoo' => 'Zoo, Aquarium',
			'poi.kind.themePark' => 'Freizeitpark',
			'poi.chipsLabel' => 'Geschäfte und Dienstleistungen in der Nähe',
			'poi.openNow' => 'Jetzt geöffnet',
			'poi.vendingSells.pizza' => 'Pizza',
			'poi.vendingSells.bread' => 'Brot',
			'poi.vendingSells.farmProducts' => 'Hofprodukte',
			'poi.vendingSells.eggsMilk' => 'Eier und Milch',
			'poi.vendingSells.ice' => 'Eiswürfel',
			'poi.vendingAll' => 'Alle Lebensmittelautomaten',
			'poi.vendingMenu' => 'Was die Automaten verkaufen',
			'poi.vendingChip.pizza' => 'Pizzaautomaten',
			'poi.vendingChip.bread' => 'Brotautomaten',
			'poi.vendingChip.farmProducts' => 'Automaten mit Hofprodukten',
			'poi.vendingChip.eggsMilk' => 'Eier- und Milchautomaten',
			'poi.vendingChip.ice' => 'Eiswürfelautomaten',
			'poi.alwaysOpen' => 'Tag und Nacht geöffnet',
			'poi.hoursUnknown' => 'Öffnungszeiten unbekannt',
			'poi.maybeClosed' => 'Laut dem offiziellen Verzeichnis der Einrichtungen des Gesundheitswesens (FINESS) geschlossen.',
			'poi.maybeClosedSince' => ({required Object date}) => 'Bei FINESS seit ${date} als geschlossen geführt: Möglicherweise ist die Einrichtung endgültig geschlossen.',
			'poi.seasonal' => 'Saisonal: im Winter möglicherweise geschlossen.',
			'poi.fee' => 'Kostenpflichtig',
			'poi.free' => 'Kostenlos',
			'poi.stillThereTitle' => 'Noch da?',
			'poi.stillThereHint' => 'Kürzlich gesehen? Ihre Antwort hilft den nächsten Reisenden. Es wird kein Standort gesendet.',
			'poi.stillThere' => 'Noch da',
			'poi.gone' => 'Nicht mehr da',
			'poi.lastConfirmed' => ({required Object when}) => 'Als vorhanden bestätigt: ${when}',
			'poi.checkedOn' => ({required Object date}) => 'Vor Ort geprüft am ${date}',
			'poi.thanksThere' => 'Danke, notiert: noch da.',
			'poi.thanksGone' => 'Danke, notiert: nicht mehr da.',
			'poi.fuelPrices' => 'Kraftstoffpreise',
			'poi.perLitre' => ({required Object price}) => '${price}/l',
			'poi.priceUpdated' => ({required Object when}) => 'Preis aktualisiert: ${when}',
			'poi.feedRead' => ({required Object when}) => 'Preise abgerufen: ${when}',
			'poi.shortageTemporary' => 'Vorübergehend nicht verfügbar',
			'poi.shortageDefinitive' => 'Nicht mehr im Angebot',
			'poi.selfService24h' => '24-Stunden-Tankautomat',
			'poi.highway' => 'An der Autobahn',
			'poi.lpgYes' => 'Autogas (LPG) erhältlich',
			'poi.fuel.diesel' => 'Diesel',
			'poi.fuel.sp95' => 'Super 95',
			'poi.fuel.e10' => 'Super E10',
			'poi.fuel.sp98' => 'Super Plus 98',
			'poi.fuel.e85' => 'E85',
			'poi.fuel.lpg' => 'Autogas (LPG)',
			'poi.products' => 'Angebot',
			'poi.paymentTitle' => 'Bezahlung',
			'poi.product.pizza' => 'Pizza',
			'poi.product.bread' => 'Brot',
			'poi.product.eggs' => 'Eier',
			'poi.product.milk' => 'Milch',
			'poi.product.cheese' => 'Käse',
			'poi.product.meat' => 'Fleisch',
			'poi.product.vegetables' => 'Gemüse',
			'poi.product.fruit' => 'Obst',
			'poi.product.honey' => 'Honig',
			'poi.product.ice' => 'Eiswürfel',
			'poi.product.potatoes' => 'Kartoffeln',
			'poi.product.food' => 'Lebensmittel',
			'poi.payment.cash' => 'Bargeld',
			'poi.payment.coins' => 'Münzen',
			'poi.payment.notes' => 'Scheine',
			'poi.payment.cards' => 'Karte',
			'poi.payment.contactless' => 'Kontaktlos',
			'poi.payment.app' => 'Handy-App',
			'poi.justNow' => 'gerade eben',
			'poi.minutesAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'vor ${n} Minute', other: 'vor ${n} Minuten', ), 
			'poi.hoursAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'vor ${n} Stunde', other: 'vor ${n} Stunden', ), 
			'poi.readOffline' => ({required Object when}) => 'Stand ${when}: kein Netz zum Aktualisieren',
			'poi.readStale' => ({required Object when}) => 'Stand ${when}: Die Aktualisierung hat gerade nicht geklappt.',
			'poi.goneTitle' => 'Dieser Punkt ist nicht mehr auf der Karte',
			'poi.goneHint' => 'Reisende haben gemeldet, dass es ihn nicht mehr gibt, oder die letzte Aktualisierung hat ihn entfernt.',
			'poi.loadError' => 'Die Details konnten nicht geladen werden. Was die Karte darüber weiß, steht oben.',
			'poi.around' => 'Rund um diesen Platz',
			'poi.aroundEmpty' => 'Keine Geschäfte oder Dienstleistungen in der Nähe bekannt.',
			'poi.aroundError' => 'Die Geschäfte und Dienstleistungen in der Nähe konnten nicht geladen werden.',
			'poi.aroundOffline' => 'Keine Verbindung: Die Geschäfte und Dienstleistungen in der Nähe erscheinen, sobald Sie online sind.',
			'poi.onSite' => 'Vor Ort',
			'poi.backTo' => ({required Object name}) => 'Zurück zu ${name}',
			'poi.backToPlace' => 'Zurück zum Platz',
			'poi.linkError' => 'Dieser Eintrag ließ sich nicht öffnen: kein Netz, oder er ist nicht mehr auf der Karte.',
			'poi.searchSection' => 'Geschäfte und Dienstleistungen',
			'poi.searching' => 'Geschäfte und Dienstleistungen werden gesucht',
			'poi.searchOffline' => 'Geschäfte und Dienstleistungen werden online gesucht: Gerade gibt es kein Netz.',
			'poi.add.title' => 'Hier ein Automat?',
			'poi.add.hint' => 'Wählen Sie, was er verkauft: Er erscheint dann für alle Reisenden auf der Karte.',
			'poi.add.pizza' => 'Pizza',
			'poi.add.bread' => 'Brot',
			'poi.add.other' => 'Andere Lebensmittel',
			'poi.add.gate' => 'Automaten hinzufügen',
			'poi.add.sent' => 'Danke: Der Automat erscheint in wenigen Minuten auf der Karte.',
			'poi.add.duplicateTitle' => 'Schon auf der Karte',
			'poi.add.duplicateBody' => 'Ein Automat derselben Art ist schon im Umkreis von 25 m eingetragen. Ist er noch da?',
			'poi.add.duplicateThere' => 'Ja, noch da',
			'poi.add.duplicateGone' => 'Nein, nicht mehr da',
			'poi.cheapest.title' => 'Am günstigsten in meiner Nähe',
			'poi.cheapest.show' => 'Günstigste Preise',
			'poi.cheapest.zoomIn' => 'Zoomen Sie heran, um die Preise der Tankstellen zu vergleichen.',
			'poi.cheapest.none' => 'Keine Tankstelle auf der Karte verkauft diesen Kraftstoff.',
			'poi.cheapest.noneHint' => 'Verschieben Sie die Karte oder wählen Sie einen anderen Kraftstoff.',
			'poi.cheapest.error' => 'Die Preise der Tankstellen konnten nicht geladen werden.',
			'poi.trend.title' => ({required Object fuel}) => '${fuel}: Preise der letzten Tage',
			'poi.trend.none' => 'Lunaway hat hier noch keinen Preis für diesen Kraftstoff gesehen.',
			'poi.trend.failed' => 'Die Preise der letzten Tage konnten gerade nicht geladen werden.',
			'poi.trend.week' => 'Letzte 7 Tage:',
			'poi.trend.month' => 'Letzte 30 Tage:',
			'poi.trend.range' => ({required Object low, required Object high}) => 'von ${low} bis ${high}',
			'poi.trend.span' => ({required Object range, required Object move}) => '${range}, ${move}',
			'poi.trend.oneDay' => 'nur ein Tag erfasst',
			'poi.trend.steady' => 'unverändert',
			'poi.trend.down' => ({required Object amount}) => 'um ${amount} gesunken',
			'poi.trend.up' => ({required Object amount}) => 'um ${amount} gestiegen',
			'poi.trend.since' => ({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Tag erfasst seit dem ${date} (laut Datenfeed); Tage ohne Erfassung bleiben leer', other: '${n} Tage erfasst seit dem ${date} (laut Datenfeed); Tage ohne Erfassung bleiben leer', ), 
			'poi.marketDays' => 'Markttage',
			'poi.vehicles.motorhomeYes' => 'Für Wohnmobile',
			'poi.vehicles.motorhomeNo' => 'Keine Wohnmobile',
			'poi.vehicles.hgvYes' => 'Für Lkw',
			'poi.vehicles.hgvNo' => 'Keine Lkw',
			'poi.vehicles.maxHeight' => ({required Object height}) => 'Maximale Höhe: ${height}',
			'poi.searchKindNear' => ({required Object what}) => '${what} in der Nähe',
			'poi.searchKindIn' => ({required Object what, required Object town}) => '${what} in ${town}',
			'poi.cuisine.pizza' => 'Pizza',
			'poi.cuisine.italian' => 'Italienisch',
			'poi.cuisine.french' => 'Französisch',
			'poi.cuisine.regional' => 'Regional',
			'poi.cuisine.local' => 'Lokal',
			'poi.cuisine.burger' => 'Burger',
			'poi.cuisine.kebab' => 'Döner',
			'poi.cuisine.chinese' => 'Chinesisch',
			'poi.cuisine.japanese' => 'Japanisch',
			'poi.cuisine.sushi' => 'Sushi',
			'poi.cuisine.asian' => 'Asiatisch',
			'poi.cuisine.indian' => 'Indisch',
			'poi.cuisine.thai' => 'Thailändisch',
			'poi.cuisine.vietnamese' => 'Vietnamesisch',
			'poi.cuisine.korean' => 'Koreanisch',
			'poi.cuisine.mexican' => 'Mexikanisch',
			'poi.cuisine.lebanese' => 'Libanesisch',
			'poi.cuisine.greek' => 'Griechisch',
			'poi.cuisine.turkish' => 'Türkisch',
			'poi.cuisine.moroccan' => 'Marokkanisch',
			'poi.cuisine.middleEastern' => 'Orientalisch',
			'poi.cuisine.arab' => 'Arabisch',
			'poi.cuisine.african' => 'Afrikanisch',
			'poi.cuisine.american' => 'Amerikanisch',
			'poi.cuisine.spanish' => 'Spanisch',
			'poi.cuisine.tapas' => 'Tapas',
			'poi.cuisine.portuguese' => 'Portugiesisch',
			'poi.cuisine.german' => 'Deutsch',
			'poi.cuisine.mediterranean' => 'Mediterran',
			'poi.cuisine.international' => 'International',
			'poi.cuisine.seafood' => 'Meeresfrüchte',
			'poi.cuisine.fish' => 'Fisch',
			'poi.cuisine.fishAndChips' => 'Fish and Chips',
			'poi.cuisine.steakHouse' => 'Steakhaus',
			'poi.cuisine.grill' => 'Grill',
			'poi.cuisine.barbecue' => 'Barbecue',
			'poi.cuisine.chicken' => 'Hähnchen',
			'poi.cuisine.crepe' => 'Crêpes',
			'poi.cuisine.pasta' => 'Pasta',
			'poi.cuisine.noodle' => 'Nudeln',
			'poi.cuisine.ramen' => 'Ramen',
			'poi.cuisine.couscous' => 'Couscous',
			'poi.cuisine.sandwich' => 'Sandwiches',
			'poi.cuisine.bagel' => 'Bagels',
			'poi.cuisine.hotDog' => 'Hotdogs',
			'poi.cuisine.friture' => 'Pommes frites',
			'poi.cuisine.salad' => 'Salate',
			'poi.cuisine.vegetarian' => 'Vegetarisch',
			'poi.cuisine.vegan' => 'Vegan',
			'poi.cuisine.breakfast' => 'Frühstück',
			'poi.cuisine.brunch' => 'Brunch',
			'poi.cuisine.coffeeShop' => 'Kaffeebar',
			'poi.cuisine.tea' => 'Tee',
			'poi.cuisine.bubbleTea' => 'Bubble Tea',
			'poi.cuisine.juice' => 'Säfte',
			'poi.cuisine.iceCream' => 'Eis',
			'poi.cuisine.cake' => 'Kuchen',
			'poi.cuisine.donut' => 'Donuts',
			'poi.cuisine.savoy' => 'Savoyisch',
			'poi.cuisine.swiss' => 'Schweizerisch',
			'poi.cuisine.belgian' => 'Belgisch',
			'poi.cuisine.austrian' => 'Österreichisch',
			'poi.cuisine.british' => 'Britisch',
			'poi.cuisine.dutch' => 'Niederländisch',
			'poi.details.cuisineTitle' => 'Küche',
			'poi.details.dietsTitle' => 'Ernährung',
			'poi.details.facilitiesTitle' => 'Vor Ort',
			'poi.details.vehicleServicesTitle' => 'Leistungen',
			'poi.details.takeaway' => 'Zum Mitnehmen',
			'poi.details.noTakeaway' => 'Nicht zum Mitnehmen',
			'poi.details.delivery' => 'Lieferservice',
			'poi.details.noDelivery' => 'Kein Lieferservice',
			'poi.details.outdoorSeating' => 'Außenbereich',
			'poi.details.noOutdoorSeating' => 'Kein Außenbereich',
			'poi.details.wifi' => 'WLAN für Gäste',
			'poi.details.noWifi' => 'Kein WLAN',
			'poi.details.emergency' => 'Notaufnahme',
			'poi.details.noEmergency' => 'Keine Notaufnahme',
			'poi.details.wheelchairYes' => 'Rollstuhlgerecht',
			'poi.details.wheelchairLimited' => 'Eingeschränkt rollstuhlgerecht',
			'poi.details.wheelchairNo' => 'Nicht rollstuhlgerecht',
			'poi.details.googleMaps' => 'Rezensionen auf Google Maps ansehen',
			'poi.details.googleMapsHint' => 'Öffnet sich außerhalb von Lunaway, mit Name und Position dieses Ortes.',
			'poi.details.reviewsError' => 'Die Rezensionen konnten nicht angezeigt werden.',
			'poi.details.photoOf' => ({required Object name}) => 'Foto von ${name}',
			'poi.details.stars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Stern', other: '${n} Sterne', ), 
			'poi.details.reviewsOffline' => 'Rezensionen brauchen eine Verbindung.',
			'poi.diet.vegetarian' => 'Vegetarisch',
			'poi.diet.vegan' => 'Vegan',
			'poi.diet.glutenFree' => 'Glutenfrei',
			'poi.diet.halal' => 'Halal',
			'poi.diet.kosher' => 'Koscher',
			'poi.diet.lactoseFree' => 'Laktosefrei',
			'poi.reservation.yes' => 'Reservierung möglich',
			'poi.reservation.no' => 'Keine Reservierung',
			'poi.reservation.required' => 'Reservierung erforderlich',
			'poi.reservation.recommended' => 'Reservierung empfohlen',
			'poi.reservation.only' => 'Nur mit Reservierung',
			'poi.vehicleService.tyres' => 'Reifen',
			'poi.vehicleService.brakes' => 'Bremsen',
			'poi.vehicleService.oilChange' => 'Ölwechsel',
			'poi.vehicleService.glass' => 'Autoglas',
			'poi.vehicleService.airConditioning' => 'Klimaanlage',
			'poi.vehicleService.bodyRepair' => 'Karosserie',
			'poi.vehicleService.painting' => 'Lackierung',
			'poi.vehicleService.electrical' => 'Elektrik',
			'poi.vehicleService.diagnostics' => 'Diagnose',
			'poi.vehicleService.batteries' => 'Batterien',
			'poi.vehicleService.engine' => 'Motor',
			'poi.vehicleService.exhaust' => 'Auspuff',
			'poi.vehicleService.clutch' => 'Kupplung',
			'poi.vehicleService.transmission' => 'Getriebe',
			'poi.vehicleService.suspension' => 'Fahrwerk',
			'poi.vehicleService.carParts' => 'Ersatzteile',
			'poi.vehicleService.newCarSales' => 'Neuwagen',
			'poi.vehicleService.usedCarSales' => 'Gebrauchtwagen',
			'offlineMaps.title' => 'Offline-Karten',
			'offlineMaps.intro' => 'Speichern Sie vor der Abreise eine Region auf dem Gerät: ihre Plätze zum Suchen und Auswählen, ihre Karte für die Straßen ohne Netz.',
			'offlineMaps.webTitle' => 'Offline-Karten gibt es in der App',
			'offlineMaps.web' => 'Die Apps für Android und iOS speichern Regionen für unterwegs. Im Browser braucht die Karte das Netz.',
			'offlineMaps.desktopTitle' => 'Offline-Karten gibt es auf dem Smartphone',
			'offlineMaps.desktop' => 'Die Apps für Android und iOS speichern Regionen für unterwegs. Am Computer braucht die Karte das Netz.',
			'offlineMaps.unreadable' => 'Die Offline-Karten dieses Geräts konnten nicht geladen werden.',
			'offlineMaps.none' => 'Noch keine Region auf diesem Gerät.',
			'offlineMaps.used' => ({required Object size}) => 'Belegter Speicher: ${size}',
			'offlineMaps.downloads' => 'Downloads',
			'offlineMaps.installed' => 'Auf diesem Gerät',
			'offlineMaps.suggested' => 'Vorschläge',
			'offlineMaps.here' => 'Wo Sie gerade sind',
			'offlineMaps.favoritesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${n} Favorit in dieser Region', other: '${n} Favoriten in dieser Region', ), 
			'offlineMaps.france' => 'Frankreich',
			'offlineMaps.overseas' => 'Überseegebiete',
			'offlineMaps.countries' => 'Länder',
			'offlineMaps.downloadNamed' => ({required Object name, required Object size}) => '${name} herunterladen, ${size}',
			'offlineMaps.pause' => 'Pausieren',
			'offlineMaps.resume' => 'Fortsetzen',
			'offlineMaps.cancel' => 'Download abbrechen und löschen',
			'offlineMaps.waiting' => 'In der Warteschlange',
			'offlineMaps.progress' => ({required Object done, required Object total}) => '${done} von ${total}',
			'offlineMaps.paused' => ({required Object done, required Object total}) => 'Pausiert bei ${done} von ${total}',
			'offlineMaps.verifying' => 'Datei wird geprüft',
			'offlineMaps.failedNetwork' => 'Unterbrochen: kein Netz. Der Download wird an derselben Stelle fortgesetzt, sobald das Netz wieder da ist.',
			'offlineMaps.failedServer' => 'Der Server hat etwas anderes als die Karte gesendet. Versuchen Sie es später erneut.',
			'offlineMaps.failedCorrupt' => 'Die Datei kam beschädigt an und wurde gelöscht. Versuchen Sie es erneut.',
			'offlineMaps.failedStorage' => 'Nicht mehr genug Speicherplatz auf dem Gerät. Geben Sie Speicher frei und versuchen Sie es dann erneut.',
			'offlineMaps.keepOpen' => 'Lassen Sie die App während des Downloads geöffnet: Er wird unterbrochen, wenn die App in den Hintergrund geht, und fortgesetzt, wenn Sie zurückkehren.',
			'offlineMaps.dataOf' => ({required Object date}) => 'Daten vom ${date}',
			'offlineMaps.update' => ({required Object size}) => 'Aktualisieren, ${size}',
			'offlineMaps.deleteNamed' => ({required Object name}) => '${name} löschen',
			'offlineMaps.deleteTitle' => ({required Object name}) => '${name} von diesem Gerät löschen?',
			'offlineMaps.deleteBody' => 'Die Karte erscheint dann nicht mehr ohne Netz. Sie können sie erneut herunterladen.',
			'offlineMaps.listOffline' => 'Die Liste der Regionen braucht das Netz.',
			'offlineMaps.listCopy' => 'Zuletzt geladene Liste.',
			'offlineMaps.entryHint' => 'Zum Reisen ohne Netz',
			'offlineMaps.entryCount' => ({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Karten: ${n} Region, ${size}', other: 'Karten: ${n} Regionen, ${size}', ), 
			'offlineMaps.noticePack' => ({required Object name}) => 'Offline: heruntergeladene Karte, ${name}',
			'offlineMaps.noticeOutside' => 'Offline: Dieses Gebiet ist nicht heruntergeladen',
			'offlineMaps.noticePlacesOnly' => 'Offline: Plätze auf dem Gerät, Karte dieses Gebiets nicht heruntergeladen',
			'offlineMaps.noticeNone' => 'Offline: Laden Sie für das nächste Mal eine Region herunter',
			'offlineMaps.noticeOnline' => 'Offline: Die Karte braucht das Netz',
			'offlineMaps.placesTitle' => 'Plätze',
			'offlineMaps.placesHint' => 'Wenige Megabyte pro Region: Liste, Suche, Platzseiten und Filter funktionieren ohne Netz.',
			'offlineMaps.mapsTitle' => 'Karten',
			'offlineMaps.mapsHint' => 'Alle Straßen, einige hundert Megabyte pro Region: Die Karte erscheint ohne Netz.',
			'offlineMaps.entryPlaces' => ({required Object names}) => 'Plätze: ${names}',
			'offlineMaps.entryPlacesCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Plätze: ${n} Region', other: 'Plätze: ${n} Regionen', ), 
			'regions.pickerTitle' => 'Welche Plätze sollen auf diesem Gerät bleiben?',
			'regions.pickerIntro' => 'Jede Region wird einmal heruntergeladen und danach in kleinen Schritten aktualisiert. Sie können später unter Offline-Karten Regionen hinzufügen oder entfernen.',
			'regions.nearYou' => ({required Object name}) => 'In Ihrer Nähe: ${name}',
			'regions.findMine' => 'Meine Region finden',
			'regions.locating' => 'Ihre Region wird gesucht',
			'regions.notCovered' => 'Noch keine Lunaway-Region in Ihrer Nähe',
			'regions.wholeFrance' => 'Ganz Frankreich',
			'regions.showFrance' => 'Regionen Frankreichs anzeigen',
			'regions.hideFrance' => 'Regionen Frankreichs ausblenden',
			'regions.packInfo' => ({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: '${count} Platz, ${size}', other: '${count} Plätze, ${size}', ), 
			'regions.noPack' => 'Kein Paket: Plätze kommen mit den Updates, Größe unbekannt',
			'regions.download' => ({required Object size}) => 'Herunterladen, ${size}',
			'regions.unavailable' => 'Der Server bietet noch keine Regionen an: Lunaway behält ganz Frankreich.',
			'regions.listFailed' => 'Die Liste der Regionen braucht das Netz.',
			'regions.choose' => 'Regionen wählen',
			'regions.noneKept' => 'Keine Region gespeichert: Die Karte hat offline keine Plätze.',
			'regions.change' => 'Regionen hinzufügen oder entfernen',
			'regions.removeNamed' => ({required Object name}) => '${name} entfernen',
			'regions.removed' => ({required Object name}) => '${name}: Plätze von diesem Gerät entfernt',
			'regions.downloading' => ({required Object done, required Object total}) => 'Download, ${done} von ${total}',
			'regions.updating' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('de'))(n, one: 'Aktualisierung, ${count} Platz', other: 'Aktualisierung, ${count} Plätze', ), 
			'regions.waiting' => 'wartet auf den Download',
			'regions.downloadingNamed' => ({required Object name}) => 'Plätze werden heruntergeladen: ${name}',
			'regions.updated' => ({required Object when}) => 'aktualisiert ${when}',
			'regions.offerTitle' => ({required Object name}) => '${name}: Plätze offline speichern?',
			'regions.downloadThis' => 'Diese Region herunterladen',
			'regions.notHere' => ({required Object name}) => '${name} ist nicht auf diesem Gerät',
			'regions.updatesOnMobile' => 'Auch über mobile Daten aktualisieren',
			'regions.updatesOnMobileHint' => 'Sonst werden bereits heruntergeladene Regionen über WLAN aktualisiert. Ein neuer Download nutzt jedes Netz.',
			'roadReport.actionHint' => 'Ein Problem auf der Straße melden',
			'roadReport.title' => 'Was sehen Sie auf der Straße?',
			'roadReport.intro' => 'Ihre Meldung warnt andere Reisende. Wenn zwei vertrauenswürdige Konten dasselbe melden, umgehen die Routen die Stelle. Polizeikontrollen können nicht gemeldet werden.',
			'roadReport.kinds.closure' => 'Straße gesperrt',
			'roadReport.kinds.works' => 'Baustelle',
			'roadReport.kinds.narrowPassage' => 'Engstelle',
			'roadReport.kinds.lowClearance' => 'Höhenbeschränkung',
			'roadReport.kinds.other' => 'Problem auf der Straße',
			'roadReport.height' => ({required Object value}) => 'Ausgeschilderte Höhe: ${value}',
			'roadReport.send' => 'Melden',
			'roadReport.sent' => 'Danke: Andere Reisende sind gewarnt.',
			'roadReport.stillThere' => 'Noch da',
			'roadReport.over' => 'Ist vorbei',
			'roadReport.overSent' => 'Danke: notiert.',
			'roadReport.fromMap' => 'Hier ein Problem melden',
			'roadReport.notHereTitle' => 'Hier keine Meldung möglich',
			'roadReport.lower' => '10 cm niedriger',
			'roadReport.higher' => '10 cm höher',
			'roadReport.passed' => ({required Object what}) => 'Gerade passiert: ${what}. Noch da?',
			'roadReport.notHere' => ({required Object countries}) => 'Lunaway nimmt Meldungen dort an, wo ein offizieller Datenfeed sie abgleicht: ${countries}.',
			'countries.ad' => 'Andorra',
			'countries.at' => 'Österreich',
			'countries.ax' => 'Åland',
			'countries.be' => 'Belgien',
			'countries.ch' => 'Schweiz',
			'countries.cz' => 'Tschechien',
			'countries.de' => 'Deutschland',
			'countries.dk' => 'Dänemark',
			'countries.eh' => 'Westsahara',
			'countries.es' => 'Spanien',
			'countries.fi' => 'Finnland',
			'countries.fr' => 'Frankreich',
			'countries.gb' => 'Vereinigtes Königreich',
			'countries.gi' => 'Gibraltar',
			'countries.gr' => 'Griechenland',
			'countries.hr' => 'Kroatien',
			'countries.ie' => 'Irland',
			'countries.it' => 'Italien',
			'countries.li' => 'Liechtenstein',
			'countries.lu' => 'Luxemburg',
			'countries.ma' => 'Marokko',
			'countries.mc' => 'Monaco',
			'countries.nl' => 'Niederlande',
			'countries.no' => 'Norwegen',
			'countries.pl' => 'Polen',
			'countries.pt' => 'Portugal',
			'countries.se' => 'Schweden',
			'countries.si' => 'Slowenien',
			'countries.sj' => 'Spitzbergen',
			'countries.sm' => 'San Marino',
			'countries.va' => 'Vatikanstadt',
			'areas.ara' => 'Auvergne-Rhône-Alpes',
			'areas.bfc' => 'Bourgogne-Franche-Comté',
			'areas.bre' => 'Bretagne',
			'areas.cvl' => 'Centre-Val de Loire',
			'areas.cor' => 'Korsika',
			'areas.ges' => 'Grand Est',
			'areas.hdf' => 'Hauts-de-France',
			'areas.idf' => 'Île-de-France',
			'areas.nor' => 'Normandie',
			'areas.naq' => 'Nouvelle-Aquitaine',
			'areas.occ' => 'Okzitanien',
			'areas.pdl' => 'Pays de la Loire',
			'areas.pac' => 'Provence-Alpes-Côte d\'Azur',
			'areas.gp' => 'Guadeloupe',
			'areas.mq' => 'Martinique',
			'areas.gf' => 'Französisch-Guayana',
			'areas.re' => 'Réunion',
			'areas.yt' => 'Mayotte',
			'areas.franceRest' => 'Frankreich, ohne Gemeindezuordnung',
			_ => null,
		};
	}
}

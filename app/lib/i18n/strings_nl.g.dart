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
class TranslationsNl extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsNl({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.nl,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <nl>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsNl _root = this; // ignore: unused_field

	@override 
	TranslationsNl $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsNl(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => 'Lunaway';
	@override late final _Translations$nav$nl nav = _Translations$nav$nl._(_root);
	@override late final _Translations$common$nl common = _Translations$common$nl._(_root);
	@override late final _Translations$notices$nl notices = _Translations$notices$nl._(_root);
	@override late final _Translations$kinds$nl kinds = _Translations$kinds$nl._(_root);
	@override late final _Translations$families$nl families = _Translations$families$nl._(_root);
	@override late final _Translations$services$nl services = _Translations$services$nl._(_root);
	@override late final _Translations$activities$nl activities = _Translations$activities$nl._(_root);
	@override late final _Translations$amenities$nl amenities = _Translations$amenities$nl._(_root);
	@override late final _Translations$overnight$nl overnight = _Translations$overnight$nl._(_root);
	@override late final _Translations$freshness$nl freshness = _Translations$freshness$nl._(_root);
	@override late final _Translations$map$nl map = _Translations$map$nl._(_root);
	@override late final _Translations$sync$nl sync = _Translations$sync$nl._(_root);
	@override late final _Translations$location$nl location = _Translations$location$nl._(_root);
	@override late final _Translations$search$nl search = _Translations$search$nl._(_root);
	@override late final _Translations$filters$nl filters = _Translations$filters$nl._(_root);
	@override late final _Translations$place$nl place = _Translations$place$nl._(_root);
	@override late final _Translations$sources$nl sources = _Translations$sources$nl._(_root);
	@override late final _Translations$hours$nl hours = _Translations$hours$nl._(_root);
	@override late final _Translations$directions$nl directions = _Translations$directions$nl._(_root);
	@override late final _Translations$navigation$nl navigation = _Translations$navigation$nl._(_root);
	@override late final _Translations$list$nl list = _Translations$list$nl._(_root);
	@override late final _Translations$favorites$nl favorites = _Translations$favorites$nl._(_root);
	@override late final _Translations$vehicle$nl vehicle = _Translations$vehicle$nl._(_root);
	@override late final _Translations$vehicleHeight$nl vehicleHeight = _Translations$vehicleHeight$nl._(_root);
	@override late final _Translations$profile$nl profile = _Translations$profile$nl._(_root);
	@override late final _Translations$units$nl units = _Translations$units$nl._(_root);
	@override late final _Translations$languages$nl languages = _Translations$languages$nl._(_root);
	@override late final _Translations$translation$nl translation = _Translations$translation$nl._(_root);
	@override late final _Translations$locale$nl locale = _Translations$locale$nl._(_root);
	@override late final _Translations$account$nl account = _Translations$account$nl._(_root);
	@override late final _Translations$recovery$nl recovery = _Translations$recovery$nl._(_root);
	@override late final _Translations$recover$nl recover = _Translations$recover$nl._(_root);
	@override late final _Translations$deletion$nl deletion = _Translations$deletion$nl._(_root);
	@override late final _Translations$devices$nl devices = _Translations$devices$nl._(_root);
	@override late final _Translations$muted$nl muted = _Translations$muted$nl._(_root);
	@override late final _Translations$mine$nl mine = _Translations$mine$nl._(_root);
	@override late final _Translations$outbox$nl outbox = _Translations$outbox$nl._(_root);
	@override late final _Translations$placement$nl placement = _Translations$placement$nl._(_root);
	@override late final _Translations$contribute$nl contribute = _Translations$contribute$nl._(_root);
	@override late final _Translations$confirmSheet$nl confirmSheet = _Translations$confirmSheet$nl._(_root);
	@override late final _Translations$issueSheet$nl issueSheet = _Translations$issueSheet$nl._(_root);
	@override late final _Translations$reportSheet$nl reportSheet = _Translations$reportSheet$nl._(_root);
	@override late final _Translations$reviewSheet$nl reviewSheet = _Translations$reviewSheet$nl._(_root);
	@override late final _Translations$gate$nl gate = _Translations$gate$nl._(_root);
	@override late final _Translations$photoFlow$nl photoFlow = _Translations$photoFlow$nl._(_root);
	@override late final _Translations$placeForm$nl placeForm = _Translations$placeForm$nl._(_root);
	@override late final _Translations$favoritesSync$nl favoritesSync = _Translations$favoritesSync$nl._(_root);
	@override late final _Translations$poi$nl poi = _Translations$poi$nl._(_root);
	@override late final _Translations$offlineMaps$nl offlineMaps = _Translations$offlineMaps$nl._(_root);
	@override late final _Translations$regions$nl regions = _Translations$regions$nl._(_root);
	@override late final _Translations$roadReport$nl roadReport = _Translations$roadReport$nl._(_root);
	@override late final _Translations$countries$nl countries = _Translations$countries$nl._(_root);
	@override late final _Translations$areas$nl areas = _Translations$areas$nl._(_root);
}

// Path: nav
class _Translations$nav$nl extends Translations$nav$en {
	_Translations$nav$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get map => 'Kaart';
	@override String get favorites => 'Favorieten';
	@override String get profile => 'Profiel';
	@override String get fold => 'Menu inklappen';
	@override String get unfold => 'Menu uitklappen';
}

// Path: common
class _Translations$common$nl extends Translations$common$en {
	_Translations$common$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get close => 'Sluiten';
	@override String get done => 'Klaar';
	@override String get cancel => 'Annuleren';
	@override String get retry => 'Opnieuw proberen';
	@override String get save => 'Opslaan';
	@override String get delete => 'Verwijderen';
	@override String get undo => 'Ongedaan maken';
	@override String get ok => 'Begrepen';
	@override String get saveFailed => 'De wijziging kon niet worden opgeslagen.';
	@override String get send => 'Versturen';
	@override String get later => 'Later';
	@override String get next => 'Doorgaan';
	@override String get failed => 'Dat is niet gelukt. Probeer het zo opnieuw.';
	@override String get offline => 'Op dit moment geen verbinding. Probeer het opnieuw zodra je weer online bent.';
}

// Path: notices
class _Translations$notices$nl extends Translations$notices$en {
	_Translations$notices$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get close => 'Melding sluiten';
	@override String get fold => 'Melding inklappen';
	@override String get unfold => 'Melding tonen';
}

// Path: kinds
class _Translations$kinds$nl extends Translations$kinds$en {
	_Translations$kinds$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get motorhomeArea => 'Camperplaats';
	@override String get serviceArea => 'Camperservicepunt';
	@override String get campsite => 'Camping';
	@override String get parking => 'Parkeerplaats';
	@override String get nature => 'Plek in de natuur';
	@override String get restArea => 'Rustplaats';
	@override String get picnicArea => 'Picknickplaats';
	@override String get farm => 'Camperplaats bij de boer';
	@override String get homestay => 'Camperplaats bij een particulier';
	@override String get offRoad => 'Offroadplek';
	@override String get extraService => 'Handige stop';
}

// Path: families
class _Translations$families$nl extends Translations$families$en {
	_Translations$families$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get stopovers => 'Camper- en parkeerplaatsen';
	@override String get stopoversHint => 'Camperplaatsen, parkeerplaatsen, rustplaatsen';
	@override String get campsites => 'Campings en gastadressen';
	@override String get campsitesHint => 'Campings, boerderijen, particulieren';
	@override String get nature => 'Natuur';
	@override String get natureHint => 'Plekken in de natuur, onverharde wegen';
	@override String get services => 'Servicepunten';
	@override String get servicesHint => 'Water en lozen, geen overnachting';
}

// Path: services
class _Translations$services$nl extends Translations$services$en {
	_Translations$services$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get drinkingWater => 'Drinkwater';
	@override String get greyWater => 'Grijswater lozen';
	@override String get blackWater => 'Cassette legen';
	@override String get wasteBin => 'Afvalbakken';
	@override String get toilets => 'Toiletten';
	@override String get showers => 'Douches';
	@override String get electricity => 'Stroom';
	@override String get wifi => 'Wifi';
	@override String get laundry => 'Wasserette';
	@override String get lpg => 'LPG';
	@override String get gasBottles => 'Gasflessen';
	@override String get vehicleWash => 'Wasplaats';
	@override String get bakery => 'Bakker';
	@override String get swimmingPool => 'Zwembad';
	@override String get petsAllowed => 'Huisdieren welkom';
	@override String get mobileData => 'Mobiel bereik';
	@override String get winterCaravanning => 'Open in de winter';
}

// Path: activities
class _Translations$activities$nl extends Translations$activities$en {
	_Translations$activities$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get monuments => 'Bezienswaardigheden';
	@override String get windsurfKitesurf => 'Windsurfen, kitesurfen';
	@override String get mountainBiking => 'Mountainbiken';
	@override String get hiking => 'Wandelen';
	@override String get climbing => 'Klimmen';
	@override String get canoeKayak => 'Kano, kajak';
	@override String get fishing => 'Vissen';
	@override String get shoreFishing => 'Schelpdieren rapen';
	@override String get swimming => 'Zwemmen';
	@override String get motorcycling => 'Motortochten';
	@override String get viewpoint => 'Uitzichtpunt';
	@override String get playground => 'Speeltuin';
}

// Path: amenities
class _Translations$amenities$nl extends Translations$amenities$en {
	_Translations$amenities$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get water => 'Water';
	@override String get dumpStation => 'Lozingspunt';
	@override String get electricity => 'Stroom';
	@override String get toilets => 'Toiletten';
	@override String get showers => 'Douches';
	@override String get wasteBin => 'Afvalbakken';
	@override String get laundry => 'Wasserette';
	@override String get wifi => 'Wifi';
	@override String get lpg => 'LPG';
}

// Path: overnight
class _Translations$overnight$nl extends Translations$overnight$en {
	_Translations$overnight$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Overnachten toegestaan';
	@override String get tolerated => 'Overnachten gedoogd';
	@override String get dayOnly => 'Alleen overdag';
	@override String get forbidden => 'Overnachten verboden';
	@override String get unknown => 'Overnachten: onbekend';
	@override String get allowedHint => 'Je mag hier overnachten.';
	@override String get toleratedHint => 'Eén nacht wordt meestal geaccepteerd. Wees discreet en laat geen sporen achter.';
	@override String get dayOnlyHint => 'Alleen overdag parkeren. Zoek een andere plek voor de nacht.';
	@override String get forbiddenHint => 'Overnachten is hier verboden.';
	@override String get unknownHint => 'Niemand heeft het nog gemeld. Vraag het ter plaatse.';
}

// Path: freshness
class _Translations$freshness$nl extends Translations$freshness$en {
	_Translations$freshness$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String confirmed({required Object when}) => 'Door een reiziger bevestigd: ${when}';
	@override String get unconfirmed => 'Nog niet door een reiziger bevestigd';
	@override String get stale => 'Meer dan een jaar geleden voor het laatst bevestigd';
	@override String get today => 'vandaag';
	@override String daysAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'gisteren',
		other: '${n} dagen geleden',
	);
	@override String monthsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'een maand geleden',
		other: '${n} maanden geleden',
	);
	@override String yearsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'een jaar geleden',
		other: '${n} jaar geleden',
	);
}

// Path: map
class _Translations$map$nl extends Translations$map$en {
	_Translations$map$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get searchHint => 'Plek of gemeente';
	@override String get clearSearch => 'Zoekopdracht wissen';
	@override String get locateMe => 'Mijn positie tonen';
	@override String get aroundMe => 'Mijn omgeving bekijken';
	@override String get zoomIn => 'Inzoomen';
	@override String get zoomOut => 'Uitzoomen';
	@override String get filters => 'Filters';
	@override String get credit => '© OpenStreetMap · Protomaps';
	@override String get creditLabel => 'Kaartbronnen: © bijdragers van OpenStreetMap, stijl van Protomaps. Opent de auteursrechtpagina van OpenStreetMap.';
	@override String get creditPhotos => 'Foto\'s: Externe communitybron';
	@override String get creditPhotosLabel => 'Kaartbronnen: © bijdragers van OpenStreetMap, stijl van Protomaps; foto\'s: Externe communitybron. Opent de auteursrechtpagina van OpenStreetMap.';
	@override String get showList => 'Lijst';
	@override String showListCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Lijst (${n})',
		other: 'Lijst (${n})',
	);
	@override String placesHereLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'plek hier',
		other: 'plekken hier',
	);
	@override String nearestYouLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'plek het dichtst bij jou',
		other: 'plekken het dichtst bij jou',
	);
	@override String nearestCentreLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'plek het dichtst bij het midden',
		other: 'plekken het dichtst bij het midden',
	);
	@override String get pointTitle => 'Hier';
	@override String get pointHint => 'Punt op de kaart';
	@override String get directionsHere => 'Route hierheen';
	@override String get startHere => 'Hier vertrekken';
	@override String get departureChosen => 'Vertrekpunt gekozen. Open nu de bestemming om de route te zien.';
	@override String get copyCoordinates => 'Coördinaten kopiëren';
	@override String get freeTapHint => 'Tik op de kaart om erheen te gaan of er een plek toe te voegen';
	@override String get freeTapHintClick => 'Klik op de kaart om erheen te gaan of er een plek toe te voegen';
	@override String get addPlaceAtCenter => 'Plek toevoegen in het midden van de kaart';
	@override String addressSource({required Object attribution}) => 'Bron: ${attribution}';
	@override String get placesAround => 'Plekken in de buurt';
	@override String get downloading => 'De plekken in Frankrijk worden gedownload';
	@override String downloadingCount({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${count} plek ontvangen',
		other: '${count} plekken ontvangen',
	);
	@override String get noData => 'Nog geen plekken op dit apparaat';
	@override String get noDataHint => 'Download de plekken één keer: daarna werkt de kaart zonder internet.';
	@override String get download => 'Plekken downloaden';
	@override String get downloadFailed => 'Het downloaden is gestopt';
	@override String get demoBanner => 'Demo: verzonnen plekken';
	@override String get unsupported => 'De kaart is niet beschikbaar op dit systeem. Gebruik de webapp.';
}

// Path: sync
class _Translations$sync$nl extends Translations$sync$en {
	_Translations$sync$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get failedOffline => 'Op dit moment geen verbinding.';
	@override String get failedBusy => 'De server is op dit moment overbelast.';
	@override String get failedServer => 'De server heeft op dit moment een probleem.';
	@override String get failedOther => 'Het bijwerken is niet gelukt.';
	@override String get failedRefused => 'De server heeft het bijwerken geweigerd. Misschien is er een nieuwere versie van de app nodig.';
	@override String get willRetry => 'Lunaway probeert het vanzelf opnieuw.';
	@override String incomplete({required Object count}) => 'Download onvolledig: tot nu toe ${count} plekken';
	@override String get incompleteShort => 'Download onvolledig';
	@override String resuming({required Object count}) => 'Bezig met downloaden: ${count} plekken';
	@override String get resume => 'Hervatten';
}

// Path: location
class _Translations$location$nl extends Translations$location$en {
	_Translations$location$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get rationaleTitle => 'Je positie tonen?';
	@override String get rationale => 'Lunaway gebruikt je positie om de kaart op jou te centreren, plekken op afstand te sorteren en je de weg te wijzen. Voor een route gaat je positie naar de server van Lunaway, die hem niet bewaart. Voor de goedkoopste brandstof bij jou in de buurt wordt alleen een positie verstuurd die is afgerond op ongeveer 5 km. Als je een probleem op de weg meldt, wordt de plek van de melding meegestuurd.';
	@override String get allow => 'Doorgaan';
	@override String get notNow => 'Niet nu';
	@override String get deniedTitle => 'Positie uitgeschakeld voor Lunaway';
	@override String get denied => 'Je hebt de toegang tot je positie geweigerd. Sta die toegang toe in de instellingen van het apparaat om je positie te gebruiken.';
	@override String get openSettings => 'Instellingen openen';
	@override String get serviceOffTitle => 'Locatie staat uit';
	@override String get serviceOff => 'Locatie staat uit op dit apparaat. Zet hem aan via de snelle instellingen en probeer het dan opnieuw.';
	@override String get notAllowed => 'Geen toegang tot je positie. De kaart werkt ook zonder.';
	@override String get noFix => 'Je positie is nog niet gevonden. Probeer het zo meteen opnieuw, het liefst buiten.';
	@override String get unsupported => 'Dit apparaat geeft zijn positie niet door.';
	@override String get browserDeniedTitle => 'De browser blokkeert je positie';
	@override String get browserDenied => 'De browser geeft je positie niet door aan Lunaway. Om dat toe te staan: klik op het pictogram links van het webadres (een slotje of schuifjes), zet Locatie op Toestaan en klik daarna opnieuw op de positieknop.';
	@override String get browserNoFix => 'De browser heeft geen positie doorgegeven. Probeer het zo opnieuw; op een computer helpt wifi om je positie te vinden.';
}

// Path: search
class _Translations$search$nl extends Translations$search$en {
	_Translations$search$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get towns => 'Gemeenten';
	@override String get places => 'Plekken';
	@override String noResult({required Object query}) => 'Geen plek of gemeente gevonden voor “${query}”.';
	@override String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} plek',
		other: '${n} plekken',
	);
	@override String get addresses => 'Adressen';
	@override String get addressesSearching => 'Adressen worden gezocht';
	@override String get addressesFailed => 'Zoeken naar adressen lukt nu niet.';
	@override String addressSources({required Object sources}) => 'Adressen: ${sources}';
	@override String get offline => 'Geen verbinding: zoeken werkt alleen online.';
	@override late final _Translations$search$addressKind$nl addressKind = _Translations$search$addressKind$nl._(_root);
}

// Path: filters
class _Translations$filters$nl extends Translations$filters$en {
	_Translations$filters$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filters';
	@override String get families => 'Soort plek';
	@override String get familiesHint => 'Niets gekozen: alle soorten';
	@override String get familiesChosenHint => 'Alleen deze soorten';
	@override String get night => 'Overnachten';
	@override String get nightHint => 'Niets gekozen: alle plekken';
	@override String get nightChosenHint => 'Alleen plekken met deze status';
	@override String get nightPossible => 'Overnachten mogelijk';
	@override String get amenities => 'Voorzieningen';
	@override String get amenitiesHint => 'De plek moet ze allemaal hebben';
	@override String get rating => 'Minimale beoordeling';
	@override String get ratingHint => 'Beoordeling door Lunaway-reizigers, of door de andere bronnen als nog geen reiziger de plek heeft beoordeeld. Plekken zonder beoordeling worden verborgen.';
	@override String ratingAtLeast({required Object rating}) => '${rating} en hoger';
	@override String get opening => 'Openingstijden';
	@override String get openingHint => 'Plaatsen waarvan de openingstijden niet bekend zijn, blijven zichtbaar.';
	@override String get openingAllYear => 'Hele jaar';
	@override String get openingDates => 'Mijn reisdata';
	@override String get openingClearDates => 'Data wissen';
	@override String openingStay({required Object from, required Object to}) => '${from} tot ${to}';
	@override String openingStayDay({required Object date}) => 'Op ${date}';
	@override String get openingStayTitle => 'Data van je verblijf';
	@override String get openingArrival => 'Aankomst';
	@override String get openingDeparture => 'Vertrek';
	@override String get price => 'Prijs per nacht';
	@override String get freeOnly => 'Gratis';
	@override String get freeHint => 'Alleen plekken waar overnachten volgens hun bronnen gratis is';
	@override String get scrollNext => 'Volgende filters tonen';
	@override String get scrollPrevious => 'Vorige filters tonen';
	@override String get vehicle => 'Mijn voertuig';
	@override String get myVehicleFits => 'Mijn voertuig past';
	@override String myVehicleFitsHeight({required Object height}) => 'Geschikt voor ${height}';
	@override String myVehicleHint({required Object height}) => 'Verbergt plekken met een hoogtelimiet onder ${height}. Plekken zonder bekende limiet blijven op de kaart.';
	@override String get reset => 'Alles wissen';
	@override String get apply => 'Toepassen';
	@override String show({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		zero: 'Geen plek gevonden',
		one: '${count} plek tonen',
		other: '${count} plekken tonen',
	);
	@override String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} filter actief',
		other: '${n} filters actief',
	);
}

// Path: place
class _Translations$place$nl extends Translations$place$en {
	_Translations$place$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String unnamedIn({required Object kind, required Object town}) => '${kind} in ${town}';
	@override String away({required Object distance}) => 'Op ${distance} afstand';
	@override String get directions => 'Route';
	@override String get share => 'Delen';
	@override String get save => 'Opslaan';
	@override String get saved => 'Opgeslagen';
	@override String get saveHint => 'In Mijn favorieten. Lang indrukken om lijsten te kiezen.';
	@override String get saveTo => 'Opslaan in een lijst';
	@override String get chooseLists => 'Lijsten';
	@override String get savedToast => 'Toegevoegd aan Mijn favorieten';
	@override String get removedToast => 'Verwijderd uit Mijn favorieten';
	@override String get pricePerNight => 'Per nacht';
	@override String get priceFree => 'Gratis';
	@override String get priceUnknown => 'Niet vermeld';
	@override String get priceServices => 'Service';
	@override String get priceIncluded => 'Inbegrepen';
	@override String priceIncludes({required Object items}) => 'De prijs per nacht is inclusief: ${items}';
	@override late final _Translations$place$inclusions$nl inclusions = _Translations$place$inclusions$nl._(_root);
	@override String get maxHeight => 'Max. hoogte';
	@override String get capacity => 'Plaatsen';
	@override String get classification => 'Classificatie';
	@override String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} ster',
		other: '${n} sterren',
	);
	@override String get hours => 'Openingstijden';
	@override String get services => 'Voorzieningen';
	@override String get noServices => 'Geen voorzieningen vermeld.';
	@override String get activities => 'In de buurt';
	@override String get description => 'Beschrijving';
	@override String get contact => 'Contact';
	@override String get website => 'Website';
	@override String get call => 'Bellen';
	@override String get coordinates => 'Coördinaten';
	@override String get copy => 'Coördinaten kopiëren';
	@override String get copyShort => 'Kopiëren';
	@override String copyAs({required Object format}) => 'Kopiëren als ${format}';
	@override String copiesAs({required Object format}) => '“Kopiëren” kopieert: ${format}';
	@override String copied({required Object text}) => 'Gekopieerd: ${text}';
	@override String get otherFormats => 'Kies het formaat om te kopiëren';
	@override String get formatDecimal => 'Decimale graden';
	@override String get formatDms => 'Graden, minuten, seconden';
	@override String get formatGeo => 'geo:-link';
	@override String get formatGoogle => 'Google Maps-link';
	@override String get formatOsm => 'OpenStreetMap-link';
	@override String get sources => 'Bronnen';
	@override String fetched({required Object when}) => 'Opgehaald ${when}';
	@override String get viewSource => 'Bekijken bij de bron';
	@override String get gone => 'Deze plek staat niet meer op de kaart';
	@override String get goneHint => 'Sinds de laatste update is deze plek verwijderd of samengevoegd met een andere.';
	@override String get arriving => 'Deze plek wordt nog gedownload';
	@override String get arrivingHint => 'De plekken in Frankrijk worden gedownload, zodat de kaart zonder internet werkt. De pagina gaat open zodra deze plek binnen is.';
	@override String get loadError => 'Deze plek kon niet worden geladen.';
	@override String get openFailed => 'Geen enkele app kon deze link openen.';
	@override String get photos => 'Foto\'s';
	@override String get extrasOffline => 'Voor foto\'s en reviews is een verbinding nodig.';
	@override String get reviewsTitle => 'Reviews';
	@override String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} review',
		other: '${n} reviews',
	);
	@override String get noReviews => 'Nog geen reviews.';
	@override String get noOtherReviews => 'Nog geen andere reviews.';
	@override String get moreReviews => 'Meer reviews';
	@override String get moreReviewsFailed => 'Meer reviews konden niet worden geladen. Tik om het opnieuw te proberen.';
	@override String stars({required Object rating}) => '${rating} van 5';
	@override String externalRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'externe beoordeling',
		other: 'externe beoordelingen',
	);
	@override String get deletedAccount => 'Verwijderd account';
	@override late final _Translations$place$reviewVehicle$nl reviewVehicle = _Translations$place$reviewVehicle$nl._(_root);
	@override String originalLanguage({required Object language}) => 'Oorspronkelijke tekst in het ${language}';
	@override String photoPosition({required Object index, required Object count}) => 'Foto ${index} van ${count}';
	@override String get previousPhoto => 'Vorige foto';
	@override String get nextPhoto => 'Volgende foto';
	@override String get links => 'Op andere sites';
	@override String sourceWithLicence({required Object source, required Object licence}) => '${source} · ${licence}';
	@override String get licenceCcBy => 'CC BY 4.0';
	@override String photoCredit({required Object source, required Object author}) => '${source} · ${author}';
	@override String get photoStreetView => 'Straatbeeld';
	@override String get photoSurroundings => 'Omgeving';
	@override String excerptFrom({required Object source, required Object text}) => 'Volgens ${source}: ${text}';
	@override String get readMore => 'Lees meer';
	@override String updatedOn({required Object date}) => 'bijgewerkt op ${date}';
	@override String get otherSources => 'Volgens andere bronnen';
}

// Path: sources
class _Translations$sources$nl extends Translations$sources$en {
	_Translations$sources$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override late final _Translations$sources$extcom$nl extcom = _Translations$sources$extcom$nl._(_root);
}

// Path: hours
class _Translations$hours$nl extends Translations$hours$en {
	_Translations$hours$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get open => 'Nu open';
	@override String openUntil({required Object time}) => 'Open, sluit om ${time}';
	@override String openUntilDay({required Object day, required Object time}) => 'Open, sluit ${day} om ${time}';
	@override String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Open, sluit over ${n} minuut',
		other: 'Open, sluit over ${n} minuten',
	);
	@override String closedUntil({required Object time}) => 'Gesloten, gaat om ${time} open';
	@override String closedUntilDay({required Object day, required Object time}) => 'Gesloten, gaat ${day} om ${time} open';
	@override String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Gesloten, gaat over ${n} minuut open',
		other: 'Gesloten, gaat over ${n} minuten open',
	);
	@override String get closedWindow => 'Gesloten in de komende twee weken';
	@override String get tomorrow => 'morgen';
	@override String onDate({required Object date}) => 'op ${date}';
	@override String onWeekday({required Object day}) => '${day}';
	@override String get midnight => 'middernacht';
	@override String get stale => 'Open of gesloten? Werk de plekken bij in Profiel.';
	@override String get localTime => 'Tijden in de lokale tijd van de plek';
	@override late final _Translations$hours$codes$nl codes = _Translations$hours$codes$nl._(_root);
	@override late final _Translations$hours$months$nl months = _Translations$hours$months$nl._(_root);
	@override String dayOfMonth({required Object day, required Object month}) => '${day} ${month}';
	@override String dayOfYear({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}';
	@override String get allWeek => '24/7';
	@override String get allYear => 'het hele jaar';
	@override String get seasonAllYear => 'Het hele jaar open';
	@override String seasonOpenUntil({required Object date}) => 'Open tot ${date}';
	@override String seasonClosedUntil({required Object date}) => 'Gesloten, opent op ${date}';
}

// Path: directions
class _Translations$directions$nl extends Translations$directions$en {
	_Translations$directions$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Openen in';
	@override String get hint => 'Deze apps kennen de afmetingen van je voertuig niet.';
	@override String get remember => 'Altijd deze app gebruiken';
	@override String get rememberHint => 'Je kunt dit wijzigen in Profiel';
	@override String get settingTitle => 'Openen in een andere app';
	@override String get settingHint => 'De app die opent als je bij een route op “Openen in” tikt';
	@override String get askEachTime => 'Elke keer vragen';
	@override String get appleMaps => 'Kaarten';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osmAnd => 'OsmAnd';
	@override String get organicMaps => 'Organic Maps';
	@override String get magicEarth => 'Magic Earth';
	@override String get openStreetMap => 'OpenStreetMap (browser)';
	@override String get none => 'Geen navigatie-app gevonden op dit apparaat.';
}

// Path: navigation
class _Translations$navigation$nl extends Translations$navigation$en {
	_Translations$navigation$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$preview$nl preview = _Translations$navigation$preview$nl._(_root);
	@override late final _Translations$navigation$stops$nl stops = _Translations$navigation$stops$nl._(_root);
	@override late final _Translations$navigation$legs$nl legs = _Translations$navigation$legs$nl._(_root);
	@override late final _Translations$navigation$fuel$nl fuel = _Translations$navigation$fuel$nl._(_root);
	@override late final _Translations$navigation$onTheWay$nl onTheWay = _Translations$navigation$onTheWay$nl._(_root);
	@override late final _Translations$navigation$states$nl states = _Translations$navigation$states$nl._(_root);
	@override late final _Translations$navigation$noRoute$nl noRoute = _Translations$navigation$noRoute$nl._(_root);
	@override late final _Translations$navigation$ferry$nl ferry = _Translations$navigation$ferry$nl._(_root);
	@override late final _Translations$navigation$warning$nl warning = _Translations$navigation$warning$nl._(_root);
	@override late final _Translations$navigation$roadEvents$nl roadEvents = _Translations$navigation$roadEvents$nl._(_root);
	@override late final _Translations$navigation$marks$nl marks = _Translations$navigation$marks$nl._(_root);
	@override late final _Translations$navigation$guidance$nl guidance = _Translations$navigation$guidance$nl._(_root);
	@override late final _Translations$navigation$voice$nl voice = _Translations$navigation$voice$nl._(_root);
	@override late final _Translations$navigation$units$nl units = _Translations$navigation$units$nl._(_root);
	@override late final _Translations$navigation$settings$nl settings = _Translations$navigation$settings$nl._(_root);
	@override late final _Translations$navigation$enforcement$nl enforcement = _Translations$navigation$enforcement$nl._(_root);
}

// Path: list
class _Translations$list$nl extends Translations$list$en {
	_Translations$list$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Plekken in de buurt';
	@override String get empty => 'Hier geen plekken met deze filters';
	@override String get emptyHint => 'Verschuif de kaart, zoom uit of maak de filters ruimer.';
	@override String get downloading => 'De plekken komen eraan';
	@override String get downloadingHint => 'De lijst vult zich tijdens het downloaden.';
	@override String get error => 'De lijst kon niet worden geladen.';
	@override String get offline => 'Geen verbinding: de lijst werkt alleen online.';
	@override String get moreFailed => 'Meer plekken konden niet worden geladen. Opnieuw proberen';
	@override String get sortDistance => 'Afstand';
	@override String get sortRating => 'Beoordeling';
	@override String get sortNewest => 'Onlangs toegevoegd';
	@override String sortedBy({required Object sort}) => 'Lijst gesorteerd op: ${sort}';
	@override String rankedAmongNearestYou({required Object n}) => 'Gesorteerd binnen de ${n} plekken die het dichtst bij je liggen';
	@override String rankedAmongNearestCentre({required Object n}) => 'Gesorteerd binnen de ${n} plekken die het dichtst bij het midden van de kaart liggen';
	@override String get offlineTitle => 'Geen verbinding';
	@override String get offlineNotHere => 'Niets van dit gebied op dit apparaat.';
}

// Path: favorites
class _Translations$favorites$nl extends Translations$favorites$en {
	_Translations$favorites$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Favorieten';
	@override String get defaultList => 'Mijn favorieten';
	@override String get empty => 'Hier is nog niets opgeslagen';
	@override String get emptyHint => 'Tik bij een plek op Opslaan om hem te bewaren, ook offline.';
	@override String get newList => 'Nieuwe lijst';
	@override String get listName => 'Naam van de lijst';
	@override String get renameList => 'Lijst hernoemen';
	@override String get deleteList => 'Lijst verwijderen';
	@override String deleteListConfirm({required Object name}) => '“${name}” verwijderen? De plekken blijven op de kaart.';
	@override String get listActions => 'Lijstopties';
	@override String get placeActions => 'Opties voor deze plek';
	@override String get openOnMap => 'Bekijken op de kaart';
	@override String get remove => 'Uit de lijst verwijderen';
	@override String get removed => 'Uit de lijst verwijderd';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		zero: 'Leeg',
		one: '${n} plek',
		other: '${n} plekken',
	);
	@override String get error => 'Je favorieten konden niet worden geladen.';
}

// Path: vehicle
class _Translations$vehicle$nl extends Translations$vehicle$en {
	_Translations$vehicle$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mijn voertuig';
	@override String get why => 'Met de afmetingen worden plekken verborgen waar je voertuig niet past. Ze worden bij elke routeaanvraag meegestuurd en niet bewaard.';
	@override String get none => 'Beschrijf je voertuig om plekken te verbergen waar het niet past.';
	@override String get add => 'Mijn voertuig beschrijven';
	@override String get edit => 'Wijzigen';
	@override String get type => 'Type';
	@override late final _Translations$vehicle$types$nl types = _Translations$vehicle$types$nl._(_root);
	@override String get towingTitle => 'Trekt hij iets?';
	@override late final _Translations$vehicle$towing$nl towing = _Translations$vehicle$towing$nl._(_root);
	@override String get size => 'Afmetingen';
	@override String get sizeHint => 'Gangbare waarden voor het gekozen type: pas ze aan met de gegevens van je kentekenbewijs.';
	@override String get height => 'Hoogte';
	@override String get width => 'Breedte';
	@override String get length => 'Totale lengte, inclusief wat je trekt';
	@override String get weight => 'Toegestane maximummassa';
	@override String heightShort({required Object value}) => 'H ${value}';
	@override String widthShort({required Object value}) => 'B ${value}';
	@override String lengthShort({required Object value}) => 'L ${value}';
	@override String get notANumber => 'Een getal, bijvoorbeeld 2,90';
	@override String outOfRange({required Object min, required Object max, required Object unit}) => 'Tussen ${min} en ${max} ${unit}';
	@override String get navigationLater => 'De navigatie van Lunaway houdt rekening met al deze afmetingen.';
	@override String get save => 'Opslaan';
	@override String get clear => 'Wissen';
	@override String get fuelTitle => 'Brandstof';
	@override String get fuelHint => 'De prijs van jouw brandstof staat bij de tankstations op de kaart, de goedkoopste eerst.';
	@override String get consumption => 'Verbruik';
	@override String get consumptionUnit => 'l/100 km';
	@override String get lpgHeating => 'Verwarming op LPG';
	@override String get lpgHeatingHint => 'LPG-prijzen staan ook bij de tankstations.';
	@override String get cruiseTitle => 'Maximale kruissnelheid';
	@override String get cruiseHint => 'Reistijden gaan ervan uit dat je nooit harder rijdt, ook waar de weg dat toestaat. De maximumsnelheden die tijdens het rijden worden aangekondigd, blijven die van de weg.';
	@override String get cruiseNone => 'Geen limiet';
}

// Path: vehicleHeight
class _Translations$vehicleHeight$nl extends Translations$vehicleHeight$en {
	_Translations$vehicleHeight$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Hoogte van je voertuig';
	@override String get why => 'Plekken met een hoogtelimiet onder deze hoogte worden verborgen. Plekken waarvan de hoogte niet bekend is, blijven zichtbaar.';
	@override String get needed => 'Vul de hoogte in, bijvoorbeeld 2,90';
	@override String get weightOptional => 'Toegestane maximummassa (optioneel)';
	@override String get apply => 'Filteren met deze hoogte';
	@override String get later => 'De rest van het voertuig beschrijf je in Profiel, Mijn voertuig.';
}

// Path: profile
class _Translations$profile$nl extends Translations$profile$en {
	_Translations$profile$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profiel';
	@override String get noAccountNeeded => 'Geen account, geen advertenties, geen trackers. Je favorieten blijven op dit apparaat.';
	@override String get language => 'Taal';
	@override String get languageSystem => 'Systeemtaal';
	@override String get appearance => 'Weergave';
	@override String get themeAuto => 'Automatisch';
	@override String get themeLight => 'Licht';
	@override String get themeDark => 'Donker';
	@override String get themeAutoHint => 'Licht overdag, donker na zonsondergang waar je bent.';
	@override String get themeLightHint => 'Altijd licht, dag en nacht.';
	@override String get themeDarkHint => 'Altijd donker, \'s nachts rustig voor de ogen.';
	@override String get offline => 'Offline';
	@override String placesOnDevice({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'plek op dit apparaat',
		other: 'plekken op dit apparaat',
	);
	@override String offlineSize({required Object size}) => 'Gebruikte opslag: ${size}';
	@override String lastSync({required Object when}) => 'Laatst bijgewerkt ${when}';
	@override String get neverSynced => 'Nooit gedownload';
	@override String get syncNow => 'Nu bijwerken';
	@override String get syncing => 'Bezig met bijwerken';
	@override String get about => 'Over de app';
	@override String version({required Object version}) => 'Versie ${version}';
	@override String get website => 'Website';
	@override String get privacy => 'Privacybeleid';
	@override String get sourceCode => 'Broncode';
	@override String get licences => 'Licenties';
	@override String get appLicence => 'Lunaway is vrije software onder de GNU AGPL 3.0 of later.';
	@override String get routeData => 'Routes worden berekend met open data die onvolledig kunnen zijn: verkeersborden en verkeersregels gaan voor.';
	@override String get attributions => 'Bronnen en vermeldingen';
	@override String get attributionOsm => 'Plekken en kaartgegevens © bijdragers van OpenStreetMap.';
	@override String get attributionOdbl => 'Gegevens van OpenStreetMap onder de Open Database License (ODbL).';
	@override String get attributionAtout => 'Geclassificeerde campings van Atout France, geplaatst met de Base Adresse Nationale en de BD TOPO van het IGN, onder de Licence Ouverte 2.0 (Etalab).';
	@override String get attributionCommunes => 'Gemeenten van de plekken: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), onder de ODbL.';
	@override String get attributionCommunityPlaces => 'Plekken die reizigers van Lunaway hebben toegevoegd of gewijzigd, onder de ODbL, met de vermelding “Lunaway contributors”.';
	@override String get attributionTiles => 'Basiskaart geleverd door Lunaway, stijlen afgeleid van Protomaps (BSD-3-Clause), gegevens © bijdragers van OpenStreetMap.';
	@override String get attributionFonts => 'Lettertypen Fraunces en Atkinson Hyperlegible Next, SIL Open Font License 1.1.';
	@override String get attributionIcons => 'Phosphor-pictogrammen, MIT-licentie.';
	@override String get noTracking => 'Geen advertenties, geen trackers. Je account kent je e-mailadres en je telefoonnummer niet.';
	@override String get attributionBdTopo => 'Hoogte-, breedte-, lengte- en gewichtsbeperkingen van de wegen, en de positie van campings, gevonden via hun naam: IGN BD TOPO, via de Géoplateforme, onder de Licence Ouverte 2.0.';
	@override String get attributionAddresses => 'Adressen bij het zoeken in Frankrijk: de Base Adresse Nationale, via de Géoplateforme van het IGN, onder de Licence Ouverte 2.0.';
	@override String get attributionAddressesOsm => 'Adressen bij het zoeken elders: OpenStreetMap, via Photon, onder de ODbL.';
	@override String get attributionPoiOdbl => 'Winkels en diensten: OpenStreetMap, en de openingskalender van La Poste, onder de ODbL.';
	@override String get attributionPoiLo => 'Brandstofprijzen (Frans ministerie van Economie) en de zorginstellingen van FINESS (Agence du numérique en santé), onder de Licence Ouverte 2.0 (Etalab).';
	@override String get attributionPacks => 'Contouren van de offline kaarten: Contours administratifs, data.gouv.fr (ODbL), en Natural Earth (publiek domein).';
	@override String get attributionOfflineLabels => 'Namen en pictogrammen van de offline kaarten: Noto Sans-glyphs (SIL Open Font License 1.1) en Protomaps-sprites afgeleid van tangrams/icons (MIT).';
	@override String get attributionExtcom => 'Plekken, reviews, beoordelingen en foto\'s, onder een schriftelijke overeenkomst met deze bron.';
	@override String get creditsPlaces => 'Plekken';
	@override String get creditsContent => 'Foto\'s, teksten en reviews';
	@override String get creditsRoutes => 'Routes en navigatie';
	@override String get creditsSearch => 'Zoeken';
	@override String get creditsMap => 'Basiskaart';
	@override String get creditsApp => 'App';
	@override String get attributionDatatourisme => 'Plekken, beschrijvingen en foto\'s van de toeristenbureaus: DATAtourisme, onder de Licence Ouverte 2.0; bij elke tekst en elke foto staan het bureau, de auteur en de datum van de laatste update.';
	@override String get attributionCommunity => 'Reviews, beoordelingen en foto\'s van de reizigers van Lunaway, onder CC BY 4.0, met het pseudoniem van de auteur.';
	@override String get attributionCommons => 'Foto\'s van Wikimedia Commons, elk onder een eigen licentie (CC0, publiek domein, CC BY of CC BY-SA), met de auteur en een link naar de pagina.';
	@override String get attributionPanoramax => 'Straatbeelden van Panoramax: de instantie van OpenStreetMap France onder CC BY-SA 4.0, die van het IGN onder de Licence Ouverte 2.0.';
	@override String get attributionWikipedia => 'Fragmenten uit Wikipedia-artikelen, onder CC BY-SA 4.0, met een link naar het artikel.';
	@override String get attributionMangrove => 'Reviews van Mangrove Reviews, onder CC BY 4.0 of de licentie die de review vermeldt, met een link naar de review.';
	@override String get attributionTranslation => 'Automatische vertalingen: OPUS-MT-modellen van de Universiteit van Helsinki, onder CC BY 4.0, uitgevoerd op de servers van Lunaway.';
	@override String get attributionRoadEvents => 'Werkzaamheden en afsluitingen in Frankrijk: DIR en Bison Futé, verkeersbesluiten van DiaLog (DGITM), steden en departementen (Lyon, Toulouse, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Sarthe), onder de Licence Ouverte 2.0; Bordeaux Métropole en het departement Côtes-d\'Armor, onder de Licence Ouverte; Ville de Paris, Rennes Métropole en de meldingen van de reizigers van Lunaway, onder de ODbL.';
	@override String get attributionRoadEventsAbroad => 'Werkzaamheden en afsluitingen in Nederland: NDW, Nationaal Dataportaal Wegverkeer (open data); in Spanje: DGT, Dirección General de Tráfico (CC BY).';
	@override String get attributionDangerZones => 'Flitsers en gevarenzones: in Frankrijk de kaart van de Sécurité routière, hergebruikt volgens de Franse Code des relations entre le public et l\'administration, en de lijst van vaste flitsers van het ministerie van Binnenlandse Zaken, Délégation à la sécurité routière (data.gouv.fr), onder de Licence Ouverte 2.0; in Polen Główny Inspektorat Transportu Drogowego (CANARD, dane.gov.pl), in Luxemburg de Administration des ponts et chaussées (data.public.lu), in Brussel Bruxelles Mobilité (data.mobility.brussels), onder CC0; in Noorwegen “Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.”; in Ierland de controlezones van An Garda Síochána, Irish Public Sector Information, CC BY, trajecten aangepast door Lunaway; OpenStreetMap (ODbL).';
	@override String attributionCameraSource({required Object attribution}) => 'Flitsers en gevarenzones: ${attribution}';
}

// Path: units
class _Translations$units$nl extends Translations$units$en {
	_Translations$units$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String kilobytes({required Object n}) => '${n} kB';
	@override String megabytes({required Object n}) => '${n} MB';
}

// Path: languages
class _Translations$languages$nl extends Translations$languages$en {
	_Translations$languages$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Frans';
	@override String get en => 'Engels';
	@override String get de => 'Duits';
	@override String get es => 'Spaans';
	@override String get it => 'Italiaans';
	@override String get nl => 'Nederlands';
}

// Path: translation
class _Translations$translation$nl extends Translations$translation$en {
	_Translations$translation$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get translate => 'Vertalen';
	@override String get translating => 'Bezig met vertalen';
	@override String get showOriginal => 'Origineel tonen';
	@override String get showTranslation => 'Vertaling tonen';
	@override late final _Translations$translation$from$nl from = _Translations$translation$from$nl._(_root);
	@override String get offline => 'Voor het vertalen is een internetverbinding nodig.';
	@override String get failedOffline => 'Geen internetverbinding: de tekst kon niet worden vertaald.';
	@override String get busy => 'De vertaaldienst is overbelast. Probeer het later opnieuw.';
	@override String get unavailable => 'Vertalen is op dit moment niet beschikbaar.';
	@override String get gone => 'Deze tekst is niet meer beschikbaar.';
	@override String get unsupported => 'Voor deze taal is geen vertaling beschikbaar.';
	@override String get autoReviews => 'Reviews automatisch vertalen';
	@override String get autoReviewsHint => 'Reviews in een andere taal worden vertaald op de eigen server van Lunaway, zonder tussenkomst van derden.';
}

// Path: locale
class _Translations$locale$nl extends Translations$locale$en {
	_Translations$locale$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
	@override String get de => 'Deutsch';
	@override String get es => 'Español';
	@override String get it => 'Italiano';
	@override String get nl => 'Nederlands';
}

// Path: account
class _Translations$account$nl extends Translations$account$en {
	_Translations$account$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Je account';
	@override String get noneTitle => 'Nog geen account';
	@override String get noneBody => 'De kaart, het zoeken en de favorieten werken zonder account. Er wordt er een aangemaakt bij je eerste bijdrage (een beoordeling, een bevestiging, een foto), zonder e-mailadres en zonder wachtwoord. Je favorietenlijsten worden er dan aan gekoppeld.';
	@override String get recover => 'Mijn account herstellen';
	@override String memberSince({required Object date}) => 'Lid sinds ${date}';
	@override String get editPseudonym => 'Pseudoniem wijzigen';
	@override String get pseudonymTitle => 'Je pseudoniem';
	@override String get pseudonymHint => 'Openbaar: het staat bij je reviews en foto\'s. 3 tot 32 tekens.';
	@override String get pseudonymInvalid => '3 tot 32 tekens, waarvan minstens twee letters.';
	@override String get pseudonymRefused => 'Dit pseudoniem wordt niet geaccepteerd: geen link, geen contactgegevens, geen scheldwoord, geen naam die het account laat doorgaan voor het team.';
	@override String get pseudonymSaved => 'Pseudoniem opgeslagen';
	@override String level({required Object level}) => 'Vertrouwensniveau ${level}';
	@override late final _Translations$account$levelOpens$nl levelOpens = _Translations$account$levelOpens$nl._(_root);
	@override String nextLevel({required Object level}) => 'Voor niveau ${level}';
	@override String get levelTop => 'Je zit op het hoogste niveau.';
	@override late final _Translations$account$requirement$nl requirement = _Translations$account$requirement$nl._(_root);
	@override String orInstead({required Object requirement}) => 'Of ${requirement}';
	@override String get recoveryNone => 'Op dit apparaat is geen herstelkaart gemaakt. Zonder herstelkaart blijft dit account op dit apparaat: raak je het apparaat kwijt, dan ben je ook het account kwijt.';
	@override String get recoveryNoneAccount => 'Nog geen herstelkaart voor dit account. Zonder herstelkaart blijft dit account op dit apparaat: raak je het apparaat kwijt, dan ben je ook het account kwijt.';
	@override String get recoveryCreate => 'Mijn herstelkaart maken';
	@override String recoveryMade({required Object date}) => 'Gemaakt op ${date}';
	@override String get recoveryRemake => 'Opnieuw maken';
	@override String get recoveryRemakeHint => 'Een nieuwe herstelkaart maken';
	@override String get contributions => 'Mijn bijdragen';
	@override String pending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} bijdrage wacht op verzending',
		other: '${n} bijdragen wachten op verzending',
	);
	@override String get mutedAuthors => 'Verborgen auteurs';
	@override String get devices => 'Apparaten';
	@override String get signOut => 'Uitloggen';
	@override String get delete => 'Mijn account verwijderen';
	@override String get signOutTitle => 'Uitloggen op dit apparaat?';
	@override String get signOutBody => 'De sleutel van het account wordt van dit apparaat verwijderd. Om terug te komen heb je je herstelkaart nodig. Je favorieten blijven hier.';
	@override String get signOutNoCard => 'Je hebt op dit apparaat geen herstelkaart gemaakt. Zonder herstelkaart ben je dit account voorgoed kwijt.';
	@override String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Eén bijdrage die nog op verzending wacht, wordt niet verstuurd.',
		other: '${n} bijdragen die nog op verzending wachten, worden niet verstuurd.',
	);
	@override String get signedOut => 'Uitgelogd. Je favorieten blijven op dit apparaat.';
	@override String get lost => 'Dit account gaat niet meer open op dit apparaat. Herstel het met je herstelkaart: Profiel, Mijn account herstellen.';
	@override String get lostAction => 'Herstellen';
	@override String get welcomeTitle => 'Bedankt voor je eerste bijdrage';
	@override String welcomeBody({required Object name}) => 'Je account is aangemaakt, met het pseudoniem “${name}”. Geen e-mailadres en geen wachtwoord: een sleutel die op dit apparaat wordt bewaard. Je kunt het pseudoniem wijzigen in je profiel.';
	@override String get welcomeCard => 'Maak je herstelkaart om dit account op een ander apparaat terug te vinden.';
	@override String get welcomeFavorites => 'Je favorietenlijsten worden nu bij je account bewaard.';
}

// Path: recovery
class _Translations$recovery$nl extends Translations$recovery$en {
	_Translations$recovery$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Herstelkaart';
	@override String get intro => 'Een code die je account naar een nieuw apparaat brengt. Lunaway bewaart er alleen een vingerafdruk van, genoeg om hem te controleren: de code zelf kan nooit meer worden getoond, en elke nieuwe kaart heeft een andere code.';
	@override String get replaces => 'Een nieuwe kaart vervangt de vorige: de oude code werkt dan niet meer.';
	@override String replaceTitle({required Object date}) => 'De kaart van ${date} vervangen?';
	@override String replaceBody({required Object date}) => 'De nieuwe kaart krijgt een andere code. De code van de kaart van ${date} werkt vanaf nu niet meer. Hij kan niet opnieuw worden getoond: Lunaway heeft er alleen een vingerafdruk van bewaard.';
	@override String get replaceKeep => 'De oude houden';
	@override String get replaceConfirm => 'Nieuwe kaart maken';
	@override String get make => 'Kaart maken';
	@override String get codeLabel => 'Je herstelcode';
	@override String get shownOnce => 'Deze code wordt maar één keer getoond. Schrijf hem op, of sla de afbeelding op, voordat je sluit.';
	@override String get saveImage => 'Afbeelding opslaan';
	@override String get done => 'Ik heb de code genoteerd';
	@override String get doneTitle => 'Heb je de code bewaard?';
	@override String get doneBody => 'Zodra deze pagina dicht is, wordt de code niet meer getoond.';
	@override String get keep => 'Op de pagina blijven';
	@override String get cardHeading => 'Lunaway-herstelkaart';
	@override String cardAccount({required Object name}) => 'Account: ${name}';
	@override String get cardHow => 'Om het account te herstellen: Profiel, Mijn account herstellen, en typ dan deze code of scan de kaart.';
	@override String cardMade({required Object date}) => 'Gemaakt op ${date}';
	@override String get cardWarning => 'Deze code opent het account: deel hem nooit.';
	@override String get failed => 'De kaart kon niet worden gemaakt. Er is een verbinding nodig.';
	@override String get fileName => 'lunaway-herstelkaart';
	@override String get step1 => 'Maak de kaart: de code wordt maar één keer getoond.';
	@override String get step2 => 'Sla de afbeelding op, druk die af, of schrijf de code over.';
	@override String get step3 => 'Bewaar de kaart in het dashboardkastje, bij de papieren van het voertuig.';
}

// Path: recover
class _Translations$recover$nl extends Translations$recover$en {
	_Translations$recover$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mijn account herstellen';
	@override String get intro => 'Typ de code van je herstelkaart, of scan een foto van de kaart.';
	@override String get field => 'Herstelcode';
	@override String get fieldHint => '27 tekens, in groepjes van vier';
	@override String remaining({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Nog ${n} teken',
		other: 'Nog ${n} tekens',
	);
	@override String get invalid => 'Deze code hoort bij geen enkele kaart: controleer elk teken.';
	@override String get valid => 'Code compleet';
	@override String get scan => 'Kaart lezen van een foto';
	@override String get scanFile => 'Afbeelding van de kaart kiezen';
	@override String get reading => 'Kaart wordt gelezen';
	@override String get scanFailed => 'Geen leesbare code op deze afbeelding. Probeer een scherpere foto, met de kaart plat neergelegd.';
	@override String get revoke => 'Mijn oude apparaat is kwijt of gestolen: daar uitloggen';
	@override String get revokeHint => 'Al je andere apparaten worden uitgelogd.';
	@override String get submit => 'Account herstellen';
	@override String get notFound => 'Geen enkel account heeft deze code. Controleer de kaart, of maak een nieuwe vanaf een apparaat waarop je bent ingelogd.';
	@override String get tooMany => 'Te veel pogingen. Probeer het over een uur opnieuw.';
	@override String done({required Object name}) => 'Account hersteld: ${name}';
}

// Path: deletion
class _Translations$deletion$nl extends Translations$deletion$en {
	_Translations$deletion$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mijn account verwijderen';
	@override String get intro => 'Het verwijderen gebeurt direct en is definitief.';
	@override String get goneTitle => 'Wat er verdwijnt';
	@override late final _Translations$deletion$gone$nl gone = _Translations$deletion$gone$nl._(_root);
	@override String get keptTitle => 'Wat blijft, zonder je naam';
	@override String get kept => 'Je gepubliceerde geschreven reviews, je bevestigingen en je doorgevoerde wijzigingen aan plekken blijven, zonder auteur: ze maken deel uit van de kaart van andere reizigers.';
	@override String get backups => 'De back-ups van de server worden binnen ongeveer 30 dagen gewist.';
	@override String get device => 'Op dit apparaat blijven je favorieten; de sleutel van het account wordt gewist.';
	@override String get web => 'Je kunt het account ook verwijderen op lunaway.net met je herstelcode.';
	@override String get webLink => 'lunaway.net/nl/account/delete';
	@override String get confirmTitle => 'Definitief verwijderen?';
	@override String confirmBody({required Object name}) => 'Het account “${name}” en alles wat hierboven staat, worden nu verwijderd. Niemand kan het terughalen.';
	@override String get confirmCheck => 'Ik begrijp dat dit definitief is';
	@override String get confirm => 'Account verwijderen';
	@override String get done => 'Account verwijderd';
	@override String get failed => 'Het account kon niet worden verwijderd. Er is een verbinding nodig.';
}

// Path: devices
class _Translations$devices$nl extends Translations$devices$en {
	_Translations$devices$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Apparaten';
	@override String get intro => 'Elk apparaat heeft een eigen sleutel. Verwijder een apparaat dat kwijt is, of een dat je niet meer gebruikt.';
	@override String get thisDevice => 'Dit apparaat';
	@override String get other => 'Ander apparaat';
	@override String added({required Object date}) => 'Toegevoegd op ${date}';
	@override String lastUsed({required Object when}) => 'Laatst gebruikt ${when}';
	@override String get revoke => 'Verwijderen';
	@override String get revokeTitle => 'Dit apparaat verwijderen?';
	@override String get revokeBody => 'Het wordt uitgelogd en kan het account niet meer gebruiken.';
	@override String get revoked => 'Apparaat verwijderd';
	@override String get signOutOthers => 'Alle andere apparaten uitloggen';
	@override String signedOutOthers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		zero: 'Geen andere sessie open',
		one: '${n} sessie gesloten',
		other: '${n} sessies gesloten',
	);
	@override String get error => 'De apparaten konden niet worden geladen. Er is een verbinding nodig.';
}

// Path: muted
class _Translations$muted$nl extends Translations$muted$en {
	_Translations$muted$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Verborgen auteurs';
	@override String get empty => 'Niemand is verborgen';
	@override String get emptyHint => 'Wil je iemand verbergen, open dan het menu bij een review of foto van die persoon. Verbergen geldt alleen voor jou.';
	@override String get unmute => 'Weer tonen';
	@override String unmuted({required Object name}) => 'Bijdragen van ${name} worden weer getoond';
}

// Path: mine
class _Translations$mine$nl extends Translations$mine$en {
	_Translations$mine$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mijn bijdragen';
	@override String get pending => 'Wacht op verzending';
	@override String get pendingHint => 'Ze worden verstuurd zodra er weer verbinding is.';
	@override String get sendNow => 'Nu versturen';
	@override String get retry => 'Opnieuw proberen';
	@override String get discard => 'Weggooien';
	@override String get discardTitle => 'Deze bijdrage weggooien?';
	@override String get discardBody => 'De bijdrage wordt niet verstuurd.';
	@override String get reviews => 'Reviews en beoordelingen';
	@override String get photos => 'Foto\'s';
	@override String get confirmations => 'Bevestigingen';
	@override String get issues => 'Gemelde problemen';
	@override String get places => 'Toegevoegde plekken en wijzigingen';
	@override String get empty => 'Nog niets';
	@override String get emptyHint => 'Een plek beoordelen of bevestigen dat hij er nog is, telt al als bijdrage.';
	@override String latest({required Object shown, required Object total}) => 'De nieuwste ${shown} van ${total}';
	@override String get error => 'Je bijdragen konden niet worden geladen. Er is een verbinding nodig.';
	@override String get deleteTitle => 'Deze bijdrage verwijderen?';
	@override String get deleteBody => 'De bijdrage verdwijnt uit Lunaway.';
	@override String get deleteApplied => 'Deze plek hoort al bij de kaart: hij blijft erop staan, zonder je naam.';
	@override String get deleted => 'Bijdrage verwijderd';
	@override String get ratingOnly => 'Alleen beoordeling';
	@override late final _Translations$mine$status$nl status = _Translations$mine$status$nl._(_root);
	@override late final _Translations$mine$submission$nl submission = _Translations$mine$submission$nl._(_root);
	@override String get newPlace => 'Nieuwe plek';
	@override String get edit => 'Wijziging';
	@override String get aPlace => 'Een plek';
	@override String get newVendingMachine => 'Nieuwe automaat';
	@override String get poiConfirmations => 'Bevestigde winkels en diensten';
	@override String get aPoi => 'Een winkel of dienst';
}

// Path: outbox
class _Translations$outbox$nl extends Translations$outbox$en {
	_Translations$outbox$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override late final _Translations$outbox$kind$nl kind = _Translations$outbox$kind$nl._(_root);
	@override String get waiting => 'Wacht op verbinding';
	@override String get sending => 'Bezig met versturen';
	@override late final _Translations$outbox$error$nl error = _Translations$outbox$error$nl._(_root);
	@override String get sent => 'Bedankt, het is verstuurd';
	@override String get queued => 'Geen verbinding: het wordt verstuurd zodra je weer online bent';
	@override String refused({required Object reason}) => 'Niet verstuurd. ${reason}';
}

// Path: placement
class _Translations$placement$nl extends Translations$placement$en {
	_Translations$placement$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Plek aanwijzen';
	@override String get hint => 'Verschuif de kaart: het kruisje geeft de exacte plek aan.';
	@override String get confirm => 'Deze plek gebruiken';
	@override String duplicate({required Object distance, required Object name}) => 'Op ${distance} ligt al “${name}”: is dat dezelfde plek?';
	@override String get same => 'Ja, de pagina openen';
	@override String get notSame => 'Nee, het is een andere plek';
}

// Path: contribute
class _Translations$contribute$nl extends Translations$contribute$en {
	_Translations$contribute$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get yourRating => 'Jouw beoordeling';
	@override String get rateHint => 'Tik op een ster om te beoordelen';
	@override String rateStar({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} ster geven',
		other: '${n} sterren geven',
	);
	@override String get writeReview => 'Review schrijven';
	@override String get editReview => 'Je review bewerken';
	@override String get deleteReview => 'Je review verwijderen';
	@override String get deleteReviewTitle => 'Je review verwijderen?';
	@override String get deleteReviewBody => 'De tekst en de beoordeling verdwijnen van de pagina.';
	@override String get deleteRating => 'Je beoordeling verwijderen';
	@override String get deleteRatingTitle => 'Je beoordeling verwijderen?';
	@override String get deleteRatingBody => 'Je beoordeling verdwijnt van de pagina van de plek.';
	@override String get pendingSend => 'Wacht op verzending';
	@override String get statusPending => 'Wordt gecontroleerd: voorlopig alleen voor jou zichtbaar';
	@override String get statusHidden => 'Verborgen na meldingen, wacht op een moderator';
	@override String get statusRemoved => 'Verwijderd door een moderator';
	@override String get addPhoto => 'Foto toevoegen';
	@override String get firstPhoto => 'Eerste foto toevoegen';
	@override String get stillThere => 'Is het er nog?';
	@override String get more => 'Meer acties';
	@override String get reportIssue => 'Probleem melden';
	@override String get proposeEdit => 'Wijziging voorstellen';
	@override String get editPlace => 'Plek bewerken';
	@override String get reportPlace => 'Deze plek melden bij de moderators';
	@override String get toVerifyTitle => 'Te controleren';
	@override String get toVerifyBody => 'Toegevoegd door de community, wacht op twee bevestigingen. Ken je deze plek? Bevestig hem.';
	@override String get issuesTitle => 'Meldingen van de afgelopen 30 dagen';
	@override String issueCount({required Object kind, required Object count}) => '${kind} (${count})';
	@override String get addPlaceHere => 'Hier een plek toevoegen';
	@override String get addPlaceHint => 'De plek onder het kruisje.';
}

// Path: confirmSheet
class _Translations$confirmSheet$nl extends Translations$confirmSheet$en {
	_Translations$confirmSheet$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Is het er nog?';
	@override String get body => 'Ben je er onlangs geweest? Met je antwoord zien andere reizigers of de pagina klopt. Er wordt geen positie verstuurd.';
	@override String get stillOk => 'Ja, zoals beschreven';
	@override String get closed => 'Gesloten';
	@override String get changed => 'Veranderd';
	@override String get closedHint => 'Ontvangt geen reizigers meer';
	@override String get changedHint => 'Bestaat nog, maar er is iets veranderd';
	@override String get note => 'Iets toe te voegen? (optioneel)';
	@override String get noteHint => 'Bijvoorbeeld: hoogtebegrenzer geplaatst, servicezuil verplaatst';
	@override late final _Translations$confirmSheet$status$nl status = _Translations$confirmSheet$status$nl._(_root);
}

// Path: issueSheet
class _Translations$issueSheet$nl extends Translations$issueSheet$en {
	_Translations$issueSheet$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Probleem melden';
	@override String get body => 'Je melding telt mee in de waarschuwing op de pagina. Je toelichting gaat alleen naar de moderators.';
	@override late final _Translations$issueSheet$kind$nl kind = _Translations$issueSheet$kind$nl._(_root);
	@override late final _Translations$issueSheet$hint$nl hint = _Translations$issueSheet$hint$nl._(_root);
	@override String get note => 'Iets toe te voegen? (optioneel)';
	@override String get send => 'Melden';
}

// Path: reportSheet
class _Translations$reportSheet$nl extends Translations$reportSheet$en {
	_Translations$reportSheet$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get review => 'Deze review melden';
	@override String get photo => 'Deze foto melden';
	@override String get place => 'Deze plek melden';
	@override String get body => 'De moderators lezen je melding. De auteur ziet niet wie de melding heeft gedaan.';
	@override late final _Translations$reportSheet$reason$nl reason = _Translations$reportSheet$reason$nl._(_root);
	@override String get note => 'Vertel meer (optioneel)';
	@override String get noteOther => 'Beschrijf wat er mis is';
	@override String get sent => 'Bedankt, de moderators gaan ernaar kijken';
	@override String mute({required Object name}) => 'Reviews en foto\'s van ${name} verbergen';
	@override String get muteAuthor => 'Deze auteur verbergen';
	@override String muteTitle({required Object name}) => '${name} verbergen?';
	@override String get muteBody => 'De reviews en foto\'s van deze persoon worden niet meer aan jou getoond. Je kunt dit terugdraaien in je profiel.';
	@override String muted({required Object name}) => '${name} is verborgen';
	@override String get deletePhoto => 'Mijn foto verwijderen';
	@override String get deletePhotoTitle => 'Deze foto verwijderen?';
	@override String get deletePhotoBody => 'De foto verdwijnt van de pagina en van onze servers.';
}

// Path: reviewSheet
class _Translations$reviewSheet$nl extends Translations$reviewSheet$en {
	_Translations$reviewSheet$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get titleNew => 'Jouw review';
	@override String get titleEdit => 'Je review bewerken';
	@override String get starsRequired => 'Kies een beoordeling van 1 tot 5';
	@override String get text => 'Jouw review';
	@override String get textHint => 'De rust, de ontvangst, de ruimte om te manoeuvreren, wat handig was';
	@override String tooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Nog minstens ${n} teken',
		other: 'Nog minstens ${n} tekens',
	);
	@override String get visited => 'Datum van het verblijf';
	@override String get visitedNone => 'Niet vermeld';
	@override String get vehicle => 'Je voertuig';
	@override String get vehicleNone => 'Zeg ik liever niet';
	@override String get licence => 'Gepubliceerd onder CC BY 4.0, met je pseudoniem. De datum van het verblijf is optioneel: samen kunnen de datums van je reviews je reisroute verraden.';
	@override String get publish => 'Review publiceren';
}

// Path: gate
class _Translations$gate$nl extends Translations$gate$en {
	_Translations$gate$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get review => 'Geschreven reviews: vanaf niveau 1';
	@override String get photo => 'Foto\'s: vanaf niveau 1';
	@override String get addPlace => 'Plekken toevoegen: vanaf niveau 2';
	@override String get edit => 'Wijzigingen voorstellen: vanaf niveau 1';
	@override String get why => 'Niveaus beschermen de kaart tegen misbruik. Ze komen met de tijd en met bijdragen, er valt niets te kopen.';
	@override String yourLevel({required Object level}) => 'Jouw niveau: ${level}';
	@override String get noAccount => 'Nog geen account: een account begint op niveau 0.';
	@override String later({required Object level}) => 'Niveau ${level} komt na de vorige niveaus, met de tijd en met gepubliceerde bijdragen.';
	@override String get meanwhile => 'Intussen kun je plekken beoordelen, bevestigen dat ze er nog zijn of een probleem melden.';
}

// Path: photoFlow
class _Translations$photoFlow$nl extends Translations$photoFlow$en {
	_Translations$photoFlow$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Foto toevoegen';
	@override String get camera => 'Foto maken';
	@override String get gallery => 'Kiezen uit de galerij';
	@override String get preparing => 'Foto wordt voorbereid';
	@override String get licence => 'Gepubliceerd onder CC BY 4.0, met je pseudoniem. Vermijd gezichten en kentekenplaten.';
	@override String get stripped => 'De locatiegegevens en de apparaatgegevens worden vóór verzending verwijderd.';
	@override String get send => 'Foto versturen';
	@override String get unreadable => 'Deze afbeelding kan op dit apparaat niet worden gelezen. Probeer een JPEG- of PNG-foto.';
	@override String sending({required Object percent}) => 'Versturen: ${percent}%';
	@override String get pending => 'Foto wacht op verzending';
}

// Path: placeForm
class _Translations$placeForm$nl extends Translations$placeForm$en {
	_Translations$placeForm$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get addTitle => 'Plek toevoegen';
	@override String get editTitle => 'Plek bewerken';
	@override String get proposeTitle => 'Wijziging voorstellen';
	@override String get position => 'Positie op de kaart';
	@override String get kind => 'Soort plek';
	@override String get kindRequired => 'Kies een soort plek';
	@override String get name => 'Naam';
	@override String get nameHint => 'De naam die ter plaatse staat, of een korte beschrijving';
	@override String get nameInvalid => '2 tot 120 tekens';
	@override String get night => 'Overnachten';
	@override String get services => 'Voorzieningen ter plaatse';
	@override String get description => 'Beschrijving';
	@override String get descriptionHint => 'Wat helpt om de plek te vinden en te kiezen';
	@override String get details => 'Details';
	@override String get priceNight => 'Prijs per nacht (€)';
	@override String get priceServices => 'Prijs van de service (€)';
	@override String get maxHeight => 'Maximale hoogte (m)';
	@override String get capacity => 'Plaatsen';
	@override String get website => 'Website';
	@override String get phone => 'Telefoon';
	@override String get photo => 'Foto (optioneel)';
	@override String get photoReady => 'Foto klaar';
	@override String get removePhoto => 'Foto verwijderen';
	@override String get toVerify => 'De plek staat als “te controleren” op de kaart tot twee andere reizigers hem bevestigen.';
	@override String get licence => 'Plekken worden gepubliceerd onder de ODbL, met vermelding van de bijdragers van Lunaway.';
	@override String get moderated => 'Een website of telefoonnummer wordt eerst door een moderator bekeken voordat het wordt gepubliceerd.';
	@override String get direct => 'Met jouw niveau wordt de wijziging meteen doorgevoerd.';
	@override String get proposal => 'Een moderator bekijkt je voorstel voordat het wordt doorgevoerd.';
	@override String get submitAdd => 'Plek toevoegen';
	@override String get submitEdit => 'Wijziging opslaan';
	@override String get submitPropose => 'Voorstel versturen';
	@override String get nothingChanged => 'Er is niets gewijzigd';
	@override String get invalidNumber => 'Vul een getal in';
	@override String get invalidWebsite => 'Een adres dat begint met http:// of https://';
	@override String get added => 'Bedankt: de plek staat zo op de kaart';
	@override String get proposed => 'Bedankt: je voorstel wordt gecontroleerd';
}

// Path: favoritesSync
class _Translations$favoritesSync$nl extends Translations$favoritesSync$en {
	_Translations$favoritesSync$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get local => 'Alleen op dit apparaat';
	@override String get action => 'Synchroniseren';
	@override String get syncing => 'Bezig met synchroniseren';
	@override String synced({required Object when}) => 'Bewaard bij je account, gesynchroniseerd ${when}';
	@override String get failed => 'Synchroniseren lukt nu niet';
	@override String get title => 'Je favorieten synchroniseren?';
	@override String get body => 'Je lijsten worden bewaard bij een Lunaway-account, zonder e-mailadres en zonder wachtwoord, zodat je ze op een ander apparaat terugvindt. Het account wordt nu aangemaakt.';
	@override String get confirm => 'Account maken en synchroniseren';
}

// Path: poi
class _Translations$poi$nl extends Translations$poi$en {
	_Translations$poi$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override late final _Translations$poi$category$nl category = _Translations$poi$category$nl._(_root);
	@override late final _Translations$poi$kind$nl kind = _Translations$poi$kind$nl._(_root);
	@override String get chipsLabel => 'Winkels en diensten in de buurt';
	@override String get openNow => 'Nu open';
	@override late final _Translations$poi$vendingSells$nl vendingSells = _Translations$poi$vendingSells$nl._(_root);
	@override String get vendingAll => 'Alle voedselautomaten';
	@override String get vendingMenu => 'Wat de automaten verkopen';
	@override late final _Translations$poi$vendingChip$nl vendingChip = _Translations$poi$vendingChip$nl._(_root);
	@override String get alwaysOpen => 'Dag en nacht open';
	@override String get hoursUnknown => 'Openingstijden onbekend';
	@override String get maybeClosed => 'Gesloten volgens het officiële register van zorginstellingen (FINESS).';
	@override String maybeClosedSince({required Object date}) => 'Sinds ${date} door FINESS als gesloten vermeld: misschien is het definitief dicht.';
	@override String get seasonal => 'Seizoensgebonden: in de winter mogelijk gesloten.';
	@override String get fee => 'Betaald';
	@override String get free => 'Gratis';
	@override String get stillThereTitle => 'Is het er nog?';
	@override String get stillThereHint => 'Onlangs gezien? Je antwoord helpt andere reizigers. Er wordt geen positie verstuurd.';
	@override String get stillThere => 'Nog aanwezig';
	@override String get gone => 'Verdwenen';
	@override String lastConfirmed({required Object when}) => 'Aanwezigheid bevestigd ${when}';
	@override String checkedOn({required Object date}) => 'Ter plaatse gecontroleerd op ${date}';
	@override String get thanksThere => 'Bedankt, genoteerd: nog aanwezig.';
	@override String get thanksGone => 'Bedankt, genoteerd: verdwenen.';
	@override String get fuelPrices => 'Brandstofprijzen';
	@override String perLitre({required Object price}) => '${price}/l';
	@override String priceUpdated({required Object when}) => 'Prijs bijgewerkt ${when}';
	@override String feedRead({required Object when}) => 'Prijzen opgehaald ${when}';
	@override String get shortageTemporary => 'Tijdelijk uitverkocht';
	@override String get shortageDefinitive => 'Wordt niet meer verkocht';
	@override String get selfService24h => '24/7 betalen aan de pomp';
	@override String get highway => 'Aan de snelweg';
	@override String get lpgYes => 'Verkoopt LPG';
	@override late final _Translations$poi$fuel$nl fuel = _Translations$poi$fuel$nl._(_root);
	@override String get products => 'Verkoopt';
	@override String get paymentTitle => 'Betaling';
	@override late final _Translations$poi$product$nl product = _Translations$poi$product$nl._(_root);
	@override late final _Translations$poi$payment$nl payment = _Translations$poi$payment$nl._(_root);
	@override String get justNow => 'zojuist';
	@override String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} minuut geleden',
		other: '${n} minuten geleden',
	);
	@override String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} uur geleden',
		other: '${n} uur geleden',
	);
	@override String readOffline({required Object when}) => 'Opgehaald ${when}: geen verbinding om te vernieuwen';
	@override String readStale({required Object when}) => 'Opgehaald ${when}: vernieuwen is nu niet gelukt.';
	@override String get goneTitle => 'Dit punt staat niet meer op de kaart';
	@override String get goneHint => 'Reizigers hebben gemeld dat het verdwenen is, of de laatste update heeft het verwijderd.';
	@override String get loadError => 'De details konden niet worden geladen. Wat de kaart weet, staat hierboven.';
	@override String get around => 'Rond deze plek';
	@override String get aroundEmpty => 'Geen winkel of dienst bekend in de buurt.';
	@override String get aroundError => 'De winkels en diensten in de buurt konden niet worden geladen.';
	@override String get aroundOffline => 'Geen verbinding: de winkels en diensten in de buurt verschijnen zodra je online bent.';
	@override String get onSite => 'Ter plaatse';
	@override String backTo({required Object name}) => 'Terug naar ${name}';
	@override String get backToPlace => 'Terug naar de plek';
	@override String get linkError => 'Deze winkel of dienst kon niet worden geopend: geen verbinding, of hij staat niet meer op de kaart.';
	@override String get searchSection => 'Winkels en diensten';
	@override String get searching => 'Winkels en diensten worden gezocht';
	@override String get searchOffline => 'Winkels en diensten worden online gezocht: nu geen verbinding.';
	@override late final _Translations$poi$add$nl add = _Translations$poi$add$nl._(_root);
	@override late final _Translations$poi$cheapest$nl cheapest = _Translations$poi$cheapest$nl._(_root);
	@override late final _Translations$poi$trend$nl trend = _Translations$poi$trend$nl._(_root);
	@override String get marketDays => 'Marktdagen';
	@override late final _Translations$poi$vehicles$nl vehicles = _Translations$poi$vehicles$nl._(_root);
}

// Path: offlineMaps
class _Translations$offlineMaps$nl extends Translations$offlineMaps$en {
	_Translations$offlineMaps$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Offline kaarten';
	@override String get intro => 'Bewaar voor vertrek een regio op het apparaat: de plekken om te zoeken en te kiezen, de kaart om de straten zonder internet te zien.';
	@override String get webTitle => 'Offline kaarten zitten in de app';
	@override String get web => 'De apps voor Android en iOS bewaren regio\'s voor onderweg. In een browser heeft de kaart internet nodig.';
	@override String get desktopTitle => 'Offline kaarten staan op de telefoon';
	@override String get desktop => 'De apps voor Android en iOS bewaren regio\'s voor onderweg. Op een computer heeft de kaart internet nodig.';
	@override String get unreadable => 'De offline kaarten van dit apparaat konden niet worden geladen.';
	@override String get none => 'Nog geen regio op dit apparaat.';
	@override String used({required Object size}) => 'Gebruikte ruimte: ${size}';
	@override String get downloads => 'Bezig met downloaden';
	@override String get installed => 'Op dit apparaat';
	@override String get suggested => 'Voorgesteld';
	@override String get here => 'Waar je bent';
	@override String favoritesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} favoriet hier',
		other: '${n} favorieten hier',
	);
	@override String get france => 'Frankrijk';
	@override String get overseas => 'Franse overzeese gebieden';
	@override String get countries => 'Landen';
	@override String downloadNamed({required Object name, required Object size}) => '${name} downloaden, ${size}';
	@override String get pause => 'Pauzeren';
	@override String get resume => 'Hervatten';
	@override String get cancel => 'Stoppen en download verwijderen';
	@override String get waiting => 'Wacht op zijn beurt';
	@override String progress({required Object done, required Object total}) => '${done} van ${total}';
	@override String paused({required Object done, required Object total}) => 'Gepauzeerd bij ${done} van ${total}';
	@override String get verifying => 'Bestand wordt gecontroleerd';
	@override String get failedNetwork => 'Gestopt: geen verbinding. Het downloaden gaat verder waar het stopte zodra er weer verbinding is.';
	@override String get failedServer => 'De server stuurde iets anders dan de kaart. Probeer het later opnieuw.';
	@override String get failedCorrupt => 'Het bestand kwam beschadigd aan en is verwijderd. Probeer het opnieuw.';
	@override String get failedStorage => 'Niet genoeg ruimte meer op het apparaat. Maak ruimte vrij en probeer het opnieuw.';
	@override String get keepOpen => 'Houd de app open tijdens het downloaden: het stopt als de app naar de achtergrond gaat en gaat verder als je terugkomt.';
	@override String dataOf({required Object date}) => 'gegevens van ${date}';
	@override String update({required Object size}) => 'Bijwerken, ${size}';
	@override String deleteNamed({required Object name}) => '${name} verwijderen';
	@override String deleteTitle({required Object name}) => '${name} van dit apparaat verwijderen?';
	@override String get deleteBody => 'Deze regio is dan niet meer zonder internet te zien. Je kunt hem opnieuw downloaden.';
	@override String get listOffline => 'Voor de lijst met regio\'s is een verbinding nodig.';
	@override String get listCopy => 'Lijst van de laatste keer dat je online was.';
	@override String get entryHint => 'Om zonder internet te reizen';
	@override String entryCount({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Kaarten: ${n} regio, ${size}',
		other: 'Kaarten: ${n} regio\'s, ${size}',
	);
	@override String noticePack({required Object name}) => 'Offline: gedownloade kaart, ${name}';
	@override String get noticeOutside => 'Offline: dit gebied is niet gedownload';
	@override String get noticePlacesOnly => 'Offline: plekken op het apparaat, kaart van dit gebied niet gedownload';
	@override String get noticeNone => 'Offline: download een regio voor de volgende keer';
	@override String get noticeOnline => 'Offline: de kaart heeft internet nodig';
	@override String get placesTitle => 'Plekken';
	@override String get placesHint => 'Een paar megabyte per regio: de lijst, het zoeken, de detailpagina\'s en de filters werken zonder internet.';
	@override String get mapsTitle => 'Kaarten';
	@override String get mapsHint => 'Alle straten, een paar honderd megabyte per regio: de kaart werkt zonder internet.';
	@override String entryPlaces({required Object names}) => 'Plekken: ${names}';
	@override String entryPlacesCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Plekken: ${n} regio',
		other: 'Plekken: ${n} regio\'s',
	);
}

// Path: regions
class _Translations$regions$nl extends Translations$regions$en {
	_Translations$regions$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get pickerTitle => 'Welke plekken wil je op dit apparaat bewaren?';
	@override String get pickerIntro => 'Elke regio wordt één keer gedownload en daarna in kleine stukjes bijgewerkt. Je kunt later in Offline kaarten regio\'s toevoegen of verwijderen.';
	@override String nearYou({required Object name}) => 'Bij jou in de buurt: ${name}';
	@override String get findMine => 'Mijn regio vinden';
	@override String get locating => 'Je regio wordt gezocht';
	@override String get notCovered => 'Nog geen Lunaway-regio bij jou in de buurt';
	@override String get wholeFrance => 'Heel Frankrijk';
	@override String get showFrance => 'De regio\'s van Frankrijk tonen';
	@override String get hideFrance => 'De regio\'s van Frankrijk verbergen';
	@override String packInfo({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${count} plek, ${size}',
		other: '${count} plekken, ${size}',
	);
	@override String get noPack => 'Geen pakket: plekken komen met de updates, grootte onbekend';
	@override String download({required Object size}) => 'Downloaden, ${size}';
	@override String get unavailable => 'De server biedt nog geen regio\'s aan: Lunaway bewaart heel Frankrijk.';
	@override String get listFailed => 'Voor de lijst met regio\'s is een verbinding nodig.';
	@override String get choose => 'Regio\'s kiezen';
	@override String get noneKept => 'Geen regio bewaard: de kaart heeft offline geen plekken.';
	@override String get change => 'Regio\'s toevoegen of verwijderen';
	@override String removeNamed({required Object name}) => '${name} verwijderen';
	@override String removed({required Object name}) => '${name}: plekken van dit apparaat verwijderd';
	@override String downloading({required Object done, required Object total}) => 'Bezig met downloaden, ${done} van ${total}';
	@override String updating({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Bezig met bijwerken, ${count} plek',
		other: 'Bezig met bijwerken, ${count} plekken',
	);
	@override String get waiting => 'wacht op download';
	@override String downloadingNamed({required Object name}) => 'Plekken downloaden: ${name}';
	@override String updated({required Object when}) => 'bijgewerkt ${when}';
	@override String offerTitle({required Object name}) => '${name}: plekken offline bewaren?';
	@override String get downloadThis => 'Deze regio downloaden';
	@override String notHere({required Object name}) => '${name} staat niet op dit apparaat';
	@override String get updatesOnMobile => 'Bijwerken via mobiele data';
	@override String get updatesOnMobileHint => 'Anders worden al gedownloade regio\'s via wifi bijgewerkt. Een nieuwe download gebruikt elk netwerk.';
}

// Path: roadReport
class _Translations$roadReport$nl extends Translations$roadReport$en {
	_Translations$roadReport$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get actionHint => 'Een probleem op de weg melden';
	@override String get title => 'Wat zie je op de weg?';
	@override String get intro => 'Je melding waarschuwt andere reizigers. Als twee betrouwbare accounts hetzelfde melden, leiden de routes eromheen. Politiecontroles kun je niet melden.';
	@override late final _Translations$roadReport$kinds$nl kinds = _Translations$roadReport$kinds$nl._(_root);
	@override String height({required Object value}) => 'Aangegeven hoogte: ${value}';
	@override String get send => 'Melden';
	@override String get sent => 'Bedankt: andere reizigers zijn gewaarschuwd.';
	@override String get stillThere => 'Nog aanwezig';
	@override String get over => 'Niet meer aanwezig';
	@override String get overSent => 'Bedankt: genoteerd.';
	@override String get fromMap => 'Hier een probleem melden';
	@override String get notHereTitle => 'Melden kan hier niet';
	@override String get lower => '10 cm lager';
	@override String get higher => '10 cm hoger';
	@override String passed({required Object what}) => 'Je bent net langsgekomen: ${what}. Is het er nog?';
	@override String notHere({required Object countries}) => 'Lunaway neemt meldingen aan waar een officiële bron ze kan controleren: ${countries}.';
}

// Path: countries
class _Translations$countries$nl extends Translations$countries$en {
	_Translations$countries$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get ad => 'Andorra';
	@override String get at => 'Oostenrijk';
	@override String get ax => 'Åland';
	@override String get be => 'België';
	@override String get ch => 'Zwitserland';
	@override String get cz => 'Tsjechië';
	@override String get de => 'Duitsland';
	@override String get dk => 'Denemarken';
	@override String get eh => 'Westelijke Sahara';
	@override String get es => 'Spanje';
	@override String get fi => 'Finland';
	@override String get fr => 'Frankrijk';
	@override String get gb => 'Verenigd Koninkrijk';
	@override String get gi => 'Gibraltar';
	@override String get gr => 'Griekenland';
	@override String get hr => 'Kroatië';
	@override String get ie => 'Ierland';
	@override String get it => 'Italië';
	@override String get li => 'Liechtenstein';
	@override String get lu => 'Luxemburg';
	@override String get ma => 'Marokko';
	@override String get mc => 'Monaco';
	@override String get nl => 'Nederland';
	@override String get no => 'Noorwegen';
	@override String get pl => 'Polen';
	@override String get pt => 'Portugal';
	@override String get se => 'Zweden';
	@override String get si => 'Slovenië';
	@override String get sj => 'Spitsbergen';
	@override String get sm => 'San Marino';
	@override String get va => 'Vaticaanstad';
}

// Path: areas
class _Translations$areas$nl extends Translations$areas$en {
	_Translations$areas$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get ara => 'Auvergne-Rhône-Alpes';
	@override String get bfc => 'Bourgogne-Franche-Comté';
	@override String get bre => 'Bretagne';
	@override String get cvl => 'Centre-Val de Loire';
	@override String get cor => 'Corsica';
	@override String get ges => 'Grand Est';
	@override String get hdf => 'Hauts-de-France';
	@override String get idf => 'Île-de-France';
	@override String get nor => 'Normandië';
	@override String get naq => 'Nouvelle-Aquitaine';
	@override String get occ => 'Occitanië';
	@override String get pdl => 'Pays de la Loire';
	@override String get pac => 'Provence-Alpes-Côte d\'Azur';
	@override String get gp => 'Guadeloupe';
	@override String get mq => 'Martinique';
	@override String get gf => 'Frans-Guyana';
	@override String get re => 'Réunion';
	@override String get yt => 'Mayotte';
	@override String get franceRest => 'Frankrijk, overig';
}

// Path: search.addressKind
class _Translations$search$addressKind$nl extends Translations$search$addressKind$en {
	_Translations$search$addressKind$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get houseNumber => 'Adres';
	@override String get street => 'Straat';
	@override String get locality => 'Plaats';
	@override String get town => 'Gemeente';
	@override String get postcode => 'Postcode';
	@override String get region => 'Regio';
}

// Path: place.inclusions
class _Translations$place$inclusions$nl extends Translations$place$inclusions$en {
	_Translations$place$inclusions$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get services => 'voorzieningen';
	@override String get touristTax => 'toeristenbelasting';
	@override String get electricity => 'stroom';
}

// Path: place.reviewVehicle
class _Translations$place$reviewVehicle$nl extends Translations$place$reviewVehicle$en {
	_Translations$place$reviewVehicle$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get van => 'Busje';
	@override String get campervan => 'Buscamper';
	@override String get motorhome => 'Camper';
	@override String get caravan => 'Caravan';
	@override String get other => 'Ander voertuig';
}

// Path: sources.extcom
class _Translations$sources$extcom$nl extends Translations$sources$extcom$en {
	_Translations$sources$extcom$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get label => 'Externe communitybron';
	@override String get short => 'Extern';
}

// Path: hours.codes
class _Translations$hours$codes$nl extends Translations$hours$codes$en {
	_Translations$hours$codes$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get mo => 'ma';
	@override String get tu => 'di';
	@override String get we => 'wo';
	@override String get th => 'do';
	@override String get fr => 'vr';
	@override String get sa => 'za';
	@override String get su => 'zo';
	@override String get ph => 'feestdagen';
	@override String get sh => 'schoolvakanties';
	@override String get off => 'gesloten';
	@override String get closed => 'gesloten';
	@override String get sunrise => 'zonsopgang';
	@override String get sunset => 'zonsondergang';
}

// Path: hours.months
class _Translations$hours$months$nl extends Translations$hours$months$en {
	_Translations$hours$months$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get jan => 'jan.';
	@override String get feb => 'feb.';
	@override String get mar => 'mrt.';
	@override String get apr => 'apr.';
	@override String get may => 'mei';
	@override String get jun => 'jun.';
	@override String get jul => 'jul.';
	@override String get aug => 'aug.';
	@override String get sep => 'sep.';
	@override String get oct => 'okt.';
	@override String get nov => 'nov.';
	@override String get dec => 'dec.';
}

// Path: navigation.preview
class _Translations$navigation$preview$nl extends Translations$navigation$preview$en {
	_Translations$navigation$preview$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String titleTo({required Object name}) => 'Naar ${name}';
	@override String get titlePoint => 'Punt op de kaart';
	@override late final _Translations$navigation$preview$departure$nl departure = _Translations$navigation$preview$departure$nl._(_root);
	@override String get computing => 'Route wordt berekend voor je voertuig';
	@override String get start => 'Starten';
	@override String get recommended => 'Aanbevolen';
	@override String alternative({required Object n}) => 'Alternatief ${n}';
	@override String get toll => 'Tol';
	@override String get ferry => 'Veerboot';
	@override String get motorway => 'Snelweg';
	@override String get noWarnings => 'Geen beperkingen op deze route die krap zijn voor je voertuig.';
	@override String warnings({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '1 beperking om op te letten',
		other: '${n} beperkingen om op te letten',
	);
	@override String get vehicle => 'Je voertuig';
	@override String vehicleTowing({required Object vehicle}) => '${vehicle}, met aanhanger';
	@override String get editVehicle => 'Wijzigen';
	@override String cruise({required Object speed}) => 'Berekend met max. ${speed}';
	@override String get avoid => 'Vermijden';
	@override String get avoidTolls => 'Tolwegen';
	@override String get avoidMotorways => 'Snelwegen';
	@override String get avoidFerries => 'Veerboten';
	@override String get avoidUnpaved => 'Onverharde wegen';
	@override String get roadbook => 'Routebeschrijving';
	@override String get roadbookShow => 'Routebeschrijving tonen';
	@override String get roadbookHide => 'Routebeschrijving verbergen';
	@override String dataOf({required Object date}) => 'Weggegevens van ${date}';
	@override String get attributionOsm => '© bijdragers van OpenStreetMap';
	@override String attributionIgn({required Object date}) => 'IGN, BD TOPO, editie van ${date}';
	@override String get otherApps => 'Openen in…';
	@override String get back => 'Terug';
	@override late final _Translations$navigation$preview$moved$nl moved = _Translations$navigation$preview$moved$nl._(_root);
}

// Path: navigation.stops
class _Translations$navigation$stops$nl extends Translations$navigation$stops$en {
	_Translations$navigation$stops$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Tussenstops';
	@override String get add => 'Toevoegen als tussenstop';
	@override String addCost({required Object minutes}) => 'Toevoegen als tussenstop · +${minutes} min';
	@override String get addFree => 'Toevoegen als tussenstop · geen omweg';
	@override String get quoting => 'Toevoegen als tussenstop · omweg wordt berekend';
	@override String get noRoute => 'Geen route via dit punt voor je voertuig.';
	@override String get full => 'Maximaal vijf tussenstops.';
	@override String get goDirectly => 'Rechtstreeks erheen';
	@override String get openCard => 'Details bekijken';
	@override String get point => 'Punt op de kaart';
	@override String get remove => 'Tussenstop verwijderen';
	@override String get reorder => 'Sleep om de volgorde te wijzigen';
	@override String get added => 'Tussenstop toegevoegd';
	@override String get removed => 'Tussenstop verwijderd';
	@override String get moved => 'Volgorde van de tussenstops gewijzigd';
	@override String get destinationChanged => 'Nieuwe bestemming';
	@override String get failed => 'De route kon niet worden gewijzigd.';
	@override String get noQuote => 'De omweg kon niet worden berekend.';
	@override String get offline => 'Geen verbinding om de omweg te berekenen.';
}

// Path: navigation.legs
class _Translations$navigation$legs$nl extends Translations$navigation$legs$en {
	_Translations$navigation$legs$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get all => 'Alles';
	@override String stop({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}';
	@override String stopSaid({required Object number, required Object name, required Object time, required Object distance}) => 'Tussenstop ${number}: ${name}, rond ${time}, over ${distance}';
	@override String arrival({required Object name, required Object time}) => 'Bestemming · ${name} · ${time}';
	@override String arrivalSaid({required Object name, required Object time}) => 'Bestemming: ${name}, rond ${time}';
	@override String remove({required Object number, required Object name}) => 'Tussenstop ${number} verwijderen, ${name}';
}

// Path: navigation.fuel
class _Translations$navigation$fuel$nl extends Translations$navigation$fuel$en {
	_Translations$navigation$fuel$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String price({required Object price}) => '€ ${price}/l';
	@override String withDetour({required Object price}) => '€ ${price}/l incl. omweg';
	@override String detour({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min';
	@override String get onRoute => 'op de route';
	@override String get open => 'Open';
	@override String get closed => 'Gesloten';
	@override String get unknownHours => 'Openingstijden onbekend';
	@override String get add => 'Toevoegen';
	@override String get station => 'Tankstation';
	@override String get empty => 'Geen tankstation met deze brandstof in de buurt van de route.';
	@override String get failed => 'De tankstations konden niet worden geladen.';
	@override String get estimated => 'Omwegen geschat op basis van de afstand tot de route.';
	@override String get attribution => 'Prijzen: Frans ministerie van Economie (data.economie.gouv.fr)';
	@override String minutesAgo({required Object n}) => '${n} min geleden';
	@override String hoursAgo({required Object n}) => '${n} uur geleden';
	@override String daysAgo({required Object n}) => '${n} dagen geleden';
}

// Path: navigation.onTheWay
class _Translations$navigation$onTheWay$nl extends Translations$navigation$onTheWay$en {
	_Translations$navigation$onTheWay$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Onderweg';
	@override late final _Translations$navigation$onTheWay$categories$nl categories = _Translations$navigation$onTheWay$categories$nl._(_root);
	@override String fuelOfVehicle({required Object fuel}) => '${fuel}, volgens je voertuig';
	@override String get otherFuel => 'Andere brandstof';
	@override String get keepFuel => 'Bewaren als mijn brandstof';
	@override String fuelKept({required Object fuel}) => '${fuel} bewaard voor je voertuig.';
	@override String get keepFuelFailed => 'De brandstof kon niet worden bewaard.';
	@override String get loading => 'Zoeken langs de route';
	@override String get empty => 'Geen resultaten op deze route';
	@override String get emptyHint => 'Probeer een andere categorie, of open de lijst verderop opnieuw.';
	@override String get failed => 'De lijst kon niet worden geladen.';
	@override String get offline => 'Geen verbinding: de lijst komt terug met de verbinding.';
	@override String get rateLimited => 'Veel zoekopdrachten achter elkaar: probeer het over een paar minuten opnieuw.';
	@override String nearNone({required Object distance}) => 'Niets in de komende ${distance}.';
	@override String further({required Object n}) => 'Verderop (${n})';
	@override String get more => 'Meer tonen';
	@override String get moreFailed => 'De rest kon niet worden geladen.';
	@override String ahead({required Object distance}) => 'over ${distance}';
	@override String offRoute({required Object distance}) => '${distance} van de route';
	@override String get byTheRoad => 'langs de weg';
	@override String addCost({required Object minutes}) => 'Toevoegen · +${minutes} min';
	@override String get addFree => 'Toevoegen · geen omweg';
	@override String openAt({required Object time}) => 'Open als je langskomt, rond ${time}';
	@override String closedAt({required Object time}) => 'Gesloten als je langskomt, rond ${time}';
	@override String closedOpensAt({required Object time, required Object opens}) => 'Gesloten als je rond ${time} langskomt, opent om ${opens}';
	@override String perNight({required Object price}) => '${price} per nacht';
	@override String photoFrom({required Object source}) => 'Foto: ${source}';
	@override String servicesList({required Object list}) => 'Voorzieningen: ${list}';
	@override String get placesCredit => 'Plekken: Lunaway en de bronnen op elke detailpagina';
}

// Path: navigation.states
class _Translations$navigation$states$nl extends Translations$navigation$states$en {
	_Translations$navigation$states$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get vehicleTitle => 'Waarmee rijd je?';
	@override String get vehicleHint => 'De route vermijdt te lage bruggen, te smalle straten en wegen die verboden zijn voor je afmetingen. Vul de hoogte, breedte, lengte en het gewicht in.';
	@override String vehicleMissing({required Object list}) => 'Ontbreekt: ${list}';
	@override String vehicleOutOfBounds({required Object list}) => 'Buiten de toegestane waarden: ${list}';
	@override late final _Translations$navigation$states$dimension$nl dimension = _Translations$navigation$states$dimension$nl._(_root);
	@override String get describeVehicle => 'Mijn voertuig beschrijven';
	@override String get originTitle => 'Waar ben je?';
	@override String get originHint => 'Lunaway heeft je positie nodig om de route te berekenen.';
	@override String get locate => 'Mijn positie bepalen';
	@override String get offlineTitle => 'Geen verbinding';
	@override String get offlineHint => 'Routes worden berekend op de server van Lunaway. Zonder internet geeft “Openen in…” de rit door aan een navigatie-app met eigen kaarten.';
	@override String get rateLimitedTitle => 'Te veel routeaanvragen';
	@override String rateLimitedHint({required Object seconds}) => 'Probeer het over ${seconds} s opnieuw.';
	@override String get unavailableTitle => 'Routeberekening niet beschikbaar';
	@override String get unavailableHint => 'De routeservice is op dit moment niet bereikbaar. Probeer het later opnieuw.';
	@override String get refusedTitle => 'Geen route mogelijk';
	@override String get refusedHint => 'Lunaway kon voor deze aanvraag geen route berekenen: controleer de bestemming, de lengte van de rit en de waarden van het voertuig.';
	@override String get noSafeTitle => 'Geen veilige route voor je voertuig';
	@override String get noSafeHint => 'Op elke mogelijke weg geldt een beperking waar je voertuig niet aan voldoet:';
	@override String get whatToDo => 'Wat je kunt doen';
	@override String checkVehicle({required Object height, required Object weight}) => 'Controleer de ingevoerde waarden: ${height} hoog, ${weight}.';
	@override String get pickOtherPoint => 'Kies een bestemming vóór het obstakel: druk lang op de kaart.';
	@override String get noRouteTitle => 'Geen weg naar dit punt';
	@override String get noRouteHint => 'Het punt ligt misschien aan een privéweg, of op een eiland zonder veerboot.';
	@override String get allowUnpaved => 'Onverharde wegen worden vermeden: sta ze toe als de bestemming aan een onverharde weg ligt.';
	@override String get offNetworkTitle => 'Te ver van een weg';
	@override String get offNetworkHint => 'Kies een bestemming aan een weg.';
}

// Path: navigation.noRoute
class _Translations$navigation$noRoute$nl extends Translations$navigation$noRoute$en {
	_Translations$navigation$noRoute$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get originUnreachable => 'Je voertuig kan hier niet vertrekken';
	@override String originUnreachableBy({required Object limit}) => 'Je voertuig kan hier niet vertrekken: ${limit}';
	@override String get destinationUnreachable => 'Bestemming onbereikbaar voor je voertuig';
	@override String destinationUnreachableBy({required Object limit}) => 'Bestemming onbereikbaar voor je voertuig: ${limit}';
	@override String waypointUnreachable({required Object n}) => 'Tussenstop ${n} onbereikbaar voor je voertuig';
	@override String waypointUnreachableBy({required Object n, required Object limit}) => 'Tussenstop ${n} onbereikbaar voor je voertuig: ${limit}';
	@override String get blockedOnTheWay => 'Geen doorgang voor je voertuig onderweg';
	@override String blockedOnTheWayBy({required Object limit}) => 'Geen doorgang voor je voertuig onderweg: ${limit}';
	@override String get blockedHint => 'Elke tussenstop is bereikbaar, maar op elke weg ertussen geldt een beperking waar je voertuig niet aan voldoet.';
	@override String get notConnectedOrigin => 'Geen weg vanaf je positie';
	@override String get notConnectedDestination => 'Geen weg naar de bestemming';
	@override String notConnectedWaypoint({required Object n}) => 'Geen weg naar tussenstop ${n}';
	@override String get notConnectedTrip => 'Geen weg die je tussenstops verbindt';
	@override String get notConnectedHint => 'Dit ligt niet aan je voertuig: een eiland zonder autoveer, of een weg die voor alle verkeer is afgesloten.';
	@override String get outsideOrigin => 'Je positie ligt buiten het gebied waar routes worden berekend';
	@override String get outsideDestination => 'Bestemming buiten het gebied waar routes worden berekend';
	@override String outsideWaypoint({required Object n}) => 'Tussenstop ${n} buiten het gebied waar routes worden berekend';
	@override String outsideHint({required Object countries}) => 'Lunaway berekent routes in deze landen: ${countries}.';
	@override String get outsideHintUnknown => 'Lunaway berekent nog geen routes in dit land.';
	@override String get noRoadOrigin => 'Je positie ligt te ver van een weg';
	@override String get noRoadDestination => 'Bestemming te ver van een weg';
	@override String noRoadWaypoint({required Object n}) => 'Tussenstop ${n} te ver van een weg';
	@override String get noRoadHint => 'Geen weg die je voertuig mag nemen binnen 5 km van dit punt.';
	@override String get tooLong => 'Rit te lang';
	@override String tooLongHint({required Object trip, required Object max}) => '${trip} hemelsbreed van tussenstop tot tussenstop: Lunaway berekent ritten tot ${max}.';
	@override String vehicleValue({required Object value}) => 'Je voertuig: ${value}';
	@override late final _Translations$navigation$noRoute$limit$nl limit = _Translations$navigation$noRoute$limit$nl._(_root);
	@override String get editVehicle => 'Voertuig wijzigen';
	@override String get allowUnpaved => 'Onverharde wegen toestaan';
	@override String removeStop({required Object n}) => 'Tussenstop ${n} verwijderen';
	@override String removeStopNamed({required Object name}) => 'Tussenstop “${name}” verwijderen';
	@override String get placesAround => 'Plekken rond de bestemming bekijken';
	@override String get moveDestination => 'Of kies een andere bestemming: druk lang op de kaart en kies dan “Rechtstreeks erheen”.';
	@override String get moveStop => 'Voor een andere tussenstop: zoom in en tik op de kaart, of druk lang op de kaart, en kies dan “Toevoegen als tussenstop”.';
	@override String get moveOrigin => 'Het vertrekpunt is je positie: rijd naar een weg die je voertuig mag nemen en probeer het opnieuw.';
	@override String get pickInside => 'Kies een bestemming in een van deze landen.';
	@override String get shorter => 'Kies een bestemming die dichterbij ligt, of maak de rit in meerdere etappes.';
}

// Path: navigation.ferry
class _Translations$navigation$ferry$nl extends Translations$navigation$ferry$en {
	_Translations$navigation$ferry$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String title({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Veerovertocht',
		other: '${n} veerovertochten',
	);
	@override String get unnamed => 'Veerboot';
	@override String named({required Object name}) => 'Veerboot ${name}';
	@override String ports({required Object ports}) => 'Havens: ${ports}';
	@override String countries({required Object from, required Object to}) => 'Inschepen: ${from} · Ontschepen: ${to}';
	@override String country({required Object country}) => 'Land: ${country}';
	@override String where({required Object distance, required Object sea, required Object duration}) => 'Op ${distance} van het vertrekpunt · ${sea} over zee, ongeveer ${duration}';
	@override String get needed => 'De bestemming is niet bereikbaar zonder veerboot: de route neemt er een, ook al vermijd je veerboten.';
}

// Path: navigation.warning
class _Translations$navigation$warning$nl extends Translations$navigation$warning$en {
	_Translations$navigation$warning$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$warning$lowClearance$nl lowClearance = _Translations$navigation$warning$lowClearance$nl._(_root);
	@override String get unknownClearance => 'Lage doorrijhoogte, hoogte onbekend';
	@override String narrow({required Object limit}) => 'Versmalling ${limit}';
	@override String tooLong({required Object limit}) => 'Maximale lengte ${limit}';
	@override String tooHeavy({required Object limit}) => 'Maximumgewicht ${limit}';
	@override String axleLoad({required Object limit}) => 'Maximale aslast ${limit}';
	@override String get motorhomeBan => 'Verboden voor campers';
	@override String get trailerBan => 'Verboden voor aanhangers';
	@override String goodsVehicleWeight({required Object limit}) => 'Maximumgewicht vrachtverkeer ${limit}';
	@override String yours({required Object value}) => 'je voertuig: ${value}';
	@override String fromStart({required Object distance}) => 'op ${distance} van het vertrekpunt';
	@override String ahead({required Object distance}) => 'over ${distance}';
	@override String get disputed => 'bronnen spreken elkaar tegen, de laagste waarde geldt';
	@override String get goodsOnly => 'geldt voor vrachtwagens, let op de borden';
	@override String get osm => 'OpenStreetMap';
	@override String get ign => 'IGN BD TOPO';
	@override String get community => 'Lunaway-melding';
	@override String get dialog => 'Verkeersbesluit (DiaLog)';
	@override late final _Translations$navigation$warning$localAccess$nl localAccess = _Translations$navigation$warning$localAccess$nl._(_root);
}

// Path: navigation.roadEvents
class _Translations$navigation$roadEvents$nl extends Translations$navigation$roadEvents$en {
	_Translations$navigation$roadEvents$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Werkzaamheden en afsluitingen';
	@override String get none => 'Geen werkzaamheden of afsluitingen bekend op deze route.';
	@override String get stale => 'Werkzaamheden en afsluitingen: de bronnen zijn al een tijd niet bijgewerkt.';
	@override String avoided({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Route berekend om een afsluiting heen: ${names}',
		other: 'Route berekend om ${n} afsluitingen heen: ${names}',
	);
	@override String atDistance({required Object distance}) => 'op ${distance} van het vertrekpunt';
	@override String more({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'En nog ${n} op de route',
		other: 'En nog ${n} op de route',
	);
	@override String get classClosure => 'Weg afgesloten';
	@override String get classWorks => 'Werkzaamheden';
	@override String get classLaneRestriction => 'Rijstroken afgesloten';
	@override String get classVehicleLimit => 'Voertuigbeperking';
	@override String get classDetour => 'Omleiding aangegeven';
	@override String get reasonUnmatched => 'positie onzeker, misschien op de route';
	@override String get reasonStale => 'bron al een tijd niet bijgewerkt';
	@override String get reasonOutsideHours => 'waarschijnlijk niet op dit tijdstip';
	@override String get reasonGoodsVehicles => 'voor vrachtwagens';
	@override String get reasonUnconfirmed => 'gemeld door één reiziger';
	@override String get reasonAged => 'oude melding';
	@override String get reasonInside => 'de route begint of eindigt in het afgesloten stuk';
	@override String get reasonNearLimit => 'met weinig marge';
	@override String get reasonOverLimit => 'je voertuig overschrijdt de limiet';
}

// Path: navigation.marks
class _Translations$navigation$marks$nl extends Translations$navigation$marks$en {
	_Translations$navigation$marks$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get legend => 'Legenda';
	@override String get legendHide => 'Legenda inklappen';
	@override String get kindOrigin => 'Vertrek';
	@override String get kindDestination => 'Bestemming';
	@override String get kindStop => 'Tussenstop';
	@override String get kindClosure => 'Weg afgesloten';
	@override String get kindWorks => 'Werkzaamheden';
	@override String get kindLanes => 'Rijstroken afgesloten';
	@override String get kindClearance => 'Hoogtebeperking';
	@override String get kindWeight => 'Gewichtsbeperking';
	@override String get kindLimit => 'Andere beperking (breedte, lengte, verbod)';
	@override String get kindFuel => 'Tankstation';
	@override String get kindPlace => 'Plek bij de route';
	@override String get groupLegend => 'Markeringen dicht bij elkaar, gegroepeerd';
	@override String get zoneLegend => 'Gevarenzone';
	@override String zonesFrom({required Object source, required Object date}) => 'Gevarenzones: ${source}, lijst van ${date}';
	@override String group({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} markering',
		other: '${n} markeringen',
	);
	@override String get groupHint => 'Zoom in om ze een voor een te zien';
	@override String count({required Object kind, required Object n}) => '${kind}: ${n}';
	@override String stop({required Object n}) => 'Tussenstop ${n}';
	@override String get origin => 'Vertrekpunt';
	@override String get nearRoute => 'Bij de route';
	@override String get avoided => 'De route gaat eromheen';
	@override String get blocking => 'Blokkeert elke route';
	@override String get showInList => 'In de lijst bekijken';
	@override String get showAll => 'Alles tonen';
	@override String get onMap => 'op de kaart tonen';
	@override String price({required Object price}) => '€ ${price}';
	@override String get kindCamera => 'Flitser';
	@override String cameras({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} flitser',
		other: '${n} flitsers',
	);
	@override String camerasFrom({required Object source, required Object date}) => 'Flitsers: ${source}, lijst van ${date}';
	@override String bothFrom({required Object source, required Object date}) => 'Flitsers en gevarenzones: ${source}, lijst van ${date}';
	@override String sectionLength({required Object distance}) => 'Traject van ${distance}';
	@override String get cameraDirection => 'Controleert jouw rijrichting';
}

// Path: navigation.guidance
class _Translations$navigation$guidance$nl extends Translations$navigation$guidance$en {
	_Translations$navigation$guidance$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get then => 'Daarna';
	@override String arrival({required Object time}) => 'Aankomst ${time}';
	@override String get offRoute => 'Van de route af';
	@override String get rerouting => 'Nieuwe route wordt gezocht';
	@override String get rerouted => 'Nieuwe route';
	@override String reroutedLonger({required Object minutes}) => 'Nieuwe route, ${minutes} min langer';
	@override String get rerouteOffline => 'Geen verbinding voor een nieuwe route: keer terug naar de route';
	@override String get rerouteFailed => 'Geen nieuwe route gevonden: keer terug naar de route';
	@override String closureAhead({required Object distance}) => 'Weg afgesloten over ${distance}: andere route wordt gezocht';
	@override String noDetour({required Object distance}) => 'Weg afgesloten over ${distance}: geen andere weg';
	@override String eventAhead({required Object distance}) => 'Werkzaamheden over ${distance}';
	@override String eventClosure({required Object distance}) => 'Weg afgesloten over ${distance}';
	@override String eventLimit({required Object distance}) => 'Voertuigbeperking door werkzaamheden over ${distance}';
	@override String eventSource({required Object source, required Object time}) => '${source}, gegevens van ${time}';
	@override String eventSourceOn({required Object source, required Object day, required Object time}) => '${source}, gegevens van ${day} om ${time}';
	@override String avoidedClosures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: 'Route berekend om een afsluiting heen',
		other: 'Route berekend om ${n} afsluitingen heen',
	);
	@override String roadEventAhead({required Object what, required Object distance}) => '${what} over ${distance}';
	@override String closureOffline({required Object distance}) => 'Weg afgesloten over ${distance}: geen verbinding om een andere route te zoeken';
	@override String closureFailed({required Object distance}) => 'Weg afgesloten over ${distance}: nog geen andere weg';
	@override late final _Translations$navigation$guidance$voiceMode$nl voiceMode = _Translations$navigation$guidance$voiceMode$nl._(_root);
	@override String get overview => 'Hele route';
	@override String get recenter => 'Centreren';
	@override String get end => 'Stoppen';
	@override String get endTitle => 'Navigatie stoppen?';
	@override String get endConfirm => 'Stoppen';
	@override String get endKeep => 'Doorgaan';
	@override String get stopTitle => 'Navigatie stoppen?';
	@override String get stopConfirm => 'Stoppen';
	@override String get arrivedTitle => 'Je bent aangekomen';
	@override String get done => 'Klaar';
	@override String get speed => 'Snelheid';
	@override String get limit => 'Limiet';
	@override String noVoice({required Object language}) => 'Geen stem in het ${language} op dit apparaat: instructies alleen op het scherm.';
	@override String missingVoice({required Object language}) => 'De stem in het ${language} is nog niet gedownload.';
	@override String get installVoice => 'Installeren';
	@override String get voiceSettingsIos => 'Instellingen, Toegankelijkheid, Gesproken materiaal, Stemmen';
	@override String get notificationTitle => 'Lunaway wijst je de weg';
	@override String get notificationText => 'De navigatie gaat door als het scherm uitstaat.';
	@override String get notificationChannel => 'Navigatie';
	@override String get unavailable => 'De navigatie kon op dit apparaat niet starten.';
	@override late final _Translations$navigation$guidance$notificationWhy$nl notificationWhy = _Translations$navigation$guidance$notificationWhy$nl._(_root);
	@override String get positionLost => 'Positie niet beschikbaar: controleer of locatie op het apparaat aanstaat voor Lunaway.';
	@override String positionStale({required Object minutes}) => 'Laatste positie ${minutes} min geleden ontvangen: de aankomsttijd is daarop gebaseerd.';
	@override String get limitEstimated => 'Geschatte limiet';
	@override String get overLimit => 'boven de limiet';
	@override String enforcementSource({required Object source, required Object date}) => '${source}, lijst van ${date}';
	@override String get demoDrive => 'Gesimuleerde rit: demonstratie zonder gps';
	@override late final _Translations$navigation$guidance$places$nl places = _Translations$navigation$guidance$places$nl._(_root);
}

// Path: navigation.voice
class _Translations$navigation$voice$nl extends Translations$navigation$voice$en {
	_Translations$navigation$voice$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get rerouting => 'Route wordt opnieuw berekend.';
	@override String get rerouted => 'Nieuwe route.';
	@override String reroutedLonger({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(minutes,
		one: 'Nieuwe route, één minuut langer.',
		other: 'Nieuwe route, ${minutes} minuten langer.',
	);
	@override late final _Translations$navigation$voice$moved$nl moved = _Translations$navigation$voice$moved$nl._(_root);
	@override String closureAhead({required Object distance}) => 'Over ${distance} is de weg afgesloten. Er wordt een andere route gezocht.';
	@override String noDetour({required Object distance}) => 'Over ${distance} is de weg afgesloten. Er is geen andere route.';
	@override String clearance({required Object distance, required Object height}) => 'Let op, over ${distance} een lage doorrijhoogte van ${height}.';
	@override String unknownClearance({required Object distance}) => 'Let op, over ${distance} een lage doorrijhoogte, hoogte onbekend.';
	@override String narrow({required Object distance, required Object width}) => 'Let op, over ${distance} een versmalling tot ${width}.';
	@override String limit({required Object distance, required Object what}) => 'Let op, over ${distance}: ${what}.';
	@override String get arrived => 'Je bent aangekomen.';
	@override String metres({required Object n}) => '${n} meter';
	@override String kilometres({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count,
		one: '${n} kilometer',
		other: '${n} kilometer',
	);
	@override String feet({required Object n}) => '${n} voet';
	@override String miles({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count,
		one: '${n} mijl',
		other: '${n} mijl',
	);
	@override String size({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count,
		one: '${metres} meter ${cm}',
		other: '${metres} meter ${cm}',
	);
	@override String sizeWhole({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count,
		one: '${metres} meter',
		other: '${metres} meter',
	);
	@override String overSpeed({required Object limit}) => 'Maximumsnelheid ${limit}.';
	@override String dangerZone({required Object distance}) => 'Over ${distance} een gevarenzone.';
	@override String get inDangerZone => 'Gevarenzone.';
	@override late final _Translations$navigation$voice$localAccess$nl localAccess = _Translations$navigation$voice$localAccess$nl._(_root);
	@override late final _Translations$navigation$voice$roadEvent$nl roadEvent = _Translations$navigation$voice$roadEvent$nl._(_root);
	@override String get positionLost => 'Positie niet beschikbaar. Controleer de locatie van het apparaat.';
	@override String tonnes({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count,
		one: '${n} ton',
		other: '${n} ton',
	);
	@override late final _Translations$navigation$voice$camera$nl camera = _Translations$navigation$voice$camera$nl._(_root);
}

// Path: navigation.units
class _Translations$navigation$units$nl extends Translations$navigation$units$en {
	_Translations$navigation$units$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String ft({required Object n}) => '${n} ft';
	@override String mi({required Object n}) => '${n} mi';
	@override String get kmh => 'km/u';
	@override String get mph => 'mph';
	@override String hoursMinutes({required Object h, required Object m}) => '${h} u ${m} min';
	@override String minutes({required Object m}) => '${m} min';
}

// Path: navigation.settings
class _Translations$navigation$settings$nl extends Translations$navigation$settings$en {
	_Translations$navigation$settings$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Navigatie';
	@override String get avoidTitle => 'Standaard vermijden';
	@override String get voice => 'Gesproken navigatie';
	@override String get voiceFull => 'Volledig';
	@override String get voiceAlerts => 'Waarschuwingen';
	@override String get voiceMuted => 'Uit';
	@override String get voiceFullHint => 'De instructies en de waarschuwingen, met de stem van het apparaat.';
	@override String get voiceAlertsHint => 'Alleen flitsers en gevarenzones, afsluitingen, werkzaamheden en voertuigbeperkingen op je route, en routewijzigingen, na een kort signaal.';
	@override String get voiceMutedHint => 'Geen geluid: de instructies en de waarschuwingen staan op het scherm.';
	@override String get units => 'Afstanden';
	@override String get metric => 'Kilometers';
	@override String get imperial => 'Mijlen';
	@override String get speedLimit => 'Maximumsnelheid';
	@override String get speedLimitHint => 'Toont tijdens het navigeren de maximumsnelheid voor je voertuig naast je snelheid; een schatting staat in grijs.';
	@override String get speedSound => 'Gesproken snelheidswaarschuwing';
	@override String get speedSoundHint => 'Een korte waarschuwing als je te hard rijdt, met de volledige stem. Flitsers en gevarenzones volgen de gesproken navigatie.';
	@override String get exactFrance => 'Exacte locatie van flitsers in Frankrijk';
	@override String get exactFranceHint => 'In Frankrijk wordt het bezit van een apparaat dat de locatie van flitsers aangeeft bestraft met een boete van € 1.500 en 6 punten (Code de la route, art. R413-15).';
}

// Path: navigation.enforcement
class _Translations$navigation$enforcement$nl extends Translations$navigation$enforcement$en {
	_Translations$navigation$enforcement$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get fixed => 'Vaste flitser';
	@override String get redLight => 'Roodlichtcamera';
	@override String get levelCrossing => 'Flitser bij overweg';
	@override String get section => 'Trajectcontrole';
	@override String get zone => 'Gevarenzone';
	@override String average({required Object limit}) => 'gemiddeld ${limit}';
	@override String get averageLabel => 'gemiddeld';
	@override String remaining({required Object distance}) => 'nog ${distance}';
	@override String yourAverage({required Object speed}) => 'je gemiddelde ${speed}';
	@override String get zoneEnd => 'Einde gevarenzone';
	@override String get sectionEnd => 'Einde trajectcontrole';
	@override String ruleOff({required Object country}) => '${country}: geen flitserwaarschuwingen';
	@override String ruleZones({required Object country}) => '${country}: gevarenzones';
	@override String ruleExact({required Object country}) => '${country}: flitsers';
	@override String ahead({required Object what, required Object distance}) => '${what} over ${distance}';
	@override String limit({required Object limit}) => 'maximaal ${limit}';
	@override String averageLimit({required Object limit}) => 'gemiddeld maximaal ${limit}';
}

// Path: vehicle.types
class _Translations$vehicle$types$nl extends Translations$vehicle$types$en {
	_Translations$vehicle$types$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get van => 'Busje';
	@override String get campervan => 'Buscamper';
	@override String get lowProfile => 'Halfintegraal';
	@override String get overcab => 'Alkoof';
	@override String get integrated => 'Integraal';
}

// Path: vehicle.towing
class _Translations$vehicle$towing$nl extends Translations$vehicle$towing$en {
	_Translations$vehicle$towing$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get none => 'Niets';
	@override String get car => 'Een auto';
	@override String get trailer => 'Een aanhanger';
}

// Path: translation.from
class _Translations$translation$from$nl extends Translations$translation$from$en {
	_Translations$translation$from$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Automatisch vertaald uit het Frans';
	@override String get en => 'Automatisch vertaald uit het Engels';
	@override String get de => 'Automatisch vertaald uit het Duits';
	@override String get es => 'Automatisch vertaald uit het Spaans';
	@override String get it => 'Automatisch vertaald uit het Italiaans';
	@override String get nl => 'Automatisch vertaald uit het Nederlands';
	@override String unknown({required Object language}) => 'Automatisch vertaald (oorspronkelijke taal: ${language})';
}

// Path: account.levelOpens
class _Translations$account$levelOpens$nl extends Translations$account$levelOpens$en {
	_Translations$account$levelOpens$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get l0 => 'Je kunt plekken beoordelen, bevestigen dat ze er nog zijn, een probleem melden en je favorieten synchroniseren.';
	@override String get l1 => 'Je kunt ook reviews schrijven, foto\'s toevoegen en wijzigingen aan plekken voorstellen.';
	@override String get l2 => 'Je kunt ook plekken toevoegen.';
	@override String get l3 => 'Je wijzigingen aan plekken worden zonder controle doorgevoerd.';
	@override String get l4 => 'Je helpt mee met de moderatie.';
}

// Path: account.requirement
class _Translations$account$requirement$nl extends Translations$account$requirement$en {
	_Translations$account$requirement$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String age({required Object needed, required Object current}) => 'Een account van minstens ${needed} dagen oud (nu ${current})';
	@override String confirmations({required Object needed, required Object current}) => '${needed} bevestigingen van verschillende plekken (nu ${current})';
	@override String contributions({required Object needed, required Object current}) => '${needed} gepubliceerde bijdragen (nu ${current})';
	@override String activeDays({required Object needed, required Object current}) => '${needed} actieve dagen (nu ${current})';
	@override String get noRemoval => 'Geen bijdrage verwijderd door de moderators';
	@override String get sponsor => 'Een lid op niveau 2 dat voor je instaat';
	@override String get nomination => 'Een benoeming door de moderators';
	@override String get administration => 'Een aanstelling door het Lunaway-team';
}

// Path: deletion.gone
class _Translations$deletion$gone$nl extends Translations$deletion$gone$en {
	_Translations$deletion$gone$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get identity => 'Je pseudoniem en de sleutels van je apparaten';
	@override String get sessions => 'Je sessies en je herstelcode';
	@override String get lists => 'Je gesynchroniseerde favorietenlijsten en je verborgen auteurs';
	@override String get photos => 'Je foto\'s, je beoordelingen zonder tekst en je meldingen';
	@override String get pending => 'Je voorstellen die nog op controle wachten';
}

// Path: mine.status
class _Translations$mine$status$nl extends Translations$mine$status$en {
	_Translations$mine$status$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get published => 'Gepubliceerd';
	@override String get pending => 'Wordt gecontroleerd';
	@override String get hidden => 'Verborgen na meldingen';
	@override String get removed => 'Verwijderd door een moderator';
}

// Path: mine.submission
class _Translations$mine$submission$nl extends Translations$mine$submission$en {
	_Translations$mine$submission$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get proposed => 'Wacht op controle';
	@override String get accepted => 'Geaccepteerd';
	@override String get applied => 'Op de kaart';
	@override String get rejected => 'Geweigerd';
	@override String get withdrawn => 'Ingetrokken';
}

// Path: outbox.kind
class _Translations$outbox$kind$nl extends Translations$outbox$kind$en {
	_Translations$outbox$kind$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String rate({required Object stars}) => 'Beoordeling: ${stars} van 5';
	@override String get review => 'Review';
	@override String get deleteReview => 'Review verwijderen';
	@override String confirm({required Object status}) => 'Bevestiging: ${status}';
	@override String get deleteConfirmation => 'Bevestiging verwijderen';
	@override String reportIssue({required Object kind}) => 'Probleem gemeld: ${kind}';
	@override String get deleteIssueReport => 'Melding verwijderen';
	@override String get reportContent => 'Melding aan de moderators';
	@override String addPlace({required Object name}) => 'Nieuwe plek: ${name}';
	@override String get editPlace => 'Wijziging van een plek';
	@override String get deletePlaceSubmission => 'Voorgestelde plek intrekken';
	@override String get photo => 'Foto';
	@override String get deletePhoto => 'Foto verwijderen';
	@override String get mute => 'Auteur verbergen';
	@override String get unmute => 'Auteur weer tonen';
	@override String get poiThere => 'Nog aanwezig: een winkel of dienst';
	@override String get poiGone => 'Verdwenen: een winkel of dienst';
	@override String get addVendingMachine => 'Nieuwe automaat';
	@override String get deletePoiConfirmation => 'Antwoord over een winkel of dienst verwijderen';
	@override String reportRoadEvent({required Object kind}) => 'Melding over de weg: ${kind}';
	@override String get clearRoadEvent => 'Melding over de weg beëindigd';
}

// Path: outbox.error
class _Translations$outbox$error$nl extends Translations$outbox$error$en {
	_Translations$outbox$error$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get forbidden => 'Geweigerd: je niveau staat dit nog niet toe.';
	@override String get notFound => 'Geweigerd: de plek of de inhoud bestaat niet meer.';
	@override String get invalid => 'Geweigerd: controleer de tekst (lengte, links, contactgegevens).';
	@override String get unreadablePhoto => 'Foto geweigerd: onleesbaar, of al verstuurd.';
	@override String get photoTooLarge => 'Foto geweigerd: te groot.';
	@override String get placeRefused => 'De nieuwe plek van deze foto is geweigerd.';
	@override String get fileLost => 'De foto staat niet meer op het apparaat.';
	@override String get otherAccount => 'Gemaakt voor een ander account: wordt niet verstuurd.';
	@override String get other => 'Geweigerd door de server.';
	@override String get duplicate => 'Geweigerd: dezelfde automaat staat al binnen 25 m op de kaart.';
}

// Path: confirmSheet.status
class _Translations$confirmSheet$status$nl extends Translations$confirmSheet$status$en {
	_Translations$confirmSheet$status$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get stillOk => 'nog aanwezig';
	@override String get closed => 'gesloten';
	@override String get changed => 'veranderd';
}

// Path: issueSheet.kind
class _Translations$issueSheet$kind$nl extends Translations$issueSheet$kind$en {
	_Translations$issueSheet$kind$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Overnachten nu verboden';
	@override String get serviceBroken => 'Voorziening defect';
	@override String get noAccess => 'Geen toegang';
	@override String get danger => 'Gevaar';
}

// Path: issueSheet.hint
class _Translations$issueSheet$hint$nl extends Translations$issueSheet$hint$en {
	_Translations$issueSheet$hint$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Een bord, een gemeentebesluit, een bezoek van de politie';
	@override String get serviceBroken => 'Servicezuil, water, lozen of stroom buiten gebruik';
	@override String get noAccess => 'Een slagboom, werkzaamheden, een afgesloten weg';
	@override String get danger => 'Diefstal, geweld, instabiele ondergrond';
}

// Path: reportSheet.reason
class _Translations$reportSheet$reason$nl extends Translations$reportSheet$reason$en {
	_Translations$reportSheet$reason$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get spam => 'Reclame of herhaling';
	@override String get offensive => 'Beledigend, haatdragend of schokkend';
	@override String get wrong => 'Onjuist of misleidend';
	@override String get privacy => 'Toont of noemt een persoon, een kenteken, een privéadres';
	@override String get other => 'Andere reden';
}

// Path: poi.category
class _Translations$poi$category$nl extends Translations$poi$category$en {
	_Translations$poi$category$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get groceries => 'Boodschappen';
	@override String get vending => 'Voedselautomaten';
	@override String get water => 'Water en lozen';
	@override String get fuel => 'Brandstof en energie';
	@override String get health => 'Gezondheid';
	@override String get services => 'Diensten';
	@override String get food => 'Restaurants en cafés';
	@override String get sights => 'Bezienswaardigheden';
}

// Path: poi.kind
class _Translations$poi$kind$nl extends Translations$poi$kind$en {
	_Translations$poi$kind$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get supermarket => 'Supermarkt';
	@override String get convenience => 'Buurtwinkel';
	@override String get bakery => 'Bakker';
	@override String get butcher => 'Slager';
	@override String get greengrocer => 'Groenteboer';
	@override String get farmShop => 'Boerderijwinkel';
	@override String get marketplace => 'Markt';
	@override String get vendingPizza => 'Pizza-automaat';
	@override String get vendingBread => 'Broodautomaat';
	@override String get vendingFarmProducts => 'Automaat met boerderijproducten';
	@override String get vendingEggsMilk => 'Eier- of melkautomaat';
	@override String get vendingIce => 'IJsblokjesautomaat';
	@override String get vendingOther => 'Voedselautomaat';
	@override String get drinkingWater => 'Drinkwater';
	@override String get waterPoint => 'Waterpunt';
	@override String get dumpStation => 'Lozingspunt';
	@override String get toilets => 'Toiletten';
	@override String get shower => 'Douches';
	@override String get fuelStation => 'Tankstation';
	@override String get evCharging => 'Laadpaal';
	@override String get gasBottles => 'Gasflessen';
	@override String get pharmacy => 'Apotheek';
	@override String get doctor => 'Arts';
	@override String get hospital => 'Ziekenhuis';
	@override String get veterinary => 'Dierenarts';
	@override String get laundry => 'Wasserette';
	@override String get atm => 'Geldautomaat';
	@override String get postOffice => 'Postkantoor';
	@override String get touristOffice => 'Toeristenbureau';
	@override String get recyclingCentre => 'Milieustraat';
	@override String get carRepair => 'Garage';
	@override String get carWash => 'Wasplaats';
	@override String get motorhomeShop => 'Camperdealer en -werkplaats';
	@override String get outdoorShop => 'Kampeer- en outdoorwinkel';
	@override String get restaurant => 'Restaurant';
	@override String get cafe => 'Café';
	@override String get fastFood => 'Snackbar';
	@override String get viewpoint => 'Uitzichtpunt';
	@override String get attraction => 'Bezienswaardigheid';
	@override String get museum => 'Museum';
}

// Path: poi.vendingSells
class _Translations$poi$vendingSells$nl extends Translations$poi$vendingSells$en {
	_Translations$poi$vendingSells$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Brood';
	@override String get farmProducts => 'Boerderijproducten';
	@override String get eggsMilk => 'Eieren en melk';
	@override String get ice => 'IJsblokjes';
}

// Path: poi.vendingChip
class _Translations$poi$vendingChip$nl extends Translations$poi$vendingChip$en {
	_Translations$poi$vendingChip$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza-automaten';
	@override String get bread => 'Broodautomaten';
	@override String get farmProducts => 'Automaten met boerderijproducten';
	@override String get eggsMilk => 'Eier- en melkautomaten';
	@override String get ice => 'IJsblokjesautomaten';
}

// Path: poi.fuel
class _Translations$poi$fuel$nl extends Translations$poi$fuel$en {
	_Translations$poi$fuel$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get diesel => 'Diesel';
	@override String get sp95 => 'Euro 95 (E5)';
	@override String get e10 => 'Euro 95 (E10)';
	@override String get sp98 => 'Super Plus 98';
	@override String get e85 => 'E85';
	@override String get lpg => 'LPG';
}

// Path: poi.product
class _Translations$poi$product$nl extends Translations$poi$product$en {
	_Translations$poi$product$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza\'s';
	@override String get bread => 'Brood';
	@override String get eggs => 'Eieren';
	@override String get milk => 'Melk';
	@override String get cheese => 'Kaas';
	@override String get meat => 'Vlees';
	@override String get vegetables => 'Groenten';
	@override String get fruit => 'Fruit';
	@override String get honey => 'Honing';
	@override String get ice => 'IJsblokjes';
	@override String get potatoes => 'Aardappelen';
	@override String get food => 'Levensmiddelen';
}

// Path: poi.payment
class _Translations$poi$payment$nl extends Translations$poi$payment$en {
	_Translations$poi$payment$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get cash => 'Contant';
	@override String get coins => 'Munten';
	@override String get notes => 'Biljetten';
	@override String get cards => 'Betaalkaart';
	@override String get contactless => 'Contactloos';
	@override String get app => 'Telefoonapp';
}

// Path: poi.add
class _Translations$poi$add$nl extends Translations$poi$add$en {
	_Translations$poi$add$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Een automaat hier?';
	@override String get hint => 'Kies wat hij verkoopt: hij komt op de kaart voor alle reizigers.';
	@override String get pizza => 'Pizza\'s';
	@override String get bread => 'Brood';
	@override String get other => 'Ander voedsel';
	@override String get gate => 'Een automaat toevoegen';
	@override String get sent => 'Bedankt: de automaat staat binnen een paar minuten op de kaart.';
	@override String get duplicateTitle => 'Staat al op de kaart';
	@override String get duplicateBody => 'Binnen 25 m staat al een automaat van dezelfde soort. Is die er nog?';
	@override String get duplicateThere => 'Ja, die is er nog';
	@override String get duplicateGone => 'Nee, die is weg';
}

// Path: poi.cheapest
class _Translations$poi$cheapest$nl extends Translations$poi$cheapest$en {
	_Translations$poi$cheapest$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Goedkoopst bij mij in de buurt';
	@override String get show => 'Goedkoopst in de buurt';
	@override String get zoomIn => 'Zoom in om de prijzen van de tankstations te vergelijken.';
	@override String get none => 'Geen tankstation op de kaart verkoopt deze brandstof.';
	@override String get noneHint => 'Verschuif de kaart of kies een andere brandstof.';
	@override String get error => 'De prijzen van de tankstations konden niet worden geladen.';
}

// Path: poi.trend
class _Translations$poi$trend$nl extends Translations$poi$trend$en {
	_Translations$poi$trend$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String title({required Object fuel}) => '${fuel}: prijzen van de afgelopen dagen';
	@override String get none => 'Lunaway heeft hier nog geen prijs van deze brandstof gezien.';
	@override String get failed => 'De prijzen van de afgelopen dagen konden nu niet worden geladen.';
	@override String get week => 'Afgelopen 7 dagen:';
	@override String get month => 'Afgelopen 30 dagen:';
	@override String range({required Object low, required Object high}) => 'van ${low} tot ${high}';
	@override String span({required Object range, required Object move}) => '${range}, ${move}';
	@override String get oneDay => 'één dag gezien';
	@override String get steady => 'onveranderd';
	@override String down({required Object amount}) => 'gedaald met ${amount}';
	@override String up({required Object amount}) => 'gestegen met ${amount}';
	@override String since({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n,
		one: '${n} dag met prijzen sinds ${date}; dagen zonder gegevens blijven leeg',
		other: '${n} dagen met prijzen sinds ${date}; dagen zonder gegevens blijven leeg',
	);
}

// Path: poi.vehicles
class _Translations$poi$vehicles$nl extends Translations$poi$vehicles$en {
	_Translations$poi$vehicles$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get motorhomeYes => 'Geschikt voor campers';
	@override String get motorhomeNo => 'Niet voor campers';
	@override String get hgvYes => 'Geschikt voor vrachtwagens';
	@override String get hgvNo => 'Niet voor vrachtwagens';
	@override String maxHeight({required Object height}) => 'Maximale hoogte: ${height}';
}

// Path: roadReport.kinds
class _Translations$roadReport$kinds$nl extends Translations$roadReport$kinds$en {
	_Translations$roadReport$kinds$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get closure => 'Weg afgesloten';
	@override String get works => 'Werkzaamheden';
	@override String get narrowPassage => 'Versmalling';
	@override String get lowClearance => 'Lage doorrijhoogte';
	@override String get other => 'Probleem op de weg';
}

// Path: navigation.preview.departure
class _Translations$navigation$preview$departure$nl extends Translations$navigation$preview$departure$en {
	_Translations$navigation$preview$departure$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Vertrek';
	@override String from({required Object name}) => 'Vertrek: ${name}';
	@override String get myPosition => 'mijn positie';
	@override String get myPositionChoice => 'Mijn positie';
	@override String get change => 'Wijzigen';
	@override String get choose => 'Kies een vertrekpunt';
	@override String get searchHint => 'Plek, gemeente of adres';
	@override String get guidanceFromPosition => 'De navigatie start vanaf je positie, niet vanaf een gekozen vertrekpunt.';
	@override String get fromMyPosition => 'Vertrekken vanaf mijn positie';
}

// Path: navigation.preview.moved
class _Translations$navigation$preview$moved$nl extends Translations$navigation$preview$moved$en {
	_Translations$navigation$preview$moved$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String origin({required Object distance}) => 'Vertrekpunt ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken';
	@override String destination({required Object distance}) => 'Bestemming ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken';
	@override String stop({required Object n, required Object distance}) => 'Tussenstop ${n} is ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken';
}

// Path: navigation.onTheWay.categories
class _Translations$navigation$onTheWay$categories$nl extends Translations$navigation$onTheWay$categories$en {
	_Translations$navigation$onTheWay$categories$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get fuel => 'Brandstof';
	@override String get sleep => 'Overnachten';
	@override String get water => 'Water en lozen';
	@override String get groceries => 'Boodschappen';
	@override String get bakeries => 'Bakkers';
	@override String get toilets => 'Toiletten, douches';
	@override String get health => 'Gezondheid';
	@override String get services => 'Diensten';
	@override String get charging => 'Laadpalen';
	@override String get garages => 'Garages en uitrusting';
}

// Path: navigation.states.dimension
class _Translations$navigation$states$dimension$nl extends Translations$navigation$states$dimension$en {
	_Translations$navigation$states$dimension$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get height => 'hoogte';
	@override String get width => 'breedte';
	@override String get length => 'lengte';
	@override String get weight => 'gewicht';
}

// Path: navigation.noRoute.limit
class _Translations$navigation$noRoute$limit$nl extends Translations$navigation$noRoute$limit$en {
	_Translations$navigation$noRoute$limit$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'lage brug, doorrijhoogte ${limit}';
	@override String tunnel({required Object limit}) => 'tunnel, doorrijhoogte ${limit}';
	@override String buildingPassage({required Object limit}) => 'doorgang onder gebouw, doorrijhoogte ${limit}';
	@override String bridge({required Object limit}) => 'brug, doorrijhoogte ${limit}';
	@override String barrier({required Object limit}) => 'hoogtebegrenzer, doorrijhoogte ${limit}';
	@override String height({required Object limit}) => 'maximale hoogte ${limit}';
	@override String get heightUnknown => 'hoogtebeperking';
	@override String width({required Object limit}) => 'versmalling tot ${limit}';
	@override String get widthUnknown => 'versmalling';
	@override String length({required Object limit}) => 'maximale lengte ${limit}';
	@override String get lengthUnknown => 'lengtebeperking';
	@override String weight({required Object limit}) => 'maximumgewicht ${limit}';
	@override String get weightUnknown => 'gewichtsbeperking';
	@override String get unpaved => 'onverharde weg';
	@override String weightLocalAccess({required Object limit}) => 'maximumgewicht ${limit}, uitgezonderd bestemmingsverkeer';
	@override String widthLocalAccess({required Object limit}) => 'versmalling tot ${limit}, uitgezonderd bestemmingsverkeer';
	@override String lengthLocalAccess({required Object limit}) => 'maximale lengte ${limit}, uitgezonderd bestemmingsverkeer';
}

// Path: navigation.warning.lowClearance
class _Translations$navigation$warning$lowClearance$nl extends Translations$navigation$warning$lowClearance$en {
	_Translations$navigation$warning$lowClearance$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'Lage brug ${limit}';
	@override String tunnel({required Object limit}) => 'Tunnel ${limit}';
	@override String buildingPassage({required Object limit}) => 'Doorgang onder gebouw ${limit}';
	@override String bridge({required Object limit}) => 'Brug ${limit}';
	@override String barrier({required Object limit}) => 'Hoogtebegrenzer ${limit}';
	@override String road({required Object limit}) => 'Maximale hoogte ${limit}';
}

// Path: navigation.warning.localAccess
class _Translations$navigation$warning$localAccess$nl extends Translations$navigation$warning$localAccess$en {
	_Translations$navigation$warning$localAccess$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String weight({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen zwaarder dan ${limit}, tenzij je bestemming daar ligt';
	@override String axleLoad({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen met een aslast boven ${limit}, tenzij je bestemming daar ligt';
	@override String width({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen breder dan ${limit}, tenzij je bestemming daar ligt';
	@override String length({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen langer dan ${limit}, tenzij je bestemming daar ligt';
}

// Path: navigation.guidance.voiceMode
class _Translations$navigation$guidance$voiceMode$nl extends Translations$navigation$guidance$voiceMode$en {
	_Translations$navigation$guidance$voiceMode$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get full => 'Volledige stem';
	@override String get alerts => 'Stem: alleen waarschuwingen';
	@override String get muted => 'Stem uit';
	@override String get toFull => 'Terug naar de volledige stem';
	@override String get toAlerts => 'Alleen waarschuwingen laten uitspreken';
	@override String get toMuted => 'Stem uitzetten';
	@override String get saysFull => 'Volledige stem: alle instructies en alle waarschuwingen.';
	@override String get saysAlerts => 'Alleen waarschuwingen: de stem spreekt alleen bij flitsers, gevaren en routewijzigingen.';
	@override String get saysMuted => 'Stem uit: alles staat op het scherm, zonder geluid.';
}

// Path: navigation.guidance.notificationWhy
class _Translations$navigation$guidance$notificationWhy$nl extends Translations$navigation$guidance$notificationWhy$en {
	_Translations$navigation$guidance$notificationWhy$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get title => 'Melding voor de navigatie';
	@override String get body => 'Tijdens het navigeren houdt een melding de positie en de stem actief als het scherm uitstaat, en met een tik op de melding kom je terug in de navigatie. Android vraagt of Lunaway deze melding mag tonen.';
	@override String get ask => 'Doorgaan';
	@override String get later => 'Niet nu';
}

// Path: navigation.guidance.places
class _Translations$navigation$guidance$places$nl extends Translations$navigation$guidance$places$en {
	_Translations$navigation$guidance$places$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get button => 'Plekken op de kaart';
	@override String get buttonHidden => 'Plekken op de kaart: verborgen';
	@override String get title => 'Plekken op de kaart';
	@override String get sleep => 'Overnachten';
	@override String get fill => 'Tanken';
	@override String get groceries => 'Eten';
	@override String get all => 'Alles';
	@override String get everyPlace => 'Alle plekken';
	@override String get none => 'Niets';
	@override String get customize => 'Aanpassen';
	@override String get look => 'Weergave';
	@override String get photos => 'Foto\'s';
	@override String get pictograms => 'Iconen';
	@override String get dots => 'Kleine spelden';
	@override String get photosHint => 'De belangrijkste plekken als foto. Nooit op de weg voor je en nooit onder de knoppen.';
	@override String get pictogramsHint => 'De belangrijkste plekken groter, met prijs, beoordeling of overnachten.';
	@override String get dotsHint => 'Alle plekken als kleine spelden, zoals op de kaart.';
	@override String get free => 'Gratis';
	@override String get nightOk => 'Overnachten';
}

// Path: navigation.voice.moved
class _Translations$navigation$voice$moved$nl extends Translations$navigation$voice$moved$en {
	_Translations$navigation$voice$moved$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String destination({required Object distance}) => 'De bestemming is ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken.';
	@override String stop({required Object n, required Object distance}) => 'Tussenstop ${n} is ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken.';
}

// Path: navigation.voice.localAccess
class _Translations$navigation$voice$localAccess$nl extends Translations$navigation$voice$localAccess$en {
	_Translations$navigation$voice$localAccess$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String weight({required Object distance, required Object limit}) => 'Let op, over ${distance} boven ${limit} alleen bestemmingsverkeer.';
	@override String axleLoad({required Object distance, required Object limit}) => 'Let op, over ${distance} boven ${limit} per as alleen bestemmingsverkeer.';
	@override String width({required Object distance, required Object limit}) => 'Let op, over ${distance} breder dan ${limit} alleen bestemmingsverkeer.';
	@override String length({required Object distance, required Object limit}) => 'Let op, over ${distance} langer dan ${limit} alleen bestemmingsverkeer.';
}

// Path: navigation.voice.roadEvent
class _Translations$navigation$voice$roadEvent$nl extends Translations$navigation$voice$roadEvent$en {
	_Translations$navigation$voice$roadEvent$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String works({required Object distance}) => 'Over ${distance} werkzaamheden.';
	@override String lanes({required Object distance}) => 'Over ${distance} een rijstrook afgesloten.';
	@override String vehicleLimit({required Object distance}) => 'Let op, over ${distance} een voertuigbeperking door werkzaamheden.';
	@override String closure({required Object distance}) => 'Over ${distance} is de weg mogelijk afgesloten.';
	@override String detour({required Object distance}) => 'Over ${distance} een omleiding aangegeven.';
}

// Path: navigation.voice.camera
class _Translations$navigation$voice$camera$nl extends Translations$navigation$voice$camera$en {
	_Translations$navigation$voice$camera$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$voice$camera$kind$nl kind = _Translations$navigation$voice$camera$kind$nl._(_root);
	@override String radar({required Object distance, required Object what}) => 'Over ${distance} ${what}.';
	@override String radarLimit({required Object distance, required Object what, required Object limit}) => 'Over ${distance} ${what}, maximaal ${limit}.';
	@override String sectionLimit({required Object distance, required Object what, required Object limit}) => 'Over ${distance} ${what}, gemiddeld maximaal ${limit}.';
	@override String get inSection => 'Trajectcontrole.';
	@override String slowDownRadar({required Object limit}) => 'Rem af, flitser bij ${limit}.';
	@override String slowDownRoad({required Object limit}) => 'Rem af, maximaal ${limit}.';
}

// Path: navigation.voice.camera.kind
class _Translations$navigation$voice$camera$kind$nl extends Translations$navigation$voice$camera$kind$en {
	_Translations$navigation$voice$camera$kind$nl._(TranslationsNl root) : this._root = root, super.internal(root);

	final TranslationsNl _root; // ignore: unused_field

	// Translations
	@override String get fixed => 'een vaste flitser';
	@override String get redLight => 'een roodlichtcamera';
	@override String get levelCrossing => 'een flitser bij een overweg';
	@override String get section => 'een trajectcontrole';
	@override String get other => 'een flitser';
}

/// The flat map containing all translations for locale <nl>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsNl {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Kaart',
			'nav.favorites' => 'Favorieten',
			'nav.profile' => 'Profiel',
			'nav.fold' => 'Menu inklappen',
			'nav.unfold' => 'Menu uitklappen',
			'common.close' => 'Sluiten',
			'common.done' => 'Klaar',
			'common.cancel' => 'Annuleren',
			'common.retry' => 'Opnieuw proberen',
			'common.save' => 'Opslaan',
			'common.delete' => 'Verwijderen',
			'common.undo' => 'Ongedaan maken',
			'common.ok' => 'Begrepen',
			'common.saveFailed' => 'De wijziging kon niet worden opgeslagen.',
			'common.send' => 'Versturen',
			'common.later' => 'Later',
			'common.next' => 'Doorgaan',
			'common.failed' => 'Dat is niet gelukt. Probeer het zo opnieuw.',
			'common.offline' => 'Op dit moment geen verbinding. Probeer het opnieuw zodra je weer online bent.',
			'notices.close' => 'Melding sluiten',
			'notices.fold' => 'Melding inklappen',
			'notices.unfold' => 'Melding tonen',
			'kinds.motorhomeArea' => 'Camperplaats',
			'kinds.serviceArea' => 'Camperservicepunt',
			'kinds.campsite' => 'Camping',
			'kinds.parking' => 'Parkeerplaats',
			'kinds.nature' => 'Plek in de natuur',
			'kinds.restArea' => 'Rustplaats',
			'kinds.picnicArea' => 'Picknickplaats',
			'kinds.farm' => 'Camperplaats bij de boer',
			'kinds.homestay' => 'Camperplaats bij een particulier',
			'kinds.offRoad' => 'Offroadplek',
			'kinds.extraService' => 'Handige stop',
			'families.stopovers' => 'Camper- en parkeerplaatsen',
			'families.stopoversHint' => 'Camperplaatsen, parkeerplaatsen, rustplaatsen',
			'families.campsites' => 'Campings en gastadressen',
			'families.campsitesHint' => 'Campings, boerderijen, particulieren',
			'families.nature' => 'Natuur',
			'families.natureHint' => 'Plekken in de natuur, onverharde wegen',
			'families.services' => 'Servicepunten',
			'families.servicesHint' => 'Water en lozen, geen overnachting',
			'services.drinkingWater' => 'Drinkwater',
			'services.greyWater' => 'Grijswater lozen',
			'services.blackWater' => 'Cassette legen',
			'services.wasteBin' => 'Afvalbakken',
			'services.toilets' => 'Toiletten',
			'services.showers' => 'Douches',
			'services.electricity' => 'Stroom',
			'services.wifi' => 'Wifi',
			'services.laundry' => 'Wasserette',
			'services.lpg' => 'LPG',
			'services.gasBottles' => 'Gasflessen',
			'services.vehicleWash' => 'Wasplaats',
			'services.bakery' => 'Bakker',
			'services.swimmingPool' => 'Zwembad',
			'services.petsAllowed' => 'Huisdieren welkom',
			'services.mobileData' => 'Mobiel bereik',
			'services.winterCaravanning' => 'Open in de winter',
			'activities.monuments' => 'Bezienswaardigheden',
			'activities.windsurfKitesurf' => 'Windsurfen, kitesurfen',
			'activities.mountainBiking' => 'Mountainbiken',
			'activities.hiking' => 'Wandelen',
			'activities.climbing' => 'Klimmen',
			'activities.canoeKayak' => 'Kano, kajak',
			'activities.fishing' => 'Vissen',
			'activities.shoreFishing' => 'Schelpdieren rapen',
			'activities.swimming' => 'Zwemmen',
			'activities.motorcycling' => 'Motortochten',
			'activities.viewpoint' => 'Uitzichtpunt',
			'activities.playground' => 'Speeltuin',
			'amenities.water' => 'Water',
			'amenities.dumpStation' => 'Lozingspunt',
			'amenities.electricity' => 'Stroom',
			'amenities.toilets' => 'Toiletten',
			'amenities.showers' => 'Douches',
			'amenities.wasteBin' => 'Afvalbakken',
			'amenities.laundry' => 'Wasserette',
			'amenities.wifi' => 'Wifi',
			'amenities.lpg' => 'LPG',
			'overnight.allowed' => 'Overnachten toegestaan',
			'overnight.tolerated' => 'Overnachten gedoogd',
			'overnight.dayOnly' => 'Alleen overdag',
			'overnight.forbidden' => 'Overnachten verboden',
			'overnight.unknown' => 'Overnachten: onbekend',
			'overnight.allowedHint' => 'Je mag hier overnachten.',
			'overnight.toleratedHint' => 'Eén nacht wordt meestal geaccepteerd. Wees discreet en laat geen sporen achter.',
			'overnight.dayOnlyHint' => 'Alleen overdag parkeren. Zoek een andere plek voor de nacht.',
			'overnight.forbiddenHint' => 'Overnachten is hier verboden.',
			'overnight.unknownHint' => 'Niemand heeft het nog gemeld. Vraag het ter plaatse.',
			'freshness.confirmed' => ({required Object when}) => 'Door een reiziger bevestigd: ${when}',
			'freshness.unconfirmed' => 'Nog niet door een reiziger bevestigd',
			'freshness.stale' => 'Meer dan een jaar geleden voor het laatst bevestigd',
			'freshness.today' => 'vandaag',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'gisteren', other: '${n} dagen geleden', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'een maand geleden', other: '${n} maanden geleden', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'een jaar geleden', other: '${n} jaar geleden', ), 
			'map.searchHint' => 'Plek of gemeente',
			'map.clearSearch' => 'Zoekopdracht wissen',
			'map.locateMe' => 'Mijn positie tonen',
			'map.aroundMe' => 'Mijn omgeving bekijken',
			'map.zoomIn' => 'Inzoomen',
			'map.zoomOut' => 'Uitzoomen',
			'map.filters' => 'Filters',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Kaartbronnen: © bijdragers van OpenStreetMap, stijl van Protomaps. Opent de auteursrechtpagina van OpenStreetMap.',
			'map.creditPhotos' => 'Foto\'s: Externe communitybron',
			'map.creditPhotosLabel' => 'Kaartbronnen: © bijdragers van OpenStreetMap, stijl van Protomaps; foto\'s: Externe communitybron. Opent de auteursrechtpagina van OpenStreetMap.',
			'map.showList' => 'Lijst',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Lijst (${n})', other: 'Lijst (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'plek hier', other: 'plekken hier', ), 
			'map.nearestYouLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'plek het dichtst bij jou', other: 'plekken het dichtst bij jou', ), 
			'map.nearestCentreLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'plek het dichtst bij het midden', other: 'plekken het dichtst bij het midden', ), 
			'map.pointTitle' => 'Hier',
			'map.pointHint' => 'Punt op de kaart',
			'map.directionsHere' => 'Route hierheen',
			'map.startHere' => 'Hier vertrekken',
			'map.departureChosen' => 'Vertrekpunt gekozen. Open nu de bestemming om de route te zien.',
			'map.copyCoordinates' => 'Coördinaten kopiëren',
			'map.freeTapHint' => 'Tik op de kaart om erheen te gaan of er een plek toe te voegen',
			'map.freeTapHintClick' => 'Klik op de kaart om erheen te gaan of er een plek toe te voegen',
			'map.addPlaceAtCenter' => 'Plek toevoegen in het midden van de kaart',
			'map.addressSource' => ({required Object attribution}) => 'Bron: ${attribution}',
			'map.placesAround' => 'Plekken in de buurt',
			'map.downloading' => 'De plekken in Frankrijk worden gedownload',
			'map.downloadingCount' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${count} plek ontvangen', other: '${count} plekken ontvangen', ), 
			'map.noData' => 'Nog geen plekken op dit apparaat',
			'map.noDataHint' => 'Download de plekken één keer: daarna werkt de kaart zonder internet.',
			'map.download' => 'Plekken downloaden',
			'map.downloadFailed' => 'Het downloaden is gestopt',
			'map.demoBanner' => 'Demo: verzonnen plekken',
			'map.unsupported' => 'De kaart is niet beschikbaar op dit systeem. Gebruik de webapp.',
			'sync.failedOffline' => 'Op dit moment geen verbinding.',
			'sync.failedBusy' => 'De server is op dit moment overbelast.',
			'sync.failedServer' => 'De server heeft op dit moment een probleem.',
			'sync.failedOther' => 'Het bijwerken is niet gelukt.',
			'sync.failedRefused' => 'De server heeft het bijwerken geweigerd. Misschien is er een nieuwere versie van de app nodig.',
			'sync.willRetry' => 'Lunaway probeert het vanzelf opnieuw.',
			'sync.incomplete' => ({required Object count}) => 'Download onvolledig: tot nu toe ${count} plekken',
			'sync.incompleteShort' => 'Download onvolledig',
			'sync.resuming' => ({required Object count}) => 'Bezig met downloaden: ${count} plekken',
			'sync.resume' => 'Hervatten',
			'location.rationaleTitle' => 'Je positie tonen?',
			'location.rationale' => 'Lunaway gebruikt je positie om de kaart op jou te centreren, plekken op afstand te sorteren en je de weg te wijzen. Voor een route gaat je positie naar de server van Lunaway, die hem niet bewaart. Voor de goedkoopste brandstof bij jou in de buurt wordt alleen een positie verstuurd die is afgerond op ongeveer 5 km. Als je een probleem op de weg meldt, wordt de plek van de melding meegestuurd.',
			'location.allow' => 'Doorgaan',
			'location.notNow' => 'Niet nu',
			'location.deniedTitle' => 'Positie uitgeschakeld voor Lunaway',
			'location.denied' => 'Je hebt de toegang tot je positie geweigerd. Sta die toegang toe in de instellingen van het apparaat om je positie te gebruiken.',
			'location.openSettings' => 'Instellingen openen',
			'location.serviceOffTitle' => 'Locatie staat uit',
			'location.serviceOff' => 'Locatie staat uit op dit apparaat. Zet hem aan via de snelle instellingen en probeer het dan opnieuw.',
			'location.notAllowed' => 'Geen toegang tot je positie. De kaart werkt ook zonder.',
			'location.noFix' => 'Je positie is nog niet gevonden. Probeer het zo meteen opnieuw, het liefst buiten.',
			'location.unsupported' => 'Dit apparaat geeft zijn positie niet door.',
			'location.browserDeniedTitle' => 'De browser blokkeert je positie',
			'location.browserDenied' => 'De browser geeft je positie niet door aan Lunaway. Om dat toe te staan: klik op het pictogram links van het webadres (een slotje of schuifjes), zet Locatie op Toestaan en klik daarna opnieuw op de positieknop.',
			'location.browserNoFix' => 'De browser heeft geen positie doorgegeven. Probeer het zo opnieuw; op een computer helpt wifi om je positie te vinden.',
			'search.towns' => 'Gemeenten',
			'search.places' => 'Plekken',
			'search.noResult' => ({required Object query}) => 'Geen plek of gemeente gevonden voor “${query}”.',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} plek', other: '${n} plekken', ), 
			'search.addresses' => 'Adressen',
			'search.addressesSearching' => 'Adressen worden gezocht',
			'search.addressesFailed' => 'Zoeken naar adressen lukt nu niet.',
			'search.addressSources' => ({required Object sources}) => 'Adressen: ${sources}',
			'search.offline' => 'Geen verbinding: zoeken werkt alleen online.',
			'search.addressKind.houseNumber' => 'Adres',
			'search.addressKind.street' => 'Straat',
			'search.addressKind.locality' => 'Plaats',
			'search.addressKind.town' => 'Gemeente',
			'search.addressKind.postcode' => 'Postcode',
			'search.addressKind.region' => 'Regio',
			'filters.title' => 'Filters',
			'filters.families' => 'Soort plek',
			'filters.familiesHint' => 'Niets gekozen: alle soorten',
			'filters.familiesChosenHint' => 'Alleen deze soorten',
			'filters.night' => 'Overnachten',
			'filters.nightHint' => 'Niets gekozen: alle plekken',
			'filters.nightChosenHint' => 'Alleen plekken met deze status',
			'filters.nightPossible' => 'Overnachten mogelijk',
			'filters.amenities' => 'Voorzieningen',
			'filters.amenitiesHint' => 'De plek moet ze allemaal hebben',
			'filters.rating' => 'Minimale beoordeling',
			'filters.ratingHint' => 'Beoordeling door Lunaway-reizigers, of door de andere bronnen als nog geen reiziger de plek heeft beoordeeld. Plekken zonder beoordeling worden verborgen.',
			'filters.ratingAtLeast' => ({required Object rating}) => '${rating} en hoger',
			'filters.opening' => 'Openingstijden',
			'filters.openingHint' => 'Plaatsen waarvan de openingstijden niet bekend zijn, blijven zichtbaar.',
			'filters.openingAllYear' => 'Hele jaar',
			'filters.openingDates' => 'Mijn reisdata',
			'filters.openingClearDates' => 'Data wissen',
			'filters.openingStay' => ({required Object from, required Object to}) => '${from} tot ${to}',
			'filters.openingStayDay' => ({required Object date}) => 'Op ${date}',
			'filters.openingStayTitle' => 'Data van je verblijf',
			'filters.openingArrival' => 'Aankomst',
			'filters.openingDeparture' => 'Vertrek',
			'filters.price' => 'Prijs per nacht',
			'filters.freeOnly' => 'Gratis',
			'filters.freeHint' => 'Alleen plekken waar overnachten volgens hun bronnen gratis is',
			'filters.scrollNext' => 'Volgende filters tonen',
			'filters.scrollPrevious' => 'Vorige filters tonen',
			'filters.vehicle' => 'Mijn voertuig',
			'filters.myVehicleFits' => 'Mijn voertuig past',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Geschikt voor ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Verbergt plekken met een hoogtelimiet onder ${height}. Plekken zonder bekende limiet blijven op de kaart.',
			'filters.reset' => 'Alles wissen',
			'filters.apply' => 'Toepassen',
			'filters.show' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, zero: 'Geen plek gevonden', one: '${count} plek tonen', other: '${count} plekken tonen', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} filter actief', other: '${n} filters actief', ), 
			'place.unnamedIn' => ({required Object kind, required Object town}) => '${kind} in ${town}',
			'place.away' => ({required Object distance}) => 'Op ${distance} afstand',
			'place.directions' => 'Route',
			'place.share' => 'Delen',
			'place.save' => 'Opslaan',
			'place.saved' => 'Opgeslagen',
			'place.saveHint' => 'In Mijn favorieten. Lang indrukken om lijsten te kiezen.',
			'place.saveTo' => 'Opslaan in een lijst',
			'place.chooseLists' => 'Lijsten',
			'place.savedToast' => 'Toegevoegd aan Mijn favorieten',
			'place.removedToast' => 'Verwijderd uit Mijn favorieten',
			'place.pricePerNight' => 'Per nacht',
			'place.priceFree' => 'Gratis',
			'place.priceUnknown' => 'Niet vermeld',
			'place.priceServices' => 'Service',
			'place.priceIncluded' => 'Inbegrepen',
			'place.priceIncludes' => ({required Object items}) => 'De prijs per nacht is inclusief: ${items}',
			'place.inclusions.services' => 'voorzieningen',
			'place.inclusions.touristTax' => 'toeristenbelasting',
			'place.inclusions.electricity' => 'stroom',
			'place.maxHeight' => 'Max. hoogte',
			'place.capacity' => 'Plaatsen',
			'place.classification' => 'Classificatie',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} ster', other: '${n} sterren', ), 
			'place.hours' => 'Openingstijden',
			'place.services' => 'Voorzieningen',
			'place.noServices' => 'Geen voorzieningen vermeld.',
			'place.activities' => 'In de buurt',
			'place.description' => 'Beschrijving',
			'place.contact' => 'Contact',
			'place.website' => 'Website',
			'place.call' => 'Bellen',
			'place.coordinates' => 'Coördinaten',
			'place.copy' => 'Coördinaten kopiëren',
			'place.copyShort' => 'Kopiëren',
			'place.copyAs' => ({required Object format}) => 'Kopiëren als ${format}',
			'place.copiesAs' => ({required Object format}) => '“Kopiëren” kopieert: ${format}',
			'place.copied' => ({required Object text}) => 'Gekopieerd: ${text}',
			'place.otherFormats' => 'Kies het formaat om te kopiëren',
			'place.formatDecimal' => 'Decimale graden',
			'place.formatDms' => 'Graden, minuten, seconden',
			'place.formatGeo' => 'geo:-link',
			'place.formatGoogle' => 'Google Maps-link',
			'place.formatOsm' => 'OpenStreetMap-link',
			'place.sources' => 'Bronnen',
			'place.fetched' => ({required Object when}) => 'Opgehaald ${when}',
			'place.viewSource' => 'Bekijken bij de bron',
			'place.gone' => 'Deze plek staat niet meer op de kaart',
			'place.goneHint' => 'Sinds de laatste update is deze plek verwijderd of samengevoegd met een andere.',
			'place.arriving' => 'Deze plek wordt nog gedownload',
			'place.arrivingHint' => 'De plekken in Frankrijk worden gedownload, zodat de kaart zonder internet werkt. De pagina gaat open zodra deze plek binnen is.',
			'place.loadError' => 'Deze plek kon niet worden geladen.',
			'place.openFailed' => 'Geen enkele app kon deze link openen.',
			'place.photos' => 'Foto\'s',
			'place.extrasOffline' => 'Voor foto\'s en reviews is een verbinding nodig.',
			'place.reviewsTitle' => 'Reviews',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} review', other: '${n} reviews', ), 
			'place.noReviews' => 'Nog geen reviews.',
			'place.noOtherReviews' => 'Nog geen andere reviews.',
			'place.moreReviews' => 'Meer reviews',
			'place.moreReviewsFailed' => 'Meer reviews konden niet worden geladen. Tik om het opnieuw te proberen.',
			'place.stars' => ({required Object rating}) => '${rating} van 5',
			'place.externalRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'externe beoordeling', other: 'externe beoordelingen', ), 
			'place.deletedAccount' => 'Verwijderd account',
			'place.reviewVehicle.van' => 'Busje',
			'place.reviewVehicle.campervan' => 'Buscamper',
			'place.reviewVehicle.motorhome' => 'Camper',
			'place.reviewVehicle.caravan' => 'Caravan',
			'place.reviewVehicle.other' => 'Ander voertuig',
			'place.originalLanguage' => ({required Object language}) => 'Oorspronkelijke tekst in het ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Foto ${index} van ${count}',
			'place.previousPhoto' => 'Vorige foto',
			'place.nextPhoto' => 'Volgende foto',
			'place.links' => 'Op andere sites',
			'place.sourceWithLicence' => ({required Object source, required Object licence}) => '${source} · ${licence}',
			'place.licenceCcBy' => 'CC BY 4.0',
			'place.photoCredit' => ({required Object source, required Object author}) => '${source} · ${author}',
			'place.photoStreetView' => 'Straatbeeld',
			'place.photoSurroundings' => 'Omgeving',
			'place.excerptFrom' => ({required Object source, required Object text}) => 'Volgens ${source}: ${text}',
			'place.readMore' => 'Lees meer',
			'place.updatedOn' => ({required Object date}) => 'bijgewerkt op ${date}',
			'place.otherSources' => 'Volgens andere bronnen',
			'sources.extcom.label' => 'Externe communitybron',
			'sources.extcom.short' => 'Extern',
			'hours.open' => 'Nu open',
			'hours.openUntil' => ({required Object time}) => 'Open, sluit om ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Open, sluit ${day} om ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Open, sluit over ${n} minuut', other: 'Open, sluit over ${n} minuten', ), 
			'hours.closedUntil' => ({required Object time}) => 'Gesloten, gaat om ${time} open',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Gesloten, gaat ${day} om ${time} open',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Gesloten, gaat over ${n} minuut open', other: 'Gesloten, gaat over ${n} minuten open', ), 
			'hours.closedWindow' => 'Gesloten in de komende twee weken',
			'hours.tomorrow' => 'morgen',
			'hours.onDate' => ({required Object date}) => 'op ${date}',
			'hours.onWeekday' => ({required Object day}) => '${day}',
			'hours.midnight' => 'middernacht',
			'hours.stale' => 'Open of gesloten? Werk de plekken bij in Profiel.',
			'hours.localTime' => 'Tijden in de lokale tijd van de plek',
			'hours.codes.mo' => 'ma',
			'hours.codes.tu' => 'di',
			'hours.codes.we' => 'wo',
			'hours.codes.th' => 'do',
			'hours.codes.fr' => 'vr',
			'hours.codes.sa' => 'za',
			'hours.codes.su' => 'zo',
			'hours.codes.ph' => 'feestdagen',
			'hours.codes.sh' => 'schoolvakanties',
			'hours.codes.off' => 'gesloten',
			'hours.codes.closed' => 'gesloten',
			'hours.codes.sunrise' => 'zonsopgang',
			'hours.codes.sunset' => 'zonsondergang',
			'hours.months.jan' => 'jan.',
			'hours.months.feb' => 'feb.',
			'hours.months.mar' => 'mrt.',
			'hours.months.apr' => 'apr.',
			'hours.months.may' => 'mei',
			'hours.months.jun' => 'jun.',
			'hours.months.jul' => 'jul.',
			'hours.months.aug' => 'aug.',
			'hours.months.sep' => 'sep.',
			'hours.months.oct' => 'okt.',
			'hours.months.nov' => 'nov.',
			'hours.months.dec' => 'dec.',
			'hours.dayOfMonth' => ({required Object day, required Object month}) => '${day} ${month}',
			'hours.dayOfYear' => ({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}',
			'hours.allWeek' => '24/7',
			'hours.allYear' => 'het hele jaar',
			'hours.seasonAllYear' => 'Het hele jaar open',
			'hours.seasonOpenUntil' => ({required Object date}) => 'Open tot ${date}',
			'hours.seasonClosedUntil' => ({required Object date}) => 'Gesloten, opent op ${date}',
			'directions.title' => 'Openen in',
			'directions.hint' => 'Deze apps kennen de afmetingen van je voertuig niet.',
			'directions.remember' => 'Altijd deze app gebruiken',
			'directions.rememberHint' => 'Je kunt dit wijzigen in Profiel',
			'directions.settingTitle' => 'Openen in een andere app',
			'directions.settingHint' => 'De app die opent als je bij een route op “Openen in” tikt',
			'directions.askEachTime' => 'Elke keer vragen',
			'directions.appleMaps' => 'Kaarten',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (browser)',
			'directions.none' => 'Geen navigatie-app gevonden op dit apparaat.',
			'navigation.preview.titleTo' => ({required Object name}) => 'Naar ${name}',
			'navigation.preview.titlePoint' => 'Punt op de kaart',
			'navigation.preview.departure.title' => 'Vertrek',
			'navigation.preview.departure.from' => ({required Object name}) => 'Vertrek: ${name}',
			'navigation.preview.departure.myPosition' => 'mijn positie',
			'navigation.preview.departure.myPositionChoice' => 'Mijn positie',
			'navigation.preview.departure.change' => 'Wijzigen',
			'navigation.preview.departure.choose' => 'Kies een vertrekpunt',
			'navigation.preview.departure.searchHint' => 'Plek, gemeente of adres',
			'navigation.preview.departure.guidanceFromPosition' => 'De navigatie start vanaf je positie, niet vanaf een gekozen vertrekpunt.',
			'navigation.preview.departure.fromMyPosition' => 'Vertrekken vanaf mijn positie',
			'navigation.preview.computing' => 'Route wordt berekend voor je voertuig',
			'navigation.preview.start' => 'Starten',
			'navigation.preview.recommended' => 'Aanbevolen',
			'navigation.preview.alternative' => ({required Object n}) => 'Alternatief ${n}',
			'navigation.preview.toll' => 'Tol',
			'navigation.preview.ferry' => 'Veerboot',
			'navigation.preview.motorway' => 'Snelweg',
			'navigation.preview.noWarnings' => 'Geen beperkingen op deze route die krap zijn voor je voertuig.',
			'navigation.preview.warnings' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '1 beperking om op te letten', other: '${n} beperkingen om op te letten', ), 
			'navigation.preview.vehicle' => 'Je voertuig',
			'navigation.preview.vehicleTowing' => ({required Object vehicle}) => '${vehicle}, met aanhanger',
			'navigation.preview.editVehicle' => 'Wijzigen',
			'navigation.preview.cruise' => ({required Object speed}) => 'Berekend met max. ${speed}',
			'navigation.preview.avoid' => 'Vermijden',
			'navigation.preview.avoidTolls' => 'Tolwegen',
			'navigation.preview.avoidMotorways' => 'Snelwegen',
			'navigation.preview.avoidFerries' => 'Veerboten',
			'navigation.preview.avoidUnpaved' => 'Onverharde wegen',
			'navigation.preview.roadbook' => 'Routebeschrijving',
			'navigation.preview.roadbookShow' => 'Routebeschrijving tonen',
			'navigation.preview.roadbookHide' => 'Routebeschrijving verbergen',
			'navigation.preview.dataOf' => ({required Object date}) => 'Weggegevens van ${date}',
			'navigation.preview.attributionOsm' => '© bijdragers van OpenStreetMap',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, editie van ${date}',
			'navigation.preview.otherApps' => 'Openen in…',
			'navigation.preview.back' => 'Terug',
			'navigation.preview.moved.origin' => ({required Object distance}) => 'Vertrekpunt ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken',
			'navigation.preview.moved.destination' => ({required Object distance}) => 'Bestemming ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken',
			'navigation.preview.moved.stop' => ({required Object n, required Object distance}) => 'Tussenstop ${n} is ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken',
			'navigation.stops.title' => 'Tussenstops',
			'navigation.stops.add' => 'Toevoegen als tussenstop',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Toevoegen als tussenstop · +${minutes} min',
			'navigation.stops.addFree' => 'Toevoegen als tussenstop · geen omweg',
			'navigation.stops.quoting' => 'Toevoegen als tussenstop · omweg wordt berekend',
			'navigation.stops.noRoute' => 'Geen route via dit punt voor je voertuig.',
			'navigation.stops.full' => 'Maximaal vijf tussenstops.',
			'navigation.stops.goDirectly' => 'Rechtstreeks erheen',
			'navigation.stops.openCard' => 'Details bekijken',
			'navigation.stops.point' => 'Punt op de kaart',
			'navigation.stops.remove' => 'Tussenstop verwijderen',
			'navigation.stops.reorder' => 'Sleep om de volgorde te wijzigen',
			'navigation.stops.added' => 'Tussenstop toegevoegd',
			'navigation.stops.removed' => 'Tussenstop verwijderd',
			'navigation.stops.moved' => 'Volgorde van de tussenstops gewijzigd',
			'navigation.stops.destinationChanged' => 'Nieuwe bestemming',
			'navigation.stops.failed' => 'De route kon niet worden gewijzigd.',
			'navigation.stops.noQuote' => 'De omweg kon niet worden berekend.',
			'navigation.stops.offline' => 'Geen verbinding om de omweg te berekenen.',
			'navigation.legs.all' => 'Alles',
			'navigation.legs.stop' => ({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}',
			'navigation.legs.stopSaid' => ({required Object number, required Object name, required Object time, required Object distance}) => 'Tussenstop ${number}: ${name}, rond ${time}, over ${distance}',
			'navigation.legs.arrival' => ({required Object name, required Object time}) => 'Bestemming · ${name} · ${time}',
			'navigation.legs.arrivalSaid' => ({required Object name, required Object time}) => 'Bestemming: ${name}, rond ${time}',
			'navigation.legs.remove' => ({required Object number, required Object name}) => 'Tussenstop ${number} verwijderen, ${name}',
			'navigation.fuel.price' => ({required Object price}) => '€ ${price}/l',
			'navigation.fuel.withDetour' => ({required Object price}) => '€ ${price}/l incl. omweg',
			'navigation.fuel.detour' => ({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min',
			'navigation.fuel.onRoute' => 'op de route',
			'navigation.fuel.open' => 'Open',
			'navigation.fuel.closed' => 'Gesloten',
			'navigation.fuel.unknownHours' => 'Openingstijden onbekend',
			'navigation.fuel.add' => 'Toevoegen',
			'navigation.fuel.station' => 'Tankstation',
			'navigation.fuel.empty' => 'Geen tankstation met deze brandstof in de buurt van de route.',
			'navigation.fuel.failed' => 'De tankstations konden niet worden geladen.',
			'navigation.fuel.estimated' => 'Omwegen geschat op basis van de afstand tot de route.',
			'navigation.fuel.attribution' => 'Prijzen: Frans ministerie van Economie (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => '${n} min geleden',
			'navigation.fuel.hoursAgo' => ({required Object n}) => '${n} uur geleden',
			'navigation.fuel.daysAgo' => ({required Object n}) => '${n} dagen geleden',
			'navigation.onTheWay.title' => 'Onderweg',
			'navigation.onTheWay.categories.fuel' => 'Brandstof',
			'navigation.onTheWay.categories.sleep' => 'Overnachten',
			'navigation.onTheWay.categories.water' => 'Water en lozen',
			'navigation.onTheWay.categories.groceries' => 'Boodschappen',
			'navigation.onTheWay.categories.bakeries' => 'Bakkers',
			'navigation.onTheWay.categories.toilets' => 'Toiletten, douches',
			'navigation.onTheWay.categories.health' => 'Gezondheid',
			'navigation.onTheWay.categories.services' => 'Diensten',
			'navigation.onTheWay.categories.charging' => 'Laadpalen',
			'navigation.onTheWay.categories.garages' => 'Garages en uitrusting',
			'navigation.onTheWay.fuelOfVehicle' => ({required Object fuel}) => '${fuel}, volgens je voertuig',
			'navigation.onTheWay.otherFuel' => 'Andere brandstof',
			'navigation.onTheWay.keepFuel' => 'Bewaren als mijn brandstof',
			'navigation.onTheWay.fuelKept' => ({required Object fuel}) => '${fuel} bewaard voor je voertuig.',
			'navigation.onTheWay.keepFuelFailed' => 'De brandstof kon niet worden bewaard.',
			'navigation.onTheWay.loading' => 'Zoeken langs de route',
			'navigation.onTheWay.empty' => 'Geen resultaten op deze route',
			'navigation.onTheWay.emptyHint' => 'Probeer een andere categorie, of open de lijst verderop opnieuw.',
			'navigation.onTheWay.failed' => 'De lijst kon niet worden geladen.',
			'navigation.onTheWay.offline' => 'Geen verbinding: de lijst komt terug met de verbinding.',
			'navigation.onTheWay.rateLimited' => 'Veel zoekopdrachten achter elkaar: probeer het over een paar minuten opnieuw.',
			'navigation.onTheWay.nearNone' => ({required Object distance}) => 'Niets in de komende ${distance}.',
			'navigation.onTheWay.further' => ({required Object n}) => 'Verderop (${n})',
			'navigation.onTheWay.more' => 'Meer tonen',
			'navigation.onTheWay.moreFailed' => 'De rest kon niet worden geladen.',
			'navigation.onTheWay.ahead' => ({required Object distance}) => 'over ${distance}',
			'navigation.onTheWay.offRoute' => ({required Object distance}) => '${distance} van de route',
			'navigation.onTheWay.byTheRoad' => 'langs de weg',
			'navigation.onTheWay.addCost' => ({required Object minutes}) => 'Toevoegen · +${minutes} min',
			'navigation.onTheWay.addFree' => 'Toevoegen · geen omweg',
			'navigation.onTheWay.openAt' => ({required Object time}) => 'Open als je langskomt, rond ${time}',
			'navigation.onTheWay.closedAt' => ({required Object time}) => 'Gesloten als je langskomt, rond ${time}',
			'navigation.onTheWay.closedOpensAt' => ({required Object time, required Object opens}) => 'Gesloten als je rond ${time} langskomt, opent om ${opens}',
			'navigation.onTheWay.perNight' => ({required Object price}) => '${price} per nacht',
			'navigation.onTheWay.photoFrom' => ({required Object source}) => 'Foto: ${source}',
			'navigation.onTheWay.servicesList' => ({required Object list}) => 'Voorzieningen: ${list}',
			'navigation.onTheWay.placesCredit' => 'Plekken: Lunaway en de bronnen op elke detailpagina',
			'navigation.states.vehicleTitle' => 'Waarmee rijd je?',
			'navigation.states.vehicleHint' => 'De route vermijdt te lage bruggen, te smalle straten en wegen die verboden zijn voor je afmetingen. Vul de hoogte, breedte, lengte en het gewicht in.',
			'navigation.states.vehicleMissing' => ({required Object list}) => 'Ontbreekt: ${list}',
			'navigation.states.vehicleOutOfBounds' => ({required Object list}) => 'Buiten de toegestane waarden: ${list}',
			'navigation.states.dimension.height' => 'hoogte',
			'navigation.states.dimension.width' => 'breedte',
			'navigation.states.dimension.length' => 'lengte',
			'navigation.states.dimension.weight' => 'gewicht',
			'navigation.states.describeVehicle' => 'Mijn voertuig beschrijven',
			'navigation.states.originTitle' => 'Waar ben je?',
			'navigation.states.originHint' => 'Lunaway heeft je positie nodig om de route te berekenen.',
			'navigation.states.locate' => 'Mijn positie bepalen',
			'navigation.states.offlineTitle' => 'Geen verbinding',
			'navigation.states.offlineHint' => 'Routes worden berekend op de server van Lunaway. Zonder internet geeft “Openen in…” de rit door aan een navigatie-app met eigen kaarten.',
			'navigation.states.rateLimitedTitle' => 'Te veel routeaanvragen',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Probeer het over ${seconds} s opnieuw.',
			'navigation.states.unavailableTitle' => 'Routeberekening niet beschikbaar',
			'navigation.states.unavailableHint' => 'De routeservice is op dit moment niet bereikbaar. Probeer het later opnieuw.',
			'navigation.states.refusedTitle' => 'Geen route mogelijk',
			'navigation.states.refusedHint' => 'Lunaway kon voor deze aanvraag geen route berekenen: controleer de bestemming, de lengte van de rit en de waarden van het voertuig.',
			'navigation.states.noSafeTitle' => 'Geen veilige route voor je voertuig',
			'navigation.states.noSafeHint' => 'Op elke mogelijke weg geldt een beperking waar je voertuig niet aan voldoet:',
			'navigation.states.whatToDo' => 'Wat je kunt doen',
			'navigation.states.checkVehicle' => ({required Object height, required Object weight}) => 'Controleer de ingevoerde waarden: ${height} hoog, ${weight}.',
			'navigation.states.pickOtherPoint' => 'Kies een bestemming vóór het obstakel: druk lang op de kaart.',
			'navigation.states.noRouteTitle' => 'Geen weg naar dit punt',
			'navigation.states.noRouteHint' => 'Het punt ligt misschien aan een privéweg, of op een eiland zonder veerboot.',
			'navigation.states.allowUnpaved' => 'Onverharde wegen worden vermeden: sta ze toe als de bestemming aan een onverharde weg ligt.',
			'navigation.states.offNetworkTitle' => 'Te ver van een weg',
			'navigation.states.offNetworkHint' => 'Kies een bestemming aan een weg.',
			'navigation.noRoute.originUnreachable' => 'Je voertuig kan hier niet vertrekken',
			'navigation.noRoute.originUnreachableBy' => ({required Object limit}) => 'Je voertuig kan hier niet vertrekken: ${limit}',
			'navigation.noRoute.destinationUnreachable' => 'Bestemming onbereikbaar voor je voertuig',
			'navigation.noRoute.destinationUnreachableBy' => ({required Object limit}) => 'Bestemming onbereikbaar voor je voertuig: ${limit}',
			'navigation.noRoute.waypointUnreachable' => ({required Object n}) => 'Tussenstop ${n} onbereikbaar voor je voertuig',
			'navigation.noRoute.waypointUnreachableBy' => ({required Object n, required Object limit}) => 'Tussenstop ${n} onbereikbaar voor je voertuig: ${limit}',
			'navigation.noRoute.blockedOnTheWay' => 'Geen doorgang voor je voertuig onderweg',
			'navigation.noRoute.blockedOnTheWayBy' => ({required Object limit}) => 'Geen doorgang voor je voertuig onderweg: ${limit}',
			'navigation.noRoute.blockedHint' => 'Elke tussenstop is bereikbaar, maar op elke weg ertussen geldt een beperking waar je voertuig niet aan voldoet.',
			_ => null,
		} ?? switch (path) {
			'navigation.noRoute.notConnectedOrigin' => 'Geen weg vanaf je positie',
			'navigation.noRoute.notConnectedDestination' => 'Geen weg naar de bestemming',
			'navigation.noRoute.notConnectedWaypoint' => ({required Object n}) => 'Geen weg naar tussenstop ${n}',
			'navigation.noRoute.notConnectedTrip' => 'Geen weg die je tussenstops verbindt',
			'navigation.noRoute.notConnectedHint' => 'Dit ligt niet aan je voertuig: een eiland zonder autoveer, of een weg die voor alle verkeer is afgesloten.',
			'navigation.noRoute.outsideOrigin' => 'Je positie ligt buiten het gebied waar routes worden berekend',
			'navigation.noRoute.outsideDestination' => 'Bestemming buiten het gebied waar routes worden berekend',
			'navigation.noRoute.outsideWaypoint' => ({required Object n}) => 'Tussenstop ${n} buiten het gebied waar routes worden berekend',
			'navigation.noRoute.outsideHint' => ({required Object countries}) => 'Lunaway berekent routes in deze landen: ${countries}.',
			'navigation.noRoute.outsideHintUnknown' => 'Lunaway berekent nog geen routes in dit land.',
			'navigation.noRoute.noRoadOrigin' => 'Je positie ligt te ver van een weg',
			'navigation.noRoute.noRoadDestination' => 'Bestemming te ver van een weg',
			'navigation.noRoute.noRoadWaypoint' => ({required Object n}) => 'Tussenstop ${n} te ver van een weg',
			'navigation.noRoute.noRoadHint' => 'Geen weg die je voertuig mag nemen binnen 5 km van dit punt.',
			'navigation.noRoute.tooLong' => 'Rit te lang',
			'navigation.noRoute.tooLongHint' => ({required Object trip, required Object max}) => '${trip} hemelsbreed van tussenstop tot tussenstop: Lunaway berekent ritten tot ${max}.',
			'navigation.noRoute.vehicleValue' => ({required Object value}) => 'Je voertuig: ${value}',
			'navigation.noRoute.limit.underpass' => ({required Object limit}) => 'lage brug, doorrijhoogte ${limit}',
			'navigation.noRoute.limit.tunnel' => ({required Object limit}) => 'tunnel, doorrijhoogte ${limit}',
			'navigation.noRoute.limit.buildingPassage' => ({required Object limit}) => 'doorgang onder gebouw, doorrijhoogte ${limit}',
			'navigation.noRoute.limit.bridge' => ({required Object limit}) => 'brug, doorrijhoogte ${limit}',
			'navigation.noRoute.limit.barrier' => ({required Object limit}) => 'hoogtebegrenzer, doorrijhoogte ${limit}',
			'navigation.noRoute.limit.height' => ({required Object limit}) => 'maximale hoogte ${limit}',
			'navigation.noRoute.limit.heightUnknown' => 'hoogtebeperking',
			'navigation.noRoute.limit.width' => ({required Object limit}) => 'versmalling tot ${limit}',
			'navigation.noRoute.limit.widthUnknown' => 'versmalling',
			'navigation.noRoute.limit.length' => ({required Object limit}) => 'maximale lengte ${limit}',
			'navigation.noRoute.limit.lengthUnknown' => 'lengtebeperking',
			'navigation.noRoute.limit.weight' => ({required Object limit}) => 'maximumgewicht ${limit}',
			'navigation.noRoute.limit.weightUnknown' => 'gewichtsbeperking',
			'navigation.noRoute.limit.unpaved' => 'onverharde weg',
			'navigation.noRoute.limit.weightLocalAccess' => ({required Object limit}) => 'maximumgewicht ${limit}, uitgezonderd bestemmingsverkeer',
			'navigation.noRoute.limit.widthLocalAccess' => ({required Object limit}) => 'versmalling tot ${limit}, uitgezonderd bestemmingsverkeer',
			'navigation.noRoute.limit.lengthLocalAccess' => ({required Object limit}) => 'maximale lengte ${limit}, uitgezonderd bestemmingsverkeer',
			'navigation.noRoute.editVehicle' => 'Voertuig wijzigen',
			'navigation.noRoute.allowUnpaved' => 'Onverharde wegen toestaan',
			'navigation.noRoute.removeStop' => ({required Object n}) => 'Tussenstop ${n} verwijderen',
			'navigation.noRoute.removeStopNamed' => ({required Object name}) => 'Tussenstop “${name}” verwijderen',
			'navigation.noRoute.placesAround' => 'Plekken rond de bestemming bekijken',
			'navigation.noRoute.moveDestination' => 'Of kies een andere bestemming: druk lang op de kaart en kies dan “Rechtstreeks erheen”.',
			'navigation.noRoute.moveStop' => 'Voor een andere tussenstop: zoom in en tik op de kaart, of druk lang op de kaart, en kies dan “Toevoegen als tussenstop”.',
			'navigation.noRoute.moveOrigin' => 'Het vertrekpunt is je positie: rijd naar een weg die je voertuig mag nemen en probeer het opnieuw.',
			'navigation.noRoute.pickInside' => 'Kies een bestemming in een van deze landen.',
			'navigation.noRoute.shorter' => 'Kies een bestemming die dichterbij ligt, of maak de rit in meerdere etappes.',
			'navigation.ferry.title' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Veerovertocht', other: '${n} veerovertochten', ), 
			'navigation.ferry.unnamed' => 'Veerboot',
			'navigation.ferry.named' => ({required Object name}) => 'Veerboot ${name}',
			'navigation.ferry.ports' => ({required Object ports}) => 'Havens: ${ports}',
			'navigation.ferry.countries' => ({required Object from, required Object to}) => 'Inschepen: ${from} · Ontschepen: ${to}',
			'navigation.ferry.country' => ({required Object country}) => 'Land: ${country}',
			'navigation.ferry.where' => ({required Object distance, required Object sea, required Object duration}) => 'Op ${distance} van het vertrekpunt · ${sea} over zee, ongeveer ${duration}',
			'navigation.ferry.needed' => 'De bestemming is niet bereikbaar zonder veerboot: de route neemt er een, ook al vermijd je veerboten.',
			'navigation.warning.lowClearance.underpass' => ({required Object limit}) => 'Lage brug ${limit}',
			'navigation.warning.lowClearance.tunnel' => ({required Object limit}) => 'Tunnel ${limit}',
			'navigation.warning.lowClearance.buildingPassage' => ({required Object limit}) => 'Doorgang onder gebouw ${limit}',
			'navigation.warning.lowClearance.bridge' => ({required Object limit}) => 'Brug ${limit}',
			'navigation.warning.lowClearance.barrier' => ({required Object limit}) => 'Hoogtebegrenzer ${limit}',
			'navigation.warning.lowClearance.road' => ({required Object limit}) => 'Maximale hoogte ${limit}',
			'navigation.warning.unknownClearance' => 'Lage doorrijhoogte, hoogte onbekend',
			'navigation.warning.narrow' => ({required Object limit}) => 'Versmalling ${limit}',
			'navigation.warning.tooLong' => ({required Object limit}) => 'Maximale lengte ${limit}',
			'navigation.warning.tooHeavy' => ({required Object limit}) => 'Maximumgewicht ${limit}',
			'navigation.warning.axleLoad' => ({required Object limit}) => 'Maximale aslast ${limit}',
			'navigation.warning.motorhomeBan' => 'Verboden voor campers',
			'navigation.warning.trailerBan' => 'Verboden voor aanhangers',
			'navigation.warning.goodsVehicleWeight' => ({required Object limit}) => 'Maximumgewicht vrachtverkeer ${limit}',
			'navigation.warning.yours' => ({required Object value}) => 'je voertuig: ${value}',
			'navigation.warning.fromStart' => ({required Object distance}) => 'op ${distance} van het vertrekpunt',
			'navigation.warning.ahead' => ({required Object distance}) => 'over ${distance}',
			'navigation.warning.disputed' => 'bronnen spreken elkaar tegen, de laagste waarde geldt',
			'navigation.warning.goodsOnly' => 'geldt voor vrachtwagens, let op de borden',
			'navigation.warning.osm' => 'OpenStreetMap',
			'navigation.warning.ign' => 'IGN BD TOPO',
			'navigation.warning.community' => 'Lunaway-melding',
			'navigation.warning.dialog' => 'Verkeersbesluit (DiaLog)',
			'navigation.warning.localAccess.weight' => ({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen zwaarder dan ${limit}, tenzij je bestemming daar ligt',
			'navigation.warning.localAccess.axleLoad' => ({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen met een aslast boven ${limit}, tenzij je bestemming daar ligt',
			'navigation.warning.localAccess.width' => ({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen breder dan ${limit}, tenzij je bestemming daar ligt',
			'navigation.warning.localAccess.length' => ({required Object limit}) => 'Uitgezonderd bestemmingsverkeer: verboden voor voertuigen langer dan ${limit}, tenzij je bestemming daar ligt',
			'navigation.roadEvents.title' => 'Werkzaamheden en afsluitingen',
			'navigation.roadEvents.none' => 'Geen werkzaamheden of afsluitingen bekend op deze route.',
			'navigation.roadEvents.stale' => 'Werkzaamheden en afsluitingen: de bronnen zijn al een tijd niet bijgewerkt.',
			'navigation.roadEvents.avoided' => ({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Route berekend om een afsluiting heen: ${names}', other: 'Route berekend om ${n} afsluitingen heen: ${names}', ), 
			'navigation.roadEvents.atDistance' => ({required Object distance}) => 'op ${distance} van het vertrekpunt',
			'navigation.roadEvents.more' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'En nog ${n} op de route', other: 'En nog ${n} op de route', ), 
			'navigation.roadEvents.classClosure' => 'Weg afgesloten',
			'navigation.roadEvents.classWorks' => 'Werkzaamheden',
			'navigation.roadEvents.classLaneRestriction' => 'Rijstroken afgesloten',
			'navigation.roadEvents.classVehicleLimit' => 'Voertuigbeperking',
			'navigation.roadEvents.classDetour' => 'Omleiding aangegeven',
			'navigation.roadEvents.reasonUnmatched' => 'positie onzeker, misschien op de route',
			'navigation.roadEvents.reasonStale' => 'bron al een tijd niet bijgewerkt',
			'navigation.roadEvents.reasonOutsideHours' => 'waarschijnlijk niet op dit tijdstip',
			'navigation.roadEvents.reasonGoodsVehicles' => 'voor vrachtwagens',
			'navigation.roadEvents.reasonUnconfirmed' => 'gemeld door één reiziger',
			'navigation.roadEvents.reasonAged' => 'oude melding',
			'navigation.roadEvents.reasonInside' => 'de route begint of eindigt in het afgesloten stuk',
			'navigation.roadEvents.reasonNearLimit' => 'met weinig marge',
			'navigation.roadEvents.reasonOverLimit' => 'je voertuig overschrijdt de limiet',
			'navigation.marks.legend' => 'Legenda',
			'navigation.marks.legendHide' => 'Legenda inklappen',
			'navigation.marks.kindOrigin' => 'Vertrek',
			'navigation.marks.kindDestination' => 'Bestemming',
			'navigation.marks.kindStop' => 'Tussenstop',
			'navigation.marks.kindClosure' => 'Weg afgesloten',
			'navigation.marks.kindWorks' => 'Werkzaamheden',
			'navigation.marks.kindLanes' => 'Rijstroken afgesloten',
			'navigation.marks.kindClearance' => 'Hoogtebeperking',
			'navigation.marks.kindWeight' => 'Gewichtsbeperking',
			'navigation.marks.kindLimit' => 'Andere beperking (breedte, lengte, verbod)',
			'navigation.marks.kindFuel' => 'Tankstation',
			'navigation.marks.kindPlace' => 'Plek bij de route',
			'navigation.marks.groupLegend' => 'Markeringen dicht bij elkaar, gegroepeerd',
			'navigation.marks.zoneLegend' => 'Gevarenzone',
			'navigation.marks.zonesFrom' => ({required Object source, required Object date}) => 'Gevarenzones: ${source}, lijst van ${date}',
			'navigation.marks.group' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} markering', other: '${n} markeringen', ), 
			'navigation.marks.groupHint' => 'Zoom in om ze een voor een te zien',
			'navigation.marks.count' => ({required Object kind, required Object n}) => '${kind}: ${n}',
			'navigation.marks.stop' => ({required Object n}) => 'Tussenstop ${n}',
			'navigation.marks.origin' => 'Vertrekpunt',
			'navigation.marks.nearRoute' => 'Bij de route',
			'navigation.marks.avoided' => 'De route gaat eromheen',
			'navigation.marks.blocking' => 'Blokkeert elke route',
			'navigation.marks.showInList' => 'In de lijst bekijken',
			'navigation.marks.showAll' => 'Alles tonen',
			'navigation.marks.onMap' => 'op de kaart tonen',
			'navigation.marks.price' => ({required Object price}) => '€ ${price}',
			'navigation.marks.kindCamera' => 'Flitser',
			'navigation.marks.cameras' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} flitser', other: '${n} flitsers', ), 
			'navigation.marks.camerasFrom' => ({required Object source, required Object date}) => 'Flitsers: ${source}, lijst van ${date}',
			'navigation.marks.bothFrom' => ({required Object source, required Object date}) => 'Flitsers en gevarenzones: ${source}, lijst van ${date}',
			'navigation.marks.sectionLength' => ({required Object distance}) => 'Traject van ${distance}',
			'navigation.marks.cameraDirection' => 'Controleert jouw rijrichting',
			'navigation.guidance.then' => 'Daarna',
			'navigation.guidance.arrival' => ({required Object time}) => 'Aankomst ${time}',
			'navigation.guidance.offRoute' => 'Van de route af',
			'navigation.guidance.rerouting' => 'Nieuwe route wordt gezocht',
			'navigation.guidance.rerouted' => 'Nieuwe route',
			'navigation.guidance.reroutedLonger' => ({required Object minutes}) => 'Nieuwe route, ${minutes} min langer',
			'navigation.guidance.rerouteOffline' => 'Geen verbinding voor een nieuwe route: keer terug naar de route',
			'navigation.guidance.rerouteFailed' => 'Geen nieuwe route gevonden: keer terug naar de route',
			'navigation.guidance.closureAhead' => ({required Object distance}) => 'Weg afgesloten over ${distance}: andere route wordt gezocht',
			'navigation.guidance.noDetour' => ({required Object distance}) => 'Weg afgesloten over ${distance}: geen andere weg',
			'navigation.guidance.eventAhead' => ({required Object distance}) => 'Werkzaamheden over ${distance}',
			'navigation.guidance.eventClosure' => ({required Object distance}) => 'Weg afgesloten over ${distance}',
			'navigation.guidance.eventLimit' => ({required Object distance}) => 'Voertuigbeperking door werkzaamheden over ${distance}',
			'navigation.guidance.eventSource' => ({required Object source, required Object time}) => '${source}, gegevens van ${time}',
			'navigation.guidance.eventSourceOn' => ({required Object source, required Object day, required Object time}) => '${source}, gegevens van ${day} om ${time}',
			'navigation.guidance.avoidedClosures' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Route berekend om een afsluiting heen', other: 'Route berekend om ${n} afsluitingen heen', ), 
			'navigation.guidance.roadEventAhead' => ({required Object what, required Object distance}) => '${what} over ${distance}',
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Weg afgesloten over ${distance}: geen verbinding om een andere route te zoeken',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Weg afgesloten over ${distance}: nog geen andere weg',
			'navigation.guidance.voiceMode.full' => 'Volledige stem',
			'navigation.guidance.voiceMode.alerts' => 'Stem: alleen waarschuwingen',
			'navigation.guidance.voiceMode.muted' => 'Stem uit',
			'navigation.guidance.voiceMode.toFull' => 'Terug naar de volledige stem',
			'navigation.guidance.voiceMode.toAlerts' => 'Alleen waarschuwingen laten uitspreken',
			'navigation.guidance.voiceMode.toMuted' => 'Stem uitzetten',
			'navigation.guidance.voiceMode.saysFull' => 'Volledige stem: alle instructies en alle waarschuwingen.',
			'navigation.guidance.voiceMode.saysAlerts' => 'Alleen waarschuwingen: de stem spreekt alleen bij flitsers, gevaren en routewijzigingen.',
			'navigation.guidance.voiceMode.saysMuted' => 'Stem uit: alles staat op het scherm, zonder geluid.',
			'navigation.guidance.overview' => 'Hele route',
			'navigation.guidance.recenter' => 'Centreren',
			'navigation.guidance.end' => 'Stoppen',
			'navigation.guidance.endTitle' => 'Navigatie stoppen?',
			'navigation.guidance.endConfirm' => 'Stoppen',
			'navigation.guidance.endKeep' => 'Doorgaan',
			'navigation.guidance.stopTitle' => 'Navigatie stoppen?',
			'navigation.guidance.stopConfirm' => 'Stoppen',
			'navigation.guidance.arrivedTitle' => 'Je bent aangekomen',
			'navigation.guidance.done' => 'Klaar',
			'navigation.guidance.speed' => 'Snelheid',
			'navigation.guidance.limit' => 'Limiet',
			'navigation.guidance.noVoice' => ({required Object language}) => 'Geen stem in het ${language} op dit apparaat: instructies alleen op het scherm.',
			'navigation.guidance.missingVoice' => ({required Object language}) => 'De stem in het ${language} is nog niet gedownload.',
			'navigation.guidance.installVoice' => 'Installeren',
			'navigation.guidance.voiceSettingsIos' => 'Instellingen, Toegankelijkheid, Gesproken materiaal, Stemmen',
			'navigation.guidance.notificationTitle' => 'Lunaway wijst je de weg',
			'navigation.guidance.notificationText' => 'De navigatie gaat door als het scherm uitstaat.',
			'navigation.guidance.notificationChannel' => 'Navigatie',
			'navigation.guidance.unavailable' => 'De navigatie kon op dit apparaat niet starten.',
			'navigation.guidance.notificationWhy.title' => 'Melding voor de navigatie',
			'navigation.guidance.notificationWhy.body' => 'Tijdens het navigeren houdt een melding de positie en de stem actief als het scherm uitstaat, en met een tik op de melding kom je terug in de navigatie. Android vraagt of Lunaway deze melding mag tonen.',
			'navigation.guidance.notificationWhy.ask' => 'Doorgaan',
			'navigation.guidance.notificationWhy.later' => 'Niet nu',
			'navigation.guidance.positionLost' => 'Positie niet beschikbaar: controleer of locatie op het apparaat aanstaat voor Lunaway.',
			'navigation.guidance.positionStale' => ({required Object minutes}) => 'Laatste positie ${minutes} min geleden ontvangen: de aankomsttijd is daarop gebaseerd.',
			'navigation.guidance.limitEstimated' => 'Geschatte limiet',
			'navigation.guidance.overLimit' => 'boven de limiet',
			'navigation.guidance.enforcementSource' => ({required Object source, required Object date}) => '${source}, lijst van ${date}',
			'navigation.guidance.demoDrive' => 'Gesimuleerde rit: demonstratie zonder gps',
			'navigation.guidance.places.button' => 'Plekken op de kaart',
			'navigation.guidance.places.buttonHidden' => 'Plekken op de kaart: verborgen',
			'navigation.guidance.places.title' => 'Plekken op de kaart',
			'navigation.guidance.places.sleep' => 'Overnachten',
			'navigation.guidance.places.fill' => 'Tanken',
			'navigation.guidance.places.groceries' => 'Eten',
			'navigation.guidance.places.all' => 'Alles',
			'navigation.guidance.places.everyPlace' => 'Alle plekken',
			'navigation.guidance.places.none' => 'Niets',
			'navigation.guidance.places.customize' => 'Aanpassen',
			'navigation.guidance.places.look' => 'Weergave',
			'navigation.guidance.places.photos' => 'Foto\'s',
			'navigation.guidance.places.pictograms' => 'Iconen',
			'navigation.guidance.places.dots' => 'Kleine spelden',
			'navigation.guidance.places.photosHint' => 'De belangrijkste plekken als foto. Nooit op de weg voor je en nooit onder de knoppen.',
			'navigation.guidance.places.pictogramsHint' => 'De belangrijkste plekken groter, met prijs, beoordeling of overnachten.',
			'navigation.guidance.places.dotsHint' => 'Alle plekken als kleine spelden, zoals op de kaart.',
			'navigation.guidance.places.free' => 'Gratis',
			'navigation.guidance.places.nightOk' => 'Overnachten',
			'navigation.voice.rerouting' => 'Route wordt opnieuw berekend.',
			'navigation.voice.rerouted' => 'Nieuwe route.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(minutes, one: 'Nieuwe route, één minuut langer.', other: 'Nieuwe route, ${minutes} minuten langer.', ), 
			'navigation.voice.moved.destination' => ({required Object distance}) => 'De bestemming is ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken.',
			'navigation.voice.moved.stop' => ({required Object n, required Object distance}) => 'Tussenstop ${n} is ${distance} verplaatst naar de dichtstbijzijnde straat die je voertuig kan bereiken.',
			'navigation.voice.closureAhead' => ({required Object distance}) => 'Over ${distance} is de weg afgesloten. Er wordt een andere route gezocht.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'Over ${distance} is de weg afgesloten. Er is geen andere route.',
			'navigation.voice.clearance' => ({required Object distance, required Object height}) => 'Let op, over ${distance} een lage doorrijhoogte van ${height}.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Let op, over ${distance} een lage doorrijhoogte, hoogte onbekend.',
			'navigation.voice.narrow' => ({required Object distance, required Object width}) => 'Let op, over ${distance} een versmalling tot ${width}.',
			'navigation.voice.limit' => ({required Object distance, required Object what}) => 'Let op, over ${distance}: ${what}.',
			'navigation.voice.arrived' => 'Je bent aangekomen.',
			'navigation.voice.metres' => ({required Object n}) => '${n} meter',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count, one: '${n} kilometer', other: '${n} kilometer', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} voet',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count, one: '${n} mijl', other: '${n} mijl', ), 
			'navigation.voice.size' => ({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count, one: '${metres} meter ${cm}', other: '${metres} meter ${cm}', ), 
			'navigation.voice.sizeWhole' => ({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count, one: '${metres} meter', other: '${metres} meter', ), 
			'navigation.voice.overSpeed' => ({required Object limit}) => 'Maximumsnelheid ${limit}.',
			'navigation.voice.dangerZone' => ({required Object distance}) => 'Over ${distance} een gevarenzone.',
			'navigation.voice.inDangerZone' => 'Gevarenzone.',
			'navigation.voice.localAccess.weight' => ({required Object distance, required Object limit}) => 'Let op, over ${distance} boven ${limit} alleen bestemmingsverkeer.',
			'navigation.voice.localAccess.axleLoad' => ({required Object distance, required Object limit}) => 'Let op, over ${distance} boven ${limit} per as alleen bestemmingsverkeer.',
			'navigation.voice.localAccess.width' => ({required Object distance, required Object limit}) => 'Let op, over ${distance} breder dan ${limit} alleen bestemmingsverkeer.',
			'navigation.voice.localAccess.length' => ({required Object distance, required Object limit}) => 'Let op, over ${distance} langer dan ${limit} alleen bestemmingsverkeer.',
			'navigation.voice.roadEvent.works' => ({required Object distance}) => 'Over ${distance} werkzaamheden.',
			'navigation.voice.roadEvent.lanes' => ({required Object distance}) => 'Over ${distance} een rijstrook afgesloten.',
			'navigation.voice.roadEvent.vehicleLimit' => ({required Object distance}) => 'Let op, over ${distance} een voertuigbeperking door werkzaamheden.',
			'navigation.voice.roadEvent.closure' => ({required Object distance}) => 'Over ${distance} is de weg mogelijk afgesloten.',
			'navigation.voice.roadEvent.detour' => ({required Object distance}) => 'Over ${distance} een omleiding aangegeven.',
			'navigation.voice.positionLost' => 'Positie niet beschikbaar. Controleer de locatie van het apparaat.',
			'navigation.voice.tonnes' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(count, one: '${n} ton', other: '${n} ton', ), 
			'navigation.voice.camera.kind.fixed' => 'een vaste flitser',
			'navigation.voice.camera.kind.redLight' => 'een roodlichtcamera',
			'navigation.voice.camera.kind.levelCrossing' => 'een flitser bij een overweg',
			'navigation.voice.camera.kind.section' => 'een trajectcontrole',
			'navigation.voice.camera.kind.other' => 'een flitser',
			'navigation.voice.camera.radar' => ({required Object distance, required Object what}) => 'Over ${distance} ${what}.',
			'navigation.voice.camera.radarLimit' => ({required Object distance, required Object what, required Object limit}) => 'Over ${distance} ${what}, maximaal ${limit}.',
			'navigation.voice.camera.sectionLimit' => ({required Object distance, required Object what, required Object limit}) => 'Over ${distance} ${what}, gemiddeld maximaal ${limit}.',
			'navigation.voice.camera.inSection' => 'Trajectcontrole.',
			'navigation.voice.camera.slowDownRadar' => ({required Object limit}) => 'Rem af, flitser bij ${limit}.',
			'navigation.voice.camera.slowDownRoad' => ({required Object limit}) => 'Rem af, maximaal ${limit}.',
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/u',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} u ${m} min',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Navigatie',
			'navigation.settings.avoidTitle' => 'Standaard vermijden',
			'navigation.settings.voice' => 'Gesproken navigatie',
			'navigation.settings.voiceFull' => 'Volledig',
			'navigation.settings.voiceAlerts' => 'Waarschuwingen',
			'navigation.settings.voiceMuted' => 'Uit',
			'navigation.settings.voiceFullHint' => 'De instructies en de waarschuwingen, met de stem van het apparaat.',
			'navigation.settings.voiceAlertsHint' => 'Alleen flitsers en gevarenzones, afsluitingen, werkzaamheden en voertuigbeperkingen op je route, en routewijzigingen, na een kort signaal.',
			'navigation.settings.voiceMutedHint' => 'Geen geluid: de instructies en de waarschuwingen staan op het scherm.',
			'navigation.settings.units' => 'Afstanden',
			'navigation.settings.metric' => 'Kilometers',
			'navigation.settings.imperial' => 'Mijlen',
			'navigation.settings.speedLimit' => 'Maximumsnelheid',
			'navigation.settings.speedLimitHint' => 'Toont tijdens het navigeren de maximumsnelheid voor je voertuig naast je snelheid; een schatting staat in grijs.',
			'navigation.settings.speedSound' => 'Gesproken snelheidswaarschuwing',
			'navigation.settings.speedSoundHint' => 'Een korte waarschuwing als je te hard rijdt, met de volledige stem. Flitsers en gevarenzones volgen de gesproken navigatie.',
			'navigation.settings.exactFrance' => 'Exacte locatie van flitsers in Frankrijk',
			'navigation.settings.exactFranceHint' => 'In Frankrijk wordt het bezit van een apparaat dat de locatie van flitsers aangeeft bestraft met een boete van € 1.500 en 6 punten (Code de la route, art. R413-15).',
			'navigation.enforcement.fixed' => 'Vaste flitser',
			'navigation.enforcement.redLight' => 'Roodlichtcamera',
			'navigation.enforcement.levelCrossing' => 'Flitser bij overweg',
			'navigation.enforcement.section' => 'Trajectcontrole',
			'navigation.enforcement.zone' => 'Gevarenzone',
			'navigation.enforcement.average' => ({required Object limit}) => 'gemiddeld ${limit}',
			'navigation.enforcement.averageLabel' => 'gemiddeld',
			'navigation.enforcement.remaining' => ({required Object distance}) => 'nog ${distance}',
			'navigation.enforcement.yourAverage' => ({required Object speed}) => 'je gemiddelde ${speed}',
			'navigation.enforcement.zoneEnd' => 'Einde gevarenzone',
			'navigation.enforcement.sectionEnd' => 'Einde trajectcontrole',
			'navigation.enforcement.ruleOff' => ({required Object country}) => '${country}: geen flitserwaarschuwingen',
			'navigation.enforcement.ruleZones' => ({required Object country}) => '${country}: gevarenzones',
			'navigation.enforcement.ruleExact' => ({required Object country}) => '${country}: flitsers',
			'navigation.enforcement.ahead' => ({required Object what, required Object distance}) => '${what} over ${distance}',
			'navigation.enforcement.limit' => ({required Object limit}) => 'maximaal ${limit}',
			'navigation.enforcement.averageLimit' => ({required Object limit}) => 'gemiddeld maximaal ${limit}',
			'list.title' => 'Plekken in de buurt',
			'list.empty' => 'Hier geen plekken met deze filters',
			'list.emptyHint' => 'Verschuif de kaart, zoom uit of maak de filters ruimer.',
			'list.downloading' => 'De plekken komen eraan',
			'list.downloadingHint' => 'De lijst vult zich tijdens het downloaden.',
			'list.error' => 'De lijst kon niet worden geladen.',
			'list.offline' => 'Geen verbinding: de lijst werkt alleen online.',
			'list.moreFailed' => 'Meer plekken konden niet worden geladen. Opnieuw proberen',
			'list.sortDistance' => 'Afstand',
			'list.sortRating' => 'Beoordeling',
			'list.sortNewest' => 'Onlangs toegevoegd',
			'list.sortedBy' => ({required Object sort}) => 'Lijst gesorteerd op: ${sort}',
			'list.rankedAmongNearestYou' => ({required Object n}) => 'Gesorteerd binnen de ${n} plekken die het dichtst bij je liggen',
			'list.rankedAmongNearestCentre' => ({required Object n}) => 'Gesorteerd binnen de ${n} plekken die het dichtst bij het midden van de kaart liggen',
			'list.offlineTitle' => 'Geen verbinding',
			'list.offlineNotHere' => 'Niets van dit gebied op dit apparaat.',
			'favorites.title' => 'Favorieten',
			'favorites.defaultList' => 'Mijn favorieten',
			'favorites.empty' => 'Hier is nog niets opgeslagen',
			'favorites.emptyHint' => 'Tik bij een plek op Opslaan om hem te bewaren, ook offline.',
			'favorites.newList' => 'Nieuwe lijst',
			'favorites.listName' => 'Naam van de lijst',
			'favorites.renameList' => 'Lijst hernoemen',
			'favorites.deleteList' => 'Lijst verwijderen',
			'favorites.deleteListConfirm' => ({required Object name}) => '“${name}” verwijderen? De plekken blijven op de kaart.',
			'favorites.listActions' => 'Lijstopties',
			'favorites.placeActions' => 'Opties voor deze plek',
			'favorites.openOnMap' => 'Bekijken op de kaart',
			'favorites.remove' => 'Uit de lijst verwijderen',
			'favorites.removed' => 'Uit de lijst verwijderd',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, zero: 'Leeg', one: '${n} plek', other: '${n} plekken', ), 
			'favorites.error' => 'Je favorieten konden niet worden geladen.',
			'vehicle.title' => 'Mijn voertuig',
			'vehicle.why' => 'Met de afmetingen worden plekken verborgen waar je voertuig niet past. Ze worden bij elke routeaanvraag meegestuurd en niet bewaard.',
			'vehicle.none' => 'Beschrijf je voertuig om plekken te verbergen waar het niet past.',
			'vehicle.add' => 'Mijn voertuig beschrijven',
			'vehicle.edit' => 'Wijzigen',
			'vehicle.type' => 'Type',
			'vehicle.types.van' => 'Busje',
			'vehicle.types.campervan' => 'Buscamper',
			'vehicle.types.lowProfile' => 'Halfintegraal',
			'vehicle.types.overcab' => 'Alkoof',
			'vehicle.types.integrated' => 'Integraal',
			'vehicle.towingTitle' => 'Trekt hij iets?',
			'vehicle.towing.none' => 'Niets',
			'vehicle.towing.car' => 'Een auto',
			'vehicle.towing.trailer' => 'Een aanhanger',
			'vehicle.size' => 'Afmetingen',
			'vehicle.sizeHint' => 'Gangbare waarden voor het gekozen type: pas ze aan met de gegevens van je kentekenbewijs.',
			'vehicle.height' => 'Hoogte',
			'vehicle.width' => 'Breedte',
			'vehicle.length' => 'Totale lengte, inclusief wat je trekt',
			'vehicle.weight' => 'Toegestane maximummassa',
			'vehicle.heightShort' => ({required Object value}) => 'H ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'B ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'L ${value}',
			'vehicle.notANumber' => 'Een getal, bijvoorbeeld 2,90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Tussen ${min} en ${max} ${unit}',
			'vehicle.navigationLater' => 'De navigatie van Lunaway houdt rekening met al deze afmetingen.',
			'vehicle.save' => 'Opslaan',
			'vehicle.clear' => 'Wissen',
			'vehicle.fuelTitle' => 'Brandstof',
			'vehicle.fuelHint' => 'De prijs van jouw brandstof staat bij de tankstations op de kaart, de goedkoopste eerst.',
			'vehicle.consumption' => 'Verbruik',
			'vehicle.consumptionUnit' => 'l/100 km',
			'vehicle.lpgHeating' => 'Verwarming op LPG',
			'vehicle.lpgHeatingHint' => 'LPG-prijzen staan ook bij de tankstations.',
			'vehicle.cruiseTitle' => 'Maximale kruissnelheid',
			'vehicle.cruiseHint' => 'Reistijden gaan ervan uit dat je nooit harder rijdt, ook waar de weg dat toestaat. De maximumsnelheden die tijdens het rijden worden aangekondigd, blijven die van de weg.',
			'vehicle.cruiseNone' => 'Geen limiet',
			'vehicleHeight.title' => 'Hoogte van je voertuig',
			'vehicleHeight.why' => 'Plekken met een hoogtelimiet onder deze hoogte worden verborgen. Plekken waarvan de hoogte niet bekend is, blijven zichtbaar.',
			'vehicleHeight.needed' => 'Vul de hoogte in, bijvoorbeeld 2,90',
			'vehicleHeight.weightOptional' => 'Toegestane maximummassa (optioneel)',
			'vehicleHeight.apply' => 'Filteren met deze hoogte',
			'vehicleHeight.later' => 'De rest van het voertuig beschrijf je in Profiel, Mijn voertuig.',
			'profile.title' => 'Profiel',
			'profile.noAccountNeeded' => 'Geen account, geen advertenties, geen trackers. Je favorieten blijven op dit apparaat.',
			'profile.language' => 'Taal',
			'profile.languageSystem' => 'Systeemtaal',
			'profile.appearance' => 'Weergave',
			'profile.themeAuto' => 'Automatisch',
			'profile.themeLight' => 'Licht',
			'profile.themeDark' => 'Donker',
			'profile.themeAutoHint' => 'Licht overdag, donker na zonsondergang waar je bent.',
			'profile.themeLightHint' => 'Altijd licht, dag en nacht.',
			'profile.themeDarkHint' => 'Altijd donker, \'s nachts rustig voor de ogen.',
			'profile.offline' => 'Offline',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'plek op dit apparaat', other: 'plekken op dit apparaat', ), 
			'profile.offlineSize' => ({required Object size}) => 'Gebruikte opslag: ${size}',
			'profile.lastSync' => ({required Object when}) => 'Laatst bijgewerkt ${when}',
			'profile.neverSynced' => 'Nooit gedownload',
			'profile.syncNow' => 'Nu bijwerken',
			'profile.syncing' => 'Bezig met bijwerken',
			'profile.about' => 'Over de app',
			'profile.version' => ({required Object version}) => 'Versie ${version}',
			'profile.website' => 'Website',
			'profile.privacy' => 'Privacybeleid',
			'profile.sourceCode' => 'Broncode',
			'profile.licences' => 'Licenties',
			'profile.appLicence' => 'Lunaway is vrije software onder de GNU AGPL 3.0 of later.',
			'profile.routeData' => 'Routes worden berekend met open data die onvolledig kunnen zijn: verkeersborden en verkeersregels gaan voor.',
			'profile.attributions' => 'Bronnen en vermeldingen',
			'profile.attributionOsm' => 'Plekken en kaartgegevens © bijdragers van OpenStreetMap.',
			'profile.attributionOdbl' => 'Gegevens van OpenStreetMap onder de Open Database License (ODbL).',
			'profile.attributionAtout' => 'Geclassificeerde campings van Atout France, geplaatst met de Base Adresse Nationale en de BD TOPO van het IGN, onder de Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Gemeenten van de plekken: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), onder de ODbL.',
			'profile.attributionCommunityPlaces' => 'Plekken die reizigers van Lunaway hebben toegevoegd of gewijzigd, onder de ODbL, met de vermelding “Lunaway contributors”.',
			'profile.attributionTiles' => 'Basiskaart geleverd door Lunaway, stijlen afgeleid van Protomaps (BSD-3-Clause), gegevens © bijdragers van OpenStreetMap.',
			'profile.attributionFonts' => 'Lettertypen Fraunces en Atkinson Hyperlegible Next, SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Phosphor-pictogrammen, MIT-licentie.',
			'profile.noTracking' => 'Geen advertenties, geen trackers. Je account kent je e-mailadres en je telefoonnummer niet.',
			'profile.attributionBdTopo' => 'Hoogte-, breedte-, lengte- en gewichtsbeperkingen van de wegen, en de positie van campings, gevonden via hun naam: IGN BD TOPO, via de Géoplateforme, onder de Licence Ouverte 2.0.',
			'profile.attributionAddresses' => 'Adressen bij het zoeken in Frankrijk: de Base Adresse Nationale, via de Géoplateforme van het IGN, onder de Licence Ouverte 2.0.',
			'profile.attributionAddressesOsm' => 'Adressen bij het zoeken elders: OpenStreetMap, via Photon, onder de ODbL.',
			'profile.attributionPoiOdbl' => 'Winkels en diensten: OpenStreetMap, en de openingskalender van La Poste, onder de ODbL.',
			'profile.attributionPoiLo' => 'Brandstofprijzen (Frans ministerie van Economie) en de zorginstellingen van FINESS (Agence du numérique en santé), onder de Licence Ouverte 2.0 (Etalab).',
			'profile.attributionPacks' => 'Contouren van de offline kaarten: Contours administratifs, data.gouv.fr (ODbL), en Natural Earth (publiek domein).',
			'profile.attributionOfflineLabels' => 'Namen en pictogrammen van de offline kaarten: Noto Sans-glyphs (SIL Open Font License 1.1) en Protomaps-sprites afgeleid van tangrams/icons (MIT).',
			'profile.attributionExtcom' => 'Plekken, reviews, beoordelingen en foto\'s, onder een schriftelijke overeenkomst met deze bron.',
			'profile.creditsPlaces' => 'Plekken',
			'profile.creditsContent' => 'Foto\'s, teksten en reviews',
			'profile.creditsRoutes' => 'Routes en navigatie',
			'profile.creditsSearch' => 'Zoeken',
			'profile.creditsMap' => 'Basiskaart',
			'profile.creditsApp' => 'App',
			'profile.attributionDatatourisme' => 'Plekken, beschrijvingen en foto\'s van de toeristenbureaus: DATAtourisme, onder de Licence Ouverte 2.0; bij elke tekst en elke foto staan het bureau, de auteur en de datum van de laatste update.',
			'profile.attributionCommunity' => 'Reviews, beoordelingen en foto\'s van de reizigers van Lunaway, onder CC BY 4.0, met het pseudoniem van de auteur.',
			'profile.attributionCommons' => 'Foto\'s van Wikimedia Commons, elk onder een eigen licentie (CC0, publiek domein, CC BY of CC BY-SA), met de auteur en een link naar de pagina.',
			'profile.attributionPanoramax' => 'Straatbeelden van Panoramax: de instantie van OpenStreetMap France onder CC BY-SA 4.0, die van het IGN onder de Licence Ouverte 2.0.',
			'profile.attributionWikipedia' => 'Fragmenten uit Wikipedia-artikelen, onder CC BY-SA 4.0, met een link naar het artikel.',
			'profile.attributionMangrove' => 'Reviews van Mangrove Reviews, onder CC BY 4.0 of de licentie die de review vermeldt, met een link naar de review.',
			'profile.attributionTranslation' => 'Automatische vertalingen: OPUS-MT-modellen van de Universiteit van Helsinki, onder CC BY 4.0, uitgevoerd op de servers van Lunaway.',
			'profile.attributionRoadEvents' => 'Werkzaamheden en afsluitingen in Frankrijk: DIR en Bison Futé, verkeersbesluiten van DiaLog (DGITM), steden en departementen (Lyon, Toulouse, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Sarthe), onder de Licence Ouverte 2.0; Bordeaux Métropole en het departement Côtes-d\'Armor, onder de Licence Ouverte; Ville de Paris, Rennes Métropole en de meldingen van de reizigers van Lunaway, onder de ODbL.',
			'profile.attributionRoadEventsAbroad' => 'Werkzaamheden en afsluitingen in Nederland: NDW, Nationaal Dataportaal Wegverkeer (open data); in Spanje: DGT, Dirección General de Tráfico (CC BY).',
			'profile.attributionDangerZones' => 'Flitsers en gevarenzones: in Frankrijk de kaart van de Sécurité routière, hergebruikt volgens de Franse Code des relations entre le public et l\'administration, en de lijst van vaste flitsers van het ministerie van Binnenlandse Zaken, Délégation à la sécurité routière (data.gouv.fr), onder de Licence Ouverte 2.0; in Polen Główny Inspektorat Transportu Drogowego (CANARD, dane.gov.pl), in Luxemburg de Administration des ponts et chaussées (data.public.lu), in Brussel Bruxelles Mobilité (data.mobility.brussels), onder CC0; in Noorwegen “Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.”; in Ierland de controlezones van An Garda Síochána, Irish Public Sector Information, CC BY, trajecten aangepast door Lunaway; OpenStreetMap (ODbL).',
			'profile.attributionCameraSource' => ({required Object attribution}) => 'Flitsers en gevarenzones: ${attribution}',
			'units.kilobytes' => ({required Object n}) => '${n} kB',
			'units.megabytes' => ({required Object n}) => '${n} MB',
			'languages.fr' => 'Frans',
			'languages.en' => 'Engels',
			'languages.de' => 'Duits',
			'languages.es' => 'Spaans',
			'languages.it' => 'Italiaans',
			'languages.nl' => 'Nederlands',
			'translation.translate' => 'Vertalen',
			'translation.translating' => 'Bezig met vertalen',
			'translation.showOriginal' => 'Origineel tonen',
			'translation.showTranslation' => 'Vertaling tonen',
			'translation.from.fr' => 'Automatisch vertaald uit het Frans',
			'translation.from.en' => 'Automatisch vertaald uit het Engels',
			'translation.from.de' => 'Automatisch vertaald uit het Duits',
			'translation.from.es' => 'Automatisch vertaald uit het Spaans',
			'translation.from.it' => 'Automatisch vertaald uit het Italiaans',
			'translation.from.nl' => 'Automatisch vertaald uit het Nederlands',
			'translation.from.unknown' => ({required Object language}) => 'Automatisch vertaald (oorspronkelijke taal: ${language})',
			'translation.offline' => 'Voor het vertalen is een internetverbinding nodig.',
			'translation.failedOffline' => 'Geen internetverbinding: de tekst kon niet worden vertaald.',
			'translation.busy' => 'De vertaaldienst is overbelast. Probeer het later opnieuw.',
			'translation.unavailable' => 'Vertalen is op dit moment niet beschikbaar.',
			'translation.gone' => 'Deze tekst is niet meer beschikbaar.',
			'translation.unsupported' => 'Voor deze taal is geen vertaling beschikbaar.',
			'translation.autoReviews' => 'Reviews automatisch vertalen',
			'translation.autoReviewsHint' => 'Reviews in een andere taal worden vertaald op de eigen server van Lunaway, zonder tussenkomst van derden.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			'locale.de' => 'Deutsch',
			'locale.es' => 'Español',
			'locale.it' => 'Italiano',
			'locale.nl' => 'Nederlands',
			'account.title' => 'Je account',
			'account.noneTitle' => 'Nog geen account',
			'account.noneBody' => 'De kaart, het zoeken en de favorieten werken zonder account. Er wordt er een aangemaakt bij je eerste bijdrage (een beoordeling, een bevestiging, een foto), zonder e-mailadres en zonder wachtwoord. Je favorietenlijsten worden er dan aan gekoppeld.',
			'account.recover' => 'Mijn account herstellen',
			'account.memberSince' => ({required Object date}) => 'Lid sinds ${date}',
			'account.editPseudonym' => 'Pseudoniem wijzigen',
			'account.pseudonymTitle' => 'Je pseudoniem',
			'account.pseudonymHint' => 'Openbaar: het staat bij je reviews en foto\'s. 3 tot 32 tekens.',
			'account.pseudonymInvalid' => '3 tot 32 tekens, waarvan minstens twee letters.',
			'account.pseudonymRefused' => 'Dit pseudoniem wordt niet geaccepteerd: geen link, geen contactgegevens, geen scheldwoord, geen naam die het account laat doorgaan voor het team.',
			'account.pseudonymSaved' => 'Pseudoniem opgeslagen',
			'account.level' => ({required Object level}) => 'Vertrouwensniveau ${level}',
			'account.levelOpens.l0' => 'Je kunt plekken beoordelen, bevestigen dat ze er nog zijn, een probleem melden en je favorieten synchroniseren.',
			'account.levelOpens.l1' => 'Je kunt ook reviews schrijven, foto\'s toevoegen en wijzigingen aan plekken voorstellen.',
			'account.levelOpens.l2' => 'Je kunt ook plekken toevoegen.',
			'account.levelOpens.l3' => 'Je wijzigingen aan plekken worden zonder controle doorgevoerd.',
			'account.levelOpens.l4' => 'Je helpt mee met de moderatie.',
			'account.nextLevel' => ({required Object level}) => 'Voor niveau ${level}',
			'account.levelTop' => 'Je zit op het hoogste niveau.',
			'account.requirement.age' => ({required Object needed, required Object current}) => 'Een account van minstens ${needed} dagen oud (nu ${current})',
			'account.requirement.confirmations' => ({required Object needed, required Object current}) => '${needed} bevestigingen van verschillende plekken (nu ${current})',
			'account.requirement.contributions' => ({required Object needed, required Object current}) => '${needed} gepubliceerde bijdragen (nu ${current})',
			'account.requirement.activeDays' => ({required Object needed, required Object current}) => '${needed} actieve dagen (nu ${current})',
			'account.requirement.noRemoval' => 'Geen bijdrage verwijderd door de moderators',
			'account.requirement.sponsor' => 'Een lid op niveau 2 dat voor je instaat',
			'account.requirement.nomination' => 'Een benoeming door de moderators',
			'account.requirement.administration' => 'Een aanstelling door het Lunaway-team',
			'account.orInstead' => ({required Object requirement}) => 'Of ${requirement}',
			'account.recoveryNone' => 'Op dit apparaat is geen herstelkaart gemaakt. Zonder herstelkaart blijft dit account op dit apparaat: raak je het apparaat kwijt, dan ben je ook het account kwijt.',
			'account.recoveryNoneAccount' => 'Nog geen herstelkaart voor dit account. Zonder herstelkaart blijft dit account op dit apparaat: raak je het apparaat kwijt, dan ben je ook het account kwijt.',
			'account.recoveryCreate' => 'Mijn herstelkaart maken',
			'account.recoveryMade' => ({required Object date}) => 'Gemaakt op ${date}',
			'account.recoveryRemake' => 'Opnieuw maken',
			'account.recoveryRemakeHint' => 'Een nieuwe herstelkaart maken',
			'account.contributions' => 'Mijn bijdragen',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} bijdrage wacht op verzending', other: '${n} bijdragen wachten op verzending', ), 
			'account.mutedAuthors' => 'Verborgen auteurs',
			'account.devices' => 'Apparaten',
			'account.signOut' => 'Uitloggen',
			'account.delete' => 'Mijn account verwijderen',
			'account.signOutTitle' => 'Uitloggen op dit apparaat?',
			'account.signOutBody' => 'De sleutel van het account wordt van dit apparaat verwijderd. Om terug te komen heb je je herstelkaart nodig. Je favorieten blijven hier.',
			'account.signOutNoCard' => 'Je hebt op dit apparaat geen herstelkaart gemaakt. Zonder herstelkaart ben je dit account voorgoed kwijt.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Eén bijdrage die nog op verzending wacht, wordt niet verstuurd.', other: '${n} bijdragen die nog op verzending wachten, worden niet verstuurd.', ), 
			'account.signedOut' => 'Uitgelogd. Je favorieten blijven op dit apparaat.',
			'account.lost' => 'Dit account gaat niet meer open op dit apparaat. Herstel het met je herstelkaart: Profiel, Mijn account herstellen.',
			'account.lostAction' => 'Herstellen',
			'account.welcomeTitle' => 'Bedankt voor je eerste bijdrage',
			_ => null,
		} ?? switch (path) {
			'account.welcomeBody' => ({required Object name}) => 'Je account is aangemaakt, met het pseudoniem “${name}”. Geen e-mailadres en geen wachtwoord: een sleutel die op dit apparaat wordt bewaard. Je kunt het pseudoniem wijzigen in je profiel.',
			'account.welcomeCard' => 'Maak je herstelkaart om dit account op een ander apparaat terug te vinden.',
			'account.welcomeFavorites' => 'Je favorietenlijsten worden nu bij je account bewaard.',
			'recovery.title' => 'Herstelkaart',
			'recovery.intro' => 'Een code die je account naar een nieuw apparaat brengt. Lunaway bewaart er alleen een vingerafdruk van, genoeg om hem te controleren: de code zelf kan nooit meer worden getoond, en elke nieuwe kaart heeft een andere code.',
			'recovery.replaces' => 'Een nieuwe kaart vervangt de vorige: de oude code werkt dan niet meer.',
			'recovery.replaceTitle' => ({required Object date}) => 'De kaart van ${date} vervangen?',
			'recovery.replaceBody' => ({required Object date}) => 'De nieuwe kaart krijgt een andere code. De code van de kaart van ${date} werkt vanaf nu niet meer. Hij kan niet opnieuw worden getoond: Lunaway heeft er alleen een vingerafdruk van bewaard.',
			'recovery.replaceKeep' => 'De oude houden',
			'recovery.replaceConfirm' => 'Nieuwe kaart maken',
			'recovery.make' => 'Kaart maken',
			'recovery.codeLabel' => 'Je herstelcode',
			'recovery.shownOnce' => 'Deze code wordt maar één keer getoond. Schrijf hem op, of sla de afbeelding op, voordat je sluit.',
			'recovery.saveImage' => 'Afbeelding opslaan',
			'recovery.done' => 'Ik heb de code genoteerd',
			'recovery.doneTitle' => 'Heb je de code bewaard?',
			'recovery.doneBody' => 'Zodra deze pagina dicht is, wordt de code niet meer getoond.',
			'recovery.keep' => 'Op de pagina blijven',
			'recovery.cardHeading' => 'Lunaway-herstelkaart',
			'recovery.cardAccount' => ({required Object name}) => 'Account: ${name}',
			'recovery.cardHow' => 'Om het account te herstellen: Profiel, Mijn account herstellen, en typ dan deze code of scan de kaart.',
			'recovery.cardMade' => ({required Object date}) => 'Gemaakt op ${date}',
			'recovery.cardWarning' => 'Deze code opent het account: deel hem nooit.',
			'recovery.failed' => 'De kaart kon niet worden gemaakt. Er is een verbinding nodig.',
			'recovery.fileName' => 'lunaway-herstelkaart',
			'recovery.step1' => 'Maak de kaart: de code wordt maar één keer getoond.',
			'recovery.step2' => 'Sla de afbeelding op, druk die af, of schrijf de code over.',
			'recovery.step3' => 'Bewaar de kaart in het dashboardkastje, bij de papieren van het voertuig.',
			'recover.title' => 'Mijn account herstellen',
			'recover.intro' => 'Typ de code van je herstelkaart, of scan een foto van de kaart.',
			'recover.field' => 'Herstelcode',
			'recover.fieldHint' => '27 tekens, in groepjes van vier',
			'recover.remaining' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Nog ${n} teken', other: 'Nog ${n} tekens', ), 
			'recover.invalid' => 'Deze code hoort bij geen enkele kaart: controleer elk teken.',
			'recover.valid' => 'Code compleet',
			'recover.scan' => 'Kaart lezen van een foto',
			'recover.scanFile' => 'Afbeelding van de kaart kiezen',
			'recover.reading' => 'Kaart wordt gelezen',
			'recover.scanFailed' => 'Geen leesbare code op deze afbeelding. Probeer een scherpere foto, met de kaart plat neergelegd.',
			'recover.revoke' => 'Mijn oude apparaat is kwijt of gestolen: daar uitloggen',
			'recover.revokeHint' => 'Al je andere apparaten worden uitgelogd.',
			'recover.submit' => 'Account herstellen',
			'recover.notFound' => 'Geen enkel account heeft deze code. Controleer de kaart, of maak een nieuwe vanaf een apparaat waarop je bent ingelogd.',
			'recover.tooMany' => 'Te veel pogingen. Probeer het over een uur opnieuw.',
			'recover.done' => ({required Object name}) => 'Account hersteld: ${name}',
			'deletion.title' => 'Mijn account verwijderen',
			'deletion.intro' => 'Het verwijderen gebeurt direct en is definitief.',
			'deletion.goneTitle' => 'Wat er verdwijnt',
			'deletion.gone.identity' => 'Je pseudoniem en de sleutels van je apparaten',
			'deletion.gone.sessions' => 'Je sessies en je herstelcode',
			'deletion.gone.lists' => 'Je gesynchroniseerde favorietenlijsten en je verborgen auteurs',
			'deletion.gone.photos' => 'Je foto\'s, je beoordelingen zonder tekst en je meldingen',
			'deletion.gone.pending' => 'Je voorstellen die nog op controle wachten',
			'deletion.keptTitle' => 'Wat blijft, zonder je naam',
			'deletion.kept' => 'Je gepubliceerde geschreven reviews, je bevestigingen en je doorgevoerde wijzigingen aan plekken blijven, zonder auteur: ze maken deel uit van de kaart van andere reizigers.',
			'deletion.backups' => 'De back-ups van de server worden binnen ongeveer 30 dagen gewist.',
			'deletion.device' => 'Op dit apparaat blijven je favorieten; de sleutel van het account wordt gewist.',
			'deletion.web' => 'Je kunt het account ook verwijderen op lunaway.net met je herstelcode.',
			'deletion.webLink' => 'lunaway.net/nl/account/delete',
			'deletion.confirmTitle' => 'Definitief verwijderen?',
			'deletion.confirmBody' => ({required Object name}) => 'Het account “${name}” en alles wat hierboven staat, worden nu verwijderd. Niemand kan het terughalen.',
			'deletion.confirmCheck' => 'Ik begrijp dat dit definitief is',
			'deletion.confirm' => 'Account verwijderen',
			'deletion.done' => 'Account verwijderd',
			'deletion.failed' => 'Het account kon niet worden verwijderd. Er is een verbinding nodig.',
			'devices.title' => 'Apparaten',
			'devices.intro' => 'Elk apparaat heeft een eigen sleutel. Verwijder een apparaat dat kwijt is, of een dat je niet meer gebruikt.',
			'devices.thisDevice' => 'Dit apparaat',
			'devices.other' => 'Ander apparaat',
			'devices.added' => ({required Object date}) => 'Toegevoegd op ${date}',
			'devices.lastUsed' => ({required Object when}) => 'Laatst gebruikt ${when}',
			'devices.revoke' => 'Verwijderen',
			'devices.revokeTitle' => 'Dit apparaat verwijderen?',
			'devices.revokeBody' => 'Het wordt uitgelogd en kan het account niet meer gebruiken.',
			'devices.revoked' => 'Apparaat verwijderd',
			'devices.signOutOthers' => 'Alle andere apparaten uitloggen',
			'devices.signedOutOthers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, zero: 'Geen andere sessie open', one: '${n} sessie gesloten', other: '${n} sessies gesloten', ), 
			'devices.error' => 'De apparaten konden niet worden geladen. Er is een verbinding nodig.',
			'muted.title' => 'Verborgen auteurs',
			'muted.empty' => 'Niemand is verborgen',
			'muted.emptyHint' => 'Wil je iemand verbergen, open dan het menu bij een review of foto van die persoon. Verbergen geldt alleen voor jou.',
			'muted.unmute' => 'Weer tonen',
			'muted.unmuted' => ({required Object name}) => 'Bijdragen van ${name} worden weer getoond',
			'mine.title' => 'Mijn bijdragen',
			'mine.pending' => 'Wacht op verzending',
			'mine.pendingHint' => 'Ze worden verstuurd zodra er weer verbinding is.',
			'mine.sendNow' => 'Nu versturen',
			'mine.retry' => 'Opnieuw proberen',
			'mine.discard' => 'Weggooien',
			'mine.discardTitle' => 'Deze bijdrage weggooien?',
			'mine.discardBody' => 'De bijdrage wordt niet verstuurd.',
			'mine.reviews' => 'Reviews en beoordelingen',
			'mine.photos' => 'Foto\'s',
			'mine.confirmations' => 'Bevestigingen',
			'mine.issues' => 'Gemelde problemen',
			'mine.places' => 'Toegevoegde plekken en wijzigingen',
			'mine.empty' => 'Nog niets',
			'mine.emptyHint' => 'Een plek beoordelen of bevestigen dat hij er nog is, telt al als bijdrage.',
			'mine.latest' => ({required Object shown, required Object total}) => 'De nieuwste ${shown} van ${total}',
			'mine.error' => 'Je bijdragen konden niet worden geladen. Er is een verbinding nodig.',
			'mine.deleteTitle' => 'Deze bijdrage verwijderen?',
			'mine.deleteBody' => 'De bijdrage verdwijnt uit Lunaway.',
			'mine.deleteApplied' => 'Deze plek hoort al bij de kaart: hij blijft erop staan, zonder je naam.',
			'mine.deleted' => 'Bijdrage verwijderd',
			'mine.ratingOnly' => 'Alleen beoordeling',
			'mine.status.published' => 'Gepubliceerd',
			'mine.status.pending' => 'Wordt gecontroleerd',
			'mine.status.hidden' => 'Verborgen na meldingen',
			'mine.status.removed' => 'Verwijderd door een moderator',
			'mine.submission.proposed' => 'Wacht op controle',
			'mine.submission.accepted' => 'Geaccepteerd',
			'mine.submission.applied' => 'Op de kaart',
			'mine.submission.rejected' => 'Geweigerd',
			'mine.submission.withdrawn' => 'Ingetrokken',
			'mine.newPlace' => 'Nieuwe plek',
			'mine.edit' => 'Wijziging',
			'mine.aPlace' => 'Een plek',
			'mine.newVendingMachine' => 'Nieuwe automaat',
			'mine.poiConfirmations' => 'Bevestigde winkels en diensten',
			'mine.aPoi' => 'Een winkel of dienst',
			'outbox.kind.rate' => ({required Object stars}) => 'Beoordeling: ${stars} van 5',
			'outbox.kind.review' => 'Review',
			'outbox.kind.deleteReview' => 'Review verwijderen',
			'outbox.kind.confirm' => ({required Object status}) => 'Bevestiging: ${status}',
			'outbox.kind.deleteConfirmation' => 'Bevestiging verwijderen',
			'outbox.kind.reportIssue' => ({required Object kind}) => 'Probleem gemeld: ${kind}',
			'outbox.kind.deleteIssueReport' => 'Melding verwijderen',
			'outbox.kind.reportContent' => 'Melding aan de moderators',
			'outbox.kind.addPlace' => ({required Object name}) => 'Nieuwe plek: ${name}',
			'outbox.kind.editPlace' => 'Wijziging van een plek',
			'outbox.kind.deletePlaceSubmission' => 'Voorgestelde plek intrekken',
			'outbox.kind.photo' => 'Foto',
			'outbox.kind.deletePhoto' => 'Foto verwijderen',
			'outbox.kind.mute' => 'Auteur verbergen',
			'outbox.kind.unmute' => 'Auteur weer tonen',
			'outbox.kind.poiThere' => 'Nog aanwezig: een winkel of dienst',
			'outbox.kind.poiGone' => 'Verdwenen: een winkel of dienst',
			'outbox.kind.addVendingMachine' => 'Nieuwe automaat',
			'outbox.kind.deletePoiConfirmation' => 'Antwoord over een winkel of dienst verwijderen',
			'outbox.kind.reportRoadEvent' => ({required Object kind}) => 'Melding over de weg: ${kind}',
			'outbox.kind.clearRoadEvent' => 'Melding over de weg beëindigd',
			'outbox.waiting' => 'Wacht op verbinding',
			'outbox.sending' => 'Bezig met versturen',
			'outbox.error.forbidden' => 'Geweigerd: je niveau staat dit nog niet toe.',
			'outbox.error.notFound' => 'Geweigerd: de plek of de inhoud bestaat niet meer.',
			'outbox.error.invalid' => 'Geweigerd: controleer de tekst (lengte, links, contactgegevens).',
			'outbox.error.unreadablePhoto' => 'Foto geweigerd: onleesbaar, of al verstuurd.',
			'outbox.error.photoTooLarge' => 'Foto geweigerd: te groot.',
			'outbox.error.placeRefused' => 'De nieuwe plek van deze foto is geweigerd.',
			'outbox.error.fileLost' => 'De foto staat niet meer op het apparaat.',
			'outbox.error.otherAccount' => 'Gemaakt voor een ander account: wordt niet verstuurd.',
			'outbox.error.other' => 'Geweigerd door de server.',
			'outbox.error.duplicate' => 'Geweigerd: dezelfde automaat staat al binnen 25 m op de kaart.',
			'outbox.sent' => 'Bedankt, het is verstuurd',
			'outbox.queued' => 'Geen verbinding: het wordt verstuurd zodra je weer online bent',
			'outbox.refused' => ({required Object reason}) => 'Niet verstuurd. ${reason}',
			'placement.title' => 'Plek aanwijzen',
			'placement.hint' => 'Verschuif de kaart: het kruisje geeft de exacte plek aan.',
			'placement.confirm' => 'Deze plek gebruiken',
			'placement.duplicate' => ({required Object distance, required Object name}) => 'Op ${distance} ligt al “${name}”: is dat dezelfde plek?',
			'placement.same' => 'Ja, de pagina openen',
			'placement.notSame' => 'Nee, het is een andere plek',
			'contribute.yourRating' => 'Jouw beoordeling',
			'contribute.rateHint' => 'Tik op een ster om te beoordelen',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} ster geven', other: '${n} sterren geven', ), 
			'contribute.writeReview' => 'Review schrijven',
			'contribute.editReview' => 'Je review bewerken',
			'contribute.deleteReview' => 'Je review verwijderen',
			'contribute.deleteReviewTitle' => 'Je review verwijderen?',
			'contribute.deleteReviewBody' => 'De tekst en de beoordeling verdwijnen van de pagina.',
			'contribute.deleteRating' => 'Je beoordeling verwijderen',
			'contribute.deleteRatingTitle' => 'Je beoordeling verwijderen?',
			'contribute.deleteRatingBody' => 'Je beoordeling verdwijnt van de pagina van de plek.',
			'contribute.pendingSend' => 'Wacht op verzending',
			'contribute.statusPending' => 'Wordt gecontroleerd: voorlopig alleen voor jou zichtbaar',
			'contribute.statusHidden' => 'Verborgen na meldingen, wacht op een moderator',
			'contribute.statusRemoved' => 'Verwijderd door een moderator',
			'contribute.addPhoto' => 'Foto toevoegen',
			'contribute.firstPhoto' => 'Eerste foto toevoegen',
			'contribute.stillThere' => 'Is het er nog?',
			'contribute.more' => 'Meer acties',
			'contribute.reportIssue' => 'Probleem melden',
			'contribute.proposeEdit' => 'Wijziging voorstellen',
			'contribute.editPlace' => 'Plek bewerken',
			'contribute.reportPlace' => 'Deze plek melden bij de moderators',
			'contribute.toVerifyTitle' => 'Te controleren',
			'contribute.toVerifyBody' => 'Toegevoegd door de community, wacht op twee bevestigingen. Ken je deze plek? Bevestig hem.',
			'contribute.issuesTitle' => 'Meldingen van de afgelopen 30 dagen',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlaceHere' => 'Hier een plek toevoegen',
			'contribute.addPlaceHint' => 'De plek onder het kruisje.',
			'confirmSheet.title' => 'Is het er nog?',
			'confirmSheet.body' => 'Ben je er onlangs geweest? Met je antwoord zien andere reizigers of de pagina klopt. Er wordt geen positie verstuurd.',
			'confirmSheet.stillOk' => 'Ja, zoals beschreven',
			'confirmSheet.closed' => 'Gesloten',
			'confirmSheet.changed' => 'Veranderd',
			'confirmSheet.closedHint' => 'Ontvangt geen reizigers meer',
			'confirmSheet.changedHint' => 'Bestaat nog, maar er is iets veranderd',
			'confirmSheet.note' => 'Iets toe te voegen? (optioneel)',
			'confirmSheet.noteHint' => 'Bijvoorbeeld: hoogtebegrenzer geplaatst, servicezuil verplaatst',
			'confirmSheet.status.stillOk' => 'nog aanwezig',
			'confirmSheet.status.closed' => 'gesloten',
			'confirmSheet.status.changed' => 'veranderd',
			'issueSheet.title' => 'Probleem melden',
			'issueSheet.body' => 'Je melding telt mee in de waarschuwing op de pagina. Je toelichting gaat alleen naar de moderators.',
			'issueSheet.kind.nightBan' => 'Overnachten nu verboden',
			'issueSheet.kind.serviceBroken' => 'Voorziening defect',
			'issueSheet.kind.noAccess' => 'Geen toegang',
			'issueSheet.kind.danger' => 'Gevaar',
			'issueSheet.hint.nightBan' => 'Een bord, een gemeentebesluit, een bezoek van de politie',
			'issueSheet.hint.serviceBroken' => 'Servicezuil, water, lozen of stroom buiten gebruik',
			'issueSheet.hint.noAccess' => 'Een slagboom, werkzaamheden, een afgesloten weg',
			'issueSheet.hint.danger' => 'Diefstal, geweld, instabiele ondergrond',
			'issueSheet.note' => 'Iets toe te voegen? (optioneel)',
			'issueSheet.send' => 'Melden',
			'reportSheet.review' => 'Deze review melden',
			'reportSheet.photo' => 'Deze foto melden',
			'reportSheet.place' => 'Deze plek melden',
			'reportSheet.body' => 'De moderators lezen je melding. De auteur ziet niet wie de melding heeft gedaan.',
			'reportSheet.reason.spam' => 'Reclame of herhaling',
			'reportSheet.reason.offensive' => 'Beledigend, haatdragend of schokkend',
			'reportSheet.reason.wrong' => 'Onjuist of misleidend',
			'reportSheet.reason.privacy' => 'Toont of noemt een persoon, een kenteken, een privéadres',
			'reportSheet.reason.other' => 'Andere reden',
			'reportSheet.note' => 'Vertel meer (optioneel)',
			'reportSheet.noteOther' => 'Beschrijf wat er mis is',
			'reportSheet.sent' => 'Bedankt, de moderators gaan ernaar kijken',
			'reportSheet.mute' => ({required Object name}) => 'Reviews en foto\'s van ${name} verbergen',
			'reportSheet.muteAuthor' => 'Deze auteur verbergen',
			'reportSheet.muteTitle' => ({required Object name}) => '${name} verbergen?',
			'reportSheet.muteBody' => 'De reviews en foto\'s van deze persoon worden niet meer aan jou getoond. Je kunt dit terugdraaien in je profiel.',
			'reportSheet.muted' => ({required Object name}) => '${name} is verborgen',
			'reportSheet.deletePhoto' => 'Mijn foto verwijderen',
			'reportSheet.deletePhotoTitle' => 'Deze foto verwijderen?',
			'reportSheet.deletePhotoBody' => 'De foto verdwijnt van de pagina en van onze servers.',
			'reviewSheet.titleNew' => 'Jouw review',
			'reviewSheet.titleEdit' => 'Je review bewerken',
			'reviewSheet.starsRequired' => 'Kies een beoordeling van 1 tot 5',
			'reviewSheet.text' => 'Jouw review',
			'reviewSheet.textHint' => 'De rust, de ontvangst, de ruimte om te manoeuvreren, wat handig was',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Nog minstens ${n} teken', other: 'Nog minstens ${n} tekens', ), 
			'reviewSheet.visited' => 'Datum van het verblijf',
			'reviewSheet.visitedNone' => 'Niet vermeld',
			'reviewSheet.vehicle' => 'Je voertuig',
			'reviewSheet.vehicleNone' => 'Zeg ik liever niet',
			'reviewSheet.licence' => 'Gepubliceerd onder CC BY 4.0, met je pseudoniem. De datum van het verblijf is optioneel: samen kunnen de datums van je reviews je reisroute verraden.',
			'reviewSheet.publish' => 'Review publiceren',
			'gate.review' => 'Geschreven reviews: vanaf niveau 1',
			'gate.photo' => 'Foto\'s: vanaf niveau 1',
			'gate.addPlace' => 'Plekken toevoegen: vanaf niveau 2',
			'gate.edit' => 'Wijzigingen voorstellen: vanaf niveau 1',
			'gate.why' => 'Niveaus beschermen de kaart tegen misbruik. Ze komen met de tijd en met bijdragen, er valt niets te kopen.',
			'gate.yourLevel' => ({required Object level}) => 'Jouw niveau: ${level}',
			'gate.noAccount' => 'Nog geen account: een account begint op niveau 0.',
			'gate.later' => ({required Object level}) => 'Niveau ${level} komt na de vorige niveaus, met de tijd en met gepubliceerde bijdragen.',
			'gate.meanwhile' => 'Intussen kun je plekken beoordelen, bevestigen dat ze er nog zijn of een probleem melden.',
			'photoFlow.title' => 'Foto toevoegen',
			'photoFlow.camera' => 'Foto maken',
			'photoFlow.gallery' => 'Kiezen uit de galerij',
			'photoFlow.preparing' => 'Foto wordt voorbereid',
			'photoFlow.licence' => 'Gepubliceerd onder CC BY 4.0, met je pseudoniem. Vermijd gezichten en kentekenplaten.',
			'photoFlow.stripped' => 'De locatiegegevens en de apparaatgegevens worden vóór verzending verwijderd.',
			'photoFlow.send' => 'Foto versturen',
			'photoFlow.unreadable' => 'Deze afbeelding kan op dit apparaat niet worden gelezen. Probeer een JPEG- of PNG-foto.',
			'photoFlow.sending' => ({required Object percent}) => 'Versturen: ${percent}%',
			'photoFlow.pending' => 'Foto wacht op verzending',
			'placeForm.addTitle' => 'Plek toevoegen',
			'placeForm.editTitle' => 'Plek bewerken',
			'placeForm.proposeTitle' => 'Wijziging voorstellen',
			'placeForm.position' => 'Positie op de kaart',
			'placeForm.kind' => 'Soort plek',
			'placeForm.kindRequired' => 'Kies een soort plek',
			'placeForm.name' => 'Naam',
			'placeForm.nameHint' => 'De naam die ter plaatse staat, of een korte beschrijving',
			'placeForm.nameInvalid' => '2 tot 120 tekens',
			'placeForm.night' => 'Overnachten',
			'placeForm.services' => 'Voorzieningen ter plaatse',
			'placeForm.description' => 'Beschrijving',
			'placeForm.descriptionHint' => 'Wat helpt om de plek te vinden en te kiezen',
			'placeForm.details' => 'Details',
			'placeForm.priceNight' => 'Prijs per nacht (€)',
			'placeForm.priceServices' => 'Prijs van de service (€)',
			'placeForm.maxHeight' => 'Maximale hoogte (m)',
			'placeForm.capacity' => 'Plaatsen',
			'placeForm.website' => 'Website',
			'placeForm.phone' => 'Telefoon',
			'placeForm.photo' => 'Foto (optioneel)',
			'placeForm.photoReady' => 'Foto klaar',
			'placeForm.removePhoto' => 'Foto verwijderen',
			'placeForm.toVerify' => 'De plek staat als “te controleren” op de kaart tot twee andere reizigers hem bevestigen.',
			'placeForm.licence' => 'Plekken worden gepubliceerd onder de ODbL, met vermelding van de bijdragers van Lunaway.',
			'placeForm.moderated' => 'Een website of telefoonnummer wordt eerst door een moderator bekeken voordat het wordt gepubliceerd.',
			'placeForm.direct' => 'Met jouw niveau wordt de wijziging meteen doorgevoerd.',
			'placeForm.proposal' => 'Een moderator bekijkt je voorstel voordat het wordt doorgevoerd.',
			'placeForm.submitAdd' => 'Plek toevoegen',
			'placeForm.submitEdit' => 'Wijziging opslaan',
			'placeForm.submitPropose' => 'Voorstel versturen',
			'placeForm.nothingChanged' => 'Er is niets gewijzigd',
			'placeForm.invalidNumber' => 'Vul een getal in',
			'placeForm.invalidWebsite' => 'Een adres dat begint met http:// of https://',
			'placeForm.added' => 'Bedankt: de plek staat zo op de kaart',
			'placeForm.proposed' => 'Bedankt: je voorstel wordt gecontroleerd',
			'favoritesSync.local' => 'Alleen op dit apparaat',
			'favoritesSync.action' => 'Synchroniseren',
			'favoritesSync.syncing' => 'Bezig met synchroniseren',
			'favoritesSync.synced' => ({required Object when}) => 'Bewaard bij je account, gesynchroniseerd ${when}',
			'favoritesSync.failed' => 'Synchroniseren lukt nu niet',
			'favoritesSync.title' => 'Je favorieten synchroniseren?',
			'favoritesSync.body' => 'Je lijsten worden bewaard bij een Lunaway-account, zonder e-mailadres en zonder wachtwoord, zodat je ze op een ander apparaat terugvindt. Het account wordt nu aangemaakt.',
			'favoritesSync.confirm' => 'Account maken en synchroniseren',
			'poi.category.groceries' => 'Boodschappen',
			'poi.category.vending' => 'Voedselautomaten',
			'poi.category.water' => 'Water en lozen',
			'poi.category.fuel' => 'Brandstof en energie',
			'poi.category.health' => 'Gezondheid',
			'poi.category.services' => 'Diensten',
			'poi.category.food' => 'Restaurants en cafés',
			'poi.category.sights' => 'Bezienswaardigheden',
			'poi.kind.supermarket' => 'Supermarkt',
			'poi.kind.convenience' => 'Buurtwinkel',
			'poi.kind.bakery' => 'Bakker',
			'poi.kind.butcher' => 'Slager',
			'poi.kind.greengrocer' => 'Groenteboer',
			'poi.kind.farmShop' => 'Boerderijwinkel',
			'poi.kind.marketplace' => 'Markt',
			'poi.kind.vendingPizza' => 'Pizza-automaat',
			'poi.kind.vendingBread' => 'Broodautomaat',
			'poi.kind.vendingFarmProducts' => 'Automaat met boerderijproducten',
			'poi.kind.vendingEggsMilk' => 'Eier- of melkautomaat',
			'poi.kind.vendingIce' => 'IJsblokjesautomaat',
			'poi.kind.vendingOther' => 'Voedselautomaat',
			'poi.kind.drinkingWater' => 'Drinkwater',
			'poi.kind.waterPoint' => 'Waterpunt',
			'poi.kind.dumpStation' => 'Lozingspunt',
			'poi.kind.toilets' => 'Toiletten',
			'poi.kind.shower' => 'Douches',
			'poi.kind.fuelStation' => 'Tankstation',
			'poi.kind.evCharging' => 'Laadpaal',
			'poi.kind.gasBottles' => 'Gasflessen',
			'poi.kind.pharmacy' => 'Apotheek',
			'poi.kind.doctor' => 'Arts',
			'poi.kind.hospital' => 'Ziekenhuis',
			'poi.kind.veterinary' => 'Dierenarts',
			'poi.kind.laundry' => 'Wasserette',
			'poi.kind.atm' => 'Geldautomaat',
			'poi.kind.postOffice' => 'Postkantoor',
			'poi.kind.touristOffice' => 'Toeristenbureau',
			'poi.kind.recyclingCentre' => 'Milieustraat',
			'poi.kind.carRepair' => 'Garage',
			'poi.kind.carWash' => 'Wasplaats',
			'poi.kind.motorhomeShop' => 'Camperdealer en -werkplaats',
			'poi.kind.outdoorShop' => 'Kampeer- en outdoorwinkel',
			'poi.kind.restaurant' => 'Restaurant',
			'poi.kind.cafe' => 'Café',
			'poi.kind.fastFood' => 'Snackbar',
			'poi.kind.viewpoint' => 'Uitzichtpunt',
			'poi.kind.attraction' => 'Bezienswaardigheid',
			'poi.kind.museum' => 'Museum',
			'poi.chipsLabel' => 'Winkels en diensten in de buurt',
			'poi.openNow' => 'Nu open',
			'poi.vendingSells.pizza' => 'Pizza',
			'poi.vendingSells.bread' => 'Brood',
			'poi.vendingSells.farmProducts' => 'Boerderijproducten',
			'poi.vendingSells.eggsMilk' => 'Eieren en melk',
			'poi.vendingSells.ice' => 'IJsblokjes',
			'poi.vendingAll' => 'Alle voedselautomaten',
			'poi.vendingMenu' => 'Wat de automaten verkopen',
			'poi.vendingChip.pizza' => 'Pizza-automaten',
			'poi.vendingChip.bread' => 'Broodautomaten',
			'poi.vendingChip.farmProducts' => 'Automaten met boerderijproducten',
			'poi.vendingChip.eggsMilk' => 'Eier- en melkautomaten',
			'poi.vendingChip.ice' => 'IJsblokjesautomaten',
			'poi.alwaysOpen' => 'Dag en nacht open',
			'poi.hoursUnknown' => 'Openingstijden onbekend',
			'poi.maybeClosed' => 'Gesloten volgens het officiële register van zorginstellingen (FINESS).',
			'poi.maybeClosedSince' => ({required Object date}) => 'Sinds ${date} door FINESS als gesloten vermeld: misschien is het definitief dicht.',
			'poi.seasonal' => 'Seizoensgebonden: in de winter mogelijk gesloten.',
			'poi.fee' => 'Betaald',
			'poi.free' => 'Gratis',
			'poi.stillThereTitle' => 'Is het er nog?',
			'poi.stillThereHint' => 'Onlangs gezien? Je antwoord helpt andere reizigers. Er wordt geen positie verstuurd.',
			'poi.stillThere' => 'Nog aanwezig',
			'poi.gone' => 'Verdwenen',
			'poi.lastConfirmed' => ({required Object when}) => 'Aanwezigheid bevestigd ${when}',
			'poi.checkedOn' => ({required Object date}) => 'Ter plaatse gecontroleerd op ${date}',
			'poi.thanksThere' => 'Bedankt, genoteerd: nog aanwezig.',
			'poi.thanksGone' => 'Bedankt, genoteerd: verdwenen.',
			'poi.fuelPrices' => 'Brandstofprijzen',
			'poi.perLitre' => ({required Object price}) => '${price}/l',
			'poi.priceUpdated' => ({required Object when}) => 'Prijs bijgewerkt ${when}',
			'poi.feedRead' => ({required Object when}) => 'Prijzen opgehaald ${when}',
			'poi.shortageTemporary' => 'Tijdelijk uitverkocht',
			'poi.shortageDefinitive' => 'Wordt niet meer verkocht',
			'poi.selfService24h' => '24/7 betalen aan de pomp',
			'poi.highway' => 'Aan de snelweg',
			'poi.lpgYes' => 'Verkoopt LPG',
			'poi.fuel.diesel' => 'Diesel',
			'poi.fuel.sp95' => 'Euro 95 (E5)',
			'poi.fuel.e10' => 'Euro 95 (E10)',
			'poi.fuel.sp98' => 'Super Plus 98',
			'poi.fuel.e85' => 'E85',
			'poi.fuel.lpg' => 'LPG',
			'poi.products' => 'Verkoopt',
			'poi.paymentTitle' => 'Betaling',
			'poi.product.pizza' => 'Pizza\'s',
			'poi.product.bread' => 'Brood',
			'poi.product.eggs' => 'Eieren',
			'poi.product.milk' => 'Melk',
			'poi.product.cheese' => 'Kaas',
			'poi.product.meat' => 'Vlees',
			'poi.product.vegetables' => 'Groenten',
			'poi.product.fruit' => 'Fruit',
			'poi.product.honey' => 'Honing',
			'poi.product.ice' => 'IJsblokjes',
			'poi.product.potatoes' => 'Aardappelen',
			'poi.product.food' => 'Levensmiddelen',
			'poi.payment.cash' => 'Contant',
			'poi.payment.coins' => 'Munten',
			'poi.payment.notes' => 'Biljetten',
			'poi.payment.cards' => 'Betaalkaart',
			'poi.payment.contactless' => 'Contactloos',
			'poi.payment.app' => 'Telefoonapp',
			'poi.justNow' => 'zojuist',
			'poi.minutesAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} minuut geleden', other: '${n} minuten geleden', ), 
			'poi.hoursAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} uur geleden', other: '${n} uur geleden', ), 
			'poi.readOffline' => ({required Object when}) => 'Opgehaald ${when}: geen verbinding om te vernieuwen',
			'poi.readStale' => ({required Object when}) => 'Opgehaald ${when}: vernieuwen is nu niet gelukt.',
			'poi.goneTitle' => 'Dit punt staat niet meer op de kaart',
			'poi.goneHint' => 'Reizigers hebben gemeld dat het verdwenen is, of de laatste update heeft het verwijderd.',
			'poi.loadError' => 'De details konden niet worden geladen. Wat de kaart weet, staat hierboven.',
			'poi.around' => 'Rond deze plek',
			'poi.aroundEmpty' => 'Geen winkel of dienst bekend in de buurt.',
			'poi.aroundError' => 'De winkels en diensten in de buurt konden niet worden geladen.',
			'poi.aroundOffline' => 'Geen verbinding: de winkels en diensten in de buurt verschijnen zodra je online bent.',
			'poi.onSite' => 'Ter plaatse',
			'poi.backTo' => ({required Object name}) => 'Terug naar ${name}',
			'poi.backToPlace' => 'Terug naar de plek',
			'poi.linkError' => 'Deze winkel of dienst kon niet worden geopend: geen verbinding, of hij staat niet meer op de kaart.',
			'poi.searchSection' => 'Winkels en diensten',
			'poi.searching' => 'Winkels en diensten worden gezocht',
			'poi.searchOffline' => 'Winkels en diensten worden online gezocht: nu geen verbinding.',
			'poi.add.title' => 'Een automaat hier?',
			'poi.add.hint' => 'Kies wat hij verkoopt: hij komt op de kaart voor alle reizigers.',
			'poi.add.pizza' => 'Pizza\'s',
			'poi.add.bread' => 'Brood',
			'poi.add.other' => 'Ander voedsel',
			'poi.add.gate' => 'Een automaat toevoegen',
			'poi.add.sent' => 'Bedankt: de automaat staat binnen een paar minuten op de kaart.',
			'poi.add.duplicateTitle' => 'Staat al op de kaart',
			'poi.add.duplicateBody' => 'Binnen 25 m staat al een automaat van dezelfde soort. Is die er nog?',
			'poi.add.duplicateThere' => 'Ja, die is er nog',
			'poi.add.duplicateGone' => 'Nee, die is weg',
			'poi.cheapest.title' => 'Goedkoopst bij mij in de buurt',
			'poi.cheapest.show' => 'Goedkoopst in de buurt',
			'poi.cheapest.zoomIn' => 'Zoom in om de prijzen van de tankstations te vergelijken.',
			'poi.cheapest.none' => 'Geen tankstation op de kaart verkoopt deze brandstof.',
			'poi.cheapest.noneHint' => 'Verschuif de kaart of kies een andere brandstof.',
			'poi.cheapest.error' => 'De prijzen van de tankstations konden niet worden geladen.',
			'poi.trend.title' => ({required Object fuel}) => '${fuel}: prijzen van de afgelopen dagen',
			'poi.trend.none' => 'Lunaway heeft hier nog geen prijs van deze brandstof gezien.',
			'poi.trend.failed' => 'De prijzen van de afgelopen dagen konden nu niet worden geladen.',
			'poi.trend.week' => 'Afgelopen 7 dagen:',
			'poi.trend.month' => 'Afgelopen 30 dagen:',
			'poi.trend.range' => ({required Object low, required Object high}) => 'van ${low} tot ${high}',
			'poi.trend.span' => ({required Object range, required Object move}) => '${range}, ${move}',
			'poi.trend.oneDay' => 'één dag gezien',
			'poi.trend.steady' => 'onveranderd',
			'poi.trend.down' => ({required Object amount}) => 'gedaald met ${amount}',
			'poi.trend.up' => ({required Object amount}) => 'gestegen met ${amount}',
			'poi.trend.since' => ({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} dag met prijzen sinds ${date}; dagen zonder gegevens blijven leeg', other: '${n} dagen met prijzen sinds ${date}; dagen zonder gegevens blijven leeg', ), 
			'poi.marketDays' => 'Marktdagen',
			'poi.vehicles.motorhomeYes' => 'Geschikt voor campers',
			'poi.vehicles.motorhomeNo' => 'Niet voor campers',
			'poi.vehicles.hgvYes' => 'Geschikt voor vrachtwagens',
			'poi.vehicles.hgvNo' => 'Niet voor vrachtwagens',
			'poi.vehicles.maxHeight' => ({required Object height}) => 'Maximale hoogte: ${height}',
			'offlineMaps.title' => 'Offline kaarten',
			'offlineMaps.intro' => 'Bewaar voor vertrek een regio op het apparaat: de plekken om te zoeken en te kiezen, de kaart om de straten zonder internet te zien.',
			'offlineMaps.webTitle' => 'Offline kaarten zitten in de app',
			'offlineMaps.web' => 'De apps voor Android en iOS bewaren regio\'s voor onderweg. In een browser heeft de kaart internet nodig.',
			'offlineMaps.desktopTitle' => 'Offline kaarten staan op de telefoon',
			'offlineMaps.desktop' => 'De apps voor Android en iOS bewaren regio\'s voor onderweg. Op een computer heeft de kaart internet nodig.',
			'offlineMaps.unreadable' => 'De offline kaarten van dit apparaat konden niet worden geladen.',
			'offlineMaps.none' => 'Nog geen regio op dit apparaat.',
			'offlineMaps.used' => ({required Object size}) => 'Gebruikte ruimte: ${size}',
			'offlineMaps.downloads' => 'Bezig met downloaden',
			'offlineMaps.installed' => 'Op dit apparaat',
			'offlineMaps.suggested' => 'Voorgesteld',
			'offlineMaps.here' => 'Waar je bent',
			'offlineMaps.favoritesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${n} favoriet hier', other: '${n} favorieten hier', ), 
			'offlineMaps.france' => 'Frankrijk',
			'offlineMaps.overseas' => 'Franse overzeese gebieden',
			'offlineMaps.countries' => 'Landen',
			'offlineMaps.downloadNamed' => ({required Object name, required Object size}) => '${name} downloaden, ${size}',
			'offlineMaps.pause' => 'Pauzeren',
			'offlineMaps.resume' => 'Hervatten',
			'offlineMaps.cancel' => 'Stoppen en download verwijderen',
			'offlineMaps.waiting' => 'Wacht op zijn beurt',
			'offlineMaps.progress' => ({required Object done, required Object total}) => '${done} van ${total}',
			'offlineMaps.paused' => ({required Object done, required Object total}) => 'Gepauzeerd bij ${done} van ${total}',
			'offlineMaps.verifying' => 'Bestand wordt gecontroleerd',
			'offlineMaps.failedNetwork' => 'Gestopt: geen verbinding. Het downloaden gaat verder waar het stopte zodra er weer verbinding is.',
			'offlineMaps.failedServer' => 'De server stuurde iets anders dan de kaart. Probeer het later opnieuw.',
			'offlineMaps.failedCorrupt' => 'Het bestand kwam beschadigd aan en is verwijderd. Probeer het opnieuw.',
			'offlineMaps.failedStorage' => 'Niet genoeg ruimte meer op het apparaat. Maak ruimte vrij en probeer het opnieuw.',
			'offlineMaps.keepOpen' => 'Houd de app open tijdens het downloaden: het stopt als de app naar de achtergrond gaat en gaat verder als je terugkomt.',
			'offlineMaps.dataOf' => ({required Object date}) => 'gegevens van ${date}',
			'offlineMaps.update' => ({required Object size}) => 'Bijwerken, ${size}',
			'offlineMaps.deleteNamed' => ({required Object name}) => '${name} verwijderen',
			'offlineMaps.deleteTitle' => ({required Object name}) => '${name} van dit apparaat verwijderen?',
			'offlineMaps.deleteBody' => 'Deze regio is dan niet meer zonder internet te zien. Je kunt hem opnieuw downloaden.',
			'offlineMaps.listOffline' => 'Voor de lijst met regio\'s is een verbinding nodig.',
			_ => null,
		} ?? switch (path) {
			'offlineMaps.listCopy' => 'Lijst van de laatste keer dat je online was.',
			'offlineMaps.entryHint' => 'Om zonder internet te reizen',
			'offlineMaps.entryCount' => ({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Kaarten: ${n} regio, ${size}', other: 'Kaarten: ${n} regio\'s, ${size}', ), 
			'offlineMaps.noticePack' => ({required Object name}) => 'Offline: gedownloade kaart, ${name}',
			'offlineMaps.noticeOutside' => 'Offline: dit gebied is niet gedownload',
			'offlineMaps.noticePlacesOnly' => 'Offline: plekken op het apparaat, kaart van dit gebied niet gedownload',
			'offlineMaps.noticeNone' => 'Offline: download een regio voor de volgende keer',
			'offlineMaps.noticeOnline' => 'Offline: de kaart heeft internet nodig',
			'offlineMaps.placesTitle' => 'Plekken',
			'offlineMaps.placesHint' => 'Een paar megabyte per regio: de lijst, het zoeken, de detailpagina\'s en de filters werken zonder internet.',
			'offlineMaps.mapsTitle' => 'Kaarten',
			'offlineMaps.mapsHint' => 'Alle straten, een paar honderd megabyte per regio: de kaart werkt zonder internet.',
			'offlineMaps.entryPlaces' => ({required Object names}) => 'Plekken: ${names}',
			'offlineMaps.entryPlacesCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Plekken: ${n} regio', other: 'Plekken: ${n} regio\'s', ), 
			'regions.pickerTitle' => 'Welke plekken wil je op dit apparaat bewaren?',
			'regions.pickerIntro' => 'Elke regio wordt één keer gedownload en daarna in kleine stukjes bijgewerkt. Je kunt later in Offline kaarten regio\'s toevoegen of verwijderen.',
			'regions.nearYou' => ({required Object name}) => 'Bij jou in de buurt: ${name}',
			'regions.findMine' => 'Mijn regio vinden',
			'regions.locating' => 'Je regio wordt gezocht',
			'regions.notCovered' => 'Nog geen Lunaway-regio bij jou in de buurt',
			'regions.wholeFrance' => 'Heel Frankrijk',
			'regions.showFrance' => 'De regio\'s van Frankrijk tonen',
			'regions.hideFrance' => 'De regio\'s van Frankrijk verbergen',
			'regions.packInfo' => ({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: '${count} plek, ${size}', other: '${count} plekken, ${size}', ), 
			'regions.noPack' => 'Geen pakket: plekken komen met de updates, grootte onbekend',
			'regions.download' => ({required Object size}) => 'Downloaden, ${size}',
			'regions.unavailable' => 'De server biedt nog geen regio\'s aan: Lunaway bewaart heel Frankrijk.',
			'regions.listFailed' => 'Voor de lijst met regio\'s is een verbinding nodig.',
			'regions.choose' => 'Regio\'s kiezen',
			'regions.noneKept' => 'Geen regio bewaard: de kaart heeft offline geen plekken.',
			'regions.change' => 'Regio\'s toevoegen of verwijderen',
			'regions.removeNamed' => ({required Object name}) => '${name} verwijderen',
			'regions.removed' => ({required Object name}) => '${name}: plekken van dit apparaat verwijderd',
			'regions.downloading' => ({required Object done, required Object total}) => 'Bezig met downloaden, ${done} van ${total}',
			'regions.updating' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('nl'))(n, one: 'Bezig met bijwerken, ${count} plek', other: 'Bezig met bijwerken, ${count} plekken', ), 
			'regions.waiting' => 'wacht op download',
			'regions.downloadingNamed' => ({required Object name}) => 'Plekken downloaden: ${name}',
			'regions.updated' => ({required Object when}) => 'bijgewerkt ${when}',
			'regions.offerTitle' => ({required Object name}) => '${name}: plekken offline bewaren?',
			'regions.downloadThis' => 'Deze regio downloaden',
			'regions.notHere' => ({required Object name}) => '${name} staat niet op dit apparaat',
			'regions.updatesOnMobile' => 'Bijwerken via mobiele data',
			'regions.updatesOnMobileHint' => 'Anders worden al gedownloade regio\'s via wifi bijgewerkt. Een nieuwe download gebruikt elk netwerk.',
			'roadReport.actionHint' => 'Een probleem op de weg melden',
			'roadReport.title' => 'Wat zie je op de weg?',
			'roadReport.intro' => 'Je melding waarschuwt andere reizigers. Als twee betrouwbare accounts hetzelfde melden, leiden de routes eromheen. Politiecontroles kun je niet melden.',
			'roadReport.kinds.closure' => 'Weg afgesloten',
			'roadReport.kinds.works' => 'Werkzaamheden',
			'roadReport.kinds.narrowPassage' => 'Versmalling',
			'roadReport.kinds.lowClearance' => 'Lage doorrijhoogte',
			'roadReport.kinds.other' => 'Probleem op de weg',
			'roadReport.height' => ({required Object value}) => 'Aangegeven hoogte: ${value}',
			'roadReport.send' => 'Melden',
			'roadReport.sent' => 'Bedankt: andere reizigers zijn gewaarschuwd.',
			'roadReport.stillThere' => 'Nog aanwezig',
			'roadReport.over' => 'Niet meer aanwezig',
			'roadReport.overSent' => 'Bedankt: genoteerd.',
			'roadReport.fromMap' => 'Hier een probleem melden',
			'roadReport.notHereTitle' => 'Melden kan hier niet',
			'roadReport.lower' => '10 cm lager',
			'roadReport.higher' => '10 cm hoger',
			'roadReport.passed' => ({required Object what}) => 'Je bent net langsgekomen: ${what}. Is het er nog?',
			'roadReport.notHere' => ({required Object countries}) => 'Lunaway neemt meldingen aan waar een officiële bron ze kan controleren: ${countries}.',
			'countries.ad' => 'Andorra',
			'countries.at' => 'Oostenrijk',
			'countries.ax' => 'Åland',
			'countries.be' => 'België',
			'countries.ch' => 'Zwitserland',
			'countries.cz' => 'Tsjechië',
			'countries.de' => 'Duitsland',
			'countries.dk' => 'Denemarken',
			'countries.eh' => 'Westelijke Sahara',
			'countries.es' => 'Spanje',
			'countries.fi' => 'Finland',
			'countries.fr' => 'Frankrijk',
			'countries.gb' => 'Verenigd Koninkrijk',
			'countries.gi' => 'Gibraltar',
			'countries.gr' => 'Griekenland',
			'countries.hr' => 'Kroatië',
			'countries.ie' => 'Ierland',
			'countries.it' => 'Italië',
			'countries.li' => 'Liechtenstein',
			'countries.lu' => 'Luxemburg',
			'countries.ma' => 'Marokko',
			'countries.mc' => 'Monaco',
			'countries.nl' => 'Nederland',
			'countries.no' => 'Noorwegen',
			'countries.pl' => 'Polen',
			'countries.pt' => 'Portugal',
			'countries.se' => 'Zweden',
			'countries.si' => 'Slovenië',
			'countries.sj' => 'Spitsbergen',
			'countries.sm' => 'San Marino',
			'countries.va' => 'Vaticaanstad',
			'areas.ara' => 'Auvergne-Rhône-Alpes',
			'areas.bfc' => 'Bourgogne-Franche-Comté',
			'areas.bre' => 'Bretagne',
			'areas.cvl' => 'Centre-Val de Loire',
			'areas.cor' => 'Corsica',
			'areas.ges' => 'Grand Est',
			'areas.hdf' => 'Hauts-de-France',
			'areas.idf' => 'Île-de-France',
			'areas.nor' => 'Normandië',
			'areas.naq' => 'Nouvelle-Aquitaine',
			'areas.occ' => 'Occitanië',
			'areas.pdl' => 'Pays de la Loire',
			'areas.pac' => 'Provence-Alpes-Côte d\'Azur',
			'areas.gp' => 'Guadeloupe',
			'areas.mq' => 'Martinique',
			'areas.gf' => 'Frans-Guyana',
			'areas.re' => 'Réunion',
			'areas.yt' => 'Mayotte',
			'areas.franceRest' => 'Frankrijk, overig',
			_ => null,
		};
	}
}

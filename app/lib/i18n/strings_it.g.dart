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
class TranslationsIt extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsIt({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.it,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <it>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsIt _root = this; // ignore: unused_field

	@override 
	TranslationsIt $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsIt(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => 'Lunaway';
	@override late final _Translations$nav$it nav = _Translations$nav$it._(_root);
	@override late final _Translations$common$it common = _Translations$common$it._(_root);
	@override late final _Translations$notices$it notices = _Translations$notices$it._(_root);
	@override late final _Translations$kinds$it kinds = _Translations$kinds$it._(_root);
	@override late final _Translations$families$it families = _Translations$families$it._(_root);
	@override late final _Translations$services$it services = _Translations$services$it._(_root);
	@override late final _Translations$activities$it activities = _Translations$activities$it._(_root);
	@override late final _Translations$amenities$it amenities = _Translations$amenities$it._(_root);
	@override late final _Translations$overnight$it overnight = _Translations$overnight$it._(_root);
	@override late final _Translations$freshness$it freshness = _Translations$freshness$it._(_root);
	@override late final _Translations$map$it map = _Translations$map$it._(_root);
	@override late final _Translations$sync$it sync = _Translations$sync$it._(_root);
	@override late final _Translations$location$it location = _Translations$location$it._(_root);
	@override late final _Translations$search$it search = _Translations$search$it._(_root);
	@override late final _Translations$filters$it filters = _Translations$filters$it._(_root);
	@override late final _Translations$place$it place = _Translations$place$it._(_root);
	@override late final _Translations$sources$it sources = _Translations$sources$it._(_root);
	@override late final _Translations$hours$it hours = _Translations$hours$it._(_root);
	@override late final _Translations$directions$it directions = _Translations$directions$it._(_root);
	@override late final _Translations$navigation$it navigation = _Translations$navigation$it._(_root);
	@override late final _Translations$list$it list = _Translations$list$it._(_root);
	@override late final _Translations$favorites$it favorites = _Translations$favorites$it._(_root);
	@override late final _Translations$vehicle$it vehicle = _Translations$vehicle$it._(_root);
	@override late final _Translations$vehicleHeight$it vehicleHeight = _Translations$vehicleHeight$it._(_root);
	@override late final _Translations$profile$it profile = _Translations$profile$it._(_root);
	@override late final _Translations$units$it units = _Translations$units$it._(_root);
	@override late final _Translations$languages$it languages = _Translations$languages$it._(_root);
	@override late final _Translations$translation$it translation = _Translations$translation$it._(_root);
	@override late final _Translations$locale$it locale = _Translations$locale$it._(_root);
	@override late final _Translations$account$it account = _Translations$account$it._(_root);
	@override late final _Translations$recovery$it recovery = _Translations$recovery$it._(_root);
	@override late final _Translations$recover$it recover = _Translations$recover$it._(_root);
	@override late final _Translations$deletion$it deletion = _Translations$deletion$it._(_root);
	@override late final _Translations$devices$it devices = _Translations$devices$it._(_root);
	@override late final _Translations$muted$it muted = _Translations$muted$it._(_root);
	@override late final _Translations$mine$it mine = _Translations$mine$it._(_root);
	@override late final _Translations$outbox$it outbox = _Translations$outbox$it._(_root);
	@override late final _Translations$placement$it placement = _Translations$placement$it._(_root);
	@override late final _Translations$contribute$it contribute = _Translations$contribute$it._(_root);
	@override late final _Translations$confirmSheet$it confirmSheet = _Translations$confirmSheet$it._(_root);
	@override late final _Translations$issueSheet$it issueSheet = _Translations$issueSheet$it._(_root);
	@override late final _Translations$reportSheet$it reportSheet = _Translations$reportSheet$it._(_root);
	@override late final _Translations$reviewSheet$it reviewSheet = _Translations$reviewSheet$it._(_root);
	@override late final _Translations$gate$it gate = _Translations$gate$it._(_root);
	@override late final _Translations$photoFlow$it photoFlow = _Translations$photoFlow$it._(_root);
	@override late final _Translations$placeForm$it placeForm = _Translations$placeForm$it._(_root);
	@override late final _Translations$favoritesSync$it favoritesSync = _Translations$favoritesSync$it._(_root);
	@override late final _Translations$poi$it poi = _Translations$poi$it._(_root);
	@override late final _Translations$offlineMaps$it offlineMaps = _Translations$offlineMaps$it._(_root);
	@override late final _Translations$regions$it regions = _Translations$regions$it._(_root);
	@override late final _Translations$roadReport$it roadReport = _Translations$roadReport$it._(_root);
	@override late final _Translations$countries$it countries = _Translations$countries$it._(_root);
	@override late final _Translations$areas$it areas = _Translations$areas$it._(_root);
}

// Path: nav
class _Translations$nav$it extends Translations$nav$en {
	_Translations$nav$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get map => 'Mappa';
	@override String get favorites => 'Preferiti';
	@override String get profile => 'Profilo';
	@override String get fold => 'Riduci il menu';
	@override String get unfold => 'Espandi il menu';
}

// Path: common
class _Translations$common$it extends Translations$common$en {
	_Translations$common$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get close => 'Chiudi';
	@override String get done => 'Fatto';
	@override String get cancel => 'Annulla';
	@override String get retry => 'Riprova';
	@override String get save => 'Salva';
	@override String get delete => 'Elimina';
	@override String get undo => 'Annulla';
	@override String get ok => 'Ho capito';
	@override String get saveFailed => 'Non è stato possibile salvare la modifica.';
	@override String get send => 'Invia';
	@override String get later => 'Più tardi';
	@override String get next => 'Continua';
	@override String get failed => 'L\'operazione non è riuscita. Riprova tra un momento.';
	@override String get offline => 'Nessuna connessione al momento. Riprova quando torna la rete.';
}

// Path: notices
class _Translations$notices$it extends Translations$notices$en {
	_Translations$notices$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get close => 'Chiudi l\'avviso';
	@override String get fold => 'Comprimi l\'avviso';
	@override String get unfold => 'Mostra l\'avviso';
}

// Path: kinds
class _Translations$kinds$it extends Translations$kinds$en {
	_Translations$kinds$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get motorhomeArea => 'Area sosta camper';
	@override String get serviceArea => 'Area camper service';
	@override String get campsite => 'Campeggio';
	@override String get parking => 'Parcheggio';
	@override String get nature => 'Sosta in natura';
	@override String get restArea => 'Area di sosta stradale';
	@override String get picnicArea => 'Area picnic';
	@override String get farm => 'Sosta in fattoria';
	@override String get homestay => 'Ospitalità da privati';
	@override String get offRoad => 'Sosta fuoristrada';
	@override String get extraService => 'Servizi utili';
}

// Path: families
class _Translations$families$it extends Translations$families$en {
	_Translations$families$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get stopovers => 'Aree e parcheggi';
	@override String get stopoversHint => 'Aree sosta camper, parcheggi, aree di sosta stradali';
	@override String get campsites => 'Campeggi e ospitalità';
	@override String get campsitesHint => 'Campeggi, fattorie, privati';
	@override String get nature => 'Natura';
	@override String get natureHint => 'Sosta in natura, sterrati';
	@override String get services => 'Servizi';
	@override String get servicesHint => 'Acqua e scarico, senza pernottamento';
}

// Path: services
class _Translations$services$it extends Translations$services$en {
	_Translations$services$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get drinkingWater => 'Acqua potabile';
	@override String get greyWater => 'Scarico acque grigie';
	@override String get blackWater => 'Scarico cassetta WC';
	@override String get wasteBin => 'Raccolta rifiuti';
	@override String get toilets => 'Bagni';
	@override String get showers => 'Docce';
	@override String get electricity => 'Corrente elettrica';
	@override String get wifi => 'Wi-Fi';
	@override String get laundry => 'Lavanderia';
	@override String get lpg => 'GPL';
	@override String get gasBottles => 'Bombole del gas';
	@override String get vehicleWash => 'Lavaggio del veicolo';
	@override String get bakery => 'Panetteria';
	@override String get swimmingPool => 'Piscina';
	@override String get petsAllowed => 'Animali ammessi';
	@override String get mobileData => 'Rete mobile';
	@override String get winterCaravanning => 'Aperto in inverno';
}

// Path: activities
class _Translations$activities$it extends Translations$activities$en {
	_Translations$activities$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get monuments => 'Visite turistiche';
	@override String get windsurfKitesurf => 'Windsurf, kitesurf';
	@override String get mountainBiking => 'Mountain bike';
	@override String get hiking => 'Escursionismo';
	@override String get climbing => 'Arrampicata';
	@override String get canoeKayak => 'Canoa, kayak';
	@override String get fishing => 'Pesca';
	@override String get shoreFishing => 'Raccolta di molluschi';
	@override String get swimming => 'Balneazione';
	@override String get motorcycling => 'Giri in moto';
	@override String get viewpoint => 'Punto panoramico';
	@override String get playground => 'Parco giochi';
}

// Path: amenities
class _Translations$amenities$it extends Translations$amenities$en {
	_Translations$amenities$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get water => 'Acqua';
	@override String get dumpStation => 'Scarico';
	@override String get electricity => 'Corrente elettrica';
	@override String get toilets => 'Bagni';
	@override String get showers => 'Docce';
	@override String get wasteBin => 'Rifiuti';
	@override String get laundry => 'Lavanderia';
	@override String get wifi => 'Wi-Fi';
	@override String get lpg => 'GPL';
}

// Path: overnight
class _Translations$overnight$it extends Translations$overnight$en {
	_Translations$overnight$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Pernottamento consentito';
	@override String get tolerated => 'Pernottamento tollerato';
	@override String get dayOnly => 'Solo di giorno';
	@override String get forbidden => 'Pernottamento vietato';
	@override String get unknown => 'Pernottamento non indicato';
	@override String get allowedHint => 'Qui puoi passare la notte.';
	@override String get toleratedHint => 'Di solito una notte è accettata. Discrezione d\'obbligo, non lasciare tracce.';
	@override String get dayOnlyHint => 'Sosta solo di giorno. Cerca un altro luogo per la notte.';
	@override String get forbiddenHint => 'Qui è vietato passare la notte.';
	@override String get unknownHint => 'Nessuno l\'ha ancora indicato. Informati sul posto.';
}

// Path: freshness
class _Translations$freshness$it extends Translations$freshness$en {
	_Translations$freshness$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String confirmed({required Object when}) => 'Confermato da un viaggiatore ${when}';
	@override String get unconfirmed => 'Non ancora confermato da un viaggiatore';
	@override String get stale => 'Ultima conferma più di un anno fa';
	@override String get today => 'oggi';
	@override String daysAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'ieri',
		other: '${n} giorni fa',
	);
	@override String monthsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'un mese fa',
		other: '${n} mesi fa',
	);
	@override String yearsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'un anno fa',
		other: '${n} anni fa',
	);
}

// Path: map
class _Translations$map$it extends Translations$map$en {
	_Translations$map$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get searchHint => 'Un luogo, un comune';
	@override String get clearSearch => 'Cancella la ricerca';
	@override String get locateMe => 'Mostra la mia posizione';
	@override String get aroundMe => 'Mostra i luoghi vicino a me';
	@override String get zoomIn => 'Aumenta lo zoom';
	@override String get zoomOut => 'Riduci lo zoom';
	@override String get filters => 'Filtri';
	@override String get credit => '© OpenStreetMap · Protomaps';
	@override String get creditLabel => 'Crediti della mappa: © contributori di OpenStreetMap, stile Protomaps. Apre la pagina dei diritti d\'autore di OpenStreetMap.';
	@override String get showList => 'Elenco';
	@override String showListCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Elenco (${n})',
		other: 'Elenco (${n})',
	);
	@override String placesHereLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'luogo qui',
		other: 'luoghi qui',
	);
	@override String nearestYouLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'luogo più vicino a te',
		other: 'luoghi più vicini a te',
	);
	@override String nearestCentreLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'luogo più vicino al centro',
		other: 'luoghi più vicini al centro',
	);
	@override String get pointTitle => 'Qui';
	@override String get pointHint => 'Punto sulla mappa';
	@override String get directionsHere => 'Percorso fino a qui';
	@override String get startHere => 'Parti da qui';
	@override String get departureChosen => 'Punto di partenza impostato: ora apri la scheda della destinazione e tocca Percorso.';
	@override String get copyCoordinates => 'Copia le coordinate';
	@override String get freeTapHint => 'Tocca un punto della mappa per andarci o per aggiungere un luogo';
	@override String get freeTapHintClick => 'Fai clic su un punto della mappa per andarci o per aggiungere un luogo';
	@override String get addPlaceAtCenter => 'Aggiungi un luogo al centro della mappa';
	@override String addressSource({required Object attribution}) => 'Fonte: ${attribution}';
	@override String get placesAround => 'Luoghi nei dintorni';
	@override String get downloading => 'Download dei luoghi della Francia';
	@override String downloadingCount({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${count} luogo ricevuto',
		other: '${count} luoghi ricevuti',
	);
	@override String get noData => 'Ancora nessun luogo su questo dispositivo';
	@override String get noDataHint => 'Scarica i luoghi una volta sola: poi la mappa funziona senza rete.';
	@override String get download => 'Scarica i luoghi';
	@override String get downloadFailed => 'Il download si è interrotto';
	@override String get demoBanner => 'Demo: luoghi fittizi';
	@override String get unsupported => 'La mappa non è disponibile su questo sistema. Usa l\'app web.';
}

// Path: sync
class _Translations$sync$it extends Translations$sync$en {
	_Translations$sync$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get failedOffline => 'Nessuna connessione per ora.';
	@override String get failedBusy => 'Il server è molto carico.';
	@override String get failedServer => 'Il server ha un problema al momento.';
	@override String get failedOther => 'L\'aggiornamento non è riuscito.';
	@override String get failedRefused => 'Il server ha rifiutato l\'aggiornamento. Forse serve una versione più recente dell\'app.';
	@override String get willRetry => 'Lunaway riproverà automaticamente.';
	@override String incomplete({required Object count}) => 'Download incompleto: finora ${count} luoghi';
	@override String get incompleteShort => 'Download incompleto';
	@override String resuming({required Object count}) => 'Download in corso: ${count} luoghi';
	@override String get resume => 'Riprendi';
}

// Path: location
class _Translations$location$it extends Translations$location$en {
	_Translations$location$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get rationaleTitle => 'Mostrare la tua posizione?';
	@override String get rationale => 'Lunaway la usa per centrare la mappa su di te, ordinare i luoghi per distanza e guidarti. Per un percorso, la tua posizione viene inviata al server di Lunaway, che non la conserva. Per il carburante più economico nei dintorni viene inviata solo una posizione arrotondata a circa 5 km. Una segnalazione stradale viene inviata insieme al punto in cui la fai.';
	@override String get allow => 'Continua';
	@override String get notNow => 'Non ora';
	@override String get deniedTitle => 'Posizione disattivata per Lunaway';
	@override String get denied => 'Hai rifiutato l\'accesso alla posizione. Per usarla, consentila nelle impostazioni del dispositivo.';
	@override String get openSettings => 'Apri le impostazioni';
	@override String get serviceOffTitle => 'Localizzazione disattivata';
	@override String get serviceOff => 'La localizzazione del dispositivo è disattivata. Attivala nelle impostazioni rapide, poi riprova.';
	@override String get notAllowed => 'Posizione non consentita. La mappa funziona anche senza.';
	@override String get noFix => 'Posizione non ancora trovata. Riprova all\'aperto o tra un momento.';
	@override String get unsupported => 'Questo dispositivo non fornisce la sua posizione.';
	@override String get browserDeniedTitle => 'Posizione bloccata dal browser';
	@override String get browserDenied => 'Il browser blocca l\'accesso di Lunaway alla tua posizione. Per consentirlo, fai clic sull\'icona a sinistra dell\'indirizzo del sito (un lucchetto o dei cursori), imposta Posizione su Consenti, poi fai di nuovo clic sul pulsante della posizione.';
	@override String get browserNoFix => 'Il browser non ha fornito alcuna posizione. Riprova tra un momento; su un computer, il Wi-Fi aiuta a trovarla.';
}

// Path: search
class _Translations$search$it extends Translations$search$en {
	_Translations$search$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get towns => 'Comuni';
	@override String get places => 'Luoghi';
	@override String noResult({required Object query}) => 'Nessun luogo né comune corrisponde a «${query}».';
	@override String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} luogo',
		other: '${n} luoghi',
	);
	@override String get addresses => 'Indirizzi';
	@override String get addressesSearching => 'Ricerca degli indirizzi';
	@override String get addressesFailed => 'Al momento non è stato possibile cercare gli indirizzi.';
	@override String addressSources({required Object sources}) => 'Indirizzi: ${sources}';
	@override String get offline => 'Nessuna connessione: la ricerca ha bisogno della rete.';
	@override late final _Translations$search$addressKind$it addressKind = _Translations$search$addressKind$it._(_root);
}

// Path: filters
class _Translations$filters$it extends Translations$filters$en {
	_Translations$filters$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filtri';
	@override String get families => 'Tipo di luogo';
	@override String get familiesHint => 'Nessuna scelta: tutti i tipi';
	@override String get familiesChosenHint => 'Solo questi tipi';
	@override String get night => 'Pernottamento';
	@override String get nightHint => 'Nessuna scelta: tutti i luoghi';
	@override String get nightChosenHint => 'Solo i luoghi con queste condizioni di pernottamento';
	@override String get nightPossible => 'Pernottamento possibile';
	@override String get amenities => 'Servizi';
	@override String get amenitiesHint => 'Il luogo deve averli tutti';
	@override String get rating => 'Valutazione minima';
	@override String get ratingHint => 'Valutazione dei viaggiatori di Lunaway, oppure quella delle altre fonti se nessuno l\'ha valutato. Un luogo senza valutazione viene nascosto.';
	@override String ratingAtLeast({required Object rating}) => '${rating} o più';
	@override String get opening => 'Apertura';
	@override String get openingHint => 'I luoghi di cui non si conosce l\'apertura restano visibili.';
	@override String get openingAllYear => 'Tutto l\'anno';
	@override String get openingDates => 'Le mie date';
	@override String get openingClearDates => 'Cancella le date';
	@override String openingStay({required Object from, required Object to}) => 'Dal ${from} al ${to}';
	@override String openingStayDay({required Object date}) => 'Il ${date}';
	@override String get openingStayTitle => 'Date del tuo soggiorno';
	@override String get openingArrival => 'Arrivo';
	@override String get openingDeparture => 'Partenza';
	@override String get price => 'Prezzo a notte';
	@override String get freeOnly => 'Gratuito';
	@override String get freeHint => 'Solo i luoghi in cui la notte è gratuita secondo le loro fonti';
	@override String get scrollNext => 'Mostra i filtri successivi';
	@override String get scrollPrevious => 'Mostra i filtri precedenti';
	@override String get vehicle => 'Il mio veicolo';
	@override String get myVehicleFits => 'Il mio veicolo passa';
	@override String myVehicleFitsHeight({required Object height}) => 'Adatto a ${height}';
	@override String myVehicleHint({required Object height}) => 'Nasconde i luoghi con un limite inferiore a ${height}. I luoghi senza altezza nota restano sulla mappa.';
	@override String get reset => 'Cancella tutto';
	@override String get apply => 'Applica';
	@override String show({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		zero: 'Nessun luogo corrisponde',
		one: 'Mostra ${count} luogo',
		other: 'Mostra ${count} luoghi',
	);
	@override String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} filtro attivo',
		other: '${n} filtri attivi',
	);
}

// Path: place
class _Translations$place$it extends Translations$place$en {
	_Translations$place$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String unnamedTitle({required Object kind, required Object where}) => '${kind} · ${where}';
	@override String away({required Object distance}) => 'a ${distance}';
	@override String get directions => 'Percorso';
	@override String get share => 'Condividi';
	@override String get save => 'Salva';
	@override String get saved => 'Salvato';
	@override String get saveHint => 'Aggiungi ai preferiti. Tieni premuto per scegliere le liste.';
	@override String get saveTo => 'Salva in una lista';
	@override String get chooseLists => 'Liste';
	@override String get savedToast => 'Aggiunto ai miei preferiti';
	@override String get removedToast => 'Rimosso dai miei preferiti';
	@override String get pricePerNight => 'Prezzo a notte';
	@override String get priceFree => 'Gratuito';
	@override String get priceUnknown => 'Non indicato';
	@override String get priceServices => 'Servizi';
	@override String get priceIncluded => 'Inclusi';
	@override String priceIncludes({required Object items}) => 'Il prezzo a notte comprende: ${items}';
	@override late final _Translations$place$inclusions$it inclusions = _Translations$place$inclusions$it._(_root);
	@override String get maxHeight => 'Altezza max.';
	@override String get capacity => 'Posti';
	@override String get classification => 'Classificazione';
	@override String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} stella',
		other: '${n} stelle',
	);
	@override String get hours => 'Orari';
	@override String get services => 'Servizi';
	@override String get noServices => 'Nessun servizio indicato.';
	@override String get activities => 'Nei dintorni';
	@override String get description => 'Descrizione';
	@override String get contact => 'Contatti';
	@override String get website => 'Sito web';
	@override String get call => 'Chiama';
	@override String get coordinates => 'Coordinate';
	@override String get address => 'Indirizzo';
	@override String get copyAddress => 'Copia l\'indirizzo';
	@override String addressSource({required Object source}) => 'Fonte: ${source}';
	@override String get copy => 'Copia le coordinate';
	@override String get copyShort => 'Copia';
	@override String copyAs({required Object format}) => 'Copia in formato ${format}';
	@override String copiesAs({required Object format}) => 'Il pulsante «Copia» usa: ${format}';
	@override String copied({required Object text}) => 'Copiato: ${text}';
	@override String get otherFormats => 'Scegli il formato da copiare';
	@override String get formatDecimal => 'Gradi decimali';
	@override String get formatDms => 'Gradi, minuti, secondi';
	@override String get formatGeo => 'Link geo:';
	@override String get formatGoogle => 'Link Google Maps';
	@override String get formatOsm => 'Link OpenStreetMap';
	@override String get sources => 'Fonti';
	@override String fetched({required Object when}) => 'Rilevato ${when}';
	@override String get viewSource => 'Apri la fonte';
	@override String get gone => 'Questo luogo non è più sulla mappa';
	@override String get goneHint => 'È stato rimosso o unito a un altro con l\'ultimo aggiornamento.';
	@override String get arriving => 'Questo luogo è ancora in download';
	@override String get arrivingHint => 'I luoghi della Francia si stanno scaricando perché la mappa funzioni senza rete. La scheda si apre appena arriva questo luogo.';
	@override String get loadError => 'Non è stato possibile caricare questo luogo.';
	@override String get openFailed => 'Nessuna app è riuscita ad aprire questo link.';
	@override String get photos => 'Foto';
	@override String get extrasOffline => 'Foto e recensioni richiedono una connessione.';
	@override String get reviewsTitle => 'Recensioni';
	@override String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} recensione',
		other: '${n} recensioni',
	);
	@override String get noReviews => 'Ancora nessuna recensione.';
	@override String get noOtherReviews => 'Ancora nessun\'altra recensione.';
	@override String get moreReviews => 'Altre recensioni';
	@override String get moreReviewsFailed => 'Non è stato possibile caricare altre recensioni. Tocca per riprovare.';
	@override String stars({required Object rating}) => '${rating} su 5';
	@override String externalRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'valutazione esterna',
		other: 'valutazioni esterne',
	);
	@override String lunawayRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'valutazione Lunaway',
		other: 'valutazioni Lunaway',
	);
	@override String get deletedAccount => 'Account eliminato';
	@override late final _Translations$place$reviewVehicle$it reviewVehicle = _Translations$place$reviewVehicle$it._(_root);
	@override String originalLanguage({required Object language}) => 'Testo originale in ${language}';
	@override String descriptionIn({required Object language}) => 'Descrizione in ${language}';
	@override String photoPosition({required Object index, required Object count}) => 'Foto ${index} di ${count}';
	@override String get previousPhoto => 'Foto precedente';
	@override String get nextPhoto => 'Foto successiva';
	@override String get links => 'Su altri siti';
	@override String sourceWithLicence({required Object source, required Object licence}) => '${source} · ${licence}';
	@override String get licenceCcBy => 'CC BY 4.0';
	@override String photoCredit({required Object source, required Object author}) => '${source} · ${author}';
	@override String get photoStreetView => 'Vista dalla strada';
	@override String get photoSurroundings => 'Nei dintorni';
	@override String excerptFrom({required Object source, required Object text}) => 'Secondo ${source}: ${text}';
	@override String get readMore => 'Leggi tutto';
	@override String updatedOn({required Object date}) => 'aggiornato il ${date}';
	@override String get otherSources => 'Secondo altre fonti';
}

// Path: sources
class _Translations$sources$it extends Translations$sources$en {
	_Translations$sources$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override late final _Translations$sources$extcom$it extcom = _Translations$sources$extcom$it._(_root);
}

// Path: hours
class _Translations$hours$it extends Translations$hours$en {
	_Translations$hours$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get open => 'Aperto ora';
	@override String openUntil({required Object time}) => 'Aperto, chiude alle ${time}';
	@override String openUntilDay({required Object day, required Object time}) => 'Aperto, chiude ${day} alle ${time}';
	@override String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Aperto, chiude tra ${n} minuto',
		other: 'Aperto, chiude tra ${n} minuti',
	);
	@override String closedUntil({required Object time}) => 'Chiuso, apre alle ${time}';
	@override String closedUntilDay({required Object day, required Object time}) => 'Chiuso, apre ${day} alle ${time}';
	@override String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Chiuso, apre tra ${n} minuto',
		other: 'Chiuso, apre tra ${n} minuti',
	);
	@override String get closedWindow => 'Chiuso per le prossime due settimane';
	@override String get tomorrow => 'domani';
	@override String onDate({required Object date}) => 'il ${date}';
	@override String onWeekday({required Object day}) => '${day}';
	@override String get midnight => '24:00';
	@override String get stale => 'Aperto o chiuso? Aggiorna i luoghi nel Profilo.';
	@override String get localTime => 'Orari espressi nell\'ora locale';
	@override late final _Translations$hours$codes$it codes = _Translations$hours$codes$it._(_root);
	@override late final _Translations$hours$months$it months = _Translations$hours$months$it._(_root);
	@override String dayOfMonth({required Object day, required Object month}) => '${day} ${month}';
	@override String dayOfYear({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}';
	@override String get allWeek => '24 ore su 24, 7 giorni su 7';
	@override String get allYear => 'tutto l\'anno';
	@override String get seasonAllYear => 'Aperto tutto l\'anno';
	@override String seasonOpenUntil({required Object date}) => 'Aperto fino al ${date}';
	@override String seasonClosedUntil({required Object date}) => 'Chiuso, apre il ${date}';
}

// Path: directions
class _Translations$directions$it extends Translations$directions$en {
	_Translations$directions$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Apri con';
	@override String get hint => 'Queste app non conoscono le dimensioni del tuo veicolo.';
	@override String get remember => 'Usa sempre questa app';
	@override String get rememberHint => 'Puoi cambiarla nel Profilo';
	@override String get settingTitle => 'Apri con un\'altra app';
	@override String get settingHint => 'L\'app che si apre toccando «Apri con» in un percorso';
	@override String get askEachTime => 'Chiedi ogni volta';
	@override String get appleMaps => 'Mappe';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osmAnd => 'OsmAnd';
	@override String get organicMaps => 'Organic Maps';
	@override String get magicEarth => 'Magic Earth';
	@override String get openStreetMap => 'OpenStreetMap (browser)';
	@override String get none => 'Nessuna app di navigazione trovata su questo dispositivo.';
}

// Path: navigation
class _Translations$navigation$it extends Translations$navigation$en {
	_Translations$navigation$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$preview$it preview = _Translations$navigation$preview$it._(_root);
	@override late final _Translations$navigation$stops$it stops = _Translations$navigation$stops$it._(_root);
	@override late final _Translations$navigation$legs$it legs = _Translations$navigation$legs$it._(_root);
	@override late final _Translations$navigation$fuel$it fuel = _Translations$navigation$fuel$it._(_root);
	@override late final _Translations$navigation$onTheWay$it onTheWay = _Translations$navigation$onTheWay$it._(_root);
	@override late final _Translations$navigation$states$it states = _Translations$navigation$states$it._(_root);
	@override late final _Translations$navigation$noRoute$it noRoute = _Translations$navigation$noRoute$it._(_root);
	@override late final _Translations$navigation$ferry$it ferry = _Translations$navigation$ferry$it._(_root);
	@override late final _Translations$navigation$warning$it warning = _Translations$navigation$warning$it._(_root);
	@override late final _Translations$navigation$roadEvents$it roadEvents = _Translations$navigation$roadEvents$it._(_root);
	@override late final _Translations$navigation$marks$it marks = _Translations$navigation$marks$it._(_root);
	@override late final _Translations$navigation$guidance$it guidance = _Translations$navigation$guidance$it._(_root);
	@override late final _Translations$navigation$voice$it voice = _Translations$navigation$voice$it._(_root);
	@override late final _Translations$navigation$units$it units = _Translations$navigation$units$it._(_root);
	@override late final _Translations$navigation$settings$it settings = _Translations$navigation$settings$it._(_root);
	@override late final _Translations$navigation$enforcement$it enforcement = _Translations$navigation$enforcement$it._(_root);
}

// Path: list
class _Translations$list$it extends Translations$list$en {
	_Translations$list$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Luoghi nelle vicinanze';
	@override String get empty => 'Nessun luogo qui intorno con questi filtri';
	@override String get emptyHint => 'Sposta la mappa, riduci lo zoom o allenta i filtri.';
	@override String get downloading => 'I luoghi stanno arrivando';
	@override String get downloadingHint => 'L\'elenco si riempie durante il download.';
	@override String get error => 'Non è stato possibile caricare l\'elenco.';
	@override String get offline => 'Nessuna connessione: l\'elenco ha bisogno della rete.';
	@override String get moreFailed => 'Non è stato possibile caricare altri luoghi. Tocca per riprovare.';
	@override String get sortDistance => 'Distanza';
	@override String get sortRating => 'Valutazione';
	@override String get sortNewest => 'Aggiunti di recente';
	@override String sortedBy({required Object sort}) => 'Elenco ordinato per: ${sort}';
	@override String rankedAmongNearestYou({required Object n}) => 'Ordine calcolato sui ${n} luoghi più vicini a te';
	@override String rankedAmongNearestCentre({required Object n}) => 'Ordine calcolato sui ${n} luoghi più vicini al centro della mappa';
	@override String get offlineTitle => 'Nessuna connessione';
	@override String get offlineNotHere => 'Niente di quest\'area su questo dispositivo.';
}

// Path: favorites
class _Translations$favorites$it extends Translations$favorites$en {
	_Translations$favorites$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Preferiti';
	@override String get defaultList => 'I miei preferiti';
	@override String get empty => 'Ancora niente di salvato qui';
	@override String get emptyHint => 'Tocca Salva nella scheda di un luogo per ritrovarlo, anche offline.';
	@override String get newList => 'Nuova lista';
	@override String get listName => 'Nome della lista';
	@override String get renameList => 'Rinomina la lista';
	@override String get deleteList => 'Elimina la lista';
	@override String deleteListConfirm({required Object name}) => 'Eliminare «${name}»? I luoghi restano sulla mappa.';
	@override String get listActions => 'Opzioni della lista';
	@override String get placeActions => 'Opzioni del luogo';
	@override String get openOnMap => 'Vedi sulla mappa';
	@override String get remove => 'Rimuovi dalla lista';
	@override String get removed => 'Rimosso dalla lista';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		zero: 'Vuota',
		one: '${n} luogo',
		other: '${n} luoghi',
	);
	@override String get error => 'Non è stato possibile caricare i tuoi preferiti.';
}

// Path: vehicle
class _Translations$vehicle$it extends Translations$vehicle$en {
	_Translations$vehicle$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Il mio veicolo';
	@override String get why => 'Le dimensioni del tuo veicolo servono a nascondere i luoghi in cui non passa. Vengono inviate con ogni richiesta di percorso, senza essere conservate.';
	@override String get none => 'Descrivi il tuo veicolo per nascondere i luoghi in cui non passa.';
	@override String get add => 'Descrivi il mio veicolo';
	@override String get edit => 'Modifica';
	@override String get type => 'Tipo';
	@override late final _Translations$vehicle$types$it types = _Translations$vehicle$types$it._(_root);
	@override String get towingTitle => 'Traino';
	@override late final _Translations$vehicle$towing$it towing = _Translations$vehicle$towing$it._(_root);
	@override String get size => 'Dimensioni';
	@override String get sizeHint => 'Valori tipici del tipo scelto: correggili con quelli del tuo libretto di circolazione.';
	@override String get height => 'Altezza';
	@override String get width => 'Larghezza';
	@override String get length => 'Lunghezza totale, traino compreso';
	@override String get weight => 'Massa complessiva a pieno carico';
	@override String heightShort({required Object value}) => 'alt. ${value}';
	@override String widthShort({required Object value}) => 'largh. ${value}';
	@override String lengthShort({required Object value}) => 'lungh. ${value}';
	@override String get notANumber => 'Un numero, per esempio 2,90';
	@override String outOfRange({required Object min, required Object max, required Object unit}) => 'Tra ${min} e ${max} ${unit}';
	@override String get navigationLater => 'La navigazione di Lunaway tiene conto di tutte queste dimensioni.';
	@override String get save => 'Salva';
	@override String get clear => 'Cancella';
	@override String get fuelTitle => 'Carburante';
	@override String get fuelHint => 'Il prezzo del tuo carburante appare sui distributori della mappa, con i più economici per primi.';
	@override String get consumption => 'Consumo';
	@override String get consumptionUnit => 'l/100 km';
	@override String get lpgHeating => 'Riscaldamento a GPL';
	@override String get lpgHeatingHint => 'Anche i prezzi del GPL appaiono sui distributori.';
	@override String get cruiseTitle => 'Velocità di crociera massima';
	@override String get cruiseHint => 'I tempi di percorrenza presuppongono che tu non vada mai più veloce, anche dove la strada lo consente. I limiti annunciati durante la navigazione restano quelli della strada.';
	@override String get cruiseNone => 'Nessun limite';
}

// Path: vehicleHeight
class _Translations$vehicleHeight$it extends Translations$vehicleHeight$en {
	_Translations$vehicleHeight$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Altezza del tuo veicolo';
	@override String get why => 'I luoghi con un limite più basso verranno nascosti. Quelli senza altezza nota restano sulla mappa.';
	@override String get needed => 'Indica l\'altezza, per esempio 2,90';
	@override String get weightOptional => 'Massa complessiva (facoltativa)';
	@override String get apply => 'Filtra con questa altezza';
	@override String get later => 'Gli altri dati del veicolo si inseriscono in Profilo, Il mio veicolo.';
}

// Path: profile
class _Translations$profile$it extends Translations$profile$en {
	_Translations$profile$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profilo';
	@override String get noAccountNeeded => 'Nessun account, nessuna pubblicità, nessun tracciamento. I tuoi preferiti restano su questo dispositivo.';
	@override String get language => 'Lingua';
	@override String get languageSystem => 'Lingua del dispositivo';
	@override String get appearance => 'Aspetto';
	@override String get themeAuto => 'Automatico';
	@override String get themeLight => 'Chiaro';
	@override String get themeDark => 'Scuro';
	@override String get themeAutoHint => 'Chiaro di giorno, scuro dopo il tramonto dove ti trovi.';
	@override String get themeLightHint => 'Sempre chiaro, di giorno e di notte.';
	@override String get themeDarkHint => 'Sempre scuro, riposante per gli occhi di notte.';
	@override String get offline => 'Offline';
	@override String placesOnDevice({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'luogo su questo dispositivo',
		other: 'luoghi su questo dispositivo',
	);
	@override String offlineSize({required Object size}) => 'Spazio occupato: ${size}';
	@override String lastSync({required Object when}) => 'Ultimo aggiornamento ${when}';
	@override String get neverSynced => 'Mai scaricato';
	@override String get syncNow => 'Aggiorna ora';
	@override String get syncing => 'Aggiornamento in corso';
	@override String get about => 'Informazioni';
	@override String version({required Object version}) => 'Versione ${version}';
	@override String get website => 'Sito web';
	@override String get privacy => 'Informativa sulla privacy';
	@override String get sourceCode => 'Codice sorgente';
	@override String get licences => 'Licenze';
	@override String get appLicence => 'Lunaway è software libero con licenza GNU AGPL 3.0 o successiva.';
	@override String get routeData => 'I percorsi si basano su dati aperti che possono essere incompleti: la segnaletica e il codice della strada prevalgono.';
	@override String get attributions => 'Fonti e crediti';
	@override String get attributionOsm => 'Luoghi e dati cartografici © contributori di OpenStreetMap.';
	@override String get attributionOdbl => 'Dati di OpenStreetMap con licenza Open Database License (ODbL).';
	@override String get attributionAtout => 'Campeggi classificati di Atout France, posizionati con la Base Adresse Nationale e la BD TOPO dell\'IGN, con Licence Ouverte 2.0 (Etalab).';
	@override String get attributionCommunes => 'Comuni dei luoghi: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), con licenza ODbL.';
	@override String get attributionCommunityPlaces => 'Luoghi aggiunti e modificati dai viaggiatori di Lunaway, con licenza ODbL e la menzione «Lunaway contributors».';
	@override String get attributionTiles => 'Mappa di base fornita da Lunaway, stili derivati da Protomaps (BSD-3-Clause), dati © contributori di OpenStreetMap.';
	@override String get attributionFonts => 'Caratteri Fraunces e Atkinson Hyperlegible Next, con licenza SIL Open Font License 1.1.';
	@override String get attributionIcons => 'Icone Phosphor, con licenza MIT.';
	@override String get noTracking => 'Nessuna pubblicità, nessun tracciamento. Il tuo account non conosce né la tua e-mail né il tuo numero di telefono.';
	@override String get attributionBdTopo => 'Limiti di altezza, larghezza, lunghezza e peso delle strade, e campeggi posizionati in base al nome: BD TOPO dell\'IGN, tramite la Géoplateforme, con Licence Ouverte 2.0.';
	@override String get attributionAddresses => 'Indirizzi della ricerca in Francia: Base Adresse Nationale, tramite la Géoplateforme dell\'IGN, con Licence Ouverte 2.0.';
	@override String get attributionAddressesOsm => 'Indirizzi della ricerca altrove: OpenStreetMap, tramite Photon, con licenza ODbL.';
	@override String get attributionPoiOdbl => 'Negozi e servizi: OpenStreetMap e gli orari di apertura di La Poste, con licenza ODbL.';
	@override String get attributionPoiLo => 'Prezzi dei carburanti (Ministero dell\'Economia francese) e strutture sanitarie FINESS (Agence du numérique en santé), con Licence Ouverte 2.0 (Etalab).';
	@override String get attributionPacks => 'Contorni delle mappe offline: Contours administratifs, data.gouv.fr (ODbL), e Natural Earth (pubblico dominio).';
	@override String get attributionOfflineLabels => 'Nomi e icone delle mappe offline: glifi Noto Sans (SIL Open Font License 1.1) e sprite Protomaps derivati da tangrams/icons (MIT).';
	@override String get attributionExtcom => 'Luoghi, recensioni, valutazioni e foto, in base a un accordo scritto con questa fonte.';
	@override String get creditsPlaces => 'Luoghi';
	@override String get creditsContent => 'Foto, testi e recensioni';
	@override String get creditsRoutes => 'Percorsi e navigazione';
	@override String get creditsSearch => 'Ricerca';
	@override String get creditsMap => 'Mappa di base';
	@override String get creditsApp => 'App';
	@override String get attributionDatatourisme => 'Luoghi, descrizioni e foto degli uffici turistici: DATAtourisme, con Licence Ouverte 2.0; ogni testo e ogni foto indica il suo ufficio, il suo autore e la data dell\'ultimo aggiornamento.';
	@override String get attributionCommunity => 'Recensioni, valutazioni e foto dei viaggiatori di Lunaway, con licenza CC BY 4.0 e lo pseudonimo del loro autore.';
	@override String get attributionCommons => 'Foto di Wikimedia Commons, ciascuna con la propria licenza (CC0, pubblico dominio, CC BY o CC BY-SA), con il suo autore e un link alla sua pagina.';
	@override String get attributionPanoramax => 'Viste dalla strada di Panoramax: istanza di OpenStreetMap France con licenza CC BY-SA 4.0, istanza dell\'IGN con Licence Ouverte 2.0.';
	@override String get attributionWikipedia => 'Estratti di articoli di Wikipedia, con licenza CC BY-SA 4.0 e un link all\'articolo.';
	@override String get attributionMangrove => 'Recensioni di Mangrove Reviews, con licenza CC BY 4.0 o quella dichiarata dalla recensione, e un link alla recensione.';
	@override String get attributionTranslation => 'Traduzioni automatiche: modelli OPUS-MT dell\'Università di Helsinki, con licenza CC BY 4.0, eseguiti sui server di Lunaway.';
	@override String get attributionRoadEvents => 'Lavori e chiusure in Francia: DIR e Bison Futé, ordinanze di circolazione DiaLog (DGITM), città metropolitane e dipartimenti (Lyon, Toulouse, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Sarthe), con Licence Ouverte 2.0; Bordeaux Métropole e dipartimento delle Côtes-d\'Armor, con Licence Ouverte; Ville de Paris, Rennes Métropole e segnalazioni dei viaggiatori di Lunaway, con licenza ODbL.';
	@override String get attributionRoadEventsAbroad => 'Lavori e chiusure nei Paesi Bassi: NDW, Nationaal Dataportaal Wegverkeer (dati aperti); in Spagna: DGT, Dirección General de Tráfico (CC BY).';
	@override String get attributionDangerZones => 'Autovelox e zone di pericolo: in Francia, la mappa della Sécurité routière, riutilizzata secondo il Code des relations entre le public et l\'administration francese, e l\'elenco degli autovelox fissi del Ministero dell\'Interno, Délégation à la sécurité routière (data.gouv.fr), con Licence Ouverte 2.0; in Polonia, Główny Inspektorat Transportu Drogowego (CANARD, dane.gov.pl), in Lussemburgo, l\'Administration des ponts et chaussées (data.public.lu), a Bruxelles, Bruxelles Mobilité (data.mobility.brussels), con CC0; in Norvegia, «Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.»; in Irlanda, le zone di controllo di An Garda Síochána, Irish Public Sector Information, CC BY, tracciati adattati da Lunaway; OpenStreetMap (ODbL).';
	@override String attributionCameraSource({required Object attribution}) => 'Autovelox e zone di pericolo: ${attribution}';
}

// Path: units
class _Translations$units$it extends Translations$units$en {
	_Translations$units$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String kilobytes({required Object n}) => '${n} kB';
	@override String megabytes({required Object n}) => '${n} MB';
}

// Path: languages
class _Translations$languages$it extends Translations$languages$en {
	_Translations$languages$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get fr => 'francese';
	@override String get en => 'inglese';
	@override String get de => 'tedesco';
	@override String get es => 'spagnolo';
	@override String get it => 'italiano';
	@override String get nl => 'olandese';
}

// Path: translation
class _Translations$translation$it extends Translations$translation$en {
	_Translations$translation$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get translate => 'Traduci';
	@override String get translating => 'Traduzione in corso';
	@override String get showOriginal => 'Mostra l\'originale';
	@override String get showTranslation => 'Mostra la traduzione';
	@override late final _Translations$translation$from$it from = _Translations$translation$from$it._(_root);
	@override String get offline => 'Per tradurre serve una connessione a internet.';
	@override String get failedOffline => 'Nessuna connessione: impossibile tradurre il testo.';
	@override String get busy => 'Il servizio di traduzione è sovraccarico. Riprova più tardi.';
	@override String get unavailable => 'La traduzione non è disponibile al momento.';
	@override String get gone => 'Questo testo non è più disponibile.';
	@override String get unsupported => 'Nessuna traduzione disponibile per questa lingua.';
	@override String get autoReviews => 'Traduci automaticamente le recensioni';
	@override String get autoReviewsHint => 'Le recensioni scritte in un\'altra lingua vengono tradotte dal server di Lunaway, senza passare da servizi esterni.';
}

// Path: locale
class _Translations$locale$it extends Translations$locale$en {
	_Translations$locale$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
	@override String get de => 'Deutsch';
	@override String get es => 'Español';
	@override String get it => 'Italiano';
	@override String get nl => 'Nederlands';
}

// Path: account
class _Translations$account$it extends Translations$account$en {
	_Translations$account$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Il tuo account';
	@override String get noneTitle => 'Ancora nessun account';
	@override String get noneBody => 'La mappa, la ricerca e i preferiti funzionano senza account. L\'account si crea da solo al tuo primo contributo (una valutazione, una conferma, una foto), senza e-mail né password. Da quel momento le tue liste di preferiti sono collegate all\'account.';
	@override String get recover => 'Recupera il mio account';
	@override String memberSince({required Object date}) => 'Membro da ${date}';
	@override String get editPseudonym => 'Cambia lo pseudonimo';
	@override String get pseudonymTitle => 'Il tuo pseudonimo';
	@override String get pseudonymHint => 'È pubblico: appare con le tue recensioni e le tue foto. Da 3 a 32 caratteri.';
	@override String get pseudonymInvalid => 'Da 3 a 32 caratteri, di cui almeno due lettere.';
	@override String get pseudonymRefused => 'Questo pseudonimo non è accettato: niente link, recapiti o parole offensive, né un nome che si spacci per il team di Lunaway.';
	@override String get pseudonymSaved => 'Pseudonimo salvato';
	@override String level({required Object level}) => 'Livello di fiducia ${level}';
	@override late final _Translations$account$levelOpens$it levelOpens = _Translations$account$levelOpens$it._(_root);
	@override String nextLevel({required Object level}) => 'Per il livello ${level}';
	@override String get levelTop => 'Sei al livello più alto.';
	@override late final _Translations$account$requirement$it requirement = _Translations$account$requirement$it._(_root);
	@override String orInstead({required Object requirement}) => 'Oppure ${requirement}';
	@override String get recoveryNone => 'Nessuna scheda di recupero creata su questo dispositivo. Senza scheda, questo account resta legato a questo dispositivo: se perdi il dispositivo, perdi anche l\'account.';
	@override String get recoveryNoneAccount => 'Ancora nessuna scheda di recupero per questo account. Senza scheda, questo account resta legato a questo dispositivo: se perdi il dispositivo, perdi anche l\'account.';
	@override String get recoveryCreate => 'Crea la mia scheda di recupero';
	@override String recoveryMade({required Object date}) => 'Creata il ${date}';
	@override String get recoveryRemake => 'Ricrea';
	@override String get recoveryRemakeHint => 'Crea una nuova scheda di recupero';
	@override String get contributions => 'I miei contributi';
	@override String pending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} contributo in attesa di invio',
		other: '${n} contributi in attesa di invio',
	);
	@override String get mutedAuthors => 'Autori nascosti';
	@override String get devices => 'Dispositivi';
	@override String get signOut => 'Esci';
	@override String get delete => 'Elimina il mio account';
	@override String get signOutTitle => 'Uscire dall\'account su questo dispositivo?';
	@override String get signOutBody => 'La chiave dell\'account viene cancellata da questo dispositivo. Per rientrare ti servirà la tua scheda di recupero. I tuoi preferiti restano qui.';
	@override String get signOutNoCard => 'Non hai creato una scheda di recupero su questo dispositivo. Senza scheda, questo account andrà perso per sempre.';
	@override String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Un contributo in attesa di invio non verrà inviato.',
		other: '${n} contributi in attesa di invio non verranno inviati.',
	);
	@override String get signedOut => 'Disconnesso. I tuoi preferiti restano su questo dispositivo.';
	@override String get lost => 'Questo account non si apre più su questo dispositivo. Recuperalo con la tua scheda di recupero: Profilo, Recupera il mio account.';
	@override String get lostAction => 'Recupera';
	@override String get welcomeTitle => 'Grazie per il tuo primo contributo';
	@override String welcomeBody({required Object name}) => 'Il tuo account è stato creato con lo pseudonimo «${name}». Niente e-mail né password: una chiave conservata su questo dispositivo. Puoi cambiare lo pseudonimo nel Profilo.';
	@override String get welcomeCard => 'Crea la tua scheda di recupero per ritrovare questo account su un altro dispositivo.';
	@override String get welcomeFavorites => 'Le tue liste di preferiti ora sono conservate con il tuo account.';
}

// Path: recovery
class _Translations$recovery$it extends Translations$recovery$en {
	_Translations$recovery$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Scheda di recupero';
	@override String get intro => 'Un codice che riporta il tuo account su un nuovo dispositivo. Lunaway ne conserva solo un\'impronta, che serve a verificarlo: il codice stesso non potrà mai più essere mostrato, e ogni nuova scheda ha un codice diverso.';
	@override String get replaces => 'Una nuova scheda sostituisce la precedente: il vecchio codice smetterà di funzionare.';
	@override String replaceTitle({required Object date}) => 'Sostituire la scheda del ${date}?';
	@override String replaceBody({required Object date}) => 'La nuova scheda avrà un altro codice. Quello della scheda del ${date} smette di funzionare da subito. Non può essere mostrato di nuovo: Lunaway ne ha conservato solo un\'impronta.';
	@override String get replaceKeep => 'Tieni la vecchia';
	@override String get replaceConfirm => 'Crea una nuova scheda';
	@override String get make => 'Crea la scheda';
	@override String get codeLabel => 'Il tuo codice di recupero';
	@override String get shownOnce => 'Questo codice appare una sola volta. Annotalo, o salva l\'immagine, prima di chiudere.';
	@override String get saveImage => 'Salva l\'immagine';
	@override String get done => 'Ho annotato il codice';
	@override String get doneTitle => 'Hai conservato il codice?';
	@override String get doneBody => 'Una volta chiusa questa pagina, il codice non apparirà più.';
	@override String get keep => 'Resta sulla pagina';
	@override String get cardHeading => 'Scheda di recupero Lunaway';
	@override String cardAccount({required Object name}) => 'Account: ${name}';
	@override String get cardHow => 'Per recuperare l\'account: Profilo, Recupera il mio account, poi digita questo codice o fotografa la scheda.';
	@override String cardMade({required Object date}) => 'Creata il ${date}';
	@override String get cardWarning => 'Questo codice apre l\'account: non darlo mai a nessuno.';
	@override String get failed => 'Non è stato possibile creare la scheda. Serve una connessione.';
	@override String get fileName => 'scheda-di-recupero-lunaway';
	@override String get step1 => 'Crea la scheda: il codice appare una sola volta.';
	@override String get step2 => 'Salva l\'immagine, stampala, o ricopia il codice a mano.';
	@override String get step3 => 'Conservala nel cassetto portaoggetti, con i documenti del veicolo.';
}

// Path: recover
class _Translations$recover$it extends Translations$recover$en {
	_Translations$recover$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Recupera il mio account';
	@override String get intro => 'Digita il codice della tua scheda di recupero, o leggilo da una foto della scheda.';
	@override String get field => 'Codice di recupero';
	@override String get fieldHint => '27 caratteri, a gruppi di quattro';
	@override String remaining({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Ancora ${n} carattere',
		other: 'Ancora ${n} caratteri',
	);
	@override String get invalid => 'Questo codice non corrisponde a nessuna scheda: controlla ogni carattere.';
	@override String get valid => 'Codice completo';
	@override String get scan => 'Leggi la scheda da una foto';
	@override String get scanFile => 'Scegli l\'immagine della scheda';
	@override String get reading => 'Lettura della scheda';
	@override String get scanFailed => 'Nessun codice leggibile in questa immagine. Prova con una foto più nitida, con la scheda ben piatta.';
	@override String get revoke => 'Il mio vecchio dispositivo è stato perso o rubato: disconnettilo';
	@override String get revokeHint => 'Tutti gli altri tuoi dispositivi verranno disconnessi.';
	@override String get submit => 'Recupera l\'account';
	@override String get notFound => 'Nessun account ha questo codice. Controlla la scheda, o creane una nuova da un dispositivo connesso.';
	@override String get tooMany => 'Troppi tentativi per ora. Riprova tra un\'ora.';
	@override String done({required Object name}) => 'Account recuperato: ${name}';
}

// Path: deletion
class _Translations$deletion$it extends Translations$deletion$en {
	_Translations$deletion$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Elimina il mio account';
	@override String get intro => 'L\'eliminazione è immediata e definitiva.';
	@override String get goneTitle => 'Cosa viene eliminato';
	@override late final _Translations$deletion$gone$it gone = _Translations$deletion$gone$it._(_root);
	@override String get keptTitle => 'Cosa resta, senza il tuo nome';
	@override String get kept => 'Le tue recensioni scritte pubblicate, le tue conferme e le tue modifiche ai luoghi già applicate restano, senza autore: fanno parte della mappa degli altri viaggiatori.';
	@override String get backups => 'I backup del server vengono cancellati entro circa 30 giorni.';
	@override String get device => 'Su questo dispositivo i tuoi preferiti restano; la chiave dell\'account viene cancellata.';
	@override String get web => 'Puoi eliminarlo anche su lunaway.net con il tuo codice di recupero.';
	@override String get webLink => 'lunaway.net/it/account/delete';
	@override String get confirmTitle => 'Eliminare definitivamente?';
	@override String confirmBody({required Object name}) => 'L\'account «${name}» e tutto ciò che è elencato vengono eliminati ora. Nessuno potrà ripristinarlo.';
	@override String get confirmCheck => 'Ho capito che è definitivo';
	@override String get confirm => 'Elimina l\'account';
	@override String get done => 'Account eliminato';
	@override String get failed => 'Non è stato possibile eliminare l\'account. Serve una connessione.';
}

// Path: devices
class _Translations$devices$it extends Translations$devices$en {
	_Translations$devices$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Dispositivi';
	@override String get intro => 'Ogni dispositivo ha la sua chiave. Rimuovi un dispositivo perso, o uno che non usi più.';
	@override String get thisDevice => 'Questo dispositivo';
	@override String get other => 'Altro dispositivo';
	@override String added({required Object date}) => 'Aggiunto il ${date}';
	@override String lastUsed({required Object when}) => 'Ultimo utilizzo ${when}';
	@override String get revoke => 'Rimuovi';
	@override String get revokeTitle => 'Rimuovere questo dispositivo?';
	@override String get revokeBody => 'Verrà disconnesso e non potrà più usare l\'account.';
	@override String get revoked => 'Dispositivo rimosso';
	@override String get signOutOthers => 'Disconnetti tutti gli altri dispositivi';
	@override String signedOutOthers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		zero: 'Nessun\'altra sessione aperta',
		one: '${n} sessione chiusa',
		other: '${n} sessioni chiuse',
	);
	@override String get error => 'Non è stato possibile caricare i dispositivi. Serve una connessione.';
}

// Path: muted
class _Translations$muted$it extends Translations$muted$en {
	_Translations$muted$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Autori nascosti';
	@override String get empty => 'Nessuno è nascosto';
	@override String get emptyHint => 'Per nascondere qualcuno, apri il menu di una sua recensione o di una sua foto. La scelta vale solo per te.';
	@override String get unmute => 'Mostra di nuovo';
	@override String unmuted({required Object name}) => 'I contributi di ${name} verranno mostrati di nuovo';
}

// Path: mine
class _Translations$mine$it extends Translations$mine$en {
	_Translations$mine$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'I miei contributi';
	@override String get pending => 'In attesa di invio';
	@override String get pendingHint => 'Verranno inviati appena torna la rete.';
	@override String get sendNow => 'Invia ora';
	@override String get retry => 'Riprova';
	@override String get discard => 'Scarta';
	@override String get discardTitle => 'Scartare questo contributo?';
	@override String get discardBody => 'Non verrà inviato.';
	@override String get reviews => 'Recensioni e valutazioni';
	@override String get photos => 'Foto';
	@override String get confirmations => 'Conferme';
	@override String get issues => 'Problemi segnalati';
	@override String get places => 'Luoghi aggiunti e modifiche';
	@override String get empty => 'Ancora niente';
	@override String get emptyHint => 'Valutare un luogo o confermare che c\'è ancora è già un contributo.';
	@override String latest({required Object shown, required Object total}) => 'I ${shown} più recenti su ${total}';
	@override String get error => 'Non è stato possibile caricare i tuoi contributi. Serve una connessione.';
	@override String get deleteTitle => 'Eliminare questo contributo?';
	@override String get deleteBody => 'Viene rimosso da Lunaway.';
	@override String get deleteApplied => 'Questo luogo fa già parte della mappa: ci resta, senza il tuo nome.';
	@override String get deleted => 'Contributo eliminato';
	@override String get ratingOnly => 'Solo valutazione';
	@override late final _Translations$mine$status$it status = _Translations$mine$status$it._(_root);
	@override late final _Translations$mine$submission$it submission = _Translations$mine$submission$it._(_root);
	@override String get newPlace => 'Nuovo luogo';
	@override String get edit => 'Modifica';
	@override String get aPlace => 'Un luogo';
	@override String get newVendingMachine => 'Nuovo distributore automatico';
	@override String get poiConfirmations => 'Negozi e servizi confermati';
	@override String get aPoi => 'Un negozio o un servizio';
}

// Path: outbox
class _Translations$outbox$it extends Translations$outbox$en {
	_Translations$outbox$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override late final _Translations$outbox$kind$it kind = _Translations$outbox$kind$it._(_root);
	@override String get waiting => 'In attesa della rete';
	@override String get sending => 'Invio in corso';
	@override late final _Translations$outbox$error$it error = _Translations$outbox$error$it._(_root);
	@override String get sent => 'Grazie, inviato';
	@override String get queued => 'Nessuna rete: verrà inviato appena torna';
	@override String refused({required Object reason}) => 'Non inviato. ${reason}';
}

// Path: placement
class _Translations$placement$it extends Translations$placement$en {
	_Translations$placement$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Posiziona il luogo';
	@override String get hint => 'Sposta la mappa: la croce indica il punto esatto.';
	@override String get confirm => 'Conferma questa posizione';
	@override String duplicate({required Object name, required Object distance}) => 'C\'è già «${name}» a ${distance}: è lo stesso luogo?';
	@override String get same => 'Sì, apri la sua scheda';
	@override String get notSame => 'No, è un altro luogo';
}

// Path: contribute
class _Translations$contribute$it extends Translations$contribute$en {
	_Translations$contribute$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get yourRating => 'La tua valutazione';
	@override String get rateHint => 'Tocca una stella per valutare';
	@override String rateStar({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Valuta con ${n} stella',
		other: 'Valuta con ${n} stelle',
	);
	@override String get writeReview => 'Scrivi una recensione';
	@override String get editReview => 'Modifica la tua recensione';
	@override String get deleteReview => 'Elimina la tua recensione';
	@override String get deleteReviewTitle => 'Eliminare la tua recensione?';
	@override String get deleteReviewBody => 'Il testo e la valutazione spariscono dalla scheda.';
	@override String get deleteRating => 'Rimuovi la tua valutazione';
	@override String get deleteRatingTitle => 'Rimuovere la tua valutazione?';
	@override String get deleteRatingBody => 'La tua valutazione sparisce dalla scheda del luogo.';
	@override String get pendingSend => 'In attesa di invio';
	@override String get statusPending => 'In revisione: per ora visibile solo a te';
	@override String get statusHidden => 'Nascosto dopo alcune segnalazioni, in attesa di un moderatore';
	@override String get statusRemoved => 'Rimosso dalla moderazione';
	@override String get addPhoto => 'Aggiungi una foto';
	@override String get firstPhoto => 'Aggiungi la prima foto';
	@override String get stillThere => 'C\'è ancora?';
	@override String get more => 'Altre azioni';
	@override String get reportIssue => 'Segnala un problema';
	@override String get proposeEdit => 'Proponi una modifica';
	@override String get editPlace => 'Modifica il luogo';
	@override String get reportPlace => 'Segnala questo luogo ai moderatori';
	@override String get toVerifyTitle => 'Da verificare';
	@override String get toVerifyBody => 'Luogo aggiunto dalla comunità, in attesa di due conferme. Lo conosci? Confermalo.';
	@override String get issuesTitle => 'Segnalazioni degli ultimi 30 giorni';
	@override String issueCount({required Object kind, required Object count}) => '${kind} (${count})';
	@override String get addPlaceHere => 'Aggiungi un luogo qui';
	@override String get addPlaceHint => 'Il punto scelto sotto la croce.';
}

// Path: confirmSheet
class _Translations$confirmSheet$it extends Translations$confirmSheet$en {
	_Translations$confirmSheet$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'C\'è ancora?';
	@override String get body => 'Ci sei passato di recente? La tua risposta mostra ai prossimi viaggiatori che la scheda è aggiornata. Non viene inviata alcuna posizione.';
	@override String get stillOk => 'Sì, come descritto';
	@override String get closed => 'Chiuso';
	@override String get changed => 'Cambiato';
	@override String get closedHint => 'Non accoglie più viaggiatori';
	@override String get changedHint => 'C\'è ancora, ma qualcosa è cambiato';
	@override String get note => 'Qualcosa da aggiungere? (facoltativo)';
	@override String get noteHint => 'Per esempio: barra limitatrice installata, colonnina spostata';
	@override late final _Translations$confirmSheet$status$it status = _Translations$confirmSheet$status$it._(_root);
}

// Path: issueSheet
class _Translations$issueSheet$it extends Translations$issueSheet$en {
	_Translations$issueSheet$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Segnala un problema';
	@override String get body => 'La tua segnalazione contribuisce all\'avviso mostrato sulla scheda. La nota la leggono solo i moderatori.';
	@override late final _Translations$issueSheet$kind$it kind = _Translations$issueSheet$kind$it._(_root);
	@override late final _Translations$issueSheet$hint$it hint = _Translations$issueSheet$hint$it._(_root);
	@override String get note => 'Qualcosa da aggiungere? (facoltativo)';
	@override String get send => 'Segnala';
}

// Path: reportSheet
class _Translations$reportSheet$it extends Translations$reportSheet$en {
	_Translations$reportSheet$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get review => 'Segnala questa recensione';
	@override String get photo => 'Segnala questa foto';
	@override String get place => 'Segnala questo luogo';
	@override String get body => 'I moderatori la esamineranno. L\'autore non saprà chi ha fatto la segnalazione.';
	@override late final _Translations$reportSheet$reason$it reason = _Translations$reportSheet$reason$it._(_root);
	@override String get note => 'Aggiungi dettagli (facoltativo)';
	@override String get noteOther => 'Spiega cosa non va';
	@override String get sent => 'Grazie, i moderatori daranno un\'occhiata';
	@override String mute({required Object name}) => 'Nascondi recensioni e foto di ${name}';
	@override String get muteAuthor => 'Nascondi questo autore';
	@override String muteTitle({required Object name}) => 'Nascondere ${name}?';
	@override String get muteBody => 'Le sue recensioni e le sue foto non ti verranno più mostrate. Puoi cambiare idea nel Profilo.';
	@override String muted({required Object name}) => 'Contributi di ${name} nascosti';
	@override String get deletePhoto => 'Elimina la mia foto';
	@override String get deletePhotoTitle => 'Eliminare questa foto?';
	@override String get deletePhotoBody => 'Viene rimossa dalla scheda e dai nostri server.';
}

// Path: reviewSheet
class _Translations$reviewSheet$it extends Translations$reviewSheet$en {
	_Translations$reviewSheet$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get titleNew => 'La tua recensione';
	@override String get titleEdit => 'Modifica la tua recensione';
	@override String get starsRequired => 'Scegli una valutazione da 1 a 5';
	@override String get text => 'La tua recensione';
	@override String get textHint => 'La tranquillità, l\'accoglienza, lo spazio per manovrare, cosa ti è stato utile';
	@override String tooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Ancora almeno ${n} carattere',
		other: 'Ancora almeno ${n} caratteri',
	);
	@override String get visited => 'Data del soggiorno';
	@override String get visitedNone => 'Non indicata';
	@override String get vehicle => 'Il tuo veicolo';
	@override String get vehicleNone => 'Preferisco non dirlo';
	@override String get licence => 'Pubblicata con licenza CC BY 4.0, con il tuo pseudonimo. La data del soggiorno è facoltativa: messe insieme, le date delle tue recensioni possono rivelare il tuo itinerario.';
	@override String get publish => 'Pubblica la recensione';
}

// Path: gate
class _Translations$gate$it extends Translations$gate$en {
	_Translations$gate$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get review => 'Recensioni scritte: dal livello 1';
	@override String get photo => 'Foto: dal livello 1';
	@override String get addPlace => 'Aggiunta di luoghi: dal livello 2';
	@override String get edit => 'Proposte di modifica: dal livello 1';
	@override String get why => 'I livelli proteggono la mappa dagli abusi. Arrivano con il tempo e i contributi, senza niente da comprare.';
	@override String yourLevel({required Object level}) => 'Il tuo livello: ${level}';
	@override String get noAccount => 'Ancora nessun account: un account parte dal livello 0.';
	@override String later({required Object level}) => 'Il livello ${level} arriva dopo i precedenti, con il tempo e i contributi pubblicati.';
	@override String get meanwhile => 'Nel frattempo puoi valutare i luoghi, confermare che ci sono ancora o segnalare un problema.';
}

// Path: photoFlow
class _Translations$photoFlow$it extends Translations$photoFlow$en {
	_Translations$photoFlow$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Aggiungi una foto';
	@override String get camera => 'Scatta una foto';
	@override String get gallery => 'Scegli dalla galleria';
	@override String get preparing => 'Preparazione della foto';
	@override String get licence => 'Pubblicata con licenza CC BY 4.0, con il tuo pseudonimo. Evita volti e targhe.';
	@override String get stripped => 'La posizione e i dati del dispositivo vengono rimossi prima dell\'invio.';
	@override String get send => 'Invia la foto';
	@override String get unreadable => 'Questa immagine non può essere letta su questo dispositivo. Prova con una foto JPEG o PNG.';
	@override String sending({required Object percent}) => 'Invio ${percent}%';
	@override String get pending => 'Foto in attesa di invio';
}

// Path: placeForm
class _Translations$placeForm$it extends Translations$placeForm$en {
	_Translations$placeForm$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get addTitle => 'Aggiungi un luogo';
	@override String get editTitle => 'Modifica il luogo';
	@override String get proposeTitle => 'Proponi una modifica';
	@override String get position => 'Posizione sulla mappa';
	@override String get kind => 'Tipo di luogo';
	@override String get kindRequired => 'Scegli un tipo di luogo';
	@override String get name => 'Nome';
	@override String get nameHint => 'Il nome indicato sul posto, o una breve descrizione';
	@override String get nameInvalid => 'Da 2 a 120 caratteri';
	@override String get night => 'Pernottamento';
	@override String get services => 'Servizi sul posto';
	@override String get description => 'Descrizione';
	@override String get descriptionHint => 'Ciò che aiuta a trovare e a scegliere il luogo';
	@override String get details => 'Dettagli';
	@override String get priceNight => 'Prezzo a notte (€)';
	@override String get priceServices => 'Prezzo dei servizi (€)';
	@override String get maxHeight => 'Altezza massima (m)';
	@override String get capacity => 'Posti';
	@override String get website => 'Sito web';
	@override String get phone => 'Telefono';
	@override String get photo => 'Foto (facoltativa)';
	@override String get photoReady => 'Foto pronta';
	@override String get removePhoto => 'Rimuovi la foto';
	@override String get toVerify => 'Il luogo apparirà come «da verificare» finché altri due viaggiatori non lo confermeranno.';
	@override String get licence => 'I luoghi sono pubblicati con licenza ODbL, attribuiti ai contributori di Lunaway.';
	@override String get moderated => 'Un sito web o un numero di telefono passa da un moderatore prima di essere pubblicato.';
	@override String get direct => 'Con il tuo livello la modifica viene applicata subito.';
	@override String get proposal => 'Un moderatore esaminerà la tua proposta prima che venga applicata.';
	@override String get submitAdd => 'Aggiungi il luogo';
	@override String get submitEdit => 'Salva la modifica';
	@override String get submitPropose => 'Invia la proposta';
	@override String get nothingChanged => 'Non è cambiato niente';
	@override String get invalidNumber => 'Inserisci un numero';
	@override String get invalidWebsite => 'Un indirizzo che inizia con http:// o https://';
	@override String get added => 'Grazie: il luogo arriva sulla mappa tra un attimo';
	@override String get proposed => 'Grazie: la tua proposta passa in revisione';
}

// Path: favoritesSync
class _Translations$favoritesSync$it extends Translations$favoritesSync$en {
	_Translations$favoritesSync$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get local => 'Solo su questo dispositivo';
	@override String get action => 'Sincronizza';
	@override String get syncing => 'Sincronizzazione in corso';
	@override String synced({required Object when}) => 'Conservati con il tuo account, sincronizzati ${when}';
	@override String get failed => 'Impossibile sincronizzare al momento';
	@override String get title => 'Sincronizzare i tuoi preferiti?';
	@override String get body => 'Le tue liste verranno conservate con un account Lunaway, senza e-mail né password, per ritrovarle su un altro dispositivo. L\'account viene creato ora.';
	@override String get confirm => 'Crea l\'account e sincronizza';
}

// Path: poi
class _Translations$poi$it extends Translations$poi$en {
	_Translations$poi$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override late final _Translations$poi$category$it category = _Translations$poi$category$it._(_root);
	@override late final _Translations$poi$kind$it kind = _Translations$poi$kind$it._(_root);
	@override String get chipsLabel => 'Negozi e servizi nei dintorni';
	@override String get openNow => 'Aperto ora';
	@override late final _Translations$poi$vendingSells$it vendingSells = _Translations$poi$vendingSells$it._(_root);
	@override String get vendingAll => 'Tutti i distributori di alimenti';
	@override String get vendingMenu => 'Cosa vendono i distributori';
	@override late final _Translations$poi$vendingChip$it vendingChip = _Translations$poi$vendingChip$it._(_root);
	@override String get alwaysOpen => 'Aperto giorno e notte';
	@override String get hoursUnknown => 'Orari sconosciuti';
	@override String get maybeClosed => 'Chiuso secondo il registro ufficiale francese delle strutture sanitarie (FINESS).';
	@override String maybeClosedSince({required Object date}) => 'Indicato come chiuso da FINESS dal ${date}: potrebbe aver chiuso definitivamente.';
	@override String get seasonal => 'Stagionale: potrebbe essere chiuso in inverno.';
	@override String get fee => 'A pagamento';
	@override String get free => 'Gratuito';
	@override String get stillThereTitle => 'C\'è ancora?';
	@override String get stillThereHint => 'L\'hai visto di recente? La tua risposta aiuta i prossimi viaggiatori. Non viene inviata alcuna posizione.';
	@override String get stillThere => 'C\'è ancora';
	@override String get gone => 'Non c\'è più';
	@override String lastConfirmed({required Object when}) => 'Presenza confermata ${when}';
	@override String checkedOn({required Object date}) => 'Verificato sul posto il ${date}';
	@override String get thanksThere => 'Grazie, annotato: c\'è ancora.';
	@override String get thanksGone => 'Grazie, annotato: non c\'è più.';
	@override String get fuelPrices => 'Prezzi dei carburanti';
	@override String perLitre({required Object price}) => '${price}/l';
	@override String priceUpdated({required Object when}) => 'Prezzo aggiornato ${when}';
	@override String feedRead({required Object when}) => 'Prezzi rilevati ${when}';
	@override String get shortageTemporary => 'Temporaneamente esaurito';
	@override String get shortageDefinitive => 'Non più in vendita';
	@override String get selfService24h => 'Pagamento con carta 24 ore su 24';
	@override String get highway => 'In autostrada';
	@override String get lpgYes => 'Vende GPL';
	@override late final _Translations$poi$fuel$it fuel = _Translations$poi$fuel$it._(_root);
	@override String get products => 'Vende';
	@override String get paymentTitle => 'Pagamento';
	@override late final _Translations$poi$product$it product = _Translations$poi$product$it._(_root);
	@override late final _Translations$poi$payment$it payment = _Translations$poi$payment$it._(_root);
	@override String get justNow => 'poco fa';
	@override String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} minuto fa',
		other: '${n} minuti fa',
	);
	@override String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} ora fa',
		other: '${n} ore fa',
	);
	@override String readOffline({required Object when}) => 'Rilevato ${when}: nessuna rete per aggiornarlo';
	@override String readStale({required Object when}) => 'Rilevato ${when}: al momento non è stato possibile aggiornarlo.';
	@override String get goneTitle => 'Questo punto non è più sulla mappa';
	@override String get goneHint => 'Alcuni viaggiatori hanno detto che non c\'è più, oppure l\'ultimo aggiornamento l\'ha rimosso.';
	@override String get loadError => 'Non è stato possibile caricare i dettagli. Qui sopra trovi le informazioni già presenti sulla mappa.';
	@override String get around => 'Intorno a questo luogo';
	@override String get aroundEmpty => 'Nessun negozio né servizio noto qui intorno.';
	@override String get aroundError => 'Non è stato possibile caricare i negozi e i servizi nei dintorni.';
	@override String get aroundOffline => 'Nessuna rete: i negozi e i servizi nei dintorni appariranno quando sarai connesso.';
	@override String get onSite => 'Sul posto';
	@override String backTo({required Object name}) => 'Torna a ${name}';
	@override String get backToPlace => 'Torna al luogo';
	@override String get linkError => 'Non è stato possibile aprire questo negozio o servizio: nessuna rete, oppure non è più sulla mappa.';
	@override String get searchSection => 'Negozi e servizi';
	@override String get searching => 'Ricerca di negozi e servizi';
	@override String get searchOffline => 'Negozi e servizi si cercano online: ora non c\'è rete.';
	@override late final _Translations$poi$add$it add = _Translations$poi$add$it._(_root);
	@override late final _Translations$poi$cheapest$it cheapest = _Translations$poi$cheapest$it._(_root);
	@override late final _Translations$poi$trend$it trend = _Translations$poi$trend$it._(_root);
	@override String get marketDays => 'Giorni di mercato';
	@override late final _Translations$poi$vehicles$it vehicles = _Translations$poi$vehicles$it._(_root);
}

// Path: offlineMaps
class _Translations$offlineMaps$it extends Translations$offlineMaps$en {
	_Translations$offlineMaps$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mappe offline';
	@override String get intro => 'Prima di partire, conserva una regione sul dispositivo: i suoi luoghi per cercare e scegliere, la sua mappa per vedere le strade senza rete.';
	@override String get webTitle => 'Le mappe offline sono nell\'app';
	@override String get web => 'Le app per Android e iOS conservano le regioni per il viaggio. In un browser, la mappa ha bisogno della rete.';
	@override String get desktopTitle => 'Le mappe offline sono sul telefono';
	@override String get desktop => 'Le app per Android e iOS conservano le regioni per il viaggio. Su un computer, la mappa ha bisogno della rete.';
	@override String get unreadable => 'Non è stato possibile caricare le mappe offline di questo dispositivo.';
	@override String get none => 'Ancora nessuna regione su questo dispositivo.';
	@override String used({required Object size}) => 'Spazio occupato: ${size}';
	@override String get downloads => 'Download in corso';
	@override String get installed => 'Su questo dispositivo';
	@override String get suggested => 'Suggerite';
	@override String get here => 'Dove ti trovi';
	@override String favoritesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} preferito in questa regione',
		other: '${n} preferiti in questa regione',
	);
	@override String get france => 'Francia';
	@override String get overseas => 'Francia d\'oltremare';
	@override String get countries => 'Paesi';
	@override String downloadNamed({required Object name, required Object size}) => 'Scarica ${name}, ${size}';
	@override String get pause => 'Metti in pausa';
	@override String get resume => 'Riprendi';
	@override String get cancel => 'Interrompi ed elimina il download';
	@override String get waiting => 'In attesa del suo turno';
	@override String progress({required Object done, required Object total}) => '${done} di ${total}';
	@override String paused({required Object done, required Object total}) => 'In pausa: ${done} di ${total}';
	@override String get verifying => 'Verifica del file';
	@override String get failedNetwork => 'Interrotto: nessuna rete. Riprenderà da dove si è fermato appena torna la rete.';
	@override String get failedServer => 'Il server ha inviato qualcosa di diverso dalla mappa. Riprova più tardi.';
	@override String get failedCorrupt => 'Il file è arrivato danneggiato ed è stato eliminato. Riprova.';
	@override String get failedStorage => 'Spazio insufficiente sul dispositivo. Libera un po\' di spazio, poi riprova.';
	@override String get keepOpen => 'Tieni l\'app aperta durante il download: si interrompe quando l\'app passa in background e riprende quando ci torni.';
	@override String dataOf({required Object date}) => 'dati del ${date}';
	@override String update({required Object size}) => 'Aggiorna, ${size}';
	@override String deleteNamed({required Object name}) => 'Elimina ${name}';
	@override String deleteTitle({required Object name}) => 'Eliminare ${name} da questo dispositivo?';
	@override String get deleteBody => 'Non sarà più visibile senza rete. Potrai scaricarla di nuovo.';
	@override String get listOffline => 'L\'elenco delle regioni ha bisogno della rete.';
	@override String get listCopy => 'Elenco conservato dall\'ultima connessione.';
	@override String get entryHint => 'Per viaggiare senza rete';
	@override String entryCount({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Mappe: ${n} regione, ${size}',
		other: 'Mappe: ${n} regioni, ${size}',
	);
	@override String noticePack({required Object name}) => 'Offline: mappa scaricata, ${name}';
	@override String get noticeOutside => 'Offline: quest\'area non è scaricata';
	@override String get noticePlacesOnly => 'Offline: luoghi sul dispositivo, mappa di quest\'area da scaricare';
	@override String get noticeNone => 'Offline: scarica una regione per la prossima volta';
	@override String get noticeOnline => 'Offline: la mappa ha bisogno della rete';
	@override String get placesTitle => 'Luoghi';
	@override String get placesHint => 'Pochi megabyte per regione: elenco, ricerca, schede e filtri funzionano senza rete.';
	@override String get mapsTitle => 'Mappe';
	@override String get mapsHint => 'Tutte le strade, qualche centinaio di megabyte per regione: la mappa si vede senza rete.';
	@override String entryPlaces({required Object names}) => 'Luoghi: ${names}';
	@override String entryPlacesCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Luoghi: ${n} regione',
		other: 'Luoghi: ${n} regioni',
	);
}

// Path: regions
class _Translations$regions$it extends Translations$regions$en {
	_Translations$regions$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get pickerTitle => 'Quali luoghi tenere su questo dispositivo?';
	@override String get pickerIntro => 'Ogni regione si scarica una volta, poi si aggiorna con piccoli download. Potrai aggiungere o rimuovere regioni più tardi in Mappe offline.';
	@override String nearYou({required Object name}) => 'Vicino a te: ${name}';
	@override String get findMine => 'Trova la mia regione';
	@override String get locating => 'Ricerca della tua regione';
	@override String get notCovered => 'Ancora nessuna regione Lunaway intorno a te';
	@override String get wholeFrance => 'Tutta la Francia';
	@override String get showFrance => 'Mostra le regioni della Francia';
	@override String get hideFrance => 'Nascondi le regioni della Francia';
	@override String packInfo({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${count} luogo, ${size}',
		other: '${count} luoghi, ${size}',
	);
	@override String get noPack => 'Senza pacchetto: luoghi ricevuti con gli aggiornamenti, dimensione sconosciuta';
	@override String download({required Object size}) => 'Scarica, ${size}';
	@override String get unavailable => 'Il server non offre ancora regioni: Lunaway conserva tutta la Francia.';
	@override String get listFailed => 'L\'elenco delle regioni ha bisogno della rete.';
	@override String get choose => 'Scegli le regioni';
	@override String get noneKept => 'Nessuna regione conservata: la mappa non ha luoghi offline.';
	@override String get change => 'Aggiungi o rimuovi regioni';
	@override String removeNamed({required Object name}) => 'Rimuovi ${name}';
	@override String removed({required Object name}) => '${name}: luoghi rimossi da questo dispositivo';
	@override String downloading({required Object done, required Object total}) => 'Download, ${done} di ${total}';
	@override String updating({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Aggiornamento, ${count} luogo',
		other: 'Aggiornamento, ${count} luoghi',
	);
	@override String get waiting => 'in attesa del download';
	@override String downloadingNamed({required Object name}) => 'Download dei luoghi: ${name}';
	@override String updated({required Object when}) => 'ultimo aggiornamento ${when}';
	@override String offerTitle({required Object name}) => '${name}: conservare i luoghi offline?';
	@override String get downloadThis => 'Scarica questa regione';
	@override String notHere({required Object name}) => '${name} non è su questo dispositivo';
	@override String get updatesOnMobile => 'Aggiorna con i dati mobili';
	@override String get updatesOnMobileHint => 'Altrimenti le regioni già scaricate si aggiornano in Wi-Fi. Un nuovo download usa qualsiasi rete.';
}

// Path: roadReport
class _Translations$roadReport$it extends Translations$roadReport$en {
	_Translations$roadReport$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get actionHint => 'Segnala un problema sulla strada';
	@override String get title => 'Cosa vedi sulla strada?';
	@override String get intro => 'La tua segnalazione avvisa gli altri viaggiatori. Quando due account affidabili segnalano la stessa cosa, i percorsi la evitano. I controlli di polizia non si segnalano.';
	@override late final _Translations$roadReport$kinds$it kinds = _Translations$roadReport$kinds$it._(_root);
	@override String height({required Object value}) => 'Altezza indicata: ${value}';
	@override String get send => 'Segnala';
	@override String get sent => 'Grazie: gli altri viaggiatori sono avvisati.';
	@override String get stillThere => 'C\'è ancora';
	@override String get over => 'Non c\'è più';
	@override String get overSent => 'Grazie: annotato.';
	@override String get fromMap => 'Segnala un problema qui';
	@override String get notHereTitle => 'Segnalazioni non disponibili qui';
	@override String get lower => '10 cm in meno';
	@override String get higher => '10 cm in più';
	@override String passed({required Object what}) => 'Appena superato: ${what}. C\'è ancora?';
	@override String notHere({required Object countries}) => 'Lunaway accetta segnalazioni dove una fonte ufficiale le può verificare: ${countries}.';
}

// Path: countries
class _Translations$countries$it extends Translations$countries$en {
	_Translations$countries$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get ad => 'Andorra';
	@override String get at => 'Austria';
	@override String get ax => 'Isole Åland';
	@override String get be => 'Belgio';
	@override String get ch => 'Svizzera';
	@override String get cz => 'Repubblica Ceca';
	@override String get de => 'Germania';
	@override String get dk => 'Danimarca';
	@override String get eh => 'Sahara Occidentale';
	@override String get es => 'Spagna';
	@override String get fi => 'Finlandia';
	@override String get fr => 'Francia';
	@override String get gb => 'Regno Unito';
	@override String get gi => 'Gibilterra';
	@override String get gr => 'Grecia';
	@override String get hr => 'Croazia';
	@override String get ie => 'Irlanda';
	@override String get it => 'Italia';
	@override String get li => 'Liechtenstein';
	@override String get lu => 'Lussemburgo';
	@override String get ma => 'Marocco';
	@override String get mc => 'Principato di Monaco';
	@override String get nl => 'Paesi Bassi';
	@override String get no => 'Norvegia';
	@override String get pl => 'Polonia';
	@override String get pt => 'Portogallo';
	@override String get se => 'Svezia';
	@override String get si => 'Slovenia';
	@override String get sj => 'Svalbard';
	@override String get sm => 'San Marino';
	@override String get va => 'Città del Vaticano';
}

// Path: areas
class _Translations$areas$it extends Translations$areas$en {
	_Translations$areas$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get ara => 'Alvernia-Rodano-Alpi';
	@override String get bfc => 'Borgogna-Franca Contea';
	@override String get bre => 'Bretagna';
	@override String get cvl => 'Centro-Valle della Loira';
	@override String get cor => 'Corsica';
	@override String get ges => 'Grand Est';
	@override String get hdf => 'Hauts-de-France';
	@override String get idf => 'Île-de-France';
	@override String get nor => 'Normandia';
	@override String get naq => 'Nuova Aquitania';
	@override String get occ => 'Occitania';
	@override String get pdl => 'Paesi della Loira';
	@override String get pac => 'Provenza-Alpi-Costa Azzurra';
	@override String get gp => 'Guadalupa';
	@override String get mq => 'Martinica';
	@override String get gf => 'Guyana francese';
	@override String get re => 'Riunione';
	@override String get yt => 'Mayotte';
	@override String get franceRest => 'Resto della Francia';
}

// Path: search.addressKind
class _Translations$search$addressKind$it extends Translations$search$addressKind$en {
	_Translations$search$addressKind$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get houseNumber => 'Indirizzo';
	@override String get street => 'Via';
	@override String get locality => 'Località';
	@override String get town => 'Comune';
	@override String get postcode => 'CAP';
	@override String get region => 'Regione';
}

// Path: place.inclusions
class _Translations$place$inclusions$it extends Translations$place$inclusions$en {
	_Translations$place$inclusions$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get services => 'servizi';
	@override String get touristTax => 'tassa di soggiorno';
	@override String get electricity => 'corrente elettrica';
}

// Path: place.reviewVehicle
class _Translations$place$reviewVehicle$it extends Translations$place$reviewVehicle$en {
	_Translations$place$reviewVehicle$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Furgonato';
	@override String get motorhome => 'Camper';
	@override String get caravan => 'Caravan';
	@override String get other => 'Altro veicolo';
}

// Path: sources.extcom
class _Translations$sources$extcom$it extends Translations$sources$extcom$en {
	_Translations$sources$extcom$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get label => 'Fonte comunitaria esterna';
	@override String get short => 'Esterna';
}

// Path: hours.codes
class _Translations$hours$codes$it extends Translations$hours$codes$en {
	_Translations$hours$codes$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get mo => 'lun';
	@override String get tu => 'mar';
	@override String get we => 'mer';
	@override String get th => 'gio';
	@override String get fr => 'ven';
	@override String get sa => 'sab';
	@override String get su => 'dom';
	@override String get ph => 'festivi';
	@override String get sh => 'vacanze scolastiche';
	@override String get off => 'chiuso';
	@override String get closed => 'chiuso';
	@override String get sunrise => 'alba';
	@override String get sunset => 'tramonto';
}

// Path: hours.months
class _Translations$hours$months$it extends Translations$hours$months$en {
	_Translations$hours$months$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get jan => 'gen';
	@override String get feb => 'feb';
	@override String get mar => 'mar';
	@override String get apr => 'apr';
	@override String get may => 'mag';
	@override String get jun => 'giu';
	@override String get jul => 'lug';
	@override String get aug => 'ago';
	@override String get sep => 'set';
	@override String get oct => 'ott';
	@override String get nov => 'nov';
	@override String get dec => 'dic';
}

// Path: navigation.preview
class _Translations$navigation$preview$it extends Translations$navigation$preview$en {
	_Translations$navigation$preview$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String titleTo({required Object name}) => 'Verso ${name}';
	@override String get titlePoint => 'Punto sulla mappa';
	@override late final _Translations$navigation$preview$departure$it departure = _Translations$navigation$preview$departure$it._(_root);
	@override String get computing => 'Calcolo di un percorso per il tuo veicolo';
	@override String get start => 'Avvia';
	@override String get recommended => 'Consigliato';
	@override String alternative({required Object n}) => 'Alternativa ${n}';
	@override String get toll => 'Pedaggio';
	@override String get ferry => 'Traghetto';
	@override String get motorway => 'Autostrada';
	@override String get noWarnings => 'Nessun limite vicino alle dimensioni del tuo veicolo su questo percorso.';
	@override String warnings({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '1 limite da tenere d\'occhio',
		other: '${n} limiti da tenere d\'occhio',
	);
	@override String get vehicle => 'Il tuo veicolo';
	@override String vehicleTowing({required Object vehicle}) => '${vehicle}, con traino';
	@override String get editVehicle => 'Modifica';
	@override String cruise({required Object speed}) => 'Tempi calcolati a ${speed} max';
	@override String get avoid => 'Evita';
	@override String get avoidTolls => 'Pedaggi';
	@override String get avoidMotorways => 'Autostrade';
	@override String get avoidFerries => 'Traghetti';
	@override String get avoidUnpaved => 'Strade sterrate';
	@override String get roadbook => 'Indicazioni passo passo';
	@override String get roadbookShow => 'Mostra le indicazioni';
	@override String get roadbookHide => 'Nascondi le indicazioni';
	@override String dataOf({required Object date}) => 'Dati stradali del ${date}';
	@override String get attributionOsm => '© contributori di OpenStreetMap';
	@override String attributionIgn({required Object date}) => 'IGN, BD TOPO, edizione del ${date}';
	@override String get otherApps => 'Apri con…';
	@override String get back => 'Indietro';
	@override late final _Translations$navigation$preview$moved$it moved = _Translations$navigation$preview$moved$it._(_root);
}

// Path: navigation.stops
class _Translations$navigation$stops$it extends Translations$navigation$stops$en {
	_Translations$navigation$stops$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Tappe';
	@override String get add => 'Aggiungi come tappa';
	@override String addCost({required Object minutes}) => 'Aggiungi come tappa · +${minutes} min';
	@override String get addFree => 'Aggiungi come tappa · nessuna deviazione';
	@override String get quoting => 'Aggiungi come tappa · calcolo della deviazione';
	@override String get noRoute => 'Nessun percorso per il tuo veicolo passando da questo punto.';
	@override String get full => 'Al massimo cinque tappe.';
	@override String get goDirectly => 'Vai direttamente';
	@override String get openCard => 'Vedi la scheda';
	@override String get point => 'Punto sulla mappa';
	@override String get remove => 'Rimuovi la tappa';
	@override String get reorder => 'Trascina per cambiare l\'ordine';
	@override String get added => 'Tappa aggiunta';
	@override String get removed => 'Tappa rimossa';
	@override String get moved => 'Ordine delle tappe cambiato';
	@override String get destinationChanged => 'Nuova destinazione';
	@override String get failed => 'Non è stato possibile modificare il percorso.';
	@override String get noQuote => 'Non è stato possibile calcolare la deviazione.';
	@override String get offline => 'Nessuna rete per calcolare la deviazione.';
}

// Path: navigation.legs
class _Translations$navigation$legs$it extends Translations$navigation$legs$en {
	_Translations$navigation$legs$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get all => 'Tutto';
	@override String stop({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}';
	@override String stopSaid({required Object number, required Object name, required Object time, required Object distance}) => 'Tappa ${number}: ${name}, verso le ${time}, a ${distance}';
	@override String arrival({required Object name, required Object time}) => 'Destinazione · ${name} · ${time}';
	@override String arrivalSaid({required Object name, required Object time}) => 'Destinazione: ${name}, verso le ${time}';
	@override String remove({required Object number, required Object name}) => 'Rimuovi la tappa ${number}, ${name}';
}

// Path: navigation.fuel
class _Translations$navigation$fuel$it extends Translations$navigation$fuel$en {
	_Translations$navigation$fuel$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String price({required Object price}) => '${price} €/l';
	@override String withDetour({required Object price}) => '${price} €/l deviazione inclusa';
	@override String detour({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min';
	@override String get onRoute => 'sul percorso';
	@override String get open => 'Aperto';
	@override String get closed => 'Chiuso';
	@override String get unknownHours => 'Orari sconosciuti';
	@override String get add => 'Aggiungi';
	@override String get station => 'Distributore';
	@override String get empty => 'Nessun distributore con questo carburante vicino al percorso.';
	@override String get failed => 'Non è stato possibile caricare i distributori.';
	@override String get estimated => 'Deviazioni stimate in base alla distanza dal percorso.';
	@override String get attribution => 'Prezzi: Ministero dell\'Economia francese (data.economie.gouv.fr)';
	@override String minutesAgo({required Object n}) => '${n} min fa';
	@override String hoursAgo({required Object n}) => '${n} h fa';
	@override String daysAgo({required Object n}) => '${n} gg fa';
}

// Path: navigation.onTheWay
class _Translations$navigation$onTheWay$it extends Translations$navigation$onTheWay$en {
	_Translations$navigation$onTheWay$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Lungo il percorso';
	@override late final _Translations$navigation$onTheWay$categories$it categories = _Translations$navigation$onTheWay$categories$it._(_root);
	@override String fuelOfVehicle({required Object fuel}) => '${fuel}, secondo il tuo veicolo';
	@override String get otherFuel => 'Altro carburante';
	@override String get keepFuel => 'Salva come mio carburante';
	@override String fuelKept({required Object fuel}) => '${fuel} salvato per il tuo veicolo.';
	@override String get keepFuelFailed => 'Non è stato possibile salvare il carburante.';
	@override String get loading => 'Ricerca lungo il percorso';
	@override String get empty => 'Nessun risultato su questo percorso';
	@override String get emptyHint => 'Prova un\'altra categoria, o riapri l\'elenco più avanti lungo la strada.';
	@override String get failed => 'Non è stato possibile caricare l\'elenco.';
	@override String get offline => 'Nessuna rete: l\'elenco tornerà con la connessione.';
	@override String get rateLimited => 'Molte ricerche di seguito: riprova tra qualche minuto.';
	@override String nearNone({required Object distance}) => 'Niente nei prossimi ${distance}.';
	@override String further({required Object n}) => 'Più avanti (${n})';
	@override String get more => 'Mostra altro';
	@override String get moreFailed => 'Non è stato possibile caricare il resto.';
	@override String ahead({required Object distance}) => 'tra ${distance}';
	@override String offRoute({required Object distance}) => 'a ${distance} dal percorso';
	@override String get byTheRoad => 'a bordo strada';
	@override String addCost({required Object minutes}) => 'Aggiungi · +${minutes} min';
	@override String get addFree => 'Aggiungi · nessuna deviazione';
	@override String openAt({required Object time}) => 'Aperto al tuo passaggio, verso le ${time}';
	@override String closedAt({required Object time}) => 'Chiuso al tuo passaggio, verso le ${time}';
	@override String closedOpensAt({required Object time, required Object opens}) => 'Chiuso al tuo passaggio verso le ${time}, apre alle ${opens}';
	@override String perNight({required Object price}) => '${price} a notte';
	@override String photoFrom({required Object source}) => 'Foto: ${source}';
	@override String servicesList({required Object list}) => 'Servizi: ${list}';
	@override String get placesCredit => 'Luoghi: Lunaway e le fonti indicate su ogni scheda';
}

// Path: navigation.states
class _Translations$navigation$states$it extends Translations$navigation$states$en {
	_Translations$navigation$states$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get vehicleTitle => 'Che veicolo guidi?';
	@override String get vehicleHint => 'Il percorso evita ponti troppo bassi, vie troppo strette e strade vietate a un veicolo delle tue dimensioni. Indica altezza, larghezza, lunghezza e peso.';
	@override String vehicleMissing({required Object list}) => 'Dati mancanti: ${list}';
	@override String vehicleOutOfBounds({required Object list}) => 'Fuori dai valori accettati: ${list}';
	@override late final _Translations$navigation$states$dimension$it dimension = _Translations$navigation$states$dimension$it._(_root);
	@override String get describeVehicle => 'Descrivi il tuo veicolo';
	@override String get originTitle => 'Dove sei?';
	@override String get originHint => 'Lunaway ha bisogno della tua posizione per calcolare il percorso.';
	@override String get locate => 'Localizzami';
	@override String get offlineTitle => 'Nessuna connessione';
	@override String get offlineHint => 'I percorsi vengono calcolati sul server di Lunaway. Senza rete, «Apri con…» passa il viaggio a un\'app di navigazione che conserva le sue mappe.';
	@override String get rateLimitedTitle => 'Troppe richieste di percorso';
	@override String rateLimitedHint({required Object seconds}) => 'Riprova tra ${seconds} s.';
	@override String get unavailableTitle => 'Calcolo del percorso non disponibile';
	@override String get unavailableHint => 'Il servizio non è disponibile al momento. Riprova più tardi.';
	@override String get refusedTitle => 'Nessun percorso qui';
	@override String get refusedHint => 'Lunaway non è riuscito a calcolare un percorso per questa richiesta: controlla la destinazione, la lunghezza del tragitto e i dati del veicolo.';
	@override String get noSafeTitle => 'Nessun percorso sicuro per il tuo veicolo';
	@override String get noSafeHint => 'Ogni strada possibile passa da un limite che il tuo veicolo supera:';
	@override String get whatToDo => 'Cosa puoi fare';
	@override String checkVehicle({required Object height, required Object weight}) => 'Controlla i valori inseriti: ${height} di altezza, ${weight}.';
	@override String get pickOtherPoint => 'Scegli una destinazione prima dell\'ostacolo: tieni premuto sulla mappa.';
	@override String get noRouteTitle => 'Nessuna strada porta a questo punto';
	@override String get noRouteHint => 'Forse il punto si trova su una strada privata, o su un\'isola senza traghetto.';
	@override String get allowUnpaved => 'Le strade sterrate vengono evitate: consentile se la destinazione si trova su uno sterrato.';
	@override String get offNetworkTitle => 'Troppo lontano da una strada';
	@override String get offNetworkHint => 'Scegli una destinazione su una strada.';
}

// Path: navigation.noRoute
class _Translations$navigation$noRoute$it extends Translations$navigation$noRoute$en {
	_Translations$navigation$noRoute$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get originUnreachable => 'Il tuo veicolo non può partire da qui';
	@override String originUnreachableBy({required Object limit}) => 'Il tuo veicolo non può partire da qui: ${limit}';
	@override String get destinationUnreachable => 'Destinazione irraggiungibile per il tuo veicolo';
	@override String destinationUnreachableBy({required Object limit}) => 'Destinazione irraggiungibile per il tuo veicolo: ${limit}';
	@override String waypointUnreachable({required Object n}) => 'Tappa ${n} irraggiungibile per il tuo veicolo';
	@override String waypointUnreachableBy({required Object n, required Object limit}) => 'Tappa ${n} irraggiungibile per il tuo veicolo: ${limit}';
	@override String get blockedOnTheWay => 'Nessun passaggio per il tuo veicolo tra le tappe';
	@override String blockedOnTheWayBy({required Object limit}) => 'Nessun passaggio per il tuo veicolo tra le tappe: ${limit}';
	@override String get blockedHint => 'Ogni tappa è raggiungibile, ma tutte le strade che le collegano passano da un limite che il tuo veicolo supera.';
	@override String get notConnectedOrigin => 'Nessuna strada parte dalla tua posizione';
	@override String get notConnectedDestination => 'Nessuna strada porta alla destinazione';
	@override String notConnectedWaypoint({required Object n}) => 'Nessuna strada porta alla tappa ${n}';
	@override String get notConnectedTrip => 'Nessuna strada collega le tue tappe';
	@override String get notConnectedHint => 'Qualunque sia il veicolo: un\'isola senza traghetto per veicoli, o una strada chiusa al traffico.';
	@override String get outsideOrigin => 'La tua posizione è fuori dalla zona coperta dai percorsi';
	@override String get outsideDestination => 'Destinazione fuori dalla zona coperta dai percorsi';
	@override String outsideWaypoint({required Object n}) => 'Tappa ${n} fuori dalla zona coperta dai percorsi';
	@override String outsideHint({required Object countries}) => 'Lunaway calcola i percorsi in questi paesi: ${countries}.';
	@override String get outsideHintUnknown => 'Lunaway non calcola ancora percorsi in questo paese.';
	@override String get noRoadOrigin => 'La tua posizione è troppo lontana da una strada';
	@override String get noRoadDestination => 'Destinazione troppo lontana da una strada';
	@override String noRoadWaypoint({required Object n}) => 'Tappa ${n} troppo lontana da una strada';
	@override String get noRoadHint => 'Nessuna strada percorribile dal tuo veicolo entro 5 km da questo punto.';
	@override String get tooLong => 'Tragitto troppo lungo';
	@override String tooLongHint({required Object trip, required Object max}) => '${trip} in linea d\'aria da tappa a tappa: Lunaway calcola tragitti di ${max} al massimo.';
	@override String vehicleValue({required Object value}) => 'Il tuo veicolo: ${value}';
	@override late final _Translations$navigation$noRoute$limit$it limit = _Translations$navigation$noRoute$limit$it._(_root);
	@override String get editVehicle => 'Modifica il veicolo';
	@override String get allowUnpaved => 'Consenti le strade sterrate';
	@override String removeStop({required Object n}) => 'Rimuovi la tappa ${n}';
	@override String removeStopNamed({required Object name}) => 'Rimuovi la tappa «${name}»';
	@override String get placesAround => 'Vedi i luoghi intorno alla destinazione';
	@override String get moveDestination => 'Oppure scegli un\'altra destinazione: tieni premuto sulla mappa, poi «Vai direttamente».';
	@override String get moveStop => 'Per un\'altra tappa: ingrandisci bene la mappa e tocca il punto, oppure tieni premuto, poi «Aggiungi come tappa».';
	@override String get moveOrigin => 'La partenza è la tua posizione: raggiungi una strada che il tuo veicolo può percorrere, poi riprova.';
	@override String get pickInside => 'Scegli una destinazione in uno di questi paesi.';
	@override String get shorter => 'Scegli una destinazione più vicina, oppure dividi il viaggio in più tappe.';
}

// Path: navigation.ferry
class _Translations$navigation$ferry$it extends Translations$navigation$ferry$en {
	_Translations$navigation$ferry$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String title({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Traversata in traghetto',
		other: '${n} traversate in traghetto',
	);
	@override String get unnamed => 'Traghetto';
	@override String named({required Object name}) => 'Traghetto ${name}';
	@override String ports({required Object ports}) => 'Porti: ${ports}';
	@override String countries({required Object from, required Object to}) => 'Imbarco: ${from} · Sbarco: ${to}';
	@override String country({required Object country}) => 'Paese: ${country}';
	@override String where({required Object distance, required Object sea, required Object duration}) => 'A ${distance} dalla partenza · ${sea} in mare, circa ${duration}';
	@override String get needed => 'La destinazione non si raggiunge senza traghetto: il percorso ne prende uno, anche se hai scelto di evitare i traghetti.';
}

// Path: navigation.warning
class _Translations$navigation$warning$it extends Translations$navigation$warning$en {
	_Translations$navigation$warning$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$warning$lowClearance$it lowClearance = _Translations$navigation$warning$lowClearance$it._(_root);
	@override String get unknownClearance => 'Passaggio basso, altezza sconosciuta';
	@override String narrow({required Object limit}) => 'Strettoia ${limit}';
	@override String tooLong({required Object limit}) => 'Lunghezza massima ${limit}';
	@override String tooHeavy({required Object limit}) => 'Peso massimo ${limit}';
	@override String axleLoad({required Object limit}) => 'Carico massimo per asse ${limit}';
	@override String get motorhomeBan => 'Vietato ai camper';
	@override String get trailerBan => 'Vietato ai rimorchi';
	@override String goodsVehicleWeight({required Object limit}) => 'Peso massimo per mezzi pesanti ${limit}';
	@override String yours({required Object value}) => 'il tuo veicolo: ${value}';
	@override String fromStart({required Object distance}) => 'a ${distance} dalla partenza';
	@override String ahead({required Object distance}) => 'tra ${distance}';
	@override String get disputed => 'le fonti non concordano, vale il valore più basso';
	@override String get goodsOnly => 'riguarda i mezzi pesanti, controlla i cartelli';
	@override String get osm => 'OpenStreetMap';
	@override String get ign => 'IGN BD TOPO';
	@override String get community => 'Segnalazione Lunaway';
	@override String get dialog => 'Ordinanza di circolazione (DiaLog)';
	@override late final _Translations$navigation$warning$localAccess$it localAccess = _Translations$navigation$warning$localAccess$it._(_root);
}

// Path: navigation.roadEvents
class _Translations$navigation$roadEvents$it extends Translations$navigation$roadEvents$en {
	_Translations$navigation$roadEvents$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Lavori e chiusure';
	@override String get none => 'Nessun lavoro né chiusura noti su questo percorso.';
	@override String get stale => 'Lavori e chiusure: le fonti non sono aggiornate di recente.';
	@override String avoided({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Percorso calcolato evitando una chiusura: ${names}',
		other: 'Percorso calcolato evitando ${n} chiusure: ${names}',
	);
	@override String atDistance({required Object distance}) => 'a ${distance} dalla partenza';
	@override String more({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'E un altro sul percorso',
		other: 'E altri ${n} sul percorso',
	);
	@override String get classClosure => 'Strada chiusa';
	@override String get classWorks => 'Lavori';
	@override String get classLaneRestriction => 'Corsie ridotte';
	@override String get classVehicleLimit => 'Limite di dimensioni';
	@override String get classDetour => 'Deviazione segnalata';
	@override String get reasonUnmatched => 'posizione incerta, forse sul percorso';
	@override String get reasonStale => 'fonte non aggiornata di recente';
	@override String get reasonOutsideHours => 'fuori dall\'orario previsto';
	@override String get reasonGoodsVehicles => 'per i mezzi pesanti';
	@override String get reasonUnconfirmed => 'segnalato da un solo viaggiatore';
	@override String get reasonAged => 'segnalazione vecchia';
	@override String get reasonInside => 'il percorso inizia o finisce al suo interno';
	@override String get reasonNearLimit => 'con poco margine';
	@override String get reasonOverLimit => 'il tuo veicolo supera il limite';
}

// Path: navigation.marks
class _Translations$navigation$marks$it extends Translations$navigation$marks$en {
	_Translations$navigation$marks$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get legend => 'Legenda';
	@override String get legendHide => 'Chiudi la legenda';
	@override String get kindOrigin => 'Partenza';
	@override String get kindDestination => 'Destinazione';
	@override String get kindStop => 'Tappa';
	@override String get kindClosure => 'Strada chiusa';
	@override String get kindWorks => 'Lavori';
	@override String get kindLanes => 'Corsie ridotte';
	@override String get kindClearance => 'Altezza limitata';
	@override String get kindWeight => 'Peso limitato';
	@override String get kindLimit => 'Altro limite (larghezza, lunghezza, divieto)';
	@override String get kindFuel => 'Distributore';
	@override String get kindPlace => 'Luogo vicino al percorso';
	@override String get groupLegend => 'Indicatori vicini raggruppati';
	@override String get zoneLegend => 'Zona di pericolo';
	@override String zonesFrom({required Object source, required Object date}) => 'Zone di pericolo: ${source}, elenco del ${date}';
	@override String group({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} indicatore',
		other: '${n} indicatori',
	);
	@override String get groupHint => 'Ingrandisci per vederli uno per uno';
	@override String count({required Object kind, required Object n}) => '${kind}: ${n}';
	@override String stop({required Object n}) => 'Tappa ${n}';
	@override String get origin => 'Punto di partenza';
	@override String get nearRoute => 'Vicino al percorso';
	@override String get avoided => 'Il percorso lo evita';
	@override String get blocking => 'Blocca ogni percorso';
	@override String get showInList => 'Vedi nell\'elenco';
	@override String get showAll => 'Mostra tutto';
	@override String get onMap => 'mostra sulla mappa';
	@override String price({required Object price}) => '${price} €';
	@override String get kindCamera => 'Autovelox';
	@override String cameras({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} autovelox',
		other: '${n} autovelox',
	);
	@override String camerasFrom({required Object source, required Object date}) => 'Autovelox: ${source}, elenco del ${date}';
	@override String bothFrom({required Object source, required Object date}) => 'Autovelox e zone di pericolo: ${source}, elenco del ${date}';
	@override String sectionLength({required Object distance}) => 'Tratto di ${distance}';
	@override String get cameraDirection => 'Controlla il tuo senso di marcia';
}

// Path: navigation.guidance
class _Translations$navigation$guidance$it extends Translations$navigation$guidance$en {
	_Translations$navigation$guidance$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get then => 'Poi';
	@override String arrival({required Object time}) => 'Arrivo alle ${time}';
	@override String get offRoute => 'Fuori percorso';
	@override String get rerouting => 'Ricerca di un nuovo percorso';
	@override String get rerouted => 'Nuovo percorso';
	@override String reroutedLonger({required Object minutes}) => 'Nuovo percorso, ${minutes} min in più';
	@override String get rerouteOffline => 'Nessuna rete per un nuovo percorso: torna sul percorso';
	@override String get rerouteFailed => 'Nessun nuovo percorso: torna sul percorso';
	@override String closureAhead({required Object distance}) => 'Strada chiusa tra ${distance}: ricerca di un\'alternativa';
	@override String noDetour({required Object distance}) => 'Strada chiusa tra ${distance}: nessuna alternativa';
	@override String eventAhead({required Object distance}) => 'Lavori tra ${distance}';
	@override String eventClosure({required Object distance}) => 'Strada chiusa tra ${distance}';
	@override String eventLimit({required Object distance}) => 'Lavori tra ${distance}: dimensioni limitate';
	@override String eventSource({required Object source, required Object time}) => '${source}, dati delle ${time}';
	@override String eventSourceOn({required Object source, required Object day, required Object time}) => '${source}, dati del ${day} alle ${time}';
	@override String avoidedClosures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: 'Percorso calcolato evitando una chiusura',
		other: 'Percorso calcolato evitando ${n} chiusure',
	);
	@override String roadEventAhead({required Object what, required Object distance}) => '${what} tra ${distance}';
	@override String closureOffline({required Object distance}) => 'Strada chiusa tra ${distance}: nessuna rete per cercare un\'alternativa';
	@override String closureFailed({required Object distance}) => 'Strada chiusa tra ${distance}: ancora nessuna alternativa';
	@override late final _Translations$navigation$guidance$voiceMode$it voiceMode = _Translations$navigation$guidance$voiceMode$it._(_root);
	@override String get overview => 'Tutto il percorso';
	@override String get recenter => 'Ricentra';
	@override String get end => 'Termina';
	@override String get endTitle => 'Terminare la navigazione?';
	@override String get endConfirm => 'Termina';
	@override String get endKeep => 'Continua';
	@override String get stopTitle => 'Interrompere la navigazione?';
	@override String get stopConfirm => 'Interrompi';
	@override String get arrivedTitle => 'Sei arrivato a destinazione';
	@override String get done => 'Termina';
	@override String get speed => 'Velocità';
	@override String get limit => 'Limite';
	@override String noVoice({required Object language}) => 'Nessuna voce in ${language} su questo dispositivo: istruzioni solo sullo schermo.';
	@override String missingVoice({required Object language}) => 'La voce in ${language} non è ancora scaricata.';
	@override String get installVoice => 'Installa';
	@override String get voiceSettingsIos => 'Impostazioni, Accessibilità, Contenuto letto ad alta voce, Voci';
	@override String get notificationTitle => 'Lunaway ti sta guidando';
	@override String get notificationText => 'La navigazione continua anche a schermo spento.';
	@override String get notificationChannel => 'Navigazione';
	@override String get unavailable => 'Non è stato possibile avviare la navigazione su questo dispositivo.';
	@override late final _Translations$navigation$guidance$notificationWhy$it notificationWhy = _Translations$navigation$guidance$notificationWhy$it._(_root);
	@override String get positionLost => 'Posizione non disponibile: verifica che la localizzazione del dispositivo sia attiva per Lunaway.';
	@override String positionStale({required Object minutes}) => 'Ultima posizione ricevuta ${minutes} min fa: l\'orario di arrivo si basa su questa.';
	@override String get limitEstimated => 'Limite stimato';
	@override String get overLimit => 'oltre il limite';
	@override String enforcementSource({required Object source, required Object date}) => '${source}, elenco del ${date}';
	@override String get demoDrive => 'Viaggio simulato: dimostrazione senza GPS';
	@override late final _Translations$navigation$guidance$places$it places = _Translations$navigation$guidance$places$it._(_root);
}

// Path: navigation.voice
class _Translations$navigation$voice$it extends Translations$navigation$voice$en {
	_Translations$navigation$voice$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get rerouting => 'Ricalcolo del percorso.';
	@override String get rerouted => 'Nuovo percorso.';
	@override String reroutedLonger({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(minutes,
		one: 'Nuovo percorso, un minuto in più.',
		other: 'Nuovo percorso, ${minutes} minuti in più.',
	);
	@override late final _Translations$navigation$voice$moved$it moved = _Translations$navigation$voice$moved$it._(_root);
	@override String closureAhead({required Object distance}) => 'Strada chiusa tra ${distance}. Ricerca di un percorso alternativo.';
	@override String noDetour({required Object distance}) => 'Strada chiusa tra ${distance}. Non ci sono alternative.';
	@override String clearance({required Object distance, required Object height}) => 'Attenzione, tra ${distance}, passaggio basso di ${height}.';
	@override String unknownClearance({required Object distance}) => 'Attenzione, tra ${distance}, passaggio basso di altezza sconosciuta.';
	@override String narrow({required Object distance, required Object width}) => 'Attenzione, tra ${distance}, strettoia larga ${width}.';
	@override String limit({required Object distance, required Object what}) => 'Attenzione, tra ${distance}, ${what}.';
	@override String get arrived => 'Sei arrivato a destinazione.';
	@override String metres({required Object n}) => '${n} metri';
	@override String kilometres({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count,
		one: 'un chilometro',
		other: '${n} chilometri',
	);
	@override String feet({required Object n}) => '${n} piedi';
	@override String miles({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count,
		one: 'un miglio',
		other: '${n} miglia',
	);
	@override String size({required num count, required Object cm, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count,
		one: 'un metro e ${cm}',
		other: '${metres} metri e ${cm}',
	);
	@override String sizeWhole({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count,
		one: 'un metro',
		other: '${metres} metri',
	);
	@override String overSpeed({required Object limit}) => 'Limite di velocità ${limit}.';
	@override String dangerZone({required Object distance}) => 'Zona di pericolo tra ${distance}.';
	@override String get inDangerZone => 'Zona di pericolo.';
	@override late final _Translations$navigation$voice$localAccess$it localAccess = _Translations$navigation$voice$localAccess$it._(_root);
	@override late final _Translations$navigation$voice$roadEvent$it roadEvent = _Translations$navigation$voice$roadEvent$it._(_root);
	@override String get positionLost => 'Posizione non disponibile. Controlla la localizzazione del dispositivo.';
	@override String tonnes({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count,
		one: 'una tonnellata',
		other: '${n} tonnellate',
	);
	@override late final _Translations$navigation$voice$camera$it camera = _Translations$navigation$voice$camera$it._(_root);
}

// Path: navigation.units
class _Translations$navigation$units$it extends Translations$navigation$units$en {
	_Translations$navigation$units$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String ft({required Object n}) => '${n} ft';
	@override String mi({required Object n}) => '${n} mi';
	@override String get kmh => 'km/h';
	@override String get mph => 'mph';
	@override String hoursMinutes({required Object h, required Object m}) => '${h} h ${m} min';
	@override String minutes({required Object m}) => '${m} min';
}

// Path: navigation.settings
class _Translations$navigation$settings$it extends Translations$navigation$settings$en {
	_Translations$navigation$settings$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Navigazione';
	@override String get avoidTitle => 'Evita per impostazione predefinita';
	@override String get voice => 'Voce della navigazione';
	@override String get voiceFull => 'Completa';
	@override String get voiceAlerts => 'Avvisi';
	@override String get voiceMuted => 'Disattivata';
	@override String get voiceFullHint => 'Le indicazioni e gli avvisi, con la voce del dispositivo.';
	@override String get voiceAlertsHint => 'Solo autovelox e zone di pericolo, chiusure, lavori e limiti di dimensioni lungo il percorso, e cambi di percorso, dopo un breve segnale acustico.';
	@override String get voiceMutedHint => 'Nessun suono: indicazioni e avvisi sullo schermo.';
	@override String get units => 'Distanze';
	@override String get metric => 'Chilometri';
	@override String get imperial => 'Miglia';
	@override String get speedLimit => 'Limite di velocità';
	@override String get speedLimitHint => 'Mostra il limite valido per il tuo veicolo accanto alla velocità; se è stimato appare in grigio.';
	@override String get speedSound => 'Avviso vocale del limite';
	@override String get speedSoundHint => 'Un avviso quando superi il limite, con la voce completa. Autovelox e zone di pericolo seguono la voce della navigazione.';
	@override String get exactFrance => 'Posizione esatta degli autovelox in Francia';
	@override String get exactFranceHint => 'In Francia, possedere un dispositivo che segnala la posizione degli autovelox è punito con una multa di 1.500 € e la decurtazione di 6 punti (Code de la route, art. R413-15).';
}

// Path: navigation.enforcement
class _Translations$navigation$enforcement$it extends Translations$navigation$enforcement$en {
	_Translations$navigation$enforcement$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get fixed => 'Autovelox fisso';
	@override String get redLight => 'Telecamera al semaforo';
	@override String get levelCrossing => 'Telecamera al passaggio a livello';
	@override String get section => 'Tutor';
	@override String get zone => 'Zona di pericolo';
	@override String average({required Object limit}) => 'media ${limit}';
	@override String get averageLabel => 'media';
	@override String remaining({required Object distance}) => 'per altri ${distance}';
	@override String yourAverage({required Object speed}) => 'la tua media ${speed}';
	@override String get zoneEnd => 'Fine della zona di pericolo';
	@override String get sectionEnd => 'Fine del controllo della velocità media';
	@override String ruleOff({required Object country}) => '${country}: nessun avviso autovelox';
	@override String ruleZones({required Object country}) => '${country}: zone di pericolo';
	@override String ruleExact({required Object country}) => '${country}: autovelox';
	@override String ahead({required Object what, required Object distance}) => '${what} tra ${distance}';
	@override String limit({required Object limit}) => 'limite ${limit}';
	@override String averageLimit({required Object limit}) => 'media massima ${limit}';
}

// Path: vehicle.types
class _Translations$vehicle$types$it extends Translations$vehicle$types$en {
	_Translations$vehicle$types$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Furgonato';
	@override String get lowProfile => 'Semintegrale';
	@override String get overcab => 'Mansardato';
	@override String get integrated => 'Motorhome';
}

// Path: vehicle.towing
class _Translations$vehicle$towing$it extends Translations$vehicle$towing$en {
	_Translations$vehicle$towing$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get none => 'Nessuno';
	@override String get car => 'Un\'auto';
	@override String get trailer => 'Un rimorchio';
}

// Path: translation.from
class _Translations$translation$from$it extends Translations$translation$from$en {
	_Translations$translation$from$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Tradotto automaticamente dal francese';
	@override String get en => 'Tradotto automaticamente dall\'inglese';
	@override String get de => 'Tradotto automaticamente dal tedesco';
	@override String get es => 'Tradotto automaticamente dallo spagnolo';
	@override String get it => 'Tradotto automaticamente dall\'italiano';
	@override String get nl => 'Tradotto automaticamente dall\'olandese';
	@override String unknown({required Object language}) => 'Tradotto automaticamente (lingua originale: ${language})';
}

// Path: account.levelOpens
class _Translations$account$levelOpens$it extends Translations$account$levelOpens$en {
	_Translations$account$levelOpens$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get l0 => 'Puoi valutare i luoghi, confermare che ci sono ancora, segnalare un problema e sincronizzare i tuoi preferiti.';
	@override String get l1 => 'Puoi anche scrivere recensioni, aggiungere foto e proporre modifiche ai luoghi.';
	@override String get l2 => 'Puoi anche aggiungere luoghi.';
	@override String get l3 => 'Le tue modifiche ai luoghi vengono applicate senza revisione.';
	@override String get l4 => 'Partecipi alla moderazione.';
}

// Path: account.requirement
class _Translations$account$requirement$it extends Translations$account$requirement$en {
	_Translations$account$requirement$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String age({required Object needed, required Object current}) => 'Account creato da almeno ${needed} giorni (${current} finora)';
	@override String confirmations({required Object needed, required Object current}) => '${needed} conferme di luoghi diversi (${current} finora)';
	@override String contributions({required Object needed, required Object current}) => '${needed} contributi pubblicati (${current} finora)';
	@override String activeDays({required Object needed, required Object current}) => '${needed} giorni di attività (${current} finora)';
	@override String get noRemoval => 'Nessun contributo rimosso dalla moderazione';
	@override String get sponsor => 'La garanzia di un membro di livello 2';
	@override String get nomination => 'Una nomina da parte della moderazione';
	@override String get administration => 'Una designazione da parte del team di Lunaway';
}

// Path: deletion.gone
class _Translations$deletion$gone$it extends Translations$deletion$gone$en {
	_Translations$deletion$gone$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get identity => 'Il tuo pseudonimo e le chiavi dei tuoi dispositivi';
	@override String get sessions => 'Le tue sessioni e il tuo codice di recupero';
	@override String get lists => 'Le tue liste di preferiti sincronizzate e gli autori che hai nascosto';
	@override String get photos => 'Le tue foto, le tue valutazioni senza testo e le tue segnalazioni';
	@override String get pending => 'Le tue proposte in attesa di revisione';
}

// Path: mine.status
class _Translations$mine$status$it extends Translations$mine$status$en {
	_Translations$mine$status$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get published => 'Pubblicato';
	@override String get pending => 'In revisione';
	@override String get hidden => 'Nascosto dopo alcune segnalazioni';
	@override String get removed => 'Rimosso dalla moderazione';
}

// Path: mine.submission
class _Translations$mine$submission$it extends Translations$mine$submission$en {
	_Translations$mine$submission$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get proposed => 'In attesa di revisione';
	@override String get accepted => 'Accettato';
	@override String get applied => 'Sulla mappa';
	@override String get rejected => 'Rifiutato';
	@override String get withdrawn => 'Ritirato';
}

// Path: outbox.kind
class _Translations$outbox$kind$it extends Translations$outbox$kind$en {
	_Translations$outbox$kind$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String rate({required Object stars}) => 'Valutazione di ${stars} su 5';
	@override String get review => 'Recensione';
	@override String get deleteReview => 'Eliminazione di una recensione';
	@override String confirm({required Object status}) => 'Conferma: ${status}';
	@override String get deleteConfirmation => 'Eliminazione di una conferma';
	@override String reportIssue({required Object kind}) => 'Problema segnalato: ${kind}';
	@override String get deleteIssueReport => 'Eliminazione di una segnalazione';
	@override String get reportContent => 'Segnalazione ai moderatori';
	@override String addPlace({required Object name}) => 'Nuovo luogo: ${name}';
	@override String get editPlace => 'Modifica di un luogo';
	@override String get deletePlaceSubmission => 'Ritiro di un luogo proposto';
	@override String get photo => 'Foto';
	@override String get deletePhoto => 'Eliminazione di una foto';
	@override String get mute => 'Nascondere un autore';
	@override String get unmute => 'Mostrare di nuovo un autore';
	@override String get poiThere => 'Ancora lì: un negozio o un servizio';
	@override String get poiGone => 'Non c\'è più: un negozio o un servizio';
	@override String get addVendingMachine => 'Nuovo distributore automatico';
	@override String get deletePoiConfirmation => 'Eliminazione di una risposta su un negozio o un servizio';
	@override String reportRoadEvent({required Object kind}) => 'Segnalazione stradale: ${kind}';
	@override String get clearRoadEvent => 'Fine di una segnalazione stradale';
}

// Path: outbox.error
class _Translations$outbox$error$it extends Translations$outbox$error$en {
	_Translations$outbox$error$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get forbidden => 'Rifiutato: il tuo livello non lo consente ancora.';
	@override String get notFound => 'Rifiutato: il luogo o il contenuto non esiste più.';
	@override String get invalid => 'Rifiutato: controlla il testo (lunghezza, link, recapiti).';
	@override String get unreadablePhoto => 'Foto rifiutata: illeggibile, o già inviata.';
	@override String get photoTooLarge => 'Foto rifiutata: troppo pesante.';
	@override String get placeRefused => 'Il nuovo luogo di questa foto è stato rifiutato.';
	@override String get fileLost => 'La foto non è più sul dispositivo.';
	@override String get otherAccount => 'Preparato per un altro account: non verrà inviato.';
	@override String get other => 'Rifiutato dal server.';
	@override String get duplicate => 'Rifiutato: lo stesso distributore automatico è già indicato entro 25 m.';
}

// Path: confirmSheet.status
class _Translations$confirmSheet$status$it extends Translations$confirmSheet$status$en {
	_Translations$confirmSheet$status$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get stillOk => 'c\'è ancora';
	@override String get closed => 'chiuso';
	@override String get changed => 'cambiato';
}

// Path: issueSheet.kind
class _Translations$issueSheet$kind$it extends Translations$issueSheet$kind$en {
	_Translations$issueSheet$kind$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Pernottamento ora vietato';
	@override String get serviceBroken => 'Servizio guasto';
	@override String get noAccess => 'Accesso impossibile';
	@override String get danger => 'Pericolo';
}

// Path: issueSheet.hint
class _Translations$issueSheet$hint$it extends Translations$issueSheet$hint$en {
	_Translations$issueSheet$hint$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Un cartello, un\'ordinanza comunale, un controllo della polizia';
	@override String get serviceBroken => 'Colonnina, acqua, scarico o corrente fuori servizio';
	@override String get noAccess => 'Una sbarra, lavori, una strada chiusa';
	@override String get danger => 'Furti, aggressioni, terreno instabile';
}

// Path: reportSheet.reason
class _Translations$reportSheet$reason$it extends Translations$reportSheet$reason$en {
	_Translations$reportSheet$reason$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get spam => 'Pubblicità o ripetizioni';
	@override String get offensive => 'Offensivo, che incita all\'odio o scioccante';
	@override String get wrong => 'Falso o fuorviante';
	@override String get privacy => 'Mostra o nomina una persona, una targa, un indirizzo privato';
	@override String get other => 'Altro motivo';
}

// Path: poi.category
class _Translations$poi$category$it extends Translations$poi$category$en {
	_Translations$poi$category$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get groceries => 'Spesa';
	@override String get vending => 'Distributori automatici';
	@override String get water => 'Acqua e scarico';
	@override String get fuel => 'Carburante ed energia';
	@override String get health => 'Salute';
	@override String get services => 'Servizi';
	@override String get food => 'Ristoranti e bar';
	@override String get sights => 'Da vedere';
}

// Path: poi.kind
class _Translations$poi$kind$it extends Translations$poi$kind$en {
	_Translations$poi$kind$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get supermarket => 'Supermercato';
	@override String get convenience => 'Minimarket';
	@override String get bakery => 'Panetteria';
	@override String get butcher => 'Macelleria';
	@override String get greengrocer => 'Fruttivendolo';
	@override String get farmShop => 'Vendita diretta in fattoria';
	@override String get marketplace => 'Mercato';
	@override String get vendingPizza => 'Distributore di pizza';
	@override String get vendingBread => 'Distributore di pane';
	@override String get vendingFarmProducts => 'Distributore di prodotti agricoli';
	@override String get vendingEggsMilk => 'Distributore di uova e latte';
	@override String get vendingIce => 'Distributore di ghiaccio';
	@override String get vendingOther => 'Distributore automatico di alimenti';
	@override String get drinkingWater => 'Acqua potabile';
	@override String get waterPoint => 'Punto acqua';
	@override String get dumpStation => 'Punto di scarico';
	@override String get toilets => 'Bagni';
	@override String get shower => 'Docce';
	@override String get fuelStation => 'Distributore';
	@override String get evCharging => 'Colonnina di ricarica';
	@override String get gasBottles => 'Bombole del gas';
	@override String get pharmacy => 'Farmacia';
	@override String get doctor => 'Medico';
	@override String get hospital => 'Ospedale';
	@override String get veterinary => 'Veterinario';
	@override String get laundry => 'Lavanderia';
	@override String get atm => 'Bancomat';
	@override String get postOffice => 'Ufficio postale';
	@override String get touristOffice => 'Ufficio turistico';
	@override String get recyclingCentre => 'Isola ecologica';
	@override String get carRepair => 'Officina';
	@override String get carWash => 'Autolavaggio';
	@override String get motorhomeShop => 'Concessionaria e officina camper';
	@override String get outdoorShop => 'Negozio di campeggio e outdoor';
	@override String get restaurant => 'Ristorante';
	@override String get cafe => 'Bar';
	@override String get fastFood => 'Fast food';
	@override String get viewpoint => 'Punto panoramico';
	@override String get attraction => 'Attrazione';
	@override String get museum => 'Museo';
}

// Path: poi.vendingSells
class _Translations$poi$vendingSells$it extends Translations$poi$vendingSells$en {
	_Translations$poi$vendingSells$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Pane';
	@override String get farmProducts => 'Prodotti agricoli';
	@override String get eggsMilk => 'Uova e latte';
	@override String get ice => 'Ghiaccio';
}

// Path: poi.vendingChip
class _Translations$poi$vendingChip$it extends Translations$poi$vendingChip$en {
	_Translations$poi$vendingChip$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Distributori di pizza';
	@override String get bread => 'Distributori di pane';
	@override String get farmProducts => 'Distributori di prodotti agricoli';
	@override String get eggsMilk => 'Distributori di uova e latte';
	@override String get ice => 'Distributori di ghiaccio';
}

// Path: poi.fuel
class _Translations$poi$fuel$it extends Translations$poi$fuel$en {
	_Translations$poi$fuel$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get diesel => 'Gasolio';
	@override String get sp95 => 'Benzina 95';
	@override String get e10 => 'Benzina E10';
	@override String get sp98 => 'Benzina 98';
	@override String get e85 => 'E85';
	@override String get lpg => 'GPL';
}

// Path: poi.product
class _Translations$poi$product$it extends Translations$poi$product$en {
	_Translations$poi$product$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Pane';
	@override String get eggs => 'Uova';
	@override String get milk => 'Latte';
	@override String get cheese => 'Formaggio';
	@override String get meat => 'Carne';
	@override String get vegetables => 'Verdura';
	@override String get fruit => 'Frutta';
	@override String get honey => 'Miele';
	@override String get ice => 'Ghiaccio';
	@override String get potatoes => 'Patate';
	@override String get food => 'Alimentari';
}

// Path: poi.payment
class _Translations$poi$payment$it extends Translations$poi$payment$en {
	_Translations$poi$payment$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get cash => 'Contanti';
	@override String get coins => 'Monete';
	@override String get notes => 'Banconote';
	@override String get cards => 'Carta';
	@override String get contactless => 'Contactless';
	@override String get app => 'App';
}

// Path: poi.add
class _Translations$poi$add$it extends Translations$poi$add$en {
	_Translations$poi$add$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Un distributore automatico qui?';
	@override String get hint => 'Scegli cosa vende: verrà aggiunto alla mappa di tutti i viaggiatori.';
	@override String get pizza => 'Pizza';
	@override String get bread => 'Pane';
	@override String get other => 'Altri alimenti';
	@override String get gate => 'Aggiunta di un distributore automatico';
	@override String get sent => 'Grazie: il distributore appare sulla mappa entro pochi minuti.';
	@override String get duplicateTitle => 'Già sulla mappa';
	@override String get duplicateBody => 'Un distributore dello stesso tipo è già indicato entro 25 m. C\'è ancora?';
	@override String get duplicateThere => 'Sì, c\'è ancora';
	@override String get duplicateGone => 'No, non c\'è più';
}

// Path: poi.cheapest
class _Translations$poi$cheapest$it extends Translations$poi$cheapest$en {
	_Translations$poi$cheapest$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'I più economici vicino a me';
	@override String get show => 'I più economici qui intorno';
	@override String get zoomIn => 'Ingrandisci per confrontare i prezzi dei distributori.';
	@override String get none => 'Nessun distributore sulla mappa vende questo carburante.';
	@override String get noneHint => 'Sposta la mappa o scegli un altro carburante.';
	@override String get error => 'Non è stato possibile caricare i prezzi dei distributori.';
}

// Path: poi.trend
class _Translations$poi$trend$it extends Translations$poi$trend$en {
	_Translations$poi$trend$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String title({required Object fuel}) => '${fuel}: prezzi degli ultimi giorni';
	@override String get none => 'Lunaway non ha ancora visto un prezzo di questo carburante qui.';
	@override String get failed => 'Al momento non è stato possibile leggere i prezzi degli ultimi giorni.';
	@override String get week => 'Ultimi 7 giorni:';
	@override String get month => 'Ultimi 30 giorni:';
	@override String range({required Object low, required Object high}) => 'da ${low} a ${high}';
	@override String span({required Object range, required Object move}) => '${range}, ${move}';
	@override String get oneDay => 'un solo giorno rilevato';
	@override String get steady => 'stabile';
	@override String down({required Object amount}) => 'in calo di ${amount}';
	@override String up({required Object amount}) => 'in aumento di ${amount}';
	@override String since({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n,
		one: '${n} giorno con prezzi rilevati da Lunaway dal ${date}; i giorni senza rilevazione restano vuoti',
		other: '${n} giorni con prezzi rilevati da Lunaway dal ${date}; i giorni senza rilevazione restano vuoti',
	);
}

// Path: poi.vehicles
class _Translations$poi$vehicles$it extends Translations$poi$vehicles$en {
	_Translations$poi$vehicles$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get motorhomeYes => 'Accetta camper';
	@override String get motorhomeNo => 'Camper non ammessi';
	@override String get hgvYes => 'Accetta mezzi pesanti';
	@override String get hgvNo => 'Mezzi pesanti non ammessi';
	@override String maxHeight({required Object height}) => 'Altezza massima: ${height}';
}

// Path: roadReport.kinds
class _Translations$roadReport$kinds$it extends Translations$roadReport$kinds$en {
	_Translations$roadReport$kinds$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get closure => 'Strada chiusa';
	@override String get works => 'Lavori stradali';
	@override String get narrowPassage => 'Strettoia';
	@override String get lowClearance => 'Altezza limitata';
	@override String get other => 'Problema sulla strada';
}

// Path: navigation.preview.departure
class _Translations$navigation$preview$departure$it extends Translations$navigation$preview$departure$en {
	_Translations$navigation$preview$departure$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Partenza';
	@override String from({required Object name}) => 'Partenza: ${name}';
	@override String get myPosition => 'la mia posizione';
	@override String get myPositionChoice => 'La mia posizione';
	@override String get change => 'Cambia';
	@override String get choose => 'Scegli il punto di partenza';
	@override String get searchHint => 'Un luogo, un comune, un indirizzo';
	@override String get guidanceFromPosition => 'La navigazione parte sempre dalla tua posizione, non dal punto di partenza scelto.';
	@override String get fromMyPosition => 'Usa la mia posizione';
}

// Path: navigation.preview.moved
class _Translations$navigation$preview$moved$it extends Translations$navigation$preview$moved$en {
	_Translations$navigation$preview$moved$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String origin({required Object distance}) => 'Punto di partenza spostato di ${distance} verso la strada accessibile più vicina';
	@override String destination({required Object distance}) => 'Destinazione spostata di ${distance} verso la strada accessibile più vicina';
	@override String stop({required Object n, required Object distance}) => 'Tappa ${n} spostata di ${distance} verso la strada accessibile più vicina';
}

// Path: navigation.onTheWay.categories
class _Translations$navigation$onTheWay$categories$it extends Translations$navigation$onTheWay$categories$en {
	_Translations$navigation$onTheWay$categories$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get fuel => 'Carburante';
	@override String get sleep => 'Dormire';
	@override String get water => 'Acqua e scarico';
	@override String get groceries => 'Spesa';
	@override String get bakeries => 'Panetterie';
	@override String get toilets => 'Bagni, docce';
	@override String get health => 'Salute';
	@override String get services => 'Servizi';
	@override String get charging => 'Ricarica';
	@override String get garages => 'Officine e attrezzatura';
}

// Path: navigation.states.dimension
class _Translations$navigation$states$dimension$it extends Translations$navigation$states$dimension$en {
	_Translations$navigation$states$dimension$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get height => 'altezza';
	@override String get width => 'larghezza';
	@override String get length => 'lunghezza';
	@override String get weight => 'peso';
}

// Path: navigation.noRoute.limit
class _Translations$navigation$noRoute$limit$it extends Translations$navigation$noRoute$limit$en {
	_Translations$navigation$noRoute$limit$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'sottopasso, altezza ${limit}';
	@override String tunnel({required Object limit}) => 'galleria, altezza ${limit}';
	@override String buildingPassage({required Object limit}) => 'passaggio coperto, altezza ${limit}';
	@override String bridge({required Object limit}) => 'ponte, altezza ${limit}';
	@override String barrier({required Object limit}) => 'barra limitatrice a ${limit}';
	@override String height({required Object limit}) => 'altezza limitata a ${limit}';
	@override String get heightUnknown => 'altezza limitata';
	@override String width({required Object limit}) => 'strettoia larga ${limit}';
	@override String get widthUnknown => 'strettoia';
	@override String length({required Object limit}) => 'lunghezza limitata a ${limit}';
	@override String get lengthUnknown => 'lunghezza limitata';
	@override String weight({required Object limit}) => 'peso limitato a ${limit}';
	@override String get weightUnknown => 'peso limitato';
	@override String get unpaved => 'strada sterrata';
	@override String weightLocalAccess({required Object limit}) => 'peso limitato a ${limit} eccetto frontisti';
	@override String widthLocalAccess({required Object limit}) => 'strettoia larga ${limit}, eccetto frontisti';
	@override String lengthLocalAccess({required Object limit}) => 'lunghezza limitata a ${limit} eccetto frontisti';
}

// Path: navigation.warning.lowClearance
class _Translations$navigation$warning$lowClearance$it extends Translations$navigation$warning$lowClearance$en {
	_Translations$navigation$warning$lowClearance$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'Sottopasso ${limit}';
	@override String tunnel({required Object limit}) => 'Galleria ${limit}';
	@override String buildingPassage({required Object limit}) => 'Passaggio coperto ${limit}';
	@override String bridge({required Object limit}) => 'Ponte ${limit}';
	@override String barrier({required Object limit}) => 'Barra limitatrice ${limit}';
	@override String road({required Object limit}) => 'Altezza massima ${limit}';
}

// Path: navigation.warning.localAccess
class _Translations$navigation$warning$localAccess$it extends Translations$navigation$warning$localAccess$en {
	_Translations$navigation$warning$localAccess$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String weight({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli oltre ${limit}, salvo per raggiungere la tua destinazione';
	@override String axleLoad({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli oltre ${limit} per asse, salvo per raggiungere la tua destinazione';
	@override String width({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli più larghi di ${limit}, salvo per raggiungere la tua destinazione';
	@override String length({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli più lunghi di ${limit}, salvo per raggiungere la tua destinazione';
}

// Path: navigation.guidance.voiceMode
class _Translations$navigation$guidance$voiceMode$it extends Translations$navigation$guidance$voiceMode$en {
	_Translations$navigation$guidance$voiceMode$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get full => 'Voce completa';
	@override String get alerts => 'Voce: solo avvisi';
	@override String get muted => 'Voce disattivata';
	@override String get toFull => 'Torna alla voce completa';
	@override String get toAlerts => 'Passa ai soli avvisi';
	@override String get toMuted => 'Disattiva la voce';
	@override String get saysFull => 'Voce completa: tutte le indicazioni e tutti gli avvisi.';
	@override String get saysAlerts => 'Solo avvisi: la voce parla solo per autovelox, pericoli e cambi di percorso.';
	@override String get saysMuted => 'Voce disattivata: tutto appare sullo schermo, senza alcun suono.';
}

// Path: navigation.guidance.notificationWhy
class _Translations$navigation$guidance$notificationWhy$it extends Translations$navigation$guidance$notificationWhy$en {
	_Translations$navigation$guidance$notificationWhy$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notifica di navigazione';
	@override String get body => 'Durante la navigazione, una notifica mantiene attive la posizione e la voce a schermo spento; toccandola torni alla navigazione. Android ti chiederà se Lunaway può mostrarla.';
	@override String get ask => 'Continua';
	@override String get later => 'Non ora';
}

// Path: navigation.guidance.places
class _Translations$navigation$guidance$places$it extends Translations$navigation$guidance$places$en {
	_Translations$navigation$guidance$places$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get button => 'Luoghi sulla mappa';
	@override String get buttonHidden => 'Luoghi sulla mappa: nascosti';
	@override String get title => 'Luoghi sulla mappa';
	@override String get sleep => 'Per dormire';
	@override String get fill => 'Rifornimento';
	@override String get groceries => 'Per mangiare';
	@override String get all => 'Tutto';
	@override String get everyPlace => 'Tutti i luoghi';
	@override String get none => 'Niente';
	@override String get customize => 'Personalizza';
	@override String get look => 'Visualizzazione';
	@override String get photos => 'Foto';
	@override String get pictograms => 'Icone';
	@override String get dots => 'Segnaposto';
	@override String get photosHint => 'I luoghi che contano di più, in foto. Mai sulla strada davanti a te né sotto i pulsanti.';
	@override String get pictogramsHint => 'I luoghi che contano di più, in grande, con prezzo, valutazione o pernottamento.';
	@override String get dotsHint => 'Tutti i luoghi come piccoli segnaposto, come sulla mappa.';
	@override String get free => 'Gratis';
	@override String get nightOk => 'Pernotto';
}

// Path: navigation.voice.moved
class _Translations$navigation$voice$moved$it extends Translations$navigation$voice$moved$en {
	_Translations$navigation$voice$moved$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String destination({required Object distance}) => 'Destinazione spostata di ${distance} verso la strada accessibile più vicina.';
	@override String stop({required Object n, required Object distance}) => 'Tappa ${n} spostata di ${distance} verso la strada accessibile più vicina.';
}

// Path: navigation.voice.localAccess
class _Translations$navigation$voice$localAccess$it extends Translations$navigation$voice$localAccess$en {
	_Translations$navigation$voice$localAccess$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String weight({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto di transito oltre ${limit}, eccetto frontisti.';
	@override String axleLoad({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto di transito oltre ${limit} per asse, eccetto frontisti.';
	@override String width({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto ai veicoli più larghi di ${limit}, eccetto frontisti.';
	@override String length({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto ai veicoli più lunghi di ${limit}, eccetto frontisti.';
}

// Path: navigation.voice.roadEvent
class _Translations$navigation$voice$roadEvent$it extends Translations$navigation$voice$roadEvent$en {
	_Translations$navigation$voice$roadEvent$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String works({required Object distance}) => 'Lavori tra ${distance}.';
	@override String lanes({required Object distance}) => 'Corsia ridotta tra ${distance}.';
	@override String vehicleLimit({required Object distance}) => 'Attenzione, tra ${distance}, limite di dimensioni per lavori.';
	@override String closure({required Object distance}) => 'Strada forse chiusa tra ${distance}.';
	@override String detour({required Object distance}) => 'Deviazione segnalata tra ${distance}.';
}

// Path: navigation.voice.camera
class _Translations$navigation$voice$camera$it extends Translations$navigation$voice$camera$en {
	_Translations$navigation$voice$camera$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$voice$camera$kind$it kind = _Translations$navigation$voice$camera$kind$it._(_root);
	@override String radar({required Object what, required Object distance}) => '${what} tra ${distance}.';
	@override String radarLimit({required Object what, required Object distance, required Object limit}) => '${what} tra ${distance}, limite ${limit}.';
	@override String sectionLimit({required Object what, required Object distance, required Object limit}) => '${what} tra ${distance}, media massima ${limit}.';
	@override String get inSection => 'Controllo della velocità media.';
	@override String slowDownRadar({required Object limit}) => 'Rallenta, autovelox con limite ${limit}.';
	@override String slowDownRoad({required Object limit}) => 'Rallenta, limite ${limit}.';
}

// Path: navigation.voice.camera.kind
class _Translations$navigation$voice$camera$kind$it extends Translations$navigation$voice$camera$kind$en {
	_Translations$navigation$voice$camera$kind$it._(TranslationsIt root) : this._root = root, super.internal(root);

	final TranslationsIt _root; // ignore: unused_field

	// Translations
	@override String get fixed => 'Autovelox fisso';
	@override String get redLight => 'Telecamera al semaforo';
	@override String get levelCrossing => 'Telecamera al passaggio a livello';
	@override String get section => 'Tutor';
	@override String get other => 'Autovelox';
}

/// The flat map containing all translations for locale <it>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsIt {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Mappa',
			'nav.favorites' => 'Preferiti',
			'nav.profile' => 'Profilo',
			'nav.fold' => 'Riduci il menu',
			'nav.unfold' => 'Espandi il menu',
			'common.close' => 'Chiudi',
			'common.done' => 'Fatto',
			'common.cancel' => 'Annulla',
			'common.retry' => 'Riprova',
			'common.save' => 'Salva',
			'common.delete' => 'Elimina',
			'common.undo' => 'Annulla',
			'common.ok' => 'Ho capito',
			'common.saveFailed' => 'Non è stato possibile salvare la modifica.',
			'common.send' => 'Invia',
			'common.later' => 'Più tardi',
			'common.next' => 'Continua',
			'common.failed' => 'L\'operazione non è riuscita. Riprova tra un momento.',
			'common.offline' => 'Nessuna connessione al momento. Riprova quando torna la rete.',
			'notices.close' => 'Chiudi l\'avviso',
			'notices.fold' => 'Comprimi l\'avviso',
			'notices.unfold' => 'Mostra l\'avviso',
			'kinds.motorhomeArea' => 'Area sosta camper',
			'kinds.serviceArea' => 'Area camper service',
			'kinds.campsite' => 'Campeggio',
			'kinds.parking' => 'Parcheggio',
			'kinds.nature' => 'Sosta in natura',
			'kinds.restArea' => 'Area di sosta stradale',
			'kinds.picnicArea' => 'Area picnic',
			'kinds.farm' => 'Sosta in fattoria',
			'kinds.homestay' => 'Ospitalità da privati',
			'kinds.offRoad' => 'Sosta fuoristrada',
			'kinds.extraService' => 'Servizi utili',
			'families.stopovers' => 'Aree e parcheggi',
			'families.stopoversHint' => 'Aree sosta camper, parcheggi, aree di sosta stradali',
			'families.campsites' => 'Campeggi e ospitalità',
			'families.campsitesHint' => 'Campeggi, fattorie, privati',
			'families.nature' => 'Natura',
			'families.natureHint' => 'Sosta in natura, sterrati',
			'families.services' => 'Servizi',
			'families.servicesHint' => 'Acqua e scarico, senza pernottamento',
			'services.drinkingWater' => 'Acqua potabile',
			'services.greyWater' => 'Scarico acque grigie',
			'services.blackWater' => 'Scarico cassetta WC',
			'services.wasteBin' => 'Raccolta rifiuti',
			'services.toilets' => 'Bagni',
			'services.showers' => 'Docce',
			'services.electricity' => 'Corrente elettrica',
			'services.wifi' => 'Wi-Fi',
			'services.laundry' => 'Lavanderia',
			'services.lpg' => 'GPL',
			'services.gasBottles' => 'Bombole del gas',
			'services.vehicleWash' => 'Lavaggio del veicolo',
			'services.bakery' => 'Panetteria',
			'services.swimmingPool' => 'Piscina',
			'services.petsAllowed' => 'Animali ammessi',
			'services.mobileData' => 'Rete mobile',
			'services.winterCaravanning' => 'Aperto in inverno',
			'activities.monuments' => 'Visite turistiche',
			'activities.windsurfKitesurf' => 'Windsurf, kitesurf',
			'activities.mountainBiking' => 'Mountain bike',
			'activities.hiking' => 'Escursionismo',
			'activities.climbing' => 'Arrampicata',
			'activities.canoeKayak' => 'Canoa, kayak',
			'activities.fishing' => 'Pesca',
			'activities.shoreFishing' => 'Raccolta di molluschi',
			'activities.swimming' => 'Balneazione',
			'activities.motorcycling' => 'Giri in moto',
			'activities.viewpoint' => 'Punto panoramico',
			'activities.playground' => 'Parco giochi',
			'amenities.water' => 'Acqua',
			'amenities.dumpStation' => 'Scarico',
			'amenities.electricity' => 'Corrente elettrica',
			'amenities.toilets' => 'Bagni',
			'amenities.showers' => 'Docce',
			'amenities.wasteBin' => 'Rifiuti',
			'amenities.laundry' => 'Lavanderia',
			'amenities.wifi' => 'Wi-Fi',
			'amenities.lpg' => 'GPL',
			'overnight.allowed' => 'Pernottamento consentito',
			'overnight.tolerated' => 'Pernottamento tollerato',
			'overnight.dayOnly' => 'Solo di giorno',
			'overnight.forbidden' => 'Pernottamento vietato',
			'overnight.unknown' => 'Pernottamento non indicato',
			'overnight.allowedHint' => 'Qui puoi passare la notte.',
			'overnight.toleratedHint' => 'Di solito una notte è accettata. Discrezione d\'obbligo, non lasciare tracce.',
			'overnight.dayOnlyHint' => 'Sosta solo di giorno. Cerca un altro luogo per la notte.',
			'overnight.forbiddenHint' => 'Qui è vietato passare la notte.',
			'overnight.unknownHint' => 'Nessuno l\'ha ancora indicato. Informati sul posto.',
			'freshness.confirmed' => ({required Object when}) => 'Confermato da un viaggiatore ${when}',
			'freshness.unconfirmed' => 'Non ancora confermato da un viaggiatore',
			'freshness.stale' => 'Ultima conferma più di un anno fa',
			'freshness.today' => 'oggi',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'ieri', other: '${n} giorni fa', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'un mese fa', other: '${n} mesi fa', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'un anno fa', other: '${n} anni fa', ), 
			'map.searchHint' => 'Un luogo, un comune',
			'map.clearSearch' => 'Cancella la ricerca',
			'map.locateMe' => 'Mostra la mia posizione',
			'map.aroundMe' => 'Mostra i luoghi vicino a me',
			'map.zoomIn' => 'Aumenta lo zoom',
			'map.zoomOut' => 'Riduci lo zoom',
			'map.filters' => 'Filtri',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Crediti della mappa: © contributori di OpenStreetMap, stile Protomaps. Apre la pagina dei diritti d\'autore di OpenStreetMap.',
			'map.showList' => 'Elenco',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Elenco (${n})', other: 'Elenco (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'luogo qui', other: 'luoghi qui', ), 
			'map.nearestYouLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'luogo più vicino a te', other: 'luoghi più vicini a te', ), 
			'map.nearestCentreLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'luogo più vicino al centro', other: 'luoghi più vicini al centro', ), 
			'map.pointTitle' => 'Qui',
			'map.pointHint' => 'Punto sulla mappa',
			'map.directionsHere' => 'Percorso fino a qui',
			'map.startHere' => 'Parti da qui',
			'map.departureChosen' => 'Punto di partenza impostato: ora apri la scheda della destinazione e tocca Percorso.',
			'map.copyCoordinates' => 'Copia le coordinate',
			'map.freeTapHint' => 'Tocca un punto della mappa per andarci o per aggiungere un luogo',
			'map.freeTapHintClick' => 'Fai clic su un punto della mappa per andarci o per aggiungere un luogo',
			'map.addPlaceAtCenter' => 'Aggiungi un luogo al centro della mappa',
			'map.addressSource' => ({required Object attribution}) => 'Fonte: ${attribution}',
			'map.placesAround' => 'Luoghi nei dintorni',
			'map.downloading' => 'Download dei luoghi della Francia',
			'map.downloadingCount' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${count} luogo ricevuto', other: '${count} luoghi ricevuti', ), 
			'map.noData' => 'Ancora nessun luogo su questo dispositivo',
			'map.noDataHint' => 'Scarica i luoghi una volta sola: poi la mappa funziona senza rete.',
			'map.download' => 'Scarica i luoghi',
			'map.downloadFailed' => 'Il download si è interrotto',
			'map.demoBanner' => 'Demo: luoghi fittizi',
			'map.unsupported' => 'La mappa non è disponibile su questo sistema. Usa l\'app web.',
			'sync.failedOffline' => 'Nessuna connessione per ora.',
			'sync.failedBusy' => 'Il server è molto carico.',
			'sync.failedServer' => 'Il server ha un problema al momento.',
			'sync.failedOther' => 'L\'aggiornamento non è riuscito.',
			'sync.failedRefused' => 'Il server ha rifiutato l\'aggiornamento. Forse serve una versione più recente dell\'app.',
			'sync.willRetry' => 'Lunaway riproverà automaticamente.',
			'sync.incomplete' => ({required Object count}) => 'Download incompleto: finora ${count} luoghi',
			'sync.incompleteShort' => 'Download incompleto',
			'sync.resuming' => ({required Object count}) => 'Download in corso: ${count} luoghi',
			'sync.resume' => 'Riprendi',
			'location.rationaleTitle' => 'Mostrare la tua posizione?',
			'location.rationale' => 'Lunaway la usa per centrare la mappa su di te, ordinare i luoghi per distanza e guidarti. Per un percorso, la tua posizione viene inviata al server di Lunaway, che non la conserva. Per il carburante più economico nei dintorni viene inviata solo una posizione arrotondata a circa 5 km. Una segnalazione stradale viene inviata insieme al punto in cui la fai.',
			'location.allow' => 'Continua',
			'location.notNow' => 'Non ora',
			'location.deniedTitle' => 'Posizione disattivata per Lunaway',
			'location.denied' => 'Hai rifiutato l\'accesso alla posizione. Per usarla, consentila nelle impostazioni del dispositivo.',
			'location.openSettings' => 'Apri le impostazioni',
			'location.serviceOffTitle' => 'Localizzazione disattivata',
			'location.serviceOff' => 'La localizzazione del dispositivo è disattivata. Attivala nelle impostazioni rapide, poi riprova.',
			'location.notAllowed' => 'Posizione non consentita. La mappa funziona anche senza.',
			'location.noFix' => 'Posizione non ancora trovata. Riprova all\'aperto o tra un momento.',
			'location.unsupported' => 'Questo dispositivo non fornisce la sua posizione.',
			'location.browserDeniedTitle' => 'Posizione bloccata dal browser',
			'location.browserDenied' => 'Il browser blocca l\'accesso di Lunaway alla tua posizione. Per consentirlo, fai clic sull\'icona a sinistra dell\'indirizzo del sito (un lucchetto o dei cursori), imposta Posizione su Consenti, poi fai di nuovo clic sul pulsante della posizione.',
			'location.browserNoFix' => 'Il browser non ha fornito alcuna posizione. Riprova tra un momento; su un computer, il Wi-Fi aiuta a trovarla.',
			'search.towns' => 'Comuni',
			'search.places' => 'Luoghi',
			'search.noResult' => ({required Object query}) => 'Nessun luogo né comune corrisponde a «${query}».',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} luogo', other: '${n} luoghi', ), 
			'search.addresses' => 'Indirizzi',
			'search.addressesSearching' => 'Ricerca degli indirizzi',
			'search.addressesFailed' => 'Al momento non è stato possibile cercare gli indirizzi.',
			'search.addressSources' => ({required Object sources}) => 'Indirizzi: ${sources}',
			'search.offline' => 'Nessuna connessione: la ricerca ha bisogno della rete.',
			'search.addressKind.houseNumber' => 'Indirizzo',
			'search.addressKind.street' => 'Via',
			'search.addressKind.locality' => 'Località',
			'search.addressKind.town' => 'Comune',
			'search.addressKind.postcode' => 'CAP',
			'search.addressKind.region' => 'Regione',
			'filters.title' => 'Filtri',
			'filters.families' => 'Tipo di luogo',
			'filters.familiesHint' => 'Nessuna scelta: tutti i tipi',
			'filters.familiesChosenHint' => 'Solo questi tipi',
			'filters.night' => 'Pernottamento',
			'filters.nightHint' => 'Nessuna scelta: tutti i luoghi',
			'filters.nightChosenHint' => 'Solo i luoghi con queste condizioni di pernottamento',
			'filters.nightPossible' => 'Pernottamento possibile',
			'filters.amenities' => 'Servizi',
			'filters.amenitiesHint' => 'Il luogo deve averli tutti',
			'filters.rating' => 'Valutazione minima',
			'filters.ratingHint' => 'Valutazione dei viaggiatori di Lunaway, oppure quella delle altre fonti se nessuno l\'ha valutato. Un luogo senza valutazione viene nascosto.',
			'filters.ratingAtLeast' => ({required Object rating}) => '${rating} o più',
			'filters.opening' => 'Apertura',
			'filters.openingHint' => 'I luoghi di cui non si conosce l\'apertura restano visibili.',
			'filters.openingAllYear' => 'Tutto l\'anno',
			'filters.openingDates' => 'Le mie date',
			'filters.openingClearDates' => 'Cancella le date',
			'filters.openingStay' => ({required Object from, required Object to}) => 'Dal ${from} al ${to}',
			'filters.openingStayDay' => ({required Object date}) => 'Il ${date}',
			'filters.openingStayTitle' => 'Date del tuo soggiorno',
			'filters.openingArrival' => 'Arrivo',
			'filters.openingDeparture' => 'Partenza',
			'filters.price' => 'Prezzo a notte',
			'filters.freeOnly' => 'Gratuito',
			'filters.freeHint' => 'Solo i luoghi in cui la notte è gratuita secondo le loro fonti',
			'filters.scrollNext' => 'Mostra i filtri successivi',
			'filters.scrollPrevious' => 'Mostra i filtri precedenti',
			'filters.vehicle' => 'Il mio veicolo',
			'filters.myVehicleFits' => 'Il mio veicolo passa',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Adatto a ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Nasconde i luoghi con un limite inferiore a ${height}. I luoghi senza altezza nota restano sulla mappa.',
			'filters.reset' => 'Cancella tutto',
			'filters.apply' => 'Applica',
			'filters.show' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, zero: 'Nessun luogo corrisponde', one: 'Mostra ${count} luogo', other: 'Mostra ${count} luoghi', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} filtro attivo', other: '${n} filtri attivi', ), 
			'place.unnamedTitle' => ({required Object kind, required Object where}) => '${kind} · ${where}',
			'place.away' => ({required Object distance}) => 'a ${distance}',
			'place.directions' => 'Percorso',
			'place.share' => 'Condividi',
			'place.save' => 'Salva',
			'place.saved' => 'Salvato',
			'place.saveHint' => 'Aggiungi ai preferiti. Tieni premuto per scegliere le liste.',
			'place.saveTo' => 'Salva in una lista',
			'place.chooseLists' => 'Liste',
			'place.savedToast' => 'Aggiunto ai miei preferiti',
			'place.removedToast' => 'Rimosso dai miei preferiti',
			'place.pricePerNight' => 'Prezzo a notte',
			'place.priceFree' => 'Gratuito',
			'place.priceUnknown' => 'Non indicato',
			'place.priceServices' => 'Servizi',
			'place.priceIncluded' => 'Inclusi',
			'place.priceIncludes' => ({required Object items}) => 'Il prezzo a notte comprende: ${items}',
			'place.inclusions.services' => 'servizi',
			'place.inclusions.touristTax' => 'tassa di soggiorno',
			'place.inclusions.electricity' => 'corrente elettrica',
			'place.maxHeight' => 'Altezza max.',
			'place.capacity' => 'Posti',
			'place.classification' => 'Classificazione',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} stella', other: '${n} stelle', ), 
			'place.hours' => 'Orari',
			'place.services' => 'Servizi',
			'place.noServices' => 'Nessun servizio indicato.',
			'place.activities' => 'Nei dintorni',
			'place.description' => 'Descrizione',
			'place.contact' => 'Contatti',
			'place.website' => 'Sito web',
			'place.call' => 'Chiama',
			'place.coordinates' => 'Coordinate',
			'place.address' => 'Indirizzo',
			'place.copyAddress' => 'Copia l\'indirizzo',
			'place.addressSource' => ({required Object source}) => 'Fonte: ${source}',
			'place.copy' => 'Copia le coordinate',
			'place.copyShort' => 'Copia',
			'place.copyAs' => ({required Object format}) => 'Copia in formato ${format}',
			'place.copiesAs' => ({required Object format}) => 'Il pulsante «Copia» usa: ${format}',
			'place.copied' => ({required Object text}) => 'Copiato: ${text}',
			'place.otherFormats' => 'Scegli il formato da copiare',
			'place.formatDecimal' => 'Gradi decimali',
			'place.formatDms' => 'Gradi, minuti, secondi',
			'place.formatGeo' => 'Link geo:',
			'place.formatGoogle' => 'Link Google Maps',
			'place.formatOsm' => 'Link OpenStreetMap',
			'place.sources' => 'Fonti',
			'place.fetched' => ({required Object when}) => 'Rilevato ${when}',
			'place.viewSource' => 'Apri la fonte',
			'place.gone' => 'Questo luogo non è più sulla mappa',
			'place.goneHint' => 'È stato rimosso o unito a un altro con l\'ultimo aggiornamento.',
			'place.arriving' => 'Questo luogo è ancora in download',
			'place.arrivingHint' => 'I luoghi della Francia si stanno scaricando perché la mappa funzioni senza rete. La scheda si apre appena arriva questo luogo.',
			'place.loadError' => 'Non è stato possibile caricare questo luogo.',
			'place.openFailed' => 'Nessuna app è riuscita ad aprire questo link.',
			'place.photos' => 'Foto',
			'place.extrasOffline' => 'Foto e recensioni richiedono una connessione.',
			'place.reviewsTitle' => 'Recensioni',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} recensione', other: '${n} recensioni', ), 
			'place.noReviews' => 'Ancora nessuna recensione.',
			'place.noOtherReviews' => 'Ancora nessun\'altra recensione.',
			'place.moreReviews' => 'Altre recensioni',
			'place.moreReviewsFailed' => 'Non è stato possibile caricare altre recensioni. Tocca per riprovare.',
			'place.stars' => ({required Object rating}) => '${rating} su 5',
			'place.externalRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'valutazione esterna', other: 'valutazioni esterne', ), 
			'place.lunawayRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'valutazione Lunaway', other: 'valutazioni Lunaway', ), 
			'place.deletedAccount' => 'Account eliminato',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Furgonato',
			'place.reviewVehicle.motorhome' => 'Camper',
			'place.reviewVehicle.caravan' => 'Caravan',
			'place.reviewVehicle.other' => 'Altro veicolo',
			'place.originalLanguage' => ({required Object language}) => 'Testo originale in ${language}',
			'place.descriptionIn' => ({required Object language}) => 'Descrizione in ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Foto ${index} di ${count}',
			'place.previousPhoto' => 'Foto precedente',
			'place.nextPhoto' => 'Foto successiva',
			'place.links' => 'Su altri siti',
			'place.sourceWithLicence' => ({required Object source, required Object licence}) => '${source} · ${licence}',
			'place.licenceCcBy' => 'CC BY 4.0',
			'place.photoCredit' => ({required Object source, required Object author}) => '${source} · ${author}',
			'place.photoStreetView' => 'Vista dalla strada',
			'place.photoSurroundings' => 'Nei dintorni',
			'place.excerptFrom' => ({required Object source, required Object text}) => 'Secondo ${source}: ${text}',
			'place.readMore' => 'Leggi tutto',
			'place.updatedOn' => ({required Object date}) => 'aggiornato il ${date}',
			'place.otherSources' => 'Secondo altre fonti',
			'sources.extcom.label' => 'Fonte comunitaria esterna',
			'sources.extcom.short' => 'Esterna',
			'hours.open' => 'Aperto ora',
			'hours.openUntil' => ({required Object time}) => 'Aperto, chiude alle ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Aperto, chiude ${day} alle ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Aperto, chiude tra ${n} minuto', other: 'Aperto, chiude tra ${n} minuti', ), 
			'hours.closedUntil' => ({required Object time}) => 'Chiuso, apre alle ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Chiuso, apre ${day} alle ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Chiuso, apre tra ${n} minuto', other: 'Chiuso, apre tra ${n} minuti', ), 
			'hours.closedWindow' => 'Chiuso per le prossime due settimane',
			'hours.tomorrow' => 'domani',
			'hours.onDate' => ({required Object date}) => 'il ${date}',
			'hours.onWeekday' => ({required Object day}) => '${day}',
			'hours.midnight' => '24:00',
			'hours.stale' => 'Aperto o chiuso? Aggiorna i luoghi nel Profilo.',
			'hours.localTime' => 'Orari espressi nell\'ora locale',
			'hours.codes.mo' => 'lun',
			'hours.codes.tu' => 'mar',
			'hours.codes.we' => 'mer',
			'hours.codes.th' => 'gio',
			'hours.codes.fr' => 'ven',
			'hours.codes.sa' => 'sab',
			'hours.codes.su' => 'dom',
			'hours.codes.ph' => 'festivi',
			'hours.codes.sh' => 'vacanze scolastiche',
			'hours.codes.off' => 'chiuso',
			'hours.codes.closed' => 'chiuso',
			'hours.codes.sunrise' => 'alba',
			'hours.codes.sunset' => 'tramonto',
			'hours.months.jan' => 'gen',
			'hours.months.feb' => 'feb',
			'hours.months.mar' => 'mar',
			'hours.months.apr' => 'apr',
			'hours.months.may' => 'mag',
			'hours.months.jun' => 'giu',
			'hours.months.jul' => 'lug',
			'hours.months.aug' => 'ago',
			'hours.months.sep' => 'set',
			'hours.months.oct' => 'ott',
			'hours.months.nov' => 'nov',
			'hours.months.dec' => 'dic',
			'hours.dayOfMonth' => ({required Object day, required Object month}) => '${day} ${month}',
			'hours.dayOfYear' => ({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}',
			'hours.allWeek' => '24 ore su 24, 7 giorni su 7',
			'hours.allYear' => 'tutto l\'anno',
			'hours.seasonAllYear' => 'Aperto tutto l\'anno',
			'hours.seasonOpenUntil' => ({required Object date}) => 'Aperto fino al ${date}',
			'hours.seasonClosedUntil' => ({required Object date}) => 'Chiuso, apre il ${date}',
			'directions.title' => 'Apri con',
			'directions.hint' => 'Queste app non conoscono le dimensioni del tuo veicolo.',
			'directions.remember' => 'Usa sempre questa app',
			'directions.rememberHint' => 'Puoi cambiarla nel Profilo',
			'directions.settingTitle' => 'Apri con un\'altra app',
			'directions.settingHint' => 'L\'app che si apre toccando «Apri con» in un percorso',
			'directions.askEachTime' => 'Chiedi ogni volta',
			'directions.appleMaps' => 'Mappe',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (browser)',
			'directions.none' => 'Nessuna app di navigazione trovata su questo dispositivo.',
			'navigation.preview.titleTo' => ({required Object name}) => 'Verso ${name}',
			'navigation.preview.titlePoint' => 'Punto sulla mappa',
			'navigation.preview.departure.title' => 'Partenza',
			'navigation.preview.departure.from' => ({required Object name}) => 'Partenza: ${name}',
			'navigation.preview.departure.myPosition' => 'la mia posizione',
			'navigation.preview.departure.myPositionChoice' => 'La mia posizione',
			'navigation.preview.departure.change' => 'Cambia',
			'navigation.preview.departure.choose' => 'Scegli il punto di partenza',
			'navigation.preview.departure.searchHint' => 'Un luogo, un comune, un indirizzo',
			'navigation.preview.departure.guidanceFromPosition' => 'La navigazione parte sempre dalla tua posizione, non dal punto di partenza scelto.',
			'navigation.preview.departure.fromMyPosition' => 'Usa la mia posizione',
			'navigation.preview.computing' => 'Calcolo di un percorso per il tuo veicolo',
			'navigation.preview.start' => 'Avvia',
			'navigation.preview.recommended' => 'Consigliato',
			'navigation.preview.alternative' => ({required Object n}) => 'Alternativa ${n}',
			'navigation.preview.toll' => 'Pedaggio',
			'navigation.preview.ferry' => 'Traghetto',
			'navigation.preview.motorway' => 'Autostrada',
			'navigation.preview.noWarnings' => 'Nessun limite vicino alle dimensioni del tuo veicolo su questo percorso.',
			'navigation.preview.warnings' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '1 limite da tenere d\'occhio', other: '${n} limiti da tenere d\'occhio', ), 
			'navigation.preview.vehicle' => 'Il tuo veicolo',
			'navigation.preview.vehicleTowing' => ({required Object vehicle}) => '${vehicle}, con traino',
			'navigation.preview.editVehicle' => 'Modifica',
			'navigation.preview.cruise' => ({required Object speed}) => 'Tempi calcolati a ${speed} max',
			'navigation.preview.avoid' => 'Evita',
			'navigation.preview.avoidTolls' => 'Pedaggi',
			'navigation.preview.avoidMotorways' => 'Autostrade',
			'navigation.preview.avoidFerries' => 'Traghetti',
			'navigation.preview.avoidUnpaved' => 'Strade sterrate',
			'navigation.preview.roadbook' => 'Indicazioni passo passo',
			'navigation.preview.roadbookShow' => 'Mostra le indicazioni',
			'navigation.preview.roadbookHide' => 'Nascondi le indicazioni',
			'navigation.preview.dataOf' => ({required Object date}) => 'Dati stradali del ${date}',
			'navigation.preview.attributionOsm' => '© contributori di OpenStreetMap',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, edizione del ${date}',
			'navigation.preview.otherApps' => 'Apri con…',
			'navigation.preview.back' => 'Indietro',
			'navigation.preview.moved.origin' => ({required Object distance}) => 'Punto di partenza spostato di ${distance} verso la strada accessibile più vicina',
			'navigation.preview.moved.destination' => ({required Object distance}) => 'Destinazione spostata di ${distance} verso la strada accessibile più vicina',
			'navigation.preview.moved.stop' => ({required Object n, required Object distance}) => 'Tappa ${n} spostata di ${distance} verso la strada accessibile più vicina',
			'navigation.stops.title' => 'Tappe',
			'navigation.stops.add' => 'Aggiungi come tappa',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Aggiungi come tappa · +${minutes} min',
			'navigation.stops.addFree' => 'Aggiungi come tappa · nessuna deviazione',
			'navigation.stops.quoting' => 'Aggiungi come tappa · calcolo della deviazione',
			'navigation.stops.noRoute' => 'Nessun percorso per il tuo veicolo passando da questo punto.',
			'navigation.stops.full' => 'Al massimo cinque tappe.',
			'navigation.stops.goDirectly' => 'Vai direttamente',
			'navigation.stops.openCard' => 'Vedi la scheda',
			'navigation.stops.point' => 'Punto sulla mappa',
			'navigation.stops.remove' => 'Rimuovi la tappa',
			'navigation.stops.reorder' => 'Trascina per cambiare l\'ordine',
			'navigation.stops.added' => 'Tappa aggiunta',
			'navigation.stops.removed' => 'Tappa rimossa',
			'navigation.stops.moved' => 'Ordine delle tappe cambiato',
			'navigation.stops.destinationChanged' => 'Nuova destinazione',
			'navigation.stops.failed' => 'Non è stato possibile modificare il percorso.',
			'navigation.stops.noQuote' => 'Non è stato possibile calcolare la deviazione.',
			'navigation.stops.offline' => 'Nessuna rete per calcolare la deviazione.',
			'navigation.legs.all' => 'Tutto',
			'navigation.legs.stop' => ({required Object name, required Object time, required Object distance}) => '${name} · ${time} · ${distance}',
			'navigation.legs.stopSaid' => ({required Object number, required Object name, required Object time, required Object distance}) => 'Tappa ${number}: ${name}, verso le ${time}, a ${distance}',
			'navigation.legs.arrival' => ({required Object name, required Object time}) => 'Destinazione · ${name} · ${time}',
			'navigation.legs.arrivalSaid' => ({required Object name, required Object time}) => 'Destinazione: ${name}, verso le ${time}',
			'navigation.legs.remove' => ({required Object number, required Object name}) => 'Rimuovi la tappa ${number}, ${name}',
			'navigation.fuel.price' => ({required Object price}) => '${price} €/l',
			'navigation.fuel.withDetour' => ({required Object price}) => '${price} €/l deviazione inclusa',
			'navigation.fuel.detour' => ({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min',
			'navigation.fuel.onRoute' => 'sul percorso',
			'navigation.fuel.open' => 'Aperto',
			'navigation.fuel.closed' => 'Chiuso',
			'navigation.fuel.unknownHours' => 'Orari sconosciuti',
			'navigation.fuel.add' => 'Aggiungi',
			'navigation.fuel.station' => 'Distributore',
			'navigation.fuel.empty' => 'Nessun distributore con questo carburante vicino al percorso.',
			'navigation.fuel.failed' => 'Non è stato possibile caricare i distributori.',
			'navigation.fuel.estimated' => 'Deviazioni stimate in base alla distanza dal percorso.',
			'navigation.fuel.attribution' => 'Prezzi: Ministero dell\'Economia francese (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => '${n} min fa',
			'navigation.fuel.hoursAgo' => ({required Object n}) => '${n} h fa',
			'navigation.fuel.daysAgo' => ({required Object n}) => '${n} gg fa',
			'navigation.onTheWay.title' => 'Lungo il percorso',
			'navigation.onTheWay.categories.fuel' => 'Carburante',
			'navigation.onTheWay.categories.sleep' => 'Dormire',
			'navigation.onTheWay.categories.water' => 'Acqua e scarico',
			'navigation.onTheWay.categories.groceries' => 'Spesa',
			'navigation.onTheWay.categories.bakeries' => 'Panetterie',
			'navigation.onTheWay.categories.toilets' => 'Bagni, docce',
			'navigation.onTheWay.categories.health' => 'Salute',
			'navigation.onTheWay.categories.services' => 'Servizi',
			'navigation.onTheWay.categories.charging' => 'Ricarica',
			'navigation.onTheWay.categories.garages' => 'Officine e attrezzatura',
			'navigation.onTheWay.fuelOfVehicle' => ({required Object fuel}) => '${fuel}, secondo il tuo veicolo',
			'navigation.onTheWay.otherFuel' => 'Altro carburante',
			'navigation.onTheWay.keepFuel' => 'Salva come mio carburante',
			'navigation.onTheWay.fuelKept' => ({required Object fuel}) => '${fuel} salvato per il tuo veicolo.',
			'navigation.onTheWay.keepFuelFailed' => 'Non è stato possibile salvare il carburante.',
			'navigation.onTheWay.loading' => 'Ricerca lungo il percorso',
			'navigation.onTheWay.empty' => 'Nessun risultato su questo percorso',
			'navigation.onTheWay.emptyHint' => 'Prova un\'altra categoria, o riapri l\'elenco più avanti lungo la strada.',
			'navigation.onTheWay.failed' => 'Non è stato possibile caricare l\'elenco.',
			'navigation.onTheWay.offline' => 'Nessuna rete: l\'elenco tornerà con la connessione.',
			'navigation.onTheWay.rateLimited' => 'Molte ricerche di seguito: riprova tra qualche minuto.',
			'navigation.onTheWay.nearNone' => ({required Object distance}) => 'Niente nei prossimi ${distance}.',
			'navigation.onTheWay.further' => ({required Object n}) => 'Più avanti (${n})',
			'navigation.onTheWay.more' => 'Mostra altro',
			'navigation.onTheWay.moreFailed' => 'Non è stato possibile caricare il resto.',
			'navigation.onTheWay.ahead' => ({required Object distance}) => 'tra ${distance}',
			'navigation.onTheWay.offRoute' => ({required Object distance}) => 'a ${distance} dal percorso',
			'navigation.onTheWay.byTheRoad' => 'a bordo strada',
			'navigation.onTheWay.addCost' => ({required Object minutes}) => 'Aggiungi · +${minutes} min',
			'navigation.onTheWay.addFree' => 'Aggiungi · nessuna deviazione',
			'navigation.onTheWay.openAt' => ({required Object time}) => 'Aperto al tuo passaggio, verso le ${time}',
			'navigation.onTheWay.closedAt' => ({required Object time}) => 'Chiuso al tuo passaggio, verso le ${time}',
			'navigation.onTheWay.closedOpensAt' => ({required Object time, required Object opens}) => 'Chiuso al tuo passaggio verso le ${time}, apre alle ${opens}',
			'navigation.onTheWay.perNight' => ({required Object price}) => '${price} a notte',
			'navigation.onTheWay.photoFrom' => ({required Object source}) => 'Foto: ${source}',
			'navigation.onTheWay.servicesList' => ({required Object list}) => 'Servizi: ${list}',
			'navigation.onTheWay.placesCredit' => 'Luoghi: Lunaway e le fonti indicate su ogni scheda',
			'navigation.states.vehicleTitle' => 'Che veicolo guidi?',
			'navigation.states.vehicleHint' => 'Il percorso evita ponti troppo bassi, vie troppo strette e strade vietate a un veicolo delle tue dimensioni. Indica altezza, larghezza, lunghezza e peso.',
			'navigation.states.vehicleMissing' => ({required Object list}) => 'Dati mancanti: ${list}',
			'navigation.states.vehicleOutOfBounds' => ({required Object list}) => 'Fuori dai valori accettati: ${list}',
			'navigation.states.dimension.height' => 'altezza',
			'navigation.states.dimension.width' => 'larghezza',
			'navigation.states.dimension.length' => 'lunghezza',
			'navigation.states.dimension.weight' => 'peso',
			'navigation.states.describeVehicle' => 'Descrivi il tuo veicolo',
			'navigation.states.originTitle' => 'Dove sei?',
			'navigation.states.originHint' => 'Lunaway ha bisogno della tua posizione per calcolare il percorso.',
			'navigation.states.locate' => 'Localizzami',
			'navigation.states.offlineTitle' => 'Nessuna connessione',
			'navigation.states.offlineHint' => 'I percorsi vengono calcolati sul server di Lunaway. Senza rete, «Apri con…» passa il viaggio a un\'app di navigazione che conserva le sue mappe.',
			'navigation.states.rateLimitedTitle' => 'Troppe richieste di percorso',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Riprova tra ${seconds} s.',
			'navigation.states.unavailableTitle' => 'Calcolo del percorso non disponibile',
			'navigation.states.unavailableHint' => 'Il servizio non è disponibile al momento. Riprova più tardi.',
			'navigation.states.refusedTitle' => 'Nessun percorso qui',
			'navigation.states.refusedHint' => 'Lunaway non è riuscito a calcolare un percorso per questa richiesta: controlla la destinazione, la lunghezza del tragitto e i dati del veicolo.',
			'navigation.states.noSafeTitle' => 'Nessun percorso sicuro per il tuo veicolo',
			'navigation.states.noSafeHint' => 'Ogni strada possibile passa da un limite che il tuo veicolo supera:',
			'navigation.states.whatToDo' => 'Cosa puoi fare',
			'navigation.states.checkVehicle' => ({required Object height, required Object weight}) => 'Controlla i valori inseriti: ${height} di altezza, ${weight}.',
			'navigation.states.pickOtherPoint' => 'Scegli una destinazione prima dell\'ostacolo: tieni premuto sulla mappa.',
			'navigation.states.noRouteTitle' => 'Nessuna strada porta a questo punto',
			'navigation.states.noRouteHint' => 'Forse il punto si trova su una strada privata, o su un\'isola senza traghetto.',
			'navigation.states.allowUnpaved' => 'Le strade sterrate vengono evitate: consentile se la destinazione si trova su uno sterrato.',
			'navigation.states.offNetworkTitle' => 'Troppo lontano da una strada',
			'navigation.states.offNetworkHint' => 'Scegli una destinazione su una strada.',
			'navigation.noRoute.originUnreachable' => 'Il tuo veicolo non può partire da qui',
			'navigation.noRoute.originUnreachableBy' => ({required Object limit}) => 'Il tuo veicolo non può partire da qui: ${limit}',
			'navigation.noRoute.destinationUnreachable' => 'Destinazione irraggiungibile per il tuo veicolo',
			'navigation.noRoute.destinationUnreachableBy' => ({required Object limit}) => 'Destinazione irraggiungibile per il tuo veicolo: ${limit}',
			'navigation.noRoute.waypointUnreachable' => ({required Object n}) => 'Tappa ${n} irraggiungibile per il tuo veicolo',
			'navigation.noRoute.waypointUnreachableBy' => ({required Object n, required Object limit}) => 'Tappa ${n} irraggiungibile per il tuo veicolo: ${limit}',
			_ => null,
		} ?? switch (path) {
			'navigation.noRoute.blockedOnTheWay' => 'Nessun passaggio per il tuo veicolo tra le tappe',
			'navigation.noRoute.blockedOnTheWayBy' => ({required Object limit}) => 'Nessun passaggio per il tuo veicolo tra le tappe: ${limit}',
			'navigation.noRoute.blockedHint' => 'Ogni tappa è raggiungibile, ma tutte le strade che le collegano passano da un limite che il tuo veicolo supera.',
			'navigation.noRoute.notConnectedOrigin' => 'Nessuna strada parte dalla tua posizione',
			'navigation.noRoute.notConnectedDestination' => 'Nessuna strada porta alla destinazione',
			'navigation.noRoute.notConnectedWaypoint' => ({required Object n}) => 'Nessuna strada porta alla tappa ${n}',
			'navigation.noRoute.notConnectedTrip' => 'Nessuna strada collega le tue tappe',
			'navigation.noRoute.notConnectedHint' => 'Qualunque sia il veicolo: un\'isola senza traghetto per veicoli, o una strada chiusa al traffico.',
			'navigation.noRoute.outsideOrigin' => 'La tua posizione è fuori dalla zona coperta dai percorsi',
			'navigation.noRoute.outsideDestination' => 'Destinazione fuori dalla zona coperta dai percorsi',
			'navigation.noRoute.outsideWaypoint' => ({required Object n}) => 'Tappa ${n} fuori dalla zona coperta dai percorsi',
			'navigation.noRoute.outsideHint' => ({required Object countries}) => 'Lunaway calcola i percorsi in questi paesi: ${countries}.',
			'navigation.noRoute.outsideHintUnknown' => 'Lunaway non calcola ancora percorsi in questo paese.',
			'navigation.noRoute.noRoadOrigin' => 'La tua posizione è troppo lontana da una strada',
			'navigation.noRoute.noRoadDestination' => 'Destinazione troppo lontana da una strada',
			'navigation.noRoute.noRoadWaypoint' => ({required Object n}) => 'Tappa ${n} troppo lontana da una strada',
			'navigation.noRoute.noRoadHint' => 'Nessuna strada percorribile dal tuo veicolo entro 5 km da questo punto.',
			'navigation.noRoute.tooLong' => 'Tragitto troppo lungo',
			'navigation.noRoute.tooLongHint' => ({required Object trip, required Object max}) => '${trip} in linea d\'aria da tappa a tappa: Lunaway calcola tragitti di ${max} al massimo.',
			'navigation.noRoute.vehicleValue' => ({required Object value}) => 'Il tuo veicolo: ${value}',
			'navigation.noRoute.limit.underpass' => ({required Object limit}) => 'sottopasso, altezza ${limit}',
			'navigation.noRoute.limit.tunnel' => ({required Object limit}) => 'galleria, altezza ${limit}',
			'navigation.noRoute.limit.buildingPassage' => ({required Object limit}) => 'passaggio coperto, altezza ${limit}',
			'navigation.noRoute.limit.bridge' => ({required Object limit}) => 'ponte, altezza ${limit}',
			'navigation.noRoute.limit.barrier' => ({required Object limit}) => 'barra limitatrice a ${limit}',
			'navigation.noRoute.limit.height' => ({required Object limit}) => 'altezza limitata a ${limit}',
			'navigation.noRoute.limit.heightUnknown' => 'altezza limitata',
			'navigation.noRoute.limit.width' => ({required Object limit}) => 'strettoia larga ${limit}',
			'navigation.noRoute.limit.widthUnknown' => 'strettoia',
			'navigation.noRoute.limit.length' => ({required Object limit}) => 'lunghezza limitata a ${limit}',
			'navigation.noRoute.limit.lengthUnknown' => 'lunghezza limitata',
			'navigation.noRoute.limit.weight' => ({required Object limit}) => 'peso limitato a ${limit}',
			'navigation.noRoute.limit.weightUnknown' => 'peso limitato',
			'navigation.noRoute.limit.unpaved' => 'strada sterrata',
			'navigation.noRoute.limit.weightLocalAccess' => ({required Object limit}) => 'peso limitato a ${limit} eccetto frontisti',
			'navigation.noRoute.limit.widthLocalAccess' => ({required Object limit}) => 'strettoia larga ${limit}, eccetto frontisti',
			'navigation.noRoute.limit.lengthLocalAccess' => ({required Object limit}) => 'lunghezza limitata a ${limit} eccetto frontisti',
			'navigation.noRoute.editVehicle' => 'Modifica il veicolo',
			'navigation.noRoute.allowUnpaved' => 'Consenti le strade sterrate',
			'navigation.noRoute.removeStop' => ({required Object n}) => 'Rimuovi la tappa ${n}',
			'navigation.noRoute.removeStopNamed' => ({required Object name}) => 'Rimuovi la tappa «${name}»',
			'navigation.noRoute.placesAround' => 'Vedi i luoghi intorno alla destinazione',
			'navigation.noRoute.moveDestination' => 'Oppure scegli un\'altra destinazione: tieni premuto sulla mappa, poi «Vai direttamente».',
			'navigation.noRoute.moveStop' => 'Per un\'altra tappa: ingrandisci bene la mappa e tocca il punto, oppure tieni premuto, poi «Aggiungi come tappa».',
			'navigation.noRoute.moveOrigin' => 'La partenza è la tua posizione: raggiungi una strada che il tuo veicolo può percorrere, poi riprova.',
			'navigation.noRoute.pickInside' => 'Scegli una destinazione in uno di questi paesi.',
			'navigation.noRoute.shorter' => 'Scegli una destinazione più vicina, oppure dividi il viaggio in più tappe.',
			'navigation.ferry.title' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Traversata in traghetto', other: '${n} traversate in traghetto', ), 
			'navigation.ferry.unnamed' => 'Traghetto',
			'navigation.ferry.named' => ({required Object name}) => 'Traghetto ${name}',
			'navigation.ferry.ports' => ({required Object ports}) => 'Porti: ${ports}',
			'navigation.ferry.countries' => ({required Object from, required Object to}) => 'Imbarco: ${from} · Sbarco: ${to}',
			'navigation.ferry.country' => ({required Object country}) => 'Paese: ${country}',
			'navigation.ferry.where' => ({required Object distance, required Object sea, required Object duration}) => 'A ${distance} dalla partenza · ${sea} in mare, circa ${duration}',
			'navigation.ferry.needed' => 'La destinazione non si raggiunge senza traghetto: il percorso ne prende uno, anche se hai scelto di evitare i traghetti.',
			'navigation.warning.lowClearance.underpass' => ({required Object limit}) => 'Sottopasso ${limit}',
			'navigation.warning.lowClearance.tunnel' => ({required Object limit}) => 'Galleria ${limit}',
			'navigation.warning.lowClearance.buildingPassage' => ({required Object limit}) => 'Passaggio coperto ${limit}',
			'navigation.warning.lowClearance.bridge' => ({required Object limit}) => 'Ponte ${limit}',
			'navigation.warning.lowClearance.barrier' => ({required Object limit}) => 'Barra limitatrice ${limit}',
			'navigation.warning.lowClearance.road' => ({required Object limit}) => 'Altezza massima ${limit}',
			'navigation.warning.unknownClearance' => 'Passaggio basso, altezza sconosciuta',
			'navigation.warning.narrow' => ({required Object limit}) => 'Strettoia ${limit}',
			'navigation.warning.tooLong' => ({required Object limit}) => 'Lunghezza massima ${limit}',
			'navigation.warning.tooHeavy' => ({required Object limit}) => 'Peso massimo ${limit}',
			'navigation.warning.axleLoad' => ({required Object limit}) => 'Carico massimo per asse ${limit}',
			'navigation.warning.motorhomeBan' => 'Vietato ai camper',
			'navigation.warning.trailerBan' => 'Vietato ai rimorchi',
			'navigation.warning.goodsVehicleWeight' => ({required Object limit}) => 'Peso massimo per mezzi pesanti ${limit}',
			'navigation.warning.yours' => ({required Object value}) => 'il tuo veicolo: ${value}',
			'navigation.warning.fromStart' => ({required Object distance}) => 'a ${distance} dalla partenza',
			'navigation.warning.ahead' => ({required Object distance}) => 'tra ${distance}',
			'navigation.warning.disputed' => 'le fonti non concordano, vale il valore più basso',
			'navigation.warning.goodsOnly' => 'riguarda i mezzi pesanti, controlla i cartelli',
			'navigation.warning.osm' => 'OpenStreetMap',
			'navigation.warning.ign' => 'IGN BD TOPO',
			'navigation.warning.community' => 'Segnalazione Lunaway',
			'navigation.warning.dialog' => 'Ordinanza di circolazione (DiaLog)',
			'navigation.warning.localAccess.weight' => ({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli oltre ${limit}, salvo per raggiungere la tua destinazione',
			'navigation.warning.localAccess.axleLoad' => ({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli oltre ${limit} per asse, salvo per raggiungere la tua destinazione',
			'navigation.warning.localAccess.width' => ({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli più larghi di ${limit}, salvo per raggiungere la tua destinazione',
			'navigation.warning.localAccess.length' => ({required Object limit}) => 'Eccetto frontisti: vietato ai veicoli più lunghi di ${limit}, salvo per raggiungere la tua destinazione',
			'navigation.roadEvents.title' => 'Lavori e chiusure',
			'navigation.roadEvents.none' => 'Nessun lavoro né chiusura noti su questo percorso.',
			'navigation.roadEvents.stale' => 'Lavori e chiusure: le fonti non sono aggiornate di recente.',
			'navigation.roadEvents.avoided' => ({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Percorso calcolato evitando una chiusura: ${names}', other: 'Percorso calcolato evitando ${n} chiusure: ${names}', ), 
			'navigation.roadEvents.atDistance' => ({required Object distance}) => 'a ${distance} dalla partenza',
			'navigation.roadEvents.more' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'E un altro sul percorso', other: 'E altri ${n} sul percorso', ), 
			'navigation.roadEvents.classClosure' => 'Strada chiusa',
			'navigation.roadEvents.classWorks' => 'Lavori',
			'navigation.roadEvents.classLaneRestriction' => 'Corsie ridotte',
			'navigation.roadEvents.classVehicleLimit' => 'Limite di dimensioni',
			'navigation.roadEvents.classDetour' => 'Deviazione segnalata',
			'navigation.roadEvents.reasonUnmatched' => 'posizione incerta, forse sul percorso',
			'navigation.roadEvents.reasonStale' => 'fonte non aggiornata di recente',
			'navigation.roadEvents.reasonOutsideHours' => 'fuori dall\'orario previsto',
			'navigation.roadEvents.reasonGoodsVehicles' => 'per i mezzi pesanti',
			'navigation.roadEvents.reasonUnconfirmed' => 'segnalato da un solo viaggiatore',
			'navigation.roadEvents.reasonAged' => 'segnalazione vecchia',
			'navigation.roadEvents.reasonInside' => 'il percorso inizia o finisce al suo interno',
			'navigation.roadEvents.reasonNearLimit' => 'con poco margine',
			'navigation.roadEvents.reasonOverLimit' => 'il tuo veicolo supera il limite',
			'navigation.marks.legend' => 'Legenda',
			'navigation.marks.legendHide' => 'Chiudi la legenda',
			'navigation.marks.kindOrigin' => 'Partenza',
			'navigation.marks.kindDestination' => 'Destinazione',
			'navigation.marks.kindStop' => 'Tappa',
			'navigation.marks.kindClosure' => 'Strada chiusa',
			'navigation.marks.kindWorks' => 'Lavori',
			'navigation.marks.kindLanes' => 'Corsie ridotte',
			'navigation.marks.kindClearance' => 'Altezza limitata',
			'navigation.marks.kindWeight' => 'Peso limitato',
			'navigation.marks.kindLimit' => 'Altro limite (larghezza, lunghezza, divieto)',
			'navigation.marks.kindFuel' => 'Distributore',
			'navigation.marks.kindPlace' => 'Luogo vicino al percorso',
			'navigation.marks.groupLegend' => 'Indicatori vicini raggruppati',
			'navigation.marks.zoneLegend' => 'Zona di pericolo',
			'navigation.marks.zonesFrom' => ({required Object source, required Object date}) => 'Zone di pericolo: ${source}, elenco del ${date}',
			'navigation.marks.group' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} indicatore', other: '${n} indicatori', ), 
			'navigation.marks.groupHint' => 'Ingrandisci per vederli uno per uno',
			'navigation.marks.count' => ({required Object kind, required Object n}) => '${kind}: ${n}',
			'navigation.marks.stop' => ({required Object n}) => 'Tappa ${n}',
			'navigation.marks.origin' => 'Punto di partenza',
			'navigation.marks.nearRoute' => 'Vicino al percorso',
			'navigation.marks.avoided' => 'Il percorso lo evita',
			'navigation.marks.blocking' => 'Blocca ogni percorso',
			'navigation.marks.showInList' => 'Vedi nell\'elenco',
			'navigation.marks.showAll' => 'Mostra tutto',
			'navigation.marks.onMap' => 'mostra sulla mappa',
			'navigation.marks.price' => ({required Object price}) => '${price} €',
			'navigation.marks.kindCamera' => 'Autovelox',
			'navigation.marks.cameras' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} autovelox', other: '${n} autovelox', ), 
			'navigation.marks.camerasFrom' => ({required Object source, required Object date}) => 'Autovelox: ${source}, elenco del ${date}',
			'navigation.marks.bothFrom' => ({required Object source, required Object date}) => 'Autovelox e zone di pericolo: ${source}, elenco del ${date}',
			'navigation.marks.sectionLength' => ({required Object distance}) => 'Tratto di ${distance}',
			'navigation.marks.cameraDirection' => 'Controlla il tuo senso di marcia',
			'navigation.guidance.then' => 'Poi',
			'navigation.guidance.arrival' => ({required Object time}) => 'Arrivo alle ${time}',
			'navigation.guidance.offRoute' => 'Fuori percorso',
			'navigation.guidance.rerouting' => 'Ricerca di un nuovo percorso',
			'navigation.guidance.rerouted' => 'Nuovo percorso',
			'navigation.guidance.reroutedLonger' => ({required Object minutes}) => 'Nuovo percorso, ${minutes} min in più',
			'navigation.guidance.rerouteOffline' => 'Nessuna rete per un nuovo percorso: torna sul percorso',
			'navigation.guidance.rerouteFailed' => 'Nessun nuovo percorso: torna sul percorso',
			'navigation.guidance.closureAhead' => ({required Object distance}) => 'Strada chiusa tra ${distance}: ricerca di un\'alternativa',
			'navigation.guidance.noDetour' => ({required Object distance}) => 'Strada chiusa tra ${distance}: nessuna alternativa',
			'navigation.guidance.eventAhead' => ({required Object distance}) => 'Lavori tra ${distance}',
			'navigation.guidance.eventClosure' => ({required Object distance}) => 'Strada chiusa tra ${distance}',
			'navigation.guidance.eventLimit' => ({required Object distance}) => 'Lavori tra ${distance}: dimensioni limitate',
			'navigation.guidance.eventSource' => ({required Object source, required Object time}) => '${source}, dati delle ${time}',
			'navigation.guidance.eventSourceOn' => ({required Object source, required Object day, required Object time}) => '${source}, dati del ${day} alle ${time}',
			'navigation.guidance.avoidedClosures' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Percorso calcolato evitando una chiusura', other: 'Percorso calcolato evitando ${n} chiusure', ), 
			'navigation.guidance.roadEventAhead' => ({required Object what, required Object distance}) => '${what} tra ${distance}',
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Strada chiusa tra ${distance}: nessuna rete per cercare un\'alternativa',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Strada chiusa tra ${distance}: ancora nessuna alternativa',
			'navigation.guidance.voiceMode.full' => 'Voce completa',
			'navigation.guidance.voiceMode.alerts' => 'Voce: solo avvisi',
			'navigation.guidance.voiceMode.muted' => 'Voce disattivata',
			'navigation.guidance.voiceMode.toFull' => 'Torna alla voce completa',
			'navigation.guidance.voiceMode.toAlerts' => 'Passa ai soli avvisi',
			'navigation.guidance.voiceMode.toMuted' => 'Disattiva la voce',
			'navigation.guidance.voiceMode.saysFull' => 'Voce completa: tutte le indicazioni e tutti gli avvisi.',
			'navigation.guidance.voiceMode.saysAlerts' => 'Solo avvisi: la voce parla solo per autovelox, pericoli e cambi di percorso.',
			'navigation.guidance.voiceMode.saysMuted' => 'Voce disattivata: tutto appare sullo schermo, senza alcun suono.',
			'navigation.guidance.overview' => 'Tutto il percorso',
			'navigation.guidance.recenter' => 'Ricentra',
			'navigation.guidance.end' => 'Termina',
			'navigation.guidance.endTitle' => 'Terminare la navigazione?',
			'navigation.guidance.endConfirm' => 'Termina',
			'navigation.guidance.endKeep' => 'Continua',
			'navigation.guidance.stopTitle' => 'Interrompere la navigazione?',
			'navigation.guidance.stopConfirm' => 'Interrompi',
			'navigation.guidance.arrivedTitle' => 'Sei arrivato a destinazione',
			'navigation.guidance.done' => 'Termina',
			'navigation.guidance.speed' => 'Velocità',
			'navigation.guidance.limit' => 'Limite',
			'navigation.guidance.noVoice' => ({required Object language}) => 'Nessuna voce in ${language} su questo dispositivo: istruzioni solo sullo schermo.',
			'navigation.guidance.missingVoice' => ({required Object language}) => 'La voce in ${language} non è ancora scaricata.',
			'navigation.guidance.installVoice' => 'Installa',
			'navigation.guidance.voiceSettingsIos' => 'Impostazioni, Accessibilità, Contenuto letto ad alta voce, Voci',
			'navigation.guidance.notificationTitle' => 'Lunaway ti sta guidando',
			'navigation.guidance.notificationText' => 'La navigazione continua anche a schermo spento.',
			'navigation.guidance.notificationChannel' => 'Navigazione',
			'navigation.guidance.unavailable' => 'Non è stato possibile avviare la navigazione su questo dispositivo.',
			'navigation.guidance.notificationWhy.title' => 'Notifica di navigazione',
			'navigation.guidance.notificationWhy.body' => 'Durante la navigazione, una notifica mantiene attive la posizione e la voce a schermo spento; toccandola torni alla navigazione. Android ti chiederà se Lunaway può mostrarla.',
			'navigation.guidance.notificationWhy.ask' => 'Continua',
			'navigation.guidance.notificationWhy.later' => 'Non ora',
			'navigation.guidance.positionLost' => 'Posizione non disponibile: verifica che la localizzazione del dispositivo sia attiva per Lunaway.',
			'navigation.guidance.positionStale' => ({required Object minutes}) => 'Ultima posizione ricevuta ${minutes} min fa: l\'orario di arrivo si basa su questa.',
			'navigation.guidance.limitEstimated' => 'Limite stimato',
			'navigation.guidance.overLimit' => 'oltre il limite',
			'navigation.guidance.enforcementSource' => ({required Object source, required Object date}) => '${source}, elenco del ${date}',
			'navigation.guidance.demoDrive' => 'Viaggio simulato: dimostrazione senza GPS',
			'navigation.guidance.places.button' => 'Luoghi sulla mappa',
			'navigation.guidance.places.buttonHidden' => 'Luoghi sulla mappa: nascosti',
			'navigation.guidance.places.title' => 'Luoghi sulla mappa',
			'navigation.guidance.places.sleep' => 'Per dormire',
			'navigation.guidance.places.fill' => 'Rifornimento',
			'navigation.guidance.places.groceries' => 'Per mangiare',
			'navigation.guidance.places.all' => 'Tutto',
			'navigation.guidance.places.everyPlace' => 'Tutti i luoghi',
			'navigation.guidance.places.none' => 'Niente',
			'navigation.guidance.places.customize' => 'Personalizza',
			'navigation.guidance.places.look' => 'Visualizzazione',
			'navigation.guidance.places.photos' => 'Foto',
			'navigation.guidance.places.pictograms' => 'Icone',
			'navigation.guidance.places.dots' => 'Segnaposto',
			'navigation.guidance.places.photosHint' => 'I luoghi che contano di più, in foto. Mai sulla strada davanti a te né sotto i pulsanti.',
			'navigation.guidance.places.pictogramsHint' => 'I luoghi che contano di più, in grande, con prezzo, valutazione o pernottamento.',
			'navigation.guidance.places.dotsHint' => 'Tutti i luoghi come piccoli segnaposto, come sulla mappa.',
			'navigation.guidance.places.free' => 'Gratis',
			'navigation.guidance.places.nightOk' => 'Pernotto',
			'navigation.voice.rerouting' => 'Ricalcolo del percorso.',
			'navigation.voice.rerouted' => 'Nuovo percorso.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(minutes, one: 'Nuovo percorso, un minuto in più.', other: 'Nuovo percorso, ${minutes} minuti in più.', ), 
			'navigation.voice.moved.destination' => ({required Object distance}) => 'Destinazione spostata di ${distance} verso la strada accessibile più vicina.',
			'navigation.voice.moved.stop' => ({required Object n, required Object distance}) => 'Tappa ${n} spostata di ${distance} verso la strada accessibile più vicina.',
			'navigation.voice.closureAhead' => ({required Object distance}) => 'Strada chiusa tra ${distance}. Ricerca di un percorso alternativo.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'Strada chiusa tra ${distance}. Non ci sono alternative.',
			'navigation.voice.clearance' => ({required Object distance, required Object height}) => 'Attenzione, tra ${distance}, passaggio basso di ${height}.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Attenzione, tra ${distance}, passaggio basso di altezza sconosciuta.',
			'navigation.voice.narrow' => ({required Object distance, required Object width}) => 'Attenzione, tra ${distance}, strettoia larga ${width}.',
			'navigation.voice.limit' => ({required Object distance, required Object what}) => 'Attenzione, tra ${distance}, ${what}.',
			'navigation.voice.arrived' => 'Sei arrivato a destinazione.',
			'navigation.voice.metres' => ({required Object n}) => '${n} metri',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count, one: 'un chilometro', other: '${n} chilometri', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} piedi',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count, one: 'un miglio', other: '${n} miglia', ), 
			'navigation.voice.size' => ({required num count, required Object cm, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count, one: 'un metro e ${cm}', other: '${metres} metri e ${cm}', ), 
			'navigation.voice.sizeWhole' => ({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count, one: 'un metro', other: '${metres} metri', ), 
			'navigation.voice.overSpeed' => ({required Object limit}) => 'Limite di velocità ${limit}.',
			'navigation.voice.dangerZone' => ({required Object distance}) => 'Zona di pericolo tra ${distance}.',
			'navigation.voice.inDangerZone' => 'Zona di pericolo.',
			'navigation.voice.localAccess.weight' => ({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto di transito oltre ${limit}, eccetto frontisti.',
			'navigation.voice.localAccess.axleLoad' => ({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto di transito oltre ${limit} per asse, eccetto frontisti.',
			'navigation.voice.localAccess.width' => ({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto ai veicoli più larghi di ${limit}, eccetto frontisti.',
			'navigation.voice.localAccess.length' => ({required Object distance, required Object limit}) => 'Attenzione, tra ${distance}, divieto ai veicoli più lunghi di ${limit}, eccetto frontisti.',
			'navigation.voice.roadEvent.works' => ({required Object distance}) => 'Lavori tra ${distance}.',
			'navigation.voice.roadEvent.lanes' => ({required Object distance}) => 'Corsia ridotta tra ${distance}.',
			'navigation.voice.roadEvent.vehicleLimit' => ({required Object distance}) => 'Attenzione, tra ${distance}, limite di dimensioni per lavori.',
			'navigation.voice.roadEvent.closure' => ({required Object distance}) => 'Strada forse chiusa tra ${distance}.',
			'navigation.voice.roadEvent.detour' => ({required Object distance}) => 'Deviazione segnalata tra ${distance}.',
			'navigation.voice.positionLost' => 'Posizione non disponibile. Controlla la localizzazione del dispositivo.',
			'navigation.voice.tonnes' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(count, one: 'una tonnellata', other: '${n} tonnellate', ), 
			'navigation.voice.camera.kind.fixed' => 'Autovelox fisso',
			'navigation.voice.camera.kind.redLight' => 'Telecamera al semaforo',
			'navigation.voice.camera.kind.levelCrossing' => 'Telecamera al passaggio a livello',
			'navigation.voice.camera.kind.section' => 'Tutor',
			'navigation.voice.camera.kind.other' => 'Autovelox',
			'navigation.voice.camera.radar' => ({required Object what, required Object distance}) => '${what} tra ${distance}.',
			'navigation.voice.camera.radarLimit' => ({required Object what, required Object distance, required Object limit}) => '${what} tra ${distance}, limite ${limit}.',
			'navigation.voice.camera.sectionLimit' => ({required Object what, required Object distance, required Object limit}) => '${what} tra ${distance}, media massima ${limit}.',
			'navigation.voice.camera.inSection' => 'Controllo della velocità media.',
			'navigation.voice.camera.slowDownRadar' => ({required Object limit}) => 'Rallenta, autovelox con limite ${limit}.',
			'navigation.voice.camera.slowDownRoad' => ({required Object limit}) => 'Rallenta, limite ${limit}.',
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} h ${m} min',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Navigazione',
			'navigation.settings.avoidTitle' => 'Evita per impostazione predefinita',
			'navigation.settings.voice' => 'Voce della navigazione',
			'navigation.settings.voiceFull' => 'Completa',
			'navigation.settings.voiceAlerts' => 'Avvisi',
			'navigation.settings.voiceMuted' => 'Disattivata',
			'navigation.settings.voiceFullHint' => 'Le indicazioni e gli avvisi, con la voce del dispositivo.',
			'navigation.settings.voiceAlertsHint' => 'Solo autovelox e zone di pericolo, chiusure, lavori e limiti di dimensioni lungo il percorso, e cambi di percorso, dopo un breve segnale acustico.',
			'navigation.settings.voiceMutedHint' => 'Nessun suono: indicazioni e avvisi sullo schermo.',
			'navigation.settings.units' => 'Distanze',
			'navigation.settings.metric' => 'Chilometri',
			'navigation.settings.imperial' => 'Miglia',
			'navigation.settings.speedLimit' => 'Limite di velocità',
			'navigation.settings.speedLimitHint' => 'Mostra il limite valido per il tuo veicolo accanto alla velocità; se è stimato appare in grigio.',
			'navigation.settings.speedSound' => 'Avviso vocale del limite',
			'navigation.settings.speedSoundHint' => 'Un avviso quando superi il limite, con la voce completa. Autovelox e zone di pericolo seguono la voce della navigazione.',
			'navigation.settings.exactFrance' => 'Posizione esatta degli autovelox in Francia',
			'navigation.settings.exactFranceHint' => 'In Francia, possedere un dispositivo che segnala la posizione degli autovelox è punito con una multa di 1.500 € e la decurtazione di 6 punti (Code de la route, art. R413-15).',
			'navigation.enforcement.fixed' => 'Autovelox fisso',
			'navigation.enforcement.redLight' => 'Telecamera al semaforo',
			'navigation.enforcement.levelCrossing' => 'Telecamera al passaggio a livello',
			'navigation.enforcement.section' => 'Tutor',
			'navigation.enforcement.zone' => 'Zona di pericolo',
			'navigation.enforcement.average' => ({required Object limit}) => 'media ${limit}',
			'navigation.enforcement.averageLabel' => 'media',
			'navigation.enforcement.remaining' => ({required Object distance}) => 'per altri ${distance}',
			'navigation.enforcement.yourAverage' => ({required Object speed}) => 'la tua media ${speed}',
			'navigation.enforcement.zoneEnd' => 'Fine della zona di pericolo',
			'navigation.enforcement.sectionEnd' => 'Fine del controllo della velocità media',
			'navigation.enforcement.ruleOff' => ({required Object country}) => '${country}: nessun avviso autovelox',
			'navigation.enforcement.ruleZones' => ({required Object country}) => '${country}: zone di pericolo',
			'navigation.enforcement.ruleExact' => ({required Object country}) => '${country}: autovelox',
			'navigation.enforcement.ahead' => ({required Object what, required Object distance}) => '${what} tra ${distance}',
			'navigation.enforcement.limit' => ({required Object limit}) => 'limite ${limit}',
			'navigation.enforcement.averageLimit' => ({required Object limit}) => 'media massima ${limit}',
			'list.title' => 'Luoghi nelle vicinanze',
			'list.empty' => 'Nessun luogo qui intorno con questi filtri',
			'list.emptyHint' => 'Sposta la mappa, riduci lo zoom o allenta i filtri.',
			'list.downloading' => 'I luoghi stanno arrivando',
			'list.downloadingHint' => 'L\'elenco si riempie durante il download.',
			'list.error' => 'Non è stato possibile caricare l\'elenco.',
			'list.offline' => 'Nessuna connessione: l\'elenco ha bisogno della rete.',
			'list.moreFailed' => 'Non è stato possibile caricare altri luoghi. Tocca per riprovare.',
			'list.sortDistance' => 'Distanza',
			'list.sortRating' => 'Valutazione',
			'list.sortNewest' => 'Aggiunti di recente',
			'list.sortedBy' => ({required Object sort}) => 'Elenco ordinato per: ${sort}',
			'list.rankedAmongNearestYou' => ({required Object n}) => 'Ordine calcolato sui ${n} luoghi più vicini a te',
			'list.rankedAmongNearestCentre' => ({required Object n}) => 'Ordine calcolato sui ${n} luoghi più vicini al centro della mappa',
			'list.offlineTitle' => 'Nessuna connessione',
			'list.offlineNotHere' => 'Niente di quest\'area su questo dispositivo.',
			'favorites.title' => 'Preferiti',
			'favorites.defaultList' => 'I miei preferiti',
			'favorites.empty' => 'Ancora niente di salvato qui',
			'favorites.emptyHint' => 'Tocca Salva nella scheda di un luogo per ritrovarlo, anche offline.',
			'favorites.newList' => 'Nuova lista',
			'favorites.listName' => 'Nome della lista',
			'favorites.renameList' => 'Rinomina la lista',
			'favorites.deleteList' => 'Elimina la lista',
			'favorites.deleteListConfirm' => ({required Object name}) => 'Eliminare «${name}»? I luoghi restano sulla mappa.',
			'favorites.listActions' => 'Opzioni della lista',
			'favorites.placeActions' => 'Opzioni del luogo',
			'favorites.openOnMap' => 'Vedi sulla mappa',
			'favorites.remove' => 'Rimuovi dalla lista',
			'favorites.removed' => 'Rimosso dalla lista',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, zero: 'Vuota', one: '${n} luogo', other: '${n} luoghi', ), 
			'favorites.error' => 'Non è stato possibile caricare i tuoi preferiti.',
			'vehicle.title' => 'Il mio veicolo',
			'vehicle.why' => 'Le dimensioni del tuo veicolo servono a nascondere i luoghi in cui non passa. Vengono inviate con ogni richiesta di percorso, senza essere conservate.',
			'vehicle.none' => 'Descrivi il tuo veicolo per nascondere i luoghi in cui non passa.',
			'vehicle.add' => 'Descrivi il mio veicolo',
			'vehicle.edit' => 'Modifica',
			'vehicle.type' => 'Tipo',
			'vehicle.types.van' => 'Van',
			'vehicle.types.campervan' => 'Furgonato',
			'vehicle.types.lowProfile' => 'Semintegrale',
			'vehicle.types.overcab' => 'Mansardato',
			'vehicle.types.integrated' => 'Motorhome',
			'vehicle.towingTitle' => 'Traino',
			'vehicle.towing.none' => 'Nessuno',
			'vehicle.towing.car' => 'Un\'auto',
			'vehicle.towing.trailer' => 'Un rimorchio',
			'vehicle.size' => 'Dimensioni',
			'vehicle.sizeHint' => 'Valori tipici del tipo scelto: correggili con quelli del tuo libretto di circolazione.',
			'vehicle.height' => 'Altezza',
			'vehicle.width' => 'Larghezza',
			'vehicle.length' => 'Lunghezza totale, traino compreso',
			'vehicle.weight' => 'Massa complessiva a pieno carico',
			'vehicle.heightShort' => ({required Object value}) => 'alt. ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'largh. ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'lungh. ${value}',
			'vehicle.notANumber' => 'Un numero, per esempio 2,90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Tra ${min} e ${max} ${unit}',
			'vehicle.navigationLater' => 'La navigazione di Lunaway tiene conto di tutte queste dimensioni.',
			'vehicle.save' => 'Salva',
			'vehicle.clear' => 'Cancella',
			'vehicle.fuelTitle' => 'Carburante',
			'vehicle.fuelHint' => 'Il prezzo del tuo carburante appare sui distributori della mappa, con i più economici per primi.',
			'vehicle.consumption' => 'Consumo',
			'vehicle.consumptionUnit' => 'l/100 km',
			'vehicle.lpgHeating' => 'Riscaldamento a GPL',
			'vehicle.lpgHeatingHint' => 'Anche i prezzi del GPL appaiono sui distributori.',
			'vehicle.cruiseTitle' => 'Velocità di crociera massima',
			'vehicle.cruiseHint' => 'I tempi di percorrenza presuppongono che tu non vada mai più veloce, anche dove la strada lo consente. I limiti annunciati durante la navigazione restano quelli della strada.',
			'vehicle.cruiseNone' => 'Nessun limite',
			'vehicleHeight.title' => 'Altezza del tuo veicolo',
			'vehicleHeight.why' => 'I luoghi con un limite più basso verranno nascosti. Quelli senza altezza nota restano sulla mappa.',
			'vehicleHeight.needed' => 'Indica l\'altezza, per esempio 2,90',
			'vehicleHeight.weightOptional' => 'Massa complessiva (facoltativa)',
			'vehicleHeight.apply' => 'Filtra con questa altezza',
			'vehicleHeight.later' => 'Gli altri dati del veicolo si inseriscono in Profilo, Il mio veicolo.',
			'profile.title' => 'Profilo',
			'profile.noAccountNeeded' => 'Nessun account, nessuna pubblicità, nessun tracciamento. I tuoi preferiti restano su questo dispositivo.',
			'profile.language' => 'Lingua',
			'profile.languageSystem' => 'Lingua del dispositivo',
			'profile.appearance' => 'Aspetto',
			'profile.themeAuto' => 'Automatico',
			'profile.themeLight' => 'Chiaro',
			'profile.themeDark' => 'Scuro',
			'profile.themeAutoHint' => 'Chiaro di giorno, scuro dopo il tramonto dove ti trovi.',
			'profile.themeLightHint' => 'Sempre chiaro, di giorno e di notte.',
			'profile.themeDarkHint' => 'Sempre scuro, riposante per gli occhi di notte.',
			'profile.offline' => 'Offline',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'luogo su questo dispositivo', other: 'luoghi su questo dispositivo', ), 
			'profile.offlineSize' => ({required Object size}) => 'Spazio occupato: ${size}',
			'profile.lastSync' => ({required Object when}) => 'Ultimo aggiornamento ${when}',
			'profile.neverSynced' => 'Mai scaricato',
			'profile.syncNow' => 'Aggiorna ora',
			'profile.syncing' => 'Aggiornamento in corso',
			'profile.about' => 'Informazioni',
			'profile.version' => ({required Object version}) => 'Versione ${version}',
			'profile.website' => 'Sito web',
			'profile.privacy' => 'Informativa sulla privacy',
			'profile.sourceCode' => 'Codice sorgente',
			'profile.licences' => 'Licenze',
			'profile.appLicence' => 'Lunaway è software libero con licenza GNU AGPL 3.0 o successiva.',
			'profile.routeData' => 'I percorsi si basano su dati aperti che possono essere incompleti: la segnaletica e il codice della strada prevalgono.',
			'profile.attributions' => 'Fonti e crediti',
			'profile.attributionOsm' => 'Luoghi e dati cartografici © contributori di OpenStreetMap.',
			'profile.attributionOdbl' => 'Dati di OpenStreetMap con licenza Open Database License (ODbL).',
			'profile.attributionAtout' => 'Campeggi classificati di Atout France, posizionati con la Base Adresse Nationale e la BD TOPO dell\'IGN, con Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Comuni dei luoghi: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), con licenza ODbL.',
			'profile.attributionCommunityPlaces' => 'Luoghi aggiunti e modificati dai viaggiatori di Lunaway, con licenza ODbL e la menzione «Lunaway contributors».',
			'profile.attributionTiles' => 'Mappa di base fornita da Lunaway, stili derivati da Protomaps (BSD-3-Clause), dati © contributori di OpenStreetMap.',
			'profile.attributionFonts' => 'Caratteri Fraunces e Atkinson Hyperlegible Next, con licenza SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Icone Phosphor, con licenza MIT.',
			'profile.noTracking' => 'Nessuna pubblicità, nessun tracciamento. Il tuo account non conosce né la tua e-mail né il tuo numero di telefono.',
			'profile.attributionBdTopo' => 'Limiti di altezza, larghezza, lunghezza e peso delle strade, e campeggi posizionati in base al nome: BD TOPO dell\'IGN, tramite la Géoplateforme, con Licence Ouverte 2.0.',
			'profile.attributionAddresses' => 'Indirizzi della ricerca in Francia: Base Adresse Nationale, tramite la Géoplateforme dell\'IGN, con Licence Ouverte 2.0.',
			'profile.attributionAddressesOsm' => 'Indirizzi della ricerca altrove: OpenStreetMap, tramite Photon, con licenza ODbL.',
			'profile.attributionPoiOdbl' => 'Negozi e servizi: OpenStreetMap e gli orari di apertura di La Poste, con licenza ODbL.',
			'profile.attributionPoiLo' => 'Prezzi dei carburanti (Ministero dell\'Economia francese) e strutture sanitarie FINESS (Agence du numérique en santé), con Licence Ouverte 2.0 (Etalab).',
			'profile.attributionPacks' => 'Contorni delle mappe offline: Contours administratifs, data.gouv.fr (ODbL), e Natural Earth (pubblico dominio).',
			'profile.attributionOfflineLabels' => 'Nomi e icone delle mappe offline: glifi Noto Sans (SIL Open Font License 1.1) e sprite Protomaps derivati da tangrams/icons (MIT).',
			'profile.attributionExtcom' => 'Luoghi, recensioni, valutazioni e foto, in base a un accordo scritto con questa fonte.',
			'profile.creditsPlaces' => 'Luoghi',
			'profile.creditsContent' => 'Foto, testi e recensioni',
			'profile.creditsRoutes' => 'Percorsi e navigazione',
			'profile.creditsSearch' => 'Ricerca',
			'profile.creditsMap' => 'Mappa di base',
			'profile.creditsApp' => 'App',
			'profile.attributionDatatourisme' => 'Luoghi, descrizioni e foto degli uffici turistici: DATAtourisme, con Licence Ouverte 2.0; ogni testo e ogni foto indica il suo ufficio, il suo autore e la data dell\'ultimo aggiornamento.',
			'profile.attributionCommunity' => 'Recensioni, valutazioni e foto dei viaggiatori di Lunaway, con licenza CC BY 4.0 e lo pseudonimo del loro autore.',
			'profile.attributionCommons' => 'Foto di Wikimedia Commons, ciascuna con la propria licenza (CC0, pubblico dominio, CC BY o CC BY-SA), con il suo autore e un link alla sua pagina.',
			'profile.attributionPanoramax' => 'Viste dalla strada di Panoramax: istanza di OpenStreetMap France con licenza CC BY-SA 4.0, istanza dell\'IGN con Licence Ouverte 2.0.',
			'profile.attributionWikipedia' => 'Estratti di articoli di Wikipedia, con licenza CC BY-SA 4.0 e un link all\'articolo.',
			'profile.attributionMangrove' => 'Recensioni di Mangrove Reviews, con licenza CC BY 4.0 o quella dichiarata dalla recensione, e un link alla recensione.',
			'profile.attributionTranslation' => 'Traduzioni automatiche: modelli OPUS-MT dell\'Università di Helsinki, con licenza CC BY 4.0, eseguiti sui server di Lunaway.',
			'profile.attributionRoadEvents' => 'Lavori e chiusure in Francia: DIR e Bison Futé, ordinanze di circolazione DiaLog (DGITM), città metropolitane e dipartimenti (Lyon, Toulouse, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Sarthe), con Licence Ouverte 2.0; Bordeaux Métropole e dipartimento delle Côtes-d\'Armor, con Licence Ouverte; Ville de Paris, Rennes Métropole e segnalazioni dei viaggiatori di Lunaway, con licenza ODbL.',
			'profile.attributionRoadEventsAbroad' => 'Lavori e chiusure nei Paesi Bassi: NDW, Nationaal Dataportaal Wegverkeer (dati aperti); in Spagna: DGT, Dirección General de Tráfico (CC BY).',
			'profile.attributionDangerZones' => 'Autovelox e zone di pericolo: in Francia, la mappa della Sécurité routière, riutilizzata secondo il Code des relations entre le public et l\'administration francese, e l\'elenco degli autovelox fissi del Ministero dell\'Interno, Délégation à la sécurité routière (data.gouv.fr), con Licence Ouverte 2.0; in Polonia, Główny Inspektorat Transportu Drogowego (CANARD, dane.gov.pl), in Lussemburgo, l\'Administration des ponts et chaussées (data.public.lu), a Bruxelles, Bruxelles Mobilité (data.mobility.brussels), con CC0; in Norvegia, «Inneholder data under norsk lisens for offentlige data (NLOD) tilgjengeliggjort av Statens vegvesen.»; in Irlanda, le zone di controllo di An Garda Síochána, Irish Public Sector Information, CC BY, tracciati adattati da Lunaway; OpenStreetMap (ODbL).',
			'profile.attributionCameraSource' => ({required Object attribution}) => 'Autovelox e zone di pericolo: ${attribution}',
			'units.kilobytes' => ({required Object n}) => '${n} kB',
			'units.megabytes' => ({required Object n}) => '${n} MB',
			'languages.fr' => 'francese',
			'languages.en' => 'inglese',
			'languages.de' => 'tedesco',
			'languages.es' => 'spagnolo',
			'languages.it' => 'italiano',
			'languages.nl' => 'olandese',
			'translation.translate' => 'Traduci',
			'translation.translating' => 'Traduzione in corso',
			'translation.showOriginal' => 'Mostra l\'originale',
			'translation.showTranslation' => 'Mostra la traduzione',
			'translation.from.fr' => 'Tradotto automaticamente dal francese',
			'translation.from.en' => 'Tradotto automaticamente dall\'inglese',
			'translation.from.de' => 'Tradotto automaticamente dal tedesco',
			'translation.from.es' => 'Tradotto automaticamente dallo spagnolo',
			'translation.from.it' => 'Tradotto automaticamente dall\'italiano',
			'translation.from.nl' => 'Tradotto automaticamente dall\'olandese',
			'translation.from.unknown' => ({required Object language}) => 'Tradotto automaticamente (lingua originale: ${language})',
			'translation.offline' => 'Per tradurre serve una connessione a internet.',
			'translation.failedOffline' => 'Nessuna connessione: impossibile tradurre il testo.',
			'translation.busy' => 'Il servizio di traduzione è sovraccarico. Riprova più tardi.',
			'translation.unavailable' => 'La traduzione non è disponibile al momento.',
			'translation.gone' => 'Questo testo non è più disponibile.',
			'translation.unsupported' => 'Nessuna traduzione disponibile per questa lingua.',
			'translation.autoReviews' => 'Traduci automaticamente le recensioni',
			'translation.autoReviewsHint' => 'Le recensioni scritte in un\'altra lingua vengono tradotte dal server di Lunaway, senza passare da servizi esterni.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			'locale.de' => 'Deutsch',
			'locale.es' => 'Español',
			'locale.it' => 'Italiano',
			'locale.nl' => 'Nederlands',
			'account.title' => 'Il tuo account',
			'account.noneTitle' => 'Ancora nessun account',
			'account.noneBody' => 'La mappa, la ricerca e i preferiti funzionano senza account. L\'account si crea da solo al tuo primo contributo (una valutazione, una conferma, una foto), senza e-mail né password. Da quel momento le tue liste di preferiti sono collegate all\'account.',
			'account.recover' => 'Recupera il mio account',
			'account.memberSince' => ({required Object date}) => 'Membro da ${date}',
			'account.editPseudonym' => 'Cambia lo pseudonimo',
			'account.pseudonymTitle' => 'Il tuo pseudonimo',
			'account.pseudonymHint' => 'È pubblico: appare con le tue recensioni e le tue foto. Da 3 a 32 caratteri.',
			'account.pseudonymInvalid' => 'Da 3 a 32 caratteri, di cui almeno due lettere.',
			'account.pseudonymRefused' => 'Questo pseudonimo non è accettato: niente link, recapiti o parole offensive, né un nome che si spacci per il team di Lunaway.',
			'account.pseudonymSaved' => 'Pseudonimo salvato',
			'account.level' => ({required Object level}) => 'Livello di fiducia ${level}',
			'account.levelOpens.l0' => 'Puoi valutare i luoghi, confermare che ci sono ancora, segnalare un problema e sincronizzare i tuoi preferiti.',
			'account.levelOpens.l1' => 'Puoi anche scrivere recensioni, aggiungere foto e proporre modifiche ai luoghi.',
			'account.levelOpens.l2' => 'Puoi anche aggiungere luoghi.',
			'account.levelOpens.l3' => 'Le tue modifiche ai luoghi vengono applicate senza revisione.',
			'account.levelOpens.l4' => 'Partecipi alla moderazione.',
			'account.nextLevel' => ({required Object level}) => 'Per il livello ${level}',
			'account.levelTop' => 'Sei al livello più alto.',
			'account.requirement.age' => ({required Object needed, required Object current}) => 'Account creato da almeno ${needed} giorni (${current} finora)',
			'account.requirement.confirmations' => ({required Object needed, required Object current}) => '${needed} conferme di luoghi diversi (${current} finora)',
			'account.requirement.contributions' => ({required Object needed, required Object current}) => '${needed} contributi pubblicati (${current} finora)',
			'account.requirement.activeDays' => ({required Object needed, required Object current}) => '${needed} giorni di attività (${current} finora)',
			'account.requirement.noRemoval' => 'Nessun contributo rimosso dalla moderazione',
			'account.requirement.sponsor' => 'La garanzia di un membro di livello 2',
			'account.requirement.nomination' => 'Una nomina da parte della moderazione',
			'account.requirement.administration' => 'Una designazione da parte del team di Lunaway',
			'account.orInstead' => ({required Object requirement}) => 'Oppure ${requirement}',
			'account.recoveryNone' => 'Nessuna scheda di recupero creata su questo dispositivo. Senza scheda, questo account resta legato a questo dispositivo: se perdi il dispositivo, perdi anche l\'account.',
			'account.recoveryNoneAccount' => 'Ancora nessuna scheda di recupero per questo account. Senza scheda, questo account resta legato a questo dispositivo: se perdi il dispositivo, perdi anche l\'account.',
			'account.recoveryCreate' => 'Crea la mia scheda di recupero',
			'account.recoveryMade' => ({required Object date}) => 'Creata il ${date}',
			'account.recoveryRemake' => 'Ricrea',
			'account.recoveryRemakeHint' => 'Crea una nuova scheda di recupero',
			'account.contributions' => 'I miei contributi',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} contributo in attesa di invio', other: '${n} contributi in attesa di invio', ), 
			'account.mutedAuthors' => 'Autori nascosti',
			'account.devices' => 'Dispositivi',
			'account.signOut' => 'Esci',
			'account.delete' => 'Elimina il mio account',
			'account.signOutTitle' => 'Uscire dall\'account su questo dispositivo?',
			'account.signOutBody' => 'La chiave dell\'account viene cancellata da questo dispositivo. Per rientrare ti servirà la tua scheda di recupero. I tuoi preferiti restano qui.',
			'account.signOutNoCard' => 'Non hai creato una scheda di recupero su questo dispositivo. Senza scheda, questo account andrà perso per sempre.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Un contributo in attesa di invio non verrà inviato.', other: '${n} contributi in attesa di invio non verranno inviati.', ), 
			'account.signedOut' => 'Disconnesso. I tuoi preferiti restano su questo dispositivo.',
			_ => null,
		} ?? switch (path) {
			'account.lost' => 'Questo account non si apre più su questo dispositivo. Recuperalo con la tua scheda di recupero: Profilo, Recupera il mio account.',
			'account.lostAction' => 'Recupera',
			'account.welcomeTitle' => 'Grazie per il tuo primo contributo',
			'account.welcomeBody' => ({required Object name}) => 'Il tuo account è stato creato con lo pseudonimo «${name}». Niente e-mail né password: una chiave conservata su questo dispositivo. Puoi cambiare lo pseudonimo nel Profilo.',
			'account.welcomeCard' => 'Crea la tua scheda di recupero per ritrovare questo account su un altro dispositivo.',
			'account.welcomeFavorites' => 'Le tue liste di preferiti ora sono conservate con il tuo account.',
			'recovery.title' => 'Scheda di recupero',
			'recovery.intro' => 'Un codice che riporta il tuo account su un nuovo dispositivo. Lunaway ne conserva solo un\'impronta, che serve a verificarlo: il codice stesso non potrà mai più essere mostrato, e ogni nuova scheda ha un codice diverso.',
			'recovery.replaces' => 'Una nuova scheda sostituisce la precedente: il vecchio codice smetterà di funzionare.',
			'recovery.replaceTitle' => ({required Object date}) => 'Sostituire la scheda del ${date}?',
			'recovery.replaceBody' => ({required Object date}) => 'La nuova scheda avrà un altro codice. Quello della scheda del ${date} smette di funzionare da subito. Non può essere mostrato di nuovo: Lunaway ne ha conservato solo un\'impronta.',
			'recovery.replaceKeep' => 'Tieni la vecchia',
			'recovery.replaceConfirm' => 'Crea una nuova scheda',
			'recovery.make' => 'Crea la scheda',
			'recovery.codeLabel' => 'Il tuo codice di recupero',
			'recovery.shownOnce' => 'Questo codice appare una sola volta. Annotalo, o salva l\'immagine, prima di chiudere.',
			'recovery.saveImage' => 'Salva l\'immagine',
			'recovery.done' => 'Ho annotato il codice',
			'recovery.doneTitle' => 'Hai conservato il codice?',
			'recovery.doneBody' => 'Una volta chiusa questa pagina, il codice non apparirà più.',
			'recovery.keep' => 'Resta sulla pagina',
			'recovery.cardHeading' => 'Scheda di recupero Lunaway',
			'recovery.cardAccount' => ({required Object name}) => 'Account: ${name}',
			'recovery.cardHow' => 'Per recuperare l\'account: Profilo, Recupera il mio account, poi digita questo codice o fotografa la scheda.',
			'recovery.cardMade' => ({required Object date}) => 'Creata il ${date}',
			'recovery.cardWarning' => 'Questo codice apre l\'account: non darlo mai a nessuno.',
			'recovery.failed' => 'Non è stato possibile creare la scheda. Serve una connessione.',
			'recovery.fileName' => 'scheda-di-recupero-lunaway',
			'recovery.step1' => 'Crea la scheda: il codice appare una sola volta.',
			'recovery.step2' => 'Salva l\'immagine, stampala, o ricopia il codice a mano.',
			'recovery.step3' => 'Conservala nel cassetto portaoggetti, con i documenti del veicolo.',
			'recover.title' => 'Recupera il mio account',
			'recover.intro' => 'Digita il codice della tua scheda di recupero, o leggilo da una foto della scheda.',
			'recover.field' => 'Codice di recupero',
			'recover.fieldHint' => '27 caratteri, a gruppi di quattro',
			'recover.remaining' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Ancora ${n} carattere', other: 'Ancora ${n} caratteri', ), 
			'recover.invalid' => 'Questo codice non corrisponde a nessuna scheda: controlla ogni carattere.',
			'recover.valid' => 'Codice completo',
			'recover.scan' => 'Leggi la scheda da una foto',
			'recover.scanFile' => 'Scegli l\'immagine della scheda',
			'recover.reading' => 'Lettura della scheda',
			'recover.scanFailed' => 'Nessun codice leggibile in questa immagine. Prova con una foto più nitida, con la scheda ben piatta.',
			'recover.revoke' => 'Il mio vecchio dispositivo è stato perso o rubato: disconnettilo',
			'recover.revokeHint' => 'Tutti gli altri tuoi dispositivi verranno disconnessi.',
			'recover.submit' => 'Recupera l\'account',
			'recover.notFound' => 'Nessun account ha questo codice. Controlla la scheda, o creane una nuova da un dispositivo connesso.',
			'recover.tooMany' => 'Troppi tentativi per ora. Riprova tra un\'ora.',
			'recover.done' => ({required Object name}) => 'Account recuperato: ${name}',
			'deletion.title' => 'Elimina il mio account',
			'deletion.intro' => 'L\'eliminazione è immediata e definitiva.',
			'deletion.goneTitle' => 'Cosa viene eliminato',
			'deletion.gone.identity' => 'Il tuo pseudonimo e le chiavi dei tuoi dispositivi',
			'deletion.gone.sessions' => 'Le tue sessioni e il tuo codice di recupero',
			'deletion.gone.lists' => 'Le tue liste di preferiti sincronizzate e gli autori che hai nascosto',
			'deletion.gone.photos' => 'Le tue foto, le tue valutazioni senza testo e le tue segnalazioni',
			'deletion.gone.pending' => 'Le tue proposte in attesa di revisione',
			'deletion.keptTitle' => 'Cosa resta, senza il tuo nome',
			'deletion.kept' => 'Le tue recensioni scritte pubblicate, le tue conferme e le tue modifiche ai luoghi già applicate restano, senza autore: fanno parte della mappa degli altri viaggiatori.',
			'deletion.backups' => 'I backup del server vengono cancellati entro circa 30 giorni.',
			'deletion.device' => 'Su questo dispositivo i tuoi preferiti restano; la chiave dell\'account viene cancellata.',
			'deletion.web' => 'Puoi eliminarlo anche su lunaway.net con il tuo codice di recupero.',
			'deletion.webLink' => 'lunaway.net/it/account/delete',
			'deletion.confirmTitle' => 'Eliminare definitivamente?',
			'deletion.confirmBody' => ({required Object name}) => 'L\'account «${name}» e tutto ciò che è elencato vengono eliminati ora. Nessuno potrà ripristinarlo.',
			'deletion.confirmCheck' => 'Ho capito che è definitivo',
			'deletion.confirm' => 'Elimina l\'account',
			'deletion.done' => 'Account eliminato',
			'deletion.failed' => 'Non è stato possibile eliminare l\'account. Serve una connessione.',
			'devices.title' => 'Dispositivi',
			'devices.intro' => 'Ogni dispositivo ha la sua chiave. Rimuovi un dispositivo perso, o uno che non usi più.',
			'devices.thisDevice' => 'Questo dispositivo',
			'devices.other' => 'Altro dispositivo',
			'devices.added' => ({required Object date}) => 'Aggiunto il ${date}',
			'devices.lastUsed' => ({required Object when}) => 'Ultimo utilizzo ${when}',
			'devices.revoke' => 'Rimuovi',
			'devices.revokeTitle' => 'Rimuovere questo dispositivo?',
			'devices.revokeBody' => 'Verrà disconnesso e non potrà più usare l\'account.',
			'devices.revoked' => 'Dispositivo rimosso',
			'devices.signOutOthers' => 'Disconnetti tutti gli altri dispositivi',
			'devices.signedOutOthers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, zero: 'Nessun\'altra sessione aperta', one: '${n} sessione chiusa', other: '${n} sessioni chiuse', ), 
			'devices.error' => 'Non è stato possibile caricare i dispositivi. Serve una connessione.',
			'muted.title' => 'Autori nascosti',
			'muted.empty' => 'Nessuno è nascosto',
			'muted.emptyHint' => 'Per nascondere qualcuno, apri il menu di una sua recensione o di una sua foto. La scelta vale solo per te.',
			'muted.unmute' => 'Mostra di nuovo',
			'muted.unmuted' => ({required Object name}) => 'I contributi di ${name} verranno mostrati di nuovo',
			'mine.title' => 'I miei contributi',
			'mine.pending' => 'In attesa di invio',
			'mine.pendingHint' => 'Verranno inviati appena torna la rete.',
			'mine.sendNow' => 'Invia ora',
			'mine.retry' => 'Riprova',
			'mine.discard' => 'Scarta',
			'mine.discardTitle' => 'Scartare questo contributo?',
			'mine.discardBody' => 'Non verrà inviato.',
			'mine.reviews' => 'Recensioni e valutazioni',
			'mine.photos' => 'Foto',
			'mine.confirmations' => 'Conferme',
			'mine.issues' => 'Problemi segnalati',
			'mine.places' => 'Luoghi aggiunti e modifiche',
			'mine.empty' => 'Ancora niente',
			'mine.emptyHint' => 'Valutare un luogo o confermare che c\'è ancora è già un contributo.',
			'mine.latest' => ({required Object shown, required Object total}) => 'I ${shown} più recenti su ${total}',
			'mine.error' => 'Non è stato possibile caricare i tuoi contributi. Serve una connessione.',
			'mine.deleteTitle' => 'Eliminare questo contributo?',
			'mine.deleteBody' => 'Viene rimosso da Lunaway.',
			'mine.deleteApplied' => 'Questo luogo fa già parte della mappa: ci resta, senza il tuo nome.',
			'mine.deleted' => 'Contributo eliminato',
			'mine.ratingOnly' => 'Solo valutazione',
			'mine.status.published' => 'Pubblicato',
			'mine.status.pending' => 'In revisione',
			'mine.status.hidden' => 'Nascosto dopo alcune segnalazioni',
			'mine.status.removed' => 'Rimosso dalla moderazione',
			'mine.submission.proposed' => 'In attesa di revisione',
			'mine.submission.accepted' => 'Accettato',
			'mine.submission.applied' => 'Sulla mappa',
			'mine.submission.rejected' => 'Rifiutato',
			'mine.submission.withdrawn' => 'Ritirato',
			'mine.newPlace' => 'Nuovo luogo',
			'mine.edit' => 'Modifica',
			'mine.aPlace' => 'Un luogo',
			'mine.newVendingMachine' => 'Nuovo distributore automatico',
			'mine.poiConfirmations' => 'Negozi e servizi confermati',
			'mine.aPoi' => 'Un negozio o un servizio',
			'outbox.kind.rate' => ({required Object stars}) => 'Valutazione di ${stars} su 5',
			'outbox.kind.review' => 'Recensione',
			'outbox.kind.deleteReview' => 'Eliminazione di una recensione',
			'outbox.kind.confirm' => ({required Object status}) => 'Conferma: ${status}',
			'outbox.kind.deleteConfirmation' => 'Eliminazione di una conferma',
			'outbox.kind.reportIssue' => ({required Object kind}) => 'Problema segnalato: ${kind}',
			'outbox.kind.deleteIssueReport' => 'Eliminazione di una segnalazione',
			'outbox.kind.reportContent' => 'Segnalazione ai moderatori',
			'outbox.kind.addPlace' => ({required Object name}) => 'Nuovo luogo: ${name}',
			'outbox.kind.editPlace' => 'Modifica di un luogo',
			'outbox.kind.deletePlaceSubmission' => 'Ritiro di un luogo proposto',
			'outbox.kind.photo' => 'Foto',
			'outbox.kind.deletePhoto' => 'Eliminazione di una foto',
			'outbox.kind.mute' => 'Nascondere un autore',
			'outbox.kind.unmute' => 'Mostrare di nuovo un autore',
			'outbox.kind.poiThere' => 'Ancora lì: un negozio o un servizio',
			'outbox.kind.poiGone' => 'Non c\'è più: un negozio o un servizio',
			'outbox.kind.addVendingMachine' => 'Nuovo distributore automatico',
			'outbox.kind.deletePoiConfirmation' => 'Eliminazione di una risposta su un negozio o un servizio',
			'outbox.kind.reportRoadEvent' => ({required Object kind}) => 'Segnalazione stradale: ${kind}',
			'outbox.kind.clearRoadEvent' => 'Fine di una segnalazione stradale',
			'outbox.waiting' => 'In attesa della rete',
			'outbox.sending' => 'Invio in corso',
			'outbox.error.forbidden' => 'Rifiutato: il tuo livello non lo consente ancora.',
			'outbox.error.notFound' => 'Rifiutato: il luogo o il contenuto non esiste più.',
			'outbox.error.invalid' => 'Rifiutato: controlla il testo (lunghezza, link, recapiti).',
			'outbox.error.unreadablePhoto' => 'Foto rifiutata: illeggibile, o già inviata.',
			'outbox.error.photoTooLarge' => 'Foto rifiutata: troppo pesante.',
			'outbox.error.placeRefused' => 'Il nuovo luogo di questa foto è stato rifiutato.',
			'outbox.error.fileLost' => 'La foto non è più sul dispositivo.',
			'outbox.error.otherAccount' => 'Preparato per un altro account: non verrà inviato.',
			'outbox.error.other' => 'Rifiutato dal server.',
			'outbox.error.duplicate' => 'Rifiutato: lo stesso distributore automatico è già indicato entro 25 m.',
			'outbox.sent' => 'Grazie, inviato',
			'outbox.queued' => 'Nessuna rete: verrà inviato appena torna',
			'outbox.refused' => ({required Object reason}) => 'Non inviato. ${reason}',
			'placement.title' => 'Posiziona il luogo',
			'placement.hint' => 'Sposta la mappa: la croce indica il punto esatto.',
			'placement.confirm' => 'Conferma questa posizione',
			'placement.duplicate' => ({required Object name, required Object distance}) => 'C\'è già «${name}» a ${distance}: è lo stesso luogo?',
			'placement.same' => 'Sì, apri la sua scheda',
			'placement.notSame' => 'No, è un altro luogo',
			'contribute.yourRating' => 'La tua valutazione',
			'contribute.rateHint' => 'Tocca una stella per valutare',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Valuta con ${n} stella', other: 'Valuta con ${n} stelle', ), 
			'contribute.writeReview' => 'Scrivi una recensione',
			'contribute.editReview' => 'Modifica la tua recensione',
			'contribute.deleteReview' => 'Elimina la tua recensione',
			'contribute.deleteReviewTitle' => 'Eliminare la tua recensione?',
			'contribute.deleteReviewBody' => 'Il testo e la valutazione spariscono dalla scheda.',
			'contribute.deleteRating' => 'Rimuovi la tua valutazione',
			'contribute.deleteRatingTitle' => 'Rimuovere la tua valutazione?',
			'contribute.deleteRatingBody' => 'La tua valutazione sparisce dalla scheda del luogo.',
			'contribute.pendingSend' => 'In attesa di invio',
			'contribute.statusPending' => 'In revisione: per ora visibile solo a te',
			'contribute.statusHidden' => 'Nascosto dopo alcune segnalazioni, in attesa di un moderatore',
			'contribute.statusRemoved' => 'Rimosso dalla moderazione',
			'contribute.addPhoto' => 'Aggiungi una foto',
			'contribute.firstPhoto' => 'Aggiungi la prima foto',
			'contribute.stillThere' => 'C\'è ancora?',
			'contribute.more' => 'Altre azioni',
			'contribute.reportIssue' => 'Segnala un problema',
			'contribute.proposeEdit' => 'Proponi una modifica',
			'contribute.editPlace' => 'Modifica il luogo',
			'contribute.reportPlace' => 'Segnala questo luogo ai moderatori',
			'contribute.toVerifyTitle' => 'Da verificare',
			'contribute.toVerifyBody' => 'Luogo aggiunto dalla comunità, in attesa di due conferme. Lo conosci? Confermalo.',
			'contribute.issuesTitle' => 'Segnalazioni degli ultimi 30 giorni',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlaceHere' => 'Aggiungi un luogo qui',
			'contribute.addPlaceHint' => 'Il punto scelto sotto la croce.',
			'confirmSheet.title' => 'C\'è ancora?',
			'confirmSheet.body' => 'Ci sei passato di recente? La tua risposta mostra ai prossimi viaggiatori che la scheda è aggiornata. Non viene inviata alcuna posizione.',
			'confirmSheet.stillOk' => 'Sì, come descritto',
			'confirmSheet.closed' => 'Chiuso',
			'confirmSheet.changed' => 'Cambiato',
			'confirmSheet.closedHint' => 'Non accoglie più viaggiatori',
			'confirmSheet.changedHint' => 'C\'è ancora, ma qualcosa è cambiato',
			'confirmSheet.note' => 'Qualcosa da aggiungere? (facoltativo)',
			'confirmSheet.noteHint' => 'Per esempio: barra limitatrice installata, colonnina spostata',
			'confirmSheet.status.stillOk' => 'c\'è ancora',
			'confirmSheet.status.closed' => 'chiuso',
			'confirmSheet.status.changed' => 'cambiato',
			'issueSheet.title' => 'Segnala un problema',
			'issueSheet.body' => 'La tua segnalazione contribuisce all\'avviso mostrato sulla scheda. La nota la leggono solo i moderatori.',
			'issueSheet.kind.nightBan' => 'Pernottamento ora vietato',
			'issueSheet.kind.serviceBroken' => 'Servizio guasto',
			'issueSheet.kind.noAccess' => 'Accesso impossibile',
			'issueSheet.kind.danger' => 'Pericolo',
			'issueSheet.hint.nightBan' => 'Un cartello, un\'ordinanza comunale, un controllo della polizia',
			'issueSheet.hint.serviceBroken' => 'Colonnina, acqua, scarico o corrente fuori servizio',
			'issueSheet.hint.noAccess' => 'Una sbarra, lavori, una strada chiusa',
			'issueSheet.hint.danger' => 'Furti, aggressioni, terreno instabile',
			'issueSheet.note' => 'Qualcosa da aggiungere? (facoltativo)',
			'issueSheet.send' => 'Segnala',
			'reportSheet.review' => 'Segnala questa recensione',
			'reportSheet.photo' => 'Segnala questa foto',
			'reportSheet.place' => 'Segnala questo luogo',
			'reportSheet.body' => 'I moderatori la esamineranno. L\'autore non saprà chi ha fatto la segnalazione.',
			'reportSheet.reason.spam' => 'Pubblicità o ripetizioni',
			'reportSheet.reason.offensive' => 'Offensivo, che incita all\'odio o scioccante',
			'reportSheet.reason.wrong' => 'Falso o fuorviante',
			'reportSheet.reason.privacy' => 'Mostra o nomina una persona, una targa, un indirizzo privato',
			'reportSheet.reason.other' => 'Altro motivo',
			'reportSheet.note' => 'Aggiungi dettagli (facoltativo)',
			'reportSheet.noteOther' => 'Spiega cosa non va',
			'reportSheet.sent' => 'Grazie, i moderatori daranno un\'occhiata',
			'reportSheet.mute' => ({required Object name}) => 'Nascondi recensioni e foto di ${name}',
			'reportSheet.muteAuthor' => 'Nascondi questo autore',
			'reportSheet.muteTitle' => ({required Object name}) => 'Nascondere ${name}?',
			'reportSheet.muteBody' => 'Le sue recensioni e le sue foto non ti verranno più mostrate. Puoi cambiare idea nel Profilo.',
			'reportSheet.muted' => ({required Object name}) => 'Contributi di ${name} nascosti',
			'reportSheet.deletePhoto' => 'Elimina la mia foto',
			'reportSheet.deletePhotoTitle' => 'Eliminare questa foto?',
			'reportSheet.deletePhotoBody' => 'Viene rimossa dalla scheda e dai nostri server.',
			'reviewSheet.titleNew' => 'La tua recensione',
			'reviewSheet.titleEdit' => 'Modifica la tua recensione',
			'reviewSheet.starsRequired' => 'Scegli una valutazione da 1 a 5',
			'reviewSheet.text' => 'La tua recensione',
			'reviewSheet.textHint' => 'La tranquillità, l\'accoglienza, lo spazio per manovrare, cosa ti è stato utile',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Ancora almeno ${n} carattere', other: 'Ancora almeno ${n} caratteri', ), 
			'reviewSheet.visited' => 'Data del soggiorno',
			'reviewSheet.visitedNone' => 'Non indicata',
			'reviewSheet.vehicle' => 'Il tuo veicolo',
			'reviewSheet.vehicleNone' => 'Preferisco non dirlo',
			'reviewSheet.licence' => 'Pubblicata con licenza CC BY 4.0, con il tuo pseudonimo. La data del soggiorno è facoltativa: messe insieme, le date delle tue recensioni possono rivelare il tuo itinerario.',
			'reviewSheet.publish' => 'Pubblica la recensione',
			'gate.review' => 'Recensioni scritte: dal livello 1',
			'gate.photo' => 'Foto: dal livello 1',
			'gate.addPlace' => 'Aggiunta di luoghi: dal livello 2',
			'gate.edit' => 'Proposte di modifica: dal livello 1',
			'gate.why' => 'I livelli proteggono la mappa dagli abusi. Arrivano con il tempo e i contributi, senza niente da comprare.',
			'gate.yourLevel' => ({required Object level}) => 'Il tuo livello: ${level}',
			'gate.noAccount' => 'Ancora nessun account: un account parte dal livello 0.',
			'gate.later' => ({required Object level}) => 'Il livello ${level} arriva dopo i precedenti, con il tempo e i contributi pubblicati.',
			'gate.meanwhile' => 'Nel frattempo puoi valutare i luoghi, confermare che ci sono ancora o segnalare un problema.',
			'photoFlow.title' => 'Aggiungi una foto',
			'photoFlow.camera' => 'Scatta una foto',
			'photoFlow.gallery' => 'Scegli dalla galleria',
			'photoFlow.preparing' => 'Preparazione della foto',
			'photoFlow.licence' => 'Pubblicata con licenza CC BY 4.0, con il tuo pseudonimo. Evita volti e targhe.',
			'photoFlow.stripped' => 'La posizione e i dati del dispositivo vengono rimossi prima dell\'invio.',
			'photoFlow.send' => 'Invia la foto',
			'photoFlow.unreadable' => 'Questa immagine non può essere letta su questo dispositivo. Prova con una foto JPEG o PNG.',
			'photoFlow.sending' => ({required Object percent}) => 'Invio ${percent}%',
			'photoFlow.pending' => 'Foto in attesa di invio',
			'placeForm.addTitle' => 'Aggiungi un luogo',
			'placeForm.editTitle' => 'Modifica il luogo',
			'placeForm.proposeTitle' => 'Proponi una modifica',
			'placeForm.position' => 'Posizione sulla mappa',
			'placeForm.kind' => 'Tipo di luogo',
			'placeForm.kindRequired' => 'Scegli un tipo di luogo',
			'placeForm.name' => 'Nome',
			'placeForm.nameHint' => 'Il nome indicato sul posto, o una breve descrizione',
			'placeForm.nameInvalid' => 'Da 2 a 120 caratteri',
			'placeForm.night' => 'Pernottamento',
			'placeForm.services' => 'Servizi sul posto',
			'placeForm.description' => 'Descrizione',
			'placeForm.descriptionHint' => 'Ciò che aiuta a trovare e a scegliere il luogo',
			'placeForm.details' => 'Dettagli',
			'placeForm.priceNight' => 'Prezzo a notte (€)',
			'placeForm.priceServices' => 'Prezzo dei servizi (€)',
			'placeForm.maxHeight' => 'Altezza massima (m)',
			'placeForm.capacity' => 'Posti',
			'placeForm.website' => 'Sito web',
			'placeForm.phone' => 'Telefono',
			'placeForm.photo' => 'Foto (facoltativa)',
			'placeForm.photoReady' => 'Foto pronta',
			'placeForm.removePhoto' => 'Rimuovi la foto',
			'placeForm.toVerify' => 'Il luogo apparirà come «da verificare» finché altri due viaggiatori non lo confermeranno.',
			'placeForm.licence' => 'I luoghi sono pubblicati con licenza ODbL, attribuiti ai contributori di Lunaway.',
			'placeForm.moderated' => 'Un sito web o un numero di telefono passa da un moderatore prima di essere pubblicato.',
			'placeForm.direct' => 'Con il tuo livello la modifica viene applicata subito.',
			'placeForm.proposal' => 'Un moderatore esaminerà la tua proposta prima che venga applicata.',
			'placeForm.submitAdd' => 'Aggiungi il luogo',
			'placeForm.submitEdit' => 'Salva la modifica',
			'placeForm.submitPropose' => 'Invia la proposta',
			'placeForm.nothingChanged' => 'Non è cambiato niente',
			'placeForm.invalidNumber' => 'Inserisci un numero',
			'placeForm.invalidWebsite' => 'Un indirizzo che inizia con http:// o https://',
			'placeForm.added' => 'Grazie: il luogo arriva sulla mappa tra un attimo',
			'placeForm.proposed' => 'Grazie: la tua proposta passa in revisione',
			'favoritesSync.local' => 'Solo su questo dispositivo',
			'favoritesSync.action' => 'Sincronizza',
			'favoritesSync.syncing' => 'Sincronizzazione in corso',
			'favoritesSync.synced' => ({required Object when}) => 'Conservati con il tuo account, sincronizzati ${when}',
			'favoritesSync.failed' => 'Impossibile sincronizzare al momento',
			'favoritesSync.title' => 'Sincronizzare i tuoi preferiti?',
			'favoritesSync.body' => 'Le tue liste verranno conservate con un account Lunaway, senza e-mail né password, per ritrovarle su un altro dispositivo. L\'account viene creato ora.',
			'favoritesSync.confirm' => 'Crea l\'account e sincronizza',
			'poi.category.groceries' => 'Spesa',
			'poi.category.vending' => 'Distributori automatici',
			'poi.category.water' => 'Acqua e scarico',
			'poi.category.fuel' => 'Carburante ed energia',
			'poi.category.health' => 'Salute',
			'poi.category.services' => 'Servizi',
			'poi.category.food' => 'Ristoranti e bar',
			'poi.category.sights' => 'Da vedere',
			'poi.kind.supermarket' => 'Supermercato',
			'poi.kind.convenience' => 'Minimarket',
			'poi.kind.bakery' => 'Panetteria',
			'poi.kind.butcher' => 'Macelleria',
			'poi.kind.greengrocer' => 'Fruttivendolo',
			'poi.kind.farmShop' => 'Vendita diretta in fattoria',
			'poi.kind.marketplace' => 'Mercato',
			'poi.kind.vendingPizza' => 'Distributore di pizza',
			'poi.kind.vendingBread' => 'Distributore di pane',
			'poi.kind.vendingFarmProducts' => 'Distributore di prodotti agricoli',
			'poi.kind.vendingEggsMilk' => 'Distributore di uova e latte',
			'poi.kind.vendingIce' => 'Distributore di ghiaccio',
			'poi.kind.vendingOther' => 'Distributore automatico di alimenti',
			'poi.kind.drinkingWater' => 'Acqua potabile',
			'poi.kind.waterPoint' => 'Punto acqua',
			'poi.kind.dumpStation' => 'Punto di scarico',
			'poi.kind.toilets' => 'Bagni',
			'poi.kind.shower' => 'Docce',
			'poi.kind.fuelStation' => 'Distributore',
			'poi.kind.evCharging' => 'Colonnina di ricarica',
			'poi.kind.gasBottles' => 'Bombole del gas',
			'poi.kind.pharmacy' => 'Farmacia',
			'poi.kind.doctor' => 'Medico',
			'poi.kind.hospital' => 'Ospedale',
			'poi.kind.veterinary' => 'Veterinario',
			'poi.kind.laundry' => 'Lavanderia',
			'poi.kind.atm' => 'Bancomat',
			'poi.kind.postOffice' => 'Ufficio postale',
			'poi.kind.touristOffice' => 'Ufficio turistico',
			'poi.kind.recyclingCentre' => 'Isola ecologica',
			'poi.kind.carRepair' => 'Officina',
			'poi.kind.carWash' => 'Autolavaggio',
			'poi.kind.motorhomeShop' => 'Concessionaria e officina camper',
			'poi.kind.outdoorShop' => 'Negozio di campeggio e outdoor',
			'poi.kind.restaurant' => 'Ristorante',
			'poi.kind.cafe' => 'Bar',
			'poi.kind.fastFood' => 'Fast food',
			'poi.kind.viewpoint' => 'Punto panoramico',
			'poi.kind.attraction' => 'Attrazione',
			'poi.kind.museum' => 'Museo',
			'poi.chipsLabel' => 'Negozi e servizi nei dintorni',
			'poi.openNow' => 'Aperto ora',
			'poi.vendingSells.pizza' => 'Pizza',
			'poi.vendingSells.bread' => 'Pane',
			'poi.vendingSells.farmProducts' => 'Prodotti agricoli',
			'poi.vendingSells.eggsMilk' => 'Uova e latte',
			'poi.vendingSells.ice' => 'Ghiaccio',
			'poi.vendingAll' => 'Tutti i distributori di alimenti',
			'poi.vendingMenu' => 'Cosa vendono i distributori',
			'poi.vendingChip.pizza' => 'Distributori di pizza',
			'poi.vendingChip.bread' => 'Distributori di pane',
			'poi.vendingChip.farmProducts' => 'Distributori di prodotti agricoli',
			'poi.vendingChip.eggsMilk' => 'Distributori di uova e latte',
			'poi.vendingChip.ice' => 'Distributori di ghiaccio',
			'poi.alwaysOpen' => 'Aperto giorno e notte',
			'poi.hoursUnknown' => 'Orari sconosciuti',
			'poi.maybeClosed' => 'Chiuso secondo il registro ufficiale francese delle strutture sanitarie (FINESS).',
			'poi.maybeClosedSince' => ({required Object date}) => 'Indicato come chiuso da FINESS dal ${date}: potrebbe aver chiuso definitivamente.',
			'poi.seasonal' => 'Stagionale: potrebbe essere chiuso in inverno.',
			'poi.fee' => 'A pagamento',
			'poi.free' => 'Gratuito',
			'poi.stillThereTitle' => 'C\'è ancora?',
			'poi.stillThereHint' => 'L\'hai visto di recente? La tua risposta aiuta i prossimi viaggiatori. Non viene inviata alcuna posizione.',
			'poi.stillThere' => 'C\'è ancora',
			'poi.gone' => 'Non c\'è più',
			'poi.lastConfirmed' => ({required Object when}) => 'Presenza confermata ${when}',
			'poi.checkedOn' => ({required Object date}) => 'Verificato sul posto il ${date}',
			'poi.thanksThere' => 'Grazie, annotato: c\'è ancora.',
			'poi.thanksGone' => 'Grazie, annotato: non c\'è più.',
			'poi.fuelPrices' => 'Prezzi dei carburanti',
			'poi.perLitre' => ({required Object price}) => '${price}/l',
			'poi.priceUpdated' => ({required Object when}) => 'Prezzo aggiornato ${when}',
			'poi.feedRead' => ({required Object when}) => 'Prezzi rilevati ${when}',
			'poi.shortageTemporary' => 'Temporaneamente esaurito',
			'poi.shortageDefinitive' => 'Non più in vendita',
			'poi.selfService24h' => 'Pagamento con carta 24 ore su 24',
			'poi.highway' => 'In autostrada',
			'poi.lpgYes' => 'Vende GPL',
			'poi.fuel.diesel' => 'Gasolio',
			'poi.fuel.sp95' => 'Benzina 95',
			'poi.fuel.e10' => 'Benzina E10',
			'poi.fuel.sp98' => 'Benzina 98',
			'poi.fuel.e85' => 'E85',
			'poi.fuel.lpg' => 'GPL',
			'poi.products' => 'Vende',
			'poi.paymentTitle' => 'Pagamento',
			'poi.product.pizza' => 'Pizza',
			'poi.product.bread' => 'Pane',
			'poi.product.eggs' => 'Uova',
			'poi.product.milk' => 'Latte',
			'poi.product.cheese' => 'Formaggio',
			'poi.product.meat' => 'Carne',
			'poi.product.vegetables' => 'Verdura',
			'poi.product.fruit' => 'Frutta',
			'poi.product.honey' => 'Miele',
			'poi.product.ice' => 'Ghiaccio',
			'poi.product.potatoes' => 'Patate',
			'poi.product.food' => 'Alimentari',
			'poi.payment.cash' => 'Contanti',
			'poi.payment.coins' => 'Monete',
			'poi.payment.notes' => 'Banconote',
			'poi.payment.cards' => 'Carta',
			'poi.payment.contactless' => 'Contactless',
			'poi.payment.app' => 'App',
			'poi.justNow' => 'poco fa',
			'poi.minutesAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} minuto fa', other: '${n} minuti fa', ), 
			'poi.hoursAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} ora fa', other: '${n} ore fa', ), 
			'poi.readOffline' => ({required Object when}) => 'Rilevato ${when}: nessuna rete per aggiornarlo',
			'poi.readStale' => ({required Object when}) => 'Rilevato ${when}: al momento non è stato possibile aggiornarlo.',
			'poi.goneTitle' => 'Questo punto non è più sulla mappa',
			'poi.goneHint' => 'Alcuni viaggiatori hanno detto che non c\'è più, oppure l\'ultimo aggiornamento l\'ha rimosso.',
			'poi.loadError' => 'Non è stato possibile caricare i dettagli. Qui sopra trovi le informazioni già presenti sulla mappa.',
			'poi.around' => 'Intorno a questo luogo',
			'poi.aroundEmpty' => 'Nessun negozio né servizio noto qui intorno.',
			'poi.aroundError' => 'Non è stato possibile caricare i negozi e i servizi nei dintorni.',
			'poi.aroundOffline' => 'Nessuna rete: i negozi e i servizi nei dintorni appariranno quando sarai connesso.',
			'poi.onSite' => 'Sul posto',
			'poi.backTo' => ({required Object name}) => 'Torna a ${name}',
			'poi.backToPlace' => 'Torna al luogo',
			'poi.linkError' => 'Non è stato possibile aprire questo negozio o servizio: nessuna rete, oppure non è più sulla mappa.',
			'poi.searchSection' => 'Negozi e servizi',
			'poi.searching' => 'Ricerca di negozi e servizi',
			'poi.searchOffline' => 'Negozi e servizi si cercano online: ora non c\'è rete.',
			'poi.add.title' => 'Un distributore automatico qui?',
			'poi.add.hint' => 'Scegli cosa vende: verrà aggiunto alla mappa di tutti i viaggiatori.',
			'poi.add.pizza' => 'Pizza',
			'poi.add.bread' => 'Pane',
			'poi.add.other' => 'Altri alimenti',
			'poi.add.gate' => 'Aggiunta di un distributore automatico',
			'poi.add.sent' => 'Grazie: il distributore appare sulla mappa entro pochi minuti.',
			'poi.add.duplicateTitle' => 'Già sulla mappa',
			'poi.add.duplicateBody' => 'Un distributore dello stesso tipo è già indicato entro 25 m. C\'è ancora?',
			'poi.add.duplicateThere' => 'Sì, c\'è ancora',
			'poi.add.duplicateGone' => 'No, non c\'è più',
			'poi.cheapest.title' => 'I più economici vicino a me',
			'poi.cheapest.show' => 'I più economici qui intorno',
			'poi.cheapest.zoomIn' => 'Ingrandisci per confrontare i prezzi dei distributori.',
			'poi.cheapest.none' => 'Nessun distributore sulla mappa vende questo carburante.',
			'poi.cheapest.noneHint' => 'Sposta la mappa o scegli un altro carburante.',
			'poi.cheapest.error' => 'Non è stato possibile caricare i prezzi dei distributori.',
			'poi.trend.title' => ({required Object fuel}) => '${fuel}: prezzi degli ultimi giorni',
			'poi.trend.none' => 'Lunaway non ha ancora visto un prezzo di questo carburante qui.',
			'poi.trend.failed' => 'Al momento non è stato possibile leggere i prezzi degli ultimi giorni.',
			'poi.trend.week' => 'Ultimi 7 giorni:',
			'poi.trend.month' => 'Ultimi 30 giorni:',
			'poi.trend.range' => ({required Object low, required Object high}) => 'da ${low} a ${high}',
			'poi.trend.span' => ({required Object range, required Object move}) => '${range}, ${move}',
			'poi.trend.oneDay' => 'un solo giorno rilevato',
			'poi.trend.steady' => 'stabile',
			'poi.trend.down' => ({required Object amount}) => 'in calo di ${amount}',
			'poi.trend.up' => ({required Object amount}) => 'in aumento di ${amount}',
			'poi.trend.since' => ({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} giorno con prezzi rilevati da Lunaway dal ${date}; i giorni senza rilevazione restano vuoti', other: '${n} giorni con prezzi rilevati da Lunaway dal ${date}; i giorni senza rilevazione restano vuoti', ), 
			'poi.marketDays' => 'Giorni di mercato',
			'poi.vehicles.motorhomeYes' => 'Accetta camper',
			'poi.vehicles.motorhomeNo' => 'Camper non ammessi',
			'poi.vehicles.hgvYes' => 'Accetta mezzi pesanti',
			'poi.vehicles.hgvNo' => 'Mezzi pesanti non ammessi',
			'poi.vehicles.maxHeight' => ({required Object height}) => 'Altezza massima: ${height}',
			'offlineMaps.title' => 'Mappe offline',
			'offlineMaps.intro' => 'Prima di partire, conserva una regione sul dispositivo: i suoi luoghi per cercare e scegliere, la sua mappa per vedere le strade senza rete.',
			'offlineMaps.webTitle' => 'Le mappe offline sono nell\'app',
			'offlineMaps.web' => 'Le app per Android e iOS conservano le regioni per il viaggio. In un browser, la mappa ha bisogno della rete.',
			'offlineMaps.desktopTitle' => 'Le mappe offline sono sul telefono',
			'offlineMaps.desktop' => 'Le app per Android e iOS conservano le regioni per il viaggio. Su un computer, la mappa ha bisogno della rete.',
			'offlineMaps.unreadable' => 'Non è stato possibile caricare le mappe offline di questo dispositivo.',
			'offlineMaps.none' => 'Ancora nessuna regione su questo dispositivo.',
			'offlineMaps.used' => ({required Object size}) => 'Spazio occupato: ${size}',
			'offlineMaps.downloads' => 'Download in corso',
			'offlineMaps.installed' => 'Su questo dispositivo',
			'offlineMaps.suggested' => 'Suggerite',
			'offlineMaps.here' => 'Dove ti trovi',
			'offlineMaps.favoritesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${n} preferito in questa regione', other: '${n} preferiti in questa regione', ), 
			'offlineMaps.france' => 'Francia',
			'offlineMaps.overseas' => 'Francia d\'oltremare',
			'offlineMaps.countries' => 'Paesi',
			'offlineMaps.downloadNamed' => ({required Object name, required Object size}) => 'Scarica ${name}, ${size}',
			'offlineMaps.pause' => 'Metti in pausa',
			'offlineMaps.resume' => 'Riprendi',
			'offlineMaps.cancel' => 'Interrompi ed elimina il download',
			'offlineMaps.waiting' => 'In attesa del suo turno',
			'offlineMaps.progress' => ({required Object done, required Object total}) => '${done} di ${total}',
			'offlineMaps.paused' => ({required Object done, required Object total}) => 'In pausa: ${done} di ${total}',
			'offlineMaps.verifying' => 'Verifica del file',
			'offlineMaps.failedNetwork' => 'Interrotto: nessuna rete. Riprenderà da dove si è fermato appena torna la rete.',
			'offlineMaps.failedServer' => 'Il server ha inviato qualcosa di diverso dalla mappa. Riprova più tardi.',
			'offlineMaps.failedCorrupt' => 'Il file è arrivato danneggiato ed è stato eliminato. Riprova.',
			'offlineMaps.failedStorage' => 'Spazio insufficiente sul dispositivo. Libera un po\' di spazio, poi riprova.',
			'offlineMaps.keepOpen' => 'Tieni l\'app aperta durante il download: si interrompe quando l\'app passa in background e riprende quando ci torni.',
			'offlineMaps.dataOf' => ({required Object date}) => 'dati del ${date}',
			'offlineMaps.update' => ({required Object size}) => 'Aggiorna, ${size}',
			'offlineMaps.deleteNamed' => ({required Object name}) => 'Elimina ${name}',
			_ => null,
		} ?? switch (path) {
			'offlineMaps.deleteTitle' => ({required Object name}) => 'Eliminare ${name} da questo dispositivo?',
			'offlineMaps.deleteBody' => 'Non sarà più visibile senza rete. Potrai scaricarla di nuovo.',
			'offlineMaps.listOffline' => 'L\'elenco delle regioni ha bisogno della rete.',
			'offlineMaps.listCopy' => 'Elenco conservato dall\'ultima connessione.',
			'offlineMaps.entryHint' => 'Per viaggiare senza rete',
			'offlineMaps.entryCount' => ({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Mappe: ${n} regione, ${size}', other: 'Mappe: ${n} regioni, ${size}', ), 
			'offlineMaps.noticePack' => ({required Object name}) => 'Offline: mappa scaricata, ${name}',
			'offlineMaps.noticeOutside' => 'Offline: quest\'area non è scaricata',
			'offlineMaps.noticePlacesOnly' => 'Offline: luoghi sul dispositivo, mappa di quest\'area da scaricare',
			'offlineMaps.noticeNone' => 'Offline: scarica una regione per la prossima volta',
			'offlineMaps.noticeOnline' => 'Offline: la mappa ha bisogno della rete',
			'offlineMaps.placesTitle' => 'Luoghi',
			'offlineMaps.placesHint' => 'Pochi megabyte per regione: elenco, ricerca, schede e filtri funzionano senza rete.',
			'offlineMaps.mapsTitle' => 'Mappe',
			'offlineMaps.mapsHint' => 'Tutte le strade, qualche centinaio di megabyte per regione: la mappa si vede senza rete.',
			'offlineMaps.entryPlaces' => ({required Object names}) => 'Luoghi: ${names}',
			'offlineMaps.entryPlacesCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Luoghi: ${n} regione', other: 'Luoghi: ${n} regioni', ), 
			'regions.pickerTitle' => 'Quali luoghi tenere su questo dispositivo?',
			'regions.pickerIntro' => 'Ogni regione si scarica una volta, poi si aggiorna con piccoli download. Potrai aggiungere o rimuovere regioni più tardi in Mappe offline.',
			'regions.nearYou' => ({required Object name}) => 'Vicino a te: ${name}',
			'regions.findMine' => 'Trova la mia regione',
			'regions.locating' => 'Ricerca della tua regione',
			'regions.notCovered' => 'Ancora nessuna regione Lunaway intorno a te',
			'regions.wholeFrance' => 'Tutta la Francia',
			'regions.showFrance' => 'Mostra le regioni della Francia',
			'regions.hideFrance' => 'Nascondi le regioni della Francia',
			'regions.packInfo' => ({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: '${count} luogo, ${size}', other: '${count} luoghi, ${size}', ), 
			'regions.noPack' => 'Senza pacchetto: luoghi ricevuti con gli aggiornamenti, dimensione sconosciuta',
			'regions.download' => ({required Object size}) => 'Scarica, ${size}',
			'regions.unavailable' => 'Il server non offre ancora regioni: Lunaway conserva tutta la Francia.',
			'regions.listFailed' => 'L\'elenco delle regioni ha bisogno della rete.',
			'regions.choose' => 'Scegli le regioni',
			'regions.noneKept' => 'Nessuna regione conservata: la mappa non ha luoghi offline.',
			'regions.change' => 'Aggiungi o rimuovi regioni',
			'regions.removeNamed' => ({required Object name}) => 'Rimuovi ${name}',
			'regions.removed' => ({required Object name}) => '${name}: luoghi rimossi da questo dispositivo',
			'regions.downloading' => ({required Object done, required Object total}) => 'Download, ${done} di ${total}',
			'regions.updating' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('it'))(n, one: 'Aggiornamento, ${count} luogo', other: 'Aggiornamento, ${count} luoghi', ), 
			'regions.waiting' => 'in attesa del download',
			'regions.downloadingNamed' => ({required Object name}) => 'Download dei luoghi: ${name}',
			'regions.updated' => ({required Object when}) => 'ultimo aggiornamento ${when}',
			'regions.offerTitle' => ({required Object name}) => '${name}: conservare i luoghi offline?',
			'regions.downloadThis' => 'Scarica questa regione',
			'regions.notHere' => ({required Object name}) => '${name} non è su questo dispositivo',
			'regions.updatesOnMobile' => 'Aggiorna con i dati mobili',
			'regions.updatesOnMobileHint' => 'Altrimenti le regioni già scaricate si aggiornano in Wi-Fi. Un nuovo download usa qualsiasi rete.',
			'roadReport.actionHint' => 'Segnala un problema sulla strada',
			'roadReport.title' => 'Cosa vedi sulla strada?',
			'roadReport.intro' => 'La tua segnalazione avvisa gli altri viaggiatori. Quando due account affidabili segnalano la stessa cosa, i percorsi la evitano. I controlli di polizia non si segnalano.',
			'roadReport.kinds.closure' => 'Strada chiusa',
			'roadReport.kinds.works' => 'Lavori stradali',
			'roadReport.kinds.narrowPassage' => 'Strettoia',
			'roadReport.kinds.lowClearance' => 'Altezza limitata',
			'roadReport.kinds.other' => 'Problema sulla strada',
			'roadReport.height' => ({required Object value}) => 'Altezza indicata: ${value}',
			'roadReport.send' => 'Segnala',
			'roadReport.sent' => 'Grazie: gli altri viaggiatori sono avvisati.',
			'roadReport.stillThere' => 'C\'è ancora',
			'roadReport.over' => 'Non c\'è più',
			'roadReport.overSent' => 'Grazie: annotato.',
			'roadReport.fromMap' => 'Segnala un problema qui',
			'roadReport.notHereTitle' => 'Segnalazioni non disponibili qui',
			'roadReport.lower' => '10 cm in meno',
			'roadReport.higher' => '10 cm in più',
			'roadReport.passed' => ({required Object what}) => 'Appena superato: ${what}. C\'è ancora?',
			'roadReport.notHere' => ({required Object countries}) => 'Lunaway accetta segnalazioni dove una fonte ufficiale le può verificare: ${countries}.',
			'countries.ad' => 'Andorra',
			'countries.at' => 'Austria',
			'countries.ax' => 'Isole Åland',
			'countries.be' => 'Belgio',
			'countries.ch' => 'Svizzera',
			'countries.cz' => 'Repubblica Ceca',
			'countries.de' => 'Germania',
			'countries.dk' => 'Danimarca',
			'countries.eh' => 'Sahara Occidentale',
			'countries.es' => 'Spagna',
			'countries.fi' => 'Finlandia',
			'countries.fr' => 'Francia',
			'countries.gb' => 'Regno Unito',
			'countries.gi' => 'Gibilterra',
			'countries.gr' => 'Grecia',
			'countries.hr' => 'Croazia',
			'countries.ie' => 'Irlanda',
			'countries.it' => 'Italia',
			'countries.li' => 'Liechtenstein',
			'countries.lu' => 'Lussemburgo',
			'countries.ma' => 'Marocco',
			'countries.mc' => 'Principato di Monaco',
			'countries.nl' => 'Paesi Bassi',
			'countries.no' => 'Norvegia',
			'countries.pl' => 'Polonia',
			'countries.pt' => 'Portogallo',
			'countries.se' => 'Svezia',
			'countries.si' => 'Slovenia',
			'countries.sj' => 'Svalbard',
			'countries.sm' => 'San Marino',
			'countries.va' => 'Città del Vaticano',
			'areas.ara' => 'Alvernia-Rodano-Alpi',
			'areas.bfc' => 'Borgogna-Franca Contea',
			'areas.bre' => 'Bretagna',
			'areas.cvl' => 'Centro-Valle della Loira',
			'areas.cor' => 'Corsica',
			'areas.ges' => 'Grand Est',
			'areas.hdf' => 'Hauts-de-France',
			'areas.idf' => 'Île-de-France',
			'areas.nor' => 'Normandia',
			'areas.naq' => 'Nuova Aquitania',
			'areas.occ' => 'Occitania',
			'areas.pdl' => 'Paesi della Loira',
			'areas.pac' => 'Provenza-Alpi-Costa Azzurra',
			'areas.gp' => 'Guadalupa',
			'areas.mq' => 'Martinica',
			'areas.gf' => 'Guyana francese',
			'areas.re' => 'Riunione',
			'areas.yt' => 'Mayotte',
			'areas.franceRest' => 'Resto della Francia',
			_ => null,
		};
	}
}

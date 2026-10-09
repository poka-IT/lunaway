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
class TranslationsFr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsFr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.fr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <fr>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsFr _root = this; // ignore: unused_field

	@override 
	TranslationsFr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsFr(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => 'Lunaway';
	@override late final _Translations$nav$fr nav = _Translations$nav$fr._(_root);
	@override late final _Translations$common$fr common = _Translations$common$fr._(_root);
	@override late final _Translations$kinds$fr kinds = _Translations$kinds$fr._(_root);
	@override late final _Translations$families$fr families = _Translations$families$fr._(_root);
	@override late final _Translations$services$fr services = _Translations$services$fr._(_root);
	@override late final _Translations$activities$fr activities = _Translations$activities$fr._(_root);
	@override late final _Translations$amenities$fr amenities = _Translations$amenities$fr._(_root);
	@override late final _Translations$overnight$fr overnight = _Translations$overnight$fr._(_root);
	@override late final _Translations$freshness$fr freshness = _Translations$freshness$fr._(_root);
	@override late final _Translations$map$fr map = _Translations$map$fr._(_root);
	@override late final _Translations$sync$fr sync = _Translations$sync$fr._(_root);
	@override late final _Translations$location$fr location = _Translations$location$fr._(_root);
	@override late final _Translations$search$fr search = _Translations$search$fr._(_root);
	@override late final _Translations$filters$fr filters = _Translations$filters$fr._(_root);
	@override late final _Translations$place$fr place = _Translations$place$fr._(_root);
	@override late final _Translations$sources$fr sources = _Translations$sources$fr._(_root);
	@override late final _Translations$hours$fr hours = _Translations$hours$fr._(_root);
	@override late final _Translations$directions$fr directions = _Translations$directions$fr._(_root);
	@override late final _Translations$navigation$fr navigation = _Translations$navigation$fr._(_root);
	@override late final _Translations$list$fr list = _Translations$list$fr._(_root);
	@override late final _Translations$favorites$fr favorites = _Translations$favorites$fr._(_root);
	@override late final _Translations$vehicle$fr vehicle = _Translations$vehicle$fr._(_root);
	@override late final _Translations$vehicleHeight$fr vehicleHeight = _Translations$vehicleHeight$fr._(_root);
	@override late final _Translations$profile$fr profile = _Translations$profile$fr._(_root);
	@override late final _Translations$units$fr units = _Translations$units$fr._(_root);
	@override late final _Translations$languages$fr languages = _Translations$languages$fr._(_root);
	@override late final _Translations$translation$fr translation = _Translations$translation$fr._(_root);
	@override late final _Translations$locale$fr locale = _Translations$locale$fr._(_root);
	@override late final _Translations$account$fr account = _Translations$account$fr._(_root);
	@override late final _Translations$recovery$fr recovery = _Translations$recovery$fr._(_root);
	@override late final _Translations$recover$fr recover = _Translations$recover$fr._(_root);
	@override late final _Translations$deletion$fr deletion = _Translations$deletion$fr._(_root);
	@override late final _Translations$devices$fr devices = _Translations$devices$fr._(_root);
	@override late final _Translations$muted$fr muted = _Translations$muted$fr._(_root);
	@override late final _Translations$mine$fr mine = _Translations$mine$fr._(_root);
	@override late final _Translations$outbox$fr outbox = _Translations$outbox$fr._(_root);
	@override late final _Translations$placement$fr placement = _Translations$placement$fr._(_root);
	@override late final _Translations$contribute$fr contribute = _Translations$contribute$fr._(_root);
	@override late final _Translations$confirmSheet$fr confirmSheet = _Translations$confirmSheet$fr._(_root);
	@override late final _Translations$issueSheet$fr issueSheet = _Translations$issueSheet$fr._(_root);
	@override late final _Translations$reportSheet$fr reportSheet = _Translations$reportSheet$fr._(_root);
	@override late final _Translations$reviewSheet$fr reviewSheet = _Translations$reviewSheet$fr._(_root);
	@override late final _Translations$gate$fr gate = _Translations$gate$fr._(_root);
	@override late final _Translations$photoFlow$fr photoFlow = _Translations$photoFlow$fr._(_root);
	@override late final _Translations$placeForm$fr placeForm = _Translations$placeForm$fr._(_root);
	@override late final _Translations$favoritesSync$fr favoritesSync = _Translations$favoritesSync$fr._(_root);
	@override late final _Translations$poi$fr poi = _Translations$poi$fr._(_root);
	@override late final _Translations$offlineMaps$fr offlineMaps = _Translations$offlineMaps$fr._(_root);
	@override late final _Translations$regions$fr regions = _Translations$regions$fr._(_root);
	@override late final _Translations$roadReport$fr roadReport = _Translations$roadReport$fr._(_root);
	@override late final _Translations$countries$fr countries = _Translations$countries$fr._(_root);
	@override late final _Translations$areas$fr areas = _Translations$areas$fr._(_root);
}

// Path: nav
class _Translations$nav$fr extends Translations$nav$en {
	_Translations$nav$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get map => 'Carte';
	@override String get favorites => 'Favoris';
	@override String get profile => 'Profil';
	@override String get fold => 'Réduire le menu';
	@override String get unfold => 'Afficher le menu en entier';
}

// Path: common
class _Translations$common$fr extends Translations$common$en {
	_Translations$common$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get close => 'Fermer';
	@override String get done => 'Terminé';
	@override String get cancel => 'Annuler';
	@override String get retry => 'Réessayer';
	@override String get save => 'Enregistrer';
	@override String get delete => 'Supprimer';
	@override String get undo => 'Annuler';
	@override String get ok => 'Compris';
	@override String get saveFailed => 'La modification n\'a pas pu être enregistrée.';
	@override String get send => 'Envoyer';
	@override String get later => 'Plus tard';
	@override String get next => 'Continuer';
	@override String get failed => 'L\'opération n\'a pas abouti. Réessayez dans un moment.';
	@override String get offline => 'Pas de réseau pour l\'instant. Réessayez quand il reviendra.';
}

// Path: kinds
class _Translations$kinds$fr extends Translations$kinds$en {
	_Translations$kinds$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get motorhomeArea => 'Aire de camping-car';
	@override String get serviceArea => 'Aire de services';
	@override String get campsite => 'Camping';
	@override String get parking => 'Parking';
	@override String get nature => 'Lieu en pleine nature';
	@override String get restArea => 'Aire de repos';
	@override String get picnicArea => 'Aire de pique-nique';
	@override String get farm => 'Accueil à la ferme';
	@override String get homestay => 'Accueil chez un particulier';
	@override String get offRoad => 'Lieu tout-terrain';
	@override String get extraService => 'Arrêt pratique';
}

// Path: families
class _Translations$families$fr extends Translations$families$en {
	_Translations$families$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get stopovers => 'Aires et parkings';
	@override String get stopoversHint => 'Aires de camping-car, parkings, aires de repos';
	@override String get campsites => 'Campings et accueils';
	@override String get campsitesHint => 'Campings, fermes, particuliers';
	@override String get nature => 'Nature';
	@override String get natureHint => 'Lieux en pleine nature, pistes';
	@override String get services => 'Services';
	@override String get servicesHint => 'Eau et vidange, pas de nuit sur place';
}

// Path: services
class _Translations$services$fr extends Translations$services$en {
	_Translations$services$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get drinkingWater => 'Eau potable';
	@override String get greyWater => 'Vidange eaux grises';
	@override String get blackWater => 'Vidange cassette';
	@override String get wasteBin => 'Poubelles';
	@override String get toilets => 'Toilettes';
	@override String get showers => 'Douches';
	@override String get electricity => 'Électricité';
	@override String get wifi => 'Wi-Fi';
	@override String get laundry => 'Laverie';
	@override String get lpg => 'GPL';
	@override String get gasBottles => 'Bouteilles de gaz';
	@override String get vehicleWash => 'Lavage du véhicule';
	@override String get bakery => 'Boulangerie';
	@override String get swimmingPool => 'Piscine';
	@override String get petsAllowed => 'Animaux acceptés';
	@override String get mobileData => 'Réseau mobile';
	@override String get winterCaravanning => 'Ouvert en hiver';
}

// Path: activities
class _Translations$activities$fr extends Translations$activities$en {
	_Translations$activities$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get monuments => 'Visites';
	@override String get windsurfKitesurf => 'Planche à voile, kitesurf';
	@override String get mountainBiking => 'VTT';
	@override String get hiking => 'Randonnée';
	@override String get climbing => 'Escalade';
	@override String get canoeKayak => 'Canoë, kayak';
	@override String get fishing => 'Pêche';
	@override String get shoreFishing => 'Pêche à pied';
	@override String get swimming => 'Baignade';
	@override String get motorcycling => 'Balades à moto';
	@override String get viewpoint => 'Point de vue';
	@override String get playground => 'Jeux pour enfants';
}

// Path: amenities
class _Translations$amenities$fr extends Translations$amenities$en {
	_Translations$amenities$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get water => 'Eau';
	@override String get dumpStation => 'Vidange';
	@override String get electricity => 'Électricité';
	@override String get toilets => 'Toilettes';
	@override String get showers => 'Douches';
	@override String get wasteBin => 'Poubelles';
	@override String get laundry => 'Laverie';
	@override String get wifi => 'Wi-Fi';
	@override String get lpg => 'GPL';
}

// Path: overnight
class _Translations$overnight$fr extends Translations$overnight$en {
	_Translations$overnight$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Nuit autorisée';
	@override String get tolerated => 'Nuit tolérée';
	@override String get dayOnly => 'De jour seulement';
	@override String get forbidden => 'Nuit interdite';
	@override String get unknown => 'Nuit non renseignée';
	@override String get allowedHint => 'Vous pouvez passer la nuit ici.';
	@override String get toleratedHint => 'Une nuit est en général acceptée. Discrétion de rigueur, ne laissez aucune trace.';
	@override String get dayOnlyHint => 'Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.';
	@override String get forbiddenHint => 'Passer la nuit ici est interdit.';
	@override String get unknownHint => 'Personne ne l\'a encore indiqué. Renseignez-vous sur place.';
}

// Path: freshness
class _Translations$freshness$fr extends Translations$freshness$en {
	_Translations$freshness$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String confirmed({required Object when}) => 'Confirmé par un voyageur ${when}';
	@override String get unconfirmed => 'Pas encore confirmé par un voyageur';
	@override String get stale => 'Dernière confirmation il y a plus d\'un an';
	@override String get today => 'aujourd\'hui';
	@override String daysAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'hier',
		other: 'il y a ${n} jours',
	);
	@override String monthsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'il y a un mois',
		other: 'il y a ${n} mois',
	);
	@override String yearsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'il y a un an',
		other: 'il y a ${n} ans',
	);
}

// Path: map
class _Translations$map$fr extends Translations$map$en {
	_Translations$map$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get searchHint => 'Un lieu, une commune';
	@override String get clearSearch => 'Effacer la recherche';
	@override String get locateMe => 'Afficher ma position';
	@override String get aroundMe => 'Voir autour de moi';
	@override String get zoomIn => 'Zoomer';
	@override String get zoomOut => 'Dézoomer';
	@override String get filters => 'Filtres';
	@override String get credit => '© OpenStreetMap · Protomaps';
	@override String get creditLabel => 'Crédits de la carte : © les contributeurs d\'OpenStreetMap, style Protomaps. Ouvre la page des droits d\'OpenStreetMap.';
	@override String get showList => 'Liste';
	@override String showListCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Liste (${n})',
		other: 'Liste (${n})',
	);
	@override String placesHereLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'lieu ici',
		other: 'lieux ici',
	);
	@override String nearestYouLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'lieu le plus proche de vous',
		other: 'lieux les plus proches de vous',
	);
	@override String nearestCentreLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'lieu le plus proche du centre',
		other: 'lieux les plus proches du centre',
	);
	@override String get pointTitle => 'Ici';
	@override String get pointHint => 'Point sur la carte';
	@override String get directionsHere => 'Itinéraire jusqu\'ici';
	@override String get startHere => 'Partir d\'ici';
	@override String get departureChosen => 'Départ choisi : ouvrez maintenant la destination et son itinéraire.';
	@override String get copyCoordinates => 'Copier les coordonnées';
	@override String get freeTapHint => 'Touchez la carte pour y aller ou y ajouter un lieu';
	@override String get freeTapHintClick => 'Cliquez sur la carte pour y aller ou y ajouter un lieu';
	@override String get addPlaceAtCenter => 'Ajouter un lieu au centre de la carte';
	@override String addressSource({required Object attribution}) => 'Source : ${attribution}';
	@override String get placesAround => 'Les lieux autour';
	@override String get downloading => 'Téléchargement des lieux de France';
	@override String downloadingCount({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${count} lieu reçu',
		other: '${count} lieux reçus',
	);
	@override String get noData => 'Aucun lieu sur cet appareil pour l\'instant';
	@override String get noDataHint => 'Téléchargez les lieux une fois : la carte fonctionne ensuite sans réseau.';
	@override String get download => 'Télécharger les lieux';
	@override String get downloadFailed => 'Le téléchargement s\'est interrompu';
	@override String get demoBanner => 'Démo : lieux inventés';
	@override String get unsupported => 'La carte n\'est pas disponible sur ce système. Utilisez l\'application web.';
}

// Path: sync
class _Translations$sync$fr extends Translations$sync$en {
	_Translations$sync$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get failedOffline => 'Pas de connexion pour l\'instant.';
	@override String get failedBusy => 'Le serveur est très demandé.';
	@override String get failedServer => 'Le serveur a un problème pour l\'instant.';
	@override String get failedOther => 'La mise à jour n\'a pas abouti.';
	@override String get failedRefused => 'Le serveur a refusé la mise à jour. Une nouvelle version de l\'application est peut-être nécessaire.';
	@override String get willRetry => 'Lunaway réessaiera tout seul.';
	@override String incomplete({required Object count}) => 'Téléchargement incomplet : ${count} lieux pour l\'instant';
	@override String get incompleteShort => 'Téléchargement incomplet';
	@override String resuming({required Object count}) => 'Téléchargement en cours : ${count} lieux';
	@override String get resume => 'Reprendre';
}

// Path: location
class _Translations$location$fr extends Translations$location$en {
	_Translations$location$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get rationaleTitle => 'Afficher votre position ?';
	@override String get rationale => 'Lunaway s\'en sert pour centrer la carte sur vous, trier les lieux par distance et vous guider. Pour un itinéraire, votre position est envoyée au serveur de Lunaway, qui ne la conserve pas. Pour le carburant le moins cher autour de vous, seule une position arrondie à environ 5 km est envoyée. Un signalement sur la route part avec l\'endroit où vous le faites.';
	@override String get allow => 'Continuer';
	@override String get notNow => 'Pas maintenant';
	@override String get deniedTitle => 'Position désactivée pour Lunaway';
	@override String get denied => 'Vous avez refusé l\'accès à la position. Pour l\'utiliser, autorisez-le dans les réglages de l\'appareil.';
	@override String get openSettings => 'Ouvrir les réglages';
	@override String get serviceOffTitle => 'Localisation désactivée';
	@override String get serviceOff => 'La localisation de l\'appareil est désactivée. Activez-la dans les réglages rapides, puis réessayez.';
	@override String get notAllowed => 'Position non autorisée. La carte fonctionne sans elle.';
	@override String get noFix => 'Position introuvable pour l\'instant. Réessayez à découvert ou dans un moment.';
	@override String get unsupported => 'Cet appareil ne donne pas sa position.';
	@override String get browserDeniedTitle => 'Position bloquée par le navigateur';
	@override String get browserDenied => 'Le navigateur refuse votre position à Lunaway. Pour l\'autoriser, cliquez sur l\'icône à gauche de l\'adresse du site (un cadenas ou des curseurs), mettez Position sur Autoriser, puis cliquez de nouveau sur le bouton de position.';
	@override String get browserNoFix => 'Le navigateur n\'a pas donné de position. Réessayez dans un moment ; sur un ordinateur, le Wi-Fi aide à la trouver.';
}

// Path: search
class _Translations$search$fr extends Translations$search$en {
	_Translations$search$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get towns => 'Communes';
	@override String get places => 'Lieux';
	@override String noResult({required Object query}) => 'Aucun lieu ni aucune commune ne correspond à « ${query} ».';
	@override String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} lieu',
		other: '${n} lieux',
	);
	@override String get addresses => 'Adresses';
	@override String get addressesSearching => 'Recherche des adresses';
	@override String get addressesFailed => 'Les adresses n\'ont pas pu être cherchées pour l\'instant.';
	@override String addressSources({required Object sources}) => 'Adresses : ${sources}';
	@override String get offline => 'Pas de connexion : la recherche a besoin du réseau.';
	@override late final _Translations$search$addressKind$fr addressKind = _Translations$search$addressKind$fr._(_root);
}

// Path: filters
class _Translations$filters$fr extends Translations$filters$en {
	_Translations$filters$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filtres';
	@override String get families => 'Type de lieu';
	@override String get familiesHint => 'Aucun choix : tous les types';
	@override String get familiesChosenHint => 'Seulement ces types';
	@override String get night => 'Nuit sur place';
	@override String get nightHint => 'Aucun choix : tous les lieux';
	@override String get nightChosenHint => 'Seulement les lieux de ces statuts';
	@override String get nightPossible => 'Nuit possible';
	@override String get amenities => 'Services';
	@override String get amenitiesHint => 'Le lieu doit tous les avoir';
	@override String get rating => 'Note minimale';
	@override String get ratingHint => 'Note des visiteurs de Lunaway, ou celle des autres sources quand ils n\'ont pas noté le lieu. Un lieu sans note est masqué.';
	@override String ratingAtLeast({required Object rating}) => '${rating} et plus';
	@override String get opening => 'Ouverture';
	@override String get openingHint => 'Les lieux dont l\'ouverture n\'est pas connue restent affichés.';
	@override String get openingAllYear => 'Toute l\'année';
	@override String get openingDates => 'À mes dates';
	@override String get openingClearDates => 'Effacer les dates';
	@override String openingStay({required Object from, required Object to}) => 'Du ${from} au ${to}';
	@override String openingStayDay({required Object date}) => 'Le ${date}';
	@override String get openingStayTitle => 'Dates du séjour';
	@override String get openingArrival => 'Arrivée';
	@override String get openingDeparture => 'Départ';
	@override String get price => 'Prix de la nuit';
	@override String get freeOnly => 'Gratuit';
	@override String get freeHint => 'Seulement les lieux dont la nuit est gratuite d\'après leurs sources';
	@override String get scrollNext => 'Voir les filtres suivants';
	@override String get scrollPrevious => 'Voir les filtres précédents';
	@override String get vehicle => 'Mon véhicule';
	@override String get myVehicleFits => 'Mon véhicule passe';
	@override String myVehicleFitsHeight({required Object height}) => 'Passe à ${height}';
	@override String myVehicleHint({required Object height}) => 'Masque les lieux limités sous ${height}. Les lieux sans hauteur connue restent affichés.';
	@override String get reset => 'Tout effacer';
	@override String get apply => 'Appliquer';
	@override String show({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		zero: 'Aucun lieu ne correspond',
		one: 'Afficher ${count} lieu',
		other: 'Afficher ${count} lieux',
	);
	@override String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} filtre actif',
		other: '${n} filtres actifs',
	);
}

// Path: place
class _Translations$place$fr extends Translations$place$en {
	_Translations$place$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String unnamedIn({required Object kind, required Object town}) => '${kind} à ${town}';
	@override String away({required Object distance}) => 'à ${distance}';
	@override String get directions => 'Itinéraire';
	@override String get share => 'Partager';
	@override String get save => 'Enregistrer';
	@override String get saved => 'Enregistré';
	@override String get saveHint => 'Dans Mes favoris. Appui long pour choisir des listes.';
	@override String get saveTo => 'Enregistrer dans une liste';
	@override String get chooseLists => 'Listes';
	@override String get savedToast => 'Ajouté à Mes favoris';
	@override String get removedToast => 'Retiré de Mes favoris';
	@override String get pricePerNight => 'Prix de la nuit';
	@override String get priceFree => 'Gratuit';
	@override String get priceUnknown => 'Non indiqué';
	@override String get priceServices => 'Services';
	@override String get priceIncluded => 'Inclus';
	@override String priceIncludes({required Object items}) => 'Le prix de la nuit comprend : ${items}';
	@override late final _Translations$place$inclusions$fr inclusions = _Translations$place$inclusions$fr._(_root);
	@override String get maxHeight => 'Hauteur max.';
	@override String get capacity => 'Emplacements';
	@override String get classification => 'Classement';
	@override String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} étoile',
		other: '${n} étoiles',
	);
	@override String get hours => 'Horaires';
	@override String get services => 'Services';
	@override String get noServices => 'Aucun service indiqué.';
	@override String get activities => 'À proximité';
	@override String get description => 'Description';
	@override String get contact => 'Contact';
	@override String get website => 'Site web';
	@override String get call => 'Appeler';
	@override String get coordinates => 'Coordonnées';
	@override String get copy => 'Copier les coordonnées';
	@override String get copyShort => 'Copier';
	@override String copyAs({required Object format}) => 'Copier en ${format}';
	@override String copiesAs({required Object format}) => '« Copier » copie : ${format}';
	@override String copied({required Object text}) => 'Copié : ${text}';
	@override String get otherFormats => 'Choisir le format copié';
	@override String get formatDecimal => 'Degrés décimaux';
	@override String get formatDms => 'Degrés, minutes, secondes';
	@override String get formatGeo => 'Lien geo:';
	@override String get formatGoogle => 'Lien Google Maps';
	@override String get formatOsm => 'Lien OpenStreetMap';
	@override String get sources => 'Sources';
	@override String fetched({required Object when}) => 'Relevé ${when}';
	@override String get viewSource => 'Voir à la source';
	@override String get gone => 'Ce lieu n\'est plus sur la carte';
	@override String get goneHint => 'Il a été retiré ou fusionné avec un autre depuis la dernière mise à jour.';
	@override String get arriving => 'Ce lieu est en cours de téléchargement';
	@override String get arrivingHint => 'Les lieux de France se téléchargent pour que la carte marche sans réseau. La fiche s\'ouvre dès que celui-ci est arrivé.';
	@override String get loadError => 'Ce lieu n\'a pas pu s\'afficher.';
	@override String get openFailed => 'Aucune application n\'a pu ouvrir ce lien.';
	@override String get photos => 'Photos';
	@override String get extrasOffline => 'Les photos et les avis demandent une connexion.';
	@override String get reviewsTitle => 'Avis';
	@override String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} avis',
		other: '${n} avis',
	);
	@override String get noReviews => 'Aucun avis pour l\'instant.';
	@override String get noOtherReviews => 'Aucun autre avis pour l\'instant.';
	@override String get moreReviews => 'Plus d\'avis';
	@override String get moreReviewsFailed => 'La suite des avis n\'a pas pu se charger. Touchez pour réessayer.';
	@override String stars({required Object rating}) => '${rating} sur 5';
	@override String externalRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'avis externe',
		other: 'avis externes',
	);
	@override String get deletedAccount => 'Compte supprimé';
	@override late final _Translations$place$reviewVehicle$fr reviewVehicle = _Translations$place$reviewVehicle$fr._(_root);
	@override String originalLanguage({required Object language}) => 'Texte d\'origine en ${language}';
	@override String photoPosition({required Object index, required Object count}) => 'Photo ${index} sur ${count}';
	@override String get previousPhoto => 'Photo précédente';
	@override String get nextPhoto => 'Photo suivante';
	@override String get links => 'Sur d\'autres sites';
	@override String sourceWithLicence({required Object source, required Object licence}) => '${source} · ${licence}';
	@override String get licenceCcBy => 'CC BY 4.0';
	@override String photoCredit({required Object source, required Object author}) => '${source} · ${author}';
	@override String get photoStreetView => 'Vue de la rue';
	@override String get photoSurroundings => 'Aux alentours';
	@override String excerptFrom({required Object source, required Object text}) => 'D\'après ${source} : ${text}';
	@override String get readMore => 'Lire la suite';
	@override String updatedOn({required Object date}) => 'mis à jour le ${date}';
	@override String get otherSources => 'D\'après d\'autres sources';
}

// Path: sources
class _Translations$sources$fr extends Translations$sources$en {
	_Translations$sources$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$sources$extcom$fr extcom = _Translations$sources$extcom$fr._(_root);
}

// Path: hours
class _Translations$hours$fr extends Translations$hours$en {
	_Translations$hours$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get open => 'Ouvert maintenant';
	@override String openUntil({required Object time}) => 'Ouvert, ferme à ${time}';
	@override String openUntilDay({required Object day, required Object time}) => 'Ouvert, ferme ${day} à ${time}';
	@override String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Ouvert, ferme dans ${n} minute',
		other: 'Ouvert, ferme dans ${n} minutes',
	);
	@override String closedUntil({required Object time}) => 'Fermé, ouvre à ${time}';
	@override String closedUntilDay({required Object day, required Object time}) => 'Fermé, ouvre ${day} à ${time}';
	@override String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Fermé, ouvre dans ${n} minute',
		other: 'Fermé, ouvre dans ${n} minutes',
	);
	@override String get closedWindow => 'Fermé pendant les deux semaines à venir';
	@override String get tomorrow => 'demain';
	@override String onDate({required Object date}) => 'le ${date}';
	@override String onWeekday({required Object day}) => '${day}';
	@override String get midnight => 'minuit';
	@override String get stale => 'Ouvert ou fermé ? Mettez à jour les lieux dans Profil.';
	@override String get localTime => 'Horaires à l\'heure locale du lieu';
	@override late final _Translations$hours$codes$fr codes = _Translations$hours$codes$fr._(_root);
	@override late final _Translations$hours$months$fr months = _Translations$hours$months$fr._(_root);
	@override String dayOfMonth({required Object day, required Object month}) => '${day} ${month}';
	@override String dayOfYear({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}';
	@override String get allWeek => '24 h/24, 7 j/7';
	@override String get allYear => 'toute l\'année';
	@override String get seasonAllYear => 'Ouvert toute l\'année';
	@override String seasonOpenUntil({required Object date}) => 'Ouvert jusqu\'au ${date}';
	@override String seasonClosedUntil({required Object date}) => 'Fermé, ouvre le ${date}';
}

// Path: directions
class _Translations$directions$fr extends Translations$directions$en {
	_Translations$directions$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ouvrir dans';
	@override String get hint => 'Ces applications ne connaissent pas le gabarit de votre véhicule.';
	@override String get remember => 'Toujours utiliser cette application';
	@override String get rememberHint => 'Modifiable dans Profil';
	@override String get settingTitle => 'Ouvrir dans une autre application';
	@override String get settingHint => 'L\'application que lance « Ouvrir dans » depuis un itinéraire';
	@override String get askEachTime => 'Demander à chaque fois';
	@override String get appleMaps => 'Plans';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osmAnd => 'OsmAnd';
	@override String get organicMaps => 'Organic Maps';
	@override String get magicEarth => 'Magic Earth';
	@override String get openStreetMap => 'OpenStreetMap (navigateur)';
	@override String get none => 'Aucune application de navigation trouvée sur cet appareil.';
}

// Path: navigation
class _Translations$navigation$fr extends Translations$navigation$en {
	_Translations$navigation$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$preview$fr preview = _Translations$navigation$preview$fr._(_root);
	@override late final _Translations$navigation$stops$fr stops = _Translations$navigation$stops$fr._(_root);
	@override late final _Translations$navigation$fuel$fr fuel = _Translations$navigation$fuel$fr._(_root);
	@override late final _Translations$navigation$onTheWay$fr onTheWay = _Translations$navigation$onTheWay$fr._(_root);
	@override late final _Translations$navigation$states$fr states = _Translations$navigation$states$fr._(_root);
	@override late final _Translations$navigation$noRoute$fr noRoute = _Translations$navigation$noRoute$fr._(_root);
	@override late final _Translations$navigation$ferry$fr ferry = _Translations$navigation$ferry$fr._(_root);
	@override late final _Translations$navigation$warning$fr warning = _Translations$navigation$warning$fr._(_root);
	@override late final _Translations$navigation$roadEvents$fr roadEvents = _Translations$navigation$roadEvents$fr._(_root);
	@override late final _Translations$navigation$marks$fr marks = _Translations$navigation$marks$fr._(_root);
	@override late final _Translations$navigation$guidance$fr guidance = _Translations$navigation$guidance$fr._(_root);
	@override late final _Translations$navigation$voice$fr voice = _Translations$navigation$voice$fr._(_root);
	@override late final _Translations$navigation$units$fr units = _Translations$navigation$units$fr._(_root);
	@override late final _Translations$navigation$settings$fr settings = _Translations$navigation$settings$fr._(_root);
}

// Path: list
class _Translations$list$fr extends Translations$list$en {
	_Translations$list$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Lieux à proximité';
	@override String get empty => 'Aucun lieu par ici avec ces filtres';
	@override String get emptyHint => 'Déplacez la carte, dézoomez ou assouplissez les filtres.';
	@override String get downloading => 'Les lieux arrivent';
	@override String get downloadingHint => 'La liste se remplit pendant le téléchargement.';
	@override String get error => 'La liste n\'a pas pu s\'afficher.';
	@override String get offline => 'Pas de connexion : la liste a besoin du réseau.';
	@override String get moreFailed => 'La suite de la liste n\'a pas pu s\'afficher. Réessayer';
	@override String get sortDistance => 'Distance';
	@override String get sortRating => 'Note';
	@override String get sortNewest => 'Ajoutés récemment';
	@override String sortedBy({required Object sort}) => 'Liste triée par : ${sort}';
	@override String rankedAmongNearestYou({required Object n}) => 'Classés parmi les ${n} lieux les plus proches de vous';
	@override String rankedAmongNearestCentre({required Object n}) => 'Classés parmi les ${n} lieux les plus proches du centre de la carte';
	@override String get offlineTitle => 'Pas de connexion';
	@override String get offlineNotHere => 'Rien de cette zone sur cet appareil.';
}

// Path: favorites
class _Translations$favorites$fr extends Translations$favorites$en {
	_Translations$favorites$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Favoris';
	@override String get defaultList => 'Mes favoris';
	@override String get empty => 'Rien d\'enregistré ici pour l\'instant';
	@override String get emptyHint => 'Touchez Enregistrer sur un lieu pour le garder, même hors connexion.';
	@override String get newList => 'Nouvelle liste';
	@override String get listName => 'Nom de la liste';
	@override String get renameList => 'Renommer la liste';
	@override String get deleteList => 'Supprimer la liste';
	@override String deleteListConfirm({required Object name}) => 'Supprimer « ${name} » ? Les lieux restent sur la carte.';
	@override String get listActions => 'Options de la liste';
	@override String get placeActions => 'Options du lieu';
	@override String get openOnMap => 'Voir sur la carte';
	@override String get remove => 'Retirer de la liste';
	@override String get removed => 'Retiré de la liste';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		zero: 'Vide',
		one: '${n} lieu',
		other: '${n} lieux',
	);
	@override String get error => 'Vos favoris n\'ont pas pu s\'afficher.';
}

// Path: vehicle
class _Translations$vehicle$fr extends Translations$vehicle$en {
	_Translations$vehicle$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mon véhicule';
	@override String get why => 'Ses dimensions servent à masquer les lieux où il ne passe pas. Elles sont envoyées avec chaque demande d\'itinéraire, sans être conservées.';
	@override String get none => 'Décrivez votre véhicule pour masquer les lieux où il ne passe pas.';
	@override String get add => 'Décrire mon véhicule';
	@override String get edit => 'Modifier';
	@override String get type => 'Type';
	@override late final _Translations$vehicle$types$fr types = _Translations$vehicle$types$fr._(_root);
	@override String get towingTitle => 'Il tracte';
	@override late final _Translations$vehicle$towing$fr towing = _Translations$vehicle$towing$fr._(_root);
	@override String get size => 'Dimensions';
	@override String get sizeHint => 'Valeurs typiques du type choisi : corrigez-les avec celles de votre carte grise.';
	@override String get height => 'Hauteur';
	@override String get width => 'Largeur';
	@override String get length => 'Longueur totale, attelage compris';
	@override String get weight => 'Poids total autorisé (PTAC)';
	@override String heightShort({required Object value}) => 'H ${value}';
	@override String widthShort({required Object value}) => 'l ${value}';
	@override String lengthShort({required Object value}) => 'L ${value}';
	@override String get notANumber => 'Un nombre, par exemple 2,90';
	@override String outOfRange({required Object min, required Object max, required Object unit}) => 'Entre ${min} et ${max} ${unit}';
	@override String get navigationLater => 'Le guidage de Lunaway tient compte de toutes ces dimensions.';
	@override String get save => 'Enregistrer';
	@override String get clear => 'Effacer';
	@override String get fuelTitle => 'Carburant';
	@override String get fuelHint => 'Le prix de votre carburant s\'affiche sur les stations de la carte, les moins chères en premier.';
	@override String get consumption => 'Consommation';
	@override String get consumptionUnit => 'L/100 km';
	@override String get lpgHeating => 'Chauffage au GPL';
	@override String get lpgHeatingHint => 'Le prix du GPL s\'affiche aussi sur les stations.';
	@override String get cruiseTitle => 'Vitesse de croisière max';
	@override String get cruiseHint => 'Les temps de trajet supposent que vous ne roulez jamais plus vite, même là où la route le permet. Les limitations annoncées pendant le guidage restent celles de la route.';
	@override String get cruiseNone => 'Pas de limite';
}

// Path: vehicleHeight
class _Translations$vehicleHeight$fr extends Translations$vehicleHeight$en {
	_Translations$vehicleHeight$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Hauteur de votre véhicule';
	@override String get why => 'Les lieux limités plus bas seront masqués. Ceux dont la hauteur n\'est pas connue restent affichés.';
	@override String get needed => 'Indiquez la hauteur, par exemple 2,90';
	@override String get weightOptional => 'Poids total autorisé (facultatif)';
	@override String get apply => 'Filtrer avec cette hauteur';
	@override String get later => 'Le reste du véhicule se décrit dans Profil, Mon véhicule.';
}

// Path: profile
class _Translations$profile$fr extends Translations$profile$en {
	_Translations$profile$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profil';
	@override String get noAccountNeeded => 'Sans compte, sans publicité, sans traceur. Vos favoris restent sur cet appareil.';
	@override String get language => 'Langue';
	@override String get languageSystem => 'Comme l\'appareil';
	@override String get appearance => 'Apparence';
	@override String get themeAuto => 'Auto';
	@override String get themeLight => 'Clair';
	@override String get themeDark => 'Sombre';
	@override String get themeAutoHint => 'Clair le jour, sombre après le coucher du soleil là où vous êtes.';
	@override String get themeLightHint => 'Toujours clair, de jour comme de nuit.';
	@override String get themeDarkHint => 'Toujours sombre, doux pour les yeux la nuit.';
	@override String get offline => 'Hors ligne';
	@override String placesOnDevice({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'lieu sur cet appareil',
		other: 'lieux sur cet appareil',
	);
	@override String offlineSize({required Object size}) => 'Espace utilisé : ${size}';
	@override String lastSync({required Object when}) => 'Dernière mise à jour ${when}';
	@override String get neverSynced => 'Jamais téléchargé';
	@override String get syncNow => 'Mettre à jour';
	@override String get syncing => 'Mise à jour en cours';
	@override String get about => 'À propos';
	@override String version({required Object version}) => 'Version ${version}';
	@override String get website => 'Site web';
	@override String get privacy => 'Politique de confidentialité';
	@override String get sourceCode => 'Code source';
	@override String get licences => 'Licences';
	@override String get appLicence => 'Lunaway est un logiciel libre sous licence GNU AGPL 3.0 ou ultérieure.';
	@override String get attributions => 'Sources et crédits';
	@override String get attributionOsm => 'Lieux et données cartographiques © les contributeurs d\'OpenStreetMap.';
	@override String get attributionOdbl => 'Données d\'OpenStreetMap sous licence Open Database License (ODbL).';
	@override String get attributionAtout => 'Campings classés d\'Atout France, sous Licence Ouverte 2.0 (Etalab).';
	@override String get attributionCommunes => 'Communes des lieux : Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), sous licence ODbL.';
	@override String get attributionTiles => 'Fond de carte servi par Lunaway, styles dérivés de Protomaps (BSD-3-Clause), données © les contributeurs d\'OpenStreetMap.';
	@override String get attributionFonts => 'Polices Fraunces et Atkinson Hyperlegible Next, sous licence SIL Open Font License 1.1.';
	@override String get attributionIcons => 'Icônes Phosphor, sous licence MIT.';
	@override String get noTracking => 'Sans publicité ni traceur. Votre compte ne connaît ni votre e-mail ni votre téléphone.';
	@override String get attributionBdTopo => 'Hauteurs, largeurs, longueurs et poids limités des routes, et campings placés par leur nom : BD TOPO de l\'IGN, par la Géoplateforme, sous Licence Ouverte 2.0.';
	@override String get attributionAddresses => 'Adresses de la recherche en France : Base Adresse Nationale, par la Géoplateforme de l\'IGN, sous Licence Ouverte 2.0.';
	@override String get attributionAddressesOsm => 'Adresses de la recherche ailleurs : OpenStreetMap, par Photon, sous ODbL.';
	@override String get attributionPoiOdbl => 'Commerces et services : OpenStreetMap, et le calendrier d\'ouverture de La Poste, sous ODbL.';
	@override String get attributionPoiLo => 'Prix des carburants (ministère de l\'Économie) et établissements de santé FINESS, sous Licence Ouverte 2.0 (Etalab).';
	@override String get attributionPacks => 'Contours des cartes hors ligne : Contours administratifs, data.gouv.fr (ODbL), et Natural Earth (domaine public).';
	@override String get attributionOfflineLabels => 'Noms et icônes des cartes hors ligne : glyphes Noto Sans (SIL Open Font License 1.1) et sprites Protomaps dérivés de tangrams/icons (MIT).';
	@override String get attributionExtcom => 'Lieux, avis, notes et photos, sous accord écrit avec cette source.';
	@override String get creditsPlaces => 'Lieux';
	@override String get creditsContent => 'Photos, textes et avis';
	@override String get creditsRoutes => 'Itinéraires et guidage';
	@override String get creditsSearch => 'Recherche';
	@override String get creditsMap => 'Fond de carte';
	@override String get creditsApp => 'Application';
	@override String get attributionDatatourisme => 'Lieux, descriptions et photos des offices de tourisme : DATAtourisme, sous Licence Ouverte 2.0 ; chaque texte et chaque photo nomme son office, son auteur et sa date de mise à jour.';
	@override String get attributionCommunity => 'Avis, notes et photos des voyageurs de Lunaway, sous licence CC BY 4.0, avec le pseudonyme de leur auteur.';
	@override String get attributionCommons => 'Photos de Wikimedia Commons, chacune sous sa licence (CC0, CC BY ou CC BY-SA), avec son auteur et un lien vers sa page.';
	@override String get attributionPanoramax => 'Vues de la rue de Panoramax : instance d\'OpenStreetMap France sous licence CC BY-SA 4.0, instance de l\'IGN sous Licence Ouverte 2.0.';
	@override String get attributionWikipedia => 'Extraits d\'articles de Wikipedia, sous licence CC BY-SA 4.0, avec un lien vers l\'article.';
	@override String get attributionMangrove => 'Avis de Mangrove Reviews, sous licence CC BY 4.0 ou celle que l\'avis déclare, avec un lien vers l\'avis.';
	@override String get attributionRoadEvents => 'Travaux et fermetures en France : DIR et Bison Futé, arrêtés de circulation DiaLog (DGITM), métropoles et départements (Lyon, Toulouse, Bordeaux, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d\'Armor, Sarthe), sous Licence Ouverte 2.0 ; Rennes Métropole et signalements des voyageurs de Lunaway, sous ODbL.';
	@override String get attributionRoadEventsAbroad => 'Travaux et fermetures aux Pays-Bas : NDW, Nationaal Dataportaal Wegverkeer (données ouvertes) ; en Espagne : DGT, Dirección General de Tráfico (CC BY).';
	@override String get attributionDangerZones => 'Zones de danger : listes officielles des radars (Sécurité routière en France, réutilisée selon le Code des relations entre le public et l\'administration ; Pologne et Luxembourg, CC0 ; Catalogne, licence ouverte de la Generalitat ; Norvège, NLOD) et OpenStreetMap (ODbL).';
}

// Path: units
class _Translations$units$fr extends Translations$units$en {
	_Translations$units$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String kilobytes({required Object n}) => '${n} ko';
	@override String megabytes({required Object n}) => '${n} Mo';
}

// Path: languages
class _Translations$languages$fr extends Translations$languages$en {
	_Translations$languages$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get fr => 'français';
	@override String get en => 'anglais';
	@override String get de => 'allemand';
	@override String get es => 'espagnol';
	@override String get it => 'italien';
	@override String get nl => 'néerlandais';
}

// Path: translation
class _Translations$translation$fr extends Translations$translation$en {
	_Translations$translation$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get translate => 'Traduire';
	@override String get translating => 'Traduction en cours';
	@override String get showOriginal => 'Voir l\'original';
	@override String get showTranslation => 'Voir la traduction';
	@override late final _Translations$translation$from$fr from = _Translations$translation$from$fr._(_root);
	@override String get offline => 'La traduction a besoin du réseau.';
	@override String get failedOffline => 'Pas de connexion : le texte n\'a pas pu être traduit.';
	@override String get busy => 'Le service de traduction est occupé. Réessayez plus tard.';
	@override String get unavailable => 'La traduction n\'est pas disponible pour l\'instant.';
	@override String get gone => 'Ce texte n\'est plus disponible.';
	@override String get unsupported => 'Pas de traduction disponible pour cette langue.';
	@override String get autoReviews => 'Traduire automatiquement les avis';
	@override String get autoReviewsHint => 'Les avis écrits dans une autre langue sont traduits par le serveur de Lunaway, sans aucun service tiers.';
}

// Path: locale
class _Translations$locale$fr extends Translations$locale$en {
	_Translations$locale$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
	@override String get de => 'Deutsch';
	@override String get es => 'Español';
	@override String get it => 'Italiano';
	@override String get nl => 'Nederlands';
}

// Path: account
class _Translations$account$fr extends Translations$account$en {
	_Translations$account$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Votre compte';
	@override String get noneTitle => 'Pas encore de compte';
	@override String get noneBody => 'La carte, la recherche et les favoris fonctionnent sans compte. Il se crée tout seul à votre première contribution (une note, une confirmation, une photo), sans e-mail ni mot de passe. Vos listes de favoris y sont alors rattachées.';
	@override String get recover => 'Retrouver mon compte';
	@override String memberSince({required Object date}) => 'Membre depuis ${date}';
	@override String get editPseudonym => 'Modifier le pseudonyme';
	@override String get pseudonymTitle => 'Votre pseudonyme';
	@override String get pseudonymHint => 'Public : il accompagne vos avis et vos photos. De 3 à 32 caractères.';
	@override String get pseudonymInvalid => 'De 3 à 32 caractères, dont au moins deux lettres.';
	@override String get pseudonymRefused => 'Ce pseudonyme n\'est pas accepté : ni lien, ni coordonnées, ni mot injurieux, ni nom qui ferait passer le compte pour l\'équipe.';
	@override String get pseudonymSaved => 'Pseudonyme enregistré';
	@override String level({required Object level}) => 'Niveau de confiance ${level}';
	@override late final _Translations$account$levelOpens$fr levelOpens = _Translations$account$levelOpens$fr._(_root);
	@override String nextLevel({required Object level}) => 'Pour le niveau ${level}';
	@override String get levelTop => 'Vous êtes au niveau le plus haut.';
	@override late final _Translations$account$requirement$fr requirement = _Translations$account$requirement$fr._(_root);
	@override String orInstead({required Object requirement}) => 'Ou bien ${requirement}';
	@override String get recoveryNone => 'Aucune carte de secours faite sur cet appareil. Sans elle, ce compte reste sur cet appareil : s\'il est perdu, le compte l\'est aussi.';
	@override String get recoveryNoneAccount => 'Pas encore de carte de secours pour ce compte. Sans elle, ce compte reste sur cet appareil : s\'il est perdu, le compte l\'est aussi.';
	@override String get recoveryCreate => 'Faire ma carte de secours';
	@override String recoveryMade({required Object date}) => 'Faite le ${date}';
	@override String get recoveryRemake => 'Refaire';
	@override String get recoveryRemakeHint => 'Refaire la carte de secours';
	@override String get contributions => 'Mes contributions';
	@override String pending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} contribution en attente d\'envoi',
		other: '${n} contributions en attente d\'envoi',
	);
	@override String get mutedAuthors => 'Auteurs masqués';
	@override String get devices => 'Appareils';
	@override String get signOut => 'Se déconnecter';
	@override String get delete => 'Supprimer mon compte';
	@override String get signOutTitle => 'Se déconnecter de cet appareil ?';
	@override String get signOutBody => 'La clé du compte est effacée de cet appareil. Pour revenir, il faudra votre carte de secours. Vos favoris restent ici.';
	@override String get signOutNoCard => 'Vous n\'avez pas fait de carte de secours sur cet appareil. Sans elle, ce compte sera perdu pour de bon.';
	@override String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Une contribution en attente d\'envoi ne partira pas.',
		other: '${n} contributions en attente d\'envoi ne partiront pas.',
	);
	@override String get signedOut => 'Déconnecté. Vos favoris restent sur cet appareil.';
	@override String get lost => 'Ce compte ne s\'ouvre plus sur cet appareil. Retrouvez-le avec votre carte de secours : Profil, Retrouver mon compte.';
	@override String get lostAction => 'Retrouver';
	@override String get welcomeTitle => 'Merci pour votre première contribution';
	@override String welcomeBody({required Object name}) => 'Votre compte est créé, sous le pseudonyme « ${name} ». Pas d\'e-mail ni de mot de passe : une clé gardée sur cet appareil. Le pseudonyme se change dans le profil.';
	@override String get welcomeCard => 'Faites votre carte de secours pour retrouver ce compte sur un autre appareil.';
	@override String get welcomeFavorites => 'Vos listes de favoris sont maintenant gardées avec votre compte.';
}

// Path: recovery
class _Translations$recovery$fr extends Translations$recovery$en {
	_Translations$recovery$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Carte de secours';
	@override String get intro => 'Un code qui ramène votre compte sur un nouvel appareil. Lunaway n\'en garde qu\'une empreinte, qui sert à le vérifier : le code lui-même ne peut plus jamais être affiché, et chaque nouvelle carte a un code différent.';
	@override String get replaces => 'Une nouvelle carte remplace la précédente : l\'ancien code cessera de marcher.';
	@override String replaceTitle({required Object date}) => 'Remplacer la carte du ${date} ?';
	@override String replaceBody({required Object date}) => 'La nouvelle carte aura un autre code. Celui de la carte du ${date} cessera de marcher dès maintenant. Il ne peut pas être réaffiché : Lunaway n\'en a gardé qu\'une empreinte.';
	@override String get replaceKeep => 'Garder l\'ancienne';
	@override String get replaceConfirm => 'Faire une nouvelle carte';
	@override String get make => 'Faire la carte';
	@override String get codeLabel => 'Votre code de secours';
	@override String get shownOnce => 'Ce code ne s\'affiche qu\'une fois. Notez-le, ou enregistrez l\'image, avant de fermer.';
	@override String get saveImage => 'Enregistrer l\'image';
	@override String get done => 'J\'ai noté le code';
	@override String get doneTitle => 'Vous avez bien gardé le code ?';
	@override String get doneBody => 'Une fois cette page fermée, il ne s\'affichera plus.';
	@override String get keep => 'Rester sur la page';
	@override String get cardHeading => 'Carte de secours Lunaway';
	@override String cardAccount({required Object name}) => 'Compte : ${name}';
	@override String get cardHow => 'Pour retrouver le compte : Profil, Retrouver mon compte, puis saisissez ce code ou photographiez la carte.';
	@override String cardMade({required Object date}) => 'Faite le ${date}';
	@override String get cardWarning => 'Ce code ouvre le compte : ne le confiez à personne.';
	@override String get failed => 'La carte n\'a pas pu être faite. Il faut une connexion.';
	@override String get fileName => 'carte-de-secours-lunaway';
	@override String get step1 => 'Faites la carte : le code ne s\'affiche qu\'une fois.';
	@override String get step2 => 'Enregistrez l\'image, imprimez-la, ou recopiez le code à la main.';
	@override String get step3 => 'Rangez-la dans la boîte à gants, avec les papiers du véhicule.';
}

// Path: recover
class _Translations$recover$fr extends Translations$recover$en {
	_Translations$recover$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Retrouver mon compte';
	@override String get intro => 'Tapez le code de votre carte de secours, ou lisez-le sur une photo de la carte.';
	@override String get field => 'Code de secours';
	@override String get fieldHint => '27 caractères, par groupes de quatre';
	@override String remaining({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Encore ${n} caractère',
		other: 'Encore ${n} caractères',
	);
	@override String get invalid => 'Ce code ne correspond à aucune carte : vérifiez chaque caractère.';
	@override String get valid => 'Code complet';
	@override String get scan => 'Lire la carte sur une photo';
	@override String get scanFile => 'Choisir l\'image de la carte';
	@override String get reading => 'Lecture de la carte';
	@override String get scanFailed => 'Aucun code lisible sur cette image. Essayez une photo plus nette, la carte bien à plat.';
	@override String get revoke => 'Mon ancien appareil est perdu ou volé : le déconnecter';
	@override String get revokeHint => 'Tous vos autres appareils seront déconnectés.';
	@override String get submit => 'Retrouver le compte';
	@override String get notFound => 'Aucun compte n\'a ce code. Vérifiez la carte, ou faites-en une nouvelle depuis un appareil connecté.';
	@override String get tooMany => 'Trop d\'essais pour l\'instant. Réessayez dans une heure.';
	@override String done({required Object name}) => 'Compte retrouvé : ${name}';
}

// Path: deletion
class _Translations$deletion$fr extends Translations$deletion$en {
	_Translations$deletion$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Supprimer mon compte';
	@override String get intro => 'La suppression est immédiate et définitive.';
	@override String get goneTitle => 'Ce qui disparaît';
	@override late final _Translations$deletion$gone$fr gone = _Translations$deletion$gone$fr._(_root);
	@override String get keptTitle => 'Ce qui reste, sans votre nom';
	@override String get kept => 'Vos avis écrits publiés, vos confirmations et vos modifications de lieux déjà appliquées restent, sans auteur : ils font partie de la carte des autres voyageurs.';
	@override String get backups => 'Les sauvegardes du serveur s\'effacent en 30 jours environ.';
	@override String get device => 'Sur cet appareil, vos favoris restent ; la clé du compte est effacée.';
	@override String get web => 'La suppression est aussi possible sur lunaway.net avec votre code de secours.';
	@override String get webLink => 'lunaway.net/account/delete';
	@override String get confirmTitle => 'Supprimer définitivement ?';
	@override String confirmBody({required Object name}) => 'Le compte « ${name} » et tout ce qui est listé disparaissent maintenant. Personne ne pourra le rétablir.';
	@override String get confirmCheck => 'Je comprends que c\'est définitif';
	@override String get confirm => 'Supprimer le compte';
	@override String get done => 'Compte supprimé';
	@override String get failed => 'Le compte n\'a pas pu être supprimé. Il faut une connexion.';
}

// Path: devices
class _Translations$devices$fr extends Translations$devices$en {
	_Translations$devices$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Appareils';
	@override String get intro => 'Chaque appareil a sa propre clé. Retirez un appareil perdu, ou celui que vous n\'utilisez plus.';
	@override String get thisDevice => 'Cet appareil';
	@override String get other => 'Autre appareil';
	@override String added({required Object date}) => 'Ajouté le ${date}';
	@override String lastUsed({required Object when}) => 'Dernier usage ${when}';
	@override String get revoke => 'Retirer';
	@override String get revokeTitle => 'Retirer cet appareil ?';
	@override String get revokeBody => 'Il sera déconnecté et ne pourra plus utiliser le compte.';
	@override String get revoked => 'Appareil retiré';
	@override String get signOutOthers => 'Déconnecter tous les autres appareils';
	@override String signedOutOthers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		zero: 'Aucune autre session ouverte',
		one: '${n} session fermée',
		other: '${n} sessions fermées',
	);
	@override String get error => 'Les appareils n\'ont pas pu s\'afficher. Il faut du réseau.';
}

// Path: muted
class _Translations$muted$fr extends Translations$muted$en {
	_Translations$muted$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Auteurs masqués';
	@override String get empty => 'Personne n\'est masqué';
	@override String get emptyHint => 'Pour masquer quelqu\'un, ouvrez le menu d\'un de ses avis ou d\'une de ses photos. Le masquage ne vaut que pour vous.';
	@override String get unmute => 'Ne plus masquer';
	@override String unmuted({required Object name}) => 'Les contributions de ${name} s\'afficheront de nouveau';
}

// Path: mine
class _Translations$mine$fr extends Translations$mine$en {
	_Translations$mine$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mes contributions';
	@override String get pending => 'En attente d\'envoi';
	@override String get pendingHint => 'Elles partent dès que le réseau revient.';
	@override String get sendNow => 'Envoyer maintenant';
	@override String get retry => 'Réessayer';
	@override String get discard => 'Abandonner';
	@override String get discardTitle => 'Abandonner cette contribution ?';
	@override String get discardBody => 'Elle ne sera pas envoyée.';
	@override String get reviews => 'Avis et notes';
	@override String get photos => 'Photos';
	@override String get confirmations => 'Confirmations';
	@override String get issues => 'Problèmes signalés';
	@override String get places => 'Lieux ajoutés et modifications';
	@override String get empty => 'Rien pour l\'instant';
	@override String get emptyHint => 'Noter un lieu ou confirmer qu\'il est toujours là, c\'est déjà une contribution.';
	@override String latest({required Object shown, required Object total}) => 'Les ${shown} contributions les plus récentes, sur ${total}';
	@override String get error => 'Vos contributions n\'ont pas pu s\'afficher. Il faut du réseau.';
	@override String get deleteTitle => 'Supprimer cette contribution ?';
	@override String get deleteBody => 'Elle disparaît de Lunaway.';
	@override String get deleteApplied => 'Ce lieu fait déjà partie de la carte : il y reste, sans votre nom.';
	@override String get deleted => 'Contribution supprimée';
	@override String get ratingOnly => 'Note seule';
	@override late final _Translations$mine$status$fr status = _Translations$mine$status$fr._(_root);
	@override late final _Translations$mine$submission$fr submission = _Translations$mine$submission$fr._(_root);
	@override String get newPlace => 'Nouveau lieu';
	@override String get edit => 'Modification';
	@override String get aPlace => 'Un lieu';
	@override String get newVendingMachine => 'Nouveau distributeur';
	@override String get poiConfirmations => 'Commerces et services confirmés';
	@override String get aPoi => 'Un commerce ou service';
}

// Path: outbox
class _Translations$outbox$fr extends Translations$outbox$en {
	_Translations$outbox$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$outbox$kind$fr kind = _Translations$outbox$kind$fr._(_root);
	@override String get waiting => 'En attente du réseau';
	@override String get sending => 'Envoi en cours';
	@override late final _Translations$outbox$error$fr error = _Translations$outbox$error$fr._(_root);
	@override String get sent => 'Merci, c\'est envoyé';
	@override String get queued => 'Pas de réseau : envoi dès qu\'il revient';
	@override String refused({required Object reason}) => 'Pas envoyé. ${reason}';
}

// Path: placement
class _Translations$placement$fr extends Translations$placement$en {
	_Translations$placement$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Placez le lieu';
	@override String get hint => 'Déplacez la carte : la croix marque l\'endroit exact.';
	@override String get confirm => 'Valider cet emplacement';
	@override String duplicate({required Object name, required Object distance}) => 'Il y a déjà « ${name} » à ${distance} : est-ce le même endroit ?';
	@override String get same => 'Oui, ouvrir sa fiche';
	@override String get notSame => 'Non, c\'est un autre lieu';
}

// Path: contribute
class _Translations$contribute$fr extends Translations$contribute$en {
	_Translations$contribute$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get yourRating => 'Votre note';
	@override String get rateHint => 'Touchez une étoile pour noter';
	@override String rateStar({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Noter ${n} étoile',
		other: 'Noter ${n} étoiles',
	);
	@override String get writeReview => 'Écrire un avis';
	@override String get editReview => 'Modifier votre avis';
	@override String get deleteReview => 'Supprimer votre avis';
	@override String get deleteReviewTitle => 'Supprimer votre avis ?';
	@override String get deleteReviewBody => 'Le texte et la note disparaissent de la fiche.';
	@override String get deleteRating => 'Retirer votre note';
	@override String get deleteRatingTitle => 'Retirer votre note ?';
	@override String get deleteRatingBody => 'Votre note disparaît de la fiche.';
	@override String get pendingSend => 'En attente d\'envoi';
	@override String get statusPending => 'En relecture : visible par vous uniquement pour l\'instant';
	@override String get statusHidden => 'Masqué après des signalements, en attente d\'un modérateur';
	@override String get statusRemoved => 'Retiré par la modération';
	@override String get addPhoto => 'Ajouter une photo';
	@override String get firstPhoto => 'Ajouter la première photo';
	@override String get stillThere => 'Toujours là ?';
	@override String get more => 'Plus d\'actions';
	@override String get reportIssue => 'Signaler un problème';
	@override String get proposeEdit => 'Proposer une modification';
	@override String get editPlace => 'Modifier le lieu';
	@override String get reportPlace => 'Signaler ce lieu à la modération';
	@override String get toVerifyTitle => 'À vérifier';
	@override String get toVerifyBody => 'Lieu ajouté par la communauté, en attente de deux confirmations. Vous le connaissez ? Confirmez-le.';
	@override String get issuesTitle => 'Signalements des 30 derniers jours';
	@override String issueCount({required Object kind, required Object count}) => '${kind} (${count})';
	@override String get addPlaceHere => 'Créer un lieu ici';
	@override String get addPlaceHint => 'L\'endroit choisi sous la croix.';
}

// Path: confirmSheet
class _Translations$confirmSheet$fr extends Translations$confirmSheet$en {
	_Translations$confirmSheet$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Toujours là ?';
	@override String get body => 'Vous y êtes passé récemment ? Votre réponse montre aux prochains voyageurs que la fiche est à jour. Aucune position n\'est envoyée.';
	@override String get stillOk => 'Oui, comme décrit';
	@override String get closed => 'Fermé';
	@override String get changed => 'Changé';
	@override String get closedHint => 'N\'accueille plus de voyageurs';
	@override String get changedHint => 'Existe, mais quelque chose a changé';
	@override String get note => 'Une précision (facultative)';
	@override String get noteHint => 'Par exemple : barrière de hauteur posée, borne déplacée';
	@override late final _Translations$confirmSheet$status$fr status = _Translations$confirmSheet$status$fr._(_root);
}

// Path: issueSheet
class _Translations$issueSheet$fr extends Translations$issueSheet$en {
	_Translations$issueSheet$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Signaler un problème';
	@override String get body => 'Votre signalement compte dans l\'avertissement affiché sur la fiche. Votre précision ne va qu\'aux modérateurs.';
	@override late final _Translations$issueSheet$kind$fr kind = _Translations$issueSheet$kind$fr._(_root);
	@override late final _Translations$issueSheet$hint$fr hint = _Translations$issueSheet$hint$fr._(_root);
	@override String get note => 'Une précision (facultative)';
	@override String get send => 'Signaler';
}

// Path: reportSheet
class _Translations$reportSheet$fr extends Translations$reportSheet$en {
	_Translations$reportSheet$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get review => 'Signaler cet avis';
	@override String get photo => 'Signaler cette photo';
	@override String get place => 'Signaler ce lieu';
	@override String get body => 'Les modérateurs le liront. L\'auteur ne saura pas qui l\'a signalé.';
	@override late final _Translations$reportSheet$reason$fr reason = _Translations$reportSheet$reason$fr._(_root);
	@override String get note => 'Dites-en plus (facultatif)';
	@override String get noteOther => 'Dites ce qui ne va pas';
	@override String get sent => 'Merci, les modérateurs vont regarder';
	@override String mute({required Object name}) => 'Masquer les avis et photos de ${name}';
	@override String get muteAuthor => 'Masquer cet auteur';
	@override String muteTitle({required Object name}) => 'Masquer ${name} ?';
	@override String get muteBody => 'Ses avis et ses photos ne s\'afficheront plus pour vous. Vous pourrez revenir sur ce choix dans le profil.';
	@override String muted({required Object name}) => '${name} est masqué';
	@override String get deletePhoto => 'Supprimer ma photo';
	@override String get deletePhotoTitle => 'Supprimer cette photo ?';
	@override String get deletePhotoBody => 'Elle disparaît de la fiche et de nos serveurs.';
}

// Path: reviewSheet
class _Translations$reviewSheet$fr extends Translations$reviewSheet$en {
	_Translations$reviewSheet$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get titleNew => 'Votre avis';
	@override String get titleEdit => 'Modifier votre avis';
	@override String get starsRequired => 'Choisissez une note de 1 à 5';
	@override String get text => 'Votre avis';
	@override String get textHint => 'Le calme, l\'accueil, la place pour manœuvrer, ce qui vous a servi';
	@override String tooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Encore ${n} caractère au moins',
		other: 'Encore ${n} caractères au moins',
	);
	@override String get visited => 'Date du séjour';
	@override String get visitedNone => 'Non précisée';
	@override String get vehicle => 'Votre véhicule';
	@override String get vehicleNone => 'Ne pas préciser';
	@override String get licence => 'Publié sous licence CC BY 4.0, avec votre pseudonyme. La date du séjour est facultative : réunies, les dates de vos avis peuvent révéler votre parcours.';
	@override String get publish => 'Publier l\'avis';
}

// Path: gate
class _Translations$gate$fr extends Translations$gate$en {
	_Translations$gate$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get review => 'Avis écrits : à partir du niveau 1';
	@override String get photo => 'Photos : à partir du niveau 1';
	@override String get addPlace => 'Ajout de lieux : à partir du niveau 2';
	@override String get edit => 'Propositions de modification : à partir du niveau 1';
	@override String get why => 'Les niveaux protègent la carte des abus. Ils viennent avec le temps et les contributions, sans rien à acheter.';
	@override String yourLevel({required Object level}) => 'Votre niveau : ${level}';
	@override String get noAccount => 'Pas encore de compte : un compte commence au niveau 0.';
	@override String later({required Object level}) => 'Le niveau ${level} vient après les précédents, avec le temps et les contributions publiées.';
	@override String get meanwhile => 'En attendant, vous pouvez noter les lieux, confirmer qu\'ils sont toujours là ou signaler un problème.';
}

// Path: photoFlow
class _Translations$photoFlow$fr extends Translations$photoFlow$en {
	_Translations$photoFlow$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ajouter une photo';
	@override String get camera => 'Prendre une photo';
	@override String get gallery => 'Choisir dans la galerie';
	@override String get preparing => 'Préparation de la photo';
	@override String get licence => 'Publiée sous licence CC BY 4.0, avec votre pseudonyme. Évitez les visages et les plaques d\'immatriculation.';
	@override String get stripped => 'La position et les données de l\'appareil sont retirées avant l\'envoi.';
	@override String get send => 'Envoyer la photo';
	@override String get unreadable => 'Cette image ne peut pas être lue sur cet appareil. Essayez une photo JPEG ou PNG.';
	@override String sending({required Object percent}) => 'Envoi ${percent} %';
	@override String get pending => 'Photo en attente d\'envoi';
}

// Path: placeForm
class _Translations$placeForm$fr extends Translations$placeForm$en {
	_Translations$placeForm$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get addTitle => 'Ajouter un lieu';
	@override String get editTitle => 'Modifier le lieu';
	@override String get proposeTitle => 'Proposer une modification';
	@override String get position => 'Position sur la carte';
	@override String get kind => 'Type de lieu';
	@override String get kindRequired => 'Choisissez un type de lieu';
	@override String get name => 'Nom';
	@override String get nameHint => 'Le nom affiché sur place, ou une description courte';
	@override String get nameInvalid => 'De 2 à 120 caractères';
	@override String get night => 'Nuit sur place';
	@override String get services => 'Services sur place';
	@override String get description => 'Description';
	@override String get descriptionHint => 'Ce qui aide à trouver et à choisir le lieu';
	@override String get details => 'Précisions';
	@override String get priceNight => 'Prix de la nuit (€)';
	@override String get priceServices => 'Prix des services (€)';
	@override String get maxHeight => 'Hauteur maximale (m)';
	@override String get capacity => 'Emplacements';
	@override String get website => 'Site web';
	@override String get phone => 'Téléphone';
	@override String get photo => 'Photo (facultative)';
	@override String get photoReady => 'Photo prête';
	@override String get removePhoto => 'Retirer la photo';
	@override String get toVerify => 'Le lieu apparaîtra « à vérifier » jusqu\'à ce que deux autres voyageurs le confirment.';
	@override String get licence => 'Les lieux sont publiés sous licence ODbL, crédités aux contributeurs de Lunaway.';
	@override String get moderated => 'Un site web ou un téléphone passe par un modérateur avant d\'être publié.';
	@override String get direct => 'Votre niveau applique la modification tout de suite.';
	@override String get proposal => 'Un modérateur relira votre proposition avant qu\'elle s\'applique.';
	@override String get submitAdd => 'Ajouter le lieu';
	@override String get submitEdit => 'Enregistrer la modification';
	@override String get submitPropose => 'Envoyer la proposition';
	@override String get nothingChanged => 'Rien n\'a changé';
	@override String get invalidNumber => 'Un nombre, s\'il vous plaît';
	@override String get invalidWebsite => 'Une adresse qui commence par http:// ou https://';
	@override String get added => 'Merci : le lieu arrive sur la carte dans un instant';
	@override String get proposed => 'Merci : votre proposition part en relecture';
}

// Path: favoritesSync
class _Translations$favoritesSync$fr extends Translations$favoritesSync$en {
	_Translations$favoritesSync$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get local => 'Sur cet appareil seulement';
	@override String get action => 'Synchroniser';
	@override String get syncing => 'Synchronisation en cours';
	@override String synced({required Object when}) => 'Gardés avec votre compte, synchronisés ${when}';
	@override String get failed => 'Synchronisation impossible pour l\'instant';
	@override String get title => 'Synchroniser vos favoris ?';
	@override String get body => 'Vos listes seront gardées avec un compte Lunaway, sans e-mail ni mot de passe, pour les retrouver sur un autre appareil. Le compte se crée maintenant.';
	@override String get confirm => 'Créer le compte et synchroniser';
}

// Path: poi
class _Translations$poi$fr extends Translations$poi$en {
	_Translations$poi$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$poi$category$fr category = _Translations$poi$category$fr._(_root);
	@override late final _Translations$poi$kind$fr kind = _Translations$poi$kind$fr._(_root);
	@override String get chipsLabel => 'Commerces et services autour';
	@override String get openNow => 'Ouvert maintenant';
	@override late final _Translations$poi$vendingSells$fr vendingSells = _Translations$poi$vendingSells$fr._(_root);
	@override String get vendingAll => 'Tous les distributeurs alimentaires';
	@override String get vendingMenu => 'Ce que vendent les distributeurs';
	@override late final _Translations$poi$vendingChip$fr vendingChip = _Translations$poi$vendingChip$fr._(_root);
	@override String get alwaysOpen => 'Ouvert jour et nuit';
	@override String get hoursUnknown => 'Horaires inconnus';
	@override String get maybeClosed => 'Fermé selon l\'annuaire officiel des établissements de santé (FINESS).';
	@override String maybeClosedSince({required Object date}) => 'Indiqué fermé par FINESS depuis le ${date} : il a peut-être fermé définitivement.';
	@override String get seasonal => 'Saisonnier : il peut être fermé en hiver.';
	@override String get fee => 'Payant';
	@override String get free => 'Gratuit';
	@override String get stillThereTitle => 'Toujours là ?';
	@override String get stillThereHint => 'Vu récemment ? Votre réponse aide les prochains voyageurs. Aucune position n\'est envoyée.';
	@override String get stillThere => 'Toujours là';
	@override String get gone => 'N\'existe plus';
	@override String lastConfirmed({required Object when}) => 'Confirmé présent ${when}';
	@override String checkedOn({required Object date}) => 'Vérifié sur place le ${date}';
	@override String get thanksThere => 'Merci, c\'est noté : toujours là.';
	@override String get thanksGone => 'Merci, c\'est noté : n\'existe plus.';
	@override String get fuelPrices => 'Prix des carburants';
	@override String perLitre({required Object price}) => '${price}/L';
	@override String priceUpdated({required Object when}) => 'Prix mis à jour ${when}';
	@override String feedRead({required Object when}) => 'Prix relevés ${when}';
	@override String get shortageTemporary => 'En rupture pour l\'instant';
	@override String get shortageDefinitive => 'N\'en vend plus';
	@override String get selfService24h => 'Paiement par carte 24 h/24';
	@override String get highway => 'Sur autoroute';
	@override String get lpgYes => 'Vend du GPL';
	@override late final _Translations$poi$fuel$fr fuel = _Translations$poi$fuel$fr._(_root);
	@override String get products => 'Vend';
	@override String get paymentTitle => 'Paiement';
	@override late final _Translations$poi$product$fr product = _Translations$poi$product$fr._(_root);
	@override late final _Translations$poi$payment$fr payment = _Translations$poi$payment$fr._(_root);
	@override String get justNow => 'à l\'instant';
	@override String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'il y a ${n} minute',
		other: 'il y a ${n} minutes',
	);
	@override String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'il y a ${n} heure',
		other: 'il y a ${n} heures',
	);
	@override String readOffline({required Object when}) => 'Relevé ${when} : pas de réseau pour l\'actualiser';
	@override String readStale({required Object when}) => 'Relevé ${when} : l\'actualisation n\'a pas abouti pour l\'instant.';
	@override String get goneTitle => 'Ce point n\'est plus sur la carte';
	@override String get goneHint => 'Des voyageurs l\'ont dit disparu, ou la dernière mise à jour l\'a retiré.';
	@override String get loadError => 'Le détail n\'a pas pu s\'afficher. Ce que la carte en sait est au-dessus.';
	@override String get around => 'Autour de ce lieu';
	@override String get aroundEmpty => 'Aucun commerce ni service connu autour.';
	@override String get aroundError => 'Les commerces et services autour n\'ont pas pu s\'afficher.';
	@override String get aroundOffline => 'Pas de réseau : les commerces et services autour s\'afficheront avec une connexion.';
	@override String get onSite => 'Sur place';
	@override String backTo({required Object name}) => 'Retour à ${name}';
	@override String get backToPlace => 'Retour au lieu';
	@override String get linkError => 'Ce commerce ou service n\'a pas pu être ouvert : pas de réseau, ou il n\'est plus sur la carte.';
	@override String get searchSection => 'Commerces et services';
	@override String get searching => 'Recherche des commerces et services';
	@override String get searchOffline => 'Les commerces et services se cherchent en ligne : pas de réseau maintenant.';
	@override late final _Translations$poi$add$fr add = _Translations$poi$add$fr._(_root);
	@override late final _Translations$poi$cheapest$fr cheapest = _Translations$poi$cheapest$fr._(_root);
	@override late final _Translations$poi$trend$fr trend = _Translations$poi$trend$fr._(_root);
}

// Path: offlineMaps
class _Translations$offlineMaps$fr extends Translations$offlineMaps$en {
	_Translations$offlineMaps$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Cartes hors ligne';
	@override String get intro => 'Avant de partir, gardez une région sur l\'appareil : ses lieux pour chercher et choisir, sa carte pour voir les rues sans réseau.';
	@override String get webTitle => 'Les cartes hors ligne sont dans l\'application';
	@override String get web => 'Les applications Android et iOS gardent des régions pour la route. Dans un navigateur, la carte a besoin du réseau.';
	@override String get desktopTitle => 'Les cartes hors ligne sont sur le téléphone';
	@override String get desktop => 'Les applications Android et iOS gardent des régions pour la route. Sur ordinateur, la carte a besoin du réseau.';
	@override String get unreadable => 'Les cartes hors ligne de cet appareil n\'ont pas pu s\'afficher.';
	@override String get none => 'Aucune région sur cet appareil pour l\'instant.';
	@override String used({required Object size}) => 'Espace utilisé : ${size}';
	@override String get downloads => 'Téléchargements';
	@override String get installed => 'Sur cet appareil';
	@override String get suggested => 'Suggérées';
	@override String get here => 'Là où vous êtes';
	@override String favoritesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} favori dans cette région',
		other: '${n} favoris dans cette région',
	);
	@override String get france => 'France';
	@override String get overseas => 'Outre-mer';
	@override String get countries => 'Pays';
	@override String downloadNamed({required Object name, required Object size}) => 'Télécharger ${name}, ${size}';
	@override String get pause => 'Mettre en pause';
	@override String get resume => 'Reprendre';
	@override String get cancel => 'Arrêter et effacer le téléchargement';
	@override String get waiting => 'En attente de son tour';
	@override String progress({required Object done, required Object total}) => '${done} sur ${total}';
	@override String paused({required Object done, required Object total}) => 'En pause à ${done} sur ${total}';
	@override String get verifying => 'Vérification du fichier';
	@override String get failedNetwork => 'Interrompu : pas de réseau. Il reprendra là où il s\'est arrêté dès que le réseau reviendra.';
	@override String get failedServer => 'Le serveur a envoyé autre chose que la carte. Réessayez plus tard.';
	@override String get failedCorrupt => 'Le fichier est arrivé abîmé et a été effacé. Réessayez.';
	@override String get failedStorage => 'Plus assez de place sur l\'appareil. Libérez de l\'espace, puis réessayez.';
	@override String get keepOpen => 'Gardez l\'application ouverte pendant le téléchargement : il s\'interrompt quand elle passe en arrière-plan et reprend quand vous y revenez.';
	@override String dataOf({required Object date}) => 'données du ${date}';
	@override String update({required Object size}) => 'Mettre à jour, ${size}';
	@override String deleteNamed({required Object name}) => 'Supprimer ${name}';
	@override String deleteTitle({required Object name}) => 'Supprimer ${name} de cet appareil ?';
	@override String get deleteBody => 'Elle ne s\'affichera plus sans réseau. Vous pourrez la télécharger de nouveau.';
	@override String get listOffline => 'La liste des régions demande du réseau.';
	@override String get listCopy => 'Liste gardée de la dernière connexion.';
	@override String get entryHint => 'Pour voyager sans réseau';
	@override String entryCount({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Cartes : ${n} région, ${size}',
		other: 'Cartes : ${n} régions, ${size}',
	);
	@override String noticePack({required Object name}) => 'Hors ligne : carte téléchargée, ${name}';
	@override String get noticeOutside => 'Hors ligne : cette zone n\'est pas téléchargée';
	@override String get noticePlacesOnly => 'Hors ligne : lieux sur l\'appareil, carte de cette zone à télécharger';
	@override String get noticeNone => 'Hors ligne : téléchargez une région pour la prochaine fois';
	@override String get noticeOnline => 'Hors ligne : la carte a besoin du réseau';
	@override String get placesTitle => 'Lieux';
	@override String get placesHint => 'Quelques mégaoctets par région : la liste, la recherche, les fiches et les filtres marchent sans réseau.';
	@override String get mapsTitle => 'Cartes';
	@override String get mapsHint => 'Toutes les rues, quelques centaines de mégaoctets par région : la carte s\'affiche sans réseau.';
	@override String entryPlaces({required Object names}) => 'Lieux : ${names}';
	@override String entryPlacesCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Lieux : ${n} région',
		other: 'Lieux : ${n} régions',
	);
}

// Path: regions
class _Translations$regions$fr extends Translations$regions$en {
	_Translations$regions$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get pickerTitle => 'Quels lieux garder sur cet appareil ?';
	@override String get pickerIntro => 'Chaque région se télécharge une fois, puis se met à jour par petits morceaux. Vous pourrez en ajouter ou en retirer plus tard dans Cartes hors ligne.';
	@override String nearYou({required Object name}) => 'Près de vous : ${name}';
	@override String get findMine => 'Trouver ma région';
	@override String get locating => 'Recherche de votre région';
	@override String get notCovered => 'Pas encore de région Lunaway autour de vous';
	@override String get wholeFrance => 'Toute la France';
	@override String get showFrance => 'Afficher les régions de France';
	@override String get hideFrance => 'Masquer les régions de France';
	@override String packInfo({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${count} lieu, ${size}',
		other: '${count} lieux, ${size}',
	);
	@override String get noPack => 'Sans paquet : lieux reçus avec les mises à jour, taille inconnue';
	@override String download({required Object size}) => 'Télécharger, ${size}';
	@override String get unavailable => 'Le serveur ne propose pas encore de régions : Lunaway garde toute la France.';
	@override String get listFailed => 'La liste des régions demande du réseau.';
	@override String get choose => 'Choisir les régions';
	@override String get noneKept => 'Aucune région gardée : la carte n\'a aucun lieu hors connexion.';
	@override String get change => 'Ajouter ou retirer des régions';
	@override String removeNamed({required Object name}) => 'Retirer ${name}';
	@override String removed({required Object name}) => '${name} : lieux retirés de cet appareil';
	@override String downloading({required Object done, required Object total}) => 'Téléchargement, ${done} sur ${total}';
	@override String updating({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Mise à jour, ${count} lieu',
		other: 'Mise à jour, ${count} lieux',
	);
	@override String get waiting => 'en attente de son téléchargement';
	@override String downloadingNamed({required Object name}) => 'Téléchargement des lieux : ${name}';
	@override String updated({required Object when}) => 'mis à jour ${when}';
	@override String offerTitle({required Object name}) => '${name} : garder ses lieux hors connexion ?';
	@override String get downloadThis => 'Télécharger cette région';
	@override String notHere({required Object name}) => '${name} n\'est pas sur cet appareil';
	@override String get updatesOnMobile => 'Mettre à jour avec les données mobiles';
	@override String get updatesOnMobileHint => 'Sinon, les régions déjà téléchargées se mettent à jour en Wi-Fi. Un nouveau téléchargement passe par tout réseau.';
}

// Path: roadReport
class _Translations$roadReport$fr extends Translations$roadReport$en {
	_Translations$roadReport$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get actionHint => 'Signaler un problème sur la route';
	@override String get title => 'Que voyez-vous sur la route ?';
	@override String get intro => 'Votre signalement prévient les autres voyageurs. Quand deux comptes de confiance signalent la même chose, les itinéraires l\'évitent. Les contrôles de police ne se signalent pas.';
	@override late final _Translations$roadReport$kinds$fr kinds = _Translations$roadReport$kinds$fr._(_root);
	@override String height({required Object value}) => 'Hauteur indiquée : ${value}';
	@override String get send => 'Signaler';
	@override String get sent => 'Merci : les autres voyageurs sont prévenus.';
	@override String get movingTitle => 'Vous roulez';
	@override String get movingBody => 'Ne signalez rien en conduisant. Un passager peut le faire ; sinon, arrêtez-vous d\'abord.';
	@override String get passenger => 'Je suis passager';
	@override String get stillThere => 'Toujours là';
	@override String get over => 'C\'est fini';
	@override String get overSent => 'Merci : c\'est noté.';
	@override String get fromMap => 'Signaler un problème ici';
	@override String get notHereTitle => 'Pas de signalement ici';
	@override String get lower => 'Plus bas de 10 cm';
	@override String get higher => 'Plus haut de 10 cm';
	@override String passed({required Object what}) => 'Vous venez de passer : ${what}. Toujours là ?';
	@override String notHere({required Object countries}) => 'Lunaway accepte les signalements là où un flux officiel les recoupe : ${countries}.';
}

// Path: countries
class _Translations$countries$fr extends Translations$countries$en {
	_Translations$countries$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get ad => 'Andorre';
	@override String get at => 'Autriche';
	@override String get ax => 'Åland';
	@override String get be => 'Belgique';
	@override String get ch => 'Suisse';
	@override String get cz => 'Tchéquie';
	@override String get de => 'Allemagne';
	@override String get dk => 'Danemark';
	@override String get eh => 'Sahara occidental';
	@override String get es => 'Espagne';
	@override String get fi => 'Finlande';
	@override String get fr => 'France';
	@override String get gb => 'Royaume-Uni';
	@override String get gi => 'Gibraltar';
	@override String get gr => 'Grèce';
	@override String get hr => 'Croatie';
	@override String get ie => 'Irlande';
	@override String get it => 'Italie';
	@override String get li => 'Liechtenstein';
	@override String get lu => 'Luxembourg';
	@override String get ma => 'Maroc';
	@override String get mc => 'Monaco';
	@override String get nl => 'Pays-Bas';
	@override String get no => 'Norvège';
	@override String get pl => 'Pologne';
	@override String get pt => 'Portugal';
	@override String get se => 'Suède';
	@override String get si => 'Slovénie';
	@override String get sj => 'Svalbard';
	@override String get sm => 'Saint-Marin';
	@override String get va => 'Vatican';
}

// Path: areas
class _Translations$areas$fr extends Translations$areas$en {
	_Translations$areas$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get ara => 'Auvergne-Rhône-Alpes';
	@override String get bfc => 'Bourgogne-Franche-Comté';
	@override String get bre => 'Bretagne';
	@override String get cvl => 'Centre-Val de Loire';
	@override String get cor => 'Corse';
	@override String get ges => 'Grand Est';
	@override String get hdf => 'Hauts-de-France';
	@override String get idf => 'Île-de-France';
	@override String get nor => 'Normandie';
	@override String get naq => 'Nouvelle-Aquitaine';
	@override String get occ => 'Occitanie';
	@override String get pdl => 'Pays de la Loire';
	@override String get pac => 'Provence-Alpes-Côte d\'Azur';
	@override String get gp => 'Guadeloupe';
	@override String get mq => 'Martinique';
	@override String get gf => 'Guyane';
	@override String get re => 'La Réunion';
	@override String get yt => 'Mayotte';
	@override String get franceRest => 'France, hors commune';
}

// Path: search.addressKind
class _Translations$search$addressKind$fr extends Translations$search$addressKind$en {
	_Translations$search$addressKind$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get houseNumber => 'Adresse';
	@override String get street => 'Rue';
	@override String get locality => 'Lieu-dit';
	@override String get town => 'Commune';
	@override String get postcode => 'Code postal';
	@override String get region => 'Région';
}

// Path: place.inclusions
class _Translations$place$inclusions$fr extends Translations$place$inclusions$en {
	_Translations$place$inclusions$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get services => 'services';
	@override String get touristTax => 'taxe de séjour';
	@override String get electricity => 'électricité';
}

// Path: place.reviewVehicle
class _Translations$place$reviewVehicle$fr extends Translations$place$reviewVehicle$en {
	_Translations$place$reviewVehicle$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Fourgon aménagé';
	@override String get motorhome => 'Camping-car';
	@override String get caravan => 'Caravane';
	@override String get other => 'Autre véhicule';
}

// Path: sources.extcom
class _Translations$sources$extcom$fr extends Translations$sources$extcom$en {
	_Translations$sources$extcom$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get label => 'Source communautaire externe';
	@override String get short => 'Externe';
}

// Path: hours.codes
class _Translations$hours$codes$fr extends Translations$hours$codes$en {
	_Translations$hours$codes$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get mo => 'lun.';
	@override String get tu => 'mar.';
	@override String get we => 'mer.';
	@override String get th => 'jeu.';
	@override String get fr => 'ven.';
	@override String get sa => 'sam.';
	@override String get su => 'dim.';
	@override String get ph => 'jours fériés';
	@override String get sh => 'vacances scolaires';
	@override String get off => 'fermé';
	@override String get closed => 'fermé';
	@override String get sunrise => 'lever du soleil';
	@override String get sunset => 'coucher du soleil';
}

// Path: hours.months
class _Translations$hours$months$fr extends Translations$hours$months$en {
	_Translations$hours$months$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get jan => 'janv.';
	@override String get feb => 'févr.';
	@override String get mar => 'mars';
	@override String get apr => 'avr.';
	@override String get may => 'mai';
	@override String get jun => 'juin';
	@override String get jul => 'juil.';
	@override String get aug => 'août';
	@override String get sep => 'sept.';
	@override String get oct => 'oct.';
	@override String get nov => 'nov.';
	@override String get dec => 'déc.';
}

// Path: navigation.preview
class _Translations$navigation$preview$fr extends Translations$navigation$preview$en {
	_Translations$navigation$preview$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String titleTo({required Object name}) => 'Vers ${name}';
	@override String get titlePoint => 'Point sur la carte';
	@override late final _Translations$navigation$preview$departure$fr departure = _Translations$navigation$preview$departure$fr._(_root);
	@override String get computing => 'Calcul d\'un itinéraire pour votre véhicule';
	@override String get start => 'C\'est parti !';
	@override String get recommended => 'Recommandé';
	@override String alternative({required Object n}) => 'Variante ${n}';
	@override String get toll => 'Péage';
	@override String get ferry => 'Ferry';
	@override String get motorway => 'Autoroute';
	@override String get noWarnings => 'Aucune limite proche du gabarit de votre véhicule sur ce trajet.';
	@override String warnings({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '1 limite à surveiller',
		other: '${n} limites à surveiller',
	);
	@override String get vehicle => 'Votre véhicule';
	@override String vehicleTowing({required Object vehicle}) => '${vehicle}, avec attelage';
	@override String get editVehicle => 'Modifier';
	@override String cruise({required Object speed}) => 'Calculé à ${speed} max';
	@override String get avoid => 'Éviter';
	@override String get avoidTolls => 'Péages';
	@override String get avoidMotorways => 'Autoroutes';
	@override String get avoidFerries => 'Ferries';
	@override String get avoidUnpaved => 'Routes non revêtues';
	@override String get roadbook => 'Feuille de route';
	@override String get roadbookShow => 'Voir les instructions';
	@override String get roadbookHide => 'Masquer les instructions';
	@override String dataOf({required Object date}) => 'Données routières du ${date}';
	@override String get attributionOsm => '© les contributeurs d\'OpenStreetMap';
	@override String attributionIgn({required Object date}) => 'IGN, BD TOPO, édition du ${date}';
	@override String get disclaimer => 'Lunaway calcule l\'itinéraire avec les dimensions de votre véhicule et des données ouvertes (OpenStreetMap, IGN) qui peuvent être incomplètes ou erronées. La signalisation et le code de la route priment sur les indications de l\'application. Vous restez seul responsable de votre conduite.';
	@override String get otherApps => 'Ouvrir dans…';
	@override String get back => 'Retour';
	@override late final _Translations$navigation$preview$moved$fr moved = _Translations$navigation$preview$moved$fr._(_root);
}

// Path: navigation.stops
class _Translations$navigation$stops$fr extends Translations$navigation$stops$en {
	_Translations$navigation$stops$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Étapes';
	@override String get add => 'Ajouter comme étape';
	@override String addCost({required Object minutes}) => 'Ajouter comme étape · +${minutes} min';
	@override String get addFree => 'Ajouter comme étape · sans détour';
	@override String get quoting => 'Ajouter comme étape · calcul du détour';
	@override String get noRoute => 'Pas d\'itinéraire par ce point pour votre véhicule.';
	@override String get full => 'Cinq étapes au plus.';
	@override String get goDirectly => 'Y aller directement';
	@override String get openCard => 'Voir la fiche';
	@override String get point => 'Point sur la carte';
	@override String get remove => 'Retirer l\'étape';
	@override String get reorder => 'Glisser pour changer l\'ordre';
	@override String get added => 'Étape ajoutée';
	@override String get removed => 'Étape retirée';
	@override String get moved => 'Ordre des étapes changé';
	@override String get destinationChanged => 'Nouvelle destination';
	@override String get failed => 'L\'itinéraire n\'a pas pu être changé.';
	@override String get noQuote => 'Le détour n\'a pas pu être calculé.';
	@override String get offline => 'Pas de réseau pour calculer le détour.';
}

// Path: navigation.fuel
class _Translations$navigation$fuel$fr extends Translations$navigation$fuel$en {
	_Translations$navigation$fuel$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String price({required Object price}) => '${price} €/L';
	@override String withDetour({required Object price}) => '${price} €/L détour compris';
	@override String detour({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min';
	@override String get onRoute => 'sur le trajet';
	@override String get open => 'Ouvert';
	@override String get closed => 'Fermé';
	@override String get unknownHours => 'Horaires inconnus';
	@override String get add => 'Ajouter';
	@override String get station => 'Station-service';
	@override String get empty => 'Aucune station de ce carburant près du trajet.';
	@override String get failed => 'Les stations n\'ont pas pu être chargées.';
	@override String get estimated => 'Détours estimés d\'après la distance à la route.';
	@override String get attribution => 'Prix : ministère de l\'Économie (data.economie.gouv.fr)';
	@override String minutesAgo({required Object n}) => 'il y a ${n} min';
	@override String hoursAgo({required Object n}) => 'il y a ${n} h';
	@override String daysAgo({required Object n}) => 'il y a ${n} j';
}

// Path: navigation.onTheWay
class _Translations$navigation$onTheWay$fr extends Translations$navigation$onTheWay$en {
	_Translations$navigation$onTheWay$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sur le trajet';
	@override late final _Translations$navigation$onTheWay$categories$fr categories = _Translations$navigation$onTheWay$categories$fr._(_root);
	@override String fuelOfVehicle({required Object fuel}) => '${fuel}, d\'après votre véhicule';
	@override String get otherFuel => 'Autre carburant';
	@override String get keepFuel => 'Retenir comme mon carburant';
	@override String fuelKept({required Object fuel}) => '${fuel} retenu pour votre véhicule.';
	@override String get keepFuelFailed => 'Le carburant n\'a pas pu être retenu.';
	@override String get loading => 'Recherche le long du trajet';
	@override String get empty => 'Pas de résultat sur ce trajet';
	@override String get emptyHint => 'Essayez une autre catégorie, ou rouvrez la liste plus loin sur la route.';
	@override String get failed => 'La liste n\'a pas pu être chargée.';
	@override String get offline => 'Pas de réseau : la liste reviendra avec la connexion.';
	@override String get rateLimited => 'Beaucoup de recherches d\'affilée : réessayez dans quelques minutes.';
	@override String nearNone({required Object distance}) => 'Rien dans les ${distance} devant vous.';
	@override String further({required Object n}) => 'Plus loin (${n})';
	@override String get more => 'Voir plus';
	@override String get moreFailed => 'La suite n\'a pas pu être chargée.';
	@override String ahead({required Object distance}) => 'dans ${distance}';
	@override String offRoute({required Object distance}) => 'à ${distance} de la route';
	@override String get byTheRoad => 'au bord de la route';
	@override String addCost({required Object minutes}) => 'Ajouter · +${minutes} min';
	@override String get addFree => 'Ajouter · sans détour';
	@override String openAt({required Object time}) => 'Ouvert à votre passage, vers ${time}';
	@override String closedAt({required Object time}) => 'Fermé à votre passage, vers ${time}';
	@override String closedOpensAt({required Object time, required Object opens}) => 'Fermé à votre passage vers ${time}, ouvre à ${opens}';
	@override String perNight({required Object price}) => '${price} la nuit';
	@override String photoFrom({required Object source}) => 'Photo : ${source}';
	@override String servicesList({required Object list}) => 'Services : ${list}';
	@override String get movingBody => 'Ne cherchez rien en conduisant. Un passager peut le faire ; sinon, arrêtez-vous d\'abord.';
	@override String get placesCredit => 'Lieux : Lunaway et les sources nommées sur chaque fiche';
}

// Path: navigation.states
class _Translations$navigation$states$fr extends Translations$navigation$states$en {
	_Translations$navigation$states$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get vehicleTitle => 'Quel est votre véhicule ?';
	@override String get vehicleHint => 'L\'itinéraire évite les ponts trop bas, les rues trop étroites et les routes interdites à votre gabarit. Indiquez sa hauteur, sa largeur, sa longueur et son poids.';
	@override String vehicleMissing({required Object list}) => 'Il manque : ${list}';
	@override String vehicleOutOfBounds({required Object list}) => 'Hors des valeurs acceptées : ${list}';
	@override late final _Translations$navigation$states$dimension$fr dimension = _Translations$navigation$states$dimension$fr._(_root);
	@override String get describeVehicle => 'Décrire mon véhicule';
	@override String get originTitle => 'Où êtes-vous ?';
	@override String get originHint => 'Lunaway a besoin de votre position pour calculer l\'itinéraire.';
	@override String get locate => 'Me localiser';
	@override String get offlineTitle => 'Pas de connexion';
	@override String get offlineHint => 'Les itinéraires se calculent sur le serveur de Lunaway. Sans réseau, « Ouvrir dans… » confie le trajet à une application de navigation qui garde ses cartes.';
	@override String get rateLimitedTitle => 'Trop d\'itinéraires demandés';
	@override String rateLimitedHint({required Object seconds}) => 'Réessayez dans ${seconds} s.';
	@override String get unavailableTitle => 'Calcul d\'itinéraire indisponible';
	@override String get unavailableHint => 'Le service est arrêté pour le moment. Réessayez plus tard.';
	@override String get refusedTitle => 'Pas d\'itinéraire ici';
	@override String get refusedHint => 'Lunaway n\'a pas pu calculer d\'itinéraire pour cette demande : vérifiez la destination, la longueur du trajet et les valeurs du véhicule.';
	@override String get noSafeTitle => 'Aucun itinéraire sûr pour votre véhicule';
	@override String get noSafeHint => 'Chaque route possible passe par une limite que votre véhicule dépasse :';
	@override String get whatToDo => 'Ce que vous pouvez faire';
	@override String checkVehicle({required Object height, required Object weight}) => 'Vérifiez les valeurs saisies : ${height} de haut, ${weight}.';
	@override String get pickOtherPoint => 'Choisissez une arrivée avant l\'obstacle : appui long sur la carte.';
	@override String get noRouteTitle => 'Aucune route ne mène à ce point';
	@override String get noRouteHint => 'Le point est peut-être sur une voie privée, ou sur une île sans ferry.';
	@override String get allowUnpaved => 'Les voies non revêtues sont évitées : autorisez-les si l\'arrivée est sur un chemin.';
	@override String get offNetworkTitle => 'Trop loin d\'une route';
	@override String get offNetworkHint => 'Choisissez une arrivée sur une route.';
}

// Path: navigation.noRoute
class _Translations$navigation$noRoute$fr extends Translations$navigation$noRoute$en {
	_Translations$navigation$noRoute$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get originUnreachable => 'Départ impossible avec votre véhicule';
	@override String originUnreachableBy({required Object limit}) => 'Départ impossible avec votre véhicule : ${limit}';
	@override String get destinationUnreachable => 'Destination inaccessible avec votre véhicule';
	@override String destinationUnreachableBy({required Object limit}) => 'Destination inaccessible avec votre véhicule : ${limit}';
	@override String waypointUnreachable({required Object n}) => 'Étape ${n} inaccessible avec votre véhicule';
	@override String waypointUnreachableBy({required Object n, required Object limit}) => 'Étape ${n} inaccessible avec votre véhicule : ${limit}';
	@override String get blockedOnTheWay => 'Aucun passage pour votre véhicule entre les étapes';
	@override String blockedOnTheWayBy({required Object limit}) => 'Aucun passage pour votre véhicule entre les étapes : ${limit}';
	@override String get blockedHint => 'Chaque étape est accessible, mais toutes les routes qui les relient passent par une limite que votre véhicule dépasse.';
	@override String get notConnectedOrigin => 'Aucune route ne part de votre position';
	@override String get notConnectedDestination => 'Aucune route ne mène à la destination';
	@override String notConnectedWaypoint({required Object n}) => 'Aucune route ne mène à l\'étape ${n}';
	@override String get notConnectedTrip => 'Aucune route ne relie vos étapes';
	@override String get notConnectedHint => 'Quel que soit le véhicule : une île sans ferry pour les véhicules, ou une voie fermée à la circulation.';
	@override String get outsideOrigin => 'Votre position est hors de la zone des itinéraires';
	@override String get outsideDestination => 'Destination hors de la zone des itinéraires';
	@override String outsideWaypoint({required Object n}) => 'Étape ${n} hors de la zone des itinéraires';
	@override String outsideHint({required Object countries}) => 'Lunaway calcule les itinéraires dans ces pays : ${countries}.';
	@override String get outsideHintUnknown => 'Lunaway ne calcule pas encore d\'itinéraire dans ce pays.';
	@override String get noRoadOrigin => 'Votre position est trop loin d\'une route';
	@override String get noRoadDestination => 'Destination trop loin d\'une route';
	@override String noRoadWaypoint({required Object n}) => 'Étape ${n} trop loin d\'une route';
	@override String get noRoadHint => 'Aucune route que votre véhicule peut prendre à moins de 5 km de ce point.';
	@override String get tooLong => 'Trajet trop long';
	@override String tooLongHint({required Object trip, required Object max}) => '${trip} à vol d\'oiseau d\'étape en étape : Lunaway calcule les trajets de ${max} au plus.';
	@override String vehicleValue({required Object value}) => 'Votre véhicule : ${value}';
	@override late final _Translations$navigation$noRoute$limit$fr limit = _Translations$navigation$noRoute$limit$fr._(_root);
	@override String get editVehicle => 'Modifier le véhicule';
	@override String get allowUnpaved => 'Autoriser les routes non revêtues';
	@override String removeStop({required Object n}) => 'Retirer l\'étape ${n}';
	@override String removeStopNamed({required Object name}) => 'Retirer l\'étape « ${name} »';
	@override String get placesAround => 'Voir les lieux autour de la destination';
	@override String get moveDestination => 'Ou choisissez une autre arrivée : appui long sur la carte, puis « Y aller directement ».';
	@override String get moveStop => 'Pour une autre étape : touchez la carte de près, ou appui long, puis « Ajouter comme étape ».';
	@override String get moveOrigin => 'Le départ est votre position : rejoignez une route que votre véhicule peut prendre, puis réessayez.';
	@override String get pickInside => 'Choisissez une destination dans un de ces pays.';
	@override String get shorter => 'Choisissez une destination plus proche, ou faites le trajet en plusieurs fois.';
}

// Path: navigation.ferry
class _Translations$navigation$ferry$fr extends Translations$navigation$ferry$en {
	_Translations$navigation$ferry$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String title({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Traversée en ferry',
		other: '${n} traversées en ferry',
	);
	@override String get unnamed => 'Ferry';
	@override String named({required Object name}) => 'Ferry ${name}';
	@override String ports({required Object ports}) => 'Ports : ${ports}';
	@override String countries({required Object from, required Object to}) => 'Embarquement : ${from} · Débarquement : ${to}';
	@override String country({required Object country}) => 'Pays : ${country}';
	@override String where({required Object distance, required Object sea, required Object duration}) => 'À ${distance} du départ · ${sea} en mer, environ ${duration}';
	@override String get needed => 'La destination ne peut pas être atteinte sans ferry : l\'itinéraire en prend un, même si vous évitez les ferries.';
}

// Path: navigation.warning
class _Translations$navigation$warning$fr extends Translations$navigation$warning$en {
	_Translations$navigation$warning$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$warning$lowClearance$fr lowClearance = _Translations$navigation$warning$lowClearance$fr._(_root);
	@override String get unknownClearance => 'Passage bas, hauteur inconnue';
	@override String narrow({required Object limit}) => 'Passage étroit ${limit}';
	@override String tooLong({required Object limit}) => 'Longueur limitée ${limit}';
	@override String tooHeavy({required Object limit}) => 'Poids limité ${limit}';
	@override String axleLoad({required Object limit}) => 'Charge à l\'essieu limitée ${limit}';
	@override String get motorhomeBan => 'Interdit aux camping-cars';
	@override String get trailerBan => 'Interdit aux remorques';
	@override String goodsVehicleWeight({required Object limit}) => 'Poids limité pour les poids lourds ${limit}';
	@override String yours({required Object value}) => 'votre véhicule : ${value}';
	@override String fromStart({required Object distance}) => 'à ${distance} du départ';
	@override String ahead({required Object distance}) => 'dans ${distance}';
	@override String get disputed => 'les sources divergent, la valeur la plus basse s\'applique';
	@override String get goodsOnly => 'vise les poids lourds de marchandises, voyez les panneaux';
	@override String get osm => 'OpenStreetMap';
	@override String get ign => 'IGN BD TOPO';
	@override String get community => 'Signalement Lunaway';
	@override String get dialog => 'Arrêté de circulation (DiaLog)';
	@override late final _Translations$navigation$warning$localAccess$fr localAccess = _Translations$navigation$warning$localAccess$fr._(_root);
}

// Path: navigation.roadEvents
class _Translations$navigation$roadEvents$fr extends Translations$navigation$roadEvents$en {
	_Translations$navigation$roadEvents$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Travaux et fermetures';
	@override String get none => 'Pas de travaux ni de fermeture connus sur ce trajet.';
	@override String get stale => 'Travaux et fermetures : les sources n\'ont pas été lues récemment.';
	@override String avoided({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Itinéraire calculé autour d\'une fermeture : ${names}',
		other: 'Itinéraire calculé autour de ${n} fermetures : ${names}',
	);
	@override String atDistance({required Object distance}) => 'à ${distance} du départ';
	@override String more({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Et ${n} autre sur le trajet',
		other: 'Et ${n} autres sur le trajet',
	);
	@override String get classClosure => 'Route fermée';
	@override String get classWorks => 'Travaux';
	@override String get classLaneRestriction => 'Voies réduites';
	@override String get classVehicleLimit => 'Gabarit limité';
	@override String get classDetour => 'Déviation signalée';
	@override String get reasonUnmatched => 'position incertaine, peut-être sur le trajet';
	@override String get reasonStale => 'source pas lue récemment';
	@override String get reasonOutsideHours => 'hors des heures supposées';
	@override String get reasonGoodsVehicles => 'pour les poids lourds';
	@override String get reasonUnconfirmed => 'signalé par un seul voyageur';
	@override String get reasonAged => 'signalement ancien';
	@override String get reasonInside => 'le trajet commence ou finit dedans';
	@override String get reasonNearLimit => 'de justesse';
	@override String get reasonOverLimit => 'au-dessus de la limite de votre véhicule';
}

// Path: navigation.marks
class _Translations$navigation$marks$fr extends Translations$navigation$marks$en {
	_Translations$navigation$marks$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get legend => 'Légende';
	@override String get legendHide => 'Replier la légende';
	@override String get kindOrigin => 'Départ';
	@override String get kindDestination => 'Arrivée';
	@override String get kindStop => 'Étape';
	@override String get kindClosure => 'Route fermée';
	@override String get kindWorks => 'Travaux';
	@override String get kindLanes => 'Voies réduites';
	@override String get kindClearance => 'Hauteur limitée';
	@override String get kindWeight => 'Poids limité';
	@override String get kindLimit => 'Autre limite (largeur, longueur, interdiction)';
	@override String get kindFuel => 'Station-service';
	@override String get kindPlace => 'Lieu près du trajet';
	@override String get groupLegend => 'Repères proches regroupés';
	@override String get zoneLegend => 'Zone de danger';
	@override String zonesFrom({required Object source, required Object date}) => 'Zones de danger : ${source}, liste du ${date}';
	@override String group({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} repère',
		other: '${n} repères',
	);
	@override String get groupHint => 'Rapprochez-vous pour les voir un par un';
	@override String count({required Object kind, required Object n}) => '${kind} : ${n}';
	@override String stop({required Object n}) => 'Étape ${n}';
	@override String get origin => 'Point de départ';
	@override String get nearRoute => 'Près du trajet';
	@override String get avoided => 'L\'itinéraire passe à côté';
	@override String get blocking => 'Bloque chaque itinéraire';
	@override String get showInList => 'Voir dans la liste';
	@override String get showAll => 'Tout afficher';
	@override String get onMap => 'montrer sur la carte';
	@override String price({required Object price}) => '${price} €';
}

// Path: navigation.guidance
class _Translations$navigation$guidance$fr extends Translations$navigation$guidance$en {
	_Translations$navigation$guidance$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get then => 'Puis';
	@override String arrival({required Object time}) => 'Arrivée ${time}';
	@override String get offRoute => 'Hors itinéraire';
	@override String get rerouting => 'Recherche d\'un nouvel itinéraire';
	@override String get rerouted => 'Nouvel itinéraire';
	@override String reroutedLonger({required Object minutes}) => 'Nouvel itinéraire, ${minutes} min de plus';
	@override String get rerouteOffline => 'Pas de réseau pour un nouvel itinéraire : rejoignez le trajet';
	@override String get rerouteFailed => 'Aucun nouvel itinéraire : rejoignez le trajet';
	@override String closureAhead({required Object distance}) => 'Route fermée dans ${distance} : recherche d\'un autre chemin';
	@override String noDetour({required Object distance}) => 'Route fermée dans ${distance} : aucun autre chemin';
	@override String eventAhead({required Object distance}) => 'Travaux dans ${distance}';
	@override String eventClosure({required Object distance}) => 'Route fermée dans ${distance}';
	@override String eventLimit({required Object distance}) => 'Gabarit limité par des travaux dans ${distance}';
	@override String eventSource({required Object source, required Object time}) => '${source}, données de ${time}';
	@override String eventSourceOn({required Object source, required Object day, required Object time}) => '${source}, données du ${day} à ${time}';
	@override String avoidedClosures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'Itinéraire calculé autour d\'une fermeture',
		other: 'Itinéraire calculé autour de ${n} fermetures',
	);
	@override String roadEventAhead({required Object what, required Object distance}) => '${what} dans ${distance}';
	@override String closureOffline({required Object distance}) => 'Route fermée dans ${distance} : pas de réseau pour chercher un autre chemin';
	@override String closureFailed({required Object distance}) => 'Route fermée dans ${distance} : pas encore d\'autre chemin';
	@override String get voiceOn => 'Activer la voix';
	@override String get voiceOff => 'Couper la voix';
	@override String get overview => 'Tout le trajet';
	@override String get recenter => 'Recentrer';
	@override String get end => 'Terminer';
	@override String get endTitle => 'Terminer le guidage ?';
	@override String get endConfirm => 'Terminer';
	@override String get endKeep => 'Continuer';
	@override String get stopTitle => 'Arrêter le guidage ?';
	@override String get stopConfirm => 'Arrêter';
	@override String get arrivedTitle => 'Vous êtes à destination';
	@override String get done => 'Terminer';
	@override String get speed => 'Vitesse';
	@override String get limit => 'Limite';
	@override String noVoice({required Object language}) => 'Aucune voix en ${language} sur cet appareil : instructions à l\'écran seulement.';
	@override String missingVoice({required Object language}) => 'La voix en ${language} n\'est pas encore téléchargée.';
	@override String get installVoice => 'Installer';
	@override String get voiceSettingsIos => 'Réglages, Accessibilité, Contenu énoncé, Voix';
	@override String get notificationTitle => 'Lunaway vous guide';
	@override String get notificationText => 'Le guidage continue écran éteint.';
	@override String get notificationChannel => 'Guidage';
	@override String get unavailable => 'Le guidage n\'a pas pu démarrer sur cet appareil.';
	@override late final _Translations$navigation$guidance$notificationWhy$fr notificationWhy = _Translations$navigation$guidance$notificationWhy$fr._(_root);
	@override String get positionLost => 'Position indisponible : vérifiez que la localisation de l\'appareil est activée pour Lunaway.';
	@override String positionStale({required Object minutes}) => 'Dernière position reçue il y a ${minutes} min : l\'heure d\'arrivée en dépend.';
	@override String get firstTitle => 'Avant de partir';
	@override String get firstAccept => 'J\'ai compris';
	@override String dangerZone({required Object distance}) => 'Zone de danger dans ${distance}';
	@override String inDangerZone({required Object distance}) => 'Zone de danger, encore ${distance}';
	@override String cameraAhead({required Object distance}) => 'Radar dans ${distance}';
	@override String cameraLimit({required Object distance, required Object limit}) => 'Radar dans ${distance}, ${limit}';
	@override String get limitEstimated => 'Limite estimée';
	@override String get overLimit => 'au-dessus de la limite';
	@override String enforcementSource({required Object source, required Object date}) => '${source}, liste du ${date}';
	@override String get demoDrive => 'Trajet simulé : démonstration sans GPS';
	@override late final _Translations$navigation$guidance$places$fr places = _Translations$navigation$guidance$places$fr._(_root);
}

// Path: navigation.voice
class _Translations$navigation$voice$fr extends Translations$navigation$voice$en {
	_Translations$navigation$voice$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get rerouting => 'Recalcul de l\'itinéraire.';
	@override String get rerouted => 'Nouvel itinéraire.';
	@override String reroutedLonger({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(minutes,
		one: 'Nouvel itinéraire, une minute de plus.',
		other: 'Nouvel itinéraire, ${minutes} minutes de plus.',
	);
	@override late final _Translations$navigation$voice$moved$fr moved = _Translations$navigation$voice$moved$fr._(_root);
	@override String closureAhead({required Object distance}) => 'Route fermée dans ${distance}. Recherche d\'un autre chemin.';
	@override String noDetour({required Object distance}) => 'Route fermée dans ${distance}. Il n\'y a pas d\'autre chemin.';
	@override String clearance({required Object height, required Object distance}) => 'Attention, passage bas de ${height} dans ${distance}.';
	@override String unknownClearance({required Object distance}) => 'Attention, passage bas de hauteur inconnue dans ${distance}.';
	@override String narrow({required Object width, required Object distance}) => 'Attention, passage étroit de ${width} dans ${distance}.';
	@override String limit({required Object what, required Object distance}) => 'Attention, ${what} dans ${distance}.';
	@override String get arrived => 'Vous êtes à destination.';
	@override String metres({required Object n}) => '${n} mètres';
	@override String kilometres({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count,
		one: '${n} kilomètre',
		other: '${n} kilomètres',
	);
	@override String feet({required Object n}) => '${n} pieds';
	@override String miles({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count,
		one: '${n} mile',
		other: '${n} miles',
	);
	@override String size({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count,
		one: '${metres} mètre ${cm}',
		other: '${metres} mètres ${cm}',
	);
	@override String sizeWhole({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count,
		one: '${metres} mètre',
		other: '${metres} mètres',
	);
	@override String overSpeed({required Object limit}) => 'Vitesse limitée à ${limit}.';
	@override String dangerZone({required Object distance}) => 'Zone de danger dans ${distance}.';
	@override String get inDangerZone => 'Zone de danger.';
	@override String camera({required Object distance}) => 'Radar dans ${distance}.';
	@override late final _Translations$navigation$voice$localAccess$fr localAccess = _Translations$navigation$voice$localAccess$fr._(_root);
	@override String tonnes({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count,
		one: '${n} tonne',
		other: '${n} tonnes',
	);
}

// Path: navigation.units
class _Translations$navigation$units$fr extends Translations$navigation$units$en {
	_Translations$navigation$units$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String ft({required Object n}) => '${n} ft';
	@override String mi({required Object n}) => '${n} mi';
	@override String get kmh => 'km/h';
	@override String get mph => 'mph';
	@override String hoursMinutes({required Object h, required Object m}) => '${h} h ${m}';
	@override String minutes({required Object m}) => '${m} min';
}

// Path: navigation.settings
class _Translations$navigation$settings$fr extends Translations$navigation$settings$en {
	_Translations$navigation$settings$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Guidage';
	@override String get avoidTitle => 'Éviter par défaut';
	@override String get voice => 'Instructions vocales';
	@override String get voiceHint => 'Avec la voix de l\'appareil';
	@override String get units => 'Distances';
	@override String get metric => 'Kilomètres';
	@override String get imperial => 'Miles';
	@override String get speedLimit => 'Limite de vitesse';
	@override String get speedLimitHint => 'La limite pour votre véhicule à côté de la vitesse pendant le guidage ; une estimation s\'affiche en gris.';
	@override String get speedSound => 'Alertes de vitesse parlées';
	@override String get speedSoundHint => 'Un mot quand vous dépassez la limite, et avant une zone de danger là où le pays les autorise. Coupé : le panneau et les bandeaux seuls.';
}

// Path: vehicle.types
class _Translations$vehicle$types$fr extends Translations$vehicle$types$en {
	_Translations$vehicle$types$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Fourgon aménagé';
	@override String get lowProfile => 'Profilé';
	@override String get overcab => 'Capucine';
	@override String get integrated => 'Intégral';
}

// Path: vehicle.towing
class _Translations$vehicle$towing$fr extends Translations$vehicle$towing$en {
	_Translations$vehicle$towing$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get none => 'Rien';
	@override String get car => 'Une voiture';
	@override String get trailer => 'Une remorque';
}

// Path: translation.from
class _Translations$translation$from$fr extends Translations$translation$from$en {
	_Translations$translation$from$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Traduit automatiquement du français';
	@override String get en => 'Traduit automatiquement de l\'anglais';
	@override String get de => 'Traduit automatiquement de l\'allemand';
	@override String get es => 'Traduit automatiquement de l\'espagnol';
	@override String get it => 'Traduit automatiquement de l\'italien';
	@override String get nl => 'Traduit automatiquement du néerlandais';
	@override String unknown({required Object language}) => 'Traduit automatiquement (langue d\'origine : ${language})';
}

// Path: account.levelOpens
class _Translations$account$levelOpens$fr extends Translations$account$levelOpens$en {
	_Translations$account$levelOpens$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get l0 => 'Vous pouvez noter les lieux, confirmer qu\'ils sont toujours là, signaler un problème et synchroniser vos favoris.';
	@override String get l1 => 'Vous pouvez aussi écrire des avis, ajouter des photos et proposer des modifications de lieux.';
	@override String get l2 => 'Vous pouvez aussi ajouter des lieux.';
	@override String get l3 => 'Vos modifications de lieux s\'appliquent sans relecture.';
	@override String get l4 => 'Vous participez à la modération.';
}

// Path: account.requirement
class _Translations$account$requirement$fr extends Translations$account$requirement$en {
	_Translations$account$requirement$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String age({required Object needed, required Object current}) => 'Un compte d\'au moins ${needed} jours (${current} pour l\'instant)';
	@override String confirmations({required Object needed, required Object current}) => '${needed} confirmations de lieux différents (${current} pour l\'instant)';
	@override String contributions({required Object needed, required Object current}) => '${needed} contributions publiées (${current} pour l\'instant)';
	@override String activeDays({required Object needed, required Object current}) => '${needed} jours d\'activité (${current} pour l\'instant)';
	@override String get noRemoval => 'Aucune contribution retirée par la modération';
	@override String get sponsor => 'Le parrainage d\'un membre de niveau 2';
	@override String get nomination => 'Une nomination par la modération';
	@override String get administration => 'Une désignation par l\'équipe de Lunaway';
}

// Path: deletion.gone
class _Translations$deletion$gone$fr extends Translations$deletion$gone$en {
	_Translations$deletion$gone$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get identity => 'Votre pseudonyme et les clés de vos appareils';
	@override String get sessions => 'Vos sessions et votre code de secours';
	@override String get lists => 'Vos listes de favoris synchronisées et vos auteurs masqués';
	@override String get photos => 'Vos photos, vos notes sans texte et vos signalements';
	@override String get pending => 'Vos propositions en attente de relecture';
}

// Path: mine.status
class _Translations$mine$status$fr extends Translations$mine$status$en {
	_Translations$mine$status$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get published => 'Publié';
	@override String get pending => 'En relecture';
	@override String get hidden => 'Masqué après des signalements';
	@override String get removed => 'Retiré par la modération';
}

// Path: mine.submission
class _Translations$mine$submission$fr extends Translations$mine$submission$en {
	_Translations$mine$submission$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get proposed => 'En attente de relecture';
	@override String get accepted => 'Accepté';
	@override String get applied => 'Sur la carte';
	@override String get rejected => 'Refusé';
	@override String get withdrawn => 'Retiré';
}

// Path: outbox.kind
class _Translations$outbox$kind$fr extends Translations$outbox$kind$en {
	_Translations$outbox$kind$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String rate({required Object stars}) => 'Note de ${stars} sur 5';
	@override String get review => 'Avis';
	@override String get deleteReview => 'Suppression d\'un avis';
	@override String confirm({required Object status}) => 'Toujours là ? ${status}';
	@override String get deleteConfirmation => 'Suppression d\'une confirmation';
	@override String reportIssue({required Object kind}) => 'Problème signalé : ${kind}';
	@override String get deleteIssueReport => 'Suppression d\'un signalement';
	@override String get reportContent => 'Signalement à la modération';
	@override String addPlace({required Object name}) => 'Nouveau lieu : ${name}';
	@override String get editPlace => 'Modification d\'un lieu';
	@override String get deletePlaceSubmission => 'Retrait d\'un lieu proposé';
	@override String get photo => 'Photo';
	@override String get deletePhoto => 'Suppression d\'une photo';
	@override String get mute => 'Masquer un auteur';
	@override String get unmute => 'Ne plus masquer un auteur';
	@override String get poiThere => 'Toujours là : un commerce ou service';
	@override String get poiGone => 'Plus là : un commerce ou service';
	@override String get addVendingMachine => 'Nouveau distributeur';
	@override String get deletePoiConfirmation => 'Suppression d\'une réponse sur un commerce ou service';
	@override String reportRoadEvent({required Object kind}) => 'Signalement sur la route : ${kind}';
	@override String get clearRoadEvent => 'Fin d\'un signalement sur la route';
}

// Path: outbox.error
class _Translations$outbox$error$fr extends Translations$outbox$error$en {
	_Translations$outbox$error$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get forbidden => 'Refusé : votre niveau ne le permet pas encore.';
	@override String get notFound => 'Refusé : le lieu ou le contenu n\'existe plus.';
	@override String get invalid => 'Refusé : vérifiez le texte (longueur, liens, coordonnées).';
	@override String get unreadablePhoto => 'Photo refusée : illisible, ou déjà envoyée.';
	@override String get photoTooLarge => 'Photo refusée : trop lourde.';
	@override String get placeRefused => 'Le nouveau lieu de cette photo a été refusé.';
	@override String get fileLost => 'La photo n\'est plus sur l\'appareil.';
	@override String get otherAccount => 'Préparée pour un autre compte : elle ne sera pas envoyée.';
	@override String get other => 'Refusé par le serveur.';
	@override String get duplicate => 'Refusé : le même distributeur est déjà indiqué à moins de 25 m.';
}

// Path: confirmSheet.status
class _Translations$confirmSheet$status$fr extends Translations$confirmSheet$status$en {
	_Translations$confirmSheet$status$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get stillOk => 'toujours là';
	@override String get closed => 'fermé';
	@override String get changed => 'changé';
}

// Path: issueSheet.kind
class _Translations$issueSheet$kind$fr extends Translations$issueSheet$kind$en {
	_Translations$issueSheet$kind$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Nuit interdite désormais';
	@override String get serviceBroken => 'Service en panne';
	@override String get noAccess => 'Accès impossible';
	@override String get danger => 'Danger';
}

// Path: issueSheet.hint
class _Translations$issueSheet$hint$fr extends Translations$issueSheet$hint$en {
	_Translations$issueSheet$hint$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Panneau, arrêté municipal, passage de la police';
	@override String get serviceBroken => 'Borne, eau, vidange ou électricité hors service';
	@override String get noAccess => 'Barrière, travaux, route fermée';
	@override String get danger => 'Vol, agression, terrain instable';
}

// Path: reportSheet.reason
class _Translations$reportSheet$reason$fr extends Translations$reportSheet$reason$en {
	_Translations$reportSheet$reason$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get spam => 'Publicité ou répétition';
	@override String get offensive => 'Insultant, haineux ou choquant';
	@override String get wrong => 'Faux ou trompeur';
	@override String get privacy => 'Montre ou nomme une personne, une plaque, une adresse privée';
	@override String get other => 'Autre raison';
}

// Path: poi.category
class _Translations$poi$category$fr extends Translations$poi$category$en {
	_Translations$poi$category$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get groceries => 'Courses';
	@override String get vending => 'Distributeurs alimentaires';
	@override String get water => 'Eau et vidange';
	@override String get fuel => 'Carburant et énergie';
	@override String get health => 'Santé';
	@override String get services => 'Services';
}

// Path: poi.kind
class _Translations$poi$kind$fr extends Translations$poi$kind$en {
	_Translations$poi$kind$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get supermarket => 'Supermarché';
	@override String get convenience => 'Supérette';
	@override String get bakery => 'Boulangerie';
	@override String get butcher => 'Boucherie';
	@override String get greengrocer => 'Primeur';
	@override String get farmShop => 'Vente à la ferme';
	@override String get marketplace => 'Marché';
	@override String get vendingPizza => 'Distributeur de pizzas';
	@override String get vendingBread => 'Distributeur de pain';
	@override String get vendingFarmProducts => 'Distributeur de produits fermiers';
	@override String get vendingEggsMilk => 'Distributeur d\'œufs ou de lait';
	@override String get vendingIce => 'Distributeur de glaçons';
	@override String get vendingOther => 'Distributeur alimentaire';
	@override String get drinkingWater => 'Eau potable';
	@override String get waterPoint => 'Point d\'eau';
	@override String get dumpStation => 'Borne de vidange';
	@override String get toilets => 'Toilettes';
	@override String get shower => 'Douches';
	@override String get fuelStation => 'Station-service';
	@override String get evCharging => 'Borne de recharge';
	@override String get gasBottles => 'Bouteilles de gaz';
	@override String get pharmacy => 'Pharmacie';
	@override String get doctor => 'Médecin';
	@override String get hospital => 'Hôpital';
	@override String get veterinary => 'Vétérinaire';
	@override String get laundry => 'Laverie';
	@override String get atm => 'Distributeur de billets';
	@override String get postOffice => 'Bureau de poste';
	@override String get touristOffice => 'Office de tourisme';
	@override String get recyclingCentre => 'Déchèterie';
	@override String get carRepair => 'Garage';
	@override String get carWash => 'Lavage';
	@override String get motorhomeShop => 'Concession et atelier camping-car';
}

// Path: poi.vendingSells
class _Translations$poi$vendingSells$fr extends Translations$poi$vendingSells$en {
	_Translations$poi$vendingSells$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Pain';
	@override String get farmProducts => 'Produits de la ferme';
	@override String get eggsMilk => 'Œufs et lait';
	@override String get ice => 'Glaçons';
}

// Path: poi.vendingChip
class _Translations$poi$vendingChip$fr extends Translations$poi$vendingChip$en {
	_Translations$poi$vendingChip$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Distributeurs de pizza';
	@override String get bread => 'Distributeurs de pain';
	@override String get farmProducts => 'Distributeurs de produits de la ferme';
	@override String get eggsMilk => 'Distributeurs d\'œufs et de lait';
	@override String get ice => 'Distributeurs de glaçons';
}

// Path: poi.fuel
class _Translations$poi$fuel$fr extends Translations$poi$fuel$en {
	_Translations$poi$fuel$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get diesel => 'Gazole';
	@override String get sp95 => 'SP95';
	@override String get e10 => 'SP95-E10';
	@override String get sp98 => 'SP98';
	@override String get e85 => 'E85';
	@override String get lpg => 'GPL';
}

// Path: poi.product
class _Translations$poi$product$fr extends Translations$poi$product$en {
	_Translations$poi$product$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizzas';
	@override String get bread => 'Pain';
	@override String get eggs => 'Œufs';
	@override String get milk => 'Lait';
	@override String get cheese => 'Fromage';
	@override String get meat => 'Viande';
	@override String get vegetables => 'Légumes';
	@override String get fruit => 'Fruits';
	@override String get honey => 'Miel';
	@override String get ice => 'Glaçons';
	@override String get potatoes => 'Pommes de terre';
	@override String get food => 'Alimentation';
}

// Path: poi.payment
class _Translations$poi$payment$fr extends Translations$poi$payment$en {
	_Translations$poi$payment$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get cash => 'Espèces';
	@override String get coins => 'Pièces';
	@override String get notes => 'Billets';
	@override String get cards => 'Carte';
	@override String get contactless => 'Sans contact';
	@override String get app => 'Application';
}

// Path: poi.add
class _Translations$poi$add$fr extends Translations$poi$add$en {
	_Translations$poi$add$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Un distributeur ici ?';
	@override String get hint => 'Choisissez ce qu\'il vend : il s\'ajoute à la carte de tous les voyageurs.';
	@override String get pizza => 'Pizzas';
	@override String get bread => 'Pain';
	@override String get other => 'Autre';
	@override String get gate => 'Ajouter un distributeur';
	@override String get sent => 'Merci : le distributeur apparaît sur la carte d\'ici quelques minutes.';
	@override String get duplicateTitle => 'Déjà sur la carte';
	@override String get duplicateBody => 'Un distributeur du même type est déjà indiqué à moins de 25 m. Est-il toujours là ?';
	@override String get duplicateThere => 'Oui, toujours là';
	@override String get duplicateGone => 'Non, il n\'y est plus';
}

// Path: poi.cheapest
class _Translations$poi$cheapest$fr extends Translations$poi$cheapest$en {
	_Translations$poi$cheapest$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Moins cher autour de moi';
	@override String get show => 'Moins cher autour';
	@override String get zoomIn => 'Zoomez pour comparer les prix des stations.';
	@override String get none => 'Aucune station de la carte ne vend ce carburant.';
	@override String get noneHint => 'Déplacez la carte ou choisissez un autre carburant.';
	@override String get error => 'Les prix des stations n\'ont pas pu s\'afficher.';
}

// Path: poi.trend
class _Translations$poi$trend$fr extends Translations$poi$trend$en {
	_Translations$poi$trend$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String title({required Object fuel}) => '${fuel} : prix des derniers jours';
	@override String get none => 'Lunaway n\'a pas encore vu de prix de ce carburant ici.';
	@override String get failed => 'Les prix des derniers jours n\'ont pas pu être lus pour l\'instant.';
	@override String get week => '7 derniers jours :';
	@override String get month => '30 derniers jours :';
	@override String range({required Object low, required Object high}) => 'de ${low} à ${high}';
	@override String span({required Object range, required Object move}) => '${range}, ${move}';
	@override String get oneDay => 'un seul jour relevé';
	@override String get steady => 'stable';
	@override String down({required Object amount}) => 'en baisse de ${amount}';
	@override String up({required Object amount}) => 'en hausse de ${amount}';
	@override String since({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} jour relevé depuis le ${date}, tel que Lunaway lit le flux ; un jour sans relevé reste vide',
		other: '${n} jours relevés depuis le ${date}, tel que Lunaway lit le flux ; un jour sans relevé reste vide',
	);
}

// Path: roadReport.kinds
class _Translations$roadReport$kinds$fr extends Translations$roadReport$kinds$en {
	_Translations$roadReport$kinds$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get closure => 'Route fermée';
	@override String get works => 'Travaux';
	@override String get narrowPassage => 'Passage étroit';
	@override String get lowClearance => 'Hauteur limitée';
	@override String get other => 'Problème sur la route';
}

// Path: navigation.preview.departure
class _Translations$navigation$preview$departure$fr extends Translations$navigation$preview$departure$en {
	_Translations$navigation$preview$departure$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Départ';
	@override String from({required Object name}) => 'Départ : ${name}';
	@override String get myPosition => 'ma position';
	@override String get myPositionChoice => 'Ma position';
	@override String get change => 'Changer';
	@override String get choose => 'Choisir un départ';
	@override String get searchHint => 'Un lieu, une commune, une adresse';
	@override String get guidanceFromPosition => 'Le guidage part de votre position, pas d\'un départ choisi.';
	@override String get fromMyPosition => 'Partir de ma position';
}

// Path: navigation.preview.moved
class _Translations$navigation$preview$moved$fr extends Translations$navigation$preview$moved$en {
	_Translations$navigation$preview$moved$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String origin({required Object distance}) => 'Point de départ déplacé de ${distance} vers la rue accessible la plus proche';
	@override String destination({required Object distance}) => 'Point d\'arrivée déplacé de ${distance} vers la rue accessible la plus proche';
	@override String stop({required Object n, required Object distance}) => 'Étape ${n} déplacée de ${distance} vers la rue accessible la plus proche';
}

// Path: navigation.onTheWay.categories
class _Translations$navigation$onTheWay$categories$fr extends Translations$navigation$onTheWay$categories$en {
	_Translations$navigation$onTheWay$categories$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get fuel => 'Carburant';
	@override String get sleep => 'Dormir';
	@override String get water => 'Eau et vidange';
	@override String get groceries => 'Courses';
	@override String get bakeries => 'Boulangeries';
	@override String get toilets => 'Toilettes, douches';
	@override String get health => 'Santé';
	@override String get services => 'Services';
	@override String get charging => 'Recharge';
	@override String get garages => 'Garages';
}

// Path: navigation.states.dimension
class _Translations$navigation$states$dimension$fr extends Translations$navigation$states$dimension$en {
	_Translations$navigation$states$dimension$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get height => 'hauteur';
	@override String get width => 'largeur';
	@override String get length => 'longueur';
	@override String get weight => 'poids';
}

// Path: navigation.noRoute.limit
class _Translations$navigation$noRoute$limit$fr extends Translations$navigation$noRoute$limit$en {
	_Translations$navigation$noRoute$limit$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'pont bas à ${limit}';
	@override String tunnel({required Object limit}) => 'tunnel à ${limit}';
	@override String buildingPassage({required Object limit}) => 'porche à ${limit}';
	@override String bridge({required Object limit}) => 'pont à ${limit}';
	@override String barrier({required Object limit}) => 'barre de hauteur à ${limit}';
	@override String height({required Object limit}) => 'hauteur limitée à ${limit}';
	@override String get heightUnknown => 'hauteur limitée';
	@override String width({required Object limit}) => 'passage étroit de ${limit}';
	@override String get widthUnknown => 'passage étroit';
	@override String length({required Object limit}) => 'longueur limitée à ${limit}';
	@override String get lengthUnknown => 'longueur limitée';
	@override String weight({required Object limit}) => 'poids limité à ${limit}';
	@override String get weightUnknown => 'poids limité';
	@override String get unpaved => 'route non revêtue';
	@override String weightLocalAccess({required Object limit}) => 'poids limité à ${limit} sauf desserte';
	@override String widthLocalAccess({required Object limit}) => 'passage étroit de ${limit} sauf desserte';
	@override String lengthLocalAccess({required Object limit}) => 'longueur limitée à ${limit} sauf desserte';
}

// Path: navigation.warning.lowClearance
class _Translations$navigation$warning$lowClearance$fr extends Translations$navigation$warning$lowClearance$en {
	_Translations$navigation$warning$lowClearance$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'Pont bas ${limit}';
	@override String tunnel({required Object limit}) => 'Tunnel ${limit}';
	@override String buildingPassage({required Object limit}) => 'Porche ${limit}';
	@override String bridge({required Object limit}) => 'Pont ${limit}';
	@override String barrier({required Object limit}) => 'Barre de hauteur ${limit}';
	@override String road({required Object limit}) => 'Hauteur limitée ${limit}';
}

// Path: navigation.warning.localAccess
class _Translations$navigation$warning$localAccess$fr extends Translations$navigation$warning$localAccess$en {
	_Translations$navigation$warning$localAccess$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String weight({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} sauf pour rejoindre votre destination';
	@override String axleLoad({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} par essieu sauf pour rejoindre votre destination';
	@override String width({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} de large sauf pour rejoindre votre destination';
	@override String length({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} de long sauf pour rejoindre votre destination';
}

// Path: navigation.guidance.notificationWhy
class _Translations$navigation$guidance$notificationWhy$fr extends Translations$navigation$guidance$notificationWhy$en {
	_Translations$navigation$guidance$notificationWhy$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notification du guidage';
	@override String get body => 'Pendant le guidage, une notification garde la position et la voix actives écran éteint, et la toucher ramène au guidage. Android va demander si Lunaway peut l\'afficher.';
	@override String get ask => 'Continuer';
	@override String get later => 'Pas maintenant';
}

// Path: navigation.guidance.places
class _Translations$navigation$guidance$places$fr extends Translations$navigation$guidance$places$en {
	_Translations$navigation$guidance$places$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get button => 'Lieux sur la carte';
	@override String get buttonHidden => 'Lieux sur la carte : masqués';
	@override String get title => 'Lieux sur la carte';
	@override String get sleep => 'Pour dormir';
	@override String get fill => 'Pour le plein';
	@override String get groceries => 'Courses';
	@override String get all => 'Tout';
	@override String get none => 'Rien';
	@override String get customize => 'Personnaliser';
	@override String get look => 'Affichage';
	@override String get photos => 'Photos';
	@override String get pictograms => 'Pictogrammes';
	@override String get dots => 'Points discrets';
	@override String get photosHint => 'Les lieux qui comptent le plus, en photo. Jamais sur la route devant vous ni sous les boutons.';
	@override String get pictogramsHint => 'Les lieux qui comptent le plus, en grand, avec leur prix, leur note ou la nuit.';
	@override String get dotsHint => 'Tous les lieux en petites épingles, comme sur la carte.';
	@override String get free => 'Gratuit';
	@override String get nightOk => 'Nuit OK';
}

// Path: navigation.voice.moved
class _Translations$navigation$voice$moved$fr extends Translations$navigation$voice$moved$en {
	_Translations$navigation$voice$moved$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String destination({required Object distance}) => 'Point d\'arrivée déplacé de ${distance} vers la rue accessible la plus proche.';
	@override String stop({required Object n, required Object distance}) => 'Étape ${n} déplacée de ${distance} vers la rue accessible la plus proche.';
}

// Path: navigation.voice.localAccess
class _Translations$navigation$voice$localAccess$fr extends Translations$navigation$voice$localAccess$en {
	_Translations$navigation$voice$localAccess$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String weight({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} seulement pour la desserte.';
	@override String axleLoad({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} par essieu seulement pour la desserte.';
	@override String width({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} de large seulement pour la desserte.';
	@override String length({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} de long seulement pour la desserte.';
}

/// The flat map containing all translations for locale <fr>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsFr {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Carte',
			'nav.favorites' => 'Favoris',
			'nav.profile' => 'Profil',
			'nav.fold' => 'Réduire le menu',
			'nav.unfold' => 'Afficher le menu en entier',
			'common.close' => 'Fermer',
			'common.done' => 'Terminé',
			'common.cancel' => 'Annuler',
			'common.retry' => 'Réessayer',
			'common.save' => 'Enregistrer',
			'common.delete' => 'Supprimer',
			'common.undo' => 'Annuler',
			'common.ok' => 'Compris',
			'common.saveFailed' => 'La modification n\'a pas pu être enregistrée.',
			'common.send' => 'Envoyer',
			'common.later' => 'Plus tard',
			'common.next' => 'Continuer',
			'common.failed' => 'L\'opération n\'a pas abouti. Réessayez dans un moment.',
			'common.offline' => 'Pas de réseau pour l\'instant. Réessayez quand il reviendra.',
			'kinds.motorhomeArea' => 'Aire de camping-car',
			'kinds.serviceArea' => 'Aire de services',
			'kinds.campsite' => 'Camping',
			'kinds.parking' => 'Parking',
			'kinds.nature' => 'Lieu en pleine nature',
			'kinds.restArea' => 'Aire de repos',
			'kinds.picnicArea' => 'Aire de pique-nique',
			'kinds.farm' => 'Accueil à la ferme',
			'kinds.homestay' => 'Accueil chez un particulier',
			'kinds.offRoad' => 'Lieu tout-terrain',
			'kinds.extraService' => 'Arrêt pratique',
			'families.stopovers' => 'Aires et parkings',
			'families.stopoversHint' => 'Aires de camping-car, parkings, aires de repos',
			'families.campsites' => 'Campings et accueils',
			'families.campsitesHint' => 'Campings, fermes, particuliers',
			'families.nature' => 'Nature',
			'families.natureHint' => 'Lieux en pleine nature, pistes',
			'families.services' => 'Services',
			'families.servicesHint' => 'Eau et vidange, pas de nuit sur place',
			'services.drinkingWater' => 'Eau potable',
			'services.greyWater' => 'Vidange eaux grises',
			'services.blackWater' => 'Vidange cassette',
			'services.wasteBin' => 'Poubelles',
			'services.toilets' => 'Toilettes',
			'services.showers' => 'Douches',
			'services.electricity' => 'Électricité',
			'services.wifi' => 'Wi-Fi',
			'services.laundry' => 'Laverie',
			'services.lpg' => 'GPL',
			'services.gasBottles' => 'Bouteilles de gaz',
			'services.vehicleWash' => 'Lavage du véhicule',
			'services.bakery' => 'Boulangerie',
			'services.swimmingPool' => 'Piscine',
			'services.petsAllowed' => 'Animaux acceptés',
			'services.mobileData' => 'Réseau mobile',
			'services.winterCaravanning' => 'Ouvert en hiver',
			'activities.monuments' => 'Visites',
			'activities.windsurfKitesurf' => 'Planche à voile, kitesurf',
			'activities.mountainBiking' => 'VTT',
			'activities.hiking' => 'Randonnée',
			'activities.climbing' => 'Escalade',
			'activities.canoeKayak' => 'Canoë, kayak',
			'activities.fishing' => 'Pêche',
			'activities.shoreFishing' => 'Pêche à pied',
			'activities.swimming' => 'Baignade',
			'activities.motorcycling' => 'Balades à moto',
			'activities.viewpoint' => 'Point de vue',
			'activities.playground' => 'Jeux pour enfants',
			'amenities.water' => 'Eau',
			'amenities.dumpStation' => 'Vidange',
			'amenities.electricity' => 'Électricité',
			'amenities.toilets' => 'Toilettes',
			'amenities.showers' => 'Douches',
			'amenities.wasteBin' => 'Poubelles',
			'amenities.laundry' => 'Laverie',
			'amenities.wifi' => 'Wi-Fi',
			'amenities.lpg' => 'GPL',
			'overnight.allowed' => 'Nuit autorisée',
			'overnight.tolerated' => 'Nuit tolérée',
			'overnight.dayOnly' => 'De jour seulement',
			'overnight.forbidden' => 'Nuit interdite',
			'overnight.unknown' => 'Nuit non renseignée',
			'overnight.allowedHint' => 'Vous pouvez passer la nuit ici.',
			'overnight.toleratedHint' => 'Une nuit est en général acceptée. Discrétion de rigueur, ne laissez aucune trace.',
			'overnight.dayOnlyHint' => 'Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.',
			'overnight.forbiddenHint' => 'Passer la nuit ici est interdit.',
			'overnight.unknownHint' => 'Personne ne l\'a encore indiqué. Renseignez-vous sur place.',
			'freshness.confirmed' => ({required Object when}) => 'Confirmé par un voyageur ${when}',
			'freshness.unconfirmed' => 'Pas encore confirmé par un voyageur',
			'freshness.stale' => 'Dernière confirmation il y a plus d\'un an',
			'freshness.today' => 'aujourd\'hui',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'hier', other: 'il y a ${n} jours', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a un mois', other: 'il y a ${n} mois', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a un an', other: 'il y a ${n} ans', ), 
			'map.searchHint' => 'Un lieu, une commune',
			'map.clearSearch' => 'Effacer la recherche',
			'map.locateMe' => 'Afficher ma position',
			'map.aroundMe' => 'Voir autour de moi',
			'map.zoomIn' => 'Zoomer',
			'map.zoomOut' => 'Dézoomer',
			'map.filters' => 'Filtres',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Crédits de la carte : © les contributeurs d\'OpenStreetMap, style Protomaps. Ouvre la page des droits d\'OpenStreetMap.',
			'map.showList' => 'Liste',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Liste (${n})', other: 'Liste (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu ici', other: 'lieux ici', ), 
			'map.nearestYouLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu le plus proche de vous', other: 'lieux les plus proches de vous', ), 
			'map.nearestCentreLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu le plus proche du centre', other: 'lieux les plus proches du centre', ), 
			'map.pointTitle' => 'Ici',
			'map.pointHint' => 'Point sur la carte',
			'map.directionsHere' => 'Itinéraire jusqu\'ici',
			'map.startHere' => 'Partir d\'ici',
			'map.departureChosen' => 'Départ choisi : ouvrez maintenant la destination et son itinéraire.',
			'map.copyCoordinates' => 'Copier les coordonnées',
			'map.freeTapHint' => 'Touchez la carte pour y aller ou y ajouter un lieu',
			'map.freeTapHintClick' => 'Cliquez sur la carte pour y aller ou y ajouter un lieu',
			'map.addPlaceAtCenter' => 'Ajouter un lieu au centre de la carte',
			'map.addressSource' => ({required Object attribution}) => 'Source : ${attribution}',
			'map.placesAround' => 'Les lieux autour',
			'map.downloading' => 'Téléchargement des lieux de France',
			'map.downloadingCount' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${count} lieu reçu', other: '${count} lieux reçus', ), 
			'map.noData' => 'Aucun lieu sur cet appareil pour l\'instant',
			'map.noDataHint' => 'Téléchargez les lieux une fois : la carte fonctionne ensuite sans réseau.',
			'map.download' => 'Télécharger les lieux',
			'map.downloadFailed' => 'Le téléchargement s\'est interrompu',
			'map.demoBanner' => 'Démo : lieux inventés',
			'map.unsupported' => 'La carte n\'est pas disponible sur ce système. Utilisez l\'application web.',
			'sync.failedOffline' => 'Pas de connexion pour l\'instant.',
			'sync.failedBusy' => 'Le serveur est très demandé.',
			'sync.failedServer' => 'Le serveur a un problème pour l\'instant.',
			'sync.failedOther' => 'La mise à jour n\'a pas abouti.',
			'sync.failedRefused' => 'Le serveur a refusé la mise à jour. Une nouvelle version de l\'application est peut-être nécessaire.',
			'sync.willRetry' => 'Lunaway réessaiera tout seul.',
			'sync.incomplete' => ({required Object count}) => 'Téléchargement incomplet : ${count} lieux pour l\'instant',
			'sync.incompleteShort' => 'Téléchargement incomplet',
			'sync.resuming' => ({required Object count}) => 'Téléchargement en cours : ${count} lieux',
			'sync.resume' => 'Reprendre',
			'location.rationaleTitle' => 'Afficher votre position ?',
			'location.rationale' => 'Lunaway s\'en sert pour centrer la carte sur vous, trier les lieux par distance et vous guider. Pour un itinéraire, votre position est envoyée au serveur de Lunaway, qui ne la conserve pas. Pour le carburant le moins cher autour de vous, seule une position arrondie à environ 5 km est envoyée. Un signalement sur la route part avec l\'endroit où vous le faites.',
			'location.allow' => 'Continuer',
			'location.notNow' => 'Pas maintenant',
			'location.deniedTitle' => 'Position désactivée pour Lunaway',
			'location.denied' => 'Vous avez refusé l\'accès à la position. Pour l\'utiliser, autorisez-le dans les réglages de l\'appareil.',
			'location.openSettings' => 'Ouvrir les réglages',
			'location.serviceOffTitle' => 'Localisation désactivée',
			'location.serviceOff' => 'La localisation de l\'appareil est désactivée. Activez-la dans les réglages rapides, puis réessayez.',
			'location.notAllowed' => 'Position non autorisée. La carte fonctionne sans elle.',
			'location.noFix' => 'Position introuvable pour l\'instant. Réessayez à découvert ou dans un moment.',
			'location.unsupported' => 'Cet appareil ne donne pas sa position.',
			'location.browserDeniedTitle' => 'Position bloquée par le navigateur',
			'location.browserDenied' => 'Le navigateur refuse votre position à Lunaway. Pour l\'autoriser, cliquez sur l\'icône à gauche de l\'adresse du site (un cadenas ou des curseurs), mettez Position sur Autoriser, puis cliquez de nouveau sur le bouton de position.',
			'location.browserNoFix' => 'Le navigateur n\'a pas donné de position. Réessayez dans un moment ; sur un ordinateur, le Wi-Fi aide à la trouver.',
			'search.towns' => 'Communes',
			'search.places' => 'Lieux',
			'search.noResult' => ({required Object query}) => 'Aucun lieu ni aucune commune ne correspond à « ${query} ».',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} lieu', other: '${n} lieux', ), 
			'search.addresses' => 'Adresses',
			'search.addressesSearching' => 'Recherche des adresses',
			'search.addressesFailed' => 'Les adresses n\'ont pas pu être cherchées pour l\'instant.',
			'search.addressSources' => ({required Object sources}) => 'Adresses : ${sources}',
			'search.offline' => 'Pas de connexion : la recherche a besoin du réseau.',
			'search.addressKind.houseNumber' => 'Adresse',
			'search.addressKind.street' => 'Rue',
			'search.addressKind.locality' => 'Lieu-dit',
			'search.addressKind.town' => 'Commune',
			'search.addressKind.postcode' => 'Code postal',
			'search.addressKind.region' => 'Région',
			'filters.title' => 'Filtres',
			'filters.families' => 'Type de lieu',
			'filters.familiesHint' => 'Aucun choix : tous les types',
			'filters.familiesChosenHint' => 'Seulement ces types',
			'filters.night' => 'Nuit sur place',
			'filters.nightHint' => 'Aucun choix : tous les lieux',
			'filters.nightChosenHint' => 'Seulement les lieux de ces statuts',
			'filters.nightPossible' => 'Nuit possible',
			'filters.amenities' => 'Services',
			'filters.amenitiesHint' => 'Le lieu doit tous les avoir',
			'filters.rating' => 'Note minimale',
			'filters.ratingHint' => 'Note des visiteurs de Lunaway, ou celle des autres sources quand ils n\'ont pas noté le lieu. Un lieu sans note est masqué.',
			'filters.ratingAtLeast' => ({required Object rating}) => '${rating} et plus',
			'filters.opening' => 'Ouverture',
			'filters.openingHint' => 'Les lieux dont l\'ouverture n\'est pas connue restent affichés.',
			'filters.openingAllYear' => 'Toute l\'année',
			'filters.openingDates' => 'À mes dates',
			'filters.openingClearDates' => 'Effacer les dates',
			'filters.openingStay' => ({required Object from, required Object to}) => 'Du ${from} au ${to}',
			'filters.openingStayDay' => ({required Object date}) => 'Le ${date}',
			'filters.openingStayTitle' => 'Dates du séjour',
			'filters.openingArrival' => 'Arrivée',
			'filters.openingDeparture' => 'Départ',
			'filters.price' => 'Prix de la nuit',
			'filters.freeOnly' => 'Gratuit',
			'filters.freeHint' => 'Seulement les lieux dont la nuit est gratuite d\'après leurs sources',
			'filters.scrollNext' => 'Voir les filtres suivants',
			'filters.scrollPrevious' => 'Voir les filtres précédents',
			'filters.vehicle' => 'Mon véhicule',
			'filters.myVehicleFits' => 'Mon véhicule passe',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Passe à ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Masque les lieux limités sous ${height}. Les lieux sans hauteur connue restent affichés.',
			'filters.reset' => 'Tout effacer',
			'filters.apply' => 'Appliquer',
			'filters.show' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, zero: 'Aucun lieu ne correspond', one: 'Afficher ${count} lieu', other: 'Afficher ${count} lieux', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} filtre actif', other: '${n} filtres actifs', ), 
			'place.unnamedIn' => ({required Object kind, required Object town}) => '${kind} à ${town}',
			'place.away' => ({required Object distance}) => 'à ${distance}',
			'place.directions' => 'Itinéraire',
			'place.share' => 'Partager',
			'place.save' => 'Enregistrer',
			'place.saved' => 'Enregistré',
			'place.saveHint' => 'Dans Mes favoris. Appui long pour choisir des listes.',
			'place.saveTo' => 'Enregistrer dans une liste',
			'place.chooseLists' => 'Listes',
			'place.savedToast' => 'Ajouté à Mes favoris',
			'place.removedToast' => 'Retiré de Mes favoris',
			'place.pricePerNight' => 'Prix de la nuit',
			'place.priceFree' => 'Gratuit',
			'place.priceUnknown' => 'Non indiqué',
			'place.priceServices' => 'Services',
			'place.priceIncluded' => 'Inclus',
			'place.priceIncludes' => ({required Object items}) => 'Le prix de la nuit comprend : ${items}',
			'place.inclusions.services' => 'services',
			'place.inclusions.touristTax' => 'taxe de séjour',
			'place.inclusions.electricity' => 'électricité',
			'place.maxHeight' => 'Hauteur max.',
			'place.capacity' => 'Emplacements',
			'place.classification' => 'Classement',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} étoile', other: '${n} étoiles', ), 
			'place.hours' => 'Horaires',
			'place.services' => 'Services',
			'place.noServices' => 'Aucun service indiqué.',
			'place.activities' => 'À proximité',
			'place.description' => 'Description',
			'place.contact' => 'Contact',
			'place.website' => 'Site web',
			'place.call' => 'Appeler',
			'place.coordinates' => 'Coordonnées',
			'place.copy' => 'Copier les coordonnées',
			'place.copyShort' => 'Copier',
			'place.copyAs' => ({required Object format}) => 'Copier en ${format}',
			'place.copiesAs' => ({required Object format}) => '« Copier » copie : ${format}',
			'place.copied' => ({required Object text}) => 'Copié : ${text}',
			'place.otherFormats' => 'Choisir le format copié',
			'place.formatDecimal' => 'Degrés décimaux',
			'place.formatDms' => 'Degrés, minutes, secondes',
			'place.formatGeo' => 'Lien geo:',
			'place.formatGoogle' => 'Lien Google Maps',
			'place.formatOsm' => 'Lien OpenStreetMap',
			'place.sources' => 'Sources',
			'place.fetched' => ({required Object when}) => 'Relevé ${when}',
			'place.viewSource' => 'Voir à la source',
			'place.gone' => 'Ce lieu n\'est plus sur la carte',
			'place.goneHint' => 'Il a été retiré ou fusionné avec un autre depuis la dernière mise à jour.',
			'place.arriving' => 'Ce lieu est en cours de téléchargement',
			'place.arrivingHint' => 'Les lieux de France se téléchargent pour que la carte marche sans réseau. La fiche s\'ouvre dès que celui-ci est arrivé.',
			'place.loadError' => 'Ce lieu n\'a pas pu s\'afficher.',
			'place.openFailed' => 'Aucune application n\'a pu ouvrir ce lien.',
			'place.photos' => 'Photos',
			'place.extrasOffline' => 'Les photos et les avis demandent une connexion.',
			'place.reviewsTitle' => 'Avis',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} avis', other: '${n} avis', ), 
			'place.noReviews' => 'Aucun avis pour l\'instant.',
			'place.noOtherReviews' => 'Aucun autre avis pour l\'instant.',
			'place.moreReviews' => 'Plus d\'avis',
			'place.moreReviewsFailed' => 'La suite des avis n\'a pas pu se charger. Touchez pour réessayer.',
			'place.stars' => ({required Object rating}) => '${rating} sur 5',
			'place.externalRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'avis externe', other: 'avis externes', ), 
			'place.deletedAccount' => 'Compte supprimé',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Fourgon aménagé',
			'place.reviewVehicle.motorhome' => 'Camping-car',
			'place.reviewVehicle.caravan' => 'Caravane',
			'place.reviewVehicle.other' => 'Autre véhicule',
			'place.originalLanguage' => ({required Object language}) => 'Texte d\'origine en ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Photo ${index} sur ${count}',
			'place.previousPhoto' => 'Photo précédente',
			'place.nextPhoto' => 'Photo suivante',
			'place.links' => 'Sur d\'autres sites',
			'place.sourceWithLicence' => ({required Object source, required Object licence}) => '${source} · ${licence}',
			'place.licenceCcBy' => 'CC BY 4.0',
			'place.photoCredit' => ({required Object source, required Object author}) => '${source} · ${author}',
			'place.photoStreetView' => 'Vue de la rue',
			'place.photoSurroundings' => 'Aux alentours',
			'place.excerptFrom' => ({required Object source, required Object text}) => 'D\'après ${source} : ${text}',
			'place.readMore' => 'Lire la suite',
			'place.updatedOn' => ({required Object date}) => 'mis à jour le ${date}',
			'place.otherSources' => 'D\'après d\'autres sources',
			'sources.extcom.label' => 'Source communautaire externe',
			'sources.extcom.short' => 'Externe',
			'hours.open' => 'Ouvert maintenant',
			'hours.openUntil' => ({required Object time}) => 'Ouvert, ferme à ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Ouvert, ferme ${day} à ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Ouvert, ferme dans ${n} minute', other: 'Ouvert, ferme dans ${n} minutes', ), 
			'hours.closedUntil' => ({required Object time}) => 'Fermé, ouvre à ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Fermé, ouvre ${day} à ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Fermé, ouvre dans ${n} minute', other: 'Fermé, ouvre dans ${n} minutes', ), 
			'hours.closedWindow' => 'Fermé pendant les deux semaines à venir',
			'hours.tomorrow' => 'demain',
			'hours.onDate' => ({required Object date}) => 'le ${date}',
			'hours.onWeekday' => ({required Object day}) => '${day}',
			'hours.midnight' => 'minuit',
			'hours.stale' => 'Ouvert ou fermé ? Mettez à jour les lieux dans Profil.',
			'hours.localTime' => 'Horaires à l\'heure locale du lieu',
			'hours.codes.mo' => 'lun.',
			'hours.codes.tu' => 'mar.',
			'hours.codes.we' => 'mer.',
			'hours.codes.th' => 'jeu.',
			'hours.codes.fr' => 'ven.',
			'hours.codes.sa' => 'sam.',
			'hours.codes.su' => 'dim.',
			'hours.codes.ph' => 'jours fériés',
			'hours.codes.sh' => 'vacances scolaires',
			'hours.codes.off' => 'fermé',
			'hours.codes.closed' => 'fermé',
			'hours.codes.sunrise' => 'lever du soleil',
			'hours.codes.sunset' => 'coucher du soleil',
			'hours.months.jan' => 'janv.',
			'hours.months.feb' => 'févr.',
			'hours.months.mar' => 'mars',
			'hours.months.apr' => 'avr.',
			'hours.months.may' => 'mai',
			'hours.months.jun' => 'juin',
			'hours.months.jul' => 'juil.',
			'hours.months.aug' => 'août',
			'hours.months.sep' => 'sept.',
			'hours.months.oct' => 'oct.',
			'hours.months.nov' => 'nov.',
			'hours.months.dec' => 'déc.',
			'hours.dayOfMonth' => ({required Object day, required Object month}) => '${day} ${month}',
			'hours.dayOfYear' => ({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}',
			'hours.allWeek' => '24 h/24, 7 j/7',
			'hours.allYear' => 'toute l\'année',
			'hours.seasonAllYear' => 'Ouvert toute l\'année',
			'hours.seasonOpenUntil' => ({required Object date}) => 'Ouvert jusqu\'au ${date}',
			'hours.seasonClosedUntil' => ({required Object date}) => 'Fermé, ouvre le ${date}',
			'directions.title' => 'Ouvrir dans',
			'directions.hint' => 'Ces applications ne connaissent pas le gabarit de votre véhicule.',
			'directions.remember' => 'Toujours utiliser cette application',
			'directions.rememberHint' => 'Modifiable dans Profil',
			'directions.settingTitle' => 'Ouvrir dans une autre application',
			'directions.settingHint' => 'L\'application que lance « Ouvrir dans » depuis un itinéraire',
			'directions.askEachTime' => 'Demander à chaque fois',
			'directions.appleMaps' => 'Plans',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (navigateur)',
			'directions.none' => 'Aucune application de navigation trouvée sur cet appareil.',
			'navigation.preview.titleTo' => ({required Object name}) => 'Vers ${name}',
			'navigation.preview.titlePoint' => 'Point sur la carte',
			'navigation.preview.departure.title' => 'Départ',
			'navigation.preview.departure.from' => ({required Object name}) => 'Départ : ${name}',
			'navigation.preview.departure.myPosition' => 'ma position',
			'navigation.preview.departure.myPositionChoice' => 'Ma position',
			'navigation.preview.departure.change' => 'Changer',
			'navigation.preview.departure.choose' => 'Choisir un départ',
			'navigation.preview.departure.searchHint' => 'Un lieu, une commune, une adresse',
			'navigation.preview.departure.guidanceFromPosition' => 'Le guidage part de votre position, pas d\'un départ choisi.',
			'navigation.preview.departure.fromMyPosition' => 'Partir de ma position',
			'navigation.preview.computing' => 'Calcul d\'un itinéraire pour votre véhicule',
			'navigation.preview.start' => 'C\'est parti !',
			'navigation.preview.recommended' => 'Recommandé',
			'navigation.preview.alternative' => ({required Object n}) => 'Variante ${n}',
			'navigation.preview.toll' => 'Péage',
			'navigation.preview.ferry' => 'Ferry',
			'navigation.preview.motorway' => 'Autoroute',
			'navigation.preview.noWarnings' => 'Aucune limite proche du gabarit de votre véhicule sur ce trajet.',
			'navigation.preview.warnings' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '1 limite à surveiller', other: '${n} limites à surveiller', ), 
			'navigation.preview.vehicle' => 'Votre véhicule',
			'navigation.preview.vehicleTowing' => ({required Object vehicle}) => '${vehicle}, avec attelage',
			'navigation.preview.editVehicle' => 'Modifier',
			'navigation.preview.cruise' => ({required Object speed}) => 'Calculé à ${speed} max',
			'navigation.preview.avoid' => 'Éviter',
			'navigation.preview.avoidTolls' => 'Péages',
			'navigation.preview.avoidMotorways' => 'Autoroutes',
			'navigation.preview.avoidFerries' => 'Ferries',
			'navigation.preview.avoidUnpaved' => 'Routes non revêtues',
			'navigation.preview.roadbook' => 'Feuille de route',
			'navigation.preview.roadbookShow' => 'Voir les instructions',
			'navigation.preview.roadbookHide' => 'Masquer les instructions',
			'navigation.preview.dataOf' => ({required Object date}) => 'Données routières du ${date}',
			'navigation.preview.attributionOsm' => '© les contributeurs d\'OpenStreetMap',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, édition du ${date}',
			'navigation.preview.disclaimer' => 'Lunaway calcule l\'itinéraire avec les dimensions de votre véhicule et des données ouvertes (OpenStreetMap, IGN) qui peuvent être incomplètes ou erronées. La signalisation et le code de la route priment sur les indications de l\'application. Vous restez seul responsable de votre conduite.',
			'navigation.preview.otherApps' => 'Ouvrir dans…',
			'navigation.preview.back' => 'Retour',
			'navigation.preview.moved.origin' => ({required Object distance}) => 'Point de départ déplacé de ${distance} vers la rue accessible la plus proche',
			'navigation.preview.moved.destination' => ({required Object distance}) => 'Point d\'arrivée déplacé de ${distance} vers la rue accessible la plus proche',
			'navigation.preview.moved.stop' => ({required Object n, required Object distance}) => 'Étape ${n} déplacée de ${distance} vers la rue accessible la plus proche',
			'navigation.stops.title' => 'Étapes',
			'navigation.stops.add' => 'Ajouter comme étape',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Ajouter comme étape · +${minutes} min',
			'navigation.stops.addFree' => 'Ajouter comme étape · sans détour',
			'navigation.stops.quoting' => 'Ajouter comme étape · calcul du détour',
			'navigation.stops.noRoute' => 'Pas d\'itinéraire par ce point pour votre véhicule.',
			'navigation.stops.full' => 'Cinq étapes au plus.',
			'navigation.stops.goDirectly' => 'Y aller directement',
			'navigation.stops.openCard' => 'Voir la fiche',
			'navigation.stops.point' => 'Point sur la carte',
			'navigation.stops.remove' => 'Retirer l\'étape',
			'navigation.stops.reorder' => 'Glisser pour changer l\'ordre',
			'navigation.stops.added' => 'Étape ajoutée',
			'navigation.stops.removed' => 'Étape retirée',
			'navigation.stops.moved' => 'Ordre des étapes changé',
			'navigation.stops.destinationChanged' => 'Nouvelle destination',
			'navigation.stops.failed' => 'L\'itinéraire n\'a pas pu être changé.',
			'navigation.stops.noQuote' => 'Le détour n\'a pas pu être calculé.',
			'navigation.stops.offline' => 'Pas de réseau pour calculer le détour.',
			'navigation.fuel.price' => ({required Object price}) => '${price} €/L',
			'navigation.fuel.withDetour' => ({required Object price}) => '${price} €/L détour compris',
			'navigation.fuel.detour' => ({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min',
			'navigation.fuel.onRoute' => 'sur le trajet',
			'navigation.fuel.open' => 'Ouvert',
			'navigation.fuel.closed' => 'Fermé',
			'navigation.fuel.unknownHours' => 'Horaires inconnus',
			'navigation.fuel.add' => 'Ajouter',
			'navigation.fuel.station' => 'Station-service',
			'navigation.fuel.empty' => 'Aucune station de ce carburant près du trajet.',
			'navigation.fuel.failed' => 'Les stations n\'ont pas pu être chargées.',
			'navigation.fuel.estimated' => 'Détours estimés d\'après la distance à la route.',
			'navigation.fuel.attribution' => 'Prix : ministère de l\'Économie (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => 'il y a ${n} min',
			'navigation.fuel.hoursAgo' => ({required Object n}) => 'il y a ${n} h',
			'navigation.fuel.daysAgo' => ({required Object n}) => 'il y a ${n} j',
			'navigation.onTheWay.title' => 'Sur le trajet',
			'navigation.onTheWay.categories.fuel' => 'Carburant',
			'navigation.onTheWay.categories.sleep' => 'Dormir',
			'navigation.onTheWay.categories.water' => 'Eau et vidange',
			'navigation.onTheWay.categories.groceries' => 'Courses',
			'navigation.onTheWay.categories.bakeries' => 'Boulangeries',
			'navigation.onTheWay.categories.toilets' => 'Toilettes, douches',
			'navigation.onTheWay.categories.health' => 'Santé',
			'navigation.onTheWay.categories.services' => 'Services',
			'navigation.onTheWay.categories.charging' => 'Recharge',
			'navigation.onTheWay.categories.garages' => 'Garages',
			'navigation.onTheWay.fuelOfVehicle' => ({required Object fuel}) => '${fuel}, d\'après votre véhicule',
			'navigation.onTheWay.otherFuel' => 'Autre carburant',
			'navigation.onTheWay.keepFuel' => 'Retenir comme mon carburant',
			'navigation.onTheWay.fuelKept' => ({required Object fuel}) => '${fuel} retenu pour votre véhicule.',
			'navigation.onTheWay.keepFuelFailed' => 'Le carburant n\'a pas pu être retenu.',
			'navigation.onTheWay.loading' => 'Recherche le long du trajet',
			'navigation.onTheWay.empty' => 'Pas de résultat sur ce trajet',
			'navigation.onTheWay.emptyHint' => 'Essayez une autre catégorie, ou rouvrez la liste plus loin sur la route.',
			'navigation.onTheWay.failed' => 'La liste n\'a pas pu être chargée.',
			'navigation.onTheWay.offline' => 'Pas de réseau : la liste reviendra avec la connexion.',
			'navigation.onTheWay.rateLimited' => 'Beaucoup de recherches d\'affilée : réessayez dans quelques minutes.',
			'navigation.onTheWay.nearNone' => ({required Object distance}) => 'Rien dans les ${distance} devant vous.',
			'navigation.onTheWay.further' => ({required Object n}) => 'Plus loin (${n})',
			'navigation.onTheWay.more' => 'Voir plus',
			'navigation.onTheWay.moreFailed' => 'La suite n\'a pas pu être chargée.',
			'navigation.onTheWay.ahead' => ({required Object distance}) => 'dans ${distance}',
			'navigation.onTheWay.offRoute' => ({required Object distance}) => 'à ${distance} de la route',
			'navigation.onTheWay.byTheRoad' => 'au bord de la route',
			'navigation.onTheWay.addCost' => ({required Object minutes}) => 'Ajouter · +${minutes} min',
			'navigation.onTheWay.addFree' => 'Ajouter · sans détour',
			'navigation.onTheWay.openAt' => ({required Object time}) => 'Ouvert à votre passage, vers ${time}',
			'navigation.onTheWay.closedAt' => ({required Object time}) => 'Fermé à votre passage, vers ${time}',
			'navigation.onTheWay.closedOpensAt' => ({required Object time, required Object opens}) => 'Fermé à votre passage vers ${time}, ouvre à ${opens}',
			'navigation.onTheWay.perNight' => ({required Object price}) => '${price} la nuit',
			'navigation.onTheWay.photoFrom' => ({required Object source}) => 'Photo : ${source}',
			'navigation.onTheWay.servicesList' => ({required Object list}) => 'Services : ${list}',
			'navigation.onTheWay.movingBody' => 'Ne cherchez rien en conduisant. Un passager peut le faire ; sinon, arrêtez-vous d\'abord.',
			'navigation.onTheWay.placesCredit' => 'Lieux : Lunaway et les sources nommées sur chaque fiche',
			'navigation.states.vehicleTitle' => 'Quel est votre véhicule ?',
			'navigation.states.vehicleHint' => 'L\'itinéraire évite les ponts trop bas, les rues trop étroites et les routes interdites à votre gabarit. Indiquez sa hauteur, sa largeur, sa longueur et son poids.',
			'navigation.states.vehicleMissing' => ({required Object list}) => 'Il manque : ${list}',
			'navigation.states.vehicleOutOfBounds' => ({required Object list}) => 'Hors des valeurs acceptées : ${list}',
			'navigation.states.dimension.height' => 'hauteur',
			'navigation.states.dimension.width' => 'largeur',
			'navigation.states.dimension.length' => 'longueur',
			'navigation.states.dimension.weight' => 'poids',
			'navigation.states.describeVehicle' => 'Décrire mon véhicule',
			'navigation.states.originTitle' => 'Où êtes-vous ?',
			'navigation.states.originHint' => 'Lunaway a besoin de votre position pour calculer l\'itinéraire.',
			'navigation.states.locate' => 'Me localiser',
			'navigation.states.offlineTitle' => 'Pas de connexion',
			'navigation.states.offlineHint' => 'Les itinéraires se calculent sur le serveur de Lunaway. Sans réseau, « Ouvrir dans… » confie le trajet à une application de navigation qui garde ses cartes.',
			'navigation.states.rateLimitedTitle' => 'Trop d\'itinéraires demandés',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Réessayez dans ${seconds} s.',
			'navigation.states.unavailableTitle' => 'Calcul d\'itinéraire indisponible',
			'navigation.states.unavailableHint' => 'Le service est arrêté pour le moment. Réessayez plus tard.',
			'navigation.states.refusedTitle' => 'Pas d\'itinéraire ici',
			'navigation.states.refusedHint' => 'Lunaway n\'a pas pu calculer d\'itinéraire pour cette demande : vérifiez la destination, la longueur du trajet et les valeurs du véhicule.',
			'navigation.states.noSafeTitle' => 'Aucun itinéraire sûr pour votre véhicule',
			'navigation.states.noSafeHint' => 'Chaque route possible passe par une limite que votre véhicule dépasse :',
			'navigation.states.whatToDo' => 'Ce que vous pouvez faire',
			'navigation.states.checkVehicle' => ({required Object height, required Object weight}) => 'Vérifiez les valeurs saisies : ${height} de haut, ${weight}.',
			'navigation.states.pickOtherPoint' => 'Choisissez une arrivée avant l\'obstacle : appui long sur la carte.',
			'navigation.states.noRouteTitle' => 'Aucune route ne mène à ce point',
			'navigation.states.noRouteHint' => 'Le point est peut-être sur une voie privée, ou sur une île sans ferry.',
			'navigation.states.allowUnpaved' => 'Les voies non revêtues sont évitées : autorisez-les si l\'arrivée est sur un chemin.',
			'navigation.states.offNetworkTitle' => 'Trop loin d\'une route',
			'navigation.states.offNetworkHint' => 'Choisissez une arrivée sur une route.',
			'navigation.noRoute.originUnreachable' => 'Départ impossible avec votre véhicule',
			'navigation.noRoute.originUnreachableBy' => ({required Object limit}) => 'Départ impossible avec votre véhicule : ${limit}',
			'navigation.noRoute.destinationUnreachable' => 'Destination inaccessible avec votre véhicule',
			'navigation.noRoute.destinationUnreachableBy' => ({required Object limit}) => 'Destination inaccessible avec votre véhicule : ${limit}',
			'navigation.noRoute.waypointUnreachable' => ({required Object n}) => 'Étape ${n} inaccessible avec votre véhicule',
			'navigation.noRoute.waypointUnreachableBy' => ({required Object n, required Object limit}) => 'Étape ${n} inaccessible avec votre véhicule : ${limit}',
			'navigation.noRoute.blockedOnTheWay' => 'Aucun passage pour votre véhicule entre les étapes',
			'navigation.noRoute.blockedOnTheWayBy' => ({required Object limit}) => 'Aucun passage pour votre véhicule entre les étapes : ${limit}',
			'navigation.noRoute.blockedHint' => 'Chaque étape est accessible, mais toutes les routes qui les relient passent par une limite que votre véhicule dépasse.',
			'navigation.noRoute.notConnectedOrigin' => 'Aucune route ne part de votre position',
			'navigation.noRoute.notConnectedDestination' => 'Aucune route ne mène à la destination',
			'navigation.noRoute.notConnectedWaypoint' => ({required Object n}) => 'Aucune route ne mène à l\'étape ${n}',
			'navigation.noRoute.notConnectedTrip' => 'Aucune route ne relie vos étapes',
			'navigation.noRoute.notConnectedHint' => 'Quel que soit le véhicule : une île sans ferry pour les véhicules, ou une voie fermée à la circulation.',
			'navigation.noRoute.outsideOrigin' => 'Votre position est hors de la zone des itinéraires',
			'navigation.noRoute.outsideDestination' => 'Destination hors de la zone des itinéraires',
			'navigation.noRoute.outsideWaypoint' => ({required Object n}) => 'Étape ${n} hors de la zone des itinéraires',
			'navigation.noRoute.outsideHint' => ({required Object countries}) => 'Lunaway calcule les itinéraires dans ces pays : ${countries}.',
			_ => null,
		} ?? switch (path) {
			'navigation.noRoute.outsideHintUnknown' => 'Lunaway ne calcule pas encore d\'itinéraire dans ce pays.',
			'navigation.noRoute.noRoadOrigin' => 'Votre position est trop loin d\'une route',
			'navigation.noRoute.noRoadDestination' => 'Destination trop loin d\'une route',
			'navigation.noRoute.noRoadWaypoint' => ({required Object n}) => 'Étape ${n} trop loin d\'une route',
			'navigation.noRoute.noRoadHint' => 'Aucune route que votre véhicule peut prendre à moins de 5 km de ce point.',
			'navigation.noRoute.tooLong' => 'Trajet trop long',
			'navigation.noRoute.tooLongHint' => ({required Object trip, required Object max}) => '${trip} à vol d\'oiseau d\'étape en étape : Lunaway calcule les trajets de ${max} au plus.',
			'navigation.noRoute.vehicleValue' => ({required Object value}) => 'Votre véhicule : ${value}',
			'navigation.noRoute.limit.underpass' => ({required Object limit}) => 'pont bas à ${limit}',
			'navigation.noRoute.limit.tunnel' => ({required Object limit}) => 'tunnel à ${limit}',
			'navigation.noRoute.limit.buildingPassage' => ({required Object limit}) => 'porche à ${limit}',
			'navigation.noRoute.limit.bridge' => ({required Object limit}) => 'pont à ${limit}',
			'navigation.noRoute.limit.barrier' => ({required Object limit}) => 'barre de hauteur à ${limit}',
			'navigation.noRoute.limit.height' => ({required Object limit}) => 'hauteur limitée à ${limit}',
			'navigation.noRoute.limit.heightUnknown' => 'hauteur limitée',
			'navigation.noRoute.limit.width' => ({required Object limit}) => 'passage étroit de ${limit}',
			'navigation.noRoute.limit.widthUnknown' => 'passage étroit',
			'navigation.noRoute.limit.length' => ({required Object limit}) => 'longueur limitée à ${limit}',
			'navigation.noRoute.limit.lengthUnknown' => 'longueur limitée',
			'navigation.noRoute.limit.weight' => ({required Object limit}) => 'poids limité à ${limit}',
			'navigation.noRoute.limit.weightUnknown' => 'poids limité',
			'navigation.noRoute.limit.unpaved' => 'route non revêtue',
			'navigation.noRoute.limit.weightLocalAccess' => ({required Object limit}) => 'poids limité à ${limit} sauf desserte',
			'navigation.noRoute.limit.widthLocalAccess' => ({required Object limit}) => 'passage étroit de ${limit} sauf desserte',
			'navigation.noRoute.limit.lengthLocalAccess' => ({required Object limit}) => 'longueur limitée à ${limit} sauf desserte',
			'navigation.noRoute.editVehicle' => 'Modifier le véhicule',
			'navigation.noRoute.allowUnpaved' => 'Autoriser les routes non revêtues',
			'navigation.noRoute.removeStop' => ({required Object n}) => 'Retirer l\'étape ${n}',
			'navigation.noRoute.removeStopNamed' => ({required Object name}) => 'Retirer l\'étape « ${name} »',
			'navigation.noRoute.placesAround' => 'Voir les lieux autour de la destination',
			'navigation.noRoute.moveDestination' => 'Ou choisissez une autre arrivée : appui long sur la carte, puis « Y aller directement ».',
			'navigation.noRoute.moveStop' => 'Pour une autre étape : touchez la carte de près, ou appui long, puis « Ajouter comme étape ».',
			'navigation.noRoute.moveOrigin' => 'Le départ est votre position : rejoignez une route que votre véhicule peut prendre, puis réessayez.',
			'navigation.noRoute.pickInside' => 'Choisissez une destination dans un de ces pays.',
			'navigation.noRoute.shorter' => 'Choisissez une destination plus proche, ou faites le trajet en plusieurs fois.',
			'navigation.ferry.title' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Traversée en ferry', other: '${n} traversées en ferry', ), 
			'navigation.ferry.unnamed' => 'Ferry',
			'navigation.ferry.named' => ({required Object name}) => 'Ferry ${name}',
			'navigation.ferry.ports' => ({required Object ports}) => 'Ports : ${ports}',
			'navigation.ferry.countries' => ({required Object from, required Object to}) => 'Embarquement : ${from} · Débarquement : ${to}',
			'navigation.ferry.country' => ({required Object country}) => 'Pays : ${country}',
			'navigation.ferry.where' => ({required Object distance, required Object sea, required Object duration}) => 'À ${distance} du départ · ${sea} en mer, environ ${duration}',
			'navigation.ferry.needed' => 'La destination ne peut pas être atteinte sans ferry : l\'itinéraire en prend un, même si vous évitez les ferries.',
			'navigation.warning.lowClearance.underpass' => ({required Object limit}) => 'Pont bas ${limit}',
			'navigation.warning.lowClearance.tunnel' => ({required Object limit}) => 'Tunnel ${limit}',
			'navigation.warning.lowClearance.buildingPassage' => ({required Object limit}) => 'Porche ${limit}',
			'navigation.warning.lowClearance.bridge' => ({required Object limit}) => 'Pont ${limit}',
			'navigation.warning.lowClearance.barrier' => ({required Object limit}) => 'Barre de hauteur ${limit}',
			'navigation.warning.lowClearance.road' => ({required Object limit}) => 'Hauteur limitée ${limit}',
			'navigation.warning.unknownClearance' => 'Passage bas, hauteur inconnue',
			'navigation.warning.narrow' => ({required Object limit}) => 'Passage étroit ${limit}',
			'navigation.warning.tooLong' => ({required Object limit}) => 'Longueur limitée ${limit}',
			'navigation.warning.tooHeavy' => ({required Object limit}) => 'Poids limité ${limit}',
			'navigation.warning.axleLoad' => ({required Object limit}) => 'Charge à l\'essieu limitée ${limit}',
			'navigation.warning.motorhomeBan' => 'Interdit aux camping-cars',
			'navigation.warning.trailerBan' => 'Interdit aux remorques',
			'navigation.warning.goodsVehicleWeight' => ({required Object limit}) => 'Poids limité pour les poids lourds ${limit}',
			'navigation.warning.yours' => ({required Object value}) => 'votre véhicule : ${value}',
			'navigation.warning.fromStart' => ({required Object distance}) => 'à ${distance} du départ',
			'navigation.warning.ahead' => ({required Object distance}) => 'dans ${distance}',
			'navigation.warning.disputed' => 'les sources divergent, la valeur la plus basse s\'applique',
			'navigation.warning.goodsOnly' => 'vise les poids lourds de marchandises, voyez les panneaux',
			'navigation.warning.osm' => 'OpenStreetMap',
			'navigation.warning.ign' => 'IGN BD TOPO',
			'navigation.warning.community' => 'Signalement Lunaway',
			'navigation.warning.dialog' => 'Arrêté de circulation (DiaLog)',
			'navigation.warning.localAccess.weight' => ({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} sauf pour rejoindre votre destination',
			'navigation.warning.localAccess.axleLoad' => ({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} par essieu sauf pour rejoindre votre destination',
			'navigation.warning.localAccess.width' => ({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} de large sauf pour rejoindre votre destination',
			'navigation.warning.localAccess.length' => ({required Object limit}) => 'Accès riverains (desserte) : interdit aux plus de ${limit} de long sauf pour rejoindre votre destination',
			'navigation.roadEvents.title' => 'Travaux et fermetures',
			'navigation.roadEvents.none' => 'Pas de travaux ni de fermeture connus sur ce trajet.',
			'navigation.roadEvents.stale' => 'Travaux et fermetures : les sources n\'ont pas été lues récemment.',
			'navigation.roadEvents.avoided' => ({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Itinéraire calculé autour d\'une fermeture : ${names}', other: 'Itinéraire calculé autour de ${n} fermetures : ${names}', ), 
			'navigation.roadEvents.atDistance' => ({required Object distance}) => 'à ${distance} du départ',
			'navigation.roadEvents.more' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Et ${n} autre sur le trajet', other: 'Et ${n} autres sur le trajet', ), 
			'navigation.roadEvents.classClosure' => 'Route fermée',
			'navigation.roadEvents.classWorks' => 'Travaux',
			'navigation.roadEvents.classLaneRestriction' => 'Voies réduites',
			'navigation.roadEvents.classVehicleLimit' => 'Gabarit limité',
			'navigation.roadEvents.classDetour' => 'Déviation signalée',
			'navigation.roadEvents.reasonUnmatched' => 'position incertaine, peut-être sur le trajet',
			'navigation.roadEvents.reasonStale' => 'source pas lue récemment',
			'navigation.roadEvents.reasonOutsideHours' => 'hors des heures supposées',
			'navigation.roadEvents.reasonGoodsVehicles' => 'pour les poids lourds',
			'navigation.roadEvents.reasonUnconfirmed' => 'signalé par un seul voyageur',
			'navigation.roadEvents.reasonAged' => 'signalement ancien',
			'navigation.roadEvents.reasonInside' => 'le trajet commence ou finit dedans',
			'navigation.roadEvents.reasonNearLimit' => 'de justesse',
			'navigation.roadEvents.reasonOverLimit' => 'au-dessus de la limite de votre véhicule',
			'navigation.marks.legend' => 'Légende',
			'navigation.marks.legendHide' => 'Replier la légende',
			'navigation.marks.kindOrigin' => 'Départ',
			'navigation.marks.kindDestination' => 'Arrivée',
			'navigation.marks.kindStop' => 'Étape',
			'navigation.marks.kindClosure' => 'Route fermée',
			'navigation.marks.kindWorks' => 'Travaux',
			'navigation.marks.kindLanes' => 'Voies réduites',
			'navigation.marks.kindClearance' => 'Hauteur limitée',
			'navigation.marks.kindWeight' => 'Poids limité',
			'navigation.marks.kindLimit' => 'Autre limite (largeur, longueur, interdiction)',
			'navigation.marks.kindFuel' => 'Station-service',
			'navigation.marks.kindPlace' => 'Lieu près du trajet',
			'navigation.marks.groupLegend' => 'Repères proches regroupés',
			'navigation.marks.zoneLegend' => 'Zone de danger',
			'navigation.marks.zonesFrom' => ({required Object source, required Object date}) => 'Zones de danger : ${source}, liste du ${date}',
			'navigation.marks.group' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} repère', other: '${n} repères', ), 
			'navigation.marks.groupHint' => 'Rapprochez-vous pour les voir un par un',
			'navigation.marks.count' => ({required Object kind, required Object n}) => '${kind} : ${n}',
			'navigation.marks.stop' => ({required Object n}) => 'Étape ${n}',
			'navigation.marks.origin' => 'Point de départ',
			'navigation.marks.nearRoute' => 'Près du trajet',
			'navigation.marks.avoided' => 'L\'itinéraire passe à côté',
			'navigation.marks.blocking' => 'Bloque chaque itinéraire',
			'navigation.marks.showInList' => 'Voir dans la liste',
			'navigation.marks.showAll' => 'Tout afficher',
			'navigation.marks.onMap' => 'montrer sur la carte',
			'navigation.marks.price' => ({required Object price}) => '${price} €',
			'navigation.guidance.then' => 'Puis',
			'navigation.guidance.arrival' => ({required Object time}) => 'Arrivée ${time}',
			'navigation.guidance.offRoute' => 'Hors itinéraire',
			'navigation.guidance.rerouting' => 'Recherche d\'un nouvel itinéraire',
			'navigation.guidance.rerouted' => 'Nouvel itinéraire',
			'navigation.guidance.reroutedLonger' => ({required Object minutes}) => 'Nouvel itinéraire, ${minutes} min de plus',
			'navigation.guidance.rerouteOffline' => 'Pas de réseau pour un nouvel itinéraire : rejoignez le trajet',
			'navigation.guidance.rerouteFailed' => 'Aucun nouvel itinéraire : rejoignez le trajet',
			'navigation.guidance.closureAhead' => ({required Object distance}) => 'Route fermée dans ${distance} : recherche d\'un autre chemin',
			'navigation.guidance.noDetour' => ({required Object distance}) => 'Route fermée dans ${distance} : aucun autre chemin',
			'navigation.guidance.eventAhead' => ({required Object distance}) => 'Travaux dans ${distance}',
			'navigation.guidance.eventClosure' => ({required Object distance}) => 'Route fermée dans ${distance}',
			'navigation.guidance.eventLimit' => ({required Object distance}) => 'Gabarit limité par des travaux dans ${distance}',
			'navigation.guidance.eventSource' => ({required Object source, required Object time}) => '${source}, données de ${time}',
			'navigation.guidance.eventSourceOn' => ({required Object source, required Object day, required Object time}) => '${source}, données du ${day} à ${time}',
			'navigation.guidance.avoidedClosures' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Itinéraire calculé autour d\'une fermeture', other: 'Itinéraire calculé autour de ${n} fermetures', ), 
			'navigation.guidance.roadEventAhead' => ({required Object what, required Object distance}) => '${what} dans ${distance}',
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Route fermée dans ${distance} : pas de réseau pour chercher un autre chemin',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Route fermée dans ${distance} : pas encore d\'autre chemin',
			'navigation.guidance.voiceOn' => 'Activer la voix',
			'navigation.guidance.voiceOff' => 'Couper la voix',
			'navigation.guidance.overview' => 'Tout le trajet',
			'navigation.guidance.recenter' => 'Recentrer',
			'navigation.guidance.end' => 'Terminer',
			'navigation.guidance.endTitle' => 'Terminer le guidage ?',
			'navigation.guidance.endConfirm' => 'Terminer',
			'navigation.guidance.endKeep' => 'Continuer',
			'navigation.guidance.stopTitle' => 'Arrêter le guidage ?',
			'navigation.guidance.stopConfirm' => 'Arrêter',
			'navigation.guidance.arrivedTitle' => 'Vous êtes à destination',
			'navigation.guidance.done' => 'Terminer',
			'navigation.guidance.speed' => 'Vitesse',
			'navigation.guidance.limit' => 'Limite',
			'navigation.guidance.noVoice' => ({required Object language}) => 'Aucune voix en ${language} sur cet appareil : instructions à l\'écran seulement.',
			'navigation.guidance.missingVoice' => ({required Object language}) => 'La voix en ${language} n\'est pas encore téléchargée.',
			'navigation.guidance.installVoice' => 'Installer',
			'navigation.guidance.voiceSettingsIos' => 'Réglages, Accessibilité, Contenu énoncé, Voix',
			'navigation.guidance.notificationTitle' => 'Lunaway vous guide',
			'navigation.guidance.notificationText' => 'Le guidage continue écran éteint.',
			'navigation.guidance.notificationChannel' => 'Guidage',
			'navigation.guidance.unavailable' => 'Le guidage n\'a pas pu démarrer sur cet appareil.',
			'navigation.guidance.notificationWhy.title' => 'Notification du guidage',
			'navigation.guidance.notificationWhy.body' => 'Pendant le guidage, une notification garde la position et la voix actives écran éteint, et la toucher ramène au guidage. Android va demander si Lunaway peut l\'afficher.',
			'navigation.guidance.notificationWhy.ask' => 'Continuer',
			'navigation.guidance.notificationWhy.later' => 'Pas maintenant',
			'navigation.guidance.positionLost' => 'Position indisponible : vérifiez que la localisation de l\'appareil est activée pour Lunaway.',
			'navigation.guidance.positionStale' => ({required Object minutes}) => 'Dernière position reçue il y a ${minutes} min : l\'heure d\'arrivée en dépend.',
			'navigation.guidance.firstTitle' => 'Avant de partir',
			'navigation.guidance.firstAccept' => 'J\'ai compris',
			'navigation.guidance.dangerZone' => ({required Object distance}) => 'Zone de danger dans ${distance}',
			'navigation.guidance.inDangerZone' => ({required Object distance}) => 'Zone de danger, encore ${distance}',
			'navigation.guidance.cameraAhead' => ({required Object distance}) => 'Radar dans ${distance}',
			'navigation.guidance.cameraLimit' => ({required Object distance, required Object limit}) => 'Radar dans ${distance}, ${limit}',
			'navigation.guidance.limitEstimated' => 'Limite estimée',
			'navigation.guidance.overLimit' => 'au-dessus de la limite',
			'navigation.guidance.enforcementSource' => ({required Object source, required Object date}) => '${source}, liste du ${date}',
			'navigation.guidance.demoDrive' => 'Trajet simulé : démonstration sans GPS',
			'navigation.guidance.places.button' => 'Lieux sur la carte',
			'navigation.guidance.places.buttonHidden' => 'Lieux sur la carte : masqués',
			'navigation.guidance.places.title' => 'Lieux sur la carte',
			'navigation.guidance.places.sleep' => 'Pour dormir',
			'navigation.guidance.places.fill' => 'Pour le plein',
			'navigation.guidance.places.groceries' => 'Courses',
			'navigation.guidance.places.all' => 'Tout',
			'navigation.guidance.places.none' => 'Rien',
			'navigation.guidance.places.customize' => 'Personnaliser',
			'navigation.guidance.places.look' => 'Affichage',
			'navigation.guidance.places.photos' => 'Photos',
			'navigation.guidance.places.pictograms' => 'Pictogrammes',
			'navigation.guidance.places.dots' => 'Points discrets',
			'navigation.guidance.places.photosHint' => 'Les lieux qui comptent le plus, en photo. Jamais sur la route devant vous ni sous les boutons.',
			'navigation.guidance.places.pictogramsHint' => 'Les lieux qui comptent le plus, en grand, avec leur prix, leur note ou la nuit.',
			'navigation.guidance.places.dotsHint' => 'Tous les lieux en petites épingles, comme sur la carte.',
			'navigation.guidance.places.free' => 'Gratuit',
			'navigation.guidance.places.nightOk' => 'Nuit OK',
			'navigation.voice.rerouting' => 'Recalcul de l\'itinéraire.',
			'navigation.voice.rerouted' => 'Nouvel itinéraire.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(minutes, one: 'Nouvel itinéraire, une minute de plus.', other: 'Nouvel itinéraire, ${minutes} minutes de plus.', ), 
			'navigation.voice.moved.destination' => ({required Object distance}) => 'Point d\'arrivée déplacé de ${distance} vers la rue accessible la plus proche.',
			'navigation.voice.moved.stop' => ({required Object n, required Object distance}) => 'Étape ${n} déplacée de ${distance} vers la rue accessible la plus proche.',
			'navigation.voice.closureAhead' => ({required Object distance}) => 'Route fermée dans ${distance}. Recherche d\'un autre chemin.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'Route fermée dans ${distance}. Il n\'y a pas d\'autre chemin.',
			'navigation.voice.clearance' => ({required Object height, required Object distance}) => 'Attention, passage bas de ${height} dans ${distance}.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Attention, passage bas de hauteur inconnue dans ${distance}.',
			'navigation.voice.narrow' => ({required Object width, required Object distance}) => 'Attention, passage étroit de ${width} dans ${distance}.',
			'navigation.voice.limit' => ({required Object what, required Object distance}) => 'Attention, ${what} dans ${distance}.',
			'navigation.voice.arrived' => 'Vous êtes à destination.',
			'navigation.voice.metres' => ({required Object n}) => '${n} mètres',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${n} kilomètre', other: '${n} kilomètres', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} pieds',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${n} mile', other: '${n} miles', ), 
			'navigation.voice.size' => ({required num count, required Object metres, required Object cm}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${metres} mètre ${cm}', other: '${metres} mètres ${cm}', ), 
			'navigation.voice.sizeWhole' => ({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${metres} mètre', other: '${metres} mètres', ), 
			'navigation.voice.overSpeed' => ({required Object limit}) => 'Vitesse limitée à ${limit}.',
			'navigation.voice.dangerZone' => ({required Object distance}) => 'Zone de danger dans ${distance}.',
			'navigation.voice.inDangerZone' => 'Zone de danger.',
			'navigation.voice.camera' => ({required Object distance}) => 'Radar dans ${distance}.',
			'navigation.voice.localAccess.weight' => ({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} seulement pour la desserte.',
			'navigation.voice.localAccess.axleLoad' => ({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} par essieu seulement pour la desserte.',
			'navigation.voice.localAccess.width' => ({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} de large seulement pour la desserte.',
			'navigation.voice.localAccess.length' => ({required Object distance, required Object limit}) => 'Attention, dans ${distance}, accès riverains : plus de ${limit} de long seulement pour la desserte.',
			'navigation.voice.tonnes' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${n} tonne', other: '${n} tonnes', ), 
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} h ${m}',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Guidage',
			'navigation.settings.avoidTitle' => 'Éviter par défaut',
			'navigation.settings.voice' => 'Instructions vocales',
			'navigation.settings.voiceHint' => 'Avec la voix de l\'appareil',
			'navigation.settings.units' => 'Distances',
			'navigation.settings.metric' => 'Kilomètres',
			'navigation.settings.imperial' => 'Miles',
			'navigation.settings.speedLimit' => 'Limite de vitesse',
			'navigation.settings.speedLimitHint' => 'La limite pour votre véhicule à côté de la vitesse pendant le guidage ; une estimation s\'affiche en gris.',
			'navigation.settings.speedSound' => 'Alertes de vitesse parlées',
			'navigation.settings.speedSoundHint' => 'Un mot quand vous dépassez la limite, et avant une zone de danger là où le pays les autorise. Coupé : le panneau et les bandeaux seuls.',
			'list.title' => 'Lieux à proximité',
			'list.empty' => 'Aucun lieu par ici avec ces filtres',
			'list.emptyHint' => 'Déplacez la carte, dézoomez ou assouplissez les filtres.',
			'list.downloading' => 'Les lieux arrivent',
			'list.downloadingHint' => 'La liste se remplit pendant le téléchargement.',
			'list.error' => 'La liste n\'a pas pu s\'afficher.',
			'list.offline' => 'Pas de connexion : la liste a besoin du réseau.',
			'list.moreFailed' => 'La suite de la liste n\'a pas pu s\'afficher. Réessayer',
			'list.sortDistance' => 'Distance',
			'list.sortRating' => 'Note',
			'list.sortNewest' => 'Ajoutés récemment',
			'list.sortedBy' => ({required Object sort}) => 'Liste triée par : ${sort}',
			'list.rankedAmongNearestYou' => ({required Object n}) => 'Classés parmi les ${n} lieux les plus proches de vous',
			'list.rankedAmongNearestCentre' => ({required Object n}) => 'Classés parmi les ${n} lieux les plus proches du centre de la carte',
			'list.offlineTitle' => 'Pas de connexion',
			'list.offlineNotHere' => 'Rien de cette zone sur cet appareil.',
			'favorites.title' => 'Favoris',
			'favorites.defaultList' => 'Mes favoris',
			'favorites.empty' => 'Rien d\'enregistré ici pour l\'instant',
			'favorites.emptyHint' => 'Touchez Enregistrer sur un lieu pour le garder, même hors connexion.',
			'favorites.newList' => 'Nouvelle liste',
			'favorites.listName' => 'Nom de la liste',
			'favorites.renameList' => 'Renommer la liste',
			'favorites.deleteList' => 'Supprimer la liste',
			'favorites.deleteListConfirm' => ({required Object name}) => 'Supprimer « ${name} » ? Les lieux restent sur la carte.',
			'favorites.listActions' => 'Options de la liste',
			'favorites.placeActions' => 'Options du lieu',
			'favorites.openOnMap' => 'Voir sur la carte',
			'favorites.remove' => 'Retirer de la liste',
			'favorites.removed' => 'Retiré de la liste',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, zero: 'Vide', one: '${n} lieu', other: '${n} lieux', ), 
			'favorites.error' => 'Vos favoris n\'ont pas pu s\'afficher.',
			'vehicle.title' => 'Mon véhicule',
			'vehicle.why' => 'Ses dimensions servent à masquer les lieux où il ne passe pas. Elles sont envoyées avec chaque demande d\'itinéraire, sans être conservées.',
			'vehicle.none' => 'Décrivez votre véhicule pour masquer les lieux où il ne passe pas.',
			'vehicle.add' => 'Décrire mon véhicule',
			'vehicle.edit' => 'Modifier',
			'vehicle.type' => 'Type',
			'vehicle.types.van' => 'Van',
			'vehicle.types.campervan' => 'Fourgon aménagé',
			'vehicle.types.lowProfile' => 'Profilé',
			'vehicle.types.overcab' => 'Capucine',
			'vehicle.types.integrated' => 'Intégral',
			'vehicle.towingTitle' => 'Il tracte',
			'vehicle.towing.none' => 'Rien',
			'vehicle.towing.car' => 'Une voiture',
			'vehicle.towing.trailer' => 'Une remorque',
			'vehicle.size' => 'Dimensions',
			'vehicle.sizeHint' => 'Valeurs typiques du type choisi : corrigez-les avec celles de votre carte grise.',
			'vehicle.height' => 'Hauteur',
			'vehicle.width' => 'Largeur',
			'vehicle.length' => 'Longueur totale, attelage compris',
			'vehicle.weight' => 'Poids total autorisé (PTAC)',
			'vehicle.heightShort' => ({required Object value}) => 'H ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'l ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'L ${value}',
			'vehicle.notANumber' => 'Un nombre, par exemple 2,90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Entre ${min} et ${max} ${unit}',
			'vehicle.navigationLater' => 'Le guidage de Lunaway tient compte de toutes ces dimensions.',
			'vehicle.save' => 'Enregistrer',
			'vehicle.clear' => 'Effacer',
			'vehicle.fuelTitle' => 'Carburant',
			'vehicle.fuelHint' => 'Le prix de votre carburant s\'affiche sur les stations de la carte, les moins chères en premier.',
			'vehicle.consumption' => 'Consommation',
			'vehicle.consumptionUnit' => 'L/100 km',
			'vehicle.lpgHeating' => 'Chauffage au GPL',
			'vehicle.lpgHeatingHint' => 'Le prix du GPL s\'affiche aussi sur les stations.',
			'vehicle.cruiseTitle' => 'Vitesse de croisière max',
			'vehicle.cruiseHint' => 'Les temps de trajet supposent que vous ne roulez jamais plus vite, même là où la route le permet. Les limitations annoncées pendant le guidage restent celles de la route.',
			'vehicle.cruiseNone' => 'Pas de limite',
			'vehicleHeight.title' => 'Hauteur de votre véhicule',
			'vehicleHeight.why' => 'Les lieux limités plus bas seront masqués. Ceux dont la hauteur n\'est pas connue restent affichés.',
			'vehicleHeight.needed' => 'Indiquez la hauteur, par exemple 2,90',
			'vehicleHeight.weightOptional' => 'Poids total autorisé (facultatif)',
			'vehicleHeight.apply' => 'Filtrer avec cette hauteur',
			'vehicleHeight.later' => 'Le reste du véhicule se décrit dans Profil, Mon véhicule.',
			'profile.title' => 'Profil',
			'profile.noAccountNeeded' => 'Sans compte, sans publicité, sans traceur. Vos favoris restent sur cet appareil.',
			'profile.language' => 'Langue',
			'profile.languageSystem' => 'Comme l\'appareil',
			'profile.appearance' => 'Apparence',
			'profile.themeAuto' => 'Auto',
			'profile.themeLight' => 'Clair',
			'profile.themeDark' => 'Sombre',
			'profile.themeAutoHint' => 'Clair le jour, sombre après le coucher du soleil là où vous êtes.',
			'profile.themeLightHint' => 'Toujours clair, de jour comme de nuit.',
			'profile.themeDarkHint' => 'Toujours sombre, doux pour les yeux la nuit.',
			'profile.offline' => 'Hors ligne',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu sur cet appareil', other: 'lieux sur cet appareil', ), 
			'profile.offlineSize' => ({required Object size}) => 'Espace utilisé : ${size}',
			'profile.lastSync' => ({required Object when}) => 'Dernière mise à jour ${when}',
			'profile.neverSynced' => 'Jamais téléchargé',
			'profile.syncNow' => 'Mettre à jour',
			'profile.syncing' => 'Mise à jour en cours',
			'profile.about' => 'À propos',
			'profile.version' => ({required Object version}) => 'Version ${version}',
			'profile.website' => 'Site web',
			'profile.privacy' => 'Politique de confidentialité',
			'profile.sourceCode' => 'Code source',
			'profile.licences' => 'Licences',
			'profile.appLicence' => 'Lunaway est un logiciel libre sous licence GNU AGPL 3.0 ou ultérieure.',
			'profile.attributions' => 'Sources et crédits',
			'profile.attributionOsm' => 'Lieux et données cartographiques © les contributeurs d\'OpenStreetMap.',
			'profile.attributionOdbl' => 'Données d\'OpenStreetMap sous licence Open Database License (ODbL).',
			'profile.attributionAtout' => 'Campings classés d\'Atout France, sous Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Communes des lieux : Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), sous licence ODbL.',
			'profile.attributionTiles' => 'Fond de carte servi par Lunaway, styles dérivés de Protomaps (BSD-3-Clause), données © les contributeurs d\'OpenStreetMap.',
			'profile.attributionFonts' => 'Polices Fraunces et Atkinson Hyperlegible Next, sous licence SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Icônes Phosphor, sous licence MIT.',
			'profile.noTracking' => 'Sans publicité ni traceur. Votre compte ne connaît ni votre e-mail ni votre téléphone.',
			'profile.attributionBdTopo' => 'Hauteurs, largeurs, longueurs et poids limités des routes, et campings placés par leur nom : BD TOPO de l\'IGN, par la Géoplateforme, sous Licence Ouverte 2.0.',
			'profile.attributionAddresses' => 'Adresses de la recherche en France : Base Adresse Nationale, par la Géoplateforme de l\'IGN, sous Licence Ouverte 2.0.',
			'profile.attributionAddressesOsm' => 'Adresses de la recherche ailleurs : OpenStreetMap, par Photon, sous ODbL.',
			'profile.attributionPoiOdbl' => 'Commerces et services : OpenStreetMap, et le calendrier d\'ouverture de La Poste, sous ODbL.',
			'profile.attributionPoiLo' => 'Prix des carburants (ministère de l\'Économie) et établissements de santé FINESS, sous Licence Ouverte 2.0 (Etalab).',
			'profile.attributionPacks' => 'Contours des cartes hors ligne : Contours administratifs, data.gouv.fr (ODbL), et Natural Earth (domaine public).',
			'profile.attributionOfflineLabels' => 'Noms et icônes des cartes hors ligne : glyphes Noto Sans (SIL Open Font License 1.1) et sprites Protomaps dérivés de tangrams/icons (MIT).',
			'profile.attributionExtcom' => 'Lieux, avis, notes et photos, sous accord écrit avec cette source.',
			'profile.creditsPlaces' => 'Lieux',
			'profile.creditsContent' => 'Photos, textes et avis',
			'profile.creditsRoutes' => 'Itinéraires et guidage',
			'profile.creditsSearch' => 'Recherche',
			'profile.creditsMap' => 'Fond de carte',
			'profile.creditsApp' => 'Application',
			'profile.attributionDatatourisme' => 'Lieux, descriptions et photos des offices de tourisme : DATAtourisme, sous Licence Ouverte 2.0 ; chaque texte et chaque photo nomme son office, son auteur et sa date de mise à jour.',
			'profile.attributionCommunity' => 'Avis, notes et photos des voyageurs de Lunaway, sous licence CC BY 4.0, avec le pseudonyme de leur auteur.',
			'profile.attributionCommons' => 'Photos de Wikimedia Commons, chacune sous sa licence (CC0, CC BY ou CC BY-SA), avec son auteur et un lien vers sa page.',
			'profile.attributionPanoramax' => 'Vues de la rue de Panoramax : instance d\'OpenStreetMap France sous licence CC BY-SA 4.0, instance de l\'IGN sous Licence Ouverte 2.0.',
			'profile.attributionWikipedia' => 'Extraits d\'articles de Wikipedia, sous licence CC BY-SA 4.0, avec un lien vers l\'article.',
			'profile.attributionMangrove' => 'Avis de Mangrove Reviews, sous licence CC BY 4.0 ou celle que l\'avis déclare, avec un lien vers l\'avis.',
			'profile.attributionRoadEvents' => 'Travaux et fermetures en France : DIR et Bison Futé, arrêtés de circulation DiaLog (DGITM), métropoles et départements (Lyon, Toulouse, Bordeaux, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d\'Armor, Sarthe), sous Licence Ouverte 2.0 ; Rennes Métropole et signalements des voyageurs de Lunaway, sous ODbL.',
			'profile.attributionRoadEventsAbroad' => 'Travaux et fermetures aux Pays-Bas : NDW, Nationaal Dataportaal Wegverkeer (données ouvertes) ; en Espagne : DGT, Dirección General de Tráfico (CC BY).',
			'profile.attributionDangerZones' => 'Zones de danger : listes officielles des radars (Sécurité routière en France, réutilisée selon le Code des relations entre le public et l\'administration ; Pologne et Luxembourg, CC0 ; Catalogne, licence ouverte de la Generalitat ; Norvège, NLOD) et OpenStreetMap (ODbL).',
			'units.kilobytes' => ({required Object n}) => '${n} ko',
			'units.megabytes' => ({required Object n}) => '${n} Mo',
			'languages.fr' => 'français',
			'languages.en' => 'anglais',
			'languages.de' => 'allemand',
			'languages.es' => 'espagnol',
			'languages.it' => 'italien',
			'languages.nl' => 'néerlandais',
			'translation.translate' => 'Traduire',
			'translation.translating' => 'Traduction en cours',
			'translation.showOriginal' => 'Voir l\'original',
			'translation.showTranslation' => 'Voir la traduction',
			'translation.from.fr' => 'Traduit automatiquement du français',
			'translation.from.en' => 'Traduit automatiquement de l\'anglais',
			'translation.from.de' => 'Traduit automatiquement de l\'allemand',
			'translation.from.es' => 'Traduit automatiquement de l\'espagnol',
			'translation.from.it' => 'Traduit automatiquement de l\'italien',
			'translation.from.nl' => 'Traduit automatiquement du néerlandais',
			'translation.from.unknown' => ({required Object language}) => 'Traduit automatiquement (langue d\'origine : ${language})',
			'translation.offline' => 'La traduction a besoin du réseau.',
			'translation.failedOffline' => 'Pas de connexion : le texte n\'a pas pu être traduit.',
			'translation.busy' => 'Le service de traduction est occupé. Réessayez plus tard.',
			'translation.unavailable' => 'La traduction n\'est pas disponible pour l\'instant.',
			'translation.gone' => 'Ce texte n\'est plus disponible.',
			'translation.unsupported' => 'Pas de traduction disponible pour cette langue.',
			'translation.autoReviews' => 'Traduire automatiquement les avis',
			'translation.autoReviewsHint' => 'Les avis écrits dans une autre langue sont traduits par le serveur de Lunaway, sans aucun service tiers.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			'locale.de' => 'Deutsch',
			'locale.es' => 'Español',
			'locale.it' => 'Italiano',
			'locale.nl' => 'Nederlands',
			'account.title' => 'Votre compte',
			'account.noneTitle' => 'Pas encore de compte',
			'account.noneBody' => 'La carte, la recherche et les favoris fonctionnent sans compte. Il se crée tout seul à votre première contribution (une note, une confirmation, une photo), sans e-mail ni mot de passe. Vos listes de favoris y sont alors rattachées.',
			'account.recover' => 'Retrouver mon compte',
			'account.memberSince' => ({required Object date}) => 'Membre depuis ${date}',
			'account.editPseudonym' => 'Modifier le pseudonyme',
			'account.pseudonymTitle' => 'Votre pseudonyme',
			'account.pseudonymHint' => 'Public : il accompagne vos avis et vos photos. De 3 à 32 caractères.',
			'account.pseudonymInvalid' => 'De 3 à 32 caractères, dont au moins deux lettres.',
			'account.pseudonymRefused' => 'Ce pseudonyme n\'est pas accepté : ni lien, ni coordonnées, ni mot injurieux, ni nom qui ferait passer le compte pour l\'équipe.',
			'account.pseudonymSaved' => 'Pseudonyme enregistré',
			'account.level' => ({required Object level}) => 'Niveau de confiance ${level}',
			'account.levelOpens.l0' => 'Vous pouvez noter les lieux, confirmer qu\'ils sont toujours là, signaler un problème et synchroniser vos favoris.',
			'account.levelOpens.l1' => 'Vous pouvez aussi écrire des avis, ajouter des photos et proposer des modifications de lieux.',
			'account.levelOpens.l2' => 'Vous pouvez aussi ajouter des lieux.',
			'account.levelOpens.l3' => 'Vos modifications de lieux s\'appliquent sans relecture.',
			'account.levelOpens.l4' => 'Vous participez à la modération.',
			'account.nextLevel' => ({required Object level}) => 'Pour le niveau ${level}',
			'account.levelTop' => 'Vous êtes au niveau le plus haut.',
			'account.requirement.age' => ({required Object needed, required Object current}) => 'Un compte d\'au moins ${needed} jours (${current} pour l\'instant)',
			'account.requirement.confirmations' => ({required Object needed, required Object current}) => '${needed} confirmations de lieux différents (${current} pour l\'instant)',
			'account.requirement.contributions' => ({required Object needed, required Object current}) => '${needed} contributions publiées (${current} pour l\'instant)',
			'account.requirement.activeDays' => ({required Object needed, required Object current}) => '${needed} jours d\'activité (${current} pour l\'instant)',
			'account.requirement.noRemoval' => 'Aucune contribution retirée par la modération',
			'account.requirement.sponsor' => 'Le parrainage d\'un membre de niveau 2',
			'account.requirement.nomination' => 'Une nomination par la modération',
			'account.requirement.administration' => 'Une désignation par l\'équipe de Lunaway',
			'account.orInstead' => ({required Object requirement}) => 'Ou bien ${requirement}',
			'account.recoveryNone' => 'Aucune carte de secours faite sur cet appareil. Sans elle, ce compte reste sur cet appareil : s\'il est perdu, le compte l\'est aussi.',
			'account.recoveryNoneAccount' => 'Pas encore de carte de secours pour ce compte. Sans elle, ce compte reste sur cet appareil : s\'il est perdu, le compte l\'est aussi.',
			'account.recoveryCreate' => 'Faire ma carte de secours',
			'account.recoveryMade' => ({required Object date}) => 'Faite le ${date}',
			'account.recoveryRemake' => 'Refaire',
			'account.recoveryRemakeHint' => 'Refaire la carte de secours',
			'account.contributions' => 'Mes contributions',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} contribution en attente d\'envoi', other: '${n} contributions en attente d\'envoi', ), 
			'account.mutedAuthors' => 'Auteurs masqués',
			'account.devices' => 'Appareils',
			'account.signOut' => 'Se déconnecter',
			'account.delete' => 'Supprimer mon compte',
			'account.signOutTitle' => 'Se déconnecter de cet appareil ?',
			'account.signOutBody' => 'La clé du compte est effacée de cet appareil. Pour revenir, il faudra votre carte de secours. Vos favoris restent ici.',
			'account.signOutNoCard' => 'Vous n\'avez pas fait de carte de secours sur cet appareil. Sans elle, ce compte sera perdu pour de bon.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Une contribution en attente d\'envoi ne partira pas.', other: '${n} contributions en attente d\'envoi ne partiront pas.', ), 
			'account.signedOut' => 'Déconnecté. Vos favoris restent sur cet appareil.',
			'account.lost' => 'Ce compte ne s\'ouvre plus sur cet appareil. Retrouvez-le avec votre carte de secours : Profil, Retrouver mon compte.',
			'account.lostAction' => 'Retrouver',
			'account.welcomeTitle' => 'Merci pour votre première contribution',
			'account.welcomeBody' => ({required Object name}) => 'Votre compte est créé, sous le pseudonyme « ${name} ». Pas d\'e-mail ni de mot de passe : une clé gardée sur cet appareil. Le pseudonyme se change dans le profil.',
			'account.welcomeCard' => 'Faites votre carte de secours pour retrouver ce compte sur un autre appareil.',
			'account.welcomeFavorites' => 'Vos listes de favoris sont maintenant gardées avec votre compte.',
			'recovery.title' => 'Carte de secours',
			'recovery.intro' => 'Un code qui ramène votre compte sur un nouvel appareil. Lunaway n\'en garde qu\'une empreinte, qui sert à le vérifier : le code lui-même ne peut plus jamais être affiché, et chaque nouvelle carte a un code différent.',
			'recovery.replaces' => 'Une nouvelle carte remplace la précédente : l\'ancien code cessera de marcher.',
			'recovery.replaceTitle' => ({required Object date}) => 'Remplacer la carte du ${date} ?',
			'recovery.replaceBody' => ({required Object date}) => 'La nouvelle carte aura un autre code. Celui de la carte du ${date} cessera de marcher dès maintenant. Il ne peut pas être réaffiché : Lunaway n\'en a gardé qu\'une empreinte.',
			'recovery.replaceKeep' => 'Garder l\'ancienne',
			'recovery.replaceConfirm' => 'Faire une nouvelle carte',
			'recovery.make' => 'Faire la carte',
			'recovery.codeLabel' => 'Votre code de secours',
			'recovery.shownOnce' => 'Ce code ne s\'affiche qu\'une fois. Notez-le, ou enregistrez l\'image, avant de fermer.',
			'recovery.saveImage' => 'Enregistrer l\'image',
			'recovery.done' => 'J\'ai noté le code',
			'recovery.doneTitle' => 'Vous avez bien gardé le code ?',
			'recovery.doneBody' => 'Une fois cette page fermée, il ne s\'affichera plus.',
			'recovery.keep' => 'Rester sur la page',
			'recovery.cardHeading' => 'Carte de secours Lunaway',
			'recovery.cardAccount' => ({required Object name}) => 'Compte : ${name}',
			'recovery.cardHow' => 'Pour retrouver le compte : Profil, Retrouver mon compte, puis saisissez ce code ou photographiez la carte.',
			'recovery.cardMade' => ({required Object date}) => 'Faite le ${date}',
			'recovery.cardWarning' => 'Ce code ouvre le compte : ne le confiez à personne.',
			'recovery.failed' => 'La carte n\'a pas pu être faite. Il faut une connexion.',
			'recovery.fileName' => 'carte-de-secours-lunaway',
			'recovery.step1' => 'Faites la carte : le code ne s\'affiche qu\'une fois.',
			'recovery.step2' => 'Enregistrez l\'image, imprimez-la, ou recopiez le code à la main.',
			'recovery.step3' => 'Rangez-la dans la boîte à gants, avec les papiers du véhicule.',
			'recover.title' => 'Retrouver mon compte',
			'recover.intro' => 'Tapez le code de votre carte de secours, ou lisez-le sur une photo de la carte.',
			'recover.field' => 'Code de secours',
			'recover.fieldHint' => '27 caractères, par groupes de quatre',
			'recover.remaining' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Encore ${n} caractère', other: 'Encore ${n} caractères', ), 
			'recover.invalid' => 'Ce code ne correspond à aucune carte : vérifiez chaque caractère.',
			'recover.valid' => 'Code complet',
			'recover.scan' => 'Lire la carte sur une photo',
			'recover.scanFile' => 'Choisir l\'image de la carte',
			'recover.reading' => 'Lecture de la carte',
			'recover.scanFailed' => 'Aucun code lisible sur cette image. Essayez une photo plus nette, la carte bien à plat.',
			'recover.revoke' => 'Mon ancien appareil est perdu ou volé : le déconnecter',
			'recover.revokeHint' => 'Tous vos autres appareils seront déconnectés.',
			'recover.submit' => 'Retrouver le compte',
			'recover.notFound' => 'Aucun compte n\'a ce code. Vérifiez la carte, ou faites-en une nouvelle depuis un appareil connecté.',
			'recover.tooMany' => 'Trop d\'essais pour l\'instant. Réessayez dans une heure.',
			'recover.done' => ({required Object name}) => 'Compte retrouvé : ${name}',
			'deletion.title' => 'Supprimer mon compte',
			'deletion.intro' => 'La suppression est immédiate et définitive.',
			'deletion.goneTitle' => 'Ce qui disparaît',
			'deletion.gone.identity' => 'Votre pseudonyme et les clés de vos appareils',
			'deletion.gone.sessions' => 'Vos sessions et votre code de secours',
			'deletion.gone.lists' => 'Vos listes de favoris synchronisées et vos auteurs masqués',
			'deletion.gone.photos' => 'Vos photos, vos notes sans texte et vos signalements',
			'deletion.gone.pending' => 'Vos propositions en attente de relecture',
			'deletion.keptTitle' => 'Ce qui reste, sans votre nom',
			'deletion.kept' => 'Vos avis écrits publiés, vos confirmations et vos modifications de lieux déjà appliquées restent, sans auteur : ils font partie de la carte des autres voyageurs.',
			'deletion.backups' => 'Les sauvegardes du serveur s\'effacent en 30 jours environ.',
			'deletion.device' => 'Sur cet appareil, vos favoris restent ; la clé du compte est effacée.',
			'deletion.web' => 'La suppression est aussi possible sur lunaway.net avec votre code de secours.',
			'deletion.webLink' => 'lunaway.net/account/delete',
			'deletion.confirmTitle' => 'Supprimer définitivement ?',
			'deletion.confirmBody' => ({required Object name}) => 'Le compte « ${name} » et tout ce qui est listé disparaissent maintenant. Personne ne pourra le rétablir.',
			_ => null,
		} ?? switch (path) {
			'deletion.confirmCheck' => 'Je comprends que c\'est définitif',
			'deletion.confirm' => 'Supprimer le compte',
			'deletion.done' => 'Compte supprimé',
			'deletion.failed' => 'Le compte n\'a pas pu être supprimé. Il faut une connexion.',
			'devices.title' => 'Appareils',
			'devices.intro' => 'Chaque appareil a sa propre clé. Retirez un appareil perdu, ou celui que vous n\'utilisez plus.',
			'devices.thisDevice' => 'Cet appareil',
			'devices.other' => 'Autre appareil',
			'devices.added' => ({required Object date}) => 'Ajouté le ${date}',
			'devices.lastUsed' => ({required Object when}) => 'Dernier usage ${when}',
			'devices.revoke' => 'Retirer',
			'devices.revokeTitle' => 'Retirer cet appareil ?',
			'devices.revokeBody' => 'Il sera déconnecté et ne pourra plus utiliser le compte.',
			'devices.revoked' => 'Appareil retiré',
			'devices.signOutOthers' => 'Déconnecter tous les autres appareils',
			'devices.signedOutOthers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, zero: 'Aucune autre session ouverte', one: '${n} session fermée', other: '${n} sessions fermées', ), 
			'devices.error' => 'Les appareils n\'ont pas pu s\'afficher. Il faut du réseau.',
			'muted.title' => 'Auteurs masqués',
			'muted.empty' => 'Personne n\'est masqué',
			'muted.emptyHint' => 'Pour masquer quelqu\'un, ouvrez le menu d\'un de ses avis ou d\'une de ses photos. Le masquage ne vaut que pour vous.',
			'muted.unmute' => 'Ne plus masquer',
			'muted.unmuted' => ({required Object name}) => 'Les contributions de ${name} s\'afficheront de nouveau',
			'mine.title' => 'Mes contributions',
			'mine.pending' => 'En attente d\'envoi',
			'mine.pendingHint' => 'Elles partent dès que le réseau revient.',
			'mine.sendNow' => 'Envoyer maintenant',
			'mine.retry' => 'Réessayer',
			'mine.discard' => 'Abandonner',
			'mine.discardTitle' => 'Abandonner cette contribution ?',
			'mine.discardBody' => 'Elle ne sera pas envoyée.',
			'mine.reviews' => 'Avis et notes',
			'mine.photos' => 'Photos',
			'mine.confirmations' => 'Confirmations',
			'mine.issues' => 'Problèmes signalés',
			'mine.places' => 'Lieux ajoutés et modifications',
			'mine.empty' => 'Rien pour l\'instant',
			'mine.emptyHint' => 'Noter un lieu ou confirmer qu\'il est toujours là, c\'est déjà une contribution.',
			'mine.latest' => ({required Object shown, required Object total}) => 'Les ${shown} contributions les plus récentes, sur ${total}',
			'mine.error' => 'Vos contributions n\'ont pas pu s\'afficher. Il faut du réseau.',
			'mine.deleteTitle' => 'Supprimer cette contribution ?',
			'mine.deleteBody' => 'Elle disparaît de Lunaway.',
			'mine.deleteApplied' => 'Ce lieu fait déjà partie de la carte : il y reste, sans votre nom.',
			'mine.deleted' => 'Contribution supprimée',
			'mine.ratingOnly' => 'Note seule',
			'mine.status.published' => 'Publié',
			'mine.status.pending' => 'En relecture',
			'mine.status.hidden' => 'Masqué après des signalements',
			'mine.status.removed' => 'Retiré par la modération',
			'mine.submission.proposed' => 'En attente de relecture',
			'mine.submission.accepted' => 'Accepté',
			'mine.submission.applied' => 'Sur la carte',
			'mine.submission.rejected' => 'Refusé',
			'mine.submission.withdrawn' => 'Retiré',
			'mine.newPlace' => 'Nouveau lieu',
			'mine.edit' => 'Modification',
			'mine.aPlace' => 'Un lieu',
			'mine.newVendingMachine' => 'Nouveau distributeur',
			'mine.poiConfirmations' => 'Commerces et services confirmés',
			'mine.aPoi' => 'Un commerce ou service',
			'outbox.kind.rate' => ({required Object stars}) => 'Note de ${stars} sur 5',
			'outbox.kind.review' => 'Avis',
			'outbox.kind.deleteReview' => 'Suppression d\'un avis',
			'outbox.kind.confirm' => ({required Object status}) => 'Toujours là ? ${status}',
			'outbox.kind.deleteConfirmation' => 'Suppression d\'une confirmation',
			'outbox.kind.reportIssue' => ({required Object kind}) => 'Problème signalé : ${kind}',
			'outbox.kind.deleteIssueReport' => 'Suppression d\'un signalement',
			'outbox.kind.reportContent' => 'Signalement à la modération',
			'outbox.kind.addPlace' => ({required Object name}) => 'Nouveau lieu : ${name}',
			'outbox.kind.editPlace' => 'Modification d\'un lieu',
			'outbox.kind.deletePlaceSubmission' => 'Retrait d\'un lieu proposé',
			'outbox.kind.photo' => 'Photo',
			'outbox.kind.deletePhoto' => 'Suppression d\'une photo',
			'outbox.kind.mute' => 'Masquer un auteur',
			'outbox.kind.unmute' => 'Ne plus masquer un auteur',
			'outbox.kind.poiThere' => 'Toujours là : un commerce ou service',
			'outbox.kind.poiGone' => 'Plus là : un commerce ou service',
			'outbox.kind.addVendingMachine' => 'Nouveau distributeur',
			'outbox.kind.deletePoiConfirmation' => 'Suppression d\'une réponse sur un commerce ou service',
			'outbox.kind.reportRoadEvent' => ({required Object kind}) => 'Signalement sur la route : ${kind}',
			'outbox.kind.clearRoadEvent' => 'Fin d\'un signalement sur la route',
			'outbox.waiting' => 'En attente du réseau',
			'outbox.sending' => 'Envoi en cours',
			'outbox.error.forbidden' => 'Refusé : votre niveau ne le permet pas encore.',
			'outbox.error.notFound' => 'Refusé : le lieu ou le contenu n\'existe plus.',
			'outbox.error.invalid' => 'Refusé : vérifiez le texte (longueur, liens, coordonnées).',
			'outbox.error.unreadablePhoto' => 'Photo refusée : illisible, ou déjà envoyée.',
			'outbox.error.photoTooLarge' => 'Photo refusée : trop lourde.',
			'outbox.error.placeRefused' => 'Le nouveau lieu de cette photo a été refusé.',
			'outbox.error.fileLost' => 'La photo n\'est plus sur l\'appareil.',
			'outbox.error.otherAccount' => 'Préparée pour un autre compte : elle ne sera pas envoyée.',
			'outbox.error.other' => 'Refusé par le serveur.',
			'outbox.error.duplicate' => 'Refusé : le même distributeur est déjà indiqué à moins de 25 m.',
			'outbox.sent' => 'Merci, c\'est envoyé',
			'outbox.queued' => 'Pas de réseau : envoi dès qu\'il revient',
			'outbox.refused' => ({required Object reason}) => 'Pas envoyé. ${reason}',
			'placement.title' => 'Placez le lieu',
			'placement.hint' => 'Déplacez la carte : la croix marque l\'endroit exact.',
			'placement.confirm' => 'Valider cet emplacement',
			'placement.duplicate' => ({required Object name, required Object distance}) => 'Il y a déjà « ${name} » à ${distance} : est-ce le même endroit ?',
			'placement.same' => 'Oui, ouvrir sa fiche',
			'placement.notSame' => 'Non, c\'est un autre lieu',
			'contribute.yourRating' => 'Votre note',
			'contribute.rateHint' => 'Touchez une étoile pour noter',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Noter ${n} étoile', other: 'Noter ${n} étoiles', ), 
			'contribute.writeReview' => 'Écrire un avis',
			'contribute.editReview' => 'Modifier votre avis',
			'contribute.deleteReview' => 'Supprimer votre avis',
			'contribute.deleteReviewTitle' => 'Supprimer votre avis ?',
			'contribute.deleteReviewBody' => 'Le texte et la note disparaissent de la fiche.',
			'contribute.deleteRating' => 'Retirer votre note',
			'contribute.deleteRatingTitle' => 'Retirer votre note ?',
			'contribute.deleteRatingBody' => 'Votre note disparaît de la fiche.',
			'contribute.pendingSend' => 'En attente d\'envoi',
			'contribute.statusPending' => 'En relecture : visible par vous uniquement pour l\'instant',
			'contribute.statusHidden' => 'Masqué après des signalements, en attente d\'un modérateur',
			'contribute.statusRemoved' => 'Retiré par la modération',
			'contribute.addPhoto' => 'Ajouter une photo',
			'contribute.firstPhoto' => 'Ajouter la première photo',
			'contribute.stillThere' => 'Toujours là ?',
			'contribute.more' => 'Plus d\'actions',
			'contribute.reportIssue' => 'Signaler un problème',
			'contribute.proposeEdit' => 'Proposer une modification',
			'contribute.editPlace' => 'Modifier le lieu',
			'contribute.reportPlace' => 'Signaler ce lieu à la modération',
			'contribute.toVerifyTitle' => 'À vérifier',
			'contribute.toVerifyBody' => 'Lieu ajouté par la communauté, en attente de deux confirmations. Vous le connaissez ? Confirmez-le.',
			'contribute.issuesTitle' => 'Signalements des 30 derniers jours',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlaceHere' => 'Créer un lieu ici',
			'contribute.addPlaceHint' => 'L\'endroit choisi sous la croix.',
			'confirmSheet.title' => 'Toujours là ?',
			'confirmSheet.body' => 'Vous y êtes passé récemment ? Votre réponse montre aux prochains voyageurs que la fiche est à jour. Aucune position n\'est envoyée.',
			'confirmSheet.stillOk' => 'Oui, comme décrit',
			'confirmSheet.closed' => 'Fermé',
			'confirmSheet.changed' => 'Changé',
			'confirmSheet.closedHint' => 'N\'accueille plus de voyageurs',
			'confirmSheet.changedHint' => 'Existe, mais quelque chose a changé',
			'confirmSheet.note' => 'Une précision (facultative)',
			'confirmSheet.noteHint' => 'Par exemple : barrière de hauteur posée, borne déplacée',
			'confirmSheet.status.stillOk' => 'toujours là',
			'confirmSheet.status.closed' => 'fermé',
			'confirmSheet.status.changed' => 'changé',
			'issueSheet.title' => 'Signaler un problème',
			'issueSheet.body' => 'Votre signalement compte dans l\'avertissement affiché sur la fiche. Votre précision ne va qu\'aux modérateurs.',
			'issueSheet.kind.nightBan' => 'Nuit interdite désormais',
			'issueSheet.kind.serviceBroken' => 'Service en panne',
			'issueSheet.kind.noAccess' => 'Accès impossible',
			'issueSheet.kind.danger' => 'Danger',
			'issueSheet.hint.nightBan' => 'Panneau, arrêté municipal, passage de la police',
			'issueSheet.hint.serviceBroken' => 'Borne, eau, vidange ou électricité hors service',
			'issueSheet.hint.noAccess' => 'Barrière, travaux, route fermée',
			'issueSheet.hint.danger' => 'Vol, agression, terrain instable',
			'issueSheet.note' => 'Une précision (facultative)',
			'issueSheet.send' => 'Signaler',
			'reportSheet.review' => 'Signaler cet avis',
			'reportSheet.photo' => 'Signaler cette photo',
			'reportSheet.place' => 'Signaler ce lieu',
			'reportSheet.body' => 'Les modérateurs le liront. L\'auteur ne saura pas qui l\'a signalé.',
			'reportSheet.reason.spam' => 'Publicité ou répétition',
			'reportSheet.reason.offensive' => 'Insultant, haineux ou choquant',
			'reportSheet.reason.wrong' => 'Faux ou trompeur',
			'reportSheet.reason.privacy' => 'Montre ou nomme une personne, une plaque, une adresse privée',
			'reportSheet.reason.other' => 'Autre raison',
			'reportSheet.note' => 'Dites-en plus (facultatif)',
			'reportSheet.noteOther' => 'Dites ce qui ne va pas',
			'reportSheet.sent' => 'Merci, les modérateurs vont regarder',
			'reportSheet.mute' => ({required Object name}) => 'Masquer les avis et photos de ${name}',
			'reportSheet.muteAuthor' => 'Masquer cet auteur',
			'reportSheet.muteTitle' => ({required Object name}) => 'Masquer ${name} ?',
			'reportSheet.muteBody' => 'Ses avis et ses photos ne s\'afficheront plus pour vous. Vous pourrez revenir sur ce choix dans le profil.',
			'reportSheet.muted' => ({required Object name}) => '${name} est masqué',
			'reportSheet.deletePhoto' => 'Supprimer ma photo',
			'reportSheet.deletePhotoTitle' => 'Supprimer cette photo ?',
			'reportSheet.deletePhotoBody' => 'Elle disparaît de la fiche et de nos serveurs.',
			'reviewSheet.titleNew' => 'Votre avis',
			'reviewSheet.titleEdit' => 'Modifier votre avis',
			'reviewSheet.starsRequired' => 'Choisissez une note de 1 à 5',
			'reviewSheet.text' => 'Votre avis',
			'reviewSheet.textHint' => 'Le calme, l\'accueil, la place pour manœuvrer, ce qui vous a servi',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Encore ${n} caractère au moins', other: 'Encore ${n} caractères au moins', ), 
			'reviewSheet.visited' => 'Date du séjour',
			'reviewSheet.visitedNone' => 'Non précisée',
			'reviewSheet.vehicle' => 'Votre véhicule',
			'reviewSheet.vehicleNone' => 'Ne pas préciser',
			'reviewSheet.licence' => 'Publié sous licence CC BY 4.0, avec votre pseudonyme. La date du séjour est facultative : réunies, les dates de vos avis peuvent révéler votre parcours.',
			'reviewSheet.publish' => 'Publier l\'avis',
			'gate.review' => 'Avis écrits : à partir du niveau 1',
			'gate.photo' => 'Photos : à partir du niveau 1',
			'gate.addPlace' => 'Ajout de lieux : à partir du niveau 2',
			'gate.edit' => 'Propositions de modification : à partir du niveau 1',
			'gate.why' => 'Les niveaux protègent la carte des abus. Ils viennent avec le temps et les contributions, sans rien à acheter.',
			'gate.yourLevel' => ({required Object level}) => 'Votre niveau : ${level}',
			'gate.noAccount' => 'Pas encore de compte : un compte commence au niveau 0.',
			'gate.later' => ({required Object level}) => 'Le niveau ${level} vient après les précédents, avec le temps et les contributions publiées.',
			'gate.meanwhile' => 'En attendant, vous pouvez noter les lieux, confirmer qu\'ils sont toujours là ou signaler un problème.',
			'photoFlow.title' => 'Ajouter une photo',
			'photoFlow.camera' => 'Prendre une photo',
			'photoFlow.gallery' => 'Choisir dans la galerie',
			'photoFlow.preparing' => 'Préparation de la photo',
			'photoFlow.licence' => 'Publiée sous licence CC BY 4.0, avec votre pseudonyme. Évitez les visages et les plaques d\'immatriculation.',
			'photoFlow.stripped' => 'La position et les données de l\'appareil sont retirées avant l\'envoi.',
			'photoFlow.send' => 'Envoyer la photo',
			'photoFlow.unreadable' => 'Cette image ne peut pas être lue sur cet appareil. Essayez une photo JPEG ou PNG.',
			'photoFlow.sending' => ({required Object percent}) => 'Envoi ${percent} %',
			'photoFlow.pending' => 'Photo en attente d\'envoi',
			'placeForm.addTitle' => 'Ajouter un lieu',
			'placeForm.editTitle' => 'Modifier le lieu',
			'placeForm.proposeTitle' => 'Proposer une modification',
			'placeForm.position' => 'Position sur la carte',
			'placeForm.kind' => 'Type de lieu',
			'placeForm.kindRequired' => 'Choisissez un type de lieu',
			'placeForm.name' => 'Nom',
			'placeForm.nameHint' => 'Le nom affiché sur place, ou une description courte',
			'placeForm.nameInvalid' => 'De 2 à 120 caractères',
			'placeForm.night' => 'Nuit sur place',
			'placeForm.services' => 'Services sur place',
			'placeForm.description' => 'Description',
			'placeForm.descriptionHint' => 'Ce qui aide à trouver et à choisir le lieu',
			'placeForm.details' => 'Précisions',
			'placeForm.priceNight' => 'Prix de la nuit (€)',
			'placeForm.priceServices' => 'Prix des services (€)',
			'placeForm.maxHeight' => 'Hauteur maximale (m)',
			'placeForm.capacity' => 'Emplacements',
			'placeForm.website' => 'Site web',
			'placeForm.phone' => 'Téléphone',
			'placeForm.photo' => 'Photo (facultative)',
			'placeForm.photoReady' => 'Photo prête',
			'placeForm.removePhoto' => 'Retirer la photo',
			'placeForm.toVerify' => 'Le lieu apparaîtra « à vérifier » jusqu\'à ce que deux autres voyageurs le confirment.',
			'placeForm.licence' => 'Les lieux sont publiés sous licence ODbL, crédités aux contributeurs de Lunaway.',
			'placeForm.moderated' => 'Un site web ou un téléphone passe par un modérateur avant d\'être publié.',
			'placeForm.direct' => 'Votre niveau applique la modification tout de suite.',
			'placeForm.proposal' => 'Un modérateur relira votre proposition avant qu\'elle s\'applique.',
			'placeForm.submitAdd' => 'Ajouter le lieu',
			'placeForm.submitEdit' => 'Enregistrer la modification',
			'placeForm.submitPropose' => 'Envoyer la proposition',
			'placeForm.nothingChanged' => 'Rien n\'a changé',
			'placeForm.invalidNumber' => 'Un nombre, s\'il vous plaît',
			'placeForm.invalidWebsite' => 'Une adresse qui commence par http:// ou https://',
			'placeForm.added' => 'Merci : le lieu arrive sur la carte dans un instant',
			'placeForm.proposed' => 'Merci : votre proposition part en relecture',
			'favoritesSync.local' => 'Sur cet appareil seulement',
			'favoritesSync.action' => 'Synchroniser',
			'favoritesSync.syncing' => 'Synchronisation en cours',
			'favoritesSync.synced' => ({required Object when}) => 'Gardés avec votre compte, synchronisés ${when}',
			'favoritesSync.failed' => 'Synchronisation impossible pour l\'instant',
			'favoritesSync.title' => 'Synchroniser vos favoris ?',
			'favoritesSync.body' => 'Vos listes seront gardées avec un compte Lunaway, sans e-mail ni mot de passe, pour les retrouver sur un autre appareil. Le compte se crée maintenant.',
			'favoritesSync.confirm' => 'Créer le compte et synchroniser',
			'poi.category.groceries' => 'Courses',
			'poi.category.vending' => 'Distributeurs alimentaires',
			'poi.category.water' => 'Eau et vidange',
			'poi.category.fuel' => 'Carburant et énergie',
			'poi.category.health' => 'Santé',
			'poi.category.services' => 'Services',
			'poi.kind.supermarket' => 'Supermarché',
			'poi.kind.convenience' => 'Supérette',
			'poi.kind.bakery' => 'Boulangerie',
			'poi.kind.butcher' => 'Boucherie',
			'poi.kind.greengrocer' => 'Primeur',
			'poi.kind.farmShop' => 'Vente à la ferme',
			'poi.kind.marketplace' => 'Marché',
			'poi.kind.vendingPizza' => 'Distributeur de pizzas',
			'poi.kind.vendingBread' => 'Distributeur de pain',
			'poi.kind.vendingFarmProducts' => 'Distributeur de produits fermiers',
			'poi.kind.vendingEggsMilk' => 'Distributeur d\'œufs ou de lait',
			'poi.kind.vendingIce' => 'Distributeur de glaçons',
			'poi.kind.vendingOther' => 'Distributeur alimentaire',
			'poi.kind.drinkingWater' => 'Eau potable',
			'poi.kind.waterPoint' => 'Point d\'eau',
			'poi.kind.dumpStation' => 'Borne de vidange',
			'poi.kind.toilets' => 'Toilettes',
			'poi.kind.shower' => 'Douches',
			'poi.kind.fuelStation' => 'Station-service',
			'poi.kind.evCharging' => 'Borne de recharge',
			'poi.kind.gasBottles' => 'Bouteilles de gaz',
			'poi.kind.pharmacy' => 'Pharmacie',
			'poi.kind.doctor' => 'Médecin',
			'poi.kind.hospital' => 'Hôpital',
			'poi.kind.veterinary' => 'Vétérinaire',
			'poi.kind.laundry' => 'Laverie',
			'poi.kind.atm' => 'Distributeur de billets',
			'poi.kind.postOffice' => 'Bureau de poste',
			'poi.kind.touristOffice' => 'Office de tourisme',
			'poi.kind.recyclingCentre' => 'Déchèterie',
			'poi.kind.carRepair' => 'Garage',
			'poi.kind.carWash' => 'Lavage',
			'poi.kind.motorhomeShop' => 'Concession et atelier camping-car',
			'poi.chipsLabel' => 'Commerces et services autour',
			'poi.openNow' => 'Ouvert maintenant',
			'poi.vendingSells.pizza' => 'Pizza',
			'poi.vendingSells.bread' => 'Pain',
			'poi.vendingSells.farmProducts' => 'Produits de la ferme',
			'poi.vendingSells.eggsMilk' => 'Œufs et lait',
			'poi.vendingSells.ice' => 'Glaçons',
			'poi.vendingAll' => 'Tous les distributeurs alimentaires',
			'poi.vendingMenu' => 'Ce que vendent les distributeurs',
			'poi.vendingChip.pizza' => 'Distributeurs de pizza',
			'poi.vendingChip.bread' => 'Distributeurs de pain',
			'poi.vendingChip.farmProducts' => 'Distributeurs de produits de la ferme',
			'poi.vendingChip.eggsMilk' => 'Distributeurs d\'œufs et de lait',
			'poi.vendingChip.ice' => 'Distributeurs de glaçons',
			'poi.alwaysOpen' => 'Ouvert jour et nuit',
			'poi.hoursUnknown' => 'Horaires inconnus',
			'poi.maybeClosed' => 'Fermé selon l\'annuaire officiel des établissements de santé (FINESS).',
			'poi.maybeClosedSince' => ({required Object date}) => 'Indiqué fermé par FINESS depuis le ${date} : il a peut-être fermé définitivement.',
			'poi.seasonal' => 'Saisonnier : il peut être fermé en hiver.',
			'poi.fee' => 'Payant',
			'poi.free' => 'Gratuit',
			'poi.stillThereTitle' => 'Toujours là ?',
			'poi.stillThereHint' => 'Vu récemment ? Votre réponse aide les prochains voyageurs. Aucune position n\'est envoyée.',
			'poi.stillThere' => 'Toujours là',
			'poi.gone' => 'N\'existe plus',
			'poi.lastConfirmed' => ({required Object when}) => 'Confirmé présent ${when}',
			'poi.checkedOn' => ({required Object date}) => 'Vérifié sur place le ${date}',
			'poi.thanksThere' => 'Merci, c\'est noté : toujours là.',
			'poi.thanksGone' => 'Merci, c\'est noté : n\'existe plus.',
			'poi.fuelPrices' => 'Prix des carburants',
			'poi.perLitre' => ({required Object price}) => '${price}/L',
			'poi.priceUpdated' => ({required Object when}) => 'Prix mis à jour ${when}',
			'poi.feedRead' => ({required Object when}) => 'Prix relevés ${when}',
			'poi.shortageTemporary' => 'En rupture pour l\'instant',
			'poi.shortageDefinitive' => 'N\'en vend plus',
			'poi.selfService24h' => 'Paiement par carte 24 h/24',
			'poi.highway' => 'Sur autoroute',
			'poi.lpgYes' => 'Vend du GPL',
			'poi.fuel.diesel' => 'Gazole',
			'poi.fuel.sp95' => 'SP95',
			'poi.fuel.e10' => 'SP95-E10',
			'poi.fuel.sp98' => 'SP98',
			'poi.fuel.e85' => 'E85',
			'poi.fuel.lpg' => 'GPL',
			'poi.products' => 'Vend',
			'poi.paymentTitle' => 'Paiement',
			'poi.product.pizza' => 'Pizzas',
			'poi.product.bread' => 'Pain',
			'poi.product.eggs' => 'Œufs',
			'poi.product.milk' => 'Lait',
			'poi.product.cheese' => 'Fromage',
			'poi.product.meat' => 'Viande',
			'poi.product.vegetables' => 'Légumes',
			'poi.product.fruit' => 'Fruits',
			'poi.product.honey' => 'Miel',
			'poi.product.ice' => 'Glaçons',
			'poi.product.potatoes' => 'Pommes de terre',
			'poi.product.food' => 'Alimentation',
			'poi.payment.cash' => 'Espèces',
			'poi.payment.coins' => 'Pièces',
			'poi.payment.notes' => 'Billets',
			'poi.payment.cards' => 'Carte',
			'poi.payment.contactless' => 'Sans contact',
			'poi.payment.app' => 'Application',
			'poi.justNow' => 'à l\'instant',
			'poi.minutesAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a ${n} minute', other: 'il y a ${n} minutes', ), 
			'poi.hoursAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a ${n} heure', other: 'il y a ${n} heures', ), 
			'poi.readOffline' => ({required Object when}) => 'Relevé ${when} : pas de réseau pour l\'actualiser',
			'poi.readStale' => ({required Object when}) => 'Relevé ${when} : l\'actualisation n\'a pas abouti pour l\'instant.',
			'poi.goneTitle' => 'Ce point n\'est plus sur la carte',
			'poi.goneHint' => 'Des voyageurs l\'ont dit disparu, ou la dernière mise à jour l\'a retiré.',
			'poi.loadError' => 'Le détail n\'a pas pu s\'afficher. Ce que la carte en sait est au-dessus.',
			'poi.around' => 'Autour de ce lieu',
			'poi.aroundEmpty' => 'Aucun commerce ni service connu autour.',
			'poi.aroundError' => 'Les commerces et services autour n\'ont pas pu s\'afficher.',
			'poi.aroundOffline' => 'Pas de réseau : les commerces et services autour s\'afficheront avec une connexion.',
			'poi.onSite' => 'Sur place',
			'poi.backTo' => ({required Object name}) => 'Retour à ${name}',
			'poi.backToPlace' => 'Retour au lieu',
			'poi.linkError' => 'Ce commerce ou service n\'a pas pu être ouvert : pas de réseau, ou il n\'est plus sur la carte.',
			'poi.searchSection' => 'Commerces et services',
			'poi.searching' => 'Recherche des commerces et services',
			'poi.searchOffline' => 'Les commerces et services se cherchent en ligne : pas de réseau maintenant.',
			'poi.add.title' => 'Un distributeur ici ?',
			'poi.add.hint' => 'Choisissez ce qu\'il vend : il s\'ajoute à la carte de tous les voyageurs.',
			'poi.add.pizza' => 'Pizzas',
			'poi.add.bread' => 'Pain',
			'poi.add.other' => 'Autre',
			'poi.add.gate' => 'Ajouter un distributeur',
			'poi.add.sent' => 'Merci : le distributeur apparaît sur la carte d\'ici quelques minutes.',
			'poi.add.duplicateTitle' => 'Déjà sur la carte',
			'poi.add.duplicateBody' => 'Un distributeur du même type est déjà indiqué à moins de 25 m. Est-il toujours là ?',
			'poi.add.duplicateThere' => 'Oui, toujours là',
			'poi.add.duplicateGone' => 'Non, il n\'y est plus',
			'poi.cheapest.title' => 'Moins cher autour de moi',
			'poi.cheapest.show' => 'Moins cher autour',
			'poi.cheapest.zoomIn' => 'Zoomez pour comparer les prix des stations.',
			'poi.cheapest.none' => 'Aucune station de la carte ne vend ce carburant.',
			'poi.cheapest.noneHint' => 'Déplacez la carte ou choisissez un autre carburant.',
			'poi.cheapest.error' => 'Les prix des stations n\'ont pas pu s\'afficher.',
			'poi.trend.title' => ({required Object fuel}) => '${fuel} : prix des derniers jours',
			'poi.trend.none' => 'Lunaway n\'a pas encore vu de prix de ce carburant ici.',
			'poi.trend.failed' => 'Les prix des derniers jours n\'ont pas pu être lus pour l\'instant.',
			'poi.trend.week' => '7 derniers jours :',
			'poi.trend.month' => '30 derniers jours :',
			'poi.trend.range' => ({required Object low, required Object high}) => 'de ${low} à ${high}',
			'poi.trend.span' => ({required Object range, required Object move}) => '${range}, ${move}',
			'poi.trend.oneDay' => 'un seul jour relevé',
			'poi.trend.steady' => 'stable',
			'poi.trend.down' => ({required Object amount}) => 'en baisse de ${amount}',
			'poi.trend.up' => ({required Object amount}) => 'en hausse de ${amount}',
			'poi.trend.since' => ({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} jour relevé depuis le ${date}, tel que Lunaway lit le flux ; un jour sans relevé reste vide', other: '${n} jours relevés depuis le ${date}, tel que Lunaway lit le flux ; un jour sans relevé reste vide', ), 
			'offlineMaps.title' => 'Cartes hors ligne',
			'offlineMaps.intro' => 'Avant de partir, gardez une région sur l\'appareil : ses lieux pour chercher et choisir, sa carte pour voir les rues sans réseau.',
			'offlineMaps.webTitle' => 'Les cartes hors ligne sont dans l\'application',
			'offlineMaps.web' => 'Les applications Android et iOS gardent des régions pour la route. Dans un navigateur, la carte a besoin du réseau.',
			'offlineMaps.desktopTitle' => 'Les cartes hors ligne sont sur le téléphone',
			'offlineMaps.desktop' => 'Les applications Android et iOS gardent des régions pour la route. Sur ordinateur, la carte a besoin du réseau.',
			'offlineMaps.unreadable' => 'Les cartes hors ligne de cet appareil n\'ont pas pu s\'afficher.',
			'offlineMaps.none' => 'Aucune région sur cet appareil pour l\'instant.',
			'offlineMaps.used' => ({required Object size}) => 'Espace utilisé : ${size}',
			'offlineMaps.downloads' => 'Téléchargements',
			'offlineMaps.installed' => 'Sur cet appareil',
			'offlineMaps.suggested' => 'Suggérées',
			'offlineMaps.here' => 'Là où vous êtes',
			'offlineMaps.favoritesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} favori dans cette région', other: '${n} favoris dans cette région', ), 
			'offlineMaps.france' => 'France',
			'offlineMaps.overseas' => 'Outre-mer',
			'offlineMaps.countries' => 'Pays',
			'offlineMaps.downloadNamed' => ({required Object name, required Object size}) => 'Télécharger ${name}, ${size}',
			'offlineMaps.pause' => 'Mettre en pause',
			'offlineMaps.resume' => 'Reprendre',
			'offlineMaps.cancel' => 'Arrêter et effacer le téléchargement',
			'offlineMaps.waiting' => 'En attente de son tour',
			'offlineMaps.progress' => ({required Object done, required Object total}) => '${done} sur ${total}',
			'offlineMaps.paused' => ({required Object done, required Object total}) => 'En pause à ${done} sur ${total}',
			'offlineMaps.verifying' => 'Vérification du fichier',
			'offlineMaps.failedNetwork' => 'Interrompu : pas de réseau. Il reprendra là où il s\'est arrêté dès que le réseau reviendra.',
			'offlineMaps.failedServer' => 'Le serveur a envoyé autre chose que la carte. Réessayez plus tard.',
			'offlineMaps.failedCorrupt' => 'Le fichier est arrivé abîmé et a été effacé. Réessayez.',
			'offlineMaps.failedStorage' => 'Plus assez de place sur l\'appareil. Libérez de l\'espace, puis réessayez.',
			'offlineMaps.keepOpen' => 'Gardez l\'application ouverte pendant le téléchargement : il s\'interrompt quand elle passe en arrière-plan et reprend quand vous y revenez.',
			'offlineMaps.dataOf' => ({required Object date}) => 'données du ${date}',
			'offlineMaps.update' => ({required Object size}) => 'Mettre à jour, ${size}',
			'offlineMaps.deleteNamed' => ({required Object name}) => 'Supprimer ${name}',
			'offlineMaps.deleteTitle' => ({required Object name}) => 'Supprimer ${name} de cet appareil ?',
			'offlineMaps.deleteBody' => 'Elle ne s\'affichera plus sans réseau. Vous pourrez la télécharger de nouveau.',
			'offlineMaps.listOffline' => 'La liste des régions demande du réseau.',
			'offlineMaps.listCopy' => 'Liste gardée de la dernière connexion.',
			'offlineMaps.entryHint' => 'Pour voyager sans réseau',
			'offlineMaps.entryCount' => ({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Cartes : ${n} région, ${size}', other: 'Cartes : ${n} régions, ${size}', ), 
			'offlineMaps.noticePack' => ({required Object name}) => 'Hors ligne : carte téléchargée, ${name}',
			'offlineMaps.noticeOutside' => 'Hors ligne : cette zone n\'est pas téléchargée',
			'offlineMaps.noticePlacesOnly' => 'Hors ligne : lieux sur l\'appareil, carte de cette zone à télécharger',
			'offlineMaps.noticeNone' => 'Hors ligne : téléchargez une région pour la prochaine fois',
			'offlineMaps.noticeOnline' => 'Hors ligne : la carte a besoin du réseau',
			'offlineMaps.placesTitle' => 'Lieux',
			'offlineMaps.placesHint' => 'Quelques mégaoctets par région : la liste, la recherche, les fiches et les filtres marchent sans réseau.',
			'offlineMaps.mapsTitle' => 'Cartes',
			'offlineMaps.mapsHint' => 'Toutes les rues, quelques centaines de mégaoctets par région : la carte s\'affiche sans réseau.',
			'offlineMaps.entryPlaces' => ({required Object names}) => 'Lieux : ${names}',
			'offlineMaps.entryPlacesCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Lieux : ${n} région', other: 'Lieux : ${n} régions', ), 
			'regions.pickerTitle' => 'Quels lieux garder sur cet appareil ?',
			'regions.pickerIntro' => 'Chaque région se télécharge une fois, puis se met à jour par petits morceaux. Vous pourrez en ajouter ou en retirer plus tard dans Cartes hors ligne.',
			'regions.nearYou' => ({required Object name}) => 'Près de vous : ${name}',
			'regions.findMine' => 'Trouver ma région',
			'regions.locating' => 'Recherche de votre région',
			'regions.notCovered' => 'Pas encore de région Lunaway autour de vous',
			'regions.wholeFrance' => 'Toute la France',
			'regions.showFrance' => 'Afficher les régions de France',
			'regions.hideFrance' => 'Masquer les régions de France',
			'regions.packInfo' => ({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${count} lieu, ${size}', other: '${count} lieux, ${size}', ), 
			'regions.noPack' => 'Sans paquet : lieux reçus avec les mises à jour, taille inconnue',
			'regions.download' => ({required Object size}) => 'Télécharger, ${size}',
			'regions.unavailable' => 'Le serveur ne propose pas encore de régions : Lunaway garde toute la France.',
			'regions.listFailed' => 'La liste des régions demande du réseau.',
			'regions.choose' => 'Choisir les régions',
			'regions.noneKept' => 'Aucune région gardée : la carte n\'a aucun lieu hors connexion.',
			'regions.change' => 'Ajouter ou retirer des régions',
			'regions.removeNamed' => ({required Object name}) => 'Retirer ${name}',
			'regions.removed' => ({required Object name}) => '${name} : lieux retirés de cet appareil',
			'regions.downloading' => ({required Object done, required Object total}) => 'Téléchargement, ${done} sur ${total}',
			'regions.updating' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Mise à jour, ${count} lieu', other: 'Mise à jour, ${count} lieux', ), 
			'regions.waiting' => 'en attente de son téléchargement',
			'regions.downloadingNamed' => ({required Object name}) => 'Téléchargement des lieux : ${name}',
			'regions.updated' => ({required Object when}) => 'mis à jour ${when}',
			'regions.offerTitle' => ({required Object name}) => '${name} : garder ses lieux hors connexion ?',
			'regions.downloadThis' => 'Télécharger cette région',
			'regions.notHere' => ({required Object name}) => '${name} n\'est pas sur cet appareil',
			'regions.updatesOnMobile' => 'Mettre à jour avec les données mobiles',
			'regions.updatesOnMobileHint' => 'Sinon, les régions déjà téléchargées se mettent à jour en Wi-Fi. Un nouveau téléchargement passe par tout réseau.',
			'roadReport.actionHint' => 'Signaler un problème sur la route',
			'roadReport.title' => 'Que voyez-vous sur la route ?',
			'roadReport.intro' => 'Votre signalement prévient les autres voyageurs. Quand deux comptes de confiance signalent la même chose, les itinéraires l\'évitent. Les contrôles de police ne se signalent pas.',
			'roadReport.kinds.closure' => 'Route fermée',
			'roadReport.kinds.works' => 'Travaux',
			'roadReport.kinds.narrowPassage' => 'Passage étroit',
			'roadReport.kinds.lowClearance' => 'Hauteur limitée',
			'roadReport.kinds.other' => 'Problème sur la route',
			'roadReport.height' => ({required Object value}) => 'Hauteur indiquée : ${value}',
			'roadReport.send' => 'Signaler',
			'roadReport.sent' => 'Merci : les autres voyageurs sont prévenus.',
			'roadReport.movingTitle' => 'Vous roulez',
			'roadReport.movingBody' => 'Ne signalez rien en conduisant. Un passager peut le faire ; sinon, arrêtez-vous d\'abord.',
			'roadReport.passenger' => 'Je suis passager',
			'roadReport.stillThere' => 'Toujours là',
			'roadReport.over' => 'C\'est fini',
			'roadReport.overSent' => 'Merci : c\'est noté.',
			'roadReport.fromMap' => 'Signaler un problème ici',
			'roadReport.notHereTitle' => 'Pas de signalement ici',
			'roadReport.lower' => 'Plus bas de 10 cm',
			'roadReport.higher' => 'Plus haut de 10 cm',
			'roadReport.passed' => ({required Object what}) => 'Vous venez de passer : ${what}. Toujours là ?',
			'roadReport.notHere' => ({required Object countries}) => 'Lunaway accepte les signalements là où un flux officiel les recoupe : ${countries}.',
			'countries.ad' => 'Andorre',
			'countries.at' => 'Autriche',
			'countries.ax' => 'Åland',
			'countries.be' => 'Belgique',
			'countries.ch' => 'Suisse',
			'countries.cz' => 'Tchéquie',
			'countries.de' => 'Allemagne',
			'countries.dk' => 'Danemark',
			'countries.eh' => 'Sahara occidental',
			'countries.es' => 'Espagne',
			_ => null,
		} ?? switch (path) {
			'countries.fi' => 'Finlande',
			'countries.fr' => 'France',
			'countries.gb' => 'Royaume-Uni',
			'countries.gi' => 'Gibraltar',
			'countries.gr' => 'Grèce',
			'countries.hr' => 'Croatie',
			'countries.ie' => 'Irlande',
			'countries.it' => 'Italie',
			'countries.li' => 'Liechtenstein',
			'countries.lu' => 'Luxembourg',
			'countries.ma' => 'Maroc',
			'countries.mc' => 'Monaco',
			'countries.nl' => 'Pays-Bas',
			'countries.no' => 'Norvège',
			'countries.pl' => 'Pologne',
			'countries.pt' => 'Portugal',
			'countries.se' => 'Suède',
			'countries.si' => 'Slovénie',
			'countries.sj' => 'Svalbard',
			'countries.sm' => 'Saint-Marin',
			'countries.va' => 'Vatican',
			'areas.ara' => 'Auvergne-Rhône-Alpes',
			'areas.bfc' => 'Bourgogne-Franche-Comté',
			'areas.bre' => 'Bretagne',
			'areas.cvl' => 'Centre-Val de Loire',
			'areas.cor' => 'Corse',
			'areas.ges' => 'Grand Est',
			'areas.hdf' => 'Hauts-de-France',
			'areas.idf' => 'Île-de-France',
			'areas.nor' => 'Normandie',
			'areas.naq' => 'Nouvelle-Aquitaine',
			'areas.occ' => 'Occitanie',
			'areas.pdl' => 'Pays de la Loire',
			'areas.pac' => 'Provence-Alpes-Côte d\'Azur',
			'areas.gp' => 'Guadeloupe',
			'areas.mq' => 'Martinique',
			'areas.gf' => 'Guyane',
			'areas.re' => 'La Réunion',
			'areas.yt' => 'Mayotte',
			'areas.franceRest' => 'France, hors commune',
			_ => null,
		};
	}
}

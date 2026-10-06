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
	@override late final _Translations$hours$fr hours = _Translations$hours$fr._(_root);
	@override late final _Translations$directions$fr directions = _Translations$directions$fr._(_root);
	@override late final _Translations$navigation$fr navigation = _Translations$navigation$fr._(_root);
	@override late final _Translations$list$fr list = _Translations$list$fr._(_root);
	@override late final _Translations$favorites$fr favorites = _Translations$favorites$fr._(_root);
	@override late final _Translations$vehicle$fr vehicle = _Translations$vehicle$fr._(_root);
	@override late final _Translations$profile$fr profile = _Translations$profile$fr._(_root);
	@override late final _Translations$units$fr units = _Translations$units$fr._(_root);
	@override late final _Translations$languages$fr languages = _Translations$languages$fr._(_root);
	@override late final _Translations$locale$fr locale = _Translations$locale$fr._(_root);
}

// Path: nav
class _Translations$nav$fr extends Translations$nav$en {
	_Translations$nav$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get map => 'Carte';
	@override String get favorites => 'Favoris';
	@override String get profile => 'Profil';
}

// Path: common
class _Translations$common$fr extends Translations$common$en {
	_Translations$common$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get close => 'Fermer';
	@override String get cancel => 'Annuler';
	@override String get retry => 'Réessayer';
	@override String get save => 'Enregistrer';
	@override String get delete => 'Supprimer';
	@override String get undo => 'Annuler';
	@override String get ok => 'Compris';
	@override String get saveFailed => 'La modification n\'a pas pu être enregistrée.';
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
	@override String get servicesHint => 'Eau et vidange, sans nuit';
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
	@override String get winterCaravanning => 'Séjour en hiver';
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
	@override String get toleratedHint => 'Une nuit est en général acceptée. Restez discret et ne laissez aucune trace.';
	@override String get dayOnlyHint => 'Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.';
	@override String get forbiddenHint => 'Passer la nuit ici est interdit.';
	@override String get unknownHint => 'Personne ne l\'a encore indiqué. Renseignez-vous sur place.';
}

// Path: freshness
class _Translations$freshness$fr extends Translations$freshness$en {
	_Translations$freshness$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String confirmed({required Object when}) => 'Confirmé ${when}';
	@override String updated({required Object when}) => 'Mis à jour ${when}';
	@override String get stale => 'Pas confirmé depuis plus d\'un an';
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
	@override String nearestPlacesLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: 'lieu le plus proche',
		other: 'lieux les plus proches',
	);
	@override String get pointTitle => 'Point choisi';
	@override String get pointHint => 'Ses coordonnées et l\'itinéraire jusqu\'à lui';
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
	@override String get rationale => 'Lunaway s\'en sert pour centrer la carte sur vous, trier les lieux par distance et vous guider. Pour un itinéraire, et de façon approchée pour le carburant le long du trajet, votre position part vers le serveur de Lunaway, qui n\'en garde rien.';
	@override String get allow => 'Continuer';
	@override String get notNow => 'Pas maintenant';
	@override String get deniedTitle => 'Position désactivée pour Lunaway';
	@override String get denied => 'Vous avez refusé l\'accès à la position. Pour l\'utiliser, autorisez-le dans les réglages de l\'appareil.';
	@override String get openSettings => 'Ouvrir les réglages';
	@override String get serviceOffTitle => 'Localisation éteinte';
	@override String get serviceOff => 'La localisation de l\'appareil est éteinte. Allumez-la dans les réglages rapides, puis réessayez.';
	@override String get notAllowed => 'Position non autorisée. La carte fonctionne sans elle.';
	@override String get noFix => 'Votre position n\'arrive pas. Essayez à découvert, ou dans un instant.';
	@override String get unsupported => 'Cet appareil ne donne pas sa position.';
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
}

// Path: filters
class _Translations$filters$fr extends Translations$filters$en {
	_Translations$filters$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filtres';
	@override String get families => 'Type de lieu';
	@override String get familiesHint => 'Aucun choix : tous les types';
	@override String get night => 'La nuit';
	@override String get nightHint => 'Aucun choix : tous les lieux';
	@override String get nightPossible => 'Nuit possible';
	@override String get amenities => 'Services';
	@override String get amenitiesHint => 'Le lieu doit tous les avoir';
	@override String get vehicle => 'Mon véhicule';
	@override String get myVehicleFits => 'Mon véhicule passe';
	@override String myVehicleFitsHeight({required Object height}) => 'Passe à ${height}';
	@override String myVehicleHint({required Object height}) => 'Masque les lieux limités sous ${height}. Les hauteurs inconnues restent.';
	@override String get myVehicleUnknown => 'Indiquez la hauteur de votre véhicule pour l\'utiliser.';
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
	@override String get pricePerNight => 'La nuit';
	@override String get priceFree => 'Gratuit';
	@override String get priceUnknown => 'Inconnu';
	@override String get priceServices => 'Services';
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
	@override String copied({required Object text}) => 'Copié : ${text}';
	@override String get otherFormats => 'Autres formats';
	@override String get formatDecimal => 'Degrés décimaux';
	@override String get formatDms => 'Degrés, minutes, secondes';
	@override String get formatGeo => 'Lien geo:';
	@override String get formatGoogle => 'Lien Google Maps';
	@override String get formatOsm => 'Lien OpenStreetMap';
	@override String get sources => 'Sources';
	@override String fetched({required Object when}) => 'Lu ${when}';
	@override String matchScore({required Object score}) => 'Correspondance ${score} %';
	@override String get viewSource => 'Voir à la source';
	@override String get gone => 'Ce lieu n\'est plus dans les données';
	@override String get goneHint => 'Il a été retiré ou fusionné avec un autre depuis la dernière mise à jour.';
	@override String get loadError => 'Ce lieu n\'a pas pu être lu.';
	@override String get openFailed => 'Aucune application n\'a pu ouvrir ce lien.';
	@override String get photos => 'Photos';
	@override String get extrasOffline => 'Les photos et les avis demandent une connexion.';
	@override String get reviewsTitle => 'Avis';
	@override String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} avis',
		other: '${n} avis',
	);
	@override String get noReviews => 'Aucun avis pour l\'instant.';
	@override String get moreReviews => 'Plus d\'avis';
	@override String get moreReviewsFailed => 'La suite des avis n\'a pas pu se charger. Touchez pour réessayer.';
	@override String stars({required Object rating}) => '${rating} sur 5';
	@override String get deletedAccount => 'Compte supprimé';
	@override late final _Translations$place$reviewVehicle$fr reviewVehicle = _Translations$place$reviewVehicle$fr._(_root);
	@override String originalLanguage({required Object language}) => 'Texte d\'origine en ${language}';
	@override String photoPosition({required Object index, required Object count}) => 'Photo ${index} sur ${count}';
	@override String get links => 'Ailleurs';
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
	@override String get closedWindow => 'Fermé pour les deux prochaines semaines';
	@override String get tomorrow => 'demain';
	@override String onDate({required Object date}) => 'le ${date}';
	@override String get midnight => 'minuit';
	@override String get stale => 'Ouverture inconnue : données à mettre à jour';
	@override String get localTime => 'Heures du lieu';
}

// Path: directions
class _Translations$directions$fr extends Translations$directions$en {
	_Translations$directions$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Itinéraire avec';
	@override String get hint => 'Choisissez qui vous guide. Seul le guidage Lunaway connaît le gabarit de votre véhicule.';
	@override String get remember => 'Toujours utiliser cette application';
	@override String get rememberHint => 'Modifiable dans Profil';
	@override String get settingTitle => 'Itinéraire';
	@override String get settingHint => 'Qui vous guide quand vous touchez Itinéraire';
	@override String get askEachTime => 'Demander à chaque fois';
	@override String get appleMaps => 'Plans';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osmAnd => 'OsmAnd';
	@override String get organicMaps => 'Organic Maps';
	@override String get magicEarth => 'Magic Earth';
	@override String get openStreetMap => 'OpenStreetMap (navigateur)';
}

// Path: navigation
class _Translations$navigation$fr extends Translations$navigation$en {
	_Translations$navigation$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$entry$fr entry = _Translations$navigation$entry$fr._(_root);
	@override late final _Translations$navigation$preview$fr preview = _Translations$navigation$preview$fr._(_root);
	@override late final _Translations$navigation$stops$fr stops = _Translations$navigation$stops$fr._(_root);
	@override late final _Translations$navigation$fuel$fr fuel = _Translations$navigation$fuel$fr._(_root);
	@override late final _Translations$navigation$states$fr states = _Translations$navigation$states$fr._(_root);
	@override late final _Translations$navigation$warning$fr warning = _Translations$navigation$warning$fr._(_root);
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
	@override String get title => 'Lieux autour';
	@override String get empty => 'Aucun lieu par ici avec ces filtres';
	@override String get emptyHint => 'Déplacez la carte, dézoomez ou assouplissez les filtres.';
	@override String get error => 'La liste n\'a pas pu être lue.';
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
	@override String get error => 'Vos favoris n\'ont pas pu être lus.';
}

// Path: vehicle
class _Translations$vehicle$fr extends Translations$vehicle$en {
	_Translations$vehicle$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mon véhicule';
	@override String get why => 'Sa taille filtre les lieux où il ne passe pas. Elle part avec chaque demande d\'itinéraire, et le serveur ne la garde pas.';
	@override String get whyHeight => 'Pour ne garder que les lieux où il passe, indiquez au moins sa hauteur. Elle part avec chaque demande d\'itinéraire, et le serveur ne la garde pas.';
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
	@override String get weight => 'Poids total autorisé';
	@override String heightShort({required Object value}) => 'H ${value}';
	@override String widthShort({required Object value}) => 'l ${value}';
	@override String lengthShort({required Object value}) => 'L ${value}';
	@override String get notANumber => 'Un nombre, par exemple 2,90';
	@override String outOfRange({required Object min, required Object max, required Object unit}) => 'Entre ${min} et ${max} ${unit}';
	@override String get navigationLater => 'Le guidage de Lunaway tient compte de toutes ces dimensions.';
	@override String get save => 'Enregistrer';
	@override String get clear => 'Effacer';
}

// Path: profile
class _Translations$profile$fr extends Translations$profile$en {
	_Translations$profile$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profil';
	@override String get noAccountNeeded => 'Sans compte, sans publicité, sans pisteur : tout reste sur cet appareil.';
	@override String get language => 'Langue';
	@override String get languageSystem => 'Appareil';
	@override String get appearance => 'Apparence';
	@override String get themeAuto => 'Auto';
	@override String get themeLight => 'Clair';
	@override String get themeDark => 'Sombre';
	@override String get themeAutoHint => 'Clair le jour, sombre après le coucher du soleil là où vous êtes.';
	@override String get themeLightHint => 'Toujours clair, de jour comme de nuit.';
	@override String get themeDarkHint => 'Toujours sombre, doux pour les yeux la nuit.';
	@override String get offline => 'Données hors connexion';
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
	@override String get privacy => 'Confidentialité';
	@override String get sourceCode => 'Code source';
	@override String get licences => 'Licences';
	@override String get appLicence => 'Lunaway est un logiciel libre sous licence GNU AGPL 3.0 ou ultérieure.';
	@override String get attributions => 'Sources et attributions';
	@override String get attributionOsm => 'Lieux et données cartographiques © les contributeurs d\'OpenStreetMap.';
	@override String get attributionOdbl => 'Données d\'OpenStreetMap sous licence Open Database License (ODbL).';
	@override String get attributionAtout => 'Campings classés d\'Atout France, sous Licence Ouverte 2.0 (Etalab).';
	@override String get attributionCommunes => 'Communes des lieux : Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), sous licence ODbL.';
	@override String get attributionTiles => 'Fond de carte servi par Lunaway, styles dérivés de Protomaps (BSD-3-Clause), données © les contributeurs d\'OpenStreetMap.';
	@override String get attributionFonts => 'Polices Fraunces et Atkinson Hyperlegible Next, sous licence SIL Open Font License 1.1.';
	@override String get attributionIcons => 'Icônes Phosphor, sous licence MIT.';
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

// Path: locale
class _Translations$locale$fr extends Translations$locale$en {
	_Translations$locale$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
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

// Path: navigation.entry
class _Translations$navigation$entry$fr extends Translations$navigation$entry$en {
	_Translations$navigation$entry$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get lunaway => 'Guidage Lunaway';
	@override String get lunawayHint => 'Un itinéraire calculé pour le gabarit de votre véhicule';
	@override String get vehicleMissing => 'Décrivez d\'abord votre véhicule : l\'itinéraire évite les ponts trop bas et les rues trop étroites pour lui.';
	@override String get others => 'Autres applications';
}

// Path: navigation.preview
class _Translations$navigation$preview$fr extends Translations$navigation$preview$en {
	_Translations$navigation$preview$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String titleTo({required Object name}) => 'Vers ${name}';
	@override String get titlePoint => 'Vers ce point';
	@override String get computing => 'Calcul d\'un itinéraire pour votre véhicule';
	@override String get start => 'Démarrer';
	@override String get phoneOnly => 'Le guidage pas à pas se lance depuis un téléphone.';
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
	@override String get avoid => 'Éviter';
	@override String get avoidTolls => 'Péages';
	@override String get avoidMotorways => 'Autoroutes';
	@override String get avoidFerries => 'Ferries';
	@override String get avoidUnpaved => 'Non revêtues';
	@override String get roadbook => 'Feuille de route';
	@override String get roadbookShow => 'Voir les étapes';
	@override String get roadbookHide => 'Masquer les étapes';
	@override String dataOf({required Object date}) => 'Données routières du ${date}';
	@override String get attributionOsm => '© les contributeurs d\'OpenStreetMap';
	@override String attributionIgn({required Object date}) => 'IGN, BD TOPO, édition du ${date}';
	@override String get disclaimer => 'Lunaway calcule l\'itinéraire avec les dimensions de votre véhicule et des données ouvertes (OpenStreetMap, IGN) qui peuvent être incomplètes ou erronées. La signalisation et le code de la route priment sur les indications de l\'application. Vous restez seul responsable de votre conduite.';
	@override String get otherApps => 'Ouvrir dans une autre application';
	@override String get back => 'Retour';
}

// Path: navigation.stops
class _Translations$navigation$stops$fr extends Translations$navigation$stops$en {
	_Translations$navigation$stops$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Étapes';
	@override String get add => 'Ajouter une étape';
	@override String addCost({required Object minutes}) => 'Ajouter une étape · +${minutes} min';
	@override String get addFree => 'Ajouter une étape · sans détour';
	@override String get quoting => 'Ajouter une étape · calcul du détour';
	@override String get noRoute => 'Pas d\'itinéraire par ce point pour votre véhicule.';
	@override String get full => 'Cinq étapes au plus.';
	@override String get goDirectly => 'Y aller directement';
	@override String get openCard => 'Voir la fiche';
	@override String get point => 'Point de la carte';
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
	@override String get action => 'Carburant';
	@override String get nextCheap => 'Carburant le moins cher devant';
	@override String get title => 'Carburant sur le trajet';
	@override late final _Translations$navigation$fuel$kinds$fr kinds = _Translations$navigation$fuel$kinds$fr._(_root);
	@override String price({required Object price}) => '${price} €/L';
	@override String withDetour({required Object price}) => '${price} €/L avec le détour';
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
	@override String get attribution => 'Prix : Ministère de l\'Économie, prix des carburants (data.economie.gouv.fr)';
	@override String minutesAgo({required Object n}) => 'il y a ${n} min';
	@override String hoursAgo({required Object n}) => 'il y a ${n} h';
	@override String daysAgo({required Object n}) => 'il y a ${n} j';
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
	@override String get offlineHint => 'Les itinéraires sont calculés sur le serveur de Lunaway. Réessayez une fois connecté.';
	@override String get rateLimitedTitle => 'Trop d\'itinéraires demandés';
	@override String rateLimitedHint({required Object seconds}) => 'Réessayez dans ${seconds} s.';
	@override String get unavailableTitle => 'Calcul d\'itinéraire indisponible';
	@override String get unavailableHint => 'Le service est arrêté pour le moment. Réessayez plus tard.';
	@override String get refusedTitle => 'Pas d\'itinéraire ici';
	@override String get refusedHint => 'Les itinéraires couvrent la France pour l\'instant.';
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
	@override String closureOffline({required Object distance}) => 'Route fermée dans ${distance} : pas de réseau pour chercher un autre chemin';
	@override String closureFailed({required Object distance}) => 'Route fermée dans ${distance} : pas encore d\'autre chemin';
	@override String get voiceOn => 'Activer la voix';
	@override String get voiceOff => 'Couper la voix';
	@override String get overview => 'Tout le trajet';
	@override String get recenter => 'Revenir au véhicule';
	@override String get end => 'Terminer';
	@override String get endTitle => 'Terminer le guidage ?';
	@override String get endConfirm => 'Terminer';
	@override String get endKeep => 'Continuer';
	@override String get arrivedTitle => 'Vous êtes arrivé';
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
	@override String get positionLost => 'Position indisponible : vérifiez que la localisation de l\'appareil est activée pour Lunaway.';
	@override String get firstTitle => 'Avant de partir';
	@override String get firstAccept => 'J\'ai compris';
	@override String dangerZone({required Object distance}) => 'Zone de danger dans ${distance}';
	@override String get inDangerZone => 'Zone de danger';
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
	@override String closureAhead({required Object distance}) => 'Route fermée dans ${distance}. Recherche d\'un autre chemin.';
	@override String noDetour({required Object distance}) => 'Route fermée dans ${distance}. Il n\'y a pas d\'autre chemin.';
	@override String clearance({required Object height, required Object distance}) => 'Attention, passage bas de ${height} dans ${distance}.';
	@override String unknownClearance({required Object distance}) => 'Attention, passage bas de hauteur inconnue dans ${distance}.';
	@override String narrow({required Object width, required Object distance}) => 'Attention, passage étroit de ${width} dans ${distance}.';
	@override String limit({required Object what, required Object distance}) => 'Attention, ${what} dans ${distance}.';
	@override String get arrived => 'Vous êtes arrivé.';
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
	@override String size({required Object metres, required Object cm}) => '${metres} mètres ${cm}';
	@override String sizeWhole({required Object metres}) => '${metres} mètres';
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
	@override String get voiceHint => 'Avec la voix du téléphone';
	@override String get units => 'Distances';
	@override String get metric => 'Kilomètres';
	@override String get imperial => 'Miles';
	@override String get fuel => 'Carburant du véhicule';
	@override String get consumption => 'Consommation';
	@override String get consumptionUnit => 'L/100 km';
	@override String get consumptionHint => 'Pour peser le détour vers une station moins chère.';
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

// Path: navigation.fuel.kinds
class _Translations$navigation$fuel$kinds$fr extends Translations$navigation$fuel$kinds$en {
	_Translations$navigation$fuel$kinds$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get diesel => 'Gazole';
	@override String get e10 => 'SP95-E10';
	@override String get sp95 => 'SP95';
	@override String get sp98 => 'SP98';
	@override String get e85 => 'E85';
	@override String get lpg => 'GPL';
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
			'common.close' => 'Fermer',
			'common.cancel' => 'Annuler',
			'common.retry' => 'Réessayer',
			'common.save' => 'Enregistrer',
			'common.delete' => 'Supprimer',
			'common.undo' => 'Annuler',
			'common.ok' => 'Compris',
			'common.saveFailed' => 'La modification n\'a pas pu être enregistrée.',
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
			'families.servicesHint' => 'Eau et vidange, sans nuit',
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
			'services.winterCaravanning' => 'Séjour en hiver',
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
			'overnight.toleratedHint' => 'Une nuit est en général acceptée. Restez discret et ne laissez aucune trace.',
			'overnight.dayOnlyHint' => 'Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.',
			'overnight.forbiddenHint' => 'Passer la nuit ici est interdit.',
			'overnight.unknownHint' => 'Personne ne l\'a encore indiqué. Renseignez-vous sur place.',
			'freshness.confirmed' => ({required Object when}) => 'Confirmé ${when}',
			'freshness.updated' => ({required Object when}) => 'Mis à jour ${when}',
			'freshness.stale' => 'Pas confirmé depuis plus d\'un an',
			'freshness.today' => 'aujourd\'hui',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'hier', other: 'il y a ${n} jours', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a un mois', other: 'il y a ${n} mois', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a un an', other: 'il y a ${n} ans', ), 
			'map.searchHint' => 'Un lieu, une commune',
			'map.clearSearch' => 'Effacer la recherche',
			'map.locateMe' => 'Afficher ma position',
			'map.zoomIn' => 'Zoomer',
			'map.zoomOut' => 'Dézoomer',
			'map.filters' => 'Filtres',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Crédits de la carte : © les contributeurs d\'OpenStreetMap, style Protomaps. Ouvre la page des droits d\'OpenStreetMap.',
			'map.showList' => 'Liste',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Liste (${n})', other: 'Liste (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu ici', other: 'lieux ici', ), 
			'map.nearestPlacesLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu le plus proche', other: 'lieux les plus proches', ), 
			'map.pointTitle' => 'Point choisi',
			'map.pointHint' => 'Ses coordonnées et l\'itinéraire jusqu\'à lui',
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
			'location.rationale' => 'Lunaway s\'en sert pour centrer la carte sur vous, trier les lieux par distance et vous guider. Pour un itinéraire, et de façon approchée pour le carburant le long du trajet, votre position part vers le serveur de Lunaway, qui n\'en garde rien.',
			'location.allow' => 'Continuer',
			'location.notNow' => 'Pas maintenant',
			'location.deniedTitle' => 'Position désactivée pour Lunaway',
			'location.denied' => 'Vous avez refusé l\'accès à la position. Pour l\'utiliser, autorisez-le dans les réglages de l\'appareil.',
			'location.openSettings' => 'Ouvrir les réglages',
			'location.serviceOffTitle' => 'Localisation éteinte',
			'location.serviceOff' => 'La localisation de l\'appareil est éteinte. Allumez-la dans les réglages rapides, puis réessayez.',
			'location.notAllowed' => 'Position non autorisée. La carte fonctionne sans elle.',
			'location.noFix' => 'Votre position n\'arrive pas. Essayez à découvert, ou dans un instant.',
			'location.unsupported' => 'Cet appareil ne donne pas sa position.',
			'search.towns' => 'Communes',
			'search.places' => 'Lieux',
			'search.noResult' => ({required Object query}) => 'Aucun lieu ni aucune commune ne correspond à « ${query} ».',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} lieu', other: '${n} lieux', ), 
			'filters.title' => 'Filtres',
			'filters.families' => 'Type de lieu',
			'filters.familiesHint' => 'Aucun choix : tous les types',
			'filters.night' => 'La nuit',
			'filters.nightHint' => 'Aucun choix : tous les lieux',
			'filters.nightPossible' => 'Nuit possible',
			'filters.amenities' => 'Services',
			'filters.amenitiesHint' => 'Le lieu doit tous les avoir',
			'filters.vehicle' => 'Mon véhicule',
			'filters.myVehicleFits' => 'Mon véhicule passe',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Passe à ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Masque les lieux limités sous ${height}. Les hauteurs inconnues restent.',
			'filters.myVehicleUnknown' => 'Indiquez la hauteur de votre véhicule pour l\'utiliser.',
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
			'place.pricePerNight' => 'La nuit',
			'place.priceFree' => 'Gratuit',
			'place.priceUnknown' => 'Inconnu',
			'place.priceServices' => 'Services',
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
			'place.copied' => ({required Object text}) => 'Copié : ${text}',
			'place.otherFormats' => 'Autres formats',
			'place.formatDecimal' => 'Degrés décimaux',
			'place.formatDms' => 'Degrés, minutes, secondes',
			'place.formatGeo' => 'Lien geo:',
			'place.formatGoogle' => 'Lien Google Maps',
			'place.formatOsm' => 'Lien OpenStreetMap',
			'place.sources' => 'Sources',
			'place.fetched' => ({required Object when}) => 'Lu ${when}',
			'place.matchScore' => ({required Object score}) => 'Correspondance ${score} %',
			'place.viewSource' => 'Voir à la source',
			'place.gone' => 'Ce lieu n\'est plus dans les données',
			'place.goneHint' => 'Il a été retiré ou fusionné avec un autre depuis la dernière mise à jour.',
			'place.loadError' => 'Ce lieu n\'a pas pu être lu.',
			'place.openFailed' => 'Aucune application n\'a pu ouvrir ce lien.',
			'place.photos' => 'Photos',
			'place.extrasOffline' => 'Les photos et les avis demandent une connexion.',
			'place.reviewsTitle' => 'Avis',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} avis', other: '${n} avis', ), 
			'place.noReviews' => 'Aucun avis pour l\'instant.',
			'place.moreReviews' => 'Plus d\'avis',
			'place.moreReviewsFailed' => 'La suite des avis n\'a pas pu se charger. Touchez pour réessayer.',
			'place.stars' => ({required Object rating}) => '${rating} sur 5',
			'place.deletedAccount' => 'Compte supprimé',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Fourgon aménagé',
			'place.reviewVehicle.motorhome' => 'Camping-car',
			'place.reviewVehicle.caravan' => 'Caravane',
			'place.reviewVehicle.other' => 'Autre véhicule',
			'place.originalLanguage' => ({required Object language}) => 'Texte d\'origine en ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Photo ${index} sur ${count}',
			'place.links' => 'Ailleurs',
			'hours.open' => 'Ouvert maintenant',
			'hours.openUntil' => ({required Object time}) => 'Ouvert, ferme à ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Ouvert, ferme ${day} à ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Ouvert, ferme dans ${n} minute', other: 'Ouvert, ferme dans ${n} minutes', ), 
			'hours.closedUntil' => ({required Object time}) => 'Fermé, ouvre à ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Fermé, ouvre ${day} à ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'Fermé, ouvre dans ${n} minute', other: 'Fermé, ouvre dans ${n} minutes', ), 
			'hours.closedWindow' => 'Fermé pour les deux prochaines semaines',
			'hours.tomorrow' => 'demain',
			'hours.onDate' => ({required Object date}) => 'le ${date}',
			'hours.midnight' => 'minuit',
			'hours.stale' => 'Ouverture inconnue : données à mettre à jour',
			'hours.localTime' => 'Heures du lieu',
			'directions.title' => 'Itinéraire avec',
			'directions.hint' => 'Choisissez qui vous guide. Seul le guidage Lunaway connaît le gabarit de votre véhicule.',
			'directions.remember' => 'Toujours utiliser cette application',
			'directions.rememberHint' => 'Modifiable dans Profil',
			'directions.settingTitle' => 'Itinéraire',
			'directions.settingHint' => 'Qui vous guide quand vous touchez Itinéraire',
			'directions.askEachTime' => 'Demander à chaque fois',
			'directions.appleMaps' => 'Plans',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (navigateur)',
			'navigation.entry.lunaway' => 'Guidage Lunaway',
			'navigation.entry.lunawayHint' => 'Un itinéraire calculé pour le gabarit de votre véhicule',
			'navigation.entry.vehicleMissing' => 'Décrivez d\'abord votre véhicule : l\'itinéraire évite les ponts trop bas et les rues trop étroites pour lui.',
			'navigation.entry.others' => 'Autres applications',
			'navigation.preview.titleTo' => ({required Object name}) => 'Vers ${name}',
			'navigation.preview.titlePoint' => 'Vers ce point',
			'navigation.preview.computing' => 'Calcul d\'un itinéraire pour votre véhicule',
			'navigation.preview.start' => 'Démarrer',
			'navigation.preview.phoneOnly' => 'Le guidage pas à pas se lance depuis un téléphone.',
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
			'navigation.preview.avoid' => 'Éviter',
			'navigation.preview.avoidTolls' => 'Péages',
			'navigation.preview.avoidMotorways' => 'Autoroutes',
			'navigation.preview.avoidFerries' => 'Ferries',
			'navigation.preview.avoidUnpaved' => 'Non revêtues',
			'navigation.preview.roadbook' => 'Feuille de route',
			'navigation.preview.roadbookShow' => 'Voir les étapes',
			'navigation.preview.roadbookHide' => 'Masquer les étapes',
			'navigation.preview.dataOf' => ({required Object date}) => 'Données routières du ${date}',
			'navigation.preview.attributionOsm' => '© les contributeurs d\'OpenStreetMap',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, édition du ${date}',
			'navigation.preview.disclaimer' => 'Lunaway calcule l\'itinéraire avec les dimensions de votre véhicule et des données ouvertes (OpenStreetMap, IGN) qui peuvent être incomplètes ou erronées. La signalisation et le code de la route priment sur les indications de l\'application. Vous restez seul responsable de votre conduite.',
			'navigation.preview.otherApps' => 'Ouvrir dans une autre application',
			'navigation.preview.back' => 'Retour',
			'navigation.stops.title' => 'Étapes',
			'navigation.stops.add' => 'Ajouter une étape',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Ajouter une étape · +${minutes} min',
			'navigation.stops.addFree' => 'Ajouter une étape · sans détour',
			'navigation.stops.quoting' => 'Ajouter une étape · calcul du détour',
			'navigation.stops.noRoute' => 'Pas d\'itinéraire par ce point pour votre véhicule.',
			'navigation.stops.full' => 'Cinq étapes au plus.',
			'navigation.stops.goDirectly' => 'Y aller directement',
			'navigation.stops.openCard' => 'Voir la fiche',
			'navigation.stops.point' => 'Point de la carte',
			'navigation.stops.remove' => 'Retirer l\'étape',
			'navigation.stops.reorder' => 'Glisser pour changer l\'ordre',
			'navigation.stops.added' => 'Étape ajoutée',
			'navigation.stops.removed' => 'Étape retirée',
			'navigation.stops.moved' => 'Ordre des étapes changé',
			'navigation.stops.destinationChanged' => 'Nouvelle destination',
			'navigation.stops.failed' => 'L\'itinéraire n\'a pas pu être changé.',
			'navigation.stops.noQuote' => 'Le détour n\'a pas pu être calculé.',
			'navigation.stops.offline' => 'Pas de réseau pour calculer le détour.',
			'navigation.fuel.action' => 'Carburant',
			'navigation.fuel.nextCheap' => 'Carburant le moins cher devant',
			'navigation.fuel.title' => 'Carburant sur le trajet',
			'navigation.fuel.kinds.diesel' => 'Gazole',
			'navigation.fuel.kinds.e10' => 'SP95-E10',
			'navigation.fuel.kinds.sp95' => 'SP95',
			'navigation.fuel.kinds.sp98' => 'SP98',
			'navigation.fuel.kinds.e85' => 'E85',
			'navigation.fuel.kinds.lpg' => 'GPL',
			'navigation.fuel.price' => ({required Object price}) => '${price} €/L',
			'navigation.fuel.withDetour' => ({required Object price}) => '${price} €/L avec le détour',
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
			'navigation.fuel.attribution' => 'Prix : Ministère de l\'Économie, prix des carburants (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => 'il y a ${n} min',
			'navigation.fuel.hoursAgo' => ({required Object n}) => 'il y a ${n} h',
			'navigation.fuel.daysAgo' => ({required Object n}) => 'il y a ${n} j',
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
			'navigation.states.offlineHint' => 'Les itinéraires sont calculés sur le serveur de Lunaway. Réessayez une fois connecté.',
			'navigation.states.rateLimitedTitle' => 'Trop d\'itinéraires demandés',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Réessayez dans ${seconds} s.',
			'navigation.states.unavailableTitle' => 'Calcul d\'itinéraire indisponible',
			'navigation.states.unavailableHint' => 'Le service est arrêté pour le moment. Réessayez plus tard.',
			'navigation.states.refusedTitle' => 'Pas d\'itinéraire ici',
			'navigation.states.refusedHint' => 'Les itinéraires couvrent la France pour l\'instant.',
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
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Route fermée dans ${distance} : pas de réseau pour chercher un autre chemin',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Route fermée dans ${distance} : pas encore d\'autre chemin',
			'navigation.guidance.voiceOn' => 'Activer la voix',
			'navigation.guidance.voiceOff' => 'Couper la voix',
			'navigation.guidance.overview' => 'Tout le trajet',
			'navigation.guidance.recenter' => 'Revenir au véhicule',
			'navigation.guidance.end' => 'Terminer',
			'navigation.guidance.endTitle' => 'Terminer le guidage ?',
			'navigation.guidance.endConfirm' => 'Terminer',
			'navigation.guidance.endKeep' => 'Continuer',
			'navigation.guidance.arrivedTitle' => 'Vous êtes arrivé',
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
			'navigation.guidance.positionLost' => 'Position indisponible : vérifiez que la localisation de l\'appareil est activée pour Lunaway.',
			'navigation.guidance.firstTitle' => 'Avant de partir',
			'navigation.guidance.firstAccept' => 'J\'ai compris',
			'navigation.guidance.dangerZone' => ({required Object distance}) => 'Zone de danger dans ${distance}',
			'navigation.guidance.inDangerZone' => 'Zone de danger',
			'navigation.voice.rerouting' => 'Recalcul de l\'itinéraire.',
			'navigation.voice.rerouted' => 'Nouvel itinéraire.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(minutes, one: 'Nouvel itinéraire, une minute de plus.', other: 'Nouvel itinéraire, ${minutes} minutes de plus.', ), 
			'navigation.voice.closureAhead' => ({required Object distance}) => 'Route fermée dans ${distance}. Recherche d\'un autre chemin.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'Route fermée dans ${distance}. Il n\'y a pas d\'autre chemin.',
			'navigation.voice.clearance' => ({required Object height, required Object distance}) => 'Attention, passage bas de ${height} dans ${distance}.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Attention, passage bas de hauteur inconnue dans ${distance}.',
			'navigation.voice.narrow' => ({required Object width, required Object distance}) => 'Attention, passage étroit de ${width} dans ${distance}.',
			'navigation.voice.limit' => ({required Object what, required Object distance}) => 'Attention, ${what} dans ${distance}.',
			'navigation.voice.arrived' => 'Vous êtes arrivé.',
			'navigation.voice.metres' => ({required Object n}) => '${n} mètres',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${n} kilomètre', other: '${n} kilomètres', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} pieds',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(count, one: '${n} mile', other: '${n} miles', ), 
			'navigation.voice.size' => ({required Object metres, required Object cm}) => '${metres} mètres ${cm}',
			'navigation.voice.sizeWhole' => ({required Object metres}) => '${metres} mètres',
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} h ${m}',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Guidage',
			'navigation.settings.avoidTitle' => 'Éviter par défaut',
			'navigation.settings.voice' => 'Instructions vocales',
			'navigation.settings.voiceHint' => 'Avec la voix du téléphone',
			'navigation.settings.units' => 'Distances',
			'navigation.settings.metric' => 'Kilomètres',
			'navigation.settings.imperial' => 'Miles',
			'navigation.settings.fuel' => 'Carburant du véhicule',
			'navigation.settings.consumption' => 'Consommation',
			'navigation.settings.consumptionUnit' => 'L/100 km',
			'navigation.settings.consumptionHint' => 'Pour peser le détour vers une station moins chère.',
			'list.title' => 'Lieux autour',
			'list.empty' => 'Aucun lieu par ici avec ces filtres',
			'list.emptyHint' => 'Déplacez la carte, dézoomez ou assouplissez les filtres.',
			'list.error' => 'La liste n\'a pas pu être lue.',
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
			'favorites.error' => 'Vos favoris n\'ont pas pu être lus.',
			'vehicle.title' => 'Mon véhicule',
			'vehicle.why' => 'Sa taille filtre les lieux où il ne passe pas. Elle part avec chaque demande d\'itinéraire, et le serveur ne la garde pas.',
			'vehicle.whyHeight' => 'Pour ne garder que les lieux où il passe, indiquez au moins sa hauteur. Elle part avec chaque demande d\'itinéraire, et le serveur ne la garde pas.',
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
			'vehicle.weight' => 'Poids total autorisé',
			'vehicle.heightShort' => ({required Object value}) => 'H ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'l ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'L ${value}',
			'vehicle.notANumber' => 'Un nombre, par exemple 2,90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Entre ${min} et ${max} ${unit}',
			'vehicle.navigationLater' => 'Le guidage de Lunaway tient compte de toutes ces dimensions.',
			'vehicle.save' => 'Enregistrer',
			'vehicle.clear' => 'Effacer',
			'profile.title' => 'Profil',
			'profile.noAccountNeeded' => 'Sans compte, sans publicité, sans pisteur : tout reste sur cet appareil.',
			'profile.language' => 'Langue',
			'profile.languageSystem' => 'Appareil',
			'profile.appearance' => 'Apparence',
			'profile.themeAuto' => 'Auto',
			'profile.themeLight' => 'Clair',
			'profile.themeDark' => 'Sombre',
			'profile.themeAutoHint' => 'Clair le jour, sombre après le coucher du soleil là où vous êtes.',
			'profile.themeLightHint' => 'Toujours clair, de jour comme de nuit.',
			'profile.themeDarkHint' => 'Toujours sombre, doux pour les yeux la nuit.',
			'profile.offline' => 'Données hors connexion',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'lieu sur cet appareil', other: 'lieux sur cet appareil', ), 
			'profile.offlineSize' => ({required Object size}) => 'Espace utilisé : ${size}',
			'profile.lastSync' => ({required Object when}) => 'Dernière mise à jour ${when}',
			'profile.neverSynced' => 'Jamais téléchargé',
			'profile.syncNow' => 'Mettre à jour',
			_ => null,
		} ?? switch (path) {
			'profile.syncing' => 'Mise à jour en cours',
			'profile.about' => 'À propos',
			'profile.version' => ({required Object version}) => 'Version ${version}',
			'profile.website' => 'Site web',
			'profile.privacy' => 'Confidentialité',
			'profile.sourceCode' => 'Code source',
			'profile.licences' => 'Licences',
			'profile.appLicence' => 'Lunaway est un logiciel libre sous licence GNU AGPL 3.0 ou ultérieure.',
			'profile.attributions' => 'Sources et attributions',
			'profile.attributionOsm' => 'Lieux et données cartographiques © les contributeurs d\'OpenStreetMap.',
			'profile.attributionOdbl' => 'Données d\'OpenStreetMap sous licence Open Database License (ODbL).',
			'profile.attributionAtout' => 'Campings classés d\'Atout France, sous Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Communes des lieux : Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), sous licence ODbL.',
			'profile.attributionTiles' => 'Fond de carte servi par Lunaway, styles dérivés de Protomaps (BSD-3-Clause), données © les contributeurs d\'OpenStreetMap.',
			'profile.attributionFonts' => 'Polices Fraunces et Atkinson Hyperlegible Next, sous licence SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Icônes Phosphor, sous licence MIT.',
			'units.kilobytes' => ({required Object n}) => '${n} ko',
			'units.megabytes' => ({required Object n}) => '${n} Mo',
			'languages.fr' => 'français',
			'languages.en' => 'anglais',
			'languages.de' => 'allemand',
			'languages.es' => 'espagnol',
			'languages.it' => 'italien',
			'languages.nl' => 'néerlandais',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			_ => null,
		};
	}
}

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
	@override late final _Translations$search$fr search = _Translations$search$fr._(_root);
	@override late final _Translations$filters$fr filters = _Translations$filters$fr._(_root);
	@override late final _Translations$place$fr place = _Translations$place$fr._(_root);
	@override late final _Translations$hours$fr hours = _Translations$hours$fr._(_root);
	@override late final _Translations$directions$fr directions = _Translations$directions$fr._(_root);
	@override late final _Translations$list$fr list = _Translations$list$fr._(_root);
	@override late final _Translations$favorites$fr favorites = _Translations$favorites$fr._(_root);
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
	@override String get more => 'Plus d\'options';
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
	@override String get campsites => 'Campings et accueils';
	@override String get nature => 'Nature';
	@override String get services => 'Services';
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
}

// Path: overnight
class _Translations$overnight$fr extends Translations$overnight$en {
	_Translations$overnight$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Nuit autorisée';
	@override String get tolerated => 'Nuit tolérée';
	@override String get dayOnly => 'Journée seulement';
	@override String get forbidden => 'Nuit interdite';
	@override String get unknown => 'Nuit : on ne sait pas';
	@override String get allowedHint => 'Vous pouvez passer la nuit ici.';
	@override String get toleratedHint => 'Une nuit est en général acceptée. Restez discret et ne laissez aucune trace.';
	@override String get dayOnlyHint => 'Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.';
	@override String get forbiddenHint => 'Passer la nuit ici est interdit.';
	@override String get unknownHint => 'Personne ne nous a encore dit si la nuit est permise.';
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
	@override String get searchHint => 'Chercher un lieu ou une commune';
	@override String get clearSearch => 'Effacer la recherche';
	@override String get locateMe => 'Afficher ma position';
	@override String get locationUnavailable => 'Votre position n\'est pas disponible. Vérifiez que la localisation est autorisée.';
	@override String get filters => 'Filtres';
	@override String get showList => 'Afficher la liste';
	@override String get showMap => 'Afficher la carte';
	@override String placesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} lieu ici',
		other: '${n} lieux ici',
	);
	@override String nearestPlaces({required Object n}) => 'Les ${n} lieux les plus proches';
	@override String get pointTitle => 'Point choisi';
	@override String get downloading => 'Téléchargement des lieux de France';
	@override String downloadingCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		one: '${n} lieu reçu',
		other: '${n} lieux reçus',
	);
	@override String get noData => 'Aucun lieu sur cet appareil pour l\'instant';
	@override String get noDataHint => 'Téléchargez les lieux une fois ; la carte fonctionne ensuite sans réseau.';
	@override String get download => 'Télécharger les lieux';
	@override String get downloadFailed => 'Le téléchargement a échoué. Vérifiez la connexion et réessayez.';
	@override String get demoBanner => 'Démo : lieux inventés';
	@override String get unsupported => 'La carte n\'est pas disponible sur ce système. Utilisez l\'application web.';
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
	@override String get night => 'Nuit autorisée';
	@override String get nightHint => 'Autorisée ou tolérée';
	@override String get amenities => 'Services';
	@override String get height => 'Hauteur du véhicule';
	@override String get heightAny => 'Toutes hauteurs';
	@override String get heightHint => 'Masque les lieux dont la barre de hauteur est plus basse. Les lieux sans hauteur connue restent visibles.';
	@override String get reset => 'Tout effacer';
	@override String show({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		zero: 'Aucun lieu ne correspond',
		one: 'Afficher ${n} lieu',
		other: 'Afficher ${n} lieux',
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
	@override String get directions => 'Itinéraire';
	@override String get share => 'Partager';
	@override String get save => 'Enregistrer';
	@override String get saved => 'Enregistré';
	@override String get saveTo => 'Enregistrer dans une liste';
	@override String get savedToast => 'Ajouté à vos favoris';
	@override String get removedToast => 'Retiré de vos favoris';
	@override String get facts => 'Bon à savoir';
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
	@override String get gone => 'Ce lieu n\'est plus dans les données.';
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
}

// Path: directions
class _Translations$directions$fr extends Translations$directions$en {
	_Translations$directions$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Y aller avec';
	@override String get appleMaps => 'Plans d\'Apple';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osm => 'OpenStreetMap';
	@override String get system => 'Une application de navigation';
}

// Path: list
class _Translations$list$fr extends Translations$list$en {
	_Translations$list$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Lieux autour';
	@override String get empty => 'Aucun lieu dans cette zone avec ces filtres.';
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
	@override String get empty => 'Les lieux que vous enregistrez apparaîtront ici.';
	@override String get emptyHint => 'Touchez Enregistrer sur un lieu pour le garder, même hors connexion.';
	@override String get newList => 'Nouvelle liste';
	@override String get listName => 'Nom de la liste';
	@override String get renameList => 'Renommer la liste';
	@override String get deleteList => 'Supprimer la liste';
	@override String deleteListConfirm({required Object name}) => 'Supprimer « ${name} » ? Les lieux restent sur la carte.';
	@override String get removed => 'Retiré de la liste';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		zero: 'Vide',
		one: '${n} lieu',
		other: '${n} lieux',
	);
	@override String get error => 'Vos favoris n\'ont pas pu être lus.';
}

// Path: profile
class _Translations$profile$fr extends Translations$profile$en {
	_Translations$profile$fr._(TranslationsFr root) : this._root = root, super.internal(root);

	final TranslationsFr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Profil';
	@override String get language => 'Langue';
	@override String get languageSystem => 'Appareil';
	@override String get noAccountNeeded => 'Aucun compte n\'est nécessaire. Ni publicité ni pisteur : la carte et vos favoris restent sur cet appareil.';
	@override String get offline => 'Données hors connexion';
	@override String offlinePlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n,
		zero: 'Aucun lieu sur cet appareil',
		one: '${n} lieu sur cet appareil',
		other: '${n} lieux sur cet appareil',
	);
	@override String offlineSize({required Object size}) => 'Espace utilisé : ${size}';
	@override String lastSync({required Object when}) => 'Dernière mise à jour ${when}';
	@override String get neverSynced => 'Jamais téléchargé';
	@override String get syncNow => 'Mettre à jour';
	@override String get syncing => 'Mise à jour en cours';
	@override String get syncDone => 'Les lieux sont à jour.';
	@override String get syncFailed => 'La mise à jour a échoué. Les lieux de cet appareil restent utilisables.';
	@override String get about => 'À propos';
	@override String version({required Object version}) => 'Version ${version}';
	@override String get website => 'Site web';
	@override String get privacy => 'Confidentialité';
	@override String get sourceCode => 'Code source';
	@override String get licences => 'Licences';
	@override String get attributions => 'Données et carte';
	@override String get attributionOsm => 'Lieux et données cartographiques © les contributeurs d\'OpenStreetMap, sous licence Open Database License (ODbL).';
	@override String get attributionAtout => 'Campings classés d\'Atout France, sous Licence Ouverte 2.0 (Etalab).';
	@override String get attributionTiles => 'Carte OpenFreeMap, © OpenMapTiles, données © les contributeurs d\'OpenStreetMap.';
	@override String get attributionFont => 'Police Atkinson Hyperlegible Next, sous licence SIL Open Font License 1.1.';
	@override String get appLicence => 'Lunaway est un logiciel libre sous licence GNU AGPL 3.0 ou ultérieure.';
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
			'common.more' => 'Plus d\'options',
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
			'families.campsites' => 'Campings et accueils',
			'families.nature' => 'Nature',
			'families.services' => 'Services',
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
			'overnight.allowed' => 'Nuit autorisée',
			'overnight.tolerated' => 'Nuit tolérée',
			'overnight.dayOnly' => 'Journée seulement',
			'overnight.forbidden' => 'Nuit interdite',
			'overnight.unknown' => 'Nuit : on ne sait pas',
			'overnight.allowedHint' => 'Vous pouvez passer la nuit ici.',
			'overnight.toleratedHint' => 'Une nuit est en général acceptée. Restez discret et ne laissez aucune trace.',
			'overnight.dayOnlyHint' => 'Stationnement de jour uniquement. Cherchez un autre lieu pour la nuit.',
			'overnight.forbiddenHint' => 'Passer la nuit ici est interdit.',
			'overnight.unknownHint' => 'Personne ne nous a encore dit si la nuit est permise.',
			'freshness.confirmed' => ({required Object when}) => 'Confirmé ${when}',
			'freshness.updated' => ({required Object when}) => 'Mis à jour ${when}',
			'freshness.stale' => 'Pas confirmé depuis plus d\'un an',
			'freshness.today' => 'aujourd\'hui',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'hier', other: 'il y a ${n} jours', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a un mois', other: 'il y a ${n} mois', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: 'il y a un an', other: 'il y a ${n} ans', ), 
			'map.searchHint' => 'Chercher un lieu ou une commune',
			'map.clearSearch' => 'Effacer la recherche',
			'map.locateMe' => 'Afficher ma position',
			'map.locationUnavailable' => 'Votre position n\'est pas disponible. Vérifiez que la localisation est autorisée.',
			'map.filters' => 'Filtres',
			'map.showList' => 'Afficher la liste',
			'map.showMap' => 'Afficher la carte',
			'map.placesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} lieu ici', other: '${n} lieux ici', ), 
			'map.nearestPlaces' => ({required Object n}) => 'Les ${n} lieux les plus proches',
			'map.pointTitle' => 'Point choisi',
			'map.downloading' => 'Téléchargement des lieux de France',
			'map.downloadingCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} lieu reçu', other: '${n} lieux reçus', ), 
			'map.noData' => 'Aucun lieu sur cet appareil pour l\'instant',
			'map.noDataHint' => 'Téléchargez les lieux une fois ; la carte fonctionne ensuite sans réseau.',
			'map.download' => 'Télécharger les lieux',
			'map.downloadFailed' => 'Le téléchargement a échoué. Vérifiez la connexion et réessayez.',
			'map.demoBanner' => 'Démo : lieux inventés',
			'map.unsupported' => 'La carte n\'est pas disponible sur ce système. Utilisez l\'application web.',
			'search.towns' => 'Communes',
			'search.places' => 'Lieux',
			'search.noResult' => ({required Object query}) => 'Aucun lieu ni aucune commune ne correspond à « ${query} ».',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} lieu', other: '${n} lieux', ), 
			'filters.title' => 'Filtres',
			'filters.families' => 'Type de lieu',
			'filters.night' => 'Nuit autorisée',
			'filters.nightHint' => 'Autorisée ou tolérée',
			'filters.amenities' => 'Services',
			'filters.height' => 'Hauteur du véhicule',
			'filters.heightAny' => 'Toutes hauteurs',
			'filters.heightHint' => 'Masque les lieux dont la barre de hauteur est plus basse. Les lieux sans hauteur connue restent visibles.',
			'filters.reset' => 'Tout effacer',
			'filters.show' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, zero: 'Aucun lieu ne correspond', one: 'Afficher ${n} lieu', other: 'Afficher ${n} lieux', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, one: '${n} filtre actif', other: '${n} filtres actifs', ), 
			'place.unnamedIn' => ({required Object kind, required Object town}) => '${kind} à ${town}',
			'place.directions' => 'Itinéraire',
			'place.share' => 'Partager',
			'place.save' => 'Enregistrer',
			'place.saved' => 'Enregistré',
			'place.saveTo' => 'Enregistrer dans une liste',
			'place.savedToast' => 'Ajouté à vos favoris',
			'place.removedToast' => 'Retiré de vos favoris',
			'place.facts' => 'Bon à savoir',
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
			'place.gone' => 'Ce lieu n\'est plus dans les données.',
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
			'directions.title' => 'Y aller avec',
			'directions.appleMaps' => 'Plans d\'Apple',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osm' => 'OpenStreetMap',
			'directions.system' => 'Une application de navigation',
			'list.title' => 'Lieux autour',
			'list.empty' => 'Aucun lieu dans cette zone avec ces filtres.',
			'list.emptyHint' => 'Déplacez la carte, dézoomez ou assouplissez les filtres.',
			'list.error' => 'La liste n\'a pas pu être lue.',
			'favorites.title' => 'Favoris',
			'favorites.defaultList' => 'Mes favoris',
			'favorites.empty' => 'Les lieux que vous enregistrez apparaîtront ici.',
			'favorites.emptyHint' => 'Touchez Enregistrer sur un lieu pour le garder, même hors connexion.',
			'favorites.newList' => 'Nouvelle liste',
			'favorites.listName' => 'Nom de la liste',
			'favorites.renameList' => 'Renommer la liste',
			'favorites.deleteList' => 'Supprimer la liste',
			'favorites.deleteListConfirm' => ({required Object name}) => 'Supprimer « ${name} » ? Les lieux restent sur la carte.',
			'favorites.removed' => 'Retiré de la liste',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, zero: 'Vide', one: '${n} lieu', other: '${n} lieux', ), 
			'favorites.error' => 'Vos favoris n\'ont pas pu être lus.',
			'profile.title' => 'Profil',
			'profile.language' => 'Langue',
			'profile.languageSystem' => 'Appareil',
			'profile.noAccountNeeded' => 'Aucun compte n\'est nécessaire. Ni publicité ni pisteur : la carte et vos favoris restent sur cet appareil.',
			'profile.offline' => 'Données hors connexion',
			'profile.offlinePlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('fr'))(n, zero: 'Aucun lieu sur cet appareil', one: '${n} lieu sur cet appareil', other: '${n} lieux sur cet appareil', ), 
			'profile.offlineSize' => ({required Object size}) => 'Espace utilisé : ${size}',
			'profile.lastSync' => ({required Object when}) => 'Dernière mise à jour ${when}',
			'profile.neverSynced' => 'Jamais téléchargé',
			'profile.syncNow' => 'Mettre à jour',
			'profile.syncing' => 'Mise à jour en cours',
			'profile.syncDone' => 'Les lieux sont à jour.',
			'profile.syncFailed' => 'La mise à jour a échoué. Les lieux de cet appareil restent utilisables.',
			'profile.about' => 'À propos',
			'profile.version' => ({required Object version}) => 'Version ${version}',
			'profile.website' => 'Site web',
			'profile.privacy' => 'Confidentialité',
			'profile.sourceCode' => 'Code source',
			'profile.licences' => 'Licences',
			'profile.attributions' => 'Données et carte',
			'profile.attributionOsm' => 'Lieux et données cartographiques © les contributeurs d\'OpenStreetMap, sous licence Open Database License (ODbL).',
			'profile.attributionAtout' => 'Campings classés d\'Atout France, sous Licence Ouverte 2.0 (Etalab).',
			'profile.attributionTiles' => 'Carte OpenFreeMap, © OpenMapTiles, données © les contributeurs d\'OpenStreetMap.',
			'profile.attributionFont' => 'Police Atkinson Hyperlegible Next, sous licence SIL Open Font License 1.1.',
			'profile.appLicence' => 'Lunaway est un logiciel libre sous licence GNU AGPL 3.0 ou ultérieure.',
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

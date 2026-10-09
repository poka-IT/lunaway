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
class TranslationsEs extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsEs({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  _meta = meta ?? TranslationMetadata(
		    locale: AppLocale.es,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		_meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <es>.
	final TranslationMetadata<AppLocale, Translations> _meta;
	@override TranslationMetadata<AppLocale, Translations> get $meta => _meta;

	/// Access flat map
	@override dynamic operator[](String key) => _meta.getTranslation(key) ?? super[key];

	late final TranslationsEs _root = this; // ignore: unused_field

	@override 
	TranslationsEs $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsEs(meta: meta ?? this.$meta);

	// Translations
	@override String get appTitle => 'Lunaway';
	@override late final _Translations$nav$es nav = _Translations$nav$es._(_root);
	@override late final _Translations$common$es common = _Translations$common$es._(_root);
	@override late final _Translations$kinds$es kinds = _Translations$kinds$es._(_root);
	@override late final _Translations$families$es families = _Translations$families$es._(_root);
	@override late final _Translations$services$es services = _Translations$services$es._(_root);
	@override late final _Translations$activities$es activities = _Translations$activities$es._(_root);
	@override late final _Translations$amenities$es amenities = _Translations$amenities$es._(_root);
	@override late final _Translations$overnight$es overnight = _Translations$overnight$es._(_root);
	@override late final _Translations$freshness$es freshness = _Translations$freshness$es._(_root);
	@override late final _Translations$map$es map = _Translations$map$es._(_root);
	@override late final _Translations$sync$es sync = _Translations$sync$es._(_root);
	@override late final _Translations$location$es location = _Translations$location$es._(_root);
	@override late final _Translations$search$es search = _Translations$search$es._(_root);
	@override late final _Translations$filters$es filters = _Translations$filters$es._(_root);
	@override late final _Translations$place$es place = _Translations$place$es._(_root);
	@override late final _Translations$sources$es sources = _Translations$sources$es._(_root);
	@override late final _Translations$hours$es hours = _Translations$hours$es._(_root);
	@override late final _Translations$directions$es directions = _Translations$directions$es._(_root);
	@override late final _Translations$navigation$es navigation = _Translations$navigation$es._(_root);
	@override late final _Translations$list$es list = _Translations$list$es._(_root);
	@override late final _Translations$favorites$es favorites = _Translations$favorites$es._(_root);
	@override late final _Translations$vehicle$es vehicle = _Translations$vehicle$es._(_root);
	@override late final _Translations$vehicleHeight$es vehicleHeight = _Translations$vehicleHeight$es._(_root);
	@override late final _Translations$profile$es profile = _Translations$profile$es._(_root);
	@override late final _Translations$units$es units = _Translations$units$es._(_root);
	@override late final _Translations$languages$es languages = _Translations$languages$es._(_root);
	@override late final _Translations$translation$es translation = _Translations$translation$es._(_root);
	@override late final _Translations$locale$es locale = _Translations$locale$es._(_root);
	@override late final _Translations$account$es account = _Translations$account$es._(_root);
	@override late final _Translations$recovery$es recovery = _Translations$recovery$es._(_root);
	@override late final _Translations$recover$es recover = _Translations$recover$es._(_root);
	@override late final _Translations$deletion$es deletion = _Translations$deletion$es._(_root);
	@override late final _Translations$devices$es devices = _Translations$devices$es._(_root);
	@override late final _Translations$muted$es muted = _Translations$muted$es._(_root);
	@override late final _Translations$mine$es mine = _Translations$mine$es._(_root);
	@override late final _Translations$outbox$es outbox = _Translations$outbox$es._(_root);
	@override late final _Translations$placement$es placement = _Translations$placement$es._(_root);
	@override late final _Translations$contribute$es contribute = _Translations$contribute$es._(_root);
	@override late final _Translations$confirmSheet$es confirmSheet = _Translations$confirmSheet$es._(_root);
	@override late final _Translations$issueSheet$es issueSheet = _Translations$issueSheet$es._(_root);
	@override late final _Translations$reportSheet$es reportSheet = _Translations$reportSheet$es._(_root);
	@override late final _Translations$reviewSheet$es reviewSheet = _Translations$reviewSheet$es._(_root);
	@override late final _Translations$gate$es gate = _Translations$gate$es._(_root);
	@override late final _Translations$photoFlow$es photoFlow = _Translations$photoFlow$es._(_root);
	@override late final _Translations$placeForm$es placeForm = _Translations$placeForm$es._(_root);
	@override late final _Translations$favoritesSync$es favoritesSync = _Translations$favoritesSync$es._(_root);
	@override late final _Translations$poi$es poi = _Translations$poi$es._(_root);
	@override late final _Translations$offlineMaps$es offlineMaps = _Translations$offlineMaps$es._(_root);
	@override late final _Translations$regions$es regions = _Translations$regions$es._(_root);
	@override late final _Translations$roadReport$es roadReport = _Translations$roadReport$es._(_root);
	@override late final _Translations$countries$es countries = _Translations$countries$es._(_root);
	@override late final _Translations$areas$es areas = _Translations$areas$es._(_root);
}

// Path: nav
class _Translations$nav$es extends Translations$nav$en {
	_Translations$nav$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get map => 'Mapa';
	@override String get favorites => 'Favoritos';
	@override String get profile => 'Perfil';
	@override String get fold => 'Contraer el menú';
	@override String get unfold => 'Desplegar el menú';
}

// Path: common
class _Translations$common$es extends Translations$common$en {
	_Translations$common$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get close => 'Cerrar';
	@override String get done => 'Hecho';
	@override String get cancel => 'Cancelar';
	@override String get retry => 'Reintentar';
	@override String get save => 'Guardar';
	@override String get delete => 'Eliminar';
	@override String get undo => 'Deshacer';
	@override String get ok => 'Entendido';
	@override String get saveFailed => 'No se ha podido guardar el cambio.';
	@override String get send => 'Enviar';
	@override String get later => 'Más tarde';
	@override String get next => 'Continuar';
	@override String get failed => 'No ha funcionado. Vuelve a intentarlo en un momento.';
	@override String get offline => 'Ahora mismo no hay conexión. Vuelve a intentarlo cuando tengas cobertura.';
}

// Path: kinds
class _Translations$kinds$es extends Translations$kinds$en {
	_Translations$kinds$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get motorhomeArea => 'Área de autocaravanas';
	@override String get serviceArea => 'Punto de servicio para autocaravanas';
	@override String get campsite => 'Camping';
	@override String get parking => 'Aparcamiento';
	@override String get nature => 'Lugar en plena naturaleza';
	@override String get restArea => 'Área de descanso';
	@override String get picnicArea => 'Área de pícnic';
	@override String get farm => 'Granja';
	@override String get homestay => 'Casa particular';
	@override String get offRoad => 'Lugar con acceso por pista';
	@override String get extraService => 'Parada práctica';
}

// Path: families
class _Translations$families$es extends Translations$families$en {
	_Translations$families$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get stopovers => 'Áreas y aparcamientos';
	@override String get stopoversHint => 'Áreas de autocaravanas, aparcamientos, áreas de descanso';
	@override String get campsites => 'Campings y anfitriones';
	@override String get campsitesHint => 'Campings, granjas, particulares';
	@override String get nature => 'Naturaleza';
	@override String get natureHint => 'Lugares en plena naturaleza, pistas';
	@override String get services => 'Servicios';
	@override String get servicesHint => 'Agua y vaciado, sin pernocta';
}

// Path: services
class _Translations$services$es extends Translations$services$en {
	_Translations$services$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get drinkingWater => 'Agua potable';
	@override String get greyWater => 'Vaciado de aguas grises';
	@override String get blackWater => 'Vaciado de WC químico';
	@override String get wasteBin => 'Contenedores';
	@override String get toilets => 'Aseos';
	@override String get showers => 'Duchas';
	@override String get electricity => 'Electricidad';
	@override String get wifi => 'Wi-Fi';
	@override String get laundry => 'Lavandería';
	@override String get lpg => 'GLP';
	@override String get gasBottles => 'Bombonas de gas';
	@override String get vehicleWash => 'Lavado del vehículo';
	@override String get bakery => 'Panadería';
	@override String get swimmingPool => 'Piscina';
	@override String get petsAllowed => 'Se admiten mascotas';
	@override String get mobileData => 'Cobertura móvil';
	@override String get winterCaravanning => 'Abierto en invierno';
}

// Path: activities
class _Translations$activities$es extends Translations$activities$en {
	_Translations$activities$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get monuments => 'Monumentos y visitas';
	@override String get windsurfKitesurf => 'Windsurf, kitesurf';
	@override String get mountainBiking => 'Bicicleta de montaña';
	@override String get hiking => 'Senderismo';
	@override String get climbing => 'Escalada';
	@override String get canoeKayak => 'Canoa, kayak';
	@override String get fishing => 'Pesca';
	@override String get shoreFishing => 'Marisqueo a pie';
	@override String get swimming => 'Baño';
	@override String get motorcycling => 'Rutas en moto';
	@override String get viewpoint => 'Mirador';
	@override String get playground => 'Parque infantil';
}

// Path: amenities
class _Translations$amenities$es extends Translations$amenities$en {
	_Translations$amenities$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get water => 'Agua';
	@override String get dumpStation => 'Vaciado';
	@override String get electricity => 'Electricidad';
	@override String get toilets => 'Aseos';
	@override String get showers => 'Duchas';
	@override String get wasteBin => 'Contenedores';
	@override String get laundry => 'Lavandería';
	@override String get wifi => 'Wi-Fi';
	@override String get lpg => 'GLP';
}

// Path: overnight
class _Translations$overnight$es extends Translations$overnight$en {
	_Translations$overnight$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get allowed => 'Pernocta permitida';
	@override String get tolerated => 'Pernocta tolerada';
	@override String get dayOnly => 'Solo de día';
	@override String get forbidden => 'Pernocta prohibida';
	@override String get unknown => 'Pernocta sin información';
	@override String get allowedHint => 'Puedes pasar la noche aquí.';
	@override String get toleratedHint => 'Normalmente se acepta una noche. Actúa con discreción y no dejes rastro.';
	@override String get dayOnlyHint => 'Solo se puede aparcar de día. Busca otro lugar para la noche.';
	@override String get forbiddenHint => 'Aquí está prohibido pasar la noche.';
	@override String get unknownHint => 'Nadie lo ha indicado todavía. Pregunta al llegar.';
}

// Path: freshness
class _Translations$freshness$es extends Translations$freshness$en {
	_Translations$freshness$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String confirmed({required Object when}) => 'Confirmado por un viajero ${when}';
	@override String get unconfirmed => 'Aún no lo ha confirmado ningún viajero';
	@override String get stale => 'Última confirmación hace más de un año';
	@override String get today => 'hoy';
	@override String daysAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'ayer',
		other: 'hace ${n} días',
	);
	@override String monthsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'hace un mes',
		other: 'hace ${n} meses',
	);
	@override String yearsAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'hace un año',
		other: 'hace ${n} años',
	);
}

// Path: map
class _Translations$map$es extends Translations$map$en {
	_Translations$map$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get searchHint => 'Lugar o municipio';
	@override String get clearSearch => 'Borrar la búsqueda';
	@override String get locateMe => 'Mostrar mi ubicación';
	@override String get aroundMe => 'Ver lugares cerca de mí';
	@override String get zoomIn => 'Acercar';
	@override String get zoomOut => 'Alejar';
	@override String get filters => 'Filtros';
	@override String get credit => '© OpenStreetMap · Protomaps';
	@override String get creditLabel => 'Créditos del mapa: © colaboradores de OpenStreetMap, estilo Protomaps. Abre la página de derechos de autor de OpenStreetMap.';
	@override String get showList => 'Lista';
	@override String showListCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Lista (${n})',
		other: 'Lista (${n})',
	);
	@override String placesHereLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'lugar aquí',
		other: 'lugares aquí',
	);
	@override String nearestYouLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'lugar más cercano a ti',
		other: 'lugares más cercanos a ti',
	);
	@override String nearestCentreLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'lugar más cercano al centro',
		other: 'lugares más cercanos al centro',
	);
	@override String get pointTitle => 'Aquí';
	@override String get pointHint => 'Punto en el mapa';
	@override String get directionsHere => 'Ruta hasta aquí';
	@override String get startHere => 'Salir desde aquí';
	@override String get departureChosen => 'Punto de salida elegido: ahora abre el destino para ver la ruta.';
	@override String get copyCoordinates => 'Copiar coordenadas';
	@override String get freeTapHint => 'Toca el mapa para ir allí o añadir un lugar';
	@override String get freeTapHintClick => 'Haz clic en el mapa para ir allí o añadir un lugar';
	@override String get addPlaceAtCenter => 'Añadir un lugar en el centro del mapa';
	@override String addressSource({required Object attribution}) => 'Fuente: ${attribution}';
	@override String get placesAround => 'Lugares cercanos';
	@override String get downloading => 'Descargando los lugares de Francia';
	@override String downloadingCount({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${count} lugar recibido',
		other: '${count} lugares recibidos',
	);
	@override String get noData => 'Todavía no hay lugares en este dispositivo';
	@override String get noDataHint => 'Descarga los lugares una sola vez: después el mapa funciona sin conexión.';
	@override String get download => 'Descargar los lugares';
	@override String get downloadFailed => 'La descarga se ha interrumpido';
	@override String get demoBanner => 'Demostración: lugares ficticios';
	@override String get unsupported => 'El mapa no está disponible en este sistema. Usa la aplicación web.';
}

// Path: sync
class _Translations$sync$es extends Translations$sync$en {
	_Translations$sync$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get failedOffline => 'Sin conexión por ahora.';
	@override String get failedBusy => 'El servidor está saturado.';
	@override String get failedServer => 'El servidor tiene un problema en este momento.';
	@override String get failedOther => 'La actualización no se ha completado.';
	@override String get failedRefused => 'El servidor ha rechazado la actualización. Puede que necesites una versión más reciente de la aplicación.';
	@override String get willRetry => 'Lunaway lo volverá a intentar automáticamente.';
	@override String incomplete({required Object count}) => 'Descarga incompleta: ${count} lugares por ahora';
	@override String get incompleteShort => 'Descarga incompleta';
	@override String resuming({required Object count}) => 'Descargando: ${count} lugares';
	@override String get resume => 'Reanudar';
}

// Path: location
class _Translations$location$es extends Translations$location$en {
	_Translations$location$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get rationaleTitle => '¿Mostrar tu ubicación?';
	@override String get rationale => 'Lunaway la usa para centrar el mapa en ti, ordenar los lugares por distancia y guiarte. Para calcular una ruta, tu ubicación se envía al servidor de Lunaway, que no la guarda. Para buscar el combustible más barato cerca de ti, solo se envía una ubicación redondeada a unos 5 km. Si avisas de un problema en la carretera, el aviso incluye el punto donde estás.';
	@override String get allow => 'Continuar';
	@override String get notNow => 'Ahora no';
	@override String get deniedTitle => 'Ubicación desactivada para Lunaway';
	@override String get denied => 'Has denegado el acceso a tu ubicación. Para usarla, permítelo en los ajustes del dispositivo.';
	@override String get openSettings => 'Abrir ajustes';
	@override String get serviceOffTitle => 'Ubicación desactivada';
	@override String get serviceOff => 'La ubicación está desactivada en este dispositivo. Actívala en los ajustes rápidos y vuelve a intentarlo.';
	@override String get notAllowed => 'Ubicación no permitida. El mapa funciona sin ella.';
	@override String get noFix => 'Todavía no se ha encontrado tu ubicación. Vuelve a intentarlo al aire libre o dentro de un momento.';
	@override String get unsupported => 'Este dispositivo no proporciona su ubicación.';
	@override String get browserDeniedTitle => 'El navegador bloquea tu ubicación';
	@override String get browserDenied => 'El navegador no deja que Lunaway acceda a tu ubicación. Para permitirlo, haz clic en el icono a la izquierda de la dirección del sitio (un candado o unos controles deslizantes), pon Ubicación en Permitir y vuelve a hacer clic en el botón de ubicación.';
	@override String get browserNoFix => 'El navegador no ha dado ninguna ubicación. Vuelve a intentarlo dentro de un momento; en un ordenador, el Wi-Fi ayuda a encontrarla.';
}

// Path: search
class _Translations$search$es extends Translations$search$en {
	_Translations$search$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get towns => 'Municipios';
	@override String get places => 'Lugares';
	@override String noResult({required Object query}) => 'Ningún lugar ni municipio coincide con «${query}».';
	@override String townPlaces({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} lugar',
		other: '${n} lugares',
	);
	@override String get addresses => 'Direcciones';
	@override String get addressesSearching => 'Buscando direcciones';
	@override String get addressesFailed => 'No se han podido buscar las direcciones en este momento.';
	@override String addressSources({required Object sources}) => 'Direcciones: ${sources}';
	@override String get offline => 'Sin conexión: la búsqueda necesita conexión.';
	@override late final _Translations$search$addressKind$es addressKind = _Translations$search$addressKind$es._(_root);
}

// Path: filters
class _Translations$filters$es extends Translations$filters$en {
	_Translations$filters$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filtros';
	@override String get families => 'Tipo de lugar';
	@override String get familiesHint => 'Sin elegir: todos los tipos';
	@override String get familiesChosenHint => 'Solo estos tipos';
	@override String get night => 'Pernocta';
	@override String get nightHint => 'Sin elegir: todos los lugares';
	@override String get nightChosenHint => 'Solo los lugares con estas opciones de pernocta';
	@override String get nightPossible => 'Pernocta posible';
	@override String get amenities => 'Servicios';
	@override String get amenitiesHint => 'El lugar debe tenerlos todos';
	@override String get rating => 'Valoración mínima';
	@override String get ratingHint => 'Valoración de los viajeros de Lunaway, o la de otras fuentes si ellos no han valorado el lugar. Los lugares sin valoración se ocultan.';
	@override String ratingAtLeast({required Object rating}) => '${rating} o más';
	@override String get opening => 'Apertura';
	@override String get openingHint => 'Los lugares cuya apertura no se conoce se siguen mostrando.';
	@override String get openingAllYear => 'Todo el año';
	@override String get openingDates => 'Mis fechas';
	@override String get openingClearDates => 'Borrar las fechas';
	@override String openingStay({required Object from, required Object to}) => 'Del ${from} al ${to}';
	@override String openingStayDay({required Object date}) => 'El ${date}';
	@override String get openingStayTitle => 'Fechas de tu estancia';
	@override String get openingArrival => 'Llegada';
	@override String get openingDeparture => 'Salida';
	@override String get price => 'Precio por noche';
	@override String get freeOnly => 'Gratis';
	@override String get freeHint => 'Solo los lugares donde la noche es gratis según sus fuentes';
	@override String get scrollNext => 'Ver los filtros siguientes';
	@override String get scrollPrevious => 'Ver los filtros anteriores';
	@override String get vehicle => 'Mi vehículo';
	@override String get myVehicleFits => 'Apto para mi vehículo';
	@override String myVehicleFitsHeight({required Object height}) => 'Apto para ${height}';
	@override String myVehicleHint({required Object height}) => 'Oculta los lugares con un límite de altura inferior a ${height}. Los lugares sin altura conocida siguen en el mapa.';
	@override String get reset => 'Borrar todo';
	@override String get apply => 'Aplicar';
	@override String show({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		zero: 'Ningún lugar coincide',
		one: 'Mostrar ${count} lugar',
		other: 'Mostrar ${count} lugares',
	);
	@override String active({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} filtro activo',
		other: '${n} filtros activos',
	);
}

// Path: place
class _Translations$place$es extends Translations$place$en {
	_Translations$place$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String unnamedIn({required Object kind, required Object town}) => '${kind} en ${town}';
	@override String away({required Object distance}) => 'a ${distance}';
	@override String get directions => 'Ruta';
	@override String get share => 'Compartir';
	@override String get save => 'Guardar';
	@override String get saved => 'Guardado';
	@override String get saveHint => 'En Mis favoritos. Mantén pulsado para elegir listas.';
	@override String get saveTo => 'Guardar en una lista';
	@override String get chooseLists => 'Listas';
	@override String get savedToast => 'Añadido a Mis favoritos';
	@override String get removedToast => 'Quitado de Mis favoritos';
	@override String get pricePerNight => 'Precio por noche';
	@override String get priceFree => 'Gratis';
	@override String get priceUnknown => 'Sin indicar';
	@override String get priceServices => 'Servicios';
	@override String get priceIncluded => 'Incluidos';
	@override String priceIncludes({required Object items}) => 'El precio de la noche incluye: ${items}';
	@override late final _Translations$place$inclusions$es inclusions = _Translations$place$inclusions$es._(_root);
	@override String get maxHeight => 'Altura máx.';
	@override String get capacity => 'Plazas';
	@override String get classification => 'Categoría';
	@override String classStars({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} estrella',
		other: '${n} estrellas',
	);
	@override String get hours => 'Horario';
	@override String get services => 'Servicios';
	@override String get noServices => 'No se indica ningún servicio.';
	@override String get activities => 'En los alrededores';
	@override String get description => 'Descripción';
	@override String get contact => 'Contacto';
	@override String get website => 'Sitio web';
	@override String get call => 'Llamar';
	@override String get coordinates => 'Coordenadas';
	@override String get copy => 'Copiar coordenadas';
	@override String get copyShort => 'Copiar';
	@override String copyAs({required Object format}) => 'Copiar como ${format}';
	@override String copiesAs({required Object format}) => '«Copiar» copia: ${format}';
	@override String copied({required Object text}) => 'Copiado: ${text}';
	@override String get otherFormats => 'Elegir el formato que se copia';
	@override String get formatDecimal => 'Grados decimales';
	@override String get formatDms => 'Grados, minutos, segundos';
	@override String get formatGeo => 'Enlace geo:';
	@override String get formatGoogle => 'Enlace de Google Maps';
	@override String get formatOsm => 'Enlace de OpenStreetMap';
	@override String get sources => 'Fuentes';
	@override String fetched({required Object when}) => 'Consultado ${when}';
	@override String get viewSource => 'Ver en la fuente';
	@override String get gone => 'Este lugar ya no está en el mapa';
	@override String get goneHint => 'Se ha retirado o se ha fusionado con otro desde la última actualización.';
	@override String get arriving => 'Este lugar todavía se está descargando';
	@override String get arrivingHint => 'Los lugares de Francia se están descargando para que el mapa funcione sin conexión. La ficha se abrirá en cuanto se descargue este lugar.';
	@override String get loadError => 'No se ha podido cargar este lugar.';
	@override String get openFailed => 'Ninguna aplicación ha podido abrir este enlace.';
	@override String get photos => 'Fotos';
	@override String get extrasOffline => 'Las fotos y las reseñas necesitan conexión.';
	@override String get reviewsTitle => 'Reseñas';
	@override String reviewsCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} reseña',
		other: '${n} reseñas',
	);
	@override String get noReviews => 'Todavía no hay reseñas.';
	@override String get noOtherReviews => 'Todavía no hay más reseñas.';
	@override String get moreReviews => 'Más reseñas';
	@override String get moreReviewsFailed => 'No se han podido cargar más reseñas. Toca para volver a intentarlo.';
	@override String stars({required Object rating}) => '${rating} sobre 5';
	@override String externalRatingsLabel({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'reseña externa',
		other: 'reseñas externas',
	);
	@override String get deletedAccount => 'Cuenta eliminada';
	@override late final _Translations$place$reviewVehicle$es reviewVehicle = _Translations$place$reviewVehicle$es._(_root);
	@override String originalLanguage({required Object language}) => 'Texto original en ${language}';
	@override String photoPosition({required Object index, required Object count}) => 'Foto ${index} de ${count}';
	@override String get previousPhoto => 'Foto anterior';
	@override String get nextPhoto => 'Foto siguiente';
	@override String get links => 'En otros sitios web';
	@override String sourceWithLicence({required Object source, required Object licence}) => '${source} · ${licence}';
	@override String get licenceCcBy => 'CC BY 4.0';
	@override String photoCredit({required Object source, required Object author}) => '${source} · ${author}';
	@override String get photoStreetView => 'Vista de la calle';
	@override String get photoSurroundings => 'Alrededores';
	@override String excerptFrom({required Object source, required Object text}) => 'Según ${source}: ${text}';
	@override String get readMore => 'Leer más';
	@override String updatedOn({required Object date}) => 'actualizado el ${date}';
	@override String get otherSources => 'Según otras fuentes';
}

// Path: sources
class _Translations$sources$es extends Translations$sources$en {
	_Translations$sources$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$sources$extcom$es extcom = _Translations$sources$extcom$es._(_root);
}

// Path: hours
class _Translations$hours$es extends Translations$hours$en {
	_Translations$hours$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get open => 'Abierto ahora';
	@override String openUntil({required Object time}) => 'Abierto, cierra a las ${time}';
	@override String openUntilDay({required Object day, required Object time}) => 'Abierto, cierra ${day} a las ${time}';
	@override String closesIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Abierto, cierra en ${n} minuto',
		other: 'Abierto, cierra en ${n} minutos',
	);
	@override String closedUntil({required Object time}) => 'Cerrado, abre a las ${time}';
	@override String closedUntilDay({required Object day, required Object time}) => 'Cerrado, abre ${day} a las ${time}';
	@override String opensIn({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Cerrado, abre en ${n} minuto',
		other: 'Cerrado, abre en ${n} minutos',
	);
	@override String get closedWindow => 'Cerrado durante las próximas dos semanas';
	@override String get tomorrow => 'mañana';
	@override String onDate({required Object date}) => 'el ${date}';
	@override String onWeekday({required Object day}) => 'el ${day}';
	@override String get midnight => '24:00';
	@override String get stale => '¿Abierto o cerrado? Actualiza los lugares en Perfil.';
	@override String get localTime => 'Horario en hora local del lugar';
	@override late final _Translations$hours$codes$es codes = _Translations$hours$codes$es._(_root);
	@override late final _Translations$hours$months$es months = _Translations$hours$months$es._(_root);
	@override String dayOfMonth({required Object day, required Object month}) => '${day} ${month}';
	@override String dayOfYear({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}';
	@override String get allWeek => '24 horas, todos los días';
	@override String get allYear => 'todo el año';
	@override String get seasonAllYear => 'Abierto todo el año';
	@override String seasonOpenUntil({required Object date}) => 'Abierto hasta el ${date}';
	@override String seasonClosedUntil({required Object date}) => 'Cerrado, abre el ${date}';
}

// Path: directions
class _Translations$directions$es extends Translations$directions$en {
	_Translations$directions$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Abrir en';
	@override String get hint => 'Estas aplicaciones no conocen las dimensiones de tu vehículo.';
	@override String get remember => 'Usar siempre esta aplicación';
	@override String get rememberHint => 'Puedes cambiarlo en Perfil';
	@override String get settingTitle => 'Abrir en otra aplicación';
	@override String get settingHint => 'La aplicación que se abre al tocar «Abrir en» en una ruta';
	@override String get askEachTime => 'Preguntar cada vez';
	@override String get appleMaps => 'Mapas';
	@override String get googleMaps => 'Google Maps';
	@override String get waze => 'Waze';
	@override String get osmAnd => 'OsmAnd';
	@override String get organicMaps => 'Organic Maps';
	@override String get magicEarth => 'Magic Earth';
	@override String get openStreetMap => 'OpenStreetMap (navegador)';
	@override String get none => 'No se ha encontrado ninguna aplicación de navegación en este dispositivo.';
}

// Path: navigation
class _Translations$navigation$es extends Translations$navigation$en {
	_Translations$navigation$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$preview$es preview = _Translations$navigation$preview$es._(_root);
	@override late final _Translations$navigation$stops$es stops = _Translations$navigation$stops$es._(_root);
	@override late final _Translations$navigation$fuel$es fuel = _Translations$navigation$fuel$es._(_root);
	@override late final _Translations$navigation$onTheWay$es onTheWay = _Translations$navigation$onTheWay$es._(_root);
	@override late final _Translations$navigation$states$es states = _Translations$navigation$states$es._(_root);
	@override late final _Translations$navigation$noRoute$es noRoute = _Translations$navigation$noRoute$es._(_root);
	@override late final _Translations$navigation$ferry$es ferry = _Translations$navigation$ferry$es._(_root);
	@override late final _Translations$navigation$warning$es warning = _Translations$navigation$warning$es._(_root);
	@override late final _Translations$navigation$roadEvents$es roadEvents = _Translations$navigation$roadEvents$es._(_root);
	@override late final _Translations$navigation$marks$es marks = _Translations$navigation$marks$es._(_root);
	@override late final _Translations$navigation$guidance$es guidance = _Translations$navigation$guidance$es._(_root);
	@override late final _Translations$navigation$voice$es voice = _Translations$navigation$voice$es._(_root);
	@override late final _Translations$navigation$units$es units = _Translations$navigation$units$es._(_root);
	@override late final _Translations$navigation$settings$es settings = _Translations$navigation$settings$es._(_root);
}

// Path: list
class _Translations$list$es extends Translations$list$en {
	_Translations$list$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Lugares cercanos';
	@override String get empty => 'No hay lugares por aquí con estos filtros';
	@override String get emptyHint => 'Mueve el mapa, aléjalo o quita algún filtro.';
	@override String get downloading => 'Los lugares están llegando';
	@override String get downloadingHint => 'La lista se va llenando durante la descarga.';
	@override String get error => 'No se ha podido cargar la lista.';
	@override String get offline => 'Sin conexión: la lista necesita conexión.';
	@override String get moreFailed => 'No se han podido cargar más lugares. Reintentar';
	@override String get sortDistance => 'Distancia';
	@override String get sortRating => 'Valoración';
	@override String get sortNewest => 'Añadidos recientemente';
	@override String sortedBy({required Object sort}) => 'Lista ordenada por: ${sort}';
	@override String rankedAmongNearestYou({required Object n}) => 'Ordenados entre los ${n} lugares más cercanos a ti';
	@override String rankedAmongNearestCentre({required Object n}) => 'Ordenados entre los ${n} lugares más cercanos al centro del mapa';
	@override String get offlineTitle => 'Sin conexión';
	@override String get offlineNotHere => 'Nada de esta zona en este dispositivo.';
}

// Path: favorites
class _Translations$favorites$es extends Translations$favorites$en {
	_Translations$favorites$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Favoritos';
	@override String get defaultList => 'Mis favoritos';
	@override String get empty => 'Todavía no hay nada guardado aquí';
	@override String get emptyHint => 'Toca Guardar en un lugar para conservarlo, incluso sin conexión.';
	@override String get newList => 'Nueva lista';
	@override String get listName => 'Nombre de la lista';
	@override String get renameList => 'Cambiar el nombre de la lista';
	@override String get deleteList => 'Eliminar la lista';
	@override String deleteListConfirm({required Object name}) => '¿Eliminar «${name}»? Los lugares siguen en el mapa.';
	@override String get listActions => 'Opciones de la lista';
	@override String get placeActions => 'Opciones del lugar';
	@override String get openOnMap => 'Ver en el mapa';
	@override String get remove => 'Quitar de la lista';
	@override String get removed => 'Quitado de la lista';
	@override String count({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		zero: 'Vacía',
		one: '${n} lugar',
		other: '${n} lugares',
	);
	@override String get error => 'No se han podido cargar tus favoritos.';
}

// Path: vehicle
class _Translations$vehicle$es extends Translations$vehicle$en {
	_Translations$vehicle$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mi vehículo';
	@override String get why => 'Las dimensiones de tu vehículo sirven para ocultar los lugares a los que no puede acceder. Se envían con cada solicitud de ruta y no se guardan.';
	@override String get none => 'Describe tu vehículo para ocultar los lugares a los que no puede acceder.';
	@override String get add => 'Describir mi vehículo';
	@override String get edit => 'Editar';
	@override String get type => 'Tipo';
	@override late final _Translations$vehicle$types$es types = _Translations$vehicle$types$es._(_root);
	@override String get towingTitle => 'Remolque';
	@override late final _Translations$vehicle$towing$es towing = _Translations$vehicle$towing$es._(_root);
	@override String get size => 'Dimensiones';
	@override String get sizeHint => 'Valores habituales del tipo elegido: corrígelos con los de la ficha técnica de tu vehículo.';
	@override String get height => 'Altura';
	@override String get width => 'Anchura';
	@override String get length => 'Longitud total, remolque incluido';
	@override String get weight => 'Masa máxima autorizada (MMA)';
	@override String heightShort({required Object value}) => 'Alto ${value}';
	@override String widthShort({required Object value}) => 'Ancho ${value}';
	@override String lengthShort({required Object value}) => 'Largo ${value}';
	@override String get notANumber => 'Un número, por ejemplo 2,90';
	@override String outOfRange({required Object min, required Object max, required Object unit}) => 'Entre ${min} y ${max} ${unit}';
	@override String get navigationLater => 'La navegación de Lunaway tiene en cuenta todas estas dimensiones.';
	@override String get save => 'Guardar';
	@override String get clear => 'Borrar';
	@override String get fuelTitle => 'Combustible';
	@override String get fuelHint => 'El precio de tu combustible aparece en las gasolineras del mapa, empezando por las más baratas.';
	@override String get consumption => 'Consumo';
	@override String get consumptionUnit => 'l/100 km';
	@override String get lpgHeating => 'Calefacción de GLP';
	@override String get lpgHeatingHint => 'El precio del GLP también aparece en las gasolineras.';
	@override String get cruiseTitle => 'Velocidad máxima de crucero';
	@override String get cruiseHint => 'Los tiempos de trayecto suponen que nunca vas más rápido, aunque la carretera lo permita. Los límites de velocidad que se anuncian durante la navegación siguen siendo los de la carretera.';
	@override String get cruiseNone => 'Sin límite';
}

// Path: vehicleHeight
class _Translations$vehicleHeight$es extends Translations$vehicleHeight$en {
	_Translations$vehicleHeight$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Altura de tu vehículo';
	@override String get why => 'Se ocultarán los lugares con un límite de altura más bajo. Los lugares sin altura conocida siguen en el mapa.';
	@override String get needed => 'Indica la altura, por ejemplo 2,90';
	@override String get weightOptional => 'Masa máxima autorizada (opcional)';
	@override String get apply => 'Filtrar con esta altura';
	@override String get later => 'El resto del vehículo se describe en Perfil, Mi vehículo.';
}

// Path: profile
class _Translations$profile$es extends Translations$profile$en {
	_Translations$profile$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Perfil';
	@override String get noAccountNeeded => 'Sin cuenta, sin publicidad, sin rastreadores. Tus favoritos se quedan en este dispositivo.';
	@override String get language => 'Idioma';
	@override String get languageSystem => 'Igual que el dispositivo';
	@override String get appearance => 'Apariencia';
	@override String get themeAuto => 'Automático';
	@override String get themeLight => 'Claro';
	@override String get themeDark => 'Oscuro';
	@override String get themeAutoHint => 'Claro de día, oscuro tras la puesta de sol donde estés.';
	@override String get themeLightHint => 'Siempre claro, de día y de noche.';
	@override String get themeDarkHint => 'Siempre oscuro, más cómodo para la vista de noche.';
	@override String get offline => 'Sin conexión';
	@override String placesOnDevice({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'lugar en este dispositivo',
		other: 'lugares en este dispositivo',
	);
	@override String offlineSize({required Object size}) => 'Espacio usado: ${size}';
	@override String lastSync({required Object when}) => 'Última actualización ${when}';
	@override String get neverSynced => 'Nunca descargado';
	@override String get syncNow => 'Actualizar ahora';
	@override String get syncing => 'Actualizando';
	@override String get about => 'Acerca de';
	@override String version({required Object version}) => 'Versión ${version}';
	@override String get website => 'Sitio web';
	@override String get privacy => 'Política de privacidad';
	@override String get sourceCode => 'Código fuente';
	@override String get licences => 'Licencias';
	@override String get appLicence => 'Lunaway es software libre bajo licencia GNU AGPL 3.0 o posterior.';
	@override String get attributions => 'Fuentes y créditos';
	@override String get attributionOsm => 'Lugares y datos cartográficos © colaboradores de OpenStreetMap.';
	@override String get attributionOdbl => 'Datos de OpenStreetMap bajo licencia Open Database License (ODbL).';
	@override String get attributionAtout => 'Campings clasificados de Atout France, bajo Licence Ouverte 2.0 (Etalab).';
	@override String get attributionCommunes => 'Municipios de los lugares: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), bajo licencia ODbL.';
	@override String get attributionTiles => 'Mapa base servido por Lunaway, estilos derivados de Protomaps (BSD-3-Clause), datos © colaboradores de OpenStreetMap.';
	@override String get attributionFonts => 'Tipografías Fraunces y Atkinson Hyperlegible Next, bajo licencia SIL Open Font License 1.1.';
	@override String get attributionIcons => 'Iconos Phosphor, bajo licencia MIT.';
	@override String get noTracking => 'Sin publicidad ni rastreadores. Tu cuenta no guarda ni tu correo electrónico ni tu número de teléfono.';
	@override String get attributionBdTopo => 'Límites de altura, anchura, longitud y peso de las carreteras, y campings situados por su nombre: BD TOPO del IGN, a través de la Géoplateforme, bajo Licence Ouverte 2.0.';
	@override String get attributionAddresses => 'Direcciones de la búsqueda en Francia: Base Adresse Nationale, a través de la Géoplateforme del IGN, bajo Licence Ouverte 2.0.';
	@override String get attributionAddressesOsm => 'Direcciones de la búsqueda en otros países: OpenStreetMap, a través de Photon, bajo ODbL.';
	@override String get attributionPoiOdbl => 'Comercios y servicios: OpenStreetMap y el calendario de apertura de La Poste, bajo ODbL.';
	@override String get attributionPoiLo => 'Precios de los combustibles (Ministerio de Economía de Francia) y centros sanitarios FINESS, bajo Licence Ouverte 2.0 (Etalab).';
	@override String get attributionPacks => 'Contornos de los mapas sin conexión: Contours administratifs, data.gouv.fr (ODbL), y Natural Earth (dominio público).';
	@override String get attributionOfflineLabels => 'Nombres e iconos de los mapas sin conexión: glifos Noto Sans (SIL Open Font License 1.1) y sprites de Protomaps derivados de tangrams/icons (MIT).';
	@override String get attributionExtcom => 'Lugares, reseñas, valoraciones y fotos, bajo acuerdo escrito con esta fuente.';
	@override String get creditsPlaces => 'Lugares';
	@override String get creditsContent => 'Fotos, textos y reseñas';
	@override String get creditsRoutes => 'Rutas y navegación';
	@override String get creditsSearch => 'Búsqueda';
	@override String get creditsMap => 'Mapa base';
	@override String get creditsApp => 'Aplicación';
	@override String get attributionDatatourisme => 'Lugares, descripciones y fotos de las oficinas de turismo: DATAtourisme, bajo Licence Ouverte 2.0; cada texto y cada foto indica su oficina, su autor y la fecha de su última actualización.';
	@override String get attributionCommunity => 'Reseñas, valoraciones y fotos de los viajeros de Lunaway, bajo licencia CC BY 4.0, con el seudónimo de su autor.';
	@override String get attributionCommons => 'Fotos de Wikimedia Commons, cada una bajo su propia licencia (CC0, CC BY o CC BY-SA), con su autor y un enlace a su página.';
	@override String get attributionPanoramax => 'Vistas de la calle de Panoramax: instancia de OpenStreetMap France bajo licencia CC BY-SA 4.0, instancia del IGN bajo Licence Ouverte 2.0.';
	@override String get attributionWikipedia => 'Extractos de artículos de Wikipedia, bajo licencia CC BY-SA 4.0, con un enlace al artículo.';
	@override String get attributionMangrove => 'Reseñas de Mangrove Reviews, bajo licencia CC BY 4.0 o la licencia que indique la reseña, con un enlace a la reseña.';
	@override String get attributionRoadEvents => 'Obras y cortes en Francia: DIR y Bison Futé, resoluciones de tráfico DiaLog (DGITM), metrópolis y departamentos (Lyon, Toulouse, Burdeos, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d\'Armor, Sarthe), bajo Licence Ouverte 2.0; Rennes Métropole y los avisos de los viajeros de Lunaway, bajo ODbL.';
	@override String get attributionRoadEventsAbroad => 'Obras y cortes en los Países Bajos: NDW, Nationaal Dataportaal Wegverkeer (datos abiertos); en España: DGT, Dirección General de Tráfico (CC BY).';
	@override String get attributionDangerZones => 'Zonas de peligro: listas oficiales de radares (Sécurité routière en Francia, reutilizada conforme al Code des relations entre le public et l\'administration francés; Polonia y Luxemburgo, CC0; Cataluña, licencia abierta de la Generalitat; Noruega, NLOD) y OpenStreetMap (ODbL).';
}

// Path: units
class _Translations$units$es extends Translations$units$en {
	_Translations$units$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String kilobytes({required Object n}) => '${n} kB';
	@override String megabytes({required Object n}) => '${n} MB';
}

// Path: languages
class _Translations$languages$es extends Translations$languages$en {
	_Translations$languages$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get fr => 'francés';
	@override String get en => 'inglés';
	@override String get de => 'alemán';
	@override String get es => 'español';
	@override String get it => 'italiano';
	@override String get nl => 'neerlandés';
}

// Path: translation
class _Translations$translation$es extends Translations$translation$en {
	_Translations$translation$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get translate => 'Traducir';
	@override String get translating => 'Traduciendo';
	@override String get showOriginal => 'Ver el original';
	@override String get showTranslation => 'Ver la traducción';
	@override late final _Translations$translation$from$es from = _Translations$translation$from$es._(_root);
	@override String get offline => 'Para traducir hace falta conexión a internet.';
	@override String get failedOffline => 'Sin conexión: no se ha podido traducir el texto.';
	@override String get busy => 'El servicio de traducción está saturado. Vuelve a intentarlo más tarde.';
	@override String get unavailable => 'La traducción no está disponible en este momento.';
	@override String get gone => 'Este texto ya no está disponible.';
	@override String get unsupported => 'No hay traducción disponible para este idioma.';
	@override String get autoReviews => 'Traducir las reseñas automáticamente';
	@override String get autoReviewsHint => 'Las reseñas escritas en otro idioma se traducen en el propio servidor de Lunaway, sin pasar por servicios de terceros.';
}

// Path: locale
class _Translations$locale$es extends Translations$locale$en {
	_Translations$locale$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get en => 'English';
	@override String get fr => 'Français';
	@override String get de => 'Deutsch';
	@override String get es => 'Español';
	@override String get it => 'Italiano';
	@override String get nl => 'Nederlands';
}

// Path: account
class _Translations$account$es extends Translations$account$en {
	_Translations$account$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Tu cuenta';
	@override String get noneTitle => 'Todavía no tienes cuenta';
	@override String get noneBody => 'El mapa, la búsqueda y los favoritos funcionan sin cuenta. La cuenta se crea sola con tu primera contribución (una valoración, una confirmación, una foto), sin correo electrónico ni contraseña. A partir de ese momento, tus listas de favoritos quedan vinculadas a ella.';
	@override String get recover => 'Recuperar mi cuenta';
	@override String memberSince({required Object date}) => 'Miembro desde ${date}';
	@override String get editPseudonym => 'Cambiar el seudónimo';
	@override String get pseudonymTitle => 'Tu seudónimo';
	@override String get pseudonymHint => 'Público: acompaña a tus reseñas y fotos. De 3 a 32 caracteres.';
	@override String get pseudonymInvalid => 'De 3 a 32 caracteres, con al menos dos letras.';
	@override String get pseudonymRefused => 'Este seudónimo no se acepta: ni enlaces, ni datos de contacto, ni insultos, ni nombres que se hagan pasar por el equipo de Lunaway.';
	@override String get pseudonymSaved => 'Seudónimo guardado';
	@override String level({required Object level}) => 'Nivel de confianza ${level}';
	@override late final _Translations$account$levelOpens$es levelOpens = _Translations$account$levelOpens$es._(_root);
	@override String nextLevel({required Object level}) => 'Para el nivel ${level}';
	@override String get levelTop => 'Estás en el nivel más alto.';
	@override late final _Translations$account$requirement$es requirement = _Translations$account$requirement$es._(_root);
	@override String orInstead({required Object requirement}) => 'O bien ${requirement}';
	@override String get recoveryNone => 'No se ha creado ninguna tarjeta de recuperación en este dispositivo. Sin ella, esta cuenta solo existe en este dispositivo: si lo pierdes, pierdes también la cuenta.';
	@override String get recoveryNoneAccount => 'Esta cuenta todavía no tiene tarjeta de recuperación. Sin ella, esta cuenta solo existe en este dispositivo: si lo pierdes, pierdes también la cuenta.';
	@override String get recoveryCreate => 'Crear mi tarjeta de recuperación';
	@override String recoveryMade({required Object date}) => 'Creada el ${date}';
	@override String get recoveryRemake => 'Rehacer';
	@override String get recoveryRemakeHint => 'Crear una nueva tarjeta de recuperación';
	@override String get contributions => 'Mis contribuciones';
	@override String pending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} contribución pendiente de envío',
		other: '${n} contribuciones pendientes de envío',
	);
	@override String get mutedAuthors => 'Autores ocultos';
	@override String get devices => 'Dispositivos';
	@override String get signOut => 'Cerrar sesión';
	@override String get delete => 'Eliminar mi cuenta';
	@override String get signOutTitle => '¿Cerrar sesión en este dispositivo?';
	@override String get signOutBody => 'La clave de la cuenta se borra de este dispositivo. Para volver, necesitarás tu tarjeta de recuperación. Tus favoritos se quedan aquí.';
	@override String get signOutNoCard => 'No has creado ninguna tarjeta de recuperación en este dispositivo. Sin ella, esta cuenta se perderá para siempre.';
	@override String signOutPending({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Una contribución pendiente no se enviará.',
		other: '${n} contribuciones pendientes no se enviarán.',
	);
	@override String get signedOut => 'Sesión cerrada. Tus favoritos se quedan en este dispositivo.';
	@override String get lost => 'Esta cuenta ya no se abre en este dispositivo. Recupérala con tu tarjeta de recuperación: Perfil, Recuperar mi cuenta.';
	@override String get lostAction => 'Recuperar';
	@override String get welcomeTitle => 'Gracias por tu primera contribución';
	@override String welcomeBody({required Object name}) => 'Tu cuenta está creada, con el seudónimo «${name}». Sin correo electrónico ni contraseña: una clave guardada en este dispositivo. Puedes cambiar el seudónimo en tu perfil.';
	@override String get welcomeCard => 'Crea tu tarjeta de recuperación para recuperar esta cuenta en otro dispositivo.';
	@override String get welcomeFavorites => 'Tus listas de favoritos ahora se guardan con tu cuenta.';
}

// Path: recovery
class _Translations$recovery$es extends Translations$recovery$en {
	_Translations$recovery$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Tarjeta de recuperación';
	@override String get intro => 'Un código que lleva tu cuenta a un dispositivo nuevo. Lunaway solo guarda una huella del código, suficiente para comprobarlo: el código en sí no se puede volver a mostrar nunca, y cada tarjeta nueva tiene un código distinto.';
	@override String get replaces => 'Una tarjeta nueva sustituye a la anterior: el código antiguo dejará de funcionar.';
	@override String replaceTitle({required Object date}) => '¿Sustituir la tarjeta del ${date}?';
	@override String replaceBody({required Object date}) => 'La tarjeta nueva tendrá otro código. El de la tarjeta del ${date} deja de funcionar ahora mismo. No se puede volver a mostrar: Lunaway solo guarda una huella.';
	@override String get replaceKeep => 'Conservar la antigua';
	@override String get replaceConfirm => 'Crear una tarjeta nueva';
	@override String get make => 'Crear la tarjeta';
	@override String get codeLabel => 'Tu código de recuperación';
	@override String get shownOnce => 'Este código solo se muestra una vez. Anótalo, o guarda la imagen, antes de cerrar.';
	@override String get saveImage => 'Guardar la imagen';
	@override String get done => 'He anotado el código';
	@override String get doneTitle => '¿Has guardado el código?';
	@override String get doneBody => 'Cuando cierres esta página, no volverá a mostrarse.';
	@override String get keep => 'Seguir en la página';
	@override String get cardHeading => 'Tarjeta de recuperación de Lunaway';
	@override String cardAccount({required Object name}) => 'Cuenta: ${name}';
	@override String get cardHow => 'Para recuperar la cuenta: Perfil, Recuperar mi cuenta, y luego escribe este código o fotografía la tarjeta.';
	@override String cardMade({required Object date}) => 'Creada el ${date}';
	@override String get cardWarning => 'Este código da acceso a tu cuenta: no se lo des a nadie.';
	@override String get failed => 'No se ha podido crear la tarjeta. Se necesita conexión.';
	@override String get fileName => 'tarjeta-de-recuperacion-lunaway';
	@override String get step1 => 'Crea la tarjeta: el código solo se muestra una vez.';
	@override String get step2 => 'Guarda la imagen, imprímela o copia el código a mano.';
	@override String get step3 => 'Guárdala en la guantera, con la documentación del vehículo.';
}

// Path: recover
class _Translations$recover$es extends Translations$recover$en {
	_Translations$recover$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Recuperar mi cuenta';
	@override String get intro => 'Escribe el código de tu tarjeta de recuperación o escanéalo desde una foto de la tarjeta.';
	@override String get field => 'Código de recuperación';
	@override String get fieldHint => '27 caracteres, en grupos de cuatro';
	@override String remaining({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Falta ${n} carácter',
		other: 'Faltan ${n} caracteres',
	);
	@override String get invalid => 'Este código no corresponde a ninguna tarjeta: comprueba cada carácter.';
	@override String get valid => 'Código completo';
	@override String get scan => 'Escanear la tarjeta desde una foto';
	@override String get scanFile => 'Elegir la imagen de la tarjeta';
	@override String get reading => 'Leyendo la tarjeta';
	@override String get scanFailed => 'No hay ningún código legible en esta imagen. Prueba con una foto más nítida, con la tarjeta bien plana.';
	@override String get revoke => 'Mi antiguo dispositivo se ha perdido o me lo han robado: cerrar su sesión';
	@override String get revokeHint => 'Se cerrará la sesión en todos tus demás dispositivos.';
	@override String get submit => 'Recuperar la cuenta';
	@override String get notFound => 'Ninguna cuenta tiene este código. Comprueba la tarjeta o crea una nueva desde un dispositivo con la sesión iniciada.';
	@override String get tooMany => 'Demasiados intentos por ahora. Vuelve a intentarlo dentro de una hora.';
	@override String done({required Object name}) => 'Cuenta recuperada: ${name}';
}

// Path: deletion
class _Translations$deletion$es extends Translations$deletion$en {
	_Translations$deletion$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Eliminar mi cuenta';
	@override String get intro => 'La eliminación es inmediata y definitiva.';
	@override String get goneTitle => 'Lo que se elimina';
	@override late final _Translations$deletion$gone$es gone = _Translations$deletion$gone$es._(_root);
	@override String get keptTitle => 'Lo que se conserva, sin tu nombre';
	@override String get kept => 'Tus reseñas escritas publicadas, tus confirmaciones y tus cambios de lugares ya aplicados se conservan, sin autor: forman parte del mapa de otros viajeros.';
	@override String get backups => 'Las copias de seguridad del servidor se borran en unos 30 días.';
	@override String get device => 'En este dispositivo, tus favoritos se quedan; la clave de la cuenta se borra.';
	@override String get web => 'También puedes eliminarla en lunaway.net con tu código de recuperación.';
	@override String get webLink => 'lunaway.net/account/delete';
	@override String get confirmTitle => '¿Eliminar definitivamente?';
	@override String confirmBody({required Object name}) => 'La cuenta «${name}» y todo lo indicado se eliminan ahora. Nadie podrá recuperarla.';
	@override String get confirmCheck => 'Entiendo que es definitivo';
	@override String get confirm => 'Eliminar la cuenta';
	@override String get done => 'Cuenta eliminada';
	@override String get failed => 'No se ha podido eliminar la cuenta. Se necesita conexión.';
}

// Path: devices
class _Translations$devices$es extends Translations$devices$en {
	_Translations$devices$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Dispositivos';
	@override String get intro => 'Cada dispositivo tiene su propia clave. Quita un dispositivo perdido o uno que ya no uses.';
	@override String get thisDevice => 'Este dispositivo';
	@override String get other => 'Otro dispositivo';
	@override String added({required Object date}) => 'Añadido el ${date}';
	@override String lastUsed({required Object when}) => 'Último uso ${when}';
	@override String get revoke => 'Quitar';
	@override String get revokeTitle => '¿Quitar este dispositivo?';
	@override String get revokeBody => 'Se cerrará su sesión y ya no podrá usar la cuenta.';
	@override String get revoked => 'Dispositivo quitado';
	@override String get signOutOthers => 'Cerrar sesión en todos los demás dispositivos';
	@override String signedOutOthers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		zero: 'No hay ninguna otra sesión abierta',
		one: '${n} sesión cerrada',
		other: '${n} sesiones cerradas',
	);
	@override String get error => 'No se han podido cargar los dispositivos. Se necesita conexión.';
}

// Path: muted
class _Translations$muted$es extends Translations$muted$en {
	_Translations$muted$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Autores ocultos';
	@override String get empty => 'No hay nadie oculto';
	@override String get emptyHint => 'Para ocultar a alguien, abre el menú de una de sus reseñas o fotos. Solo se oculta para ti.';
	@override String get unmute => 'Volver a mostrar';
	@override String unmuted({required Object name}) => 'Las contribuciones de ${name} volverán a mostrarse';
}

// Path: mine
class _Translations$mine$es extends Translations$mine$en {
	_Translations$mine$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mis contribuciones';
	@override String get pending => 'Pendientes de envío';
	@override String get pendingHint => 'Se enviarán en cuanto vuelva la conexión.';
	@override String get sendNow => 'Enviar ahora';
	@override String get retry => 'Reintentar';
	@override String get discard => 'Descartar';
	@override String get discardTitle => '¿Descartar esta contribución?';
	@override String get discardBody => 'No se enviará.';
	@override String get reviews => 'Reseñas y valoraciones';
	@override String get photos => 'Fotos';
	@override String get confirmations => 'Confirmaciones';
	@override String get issues => 'Avisos de problemas';
	@override String get places => 'Lugares añadidos y cambios';
	@override String get empty => 'Nada por ahora';
	@override String get emptyHint => 'Valorar un lugar o confirmar que sigue ahí ya cuenta como contribución.';
	@override String latest({required Object shown, required Object total}) => 'Las ${shown} más recientes de ${total}';
	@override String get error => 'No se han podido cargar tus contribuciones. Se necesita conexión.';
	@override String get deleteTitle => '¿Eliminar esta contribución?';
	@override String get deleteBody => 'Se borrará de Lunaway.';
	@override String get deleteApplied => 'Este lugar ya forma parte del mapa: se queda en él, sin tu nombre.';
	@override String get deleted => 'Contribución eliminada';
	@override String get ratingOnly => 'Solo valoración';
	@override late final _Translations$mine$status$es status = _Translations$mine$status$es._(_root);
	@override late final _Translations$mine$submission$es submission = _Translations$mine$submission$es._(_root);
	@override String get newPlace => 'Nuevo lugar';
	@override String get edit => 'Cambio';
	@override String get aPlace => 'Un lugar';
	@override String get newVendingMachine => 'Nueva máquina expendedora';
	@override String get poiConfirmations => 'Comercios y servicios confirmados';
	@override String get aPoi => 'Un comercio o servicio';
}

// Path: outbox
class _Translations$outbox$es extends Translations$outbox$en {
	_Translations$outbox$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$outbox$kind$es kind = _Translations$outbox$kind$es._(_root);
	@override String get waiting => 'Esperando conexión';
	@override String get sending => 'Enviando';
	@override late final _Translations$outbox$error$es error = _Translations$outbox$error$es._(_root);
	@override String get sent => 'Gracias, ya se ha enviado';
	@override String get queued => 'Sin conexión: se enviará cuando vuelva la conexión';
	@override String refused({required Object reason}) => 'No enviado. ${reason}';
}

// Path: placement
class _Translations$placement$es extends Translations$placement$en {
	_Translations$placement$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Sitúa el lugar';
	@override String get hint => 'Mueve el mapa: la cruz marca el punto exacto.';
	@override String get confirm => 'Confirmar este punto';
	@override String duplicate({required Object name, required Object distance}) => 'Ya hay «${name}» a ${distance}: ¿es el mismo sitio?';
	@override String get same => 'Sí, abrir su ficha';
	@override String get notSame => 'No, es otro lugar';
}

// Path: contribute
class _Translations$contribute$es extends Translations$contribute$en {
	_Translations$contribute$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get yourRating => 'Tu valoración';
	@override String get rateHint => 'Toca una estrella para valorar';
	@override String rateStar({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Valorar con ${n} estrella',
		other: 'Valorar con ${n} estrellas',
	);
	@override String get writeReview => 'Escribir una reseña';
	@override String get editReview => 'Modificar tu reseña';
	@override String get deleteReview => 'Eliminar tu reseña';
	@override String get deleteReviewTitle => '¿Eliminar tu reseña?';
	@override String get deleteReviewBody => 'El texto y la valoración desaparecen de la ficha.';
	@override String get deleteRating => 'Quitar tu valoración';
	@override String get deleteRatingTitle => '¿Quitar tu valoración?';
	@override String get deleteRatingBody => 'Tu valoración desaparece de la ficha del lugar.';
	@override String get pendingSend => 'Pendiente de envío';
	@override String get statusPending => 'En revisión: por ahora solo la ves tú';
	@override String get statusHidden => 'Oculta tras varias denuncias, a la espera de un moderador';
	@override String get statusRemoved => 'Retirada por la moderación';
	@override String get addPhoto => 'Añadir una foto';
	@override String get firstPhoto => 'Añadir la primera foto';
	@override String get stillThere => '¿Sigue ahí?';
	@override String get more => 'Más acciones';
	@override String get reportIssue => 'Avisar de un problema';
	@override String get proposeEdit => 'Proponer un cambio';
	@override String get editPlace => 'Modificar el lugar';
	@override String get reportPlace => 'Denunciar este lugar a la moderación';
	@override String get toVerifyTitle => 'Por verificar';
	@override String get toVerifyBody => 'Añadido por la comunidad, a la espera de dos confirmaciones. ¿Lo conoces? Confírmalo.';
	@override String get issuesTitle => 'Avisos de los últimos 30 días';
	@override String issueCount({required Object kind, required Object count}) => '${kind} (${count})';
	@override String get addPlaceHere => 'Añadir un lugar aquí';
	@override String get addPlaceHint => 'En el punto marcado por la cruz.';
}

// Path: confirmSheet
class _Translations$confirmSheet$es extends Translations$confirmSheet$en {
	_Translations$confirmSheet$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => '¿Sigue ahí?';
	@override String get body => '¿Has estado allí hace poco? Tu respuesta indica a los próximos viajeros que la ficha está al día. No se envía ninguna ubicación.';
	@override String get stillOk => 'Sí, como se describe';
	@override String get closed => 'Cerrado';
	@override String get changed => 'Ha cambiado';
	@override String get closedHint => 'Ya no acoge a viajeros';
	@override String get changedHint => 'Sigue existiendo, pero algo ha cambiado';
	@override String get note => '¿Algo que añadir? (opcional)';
	@override String get noteHint => 'Por ejemplo: han puesto una barra de gálibo, han movido el punto de servicio';
	@override late final _Translations$confirmSheet$status$es status = _Translations$confirmSheet$status$es._(_root);
}

// Path: issueSheet
class _Translations$issueSheet$es extends Translations$issueSheet$en {
	_Translations$issueSheet$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Avisar de un problema';
	@override String get body => 'Tu aviso se suma a la advertencia que aparece en la ficha. Tu comentario solo llega a los moderadores.';
	@override late final _Translations$issueSheet$kind$es kind = _Translations$issueSheet$kind$es._(_root);
	@override late final _Translations$issueSheet$hint$es hint = _Translations$issueSheet$hint$es._(_root);
	@override String get note => '¿Algo que añadir? (opcional)';
	@override String get send => 'Avisar';
}

// Path: reportSheet
class _Translations$reportSheet$es extends Translations$reportSheet$en {
	_Translations$reportSheet$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get review => 'Denunciar esta reseña';
	@override String get photo => 'Denunciar esta foto';
	@override String get place => 'Denunciar este lugar';
	@override String get body => 'Los moderadores lo leerán. El autor no sabrá quién lo ha denunciado.';
	@override late final _Translations$reportSheet$reason$es reason = _Translations$reportSheet$reason$es._(_root);
	@override String get note => 'Cuéntanos más (opcional)';
	@override String get noteOther => 'Explica qué falla';
	@override String get sent => 'Gracias, los moderadores lo revisarán';
	@override String mute({required Object name}) => 'Ocultar las reseñas y fotos de ${name}';
	@override String get muteAuthor => 'Ocultar a este autor';
	@override String muteTitle({required Object name}) => '¿Ocultar a ${name}?';
	@override String get muteBody => 'Sus reseñas y fotos dejarán de mostrarse para ti. Puedes cambiar de opinión en tu perfil.';
	@override String muted({required Object name}) => '${name} está oculto';
	@override String get deletePhoto => 'Eliminar mi foto';
	@override String get deletePhotoTitle => '¿Eliminar esta foto?';
	@override String get deletePhotoBody => 'Desaparece de la ficha y de nuestros servidores.';
}

// Path: reviewSheet
class _Translations$reviewSheet$es extends Translations$reviewSheet$en {
	_Translations$reviewSheet$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get titleNew => 'Tu reseña';
	@override String get titleEdit => 'Modificar tu reseña';
	@override String get starsRequired => 'Elige una valoración de 1 a 5';
	@override String get text => 'Tu reseña';
	@override String get textHint => 'La tranquilidad, la acogida, el espacio para maniobrar, lo que te resultó útil';
	@override String tooShort({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Al menos ${n} carácter más',
		other: 'Al menos ${n} caracteres más',
	);
	@override String get visited => 'Fecha de la estancia';
	@override String get visitedNone => 'Sin indicar';
	@override String get vehicle => 'Tu vehículo';
	@override String get vehicleNone => 'Prefiero no decirlo';
	@override String get licence => 'Se publica bajo licencia CC BY 4.0, con tu seudónimo. La fecha de la estancia es opcional: juntas, las fechas de tus reseñas pueden revelar tu recorrido.';
	@override String get publish => 'Publicar la reseña';
}

// Path: gate
class _Translations$gate$es extends Translations$gate$en {
	_Translations$gate$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get review => 'Reseñas escritas: desde el nivel 1';
	@override String get photo => 'Fotos: desde el nivel 1';
	@override String get addPlace => 'Añadir lugares: desde el nivel 2';
	@override String get edit => 'Proponer cambios: desde el nivel 1';
	@override String get why => 'Los niveles protegen el mapa de los abusos. Llegan con el tiempo y las contribuciones, sin nada que comprar.';
	@override String yourLevel({required Object level}) => 'Tu nivel: ${level}';
	@override String get noAccount => 'Todavía no tienes cuenta: una cuenta empieza en el nivel 0.';
	@override String later({required Object level}) => 'El nivel ${level} llega después de los anteriores, con el tiempo y las contribuciones publicadas.';
	@override String get meanwhile => 'Mientras tanto, puedes valorar lugares, confirmar que siguen ahí o avisar de un problema.';
}

// Path: photoFlow
class _Translations$photoFlow$es extends Translations$photoFlow$en {
	_Translations$photoFlow$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Añadir una foto';
	@override String get camera => 'Hacer una foto';
	@override String get gallery => 'Elegir de la galería';
	@override String get preparing => 'Preparando la foto';
	@override String get licence => 'Se publica bajo licencia CC BY 4.0, con tu seudónimo. Evita las caras y las matrículas.';
	@override String get stripped => 'La ubicación y los datos del dispositivo se eliminan antes del envío.';
	@override String get send => 'Enviar la foto';
	@override String get unreadable => 'Esta imagen no se puede leer en este dispositivo. Prueba con una foto JPEG o PNG.';
	@override String sending({required Object percent}) => 'Enviando ${percent} %';
	@override String get pending => 'Foto pendiente de envío';
}

// Path: placeForm
class _Translations$placeForm$es extends Translations$placeForm$en {
	_Translations$placeForm$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get addTitle => 'Añadir un lugar';
	@override String get editTitle => 'Modificar el lugar';
	@override String get proposeTitle => 'Proponer un cambio';
	@override String get position => 'Ubicación en el mapa';
	@override String get kind => 'Tipo de lugar';
	@override String get kindRequired => 'Elige un tipo de lugar';
	@override String get name => 'Nombre';
	@override String get nameHint => 'El nombre que aparece en el lugar o una descripción breve';
	@override String get nameInvalid => 'De 2 a 120 caracteres';
	@override String get night => 'Pernocta';
	@override String get services => 'Servicios en el lugar';
	@override String get description => 'Descripción';
	@override String get descriptionHint => 'Lo que ayuda a encontrar y elegir el lugar';
	@override String get details => 'Detalles';
	@override String get priceNight => 'Precio por noche (€)';
	@override String get priceServices => 'Precio de los servicios (€)';
	@override String get maxHeight => 'Altura máxima (m)';
	@override String get capacity => 'Plazas';
	@override String get website => 'Sitio web';
	@override String get phone => 'Teléfono';
	@override String get photo => 'Foto (opcional)';
	@override String get photoReady => 'Foto lista';
	@override String get removePhoto => 'Quitar la foto';
	@override String get toVerify => 'El lugar aparecerá como «por verificar» hasta que otros dos viajeros lo confirmen.';
	@override String get licence => 'Los lugares se publican bajo licencia ODbL, con crédito a los colaboradores de Lunaway.';
	@override String get moderated => 'Un sitio web o un número de teléfono pasa por un moderador antes de publicarse.';
	@override String get direct => 'Con tu nivel, el cambio se aplica al momento.';
	@override String get proposal => 'Un moderador revisará tu propuesta antes de aplicarla.';
	@override String get submitAdd => 'Añadir el lugar';
	@override String get submitEdit => 'Guardar el cambio';
	@override String get submitPropose => 'Enviar la propuesta';
	@override String get nothingChanged => 'No ha cambiado nada';
	@override String get invalidNumber => 'Introduce un número';
	@override String get invalidWebsite => 'Una dirección que empiece por http:// o https://';
	@override String get added => 'Gracias: el lugar aparecerá en el mapa en un momento';
	@override String get proposed => 'Gracias: tu propuesta pasa a revisión';
}

// Path: favoritesSync
class _Translations$favoritesSync$es extends Translations$favoritesSync$en {
	_Translations$favoritesSync$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get local => 'Solo en este dispositivo';
	@override String get action => 'Sincronizar';
	@override String get syncing => 'Sincronizando';
	@override String synced({required Object when}) => 'Guardados con tu cuenta, sincronizados ${when}';
	@override String get failed => 'No se puede sincronizar ahora mismo';
	@override String get title => '¿Sincronizar tus favoritos?';
	@override String get body => 'Tus listas se guardarán con una cuenta de Lunaway, sin correo electrónico ni contraseña, para que puedas encontrarlas en otro dispositivo. La cuenta se crea ahora.';
	@override String get confirm => 'Crear la cuenta y sincronizar';
}

// Path: poi
class _Translations$poi$es extends Translations$poi$en {
	_Translations$poi$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$poi$category$es category = _Translations$poi$category$es._(_root);
	@override late final _Translations$poi$kind$es kind = _Translations$poi$kind$es._(_root);
	@override String get chipsLabel => 'Comercios y servicios cercanos';
	@override String get openNow => 'Abierto ahora';
	@override late final _Translations$poi$vendingSells$es vendingSells = _Translations$poi$vendingSells$es._(_root);
	@override String get vendingAll => 'Todas las expendedoras de comida';
	@override String get vendingMenu => 'Lo que venden las expendedoras';
	@override late final _Translations$poi$vendingChip$es vendingChip = _Translations$poi$vendingChip$es._(_root);
	@override String get alwaysOpen => 'Abierto día y noche';
	@override String get hoursUnknown => 'Horario desconocido';
	@override String get maybeClosed => 'Cerrado según el registro oficial de centros sanitarios (FINESS).';
	@override String maybeClosedSince({required Object date}) => 'Figura como cerrado en FINESS desde el ${date}: puede que haya cerrado definitivamente.';
	@override String get seasonal => 'De temporada: puede estar cerrado en invierno.';
	@override String get fee => 'De pago';
	@override String get free => 'Gratis';
	@override String get stillThereTitle => '¿Sigue ahí?';
	@override String get stillThereHint => '¿Lo has visto hace poco? Tu respuesta ayuda a los próximos viajeros. No se envía ninguna ubicación.';
	@override String get stillThere => 'Sigue ahí';
	@override String get gone => 'Ya no existe';
	@override String lastConfirmed({required Object when}) => 'Confirmado ${when}';
	@override String checkedOn({required Object date}) => 'Comprobado en el lugar el ${date}';
	@override String get thanksThere => 'Gracias, anotado: sigue ahí.';
	@override String get thanksGone => 'Gracias, anotado: ya no existe.';
	@override String get fuelPrices => 'Precios de los combustibles';
	@override String perLitre({required Object price}) => '${price}/l';
	@override String priceUpdated({required Object when}) => 'Precio actualizado ${when}';
	@override String feedRead({required Object when}) => 'Precios consultados ${when}';
	@override String get shortageTemporary => 'Agotado por ahora';
	@override String get shortageDefinitive => 'Ya no se vende';
	@override String get selfService24h => 'Pago con tarjeta 24 h';
	@override String get highway => 'En autopista';
	@override String get lpgYes => 'Vende GLP';
	@override late final _Translations$poi$fuel$es fuel = _Translations$poi$fuel$es._(_root);
	@override String get products => 'Vende';
	@override String get paymentTitle => 'Pago';
	@override late final _Translations$poi$product$es product = _Translations$poi$product$es._(_root);
	@override late final _Translations$poi$payment$es payment = _Translations$poi$payment$es._(_root);
	@override String get justNow => 'hace un momento';
	@override String minutesAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'hace ${n} minuto',
		other: 'hace ${n} minutos',
	);
	@override String hoursAgo({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'hace ${n} hora',
		other: 'hace ${n} horas',
	);
	@override String readOffline({required Object when}) => 'Consultado ${when}: sin conexión para actualizarlo';
	@override String readStale({required Object when}) => 'Consultado ${when}: no se ha podido actualizar en este momento.';
	@override String get goneTitle => 'Este punto ya no está en el mapa';
	@override String get goneHint => 'Algunos viajeros han indicado que ya no existe, o la última actualización lo ha retirado.';
	@override String get loadError => 'No se han podido cargar los detalles. Arriba tienes lo que sabe el mapa.';
	@override String get around => 'Alrededor de este lugar';
	@override String get aroundEmpty => 'No se conoce ningún comercio ni servicio por aquí.';
	@override String get aroundError => 'No se han podido cargar los comercios y servicios cercanos.';
	@override String get aroundOffline => 'Sin conexión: los comercios y servicios cercanos aparecerán cuando tengas conexión.';
	@override String get onSite => 'En el lugar';
	@override String backTo({required Object name}) => 'Volver a ${name}';
	@override String get backToPlace => 'Volver al lugar';
	@override String get linkError => 'No se ha podido abrir este comercio o servicio: no hay conexión o ya no está en el mapa.';
	@override String get searchSection => 'Comercios y servicios';
	@override String get searching => 'Buscando comercios y servicios';
	@override String get searchOffline => 'Los comercios y servicios se buscan en línea: ahora no hay conexión.';
	@override late final _Translations$poi$add$es add = _Translations$poi$add$es._(_root);
	@override late final _Translations$poi$cheapest$es cheapest = _Translations$poi$cheapest$es._(_root);
	@override late final _Translations$poi$trend$es trend = _Translations$poi$trend$es._(_root);
}

// Path: offlineMaps
class _Translations$offlineMaps$es extends Translations$offlineMaps$en {
	_Translations$offlineMaps$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Mapas sin conexión';
	@override String get intro => 'Antes de salir, guarda una región en el dispositivo: sus lugares para buscar y elegir, su mapa para ver las calles sin conexión.';
	@override String get webTitle => 'Los mapas sin conexión están en la aplicación';
	@override String get web => 'Las aplicaciones de Android e iOS guardan regiones para el viaje. En un navegador, el mapa necesita conexión.';
	@override String get desktopTitle => 'Los mapas sin conexión están en el móvil';
	@override String get desktop => 'Las aplicaciones de Android e iOS guardan regiones para el viaje. En un ordenador, el mapa necesita conexión.';
	@override String get unreadable => 'No se han podido cargar los mapas sin conexión de este dispositivo.';
	@override String get none => 'Todavía no hay ninguna región en este dispositivo.';
	@override String used({required Object size}) => 'Espacio usado: ${size}';
	@override String get downloads => 'Descargas';
	@override String get installed => 'En este dispositivo';
	@override String get suggested => 'Sugeridas';
	@override String get here => 'Donde estás';
	@override String favoritesHere({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} favorito en esta región',
		other: '${n} favoritos en esta región',
	);
	@override String get france => 'Francia';
	@override String get overseas => 'Francia de ultramar';
	@override String get countries => 'Países';
	@override String downloadNamed({required Object name, required Object size}) => 'Descargar ${name}, ${size}';
	@override String get pause => 'Pausar';
	@override String get resume => 'Reanudar';
	@override String get cancel => 'Detener y borrar la descarga';
	@override String get waiting => 'Esperando su turno';
	@override String progress({required Object done, required Object total}) => '${done} de ${total}';
	@override String paused({required Object done, required Object total}) => 'En pausa: ${done} de ${total}';
	@override String get verifying => 'Comprobando el archivo';
	@override String get failedNetwork => 'Interrumpida: sin conexión. Se reanudará donde se quedó en cuanto vuelva la conexión.';
	@override String get failedServer => 'El servidor ha enviado algo distinto del mapa. Vuelve a intentarlo más tarde.';
	@override String get failedCorrupt => 'El archivo ha llegado dañado y se ha borrado. Vuelve a intentarlo.';
	@override String get failedStorage => 'No queda espacio suficiente en el dispositivo. Libera espacio y vuelve a intentarlo.';
	@override String get keepOpen => 'Mantén la aplicación abierta durante la descarga: se interrumpe cuando la aplicación pasa a segundo plano y se reanuda cuando vuelves.';
	@override String dataOf({required Object date}) => 'datos del ${date}';
	@override String update({required Object size}) => 'Actualizar, ${size}';
	@override String deleteNamed({required Object name}) => 'Eliminar ${name}';
	@override String deleteTitle({required Object name}) => '¿Eliminar ${name} de este dispositivo?';
	@override String get deleteBody => 'Ya no se verá sin conexión. Puedes volver a descargarla.';
	@override String get listOffline => 'La lista de regiones necesita conexión.';
	@override String get listCopy => 'Lista guardada de la última conexión.';
	@override String get entryHint => 'Para viajar sin conexión';
	@override String entryCount({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Mapas: ${n} región, ${size}',
		other: 'Mapas: ${n} regiones, ${size}',
	);
	@override String noticePack({required Object name}) => 'Sin conexión: mapa descargado, ${name}';
	@override String get noticeOutside => 'Sin conexión: esta zona no está descargada';
	@override String get noticePlacesOnly => 'Sin conexión: lugares en el dispositivo, mapa de esta zona sin descargar';
	@override String get noticeNone => 'Sin conexión: descarga una región para la próxima vez';
	@override String get noticeOnline => 'Sin conexión: el mapa necesita conexión';
	@override String get placesTitle => 'Lugares';
	@override String get placesHint => 'Unos pocos megabytes por región: la lista, la búsqueda, las fichas y los filtros funcionan sin conexión.';
	@override String get mapsTitle => 'Mapas';
	@override String get mapsHint => 'Todas las calles, unos cientos de megabytes por región: el mapa se ve sin conexión.';
	@override String entryPlaces({required Object names}) => 'Lugares: ${names}';
	@override String entryPlacesCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Lugares: ${n} región',
		other: 'Lugares: ${n} regiones',
	);
}

// Path: regions
class _Translations$regions$es extends Translations$regions$en {
	_Translations$regions$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pickerTitle => '¿Qué lugares quieres guardar en este dispositivo?';
	@override String get pickerIntro => 'Cada región se descarga una vez y después se actualiza en pequeñas partes. Más adelante puedes añadir o quitar regiones en Mapas sin conexión.';
	@override String nearYou({required Object name}) => 'Cerca de ti: ${name}';
	@override String get findMine => 'Buscar mi región';
	@override String get locating => 'Buscando tu región';
	@override String get notCovered => 'Todavía no hay ninguna región de Lunaway a tu alrededor';
	@override String get wholeFrance => 'Toda Francia';
	@override String get showFrance => 'Mostrar las regiones de Francia';
	@override String get hideFrance => 'Ocultar las regiones de Francia';
	@override String packInfo({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${count} lugar, ${size}',
		other: '${count} lugares, ${size}',
	);
	@override String get noPack => 'Sin paquete: los lugares llegan con las actualizaciones, tamaño desconocido';
	@override String download({required Object size}) => 'Descargar, ${size}';
	@override String get unavailable => 'El servidor todavía no ofrece regiones: Lunaway guarda toda Francia.';
	@override String get listFailed => 'La lista de regiones necesita conexión.';
	@override String get choose => 'Elegir las regiones';
	@override String get noneKept => 'Ninguna región guardada: el mapa no tiene lugares sin conexión.';
	@override String get change => 'Añadir o quitar regiones';
	@override String removeNamed({required Object name}) => 'Quitar ${name}';
	@override String removed({required Object name}) => '${name}: lugares quitados de este dispositivo';
	@override String downloading({required Object done, required Object total}) => 'Descargando, ${done} de ${total}';
	@override String updating({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Actualizando, ${count} lugar',
		other: 'Actualizando, ${count} lugares',
	);
	@override String get waiting => 'esperando su descarga';
	@override String downloadingNamed({required Object name}) => 'Descargando los lugares: ${name}';
	@override String updated({required Object when}) => 'última actualización ${when}';
	@override String offerTitle({required Object name}) => '${name}: ¿guardar sus lugares sin conexión?';
	@override String get downloadThis => 'Descargar esta región';
	@override String notHere({required Object name}) => '${name} no está en este dispositivo';
	@override String get updatesOnMobile => 'Actualizar con datos móviles';
	@override String get updatesOnMobileHint => 'Si no, las regiones ya descargadas se actualizan por wifi. Una descarga nueva usa cualquier red.';
}

// Path: roadReport
class _Translations$roadReport$es extends Translations$roadReport$en {
	_Translations$roadReport$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get actionHint => 'Avisar de un problema en la carretera';
	@override String get title => '¿Qué ves en la carretera?';
	@override String get intro => 'Tu aviso alerta a los demás viajeros. Cuando dos cuentas de confianza avisan de lo mismo, las rutas lo evitan. No se admiten avisos de controles policiales.';
	@override late final _Translations$roadReport$kinds$es kinds = _Translations$roadReport$kinds$es._(_root);
	@override String height({required Object value}) => 'Altura indicada: ${value}';
	@override String get send => 'Avisar';
	@override String get sent => 'Gracias: los demás viajeros quedan avisados.';
	@override String get movingTitle => 'Estás conduciendo';
	@override String get movingBody => 'No avises de nada mientras conduces. Puede hacerlo un pasajero; si no, detente primero.';
	@override String get passenger => 'No estoy conduciendo';
	@override String get stillThere => 'Sigue ahí';
	@override String get over => 'Ya ha terminado';
	@override String get overSent => 'Gracias: anotado.';
	@override String get fromMap => 'Avisar de un problema aquí';
	@override String get notHereTitle => 'Aquí no se admiten avisos';
	@override String get lower => '10 cm más bajo';
	@override String get higher => '10 cm más alto';
	@override String passed({required Object what}) => 'Acabas de pasar: ${what}. ¿Sigue ahí?';
	@override String notHere({required Object countries}) => 'Lunaway acepta avisos donde una fuente oficial los contrasta: ${countries}.';
}

// Path: countries
class _Translations$countries$es extends Translations$countries$en {
	_Translations$countries$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get ad => 'Andorra';
	@override String get at => 'Austria';
	@override String get ax => 'Åland';
	@override String get be => 'Bélgica';
	@override String get ch => 'Suiza';
	@override String get cz => 'Chequia';
	@override String get de => 'Alemania';
	@override String get dk => 'Dinamarca';
	@override String get eh => 'Sáhara Occidental';
	@override String get es => 'España';
	@override String get fi => 'Finlandia';
	@override String get fr => 'Francia';
	@override String get gb => 'Reino Unido';
	@override String get gi => 'Gibraltar';
	@override String get gr => 'Grecia';
	@override String get hr => 'Croacia';
	@override String get ie => 'Irlanda';
	@override String get it => 'Italia';
	@override String get li => 'Liechtenstein';
	@override String get lu => 'Luxemburgo';
	@override String get ma => 'Marruecos';
	@override String get mc => 'Mónaco';
	@override String get nl => 'Países Bajos';
	@override String get no => 'Noruega';
	@override String get pl => 'Polonia';
	@override String get pt => 'Portugal';
	@override String get se => 'Suecia';
	@override String get si => 'Eslovenia';
	@override String get sj => 'Svalbard';
	@override String get sm => 'San Marino';
	@override String get va => 'Ciudad del Vaticano';
}

// Path: areas
class _Translations$areas$es extends Translations$areas$en {
	_Translations$areas$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get ara => 'Auvernia-Ródano-Alpes';
	@override String get bfc => 'Borgoña-Franco Condado';
	@override String get bre => 'Bretaña';
	@override String get cvl => 'Centro-Valle de Loira';
	@override String get cor => 'Córcega';
	@override String get ges => 'Gran Este';
	@override String get hdf => 'Alta Francia';
	@override String get idf => 'Isla de Francia';
	@override String get nor => 'Normandía';
	@override String get naq => 'Nueva Aquitania';
	@override String get occ => 'Occitania';
	@override String get pdl => 'País del Loira';
	@override String get pac => 'Provenza-Alpes-Costa Azul';
	@override String get gp => 'Guadalupe';
	@override String get mq => 'Martinica';
	@override String get gf => 'Guayana Francesa';
	@override String get re => 'Reunión';
	@override String get yt => 'Mayotte';
	@override String get franceRest => 'Francia, sin municipio';
}

// Path: search.addressKind
class _Translations$search$addressKind$es extends Translations$search$addressKind$en {
	_Translations$search$addressKind$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get houseNumber => 'Dirección';
	@override String get street => 'Calle';
	@override String get locality => 'Paraje';
	@override String get town => 'Municipio';
	@override String get postcode => 'Código postal';
	@override String get region => 'Región';
}

// Path: place.inclusions
class _Translations$place$inclusions$es extends Translations$place$inclusions$en {
	_Translations$place$inclusions$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get services => 'servicios';
	@override String get touristTax => 'tasa turística';
	@override String get electricity => 'electricidad';
}

// Path: place.reviewVehicle
class _Translations$place$reviewVehicle$es extends Translations$place$reviewVehicle$en {
	_Translations$place$reviewVehicle$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Furgoneta camper';
	@override String get motorhome => 'Autocaravana';
	@override String get caravan => 'Caravana';
	@override String get other => 'Otro vehículo';
}

// Path: sources.extcom
class _Translations$sources$extcom$es extends Translations$sources$extcom$en {
	_Translations$sources$extcom$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get label => 'Fuente comunitaria externa';
	@override String get short => 'Externa';
}

// Path: hours.codes
class _Translations$hours$codes$es extends Translations$hours$codes$en {
	_Translations$hours$codes$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get mo => 'lun.';
	@override String get tu => 'mar.';
	@override String get we => 'mié.';
	@override String get th => 'jue.';
	@override String get fr => 'vie.';
	@override String get sa => 'sáb.';
	@override String get su => 'dom.';
	@override String get ph => 'festivos';
	@override String get sh => 'vacaciones escolares';
	@override String get off => 'cerrado';
	@override String get closed => 'cerrado';
	@override String get sunrise => 'amanecer';
	@override String get sunset => 'puesta de sol';
}

// Path: hours.months
class _Translations$hours$months$es extends Translations$hours$months$en {
	_Translations$hours$months$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get jan => 'ene.';
	@override String get feb => 'feb.';
	@override String get mar => 'mar.';
	@override String get apr => 'abr.';
	@override String get may => 'may.';
	@override String get jun => 'jun.';
	@override String get jul => 'jul.';
	@override String get aug => 'ago.';
	@override String get sep => 'sept.';
	@override String get oct => 'oct.';
	@override String get nov => 'nov.';
	@override String get dec => 'dic.';
}

// Path: navigation.preview
class _Translations$navigation$preview$es extends Translations$navigation$preview$en {
	_Translations$navigation$preview$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String titleTo({required Object name}) => 'Hacia ${name}';
	@override String get titlePoint => 'Punto en el mapa';
	@override late final _Translations$navigation$preview$departure$es departure = _Translations$navigation$preview$departure$es._(_root);
	@override String get computing => 'Calculando una ruta para tu vehículo';
	@override String get start => '¡Vamos!';
	@override String get recommended => 'Recomendada';
	@override String alternative({required Object n}) => 'Alternativa ${n}';
	@override String get toll => 'Peaje';
	@override String get ferry => 'Ferri';
	@override String get motorway => 'Autopista';
	@override String get noWarnings => 'Esta ruta no tiene ninguna limitación cercana a las dimensiones de tu vehículo.';
	@override String warnings({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '1 limitación a tener en cuenta',
		other: '${n} limitaciones a tener en cuenta',
	);
	@override String get vehicle => 'Tu vehículo';
	@override String vehicleTowing({required Object vehicle}) => '${vehicle}, con remolque';
	@override String get editVehicle => 'Editar';
	@override String cruise({required Object speed}) => 'Tiempo calculado a ${speed} como máximo';
	@override String get avoid => 'Evitar';
	@override String get avoidTolls => 'Peajes';
	@override String get avoidMotorways => 'Autopistas';
	@override String get avoidFerries => 'Ferris';
	@override String get avoidUnpaved => 'Caminos sin asfaltar';
	@override String get roadbook => 'Hoja de ruta';
	@override String get roadbookShow => 'Ver las indicaciones';
	@override String get roadbookHide => 'Ocultar las indicaciones';
	@override String dataOf({required Object date}) => 'Datos viales del ${date}';
	@override String get attributionOsm => '© colaboradores de OpenStreetMap';
	@override String attributionIgn({required Object date}) => 'IGN, BD TOPO, edición del ${date}';
	@override String get disclaimer => 'Lunaway calcula la ruta con las dimensiones de tu vehículo y con datos abiertos (OpenStreetMap, IGN) que pueden estar incompletos o ser erróneos. Las señales y las normas de circulación siempre tienen prioridad. La responsabilidad de la conducción es solo tuya.';
	@override String get otherApps => 'Abrir en…';
	@override String get back => 'Volver';
	@override late final _Translations$navigation$preview$moved$es moved = _Translations$navigation$preview$moved$es._(_root);
}

// Path: navigation.stops
class _Translations$navigation$stops$es extends Translations$navigation$stops$en {
	_Translations$navigation$stops$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Paradas';
	@override String get add => 'Añadir como parada';
	@override String addCost({required Object minutes}) => 'Añadir como parada · +${minutes} min';
	@override String get addFree => 'Añadir como parada · sin desvío';
	@override String get quoting => 'Añadir como parada · calculando el desvío';
	@override String get noRoute => 'No hay ruta por este punto para tu vehículo.';
	@override String get full => 'Cinco paradas como máximo.';
	@override String get goDirectly => 'Ir directamente';
	@override String get openCard => 'Ver la ficha';
	@override String get point => 'Punto en el mapa';
	@override String get remove => 'Quitar la parada';
	@override String get reorder => 'Arrastra para cambiar el orden';
	@override String get added => 'Parada añadida';
	@override String get removed => 'Parada quitada';
	@override String get moved => 'Orden de las paradas cambiado';
	@override String get destinationChanged => 'Nuevo destino';
	@override String get failed => 'No se ha podido cambiar la ruta.';
	@override String get noQuote => 'No se ha podido calcular el desvío.';
	@override String get offline => 'Sin conexión para calcular el desvío.';
}

// Path: navigation.fuel
class _Translations$navigation$fuel$es extends Translations$navigation$fuel$en {
	_Translations$navigation$fuel$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String price({required Object price}) => '${price} €/l';
	@override String withDetour({required Object price}) => '${price} €/l, desvío incluido';
	@override String detour({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min';
	@override String get onRoute => 'en la ruta';
	@override String get open => 'Abierta';
	@override String get closed => 'Cerrada';
	@override String get unknownHours => 'Horario desconocido';
	@override String get add => 'Añadir';
	@override String get station => 'Gasolinera';
	@override String get empty => 'Ninguna gasolinera vende este combustible cerca de la ruta.';
	@override String get failed => 'No se han podido cargar las gasolineras.';
	@override String get estimated => 'Desvíos estimados según la distancia a la ruta.';
	@override String get attribution => 'Precios: Ministerio de Economía de Francia (data.economie.gouv.fr)';
	@override String minutesAgo({required Object n}) => 'hace ${n} min';
	@override String hoursAgo({required Object n}) => 'hace ${n} h';
	@override String daysAgo({required Object n}) => 'hace ${n} días';
}

// Path: navigation.onTheWay
class _Translations$navigation$onTheWay$es extends Translations$navigation$onTheWay$en {
	_Translations$navigation$onTheWay$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'En el camino';
	@override late final _Translations$navigation$onTheWay$categories$es categories = _Translations$navigation$onTheWay$categories$es._(_root);
	@override String fuelOfVehicle({required Object fuel}) => '${fuel}, según tu vehículo';
	@override String get otherFuel => 'Otro combustible';
	@override String get keepFuel => 'Guardar como mi combustible';
	@override String fuelKept({required Object fuel}) => '${fuel} guardado para tu vehículo.';
	@override String get keepFuelFailed => 'No se ha podido guardar el combustible.';
	@override String get loading => 'Buscando a lo largo de la ruta';
	@override String get empty => 'Sin resultados en esta ruta';
	@override String get emptyHint => 'Prueba otra categoría, o vuelve a abrir la lista más adelante en la ruta.';
	@override String get failed => 'No se ha podido cargar la lista.';
	@override String get offline => 'Sin conexión: la lista volverá con la conexión.';
	@override String get rateLimited => 'Muchas búsquedas seguidas: vuelve a intentarlo en unos minutos.';
	@override String nearNone({required Object distance}) => 'Nada en los próximos ${distance}.';
	@override String further({required Object n}) => 'Más adelante (${n})';
	@override String get more => 'Ver más';
	@override String get moreFailed => 'No se ha podido cargar el resto.';
	@override String ahead({required Object distance}) => 'a ${distance}';
	@override String offRoute({required Object distance}) => 'a ${distance} de la ruta';
	@override String get byTheRoad => 'junto a la carretera';
	@override String addCost({required Object minutes}) => 'Añadir · +${minutes} min';
	@override String get addFree => 'Añadir · sin desvío';
	@override String openAt({required Object time}) => 'Abierto cuando pases, hacia las ${time}';
	@override String closedAt({required Object time}) => 'Cerrado cuando pases, hacia las ${time}';
	@override String closedOpensAt({required Object time, required Object opens}) => 'Cerrado cuando pases hacia las ${time}, abre a las ${opens}';
	@override String perNight({required Object price}) => '${price} la noche';
	@override String photoFrom({required Object source}) => 'Foto: ${source}';
	@override String servicesList({required Object list}) => 'Servicios: ${list}';
	@override String get movingBody => 'No busques nada mientras conduces. Puede hacerlo un pasajero; si no, detente primero.';
	@override String get placesCredit => 'Lugares: Lunaway y las fuentes indicadas en cada ficha';
}

// Path: navigation.states
class _Translations$navigation$states$es extends Translations$navigation$states$en {
	_Translations$navigation$states$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get vehicleTitle => '¿Cuál es tu vehículo?';
	@override String get vehicleHint => 'La ruta evita los puentes demasiado bajos, las calles demasiado estrechas y las carreteras prohibidas para las dimensiones de tu vehículo. Indica su altura, anchura, longitud y peso.';
	@override String vehicleMissing({required Object list}) => 'Faltan datos: ${list}';
	@override String vehicleOutOfBounds({required Object list}) => 'Fuera de los valores aceptados: ${list}';
	@override late final _Translations$navigation$states$dimension$es dimension = _Translations$navigation$states$dimension$es._(_root);
	@override String get describeVehicle => 'Describir mi vehículo';
	@override String get originTitle => '¿Dónde estás?';
	@override String get originHint => 'Lunaway necesita tu ubicación para calcular la ruta.';
	@override String get locate => 'Localizarme';
	@override String get offlineTitle => 'Sin conexión';
	@override String get offlineHint => 'Las rutas se calculan en el servidor de Lunaway. Sin conexión, «Abrir en…» pasa el viaje a una aplicación de navegación que guarda sus mapas.';
	@override String get rateLimitedTitle => 'Demasiadas rutas solicitadas';
	@override String rateLimitedHint({required Object seconds}) => 'Vuelve a intentarlo dentro de ${seconds} s.';
	@override String get unavailableTitle => 'Cálculo de rutas no disponible';
	@override String get unavailableHint => 'El servicio no está disponible en este momento. Vuelve a intentarlo más tarde.';
	@override String get refusedTitle => 'No hay ruta aquí';
	@override String get refusedHint => 'Lunaway no ha podido calcular una ruta para esta solicitud: comprueba el destino, la longitud del trayecto y los datos del vehículo.';
	@override String get noSafeTitle => 'No hay ninguna ruta segura para tu vehículo';
	@override String get noSafeHint => 'Todas las carreteras posibles pasan por una limitación que tu vehículo supera:';
	@override String get whatToDo => 'Qué puedes hacer';
	@override String checkVehicle({required Object height, required Object weight}) => 'Comprueba los datos introducidos: ${height} de alto, ${weight}.';
	@override String get pickOtherPoint => 'Elige un destino antes del obstáculo: mantén pulsado el mapa.';
	@override String get noRouteTitle => 'Ninguna carretera lleva a este punto';
	@override String get noRouteHint => 'Puede que el punto esté en una vía privada o en una isla sin ferri.';
	@override String get allowUnpaved => 'Se evitan los caminos sin asfaltar: permítelos si el destino está en una pista.';
	@override String get offNetworkTitle => 'Demasiado lejos de una carretera';
	@override String get offNetworkHint => 'Elige un destino en una carretera.';
}

// Path: navigation.noRoute
class _Translations$navigation$noRoute$es extends Translations$navigation$noRoute$en {
	_Translations$navigation$noRoute$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get originUnreachable => 'Tu vehículo no puede salir de aquí';
	@override String originUnreachableBy({required Object limit}) => 'Tu vehículo no puede salir de aquí: ${limit}';
	@override String get destinationUnreachable => 'Destino inaccesible para tu vehículo';
	@override String destinationUnreachableBy({required Object limit}) => 'Destino inaccesible para tu vehículo: ${limit}';
	@override String waypointUnreachable({required Object n}) => 'Parada ${n} inaccesible para tu vehículo';
	@override String waypointUnreachableBy({required Object n, required Object limit}) => 'Parada ${n} inaccesible para tu vehículo: ${limit}';
	@override String get blockedOnTheWay => 'Tu vehículo no tiene paso entre las paradas';
	@override String blockedOnTheWayBy({required Object limit}) => 'Tu vehículo no tiene paso entre las paradas: ${limit}';
	@override String get blockedHint => 'Se puede llegar a cada parada, pero todas las carreteras que las unen pasan por una limitación que tu vehículo supera.';
	@override String get notConnectedOrigin => 'Ninguna carretera sale de tu ubicación';
	@override String get notConnectedDestination => 'Ninguna carretera lleva al destino';
	@override String notConnectedWaypoint({required Object n}) => 'Ninguna carretera lleva a la parada ${n}';
	@override String get notConnectedTrip => 'Ninguna carretera une tus paradas';
	@override String get notConnectedHint => 'Sea cual sea el vehículo: una isla sin ferri para vehículos o una vía cerrada al tráfico.';
	@override String get outsideOrigin => 'Tu ubicación está fuera de la zona donde Lunaway calcula rutas';
	@override String get outsideDestination => 'Destino fuera de la zona donde Lunaway calcula rutas';
	@override String outsideWaypoint({required Object n}) => 'Parada ${n} fuera de la zona donde Lunaway calcula rutas';
	@override String outsideHint({required Object countries}) => 'Lunaway calcula rutas en estos países: ${countries}.';
	@override String get outsideHintUnknown => 'Lunaway todavía no calcula rutas en este país.';
	@override String get noRoadOrigin => 'Tu ubicación está demasiado lejos de una carretera';
	@override String get noRoadDestination => 'Destino demasiado lejos de una carretera';
	@override String noRoadWaypoint({required Object n}) => 'Parada ${n} demasiado lejos de una carretera';
	@override String get noRoadHint => 'No hay ninguna carretera que tu vehículo pueda tomar a menos de 5 km de este punto.';
	@override String get tooLong => 'Trayecto demasiado largo';
	@override String tooLongHint({required Object trip, required Object max}) => '${trip} en línea recta de parada en parada: Lunaway calcula trayectos de ${max} como máximo.';
	@override String vehicleValue({required Object value}) => 'Tu vehículo: ${value}';
	@override late final _Translations$navigation$noRoute$limit$es limit = _Translations$navigation$noRoute$limit$es._(_root);
	@override String get editVehicle => 'Modificar el vehículo';
	@override String get allowUnpaved => 'Permitir caminos sin asfaltar';
	@override String removeStop({required Object n}) => 'Quitar la parada ${n}';
	@override String removeStopNamed({required Object name}) => 'Quitar la parada «${name}»';
	@override String get placesAround => 'Ver los lugares alrededor del destino';
	@override String get moveDestination => 'O elige otro destino: mantén pulsado el mapa y luego «Ir directamente».';
	@override String get moveStop => 'Para otra parada: amplía bien el mapa y tócalo, o mantenlo pulsado, y luego «Añadir como parada».';
	@override String get moveOrigin => 'La salida es tu ubicación: llega a una carretera que tu vehículo pueda tomar y vuelve a intentarlo.';
	@override String get pickInside => 'Elige un destino en uno de estos países.';
	@override String get shorter => 'Elige un destino más cercano o haz el trayecto en varios tramos.';
}

// Path: navigation.ferry
class _Translations$navigation$ferry$es extends Translations$navigation$ferry$en {
	_Translations$navigation$ferry$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String title({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Travesía en ferri',
		other: '${n} travesías en ferri',
	);
	@override String get unnamed => 'Ferri';
	@override String named({required Object name}) => 'Ferri ${name}';
	@override String ports({required Object ports}) => 'Puertos: ${ports}';
	@override String countries({required Object from, required Object to}) => 'Embarque: ${from} · Desembarque: ${to}';
	@override String country({required Object country}) => 'País: ${country}';
	@override String where({required Object distance, required Object sea, required Object duration}) => 'A ${distance} de la salida · ${sea} por mar, aproximadamente ${duration}';
	@override String get needed => 'No se puede llegar al destino sin ferri: la ruta toma uno, aunque evites los ferris.';
}

// Path: navigation.warning
class _Translations$navigation$warning$es extends Translations$navigation$warning$en {
	_Translations$navigation$warning$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override late final _Translations$navigation$warning$lowClearance$es lowClearance = _Translations$navigation$warning$lowClearance$es._(_root);
	@override String get unknownClearance => 'Paso de altura limitada, altura desconocida';
	@override String narrow({required Object limit}) => 'Paso estrecho ${limit}';
	@override String tooLong({required Object limit}) => 'Longitud máxima ${limit}';
	@override String tooHeavy({required Object limit}) => 'Peso máximo ${limit}';
	@override String axleLoad({required Object limit}) => 'Carga máxima por eje ${limit}';
	@override String get motorhomeBan => 'Prohibido para autocaravanas';
	@override String get trailerBan => 'Prohibido para remolques';
	@override String goodsVehicleWeight({required Object limit}) => 'Peso máximo para camiones ${limit}';
	@override String yours({required Object value}) => 'tu vehículo: ${value}';
	@override String fromStart({required Object distance}) => 'a ${distance} de la salida';
	@override String ahead({required Object distance}) => 'a ${distance}';
	@override String get disputed => 'las fuentes no coinciden, se aplica el valor más bajo';
	@override String get goodsOnly => 'afecta a los camiones, consulta las señales';
	@override String get osm => 'OpenStreetMap';
	@override String get ign => 'IGN BD TOPO';
	@override String get community => 'Aviso de viajeros de Lunaway';
	@override String get dialog => 'Resolución de tráfico (DiaLog)';
	@override late final _Translations$navigation$warning$localAccess$es localAccess = _Translations$navigation$warning$localAccess$es._(_root);
}

// Path: navigation.roadEvents
class _Translations$navigation$roadEvents$es extends Translations$navigation$roadEvents$en {
	_Translations$navigation$roadEvents$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Obras y cortes';
	@override String get none => 'No hay obras ni cortes conocidos en esta ruta.';
	@override String get stale => 'Obras y cortes: las fuentes no se han consultado recientemente.';
	@override String avoided({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Ruta calculada evitando un corte: ${names}',
		other: 'Ruta calculada evitando ${n} cortes: ${names}',
	);
	@override String atDistance({required Object distance}) => 'a ${distance} de la salida';
	@override String more({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Y ${n} más en la ruta',
		other: 'Y ${n} más en la ruta',
	);
	@override String get classClosure => 'Carretera cortada';
	@override String get classWorks => 'Obras';
	@override String get classLaneRestriction => 'Carriles cortados';
	@override String get classVehicleLimit => 'Límite de dimensiones';
	@override String get classDetour => 'Desvío señalizado';
	@override String get reasonUnmatched => 'ubicación incierta, quizá en la ruta';
	@override String get reasonStale => 'fuente no consultada recientemente';
	@override String get reasonOutsideHours => 'fuera de su horario previsto';
	@override String get reasonGoodsVehicles => 'para camiones';
	@override String get reasonUnconfirmed => 'avisado por un solo viajero';
	@override String get reasonAged => 'aviso antiguo';
	@override String get reasonInside => 'la ruta empieza o termina dentro';
	@override String get reasonNearLimit => 'con poco margen';
	@override String get reasonOverLimit => 'por encima del límite de tu vehículo';
}

// Path: navigation.marks
class _Translations$navigation$marks$es extends Translations$navigation$marks$en {
	_Translations$navigation$marks$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get legend => 'Leyenda';
	@override String get legendHide => 'Ocultar la leyenda';
	@override String get kindOrigin => 'Salida';
	@override String get kindDestination => 'Destino';
	@override String get kindStop => 'Parada';
	@override String get kindClosure => 'Carretera cortada';
	@override String get kindWorks => 'Obras';
	@override String get kindLanes => 'Carriles cortados';
	@override String get kindClearance => 'Altura limitada';
	@override String get kindWeight => 'Peso limitado';
	@override String get kindLimit => 'Otro límite (anchura, longitud, prohibición)';
	@override String get kindFuel => 'Gasolinera';
	@override String get kindPlace => 'Lugar cerca de la ruta';
	@override String get groupLegend => 'Marcadores cercanos agrupados';
	@override String get zoneLegend => 'Zona de peligro';
	@override String zonesFrom({required Object source, required Object date}) => 'Zonas de peligro: ${source}, lista del ${date}';
	@override String group({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} marcador',
		other: '${n} marcadores',
	);
	@override String get groupHint => 'Acerca el mapa para verlos uno a uno';
	@override String count({required Object kind, required Object n}) => '${kind}: ${n}';
	@override String stop({required Object n}) => 'Parada ${n}';
	@override String get origin => 'Punto de salida';
	@override String get nearRoute => 'Cerca de la ruta';
	@override String get avoided => 'La ruta lo evita';
	@override String get blocking => 'Bloquea todas las rutas';
	@override String get showInList => 'Ver en la lista';
	@override String get showAll => 'Mostrar todo';
	@override String get onMap => 'mostrar en el mapa';
	@override String price({required Object price}) => '${price} €';
}

// Path: navigation.guidance
class _Translations$navigation$guidance$es extends Translations$navigation$guidance$en {
	_Translations$navigation$guidance$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get then => 'Luego';
	@override String arrival({required Object time}) => 'Llegada ${time}';
	@override String get offRoute => 'Fuera de la ruta';
	@override String get rerouting => 'Buscando una ruta nueva';
	@override String get rerouted => 'Nueva ruta';
	@override String reroutedLonger({required Object minutes}) => 'Nueva ruta, ${minutes} min más';
	@override String get rerouteOffline => 'Sin conexión para calcular otra ruta: vuelve a la ruta';
	@override String get rerouteFailed => 'No se ha encontrado otra ruta: vuelve a la ruta';
	@override String closureAhead({required Object distance}) => 'Carretera cortada a ${distance}: buscando otro camino';
	@override String noDetour({required Object distance}) => 'Carretera cortada a ${distance}: no hay otro camino';
	@override String eventAhead({required Object distance}) => 'Obras a ${distance}';
	@override String eventClosure({required Object distance}) => 'Carretera cortada a ${distance}';
	@override String eventLimit({required Object distance}) => 'Paso limitado por obras a ${distance}';
	@override String eventSource({required Object source, required Object time}) => '${source}, datos de las ${time}';
	@override String eventSourceOn({required Object source, required Object day, required Object time}) => '${source}, datos del ${day} a las ${time}';
	@override String avoidedClosures({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: 'Ruta calculada evitando un corte',
		other: 'Ruta calculada evitando ${n} cortes',
	);
	@override String roadEventAhead({required Object what, required Object distance}) => '${what} a ${distance}';
	@override String closureOffline({required Object distance}) => 'Carretera cortada a ${distance}: sin conexión para buscar otro camino';
	@override String closureFailed({required Object distance}) => 'Carretera cortada a ${distance}: todavía no hay otro camino';
	@override String get voiceOn => 'Activar la voz';
	@override String get voiceOff => 'Silenciar la voz';
	@override String get overview => 'Toda la ruta';
	@override String get recenter => 'Recentrar';
	@override String get end => 'Terminar';
	@override String get endTitle => '¿Terminar la navegación?';
	@override String get endConfirm => 'Terminar';
	@override String get endKeep => 'Continuar';
	@override String get stopTitle => '¿Detener la navegación?';
	@override String get stopConfirm => 'Detener';
	@override String get arrivedTitle => 'Has llegado a tu destino';
	@override String get done => 'Terminar';
	@override String get speed => 'Velocidad';
	@override String get limit => 'Límite';
	@override String noVoice({required Object language}) => 'No hay ninguna voz en ${language} en este dispositivo: instrucciones solo en pantalla.';
	@override String missingVoice({required Object language}) => 'La voz en ${language} todavía no está descargada.';
	@override String get installVoice => 'Instalar';
	@override String get voiceSettingsIos => 'Ajustes, Accesibilidad, Contenido leído, Voces';
	@override String get notificationTitle => 'Lunaway te está guiando';
	@override String get notificationText => 'La navegación continúa con la pantalla apagada.';
	@override String get notificationChannel => 'Navegación';
	@override String get unavailable => 'No se ha podido iniciar la navegación en este dispositivo.';
	@override late final _Translations$navigation$guidance$notificationWhy$es notificationWhy = _Translations$navigation$guidance$notificationWhy$es._(_root);
	@override String get positionLost => 'Ubicación no disponible: comprueba que la ubicación del dispositivo está activada para Lunaway.';
	@override String positionStale({required Object minutes}) => 'Última ubicación recibida hace ${minutes} min: la hora de llegada se basa en ella.';
	@override String get firstTitle => 'Antes de salir';
	@override String get firstAccept => 'Entendido';
	@override String dangerZone({required Object distance}) => 'Zona de peligro a ${distance}';
	@override String inDangerZone({required Object distance}) => 'Zona de peligro, quedan ${distance}';
	@override String cameraAhead({required Object distance}) => 'Radar a ${distance}';
	@override String cameraLimit({required Object distance, required Object limit}) => 'Radar a ${distance}, ${limit}';
	@override String get limitEstimated => 'Límite estimado';
	@override String get overLimit => 'por encima del límite';
	@override String enforcementSource({required Object source, required Object date}) => '${source}, lista del ${date}';
	@override String get demoDrive => 'Trayecto simulado: demostración sin GPS';
	@override late final _Translations$navigation$guidance$places$es places = _Translations$navigation$guidance$places$es._(_root);
}

// Path: navigation.voice
class _Translations$navigation$voice$es extends Translations$navigation$voice$en {
	_Translations$navigation$voice$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get rerouting => 'Recalculando la ruta.';
	@override String get rerouted => 'Nueva ruta.';
	@override String reroutedLonger({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(minutes,
		one: 'Nueva ruta, un minuto más larga.',
		other: 'Nueva ruta, ${minutes} minutos más larga.',
	);
	@override late final _Translations$navigation$voice$moved$es moved = _Translations$navigation$voice$moved$es._(_root);
	@override String closureAhead({required Object distance}) => 'En ${distance}, carretera cortada. Buscando otro camino.';
	@override String noDetour({required Object distance}) => 'En ${distance}, carretera cortada. No hay otro camino.';
	@override String clearance({required Object distance, required Object height}) => 'Atención, en ${distance}, altura máxima ${height}.';
	@override String unknownClearance({required Object distance}) => 'Atención, en ${distance}, paso bajo de altura desconocida.';
	@override String narrow({required Object distance, required Object width}) => 'Atención, en ${distance}, paso estrecho de ${width}.';
	@override String limit({required Object distance, required Object what}) => 'Atención, en ${distance}, ${what}.';
	@override String get arrived => 'Ha llegado a su destino.';
	@override String metres({required Object n}) => '${n} metros';
	@override String kilometres({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count,
		one: 'un kilómetro',
		other: '${n} kilómetros',
	);
	@override String feet({required Object n}) => '${n} pies';
	@override String miles({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count,
		one: 'una milla',
		other: '${n} millas',
	);
	@override String size({required num count, required Object cm, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count,
		one: 'un metro ${cm}',
		other: '${metres} metros ${cm}',
	);
	@override String sizeWhole({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count,
		one: 'un metro',
		other: '${metres} metros',
	);
	@override String overSpeed({required Object limit}) => 'Velocidad máxima ${limit}.';
	@override String dangerZone({required Object distance}) => 'En ${distance}, zona de peligro.';
	@override String get inDangerZone => 'Zona de peligro.';
	@override String camera({required Object distance}) => 'En ${distance}, radar.';
	@override late final _Translations$navigation$voice$localAccess$es localAccess = _Translations$navigation$voice$localAccess$es._(_root);
	@override String tonnes({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count,
		one: 'una tonelada',
		other: '${n} toneladas',
	);
}

// Path: navigation.units
class _Translations$navigation$units$es extends Translations$navigation$units$en {
	_Translations$navigation$units$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String ft({required Object n}) => '${n} ft';
	@override String mi({required Object n}) => '${n} mi';
	@override String get kmh => 'km/h';
	@override String get mph => 'mph';
	@override String hoursMinutes({required Object h, required Object m}) => '${h} h ${m} min';
	@override String minutes({required Object m}) => '${m} min';
}

// Path: navigation.settings
class _Translations$navigation$settings$es extends Translations$navigation$settings$en {
	_Translations$navigation$settings$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Navegación';
	@override String get avoidTitle => 'Evitar por defecto';
	@override String get voice => 'Instrucciones de voz';
	@override String get voiceHint => 'Con la voz del dispositivo';
	@override String get units => 'Distancias';
	@override String get metric => 'Kilómetros';
	@override String get imperial => 'Millas';
	@override String get speedLimit => 'Límite de velocidad';
	@override String get speedLimitHint => 'El límite para tu vehículo junto a la velocidad durante la navegación; si es una estimación, aparece en gris.';
	@override String get speedSound => 'Avisos de velocidad por voz';
	@override String get speedSoundHint => 'Un aviso cuando superas el límite, y antes de una zona de peligro donde el país lo permite. Desactivado: solo la señal y los avisos en pantalla.';
}

// Path: vehicle.types
class _Translations$vehicle$types$es extends Translations$vehicle$types$en {
	_Translations$vehicle$types$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get van => 'Van';
	@override String get campervan => 'Furgoneta camper';
	@override String get lowProfile => 'Perfilada';
	@override String get overcab => 'Capuchina';
	@override String get integrated => 'Integral';
}

// Path: vehicle.towing
class _Translations$vehicle$towing$es extends Translations$vehicle$towing$en {
	_Translations$vehicle$towing$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get none => 'Sin remolque';
	@override String get car => 'Un coche';
	@override String get trailer => 'Un remolque';
}

// Path: translation.from
class _Translations$translation$from$es extends Translations$translation$from$en {
	_Translations$translation$from$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get fr => 'Traducido automáticamente del francés';
	@override String get en => 'Traducido automáticamente del inglés';
	@override String get de => 'Traducido automáticamente del alemán';
	@override String get es => 'Traducido automáticamente del español';
	@override String get it => 'Traducido automáticamente del italiano';
	@override String get nl => 'Traducido automáticamente del neerlandés';
	@override String unknown({required Object language}) => 'Traducido automáticamente (idioma original: ${language})';
}

// Path: account.levelOpens
class _Translations$account$levelOpens$es extends Translations$account$levelOpens$en {
	_Translations$account$levelOpens$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get l0 => 'Puedes valorar lugares, confirmar que siguen ahí, avisar de un problema y sincronizar tus favoritos.';
	@override String get l1 => 'También puedes escribir reseñas, añadir fotos y proponer cambios en los lugares.';
	@override String get l2 => 'También puedes añadir lugares.';
	@override String get l3 => 'Tus cambios en los lugares se aplican sin revisión.';
	@override String get l4 => 'Participas en la moderación.';
}

// Path: account.requirement
class _Translations$account$requirement$es extends Translations$account$requirement$en {
	_Translations$account$requirement$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String age({required Object needed, required Object current}) => 'Una cuenta con al menos ${needed} días (${current} por ahora)';
	@override String confirmations({required Object needed, required Object current}) => '${needed} confirmaciones de lugares distintos (${current} por ahora)';
	@override String contributions({required Object needed, required Object current}) => '${needed} contribuciones publicadas (${current} por ahora)';
	@override String activeDays({required Object needed, required Object current}) => '${needed} días de actividad (${current} por ahora)';
	@override String get noRemoval => 'Ninguna contribución retirada por la moderación';
	@override String get sponsor => 'El apadrinamiento de un miembro de nivel 2';
	@override String get nomination => 'Un nombramiento por parte de la moderación';
	@override String get administration => 'Una designación por parte del equipo de Lunaway';
}

// Path: deletion.gone
class _Translations$deletion$gone$es extends Translations$deletion$gone$en {
	_Translations$deletion$gone$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get identity => 'Tu seudónimo y las claves de tus dispositivos';
	@override String get sessions => 'Tus sesiones y tu código de recuperación';
	@override String get lists => 'Tus listas de favoritos sincronizadas y tus autores ocultos';
	@override String get photos => 'Tus fotos, tus valoraciones sin texto y tus avisos';
	@override String get pending => 'Tus propuestas pendientes de revisión';
}

// Path: mine.status
class _Translations$mine$status$es extends Translations$mine$status$en {
	_Translations$mine$status$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get published => 'Publicada';
	@override String get pending => 'En revisión';
	@override String get hidden => 'Oculta tras varias denuncias';
	@override String get removed => 'Retirada por la moderación';
}

// Path: mine.submission
class _Translations$mine$submission$es extends Translations$mine$submission$en {
	_Translations$mine$submission$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get proposed => 'Pendiente de revisión';
	@override String get accepted => 'Aceptado';
	@override String get applied => 'En el mapa';
	@override String get rejected => 'Rechazado';
	@override String get withdrawn => 'Retirado';
}

// Path: outbox.kind
class _Translations$outbox$kind$es extends Translations$outbox$kind$en {
	_Translations$outbox$kind$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String rate({required Object stars}) => 'Valoración de ${stars} sobre 5';
	@override String get review => 'Reseña';
	@override String get deleteReview => 'Eliminación de una reseña';
	@override String confirm({required Object status}) => 'Confirmación: ${status}';
	@override String get deleteConfirmation => 'Eliminación de una confirmación';
	@override String reportIssue({required Object kind}) => 'Aviso de problema: ${kind}';
	@override String get deleteIssueReport => 'Eliminación de un aviso';
	@override String get reportContent => 'Denuncia a la moderación';
	@override String addPlace({required Object name}) => 'Nuevo lugar: ${name}';
	@override String get editPlace => 'Cambio en un lugar';
	@override String get deletePlaceSubmission => 'Retirada de un lugar propuesto';
	@override String get photo => 'Foto';
	@override String get deletePhoto => 'Eliminación de una foto';
	@override String get mute => 'Ocultar a un autor';
	@override String get unmute => 'Volver a mostrar a un autor';
	@override String get poiThere => 'Sigue ahí: un comercio o servicio';
	@override String get poiGone => 'Ya no está: un comercio o servicio';
	@override String get addVendingMachine => 'Nueva máquina expendedora';
	@override String get deletePoiConfirmation => 'Eliminación de una respuesta sobre un comercio o servicio';
	@override String reportRoadEvent({required Object kind}) => 'Aviso en carretera: ${kind}';
	@override String get clearRoadEvent => 'Fin de un aviso en carretera';
}

// Path: outbox.error
class _Translations$outbox$error$es extends Translations$outbox$error$en {
	_Translations$outbox$error$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get forbidden => 'Rechazado: tu nivel todavía no lo permite.';
	@override String get notFound => 'Rechazado: el lugar o el contenido ya no existe.';
	@override String get invalid => 'Rechazado: revisa el texto (longitud, enlaces, datos de contacto).';
	@override String get unreadablePhoto => 'Foto rechazada: ilegible o ya enviada.';
	@override String get photoTooLarge => 'Foto rechazada: demasiado pesada.';
	@override String get placeRefused => 'Se ha rechazado el nuevo lugar de esta foto.';
	@override String get fileLost => 'La foto ya no está en el dispositivo.';
	@override String get otherAccount => 'Preparada para otra cuenta: no se enviará.';
	@override String get other => 'Rechazado por el servidor.';
	@override String get duplicate => 'Rechazado: la misma máquina ya figura a menos de 25 m.';
}

// Path: confirmSheet.status
class _Translations$confirmSheet$status$es extends Translations$confirmSheet$status$en {
	_Translations$confirmSheet$status$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get stillOk => 'sigue ahí';
	@override String get closed => 'cerrado';
	@override String get changed => 'ha cambiado';
}

// Path: issueSheet.kind
class _Translations$issueSheet$kind$es extends Translations$issueSheet$kind$en {
	_Translations$issueSheet$kind$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Pernocta prohibida ahora';
	@override String get serviceBroken => 'Servicio averiado';
	@override String get noAccess => 'Sin acceso';
	@override String get danger => 'Peligro';
}

// Path: issueSheet.hint
class _Translations$issueSheet$hint$es extends Translations$issueSheet$hint$en {
	_Translations$issueSheet$hint$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get nightBan => 'Una señal, un bando municipal, la visita de la policía';
	@override String get serviceBroken => 'Punto de servicio, agua, vaciado o electricidad fuera de servicio';
	@override String get noAccess => 'Una barrera, obras, una carretera cortada';
	@override String get danger => 'Robo, agresión, terreno inestable';
}

// Path: reportSheet.reason
class _Translations$reportSheet$reason$es extends Translations$reportSheet$reason$en {
	_Translations$reportSheet$reason$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get spam => 'Publicidad o repetición';
	@override String get offensive => 'Insultos, odio o contenido impactante';
	@override String get wrong => 'Falso o engañoso';
	@override String get privacy => 'Muestra o nombra a una persona, una matrícula o una dirección privada';
	@override String get other => 'Otro motivo';
}

// Path: poi.category
class _Translations$poi$category$es extends Translations$poi$category$en {
	_Translations$poi$category$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get groceries => 'Compras';
	@override String get vending => 'Expendedoras de comida';
	@override String get water => 'Agua y vaciado';
	@override String get fuel => 'Combustible y energía';
	@override String get health => 'Salud';
	@override String get services => 'Servicios';
}

// Path: poi.kind
class _Translations$poi$kind$es extends Translations$poi$kind$en {
	_Translations$poi$kind$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get supermarket => 'Supermercado';
	@override String get convenience => 'Tienda de alimentación';
	@override String get bakery => 'Panadería';
	@override String get butcher => 'Carnicería';
	@override String get greengrocer => 'Frutería';
	@override String get farmShop => 'Venta directa en granja';
	@override String get marketplace => 'Mercado';
	@override String get vendingPizza => 'Expendedora de pizzas';
	@override String get vendingBread => 'Expendedora de pan';
	@override String get vendingFarmProducts => 'Expendedora de productos de granja';
	@override String get vendingEggsMilk => 'Expendedora de huevos o leche';
	@override String get vendingIce => 'Expendedora de hielo';
	@override String get vendingOther => 'Expendedora de comida';
	@override String get drinkingWater => 'Agua potable';
	@override String get waterPoint => 'Punto de agua';
	@override String get dumpStation => 'Punto de vaciado';
	@override String get toilets => 'Aseos';
	@override String get shower => 'Duchas';
	@override String get fuelStation => 'Gasolinera';
	@override String get evCharging => 'Punto de recarga';
	@override String get gasBottles => 'Bombonas de gas';
	@override String get pharmacy => 'Farmacia';
	@override String get doctor => 'Médico';
	@override String get hospital => 'Hospital';
	@override String get veterinary => 'Veterinario';
	@override String get laundry => 'Lavandería';
	@override String get atm => 'Cajero automático';
	@override String get postOffice => 'Oficina de correos';
	@override String get touristOffice => 'Oficina de turismo';
	@override String get recyclingCentre => 'Punto limpio';
	@override String get carRepair => 'Taller';
	@override String get carWash => 'Lavado de vehículos';
	@override String get motorhomeShop => 'Concesionario y taller de autocaravanas';
}

// Path: poi.vendingSells
class _Translations$poi$vendingSells$es extends Translations$poi$vendingSells$en {
	_Translations$poi$vendingSells$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizza';
	@override String get bread => 'Pan';
	@override String get farmProducts => 'Productos de granja';
	@override String get eggsMilk => 'Huevos y leche';
	@override String get ice => 'Hielo';
}

// Path: poi.vendingChip
class _Translations$poi$vendingChip$es extends Translations$poi$vendingChip$en {
	_Translations$poi$vendingChip$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Expendedoras de pizzas';
	@override String get bread => 'Expendedoras de pan';
	@override String get farmProducts => 'Expendedoras de productos de granja';
	@override String get eggsMilk => 'Expendedoras de huevos y leche';
	@override String get ice => 'Expendedoras de hielo';
}

// Path: poi.fuel
class _Translations$poi$fuel$es extends Translations$poi$fuel$en {
	_Translations$poi$fuel$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get diesel => 'Gasóleo';
	@override String get sp95 => 'Gasolina 95';
	@override String get e10 => 'Gasolina 95 E10';
	@override String get sp98 => 'Gasolina 98';
	@override String get e85 => 'E85';
	@override String get lpg => 'GLP';
}

// Path: poi.product
class _Translations$poi$product$es extends Translations$poi$product$en {
	_Translations$poi$product$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get pizza => 'Pizzas';
	@override String get bread => 'Pan';
	@override String get eggs => 'Huevos';
	@override String get milk => 'Leche';
	@override String get cheese => 'Queso';
	@override String get meat => 'Carne';
	@override String get vegetables => 'Verduras';
	@override String get fruit => 'Fruta';
	@override String get honey => 'Miel';
	@override String get ice => 'Hielo';
	@override String get potatoes => 'Patatas';
	@override String get food => 'Alimentación';
}

// Path: poi.payment
class _Translations$poi$payment$es extends Translations$poi$payment$en {
	_Translations$poi$payment$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get cash => 'Efectivo';
	@override String get coins => 'Monedas';
	@override String get notes => 'Billetes';
	@override String get cards => 'Tarjeta';
	@override String get contactless => 'Sin contacto';
	@override String get app => 'Aplicación móvil';
}

// Path: poi.add
class _Translations$poi$add$es extends Translations$poi$add$en {
	_Translations$poi$add$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => '¿Una máquina expendedora aquí?';
	@override String get hint => 'Elige lo que vende: se añadirá al mapa de todos los viajeros.';
	@override String get pizza => 'Pizzas';
	@override String get bread => 'Pan';
	@override String get other => 'Otros alimentos';
	@override String get gate => 'Añadir una máquina expendedora';
	@override String get sent => 'Gracias: la máquina aparecerá en el mapa en unos minutos.';
	@override String get duplicateTitle => 'Ya está en el mapa';
	@override String get duplicateBody => 'Ya figura una máquina del mismo tipo a menos de 25 m. ¿Sigue ahí?';
	@override String get duplicateThere => 'Sí, sigue ahí';
	@override String get duplicateGone => 'No, ya no está';
}

// Path: poi.cheapest
class _Translations$poi$cheapest$es extends Translations$poi$cheapest$en {
	_Translations$poi$cheapest$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Más barato cerca de mí';
	@override String get show => 'Más barato cerca';
	@override String get zoomIn => 'Acerca el mapa para comparar los precios de las gasolineras.';
	@override String get none => 'Ninguna gasolinera del mapa vende este combustible.';
	@override String get noneHint => 'Mueve el mapa o elige otro combustible.';
	@override String get error => 'No se han podido cargar los precios de las gasolineras.';
}

// Path: poi.trend
class _Translations$poi$trend$es extends Translations$poi$trend$en {
	_Translations$poi$trend$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String title({required Object fuel}) => '${fuel}: precios de los últimos días';
	@override String get none => 'Lunaway todavía no ha visto ningún precio de este combustible aquí.';
	@override String get failed => 'No se han podido leer ahora los precios de los últimos días.';
	@override String get week => 'Últimos 7 días:';
	@override String get month => 'Últimos 30 días:';
	@override String range({required Object low, required Object high}) => 'de ${low} a ${high}';
	@override String span({required Object range, required Object move}) => '${range}, ${move}';
	@override String get oneDay => 'un solo día registrado';
	@override String get steady => 'sin cambios';
	@override String down({required Object amount}) => 'ha bajado ${amount}';
	@override String up({required Object amount}) => 'ha subido ${amount}';
	@override String since({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n,
		one: '${n} día registrado desde el ${date} según los datos de la fuente; los días sin datos quedan en blanco',
		other: '${n} días registrados desde el ${date} según los datos de la fuente; los días sin datos quedan en blanco',
	);
}

// Path: roadReport.kinds
class _Translations$roadReport$kinds$es extends Translations$roadReport$kinds$en {
	_Translations$roadReport$kinds$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get closure => 'Carretera cortada';
	@override String get works => 'Obras';
	@override String get narrowPassage => 'Paso estrecho';
	@override String get lowClearance => 'Altura limitada';
	@override String get other => 'Problema en la carretera';
}

// Path: navigation.preview.departure
class _Translations$navigation$preview$departure$es extends Translations$navigation$preview$departure$en {
	_Translations$navigation$preview$departure$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Salida';
	@override String from({required Object name}) => 'Salida: ${name}';
	@override String get myPosition => 'mi ubicación';
	@override String get myPositionChoice => 'Mi ubicación';
	@override String get change => 'Cambiar';
	@override String get choose => 'Elegir el punto de salida';
	@override String get searchHint => 'Lugar, municipio o dirección';
	@override String get guidanceFromPosition => 'La navegación empieza en tu ubicación, no en el punto de salida elegido.';
	@override String get fromMyPosition => 'Salir desde mi ubicación';
}

// Path: navigation.preview.moved
class _Translations$navigation$preview$moved$es extends Translations$navigation$preview$moved$en {
	_Translations$navigation$preview$moved$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String origin({required Object distance}) => 'Salida desplazada ${distance} hasta la calle accesible más cercana';
	@override String destination({required Object distance}) => 'Destino desplazado ${distance} hasta la calle accesible más cercana';
	@override String stop({required Object n, required Object distance}) => 'Parada ${n} desplazada ${distance} hasta la calle accesible más cercana';
}

// Path: navigation.onTheWay.categories
class _Translations$navigation$onTheWay$categories$es extends Translations$navigation$onTheWay$categories$en {
	_Translations$navigation$onTheWay$categories$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get fuel => 'Combustible';
	@override String get sleep => 'Dormir';
	@override String get water => 'Agua y vaciado';
	@override String get groceries => 'Compras';
	@override String get bakeries => 'Panaderías';
	@override String get toilets => 'Aseos, duchas';
	@override String get health => 'Salud';
	@override String get services => 'Servicios';
	@override String get charging => 'Recarga';
	@override String get garages => 'Talleres';
}

// Path: navigation.states.dimension
class _Translations$navigation$states$dimension$es extends Translations$navigation$states$dimension$en {
	_Translations$navigation$states$dimension$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get height => 'altura';
	@override String get width => 'anchura';
	@override String get length => 'longitud';
	@override String get weight => 'peso';
}

// Path: navigation.noRoute.limit
class _Translations$navigation$noRoute$limit$es extends Translations$navigation$noRoute$limit$en {
	_Translations$navigation$noRoute$limit$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'puente bajo de ${limit}';
	@override String tunnel({required Object limit}) => 'túnel de ${limit}';
	@override String buildingPassage({required Object limit}) => 'paso bajo edificio de ${limit}';
	@override String bridge({required Object limit}) => 'puente de ${limit}';
	@override String barrier({required Object limit}) => 'barra de gálibo de ${limit}';
	@override String height({required Object limit}) => 'altura limitada a ${limit}';
	@override String get heightUnknown => 'altura limitada';
	@override String width({required Object limit}) => 'paso estrecho de ${limit}';
	@override String get widthUnknown => 'paso estrecho';
	@override String length({required Object limit}) => 'longitud limitada a ${limit}';
	@override String get lengthUnknown => 'longitud limitada';
	@override String weight({required Object limit}) => 'peso limitado a ${limit}';
	@override String get weightUnknown => 'peso limitado';
	@override String get unpaved => 'camino sin asfaltar';
	@override String weightLocalAccess({required Object limit}) => 'peso limitado a ${limit}, salvo para acceder a la zona';
	@override String widthLocalAccess({required Object limit}) => 'paso estrecho de ${limit}, salvo para acceder a la zona';
	@override String lengthLocalAccess({required Object limit}) => 'longitud limitada a ${limit}, salvo para acceder a la zona';
}

// Path: navigation.warning.lowClearance
class _Translations$navigation$warning$lowClearance$es extends Translations$navigation$warning$lowClearance$en {
	_Translations$navigation$warning$lowClearance$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String underpass({required Object limit}) => 'Puente bajo ${limit}';
	@override String tunnel({required Object limit}) => 'Túnel ${limit}';
	@override String buildingPassage({required Object limit}) => 'Paso bajo edificio ${limit}';
	@override String bridge({required Object limit}) => 'Puente ${limit}';
	@override String barrier({required Object limit}) => 'Barra de gálibo ${limit}';
	@override String road({required Object limit}) => 'Altura máxima ${limit}';
}

// Path: navigation.warning.localAccess
class _Translations$navigation$warning$localAccess$es extends Translations$navigation$warning$localAccess$en {
	_Translations$navigation$warning$localAccess$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String weight({required Object limit}) => 'Vehículos de más de ${limit}: solo para acceder a la zona';
	@override String axleLoad({required Object limit}) => 'Más de ${limit} por eje: solo para acceder a la zona';
	@override String width({required Object limit}) => 'Vehículos de más de ${limit} de ancho: solo para acceder a la zona';
	@override String length({required Object limit}) => 'Vehículos de más de ${limit} de largo: solo para acceder a la zona';
}

// Path: navigation.guidance.notificationWhy
class _Translations$navigation$guidance$notificationWhy$es extends Translations$navigation$guidance$notificationWhy$en {
	_Translations$navigation$guidance$notificationWhy$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notificación de navegación';
	@override String get body => 'Durante la navegación, una notificación mantiene activas la ubicación y la voz con la pantalla apagada, y al tocarla vuelves a la navegación. Android te preguntará si Lunaway puede mostrarla.';
	@override String get ask => 'Continuar';
	@override String get later => 'Ahora no';
}

// Path: navigation.guidance.places
class _Translations$navigation$guidance$places$es extends Translations$navigation$guidance$places$en {
	_Translations$navigation$guidance$places$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String get button => 'Lugares en el mapa';
	@override String get buttonHidden => 'Lugares en el mapa: ocultos';
	@override String get title => 'Lugares en el mapa';
	@override String get sleep => 'Para dormir';
	@override String get fill => 'Repostar';
	@override String get groceries => 'Para comer';
	@override String get all => 'Todo';
	@override String get everyPlace => 'Todos los lugares';
	@override String get none => 'Nada';
	@override String get customize => 'Personalizar';
	@override String get look => 'Vista';
	@override String get photos => 'Fotos';
	@override String get pictograms => 'Iconos';
	@override String get dots => 'Chinchetas';
	@override String get photosHint => 'Los lugares que más importan, en foto. Nunca sobre la carretera que tienes delante ni bajo los botones.';
	@override String get pictogramsHint => 'Los lugares que más importan, en grande, con su precio, su valoración o la pernocta.';
	@override String get dotsHint => 'Todos los lugares como pequeñas chinchetas, como en el mapa.';
	@override String get free => 'Gratis';
	@override String get nightOk => 'Pernocta';
}

// Path: navigation.voice.moved
class _Translations$navigation$voice$moved$es extends Translations$navigation$voice$moved$en {
	_Translations$navigation$voice$moved$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String destination({required Object distance}) => 'Destino desplazado ${distance} hasta la calle accesible más cercana.';
	@override String stop({required Object n, required Object distance}) => 'Parada ${n} desplazada ${distance} hasta la calle accesible más cercana.';
}

// Path: navigation.voice.localAccess
class _Translations$navigation$voice$localAccess$es extends Translations$navigation$voice$localAccess$en {
	_Translations$navigation$voice$localAccess$es._(TranslationsEs root) : this._root = root, super.internal(root);

	final TranslationsEs _root; // ignore: unused_field

	// Translations
	@override String weight({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit}, salvo para acceder a la zona.';
	@override String axleLoad({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit} por eje, salvo para acceder a la zona.';
	@override String width({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit} de ancho, salvo para acceder a la zona.';
	@override String length({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit} de largo, salvo para acceder a la zona.';
}

/// The flat map containing all translations for locale <es>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsEs {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'appTitle' => 'Lunaway',
			'nav.map' => 'Mapa',
			'nav.favorites' => 'Favoritos',
			'nav.profile' => 'Perfil',
			'nav.fold' => 'Contraer el menú',
			'nav.unfold' => 'Desplegar el menú',
			'common.close' => 'Cerrar',
			'common.done' => 'Hecho',
			'common.cancel' => 'Cancelar',
			'common.retry' => 'Reintentar',
			'common.save' => 'Guardar',
			'common.delete' => 'Eliminar',
			'common.undo' => 'Deshacer',
			'common.ok' => 'Entendido',
			'common.saveFailed' => 'No se ha podido guardar el cambio.',
			'common.send' => 'Enviar',
			'common.later' => 'Más tarde',
			'common.next' => 'Continuar',
			'common.failed' => 'No ha funcionado. Vuelve a intentarlo en un momento.',
			'common.offline' => 'Ahora mismo no hay conexión. Vuelve a intentarlo cuando tengas cobertura.',
			'kinds.motorhomeArea' => 'Área de autocaravanas',
			'kinds.serviceArea' => 'Punto de servicio para autocaravanas',
			'kinds.campsite' => 'Camping',
			'kinds.parking' => 'Aparcamiento',
			'kinds.nature' => 'Lugar en plena naturaleza',
			'kinds.restArea' => 'Área de descanso',
			'kinds.picnicArea' => 'Área de pícnic',
			'kinds.farm' => 'Granja',
			'kinds.homestay' => 'Casa particular',
			'kinds.offRoad' => 'Lugar con acceso por pista',
			'kinds.extraService' => 'Parada práctica',
			'families.stopovers' => 'Áreas y aparcamientos',
			'families.stopoversHint' => 'Áreas de autocaravanas, aparcamientos, áreas de descanso',
			'families.campsites' => 'Campings y anfitriones',
			'families.campsitesHint' => 'Campings, granjas, particulares',
			'families.nature' => 'Naturaleza',
			'families.natureHint' => 'Lugares en plena naturaleza, pistas',
			'families.services' => 'Servicios',
			'families.servicesHint' => 'Agua y vaciado, sin pernocta',
			'services.drinkingWater' => 'Agua potable',
			'services.greyWater' => 'Vaciado de aguas grises',
			'services.blackWater' => 'Vaciado de WC químico',
			'services.wasteBin' => 'Contenedores',
			'services.toilets' => 'Aseos',
			'services.showers' => 'Duchas',
			'services.electricity' => 'Electricidad',
			'services.wifi' => 'Wi-Fi',
			'services.laundry' => 'Lavandería',
			'services.lpg' => 'GLP',
			'services.gasBottles' => 'Bombonas de gas',
			'services.vehicleWash' => 'Lavado del vehículo',
			'services.bakery' => 'Panadería',
			'services.swimmingPool' => 'Piscina',
			'services.petsAllowed' => 'Se admiten mascotas',
			'services.mobileData' => 'Cobertura móvil',
			'services.winterCaravanning' => 'Abierto en invierno',
			'activities.monuments' => 'Monumentos y visitas',
			'activities.windsurfKitesurf' => 'Windsurf, kitesurf',
			'activities.mountainBiking' => 'Bicicleta de montaña',
			'activities.hiking' => 'Senderismo',
			'activities.climbing' => 'Escalada',
			'activities.canoeKayak' => 'Canoa, kayak',
			'activities.fishing' => 'Pesca',
			'activities.shoreFishing' => 'Marisqueo a pie',
			'activities.swimming' => 'Baño',
			'activities.motorcycling' => 'Rutas en moto',
			'activities.viewpoint' => 'Mirador',
			'activities.playground' => 'Parque infantil',
			'amenities.water' => 'Agua',
			'amenities.dumpStation' => 'Vaciado',
			'amenities.electricity' => 'Electricidad',
			'amenities.toilets' => 'Aseos',
			'amenities.showers' => 'Duchas',
			'amenities.wasteBin' => 'Contenedores',
			'amenities.laundry' => 'Lavandería',
			'amenities.wifi' => 'Wi-Fi',
			'amenities.lpg' => 'GLP',
			'overnight.allowed' => 'Pernocta permitida',
			'overnight.tolerated' => 'Pernocta tolerada',
			'overnight.dayOnly' => 'Solo de día',
			'overnight.forbidden' => 'Pernocta prohibida',
			'overnight.unknown' => 'Pernocta sin información',
			'overnight.allowedHint' => 'Puedes pasar la noche aquí.',
			'overnight.toleratedHint' => 'Normalmente se acepta una noche. Actúa con discreción y no dejes rastro.',
			'overnight.dayOnlyHint' => 'Solo se puede aparcar de día. Busca otro lugar para la noche.',
			'overnight.forbiddenHint' => 'Aquí está prohibido pasar la noche.',
			'overnight.unknownHint' => 'Nadie lo ha indicado todavía. Pregunta al llegar.',
			'freshness.confirmed' => ({required Object when}) => 'Confirmado por un viajero ${when}',
			'freshness.unconfirmed' => 'Aún no lo ha confirmado ningún viajero',
			'freshness.stale' => 'Última confirmación hace más de un año',
			'freshness.today' => 'hoy',
			'freshness.daysAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'ayer', other: 'hace ${n} días', ), 
			'freshness.monthsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'hace un mes', other: 'hace ${n} meses', ), 
			'freshness.yearsAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'hace un año', other: 'hace ${n} años', ), 
			'map.searchHint' => 'Lugar o municipio',
			'map.clearSearch' => 'Borrar la búsqueda',
			'map.locateMe' => 'Mostrar mi ubicación',
			'map.aroundMe' => 'Ver lugares cerca de mí',
			'map.zoomIn' => 'Acercar',
			'map.zoomOut' => 'Alejar',
			'map.filters' => 'Filtros',
			'map.credit' => '© OpenStreetMap · Protomaps',
			'map.creditLabel' => 'Créditos del mapa: © colaboradores de OpenStreetMap, estilo Protomaps. Abre la página de derechos de autor de OpenStreetMap.',
			'map.showList' => 'Lista',
			'map.showListCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Lista (${n})', other: 'Lista (${n})', ), 
			'map.placesHereLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'lugar aquí', other: 'lugares aquí', ), 
			'map.nearestYouLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'lugar más cercano a ti', other: 'lugares más cercanos a ti', ), 
			'map.nearestCentreLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'lugar más cercano al centro', other: 'lugares más cercanos al centro', ), 
			'map.pointTitle' => 'Aquí',
			'map.pointHint' => 'Punto en el mapa',
			'map.directionsHere' => 'Ruta hasta aquí',
			'map.startHere' => 'Salir desde aquí',
			'map.departureChosen' => 'Punto de salida elegido: ahora abre el destino para ver la ruta.',
			'map.copyCoordinates' => 'Copiar coordenadas',
			'map.freeTapHint' => 'Toca el mapa para ir allí o añadir un lugar',
			'map.freeTapHintClick' => 'Haz clic en el mapa para ir allí o añadir un lugar',
			'map.addPlaceAtCenter' => 'Añadir un lugar en el centro del mapa',
			'map.addressSource' => ({required Object attribution}) => 'Fuente: ${attribution}',
			'map.placesAround' => 'Lugares cercanos',
			'map.downloading' => 'Descargando los lugares de Francia',
			'map.downloadingCount' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${count} lugar recibido', other: '${count} lugares recibidos', ), 
			'map.noData' => 'Todavía no hay lugares en este dispositivo',
			'map.noDataHint' => 'Descarga los lugares una sola vez: después el mapa funciona sin conexión.',
			'map.download' => 'Descargar los lugares',
			'map.downloadFailed' => 'La descarga se ha interrumpido',
			'map.demoBanner' => 'Demostración: lugares ficticios',
			'map.unsupported' => 'El mapa no está disponible en este sistema. Usa la aplicación web.',
			'sync.failedOffline' => 'Sin conexión por ahora.',
			'sync.failedBusy' => 'El servidor está saturado.',
			'sync.failedServer' => 'El servidor tiene un problema en este momento.',
			'sync.failedOther' => 'La actualización no se ha completado.',
			'sync.failedRefused' => 'El servidor ha rechazado la actualización. Puede que necesites una versión más reciente de la aplicación.',
			'sync.willRetry' => 'Lunaway lo volverá a intentar automáticamente.',
			'sync.incomplete' => ({required Object count}) => 'Descarga incompleta: ${count} lugares por ahora',
			'sync.incompleteShort' => 'Descarga incompleta',
			'sync.resuming' => ({required Object count}) => 'Descargando: ${count} lugares',
			'sync.resume' => 'Reanudar',
			'location.rationaleTitle' => '¿Mostrar tu ubicación?',
			'location.rationale' => 'Lunaway la usa para centrar el mapa en ti, ordenar los lugares por distancia y guiarte. Para calcular una ruta, tu ubicación se envía al servidor de Lunaway, que no la guarda. Para buscar el combustible más barato cerca de ti, solo se envía una ubicación redondeada a unos 5 km. Si avisas de un problema en la carretera, el aviso incluye el punto donde estás.',
			'location.allow' => 'Continuar',
			'location.notNow' => 'Ahora no',
			'location.deniedTitle' => 'Ubicación desactivada para Lunaway',
			'location.denied' => 'Has denegado el acceso a tu ubicación. Para usarla, permítelo en los ajustes del dispositivo.',
			'location.openSettings' => 'Abrir ajustes',
			'location.serviceOffTitle' => 'Ubicación desactivada',
			'location.serviceOff' => 'La ubicación está desactivada en este dispositivo. Actívala en los ajustes rápidos y vuelve a intentarlo.',
			'location.notAllowed' => 'Ubicación no permitida. El mapa funciona sin ella.',
			'location.noFix' => 'Todavía no se ha encontrado tu ubicación. Vuelve a intentarlo al aire libre o dentro de un momento.',
			'location.unsupported' => 'Este dispositivo no proporciona su ubicación.',
			'location.browserDeniedTitle' => 'El navegador bloquea tu ubicación',
			'location.browserDenied' => 'El navegador no deja que Lunaway acceda a tu ubicación. Para permitirlo, haz clic en el icono a la izquierda de la dirección del sitio (un candado o unos controles deslizantes), pon Ubicación en Permitir y vuelve a hacer clic en el botón de ubicación.',
			'location.browserNoFix' => 'El navegador no ha dado ninguna ubicación. Vuelve a intentarlo dentro de un momento; en un ordenador, el Wi-Fi ayuda a encontrarla.',
			'search.towns' => 'Municipios',
			'search.places' => 'Lugares',
			'search.noResult' => ({required Object query}) => 'Ningún lugar ni municipio coincide con «${query}».',
			'search.townPlaces' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} lugar', other: '${n} lugares', ), 
			'search.addresses' => 'Direcciones',
			'search.addressesSearching' => 'Buscando direcciones',
			'search.addressesFailed' => 'No se han podido buscar las direcciones en este momento.',
			'search.addressSources' => ({required Object sources}) => 'Direcciones: ${sources}',
			'search.offline' => 'Sin conexión: la búsqueda necesita conexión.',
			'search.addressKind.houseNumber' => 'Dirección',
			'search.addressKind.street' => 'Calle',
			'search.addressKind.locality' => 'Paraje',
			'search.addressKind.town' => 'Municipio',
			'search.addressKind.postcode' => 'Código postal',
			'search.addressKind.region' => 'Región',
			'filters.title' => 'Filtros',
			'filters.families' => 'Tipo de lugar',
			'filters.familiesHint' => 'Sin elegir: todos los tipos',
			'filters.familiesChosenHint' => 'Solo estos tipos',
			'filters.night' => 'Pernocta',
			'filters.nightHint' => 'Sin elegir: todos los lugares',
			'filters.nightChosenHint' => 'Solo los lugares con estas opciones de pernocta',
			'filters.nightPossible' => 'Pernocta posible',
			'filters.amenities' => 'Servicios',
			'filters.amenitiesHint' => 'El lugar debe tenerlos todos',
			'filters.rating' => 'Valoración mínima',
			'filters.ratingHint' => 'Valoración de los viajeros de Lunaway, o la de otras fuentes si ellos no han valorado el lugar. Los lugares sin valoración se ocultan.',
			'filters.ratingAtLeast' => ({required Object rating}) => '${rating} o más',
			'filters.opening' => 'Apertura',
			'filters.openingHint' => 'Los lugares cuya apertura no se conoce se siguen mostrando.',
			'filters.openingAllYear' => 'Todo el año',
			'filters.openingDates' => 'Mis fechas',
			'filters.openingClearDates' => 'Borrar las fechas',
			'filters.openingStay' => ({required Object from, required Object to}) => 'Del ${from} al ${to}',
			'filters.openingStayDay' => ({required Object date}) => 'El ${date}',
			'filters.openingStayTitle' => 'Fechas de tu estancia',
			'filters.openingArrival' => 'Llegada',
			'filters.openingDeparture' => 'Salida',
			'filters.price' => 'Precio por noche',
			'filters.freeOnly' => 'Gratis',
			'filters.freeHint' => 'Solo los lugares donde la noche es gratis según sus fuentes',
			'filters.scrollNext' => 'Ver los filtros siguientes',
			'filters.scrollPrevious' => 'Ver los filtros anteriores',
			'filters.vehicle' => 'Mi vehículo',
			'filters.myVehicleFits' => 'Apto para mi vehículo',
			'filters.myVehicleFitsHeight' => ({required Object height}) => 'Apto para ${height}',
			'filters.myVehicleHint' => ({required Object height}) => 'Oculta los lugares con un límite de altura inferior a ${height}. Los lugares sin altura conocida siguen en el mapa.',
			'filters.reset' => 'Borrar todo',
			'filters.apply' => 'Aplicar',
			'filters.show' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, zero: 'Ningún lugar coincide', one: 'Mostrar ${count} lugar', other: 'Mostrar ${count} lugares', ), 
			'filters.active' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} filtro activo', other: '${n} filtros activos', ), 
			'place.unnamedIn' => ({required Object kind, required Object town}) => '${kind} en ${town}',
			'place.away' => ({required Object distance}) => 'a ${distance}',
			'place.directions' => 'Ruta',
			'place.share' => 'Compartir',
			'place.save' => 'Guardar',
			'place.saved' => 'Guardado',
			'place.saveHint' => 'En Mis favoritos. Mantén pulsado para elegir listas.',
			'place.saveTo' => 'Guardar en una lista',
			'place.chooseLists' => 'Listas',
			'place.savedToast' => 'Añadido a Mis favoritos',
			'place.removedToast' => 'Quitado de Mis favoritos',
			'place.pricePerNight' => 'Precio por noche',
			'place.priceFree' => 'Gratis',
			'place.priceUnknown' => 'Sin indicar',
			'place.priceServices' => 'Servicios',
			'place.priceIncluded' => 'Incluidos',
			'place.priceIncludes' => ({required Object items}) => 'El precio de la noche incluye: ${items}',
			'place.inclusions.services' => 'servicios',
			'place.inclusions.touristTax' => 'tasa turística',
			'place.inclusions.electricity' => 'electricidad',
			'place.maxHeight' => 'Altura máx.',
			'place.capacity' => 'Plazas',
			'place.classification' => 'Categoría',
			'place.classStars' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} estrella', other: '${n} estrellas', ), 
			'place.hours' => 'Horario',
			'place.services' => 'Servicios',
			'place.noServices' => 'No se indica ningún servicio.',
			'place.activities' => 'En los alrededores',
			'place.description' => 'Descripción',
			'place.contact' => 'Contacto',
			'place.website' => 'Sitio web',
			'place.call' => 'Llamar',
			'place.coordinates' => 'Coordenadas',
			'place.copy' => 'Copiar coordenadas',
			'place.copyShort' => 'Copiar',
			'place.copyAs' => ({required Object format}) => 'Copiar como ${format}',
			'place.copiesAs' => ({required Object format}) => '«Copiar» copia: ${format}',
			'place.copied' => ({required Object text}) => 'Copiado: ${text}',
			'place.otherFormats' => 'Elegir el formato que se copia',
			'place.formatDecimal' => 'Grados decimales',
			'place.formatDms' => 'Grados, minutos, segundos',
			'place.formatGeo' => 'Enlace geo:',
			'place.formatGoogle' => 'Enlace de Google Maps',
			'place.formatOsm' => 'Enlace de OpenStreetMap',
			'place.sources' => 'Fuentes',
			'place.fetched' => ({required Object when}) => 'Consultado ${when}',
			'place.viewSource' => 'Ver en la fuente',
			'place.gone' => 'Este lugar ya no está en el mapa',
			'place.goneHint' => 'Se ha retirado o se ha fusionado con otro desde la última actualización.',
			'place.arriving' => 'Este lugar todavía se está descargando',
			'place.arrivingHint' => 'Los lugares de Francia se están descargando para que el mapa funcione sin conexión. La ficha se abrirá en cuanto se descargue este lugar.',
			'place.loadError' => 'No se ha podido cargar este lugar.',
			'place.openFailed' => 'Ninguna aplicación ha podido abrir este enlace.',
			'place.photos' => 'Fotos',
			'place.extrasOffline' => 'Las fotos y las reseñas necesitan conexión.',
			'place.reviewsTitle' => 'Reseñas',
			'place.reviewsCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} reseña', other: '${n} reseñas', ), 
			'place.noReviews' => 'Todavía no hay reseñas.',
			'place.noOtherReviews' => 'Todavía no hay más reseñas.',
			'place.moreReviews' => 'Más reseñas',
			'place.moreReviewsFailed' => 'No se han podido cargar más reseñas. Toca para volver a intentarlo.',
			'place.stars' => ({required Object rating}) => '${rating} sobre 5',
			'place.externalRatingsLabel' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'reseña externa', other: 'reseñas externas', ), 
			'place.deletedAccount' => 'Cuenta eliminada',
			'place.reviewVehicle.van' => 'Van',
			'place.reviewVehicle.campervan' => 'Furgoneta camper',
			'place.reviewVehicle.motorhome' => 'Autocaravana',
			'place.reviewVehicle.caravan' => 'Caravana',
			'place.reviewVehicle.other' => 'Otro vehículo',
			'place.originalLanguage' => ({required Object language}) => 'Texto original en ${language}',
			'place.photoPosition' => ({required Object index, required Object count}) => 'Foto ${index} de ${count}',
			'place.previousPhoto' => 'Foto anterior',
			'place.nextPhoto' => 'Foto siguiente',
			'place.links' => 'En otros sitios web',
			'place.sourceWithLicence' => ({required Object source, required Object licence}) => '${source} · ${licence}',
			'place.licenceCcBy' => 'CC BY 4.0',
			'place.photoCredit' => ({required Object source, required Object author}) => '${source} · ${author}',
			'place.photoStreetView' => 'Vista de la calle',
			'place.photoSurroundings' => 'Alrededores',
			'place.excerptFrom' => ({required Object source, required Object text}) => 'Según ${source}: ${text}',
			'place.readMore' => 'Leer más',
			'place.updatedOn' => ({required Object date}) => 'actualizado el ${date}',
			'place.otherSources' => 'Según otras fuentes',
			'sources.extcom.label' => 'Fuente comunitaria externa',
			'sources.extcom.short' => 'Externa',
			'hours.open' => 'Abierto ahora',
			'hours.openUntil' => ({required Object time}) => 'Abierto, cierra a las ${time}',
			'hours.openUntilDay' => ({required Object day, required Object time}) => 'Abierto, cierra ${day} a las ${time}',
			'hours.closesIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Abierto, cierra en ${n} minuto', other: 'Abierto, cierra en ${n} minutos', ), 
			'hours.closedUntil' => ({required Object time}) => 'Cerrado, abre a las ${time}',
			'hours.closedUntilDay' => ({required Object day, required Object time}) => 'Cerrado, abre ${day} a las ${time}',
			'hours.opensIn' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Cerrado, abre en ${n} minuto', other: 'Cerrado, abre en ${n} minutos', ), 
			'hours.closedWindow' => 'Cerrado durante las próximas dos semanas',
			'hours.tomorrow' => 'mañana',
			'hours.onDate' => ({required Object date}) => 'el ${date}',
			'hours.onWeekday' => ({required Object day}) => 'el ${day}',
			'hours.midnight' => '24:00',
			'hours.stale' => '¿Abierto o cerrado? Actualiza los lugares en Perfil.',
			'hours.localTime' => 'Horario en hora local del lugar',
			'hours.codes.mo' => 'lun.',
			'hours.codes.tu' => 'mar.',
			'hours.codes.we' => 'mié.',
			'hours.codes.th' => 'jue.',
			'hours.codes.fr' => 'vie.',
			'hours.codes.sa' => 'sáb.',
			'hours.codes.su' => 'dom.',
			'hours.codes.ph' => 'festivos',
			'hours.codes.sh' => 'vacaciones escolares',
			'hours.codes.off' => 'cerrado',
			'hours.codes.closed' => 'cerrado',
			'hours.codes.sunrise' => 'amanecer',
			'hours.codes.sunset' => 'puesta de sol',
			'hours.months.jan' => 'ene.',
			'hours.months.feb' => 'feb.',
			'hours.months.mar' => 'mar.',
			'hours.months.apr' => 'abr.',
			'hours.months.may' => 'may.',
			'hours.months.jun' => 'jun.',
			'hours.months.jul' => 'jul.',
			'hours.months.aug' => 'ago.',
			'hours.months.sep' => 'sept.',
			'hours.months.oct' => 'oct.',
			'hours.months.nov' => 'nov.',
			'hours.months.dec' => 'dic.',
			'hours.dayOfMonth' => ({required Object day, required Object month}) => '${day} ${month}',
			'hours.dayOfYear' => ({required Object day, required Object month, required Object year}) => '${day} ${month} ${year}',
			'hours.allWeek' => '24 horas, todos los días',
			'hours.allYear' => 'todo el año',
			'hours.seasonAllYear' => 'Abierto todo el año',
			'hours.seasonOpenUntil' => ({required Object date}) => 'Abierto hasta el ${date}',
			'hours.seasonClosedUntil' => ({required Object date}) => 'Cerrado, abre el ${date}',
			'directions.title' => 'Abrir en',
			'directions.hint' => 'Estas aplicaciones no conocen las dimensiones de tu vehículo.',
			'directions.remember' => 'Usar siempre esta aplicación',
			'directions.rememberHint' => 'Puedes cambiarlo en Perfil',
			'directions.settingTitle' => 'Abrir en otra aplicación',
			'directions.settingHint' => 'La aplicación que se abre al tocar «Abrir en» en una ruta',
			'directions.askEachTime' => 'Preguntar cada vez',
			'directions.appleMaps' => 'Mapas',
			'directions.googleMaps' => 'Google Maps',
			'directions.waze' => 'Waze',
			'directions.osmAnd' => 'OsmAnd',
			'directions.organicMaps' => 'Organic Maps',
			'directions.magicEarth' => 'Magic Earth',
			'directions.openStreetMap' => 'OpenStreetMap (navegador)',
			'directions.none' => 'No se ha encontrado ninguna aplicación de navegación en este dispositivo.',
			'navigation.preview.titleTo' => ({required Object name}) => 'Hacia ${name}',
			'navigation.preview.titlePoint' => 'Punto en el mapa',
			'navigation.preview.departure.title' => 'Salida',
			'navigation.preview.departure.from' => ({required Object name}) => 'Salida: ${name}',
			'navigation.preview.departure.myPosition' => 'mi ubicación',
			'navigation.preview.departure.myPositionChoice' => 'Mi ubicación',
			'navigation.preview.departure.change' => 'Cambiar',
			'navigation.preview.departure.choose' => 'Elegir el punto de salida',
			'navigation.preview.departure.searchHint' => 'Lugar, municipio o dirección',
			'navigation.preview.departure.guidanceFromPosition' => 'La navegación empieza en tu ubicación, no en el punto de salida elegido.',
			'navigation.preview.departure.fromMyPosition' => 'Salir desde mi ubicación',
			'navigation.preview.computing' => 'Calculando una ruta para tu vehículo',
			'navigation.preview.start' => '¡Vamos!',
			'navigation.preview.recommended' => 'Recomendada',
			'navigation.preview.alternative' => ({required Object n}) => 'Alternativa ${n}',
			'navigation.preview.toll' => 'Peaje',
			'navigation.preview.ferry' => 'Ferri',
			'navigation.preview.motorway' => 'Autopista',
			'navigation.preview.noWarnings' => 'Esta ruta no tiene ninguna limitación cercana a las dimensiones de tu vehículo.',
			'navigation.preview.warnings' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '1 limitación a tener en cuenta', other: '${n} limitaciones a tener en cuenta', ), 
			'navigation.preview.vehicle' => 'Tu vehículo',
			'navigation.preview.vehicleTowing' => ({required Object vehicle}) => '${vehicle}, con remolque',
			'navigation.preview.editVehicle' => 'Editar',
			'navigation.preview.cruise' => ({required Object speed}) => 'Tiempo calculado a ${speed} como máximo',
			'navigation.preview.avoid' => 'Evitar',
			'navigation.preview.avoidTolls' => 'Peajes',
			'navigation.preview.avoidMotorways' => 'Autopistas',
			'navigation.preview.avoidFerries' => 'Ferris',
			'navigation.preview.avoidUnpaved' => 'Caminos sin asfaltar',
			'navigation.preview.roadbook' => 'Hoja de ruta',
			'navigation.preview.roadbookShow' => 'Ver las indicaciones',
			'navigation.preview.roadbookHide' => 'Ocultar las indicaciones',
			'navigation.preview.dataOf' => ({required Object date}) => 'Datos viales del ${date}',
			'navigation.preview.attributionOsm' => '© colaboradores de OpenStreetMap',
			'navigation.preview.attributionIgn' => ({required Object date}) => 'IGN, BD TOPO, edición del ${date}',
			'navigation.preview.disclaimer' => 'Lunaway calcula la ruta con las dimensiones de tu vehículo y con datos abiertos (OpenStreetMap, IGN) que pueden estar incompletos o ser erróneos. Las señales y las normas de circulación siempre tienen prioridad. La responsabilidad de la conducción es solo tuya.',
			'navigation.preview.otherApps' => 'Abrir en…',
			'navigation.preview.back' => 'Volver',
			'navigation.preview.moved.origin' => ({required Object distance}) => 'Salida desplazada ${distance} hasta la calle accesible más cercana',
			'navigation.preview.moved.destination' => ({required Object distance}) => 'Destino desplazado ${distance} hasta la calle accesible más cercana',
			'navigation.preview.moved.stop' => ({required Object n, required Object distance}) => 'Parada ${n} desplazada ${distance} hasta la calle accesible más cercana',
			'navigation.stops.title' => 'Paradas',
			'navigation.stops.add' => 'Añadir como parada',
			'navigation.stops.addCost' => ({required Object minutes}) => 'Añadir como parada · +${minutes} min',
			'navigation.stops.addFree' => 'Añadir como parada · sin desvío',
			'navigation.stops.quoting' => 'Añadir como parada · calculando el desvío',
			'navigation.stops.noRoute' => 'No hay ruta por este punto para tu vehículo.',
			'navigation.stops.full' => 'Cinco paradas como máximo.',
			'navigation.stops.goDirectly' => 'Ir directamente',
			'navigation.stops.openCard' => 'Ver la ficha',
			'navigation.stops.point' => 'Punto en el mapa',
			'navigation.stops.remove' => 'Quitar la parada',
			'navigation.stops.reorder' => 'Arrastra para cambiar el orden',
			'navigation.stops.added' => 'Parada añadida',
			'navigation.stops.removed' => 'Parada quitada',
			'navigation.stops.moved' => 'Orden de las paradas cambiado',
			'navigation.stops.destinationChanged' => 'Nuevo destino',
			'navigation.stops.failed' => 'No se ha podido cambiar la ruta.',
			'navigation.stops.noQuote' => 'No se ha podido calcular el desvío.',
			'navigation.stops.offline' => 'Sin conexión para calcular el desvío.',
			'navigation.fuel.price' => ({required Object price}) => '${price} €/l',
			'navigation.fuel.withDetour' => ({required Object price}) => '${price} €/l, desvío incluido',
			'navigation.fuel.detour' => ({required Object distance, required Object minutes}) => '+${distance} · +${minutes} min',
			'navigation.fuel.onRoute' => 'en la ruta',
			'navigation.fuel.open' => 'Abierta',
			'navigation.fuel.closed' => 'Cerrada',
			'navigation.fuel.unknownHours' => 'Horario desconocido',
			'navigation.fuel.add' => 'Añadir',
			'navigation.fuel.station' => 'Gasolinera',
			'navigation.fuel.empty' => 'Ninguna gasolinera vende este combustible cerca de la ruta.',
			'navigation.fuel.failed' => 'No se han podido cargar las gasolineras.',
			'navigation.fuel.estimated' => 'Desvíos estimados según la distancia a la ruta.',
			'navigation.fuel.attribution' => 'Precios: Ministerio de Economía de Francia (data.economie.gouv.fr)',
			'navigation.fuel.minutesAgo' => ({required Object n}) => 'hace ${n} min',
			'navigation.fuel.hoursAgo' => ({required Object n}) => 'hace ${n} h',
			'navigation.fuel.daysAgo' => ({required Object n}) => 'hace ${n} días',
			'navigation.onTheWay.title' => 'En el camino',
			'navigation.onTheWay.categories.fuel' => 'Combustible',
			'navigation.onTheWay.categories.sleep' => 'Dormir',
			'navigation.onTheWay.categories.water' => 'Agua y vaciado',
			'navigation.onTheWay.categories.groceries' => 'Compras',
			'navigation.onTheWay.categories.bakeries' => 'Panaderías',
			'navigation.onTheWay.categories.toilets' => 'Aseos, duchas',
			'navigation.onTheWay.categories.health' => 'Salud',
			'navigation.onTheWay.categories.services' => 'Servicios',
			'navigation.onTheWay.categories.charging' => 'Recarga',
			'navigation.onTheWay.categories.garages' => 'Talleres',
			'navigation.onTheWay.fuelOfVehicle' => ({required Object fuel}) => '${fuel}, según tu vehículo',
			'navigation.onTheWay.otherFuel' => 'Otro combustible',
			'navigation.onTheWay.keepFuel' => 'Guardar como mi combustible',
			'navigation.onTheWay.fuelKept' => ({required Object fuel}) => '${fuel} guardado para tu vehículo.',
			'navigation.onTheWay.keepFuelFailed' => 'No se ha podido guardar el combustible.',
			'navigation.onTheWay.loading' => 'Buscando a lo largo de la ruta',
			'navigation.onTheWay.empty' => 'Sin resultados en esta ruta',
			'navigation.onTheWay.emptyHint' => 'Prueba otra categoría, o vuelve a abrir la lista más adelante en la ruta.',
			'navigation.onTheWay.failed' => 'No se ha podido cargar la lista.',
			'navigation.onTheWay.offline' => 'Sin conexión: la lista volverá con la conexión.',
			'navigation.onTheWay.rateLimited' => 'Muchas búsquedas seguidas: vuelve a intentarlo en unos minutos.',
			'navigation.onTheWay.nearNone' => ({required Object distance}) => 'Nada en los próximos ${distance}.',
			'navigation.onTheWay.further' => ({required Object n}) => 'Más adelante (${n})',
			'navigation.onTheWay.more' => 'Ver más',
			'navigation.onTheWay.moreFailed' => 'No se ha podido cargar el resto.',
			'navigation.onTheWay.ahead' => ({required Object distance}) => 'a ${distance}',
			'navigation.onTheWay.offRoute' => ({required Object distance}) => 'a ${distance} de la ruta',
			'navigation.onTheWay.byTheRoad' => 'junto a la carretera',
			'navigation.onTheWay.addCost' => ({required Object minutes}) => 'Añadir · +${minutes} min',
			'navigation.onTheWay.addFree' => 'Añadir · sin desvío',
			'navigation.onTheWay.openAt' => ({required Object time}) => 'Abierto cuando pases, hacia las ${time}',
			'navigation.onTheWay.closedAt' => ({required Object time}) => 'Cerrado cuando pases, hacia las ${time}',
			'navigation.onTheWay.closedOpensAt' => ({required Object time, required Object opens}) => 'Cerrado cuando pases hacia las ${time}, abre a las ${opens}',
			'navigation.onTheWay.perNight' => ({required Object price}) => '${price} la noche',
			'navigation.onTheWay.photoFrom' => ({required Object source}) => 'Foto: ${source}',
			'navigation.onTheWay.servicesList' => ({required Object list}) => 'Servicios: ${list}',
			'navigation.onTheWay.movingBody' => 'No busques nada mientras conduces. Puede hacerlo un pasajero; si no, detente primero.',
			'navigation.onTheWay.placesCredit' => 'Lugares: Lunaway y las fuentes indicadas en cada ficha',
			'navigation.states.vehicleTitle' => '¿Cuál es tu vehículo?',
			'navigation.states.vehicleHint' => 'La ruta evita los puentes demasiado bajos, las calles demasiado estrechas y las carreteras prohibidas para las dimensiones de tu vehículo. Indica su altura, anchura, longitud y peso.',
			'navigation.states.vehicleMissing' => ({required Object list}) => 'Faltan datos: ${list}',
			'navigation.states.vehicleOutOfBounds' => ({required Object list}) => 'Fuera de los valores aceptados: ${list}',
			'navigation.states.dimension.height' => 'altura',
			'navigation.states.dimension.width' => 'anchura',
			'navigation.states.dimension.length' => 'longitud',
			'navigation.states.dimension.weight' => 'peso',
			'navigation.states.describeVehicle' => 'Describir mi vehículo',
			'navigation.states.originTitle' => '¿Dónde estás?',
			'navigation.states.originHint' => 'Lunaway necesita tu ubicación para calcular la ruta.',
			'navigation.states.locate' => 'Localizarme',
			'navigation.states.offlineTitle' => 'Sin conexión',
			'navigation.states.offlineHint' => 'Las rutas se calculan en el servidor de Lunaway. Sin conexión, «Abrir en…» pasa el viaje a una aplicación de navegación que guarda sus mapas.',
			'navigation.states.rateLimitedTitle' => 'Demasiadas rutas solicitadas',
			'navigation.states.rateLimitedHint' => ({required Object seconds}) => 'Vuelve a intentarlo dentro de ${seconds} s.',
			'navigation.states.unavailableTitle' => 'Cálculo de rutas no disponible',
			'navigation.states.unavailableHint' => 'El servicio no está disponible en este momento. Vuelve a intentarlo más tarde.',
			'navigation.states.refusedTitle' => 'No hay ruta aquí',
			'navigation.states.refusedHint' => 'Lunaway no ha podido calcular una ruta para esta solicitud: comprueba el destino, la longitud del trayecto y los datos del vehículo.',
			'navigation.states.noSafeTitle' => 'No hay ninguna ruta segura para tu vehículo',
			'navigation.states.noSafeHint' => 'Todas las carreteras posibles pasan por una limitación que tu vehículo supera:',
			'navigation.states.whatToDo' => 'Qué puedes hacer',
			'navigation.states.checkVehicle' => ({required Object height, required Object weight}) => 'Comprueba los datos introducidos: ${height} de alto, ${weight}.',
			'navigation.states.pickOtherPoint' => 'Elige un destino antes del obstáculo: mantén pulsado el mapa.',
			'navigation.states.noRouteTitle' => 'Ninguna carretera lleva a este punto',
			'navigation.states.noRouteHint' => 'Puede que el punto esté en una vía privada o en una isla sin ferri.',
			'navigation.states.allowUnpaved' => 'Se evitan los caminos sin asfaltar: permítelos si el destino está en una pista.',
			'navigation.states.offNetworkTitle' => 'Demasiado lejos de una carretera',
			'navigation.states.offNetworkHint' => 'Elige un destino en una carretera.',
			'navigation.noRoute.originUnreachable' => 'Tu vehículo no puede salir de aquí',
			'navigation.noRoute.originUnreachableBy' => ({required Object limit}) => 'Tu vehículo no puede salir de aquí: ${limit}',
			'navigation.noRoute.destinationUnreachable' => 'Destino inaccesible para tu vehículo',
			'navigation.noRoute.destinationUnreachableBy' => ({required Object limit}) => 'Destino inaccesible para tu vehículo: ${limit}',
			'navigation.noRoute.waypointUnreachable' => ({required Object n}) => 'Parada ${n} inaccesible para tu vehículo',
			'navigation.noRoute.waypointUnreachableBy' => ({required Object n, required Object limit}) => 'Parada ${n} inaccesible para tu vehículo: ${limit}',
			'navigation.noRoute.blockedOnTheWay' => 'Tu vehículo no tiene paso entre las paradas',
			'navigation.noRoute.blockedOnTheWayBy' => ({required Object limit}) => 'Tu vehículo no tiene paso entre las paradas: ${limit}',
			'navigation.noRoute.blockedHint' => 'Se puede llegar a cada parada, pero todas las carreteras que las unen pasan por una limitación que tu vehículo supera.',
			'navigation.noRoute.notConnectedOrigin' => 'Ninguna carretera sale de tu ubicación',
			'navigation.noRoute.notConnectedDestination' => 'Ninguna carretera lleva al destino',
			'navigation.noRoute.notConnectedWaypoint' => ({required Object n}) => 'Ninguna carretera lleva a la parada ${n}',
			'navigation.noRoute.notConnectedTrip' => 'Ninguna carretera une tus paradas',
			'navigation.noRoute.notConnectedHint' => 'Sea cual sea el vehículo: una isla sin ferri para vehículos o una vía cerrada al tráfico.',
			'navigation.noRoute.outsideOrigin' => 'Tu ubicación está fuera de la zona donde Lunaway calcula rutas',
			'navigation.noRoute.outsideDestination' => 'Destino fuera de la zona donde Lunaway calcula rutas',
			'navigation.noRoute.outsideWaypoint' => ({required Object n}) => 'Parada ${n} fuera de la zona donde Lunaway calcula rutas',
			'navigation.noRoute.outsideHint' => ({required Object countries}) => 'Lunaway calcula rutas en estos países: ${countries}.',
			_ => null,
		} ?? switch (path) {
			'navigation.noRoute.outsideHintUnknown' => 'Lunaway todavía no calcula rutas en este país.',
			'navigation.noRoute.noRoadOrigin' => 'Tu ubicación está demasiado lejos de una carretera',
			'navigation.noRoute.noRoadDestination' => 'Destino demasiado lejos de una carretera',
			'navigation.noRoute.noRoadWaypoint' => ({required Object n}) => 'Parada ${n} demasiado lejos de una carretera',
			'navigation.noRoute.noRoadHint' => 'No hay ninguna carretera que tu vehículo pueda tomar a menos de 5 km de este punto.',
			'navigation.noRoute.tooLong' => 'Trayecto demasiado largo',
			'navigation.noRoute.tooLongHint' => ({required Object trip, required Object max}) => '${trip} en línea recta de parada en parada: Lunaway calcula trayectos de ${max} como máximo.',
			'navigation.noRoute.vehicleValue' => ({required Object value}) => 'Tu vehículo: ${value}',
			'navigation.noRoute.limit.underpass' => ({required Object limit}) => 'puente bajo de ${limit}',
			'navigation.noRoute.limit.tunnel' => ({required Object limit}) => 'túnel de ${limit}',
			'navigation.noRoute.limit.buildingPassage' => ({required Object limit}) => 'paso bajo edificio de ${limit}',
			'navigation.noRoute.limit.bridge' => ({required Object limit}) => 'puente de ${limit}',
			'navigation.noRoute.limit.barrier' => ({required Object limit}) => 'barra de gálibo de ${limit}',
			'navigation.noRoute.limit.height' => ({required Object limit}) => 'altura limitada a ${limit}',
			'navigation.noRoute.limit.heightUnknown' => 'altura limitada',
			'navigation.noRoute.limit.width' => ({required Object limit}) => 'paso estrecho de ${limit}',
			'navigation.noRoute.limit.widthUnknown' => 'paso estrecho',
			'navigation.noRoute.limit.length' => ({required Object limit}) => 'longitud limitada a ${limit}',
			'navigation.noRoute.limit.lengthUnknown' => 'longitud limitada',
			'navigation.noRoute.limit.weight' => ({required Object limit}) => 'peso limitado a ${limit}',
			'navigation.noRoute.limit.weightUnknown' => 'peso limitado',
			'navigation.noRoute.limit.unpaved' => 'camino sin asfaltar',
			'navigation.noRoute.limit.weightLocalAccess' => ({required Object limit}) => 'peso limitado a ${limit}, salvo para acceder a la zona',
			'navigation.noRoute.limit.widthLocalAccess' => ({required Object limit}) => 'paso estrecho de ${limit}, salvo para acceder a la zona',
			'navigation.noRoute.limit.lengthLocalAccess' => ({required Object limit}) => 'longitud limitada a ${limit}, salvo para acceder a la zona',
			'navigation.noRoute.editVehicle' => 'Modificar el vehículo',
			'navigation.noRoute.allowUnpaved' => 'Permitir caminos sin asfaltar',
			'navigation.noRoute.removeStop' => ({required Object n}) => 'Quitar la parada ${n}',
			'navigation.noRoute.removeStopNamed' => ({required Object name}) => 'Quitar la parada «${name}»',
			'navigation.noRoute.placesAround' => 'Ver los lugares alrededor del destino',
			'navigation.noRoute.moveDestination' => 'O elige otro destino: mantén pulsado el mapa y luego «Ir directamente».',
			'navigation.noRoute.moveStop' => 'Para otra parada: amplía bien el mapa y tócalo, o mantenlo pulsado, y luego «Añadir como parada».',
			'navigation.noRoute.moveOrigin' => 'La salida es tu ubicación: llega a una carretera que tu vehículo pueda tomar y vuelve a intentarlo.',
			'navigation.noRoute.pickInside' => 'Elige un destino en uno de estos países.',
			'navigation.noRoute.shorter' => 'Elige un destino más cercano o haz el trayecto en varios tramos.',
			'navigation.ferry.title' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Travesía en ferri', other: '${n} travesías en ferri', ), 
			'navigation.ferry.unnamed' => 'Ferri',
			'navigation.ferry.named' => ({required Object name}) => 'Ferri ${name}',
			'navigation.ferry.ports' => ({required Object ports}) => 'Puertos: ${ports}',
			'navigation.ferry.countries' => ({required Object from, required Object to}) => 'Embarque: ${from} · Desembarque: ${to}',
			'navigation.ferry.country' => ({required Object country}) => 'País: ${country}',
			'navigation.ferry.where' => ({required Object distance, required Object sea, required Object duration}) => 'A ${distance} de la salida · ${sea} por mar, aproximadamente ${duration}',
			'navigation.ferry.needed' => 'No se puede llegar al destino sin ferri: la ruta toma uno, aunque evites los ferris.',
			'navigation.warning.lowClearance.underpass' => ({required Object limit}) => 'Puente bajo ${limit}',
			'navigation.warning.lowClearance.tunnel' => ({required Object limit}) => 'Túnel ${limit}',
			'navigation.warning.lowClearance.buildingPassage' => ({required Object limit}) => 'Paso bajo edificio ${limit}',
			'navigation.warning.lowClearance.bridge' => ({required Object limit}) => 'Puente ${limit}',
			'navigation.warning.lowClearance.barrier' => ({required Object limit}) => 'Barra de gálibo ${limit}',
			'navigation.warning.lowClearance.road' => ({required Object limit}) => 'Altura máxima ${limit}',
			'navigation.warning.unknownClearance' => 'Paso de altura limitada, altura desconocida',
			'navigation.warning.narrow' => ({required Object limit}) => 'Paso estrecho ${limit}',
			'navigation.warning.tooLong' => ({required Object limit}) => 'Longitud máxima ${limit}',
			'navigation.warning.tooHeavy' => ({required Object limit}) => 'Peso máximo ${limit}',
			'navigation.warning.axleLoad' => ({required Object limit}) => 'Carga máxima por eje ${limit}',
			'navigation.warning.motorhomeBan' => 'Prohibido para autocaravanas',
			'navigation.warning.trailerBan' => 'Prohibido para remolques',
			'navigation.warning.goodsVehicleWeight' => ({required Object limit}) => 'Peso máximo para camiones ${limit}',
			'navigation.warning.yours' => ({required Object value}) => 'tu vehículo: ${value}',
			'navigation.warning.fromStart' => ({required Object distance}) => 'a ${distance} de la salida',
			'navigation.warning.ahead' => ({required Object distance}) => 'a ${distance}',
			'navigation.warning.disputed' => 'las fuentes no coinciden, se aplica el valor más bajo',
			'navigation.warning.goodsOnly' => 'afecta a los camiones, consulta las señales',
			'navigation.warning.osm' => 'OpenStreetMap',
			'navigation.warning.ign' => 'IGN BD TOPO',
			'navigation.warning.community' => 'Aviso de viajeros de Lunaway',
			'navigation.warning.dialog' => 'Resolución de tráfico (DiaLog)',
			'navigation.warning.localAccess.weight' => ({required Object limit}) => 'Vehículos de más de ${limit}: solo para acceder a la zona',
			'navigation.warning.localAccess.axleLoad' => ({required Object limit}) => 'Más de ${limit} por eje: solo para acceder a la zona',
			'navigation.warning.localAccess.width' => ({required Object limit}) => 'Vehículos de más de ${limit} de ancho: solo para acceder a la zona',
			'navigation.warning.localAccess.length' => ({required Object limit}) => 'Vehículos de más de ${limit} de largo: solo para acceder a la zona',
			'navigation.roadEvents.title' => 'Obras y cortes',
			'navigation.roadEvents.none' => 'No hay obras ni cortes conocidos en esta ruta.',
			'navigation.roadEvents.stale' => 'Obras y cortes: las fuentes no se han consultado recientemente.',
			'navigation.roadEvents.avoided' => ({required num n, required Object names}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Ruta calculada evitando un corte: ${names}', other: 'Ruta calculada evitando ${n} cortes: ${names}', ), 
			'navigation.roadEvents.atDistance' => ({required Object distance}) => 'a ${distance} de la salida',
			'navigation.roadEvents.more' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Y ${n} más en la ruta', other: 'Y ${n} más en la ruta', ), 
			'navigation.roadEvents.classClosure' => 'Carretera cortada',
			'navigation.roadEvents.classWorks' => 'Obras',
			'navigation.roadEvents.classLaneRestriction' => 'Carriles cortados',
			'navigation.roadEvents.classVehicleLimit' => 'Límite de dimensiones',
			'navigation.roadEvents.classDetour' => 'Desvío señalizado',
			'navigation.roadEvents.reasonUnmatched' => 'ubicación incierta, quizá en la ruta',
			'navigation.roadEvents.reasonStale' => 'fuente no consultada recientemente',
			'navigation.roadEvents.reasonOutsideHours' => 'fuera de su horario previsto',
			'navigation.roadEvents.reasonGoodsVehicles' => 'para camiones',
			'navigation.roadEvents.reasonUnconfirmed' => 'avisado por un solo viajero',
			'navigation.roadEvents.reasonAged' => 'aviso antiguo',
			'navigation.roadEvents.reasonInside' => 'la ruta empieza o termina dentro',
			'navigation.roadEvents.reasonNearLimit' => 'con poco margen',
			'navigation.roadEvents.reasonOverLimit' => 'por encima del límite de tu vehículo',
			'navigation.marks.legend' => 'Leyenda',
			'navigation.marks.legendHide' => 'Ocultar la leyenda',
			'navigation.marks.kindOrigin' => 'Salida',
			'navigation.marks.kindDestination' => 'Destino',
			'navigation.marks.kindStop' => 'Parada',
			'navigation.marks.kindClosure' => 'Carretera cortada',
			'navigation.marks.kindWorks' => 'Obras',
			'navigation.marks.kindLanes' => 'Carriles cortados',
			'navigation.marks.kindClearance' => 'Altura limitada',
			'navigation.marks.kindWeight' => 'Peso limitado',
			'navigation.marks.kindLimit' => 'Otro límite (anchura, longitud, prohibición)',
			'navigation.marks.kindFuel' => 'Gasolinera',
			'navigation.marks.kindPlace' => 'Lugar cerca de la ruta',
			'navigation.marks.groupLegend' => 'Marcadores cercanos agrupados',
			'navigation.marks.zoneLegend' => 'Zona de peligro',
			'navigation.marks.zonesFrom' => ({required Object source, required Object date}) => 'Zonas de peligro: ${source}, lista del ${date}',
			'navigation.marks.group' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} marcador', other: '${n} marcadores', ), 
			'navigation.marks.groupHint' => 'Acerca el mapa para verlos uno a uno',
			'navigation.marks.count' => ({required Object kind, required Object n}) => '${kind}: ${n}',
			'navigation.marks.stop' => ({required Object n}) => 'Parada ${n}',
			'navigation.marks.origin' => 'Punto de salida',
			'navigation.marks.nearRoute' => 'Cerca de la ruta',
			'navigation.marks.avoided' => 'La ruta lo evita',
			'navigation.marks.blocking' => 'Bloquea todas las rutas',
			'navigation.marks.showInList' => 'Ver en la lista',
			'navigation.marks.showAll' => 'Mostrar todo',
			'navigation.marks.onMap' => 'mostrar en el mapa',
			'navigation.marks.price' => ({required Object price}) => '${price} €',
			'navigation.guidance.then' => 'Luego',
			'navigation.guidance.arrival' => ({required Object time}) => 'Llegada ${time}',
			'navigation.guidance.offRoute' => 'Fuera de la ruta',
			'navigation.guidance.rerouting' => 'Buscando una ruta nueva',
			'navigation.guidance.rerouted' => 'Nueva ruta',
			'navigation.guidance.reroutedLonger' => ({required Object minutes}) => 'Nueva ruta, ${minutes} min más',
			'navigation.guidance.rerouteOffline' => 'Sin conexión para calcular otra ruta: vuelve a la ruta',
			'navigation.guidance.rerouteFailed' => 'No se ha encontrado otra ruta: vuelve a la ruta',
			'navigation.guidance.closureAhead' => ({required Object distance}) => 'Carretera cortada a ${distance}: buscando otro camino',
			'navigation.guidance.noDetour' => ({required Object distance}) => 'Carretera cortada a ${distance}: no hay otro camino',
			'navigation.guidance.eventAhead' => ({required Object distance}) => 'Obras a ${distance}',
			'navigation.guidance.eventClosure' => ({required Object distance}) => 'Carretera cortada a ${distance}',
			'navigation.guidance.eventLimit' => ({required Object distance}) => 'Paso limitado por obras a ${distance}',
			'navigation.guidance.eventSource' => ({required Object source, required Object time}) => '${source}, datos de las ${time}',
			'navigation.guidance.eventSourceOn' => ({required Object source, required Object day, required Object time}) => '${source}, datos del ${day} a las ${time}',
			'navigation.guidance.avoidedClosures' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Ruta calculada evitando un corte', other: 'Ruta calculada evitando ${n} cortes', ), 
			'navigation.guidance.roadEventAhead' => ({required Object what, required Object distance}) => '${what} a ${distance}',
			'navigation.guidance.closureOffline' => ({required Object distance}) => 'Carretera cortada a ${distance}: sin conexión para buscar otro camino',
			'navigation.guidance.closureFailed' => ({required Object distance}) => 'Carretera cortada a ${distance}: todavía no hay otro camino',
			'navigation.guidance.voiceOn' => 'Activar la voz',
			'navigation.guidance.voiceOff' => 'Silenciar la voz',
			'navigation.guidance.overview' => 'Toda la ruta',
			'navigation.guidance.recenter' => 'Recentrar',
			'navigation.guidance.end' => 'Terminar',
			'navigation.guidance.endTitle' => '¿Terminar la navegación?',
			'navigation.guidance.endConfirm' => 'Terminar',
			'navigation.guidance.endKeep' => 'Continuar',
			'navigation.guidance.stopTitle' => '¿Detener la navegación?',
			'navigation.guidance.stopConfirm' => 'Detener',
			'navigation.guidance.arrivedTitle' => 'Has llegado a tu destino',
			'navigation.guidance.done' => 'Terminar',
			'navigation.guidance.speed' => 'Velocidad',
			'navigation.guidance.limit' => 'Límite',
			'navigation.guidance.noVoice' => ({required Object language}) => 'No hay ninguna voz en ${language} en este dispositivo: instrucciones solo en pantalla.',
			'navigation.guidance.missingVoice' => ({required Object language}) => 'La voz en ${language} todavía no está descargada.',
			'navigation.guidance.installVoice' => 'Instalar',
			'navigation.guidance.voiceSettingsIos' => 'Ajustes, Accesibilidad, Contenido leído, Voces',
			'navigation.guidance.notificationTitle' => 'Lunaway te está guiando',
			'navigation.guidance.notificationText' => 'La navegación continúa con la pantalla apagada.',
			'navigation.guidance.notificationChannel' => 'Navegación',
			'navigation.guidance.unavailable' => 'No se ha podido iniciar la navegación en este dispositivo.',
			'navigation.guidance.notificationWhy.title' => 'Notificación de navegación',
			'navigation.guidance.notificationWhy.body' => 'Durante la navegación, una notificación mantiene activas la ubicación y la voz con la pantalla apagada, y al tocarla vuelves a la navegación. Android te preguntará si Lunaway puede mostrarla.',
			'navigation.guidance.notificationWhy.ask' => 'Continuar',
			'navigation.guidance.notificationWhy.later' => 'Ahora no',
			'navigation.guidance.positionLost' => 'Ubicación no disponible: comprueba que la ubicación del dispositivo está activada para Lunaway.',
			'navigation.guidance.positionStale' => ({required Object minutes}) => 'Última ubicación recibida hace ${minutes} min: la hora de llegada se basa en ella.',
			'navigation.guidance.firstTitle' => 'Antes de salir',
			'navigation.guidance.firstAccept' => 'Entendido',
			'navigation.guidance.dangerZone' => ({required Object distance}) => 'Zona de peligro a ${distance}',
			'navigation.guidance.inDangerZone' => ({required Object distance}) => 'Zona de peligro, quedan ${distance}',
			'navigation.guidance.cameraAhead' => ({required Object distance}) => 'Radar a ${distance}',
			'navigation.guidance.cameraLimit' => ({required Object distance, required Object limit}) => 'Radar a ${distance}, ${limit}',
			'navigation.guidance.limitEstimated' => 'Límite estimado',
			'navigation.guidance.overLimit' => 'por encima del límite',
			'navigation.guidance.enforcementSource' => ({required Object source, required Object date}) => '${source}, lista del ${date}',
			'navigation.guidance.demoDrive' => 'Trayecto simulado: demostración sin GPS',
			'navigation.guidance.places.button' => 'Lugares en el mapa',
			'navigation.guidance.places.buttonHidden' => 'Lugares en el mapa: ocultos',
			'navigation.guidance.places.title' => 'Lugares en el mapa',
			'navigation.guidance.places.sleep' => 'Para dormir',
			'navigation.guidance.places.fill' => 'Repostar',
			'navigation.guidance.places.groceries' => 'Para comer',
			'navigation.guidance.places.all' => 'Todo',
			'navigation.guidance.places.everyPlace' => 'Todos los lugares',
			'navigation.guidance.places.none' => 'Nada',
			'navigation.guidance.places.customize' => 'Personalizar',
			'navigation.guidance.places.look' => 'Vista',
			'navigation.guidance.places.photos' => 'Fotos',
			'navigation.guidance.places.pictograms' => 'Iconos',
			'navigation.guidance.places.dots' => 'Chinchetas',
			'navigation.guidance.places.photosHint' => 'Los lugares que más importan, en foto. Nunca sobre la carretera que tienes delante ni bajo los botones.',
			'navigation.guidance.places.pictogramsHint' => 'Los lugares que más importan, en grande, con su precio, su valoración o la pernocta.',
			'navigation.guidance.places.dotsHint' => 'Todos los lugares como pequeñas chinchetas, como en el mapa.',
			'navigation.guidance.places.free' => 'Gratis',
			'navigation.guidance.places.nightOk' => 'Pernocta',
			'navigation.voice.rerouting' => 'Recalculando la ruta.',
			'navigation.voice.rerouted' => 'Nueva ruta.',
			'navigation.voice.reroutedLonger' => ({required num minutes}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(minutes, one: 'Nueva ruta, un minuto más larga.', other: 'Nueva ruta, ${minutes} minutos más larga.', ), 
			'navigation.voice.moved.destination' => ({required Object distance}) => 'Destino desplazado ${distance} hasta la calle accesible más cercana.',
			'navigation.voice.moved.stop' => ({required Object n, required Object distance}) => 'Parada ${n} desplazada ${distance} hasta la calle accesible más cercana.',
			'navigation.voice.closureAhead' => ({required Object distance}) => 'En ${distance}, carretera cortada. Buscando otro camino.',
			'navigation.voice.noDetour' => ({required Object distance}) => 'En ${distance}, carretera cortada. No hay otro camino.',
			'navigation.voice.clearance' => ({required Object distance, required Object height}) => 'Atención, en ${distance}, altura máxima ${height}.',
			'navigation.voice.unknownClearance' => ({required Object distance}) => 'Atención, en ${distance}, paso bajo de altura desconocida.',
			'navigation.voice.narrow' => ({required Object distance, required Object width}) => 'Atención, en ${distance}, paso estrecho de ${width}.',
			'navigation.voice.limit' => ({required Object distance, required Object what}) => 'Atención, en ${distance}, ${what}.',
			'navigation.voice.arrived' => 'Ha llegado a su destino.',
			'navigation.voice.metres' => ({required Object n}) => '${n} metros',
			'navigation.voice.kilometres' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count, one: 'un kilómetro', other: '${n} kilómetros', ), 
			'navigation.voice.feet' => ({required Object n}) => '${n} pies',
			'navigation.voice.miles' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count, one: 'una milla', other: '${n} millas', ), 
			'navigation.voice.size' => ({required num count, required Object cm, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count, one: 'un metro ${cm}', other: '${metres} metros ${cm}', ), 
			'navigation.voice.sizeWhole' => ({required num count, required Object metres}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count, one: 'un metro', other: '${metres} metros', ), 
			'navigation.voice.overSpeed' => ({required Object limit}) => 'Velocidad máxima ${limit}.',
			'navigation.voice.dangerZone' => ({required Object distance}) => 'En ${distance}, zona de peligro.',
			'navigation.voice.inDangerZone' => 'Zona de peligro.',
			'navigation.voice.camera' => ({required Object distance}) => 'En ${distance}, radar.',
			'navigation.voice.localAccess.weight' => ({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit}, salvo para acceder a la zona.',
			'navigation.voice.localAccess.axleLoad' => ({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit} por eje, salvo para acceder a la zona.',
			'navigation.voice.localAccess.width' => ({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit} de ancho, salvo para acceder a la zona.',
			'navigation.voice.localAccess.length' => ({required Object distance, required Object limit}) => 'Atención, en ${distance}, prohibido a vehículos de más de ${limit} de largo, salvo para acceder a la zona.',
			'navigation.voice.tonnes' => ({required num count, required Object n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(count, one: 'una tonelada', other: '${n} toneladas', ), 
			'navigation.units.ft' => ({required Object n}) => '${n} ft',
			'navigation.units.mi' => ({required Object n}) => '${n} mi',
			'navigation.units.kmh' => 'km/h',
			'navigation.units.mph' => 'mph',
			'navigation.units.hoursMinutes' => ({required Object h, required Object m}) => '${h} h ${m} min',
			'navigation.units.minutes' => ({required Object m}) => '${m} min',
			'navigation.settings.title' => 'Navegación',
			'navigation.settings.avoidTitle' => 'Evitar por defecto',
			'navigation.settings.voice' => 'Instrucciones de voz',
			'navigation.settings.voiceHint' => 'Con la voz del dispositivo',
			'navigation.settings.units' => 'Distancias',
			'navigation.settings.metric' => 'Kilómetros',
			'navigation.settings.imperial' => 'Millas',
			'navigation.settings.speedLimit' => 'Límite de velocidad',
			'navigation.settings.speedLimitHint' => 'El límite para tu vehículo junto a la velocidad durante la navegación; si es una estimación, aparece en gris.',
			'navigation.settings.speedSound' => 'Avisos de velocidad por voz',
			'navigation.settings.speedSoundHint' => 'Un aviso cuando superas el límite, y antes de una zona de peligro donde el país lo permite. Desactivado: solo la señal y los avisos en pantalla.',
			'list.title' => 'Lugares cercanos',
			'list.empty' => 'No hay lugares por aquí con estos filtros',
			'list.emptyHint' => 'Mueve el mapa, aléjalo o quita algún filtro.',
			'list.downloading' => 'Los lugares están llegando',
			'list.downloadingHint' => 'La lista se va llenando durante la descarga.',
			'list.error' => 'No se ha podido cargar la lista.',
			'list.offline' => 'Sin conexión: la lista necesita conexión.',
			'list.moreFailed' => 'No se han podido cargar más lugares. Reintentar',
			'list.sortDistance' => 'Distancia',
			'list.sortRating' => 'Valoración',
			'list.sortNewest' => 'Añadidos recientemente',
			'list.sortedBy' => ({required Object sort}) => 'Lista ordenada por: ${sort}',
			'list.rankedAmongNearestYou' => ({required Object n}) => 'Ordenados entre los ${n} lugares más cercanos a ti',
			'list.rankedAmongNearestCentre' => ({required Object n}) => 'Ordenados entre los ${n} lugares más cercanos al centro del mapa',
			'list.offlineTitle' => 'Sin conexión',
			'list.offlineNotHere' => 'Nada de esta zona en este dispositivo.',
			'favorites.title' => 'Favoritos',
			'favorites.defaultList' => 'Mis favoritos',
			'favorites.empty' => 'Todavía no hay nada guardado aquí',
			'favorites.emptyHint' => 'Toca Guardar en un lugar para conservarlo, incluso sin conexión.',
			'favorites.newList' => 'Nueva lista',
			'favorites.listName' => 'Nombre de la lista',
			'favorites.renameList' => 'Cambiar el nombre de la lista',
			'favorites.deleteList' => 'Eliminar la lista',
			'favorites.deleteListConfirm' => ({required Object name}) => '¿Eliminar «${name}»? Los lugares siguen en el mapa.',
			'favorites.listActions' => 'Opciones de la lista',
			'favorites.placeActions' => 'Opciones del lugar',
			'favorites.openOnMap' => 'Ver en el mapa',
			'favorites.remove' => 'Quitar de la lista',
			'favorites.removed' => 'Quitado de la lista',
			'favorites.count' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, zero: 'Vacía', one: '${n} lugar', other: '${n} lugares', ), 
			'favorites.error' => 'No se han podido cargar tus favoritos.',
			'vehicle.title' => 'Mi vehículo',
			'vehicle.why' => 'Las dimensiones de tu vehículo sirven para ocultar los lugares a los que no puede acceder. Se envían con cada solicitud de ruta y no se guardan.',
			'vehicle.none' => 'Describe tu vehículo para ocultar los lugares a los que no puede acceder.',
			'vehicle.add' => 'Describir mi vehículo',
			'vehicle.edit' => 'Editar',
			'vehicle.type' => 'Tipo',
			'vehicle.types.van' => 'Van',
			'vehicle.types.campervan' => 'Furgoneta camper',
			'vehicle.types.lowProfile' => 'Perfilada',
			'vehicle.types.overcab' => 'Capuchina',
			'vehicle.types.integrated' => 'Integral',
			'vehicle.towingTitle' => 'Remolque',
			'vehicle.towing.none' => 'Sin remolque',
			'vehicle.towing.car' => 'Un coche',
			'vehicle.towing.trailer' => 'Un remolque',
			'vehicle.size' => 'Dimensiones',
			'vehicle.sizeHint' => 'Valores habituales del tipo elegido: corrígelos con los de la ficha técnica de tu vehículo.',
			'vehicle.height' => 'Altura',
			'vehicle.width' => 'Anchura',
			'vehicle.length' => 'Longitud total, remolque incluido',
			'vehicle.weight' => 'Masa máxima autorizada (MMA)',
			'vehicle.heightShort' => ({required Object value}) => 'Alto ${value}',
			'vehicle.widthShort' => ({required Object value}) => 'Ancho ${value}',
			'vehicle.lengthShort' => ({required Object value}) => 'Largo ${value}',
			'vehicle.notANumber' => 'Un número, por ejemplo 2,90',
			'vehicle.outOfRange' => ({required Object min, required Object max, required Object unit}) => 'Entre ${min} y ${max} ${unit}',
			'vehicle.navigationLater' => 'La navegación de Lunaway tiene en cuenta todas estas dimensiones.',
			'vehicle.save' => 'Guardar',
			'vehicle.clear' => 'Borrar',
			'vehicle.fuelTitle' => 'Combustible',
			'vehicle.fuelHint' => 'El precio de tu combustible aparece en las gasolineras del mapa, empezando por las más baratas.',
			'vehicle.consumption' => 'Consumo',
			'vehicle.consumptionUnit' => 'l/100 km',
			'vehicle.lpgHeating' => 'Calefacción de GLP',
			'vehicle.lpgHeatingHint' => 'El precio del GLP también aparece en las gasolineras.',
			'vehicle.cruiseTitle' => 'Velocidad máxima de crucero',
			'vehicle.cruiseHint' => 'Los tiempos de trayecto suponen que nunca vas más rápido, aunque la carretera lo permita. Los límites de velocidad que se anuncian durante la navegación siguen siendo los de la carretera.',
			'vehicle.cruiseNone' => 'Sin límite',
			'vehicleHeight.title' => 'Altura de tu vehículo',
			'vehicleHeight.why' => 'Se ocultarán los lugares con un límite de altura más bajo. Los lugares sin altura conocida siguen en el mapa.',
			'vehicleHeight.needed' => 'Indica la altura, por ejemplo 2,90',
			'vehicleHeight.weightOptional' => 'Masa máxima autorizada (opcional)',
			'vehicleHeight.apply' => 'Filtrar con esta altura',
			'vehicleHeight.later' => 'El resto del vehículo se describe en Perfil, Mi vehículo.',
			'profile.title' => 'Perfil',
			'profile.noAccountNeeded' => 'Sin cuenta, sin publicidad, sin rastreadores. Tus favoritos se quedan en este dispositivo.',
			'profile.language' => 'Idioma',
			'profile.languageSystem' => 'Igual que el dispositivo',
			'profile.appearance' => 'Apariencia',
			'profile.themeAuto' => 'Automático',
			'profile.themeLight' => 'Claro',
			'profile.themeDark' => 'Oscuro',
			'profile.themeAutoHint' => 'Claro de día, oscuro tras la puesta de sol donde estés.',
			'profile.themeLightHint' => 'Siempre claro, de día y de noche.',
			'profile.themeDarkHint' => 'Siempre oscuro, más cómodo para la vista de noche.',
			'profile.offline' => 'Sin conexión',
			'profile.placesOnDevice' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'lugar en este dispositivo', other: 'lugares en este dispositivo', ), 
			'profile.offlineSize' => ({required Object size}) => 'Espacio usado: ${size}',
			'profile.lastSync' => ({required Object when}) => 'Última actualización ${when}',
			'profile.neverSynced' => 'Nunca descargado',
			'profile.syncNow' => 'Actualizar ahora',
			'profile.syncing' => 'Actualizando',
			'profile.about' => 'Acerca de',
			'profile.version' => ({required Object version}) => 'Versión ${version}',
			'profile.website' => 'Sitio web',
			'profile.privacy' => 'Política de privacidad',
			'profile.sourceCode' => 'Código fuente',
			'profile.licences' => 'Licencias',
			'profile.appLicence' => 'Lunaway es software libre bajo licencia GNU AGPL 3.0 o posterior.',
			'profile.attributions' => 'Fuentes y créditos',
			'profile.attributionOsm' => 'Lugares y datos cartográficos © colaboradores de OpenStreetMap.',
			'profile.attributionOdbl' => 'Datos de OpenStreetMap bajo licencia Open Database License (ODbL).',
			'profile.attributionAtout' => 'Campings clasificados de Atout France, bajo Licence Ouverte 2.0 (Etalab).',
			'profile.attributionCommunes' => 'Municipios de los lugares: Contours administratifs, data.gouv.fr (IGN Admin Express, OpenStreetMap), bajo licencia ODbL.',
			'profile.attributionTiles' => 'Mapa base servido por Lunaway, estilos derivados de Protomaps (BSD-3-Clause), datos © colaboradores de OpenStreetMap.',
			'profile.attributionFonts' => 'Tipografías Fraunces y Atkinson Hyperlegible Next, bajo licencia SIL Open Font License 1.1.',
			'profile.attributionIcons' => 'Iconos Phosphor, bajo licencia MIT.',
			'profile.noTracking' => 'Sin publicidad ni rastreadores. Tu cuenta no guarda ni tu correo electrónico ni tu número de teléfono.',
			'profile.attributionBdTopo' => 'Límites de altura, anchura, longitud y peso de las carreteras, y campings situados por su nombre: BD TOPO del IGN, a través de la Géoplateforme, bajo Licence Ouverte 2.0.',
			'profile.attributionAddresses' => 'Direcciones de la búsqueda en Francia: Base Adresse Nationale, a través de la Géoplateforme del IGN, bajo Licence Ouverte 2.0.',
			'profile.attributionAddressesOsm' => 'Direcciones de la búsqueda en otros países: OpenStreetMap, a través de Photon, bajo ODbL.',
			'profile.attributionPoiOdbl' => 'Comercios y servicios: OpenStreetMap y el calendario de apertura de La Poste, bajo ODbL.',
			'profile.attributionPoiLo' => 'Precios de los combustibles (Ministerio de Economía de Francia) y centros sanitarios FINESS, bajo Licence Ouverte 2.0 (Etalab).',
			'profile.attributionPacks' => 'Contornos de los mapas sin conexión: Contours administratifs, data.gouv.fr (ODbL), y Natural Earth (dominio público).',
			'profile.attributionOfflineLabels' => 'Nombres e iconos de los mapas sin conexión: glifos Noto Sans (SIL Open Font License 1.1) y sprites de Protomaps derivados de tangrams/icons (MIT).',
			'profile.attributionExtcom' => 'Lugares, reseñas, valoraciones y fotos, bajo acuerdo escrito con esta fuente.',
			'profile.creditsPlaces' => 'Lugares',
			'profile.creditsContent' => 'Fotos, textos y reseñas',
			'profile.creditsRoutes' => 'Rutas y navegación',
			'profile.creditsSearch' => 'Búsqueda',
			'profile.creditsMap' => 'Mapa base',
			'profile.creditsApp' => 'Aplicación',
			'profile.attributionDatatourisme' => 'Lugares, descripciones y fotos de las oficinas de turismo: DATAtourisme, bajo Licence Ouverte 2.0; cada texto y cada foto indica su oficina, su autor y la fecha de su última actualización.',
			'profile.attributionCommunity' => 'Reseñas, valoraciones y fotos de los viajeros de Lunaway, bajo licencia CC BY 4.0, con el seudónimo de su autor.',
			'profile.attributionCommons' => 'Fotos de Wikimedia Commons, cada una bajo su propia licencia (CC0, CC BY o CC BY-SA), con su autor y un enlace a su página.',
			'profile.attributionPanoramax' => 'Vistas de la calle de Panoramax: instancia de OpenStreetMap France bajo licencia CC BY-SA 4.0, instancia del IGN bajo Licence Ouverte 2.0.',
			'profile.attributionWikipedia' => 'Extractos de artículos de Wikipedia, bajo licencia CC BY-SA 4.0, con un enlace al artículo.',
			'profile.attributionMangrove' => 'Reseñas de Mangrove Reviews, bajo licencia CC BY 4.0 o la licencia que indique la reseña, con un enlace a la reseña.',
			'profile.attributionRoadEvents' => 'Obras y cortes en Francia: DIR y Bison Futé, resoluciones de tráfico DiaLog (DGITM), metrópolis y departamentos (Lyon, Toulouse, Burdeos, Aix-Marseille-Provence, Charente-Maritime, Mayenne, Côtes-d\'Armor, Sarthe), bajo Licence Ouverte 2.0; Rennes Métropole y los avisos de los viajeros de Lunaway, bajo ODbL.',
			'profile.attributionRoadEventsAbroad' => 'Obras y cortes en los Países Bajos: NDW, Nationaal Dataportaal Wegverkeer (datos abiertos); en España: DGT, Dirección General de Tráfico (CC BY).',
			'profile.attributionDangerZones' => 'Zonas de peligro: listas oficiales de radares (Sécurité routière en Francia, reutilizada conforme al Code des relations entre le public et l\'administration francés; Polonia y Luxemburgo, CC0; Cataluña, licencia abierta de la Generalitat; Noruega, NLOD) y OpenStreetMap (ODbL).',
			'units.kilobytes' => ({required Object n}) => '${n} kB',
			'units.megabytes' => ({required Object n}) => '${n} MB',
			'languages.fr' => 'francés',
			'languages.en' => 'inglés',
			'languages.de' => 'alemán',
			'languages.es' => 'español',
			'languages.it' => 'italiano',
			'languages.nl' => 'neerlandés',
			'translation.translate' => 'Traducir',
			'translation.translating' => 'Traduciendo',
			'translation.showOriginal' => 'Ver el original',
			'translation.showTranslation' => 'Ver la traducción',
			'translation.from.fr' => 'Traducido automáticamente del francés',
			'translation.from.en' => 'Traducido automáticamente del inglés',
			'translation.from.de' => 'Traducido automáticamente del alemán',
			'translation.from.es' => 'Traducido automáticamente del español',
			'translation.from.it' => 'Traducido automáticamente del italiano',
			'translation.from.nl' => 'Traducido automáticamente del neerlandés',
			'translation.from.unknown' => ({required Object language}) => 'Traducido automáticamente (idioma original: ${language})',
			'translation.offline' => 'Para traducir hace falta conexión a internet.',
			'translation.failedOffline' => 'Sin conexión: no se ha podido traducir el texto.',
			'translation.busy' => 'El servicio de traducción está saturado. Vuelve a intentarlo más tarde.',
			'translation.unavailable' => 'La traducción no está disponible en este momento.',
			'translation.gone' => 'Este texto ya no está disponible.',
			'translation.unsupported' => 'No hay traducción disponible para este idioma.',
			'translation.autoReviews' => 'Traducir las reseñas automáticamente',
			'translation.autoReviewsHint' => 'Las reseñas escritas en otro idioma se traducen en el propio servidor de Lunaway, sin pasar por servicios de terceros.',
			'locale.en' => 'English',
			'locale.fr' => 'Français',
			'locale.de' => 'Deutsch',
			'locale.es' => 'Español',
			'locale.it' => 'Italiano',
			'locale.nl' => 'Nederlands',
			'account.title' => 'Tu cuenta',
			'account.noneTitle' => 'Todavía no tienes cuenta',
			'account.noneBody' => 'El mapa, la búsqueda y los favoritos funcionan sin cuenta. La cuenta se crea sola con tu primera contribución (una valoración, una confirmación, una foto), sin correo electrónico ni contraseña. A partir de ese momento, tus listas de favoritos quedan vinculadas a ella.',
			'account.recover' => 'Recuperar mi cuenta',
			'account.memberSince' => ({required Object date}) => 'Miembro desde ${date}',
			'account.editPseudonym' => 'Cambiar el seudónimo',
			'account.pseudonymTitle' => 'Tu seudónimo',
			'account.pseudonymHint' => 'Público: acompaña a tus reseñas y fotos. De 3 a 32 caracteres.',
			'account.pseudonymInvalid' => 'De 3 a 32 caracteres, con al menos dos letras.',
			'account.pseudonymRefused' => 'Este seudónimo no se acepta: ni enlaces, ni datos de contacto, ni insultos, ni nombres que se hagan pasar por el equipo de Lunaway.',
			'account.pseudonymSaved' => 'Seudónimo guardado',
			'account.level' => ({required Object level}) => 'Nivel de confianza ${level}',
			'account.levelOpens.l0' => 'Puedes valorar lugares, confirmar que siguen ahí, avisar de un problema y sincronizar tus favoritos.',
			'account.levelOpens.l1' => 'También puedes escribir reseñas, añadir fotos y proponer cambios en los lugares.',
			'account.levelOpens.l2' => 'También puedes añadir lugares.',
			'account.levelOpens.l3' => 'Tus cambios en los lugares se aplican sin revisión.',
			'account.levelOpens.l4' => 'Participas en la moderación.',
			'account.nextLevel' => ({required Object level}) => 'Para el nivel ${level}',
			'account.levelTop' => 'Estás en el nivel más alto.',
			'account.requirement.age' => ({required Object needed, required Object current}) => 'Una cuenta con al menos ${needed} días (${current} por ahora)',
			'account.requirement.confirmations' => ({required Object needed, required Object current}) => '${needed} confirmaciones de lugares distintos (${current} por ahora)',
			'account.requirement.contributions' => ({required Object needed, required Object current}) => '${needed} contribuciones publicadas (${current} por ahora)',
			'account.requirement.activeDays' => ({required Object needed, required Object current}) => '${needed} días de actividad (${current} por ahora)',
			'account.requirement.noRemoval' => 'Ninguna contribución retirada por la moderación',
			'account.requirement.sponsor' => 'El apadrinamiento de un miembro de nivel 2',
			'account.requirement.nomination' => 'Un nombramiento por parte de la moderación',
			'account.requirement.administration' => 'Una designación por parte del equipo de Lunaway',
			'account.orInstead' => ({required Object requirement}) => 'O bien ${requirement}',
			'account.recoveryNone' => 'No se ha creado ninguna tarjeta de recuperación en este dispositivo. Sin ella, esta cuenta solo existe en este dispositivo: si lo pierdes, pierdes también la cuenta.',
			'account.recoveryNoneAccount' => 'Esta cuenta todavía no tiene tarjeta de recuperación. Sin ella, esta cuenta solo existe en este dispositivo: si lo pierdes, pierdes también la cuenta.',
			'account.recoveryCreate' => 'Crear mi tarjeta de recuperación',
			'account.recoveryMade' => ({required Object date}) => 'Creada el ${date}',
			'account.recoveryRemake' => 'Rehacer',
			'account.recoveryRemakeHint' => 'Crear una nueva tarjeta de recuperación',
			'account.contributions' => 'Mis contribuciones',
			'account.pending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} contribución pendiente de envío', other: '${n} contribuciones pendientes de envío', ), 
			'account.mutedAuthors' => 'Autores ocultos',
			'account.devices' => 'Dispositivos',
			'account.signOut' => 'Cerrar sesión',
			'account.delete' => 'Eliminar mi cuenta',
			'account.signOutTitle' => '¿Cerrar sesión en este dispositivo?',
			'account.signOutBody' => 'La clave de la cuenta se borra de este dispositivo. Para volver, necesitarás tu tarjeta de recuperación. Tus favoritos se quedan aquí.',
			'account.signOutNoCard' => 'No has creado ninguna tarjeta de recuperación en este dispositivo. Sin ella, esta cuenta se perderá para siempre.',
			'account.signOutPending' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Una contribución pendiente no se enviará.', other: '${n} contribuciones pendientes no se enviarán.', ), 
			'account.signedOut' => 'Sesión cerrada. Tus favoritos se quedan en este dispositivo.',
			'account.lost' => 'Esta cuenta ya no se abre en este dispositivo. Recupérala con tu tarjeta de recuperación: Perfil, Recuperar mi cuenta.',
			'account.lostAction' => 'Recuperar',
			'account.welcomeTitle' => 'Gracias por tu primera contribución',
			'account.welcomeBody' => ({required Object name}) => 'Tu cuenta está creada, con el seudónimo «${name}». Sin correo electrónico ni contraseña: una clave guardada en este dispositivo. Puedes cambiar el seudónimo en tu perfil.',
			'account.welcomeCard' => 'Crea tu tarjeta de recuperación para recuperar esta cuenta en otro dispositivo.',
			'account.welcomeFavorites' => 'Tus listas de favoritos ahora se guardan con tu cuenta.',
			'recovery.title' => 'Tarjeta de recuperación',
			'recovery.intro' => 'Un código que lleva tu cuenta a un dispositivo nuevo. Lunaway solo guarda una huella del código, suficiente para comprobarlo: el código en sí no se puede volver a mostrar nunca, y cada tarjeta nueva tiene un código distinto.',
			'recovery.replaces' => 'Una tarjeta nueva sustituye a la anterior: el código antiguo dejará de funcionar.',
			'recovery.replaceTitle' => ({required Object date}) => '¿Sustituir la tarjeta del ${date}?',
			'recovery.replaceBody' => ({required Object date}) => 'La tarjeta nueva tendrá otro código. El de la tarjeta del ${date} deja de funcionar ahora mismo. No se puede volver a mostrar: Lunaway solo guarda una huella.',
			'recovery.replaceKeep' => 'Conservar la antigua',
			'recovery.replaceConfirm' => 'Crear una tarjeta nueva',
			'recovery.make' => 'Crear la tarjeta',
			'recovery.codeLabel' => 'Tu código de recuperación',
			'recovery.shownOnce' => 'Este código solo se muestra una vez. Anótalo, o guarda la imagen, antes de cerrar.',
			'recovery.saveImage' => 'Guardar la imagen',
			'recovery.done' => 'He anotado el código',
			'recovery.doneTitle' => '¿Has guardado el código?',
			'recovery.doneBody' => 'Cuando cierres esta página, no volverá a mostrarse.',
			'recovery.keep' => 'Seguir en la página',
			'recovery.cardHeading' => 'Tarjeta de recuperación de Lunaway',
			'recovery.cardAccount' => ({required Object name}) => 'Cuenta: ${name}',
			'recovery.cardHow' => 'Para recuperar la cuenta: Perfil, Recuperar mi cuenta, y luego escribe este código o fotografía la tarjeta.',
			'recovery.cardMade' => ({required Object date}) => 'Creada el ${date}',
			'recovery.cardWarning' => 'Este código da acceso a tu cuenta: no se lo des a nadie.',
			'recovery.failed' => 'No se ha podido crear la tarjeta. Se necesita conexión.',
			'recovery.fileName' => 'tarjeta-de-recuperacion-lunaway',
			'recovery.step1' => 'Crea la tarjeta: el código solo se muestra una vez.',
			'recovery.step2' => 'Guarda la imagen, imprímela o copia el código a mano.',
			'recovery.step3' => 'Guárdala en la guantera, con la documentación del vehículo.',
			'recover.title' => 'Recuperar mi cuenta',
			'recover.intro' => 'Escribe el código de tu tarjeta de recuperación o escanéalo desde una foto de la tarjeta.',
			'recover.field' => 'Código de recuperación',
			'recover.fieldHint' => '27 caracteres, en grupos de cuatro',
			'recover.remaining' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Falta ${n} carácter', other: 'Faltan ${n} caracteres', ), 
			'recover.invalid' => 'Este código no corresponde a ninguna tarjeta: comprueba cada carácter.',
			'recover.valid' => 'Código completo',
			'recover.scan' => 'Escanear la tarjeta desde una foto',
			'recover.scanFile' => 'Elegir la imagen de la tarjeta',
			'recover.reading' => 'Leyendo la tarjeta',
			'recover.scanFailed' => 'No hay ningún código legible en esta imagen. Prueba con una foto más nítida, con la tarjeta bien plana.',
			'recover.revoke' => 'Mi antiguo dispositivo se ha perdido o me lo han robado: cerrar su sesión',
			'recover.revokeHint' => 'Se cerrará la sesión en todos tus demás dispositivos.',
			'recover.submit' => 'Recuperar la cuenta',
			'recover.notFound' => 'Ninguna cuenta tiene este código. Comprueba la tarjeta o crea una nueva desde un dispositivo con la sesión iniciada.',
			'recover.tooMany' => 'Demasiados intentos por ahora. Vuelve a intentarlo dentro de una hora.',
			'recover.done' => ({required Object name}) => 'Cuenta recuperada: ${name}',
			'deletion.title' => 'Eliminar mi cuenta',
			'deletion.intro' => 'La eliminación es inmediata y definitiva.',
			'deletion.goneTitle' => 'Lo que se elimina',
			'deletion.gone.identity' => 'Tu seudónimo y las claves de tus dispositivos',
			'deletion.gone.sessions' => 'Tus sesiones y tu código de recuperación',
			'deletion.gone.lists' => 'Tus listas de favoritos sincronizadas y tus autores ocultos',
			'deletion.gone.photos' => 'Tus fotos, tus valoraciones sin texto y tus avisos',
			'deletion.gone.pending' => 'Tus propuestas pendientes de revisión',
			'deletion.keptTitle' => 'Lo que se conserva, sin tu nombre',
			'deletion.kept' => 'Tus reseñas escritas publicadas, tus confirmaciones y tus cambios de lugares ya aplicados se conservan, sin autor: forman parte del mapa de otros viajeros.',
			'deletion.backups' => 'Las copias de seguridad del servidor se borran en unos 30 días.',
			'deletion.device' => 'En este dispositivo, tus favoritos se quedan; la clave de la cuenta se borra.',
			'deletion.web' => 'También puedes eliminarla en lunaway.net con tu código de recuperación.',
			'deletion.webLink' => 'lunaway.net/account/delete',
			'deletion.confirmTitle' => '¿Eliminar definitivamente?',
			_ => null,
		} ?? switch (path) {
			'deletion.confirmBody' => ({required Object name}) => 'La cuenta «${name}» y todo lo indicado se eliminan ahora. Nadie podrá recuperarla.',
			'deletion.confirmCheck' => 'Entiendo que es definitivo',
			'deletion.confirm' => 'Eliminar la cuenta',
			'deletion.done' => 'Cuenta eliminada',
			'deletion.failed' => 'No se ha podido eliminar la cuenta. Se necesita conexión.',
			'devices.title' => 'Dispositivos',
			'devices.intro' => 'Cada dispositivo tiene su propia clave. Quita un dispositivo perdido o uno que ya no uses.',
			'devices.thisDevice' => 'Este dispositivo',
			'devices.other' => 'Otro dispositivo',
			'devices.added' => ({required Object date}) => 'Añadido el ${date}',
			'devices.lastUsed' => ({required Object when}) => 'Último uso ${when}',
			'devices.revoke' => 'Quitar',
			'devices.revokeTitle' => '¿Quitar este dispositivo?',
			'devices.revokeBody' => 'Se cerrará su sesión y ya no podrá usar la cuenta.',
			'devices.revoked' => 'Dispositivo quitado',
			'devices.signOutOthers' => 'Cerrar sesión en todos los demás dispositivos',
			'devices.signedOutOthers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, zero: 'No hay ninguna otra sesión abierta', one: '${n} sesión cerrada', other: '${n} sesiones cerradas', ), 
			'devices.error' => 'No se han podido cargar los dispositivos. Se necesita conexión.',
			'muted.title' => 'Autores ocultos',
			'muted.empty' => 'No hay nadie oculto',
			'muted.emptyHint' => 'Para ocultar a alguien, abre el menú de una de sus reseñas o fotos. Solo se oculta para ti.',
			'muted.unmute' => 'Volver a mostrar',
			'muted.unmuted' => ({required Object name}) => 'Las contribuciones de ${name} volverán a mostrarse',
			'mine.title' => 'Mis contribuciones',
			'mine.pending' => 'Pendientes de envío',
			'mine.pendingHint' => 'Se enviarán en cuanto vuelva la conexión.',
			'mine.sendNow' => 'Enviar ahora',
			'mine.retry' => 'Reintentar',
			'mine.discard' => 'Descartar',
			'mine.discardTitle' => '¿Descartar esta contribución?',
			'mine.discardBody' => 'No se enviará.',
			'mine.reviews' => 'Reseñas y valoraciones',
			'mine.photos' => 'Fotos',
			'mine.confirmations' => 'Confirmaciones',
			'mine.issues' => 'Avisos de problemas',
			'mine.places' => 'Lugares añadidos y cambios',
			'mine.empty' => 'Nada por ahora',
			'mine.emptyHint' => 'Valorar un lugar o confirmar que sigue ahí ya cuenta como contribución.',
			'mine.latest' => ({required Object shown, required Object total}) => 'Las ${shown} más recientes de ${total}',
			'mine.error' => 'No se han podido cargar tus contribuciones. Se necesita conexión.',
			'mine.deleteTitle' => '¿Eliminar esta contribución?',
			'mine.deleteBody' => 'Se borrará de Lunaway.',
			'mine.deleteApplied' => 'Este lugar ya forma parte del mapa: se queda en él, sin tu nombre.',
			'mine.deleted' => 'Contribución eliminada',
			'mine.ratingOnly' => 'Solo valoración',
			'mine.status.published' => 'Publicada',
			'mine.status.pending' => 'En revisión',
			'mine.status.hidden' => 'Oculta tras varias denuncias',
			'mine.status.removed' => 'Retirada por la moderación',
			'mine.submission.proposed' => 'Pendiente de revisión',
			'mine.submission.accepted' => 'Aceptado',
			'mine.submission.applied' => 'En el mapa',
			'mine.submission.rejected' => 'Rechazado',
			'mine.submission.withdrawn' => 'Retirado',
			'mine.newPlace' => 'Nuevo lugar',
			'mine.edit' => 'Cambio',
			'mine.aPlace' => 'Un lugar',
			'mine.newVendingMachine' => 'Nueva máquina expendedora',
			'mine.poiConfirmations' => 'Comercios y servicios confirmados',
			'mine.aPoi' => 'Un comercio o servicio',
			'outbox.kind.rate' => ({required Object stars}) => 'Valoración de ${stars} sobre 5',
			'outbox.kind.review' => 'Reseña',
			'outbox.kind.deleteReview' => 'Eliminación de una reseña',
			'outbox.kind.confirm' => ({required Object status}) => 'Confirmación: ${status}',
			'outbox.kind.deleteConfirmation' => 'Eliminación de una confirmación',
			'outbox.kind.reportIssue' => ({required Object kind}) => 'Aviso de problema: ${kind}',
			'outbox.kind.deleteIssueReport' => 'Eliminación de un aviso',
			'outbox.kind.reportContent' => 'Denuncia a la moderación',
			'outbox.kind.addPlace' => ({required Object name}) => 'Nuevo lugar: ${name}',
			'outbox.kind.editPlace' => 'Cambio en un lugar',
			'outbox.kind.deletePlaceSubmission' => 'Retirada de un lugar propuesto',
			'outbox.kind.photo' => 'Foto',
			'outbox.kind.deletePhoto' => 'Eliminación de una foto',
			'outbox.kind.mute' => 'Ocultar a un autor',
			'outbox.kind.unmute' => 'Volver a mostrar a un autor',
			'outbox.kind.poiThere' => 'Sigue ahí: un comercio o servicio',
			'outbox.kind.poiGone' => 'Ya no está: un comercio o servicio',
			'outbox.kind.addVendingMachine' => 'Nueva máquina expendedora',
			'outbox.kind.deletePoiConfirmation' => 'Eliminación de una respuesta sobre un comercio o servicio',
			'outbox.kind.reportRoadEvent' => ({required Object kind}) => 'Aviso en carretera: ${kind}',
			'outbox.kind.clearRoadEvent' => 'Fin de un aviso en carretera',
			'outbox.waiting' => 'Esperando conexión',
			'outbox.sending' => 'Enviando',
			'outbox.error.forbidden' => 'Rechazado: tu nivel todavía no lo permite.',
			'outbox.error.notFound' => 'Rechazado: el lugar o el contenido ya no existe.',
			'outbox.error.invalid' => 'Rechazado: revisa el texto (longitud, enlaces, datos de contacto).',
			'outbox.error.unreadablePhoto' => 'Foto rechazada: ilegible o ya enviada.',
			'outbox.error.photoTooLarge' => 'Foto rechazada: demasiado pesada.',
			'outbox.error.placeRefused' => 'Se ha rechazado el nuevo lugar de esta foto.',
			'outbox.error.fileLost' => 'La foto ya no está en el dispositivo.',
			'outbox.error.otherAccount' => 'Preparada para otra cuenta: no se enviará.',
			'outbox.error.other' => 'Rechazado por el servidor.',
			'outbox.error.duplicate' => 'Rechazado: la misma máquina ya figura a menos de 25 m.',
			'outbox.sent' => 'Gracias, ya se ha enviado',
			'outbox.queued' => 'Sin conexión: se enviará cuando vuelva la conexión',
			'outbox.refused' => ({required Object reason}) => 'No enviado. ${reason}',
			'placement.title' => 'Sitúa el lugar',
			'placement.hint' => 'Mueve el mapa: la cruz marca el punto exacto.',
			'placement.confirm' => 'Confirmar este punto',
			'placement.duplicate' => ({required Object name, required Object distance}) => 'Ya hay «${name}» a ${distance}: ¿es el mismo sitio?',
			'placement.same' => 'Sí, abrir su ficha',
			'placement.notSame' => 'No, es otro lugar',
			'contribute.yourRating' => 'Tu valoración',
			'contribute.rateHint' => 'Toca una estrella para valorar',
			'contribute.rateStar' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Valorar con ${n} estrella', other: 'Valorar con ${n} estrellas', ), 
			'contribute.writeReview' => 'Escribir una reseña',
			'contribute.editReview' => 'Modificar tu reseña',
			'contribute.deleteReview' => 'Eliminar tu reseña',
			'contribute.deleteReviewTitle' => '¿Eliminar tu reseña?',
			'contribute.deleteReviewBody' => 'El texto y la valoración desaparecen de la ficha.',
			'contribute.deleteRating' => 'Quitar tu valoración',
			'contribute.deleteRatingTitle' => '¿Quitar tu valoración?',
			'contribute.deleteRatingBody' => 'Tu valoración desaparece de la ficha del lugar.',
			'contribute.pendingSend' => 'Pendiente de envío',
			'contribute.statusPending' => 'En revisión: por ahora solo la ves tú',
			'contribute.statusHidden' => 'Oculta tras varias denuncias, a la espera de un moderador',
			'contribute.statusRemoved' => 'Retirada por la moderación',
			'contribute.addPhoto' => 'Añadir una foto',
			'contribute.firstPhoto' => 'Añadir la primera foto',
			'contribute.stillThere' => '¿Sigue ahí?',
			'contribute.more' => 'Más acciones',
			'contribute.reportIssue' => 'Avisar de un problema',
			'contribute.proposeEdit' => 'Proponer un cambio',
			'contribute.editPlace' => 'Modificar el lugar',
			'contribute.reportPlace' => 'Denunciar este lugar a la moderación',
			'contribute.toVerifyTitle' => 'Por verificar',
			'contribute.toVerifyBody' => 'Añadido por la comunidad, a la espera de dos confirmaciones. ¿Lo conoces? Confírmalo.',
			'contribute.issuesTitle' => 'Avisos de los últimos 30 días',
			'contribute.issueCount' => ({required Object kind, required Object count}) => '${kind} (${count})',
			'contribute.addPlaceHere' => 'Añadir un lugar aquí',
			'contribute.addPlaceHint' => 'En el punto marcado por la cruz.',
			'confirmSheet.title' => '¿Sigue ahí?',
			'confirmSheet.body' => '¿Has estado allí hace poco? Tu respuesta indica a los próximos viajeros que la ficha está al día. No se envía ninguna ubicación.',
			'confirmSheet.stillOk' => 'Sí, como se describe',
			'confirmSheet.closed' => 'Cerrado',
			'confirmSheet.changed' => 'Ha cambiado',
			'confirmSheet.closedHint' => 'Ya no acoge a viajeros',
			'confirmSheet.changedHint' => 'Sigue existiendo, pero algo ha cambiado',
			'confirmSheet.note' => '¿Algo que añadir? (opcional)',
			'confirmSheet.noteHint' => 'Por ejemplo: han puesto una barra de gálibo, han movido el punto de servicio',
			'confirmSheet.status.stillOk' => 'sigue ahí',
			'confirmSheet.status.closed' => 'cerrado',
			'confirmSheet.status.changed' => 'ha cambiado',
			'issueSheet.title' => 'Avisar de un problema',
			'issueSheet.body' => 'Tu aviso se suma a la advertencia que aparece en la ficha. Tu comentario solo llega a los moderadores.',
			'issueSheet.kind.nightBan' => 'Pernocta prohibida ahora',
			'issueSheet.kind.serviceBroken' => 'Servicio averiado',
			'issueSheet.kind.noAccess' => 'Sin acceso',
			'issueSheet.kind.danger' => 'Peligro',
			'issueSheet.hint.nightBan' => 'Una señal, un bando municipal, la visita de la policía',
			'issueSheet.hint.serviceBroken' => 'Punto de servicio, agua, vaciado o electricidad fuera de servicio',
			'issueSheet.hint.noAccess' => 'Una barrera, obras, una carretera cortada',
			'issueSheet.hint.danger' => 'Robo, agresión, terreno inestable',
			'issueSheet.note' => '¿Algo que añadir? (opcional)',
			'issueSheet.send' => 'Avisar',
			'reportSheet.review' => 'Denunciar esta reseña',
			'reportSheet.photo' => 'Denunciar esta foto',
			'reportSheet.place' => 'Denunciar este lugar',
			'reportSheet.body' => 'Los moderadores lo leerán. El autor no sabrá quién lo ha denunciado.',
			'reportSheet.reason.spam' => 'Publicidad o repetición',
			'reportSheet.reason.offensive' => 'Insultos, odio o contenido impactante',
			'reportSheet.reason.wrong' => 'Falso o engañoso',
			'reportSheet.reason.privacy' => 'Muestra o nombra a una persona, una matrícula o una dirección privada',
			'reportSheet.reason.other' => 'Otro motivo',
			'reportSheet.note' => 'Cuéntanos más (opcional)',
			'reportSheet.noteOther' => 'Explica qué falla',
			'reportSheet.sent' => 'Gracias, los moderadores lo revisarán',
			'reportSheet.mute' => ({required Object name}) => 'Ocultar las reseñas y fotos de ${name}',
			'reportSheet.muteAuthor' => 'Ocultar a este autor',
			'reportSheet.muteTitle' => ({required Object name}) => '¿Ocultar a ${name}?',
			'reportSheet.muteBody' => 'Sus reseñas y fotos dejarán de mostrarse para ti. Puedes cambiar de opinión en tu perfil.',
			'reportSheet.muted' => ({required Object name}) => '${name} está oculto',
			'reportSheet.deletePhoto' => 'Eliminar mi foto',
			'reportSheet.deletePhotoTitle' => '¿Eliminar esta foto?',
			'reportSheet.deletePhotoBody' => 'Desaparece de la ficha y de nuestros servidores.',
			'reviewSheet.titleNew' => 'Tu reseña',
			'reviewSheet.titleEdit' => 'Modificar tu reseña',
			'reviewSheet.starsRequired' => 'Elige una valoración de 1 a 5',
			'reviewSheet.text' => 'Tu reseña',
			'reviewSheet.textHint' => 'La tranquilidad, la acogida, el espacio para maniobrar, lo que te resultó útil',
			'reviewSheet.tooShort' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Al menos ${n} carácter más', other: 'Al menos ${n} caracteres más', ), 
			'reviewSheet.visited' => 'Fecha de la estancia',
			'reviewSheet.visitedNone' => 'Sin indicar',
			'reviewSheet.vehicle' => 'Tu vehículo',
			'reviewSheet.vehicleNone' => 'Prefiero no decirlo',
			'reviewSheet.licence' => 'Se publica bajo licencia CC BY 4.0, con tu seudónimo. La fecha de la estancia es opcional: juntas, las fechas de tus reseñas pueden revelar tu recorrido.',
			'reviewSheet.publish' => 'Publicar la reseña',
			'gate.review' => 'Reseñas escritas: desde el nivel 1',
			'gate.photo' => 'Fotos: desde el nivel 1',
			'gate.addPlace' => 'Añadir lugares: desde el nivel 2',
			'gate.edit' => 'Proponer cambios: desde el nivel 1',
			'gate.why' => 'Los niveles protegen el mapa de los abusos. Llegan con el tiempo y las contribuciones, sin nada que comprar.',
			'gate.yourLevel' => ({required Object level}) => 'Tu nivel: ${level}',
			'gate.noAccount' => 'Todavía no tienes cuenta: una cuenta empieza en el nivel 0.',
			'gate.later' => ({required Object level}) => 'El nivel ${level} llega después de los anteriores, con el tiempo y las contribuciones publicadas.',
			'gate.meanwhile' => 'Mientras tanto, puedes valorar lugares, confirmar que siguen ahí o avisar de un problema.',
			'photoFlow.title' => 'Añadir una foto',
			'photoFlow.camera' => 'Hacer una foto',
			'photoFlow.gallery' => 'Elegir de la galería',
			'photoFlow.preparing' => 'Preparando la foto',
			'photoFlow.licence' => 'Se publica bajo licencia CC BY 4.0, con tu seudónimo. Evita las caras y las matrículas.',
			'photoFlow.stripped' => 'La ubicación y los datos del dispositivo se eliminan antes del envío.',
			'photoFlow.send' => 'Enviar la foto',
			'photoFlow.unreadable' => 'Esta imagen no se puede leer en este dispositivo. Prueba con una foto JPEG o PNG.',
			'photoFlow.sending' => ({required Object percent}) => 'Enviando ${percent} %',
			'photoFlow.pending' => 'Foto pendiente de envío',
			'placeForm.addTitle' => 'Añadir un lugar',
			'placeForm.editTitle' => 'Modificar el lugar',
			'placeForm.proposeTitle' => 'Proponer un cambio',
			'placeForm.position' => 'Ubicación en el mapa',
			'placeForm.kind' => 'Tipo de lugar',
			'placeForm.kindRequired' => 'Elige un tipo de lugar',
			'placeForm.name' => 'Nombre',
			'placeForm.nameHint' => 'El nombre que aparece en el lugar o una descripción breve',
			'placeForm.nameInvalid' => 'De 2 a 120 caracteres',
			'placeForm.night' => 'Pernocta',
			'placeForm.services' => 'Servicios en el lugar',
			'placeForm.description' => 'Descripción',
			'placeForm.descriptionHint' => 'Lo que ayuda a encontrar y elegir el lugar',
			'placeForm.details' => 'Detalles',
			'placeForm.priceNight' => 'Precio por noche (€)',
			'placeForm.priceServices' => 'Precio de los servicios (€)',
			'placeForm.maxHeight' => 'Altura máxima (m)',
			'placeForm.capacity' => 'Plazas',
			'placeForm.website' => 'Sitio web',
			'placeForm.phone' => 'Teléfono',
			'placeForm.photo' => 'Foto (opcional)',
			'placeForm.photoReady' => 'Foto lista',
			'placeForm.removePhoto' => 'Quitar la foto',
			'placeForm.toVerify' => 'El lugar aparecerá como «por verificar» hasta que otros dos viajeros lo confirmen.',
			'placeForm.licence' => 'Los lugares se publican bajo licencia ODbL, con crédito a los colaboradores de Lunaway.',
			'placeForm.moderated' => 'Un sitio web o un número de teléfono pasa por un moderador antes de publicarse.',
			'placeForm.direct' => 'Con tu nivel, el cambio se aplica al momento.',
			'placeForm.proposal' => 'Un moderador revisará tu propuesta antes de aplicarla.',
			'placeForm.submitAdd' => 'Añadir el lugar',
			'placeForm.submitEdit' => 'Guardar el cambio',
			'placeForm.submitPropose' => 'Enviar la propuesta',
			'placeForm.nothingChanged' => 'No ha cambiado nada',
			'placeForm.invalidNumber' => 'Introduce un número',
			'placeForm.invalidWebsite' => 'Una dirección que empiece por http:// o https://',
			'placeForm.added' => 'Gracias: el lugar aparecerá en el mapa en un momento',
			'placeForm.proposed' => 'Gracias: tu propuesta pasa a revisión',
			'favoritesSync.local' => 'Solo en este dispositivo',
			'favoritesSync.action' => 'Sincronizar',
			'favoritesSync.syncing' => 'Sincronizando',
			'favoritesSync.synced' => ({required Object when}) => 'Guardados con tu cuenta, sincronizados ${when}',
			'favoritesSync.failed' => 'No se puede sincronizar ahora mismo',
			'favoritesSync.title' => '¿Sincronizar tus favoritos?',
			'favoritesSync.body' => 'Tus listas se guardarán con una cuenta de Lunaway, sin correo electrónico ni contraseña, para que puedas encontrarlas en otro dispositivo. La cuenta se crea ahora.',
			'favoritesSync.confirm' => 'Crear la cuenta y sincronizar',
			'poi.category.groceries' => 'Compras',
			'poi.category.vending' => 'Expendedoras de comida',
			'poi.category.water' => 'Agua y vaciado',
			'poi.category.fuel' => 'Combustible y energía',
			'poi.category.health' => 'Salud',
			'poi.category.services' => 'Servicios',
			'poi.kind.supermarket' => 'Supermercado',
			'poi.kind.convenience' => 'Tienda de alimentación',
			'poi.kind.bakery' => 'Panadería',
			'poi.kind.butcher' => 'Carnicería',
			'poi.kind.greengrocer' => 'Frutería',
			'poi.kind.farmShop' => 'Venta directa en granja',
			'poi.kind.marketplace' => 'Mercado',
			'poi.kind.vendingPizza' => 'Expendedora de pizzas',
			'poi.kind.vendingBread' => 'Expendedora de pan',
			'poi.kind.vendingFarmProducts' => 'Expendedora de productos de granja',
			'poi.kind.vendingEggsMilk' => 'Expendedora de huevos o leche',
			'poi.kind.vendingIce' => 'Expendedora de hielo',
			'poi.kind.vendingOther' => 'Expendedora de comida',
			'poi.kind.drinkingWater' => 'Agua potable',
			'poi.kind.waterPoint' => 'Punto de agua',
			'poi.kind.dumpStation' => 'Punto de vaciado',
			'poi.kind.toilets' => 'Aseos',
			'poi.kind.shower' => 'Duchas',
			'poi.kind.fuelStation' => 'Gasolinera',
			'poi.kind.evCharging' => 'Punto de recarga',
			'poi.kind.gasBottles' => 'Bombonas de gas',
			'poi.kind.pharmacy' => 'Farmacia',
			'poi.kind.doctor' => 'Médico',
			'poi.kind.hospital' => 'Hospital',
			'poi.kind.veterinary' => 'Veterinario',
			'poi.kind.laundry' => 'Lavandería',
			'poi.kind.atm' => 'Cajero automático',
			'poi.kind.postOffice' => 'Oficina de correos',
			'poi.kind.touristOffice' => 'Oficina de turismo',
			'poi.kind.recyclingCentre' => 'Punto limpio',
			'poi.kind.carRepair' => 'Taller',
			'poi.kind.carWash' => 'Lavado de vehículos',
			'poi.kind.motorhomeShop' => 'Concesionario y taller de autocaravanas',
			'poi.chipsLabel' => 'Comercios y servicios cercanos',
			'poi.openNow' => 'Abierto ahora',
			'poi.vendingSells.pizza' => 'Pizza',
			'poi.vendingSells.bread' => 'Pan',
			'poi.vendingSells.farmProducts' => 'Productos de granja',
			'poi.vendingSells.eggsMilk' => 'Huevos y leche',
			'poi.vendingSells.ice' => 'Hielo',
			'poi.vendingAll' => 'Todas las expendedoras de comida',
			'poi.vendingMenu' => 'Lo que venden las expendedoras',
			'poi.vendingChip.pizza' => 'Expendedoras de pizzas',
			'poi.vendingChip.bread' => 'Expendedoras de pan',
			'poi.vendingChip.farmProducts' => 'Expendedoras de productos de granja',
			'poi.vendingChip.eggsMilk' => 'Expendedoras de huevos y leche',
			'poi.vendingChip.ice' => 'Expendedoras de hielo',
			'poi.alwaysOpen' => 'Abierto día y noche',
			'poi.hoursUnknown' => 'Horario desconocido',
			'poi.maybeClosed' => 'Cerrado según el registro oficial de centros sanitarios (FINESS).',
			'poi.maybeClosedSince' => ({required Object date}) => 'Figura como cerrado en FINESS desde el ${date}: puede que haya cerrado definitivamente.',
			'poi.seasonal' => 'De temporada: puede estar cerrado en invierno.',
			'poi.fee' => 'De pago',
			'poi.free' => 'Gratis',
			'poi.stillThereTitle' => '¿Sigue ahí?',
			'poi.stillThereHint' => '¿Lo has visto hace poco? Tu respuesta ayuda a los próximos viajeros. No se envía ninguna ubicación.',
			'poi.stillThere' => 'Sigue ahí',
			'poi.gone' => 'Ya no existe',
			'poi.lastConfirmed' => ({required Object when}) => 'Confirmado ${when}',
			'poi.checkedOn' => ({required Object date}) => 'Comprobado en el lugar el ${date}',
			'poi.thanksThere' => 'Gracias, anotado: sigue ahí.',
			'poi.thanksGone' => 'Gracias, anotado: ya no existe.',
			'poi.fuelPrices' => 'Precios de los combustibles',
			'poi.perLitre' => ({required Object price}) => '${price}/l',
			'poi.priceUpdated' => ({required Object when}) => 'Precio actualizado ${when}',
			'poi.feedRead' => ({required Object when}) => 'Precios consultados ${when}',
			'poi.shortageTemporary' => 'Agotado por ahora',
			'poi.shortageDefinitive' => 'Ya no se vende',
			'poi.selfService24h' => 'Pago con tarjeta 24 h',
			'poi.highway' => 'En autopista',
			'poi.lpgYes' => 'Vende GLP',
			'poi.fuel.diesel' => 'Gasóleo',
			'poi.fuel.sp95' => 'Gasolina 95',
			'poi.fuel.e10' => 'Gasolina 95 E10',
			'poi.fuel.sp98' => 'Gasolina 98',
			'poi.fuel.e85' => 'E85',
			'poi.fuel.lpg' => 'GLP',
			'poi.products' => 'Vende',
			'poi.paymentTitle' => 'Pago',
			'poi.product.pizza' => 'Pizzas',
			'poi.product.bread' => 'Pan',
			'poi.product.eggs' => 'Huevos',
			'poi.product.milk' => 'Leche',
			'poi.product.cheese' => 'Queso',
			'poi.product.meat' => 'Carne',
			'poi.product.vegetables' => 'Verduras',
			'poi.product.fruit' => 'Fruta',
			'poi.product.honey' => 'Miel',
			'poi.product.ice' => 'Hielo',
			'poi.product.potatoes' => 'Patatas',
			'poi.product.food' => 'Alimentación',
			'poi.payment.cash' => 'Efectivo',
			'poi.payment.coins' => 'Monedas',
			'poi.payment.notes' => 'Billetes',
			'poi.payment.cards' => 'Tarjeta',
			'poi.payment.contactless' => 'Sin contacto',
			'poi.payment.app' => 'Aplicación móvil',
			'poi.justNow' => 'hace un momento',
			'poi.minutesAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'hace ${n} minuto', other: 'hace ${n} minutos', ), 
			'poi.hoursAgo' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'hace ${n} hora', other: 'hace ${n} horas', ), 
			'poi.readOffline' => ({required Object when}) => 'Consultado ${when}: sin conexión para actualizarlo',
			'poi.readStale' => ({required Object when}) => 'Consultado ${when}: no se ha podido actualizar en este momento.',
			'poi.goneTitle' => 'Este punto ya no está en el mapa',
			'poi.goneHint' => 'Algunos viajeros han indicado que ya no existe, o la última actualización lo ha retirado.',
			'poi.loadError' => 'No se han podido cargar los detalles. Arriba tienes lo que sabe el mapa.',
			'poi.around' => 'Alrededor de este lugar',
			'poi.aroundEmpty' => 'No se conoce ningún comercio ni servicio por aquí.',
			'poi.aroundError' => 'No se han podido cargar los comercios y servicios cercanos.',
			'poi.aroundOffline' => 'Sin conexión: los comercios y servicios cercanos aparecerán cuando tengas conexión.',
			'poi.onSite' => 'En el lugar',
			'poi.backTo' => ({required Object name}) => 'Volver a ${name}',
			'poi.backToPlace' => 'Volver al lugar',
			'poi.linkError' => 'No se ha podido abrir este comercio o servicio: no hay conexión o ya no está en el mapa.',
			'poi.searchSection' => 'Comercios y servicios',
			'poi.searching' => 'Buscando comercios y servicios',
			'poi.searchOffline' => 'Los comercios y servicios se buscan en línea: ahora no hay conexión.',
			'poi.add.title' => '¿Una máquina expendedora aquí?',
			'poi.add.hint' => 'Elige lo que vende: se añadirá al mapa de todos los viajeros.',
			'poi.add.pizza' => 'Pizzas',
			'poi.add.bread' => 'Pan',
			'poi.add.other' => 'Otros alimentos',
			'poi.add.gate' => 'Añadir una máquina expendedora',
			'poi.add.sent' => 'Gracias: la máquina aparecerá en el mapa en unos minutos.',
			'poi.add.duplicateTitle' => 'Ya está en el mapa',
			'poi.add.duplicateBody' => 'Ya figura una máquina del mismo tipo a menos de 25 m. ¿Sigue ahí?',
			'poi.add.duplicateThere' => 'Sí, sigue ahí',
			'poi.add.duplicateGone' => 'No, ya no está',
			'poi.cheapest.title' => 'Más barato cerca de mí',
			'poi.cheapest.show' => 'Más barato cerca',
			'poi.cheapest.zoomIn' => 'Acerca el mapa para comparar los precios de las gasolineras.',
			'poi.cheapest.none' => 'Ninguna gasolinera del mapa vende este combustible.',
			'poi.cheapest.noneHint' => 'Mueve el mapa o elige otro combustible.',
			'poi.cheapest.error' => 'No se han podido cargar los precios de las gasolineras.',
			'poi.trend.title' => ({required Object fuel}) => '${fuel}: precios de los últimos días',
			'poi.trend.none' => 'Lunaway todavía no ha visto ningún precio de este combustible aquí.',
			'poi.trend.failed' => 'No se han podido leer ahora los precios de los últimos días.',
			'poi.trend.week' => 'Últimos 7 días:',
			'poi.trend.month' => 'Últimos 30 días:',
			'poi.trend.range' => ({required Object low, required Object high}) => 'de ${low} a ${high}',
			'poi.trend.span' => ({required Object range, required Object move}) => '${range}, ${move}',
			'poi.trend.oneDay' => 'un solo día registrado',
			'poi.trend.steady' => 'sin cambios',
			'poi.trend.down' => ({required Object amount}) => 'ha bajado ${amount}',
			'poi.trend.up' => ({required Object amount}) => 'ha subido ${amount}',
			'poi.trend.since' => ({required num n, required Object date}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} día registrado desde el ${date} según los datos de la fuente; los días sin datos quedan en blanco', other: '${n} días registrados desde el ${date} según los datos de la fuente; los días sin datos quedan en blanco', ), 
			'offlineMaps.title' => 'Mapas sin conexión',
			'offlineMaps.intro' => 'Antes de salir, guarda una región en el dispositivo: sus lugares para buscar y elegir, su mapa para ver las calles sin conexión.',
			'offlineMaps.webTitle' => 'Los mapas sin conexión están en la aplicación',
			'offlineMaps.web' => 'Las aplicaciones de Android e iOS guardan regiones para el viaje. En un navegador, el mapa necesita conexión.',
			'offlineMaps.desktopTitle' => 'Los mapas sin conexión están en el móvil',
			'offlineMaps.desktop' => 'Las aplicaciones de Android e iOS guardan regiones para el viaje. En un ordenador, el mapa necesita conexión.',
			'offlineMaps.unreadable' => 'No se han podido cargar los mapas sin conexión de este dispositivo.',
			'offlineMaps.none' => 'Todavía no hay ninguna región en este dispositivo.',
			'offlineMaps.used' => ({required Object size}) => 'Espacio usado: ${size}',
			'offlineMaps.downloads' => 'Descargas',
			'offlineMaps.installed' => 'En este dispositivo',
			'offlineMaps.suggested' => 'Sugeridas',
			'offlineMaps.here' => 'Donde estás',
			'offlineMaps.favoritesHere' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${n} favorito en esta región', other: '${n} favoritos en esta región', ), 
			'offlineMaps.france' => 'Francia',
			'offlineMaps.overseas' => 'Francia de ultramar',
			'offlineMaps.countries' => 'Países',
			'offlineMaps.downloadNamed' => ({required Object name, required Object size}) => 'Descargar ${name}, ${size}',
			'offlineMaps.pause' => 'Pausar',
			'offlineMaps.resume' => 'Reanudar',
			'offlineMaps.cancel' => 'Detener y borrar la descarga',
			'offlineMaps.waiting' => 'Esperando su turno',
			'offlineMaps.progress' => ({required Object done, required Object total}) => '${done} de ${total}',
			'offlineMaps.paused' => ({required Object done, required Object total}) => 'En pausa: ${done} de ${total}',
			'offlineMaps.verifying' => 'Comprobando el archivo',
			'offlineMaps.failedNetwork' => 'Interrumpida: sin conexión. Se reanudará donde se quedó en cuanto vuelva la conexión.',
			'offlineMaps.failedServer' => 'El servidor ha enviado algo distinto del mapa. Vuelve a intentarlo más tarde.',
			'offlineMaps.failedCorrupt' => 'El archivo ha llegado dañado y se ha borrado. Vuelve a intentarlo.',
			'offlineMaps.failedStorage' => 'No queda espacio suficiente en el dispositivo. Libera espacio y vuelve a intentarlo.',
			'offlineMaps.keepOpen' => 'Mantén la aplicación abierta durante la descarga: se interrumpe cuando la aplicación pasa a segundo plano y se reanuda cuando vuelves.',
			'offlineMaps.dataOf' => ({required Object date}) => 'datos del ${date}',
			'offlineMaps.update' => ({required Object size}) => 'Actualizar, ${size}',
			'offlineMaps.deleteNamed' => ({required Object name}) => 'Eliminar ${name}',
			'offlineMaps.deleteTitle' => ({required Object name}) => '¿Eliminar ${name} de este dispositivo?',
			'offlineMaps.deleteBody' => 'Ya no se verá sin conexión. Puedes volver a descargarla.',
			'offlineMaps.listOffline' => 'La lista de regiones necesita conexión.',
			'offlineMaps.listCopy' => 'Lista guardada de la última conexión.',
			'offlineMaps.entryHint' => 'Para viajar sin conexión',
			'offlineMaps.entryCount' => ({required num n, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Mapas: ${n} región, ${size}', other: 'Mapas: ${n} regiones, ${size}', ), 
			'offlineMaps.noticePack' => ({required Object name}) => 'Sin conexión: mapa descargado, ${name}',
			'offlineMaps.noticeOutside' => 'Sin conexión: esta zona no está descargada',
			'offlineMaps.noticePlacesOnly' => 'Sin conexión: lugares en el dispositivo, mapa de esta zona sin descargar',
			'offlineMaps.noticeNone' => 'Sin conexión: descarga una región para la próxima vez',
			'offlineMaps.noticeOnline' => 'Sin conexión: el mapa necesita conexión',
			'offlineMaps.placesTitle' => 'Lugares',
			'offlineMaps.placesHint' => 'Unos pocos megabytes por región: la lista, la búsqueda, las fichas y los filtros funcionan sin conexión.',
			'offlineMaps.mapsTitle' => 'Mapas',
			'offlineMaps.mapsHint' => 'Todas las calles, unos cientos de megabytes por región: el mapa se ve sin conexión.',
			'offlineMaps.entryPlaces' => ({required Object names}) => 'Lugares: ${names}',
			'offlineMaps.entryPlacesCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Lugares: ${n} región', other: 'Lugares: ${n} regiones', ), 
			'regions.pickerTitle' => '¿Qué lugares quieres guardar en este dispositivo?',
			'regions.pickerIntro' => 'Cada región se descarga una vez y después se actualiza en pequeñas partes. Más adelante puedes añadir o quitar regiones en Mapas sin conexión.',
			'regions.nearYou' => ({required Object name}) => 'Cerca de ti: ${name}',
			'regions.findMine' => 'Buscar mi región',
			'regions.locating' => 'Buscando tu región',
			'regions.notCovered' => 'Todavía no hay ninguna región de Lunaway a tu alrededor',
			'regions.wholeFrance' => 'Toda Francia',
			'regions.showFrance' => 'Mostrar las regiones de Francia',
			'regions.hideFrance' => 'Ocultar las regiones de Francia',
			'regions.packInfo' => ({required num n, required Object count, required Object size}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: '${count} lugar, ${size}', other: '${count} lugares, ${size}', ), 
			'regions.noPack' => 'Sin paquete: los lugares llegan con las actualizaciones, tamaño desconocido',
			'regions.download' => ({required Object size}) => 'Descargar, ${size}',
			'regions.unavailable' => 'El servidor todavía no ofrece regiones: Lunaway guarda toda Francia.',
			'regions.listFailed' => 'La lista de regiones necesita conexión.',
			'regions.choose' => 'Elegir las regiones',
			'regions.noneKept' => 'Ninguna región guardada: el mapa no tiene lugares sin conexión.',
			'regions.change' => 'Añadir o quitar regiones',
			'regions.removeNamed' => ({required Object name}) => 'Quitar ${name}',
			'regions.removed' => ({required Object name}) => '${name}: lugares quitados de este dispositivo',
			'regions.downloading' => ({required Object done, required Object total}) => 'Descargando, ${done} de ${total}',
			'regions.updating' => ({required num n, required Object count}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('es'))(n, one: 'Actualizando, ${count} lugar', other: 'Actualizando, ${count} lugares', ), 
			'regions.waiting' => 'esperando su descarga',
			'regions.downloadingNamed' => ({required Object name}) => 'Descargando los lugares: ${name}',
			'regions.updated' => ({required Object when}) => 'última actualización ${when}',
			'regions.offerTitle' => ({required Object name}) => '${name}: ¿guardar sus lugares sin conexión?',
			'regions.downloadThis' => 'Descargar esta región',
			'regions.notHere' => ({required Object name}) => '${name} no está en este dispositivo',
			'regions.updatesOnMobile' => 'Actualizar con datos móviles',
			'regions.updatesOnMobileHint' => 'Si no, las regiones ya descargadas se actualizan por wifi. Una descarga nueva usa cualquier red.',
			'roadReport.actionHint' => 'Avisar de un problema en la carretera',
			'roadReport.title' => '¿Qué ves en la carretera?',
			'roadReport.intro' => 'Tu aviso alerta a los demás viajeros. Cuando dos cuentas de confianza avisan de lo mismo, las rutas lo evitan. No se admiten avisos de controles policiales.',
			'roadReport.kinds.closure' => 'Carretera cortada',
			'roadReport.kinds.works' => 'Obras',
			'roadReport.kinds.narrowPassage' => 'Paso estrecho',
			'roadReport.kinds.lowClearance' => 'Altura limitada',
			'roadReport.kinds.other' => 'Problema en la carretera',
			'roadReport.height' => ({required Object value}) => 'Altura indicada: ${value}',
			'roadReport.send' => 'Avisar',
			'roadReport.sent' => 'Gracias: los demás viajeros quedan avisados.',
			'roadReport.movingTitle' => 'Estás conduciendo',
			'roadReport.movingBody' => 'No avises de nada mientras conduces. Puede hacerlo un pasajero; si no, detente primero.',
			'roadReport.passenger' => 'No estoy conduciendo',
			'roadReport.stillThere' => 'Sigue ahí',
			'roadReport.over' => 'Ya ha terminado',
			'roadReport.overSent' => 'Gracias: anotado.',
			'roadReport.fromMap' => 'Avisar de un problema aquí',
			'roadReport.notHereTitle' => 'Aquí no se admiten avisos',
			'roadReport.lower' => '10 cm más bajo',
			'roadReport.higher' => '10 cm más alto',
			'roadReport.passed' => ({required Object what}) => 'Acabas de pasar: ${what}. ¿Sigue ahí?',
			'roadReport.notHere' => ({required Object countries}) => 'Lunaway acepta avisos donde una fuente oficial los contrasta: ${countries}.',
			'countries.ad' => 'Andorra',
			'countries.at' => 'Austria',
			'countries.ax' => 'Åland',
			'countries.be' => 'Bélgica',
			'countries.ch' => 'Suiza',
			'countries.cz' => 'Chequia',
			'countries.de' => 'Alemania',
			'countries.dk' => 'Dinamarca',
			'countries.eh' => 'Sáhara Occidental',
			_ => null,
		} ?? switch (path) {
			'countries.es' => 'España',
			'countries.fi' => 'Finlandia',
			'countries.fr' => 'Francia',
			'countries.gb' => 'Reino Unido',
			'countries.gi' => 'Gibraltar',
			'countries.gr' => 'Grecia',
			'countries.hr' => 'Croacia',
			'countries.ie' => 'Irlanda',
			'countries.it' => 'Italia',
			'countries.li' => 'Liechtenstein',
			'countries.lu' => 'Luxemburgo',
			'countries.ma' => 'Marruecos',
			'countries.mc' => 'Mónaco',
			'countries.nl' => 'Países Bajos',
			'countries.no' => 'Noruega',
			'countries.pl' => 'Polonia',
			'countries.pt' => 'Portugal',
			'countries.se' => 'Suecia',
			'countries.si' => 'Eslovenia',
			'countries.sj' => 'Svalbard',
			'countries.sm' => 'San Marino',
			'countries.va' => 'Ciudad del Vaticano',
			'areas.ara' => 'Auvernia-Ródano-Alpes',
			'areas.bfc' => 'Borgoña-Franco Condado',
			'areas.bre' => 'Bretaña',
			'areas.cvl' => 'Centro-Valle de Loira',
			'areas.cor' => 'Córcega',
			'areas.ges' => 'Gran Este',
			'areas.hdf' => 'Alta Francia',
			'areas.idf' => 'Isla de Francia',
			'areas.nor' => 'Normandía',
			'areas.naq' => 'Nueva Aquitania',
			'areas.occ' => 'Occitania',
			'areas.pdl' => 'País del Loira',
			'areas.pac' => 'Provenza-Alpes-Costa Azul',
			'areas.gp' => 'Guadalupe',
			'areas.mq' => 'Martinica',
			'areas.gf' => 'Guayana Francesa',
			'areas.re' => 'Reunión',
			'areas.yt' => 'Mayotte',
			'areas.franceRest' => 'Francia, sin municipio',
			_ => null,
		};
	}
}

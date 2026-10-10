import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lunaway/core/time/place_zone.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/features/poi/presentation/poi_look.dart';
import 'package:lunaway/i18n/strings.g.dart';
import 'package:lunaway/shared/labels.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// The words of the points of interest.
extension PoiLabels on Translations {
  // Read through a name, so the translation gate sees every key used.
  Translations get _t => this;

  String poiCategory(PoiCategory c) => switch (c) {
    .groceries => _t.poi.category.groceries,
    .vending => _t.poi.category.vending,
    .water => _t.poi.category.water,
    .fuel => _t.poi.category.fuel,
    .health => _t.poi.category.health,
    .services => _t.poi.category.services,
    .food => _t.poi.category.food,
    .sights => _t.poi.category.sights,
    .shopping => _t.poi.category.shopping,
    .lodging => _t.poi.category.lodging,
    .leisure => _t.poi.category.leisure,
  };

  String poiKind(PoiKind k) => switch (k) {
    .supermarket => _t.poi.kind.supermarket,
    .convenience => _t.poi.kind.convenience,
    .bakery => _t.poi.kind.bakery,
    .butcher => _t.poi.kind.butcher,
    .greengrocer => _t.poi.kind.greengrocer,
    .farmShop => _t.poi.kind.farmShop,
    .marketplace => _t.poi.kind.marketplace,
    .vendingPizza => _t.poi.kind.vendingPizza,
    .vendingBread => _t.poi.kind.vendingBread,
    .vendingFarmProducts => _t.poi.kind.vendingFarmProducts,
    .vendingEggsMilk => _t.poi.kind.vendingEggsMilk,
    .vendingIce => _t.poi.kind.vendingIce,
    .vendingOther => _t.poi.kind.vendingOther,
    .drinkingWater => _t.poi.kind.drinkingWater,
    .waterPoint => _t.poi.kind.waterPoint,
    .dumpStation => _t.poi.kind.dumpStation,
    .toilets => _t.poi.kind.toilets,
    .shower => _t.poi.kind.shower,
    .fuelStation => _t.poi.kind.fuelStation,
    .evCharging => _t.poi.kind.evCharging,
    .gasBottles => _t.poi.kind.gasBottles,
    .pharmacy => _t.poi.kind.pharmacy,
    .doctor => _t.poi.kind.doctor,
    .hospital => _t.poi.kind.hospital,
    .veterinary => _t.poi.kind.veterinary,
    .laundry => _t.poi.kind.laundry,
    .atm => _t.poi.kind.atm,
    .postOffice => _t.poi.kind.postOffice,
    .touristOffice => _t.poi.kind.touristOffice,
    .recyclingCentre => _t.poi.kind.recyclingCentre,
    .carRepair => _t.poi.kind.carRepair,
    .carWash => _t.poi.kind.carWash,
    .motorhomeShop => _t.poi.kind.motorhomeShop,
    .outdoorShop => _t.poi.kind.outdoorShop,
    .restaurant => _t.poi.kind.restaurant,
    .cafe => _t.poi.kind.cafe,
    .fastFood => _t.poi.kind.fastFood,
    .viewpoint => _t.poi.kind.viewpoint,
    .attraction => _t.poi.kind.attraction,
    .museum => _t.poi.kind.museum,
    .bar => _t.poi.kind.bar,
    .pub => _t.poi.kind.pub,
    .iceCream => _t.poi.kind.iceCream,
    .deli => _t.poi.kind.deli,
    .cheese => _t.poi.kind.cheese,
    .seafood => _t.poi.kind.seafood,
    .pastry => _t.poi.kind.pastry,
    .confectionery => _t.poi.kind.confectionery,
    .wineShop => _t.poi.kind.wineShop,
    .beverages => _t.poi.kind.beverages,
    .teaCoffee => _t.poi.kind.teaCoffee,
    .organicShop => _t.poi.kind.organicShop,
    .frozenFood => _t.poi.kind.frozenFood,
    .winery => _t.poi.kind.winery,
    .brewery => _t.poi.kind.brewery,
    .distillery => _t.poi.kind.distillery,
    .beekeeper => _t.poi.kind.beekeeper,
    .dentist => _t.poi.kind.dentist,
    .clinic => _t.poi.kind.clinic,
    .physiotherapist => _t.poi.kind.physiotherapist,
    .laboratory => _t.poi.kind.laboratory,
    .nurse => _t.poi.kind.nurse,
    .midwife => _t.poi.kind.midwife,
    .podiatrist => _t.poi.kind.podiatrist,
    .psychologist => _t.poi.kind.psychologist,
    .speechTherapist => _t.poi.kind.speechTherapist,
    .alternativeMedicine => _t.poi.kind.alternativeMedicine,
    .optician => _t.poi.kind.optician,
    .hearingAids => _t.poi.kind.hearingAids,
    .medicalSupply => _t.poi.kind.medicalSupply,
    .hairdresser => _t.poi.kind.hairdresser,
    .beauty => _t.poi.kind.beauty,
    .massage => _t.poi.kind.massage,
    .tattoo => _t.poi.kind.tattoo,
    .bank => _t.poi.kind.bank,
    .moneyExchange => _t.poi.kind.moneyExchange,
    .carRental => _t.poi.kind.carRental,
    .bicycleRental => _t.poi.kind.bicycleRental,
    .boatRental => _t.poi.kind.boatRental,
    .vehicleInspection => _t.poi.kind.vehicleInspection,
    .drivingSchool => _t.poi.kind.drivingSchool,
    .dryCleaning => _t.poi.kind.dryCleaning,
    .tailor => _t.poi.kind.tailor,
    .shoeRepair => _t.poi.kind.shoeRepair,
    .locksmith => _t.poi.kind.locksmith,
    .copyshop => _t.poi.kind.copyshop,
    .photographer => _t.poi.kind.photographer,
    .travelAgency => _t.poi.kind.travelAgency,
    .estateAgent => _t.poi.kind.estateAgent,
    .insurance => _t.poi.kind.insurance,
    .funeralDirectors => _t.poi.kind.funeralDirectors,
    .petGrooming => _t.poi.kind.petGrooming,
    .tyres => _t.poi.kind.tyres,
    .carParts => _t.poi.kind.carParts,
    .carDealer => _t.poi.kind.carDealer,
    .motorcycleShop => _t.poi.kind.motorcycleShop,
    .repairShop => _t.poi.kind.repairShop,
    .internetCafe => _t.poi.kind.internetCafe,
    .coworking => _t.poi.kind.coworking,
    .townhall => _t.poi.kind.townhall,
    .police => _t.poi.kind.police,
    .library => _t.poi.kind.library,
    .rental => _t.poi.kind.rental,
    .storageRental => _t.poi.kind.storageRental,
    .animalBoarding => _t.poi.kind.animalBoarding,
    .ferryTerminal => _t.poi.kind.ferryTerminal,
    .clothes => _t.poi.kind.clothes,
    .shoes => _t.poi.kind.shoes,
    .accessories => _t.poi.kind.accessories,
    .jewellery => _t.poi.kind.jewellery,
    .books => _t.poi.kind.books,
    .newsagent => _t.poi.kind.newsagent,
    .tobacco => _t.poi.kind.tobacco,
    .stationery => _t.poi.kind.stationery,
    .gift => _t.poi.kind.gift,
    .toys => _t.poi.kind.toys,
    .sports => _t.poi.kind.sports,
    .fishingHunting => _t.poi.kind.fishingHunting,
    .bicycleShop => _t.poi.kind.bicycleShop,
    .boatShop => _t.poi.kind.boatShop,
    .florist => _t.poi.kind.florist,
    .gardenCentre => _t.poi.kind.gardenCentre,
    .hardware => _t.poi.kind.hardware,
    .home => _t.poi.kind.home,
    .electronics => _t.poi.kind.electronics,
    .cosmetics => _t.poi.kind.cosmetics,
    .departmentStore => _t.poi.kind.departmentStore,
    .varietyStore => _t.poi.kind.varietyStore,
    .secondHand => _t.poi.kind.secondHand,
    .artShop => _t.poi.kind.artShop,
    .musicShop => _t.poi.kind.musicShop,
    .petShop => _t.poi.kind.petShop,
    .babyGoods => _t.poi.kind.babyGoods,
    .fabric => _t.poi.kind.fabric,
    .craft => _t.poi.kind.craft,
    .shop => _t.poi.kind.shop,
    .hotel => _t.poi.kind.hotel,
    .guestHouse => _t.poi.kind.guestHouse,
    .hostel => _t.poi.kind.hostel,
    .holidayRental => _t.poi.kind.holidayRental,
    .mountainHut => _t.poi.kind.mountainHut,
    .cinema => _t.poi.kind.cinema,
    .theatre => _t.poi.kind.theatre,
    .eventsVenue => _t.poi.kind.eventsVenue,
    .artsCentre => _t.poi.kind.artsCentre,
    .nightclub => _t.poi.kind.nightclub,
    .casino => _t.poi.kind.casino,
    .sportsCentre => _t.poi.kind.sportsCentre,
    .fitnessCentre => _t.poi.kind.fitnessCentre,
    .swimmingPool => _t.poi.kind.swimmingPool,
    .waterPark => _t.poi.kind.waterPark,
    .golfCourse => _t.poi.kind.golfCourse,
    .miniatureGolf => _t.poi.kind.miniatureGolf,
    .marina => _t.poi.kind.marina,
    .horseRiding => _t.poi.kind.horseRiding,
    .bowlingAlley => _t.poi.kind.bowlingAlley,
    .escapeGame => _t.poi.kind.escapeGame,
    .amusementArcade => _t.poi.kind.amusementArcade,
    .iceRink => _t.poi.kind.iceRink,
    .spa => _t.poi.kind.spa,
    .dance => _t.poi.kind.dance,
    .park => _t.poi.kind.park,
    .natureReserve => _t.poi.kind.natureReserve,
    .gallery => _t.poi.kind.gallery,
    .zoo => _t.poi.kind.zoo,
    .themePark => _t.poi.kind.themePark,
  };

  /// What the machines of a [PoiKind.vendingChoices] kind sell, as the
  /// vending chip's menu lists it ("Pizza").
  String poiVendingSells(PoiKind k) => switch (k) {
    .vendingPizza => _t.poi.vendingSells.pizza,
    .vendingBread => _t.poi.vendingSells.bread,
    .vendingFarmProducts => _t.poi.vendingSells.farmProducts,
    .vendingEggsMilk => _t.poi.vendingSells.eggsMilk,
    .vendingIce => _t.poi.vendingSells.ice,
    _ => poiKind(k),
  };

  /// The vending chip's label while it shows one kind alone ("Pizza
  /// vending machines").
  String poiVendingChip(PoiKind k) => switch (k) {
    .vendingPizza => _t.poi.vendingChip.pizza,
    .vendingBread => _t.poi.vendingChip.bread,
    .vendingFarmProducts => _t.poi.vendingChip.farmProducts,
    .vendingEggsMilk => _t.poi.vendingChip.eggsMilk,
    .vendingIce => _t.poi.vendingChip.ice,
    _ => poiCategory(k.category),
  };

  /// The name, else the kind ("Pizza vending machine").
  String poiTitle(String? name, PoiKind kind) =>
      name != null && name.trim().isNotEmpty ? name : poiKind(kind);

  /// The fuel of the price feed (`FuelKind`).
  String fuelName(String fuel) => switch (fuel) {
    'DIESEL' => _t.poi.fuel.diesel,
    'SP95' => _t.poi.fuel.sp95,
    'E10' => _t.poi.fuel.e10,
    'SP98' => _t.poi.fuel.sp98,
    'E85' => _t.poi.fuel.e85,
    'LPG' => _t.poi.fuel.lpg,
    _ => fuel,
  };

  /// What a machine sells, from OpenStreetMap's `vending` values; another
  /// value shows as the source wrote it.
  String product(String value) => switch (value) {
    'pizza' => _t.poi.product.pizza,
    'bread' => _t.poi.product.bread,
    'eggs' => _t.poi.product.eggs,
    'milk' => _t.poi.product.milk,
    'cheese' => _t.poi.product.cheese,
    'meat' => _t.poi.product.meat,
    'vegetables' => _t.poi.product.vegetables,
    'fruit' => _t.poi.product.fruit,
    'honey' => _t.poi.product.honey,
    'ice_cubes' => _t.poi.product.ice,
    'potatoes' => _t.poi.product.potatoes,
    'food' => _t.poi.product.food,
    _ => value.replaceAll('_', ' '),
  };

  /// What a restaurant cooks, from OpenStreetMap's `cuisine` values;
  /// another value shows as the source wrote it.
  String cuisine(String value) => knownCuisine(value) ?? _shownAsWritten(value);

  /// The word of a cuisine the app knows; null for another value.
  String? knownCuisine(String value) => switch (value) {
    'pizza' || 'italian_pizza' => _t.poi.cuisine.pizza,
    'italian' => _t.poi.cuisine.italian,
    'french' => _t.poi.cuisine.french,
    'regional' => _t.poi.cuisine.regional,
    'local' => _t.poi.cuisine.local,
    'burger' => _t.poi.cuisine.burger,
    'kebab' => _t.poi.cuisine.kebab,
    'chinese' => _t.poi.cuisine.chinese,
    'japanese' => _t.poi.cuisine.japanese,
    'sushi' => _t.poi.cuisine.sushi,
    'asian' => _t.poi.cuisine.asian,
    'indian' => _t.poi.cuisine.indian,
    'thai' => _t.poi.cuisine.thai,
    'vietnamese' => _t.poi.cuisine.vietnamese,
    'korean' => _t.poi.cuisine.korean,
    'mexican' => _t.poi.cuisine.mexican,
    'lebanese' => _t.poi.cuisine.lebanese,
    'greek' => _t.poi.cuisine.greek,
    'turkish' => _t.poi.cuisine.turkish,
    'moroccan' => _t.poi.cuisine.moroccan,
    'middle_eastern' => _t.poi.cuisine.middleEastern,
    'arab' => _t.poi.cuisine.arab,
    'african' => _t.poi.cuisine.african,
    'american' => _t.poi.cuisine.american,
    'spanish' => _t.poi.cuisine.spanish,
    'tapas' => _t.poi.cuisine.tapas,
    'portuguese' => _t.poi.cuisine.portuguese,
    'german' => _t.poi.cuisine.german,
    'mediterranean' => _t.poi.cuisine.mediterranean,
    'international' => _t.poi.cuisine.international,
    'seafood' => _t.poi.cuisine.seafood,
    'fish' => _t.poi.cuisine.fish,
    'fish_and_chips' => _t.poi.cuisine.fishAndChips,
    'steak_house' => _t.poi.cuisine.steakHouse,
    'grill' => _t.poi.cuisine.grill,
    'barbecue' => _t.poi.cuisine.barbecue,
    'chicken' => _t.poi.cuisine.chicken,
    'crepe' => _t.poi.cuisine.crepe,
    'pasta' => _t.poi.cuisine.pasta,
    'noodle' => _t.poi.cuisine.noodle,
    'ramen' => _t.poi.cuisine.ramen,
    'couscous' => _t.poi.cuisine.couscous,
    'sandwich' => _t.poi.cuisine.sandwich,
    'bagel' => _t.poi.cuisine.bagel,
    'hot_dog' => _t.poi.cuisine.hotDog,
    'friture' => _t.poi.cuisine.friture,
    'salad' => _t.poi.cuisine.salad,
    'vegetarian' => _t.poi.cuisine.vegetarian,
    'vegan' => _t.poi.cuisine.vegan,
    'breakfast' => _t.poi.cuisine.breakfast,
    'brunch' => _t.poi.cuisine.brunch,
    'coffee_shop' => _t.poi.cuisine.coffeeShop,
    'tea' => _t.poi.cuisine.tea,
    'bubble_tea' => _t.poi.cuisine.bubbleTea,
    'juice' => _t.poi.cuisine.juice,
    'ice_cream' => _t.poi.cuisine.iceCream,
    'cake' => _t.poi.cuisine.cake,
    'donut' => _t.poi.cuisine.donut,
    _ => null,
  };

  /// A value of OpenStreetMap the app has no word for, readable: `hot_pot`
  /// reads "Hot pot".
  static String _shownAsWritten(String value) {
    final text = value.replaceAll('_', ' ').trim();
    return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }

  /// What a garage works on, from OpenStreetMap's `service:vehicle:*`
  /// values; another value shows as the source wrote it.
  String vehicleService(String value) => switch (value) {
    'tyres' => _t.poi.vehicleService.tyres,
    'brakes' => _t.poi.vehicleService.brakes,
    'oil_change' => _t.poi.vehicleService.oilChange,
    'glass' => _t.poi.vehicleService.glass,
    'air_conditioning' => _t.poi.vehicleService.airConditioning,
    'body_repair' => _t.poi.vehicleService.bodyRepair,
    'painting' => _t.poi.vehicleService.painting,
    'electrical' => _t.poi.vehicleService.electrical,
    'diagnostics' => _t.poi.vehicleService.diagnostics,
    'batteries' => _t.poi.vehicleService.batteries,
    'engine' => _t.poi.vehicleService.engine,
    'exhaust' => _t.poi.vehicleService.exhaust,
    'clutch' => _t.poi.vehicleService.clutch,
    'transmission' => _t.poi.vehicleService.transmission,
    'suspension' => _t.poi.vehicleService.suspension,
    'car_parts' => _t.poi.vehicleService.carParts,
    'new_car_sales' => _t.poi.vehicleService.newCarSales,
    'used_car_sales' => _t.poi.vehicleService.usedCarSales,
    _ => _shownAsWritten(value),
  };

  /// A diet a restaurant caters for (`vegetarian`, `gluten_free`); another
  /// value shows as the source wrote it.
  String diet(String value) => switch (value) {
    'vegetarian' => _t.poi.diet.vegetarian,
    'vegan' => _t.poi.diet.vegan,
    'gluten_free' => _t.poi.diet.glutenFree,
    'halal' => _t.poi.diet.halal,
    'kosher' => _t.poi.diet.kosher,
    'lactose_free' => _t.poi.diet.lactoseFree,
    _ => _shownAsWritten(value),
  };

  /// Whether to book, in a line.
  String reservation(PoiReservation r) => switch (r) {
    .yes => _t.poi.reservation.yes,
    .no => _t.poi.reservation.no,
    .required => _t.poi.reservation.required,
    .recommended => _t.poi.reservation.recommended,
    .only => _t.poi.reservation.only,
  };

  /// Wheelchair access as OpenStreetMap says it (`yes`, `limited`, `no`);
  /// null for another value, which says nothing sure.
  String? wheelchair(String? value) => switch (value) {
    'yes' || 'designated' => _t.poi.details.wheelchairYes,
    'limited' => _t.poi.details.wheelchairLimited,
    'no' => _t.poi.details.wheelchairNo,
    _ => null,
  };

  /// The payment methods of a point, each said once: OpenStreetMap tells
  /// credit and debit cards apart (`payment:credit_cards`,
  /// `payment:debit_cards`), a traveller reads one "Carte".
  List<String> payments(List<String> values) => [
    ...{for (final v in values) _payment(v)},
  ];

  String _payment(String value) => switch (value) {
    'cash' => _t.poi.payment.cash,
    'coins' => _t.poi.payment.coins,
    'notes' => _t.poi.payment.notes,
    'cards' || 'credit_cards' || 'debit_cards' => _t.poi.payment.cards,
    'contactless' => _t.poi.payment.contactless,
    'app' => _t.poi.payment.app,
    _ => value.replaceAll('_', ' '),
  };

  /// "1.029 €/L" or "1,029 €/L": the feed gives prices to the tenth of a
  /// cent.
  String pricePerLitre(double eur) {
    final price = NumberFormat.simpleCurrency(
      locale: $meta.locale.languageCode,
      name: 'EUR',
      decimalDigits: 3,
    ).format(eur);
    return _t.poi.perLitre(price: price);
  }

  /// "12 min ago", "3 h ago", then the days of [ago]: how fresh a price or
  /// a reading is.
  String agoFine(DateTime date, DateTime now) {
    final minutes = now.difference(date).inMinutes;
    if (minutes < 1) return _t.poi.justNow;
    if (minutes < 60) return _t.poi.minutesAgo(n: minutes);
    if (minutes < 24 * 60) return _t.poi.hoursAgo(n: minutes ~/ 60);
    return ago(date, now);
  }

  /// A point's state at [now]: "Open 24/7", "Open, closes at 19:00",
  /// "Closed, opens tomorrow at 08:00", or "Hours unknown".
  String poiOpening(PoiHours hours, DateTime now, {PlaceZone zone = PlaceZone.central}) {
    if (hours.alwaysOpen) return _t.poi.alwaysOpen;
    final state = hours.stateAt(now);
    if (state == null) return _t.poi.hoursUnknown;
    return opening(state, now, zone: zone);
  }
}

/// The colour of a state, from the colour scheme: open in the secondary
/// tone, closed in the error tone, unknown muted.
Color poiOpeningColor(ColorScheme scheme, PoiHours hours, DateTime now) =>
    switch (hours.opennessAt(now)) {
      PoiOpenness.open => scheme.secondary,
      PoiOpenness.closed => scheme.error,
      PoiOpenness.unknown => scheme.onSurfaceVariant,
    };

/// A point's tile in a list or a header: its glyph on its category's tone,
/// as on the map.
class PoiAvatar extends StatelessWidget {
  const new({required this.kind, this.size = 44, this.faded = false, super.key});

  final PoiKind kind;
  final double size;

  /// A point closed now.
  final bool faded;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: faded ? 0.55 : 1,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PoiLook.tone(kind.category),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(PoiLook.kind(kind), size: size * 0.54, color: LunaTokens.pinGlyph),
    ),
  );
}

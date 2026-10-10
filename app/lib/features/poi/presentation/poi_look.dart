import 'package:flutter/widgets.dart';
import 'package:lunaway/features/poi/domain/poi.dart';
import 'package:lunaway/shared/theme/palette.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';
import 'package:lunaway/shared/theme/tokens.dart';

/// How the points of interest look: a glyph per kind and a tone per
/// category. They stay quieter than the places (a rounded square, smaller,
/// in muted tones) so the night spots keep the map; the categories take
/// hues apart from the families of the places, the amber of the selection
/// and the coral of the alerts.
abstract final class PoiLook {
  /// The chip's icon of a category.
  static IconData category(PoiCategory c) => switch (c) {
    .groceries => PhosphorRegular.basket,
    .vending => PhosphorRegular.pizza,
    .water => PhosphorRegular.drop,
    .fuel => PhosphorRegular.gasPump,
    .health => PhosphorRegular.firstAid,
    .services => PhosphorRegular.wrench,
    .food => PhosphorRegular.forkKnife,
    .sights => PhosphorRegular.binoculars,
    .shopping => PhosphorRegular.shoppingBag,
    .lodging => PhosphorRegular.bed,
    .leisure => PhosphorRegular.ticket,
  };

  /// The glyph of a family on a pin: the map draws an establishment with
  /// it while its page is open (`PoiMapStyle.selectedImageId`).
  static IconData family(PoiCategory c) => switch (c) {
    .groceries => PhosphorFill.basket,
    .vending => PhosphorFill.pizza,
    .water => PhosphorFill.drop,
    .fuel => PhosphorFill.gasPump,
    .health => PhosphorFill.firstAid,
    .services => PhosphorFill.wrench,
    .food => PhosphorFill.forkKnife,
    .sights => PhosphorFill.binoculars,
    .shopping => PhosphorFill.shoppingBag,
    .lodging => PhosphorFill.bed,
    .leisure => PhosphorFill.ticket,
  };

  /// The glyph of a kind, on its pin and in its rows.
  static IconData kind(PoiKind k) => switch (k) {
    .supermarket => PhosphorFill.shoppingCart,
    .convenience => PhosphorFill.storefront,
    .bakery => PhosphorFill.bread,
    .butcher => PhosphorFill.knife,
    .greengrocer => PhosphorFill.carrot,
    .farmShop => PhosphorFill.barn,
    .marketplace => PhosphorFill.basket,
    .vendingPizza => PhosphorFill.pizza,
    .vendingBread => PhosphorFill.bread,
    .vendingFarmProducts => PhosphorFill.cheese,
    .vendingEggsMilk => PhosphorFill.egg,
    .vendingIce => PhosphorFill.snowflake,
    .vendingOther => PhosphorFill.package,
    .drinkingWater => PhosphorFill.drop,
    .waterPoint => PhosphorFill.dropHalfBottom,
    // The places' own icons for the same services: black water and
    // toilets (`AppIcons.service`).
    .dumpStation => PhosphorFill.toilet,
    .toilets => PhosphorFill.toiletPaper,
    .shower => PhosphorFill.shower,
    .fuelStation => PhosphorFill.gasPump,
    .evCharging => PhosphorFill.chargingStation,
    .gasBottles => PhosphorFill.cylinder,
    .pharmacy => PhosphorFill.firstAid,
    .doctor => PhosphorFill.stethoscope,
    .hospital => PhosphorFill.hospital,
    .veterinary => PhosphorFill.pawPrint,
    .laundry => PhosphorFill.washingMachine,
    .atm => PhosphorFill.money,
    .postOffice => PhosphorFill.envelopeSimple,
    .touristOffice => PhosphorFill.info,
    .recyclingCentre => PhosphorFill.recycle,
    .carRepair => PhosphorFill.wrench,
    .carWash => PhosphorFill.carProfile,
    .motorhomeShop => PhosphorFill.van,
    .outdoorShop => PhosphorFill.backpack,
    .restaurant => PhosphorFill.forkKnife,
    .cafe => PhosphorFill.coffee,
    .fastFood => PhosphorFill.hamburger,
    .viewpoint => PhosphorFill.binoculars,
    .attraction => PhosphorFill.castleTurret,
    .museum => PhosphorFill.bank,
    .bar => PhosphorFill.martini,
    .pub => PhosphorFill.beerStein,
    .iceCream => PhosphorFill.iceCream,
    .deli => PhosphorFill.bowlFood,
    .cheese => PhosphorFill.cheese,
    .seafood => PhosphorFill.fish,
    .pastry => PhosphorFill.cake,
    .confectionery => PhosphorFill.cookie,
    .wineShop => PhosphorFill.wine,
    .beverages => PhosphorFill.beerBottle,
    .teaCoffee => PhosphorFill.coffeeBean,
    .organicShop => PhosphorFill.leaf,
    .frozenFood => PhosphorFill.thermometerCold,
    .winery => PhosphorFill.champagne,
    .brewery => PhosphorFill.pintGlass,
    .distillery => PhosphorFill.brandy,
    .beekeeper => PhosphorFill.jar,
    .dentist => PhosphorFill.tooth,
    .clinic => PhosphorFill.heartbeat,
    .physiotherapist => PhosphorFill.personArmsSpread,
    .laboratory => PhosphorFill.testTube,
    .nurse => PhosphorFill.syringe,
    .midwife => PhosphorFill.baby,
    .podiatrist => PhosphorFill.footprints,
    .psychologist => PhosphorFill.brain,
    .speechTherapist => PhosphorFill.chatCircleDots,
    .alternativeMedicine => PhosphorFill.flowerLotus,
    .optician => PhosphorFill.eyeglasses,
    .hearingAids => PhosphorFill.ear,
    .medicalSupply => PhosphorFill.bandaids,
    .hairdresser => PhosphorFill.scissors,
    .beauty => PhosphorFill.sparkle,
    .massage => PhosphorFill.handPalm,
    .tattoo => PhosphorFill.penNib,
    .bank => PhosphorFill.piggyBank,
    .moneyExchange => PhosphorFill.coins,
    .carRental => PhosphorFill.key,
    .bicycleRental => PhosphorFill.bicycle,
    .boatRental => PhosphorFill.boat,
    .vehicleInspection => PhosphorFill.clipboardText,
    .drivingSchool => PhosphorFill.steeringWheel,
    .dryCleaning => PhosphorFill.shirtFolded,
    .tailor => PhosphorFill.needle,
    .shoeRepair => PhosphorFill.boot,
    .locksmith => PhosphorFill.keyhole,
    .copyshop => PhosphorFill.printer,
    .photographer => PhosphorFill.camera,
    .travelAgency => PhosphorFill.airplaneTilt,
    .estateAgent => PhosphorFill.houseLine,
    .insurance => PhosphorFill.shieldCheck,
    .funeralDirectors => PhosphorFill.flower,
    .petGrooming => PhosphorFill.dog,
    .tyres => PhosphorFill.tire,
    .carParts => PhosphorFill.engine,
    .carDealer => PhosphorFill.car,
    .motorcycleShop => PhosphorFill.motorcycle,
    .repairShop => PhosphorFill.screwdriver,
    .internetCafe => PhosphorFill.desktop,
    .coworking => PhosphorFill.laptop,
    .townhall => PhosphorFill.buildingOffice,
    .police => PhosphorFill.policeCar,
    .library => PhosphorFill.books,
    .rental => PhosphorFill.trolley,
    .storageRental => PhosphorFill.warehouse,
    .animalBoarding => PhosphorFill.cat,
    .ferryTerminal => PhosphorFill.anchor,
    .clothes => PhosphorFill.tShirt,
    .shoes => PhosphorFill.sneaker,
    .accessories => PhosphorFill.handbag,
    .jewellery => PhosphorFill.diamond,
    .books => PhosphorFill.bookOpen,
    .newsagent => PhosphorFill.newspaper,
    .tobacco => PhosphorFill.cigarette,
    .stationery => PhosphorFill.pencil,
    .gift => PhosphorFill.gift,
    .toys => PhosphorFill.puzzlePiece,
    .sports => PhosphorFill.soccerBall,
    .fishingHunting => PhosphorFill.fishSimple,
    .bicycleShop => PhosphorFill.personSimpleBike,
    .boatShop => PhosphorFill.sailboat,
    .florist => PhosphorFill.flowerTulip,
    .gardenCentre => PhosphorFill.pottedPlant,
    .hardware => PhosphorFill.toolbox,
    .home => PhosphorFill.couch,
    .electronics => PhosphorFill.deviceMobile,
    .cosmetics => PhosphorFill.sprayBottle,
    .departmentStore => PhosphorFill.shoppingBagOpen,
    .varietyStore => PhosphorFill.tag,
    .secondHand => PhosphorFill.coatHanger,
    .artShop => PhosphorFill.palette,
    .musicShop => PhosphorFill.musicNotes,
    .petShop => PhosphorFill.bone,
    .babyGoods => PhosphorFill.babyCarriage,
    .fabric => PhosphorFill.yarn,
    .craft => PhosphorFill.hammer,
    .shop => PhosphorFill.shoppingBag,
    .hotel => PhosphorFill.bed,
    .guestHouse => PhosphorFill.houseSimple,
    .hostel => PhosphorFill.buildingApartment,
    .holidayRental => PhosphorFill.house,
    .mountainHut => PhosphorFill.mountains,
    .cinema => PhosphorFill.filmSlate,
    .theatre => PhosphorFill.maskHappy,
    .eventsVenue => PhosphorFill.microphoneStage,
    .artsCentre => PhosphorFill.paintBrush,
    .nightclub => PhosphorFill.discoBall,
    .casino => PhosphorFill.pokerChip,
    .sportsCentre => PhosphorFill.basketball,
    .fitnessCentre => PhosphorFill.barbell,
    .swimmingPool => PhosphorFill.swimmingPool,
    .waterPark => PhosphorFill.waves,
    .golfCourse => PhosphorFill.golf,
    .miniatureGolf => PhosphorFill.flagPennant,
    .marina => PhosphorFill.anchorSimple,
    .horseRiding => PhosphorFill.horse,
    .bowlingAlley => PhosphorFill.bowlingBall,
    .escapeGame => PhosphorFill.lockKey,
    .amusementArcade => PhosphorFill.joystick,
    .iceRink => PhosphorFill.hockey,
    .spa => PhosphorFill.bathtub,
    .dance => PhosphorFill.sneakerMove,
    .park => PhosphorFill.tree,
    .natureReserve => PhosphorFill.butterfly,
    .gallery => PhosphorFill.imageSquare,
    .zoo => PhosphorFill.bird,
    .themePark => PhosphorFill.balloon,
  };

  /// The tone of a category: dark enough for a cream glyph (at least 4.5:1,
  /// `test/unit/contrast_test.dart`), light enough to stand on the night
  /// basemap.
  static Color tone(PoiCategory c) => switch (c) {
    .groceries => const Color(0xFF8A5A2B),
    .vending => const Color(0xFFA03F66),
    .water => const Color(0xFF2E6F9E),
    .fuel => const Color(0xFF5E6326),
    .health => const Color(0xFF2B7556),
    .services => const Color(0xFF5E4F99),
    // A brick orange and an ochre: hues no family of the places takes, and
    // darker than the coral of the alerts and the amber of the selection.
    .food => const Color(0xFFA8441C),
    .sights => const Color(0xFF7E5F0A),
    // The three families the tiles never carry stand on the map only while
    // one of them is open, ringed in amber: a magenta, an indigo and a
    // yellow green, apart from one another and from the tones above.
    .shopping => const Color(0xFF9B3478),
    .lodging => const Color(0xFF3D4E96),
    .leisure => const Color(0xFF4E6B1A),
  };

  /// The grey of the points shown at street zoom with no chip on.
  static const Color quiet = Palette.minuit400;

  /// The scale of the fuel prices, cheapest (green), middle, dearest
  /// (coral): dark enough on the cream of the day, light enough on the
  /// night. The labels on the map and the list of the cheapest share it, so
  /// a colour means the same price in both.
  static (Color, Color, Color) priceScale({required bool dark}) => dark
      ? (const Color(0xFF86D7A6), const Color(0xFFF2E1C3), const Color(0xFFF2998F))
      : (const Color(0xFF1D6B45), const Color(0xFF5A4B12), const Color(0xFFB23A2E));

  /// The colour of a price whose rank among those in view is [rank] (0 the
  /// cheapest, 1 the dearest).
  static Color price(double rank, {required bool dark}) {
    final (cheap, middle, dear) = priceScale(dark: dark);
    final r = rank.clamp(0.0, 1.0);
    return r <= 0.5 ? Color.lerp(cheap, middle, r * 2)! : Color.lerp(middle, dear, r * 2 - 1)!;
  }
}

/// The geometry of a point's pin, in logical pixels: a rounded square on a
/// cream rim with a short tail, smaller than a place's drop. The tail's tip
/// sits at the bottom centre of the image, where the map anchors it.
final class PoiPinGeometry {
  const new({this.quiet = false, this.selected = false});

  final bool quiet;
  final bool selected;

  double get side => selected ? 26 : (quiet ? 15 : 19);
  double get rim => selected ? 2.4 : (quiet ? 1.4 : 1.8);
  double get radius => side * 0.3;
  double get tail => quiet ? 3 : 4.5;
  double get halo => selected ? 6 : 0;
  double get margin => 2 + halo;

  Size get canvas {
    final outer = side + rim * 2;
    return Size((outer + margin * 2).ceilToDouble(), (outer + tail + margin * 2).ceilToDouble());
  }

  /// The centre of the square.
  Offset get center {
    final size = canvas;
    return Offset(size.width / 2, size.height - margin - tail - (side / 2 + rim));
  }
}

/// Paints the pin of [kind] on [canvas], at the logical scale of the canvas.
void paintPoiPin(Canvas canvas, PoiKind kind, {bool quiet = false, bool selected = false}) =>
    _paintPin(
      canvas,
      PoiLook.kind(kind),
      quiet ? PoiLook.quiet : PoiLook.tone(kind.category),
      quiet: quiet,
      selected: selected,
    );

/// Paints the pin of a family, with its glyph: what the map shows of an
/// establishment, whose kinds have no image of their own (the tiles never
/// carry them, and an image per kind would weigh on every map's start).
void paintPoiFamilyPin(Canvas canvas, PoiCategory category, {bool selected = false}) =>
    _paintPin(canvas, PoiLook.family(category), PoiLook.tone(category), selected: selected);

void _paintPin(
  Canvas canvas,
  IconData glyph,
  Color fill, {
  bool quiet = false,
  bool selected = false,
}) {
  final g = PoiPinGeometry(quiet: quiet, selected: selected);
  final c = g.center;
  final outerHalf = g.side / 2 + g.rim;
  final outer = RRect.fromRectAndRadius(
    Rect.fromCenter(center: c, width: outerHalf * 2, height: outerHalf * 2),
    Radius.circular(g.radius + g.rim),
  );
  final inner = RRect.fromRectAndRadius(
    Rect.fromCenter(center: c, width: g.side, height: g.side),
    Radius.circular(g.radius),
  );
  final tip = Offset(c.dx, c.dy + outerHalf + g.tail);
  final tail = Path()
    ..moveTo(c.dx - g.tail * 1.1, c.dy + outerHalf - 1)
    ..lineTo(tip.dx, tip.dy)
    ..lineTo(c.dx + g.tail * 1.1, c.dy + outerHalf - 1)
    ..close();
  final rimColor = selected ? LunaTokens.selection : LunaTokens.pinRim;
  if (selected) {
    canvas.drawRRect(
      outer.inflate(g.halo * 0.8),
      Paint()
        ..color = LunaTokens.selection.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }
  final shadow = Paint()
    ..color = const Color(0x4D061F43)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
  canvas
    ..drawRRect(outer.shift(const Offset(0, 1)), shadow)
    ..drawPath(tail.shift(const Offset(0, 1)), shadow)
    ..drawPath(tail, Paint()..color = rimColor)
    ..drawRRect(outer, Paint()..color = rimColor)
    ..drawRRect(inner, Paint()..color = fill);
  _paintGlyph(canvas, glyph, c, g.side * 0.68, LunaTokens.pinGlyph);
}

/// The size of a category's gathering dot, in logical pixels.
const poiDotSize = Size(22, 22);

/// A category's gathering dot: its tone in a cream ring, with the
/// category's glyph, so dots of two categories never read alike.
void paintPoiDot(Canvas canvas, PoiCategory category) =>
    _paintDot(canvas, category, PoiLook.category(category));

/// The gathering dot of one kind of vending machine shown alone: the
/// category's dot with the kind's glyph (a loaf for bread).
void paintPoiVendingDot(Canvas canvas, PoiKind kind) =>
    _paintDot(canvas, kind.category, PoiLook.kind(kind));

void _paintDot(Canvas canvas, PoiCategory category, IconData glyph) {
  const c = Offset(11, 11);
  canvas
    ..drawCircle(
      c.translate(0, 0.8),
      9.6,
      Paint()
        ..color = const Color(0x4D061F43)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    )
    ..drawCircle(c, 9.6, Paint()..color = LunaTokens.pinRim)
    ..drawCircle(c, 8, Paint()..color = PoiLook.tone(category));
  _paintGlyph(canvas, glyph, c, 10.5, LunaTokens.pinGlyph);
}

void _paintGlyph(Canvas canvas, IconData icon, Offset center, double size, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: size,
        height: 1,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  painter.dispose();
}

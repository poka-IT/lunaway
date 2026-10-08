import 'package:flutter/widgets.dart';
import 'package:lunaway/features/community/domain/community.dart';
import 'package:lunaway/features/navigation/domain/road_events.dart';
import 'package:lunaway/features/places/domain/place_filter.dart';
import 'package:lunaway/features/places/domain/taxonomy.dart';
import 'package:lunaway/shared/theme/phosphor_glyphs.dart';

/// The icons of the app, by meaning: Phosphor (MIT), regular weight in the
/// interface, fill for an active state. The night statuses are drawn moon
/// phases (`shared/icons/luna_icons.dart`), not icons of a set.
abstract final class AppIcons {
  static const IconData map = PhosphorRegular.mapTrifold;
  static const IconData mapSelected = PhosphorFill.mapTrifold;
  static const IconData favorite = PhosphorRegular.heart;
  static const IconData favoriteSelected = PhosphorFill.heart;
  static const IconData profile = PhosphorRegular.user;
  static const IconData profileSelected = PhosphorFill.user;
  static const IconData search = PhosphorRegular.magnifyingGlass;
  static const IconData close = PhosphorRegular.x;
  static const IconData filters = PhosphorRegular.slidersHorizontal;
  static const IconData locate = PhosphorRegular.crosshair;
  static const IconData locateActive = PhosphorFill.crosshair;

  /// Where a route starts, when it is not the device's position.
  static const IconData departure = PhosphorRegular.navigationArrow;
  static const IconData zoomIn = PhosphorRegular.plus;
  static const IconData zoomOut = PhosphorRegular.minus;
  static const IconData list = PhosphorRegular.listBullets;
  static const IconData directions = PhosphorFill.navigationArrow;
  static const IconData share = PhosphorRegular.shareNetwork;
  static const IconData copy = PhosphorRegular.copy;
  static const IconData copied = PhosphorRegular.checkCircle;
  static const IconData more = PhosphorRegular.dotsThree;
  static const IconData moreVertical = PhosphorRegular.dotsThreeVertical;
  static const IconData coordinates = PhosphorRegular.gpsFix;
  static const IconData point = PhosphorFill.mapPin;
  static const IconData town = PhosphorRegular.buildings;
  static const IconData address = PhosphorRegular.mapPin;
  static const IconData street = PhosphorRegular.signpost;
  static const IconData locality = PhosphorRegular.mapPinSimpleLine;
  static const IconData region = PhosphorRegular.globeHemisphereEast;
  static const IconData openExternal = PhosphorRegular.arrowSquareOut;
  static const IconData website = PhosphorRegular.globe;
  static const IconData call = PhosphorRegular.phone;
  static const IconData hours = PhosphorRegular.clock;
  static const IconData pricePerNight = PhosphorRegular.moonStars;
  static const IconData priceServices = PhosphorRegular.drop;
  static const IconData paid = PhosphorRegular.coins;
  static const IconData free = PhosphorRegular.tag;
  static const IconData height = PhosphorRegular.arrowsVertical;
  static const IconData width = PhosphorRegular.arrowsHorizontal;
  static const IconData length = PhosphorRegular.ruler;
  static const IconData weight = PhosphorRegular.scales;
  static const IconData capacity = PhosphorRegular.squaresFour;
  static const IconData classification = PhosphorRegular.sealCheck;
  static const IconData confirmed = PhosphorRegular.sealCheck;
  static const IconData stale = PhosphorRegular.clockCounterClockwise;
  static const IconData star = PhosphorFill.star;
  static const IconData starEmpty = PhosphorRegular.star;
  static const IconData error = PhosphorRegular.warningCircle;
  static const IconData retry = PhosphorRegular.arrowClockwise;
  static const IconData offline = PhosphorRegular.cloudSlash;
  static const IconData gone = PhosphorRegular.mapPinSimpleLine;
  static const IconData download = PhosphorRegular.downloadSimple;
  static const IconData sync = PhosphorRegular.arrowsClockwise;
  static const IconData add = PhosphorRegular.plus;
  static const IconData delete = PhosphorRegular.trash;
  static const IconData rename = PhosphorRegular.pencilSimple;
  static const IconData chevron = PhosphorRegular.caretRight;
  static const IconData previous = PhosphorRegular.caretLeft;
  static const IconData next = PhosphorRegular.caretRight;
  static const IconData sort = PhosphorRegular.sortAscending;
  static const IconData externalSource = PhosphorRegular.usersThree;
  static const IconData chevronDown = PhosphorRegular.caretDown;
  static const IconData back = PhosphorRegular.arrowLeft;
  static const IconData expand = PhosphorRegular.caretDown;
  static const IconData defaultList = PhosphorFill.heart;
  static const IconData customList = PhosphorRegular.bookmarkSimple;
  static const IconData lists = PhosphorRegular.bookmarksSimple;
  static const IconData language = PhosphorRegular.translate;

  /// Translating a review or a description into the reader's language.
  static const IconData translate = PhosphorRegular.translate;
  static const IconData appearance = PhosphorRegular.circleHalf;
  static const IconData themeAuto = PhosphorRegular.sunHorizon;
  static const IconData themeLight = PhosphorRegular.sun;
  static const IconData themeDark = PhosphorRegular.moon;
  static const IconData offlineData = PhosphorRegular.cloudArrowDown;
  static const IconData about = PhosphorRegular.info;
  static const IconData version = PhosphorRegular.tag;
  static const IconData privacy = PhosphorRegular.shieldCheck;
  static const IconData sourceCode = PhosphorRegular.code;
  static const IconData licences = PhosphorRegular.fileText;
  static const IconData attributions = PhosphorRegular.handHeart;
  static const IconData brokenImage = PhosphorRegular.imageBroken;
  static const IconData noImage = PhosphorRegular.image;
  static const IconData photos = PhosphorRegular.images;
  static const IconData vehicle = PhosphorRegular.van;
  static const IconData vehicleFits = PhosphorRegular.van;
  static const IconData check = PhosphorRegular.check;
  static const IconData checkCircle = PhosphorFill.checkCircle;
  static const IconData locationOff = PhosphorRegular.gpsSlash;
  static const IconData settings = PhosphorRegular.gear;
  static const IconData description = PhosphorRegular.textAlignLeft;
  static const IconData reviews = PhosphorRegular.chatsCircle;
  static const IconData sources = PhosphorRegular.stack;
  static const IconData activities = PhosphorRegular.personSimpleHike;
  static const IconData navigationApps = PhosphorRegular.signpost;
  static const IconData inAppNavigation = PhosphorRegular.path;
  static const IconData fuel = PhosphorRegular.gasPump;
  static const IconData reorder = PhosphorRegular.listBullets;
  static const IconData voiceOn = PhosphorRegular.speakerHigh;
  static const IconData voiceOff = PhosphorRegular.speakerSlash;
  static const IconData appleMaps = PhosphorRegular.mapTrifold;
  static const IconData googleMaps = PhosphorRegular.mapPin;
  static const IconData waze = PhosphorRegular.navigationArrow;
  static const IconData osmand = PhosphorRegular.compass;
  static const IconData organicMaps = PhosphorRegular.leaf;
  static const IconData magicEarth = PhosphorRegular.globeHemisphereEast;
  static const IconData osmWeb = PhosphorRegular.globe;
  static const IconData towing = PhosphorRegular.truckTrailer;
  static const IconData closed = PhosphorRegular.prohibit;
  static const IconData calendar = PhosphorRegular.calendarBlank;
  static const IconData openAllYear = PhosphorRegular.calendarCheck;
  static const IconData stayDates = PhosphorRegular.calendarDots;
  static const IconData camera = PhosphorRegular.camera;
  static const IconData addPhoto = PhosphorRegular.cameraPlus;
  static const IconData gallery = PhosphorRegular.images;
  static const IconData pickFile = PhosphorRegular.fileImage;
  static const IconData recoveryCard = PhosphorRegular.key;
  static const IconData qrCode = PhosphorRegular.qrCode;
  static const IconData scan = PhosphorRegular.scan;
  static const IconData signOut = PhosphorRegular.signOut;
  static const IconData device = PhosphorRegular.deviceMobile;
  static const IconData muted = PhosphorRegular.eyeSlash;
  static const IconData contributions = PhosphorRegular.listChecks;
  static const IconData addPlace = PhosphorRegular.mapPinPlus;
  static const IconData uploading = PhosphorRegular.cloudArrowUp;
  static const IconData waiting = PhosphorRegular.clockCountdown;
  static const IconData report = PhosphorRegular.flag;
  static const IconData ferry = PhosphorRegular.boat;
  static const IconData trust = PhosphorRegular.shieldStar;
  static const IconData print = PhosphorRegular.printer;
  static const IconData account = PhosphorRegular.userCircle;
  static const IconData writeReview = PhosphorRegular.notePencil;
  static const IconData toVerify = PhosphorRegular.sealQuestion;
  static const IconData warning = PhosphorRegular.warning;

  /// A road event on a route: a closure, works, lanes closed. The same
  /// glyphs as its badge on the route map.
  static IconData roadEvent(RoadEventClass c) => switch (c) {
    .closure || .detour => PhosphorRegular.barricade,
    .works => PhosphorRegular.wrench,
    .laneRestriction => PhosphorRegular.arrowsMerge,
    .vehicleLimit => PhosphorRegular.arrowsVertical,
  };

  /// A problem met at a place.
  static IconData issue(IssueKind k) => switch (k) {
    .nightBan => PhosphorRegular.prohibit,
    .serviceBroken => PhosphorRegular.wrench,
    .noAccess => PhosphorRegular.barricade,
    .danger => PhosphorRegular.warning,
  };

  /// Why something is reported to the moderators.
  static IconData reportReason(ReportReason r) => switch (r) {
    .spam => PhosphorRegular.megaphone,
    .offensive => PhosphorRegular.smileyAngry,
    .wrong => PhosphorRegular.sealQuestion,
    .privacy => PhosphorRegular.eyeSlash,
    .other => PhosphorRegular.dotsThree,
  };

  /// The glyph of a kind, inside its pin and its avatar.
  static IconData kind(PlaceKind k) => switch (k) {
    .motorhomeArea => PhosphorFill.van,
    .serviceArea => PhosphorFill.drop,
    .campsite => PhosphorFill.tent,
    .parking => PhosphorFill.letterCircleP,
    .nature => PhosphorFill.treeEvergreen,
    .restArea => PhosphorFill.coffee,
    .picnicArea => PhosphorFill.picnicTable,
    .farm => PhosphorFill.barn,
    .homestay => PhosphorFill.houseLine,
    .offRoad => PhosphorFill.jeep,
    .extraService => PhosphorFill.wrench,
  };

  /// The glyph of a family, in the filters.
  static IconData family(KindFamily f) => switch (f) {
    .stopovers => PhosphorFill.van,
    .campsites => PhosphorFill.tent,
    .nature => PhosphorFill.treeEvergreen,
    .services => PhosphorFill.drop,
  };

  static IconData service(Service s) => switch (s) {
    .drinkingWater => PhosphorRegular.drop,
    .greyWater => PhosphorRegular.dropHalfBottom,
    .blackWater => PhosphorRegular.toilet,
    .wasteBin => PhosphorRegular.trash,
    .toilets => PhosphorRegular.toiletPaper,
    .showers => PhosphorRegular.shower,
    .electricity => PhosphorRegular.plug,
    .wifi => PhosphorRegular.wifiHigh,
    .laundry => PhosphorRegular.washingMachine,
    .lpg => PhosphorRegular.gasPump,
    .gasBottles => PhosphorRegular.gasCan,
    .vehicleWash => PhosphorRegular.carSimple,
    .bakery => PhosphorRegular.bread,
    .swimmingPool => PhosphorRegular.swimmingPool,
    .petsAllowed => PhosphorRegular.pawPrint,
    .mobileData => PhosphorRegular.cellSignalHigh,
    .winterCaravanning => PhosphorRegular.snowflake,
  };

  static IconData amenity(Amenity a) => switch (a) {
    .water => service(Service.drinkingWater),
    .dumpStation => service(Service.greyWater),
    .electricity => service(Service.electricity),
    .toilets => service(Service.toilets),
    .showers => service(Service.showers),
    .wasteBin => service(Service.wasteBin),
    .laundry => service(Service.laundry),
    .wifi => service(Service.wifi),
    .lpg => service(Service.lpg),
  };

  static IconData activity(Activity a) => switch (a) {
    .monuments => PhosphorRegular.bank,
    .windsurfKitesurf => PhosphorRegular.wind,
    .mountainBiking => PhosphorRegular.bicycle,
    .hiking => PhosphorRegular.personSimpleHike,
    .climbing => PhosphorRegular.mountains,
    .canoeKayak => PhosphorRegular.waves,
    .fishing => PhosphorRegular.fish,
    .shoreFishing => PhosphorRegular.fishSimple,
    .swimming => PhosphorRegular.personSimpleSwim,
    .motorcycling => PhosphorRegular.motorcycle,
    .viewpoint => PhosphorRegular.binoculars,
    .playground => PhosphorRegular.baby,
  };
}

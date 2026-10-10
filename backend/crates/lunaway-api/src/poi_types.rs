//! The GraphQL types of the points of interest: a point, its open state,
//! what other sources say of it, and the layer's tiles.

use async_graphql::{
    ComplexObject, Context, Enum, InputObject, Object, Result, SimpleObject, dataloader::DataLoader,
};
use chrono::{DateTime, NaiveDate, Utc};
use lunaway_db::pois::{self, PoiRow};
use lunaway_domain::{
    SourceId,
    poi::{FinessEstablishment, FuelStation, OpenState, PostOfficeDays, open_state},
};
use uuid::Uuid;

use crate::{
    community_types::{SourceRating, parse_item_cursor},
    error::{internal, invalid_input},
    external_types::{ExternalPhoto, ExternalReviewConnection},
    loaders::PoiLoader,
    schema::{DB_FIELD_COST, cost, db, state},
    types::{Address, DEFAULT_REVIEWS_PAGE, MAX_REVIEWS_PAGE, OpeningInterval},
};

/// The family of a point of interest, one map chip each.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::poi::PoiCategory", name = "PoiCategory")]
pub enum GqlPoiCategory {
    /// Food shopping: supermarkets, bakeries, markets, farm shops.
    Groceries,
    /// Vending machines selling food: pizza, bread, farm products.
    Vending,
    /// Water and sanitation: drinking water, dump stations, toilets,
    /// showers.
    Water,
    /// Fuel and energy: fuel stations (with LPG), charging, gas bottles.
    Fuel,
    /// Health: pharmacies, doctors, hospitals, vets.
    Health,
    /// Services: laundries, cash machines, post offices, recycling centres,
    /// garages, vehicle washes, motorhome and outdoor shops.
    Services,
    /// Somewhere to eat or drink out: restaurants, cafés, fast food.
    Food,
    /// Something worth a stop: viewpoints, attractions, museums, tourist
    /// offices.
    Sights,
    /// Shops: clothes, books, DIY, florists, electronics. Found by the
    /// search only, never in the map tiles.
    Shopping,
    /// Places to stay: hotels, guest houses, holiday rentals, huts. Found
    /// by the search only.
    Lodging,
    /// Leisure: cinemas, pools, sports, parks, marinas. Found by the search
    /// only.
    Leisure,
}

/// What a point of interest is.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::poi::PoiKind", name = "PoiKind")]
pub enum GqlPoiKind {
    /// A supermarket.
    Supermarket,
    /// A convenience store.
    Convenience,
    /// A bakery.
    Bakery,
    /// A butcher.
    Butcher,
    /// A greengrocer.
    Greengrocer,
    /// Sale at the farm.
    FarmShop,
    /// A market; its days are in its opening hours.
    Marketplace,
    /// A pizza vending machine.
    VendingPizza,
    /// A bread vending machine.
    VendingBread,
    /// A vending machine of farm products.
    VendingFarmProducts,
    /// A vending machine of eggs or milk.
    VendingEggsMilk,
    /// An ice cube vending machine.
    VendingIce,
    /// Another food vending machine.
    VendingOther,
    /// Drinking water.
    DrinkingWater,
    /// A water point to fill a tank.
    WaterPoint,
    /// A dump station.
    DumpStation,
    /// Public toilets.
    Toilets,
    /// Showers.
    Shower,
    /// A fuel station.
    FuelStation,
    /// A charging station for electric vehicles.
    EvCharging,
    /// Gas bottles for sale or exchange.
    GasBottles,
    /// A pharmacy.
    Pharmacy,
    /// A doctor's practice.
    Doctor,
    /// A hospital.
    Hospital,
    /// A vet.
    Veterinary,
    /// A laundry.
    Laundry,
    /// A cash machine.
    Atm,
    /// A post office or a post partner.
    PostOffice,
    /// A tourist office.
    TouristOffice,
    /// A recycling centre (déchèterie).
    RecyclingCentre,
    /// A garage.
    CarRepair,
    /// A vehicle wash.
    CarWash,
    /// A caravan or motorhome dealer and workshop.
    MotorhomeShop,
    /// Camping and outdoor gear.
    OutdoorShop,
    /// A restaurant.
    Restaurant,
    /// A café.
    Cafe,
    /// Fast food.
    FastFood,
    /// A named viewpoint.
    Viewpoint,
    /// A tourist attraction (a monument, a site, a park).
    Attraction,
    /// A museum.
    Museum,
    /// Bar.
    Bar,
    /// Pub.
    Pub,
    /// Ice cream parlour.
    IceCream,
    /// Delicatessen.
    Deli,
    /// Cheese shop.
    Cheese,
    /// Fishmonger.
    Seafood,
    /// Patisserie.
    Pastry,
    /// Sweet shop.
    Confectionery,
    /// Wine shop.
    WineShop,
    /// Drinks shop.
    Beverages,
    /// Tea and coffee.
    TeaCoffee,
    /// Organic shop.
    OrganicShop,
    /// Frozen food.
    FrozenFood,
    /// Winery.
    Winery,
    /// Brewery.
    Brewery,
    /// Distillery.
    Distillery,
    /// Beekeeper.
    Beekeeper,
    /// Dentist.
    Dentist,
    /// Clinic.
    Clinic,
    /// Physiotherapist.
    Physiotherapist,
    /// Medical laboratory.
    Laboratory,
    /// Nurse.
    Nurse,
    /// Midwife.
    Midwife,
    /// Podiatrist.
    Podiatrist,
    /// Psychologist.
    Psychologist,
    /// Speech therapist.
    SpeechTherapist,
    /// Osteopath, alternative medicine.
    AlternativeMedicine,
    /// Optician.
    Optician,
    /// Hearing aids.
    HearingAids,
    /// Medical supplies.
    MedicalSupply,
    /// Hairdresser.
    Hairdresser,
    /// Beauty salon.
    Beauty,
    /// Massage.
    Massage,
    /// Tattoo studio.
    Tattoo,
    /// Bank.
    Bank,
    /// Currency exchange.
    MoneyExchange,
    /// Car hire.
    CarRental,
    /// Bike hire.
    BicycleRental,
    /// Boat hire.
    BoatRental,
    /// MOT test centre.
    VehicleInspection,
    /// Driving school.
    DrivingSchool,
    /// Dry cleaner.
    DryCleaning,
    /// Tailor.
    Tailor,
    /// Shoe repair.
    ShoeRepair,
    /// Locksmith.
    Locksmith,
    /// Print shop.
    Copyshop,
    /// Photographer.
    Photographer,
    /// Travel agent.
    TravelAgency,
    /// Estate agent.
    EstateAgent,
    /// Insurance.
    Insurance,
    /// Funeral directors.
    FuneralDirectors,
    /// Pet grooming.
    PetGrooming,
    /// Tyres.
    Tyres,
    /// Car parts.
    CarParts,
    /// Car dealer.
    CarDealer,
    /// Motorcycle shop.
    MotorcycleShop,
    /// Repair shop.
    RepairShop,
    /// Internet café.
    InternetCafe,
    /// Coworking space.
    Coworking,
    /// Town hall.
    Townhall,
    /// Police.
    Police,
    /// Library.
    Library,
    /// Hire shop.
    Rental,
    /// Self storage.
    StorageRental,
    /// Pet boarding.
    AnimalBoarding,
    /// Ferry terminal.
    FerryTerminal,
    /// Clothes shop.
    Clothes,
    /// Shoe shop.
    Shoes,
    /// Bags and accessories.
    Accessories,
    /// Jewellery.
    Jewellery,
    /// Bookshop.
    Books,
    /// Newsagent.
    Newsagent,
    /// Tobacconist.
    Tobacco,
    /// Stationery.
    Stationery,
    /// Gifts and souvenirs.
    Gift,
    /// Toys and games.
    Toys,
    /// Sports shop.
    Sports,
    /// Fishing and hunting.
    FishingHunting,
    /// Bike shop.
    BicycleShop,
    /// Boat shop.
    BoatShop,
    /// Florist.
    Florist,
    /// Garden centre.
    GardenCentre,
    /// DIY and hardware.
    Hardware,
    /// Home and furniture.
    Home,
    /// Electronics and phones.
    Electronics,
    /// Beauty and toiletries.
    Cosmetics,
    /// Department store, shopping centre.
    DepartmentStore,
    /// Discount store.
    VarietyStore,
    /// Second-hand and antiques.
    SecondHand,
    /// Art and crafts.
    ArtShop,
    /// Music shop.
    MusicShop,
    /// Pet shop.
    PetShop,
    /// Baby shop.
    BabyGoods,
    /// Fabrics and haberdashery.
    Fabric,
    /// Craftsman.
    Craft,
    /// Shop.
    Shop,
    /// Hotel.
    Hotel,
    /// Guest house.
    GuestHouse,
    /// Hostel.
    Hostel,
    /// Holiday rental.
    HolidayRental,
    /// Mountain hut.
    MountainHut,
    /// Cinema.
    Cinema,
    /// Theatre.
    Theatre,
    /// Events venue.
    EventsVenue,
    /// Arts centre.
    ArtsCentre,
    /// Nightclub.
    Nightclub,
    /// Casino.
    Casino,
    /// Sports centre.
    SportsCentre,
    /// Gym.
    FitnessCentre,
    /// Swimming pool.
    SwimmingPool,
    /// Water park.
    WaterPark,
    /// Golf course.
    GolfCourse,
    /// Crazy golf.
    MiniatureGolf,
    /// Marina.
    Marina,
    /// Riding stables.
    HorseRiding,
    /// Bowling alley.
    BowlingAlley,
    /// Escape room.
    EscapeGame,
    /// Arcade.
    AmusementArcade,
    /// Ice rink.
    IceRink,
    /// Spa and sauna.
    Spa,
    /// Dance.
    Dance,
    /// Park.
    Park,
    /// Nature reserve.
    NatureReserve,
    /// Art gallery.
    Gallery,
    /// Zoo, aquarium.
    Zoo,
    /// Theme park.
    ThemePark,
}

/// Whether to book a table or a room, as OpenStreetMap says.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum PoiReservation {
    /// One may book.
    Yes,
    /// One cannot book.
    No,
    /// One must book.
    Required,
    /// Booking is advised.
    Recommended,
    /// By booking only.
    Only,
}

impl PoiReservation {
    fn of(value: &str) -> Option<Self> {
        Some(match value {
            "yes" => Self::Yes,
            "no" => Self::No,
            "required" => Self::Required,
            "recommended" => Self::Recommended,
            "only" => Self::Only,
            _ => return None,
        })
    }
}

/// A fuel of the French price feed, one per group of its columns
/// (`docs/data-sources.md`, "Fuels of the price feed"). The feed prices no
/// AdBlue.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(remote = "lunaway_domain::poi::FuelKind", name = "FuelKind")]
pub enum GqlFuelKind {
    /// Diesel (`gazole` in the feed).
    Diesel,
    /// Unleaded 95 (`sp95`).
    #[graphql(name = "SP95")]
    Sp95,
    /// Unleaded 95 with up to 10 % ethanol (`e10`).
    E10,
    /// Unleaded 98 (`sp98`).
    #[graphql(name = "SP98")]
    Sp98,
    /// Superethanol (`e85`).
    E85,
    /// LPG for vehicles (`gplc`).
    Lpg,
}

/// How a station is out of a fuel.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
#[graphql(
    remote = "lunaway_domain::poi::ShortageKind",
    name = "FuelShortageKind"
)]
pub enum GqlShortageKind {
    /// For now: the station usually sells it.
    Temporary,
    /// For good: the station stopped selling it.
    Definitive,
}

/// Whether a point is open.
#[derive(Enum, Debug, Copy, Clone, Eq, PartialEq)]
pub enum OpenStateKind {
    /// Open now.
    Open,
    /// Closed now.
    Closed,
    /// Nothing known: no hours, hours that do not read, or a time past the
    /// computed window.
    Unknown,
}

/// The state of a point at a time, from its intervals.
#[derive(SimpleObject, Debug, Clone, Copy)]
pub struct OpenNow {
    /// Open, closed or unknown.
    pub state: OpenStateKind,
    /// When an open point closes, within the known window.
    pub closes_at: Option<DateTime<Utc>>,
    /// When a closed point opens next, within the known window.
    pub opens_at: Option<DateTime<Utc>>,
}

impl From<OpenState> for OpenNow {
    fn from(s: OpenState) -> Self {
        match s {
            OpenState::Open { until } => Self {
                state: OpenStateKind::Open,
                closes_at: until,
                opens_at: None,
            },
            OpenState::Closed { opens_at } => Self {
                state: OpenStateKind::Closed,
                closes_at: None,
                opens_at,
            },
            OpenState::Unknown => Self {
                state: OpenStateKind::Unknown,
                closes_at: None,
                opens_at: None,
            },
        }
    }
}

/// A price of the fuel feed.
#[derive(SimpleObject, Debug, Clone)]
pub struct FuelPrice {
    /// The fuel.
    pub fuel: GqlFuelKind,
    /// Euros per litre.
    pub price_eur: f64,
    /// When the station last updated it.
    pub updated_at: DateTime<Utc>,
}

/// A fuel a station is out of.
#[derive(SimpleObject, Debug, Clone)]
pub struct FuelShortage {
    /// The fuel.
    pub fuel: GqlFuelKind,
    /// For now or for good.
    pub kind: GqlShortageKind,
    /// Since when, if the feed says.
    pub since: Option<DateTime<Utc>>,
}

/// What the French fuel price feed says of a station.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(complex)]
pub struct FuelInfo {
    /// Prices, one per fuel sold.
    pub prices: Vec<FuelPrice>,
    /// Fuels it is out of.
    pub shortages: Vec<FuelShortage>,
    /// Whether it sells LPG (it may be out of it for now: see
    /// `shortages`).
    pub sells_lpg: bool,
    /// Services as the feed names them, in French (`Laverie`, `Vente de gaz
    /// domestique (Butane, Propane)`).
    pub services: Vec<String>,
    /// A card machine sells fuel day and night ("automate CB 24/24").
    #[graphql(name = "selfService24h")]
    pub automate_24_24: bool,
    /// On a motorway.
    pub highway: bool,
    /// When Lunaway read the feed (every 15 minutes).
    pub fetched_at: DateTime<Utc>,
    /// `prix-carburants`.
    pub source_id: String,
    /// The station's id in the feed.
    #[graphql(skip)]
    pub(crate) station_ref: String,
}

#[async_graphql::ComplexObject]
impl FuelInfo {
    /// The price of `fuel` over the last days, as Lunaway saw it every
    /// quarter of an hour; null when it saw none.
    #[graphql(complexity = "crate::fuel_types::PRICE_TREND_COST + child_complexity")]
    async fn price_trend(
        &self,
        ctx: &async_graphql::Context<'_>,
        fuel: GqlFuelKind,
    ) -> async_graphql::Result<Option<crate::fuel_types::FuelPriceTrend>> {
        crate::fuel_types::price_trend(ctx, &self.station_ref, fuel.into()).await
    }
}

/// What FINESS says of a health establishment, when it lists it as closed.
#[derive(SimpleObject, Debug, Clone)]
pub struct ClosureReport {
    /// The source (`finess`).
    pub source_id: String,
    /// The closure date it gives.
    pub closed_on: Option<NaiveDate>,
    /// When Lunaway read it.
    pub fetched_at: DateTime<Utc>,
}

/// A source of a point: its own, or one joined to it by an identifier.
#[derive(SimpleObject, Debug, Clone)]
pub struct PoiSourceRef {
    /// The source (`osm`, `community`, `prix-carburants`, `laposte`,
    /// `finess`); its name, licence and attribution are in
    /// `Query.sources`.
    pub source_id: String,
    /// The point's identifier there.
    pub external_id: String,
    /// Its page there, when it has one.
    pub external_url: Option<String>,
    /// When Lunaway read it.
    pub fetched_at: DateTime<Utc>,
}

/// Which source supplied a field of a point.
#[derive(SimpleObject, Debug, Clone)]
pub struct PoiFieldSource {
    /// The field, as in this schema (`openingIntervals`, `fuel`, `lpg`,
    /// `reportedClosed`); `position` stands for `lat` and `lon`.
    pub field: String,
    /// The source of the value shown.
    pub source_id: String,
    /// When that source was read.
    pub fetched_at: DateTime<Utc>,
}

/// A practical point around the places: a shop, a vending machine, water, a
/// fuel station, a pharmacy, a service.
pub struct Poi {
    pub(crate) row: PoiRow,
    /// The time `openNow` answers for by default: the request's.
    pub(crate) now: DateTime<Utc>,
    /// The fuel feed's station, read once from its joined row.
    fuel: Option<(FuelStation, DateTime<Utc>)>,
    /// FINESS's establishment, read once.
    finess: Option<(FinessEstablishment, DateTime<Utc>)>,
    /// La Poste's calendar, read once.
    post: Option<PostOfficeDays>,
}

/// The row with its hours read for the window that starts today where it
/// stands, when it is an establishment: the worker evaluates the hours of
/// the points of the tiles every day (`lunaway_conflate::pois`), not those
/// of the millions of establishments, which are read when served. A
/// window of two weeks of a usual expression takes some tens of
/// microseconds, a page of search results a millisecond. The window a
/// point kept from its days in the tiles is read again: the worker no
/// longer moves it.
fn with_hours(mut row: PoiRow, now: DateTime<Utc>) -> PoiRow {
    if row.in_tiles || row.always_open {
        return row;
    }
    let Some(hours) = row.record.opening_hours.as_deref() else {
        return row;
    };
    let eval = lunaway_conflate::opening::evaluate_at(
        Some(hours),
        row.record.address.country_code.as_deref(),
        row.record.position,
        now,
    );
    row.opening_hours_parsed = eval.parsed;
    row.opening_intervals = eval.intervals;
    row.opening_intervals_until = eval.until;
    if row.opening_intervals.is_some() {
        row.opening_source = Some(row.source_id.clone());
    }
    row
}

/// The joined row of `source`, read into its type; `None` when there is
/// none, or when it does not read (logged: only another writer than the
/// adapters could store such a row).
fn joined<T: serde::de::DeserializeOwned>(
    row: &PoiRow,
    source: &SourceId,
) -> Option<(T, DateTime<Utc>)> {
    let j = row.join(source)?;
    match T::deserialize(&j.data) {
        Ok(v) => Some((v, j.fetched_at)),
        Err(error) => {
            tracing::error!(%error, %source, poi = %row.id, "a joined row does not read");
            None
        }
    }
}

impl Poi {
    pub(crate) fn new(row: PoiRow) -> Self {
        let now = Utc::now();
        Self {
            fuel: joined(&row, &SourceId::FUEL_PRICES),
            finess: joined(&row, &SourceId::FINESS),
            post: joined::<PostOfficeDays>(&row, &SourceId::LAPOSTE).map(|(d, _)| d),
            row: with_hours(row, now),
            now,
        }
    }

    fn fuel_station(&self) -> Option<&(FuelStation, DateTime<Utc>)> {
        self.fuel.as_ref()
    }

    fn finess_entry(&self) -> Option<&(FinessEstablishment, DateTime<Utc>)> {
        self.finess.as_ref()
    }

    /// Whether La Poste's calendar supplies the intervals.
    fn hours_source(&self) -> Option<&SourceId> {
        self.row.opening_source.as_ref()
    }

    /// Whether LPG is sold, and who says: the price feed when the station
    /// is in it (the stations' own declaration, refreshed every few
    /// minutes), the point's own source otherwise.
    fn lpg_said(&self) -> Option<(bool, SourceId)> {
        if let Some((station, _)) = self.fuel_station() {
            return Some((station.tile.lpg, SourceId::FUEL_PRICES));
        }
        self.row.record.lpg.map(|l| (l, self.row.source_id.clone()))
    }
}

#[Object]
impl Poi {
    /// Stable identifier.
    async fn id(&self) -> Uuid {
        self.row.id
    }

    /// Its family.
    async fn category(&self) -> GqlPoiCategory {
        self.row.category().into()
    }

    /// What it is.
    async fn kind(&self) -> GqlPoiKind {
        self.row.record.kind.into()
    }

    /// Its name; null when the source gives none (show the kind instead:
    /// "Distributeur de pizzas").
    async fn name(&self) -> Option<&str> {
        self.row.record.name.as_deref()
    }

    /// Its brand.
    async fn brand(&self) -> Option<&str> {
        self.row.record.brand.as_deref()
    }

    /// Who runs it.
    async fn operator(&self) -> Option<&str> {
        self.row.record.operator.as_deref()
    }

    /// Latitude.
    async fn lat(&self) -> f64 {
        self.row.record.position.lat()
    }

    /// Longitude.
    async fn lon(&self) -> f64 {
        self.row.record.position.lon()
    }

    /// Straight-line distance from the place or point asked about, metres;
    /// null outside `nearbyPois` and a search with `near`.
    async fn distance_m(&self) -> Option<f64> {
        self.row.distance_m.map(|d| d.round())
    }

    /// Its postal address, when the source gives one.
    async fn address(&self) -> Option<Address> {
        let a = &self.row.record.address;
        (a.street.is_some() || a.postcode.is_some() || a.city.is_some()).then(|| Address {
            street: a.street.clone(),
            postcode: a.postcode.clone(),
            city: a.city.clone(),
            country_code: a.country_code.clone(),
        })
    }

    /// Phone number as the source writes it.
    async fn phone(&self) -> Option<&str> {
        self.row.record.phone.as_deref()
    }

    /// Website.
    async fn website(&self) -> Option<&str> {
        self.row.record.website.as_deref()
    }

    /// Opening hours in the OpenStreetMap syntax, as the source wrote them:
    /// shown as text when `openingHoursParsed` is false.
    async fn opening_hours(&self) -> Option<&str> {
        self.row.record.opening_hours.as_deref()
    }

    /// Whether the hours could be read (from the text, or from La Poste's
    /// calendar).
    async fn opening_hours_parsed(&self) -> bool {
        self.row.opening_hours_parsed
    }

    /// Open day and night (`24/7`).
    async fn always_open(&self) -> bool {
        self.row.always_open
    }

    /// Open intervals in UTC over the 14 days from local midnight of the day
    /// they were computed (La Poste's own calendar for a post office that
    /// has one); null when nothing is known. Before
    /// `openingIntervalsUntil`, a time in no interval is closed.
    async fn opening_intervals(&self) -> Option<Vec<OpeningInterval>> {
        self.row
            .opening_intervals
            .as_ref()
            .map(|v| v.iter().map(OpeningInterval::from).collect())
    }

    /// End of the window the intervals cover.
    async fn opening_intervals_until(&self) -> Option<DateTime<Utc>> {
        self.row.opening_intervals_until
    }

    /// Whether it is open at `at` (now by default), and until or from when:
    /// the same reading of the intervals the app makes offline.
    async fn open_now(&self, at: Option<DateTime<Utc>>) -> OpenNow {
        open_state(
            self.row.always_open,
            self.row.opening_intervals.as_deref(),
            self.row.opening_intervals_until,
            at.unwrap_or(self.now),
        )
        .into()
    }

    /// What a vending machine sells, as tagged (`pizza`, `bread`, `eggs`).
    async fn products(&self) -> &[String] {
        &self.row.record.products
    }

    /// Payment methods accepted (`cash`, `cards`, `contactless`).
    async fn payment(&self) -> &[String] {
        &self.row.record.payment
    }

    /// Fuels sold, as OpenStreetMap names them (`diesel`, `e10`, `lpg`).
    async fn fuels(&self) -> &[String] {
        &self.row.record.fuels
    }

    /// Whether LPG is sold, from the price feed when the station is in it,
    /// from OpenStreetMap otherwise; null when nobody says.
    async fn lpg(&self) -> Option<bool> {
        self.lpg_said().map(|(l, _)| l)
    }

    /// What the French fuel price feed says of the station.
    async fn fuel(&self) -> Option<FuelInfo> {
        let (s, fetched_at) = self.fuel_station()?;
        let fetched_at = *fetched_at;
        let station_ref = self.row.join(&SourceId::FUEL_PRICES)?.key.clone();
        Some(FuelInfo {
            station_ref,
            // What the importer read with the feed's clock, as the map.
            sells_lpg: s.tile.lpg,
            prices: s
                .prices
                .iter()
                .map(|p| FuelPrice {
                    fuel: p.fuel.into(),
                    price_eur: p.price_eur,
                    updated_at: p.updated_at,
                })
                .collect(),
            shortages: s
                .shortages
                .iter()
                .map(|x| FuelShortage {
                    fuel: x.fuel.into(),
                    kind: x.kind.into(),
                    since: x.since,
                })
                .collect(),
            services: s.services.clone(),
            automate_24_24: s.automate_24_24,
            highway: s.highway,
            fetched_at,
            source_id: SourceId::FUEL_PRICES.to_string(),
        })
    }

    /// Set when FINESS lists the establishment as closed: show it as
    /// "maybe closed" (a pharmacy that changed owner may get a new number).
    async fn reported_closed(&self) -> Option<ClosureReport> {
        let (e, fetched_at) = self.finess_entry()?;
        (!e.open).then(|| ClosureReport {
            source_id: SourceId::FINESS.to_string(),
            closed_on: e.closed_on,
            fetched_at: *fetched_at,
        })
    }

    /// Self-service.
    async fn self_service(&self) -> Option<bool> {
        self.row.record.self_service
    }

    /// Whether it charges a fee.
    async fn fee(&self) -> Option<bool> {
        self.row.record.fee
    }

    /// Open only part of the year (a fountain cut off in winter).
    async fn seasonal(&self) -> Option<bool> {
        self.row.record.seasonal
    }

    /// A hospital or a clinic with an emergency department.
    async fn emergency(&self) -> Option<bool> {
        self.row.record.emergency
    }

    /// Whether the map tiles carry it: false for an establishment the
    /// search alone finds (a hairdresser, a hotel), which the app draws
    /// itself when it shows one.
    async fn in_tiles(&self) -> bool {
        self.row.in_tiles
    }

    /// What it cooks, as OpenStreetMap names it, lower case (`pizza`,
    /// `italian`, `regional`), six at most.
    async fn cuisine(&self) -> &[String] {
        &self.row.record.cuisine
    }

    /// The diets it caters for (`vegetarian`, `vegan`, `gluten_free`,
    /// `halal`, `kosher`, `lactose_free`), as OpenStreetMap says.
    async fn diets(&self) -> &[String] {
        &self.row.record.diets
    }

    /// Food to take away; null when the source says nothing.
    async fn takeaway(&self) -> Option<bool> {
        self.row.record.takeaway
    }

    /// Delivery; null when the source says nothing.
    async fn delivery(&self) -> Option<bool> {
        self.row.record.delivery
    }

    /// Tables outside; null when the source says nothing.
    async fn outdoor_seating(&self) -> Option<bool> {
        self.row.record.outdoor_seating
    }

    /// Whether to book; null when the source says nothing.
    async fn reservation(&self) -> Option<PoiReservation> {
        self.row
            .record
            .reservation
            .as_deref()
            .and_then(PoiReservation::of)
    }

    /// A hotel's stars, 1 to 5, as OpenStreetMap says.
    async fn stars(&self) -> Option<i32> {
        self.row.record.stars.map(i32::from)
    }

    /// Internet access for the customers (Wi-Fi or a terminal); null when
    /// the source says nothing.
    async fn internet_access(&self) -> Option<bool> {
        self.row.record.internet_access
    }

    /// What a garage works on, as OpenStreetMap names it (`tyres`,
    /// `brakes`, `glass`, `air_conditioning`), twelve at most.
    async fn vehicle_services(&self) -> &[String] {
        &self.row.record.vehicle_services
    }

    /// Whether motorhomes may use it (a vehicle wash, a garage), as
    /// OpenStreetMap says; null when it says nothing, which is not a no.
    async fn motorhome(&self) -> Option<bool> {
        self.row.record.motorhome
    }

    /// Whether heavy goods vehicles may use it (a vehicle wash), as
    /// OpenStreetMap says; null when it says nothing.
    async fn hgv(&self) -> Option<bool> {
        self.row.record.hgv
    }

    /// The highest vehicle it takes, metres (a wash's gantry), as
    /// OpenStreetMap says.
    async fn max_height_m(&self) -> Option<f64> {
        self.row.record.max_height_m
    }

    /// Wheelchair access as OpenStreetMap says it (`yes`, `limited`, `no`).
    async fn wheelchair(&self) -> Option<&str> {
        self.row.record.wheelchair.as_deref()
    }

    /// The last date someone checked it on the ground (OpenStreetMap's
    /// `check_date`).
    async fn checked_on(&self) -> Option<NaiveDate> {
        self.row.record.check_date
    }

    /// The last time a Lunaway user said it is still there.
    async fn last_confirmed_at(&self) -> Option<DateTime<Utc>> {
        self.row.last_confirmed_at
    }

    /// Its own source first, then the sources joined to it.
    async fn sources(&self) -> Vec<PoiSourceRef> {
        let mut out = vec![PoiSourceRef {
            source_id: self.row.source_id.to_string(),
            external_id: self.row.external_id.clone(),
            external_url: self.row.external_url.clone(),
            fetched_at: self.row.fetched_at,
        }];
        out.extend(self.row.joins.iter().map(|j| PoiSourceRef {
            source_id: j.source_id.to_string(),
            external_id: j.key.clone(),
            external_url: None,
            fetched_at: j.fetched_at,
        }));
        out
    }

    /// For each field shown, the source that supplied it.
    async fn provenance(&self) -> Vec<PoiFieldSource> {
        let own = |field: &str| PoiFieldSource {
            field: field.to_owned(),
            source_id: self.row.source_id.to_string(),
            fetched_at: self.row.fetched_at,
        };
        let joined = |field: &str, source: &SourceId| {
            self.row.join(source).map(|j| PoiFieldSource {
                field: field.to_owned(),
                source_id: source.to_string(),
                fetched_at: j.fetched_at,
            })
        };
        let mut out = vec![own("kind"), own("position")];
        let r = &self.row.record;
        for (field, present) in [
            ("name", r.name.is_some()),
            ("brand", r.brand.is_some()),
            ("operator", r.operator.is_some()),
            ("address", !r.address.is_empty()),
            ("phone", r.phone.is_some()),
            ("website", r.website.is_some()),
            ("openingHours", r.opening_hours.is_some()),
            ("products", !r.products.is_empty()),
            ("payment", !r.payment.is_empty()),
            ("fuels", !r.fuels.is_empty()),
        ] {
            if present {
                out.push(own(field));
            }
        }
        match self.hours_source() {
            Some(s) if *s == SourceId::LAPOSTE => {
                out.extend(joined("openingIntervals", &SourceId::LAPOSTE));
            }
            Some(_) => out.push(own("openingIntervals")),
            None => {}
        }
        if let Some((_, source)) = self.lpg_said() {
            if source == SourceId::FUEL_PRICES {
                out.extend(joined("lpg", &SourceId::FUEL_PRICES));
            } else {
                out.push(own("lpg"));
            }
        }
        out.extend(joined("fuel", &SourceId::FUEL_PRICES));
        if self.finess_entry().is_some_and(|(e, _)| !e.open) {
            out.extend(joined("reportedClosed", &SourceId::FINESS));
        }
        out
    }

    /// Whether the point takes ratings and reviews (`ratePoi`,
    /// `reviewPoi`): every kind but a care practitioner's practice (doctor,
    /// dentist, nurse, midwife, therapist), whose review would say a
    /// patient's health under a public licence. Its card offers neither.
    async fn takes_reviews(&self) -> bool {
        lunaway_domain::content::poi_takes_reviews(self.row.record.kind)
    }

    /// La Poste's kind of site (`Bureau de Poste`, `Relais poste`,
    /// `Agence postale communale`), for a post office in its calendar.
    async fn post_office_kind(&self) -> Option<&str> {
        self.post.as_ref()?.kind.as_deref()
    }

    /// Ratings by source: Lunaway users' under `community-cc-by` (CC BY
    /// 4.0, with their reviews); empty while nobody rated the point. A list
    /// of points asking for it costs one query. Empty for a care practice
    /// (`takesReviews` false).
    async fn ratings(
        &self,
        ctx: &Context<'_>,
    ) -> Result<Vec<crate::community_types::SourceRating>> {
        // A point retagged as a care practice keeps no rating it took before.
        if !lunaway_domain::content::poi_takes_reviews(self.row.record.kind) {
            return Ok(Vec::new());
        }
        crate::poi_review_types::ratings(ctx, self.row.id).await
    }

    /// The published reviews with text, newest first (50 per page at most),
    /// without the authors the caller muted. Read per point. Empty for a
    /// care practice (`takesReviews` false).
    #[graphql(
        complexity = "crate::schema::cost(first, crate::poi_review_types::DEFAULT_POI_REVIEWS_PAGE, child_complexity)"
    )]
    async fn reviews(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 20)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<crate::poi_review_types::PoiReviewConnection> {
        if !lunaway_domain::content::poi_takes_reviews(self.row.record.kind) {
            return Ok(crate::poi_review_types::PoiReviewConnection {
                nodes: Vec::new(),
                end_cursor: None,
                has_next_page: false,
                total_count: 0,
            });
        }
        crate::poi_review_types::reviews(ctx, self.row.id, first, after).await
    }

    /// The caller's own rating or review of the point, whatever its
    /// status; null when anonymous or when there is none.
    #[graphql(complexity = "crate::schema::DB_FIELD_COST + child_complexity")]
    async fn my_review(
        &self,
        ctx: &Context<'_>,
    ) -> Result<Option<crate::poi_review_types::PoiReview>> {
        crate::poi_review_types::my_review(ctx, self.row.id).await
    }

    /// The reviews with text of other sources than Lunaway's community, the
    /// open reviews of Mangrove that give the point's name (with their
    /// licence and a link), newest first, 50 per page at most, as
    /// `Place.externalReviews`. Read per point when its card opens: the
    /// tiles never carry them. A hidden source shows nothing; neither does
    /// an item an operator or the reports hid.
    #[graphql(complexity = "cost(first, DEFAULT_REVIEWS_PAGE, child_complexity)")]
    async fn external_reviews(
        &self,
        ctx: &Context<'_>,
        #[graphql(default = 20)] first: Option<i32>,
        after: Option<String>,
    ) -> Result<ExternalReviewConnection> {
        let first = first.unwrap_or(DEFAULT_REVIEWS_PAGE);
        if !(1..=MAX_REVIEWS_PAGE).contains(&first) {
            return Err(invalid_input(format!(
                "first must be between 1 and {MAX_REVIEWS_PAGE}"
            )));
        }
        let after = parse_item_cursor(after.as_deref())?;
        let (pool, _permit) = db(ctx).await?;
        let open = lunaway_db::content::reviews_of_poi(pool, self.row.id, i64::from(first), after)
            .await
            .map_err(|e| internal(&e))?;
        // The language of each review its source did not label is guessed
        // from its words: up to 50 guesses, off the request's thread.
        let first = usize::try_from(first).unwrap_or(0);
        tokio::task::spawn_blocking(move || ExternalReviewConnection::open_only(open, first))
            .await
            .map_err(|e| internal(&e))
    }

    /// What other sources say of the point's ratings as a whole, by source:
    /// the mean of Mangrove's ratings. Read per point, like
    /// `externalReviews`; empty while a source is hidden.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn external_ratings(&self, ctx: &Context<'_>) -> Result<Vec<SourceRating>> {
        let (pool, _permit) = db(ctx).await?;
        Ok(lunaway_db::content::ratings_of_poi(pool, self.row.id)
            .await
            .map_err(|e| internal(&e))?
            .into_iter()
            .map(|r| SourceRating {
                source_id: r.source_id,
                average: r.average,
                count: r.count,
            })
            .collect())
    }

    /// The photos of open sources the point's own OpenStreetMap tags name
    /// (its Wikimedia Commons file or category, the image of its Wikidata
    /// item, its Panoramax picture), served from Lunaway's host, four at
    /// most, each with its source's id and label, its author, its licence
    /// and a link to its page. Read per point, like `externalReviews`.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn external_photos(&self, ctx: &Context<'_>) -> Result<Vec<ExternalPhoto>> {
        let (pool, _permit) = db(ctx).await?;
        let most = i64::try_from(lunaway_domain::content::MAX_PHOTOS_PER_POI).unwrap_or(i64::MAX);
        let rows = lunaway_db::content::photos_of_poi(pool, self.row.id, most)
            .await
            .map_err(|e| internal(&e))?;
        let media = &state(ctx).config.media;
        Ok(rows
            .into_iter()
            .map(|r| ExternalPhoto::from_content(r, media))
            .collect())
    }
}

/// The points nearest a place, for one category.
#[derive(SimpleObject)]
pub struct NearbyPois {
    /// The category.
    pub category: GqlPoiCategory,
    /// How far the search looked, metres.
    pub radius_m: f64,
    /// The nearest points, nearest first; empty when none is within
    /// `radiusM`.
    pub pois: Vec<Poi>,
}

/// One page of the points of an area.
#[derive(SimpleObject)]
pub struct PoiConnection {
    /// The points, by id.
    pub nodes: Vec<Poi>,
    /// Pass it as `after` for the next page.
    pub end_cursor: Option<String>,
    /// Whether another page follows.
    pub has_next_page: bool,
}

/// A category and its kinds, in display order.
#[derive(SimpleObject, Debug, Clone)]
pub struct PoiCategoryInfo {
    /// The category.
    pub category: GqlPoiCategory,
    /// Its kinds.
    pub kinds: Vec<GqlPoiKind>,
    /// How far `nearbyPois` looks for it by default, metres.
    pub default_radius_m: f64,
}

/// The map layer of the points of interest: vector tiles at
/// `tilesUrl` (a TileJSON at `tileJsonUrl`).
#[derive(SimpleObject, Debug, Clone)]
pub struct PoiLayer {
    /// Increases with every change of what a tile shows; part of the tile
    /// URLs, so a tile is cached for good.
    pub version: i64,
    /// When the layer last changed.
    pub updated_at: DateTime<Utc>,
    /// The tile URL template (`{z}/{x}/{y}`).
    pub tiles_url: String,
    /// The TileJSON, which names the current tiles: what a map style points
    /// at.
    pub tile_json_url: String,
    /// Lowest zoom served: clusters per category and grid cell below
    /// `pointMinZoom` (layer `poi_clusters`, properties `category`,
    /// `count`), and the food vending machines per kind (layer
    /// `poi_vending_clusters`, properties `kind`, `count`).
    pub min_zoom: i32,
    /// Zoom from which every point is in the tiles: in the default tiles,
    /// layer `pois` for the kinds the first apps knew and `pois_more` for
    /// those added since (`OUTDOOR_SHOP`), the categories `FOOD` and
    /// `SIGHTS` left out; in the tiles of every category
    /// (`/poi/all/tiles.json`), every point in `pois`.
    pub point_min_zoom: i32,
    /// Highest zoom served; the map draws the tiles of this zoom beyond.
    pub max_zoom: i32,
    /// Text to show on the map with the layer.
    pub attribution: String,
}

/// A vending machine a user adds: where it stands and what it sells.
#[derive(InputObject, Debug, Clone)]
pub struct NewVendingMachineInput {
    /// Latitude, degrees.
    pub lat: f64,
    /// Longitude, degrees.
    pub lon: f64,
    /// A vending kind (`VENDING_PIZZA`, `VENDING_BREAD`, ...).
    pub kind: GqlPoiKind,
    /// Its name, if it shows one.
    pub name: Option<String>,
    /// Who runs it.
    pub operator: Option<String>,
    /// Its brand.
    pub brand: Option<String>,
    /// What else it sells, as OpenStreetMap's `vending` values (`pizza`,
    /// `bread`, `eggs`, `cheese`, `ice_cubes`).
    pub products: Option<Vec<String>>,
    /// Payment methods (`cash`, `coins`, `notes`, `cards`, `contactless`,
    /// `app`).
    pub payment: Option<Vec<String>>,
    /// Open day and night, as most machines are.
    pub always_open: Option<bool>,
}

/// A "still there?" answer about a point.
#[derive(SimpleObject, Debug, Clone)]
#[graphql(complex)]
pub struct PoiConfirmation {
    /// Stable identifier.
    pub id: Uuid,
    /// The point.
    pub poi_id: Uuid,
    /// The answer.
    pub still_there: bool,
    /// When.
    pub created_at: DateTime<Utc>,
}

#[ComplexObject]
impl PoiConfirmation {
    /// The point, as `poi(id)` serves it: null once it is gone, or while
    /// it is hidden.
    async fn poi(&self, ctx: &Context<'_>) -> Result<Option<Poi>> {
        let row = match ctx.data_opt::<DataLoader<PoiLoader>>() {
            Some(loader) => loader
                .load_one(self.poi_id)
                .await
                .map_err(|e| internal(e.as_ref()))?,
            None => {
                let (pool, _permit) = db(ctx).await?;
                pois::by_id(pool, self.poi_id)
                    .await
                    .map_err(|e| internal(&e))?
            }
        };
        Ok(row.map(Poi::new))
    }
}

impl From<pois::PoiConfirmationRow> for PoiConfirmation {
    fn from(r: pois::PoiConfirmationRow) -> Self {
        Self {
            id: r.id,
            poi_id: r.poi_id,
            still_there: r.still_there,
            created_at: r.created_at,
        }
    }
}

/// A page of the account's "still there?" answers about points, newest
/// first.
#[derive(SimpleObject)]
pub struct PoiConfirmationConnection {
    /// The answers.
    pub nodes: Vec<PoiConfirmation>,
    /// Pass it as `after` for the next page.
    pub end_cursor: Option<String>,
    /// Whether more follow.
    pub has_next_page: bool,
    /// Answers in the whole list.
    pub total_count: i32,
}

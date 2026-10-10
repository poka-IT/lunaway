//! Which kind of point an Overture place is, from its taxonomy
//! (`taxonomy.hierarchy`, from the top: `food_and_drink`, `restaurant`,
//! `european_restaurant`, `french_restaurant`).
//!
//! The table names the nodes Lunaway reads; a place takes the first node
//! of its hierarchy, from the leaf up, that the table names. A node mapped
//! to a kind brings its whole subtree along (every cuisine of
//! `restaurant` is a restaurant), unless a node below it is named too. A
//! node mapped to `None` drops its subtree, a decision written in the
//! table; a place whose hierarchy meets no node of the table has no kind
//! and is dropped as well. Built from the taxonomy of the release
//! 2026-09-23.1 (every path of one file, counted at confidence 0.9), to
//! the kinds of `lunaway_domain::poi` and only them.
//!
//! Left out on purpose, with their subtree:
//!
//! - what Lunaway reads from an official register, which is the reference
//!   for it: fuel stations and charging points (the fuel price feed),
//!   pharmacies (FINESS), post offices (La Poste);
//! - campsites and motorhome areas: places, which the conflation merges,
//!   never points of interest;
//! - the trades and services that come to the customer, whose address is
//!   often a home: stylists, make-up artists, caterers, photographers,
//!   locksmiths (in France, also many fake "emergency" listings), IT
//!   repair, fitness and golf instructors, and the practitioners who
//!   mostly visit or receive at home (nurses, midwives, masseurs,
//!   counsellors, hypnotherapists, pet sitters); and the holiday homes,
//!   cottages and cabins, which are private houses;
//! - nodes too broad to say what a place is (`food_and_beverage_store`,
//!   `specialty_store`, `professional_service`), and the markets of farmers
//!   (a market or a farm shop: the name does not tell).

use lunaway_domain::poi::PoiKind;

/// The taxonomy nodes Lunaway reads, sorted by name (a test holds them so):
/// the kind of their subtree, or `None` to drop it.
pub const TABLE: &[(&str, Option<PoiKind>)] = &[
    ("abuse_and_addiction_treatment_center", None),
    ("amusement_park", Some(PoiKind::ThemePark)),
    ("animal_hospital", Some(PoiKind::Veterinary)),
    ("antique_store", Some(PoiKind::SecondHand)),
    ("appliance_store", Some(PoiKind::Electronics)),
    ("aquarium", Some(PoiKind::Zoo)),
    ("arcade", Some(PoiKind::AmusementArcade)),
    ("art_gallery", Some(PoiKind::Gallery)),
    ("art_supply_store", Some(PoiKind::ArtShop)),
    ("arts_crafts_and_hobby_store", Some(PoiKind::ArtShop)),
    ("atm", Some(PoiKind::Atm)),
    ("audiology", Some(PoiKind::HearingAids)),
    ("auto_body_shop", Some(PoiKind::CarRepair)),
    ("auto_broker", None),
    ("auto_dealer", Some(PoiKind::CarDealer)),
    ("auto_glass_service", Some(PoiKind::CarRepair)),
    ("auto_leasing", None),
    ("auto_parts_store", Some(PoiKind::CarParts)),
    ("auto_restoration_service", Some(PoiKind::CarRepair)),
    ("automobile_registration_service", None),
    ("automotive_repair", Some(PoiKind::CarRepair)),
    ("baby_gear_and_nursery_store", Some(PoiKind::BabyGoods)),
    ("bagel_shop", Some(PoiKind::FastFood)),
    ("bakery", Some(PoiKind::Bakery)),
    ("bank", Some(PoiKind::Bank)),
    ("bank_or_credit_union", Some(PoiKind::Bank)),
    ("bar", Some(PoiKind::Bar)),
    ("barber", Some(PoiKind::Hairdresser)),
    ("beach_equipment_rental", Some(PoiKind::Rental)),
    ("beauty_salon", Some(PoiKind::Beauty)),
    ("beauty_supply_store", Some(PoiKind::Cosmetics)),
    ("bed_and_breakfast", Some(PoiKind::GuestHouse)),
    ("bedding_and_bath_store", Some(PoiKind::Home)),
    ("beer_garden", Some(PoiKind::Pub)),
    ("beer_wine_spirits_store", Some(PoiKind::WineShop)),
    ("bike_rental", Some(PoiKind::BicycleRental)),
    ("bike_repair_maintenance", Some(PoiKind::BicycleShop)),
    ("bike_store", Some(PoiKind::BicycleShop)),
    ("blood_and_plasma_donation_center", Some(PoiKind::Clinic)),
    ("boat_dealer", Some(PoiKind::BoatShop)),
    ("boat_parts_store", Some(PoiKind::BoatShop)),
    ("boat_rental_and_training", Some(PoiKind::BoatRental)),
    ("bookstore", Some(PoiKind::Books)),
    ("bowling_alley", Some(PoiKind::BowlingAlley)),
    ("boxing_class", Some(PoiKind::FitnessCentre)),
    ("brewery", Some(PoiKind::Brewery)),
    ("bubble_tea_shop", Some(PoiKind::Cafe)),
    ("building_supply_store", Some(PoiKind::Hardware)),
    ("butcher_shop", Some(PoiKind::Butcher)),
    ("cabin", None),
    ("cafe", Some(PoiKind::Cafe)),
    ("campground", None),
    ("candle_store", Some(PoiKind::Home)),
    ("candy_store", Some(PoiKind::Confectionery)),
    ("canoe_and_kayak_hire_service", Some(PoiKind::BoatRental)),
    ("car_inspection", Some(PoiKind::VehicleInspection)),
    ("car_rental_service", Some(PoiKind::CarRental)),
    ("car_wash", Some(PoiKind::CarWash)),
    ("car_window_tinting", None),
    ("cards_and_stationery_store", Some(PoiKind::Stationery)),
    ("carpet_store", Some(PoiKind::Home)),
    ("casino", Some(PoiKind::Casino)),
    ("caterer", None),
    ("cheese_shop", Some(PoiKind::Cheese)),
    ("chocolatier", Some(PoiKind::Confectionery)),
    ("clothing_store", Some(PoiKind::Clothes)),
    ("coffee_shop", Some(PoiKind::Cafe)),
    ("comedy_club", Some(PoiKind::Theatre)),
    ("commercial_printer", None),
    (
        "complementary_and_alternative_medicine",
        Some(PoiKind::AlternativeMedicine),
    ),
    ("convenience_store", Some(PoiKind::Convenience)),
    ("costume_store", Some(PoiKind::Shop)),
    ("cottage", None),
    ("counseling", None),
    ("coworking_space", Some(PoiKind::Coworking)),
    ("craft_store", Some(PoiKind::ArtShop)),
    ("credit_union", Some(PoiKind::Bank)),
    ("cricket_ground", None),
    ("cultural_center", Some(PoiKind::ArtsCentre)),
    ("currency_exchange", Some(PoiKind::MoneyExchange)),
    ("cycling_class", Some(PoiKind::FitnessCentre)),
    ("dairy_store", Some(PoiKind::Cheese)),
    ("dance_club", Some(PoiKind::Nightclub)),
    ("dance_studio", Some(PoiKind::Dance)),
    ("delicatessen", Some(PoiKind::Deli)),
    ("dental_clinic", Some(PoiKind::Dentist)),
    ("dental_supply_store", None),
    ("department_store", Some(PoiKind::DepartmentStore)),
    ("diagnostic_imaging", Some(PoiKind::Laboratory)),
    ("dialysis_clinic", Some(PoiKind::Clinic)),
    ("diner", Some(PoiKind::Restaurant)),
    ("discount_store", Some(PoiKind::VarietyStore)),
    ("distillery", Some(PoiKind::Distillery)),
    ("do_it_yourself_store", Some(PoiKind::Hardware)),
    ("doctors_office", Some(PoiKind::Doctor)),
    ("driving_school", Some(PoiKind::DrivingSchool)),
    ("drugstore", Some(PoiKind::Cosmetics)),
    ("dry_cleaning", Some(PoiKind::DryCleaning)),
    ("electrical_supply_store", Some(PoiKind::Hardware)),
    ("electronics_repair_shop", Some(PoiKind::RepairShop)),
    ("electronics_store", Some(PoiKind::Electronics)),
    ("embroidery_and_crochet_store", Some(PoiKind::Fabric)),
    ("emergency_department", Some(PoiKind::Hospital)),
    ("emergency_pet_hospital", Some(PoiKind::Veterinary)),
    ("emissions_inspection", Some(PoiKind::VehicleInspection)),
    ("escape_room", Some(PoiKind::EscapeGame)),
    ("ethical_grocery_store", Some(PoiKind::OrganicShop)),
    ("ev_charging_station", None),
    ("event_photography_service", None),
    ("event_venue", Some(PoiKind::EventsVenue)),
    ("eyelash_service", Some(PoiKind::Beauty)),
    ("eyewear_store", Some(PoiKind::Optician)),
    ("fabric_store", Some(PoiKind::Fabric)),
    ("farmers_market", None),
    ("fashion_accessories_store", Some(PoiKind::Accessories)),
    ("fashion_and_apparel_store", Some(PoiKind::Clothes)),
    ("fashion_boutique", Some(PoiKind::Clothes)),
    ("fast_food_restaurant", Some(PoiKind::FastFood)),
    ("fertility_clinic", Some(PoiKind::Clinic)),
    ("fishmonger", Some(PoiKind::Seafood)),
    ("fitness_studio", Some(PoiKind::FitnessCentre)),
    ("fitness_trainer", None),
    ("flea_market", None),
    ("flooring_store", Some(PoiKind::Home)),
    ("florist", Some(PoiKind::Florist)),
    ("flowers_and_gifts_store", Some(PoiKind::Florist)),
    ("fondue_restaurant", Some(PoiKind::Restaurant)),
    ("food_truck_stand", None),
    ("framing_store", Some(PoiKind::ArtShop)),
    ("frozen_foods_store", Some(PoiKind::FrozenFood)),
    ("frozen_yogurt_shop", Some(PoiKind::IceCream)),
    ("funeral_service", Some(PoiKind::FuneralDirectors)),
    ("furniture_accessory_store", Some(PoiKind::Home)),
    ("furniture_store", Some(PoiKind::Home)),
    ("gas_station", None),
    ("gastropub", Some(PoiKind::Pub)),
    ("gelato_shop", Some(PoiKind::IceCream)),
    ("gift_shop", Some(PoiKind::Gift)),
    ("glass_blowing_venue", Some(PoiKind::Craft)),
    ("golf_course", Some(PoiKind::GolfCourse)),
    ("golf_instructor", None),
    ("grocery_store", Some(PoiKind::Supermarket)),
    ("guest_house", Some(PoiKind::GuestHouse)),
    ("gun_and_ammo_store", Some(PoiKind::FishingHunting)),
    ("gym", Some(PoiKind::FitnessCentre)),
    ("gymnastics_center", Some(PoiKind::SportsCentre)),
    ("hair_removal", Some(PoiKind::Beauty)),
    ("hair_salon", Some(PoiKind::Hairdresser)),
    ("hair_stylist", None),
    ("hardware_home_and_garden_store", Some(PoiKind::Hardware)),
    ("hardware_store", Some(PoiKind::Hardware)),
    ("health_food_store", Some(PoiKind::OrganicShop)),
    ("hearing_aid_store", Some(PoiKind::HearingAids)),
    ("herb_and_spice_store", Some(PoiKind::Deli)),
    ("hobby_shop", Some(PoiKind::Toys)),
    ("holiday_rental_home", None),
    ("home_decor_store", Some(PoiKind::Home)),
    ("home_goods_store", Some(PoiKind::Home)),
    ("home_health_care", None),
    ("home_improvement_store", Some(PoiKind::Hardware)),
    ("horse_riding", Some(PoiKind::HorseRiding)),
    ("horseback_riding_service", Some(PoiKind::HorseRiding)),
    ("hospital", Some(PoiKind::Hospital)),
    ("hostel", Some(PoiKind::Hostel)),
    ("hotel", Some(PoiKind::Hotel)),
    ("hunting_and_fishing_store", Some(PoiKind::FishingHunting)),
    ("hypnotherapy", None),
    ("ice_cream_shop", Some(PoiKind::IceCream)),
    ("ice_skating_rink", Some(PoiKind::IceRink)),
    ("inn", Some(PoiKind::Hotel)),
    ("insurance_agency", Some(PoiKind::Insurance)),
    ("international_grocery_store", None),
    ("internet_cafe", Some(PoiKind::InternetCafe)),
    ("it_service_and_computer_repair", None),
    ("jet_skis_rental", Some(PoiKind::BoatRental)),
    ("jewelry_store", Some(PoiKind::Jewellery)),
    ("junkyard", None),
    ("karaoke_venue", Some(PoiKind::Bar)),
    ("key_and_locksmith", None),
    ("kitchen_and_bath_store", Some(PoiKind::Home)),
    ("knitting_supply_store", Some(PoiKind::Fabric)),
    ("korean_grocery_store", None),
    ("laboratory_testing", Some(PoiKind::Laboratory)),
    ("laundromat", Some(PoiKind::Laundry)),
    ("lawn_mower_store", Some(PoiKind::GardenCentre)),
    ("leather_goods_store", Some(PoiKind::Accessories)),
    ("library", Some(PoiKind::Library)),
    ("lighting_store", Some(PoiKind::Home)),
    ("linen_store", Some(PoiKind::Home)),
    ("liquor_store", Some(PoiKind::WineShop)),
    ("lottery_vendor", Some(PoiKind::Newsagent)),
    ("luggage_store", Some(PoiKind::Accessories)),
    ("machine_and_tool_rental", Some(PoiKind::Rental)),
    ("makeup_artist", None),
    ("marina", Some(PoiKind::Marina)),
    ("massage_therapy", None),
    ("maternity_center", Some(PoiKind::Clinic)),
    ("mattress_store", Some(PoiKind::Home)),
    ("medical_spa", Some(PoiKind::Beauty)),
    ("medical_supply_store", Some(PoiKind::MedicalSupply)),
    ("miniature_golf_course", Some(PoiKind::MiniatureGolf)),
    ("mobile_phone_repair", Some(PoiKind::RepairShop)),
    ("motorcycle_dealer", Some(PoiKind::MotorcycleShop)),
    ("motorcycle_repair", Some(PoiKind::MotorcycleShop)),
    ("motorsport_vehicle_dealer", Some(PoiKind::MotorcycleShop)),
    ("motorsports_store", Some(PoiKind::MotorcycleShop)),
    ("movie_theater", Some(PoiKind::Cinema)),
    ("museum", Some(PoiKind::Museum)),
    ("music_and_dvd_store", Some(PoiKind::MusicShop)),
    ("music_venue", Some(PoiKind::EventsVenue)),
    (
        "musical_instrument_and_pro_audio_store",
        Some(PoiKind::MusicShop),
    ),
    ("nail_salon", Some(PoiKind::Beauty)),
    ("newspaper_and_magazines_store", Some(PoiKind::Newsagent)),
    ("nursery_and_gardening_store", Some(PoiKind::GardenCentre)),
    ("nursing", None),
    ("obstetrics_and_gynecology", Some(PoiKind::Doctor)),
    ("office_supply_store", Some(PoiKind::Stationery)),
    ("opera_and_ballet", Some(PoiKind::Theatre)),
    ("ophthalmology", Some(PoiKind::Doctor)),
    ("optometry", Some(PoiKind::Optician)),
    ("organic_grocery_store", Some(PoiKind::OrganicShop)),
    ("osteopathic_medicine", Some(PoiKind::AlternativeMedicine)),
    ("outdoor_furniture_store", Some(PoiKind::Home)),
    ("outdoor_store", Some(PoiKind::OutdoorShop)),
    ("outpatient_care_facility", Some(PoiKind::Clinic)),
    ("package_locker", None),
    ("packing_supply_store", None),
    ("paint_store", Some(PoiKind::Hardware)),
    ("parking", None),
    ("patisserie_cake_shop", Some(PoiKind::Pastry)),
    ("pawn_shop", Some(PoiKind::SecondHand)),
    ("pediatric_clinic", Some(PoiKind::Doctor)),
    ("performing_arts_venue", Some(PoiKind::Theatre)),
    ("permanent_makeup", None),
    ("pet_boarding", None),
    ("pet_groomer", Some(PoiKind::PetGrooming)),
    ("pet_store", Some(PoiKind::PetShop)),
    ("pharmacy", None),
    ("physical_therapy", Some(PoiKind::Physiotherapist)),
    ("podiatry", Some(PoiKind::Podiatrist)),
    ("police_station", Some(PoiKind::Police)),
    ("post_office", None),
    ("prenatal_and_perinatal_care", None),
    ("primary_care_or_general_clinic", Some(PoiKind::Doctor)),
    ("printing_service", None),
    ("produce_store", Some(PoiKind::Greengrocer)),
    ("prosthetics", Some(PoiKind::MedicalSupply)),
    ("psychiatry", Some(PoiKind::Doctor)),
    ("psychology", Some(PoiKind::Psychologist)),
    ("psychotherapy", Some(PoiKind::Psychologist)),
    ("pub", Some(PoiKind::Pub)),
    ("public_health_clinic", Some(PoiKind::Clinic)),
    ("public_market", Some(PoiKind::Marketplace)),
    ("radiology", Some(PoiKind::Laboratory)),
    ("real_estate_agent", Some(PoiKind::EstateAgent)),
    ("recreation_vehicle_repair", Some(PoiKind::MotorhomeShop)),
    ("recreational_vehicle_dealer", Some(PoiKind::MotorhomeShop)),
    ("recycling_center", Some(PoiKind::RecyclingCentre)),
    ("rental_service", Some(PoiKind::Rental)),
    ("restaurant", Some(PoiKind::Restaurant)),
    ("rug_store", Some(PoiKind::Home)),
    ("rv_park", None),
    ("rv_rental_service", Some(PoiKind::CarRental)),
    ("sandwich_shop", Some(PoiKind::FastFood)),
    ("second_hand_clothing_store", Some(PoiKind::SecondHand)),
    ("second_hand_store", Some(PoiKind::SecondHand)),
    ("self_storage_facility", Some(PoiKind::StorageRental)),
    ("session_photography_service", None),
    ("sewing_and_alterations", Some(PoiKind::Tailor)),
    ("shoe_repair", Some(PoiKind::ShoeRepair)),
    ("shoe_store", Some(PoiKind::Shoes)),
    ("shopping_mall", Some(PoiKind::DepartmentStore)),
    ("skin_care_and_makeup", Some(PoiKind::Beauty)),
    ("smoke_and_vape_store", Some(PoiKind::Tobacco)),
    ("smoothie_juice_bar", Some(PoiKind::Cafe)),
    ("souvenir_store", Some(PoiKind::Gift)),
    ("spa", Some(PoiKind::Beauty)),
    ("specialized_health_care", Some(PoiKind::Doctor)),
    ("specialty_foods_store", Some(PoiKind::Deli)),
    ("speech_therapy", Some(PoiKind::SpeechTherapist)),
    ("sport_or_fitness_facility", Some(PoiKind::SportsCentre)),
    ("sporting_goods_store", Some(PoiKind::Sports)),
    ("stadium_arena", Some(PoiKind::SportsCentre)),
    ("storage_facility", Some(PoiKind::StorageRental)),
    ("sunglasses_store", Some(PoiKind::Accessories)),
    ("surgery", Some(PoiKind::Clinic)),
    ("swimming_instructor", None),
    ("swimming_pool", Some(PoiKind::SwimmingPool)),
    ("swimwear_store", Some(PoiKind::Clothes)),
    ("tanning_salon", Some(PoiKind::Beauty)),
    ("tapas_bar", Some(PoiKind::Restaurant)),
    ("tattoo_and_piercing", Some(PoiKind::Tattoo)),
    ("tea_room", Some(PoiKind::Cafe)),
    ("theatre_venue", Some(PoiKind::Theatre)),
    ("tile_store", Some(PoiKind::Hardware)),
    ("tire_dealer_and_repair", Some(PoiKind::Tyres)),
    ("tire_shop", Some(PoiKind::Tyres)),
    ("tobacco_shop", Some(PoiKind::Tobacco)),
    ("town_hall", Some(PoiKind::Townhall)),
    ("toy_store", Some(PoiKind::Toys)),
    ("toys_and_games_store", Some(PoiKind::Toys)),
    ("trailer_rental_service", Some(PoiKind::Rental)),
    ("travel_agent", Some(PoiKind::TravelAgency)),
    ("truck_rental_service", Some(PoiKind::CarRental)),
    ("truck_repair", Some(PoiKind::CarRepair)),
    ("used_auto_dealer", Some(PoiKind::CarDealer)),
    ("vehicle_parts_store", Some(PoiKind::CarParts)),
    ("veterinarian", Some(PoiKind::Veterinary)),
    ("video_game_store", Some(PoiKind::Electronics)),
    ("vinyl_record_store", Some(PoiKind::MusicShop)),
    ("vision_or_eye_care_clinic", Some(PoiKind::Optician)),
    ("visitor_center", Some(PoiKind::TouristOffice)),
    ("warehouse_club_store", None),
    ("water_park", Some(PoiKind::WaterPark)),
    ("welding_supply_store", None),
    ("window_treatment_store", Some(PoiKind::Home)),
    ("winery", Some(PoiKind::Winery)),
    ("woodworking_supply_store", Some(PoiKind::Hardware)),
    ("zoo", Some(PoiKind::Zoo)),
];

/// The entry of `node` in [`TABLE`]: `Some(None)` for a node dropped with
/// its subtree, `None` for a node the table does not name.
fn entry(node: &str) -> Option<Option<PoiKind>> {
    TABLE
        .binary_search_by(|(n, _)| (*n).cmp(node))
        .ok()
        .map(|i| TABLE[i].1)
}

/// The kind of a place whose taxonomy, from the top, is `hierarchy`: the
/// first node from the leaf up that [`TABLE`] names decides.
#[must_use]
pub fn kind_of<S: AsRef<str>>(hierarchy: &[S]) -> Option<PoiKind> {
    hierarchy
        .iter()
        .rev()
        .find_map(|node| entry(node.as_ref()))
        .flatten()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_table_is_sorted_and_names_each_node_once() {
        assert!(
            TABLE.windows(2).all(|w| w[0].0 < w[1].0),
            "the lookup is a binary search"
        );
    }

    #[test]
    fn the_first_node_from_the_leaf_decides() {
        let k = |path: &[&str]| kind_of(path);
        assert_eq!(
            k(&[
                "food_and_drink",
                "restaurant",
                "european_restaurant",
                "western_european_restaurant",
                "french_restaurant"
            ]),
            Some(PoiKind::Restaurant),
            "every cuisine is a restaurant"
        );
        assert_eq!(
            k(&["food_and_drink", "casual_eatery", "fast_food_restaurant"]),
            Some(PoiKind::FastFood)
        );
        assert_eq!(
            k(&[
                "lifestyle_services",
                "personal_or_beauty_service",
                "hair_salon",
                "hair_stylist"
            ]),
            None,
            "a stylist without a salon is dropped, though a salon is read"
        );
        assert_eq!(
            k(&[
                "lifestyle_services",
                "personal_or_beauty_service",
                "hair_salon"
            ]),
            Some(PoiKind::Hairdresser)
        );
        assert_eq!(
            k(&[
                "travel_and_transportation",
                "vehicle_service",
                "recreation_vehicle_service",
                "recreation_vehicle_repair"
            ]),
            Some(PoiKind::MotorhomeShop),
            "a motorhome workshop"
        );
        assert_eq!(
            k(&[
                "shopping",
                "specialty_store",
                "pharmacy_and_drug_store",
                "pharmacy"
            ]),
            None,
            "pharmacies come from OpenStreetMap joined to FINESS"
        );
        assert_eq!(k(&["lodging", "campground"]), None, "a campsite is a place");
        assert_eq!(
            k(&["services_and_business", "financial_service", "accountant"]),
            None,
            "a node no row of the table names"
        );
        assert_eq!(kind_of::<&str>(&[]), None);
    }
}

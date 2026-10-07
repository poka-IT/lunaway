//! What a published dump of the places database may carry.
//!
//! The places database is shared under the ODbL, except the values whose
//! provenance is the external community source (`extcom`): they come under
//! its written agreement, which keeps them out of the open licence and
//! out of any copy handed to third parties outside the app
//! (`docs/data-sources.md`, "Licences of the places database"). The app's
//! own features (map tiles, place cards, packs) carry them; a public dump
//! never does. A dump builds each place with [`resolve_for_public_dump`]
//! instead of [`resolve`]: every value of a withheld source is replaced by
//! the next source's, or dropped, and a spot only withheld sources know is
//! left out.

use crate::{
    conflation::resolve::{Contribution, ResolvedPlace, resolve},
    source::SourceId,
};

/// The sources whose values never enter a published dump.
pub const WITHHELD_FROM_PUBLIC_DUMP: &[SourceId] = &[SourceId::EXTCOM];

/// Whether a published dump may carry values of `source`.
#[must_use]
pub fn in_public_dump(source: &SourceId) -> bool {
    !WITHHELD_FROM_PUBLIC_DUMP.contains(source)
}

/// The place as a published dump carries it: resolved from the
/// contributions of the sources a dump may carry, so that no value, no
/// alternative and no description of a withheld source remains. `None`
/// when only withheld sources describe the place: it is left out of the
/// dump.
#[must_use]
pub fn resolve_for_public_dump(contributions: &[Contribution<'_>]) -> Option<ResolvedPlace> {
    let open: Vec<Contribution<'_>> = contributions
        .iter()
        .filter(|c| in_public_dump(c.source))
        .copied()
        .collect();
    if open.is_empty() {
        return None;
    }
    resolve(&open)
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use super::*;
    use crate::{NormalizedRecord, OvernightStatus, PlaceKind, Position, Service};

    fn contribution<'a>(source: &'a SourceId, record: &'a NormalizedRecord) -> Contribution<'a> {
        Contribution {
            source,
            external_id: "1",
            fetched_at: Utc.with_ymd_and_hms(2026, 10, 7, 0, 0, 0).unwrap(),
            external_url: None,
            record,
        }
    }

    fn osm() -> NormalizedRecord {
        let mut r = NormalizedRecord::new(PlaceKind::Parking, Position::new(45.9, 6.13).unwrap());
        r.name = Some("Parking du Lac".into());
        r.services = [Service::Toilets].into();
        r
    }

    fn extcom() -> NormalizedRecord {
        let mut r =
            NormalizedRecord::new(PlaceKind::Parking, Position::new(45.9003, 6.13).unwrap());
        r.name = Some("Parking calme du lac".into());
        r.overnight = OvernightStatus::Tolerated;
        r.services = [Service::DrinkingWater].into();
        r.price_parking_eur = Some(0.0);
        r.descriptions.insert("fr".into(), "Calme la nuit.".into());
        r.description = Some("Calme la nuit.".into());
        r
    }

    #[test]
    fn a_dump_replaces_or_drops_every_value_of_the_partner() {
        let (o, x) = (osm(), extcom());
        let both = [
            contribution(&SourceId::OSM, &o),
            contribution(&SourceId::EXTCOM, &x),
        ];
        let app = resolve(&both).unwrap();
        assert_eq!(
            app.content.overnight,
            OvernightStatus::Tolerated,
            "the app shows the partner's values"
        );
        let dump = resolve_for_public_dump(&both).unwrap();
        assert_eq!(dump.content.overnight, OvernightStatus::Unknown, "dropped");
        assert_eq!(
            dump.content.services,
            [Service::Toilets],
            "replaced by OSM's"
        );
        assert_eq!(dump.content.price_parking_eur, None);
        assert_eq!(dump.content.description, None);
        assert!(dump.descriptions.is_empty());
        for p in &dump.provenance {
            assert!(
                in_public_dump(&p.source_id),
                "{}: a dump names no value of a withheld source",
                p.field
            );
            assert!(
                p.alternatives.iter().all(|a| in_public_dump(&a.source_id)),
                "{}: nor keeps one as an alternative",
                p.field
            );
        }
    }

    #[test]
    fn a_spot_only_the_partner_knows_stays_out_of_a_dump() {
        let x = extcom();
        assert!(resolve_for_public_dump(&[contribution(&SourceId::EXTCOM, &x)]).is_none());
    }

    #[test]
    fn a_place_without_the_partner_is_dumped_as_the_app_shows_it() {
        let o = osm();
        let only = [contribution(&SourceId::OSM, &o)];
        assert_eq!(resolve_for_public_dump(&only), resolve(&only));
    }
}

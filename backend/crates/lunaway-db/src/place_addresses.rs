//! The addresses of the places no source gives a street or a town: the
//! places due for a reverse geocoding ([`due`]), what the geocoder
//! answered ([`apply`], table `place_geocodes`), and the address a place
//! written by the conflation shows ([`shown`]). The rules are
//! `lunaway_domain::place_address`'s.

use lunaway_domain::{
    Address, PlaceKind, Position,
    conflation::FieldProvenance,
    place_address::{self, Completed, Geocoded, MOVED_M},
};
use sqlx::PgConnection;
use uuid::Uuid;

use crate::{DbError, PgPool, conflation::WriterTx};

/// A place due for a reverse geocoding, as it stands.
#[derive(Debug, Clone, PartialEq)]
pub struct DuePlace {
    /// Its id.
    pub id: Uuid,
    /// What it is.
    pub kind: PlaceKind,
    /// Where it is.
    pub position: Position,
    /// The address it shows, its sources' own.
    pub address: Address,
}

/// The places due for a reverse geocoding, after `after` in the order of
/// their ids, at most `limit`: live places without a street (a private
/// host never gets one) or, without a street, without a town and a
/// postcode, whose last geocoding is missing or was asked more than
/// [`MOVED_M`] from where they stand. A run walks them with the last id
/// of a page as `after`.
///
/// # Errors
///
/// [`DbError`] when the query fails or a row does not decode.
pub async fn due(pool: &PgPool, after: Uuid, limit: i64) -> Result<Vec<DuePlace>, DbError> {
    let rows = sqlx::query!(
        r#"
        SELECT p.id, p.kind, ST_Y(p.geom::geometry) AS "lat!", ST_X(p.geom::geometry) AS "lon!",
               p.street, p.postcode, p.city, p.country_code
        FROM places p
        LEFT JOIN place_geocodes g ON g.place_id = p.id
        WHERE p.id > $1 AND p.deleted_at IS NULL AND p.taken_down_at IS NULL
          AND ((p.kind <> 'homestay' AND p.street IS NULL)
               OR ((p.kind = 'homestay' OR p.street IS NULL)
                   AND p.city IS NULL AND p.postcode IS NULL))
          AND (g.place_id IS NULL
               OR ST_Distance(ST_SetSRID(ST_MakePoint(g.lon, g.lat), 4326)::geography, p.geom)
                  > $3)
        ORDER BY p.id
        LIMIT $2
        "#,
        after,
        limit,
        MOVED_M,
    )
    .fetch_all(pool)
    .await?;
    rows.into_iter()
        .map(|r| {
            Ok(DuePlace {
                id: r.id,
                kind: r
                    .kind
                    .parse()
                    .map_err(|e| DbError::decode("place kind", e))?,
                position: Position::new(r.lat, r.lon)
                    .map_err(|e| DbError::decode("place position", e))?,
                address: Address {
                    street: r.street,
                    postcode: r.postcode,
                    city: r.city,
                    country_code: r.country_code,
                    city_code: None,
                },
            })
        })
        .collect()
}

/// The reverse geocoding kept for `place`, if any.
///
/// # Errors
///
/// [`DbError`] when the query fails or the row does not decode.
pub(crate) async fn geocode_of(
    conn: &mut PgConnection,
    place: Uuid,
) -> Result<Option<Geocoded>, DbError> {
    let row = sqlx::query!(
        r#"
        SELECT lat, lon, house_number, street, postcode, city, country_code
        FROM place_geocodes WHERE place_id = $1
        "#,
        place
    )
    .fetch_optional(conn)
    .await?;
    row.map(|r| {
        Ok(Geocoded {
            asked: Some(
                Position::new(r.lat, r.lon).map_err(|e| DbError::decode("geocode position", e))?,
            ),
            house_number: r.house_number,
            street: r.street,
            postcode: r.postcode,
            city: r.city,
            country_code: r.country_code,
        })
    })
    .transpose()
}

/// The address a place of `kind` at `position` shows when the conflation
/// writes it with its sources' `source` address, and its provenance: the
/// geocoded address kept for it when the rules take it
/// (`place_address::complete`), a private host's without its street. The
/// stored geocoding is read only when it could count.
///
/// # Errors
///
/// [`DbError`] when the geocoding cannot be read.
pub(crate) async fn shown(
    conn: &mut PgConnection,
    place: Uuid,
    kind: PlaceKind,
    position: Position,
    source: &Address,
    provenance: &[FieldProvenance],
) -> Result<Option<(Address, Vec<FieldProvenance>)>, DbError> {
    let geocoded = if place_address::wants_geocoding(kind, source) {
        geocode_of(conn, place).await?
    } else {
        None
    };
    Ok(
        place_address::complete(kind, position, source, geocoded.as_ref()).map(
            |Completed { address, geocoded }| {
                let mut provenance = provenance.to_vec();
                if geocoded {
                    place_address::credit_geocoder(&mut provenance, source);
                }
                (address, provenance)
            },
        ),
    )
}

/// Keeps what the reverse geocoding of `place` gave and, when the place
/// still stands where it was asked and still shows its sources' address,
/// writes the address the rules take (`place_address::complete`) with its
/// provenance and a new position in the change feed, in the writer
/// transaction `tx`. Returns whether the place changed.
///
/// # Errors
///
/// [`DbError`] when a statement fails or a row does not decode.
pub async fn apply(tx: &mut WriterTx, place: Uuid, geocoded: &Geocoded) -> Result<bool, DbError> {
    let Some(asked) = geocoded.asked else {
        return Ok(false);
    };
    let current = sqlx::query!(
        r#"
        SELECT kind, ST_Y(geom::geometry) AS "lat!", ST_X(geom::geometry) AS "lon!",
               street, postcode, city, country_code, provenance
        FROM places
        WHERE id = $1 AND deleted_at IS NULL AND taken_down_at IS NULL
        FOR UPDATE
        "#,
        place
    )
    .fetch_optional(tx.conn())
    .await?;
    let Some(current) = current else {
        // Gone or taken down meanwhile: nothing is kept of where it stood.
        return Ok(false);
    };
    let kind: PlaceKind = current
        .kind
        .parse()
        .map_err(|e| DbError::decode("place kind", e))?;
    // A private host's street and number are not kept, even aside:
    // `place_address::pick` asks none for it, and a place that became one
    // since keeps none either.
    let host = kind == PlaceKind::Homestay;
    let (house_number, street) = if host {
        (None, None)
    } else {
        (geocoded.house_number.clone(), geocoded.street.clone())
    };
    sqlx::query!(
        r#"
        INSERT INTO place_geocodes
            (place_id, lat, lon, house_number, street, postcode, city, country_code, asked_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
        ON CONFLICT (place_id) DO UPDATE SET
            lat = EXCLUDED.lat, lon = EXCLUDED.lon, house_number = EXCLUDED.house_number,
            street = EXCLUDED.street, postcode = EXCLUDED.postcode, city = EXCLUDED.city,
            country_code = EXCLUDED.country_code, asked_at = EXCLUDED.asked_at
        "#,
        place,
        asked.lat(),
        asked.lon(),
        house_number,
        street,
        geocoded.postcode,
        geocoded.city,
        geocoded.country_code,
    )
    .execute(tx.conn())
    .await?;
    let position = Position::new(current.lat, current.lon)
        .map_err(|e| DbError::decode("place position", e))?;
    let source = Address {
        street: current.street,
        postcode: current.postcode,
        city: current.city,
        country_code: current.country_code,
        city_code: None,
    };
    // A place that gained a street or a town meanwhile (a conflation wrote
    // it) keeps it.
    if !place_address::wants_geocoding(kind, &source) {
        return Ok(false);
    }
    let Some(Completed {
        address,
        geocoded: true,
    }) = place_address::complete(kind, position, &source, Some(geocoded))
    else {
        return Ok(false);
    };
    let mut provenance: Vec<FieldProvenance> =
        serde_json::from_value(current.provenance).map_err(|e| DbError::decode("provenance", e))?;
    place_address::credit_geocoder(&mut provenance, &source);
    let provenance =
        serde_json::to_value(&provenance).map_err(|e| DbError::decode("provenance", e))?;
    let written = sqlx::query!(
        r#"
        UPDATE places SET street = $2, postcode = $3, city = $4, country_code = $5,
            provenance = $6, updated_at = now(), updated_seq = nextval('place_change_seq')
        WHERE id = $1
        "#,
        place,
        address.street,
        address.postcode,
        address.city,
        address.country_code,
        provenance,
    )
    .execute(tx.conn())
    .await?;
    Ok(written.rows_affected() > 0)
}

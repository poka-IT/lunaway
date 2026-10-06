//! The exclusion zone of a place taken down: keyed hashes of the cells
//! around where it stood, and nothing that gives the position back.
//!
//! A takedown (a private home listed as a spot, a request under the GDPR, a
//! court order) empties the place for good. The same spot listed again, by
//! another account, another OpenStreetMap element or another source, must
//! not go live unseen. At the takedown the server keeps, for each position
//! the place and its records had, the HMAC-SHA-256 under its own secret
//! (`LUNAWAY_TAKEDOWN_SECRET`) of the H3 cell that holds it and of the
//! cells around that one, [`RING`] cells deep ([`TakedownKey::zone`]). A
//! new place, or a place that moves, whose cell hashes into that set is
//! held for a moderator ([`Exclusion::covers`]).
//!
//! The cells of a resolution are finite (about 237 billion at resolution 11
//! on Earth, a few billion over Europe): anyone holding the secret can hash
//! them all and find the cells again. The secret is what keeps the zone
//! unreadable from a copy of the database, so it lives outside the
//! database and its dumps, read only by the role that writes the catalogue.
//!
//! Resolution 11, hexagons of about 25 m a side and 50 m across (H3's
//! averages), and 4 rings of neighbours: 61 cells around each position.
//! Measured over a grid of Europe in 72 directions (the test
//! `the_zone_catches_a_listing_near_the_spot_and_little_more`), the zone
//! holds every point within 125 m of the spot and none farther than 266 m.
//! The cell alone with its six neighbours at resolution 10 (66 m a side)
//! held only within 71 m in the worst direction and up to 280 m in the
//! best: a lumpier zone, with a weaker guarantee for the same reach.

use std::{collections::HashSet, fmt, str::FromStr};

use h3o::{CellIndex, LatLng, Resolution};
use hmac::{Hmac, KeyInit, Mac};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::Sha256;

use crate::{Position, UnknownCode, taxonomy::coded_enum};

coded_enum! {
    /// The kind of request behind a takedown: what the journal kept outside
    /// the database says of it, a short code, never the reason's text.
    TakedownCode {
        /// A private home listed as a spot.
        PrivateHome => "private-home",
        /// An erasure or objection under the GDPR.
        Gdpr => "gdpr",
        /// A court or authority's order.
        CourtOrder => "court-order",
        /// Anything else.
        Other => "other",
    }
}

/// The H3 resolution of the cells.
pub const RESOLUTION: Resolution = Resolution::Eleven;

/// How many rings of neighbours around a position's cell its zone takes.
pub const RING: u32 = 4;

/// The shortest secret accepted, in bytes: as long as the hash it keys.
pub const MIN_SECRET_LEN: usize = 32;

/// Prefix of every hashed message, so the secret keys nothing else by
/// accident; the version moves if the grid or the resolution ever changes.
const DOMAIN: &[u8] = b"lunaway takedown cell v1\0";

/// Why a secret is refused.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[non_exhaustive]
pub enum KeyError {
    /// Shorter than [`MIN_SECRET_LEN`] bytes.
    #[error("the takedown secret must hold {MIN_SECRET_LEN} bytes at least, it holds {0}")]
    TooShort(usize),
}

/// The server's secret that keys the cells' hashes. Its `Debug` shows no
/// byte of it.
#[derive(Clone)]
pub struct TakedownKey(Vec<u8>);

impl std::fmt::Debug for TakedownKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("TakedownKey(..)")
    }
}

impl TakedownKey {
    /// The key from the secret's bytes.
    ///
    /// # Errors
    ///
    /// [`KeyError::TooShort`] under [`MIN_SECRET_LEN`] bytes.
    pub fn new(secret: &[u8]) -> Result<Self, KeyError> {
        if secret.len() < MIN_SECRET_LEN {
            return Err(KeyError::TooShort(secret.len()));
        }
        Ok(Self(secret.to_vec()))
    }

    /// The key from the value of the environment variable that holds it:
    /// `None` when the variable is unset or empty (a server not configured
    /// yet holds nothing back, and says so once at start).
    ///
    /// # Errors
    ///
    /// [`KeyError::TooShort`] when it is set but too short: a mistake to
    /// stop on, since a zone keyed by it would not match the others.
    pub fn from_env_value(value: Option<&str>) -> Result<Option<Self>, KeyError> {
        match value.map(str::trim) {
            None | Some("") => Ok(None),
            Some(v) => Self::new(v.as_bytes()).map(Some),
        }
    }

    fn hash(&self, cell: CellIndex) -> CellHash {
        #[allow(
            clippy::expect_used,
            reason = "HMAC takes a key of any length; a fallback hash would match every cell"
        )]
        let mut mac = <Hmac<Sha256> as KeyInit>::new_from_slice(&self.0)
            .expect("HMAC accepts a key of any length");
        mac.update(DOMAIN);
        mac.update(&u64::from(cell).to_be_bytes());
        CellHash(mac.finalize().into_bytes().into())
    }

    /// A value that tells this secret from another without saying
    /// anything of it: the HMAC of a fixed label, which no cell's message
    /// can equal.
    #[must_use]
    pub fn check(&self) -> CellHash {
        #[allow(clippy::expect_used, reason = "HMAC accepts a key of any length")]
        let mut mac = <Hmac<Sha256> as KeyInit>::new_from_slice(&self.0)
            .expect("HMAC accepts a key of any length");
        mac.update(b"lunaway takedown key check v1\0");
        CellHash(mac.finalize().into_bytes().into())
    }

    /// The hash of the cell that holds `p`.
    #[must_use]
    pub fn cell_hash(&self, p: Position) -> CellHash {
        self.hash(cell_of(p))
    }

    /// The hashes of the zone around `p`: its cell and the cells around it,
    /// [`RING`] deep, so a listing on the other side of a cell's edge, or a
    /// little farther on the same plot, is caught too.
    #[must_use]
    pub fn zone(&self, p: Position) -> Vec<CellHash> {
        cell_of(p)
            .grid_disk::<Vec<_>>(RING)
            .into_iter()
            .map(|c| self.hash(c))
            .collect()
    }
}

/// The cell of `p` at [`RESOLUTION`].
///
/// # Panics
///
/// Never: h3o refuses only a coordinate that is not finite, and a
/// [`Position`] is checked finite and in range when it is made.
fn cell_of(p: Position) -> CellIndex {
    #[allow(
        clippy::expect_used,
        reason = "a Position is finite by construction, the only thing LatLng checks"
    )]
    LatLng::new(p.lat(), p.lon())
        .expect("a Position is a finite coordinate")
        .to_cell(RESOLUTION)
}

/// The keyed hash of a cell: 32 bytes, written as 64 lowercase hex digits.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct CellHash([u8; 32]);

impl std::fmt::Debug for CellHash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "CellHash({})", self.to_hex())
    }
}

impl CellHash {
    /// Its bytes.
    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// A hash from its 32 bytes; `None` for any other length.
    #[must_use]
    pub fn from_slice(bytes: &[u8]) -> Option<Self> {
        <[u8; 32]>::try_from(bytes).ok().map(Self)
    }

    /// Its 64 lowercase hex digits.
    #[must_use]
    pub fn to_hex(&self) -> String {
        const DIGITS: &[u8; 16] = b"0123456789abcdef";
        let mut out = String::with_capacity(64);
        for b in self.0 {
            out.push(char::from(DIGITS[usize::from(b >> 4)]));
            out.push(char::from(DIGITS[usize::from(b & 0x0f)]));
        }
        out
    }

    /// A hash from 64 hex digits, either case; `None` otherwise.
    #[must_use]
    pub fn from_hex(s: &str) -> Option<Self> {
        let s = s.as_bytes();
        if s.len() != 64 {
            return None;
        }
        let digit = |c: u8| {
            char::from(c)
                .to_digit(16)
                .and_then(|d| u8::try_from(d).ok())
        };
        let mut out = [0_u8; 32];
        for (byte, [hi, lo]) in out.iter_mut().zip(s.as_chunks::<2>().0) {
            *byte = (digit(*hi)? << 4) | digit(*lo)?;
        }
        Some(Self(out))
    }
}

impl Serialize for CellHash {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.to_hex())
    }
}

impl<'de> Deserialize<'de> for CellHash {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let s = String::deserialize(d)?;
        Self::from_hex(&s).ok_or_else(|| serde::de::Error::custom("a cell hash is 64 hex digits"))
    }
}

/// The cells of every takedown, with the key that hashes a position into
/// one: what the conflation checks a new or moved place against.
#[derive(Debug, Clone)]
pub struct Exclusion {
    key: TakedownKey,
    cells: HashSet<CellHash>,
}

impl Exclusion {
    /// The zone made of `cells`, hashed with `key`.
    #[must_use]
    pub fn new(key: TakedownKey, cells: impl IntoIterator<Item = CellHash>) -> Self {
        Self {
            key,
            cells: cells.into_iter().collect(),
        }
    }

    /// Whether `p` lies in a cell of a takedown's zone.
    #[must_use]
    pub fn covers(&self, p: Position) -> bool {
        !self.cells.is_empty() && self.cells.contains(&self.key.cell_hash(p))
    }

    /// Whether `a` and `b` lie in the same cell.
    #[must_use]
    pub fn same_cell(&self, a: Position, b: Position) -> bool {
        cell_of(a) == cell_of(b)
    }

    /// Whether no takedown has a zone yet.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.cells.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::EARTH_RADIUS_M;

    fn key(s: &str) -> TakedownKey {
        TakedownKey::new(format!("{s:-<32}").as_bytes()).unwrap()
    }

    fn at(lat: f64, lon: f64) -> Position {
        Position::new(lat, lon).unwrap()
    }

    /// The point `d` metres from `p` toward `bearing` degrees.
    fn toward(p: Position, bearing: f64, d: f64) -> Position {
        let (phi, lambda) = (p.lat().to_radians(), p.lon().to_radians());
        let (theta, delta) = (bearing.to_radians(), d / EARTH_RADIUS_M);
        let phi2 = (phi.sin() * delta.cos() + phi.cos() * delta.sin() * theta.cos()).asin();
        let lambda2 = lambda
            + (theta.sin() * delta.sin() * phi.cos()).atan2(delta.cos() - phi.sin() * phi2.sin());
        at(phi2.to_degrees(), lambda2.to_degrees())
    }

    #[test]
    fn a_secret_shorter_than_its_hash_is_refused_and_an_unset_one_holds_nothing() {
        assert!(TakedownKey::from_env_value(None).unwrap().is_none());
        assert!(
            TakedownKey::from_env_value(Some("  ")).unwrap().is_none(),
            "an empty variable is an unset one: the server starts and holds nothing back"
        );
        assert_eq!(
            TakedownKey::from_env_value(Some("short")).unwrap_err(),
            KeyError::TooShort(5),
            "a secret set but too short is a mistake to stop on"
        );
        assert!(
            TakedownKey::from_env_value(Some(&"a".repeat(32)))
                .unwrap()
                .is_some()
        );
        assert_eq!(format!("{:?}", key("secret")), "TakedownKey(..)");
    }

    #[test]
    fn a_hash_depends_on_the_cell_and_the_secret_only() {
        let lyon = at(45.7578, 4.8320);
        let (a, b) = (key("first"), key("second"));
        assert_eq!(a.cell_hash(lyon), a.cell_hash(at(45.75781, 4.83201)));
        assert_ne!(
            a.cell_hash(lyon),
            b.cell_hash(lyon),
            "another secret gives other hashes: without it the cells cannot be found"
        );
        assert_ne!(a.cell_hash(lyon), a.cell_hash(at(45.7678, 4.8320)));
        let zone = a.zone(lyon);
        assert_eq!(zone.len(), 61, "the cell and four rings of neighbours");
        assert!(zone.contains(&a.cell_hash(lyon)));
    }

    #[test]
    fn a_check_value_tells_two_secrets_apart() {
        assert_eq!(key("one").check(), key("one").check());
        assert_ne!(key("one").check(), key("two").check());
    }

    #[test]
    fn a_hash_reads_back_from_its_hex() {
        let h = key("x").cell_hash(at(48.85, 2.35));
        let hex = h.to_hex();
        assert_eq!(hex.len(), 64);
        assert_eq!(CellHash::from_hex(&hex), Some(h));
        assert_eq!(CellHash::from_hex(&hex.to_uppercase()), Some(h));
        assert_eq!(CellHash::from_hex(&hex[..63]), None);
        assert_eq!(CellHash::from_hex(&format!("{}g", &hex[..63])), None);
        let json = serde_json::to_string(&h).unwrap();
        assert_eq!(serde_json::from_str::<CellHash>(&json).unwrap(), h);
        assert_eq!(CellHash::from_slice(h.as_bytes()), Some(h));
        assert_eq!(CellHash::from_slice(&[0; 31]), None);
    }

    /// Over a grid of points across Europe, the distance from each point at
    /// which a listing stops being caught, in 72 directions: never under
    /// 120 m (a pin dropped at the gate, an OpenStreetMap node on the other
    /// side of the plot), never over 270 m (the neighbours a moderator may
    /// have to release). Measured on 2026-10-06: 125 and 266 m.
    #[test]
    fn the_zone_catches_a_listing_near_the_spot_and_little_more() {
        let k = key("europe");
        let (mut nearest, mut farthest) = (f64::MAX, 0.0_f64);
        let mut lat = 36.0;
        while lat <= 70.0 {
            let mut lon = -9.5;
            while lon <= 30.0 {
                let spot = at(lat, lon);
                let ex = Exclusion::new(k.clone(), k.zone(spot));
                for step in 0..72 {
                    let bearing = f64::from(step) * 5.0;
                    let mut d = 0.0;
                    while ex.covers(toward(spot, bearing, d + 1.0)) {
                        d += 1.0;
                    }
                    nearest = nearest.min(d);
                    farthest = farthest.max(d);
                }
                lon += 3.7;
            }
            lat += 2.9;
        }
        assert!(
            nearest >= 120.0,
            "a listing within 120 m of the spot is always held ({nearest} m)"
        );
        assert!(
            farthest <= 270.0,
            "a place farther than 270 m is never held ({farthest} m)"
        );
    }

    #[test]
    fn an_empty_zone_covers_nothing() {
        let k = key("none");
        let ex = Exclusion::new(k.clone(), []);
        assert!(ex.is_empty());
        assert!(!ex.covers(at(45.0, 5.0)));
        let ex = Exclusion::new(k.clone(), k.zone(at(45.0, 5.0)));
        assert!(ex.covers(at(45.0, 5.0)));
        assert!(!ex.covers(at(45.01, 5.0)), "1.1 km away");
    }
}

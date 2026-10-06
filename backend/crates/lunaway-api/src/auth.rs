//! Who is calling: the bearer session of a request, resolved once and
//! cached for the request; the sign-in challenges; and the trust level an
//! action needs.
//!
//! Public reads stay anonymous: a missing, malformed, expired or unknown
//! token on a read is ignored (the read is served as anonymous), while a
//! field that needs an account answers `UNAUTHENTICATED`.

use std::{collections::HashMap, sync::Mutex, time::Duration};

use async_graphql::{Context, Result};
use axum::http::{HeaderMap, header};
use lunaway_db::{DbError, PgPool, accounts};
use lunaway_domain::community::trust::{self, AccountStats, NextLevel, Thresholds};
use tokio::sync::OnceCell;
use uuid::Uuid;

use crate::{
    error::{forbidden, internal, level_too_low, unauthenticated},
    schema::{db, state},
};

/// The bearer token a request carries, as the hash sessions are stored
/// under. The token itself is dropped as soon as it is hashed.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct Credentials {
    /// SHA-256 of a well-formed token; `None` without one.
    pub(crate) token_hash: Option<[u8; 32]>,
}

impl Credentials {
    /// Reads `Authorization: Bearer <token>`. A token that is not shaped
    /// like one this server issues is treated as absent: it cannot match a
    /// session, so it costs no query.
    pub(crate) fn from_headers(headers: &HeaderMap) -> Self {
        let token_hash = headers
            .get(header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| {
                let (scheme, token) = v.trim().split_once(' ')?;
                scheme
                    .eq_ignore_ascii_case("bearer")
                    .then(|| lunaway_auth::token_hash(token.trim()))?
            });
        Self { token_hash }
    }
}

/// The account behind a request's session.
#[derive(Debug, Clone)]
pub(crate) struct Viewer {
    /// The account.
    pub(crate) account: accounts::AccountRow,
    /// The device key that opened the session.
    pub(crate) device_key_id: Uuid,
    /// The session, for signing out.
    pub(crate) token_hash: [u8; 32],
    /// When the session was opened by a signed sign-in.
    pub(crate) opened_at: chrono::DateTime<chrono::Utc>,
}

impl Viewer {
    pub(crate) const fn id(&self) -> Uuid {
        self.account.id
    }

    pub(crate) fn level(&self) -> u8 {
        u8::try_from(self.account.trust_level).unwrap_or(0)
    }
}

/// The viewer of one request, resolved at most once.
#[derive(Default)]
pub(crate) struct ViewerCell(OnceCell<Option<Viewer>>);

/// How long a session may go unused before its expiry is pushed back again:
/// one write an hour at most per session, not one per request.
const TOUCH_EVERY: chrono::TimeDelta = chrono::TimeDelta::hours(1);

/// The live session `credentials` name, sliding its expiry.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub(crate) async fn resolve(
    pool: &PgPool,
    credentials: Credentials,
    session_ttl: Duration,
) -> Result<Option<Viewer>, DbError> {
    let Some(hash) = credentials.token_hash else {
        return Ok(None);
    };
    let Some(session) = accounts::session(pool, &hash).await? else {
        return Ok(None);
    };
    if session.account.banned_at.is_some() {
        return Ok(None);
    }
    let now = chrono::Utc::now();
    if now - session.last_used_at > TOUCH_EVERY || session.last_active_on < now.date_naive() {
        accounts::touch_session(pool, &hash, session_ttl.as_secs_f64()).await?;
    }
    Ok(Some(Viewer {
        account: session.account,
        device_key_id: session.device_key_id,
        token_hash: hash,
        opened_at: session.created_at,
    }))
}

/// The viewer of a public read: `None` for an anonymous request and for a
/// token the server does not know.
pub(crate) async fn viewer(ctx: &Context<'_>) -> Result<Option<Viewer>> {
    let Some(cell) = ctx.data_opt::<ViewerCell>() else {
        return Ok(None);
    };
    let credentials = ctx.data_opt::<Credentials>().copied().unwrap_or_default();
    if credentials.token_hash.is_none() {
        return Ok(None);
    }
    let found = cell
        .0
        .get_or_try_init(|| async {
            let (pool, _permit) = db(ctx).await?;
            resolve(pool, credentials, state(ctx).config.auth.session_ttl)
                .await
                .map_err(|e| internal(&e))
        })
        .await?;
    Ok(found.clone())
}

/// The viewer of a field that needs an account.
pub(crate) async fn require(ctx: &Context<'_>) -> Result<Viewer> {
    viewer(ctx).await?.ok_or_else(unauthenticated)
}

/// How recent a signed sign-in must be for the actions that could lock the
/// owner out (a new recovery code, detaching devices, deleting the
/// account): a stolen bearer token alone cannot do them, the device key
/// must sign again.
pub(crate) const FRESH_SIGN_IN: chrono::TimeDelta = chrono::TimeDelta::minutes(10);

/// The viewer of an action that needs a recent signed sign-in.
pub(crate) async fn require_fresh(ctx: &Context<'_>) -> Result<Viewer> {
    let viewer = require(ctx).await?;
    if chrono::Utc::now() - viewer.opened_at > FRESH_SIGN_IN {
        return Err(crate::error::fresh_sign_in());
    }
    Ok(viewer)
}

/// What the trust rules see of `account`, and its level and next level;
/// the level is stored when it changed. `None` when the account is gone.
///
/// # Errors
///
/// [`DbError`] when a query fails.
pub(crate) async fn compute_level(
    pool: &PgPool,
    thresholds: &Thresholds,
    account: Uuid,
) -> Result<Option<(u8, Option<NextLevel>)>, DbError> {
    let Some(i) = accounts::trust_inputs(pool, account).await? else {
        return Ok(None);
    };
    let count = |n: i64| u32::try_from(n.max(0)).unwrap_or(u32::MAX);
    let stats = AccountStats {
        age_days: count(i.age_days),
        active_days: count(i.active_days),
        confirmations: count(i.confirmations),
        contributions: count(i.contributions),
        removals: count(i.removals),
        sponsored: i.sponsored,
        nominated: i.nominated,
        granted_level: u8::try_from(i.granted_level).unwrap_or(0),
    };
    let level = trust::level(&stats, thresholds);
    accounts::set_trust_level(pool, account, i16::from(level)).await?;
    Ok(Some((level, trust::next_level(&stats, thresholds))))
}

/// Checks that `viewer` may do `action`: for levels 0 and 1 its stored
/// level first, then the rules computed again (a day may have passed since
/// its last contribution); for levels 2 and up the rules computed again
/// every time. Returns the level.
pub(crate) async fn require_level(
    ctx: &Context<'_>,
    viewer: &Viewer,
    action: trust::Action,
) -> Result<u8> {
    let needed = action.required_level();
    // Levels 2 and up can be lost (a removal by moderation, a withdrawn
    // grant): those actions always read the level again.
    if viewer.level() >= needed && needed < 2 {
        return Ok(viewer.level());
    }
    let (pool, _permit) = db(ctx).await?;
    let level = compute_level(pool, &state(ctx).config.trust, viewer.id())
        .await
        .map_err(|e| internal(&e))?
        .map_or(0, |(l, _)| l);
    if level >= needed {
        Ok(level)
    } else {
        Err(level_too_low(needed, level))
    }
}

/// Computes the level again after a contribution, so it moves with the
/// account's activity; a failure is logged, not returned: the contribution
/// itself is stored.
pub(crate) async fn after_contribution(ctx: &Context<'_>, viewer: &Viewer) {
    let Ok((pool, _permit)) = db(ctx).await else {
        return;
    };
    if let Err(error) = compute_level(pool, &state(ctx).config.trust, viewer.id()).await {
        tracing::error!(%error, "cannot recompute a trust level");
    }
}

/// The sign-in challenges. A nonce carries its own expiry and a MAC under
/// a key drawn at start (`lunaway_auth::ChallengeKey`), so handing one out
/// stores nothing; only the nonces already answered are remembered, until
/// they expire, so each answers one sign-in. Answering takes a valid
/// signature and a sign-in quota, which bounds what that memory can hold.
#[derive(Debug)]
pub(crate) struct Challenges {
    key: lunaway_auth::ChallengeKey,
    ttl: Duration,
    cap: usize,
    answered: Mutex<HashMap<[u8; 16], u64>>,
}

/// Why no challenge was handed out, or why a nonce is refused.
#[derive(Debug)]
pub(crate) enum ChallengeRefusal {
    /// The random source failed.
    Random(lunaway_auth::AuthError),
    /// Malformed, forged, from before a restart, or expired.
    Invalid(lunaway_auth::NonceError),
    /// Already answered.
    Used,
    /// Too many answered nonces are remembered; the oldest expire within
    /// the challenge lifetime.
    Full,
}

fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs())
}

impl Challenges {
    pub(crate) fn new(ttl: Duration, cap: usize) -> Result<Self, lunaway_auth::AuthError> {
        Ok(Self {
            key: lunaway_auth::ChallengeKey::generate()?,
            ttl,
            cap,
            answered: Mutex::new(HashMap::new()),
        })
    }

    /// A fresh nonce and its lifetime.
    pub(crate) fn issue(&self) -> Result<(String, Duration), ChallengeRefusal> {
        let expires = unix_now().saturating_add(self.ttl.as_secs());
        let nonce = self.key.issue(expires).map_err(ChallengeRefusal::Random)?;
        Ok((nonce, self.ttl))
    }

    /// Checks that `nonce` is one of ours and still valid, before the
    /// signature is checked; nothing is remembered yet.
    pub(crate) fn check(
        &self,
        nonce: &str,
    ) -> Result<lunaway_auth::CheckedNonce, ChallengeRefusal> {
        self.key
            .check(nonce, unix_now())
            .map_err(ChallengeRefusal::Invalid)
    }

    /// Marks a checked nonce as answered, once its signature verified:
    /// refused when it was answered before.
    pub(crate) fn answer(&self, nonce: lunaway_auth::CheckedNonce) -> Result<(), ChallengeRefusal> {
        let now = unix_now();
        let mut answered = self
            .answered
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if answered.len() >= self.cap {
            answered.retain(|_, expires| *expires > now);
            if answered.len() >= self.cap {
                return Err(ChallengeRefusal::Full);
            }
        }
        if answered.insert(nonce.id, nonce.expires).is_some() {
            return Err(ChallengeRefusal::Used);
        }
        Ok(())
    }
}

/// Refuses a banned account the action.
pub(crate) fn not_banned(banned: bool) -> Result<()> {
    if banned {
        Err(forbidden("this account is banned"))
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_nonce_answers_once_and_only_in_time() {
        let c = Challenges::new(Duration::from_secs(60), 10).unwrap();
        let (nonce, _) = c.issue().unwrap();
        let checked = c.check(&nonce).unwrap();
        assert!(c.answer(checked).is_ok());
        let again = c.check(&nonce).unwrap();
        assert!(
            matches!(c.answer(again), Err(ChallengeRefusal::Used)),
            "a challenge is single use"
        );
        assert!(c.check("never-issued").is_err());
        let restarted = Challenges::new(Duration::from_secs(60), 10).unwrap();
        assert!(
            matches!(restarted.check(&nonce), Err(ChallengeRefusal::Invalid(_))),
            "a nonce from before a restart is refused"
        );
        let short = Challenges::new(Duration::from_secs(0), 10).unwrap();
        let (late, _) = short.issue().unwrap();
        assert!(
            short.check(&late).is_err(),
            "an expired challenge is refused"
        );
    }

    #[test]
    fn handing_out_challenges_stores_nothing_and_answers_are_bounded() {
        let c = Challenges::new(Duration::from_secs(60), 3).unwrap();
        for _ in 0..1_000 {
            c.issue().unwrap();
        }
        assert!(c.answered.lock().unwrap().is_empty());
        for _ in 0..3 {
            let (n, _) = c.issue().unwrap();
            c.answer(c.check(&n).unwrap()).unwrap();
        }
        let (n, _) = c.issue().unwrap();
        assert!(matches!(
            c.answer(c.check(&n).unwrap()),
            Err(ChallengeRefusal::Full)
        ));
    }

    #[test]
    fn only_a_bearer_token_shaped_like_ours_is_read() {
        let mut h = HeaderMap::new();
        assert!(Credentials::from_headers(&h).token_hash.is_none());
        let token = lunaway_auth::new_session_token().unwrap();
        h.insert(
            header::AUTHORIZATION,
            format!("Bearer {}", token.token).parse().unwrap(),
        );
        assert_eq!(Credentials::from_headers(&h).token_hash, Some(token.hash));
        h.insert(
            header::AUTHORIZATION,
            format!("bearer  {}", token.token).parse().unwrap(),
        );
        assert_eq!(Credentials::from_headers(&h).token_hash, Some(token.hash));
        h.insert(header::AUTHORIZATION, "Bearer nope".parse().unwrap());
        assert!(Credentials::from_headers(&h).token_hash.is_none());
        h.insert(
            header::AUTHORIZATION,
            format!("Basic {}", token.token).parse().unwrap(),
        );
        assert!(Credentials::from_headers(&h).token_hash.is_none());
    }
}

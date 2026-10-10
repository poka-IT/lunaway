//! Every write: signing in, the account, contributions, favourites. Each
//! resolver checks who calls (`auth`), what their level allows, the quota
//! of the action, then calls a repository of `lunaway-db`. None writes the
//! catalogue: places change through submissions the conflation worker
//! applies.

use async_graphql::{Context, ErrorExtensions, Object, Result};
use chrono::{NaiveDate, Utc};
use lunaway_auth::{DevicePublicKey, Locale, RecoveryCode, challenge_message};
use lunaway_db::{
    accounts::{self, Endorsement},
    community::{self as contributions, ReportOutcome, ReviewWrite},
    idempotency::{self, Key, Once, Operation, Seen},
    lists::{self, ListRefusal},
    poi_reviews::{self, PoiReviewWrite},
    pois, road_events,
    submissions::{self, NewSubmission, Submitted, Withdrawal},
};
use lunaway_domain::{
    Position,
    community::{
        NOTE_MAX_CHARS, REVIEW_TEXT_CHARS, ReviewStatus,
        moderation::{TextFlag, check_text},
        pseudonym::normalize_pseudonym,
        submission::{self as rules, LocalizedDescription, NewPlace, PlacePatch},
        trust::Action as Level,
    },
    is_language_tag, poi as poi_rules,
    road_events::{Confidence, community as road_community},
};
use uuid::Uuid;

use crate::{
    auth::{self, ChallengeRefusal, Viewer, not_banned},
    client::ClientKey,
    community_types::{
        Account, AuthChallenge, Confirmation, FavoriteList, FavoriteListInput, FavoritePointInput,
        GqlConfirmationStatus, GqlIssueKind, GqlReportReason, GqlReportTarget, GqlVehicleKind,
        IssueReport, NewPlaceInput, PlaceDetailsInput, PlaceSubmission, RecoveryCodeResult, Review,
        SignInResult,
    },
    error::{
        forbidden, internal, invalid_input, not_found, quota_spent, unauthenticated, unavailable,
        unknown_key,
    },
    poi_review_types::PoiReview,
    poi_types::{NewVendingMachineInput, PoiConfirmation},
    quota::{Action, Subject},
    road_event_types::{GqlRoadEventCleared, RoadEventReportInput, RoadEventReportResult},
    schema::{DB_FIELD_COST, db, state},
};

/// Root of every write.
#[derive(Debug, Default)]
pub struct MutationRoot;

/// How close a vending machine of the same kind makes a new one a
/// duplicate, metres: GPS on a phone is within about 10 m outdoors.
const DUPLICATE_RADIUS_M: f64 = 25.0;

fn client(ctx: &Context<'_>) -> Subject {
    Subject::Client(
        ctx.data_opt::<ClientKey>()
            .copied()
            .unwrap_or(ClientKey::Unknown),
    )
}

/// Takes one use of `action` for `subject`.
fn quota(ctx: &Context<'_>, action: Action, subject: Subject, what: &str) -> Result<()> {
    state(ctx)
        .quotas
        .take(action, subject)
        .map_err(|wait| quota_spent(what, wait))
}

fn account_quota(ctx: &Context<'_>, viewer: &Viewer, action: Action, what: &str) -> Result<()> {
    quota(ctx, action, Subject::Account(viewer.id()), what)
}

/// Takes one road report from the account and one from its client address:
/// accounts are cheap, so one network must not report for a crowd.
fn road_report_quota(ctx: &Context<'_>, viewer: &Viewer) -> Result<()> {
    quota(ctx, Action::RoadReportClient, client(ctx), "road reports")?;
    account_quota(ctx, viewer, Action::RoadReport, "road reports")
}

/// A road report that could not be stored: `UNAVAILABLE` while the feeds
/// hold the writers' lock, an internal error otherwise.
fn road_write_failed(e: &lunaway_db::DbError) -> async_graphql::Error {
    if road_events::is_busy(e) {
        unavailable("road reports")
    } else {
        internal(e)
    }
}

/// The live place a contribution goes to, following merges.
async fn live_place(ctx: &Context<'_>, id: Uuid) -> Result<contributions::LivePlace> {
    let (pool, _permit) = db(ctx).await?;
    contributions::live_place(pool, id)
        .await
        .map_err(|e| internal(&e))?
        .ok_or_else(|| not_found("place"))
}

/// `NOT_FOUND` unless `id` is a live point, `INVALID_INPUT` when it is a
/// care practitioner's practice: a rating or a review of one, published
/// under CC BY with its author's name and day of visit, would say a
/// patient's health (`lunaway_domain::content::poi_takes_reviews`, the
/// same rule as for the open reviews).
async fn reviewable_poi(pool: &lunaway_db::PgPool, id: Uuid) -> Result<()> {
    match pois::live_kind(pool, id).await.map_err(|e| internal(&e))? {
        None => Err(not_found("point of interest")),
        Some(kind) if !lunaway_domain::content::poi_takes_reviews(kind) => Err(invalid_input(
            "a care practitioner's practice takes no rating nor review",
        )),
        Some(_) => Ok(()),
    }
}

/// The stars of a rating, 1 to 5.
fn review_stars(stars: i32) -> Result<i16> {
    i16::try_from(stars)
        .ok()
        .filter(|s| (1..=5).contains(s))
        .ok_or_else(|| invalid_input("stars: 1 to 5"))
}

/// The text of a review, trimmed, once it and the day of the visit and the
/// language given with it are valid.
fn review_text<'a>(
    text: &'a str,
    visited_on: Option<NaiveDate>,
    lang: Option<&str>,
) -> Result<&'a str> {
    let text = text.trim();
    if !REVIEW_TEXT_CHARS.contains(&text.chars().count()) {
        return Err(invalid_input("text: 10 to 2000 characters"));
    }
    let today = Utc::now().date_naive();
    if visited_on.is_some_and(|d| d > today.succ_opt().unwrap_or(today)) {
        return Err(invalid_input("visitedOn: not in the future"));
    }
    if lang.is_some_and(|l| !is_language_tag(l)) {
        return Err(invalid_input("lang: a BCP 47 tag such as fr or en"));
    }
    Ok(text)
}

fn note(text: Option<String>) -> Result<Option<String>> {
    let text = text.map(|t| t.trim().to_owned()).filter(|t| !t.is_empty());
    if text
        .as_ref()
        .is_some_and(|t| t.chars().count() > NOTE_MAX_CHARS)
    {
        return Err(invalid_input(format!(
            "note: at most {NOTE_MAX_CHARS} characters"
        )));
    }
    Ok(text)
}

/// The idempotency key of a request, checked: `None` without one. The
/// request's arguments, as JSON, tell a request sent again from another one
/// that reuses its key.
fn key_of<'a>(
    viewer: &Viewer,
    key: Option<&'a str>,
    operation: Operation,
    arguments: &serde_json::Value,
) -> Result<Option<Key<'a>>> {
    let Some(key) = key else {
        return Ok(None);
    };
    if !idempotency::is_valid_key(key) {
        return Err(invalid_input(
            "idempotencyKey: 8 to 128 characters of A-Z a-z 0-9 . _ : -",
        ));
    }
    Ok(Some(Key::of(viewer.id(), key, operation, arguments)))
}

fn key_reused() -> async_graphql::Error {
    invalid_input("idempotencyKey: already used for another request")
}

/// What a key says before any quota is taken: the id of what the same
/// request made before, or `None` to go on with the write.
async fn seen_before(ctx: &Context<'_>, key: Option<&Key<'_>>) -> Result<Option<Uuid>> {
    let Some(key) = key else {
        return Ok(None);
    };
    let (pool, _permit) = db(ctx).await?;
    match idempotency::lookup(pool, key)
        .await
        .map_err(|e| internal(&e))?
    {
        Seen::New => Ok(None),
        Seen::Replay(id) => Ok(Some(id)),
        Seen::Reused => Err(key_reused()),
    }
}

/// The submission a request sent again made the first time.
async fn submission_replayed(
    ctx: &Context<'_>,
    viewer: &Viewer,
    id: Uuid,
) -> Result<PlaceSubmission> {
    let (pool, _permit) = db(ctx).await?;
    submissions::submission_of(pool, viewer.id(), id)
        .await
        .map_err(|e| internal(&e))?
        .map(Into::into)
        .ok_or_else(|| not_found("submission"))
}

/// The confirmation a request sent again stored the first time.
async fn confirmation_replayed(
    ctx: &Context<'_>,
    viewer: &Viewer,
    id: Uuid,
) -> Result<Confirmation> {
    let (pool, _permit) = db(ctx).await?;
    contributions::confirmation_of(pool, viewer.id(), id)
        .await
        .map_err(|e| internal(&e))?
        .ok_or_else(|| not_found("confirmation"))
        .and_then(Confirmation::try_from)
}

/// The issue report a request sent again stored the first time.
async fn issue_replayed(ctx: &Context<'_>, viewer: &Viewer, id: Uuid) -> Result<IssueReport> {
    let (pool, _permit) = db(ctx).await?;
    contributions::issue_of(pool, viewer.id(), id)
        .await
        .map_err(|e| internal(&e))?
        .ok_or_else(|| not_found("issue report"))
        .and_then(IssueReport::try_from)
}

/// The road report a request sent again stored the first time, with its
/// event as it stands now.
async fn road_report_replayed(
    ctx: &Context<'_>,
    viewer: &Viewer,
    id: Uuid,
) -> Result<RoadEventReportResult> {
    let (pool, _permit) = db(ctx).await?;
    let done = road_events::report_of(pool, viewer.id(), id)
        .await
        .map_err(|e| internal(&e))?
        .ok_or_else(|| not_found("road report"))?;
    Ok(RoadEventReportResult {
        report_id: done.report_id,
        event_id: done.event_id,
        confidence: done.confidence.into(),
        expires_at: done.expires_at,
    })
}

/// Stores a submission, once for `key` when there is one.
async fn submit_keyed(
    ctx: &Context<'_>,
    viewer: &Viewer,
    key: Option<&Key<'_>>,
    s: NewSubmission<'_>,
) -> Result<PlaceSubmission> {
    let once = {
        let (pool, _permit) = db(ctx).await?;
        match key {
            None => Once::Done(
                submissions::submit(pool, s)
                    .await
                    .map_err(|e| internal(&e))?,
            ),
            Some(k) => submissions::submit_once(pool, k, s)
                .await
                .map_err(|e| internal(&e))?,
        }
    };
    match once {
        Once::Done(row) => Ok(row.into()),
        Once::Replay(id) => submission_replayed(ctx, viewer, id).await,
        Once::Reused => Err(key_reused()),
    }
}

fn list_name(name: &str) -> Result<String> {
    let name = name.split_whitespace().collect::<Vec<_>>().join(" ");
    if (1..=60).contains(&name.chars().count()) {
        Ok(name)
    } else {
        Err(invalid_input("name: 1 to 60 characters"))
    }
}

fn list_refused(r: ListRefusal) -> async_graphql::Error {
    match r {
        ListRefusal::NotFound => not_found("list"),
        ListRefusal::NameTaken => invalid_input("another list has this name"),
        ListRefusal::Full => invalid_input(format!(
            "an account keeps {} lists of {} places at most",
            lists::MAX_LISTS,
            lists::MAX_ITEMS
        )),
        ListRefusal::TooManyPoints => invalid_input(format!(
            "an account keeps {} saved points at most",
            lists::MAX_POINTS
        )),
    }
}

/// Most points one `importFavorites` call takes, all its lists together.
const IMPORT_POINTS: usize = 500;

/// [`FavoritePointInput::parse`] as the API's refusal.
fn saved_point(point: &FavoritePointInput) -> Result<lists::NewPoint> {
    point.parse().map_err(|e| invalid_input(e.to_string()))
}

/// The codes of the rules a text trips, joined; `None` when it trips none.
fn held_for(flags: &[TextFlag]) -> Option<String> {
    (!flags.is_empty()).then(|| flags.iter().map(|f| f.code()).collect::<Vec<_>>().join(","))
}

/// Runs argon2id on a blocking thread: it holds a core for tens of
/// milliseconds.
async fn recovery_hash(code: RecoveryCode) -> Result<[u8; 32]> {
    tokio::task::spawn_blocking(move || code.hash())
        .await
        .map_err(|e| internal(&e))?
        .map_err(|e| internal(&e))
}

/// Removes media files no row refers to any more; a failure is logged, the
/// rows are already gone.
async fn remove_files(ctx: &Context<'_>, files: &[String]) {
    for f in files {
        if let Err(error) = state(ctx).media.remove(f).await {
            tracing::error!(%error, "cannot remove a media file");
        }
    }
}

/// Deletes `account` and its files, after writing the deletion to the
/// journal a restore replays. A deletion that cannot be journaled is
/// refused (`UNAVAILABLE`): it would come back with the next restore.
async fn delete_account_of(ctx: &Context<'_>, account: Uuid) -> Result<bool> {
    // The line is written and synced before a database connection is
    // taken: the disk's wait holds none of the API's connections.
    if let Some(journal) = state(ctx).config.keeping.journal() {
        journal.record(account, Utc::now()).await.map_err(|error| {
            tracing::error!(%error, "an account deletion could not be journaled; refused");
            unavailable("account deletion")
        })?;
    }
    let (pool, permit) = db(ctx).await?;
    let deleted = accounts::delete_account(pool, account)
        .await
        .map_err(|e| internal(&e))?;
    drop(permit);
    if let Some(d) = &deleted {
        remove_files(ctx, &d.orphan_files).await;
    }
    Ok(deleted.is_some())
}

/// The session for `key`, creating its account when the key is new and
/// `create` allows it; `NOT_FOUND` for a new key otherwise.
async fn open_session_for(
    ctx: &Context<'_>,
    key: &DevicePublicKey,
    locale: Option<&str>,
    create: bool,
) -> Result<SignInResult> {
    let st = state(ctx);
    let ttl = st.config.auth.session_ttl.as_secs_f64();
    let thumbprint = key.thumbprint();
    let session = lunaway_auth::new_session_token().map_err(|e| internal(&e))?;
    let (pool, permit) = db(ctx).await?;
    // Two attempts: a sign-in racing another with the same new key finds
    // the account the other created.
    for _ in 0..2 {
        if let Some(k) = accounts::key_by_thumbprint(pool, &thumbprint)
            .await
            .map_err(|e| internal(&e))?
        {
            not_banned(k.banned)?;
            let expires = accounts::open_session(pool, &k, &session.hash, ttl)
                .await
                .map_err(|e| internal(&e))?;
            let account = accounts::account(pool, k.account_id)
                .await
                .map_err(|e| internal(&e))?
                .ok_or_else(unauthenticated)?;
            drop(permit);
            let viewer = Viewer {
                account,
                device_key_id: k.id,
                token_hash: session.hash,
                opened_at: Utc::now(),
            };
            return Ok(SignInResult {
                token: session.token,
                expires_at: expires,
                created: false,
                account: Account::load(ctx, viewer).await?,
            });
        }
        // The key of a banned account that deleted itself opens nothing
        // while its record lasts (`retention::BANNED_KEY_DAYS`).
        if accounts::key_banned(pool, &key.sec1_uncompressed())
            .await
            .map_err(|e| internal(&e))?
        {
            return Err(forbidden("this account is banned"));
        }
        if !create {
            return Err(unknown_key());
        }
        quota(
            ctx,
            Action::AccountCreation,
            client(ctx),
            "accounts created",
        )?;
        let pseudonym = lunaway_auth::generate_pseudonym(Locale::parse(locale.unwrap_or("fr")))
            .map_err(|e| internal(&e))?;
        let created = accounts::create_with_key(
            pool,
            accounts::NewAccount {
                pseudonym: &pseudonym,
                thumbprint: &thumbprint,
                public_key: &key.sec1_uncompressed(),
                session_hash: &session.hash,
                session_ttl_secs: ttl,
            },
        )
        .await;
        match created {
            Ok((account, expires)) => {
                let key = accounts::key_by_thumbprint(pool, &thumbprint)
                    .await
                    .map_err(|e| internal(&e))?
                    .ok_or_else(unauthenticated)?;
                drop(permit);
                let viewer = Viewer {
                    account,
                    device_key_id: key.id,
                    token_hash: session.hash,
                    opened_at: Utc::now(),
                };
                return Ok(SignInResult {
                    token: session.token,
                    expires_at: expires,
                    created: true,
                    account: Account::load(ctx, viewer).await?,
                });
            }
            Err(error) => {
                // Most likely the key was registered a moment ago by a
                // concurrent sign-in: the creation did not count.
                st.quotas.give_back(Action::AccountCreation, client(ctx));
                tracing::warn!(%error, "account creation failed; looking the key up again");
            }
        }
    }
    Err(internal(&std::io::Error::other(
        "the account could not be created twice in a row; the cause is logged above",
    )))
}

/// Checks a signed challenge: the key, the nonce (one of ours, unexpired),
/// the signature, then that the nonce was not answered before.
fn check_signed_challenge(
    ctx: &Context<'_>,
    public_key_jwk: &str,
    nonce: &str,
    signature: &str,
) -> Result<DevicePublicKey> {
    let key = DevicePublicKey::from_jwk_json(public_key_jwk)
        .map_err(|e| invalid_input(format!("publicKeyJwk: {e}")))?;
    let challenges = &state(ctx).challenges;
    let used = || invalid_input("nonce: unknown, used or expired; ask authChallenge for a new one");
    let checked = challenges.check(nonce).map_err(|r| match r {
        ChallengeRefusal::Invalid(e) => {
            invalid_input(format!("nonce: {e}; ask authChallenge for a new one"))
        }
        _ => used(),
    })?;
    key.verify(challenge_message(nonce).as_bytes(), signature)
        .map_err(|_| unauthenticated())?;
    challenges.answer(checked).map_err(|r| match r {
        ChallengeRefusal::Full => {
            quota_spent("sign-ins at once", std::time::Duration::from_secs(30))
        }
        _ => used(),
    })?;
    Ok(key)
}

fn patch_of(d: PlaceDetailsInput) -> Result<PlacePatch> {
    Ok(PlacePatch {
        name: d.name,
        kind: d.kind.map(Into::into),
        overnight: d.overnight.map(Into::into),
        services: d.services.map(|v| v.into_iter().map(Into::into).collect()),
        activities: d
            .activities
            .map(|v| v.into_iter().map(Into::into).collect()),
        description: d.description.map(|t| LocalizedDescription {
            lang: t.lang,
            text: t.text,
        }),
        price_parking_eur: d.price_parking_eur,
        price_services_eur: d.price_services_eur,
        max_height_m: d.max_height_m,
        capacity: d
            .capacity
            .map(|c| u32::try_from(c).map_err(|_| invalid_input("capacity: not negative")))
            .transpose()?,
        opening_hours: d.opening_hours,
        website: d.website,
        phone: d.phone,
        clear: d
            .clear
            .unwrap_or_default()
            .into_iter()
            .map(Into::into)
            .collect(),
    })
}

#[Object(name = "Mutation")]
impl MutationRoot {
    /// A sign-in challenge: sign `message` with the device key (ES256) and
    /// send it to `signIn` or `recoverAccount` within five minutes. 30 a
    /// minute per client. It costs like a database field, so a document
    /// cannot ask for many at once.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn auth_challenge(&self, ctx: &Context<'_>) -> Result<AuthChallenge> {
        quota(ctx, Action::Challenge, client(ctx), "challenges")?;
        let (nonce, ttl) = state(ctx).challenges.issue().map_err(|r| match r {
            ChallengeRefusal::Random(e) => internal(&e),
            _ => internal(&std::io::Error::other("a challenge could not be issued")),
        })?;
        Ok(AuthChallenge {
            message: challenge_message(&nonce),
            nonce,
            expires_at: Utc::now() + chrono::TimeDelta::from_std(ttl).unwrap_or_default(),
        })
    }

    /// Signs in with a device key: `signature` is the ES256 signature of
    /// the challenge's `message` (raw r||s or DER, base64url). An unknown
    /// key creates an account at level 0 with a generated pseudonym for
    /// `locale`, a language tag (French words for `fr` or none, German,
    /// Spanish, Italian or Dutch words for `de`, `es`, `it` or `nl`,
    /// English words for any other); with `createIfUnknown: false` it creates
    /// nothing and answers `NOT_FOUND` with `reason` `UNKNOWN_KEY` (a
    /// device signing in again to an account that may have been deleted or
    /// detached elsewhere). 10
    /// sign-ins a minute and 5 new accounts an hour per client.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn sign_in(
        &self,
        ctx: &Context<'_>,
        public_key_jwk: String,
        nonce: String,
        signature: String,
        locale: Option<String>,
        #[graphql(default = true)] create_if_unknown: bool,
    ) -> Result<SignInResult> {
        quota(ctx, Action::SignIn, client(ctx), "sign-ins")?;
        let key = check_signed_challenge(ctx, &public_key_jwk, &nonce, &signature)?;
        open_session_for(ctx, &key, locale.as_deref(), create_if_unknown).await
    }

    /// Ends every session of the account but the current one, on this
    /// device too (a token copied from it). Needs a session opened in the
    /// last ten minutes.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn sign_out_elsewhere(&self, ctx: &Context<'_>) -> Result<i32> {
        let viewer = auth::require_fresh(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        let ended = accounts::end_other_sessions(pool, viewer.id(), &viewer.token_hash)
            .await
            .map_err(|e| internal(&e))?;
        Ok(i32::try_from(ended).unwrap_or(i32::MAX))
    }

    /// Ends the current session.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn sign_out(&self, ctx: &Context<'_>) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        accounts::delete_session(pool, &viewer.token_hash)
            .await
            .map_err(|e| internal(&e))
    }

    /// A new recovery code for the paper card; it replaces the earlier one.
    /// The server keeps only its hash: this is the only time it is shown.
    /// Needs a session opened in the last ten minutes (otherwise
    /// `UNAUTHENTICATED` with `reason` `FRESH_SIGN_IN`: sign in again).
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn create_recovery_code(&self, ctx: &Context<'_>) -> Result<RecoveryCodeResult> {
        let viewer = auth::require_fresh(ctx).await?;
        account_quota(ctx, &viewer, Action::Account, "account changes")?;
        let code = RecoveryCode::generate().map_err(|e| internal(&e))?;
        let display = code.display();
        let hash = recovery_hash(code).await?;
        let (pool, _permit) = db(ctx).await?;
        accounts::set_recovery_code(pool, viewer.id(), &hash)
            .await
            .map_err(|e| internal(&e))?;
        Ok(RecoveryCodeResult { code: display })
    }

    /// Attaches a new device key to the account of a recovery code and
    /// signs in with it. The key must be fresh (not attached to another
    /// account). With `revokeOtherDevices`, every other device key of the
    /// account and its sessions go (a lost or stolen phone). 5 attempts an
    /// hour per client.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn recover_account(
        &self,
        ctx: &Context<'_>,
        code: String,
        public_key_jwk: String,
        nonce: String,
        signature: String,
        #[graphql(default = false)] revoke_other_devices: bool,
    ) -> Result<SignInResult> {
        quota(ctx, Action::Recovery, client(ctx), "recovery attempts")?;
        let key = check_signed_challenge(ctx, &public_key_jwk, &nonce, &signature)?;
        let code =
            RecoveryCode::parse(&code).ok_or_else(|| invalid_input("code: not a recovery code"))?;
        let hash = recovery_hash(code).await?;
        let st = state(ctx);
        let session = lunaway_auth::new_session_token().map_err(|e| internal(&e))?;
        let (pool, permit) = db(ctx).await?;
        let (account_id, banned) = accounts::account_by_recovery_code(pool, &hash)
            .await
            .map_err(|e| internal(&e))?
            .ok_or_else(|| not_found("account with this recovery code"))?;
        not_banned(banned)?;
        if accounts::key_banned(pool, &key.sec1_uncompressed())
            .await
            .map_err(|e| internal(&e))?
        {
            return Err(forbidden("this device key belongs to a banned account"));
        }
        let (expires, key_id) = accounts::attach_key_and_open_session(
            pool,
            account_id,
            &key.thumbprint(),
            &key.sec1_uncompressed(),
            &session.hash,
            st.config.auth.session_ttl.as_secs_f64(),
        )
        .await
        .map_err(|e| internal(&e))?
        .ok_or_else(|| forbidden("this device key belongs to another account; use a new key"))?;
        if revoke_other_devices {
            accounts::revoke_devices(pool, account_id, None, key_id)
                .await
                .map_err(|e| internal(&e))?;
        }
        let account = accounts::account(pool, account_id)
            .await
            .map_err(|e| internal(&e))?
            .ok_or_else(|| not_found("account"))?;
        drop(permit);
        let viewer = Viewer {
            account,
            device_key_id: key_id,
            token_hash: session.hash,
            opened_at: Utc::now(),
        };
        Ok(SignInResult {
            token: session.token,
            expires_at: expires,
            created: false,
            account: Account::load(ctx, viewer).await?,
        })
    }

    /// Deletes the account: keys, sessions, recovery code, lists, mutes and
    /// photos go; published reviews, confirmations and place edits stay
    /// without author. `confirm` must be `DELETE`. Needs a session opened
    /// in the last ten minutes. The deletion is also written to a journal
    /// kept outside the backups, so a restored backup never brings the
    /// account back; `UNAVAILABLE` when that journal cannot be written
    /// (nothing is deleted): try again later.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_account(&self, ctx: &Context<'_>, confirm: String) -> Result<bool> {
        if confirm != "DELETE" {
            return Err(invalid_input("confirm must be DELETE"));
        }
        let viewer = auth::require_fresh(ctx).await?;
        delete_account_of(ctx, viewer.id()).await
    }

    /// Deletes the account of a recovery code, as `deleteAccount` does (the
    /// lunaway.net/account/delete page), journal included; a banned
    /// account may too, and the hashes of its device keys are then kept
    /// two years so they cannot open a new account (`FORBIDDEN` on
    /// `signIn`). 5 attempts an hour per client.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_account_with_recovery_code(
        &self,
        ctx: &Context<'_>,
        code: String,
    ) -> Result<bool> {
        quota(ctx, Action::Recovery, client(ctx), "recovery attempts")?;
        let code =
            RecoveryCode::parse(&code).ok_or_else(|| invalid_input("code: not a recovery code"))?;
        let hash = recovery_hash(code).await?;
        let (pool, permit) = db(ctx).await?;
        let (account, _) = accounts::account_by_recovery_code(pool, &hash)
            .await
            .map_err(|e| internal(&e))?
            .ok_or_else(|| not_found("account with this recovery code"))?;
        drop(permit);
        delete_account_of(ctx, account).await
    }

    /// Changes the public pseudonym: 3 to 32 characters, letters required,
    /// no insult, link or contact detail.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn update_profile(&self, ctx: &Context<'_>, pseudonym: String) -> Result<Account> {
        let mut viewer = auth::require(ctx).await?;
        account_quota(ctx, &viewer, Action::Account, "account changes")?;
        let pseudonym = normalize_pseudonym(&pseudonym)
            .map_err(|e| invalid_input(format!("pseudonym: {e}")))?;
        {
            let (pool, _permit) = db(ctx).await?;
            accounts::set_pseudonym(pool, viewer.id(), &pseudonym)
                .await
                .map_err(|e| internal(&e))?;
        }
        viewer.account.pseudonym = pseudonym;
        Account::load(ctx, viewer).await
    }

    /// Rates a place, 1 to 5 stars: one rating per account and place,
    /// replaced by a new one. Published at once. Level 0.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn rate(&self, ctx: &Context<'_>, place_id: Uuid, stars: i32) -> Result<Review> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let stars = review_stars(stars)?;
        account_quota(ctx, &viewer, Action::Rating, "ratings")?;
        let place = live_place(ctx, place_id).await?;
        let row = {
            let (pool, _permit) = db(ctx).await?;
            contributions::rate(pool, viewer.id(), place.id, stars)
                .await
                .map_err(|e| internal(&e))?
        };
        auth::after_contribution(ctx, &viewer).await;
        Ok(Review(row))
    }

    /// Writes a review (CC BY 4.0): stars and 10 to 2000 characters of
    /// text, with the day of the stay, the vehicle and the language. One
    /// per account and place; a new one replaces it. A text that trips the
    /// automatic rules (links, contact details, repetition, banned words)
    /// waits for a moderator (`PENDING`). Level 1; 20 a day.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    #[allow(
        clippy::too_many_arguments,
        reason = "one argument per field of the review, as the contract names them"
    )]
    async fn review(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        stars: i32,
        text: String,
        visited_on: Option<NaiveDate>,
        vehicle: Option<GqlVehicleKind>,
        lang: Option<String>,
    ) -> Result<Review> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Review).await?;
        let stars = review_stars(stars)?;
        let text = review_text(&text, visited_on, lang.as_deref())?;
        account_quota(ctx, &viewer, Action::Review, "reviews")?;
        let place = live_place(ctx, place_id).await?;
        let mut flags = check_text(text);
        let (pool, permit) = db(ctx).await?;
        if !flags.contains(&TextFlag::Repetition)
            && contributions::same_text_elsewhere(pool, viewer.id(), place.id, text)
                .await
                .map_err(|e| internal(&e))?
        {
            flags.push(TextFlag::Repetition);
            flags.sort();
        }
        let held = held_for(&flags);
        let vehicle: Option<lunaway_domain::community::VehicleKind> = vehicle.map(Into::into);
        let row = contributions::review(
            pool,
            ReviewWrite {
                account: viewer.id(),
                place: place.id,
                stars,
                body: text,
                lang: lang.as_deref(),
                visited_on,
                vehicle: vehicle.map(lunaway_domain::community::VehicleKind::code),
                status: if held.is_some() {
                    ReviewStatus::Pending
                } else {
                    ReviewStatus::Published
                },
                held_for: held.as_deref(),
            },
        )
        .await
        .map_err(|e| internal(&e))?;
        drop(permit);
        auth::after_contribution(ctx, &viewer).await;
        Ok(Review(row))
    }

    /// Deletes one of the caller's ratings or reviews, of a place or of a
    /// point of interest.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_review(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        if contributions::delete_review(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
            .is_some()
        {
            return Ok(true);
        }
        poi_reviews::delete(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
            .map(|_| true)
            .ok_or_else(|| not_found("review"))
    }

    /// Rates a point of interest or an establishment, 1 to 5 stars: one
    /// rating per account and point, replaced by a new one. Published at
    /// once. Level 0, counted with the ratings of places. `NOT_FOUND` for a
    /// point that does not exist, is gone or is hidden; `INVALID_INPUT` for
    /// a care practitioner's practice (`Poi.takesReviews` false).
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn rate_poi(&self, ctx: &Context<'_>, poi_id: Uuid, stars: i32) -> Result<PoiReview> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let stars = review_stars(stars)?;
        account_quota(ctx, &viewer, Action::Rating, "ratings")?;
        let row = {
            let (pool, _permit) = db(ctx).await?;
            reviewable_poi(pool, poi_id).await?;
            poi_reviews::rate(pool, viewer.id(), poi_id, stars)
                .await
                .map_err(|e| internal(&e))?
        };
        auth::after_contribution(ctx, &viewer).await;
        Ok(PoiReview(row))
    }

    /// Writes a review of a point of interest or an establishment (CC BY
    /// 4.0): stars and 10 to 2000 characters of text, with the day of the
    /// visit and the language. One per account and point; a new one
    /// replaces it. The rules of `review`: a text that trips the automatic
    /// rules (links, contact details, repetition, banned words) waits for a
    /// moderator (`PENDING`). Level 1; counted with the reviews of places
    /// (20 a day). `NOT_FOUND` for a point that does not exist, is gone or
    /// is hidden; `INVALID_INPUT` for a care practitioner's practice
    /// (`Poi.takesReviews` false).
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn review_poi(
        &self,
        ctx: &Context<'_>,
        poi_id: Uuid,
        stars: i32,
        text: String,
        visited_on: Option<NaiveDate>,
        lang: Option<String>,
    ) -> Result<PoiReview> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Review).await?;
        let stars = review_stars(stars)?;
        let text = review_text(&text, visited_on, lang.as_deref())?;
        account_quota(ctx, &viewer, Action::Review, "reviews")?;
        let mut flags = check_text(text);
        let (pool, permit) = db(ctx).await?;
        reviewable_poi(pool, poi_id).await?;
        if !flags.contains(&TextFlag::Repetition)
            && poi_reviews::same_text_elsewhere(pool, viewer.id(), poi_id, text)
                .await
                .map_err(|e| internal(&e))?
        {
            flags.push(TextFlag::Repetition);
            flags.sort();
        }
        let held = held_for(&flags);
        let row = poi_reviews::review(
            pool,
            PoiReviewWrite {
                account: viewer.id(),
                poi: poi_id,
                stars,
                body: text,
                lang: lang.as_deref(),
                visited_on,
                status: if held.is_some() {
                    ReviewStatus::Pending
                } else {
                    ReviewStatus::Published
                },
                held_for: held.as_deref(),
            },
        )
        .await
        .map_err(|e| internal(&e))?;
        drop(permit);
        auth::after_contribution(ctx, &viewer).await;
        Ok(PoiReview(row))
    }

    /// Answers "is it still there?"; no position is sent or kept.
    /// `CLOSED` and `CHANGED` open a check for moderators. Level 0. With
    /// `idempotencyKey` (8 to 128 characters of `A-Z a-z 0-9 . _ : -`, the
    /// outbox entry's id), the same request sent again while the key lives
    /// (30 days by default, 14 for a road report) returns the confirmation
    /// the first one stored instead of a second one; the same key with
    /// other arguments is `INVALID_INPUT`. A key goes with what it made:
    /// once that is deleted or withdrawn, the same request makes a new one.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn confirm(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        status: GqlConfirmationStatus,
        note: Option<String>,
        idempotency_key: Option<String>,
    ) -> Result<Confirmation> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let note = self::note(note)?;
        let status: lunaway_domain::community::ConfirmationStatus = status.into();
        let key = key_of(
            &viewer,
            idempotency_key.as_deref(),
            Operation::Confirm,
            &serde_json::json!({"placeId": place_id, "status": status.code(), "note": note}),
        )?;
        if let Some(id) = seen_before(ctx, key.as_ref()).await? {
            return confirmation_replayed(ctx, &viewer, id).await;
        }
        account_quota(ctx, &viewer, Action::Confirmation, "confirmations")?;
        let place = live_place(ctx, place_id).await?;
        let once = {
            let (pool, _permit) = db(ctx).await?;
            match &key {
                None => Once::Done(
                    contributions::confirm(pool, viewer.id(), place.id, status, note.as_deref())
                        .await
                        .map_err(|e| internal(&e))?,
                ),
                Some(k) => contributions::confirm_once(pool, k, place.id, status, note.as_deref())
                    .await
                    .map_err(|e| internal(&e))?,
            }
        };
        let row = match once {
            Once::Done(row) => row,
            Once::Replay(id) => return confirmation_replayed(ctx, &viewer, id).await,
            Once::Reused => return Err(key_reused()),
        };
        auth::after_contribution(ctx, &viewer).await;
        Confirmation::try_from(row)
    }

    /// Deletes one of the caller's confirmations.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_confirmation(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        contributions::delete_confirmation(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
            .map(|_| true)
            .ok_or_else(|| not_found("confirmation"))
    }

    /// Answers "still there?" about a point of interest (a vending
    /// machine, a fountain, a shop), shown or hidden. Level 0, counted with
    /// the place confirmations. Three accounts of level 1 and up saying it
    /// is gone hide it and send it to the moderators; a "still there" of an
    /// account of level 1 and up after them shows it again. Applied by the
    /// server within seconds.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn confirm_poi(
        &self,
        ctx: &Context<'_>,
        poi_id: Uuid,
        still_there: bool,
    ) -> Result<PoiConfirmation> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        account_quota(ctx, &viewer, Action::Confirmation, "confirmations")?;
        let (id, created_at) = {
            let (pool, _permit) = db(ctx).await?;
            // A hidden point can be answered: whoever finds it brings it
            // back.
            if !pois::exists(pool, poi_id).await.map_err(|e| internal(&e))? {
                return Err(not_found("point of interest"));
            }
            pois::confirm(pool, viewer.id(), poi_id, still_there)
                .await
                .map_err(|e| internal(&e))?
        };
        auth::after_contribution(ctx, &viewer).await;
        Ok(PoiConfirmation {
            id,
            poi_id,
            still_there,
            created_at,
        })
    }

    /// Deletes one of the caller's "still there?" answers about a point.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_poi_confirmation(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        pois::delete_confirmation(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
            .then_some(true)
            .ok_or_else(|| not_found("confirmation"))
    }

    /// Adds a vending machine where it stands: a pizza, bread or farm
    /// products machine, in two gestures. Level 1; counted with the new
    /// places and edits. It joins the points of interest under the ODbL
    /// as the community's, within seconds; a name or operator the
    /// automatic rules flag waits for a moderator. A machine of the same
    /// kind within 25 m is refused (`INVALID_INPUT` with `existingId`):
    /// confirm that one instead.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn add_vending_machine(
        &self,
        ctx: &Context<'_>,
        input: NewVendingMachineInput,
    ) -> Result<PlaceSubmission> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::AddPoi).await?;
        let position = Position::new(input.lat, input.lon)
            .map_err(|e| invalid_input(format!("position: {e}")))?;
        let machine = poi_rules::validate_vending(&poi_rules::NewVendingMachine {
            kind: input.kind.into(),
            position,
            name: input.name,
            operator: input.operator,
            brand: input.brand,
            products: input.products.unwrap_or_default(),
            payment: input.payment.unwrap_or_default(),
            always_open: input.always_open.unwrap_or(false),
        })
        .map_err(|e| invalid_input(e.to_string()))?;
        account_quota(ctx, &viewer, Action::Submission, "new places and edits")?;
        let mut flags: Vec<TextFlag> = [&machine.name, &machine.operator, &machine.brand]
            .into_iter()
            .flatten()
            .flat_map(|t| check_text(t))
            .collect();
        flags.sort();
        flags.dedup();
        let held = held_for(&flags);
        let (pool, _permit) = db(ctx).await?;
        if let Some(existing) = pois::vending_near(pool, position, machine.kind, DUPLICATE_RADIUS_M)
            .await
            .map_err(|e| internal(&e))?
        {
            return Err(
                invalid_input("a vending machine of this kind is mapped within 25 m")
                    .extend_with(|_, x| x.set("existingId", existing.to_string())),
            );
        }
        let row = submissions::submit(
            pool,
            NewSubmission {
                account: viewer.id(),
                device_key: viewer.device_key_id,
                what: Submitted::Poi(&machine),
                accepted: held.is_none(),
                held_for: held.as_deref(),
            },
        )
        .await
        .map_err(|e| internal(&e))?;
        Ok(row.into())
    }

    /// Reports what is seen on the road: a closed road, works, a narrow
    /// passage, a low clearance with its height, in the countries of
    /// `routing.roadEventReportCountries`. Level 0; 30 a day per
    /// account, 100 per client address. One account's report warns the
    /// others. Two reports of the same thing at the same spot (within
    /// 100 m, heading the same way, a measured figure within 0.2 m) from
    /// two accounts of level 1 or more, within two hours, make it block
    /// their routes, and a moderator is told. It lasts 12 hours (a closure)
    /// or 7 days after the last confirming pair, or the last report while
    /// unconfirmed. `UNAVAILABLE` when the feeds are being written: try
    /// again. `idempotencyKey` as for `confirm`: a report sent again
    /// returns the first one, with its event as it stands now.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn report_road_event(
        &self,
        ctx: &Context<'_>,
        input: RoadEventReportInput,
        idempotency_key: Option<String>,
    ) -> Result<RoadEventReportResult> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let at = Position::new(input.lat, input.lon)
            .map_err(|e| invalid_input(format!("position: {e}")))?;
        if !lunaway_domain::road_events::community::in_report_area(at) {
            return Err(invalid_input(
                "the position is outside the area road events may be reported in \
                 (routing.roadEventReportCountries)",
            ));
        }
        let heading_deg = input
            .heading_deg
            .map(|h| u16::try_from(h).ok().filter(|h| *h < 360))
            .map(|h| h.ok_or_else(|| invalid_input("headingDeg must be between 0 and 359")))
            .transpose()?;
        let kind = road_community::ReportKind::from(input.kind);
        road_community::validate(kind, input.value_m).map_err(|e| invalid_input(e.to_string()))?;
        // The position and course stay out of the key's digest: kept with
        // the account and the time, a digest of them would let a guess of
        // where someone was be checked.
        let key = key_of(
            &viewer,
            idempotency_key.as_deref(),
            Operation::ReportRoadEvent,
            &serde_json::json!({"kind": kind.code(), "valueM": input.value_m}),
        )?;
        if let Some(id) = seen_before(ctx, key.as_ref()).await? {
            return road_report_replayed(ctx, &viewer, id).await;
        }
        road_report_quota(ctx, &viewer)?;
        let report = road_events::NewReport {
            account: viewer.id(),
            kind,
            at,
            heading_deg,
            value_m: input.value_m,
        };
        let once = {
            let (pool, _permit) = db(ctx).await?;
            match &key {
                None => Once::Done(
                    road_events::report(pool, &report, chrono::Utc::now())
                        .await
                        .map_err(|e| road_write_failed(&e))?,
                ),
                Some(k) => road_events::report_once(pool, k, &report, chrono::Utc::now())
                    .await
                    .map_err(|e| road_write_failed(&e))?,
            }
        };
        let done = match once {
            Once::Done(done) => done,
            Once::Replay(id) => return road_report_replayed(ctx, &viewer, id).await,
            Once::Reused => return Err(key_reused()),
        };
        auth::after_contribution(ctx, &viewer).await;
        Ok(RoadEventReportResult {
            report_id: done.report_id,
            event_id: done.event_id,
            confidence: done.confidence.into(),
            expires_at: done.expires_at,
        })
    }

    /// Says a community road event is over ("plus de travaux"). It ends
    /// when its only reporter says so, or two accounts of level 1 or more
    /// have since its last report; one such account makes a blocking event
    /// a warning again; a level-0 account's is recorded for the moderators
    /// when the event blocks. Level 0, counted with the road reports. An
    /// official event (`source` other than `community`) ends with its
    /// source: `INVALID_INPUT`.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn clear_road_event(
        &self,
        ctx: &Context<'_>,
        event_id: Uuid,
    ) -> Result<GqlRoadEventCleared> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        road_report_quota(ctx, &viewer)?;
        let outcome = {
            let (pool, _permit) = db(ctx).await?;
            road_events::clear(pool, viewer.id(), event_id, chrono::Utc::now())
                .await
                .map_err(|e| road_write_failed(&e))?
        };
        let done = match outcome {
            road_events::Cleared::Ended => GqlRoadEventCleared::Ended,
            road_events::Cleared::Noted(Confidence::Confirmed) => GqlRoadEventCleared::Noted,
            road_events::Cleared::Noted(_) => GqlRoadEventCleared::Warning,
            road_events::Cleared::Official => {
                return Err(invalid_input("an official road event ends with its source"));
            }
            _ => return Err(not_found("road event")),
        };
        auth::after_contribution(ctx, &viewer).await;
        Ok(done)
    }

    /// Reports a problem met at a place (a night ban, a broken service, no
    /// access, a danger); the note goes to moderators only. Level 0; 50
    /// reports a day. The place's card counts the reports of accounts of
    /// level 1 and up, each once per kind. `idempotencyKey` as for
    /// `confirm`.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn report_issue(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        kind: GqlIssueKind,
        note: Option<String>,
        idempotency_key: Option<String>,
    ) -> Result<IssueReport> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let note = self::note(note)?;
        let kind: lunaway_domain::community::IssueKind = kind.into();
        let key = key_of(
            &viewer,
            idempotency_key.as_deref(),
            Operation::ReportIssue,
            &serde_json::json!({"placeId": place_id, "kind": kind.code(), "note": note}),
        )?;
        if let Some(id) = seen_before(ctx, key.as_ref()).await? {
            return issue_replayed(ctx, &viewer, id).await;
        }
        account_quota(ctx, &viewer, Action::Report, "reports")?;
        let place = live_place(ctx, place_id).await?;
        let once = {
            let (pool, _permit) = db(ctx).await?;
            match &key {
                None => Once::Done(
                    contributions::report_issue(pool, viewer.id(), place.id, kind, note.as_deref())
                        .await
                        .map_err(|e| internal(&e))?,
                ),
                Some(k) => {
                    contributions::report_issue_once(pool, k, place.id, kind, note.as_deref())
                        .await
                        .map_err(|e| internal(&e))?
                }
            }
        };
        let row = match once {
            Once::Done(row) => row,
            Once::Replay(id) => return issue_replayed(ctx, &viewer, id).await,
            Once::Reused => return Err(key_reused()),
        };
        // The summary counts the reports of accounts past level 0: the
        // stored level must be current.
        auth::after_contribution(ctx, &viewer).await;
        IssueReport::try_from(row)
    }

    /// Deletes one of the caller's issue reports.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_issue_report(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        contributions::delete_issue(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
            .map(|_| true)
            .ok_or_else(|| not_found("issue report"))
    }

    /// Adds a place. It becomes a record of the `community` source, merged
    /// by the conflation with what other sources say of the same spot,
    /// within seconds; a place only the community describes is `TO_VERIFY`
    /// until two other accounts confirm it. A name or description that
    /// trips the automatic rules waits for a moderator, and so does a place
    /// within a few hundred metres of a spot taken down for good (applied,
    /// with `placeId` null until a moderator releases it). Level 2.
    /// `idempotencyKey` as for `confirm`.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn add_place(
        &self,
        ctx: &Context<'_>,
        input: NewPlaceInput,
        idempotency_key: Option<String>,
    ) -> Result<PlaceSubmission> {
        let viewer = auth::require(ctx).await?;
        let level = auth::require_level(ctx, &viewer, Level::AddPlace).await?;
        let position = Position::new(input.lat, input.lon)
            .map_err(|e| invalid_input(format!("position: {e}")))?;
        let new = rules::validate_new_place(&NewPlace {
            kind: input.kind.into(),
            position,
            details: patch_of(input.details)?,
        })
        .map_err(|e| invalid_input(e.to_string()))?;
        let key = key_of(
            &viewer,
            idempotency_key.as_deref(),
            Operation::AddPlace,
            &serde_json::to_value(&new).map_err(|e| internal(&e))?,
        )?;
        if let Some(id) = seen_before(ctx, key.as_ref()).await? {
            return submission_replayed(ctx, &viewer, id).await;
        }
        account_quota(ctx, &viewer, Action::Submission, "new places and edits")?;
        let flags = flags_of(&new.details, level);
        let held = held_for(&flags);
        submit_keyed(
            ctx,
            &viewer,
            key.as_ref(),
            NewSubmission {
                account: viewer.id(),
                device_key: viewer.device_key_id,
                what: Submitted::Create(&new),
                accepted: held.is_none(),
                held_for: held.as_deref(),
            },
        )
        .await
    }

    /// Edits a place: what `patch` states replaces the community's value,
    /// and the fields in `patch.clear` lose it (the value shown still
    /// follows each field's most trusted source). From level 3 the edit
    /// applies within seconds; below, from level 1, it waits for a
    /// moderator. Every edit is kept as a revision. `idempotencyKey` as for
    /// `confirm`.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn edit_place(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        patch: PlaceDetailsInput,
        idempotency_key: Option<String>,
    ) -> Result<PlaceSubmission> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Review).await?;
        let patch =
            rules::validate_edit(&patch_of(patch)?).map_err(|e| invalid_input(e.to_string()))?;
        let key = key_of(
            &viewer,
            idempotency_key.as_deref(),
            Operation::EditPlace,
            &serde_json::json!({
                "placeId": place_id,
                "patch": serde_json::to_value(&patch).map_err(|e| internal(&e))?,
            }),
        )?;
        if let Some(id) = seen_before(ctx, key.as_ref()).await? {
            return submission_replayed(ctx, &viewer, id).await;
        }
        account_quota(ctx, &viewer, Action::Submission, "new places and edits")?;
        let place = live_place(ctx, place_id).await?;
        let level = {
            let (pool, _permit) = db(ctx).await?;
            auth::compute_level(pool, &state(ctx).config.trust, viewer.id())
                .await
                .map_err(|e| internal(&e))?
                .map_or(0, |(l, _)| l)
        };
        let direct = level >= Level::EditPlaceDirectly.required_level();
        let flags = flags_of(&patch, level);
        let held = held_for(&flags);
        submit_keyed(
            ctx,
            &viewer,
            key.as_ref(),
            NewSubmission {
                account: viewer.id(),
                device_key: viewer.device_key_id,
                what: Submitted::Edit {
                    place: place.id,
                    patch: &patch,
                },
                accepted: direct && held.is_none(),
                held_for: held.as_deref(),
            },
        )
        .await
    }

    /// Deletes one of the caller's new places or edits: one not yet
    /// applied is withdrawn; one already in the places database stays
    /// there (ODbL) without its author.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_place_submission(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        match submissions::withdraw(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
        {
            Withdrawal::NotFound => Err(not_found("submission")),
            Withdrawal::Withdrawn | Withdrawal::Detached => Ok(true),
        }
    }

    /// Deletes one of the caller's photos, files included.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_photo(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let gone = {
            let (pool, _permit) = db(ctx).await?;
            contributions::delete_photo(pool, viewer.id(), id)
                .await
                .map_err(|e| internal(&e))?
        };
        let Some((_, files)) = gone else {
            return Err(not_found("photo"));
        };
        remove_files(ctx, &files).await;
        Ok(true)
    }

    /// Hides every contribution of `accountId` from the caller.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn mute_author(&self, ctx: &Context<'_>, account_id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        if account_id == viewer.id() {
            return Err(invalid_input("accountId: not the caller's own"));
        }
        account_quota(ctx, &viewer, Action::Account, "account changes")?;
        let (pool, _permit) = db(ctx).await?;
        if contributions::mute(pool, viewer.id(), account_id)
            .await
            .map_err(|e| internal(&e))?
        {
            Ok(true)
        } else {
            Err(not_found("account"))
        }
    }

    /// Shows the contributions of `accountId` again.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn unmute_author(&self, ctx: &Context<'_>, account_id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        contributions::unmute(pool, viewer.id(), account_id)
            .await
            .map_err(|e| internal(&e))?;
        Ok(true)
    }

    /// Reports a review (of a place, or of a point of interest with
    /// `POI_REVIEW`), a photo or a place to the moderators. Three accounts
    /// reporting a review or a photo hide it until a moderator decides.
    /// Level 0; 50 reports a day.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn report_content(
        &self,
        ctx: &Context<'_>,
        target: GqlReportTarget,
        id: Uuid,
        reason: GqlReportReason,
        note: Option<String>,
    ) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let note = self::note(note)?;
        account_quota(ctx, &viewer, Action::Report, "reports")?;
        // Only reporters past level 0 count toward hiding: their stored
        // level must be current (the age rule moves without a contribution).
        auth::after_contribution(ctx, &viewer).await;
        let (pool, _permit) = db(ctx).await?;
        match contributions::report_content(
            pool,
            viewer.id(),
            target.into(),
            id,
            reason.into(),
            note.as_deref(),
            lunaway_domain::community::HIDE_AFTER_REPORTS,
        )
        .await
        .map_err(|e| internal(&e))?
        {
            ReportOutcome::NoTarget => Err(not_found("content")),
            ReportOutcome::Queued | ReportOutcome::Hidden => Ok(true),
        }
    }

    /// Creates a favourite list.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn create_list(&self, ctx: &Context<'_>, name: String) -> Result<FavoriteList> {
        let viewer = auth::require(ctx).await?;
        let name = list_name(&name)?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        let id = lists::create(pool, viewer.id(), &name)
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        one_list(pool, viewer.id(), id).await
    }

    /// Renames one of the caller's lists.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn rename_list(&self, ctx: &Context<'_>, id: Uuid, name: String) -> Result<FavoriteList> {
        let viewer = auth::require(ctx).await?;
        let name = list_name(&name)?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        lists::rename(pool, viewer.id(), id, &name)
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        one_list(pool, viewer.id(), id).await
    }

    /// Deletes one of the caller's lists.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_list(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        if lists::delete(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
        {
            Ok(true)
        } else {
            Err(not_found("list"))
        }
    }

    /// Adds a place to one of the caller's lists.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn save_to_list(
        &self,
        ctx: &Context<'_>,
        list_id: Uuid,
        place_id: Uuid,
    ) -> Result<FavoriteList> {
        let viewer = auth::require(ctx).await?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let place = live_place(ctx, place_id).await?;
        let (pool, _permit) = db(ctx).await?;
        lists::add(pool, viewer.id(), list_id, &[place.id])
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        one_list(pool, viewer.id(), list_id).await
    }

    /// Removes a place from one of the caller's lists.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn remove_from_list(
        &self,
        ctx: &Context<'_>,
        list_id: Uuid,
        place_id: Uuid,
    ) -> Result<FavoriteList> {
        let viewer = auth::require(ctx).await?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        lists::remove(pool, viewer.id(), list_id, place_id)
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        one_list(pool, viewer.id(), list_id).await
    }

    /// Saves a point (an address, a town, a bare point of the map, a shop
    /// or a service) in one of the caller's lists, or updates the point of
    /// the same id there: the last write wins. An account keeps 2000 saved
    /// points at most.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn save_point_to_list(
        &self,
        ctx: &Context<'_>,
        list_id: Uuid,
        point: FavoritePointInput,
    ) -> Result<FavoriteList> {
        let viewer = auth::require(ctx).await?;
        let point = saved_point(&point)?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        lists::save_point(pool, viewer.id(), list_id, &point)
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        one_list(pool, viewer.id(), list_id).await
    }

    /// Removes a saved point from one of the caller's lists; a point the
    /// list does not hold is already removed.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn remove_point_from_list(
        &self,
        ctx: &Context<'_>,
        list_id: Uuid,
        point_id: Uuid,
    ) -> Result<FavoriteList> {
        let viewer = auth::require(ctx).await?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        lists::remove_point(pool, viewer.id(), list_id, point_id)
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        one_list(pool, viewer.id(), list_id).await
    }

    /// Imports the favourites kept on the device before the account
    /// existed: each list merges into the account's list of the same name.
    /// At most 100 lists, 1000 places and 500 points per call (call again
    /// for more); unknown places are skipped, and a point the account's
    /// list already holds keeps the account's copy. Returns every list of
    /// the account.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn import_favorites(
        &self,
        ctx: &Context<'_>,
        lists: Vec<FavoriteListInput>,
    ) -> Result<Vec<FavoriteList>> {
        let viewer = auth::require(ctx).await?;
        let places: usize = lists.iter().map(|l| l.place_ids.len()).sum();
        let points: usize = lists.iter().map(|l| l.points.len()).sum();
        if lists.len() > 100 || places > 1_000 || points > IMPORT_POINTS {
            return Err(invalid_input(
                "at most 100 lists, 1000 places and 500 points per call; call again for the rest",
            ));
        }
        let imported = lists
            .into_iter()
            .enumerate()
            .map(|(i, l)| {
                // A refusal names the point it is about, so the device can
                // tell which of its points the server does not take.
                let points = l
                    .points
                    .iter()
                    .enumerate()
                    .map(|(j, p)| {
                        p.parse()
                            .map_err(|e| invalid_input(format!("lists[{i}].points[{j}].{e}")))
                    })
                    .collect::<Result<_>>()?;
                Ok(self::lists::ImportedList {
                    name: list_name(&l.name)?,
                    points,
                    places: l.place_ids,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        account_quota(ctx, &viewer, Action::List, "list changes")?;
        let (pool, _permit) = db(ctx).await?;
        self::lists::import(pool, viewer.id(), &imported)
            .await
            .map_err(|e| internal(&e))?
            .map_err(list_refused)?;
        Ok(self::lists::lists(pool, viewer.id())
            .await
            .map_err(|e| internal(&e))?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// Detaches one of the caller's other device keys and ends its sessions
    /// (a lost phone); `myAccount { devices }` lists them. The current
    /// device cannot detach itself: `signOut` ends its session. Needs a
    /// session opened in the last ten minutes.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn revoke_device(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require_fresh(ctx).await?;
        if id == viewer.device_key_id {
            return Err(invalid_input("id: not the current device; use signOut"));
        }
        account_quota(ctx, &viewer, Action::Account, "account changes")?;
        let (pool, _permit) = db(ctx).await?;
        match accounts::revoke_devices(pool, viewer.id(), Some(id), viewer.device_key_id)
            .await
            .map_err(|e| internal(&e))?
        {
            0 => Err(not_found("device")),
            _ => Ok(true),
        }
    }

    /// Sponsors a new account, which reaches level 1 at once. Level 2; 5 a
    /// day.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn sponsor_account(&self, ctx: &Context<'_>, account_id: Uuid) -> Result<bool> {
        endorse(ctx, account_id, Endorsement::Sponsor, Level::Sponsor).await
    }

    /// Nominates an account for level 3 (it still needs the activity the
    /// level asks). Level 4.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn nominate_account(&self, ctx: &Context<'_>, account_id: Uuid) -> Result<bool> {
        endorse(ctx, account_id, Endorsement::Nominate, Level::Nominate).await
    }
}

/// What the automatic rules find in `patch`: its texts checked like a
/// review, and a website or a phone (a link or a contact detail by nature)
/// held for a moderator unless the author's level allows direct edits.
fn flags_of(patch: &PlacePatch, level: u8) -> Vec<TextFlag> {
    let mut flags: Vec<TextFlag> = rules::texts(patch)
        .into_iter()
        .flat_map(check_text)
        .collect();
    if level < Level::EditPlaceDirectly.required_level() {
        if patch.website.is_some() {
            flags.push(TextFlag::Link);
        }
        if patch.phone.is_some() {
            flags.push(TextFlag::ContactDetails);
        }
    }
    flags.sort();
    flags.dedup();
    flags
}

async fn one_list(pool: &lunaway_db::PgPool, account: Uuid, id: Uuid) -> Result<FavoriteList> {
    lists::list(pool, account, id)
        .await
        .map_err(|e| internal(&e))?
        .map(Into::into)
        .ok_or_else(|| not_found("list"))
}

async fn endorse(
    ctx: &Context<'_>,
    account: Uuid,
    kind: Endorsement,
    level: Level,
) -> Result<bool> {
    let viewer = auth::require(ctx).await?;
    auth::require_level(ctx, &viewer, level).await?;
    if account == viewer.id() {
        return Err(invalid_input("accountId: not the caller's own"));
    }
    account_quota(
        ctx,
        &viewer,
        Action::Endorsement,
        "sponsorships and nominations",
    )?;
    let (pool, _permit) = db(ctx).await?;
    if !accounts::endorse(pool, account, kind, viewer.id())
        .await
        .map_err(|e| internal(&e))?
    {
        return Err(not_found("account"));
    }
    auth::compute_level(pool, &state(ctx).config.trust, account)
        .await
        .map_err(|e| internal(&e))?;
    Ok(true)
}

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
    lists::{self, ListRefusal},
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
        Account, AuthChallenge, Confirmation, FavoriteList, FavoriteListInput,
        GqlConfirmationStatus, GqlIssueKind, GqlReportReason, GqlReportTarget, GqlVehicleKind,
        IssueReport, NewPlaceInput, PlaceDetailsInput, PlaceSubmission, RecoveryCodeResult, Review,
        SignInResult,
    },
    error::{
        forbidden, internal, invalid_input, not_found, quota_spent, unauthenticated, unavailable,
    },
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
    }
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

/// The session for `key`, creating its account when the key is new.
async fn open_session_for(
    ctx: &Context<'_>,
    key: &DevicePublicKey,
    locale: Option<&str>,
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
    /// key creates an account at level 0 with a generated pseudonym in
    /// `locale` (`fr` or `en`). 10 sign-ins a minute and 5 new accounts an
    /// hour per client.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn sign_in(
        &self,
        ctx: &Context<'_>,
        public_key_jwk: String,
        nonce: String,
        signature: String,
        locale: Option<String>,
    ) -> Result<SignInResult> {
        quota(ctx, Action::SignIn, client(ctx), "sign-ins")?;
        let key = check_signed_challenge(ctx, &public_key_jwk, &nonce, &signature)?;
        open_session_for(ctx, &key, locale.as_deref()).await
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
    /// in the last ten minutes.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_account(&self, ctx: &Context<'_>, confirm: String) -> Result<bool> {
        if confirm != "DELETE" {
            return Err(invalid_input("confirm must be DELETE"));
        }
        let viewer = auth::require_fresh(ctx).await?;
        let (pool, permit) = db(ctx).await?;
        let deleted = accounts::delete_account(pool, viewer.id())
            .await
            .map_err(|e| internal(&e))?;
        drop(permit);
        if let Some(d) = &deleted {
            remove_files(ctx, &d.orphan_files).await;
        }
        Ok(deleted.is_some())
    }

    /// Deletes the account of a recovery code, as `deleteAccount` does (the
    /// lunaway.net/account/delete page). 5 attempts an hour per client.
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
        let deleted = accounts::delete_account(pool, account)
            .await
            .map_err(|e| internal(&e))?;
        drop(permit);
        if let Some(d) = &deleted {
            remove_files(ctx, &d.orphan_files).await;
        }
        Ok(deleted.is_some())
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
        let stars = i16::try_from(stars)
            .ok()
            .filter(|s| (1..=5).contains(s))
            .ok_or_else(|| invalid_input("stars: 1 to 5"))?;
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
        let stars = i16::try_from(stars)
            .ok()
            .filter(|s| (1..=5).contains(s))
            .ok_or_else(|| invalid_input("stars: 1 to 5"))?;
        let text = text.trim();
        if !REVIEW_TEXT_CHARS.contains(&text.chars().count()) {
            return Err(invalid_input("text: 10 to 2000 characters"));
        }
        let today = Utc::now().date_naive();
        if visited_on.is_some_and(|d| d > today.succ_opt().unwrap_or(today)) {
            return Err(invalid_input("visitedOn: not in the future"));
        }
        if lang.as_deref().is_some_and(|l| !is_language_tag(l)) {
            return Err(invalid_input("lang: a BCP 47 tag such as fr or en"));
        }
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

    /// Deletes one of the caller's ratings or reviews.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn delete_review(&self, ctx: &Context<'_>, id: Uuid) -> Result<bool> {
        let viewer = auth::require(ctx).await?;
        let (pool, _permit) = db(ctx).await?;
        contributions::delete_review(pool, viewer.id(), id)
            .await
            .map_err(|e| internal(&e))?
            .map(|_| true)
            .ok_or_else(|| not_found("review"))
    }

    /// Answers "is it still there?"; no position is sent or kept.
    /// `CLOSED` and `CHANGED` open a check for moderators. Level 0.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn confirm(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        status: GqlConfirmationStatus,
        note: Option<String>,
    ) -> Result<Confirmation> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let note = self::note(note)?;
        account_quota(ctx, &viewer, Action::Confirmation, "confirmations")?;
        let place = live_place(ctx, place_id).await?;
        let row = {
            let (pool, _permit) = db(ctx).await?;
            contributions::confirm(pool, viewer.id(), place.id, status.into(), note.as_deref())
                .await
                .map_err(|e| internal(&e))?
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
    /// passage, a low clearance with its height. Level 0; 30 a day per
    /// account, 100 per client address. One account's report warns the
    /// others. Two reports of the same thing at the same spot (within
    /// 100 m, heading the same way, a measured figure within 0.2 m) from
    /// two accounts of level 1 or more, within two hours, make it block
    /// their routes, and a moderator is told. It lasts 12 hours (a closure)
    /// or 7 days after the last confirming pair, or the last report while
    /// unconfirmed. `UNAVAILABLE` when the feeds are being written: try
    /// again.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn report_road_event(
        &self,
        ctx: &Context<'_>,
        input: RoadEventReportInput,
    ) -> Result<RoadEventReportResult> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let at = Position::new(input.lat, input.lon)
            .map_err(|e| invalid_input(format!("position: {e}")))?;
        if !lunaway_domain::routing::is_covered(at) {
            return Err(invalid_input(
                "the position is outside the area routes are computed in",
            ));
        }
        let heading_deg = input
            .heading_deg
            .map(|h| u16::try_from(h).ok().filter(|h| *h < 360))
            .map(|h| h.ok_or_else(|| invalid_input("headingDeg must be between 0 and 359")))
            .transpose()?;
        let kind = road_community::ReportKind::from(input.kind);
        road_community::validate(kind, input.value_m).map_err(|e| invalid_input(e.to_string()))?;
        road_report_quota(ctx, &viewer)?;
        let done = {
            let (pool, _permit) = db(ctx).await?;
            road_events::report(
                pool,
                &road_events::NewReport {
                    account: viewer.id(),
                    kind,
                    at,
                    heading_deg,
                    value_m: input.value_m,
                },
                chrono::Utc::now(),
            )
            .await
            .map_err(|e| road_write_failed(&e))?
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
    /// level 1 and up, each once per kind.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn report_issue(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        kind: GqlIssueKind,
        note: Option<String>,
    ) -> Result<IssueReport> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Basic).await?;
        let note = self::note(note)?;
        account_quota(ctx, &viewer, Action::Report, "reports")?;
        let place = live_place(ctx, place_id).await?;
        let row = {
            let (pool, _permit) = db(ctx).await?;
            contributions::report_issue(pool, viewer.id(), place.id, kind.into(), note.as_deref())
                .await
                .map_err(|e| internal(&e))?
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
    /// trips the automatic rules waits for a moderator. Level 2.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn add_place(&self, ctx: &Context<'_>, input: NewPlaceInput) -> Result<PlaceSubmission> {
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
        account_quota(ctx, &viewer, Action::Submission, "new places and edits")?;
        let flags = flags_of(&new.details, level);
        let held = held_for(&flags);
        let (pool, _permit) = db(ctx).await?;
        let row = submissions::submit(
            pool,
            NewSubmission {
                account: viewer.id(),
                device_key: viewer.device_key_id,
                what: Submitted::Create(&new),
                accepted: held.is_none(),
                held_for: held.as_deref(),
            },
        )
        .await
        .map_err(|e| internal(&e))?;
        Ok(row.into())
    }

    /// Edits a place: what `patch` states replaces the community's value
    /// (the value shown still follows each field's most trusted source).
    /// From level 3 the edit applies within seconds; below, from level 1,
    /// it waits for a moderator. Every edit is kept as a revision.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn edit_place(
        &self,
        ctx: &Context<'_>,
        place_id: Uuid,
        patch: PlaceDetailsInput,
    ) -> Result<PlaceSubmission> {
        let viewer = auth::require(ctx).await?;
        auth::require_level(ctx, &viewer, Level::Review).await?;
        let patch =
            rules::validate_edit(&patch_of(patch)?).map_err(|e| invalid_input(e.to_string()))?;
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
        let (pool, _permit) = db(ctx).await?;
        let row = submissions::submit(
            pool,
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
        .map_err(|e| internal(&e))?;
        Ok(row.into())
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

    /// Reports a review, a photo or a place to the moderators. Three
    /// accounts reporting a review or a photo hide it until a moderator
    /// decides. Level 0; 50 reports a day.
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

    /// Imports the favourites kept on the device before the account
    /// existed: each list merges into the account's list of the same name.
    /// At most 100 lists and 1000 places per call (call again for more);
    /// unknown places are skipped. Returns every list of the account.
    #[graphql(complexity = "DB_FIELD_COST + child_complexity")]
    async fn import_favorites(
        &self,
        ctx: &Context<'_>,
        lists: Vec<FavoriteListInput>,
    ) -> Result<Vec<FavoriteList>> {
        let viewer = auth::require(ctx).await?;
        let places: usize = lists.iter().map(|l| l.place_ids.len()).sum();
        if lists.len() > 100 || places > 1_000 {
            return Err(invalid_input(
                "at most 100 lists and 1000 places per call; call again for the rest",
            ));
        }
        let imported = lists
            .into_iter()
            .map(|l| Ok((list_name(&l.name)?, l.place_ids)))
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

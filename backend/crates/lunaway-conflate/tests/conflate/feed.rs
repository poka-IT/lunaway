//! Whatever takes something off a place's card moves the place in the
//! change feed, by box and by region: a device that synced before learns
//! the new summary at its next sync. A summary the worker recomputes only
//! when something else happens at the place would leave every device with
//! the old card until then.

use lunaway_conflate::run;
use lunaway_db::{
    PgPool, accounts, community,
    moderation::{self, Decision},
    places::{self, Change, PlaceRow},
    submissions::{self, NewSubmission, Submitted, Withdrawal},
};
use lunaway_domain::{
    BBox, PlaceKind, Position,
    community::{
        ConfirmationStatus, IssueKind, ReportReason, ReportTarget, ReviewStatus, Verification,
        submission::{NewPlace, PlacePatch},
    },
};
use uuid::Uuid;

use super::{account, as_role, at, ingest_fixtures, place_named};

/// The place as a device synced up to `cursor` receives it next, or `None`
/// when the feed does not carry it. The box and the region must agree:
/// devices sync by one or the other.
async fn fed(pool: &PgPool, place: Uuid, cursor: i64) -> Option<PlaceRow> {
    let france = BBox::new(41.0, -5.5, 51.5, 9.9).unwrap();
    let region = places::by_id(pool, place)
        .await
        .unwrap()
        .unwrap()
        .region
        .expect("a place in France has a sync region");
    let find = |changes: Vec<Change>| {
        changes.into_iter().find_map(|c| match c {
            Change::Upsert(p) if p.id == place => Some(*p),
            _ => None,
        })
    };
    let (by_box, _) = places::changes(pool, france, cursor, 1_000, true)
        .await
        .unwrap();
    let (by_region, _) = places::changes_in_region(pool, &region, cursor, 1_000, true)
        .await
        .unwrap();
    let (by_box, by_region) = (find(by_box), find(by_region));
    assert_eq!(
        by_box, by_region,
        "a device syncing by box and one syncing by region see the same place"
    );
    by_box
}

/// Runs the worker and returns the place as the feed carries it after
/// `cursor`, failing when the feed does not carry it.
async fn moved(pool: &PgPool, place: Uuid, cursor: i64, what: &str) -> PlaceRow {
    run(pool, at(2), None).await.unwrap();
    fed(pool, place, cursor)
        .await
        .unwrap_or_else(|| panic!("{what}: the place must come back in the change feed"))
}

/// An account of level 1: its confirmations and issue reports count.
async fn trusted(app: &PgPool, n: u8) -> Uuid {
    let a = account(app, n).await;
    accounts::set_trust_level(app, a, 1).await.unwrap();
    a
}

/// The stored path of a picture whose digest is `n` repeated.
fn media_path(n: u8) -> String {
    let digest = format!("{n:02x}").repeat(32);
    format!("photos/{n:02x}/{n:02x}/{digest}.webp")
}

/// A published photo of `account` at `place`, its files named after `n`.
async fn photo(app: &PgPool, account: Uuid, place: Uuid, n: u8) -> Uuid {
    community::add_photo(
        app,
        community::NewPhoto {
            account,
            place,
            path: &media_path(n),
            thumb_path: &media_path(n ^ 0xff),
            size: (800, 600),
            thumb_size: (200, 150),
            thumbhash: &[1, 2, 3],
        },
    )
    .await
    .unwrap()
    .id
}

#[sqlx::test(migrations = "../../migrations")]
async fn what_an_author_deletes_leaves_the_card_of_every_device(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let port = place_named(&pool, "Camping municipal du Port").await;
    let a = trusted(&app, 1).await;
    let confirmation = community::confirm(&app, a, port, ConfirmationStatus::StillOk, None)
        .await
        .unwrap()
        .id;
    let review = community::rate(&app, a, port, 4).await.unwrap().id;
    let photo = photo(&app, a, port, 1).await;
    let issue = community::report_issue(&app, a, port, IssueKind::NightBan, None)
        .await
        .unwrap()
        .id;
    run(&pool, at(2), None).await.unwrap();
    let card = places::by_id(&pool, port).await.unwrap().unwrap();
    assert!(card.last_confirmed_at.is_some());
    assert_eq!(
        (
            card.community.rating_count,
            card.community.photo_count,
            card.community.reported_issues.len()
        ),
        (1, 1, 1)
    );

    // The case seen in production: "still ok", then the answer deleted
    // from "My contributions".
    let cursor = places::last_seq(&pool).await.unwrap();
    community::delete_confirmation(&app, a, confirmation)
        .await
        .unwrap()
        .unwrap();
    let row = moved(&pool, port, cursor, "a deleted confirmation").await;
    assert_eq!(row.last_confirmed_at, None);

    let cursor = places::last_seq(&pool).await.unwrap();
    community::delete_review(&app, a, review)
        .await
        .unwrap()
        .unwrap();
    let row = moved(&pool, port, cursor, "a deleted rating").await;
    assert_eq!(
        (row.community.rating_count, row.community.rating_avg),
        (0, None)
    );

    let cursor = places::last_seq(&pool).await.unwrap();
    community::delete_photo(&app, a, photo)
        .await
        .unwrap()
        .unwrap();
    let row = moved(&pool, port, cursor, "a deleted photo").await;
    assert_eq!(row.community.photo_count, 0);
    assert!(row.community.cover_photos.is_empty());

    let cursor = places::last_seq(&pool).await.unwrap();
    community::delete_issue(&app, a, issue)
        .await
        .unwrap()
        .unwrap();
    let row = moved(&pool, port, cursor, "a deleted issue report").await;
    assert!(row.community.reported_issues.is_empty());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_deleted_or_banned_account_leaves_the_card_of_every_device(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let port = place_named(&pool, "Camping municipal du Port").await;
    let (gone, banned) = (trusted(&app, 1).await, trusted(&app, 2).await);
    community::rate(&app, gone, port, 2).await.unwrap();
    community::report_issue(&app, gone, port, IssueKind::Danger, None)
        .await
        .unwrap();
    community::rate(&app, banned, port, 5).await.unwrap();
    photo(&app, banned, port, 2).await;
    run(&pool, at(2), None).await.unwrap();
    let card = places::by_id(&pool, port).await.unwrap().unwrap();
    assert_eq!(
        (
            card.community.rating_count,
            card.community.photo_count,
            card.community.reported_issues.len()
        ),
        (2, 1, 1)
    );

    let cursor = places::last_seq(&pool).await.unwrap();
    accounts::delete_account(&app, gone).await.unwrap().unwrap();
    let row = moved(&pool, port, cursor, "a deleted account").await;
    assert_eq!(
        (
            row.community.rating_count,
            row.community.reported_issues.len()
        ),
        (1, 0),
        "a rating without text and the issue reports go with the account"
    );

    let cursor = places::last_seq(&pool).await.unwrap();
    accounts::ban(&app, banned, "spam").await.unwrap().unwrap();
    let row = moved(&pool, port, cursor, "a ban").await;
    assert_eq!(
        (row.community.rating_count, row.community.photo_count),
        (0, 0)
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn what_moderation_takes_down_leaves_the_card_of_every_device(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let port = place_named(&pool, "Camping municipal du Port").await;
    let (author, reporter) = (trusted(&app, 1).await, account(&app, 2).await);
    accounts::set_granted_level(&app, reporter, 2)
        .await
        .unwrap();
    let confirmation = community::confirm(&app, author, port, ConfirmationStatus::StillOk, None)
        .await
        .unwrap()
        .id;
    let review = community::review(
        &app,
        community::ReviewWrite {
            account: author,
            place: port,
            stars: 1,
            body: "Un texte qu'un lecteur trouve injurieux.",
            lang: Some("fr"),
            visited_on: None,
            vehicle: None,
            status: ReviewStatus::Published,
            held_for: None,
        },
    )
    .await
    .unwrap()
    .id;
    let photo = photo(&app, author, port, 3).await;
    community::report_issue(&app, author, port, IssueKind::NightBan, None)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();

    // A senior reporter alone hides a review when one report is enough.
    let cursor = places::last_seq(&pool).await.unwrap();
    let outcome = community::report_content(
        &app,
        reporter,
        ReportTarget::Review,
        review,
        ReportReason::Offensive,
        None,
        1,
    )
    .await
    .unwrap();
    assert_eq!(outcome, community::ReportOutcome::Hidden);
    let row = moved(&pool, port, cursor, "a review hidden by reports").await;
    assert_eq!(row.community.rating_count, 0);

    // A moderator removes a reported photo.
    community::report_content(
        &app,
        reporter,
        ReportTarget::Photo,
        photo,
        ReportReason::Offensive,
        None,
        99,
    )
    .await
    .unwrap();
    let entry = moderation::open(&app, 100)
        .await
        .unwrap()
        .into_iter()
        .find(|e| e.target_id == photo)
        .unwrap();
    let cursor = places::last_seq(&pool).await.unwrap();
    moderation::decide(&app, entry.id, Decision::Reject, None)
        .await
        .unwrap();
    let row = moved(&pool, port, cursor, "a photo a moderator removed").await;
    assert_eq!(row.community.photo_count, 0);

    let cursor = places::last_seq(&pool).await.unwrap();
    moderation::dismiss_issues(&app, port).await.unwrap();
    let row = moved(&pool, port, cursor, "issues a moderator dismissed").await;
    assert!(row.community.reported_issues.is_empty());

    let cursor = places::last_seq(&pool).await.unwrap();
    moderation::remove_confirmation(&app, confirmation)
        .await
        .unwrap()
        .unwrap();
    let row = moved(&pool, port, cursor, "a confirmation a moderator removed").await;
    assert_eq!(row.last_confirmed_at, None);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_level_that_changes_moves_the_places_its_answers_count_on(pool: PgPool) {
    ingest_fixtures(&pool).await;
    run(&pool, at(2), None).await.unwrap();
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let port = place_named(&pool, "Camping municipal du Port").await;
    // A new account's report waits for its level: a crowd of fresh
    // accounts must not stamp "night ban" on a place.
    let newcomer = account(&app, 1).await;
    community::report_issue(&app, newcomer, port, IssueKind::NightBan, None)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let card = places::by_id(&pool, port).await.unwrap().unwrap();
    assert!(card.community.reported_issues.is_empty());

    // The rules give it level 1 (`auth::compute_level`): its report counts
    // from now on, though nothing else happened at the place.
    let cursor = places::last_seq(&pool).await.unwrap();
    accounts::set_trust_level(&app, newcomer, 1).await.unwrap();
    let row = moved(&pool, port, cursor, "a level reaching 1").await;
    assert_eq!(row.community.reported_issues.len(), 1);

    // The administration sets it back to 0: the report stops counting.
    let cursor = places::last_seq(&pool).await.unwrap();
    accounts::set_granted_level(&app, newcomer, 0)
        .await
        .unwrap();
    let row = moved(&pool, port, cursor, "a level set back to 0").await;
    assert!(row.community.reported_issues.is_empty());

    // A level that changes above the line moves nothing.
    accounts::set_granted_level(&app, newcomer, 2)
        .await
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let cursor = places::last_seq(&pool).await.unwrap();
    accounts::set_trust_level(&app, newcomer, 3).await.unwrap();
    let stats = run(&pool, at(2), None).await.unwrap();
    assert_eq!(
        stats.community_refreshed, 0,
        "a summary that did not change does not move the place"
    );
    assert!(fed(&pool, port, cursor).await.is_none());
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_author_who_detaches_a_new_place_moves_it_in_the_feed(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let author = trusted(&app, 1).await;
    let device: Uuid =
        sqlx::query_scalar!("SELECT id FROM device_keys WHERE account_id = $1", author)
            .fetch_one(&pool)
            .await
            .unwrap();
    let new = NewPlace {
        kind: PlaceKind::MotorhomeArea,
        position: Position::new(46.2, 3.1).unwrap(),
        details: PlacePatch {
            name: Some("Aire des Combrailles".into()),
            ..PlacePatch::default()
        },
    };
    let sent = submissions::submit(
        &app,
        NewSubmission {
            account: author,
            device_key: device,
            what: Submitted::Create(&new),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let place = submissions::submission(&pool, sent.id)
        .await
        .unwrap()
        .unwrap()
        .place_id
        .unwrap();
    // The author's own "still ok" does not count while it is the author;
    // one other account is not enough.
    let other = trusted(&app, 2).await;
    for a in [author, other] {
        community::confirm(&app, a, place, ConfirmationStatus::StillOk, None)
            .await
            .unwrap();
    }
    run(&pool, at(2), None).await.unwrap();
    let card = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(card.community.verification, Verification::ToVerify);

    // The author takes the place out of its contributions: the place stays
    // (ODbL) without author, and its answer counts like any other.
    let cursor = places::last_seq(&pool).await.unwrap();
    assert_eq!(
        submissions::withdraw(&app, author, sent.id).await.unwrap(),
        Withdrawal::Detached
    );
    let row = moved(&pool, place, cursor, "a new place detached from its author").await;
    assert_eq!(row.community.verification, Verification::Verified);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_point_follows_its_author_s_detachment_and_its_answerers_levels(pool: PgPool) {
    use lunaway_db::pois;
    use lunaway_domain::poi::{NewVendingMachine, PoiKind};
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let author = trusted(&app, 1).await;
    let device: Uuid =
        sqlx::query_scalar!("SELECT id FROM device_keys WHERE account_id = $1", author)
            .fetch_one(&pool)
            .await
            .unwrap();
    let machine = NewVendingMachine {
        kind: PoiKind::VendingPizza,
        position: Position::new(46.0, 5.0).unwrap(),
        name: None,
        operator: None,
        brand: None,
        products: Vec::new(),
        payment: Vec::new(),
        always_open: true,
    };
    let sent = submissions::submit(
        &app,
        NewSubmission {
            account: author,
            device_key: device,
            what: Submitted::Poi(&machine),
            accepted: true,
            held_for: None,
        },
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let poi = sqlx::query_scalar!(
        "SELECT poi_id FROM place_submissions WHERE id = $1",
        sent.id
    )
    .fetch_one(&pool)
    .await
    .unwrap()
    .expect("the worker added the machine");
    let confirmed = |pool: PgPool| async move {
        sqlx::query_scalar!("SELECT last_confirmed_at FROM pois WHERE id = $1", poi)
            .fetch_one(&pool)
            .await
            .unwrap()
    };

    // Its author's "still there" does not date it while it is the author.
    pois::confirm(&app, author, poi, true).await.unwrap();
    run(&pool, at(2), None).await.unwrap();
    assert_eq!(confirmed(pool.clone()).await, None);
    assert_eq!(
        submissions::withdraw(&app, author, sent.id).await.unwrap(),
        Withdrawal::Detached
    );
    run(&pool, at(2), None).await.unwrap();
    assert!(
        confirmed(pool.clone()).await.is_some(),
        "without author, its answer dates the point like any other"
    );

    // Three new accounts say it is gone: not enough while they are new.
    let mut answerers = Vec::new();
    for n in 2..=4 {
        let a = account(&app, n).await;
        pois::confirm(&app, a, poi, false).await.unwrap();
        answerers.push(a);
    }
    run(&pool, at(2), None).await.unwrap();
    assert!(pois::is_live(&app, poi).await.unwrap());
    for a in answerers {
        accounts::set_trust_level(&app, a, 1).await.unwrap();
    }
    run(&pool, at(2), None).await.unwrap();
    assert!(
        !pois::is_live(&app, poi).await.unwrap(),
        "their level reached 1: their answers hide the point at once"
    );
}

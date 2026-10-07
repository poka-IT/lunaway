//! The "still there?" answers deleted after two years (`lunaway_db::
//! retention`) leave what they gave: the place keeps its "last confirmed"
//! and its verification through every later summary, and the accounts keep
//! the confirmations their trust level counts.

use chrono::{Duration, Utc};
use lunaway_conflate::run;
use lunaway_db::{
    PgPool, accounts, community, places, retention,
    submissions::{self, NewSubmission, Submitted},
};
use lunaway_domain::{
    PlaceKind, Position,
    community::{
        ConfirmationStatus, Verification,
        submission::{NewPlace, PlacePatch},
    },
};
use uuid::Uuid;

use super::{account, as_role, at};

#[sqlx::test(migrations = "../../migrations")]
async fn confirmations_go_after_two_years_and_the_place_keeps_what_they_gave(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let author = account(&app, 1).await;
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
    // Two accounts past level 0 say it is still there: the community's
    // place is verified.
    let confirmers = [account(&app, 2).await, account(&app, 3).await];
    for a in confirmers {
        accounts::set_trust_level(&app, a, 1).await.unwrap();
        community::confirm(&app, a, place, ConfirmationStatus::StillOk, None)
            .await
            .unwrap();
    }
    run(&pool, at(2), None).await.unwrap();
    let before = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(before.community.verification, Verification::Verified);
    assert!(before.last_confirmed_at.is_some());
    let trust_before = accounts::trust_inputs(&app, confirmers[0])
        .await
        .unwrap()
        .unwrap();

    let kept = retention::sweep(&app, Utc::now() + Duration::days(729))
        .await
        .unwrap();
    assert_eq!(kept.confirmations, 0, "two years are not over");
    let swept = retention::sweep(&app, Utc::now() + Duration::days(731))
        .await
        .unwrap();
    assert_eq!(swept.confirmations, 2);
    let left: i64 = sqlx::query_scalar!(r#"SELECT count(*) AS "n!" FROM confirmations"#)
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(left, 0, "the rows are gone, who confirmed with them");

    // Anything at the place makes the worker compute its summary again.
    sqlx::query!(
        "INSERT INTO place_refresh_queue (place_id) VALUES ($1)",
        place
    )
    .execute(&app)
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let after = places::by_id(&pool, place).await.unwrap().unwrap();
    assert_eq!(
        after.community, before.community,
        "a place does not go back to \"to verify\" because its answers aged out"
    );
    assert_eq!(
        after.last_confirmed_at, before.last_confirmed_at,
        "nor does its \"last confirmed\" move back"
    );
    assert_eq!(
        after.updated_seq, before.updated_seq,
        "nothing changed for the change feed to carry"
    );
    let trust_after = accounts::trust_inputs(&app, confirmers[0])
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        (trust_after.confirmations, trust_after.contributions),
        (trust_before.confirmations, trust_before.contributions),
        "an account's level does not drop because its answers aged out"
    );

    // A new answer still moves "last confirmed" forward.
    community::confirm(
        &app,
        confirmers[1],
        place,
        ConfirmationStatus::StillOk,
        None,
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let again = places::by_id(&pool, place).await.unwrap().unwrap();
    assert!(again.last_confirmed_at > before.last_confirmed_at);
    assert_eq!(again.community.verification, Verification::Verified);
}

/// Submits a new community place for `author` and returns the place the
/// worker made of it.
async fn community_place(pool: &PgPool, app: &PgPool, author: Uuid, name: &str, lat: f64) -> Uuid {
    let device: Uuid =
        sqlx::query_scalar!("SELECT id FROM device_keys WHERE account_id = $1", author)
            .fetch_one(pool)
            .await
            .unwrap();
    let new = NewPlace {
        kind: PlaceKind::MotorhomeArea,
        position: Position::new(lat, 3.1).unwrap(),
        details: PlacePatch {
            name: Some(name.into()),
            ..PlacePatch::default()
        },
    };
    let sent = submissions::submit(
        app,
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
    run(pool, at(2), None).await.unwrap();
    submissions::submission(pool, sent.id)
        .await
        .unwrap()
        .unwrap()
        .place_id
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_merged_place_counts_each_account_once_when_its_old_answers_go(pool: PgPool) {
    let app = as_role(&pool, "SET ROLE lunaway_app").await;
    let author = account(&app, 1).await;
    let one = community_place(&pool, &app, author, "Aire du Sioule", 46.2).await;
    let two = community_place(&pool, &app, author, "Parking du Sioule", 46.4).await;
    let (old, recent) = (account(&app, 2).await, account(&app, 3).await);
    for a in [old, recent] {
        accounts::set_trust_level(&app, a, 1).await.unwrap();
    }
    // One account answered for both spots long ago, another recently.
    for p in [one, two] {
        community::confirm(&app, old, p, ConfirmationStatus::StillOk, None)
            .await
            .unwrap();
    }
    let recent_answer = community::confirm(&app, recent, two, ConfirmationStatus::StillOk, None)
        .await
        .unwrap()
        .id;
    // The old account later says the spot changed: an answer the summary
    // does not count as a confirmation.
    let changed = community::confirm(&app, old, one, ConfirmationStatus::Changed, None)
        .await
        .unwrap()
        .id;
    sqlx::query!(
        "UPDATE confirmations SET created_at = now() + interval '5 days' WHERE id = ANY($1)",
        &[recent_answer, changed]
    )
    .execute(&pool)
    .await
    .unwrap();
    // A person states the two are one spot: one absorbs the other.
    let rec = |place: Uuid| {
        let pool = pool.clone();
        async move {
            sqlx::query_scalar!(
                "SELECT record_id FROM place_sources WHERE place_id = $1 LIMIT 1",
                place
            )
            .fetch_one(&pool)
            .await
            .unwrap()
        }
    };
    lunaway_db::records::set_constraint(
        &pool,
        rec(one).await,
        rec(two).await,
        lunaway_domain::conflation::ConstraintKind::MustLink,
        None,
    )
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let heir = places::by_id(&pool, one).await.unwrap().unwrap();
    assert_eq!(heir.community.verification, Verification::Verified);

    let swept = retention::sweep(&app, Utc::now() + Duration::days(731))
        .await
        .unwrap();
    assert_eq!(swept.confirmations, 2, "the recent answers stay");
    let tallies = sqlx::query!(r#"SELECT place_id, confirmers FROM confirmation_tallies"#)
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(
        tallies
            .iter()
            .map(|t| (t.place_id, t.confirmers))
            .collect::<Vec<_>>(),
        [(heir.id, 1)],
        "the old account counts once, on the place its answers became part of"
    );
    sqlx::query!(
        "INSERT INTO place_refresh_queue (place_id) VALUES ($1)",
        heir.id
    )
    .execute(&app)
    .await
    .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let after = places::by_id(&pool, heir.id).await.unwrap().unwrap();
    assert_eq!(
        after.community.verification,
        Verification::Verified,
        "two accounts confirmed it, one of them two years ago"
    );

    // The recent account takes its answer back: one confirmer is left.
    community::delete_confirmation(&app, recent, recent_answer)
        .await
        .unwrap()
        .unwrap();
    run(&pool, at(2), None).await.unwrap();
    let alone = places::by_id(&pool, heir.id).await.unwrap().unwrap();
    assert_eq!(
        alone.community.verification,
        Verification::ToVerify,
        "the old account's two answers made one confirmer, not two"
    );
}

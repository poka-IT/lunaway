//! The app's own operations (copied from
//! `app/lib/features/places/data/graphql/operations.dart`) validate against
//! the schema, and what they cost fits the budgets: one sync page per
//! request, and a full sync of France twice in the client's burst.

#![allow(
    clippy::unwrap_used,
    clippy::expect_used,
    reason = "a test states its preconditions with unwrap"
)]

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use async_graphql::{
    EmptySubscription, Request, Schema, ServerError, ValidationResult, Variables,
    extensions::{Extension, ExtensionContext, ExtensionFactory, NextValidation},
};
use lunaway_api::{
    Limits,
    mutation::MutationRoot,
    schema::{MAX_COMPLEXITY, QueryRoot},
};

const PLACE_FIELDS: &str = r"
fragment PlaceFields on Place {
  id
  name
  kind
  lat
  lon
  overnight
  services
  activities
  description
  address { street postcode city countryCode }
  priceParkingEur
  priceServicesEur
  priceServicesIncluded
  priceParkingIncludes
  maxHeightM
  capacity
  stars
  openingHours
  openingHoursParsed
  openingIntervals { start end }
  openingIntervalsUntil
  website
  phone
  lastConfirmedAt
  updatedAt
  sources {
    source { id name licence attribution url }
    externalId
    externalUrl
    fetchedAt
    matchScore
  }
  provenance { field sourceId alternatives { sourceId value } }
  descriptions { lang text sourceId }
  ratings { sourceId average count }
  ratingForFilters
  externalLinks { sourceId url label }
}
";

const REVIEW_FIELDS: &str = r"
fragment ReviewFields on ReviewConnection {
  nodes { id sourceId rating text lang authorName authorVehicle visitedAt createdAt }
  endCursor
  hasNextPage
  totalCount
}
";

fn changes() -> String {
    format!(
        r"
query Changes($bbox: BBoxInput!, $since: String, $first: Int) {{
  changes(bbox: $bbox, since: $since, first: $first) {{
    places {{ ...PlaceFields }}
    deleted
    cursor
    hasMore
  }}
}}
{PLACE_FIELDS}"
    )
}

fn extras() -> String {
    format!(
        r"
query PlaceExtras($id: UUID!, $first: Int) {{
  place(id: $id) {{
    id
    photos {{ id sourceId thumbUrl largeUrl }}
    reviews(first: $first) {{ ...ReviewFields }}
  }}
}}
{REVIEW_FIELDS}"
    )
}

fn reviews() -> String {
    format!(
        r"
query PlaceReviews($id: UUID!, $first: Int, $after: String) {{
  place(id: $id) {{
    id
    reviews(first: $first, after: $after) {{ ...ReviewFields }}
  }}
}}
{REVIEW_FIELDS}"
    )
}

/// Records the complexity async-graphql computed, then stops the request
/// before any resolver runs (they would need a database).
struct Capture(Arc<AtomicUsize>);

struct CaptureExt(Arc<AtomicUsize>);

impl ExtensionFactory for Capture {
    fn create(&self) -> Arc<dyn Extension> {
        Arc::new(CaptureExt(Arc::clone(&self.0)))
    }
}

#[async_graphql::async_trait::async_trait]
impl Extension for CaptureExt {
    async fn validation(
        &self,
        ctx: &ExtensionContext<'_>,
        next: NextValidation<'_>,
    ) -> Result<ValidationResult, Vec<ServerError>> {
        let result = next.run(ctx).await?;
        self.0.store(result.complexity, Ordering::SeqCst);
        Err(vec![ServerError::new("measured", None)])
    }
}

/// The complexity of `query` with `variables`, or the validation errors.
async fn complexity(query: &str, variables: serde_json::Value) -> Result<usize, Vec<String>> {
    let seen = Arc::new(AtomicUsize::new(0));
    let schema = Schema::build(QueryRoot, MutationRoot, EmptySubscription)
        .extension(Capture(Arc::clone(&seen)))
        .finish();
    let response = schema
        .execute(Request::new(query).variables(Variables::from_json(variables)))
        .await;
    let errors: Vec<String> = response
        .errors
        .iter()
        .map(|e| e.message.clone())
        .filter(|m| m != "measured")
        .collect();
    if errors.is_empty() {
        Ok(seen.load(Ordering::SeqCst))
    } else {
        Err(errors)
    }
}

#[tokio::test]
async fn the_app_s_operations_match_the_schema_and_fit_the_budget() {
    let bbox = serde_json::json!({"south": 41.0, "west": -5.5, "north": 51.5, "east": 10.0});
    let page = complexity(
        &changes(),
        serde_json::json!({"bbox": bbox, "since": null, "first": 1000}),
    )
    .await
    .expect("the app's sync operation validates");
    let id = "0199b5f6-0000-7000-8000-000000000000";
    let extra = complexity(&extras(), serde_json::json!({"id": id, "first": 20}))
        .await
        .expect("the app's place extras operation validates");
    let more = complexity(
        &reviews(),
        serde_json::json!({"id": id, "first": 20, "after": null}),
    )
    .await
    .expect("the app's reviews operation validates");
    println!("sync page of 1000 places: {page}; place extras: {extra}; next reviews: {more}");
    assert!(
        page <= MAX_COMPLEXITY && 2 * page > MAX_COMPLEXITY,
        "one sync page fits a request and two do not: page {page}, limit {MAX_COMPLEXITY}"
    );
    assert!(extra <= MAX_COMPLEXITY && more <= MAX_COMPLEXITY);
    let limits = Limits::default();
    // France takes 16 pages; every request also pays 1000 to start.
    let full_sync = 16 * (u64::try_from(page).unwrap() + 1_000);
    assert!(
        limits.rate_burst >= 2 * full_sync,
        "two full syncs of France in a row fit the burst: {} for {full_sync} each",
        limits.rate_burst
    );
    assert!(
        limits.max_cost_in_flight >= 4 * page,
        "four sync pages may run at once across clients"
    );
}

//! The app's own operations, read from its Dart sources
//! (`app/lib/features/places/data/graphql/operations.dart` and
//! `app/lib/features/regions/data/region_operations.dart`), validate against
//! the schema, and what they cost fits the budgets: a page of the change
//! feed, by box or by region, at the app's own page size and with room to
//! spare, and a full sync of France twice in the client's burst.
//!
//! The documents are read, never copied: a copy of the fragment kept here
//! went stale while the app's grew, and every update of a downloaded region
//! was refused as too complex (audit of 2026-10-10, B1).

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
    schema::{CHANGES_PAGE_SERVED, MAX_CHANGES_PAGE, MAX_COMPLEXITY, QueryRoot},
};

/// The Dart files that hold the documents measured here and the constants
/// they interpolate.
const DART_SOURCES: [&str; 2] = [
    "app/lib/features/places/data/graphql/operations.dart",
    "app/lib/features/regions/data/region_operations.dart",
];

/// The share of [`MAX_COMPLEXITY`] a page of the feed may cost: the rest is
/// the room the fragment has to grow before the page size must shrink.
const PAGE_SHARE_PERCENT: usize = 75;

/// The app's sources, read from the repository.
fn app_sources() -> String {
    DART_SOURCES
        .iter()
        .map(|path| {
            let full = format!("{}/../../../{path}", env!("CARGO_MANIFEST_DIR"));
            std::fs::read_to_string(&full).unwrap_or_else(|e| panic!("read {full}: {e}"))
        })
        .collect::<Vec<_>>()
        .join("\n")
}

/// The text of the Dart string literal `'''...'''` that starts at `from`
/// in `sources`, its escapes resolved and its `$name` interpolations
/// replaced by the constants of that name, themselves resolved.
fn dart_literal(sources: &str, from: usize) -> String {
    let body = &sources[from..];
    let open = body.find("'''").expect("a ''' literal follows") + 3;
    let len = body[open..].find("'''").expect("the literal is closed");
    let raw = &body[open..open + len];
    let mut out = String::with_capacity(raw.len());
    let mut chars = raw.char_indices().peekable();
    while let Some((i, c)) = chars.next() {
        match c {
            '\\' => {
                if let Some((_, next)) = chars.next() {
                    out.push(next);
                }
            }
            '$' => {
                let rest = &raw[i + 1..];
                let name: String = rest
                    .chars()
                    .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                    .collect();
                assert!(
                    !name.is_empty(),
                    "an interpolation this reader knows: $name"
                );
                out.push_str(&dart_constant(sources, &name));
                for _ in 0..name.len() {
                    chars.next();
                }
            }
            _ => out.push(c),
        }
    }
    out
}

/// The value of the string constant `name` (`const name = '''...''';`).
fn dart_constant(sources: &str, name: &str) -> String {
    let at = sources
        .find(&format!("const {name} = '''"))
        .unwrap_or_else(|| panic!("the app defines the constant {name}"));
    dart_literal(sources, at)
}

/// The document of the operation named `name` (`name: 'Changes'`, then
/// `document: '''...'''`).
fn dart_document(sources: &str, name: &str) -> String {
    let at = sources
        .find(&format!("name: '{name}',"))
        .unwrap_or_else(|| panic!("the app sends an operation named {name}"));
    let doc = at
        + sources[at..]
            .find("document: '''")
            .expect("the operation's document follows its name");
    dart_literal(sources, doc)
}

/// The integer constant `name` (`const name = 500;`).
fn dart_int(sources: &str, name: &str) -> usize {
    let key = format!("const {name} = ");
    let at = sources
        .find(&key)
        .unwrap_or_else(|| panic!("the app defines {name}"))
        + key.len();
    sources[at..]
        .chars()
        .take_while(char::is_ascii_digit)
        .collect::<String>()
        .parse()
        .unwrap_or_else(|e| panic!("{name} is an integer: {e}"))
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

/// The cost of a page of the feed by box over metropolitan France.
async fn bbox_page(sources: &str, first: usize) -> usize {
    let bbox = serde_json::json!({"south": 41.0, "west": -5.5, "north": 51.5, "east": 10.0});
    complexity(
        &dart_document(sources, "Changes"),
        serde_json::json!({"bbox": bbox, "since": null, "first": first}),
    )
    .await
    .expect("the app's sync by box validates")
}

/// The cost of a page of the feed of a region, from a pack's cursor.
async fn region_page(sources: &str, first: usize) -> usize {
    complexity(
        &dart_document(sources, "RegionChanges"),
        serde_json::json!({"region": "FR-ARA", "since": "c2.x.1", "first": first}),
    )
    .await
    .expect("the app's sync of a region validates")
}

#[tokio::test]
async fn a_page_of_the_app_s_feed_fits_the_budget_with_room_to_spare() {
    let sources = app_sources();
    let size = dart_int(&sources, "syncPageSize");
    assert!(
        size <= usize::try_from(CHANGES_PAGE_SERVED).unwrap(),
        "the app asks pages the API serves whole: {size} for {CHANGES_PAGE_SERVED}"
    );
    let by_box = bbox_page(&sources, size).await;
    let by_region = region_page(&sources, size).await;
    println!("a page of {size} places: by box {by_box}, by region {by_region}");
    for (what, cost) in [("by box", by_box), ("by region", by_region)] {
        assert!(
            cost * 100 <= MAX_COMPLEXITY * PAGE_SHARE_PERCENT,
            "a page of the feed {what} keeps a quarter of the budget for the fragment to grow: \
             {cost} of {MAX_COMPLEXITY}"
        );
    }
}

#[tokio::test]
async fn a_released_app_asking_pages_of_1000_is_served_pages_it_can_afford() {
    // The apps released before 2026-10-10 ask 1000 with the same fragment:
    // counted on the page the API serves, their request validates.
    let sources = app_sources();
    let asked = usize::try_from(MAX_CHANGES_PAGE).unwrap();
    let served = usize::try_from(CHANGES_PAGE_SERVED).unwrap();
    let cost = region_page(&sources, asked).await;
    assert_eq!(
        cost,
        region_page(&sources, served).await,
        "a page asked larger than the API serves costs the page served"
    );
    assert!(cost <= MAX_COMPLEXITY, "{cost} of {MAX_COMPLEXITY}");
}

#[tokio::test]
async fn the_app_s_place_extras_and_reviews_fit_the_budget() {
    let sources = app_sources();
    let id = "0199b5f6-0000-7000-8000-000000000000";
    let extra = complexity(
        &dart_document(&sources, "PlaceExtras"),
        serde_json::json!({"id": id, "first": 20}),
    )
    .await
    .expect("the app's place extras operation validates");
    let more = complexity(
        &dart_document(&sources, "PlaceReviews"),
        serde_json::json!({"id": id, "first": 20, "after": null}),
    )
    .await
    .expect("the app's reviews operation validates");
    println!("place extras: {extra}; next reviews: {more}");
    assert!(extra <= MAX_COMPLEXITY && more <= MAX_COMPLEXITY);
}

#[tokio::test]
async fn two_full_syncs_of_france_fit_a_client_s_burst() {
    let sources = app_sources();
    let size = dart_int(&sources, "syncPageSize");
    let page = u64::try_from(bbox_page(&sources, size).await).unwrap();
    let limits = Limits::default();
    // France by box, as the app syncs it against an API without regions:
    // 16 000 places, every request paying 1000 to start.
    let pages = 16_000_u64.div_ceil(u64::try_from(size).unwrap());
    let full_sync = pages * (page + 1_000);
    assert!(
        limits.rate_burst >= 2 * full_sync,
        "two full syncs of France in a row fit the burst: {} for {full_sync} each",
        limits.rate_burst
    );
    assert!(
        limits.max_cost_in_flight >= 4 * usize::try_from(page).unwrap(),
        "four sync pages may run at once across clients"
    );
}

#[test]
fn the_reader_resolves_escapes_and_interpolations() {
    let sources = concat!(
        "const a = '''x \\$b''';\n",
        "const c = '''y''';\n",
        "final op = GraphQLOperation(\n",
        "  name: 'Op',\n",
        "  document: '''\n",
        "query Op(\\$v: Int) { f(v: \\$v) }\n",
        "$a$c''',\n",
        ");\n",
        "const n = 42;\n",
    );
    assert_eq!(
        dart_document(sources, "Op"),
        "\nquery Op($v: Int) { f(v: $v) }\nx $by"
    );
    assert_eq!(dart_int(sources, "n"), 42);
}

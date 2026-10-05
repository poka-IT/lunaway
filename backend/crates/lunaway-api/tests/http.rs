//! The router answers over HTTP the way a client sees it.

// clippy's test allowance covers #[test] functions only, not the helpers an
// integration test file shares between them.
#![allow(
    clippy::unwrap_used,
    reason = "a test states its preconditions with unwrap"
)]

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use http_body_util::BodyExt;
use tower::ServiceExt;

fn app() -> axum::Router {
    lunaway_api::router(lunaway_api::build_schema())
}

async fn body_bytes(response: axum::response::Response) -> Vec<u8> {
    response
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes()
        .to_vec()
}

#[tokio::test]
async fn health_answers_ok() {
    let response = app()
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(body_bytes(response).await, b"ok");
}

#[tokio::test]
async fn graphql_serves_the_version_and_the_taxonomy() {
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(r#"{"query":"{ apiVersion placeKinds }"}"#))
        .unwrap();
    let response = app().oneshot(request).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let body: serde_json::Value = serde_json::from_slice(&body_bytes(response).await).unwrap();
    assert_eq!(body["data"]["apiVersion"], env!("CARGO_PKG_VERSION"));
    let kinds = body["data"]["placeKinds"].as_array().unwrap();
    assert_eq!(
        kinds.len(),
        lunaway_domain::PlaceKind::ALL.len(),
        "the API must expose every kind the domain knows"
    );
    assert_eq!(kinds[0], "MOTORHOME_AREA");
}

#[tokio::test]
async fn a_too_complex_query_is_refused() {
    // Each field costs one; 600 aliases of a scalar exceed the limit of 500.
    // (async-graphql leaves introspection out of the depth count, and the
    // schema has no nested type yet, so complexity is the bound testable now.)
    let fields: String = (0..600).map(|i| format!("a{i}: apiVersion ")).collect();
    let request = Request::post("/graphql")
        .header("content-type", "application/json")
        .body(Body::from(
            serde_json::json!({ "query": format!("{{ {fields} }}") }).to_string(),
        ))
        .unwrap();
    let response = app().oneshot(request).await.unwrap();
    let body: serde_json::Value = serde_json::from_slice(&body_bytes(response).await).unwrap();
    let message = body["errors"][0]["message"].as_str().unwrap_or_default();
    assert!(message.contains("too complex"), "unexpected answer: {body}");
}

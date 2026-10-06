//! `POST /graphql`: one GraphQL operation per request, as JSON, within the
//! bounds of [`Limits`].
//!
//! Before async-graphql sees a request, the endpoint refuses what no client
//! of Lunaway sends: another content type than `application/json` (no
//! multipart, so no upload is ever written to a temporary file), a body
//! over the limit, a JSON array (a batch, whose entries would each get a
//! full budget and run in parallel), a client whose budget is spent, and a
//! request that cannot get a slot in time. After it, the response is
//! refused when it would exceed its limit. Every refusal is a GraphQL error
//! body with its `extensions.code`, and the parser's own messages about a
//! malformed body are never echoed.

use std::{net::SocketAddr, sync::Arc, time::Duration};

use async_graphql::{Response as GqlResponse, ServerError, Variables};
use axum::{
    extract::{ConnectInfo, FromRequestParts, Request, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use tokio::sync::Semaphore;

use crate::{
    LunawaySchema,
    auth::{Credentials, ViewerCell},
    client::ClientKey,
    config::Limits,
    error::{INTERNAL, INVALID_INPUT, RATE_LIMITED, retry_after_seconds},
    rate::RateLimiter,
    schema::{CostShare, RequestDb},
};

/// What the endpoint needs, shared by every request.
pub(crate) struct Endpoint {
    schema: LunawaySchema,
    limits: Limits,
    rate: Arc<RateLimiter>,
    /// Requests running at once.
    slots: Semaphore,
}

impl Endpoint {
    pub(crate) fn new(schema: LunawaySchema, limits: Limits, rate: Arc<RateLimiter>) -> Self {
        Self {
            schema,
            limits,
            rate,
            slots: Semaphore::new(limits.max_concurrent_requests),
        }
    }
}

/// The JSON body of a request; unknown members (`extensions`) are ignored.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Body {
    query: String,
    #[serde(default)]
    variables: Option<serde_json::Value>,
    #[serde(default)]
    operation_name: Option<String>,
}

pub(crate) fn error_body(code: &str, message: &str, retry_after: Option<u64>) -> Vec<u8> {
    let mut extensions = serde_json::json!({ "code": code });
    if let Some(seconds) = retry_after {
        extensions["retryAfterSeconds"] = seconds.into();
    }
    serde_json::json!({
        "data": null,
        "errors": [{ "message": message, "extensions": extensions }],
    })
    .to_string()
    .into_bytes()
}

pub(crate) fn json(status: StatusCode, body: Vec<u8>) -> Response {
    (
        status,
        [(
            header::CONTENT_TYPE,
            HeaderValue::from_static("application/json"),
        )],
        body,
    )
        .into_response()
}

pub(crate) fn refuse(status: StatusCode, code: &str, message: &str) -> Response {
    json(status, error_body(code, message, None))
}

pub(crate) fn wait_response(status: StatusCode, message: &str, wait: Duration) -> Response {
    let seconds = retry_after_seconds(wait);
    let mut response = json(status, error_body(RATE_LIMITED, message, Some(seconds)));
    response
        .headers_mut()
        .insert(header::RETRY_AFTER, HeaderValue::from(seconds));
    response
}

fn is_json(headers: &HeaderMap) -> bool {
    headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(';').next())
        .is_some_and(|media| media.trim().eq_ignore_ascii_case("application/json"))
}

/// Whether reading the body failed on the size limit rather than the
/// connection.
pub(crate) fn over_limit(error: &axum::Error) -> bool {
    let mut cause: Option<&(dyn std::error::Error + 'static)> = Some(error);
    while let Some(c) = cause {
        if c.is::<http_body_util::LengthLimitError>() {
            return true;
        }
        cause = c.source();
    }
    false
}

/// Serves one GraphQL request.
pub(crate) async fn graphql(State(endpoint): State<Arc<Endpoint>>, request: Request) -> Response {
    let (mut parts, body) = request.into_parts();
    let peer = ConnectInfo::<SocketAddr>::from_request_parts(&mut parts, &())
        .await
        .ok()
        .map(|c| c.0);
    let key = ClientKey::from_request(peer, &parts.headers);
    let credentials = Credentials::from_headers(&parts.headers);
    let limits = endpoint.limits;
    if !is_json(&parts.headers) {
        return refuse(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            INVALID_INPUT,
            "the body must be application/json",
        );
    }
    let too_large = || {
        refuse(
            StatusCode::PAYLOAD_TOO_LARGE,
            INVALID_INPUT,
            &format!("the body exceeds {} bytes", limits.max_body_bytes),
        )
    };
    // An announced size is refused before a byte is read; an unannounced
    // one is read up to the limit and no further.
    let announced = parts
        .headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok());
    if announced.is_some_and(|n| n > u64::try_from(limits.max_body_bytes).unwrap_or(u64::MAX)) {
        return too_large();
    }
    let bytes = match axum::body::to_bytes(body, limits.max_body_bytes).await {
        Ok(bytes) => bytes,
        Err(e) if over_limit(&e) => return too_large(),
        Err(_) => {
            return refuse(
                StatusCode::BAD_REQUEST,
                INVALID_INPUT,
                "the body could not be read",
            );
        }
    };
    if bytes.iter().find(|b| !b.is_ascii_whitespace()) == Some(&b'[') {
        return refuse(
            StatusCode::BAD_REQUEST,
            INVALID_INPUT,
            "one operation per request: a batch (a JSON array) is refused",
        );
    }
    let Ok(body) = serde_json::from_slice::<Body>(&bytes) else {
        return refuse(
            StatusCode::BAD_REQUEST,
            INVALID_INPUT,
            "the body must be a JSON object with a string `query`, and optionally \
             `variables` and `operationName`",
        );
    };
    if let Err(wait) = endpoint.rate.admit(key) {
        return wait_response(
            StatusCode::TOO_MANY_REQUESTS,
            "this client's request budget is spent; wait and try again",
            wait,
        );
    }
    let Ok(Ok(_slot)) = tokio::time::timeout(limits.queue_wait, endpoint.slots.acquire()).await
    else {
        return wait_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "the server is busy; try again in a moment",
            Duration::from_secs(1),
        );
    };

    let mut request = async_graphql::Request::new(body.query)
        .data(key)
        .data(credentials)
        .data(ViewerCell::default())
        .data(RequestDb(Semaphore::new(limits.db_queries_per_request)))
        .data(CostShare::default());
    if let Some(variables) = body.variables {
        request = request.variables(Variables::from_json(variables));
    }
    if let Some(name) = body.operation_name {
        request = request.operation_name(name);
    }
    let Ok(response) =
        tokio::time::timeout(limits.request_timeout, endpoint.schema.execute(request)).await
    else {
        tracing::warn!(timeout = ?limits.request_timeout, "a request ran out of time");
        return refuse(
            StatusCode::GATEWAY_TIMEOUT,
            INTERNAL,
            "the request took too long",
        );
    };
    respond(response, limits.max_response_bytes)
}

fn code_of(e: &ServerError) -> Option<String> {
    match e.extensions.as_ref()?.get("code")? {
        async_graphql::Value::String(s) => Some(s.clone()),
        _ => None,
    }
}

/// The HTTP form of a GraphQL response: errors async-graphql raised itself
/// (syntax, unknown field, depth, complexity) get `INVALID_INPUT`, a spent
/// budget answers `429` with `Retry-After`, and an answer over
/// `max_bytes` is replaced by an error.
fn respond(mut response: GqlResponse, max_bytes: usize) -> Response {
    let mut wait: Option<u64> = None;
    for e in &mut response.errors {
        match code_of(e).as_deref() {
            None => {
                e.extensions
                    .get_or_insert_with(Default::default)
                    .set("code", INVALID_INPUT);
            }
            Some(RATE_LIMITED) => {
                let seconds = e
                    .extensions
                    .as_ref()
                    .and_then(|x| x.get("retryAfterSeconds"))
                    .and_then(|v| match v {
                        async_graphql::Value::Number(n) => n.as_u64(),
                        _ => None,
                    })
                    .unwrap_or(1);
                wait = Some(wait.unwrap_or(0).max(seconds));
            }
            Some(_) => {}
        }
    }
    let body = match serde_json::to_vec(&response) {
        Ok(body) => body,
        Err(error) => {
            tracing::error!(%error, "cannot serialise a response");
            return refuse(
                StatusCode::INTERNAL_SERVER_ERROR,
                INTERNAL,
                "internal error",
            );
        }
    };
    if body.len() > max_bytes {
        return refuse(
            StatusCode::OK,
            INVALID_INPUT,
            &format!(
                "the answer would exceed {max_bytes} bytes; ask for a smaller page or fewer fields"
            ),
        );
    }
    match wait {
        Some(seconds) => {
            let mut r = json(StatusCode::TOO_MANY_REQUESTS, body);
            r.headers_mut()
                .insert(header::RETRY_AFTER, HeaderValue::from(seconds));
            r
        }
        None => json(StatusCode::OK, body),
    }
}

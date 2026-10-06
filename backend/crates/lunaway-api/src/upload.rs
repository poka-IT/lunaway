//! `POST /upload`: a photo of a place, as `multipart/form-data` with two
//! fields, `placeId` (text) and `file` (the image), sent with
//! `Authorization: Bearer <session>` by an account of level 1 or more.
//!
//! The image is read into memory up to the size limit (never to a
//! temporary file), decoded within bounds, turned upright, re-encoded from
//! its pixels (no metadata survives, the GPS position included), stored
//! under its content address, and published. Refusals use the GraphQL error
//! body with its `extensions.code`, like the `/graphql` endpoint.

use std::{net::SocketAddr, sync::Arc, time::Duration};

use axum::{
    extract::{ConnectInfo, FromRequest, FromRequestParts, Multipart, Request, State},
    http::{StatusCode, header},
    response::Response,
};
use lunaway_db::{PgPool, community};
use lunaway_domain::community::trust::Action as Level;
use lunaway_media::{Limits as MediaLimits, MediaError};
use tokio::sync::Semaphore;
use uuid::Uuid;

use crate::{
    auth::{self, Credentials},
    client::ClientKey,
    community_types::Photo,
    config::ApiConfig,
    error::{FORBIDDEN, INTERNAL, INVALID_INPUT, NOT_FOUND, UNAUTHENTICATED},
    http::{error_body, json, refuse, wait_response},
    quota::{Action, QuotaLimiter, Subject},
    rate::RateLimiter,
};

/// Room for the multipart framing and the `placeId` field around the image.
const FRAMING_BYTES: usize = 64 * 1024;
/// Uploads read at once; each holds up to the size limit in memory.
pub(crate) const UPLOADS_AT_ONCE: usize = 8;
/// How long an upload waits for a slot, then for a processing worker.
const SLOT_WAIT: Duration = Duration::from_secs(10);
/// Longest time to receive the form once a slot is held: 10 MB at about
/// 700 kbit/s. Caddy bounds the body read too; this keeps a stalled client
/// from holding a slot whatever sits in front.
const READ_WAIT: Duration = Duration::from_secs(120);

/// What the upload endpoint shares across requests.
pub(crate) struct UploadEndpoint {
    pub(crate) pool: PgPool,
    pub(crate) config: Arc<ApiConfig>,
    pub(crate) rate: Arc<RateLimiter>,
    pub(crate) quotas: Arc<QuotaLimiter>,
    pub(crate) media: Arc<lunaway_media::MediaStore>,
    pub(crate) workers: Arc<Semaphore>,
    pub(crate) slots: Semaphore,
}

impl UploadEndpoint {
    /// The largest body the route accepts.
    pub(crate) fn max_body(&self) -> usize {
        self.config.media.max_upload_bytes + FRAMING_BYTES
    }
}

fn internal_error(error: &dyn std::fmt::Display) -> Response {
    tracing::error!(%error, "upload failed");
    refuse(
        StatusCode::INTERNAL_SERVER_ERROR,
        INTERNAL,
        "internal error",
    )
}

fn forbidden_level(required: u8, level: u8) -> Response {
    let mut body: serde_json::Value = serde_json::from_slice(&error_body(
        FORBIDDEN,
        &format!("photos need trust level {required}; the account is at level {level}"),
        None,
    ))
    .unwrap_or_default();
    body["errors"][0]["extensions"]["requiredLevel"] = required.into();
    body["errors"][0]["extensions"]["level"] = level.into();
    json(StatusCode::FORBIDDEN, body.to_string().into_bytes())
}

fn media_refusal(error: &MediaError) -> Response {
    if !error.is_client_error() {
        return internal_error(error);
    }
    let status = match error {
        MediaError::TooLarge { .. } => StatusCode::PAYLOAD_TOO_LARGE,
        MediaError::Unsupported => StatusCode::UNSUPPORTED_MEDIA_TYPE,
        _ => StatusCode::UNPROCESSABLE_ENTITY,
    };
    refuse(status, INVALID_INPUT, &format!("file: {error}"))
}

/// The two fields of the form.
struct Form {
    place_id: Uuid,
    file: Vec<u8>,
}

async fn read_form(mut multipart: Multipart, max_file: usize) -> Result<Form, Box<Response>> {
    let bad = |message: &str| Box::new(refuse(StatusCode::BAD_REQUEST, INVALID_INPUT, message));
    let mut place_id = None;
    let mut file: Option<Vec<u8>> = None;
    loop {
        let field = match multipart.next_field().await {
            Ok(Some(f)) => f,
            Ok(None) => break,
            Err(e) if e.status() == StatusCode::PAYLOAD_TOO_LARGE => {
                return Err(Box::new(refuse(
                    StatusCode::PAYLOAD_TOO_LARGE,
                    INVALID_INPUT,
                    &format!("the file exceeds {max_file} bytes"),
                )));
            }
            Err(_) => return Err(bad("the body is not a readable multipart form")),
        };
        match field.name() {
            Some("placeId") if place_id.is_none() => {
                let text = field
                    .text()
                    .await
                    .map_err(|_| bad("placeId could not be read"))?;
                place_id =
                    Some(Uuid::parse_str(text.trim()).map_err(|_| bad("placeId is not a UUID"))?);
            }
            Some("file") if file.is_none() => {
                let mut bytes = Vec::new();
                let mut field = field;
                loop {
                    match field.chunk().await {
                        Ok(Some(chunk)) => {
                            if bytes.len() + chunk.len() > max_file {
                                return Err(Box::new(refuse(
                                    StatusCode::PAYLOAD_TOO_LARGE,
                                    INVALID_INPUT,
                                    &format!("the file exceeds {max_file} bytes"),
                                )));
                            }
                            bytes.extend_from_slice(&chunk);
                        }
                        Ok(None) => break,
                        Err(_) => return Err(bad("the file could not be read")),
                    }
                }
                file = Some(bytes);
            }
            _ => {
                return Err(bad(
                    "the form holds placeId and file, once each, nothing else",
                ));
            }
        }
    }
    match (place_id, file) {
        (Some(place_id), Some(file)) => Ok(Form { place_id, file }),
        _ => Err(bad("the form needs placeId and file")),
    }
}

/// Serves one upload.
pub(crate) async fn upload(State(ep): State<Arc<UploadEndpoint>>, request: Request) -> Response {
    let (mut parts, body) = request.into_parts();
    let peer = ConnectInfo::<SocketAddr>::from_request_parts(&mut parts, &())
        .await
        .ok()
        .map(|c| c.0);
    let client = ClientKey::from_request(peer, &parts.headers);
    if let Err(wait) = ep.rate.admit(client) {
        return wait_response(
            StatusCode::TOO_MANY_REQUESTS,
            "this client's request budget is spent; wait and try again",
            wait,
        );
    }
    let multipart_type = parts
        .headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| {
            v.trim_start()
                .to_ascii_lowercase()
                .starts_with("multipart/form-data")
        });
    if !multipart_type {
        return refuse(
            StatusCode::UNSUPPORTED_MEDIA_TYPE,
            INVALID_INPUT,
            "the body must be multipart/form-data with placeId and file",
        );
    }
    let announced = parts
        .headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<u64>().ok());
    if announced.is_some_and(|n| n > u64::try_from(ep.max_body()).unwrap_or(u64::MAX)) {
        return refuse(
            StatusCode::PAYLOAD_TOO_LARGE,
            INVALID_INPUT,
            &format!(
                "the file exceeds {} bytes",
                ep.config.media.max_upload_bytes
            ),
        );
    }

    // Who uploads, and may they, before a byte of the body is read.
    let credentials = Credentials::from_headers(&parts.headers);
    let viewer = match auth::resolve(&ep.pool, credentials, ep.config.auth.session_ttl).await {
        Ok(Some(v)) => v,
        Ok(None) => {
            return refuse(
                StatusCode::UNAUTHORIZED,
                UNAUTHENTICATED,
                "sign in first: this needs a valid session",
            );
        }
        Err(e) => return internal_error(&e),
    };
    let needed = Level::Photo.required_level();
    if viewer.level() < needed {
        let level = match auth::compute_level(&ep.pool, &ep.config.trust, viewer.id()).await {
            Ok(l) => l.map_or(0, |(l, _)| l),
            Err(e) => return internal_error(&e),
        };
        if level < needed {
            return forbidden_level(needed, level);
        }
    }
    if let Err(wait) = ep.quotas.take(Action::Photo, Subject::Account(viewer.id())) {
        return wait_response(
            StatusCode::TOO_MANY_REQUESTS,
            "too many photos; wait and try again",
            wait,
        );
    }
    let Ok(Ok(_slot)) = tokio::time::timeout(SLOT_WAIT, ep.slots.acquire()).await else {
        ep.quotas
            .give_back(Action::Photo, Subject::Account(viewer.id()));
        return wait_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "the server is busy; try again in a moment",
            Duration::from_secs(5),
        );
    };

    let request = Request::from_parts(parts, body);
    let multipart = match Multipart::from_request(request, &()).await {
        Ok(m) => m,
        Err(_) => {
            return refuse(
                StatusCode::BAD_REQUEST,
                INVALID_INPUT,
                "the body is not a readable multipart form",
            );
        }
    };
    let form = match tokio::time::timeout(
        READ_WAIT,
        read_form(multipart, ep.config.media.max_upload_bytes),
    )
    .await
    {
        Ok(Ok(f)) => f,
        Ok(Err(r)) => return *r,
        Err(_) => {
            return refuse(
                StatusCode::REQUEST_TIMEOUT,
                INVALID_INPUT,
                "the form took too long to arrive",
            );
        }
    };
    let place = match community::live_place(&ep.pool, form.place_id).await {
        Ok(Some(p)) => p,
        Ok(None) => return refuse(StatusCode::NOT_FOUND, NOT_FOUND, "no such place"),
        Err(e) => return internal_error(&e),
    };

    let Ok(Ok(worker)) =
        tokio::time::timeout(SLOT_WAIT, Arc::clone(&ep.workers).acquire_owned()).await
    else {
        ep.quotas
            .give_back(Action::Photo, Subject::Account(viewer.id()));
        return wait_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "the server is busy; try again in a moment",
            Duration::from_secs(5),
        );
    };
    // 256 MiB for the decoded image: an 8-bit photo of 50 Mpx fits, a
    // 16-bit RGBA one (400 MB before the copies of the pipeline) does not.
    let limits = MediaLimits {
        max_bytes: ep.config.media.max_upload_bytes,
        max_alloc: 256 * 1024 * 1024,
        ..MediaLimits::default()
    };
    let processed = tokio::task::spawn_blocking(move || {
        let _worker = worker;
        lunaway_media::process(&form.file, &limits)
    })
    .await;
    let processed = match processed {
        Ok(Ok(p)) => p,
        Ok(Err(e)) => return media_refusal(&e),
        Err(e) => return internal_error(&e),
    };
    let path = processed.full.relative_path();
    match community::photo_already_sent(&ep.pool, viewer.id(), &path).await {
        Ok(true) => {
            return refuse(
                StatusCode::UNPROCESSABLE_ENTITY,
                INVALID_INPUT,
                "file: this account already sent this photo",
            );
        }
        Ok(false) => {}
        Err(e) => return internal_error(&e),
    }
    let stored = async {
        let full = ep.media.put(&processed.full).await?;
        let thumb = ep.media.put(&processed.thumb).await?;
        Ok::<_, MediaError>((full, thumb))
    }
    .await;
    let (full, thumb) = match stored {
        Ok(paths) => paths,
        Err(e) => return internal_error(&e),
    };
    let size = |w: u32| i32::try_from(w).unwrap_or(i32::MAX);
    let row = community::add_photo(
        &ep.pool,
        community::NewPhoto {
            account: viewer.id(),
            place: place.id,
            path: &full,
            thumb_path: &thumb,
            size: (size(processed.full.width), size(processed.full.height)),
            thumb_size: (size(processed.thumb.width), size(processed.thumb.height)),
            thumbhash: &processed.thumbhash,
        },
    )
    .await;
    let row = match row {
        Ok(r) => r,
        Err(e) => return internal_error(&e),
    };
    if let Err(error) = auth::compute_level(&ep.pool, &ep.config.trust, viewer.id()).await {
        tracing::error!(%error, "cannot recompute a trust level");
    }
    let photo = Photo::from_row(row, &ep.config.media);
    let body = serde_json::json!({
        "photo": {
            "id": photo.id,
            "sourceId": photo.source_id,
            "thumbUrl": photo.thumb_url,
            "largeUrl": photo.large_url,
            "width": photo.width,
            "height": photo.height,
            "thumbhash": photo.thumbhash,
            "status": "PUBLISHED",
        }
    });
    json(StatusCode::OK, body.to_string().into_bytes())
}

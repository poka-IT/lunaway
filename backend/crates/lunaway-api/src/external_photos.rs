//! `GET /external-photos/{id}/{thumb|large}`: the photo proxy of the
//! external community source (`docs/feeds.md`).
//!
//! A partner's photo is downloaded the first time a device asks for it,
//! never before (most are never looked at) and never by the device (it
//! talks to Lunaway's hosts only). The download goes through the upload's
//! pipeline (`lunaway_media`): decoded within bounds, re-encoded from its
//! pixels so no metadata survives, resized, stored under its content
//! address; the answer is then a redirect to the stored file, and the
//! photo's URLs in the API name that file from then on.
//!
//! The URL comes from a feed, which is untrusted: it must be an `https`
//! URL on a host the source's agreement in force lists, and so must every
//! redirect; the host must resolve to public addresses only (no loopback,
//! private, link-local or reserved range, so a feed cannot steer the
//! server at its own network); the answer is read within the upload's size
//! limit and a time limit. A failed download is not tried again before a
//! delay that doubles with each failure, so a refusing host is not asked
//! at every view.
//!
//! Downloads are bounded per UTC day for all clients together, and each
//! client (an IPv4 address or an IPv6 /64, with its /48) has a quota of its
//! own within that budget (`Quotas::external_photo`), kept in memory like
//! every quota: no address is stored or logged.

use std::{
    collections::HashMap,
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    sync::Arc,
    time::Duration,
};

use axum::{
    extract::{ConnectInfo, FromRequestParts, Path, Request, State},
    http::{HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
};
use chrono::Utc;
use lunaway_db::{PgPool, extcom};
use lunaway_domain::extcom::photo_url_allowed;
use lunaway_media::{Limits as MediaLimits, MediaStore};
use tokio::sync::Semaphore;
use uuid::Uuid;

use crate::{
    client::ClientKey,
    config::{ExternalPhotosConfig, MediaConfig},
    error::{INTERNAL, NOT_FOUND, UNAVAILABLE},
    http::{refuse, wait_response},
    quota::{Action, QuotaLimiter, Subject},
    rate::RateLimiter,
};

/// Redirects followed at most, each held to the agreement's hosts.
const MAX_REDIRECTS: usize = 3;
/// How long a request waits for a download slot or a media worker.
const SLOT_WAIT: Duration = Duration::from_secs(10);
/// The wait after a first failed download; it doubles with each failure.
const FIRST_RETRY: chrono::Duration = chrono::Duration::hours(1);
/// The longest wait between two tries.
const LONGEST_RETRY: chrono::Duration = chrono::Duration::days(7);

/// Where the proxy gets a photo's bytes.
#[derive(Clone)]
pub enum PhotoSource {
    /// The partner's host, over HTTPS, held to public addresses.
    Network(reqwest::Client),
    /// Photos held in memory by URL: for the tests and for a development
    /// server that must not reach the network. The agreement's hosts are
    /// checked all the same.
    Memory(Arc<HashMap<String, Vec<u8>>>),
}

impl std::fmt::Debug for PhotoSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Network(_) => f.write_str("PhotoSource::Network"),
            Self::Memory(m) => write!(f, "PhotoSource::Memory({} photos)", m.len()),
        }
    }
}

/// Why a download failed.
#[derive(Debug, thiserror::Error)]
pub enum FetchError {
    /// A URL, or a redirect, outside the agreement's hosts.
    #[error("the URL is not on a host of the agreement")]
    Host,
    /// The request failed (a refused address included).
    #[error("the download failed")]
    Http(#[source] reqwest::Error),
    /// The host answered something else than the photo.
    #[error("the host answered {0}")]
    Status(StatusCode),
    /// The answer passed the size limit.
    #[error("the photo is larger than allowed")]
    TooLarge,
    /// The download took too long.
    #[error("the download took too long")]
    Timeout,
    /// The photo is not in memory ([`PhotoSource::Memory`]).
    #[error("no such photo")]
    Missing,
}

impl PhotoSource {
    /// The network source: HTTPS only, no redirect followed by the client
    /// (the proxy checks each one), no proxy from the environment, and a
    /// resolver that refuses every address that is not public.
    ///
    /// # Errors
    ///
    /// The client's error when the TLS stack cannot be set up.
    pub fn network(timeout: Duration) -> Result<Self, reqwest::Error> {
        // reqwest is built without a bundled crypto provider (workspace
        // manifest); an error means one is installed already.
        static RING: std::sync::Once = std::sync::Once::new();
        RING.call_once(|| {
            let _ = rustls::crypto::ring::default_provider().install_default();
        });
        let client = reqwest::Client::builder()
            .user_agent(concat!(
                "Lunaway/",
                env!("CARGO_PKG_VERSION"),
                " (+https://lunaway.net)"
            ))
            .https_only(true)
            .redirect(reqwest::redirect::Policy::none())
            .no_proxy()
            .dns_resolver(Arc::new(PublicOnly))
            .connect_timeout(Duration::from_secs(10))
            .timeout(timeout)
            .build()?;
        Ok(Self::Network(client))
    }

    /// The bytes at `url`, which must be on one of `hosts`, as must every
    /// redirect; at most `max` bytes.
    ///
    /// # Errors
    ///
    /// [`FetchError`].
    pub async fn fetch(
        &self,
        url: &str,
        hosts: &[String],
        max: usize,
    ) -> Result<Vec<u8>, FetchError> {
        if !photo_url_allowed(url, hosts) {
            return Err(FetchError::Host);
        }
        let client = match self {
            Self::Memory(m) => {
                let bytes = m.get(url).ok_or(FetchError::Missing)?;
                return if bytes.len() > max {
                    Err(FetchError::TooLarge)
                } else {
                    Ok(bytes.clone())
                };
            }
            Self::Network(c) => c,
        };
        let mut current = url.to_owned();
        for _ in 0..=MAX_REDIRECTS {
            let mut response = client
                .get(&current)
                .send()
                .await
                .map_err(FetchError::Http)?;
            let status = response.status();
            if status.is_redirection() {
                let next = response
                    .headers()
                    .get(header::LOCATION)
                    .and_then(|v| v.to_str().ok())
                    .and_then(|l| reqwest::Url::parse(&current).ok()?.join(l).ok())
                    .ok_or(FetchError::Status(status))?;
                if !photo_url_allowed(next.as_str(), hosts) {
                    return Err(FetchError::Host);
                }
                current = next.to_string();
                continue;
            }
            if status != StatusCode::OK {
                return Err(FetchError::Status(status));
            }
            if response
                .content_length()
                .is_some_and(|n| n > u64::try_from(max).unwrap_or(u64::MAX))
            {
                return Err(FetchError::TooLarge);
            }
            let mut body = Vec::new();
            while let Some(chunk) = response.chunk().await.map_err(FetchError::Http)? {
                if body.len() + chunk.len() > max {
                    return Err(FetchError::TooLarge);
                }
                body.extend_from_slice(&chunk);
            }
            return Ok(body);
        }
        Err(FetchError::Status(StatusCode::LOOP_DETECTED))
    }
}

/// Resolves a name to its public addresses only; a name with none fails.
struct PublicOnly;

impl reqwest::dns::Resolve for PublicOnly {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        let host = name.as_str().to_owned();
        Box::pin(async move {
            let found = tokio::net::lookup_host((host.as_str(), 443)).await?;
            let public: Vec<SocketAddr> = found.filter(|a| is_public(a.ip())).collect();
            if public.is_empty() {
                return Err("the name resolves to no public address".into());
            }
            let addrs: reqwest::dns::Addrs = Box::new(public.into_iter());
            Ok(addrs)
        })
    }
}

/// Whether `ip` is an address of the public internet: not loopback,
/// private, shared, link-local, multicast, documentation, benchmarking or
/// reserved, and for IPv6 not unique-local, link-local, or an IPv4 address
/// in disguise that is not public itself.
#[must_use]
pub fn is_public(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => is_public_v4(v4),
        IpAddr::V6(v6) => is_public_v6(v6),
    }
}

fn is_public_v4(ip: Ipv4Addr) -> bool {
    let [a, b, c, _] = ip.octets();
    !(ip.is_unspecified()
        || ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_broadcast()
        || ip.is_documentation()
        || ip.is_multicast()
        || a == 0
        // Shared address space (carrier-grade NAT), 100.64.0.0/10.
        || (a == 100 && (64..128).contains(&b))
        // IETF protocol assignments, 192.0.0.0/24.
        || (a == 192 && b == 0 && c == 0)
        // Benchmarking, 198.18.0.0/15.
        || (a == 198 && (b == 18 || b == 19))
        // Reserved, 240.0.0.0/4.
        || a >= 240)
}

fn is_public_v6(ip: Ipv6Addr) -> bool {
    if let Some(v4) = ip.to_ipv4_mapped() {
        return is_public_v4(v4);
    }
    let s = ip.segments();
    // NAT64 (64:ff9b::/96) embeds an IPv4 address.
    if s[0] == 0x64 && s[1] == 0xff9b && s[2..6] == [0, 0, 0, 0] {
        let [a, b] = s[6].to_be_bytes();
        let [c, d] = s[7].to_be_bytes();
        return is_public_v4(Ipv4Addr::new(a, b, c, d));
    }
    // 6to4 (2002::/16) embeds an IPv4 address in its next 32 bits.
    if s[0] == 0x2002 {
        let [a, b] = s[1].to_be_bytes();
        let [c, d] = s[2].to_be_bytes();
        return is_public_v4(Ipv4Addr::new(a, b, c, d));
    }
    !(ip.is_unspecified()
        || ip.is_loopback()
        || ip.is_multicast()
        // Teredo, 2001::/32: a tunnel to an address it hides.
        || (s[0] == 0x2001 && s[1] == 0)
        // Unique local, fc00::/7.
        || (s[0] & 0xfe00) == 0xfc00
        // Link-local, fe80::/10.
        || (s[0] & 0xffc0) == 0xfe80
        // Documentation, 2001:db8::/32.
        || (s[0] == 0x2001 && s[1] == 0x0db8)
        // IPv4-compatible and other addresses of ::/96.
        || s[..6] == [0, 0, 0, 0, 0, 0])
}

/// What the proxy shares across requests.
pub(crate) struct ExternalPhotoEndpoint {
    pub(crate) pool: PgPool,
    pub(crate) rate: Arc<RateLimiter>,
    pub(crate) media: Arc<MediaStore>,
    pub(crate) media_config: MediaConfig,
    pub(crate) workers: Arc<Semaphore>,
    pub(crate) slots: Semaphore,
    pub(crate) source: PhotoSource,
    pub(crate) budget: DailyBudget,
    /// Each client's share of the downloads (`Action::ExternalPhoto`).
    pub(crate) quotas: Arc<QuotaLimiter>,
}

/// Downloads allowed per UTC day, all clients together: a client walking
/// the whole map within its own budget must not make the server copy the
/// partner's photo library in a day, nor fill the disk.
pub(crate) struct DailyBudget {
    per_day: u32,
    spent: std::sync::Mutex<(chrono::NaiveDate, u32)>,
}

impl DailyBudget {
    fn new(per_day: u32) -> Self {
        Self {
            per_day,
            spent: std::sync::Mutex::new((chrono::NaiveDate::MIN, 0)),
        }
    }

    /// Takes one download at `now`, or says how long until the next day.
    fn take(&self, now: chrono::DateTime<Utc>) -> Result<(), Duration> {
        let today = now.date_naive();
        let mut spent = self
            .spent
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if spent.0 != today {
            *spent = (today, 0);
        }
        if spent.1 >= self.per_day {
            let midnight = today
                .succ_opt()
                .map_or(now, |d| d.and_time(chrono::NaiveTime::MIN).and_utc());
            return Err((midnight - now).to_std().unwrap_or(Duration::from_secs(60)));
        }
        spent.1 += 1;
        Ok(())
    }
}

/// One download of a client's share (`Action::ExternalPhoto`), given back
/// when dropped before the partner's host is asked: a slot that never came,
/// the day's budget spent, or a client gone while it waited.
struct Share<'a> {
    quotas: &'a QuotaLimiter,
    subject: Subject,
    spent: bool,
}

impl<'a> Share<'a> {
    /// Takes one download of `client`'s share, or says how long until one
    /// is free.
    fn take(quotas: &'a QuotaLimiter, client: ClientKey) -> Result<Self, Duration> {
        let subject = Subject::Client(client);
        quotas.take(Action::ExternalPhoto, subject)?;
        Ok(Self {
            quotas,
            subject,
            spent: false,
        })
    }

    /// The download goes ahead: the share stays taken.
    fn spend(mut self) {
        self.spent = true;
    }
}

impl Drop for Share<'_> {
    fn drop(&mut self) {
        if !self.spent {
            self.quotas.give_back(Action::ExternalPhoto, self.subject);
        }
    }
}

impl ExternalPhotoEndpoint {
    #[allow(
        clippy::too_many_arguments,
        reason = "the endpoint's shared parts, each from the API state"
    )]
    pub(crate) fn new(
        pool: PgPool,
        rate: Arc<RateLimiter>,
        quotas: Arc<QuotaLimiter>,
        media: Arc<MediaStore>,
        media_config: MediaConfig,
        workers: Arc<Semaphore>,
        config: ExternalPhotosConfig,
        source: PhotoSource,
    ) -> Self {
        Self {
            pool,
            rate,
            media,
            media_config,
            workers,
            slots: Semaphore::new(config.fetches_at_once),
            source,
            budget: DailyBudget::new(config.downloads_per_day),
            quotas,
        }
    }
}

fn internal_error(error: &dyn std::fmt::Display) -> Response {
    tracing::error!(%error, "external photo failed");
    refuse(
        StatusCode::INTERNAL_SERVER_ERROR,
        INTERNAL,
        "internal error",
    )
}

fn not_found() -> Response {
    refuse(StatusCode::NOT_FOUND, NOT_FOUND, "no such photo")
}

fn redirect(to: &str) -> Response {
    let mut response = StatusCode::FOUND.into_response();
    if let Ok(v) = HeaderValue::from_str(to) {
        response.headers_mut().insert(header::LOCATION, v);
    }
    // The address of a photo's file never changes: a device may keep the
    // redirect a day, and the file itself for good.
    response.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=86400"),
    );
    response
}

/// The wait before the next try after `attempts` failures.
fn backoff(attempts: i16) -> chrono::Duration {
    let doublings = u32::try_from(attempts.clamp(0, 10)).unwrap_or(0);
    (FIRST_RETRY * 2_i32.pow(doublings)).min(LONGEST_RETRY)
}

/// Serves one photo.
pub(crate) async fn photo(
    State(ep): State<Arc<ExternalPhotoEndpoint>>,
    Path((id, size)): Path<(String, String)>,
    request: Request,
) -> Response {
    let (mut parts, _) = request.into_parts();
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
    let Ok(id) = Uuid::parse_str(&id) else {
        return not_found();
    };
    let thumb = match size.as_str() {
        "thumb" => true,
        "large" => false,
        _ => return not_found(),
    };
    let today = Utc::now().date_naive();
    let photo = match extcom::photo_for_proxy(&ep.pool, id, today).await {
        Ok(Some(p)) => p,
        Ok(None) => return not_found(),
        Err(e) => return internal_error(&e),
    };
    if let (Some(path), Some(thumb_path)) = (&photo.path, &photo.thumb_path) {
        return redirect(&ep.media_config.url(if thumb { thumb_path } else { path }));
    }
    if !photo_url_allowed(&photo.url, &photo.hosts) {
        // No agreement in force allows this host any more.
        return not_found();
    }
    if let Some(at) = photo.retry_after {
        let wait = (at - Utc::now()).to_std().unwrap_or(Duration::ZERO);
        if !wait.is_zero() {
            let mut response = refuse(
                StatusCode::SERVICE_UNAVAILABLE,
                UNAVAILABLE,
                "the photo could not be fetched; it is tried again later",
            );
            response
                .headers_mut()
                .insert(header::RETRY_AFTER, HeaderValue::from(wait.as_secs()));
            return response;
        }
    }
    // The client's share first, before it waits for a download slot: a
    // client past it neither queues nor spends the budget of the others.
    let share = match Share::take(&ep.quotas, client) {
        Ok(share) => share,
        Err(wait) => {
            return wait_response(
                StatusCode::TOO_MANY_REQUESTS,
                "this client's downloads of the partner's photos are spent; try again later",
                wait,
            );
        }
    };
    let Ok(Ok(_slot)) = tokio::time::timeout(SLOT_WAIT, ep.slots.acquire()).await else {
        return wait_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "the server is busy; try again in a moment",
            Duration::from_secs(5),
        );
    };
    if let Err(wait) = ep.budget.take(Utc::now()) {
        return wait_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "today's downloads of the partner's photos are spent; try again tomorrow",
            wait,
        );
    }
    // From here the partner's host is asked: the share is spent.
    share.spend();
    let max = ep.media_config.max_upload_bytes;
    let bytes = match ep.source.fetch(&photo.url, &photo.hosts, max).await {
        Ok(b) => b,
        Err(error) => return failed(&ep, &photo, error.to_string()).await,
    };
    let Ok(Ok(worker)) =
        tokio::time::timeout(SLOT_WAIT, Arc::clone(&ep.workers).acquire_owned()).await
    else {
        return wait_response(
            StatusCode::SERVICE_UNAVAILABLE,
            "the server is busy; try again in a moment",
            Duration::from_secs(5),
        );
    };
    let limits = MediaLimits {
        max_bytes: max,
        max_alloc: 256 * 1024 * 1024,
        ..MediaLimits::default()
    };
    let processed = tokio::task::spawn_blocking(move || {
        let _worker = worker;
        lunaway_media::process(&bytes, &limits)
    })
    .await;
    let processed = match processed {
        Ok(Ok(p)) => p,
        Ok(Err(e)) if e.is_client_error() => return failed(&ep, &photo, e.to_string()).await,
        Ok(Err(e)) => return internal_error(&e),
        Err(e) => return internal_error(&e),
    };
    let stored = async {
        let full = ep.media.put(&processed.full).await?;
        let thumb = ep.media.put(&processed.thumb).await?;
        Ok::<_, lunaway_media::MediaError>((full, thumb))
    }
    .await;
    let (full, thumb_path) = match stored {
        Ok(paths) => paths,
        Err(e) => return internal_error(&e),
    };
    let size = |w: u32| i32::try_from(w).unwrap_or(i32::MAX);
    let recorded = extcom::photo_processed(
        &ep.pool,
        photo.id,
        extcom::ProcessedPhoto {
            path: &full,
            thumb_path: &thumb_path,
            size: (size(processed.full.width), size(processed.full.height)),
            thumb_size: (size(processed.thumb.width), size(processed.thumb.height)),
            thumbhash: &processed.thumbhash,
        },
    )
    .await;
    match recorded {
        Ok(extcom::Recorded::Live) => {
            redirect(&ep.media_config.url(if thumb { &thumb_path } else { &full }))
        }
        // Retired while it downloaded (an erasure, a purge): its files are
        // named by its row for `purge-media`, and served to nobody.
        Ok(extcom::Recorded::Retired) => not_found(),
        // Another request stored it first: serve what that one recorded.
        Ok(extcom::Recorded::Already) => {
            match extcom::photo_for_proxy(&ep.pool, photo.id, today).await {
                Ok(Some(extcom::ProxyPhoto {
                    path: Some(path),
                    thumb_path: Some(thumb_path),
                    ..
                })) => redirect(&ep.media_config.url(if thumb { &thumb_path } else { &path })),
                Ok(_) => not_found(),
                Err(e) => internal_error(&e),
            }
        }
        Err(e) => internal_error(&e),
    }
}

/// Records a failed download and answers that the photo is not there yet.
async fn failed(ep: &ExternalPhotoEndpoint, photo: &extcom::ProxyPhoto, error: String) -> Response {
    // The photo's id only: its URL names a partner's file, not a person,
    // but nothing in a log line needs it.
    tracing::warn!(photo = %photo.id, %error, "external photo download failed");
    let wait = backoff(photo.attempts);
    if let Err(e) = extcom::photo_failed(&ep.pool, photo.id, Utc::now() + wait).await {
        return internal_error(&e);
    }
    let mut response = refuse(
        StatusCode::BAD_GATEWAY,
        UNAVAILABLE,
        "the photo could not be fetched; it is tried again later",
    );
    response.headers_mut().insert(
        header::RETRY_AFTER,
        HeaderValue::from(u64::try_from(wait.num_seconds()).unwrap_or(0)),
    );
    response
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_public_addresses_are_reached() {
        for private in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254",
            "100.64.0.1",
            "0.0.0.0",
            "198.18.0.1",
            "192.0.0.8",
            "240.0.0.1",
            "255.255.255.255",
            "224.0.0.1",
            "::1",
            "::",
            "fd00::1",
            "fe80::1",
            "ff02::1",
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.1",
            "64:ff9b::a9fe:a9fe",
            "::7f00:1",
            "2001:db8::1",
            "2002:7f00:1::1",
            "2001:0:4136:e378::1",
        ] {
            assert!(
                !is_public(private.parse().unwrap()),
                "{private} must not be reached by a feed's URL"
            );
        }
        for public in [
            "93.184.215.14",
            "2a01:4f8::1",
            "::ffff:93.184.215.14",
            "64:ff9b::5db8:d70e",
        ] {
            assert!(is_public(public.parse().unwrap()), "{public}");
        }
    }

    #[test]
    fn the_wait_after_a_failure_doubles_up_to_a_week() {
        assert_eq!(backoff(0), chrono::Duration::hours(1));
        assert_eq!(backoff(1), chrono::Duration::hours(2));
        assert_eq!(backoff(3), chrono::Duration::hours(8));
        assert_eq!(backoff(9), chrono::Duration::days(7));
        assert_eq!(backoff(i16::MAX), chrono::Duration::days(7));
    }

    #[tokio::test]
    async fn a_memory_source_still_holds_urls_to_the_agreement() {
        let url = "https://img.partner.example/1.jpg".to_owned();
        let source = PhotoSource::Memory(Arc::new(HashMap::from([(url.clone(), vec![1, 2, 3])])));
        let hosts = vec!["img.partner.example".to_owned()];
        assert_eq!(source.fetch(&url, &hosts, 10).await.unwrap(), vec![1, 2, 3]);
        assert!(matches!(
            source.fetch(&url, &[], 10).await,
            Err(FetchError::Host)
        ));
        assert!(matches!(
            source.fetch(&url, &hosts, 2).await,
            Err(FetchError::TooLarge)
        ));
    }
}

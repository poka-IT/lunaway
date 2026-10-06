//! The HTTP side of the road event feeds: one GET at a time, on the hosts a
//! feed publishes from only (redirects included), asked gzip-compressed and
//! inflated within a bound, conditional on the last ETag when the feed
//! gives one, retried on load shedding only and never sooner than a
//! `Retry-After` (`crate::http`).

use reqwest::{
    StatusCode,
    header::{ACCEPT_ENCODING, CONTENT_ENCODING, ETAG, IF_NONE_MATCH},
};

use crate::{
    IngestError,
    http::{RetryPolicy, check_status, read_capped, with_retry},
    web::check_host,
};

/// What a GET gave.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Answer {
    /// The body, inflated, with the ETag the server sent.
    Body {
        /// The bytes.
        bytes: Vec<u8>,
        /// The validator, for the next conditional GET.
        etag: Option<String>,
    },
    /// Unchanged since the ETag sent (304).
    NotModified,
    /// Not there (404): an increment not yet published.
    NotFound,
}

/// How to ask.
#[derive(Debug, Clone, Copy)]
pub struct Ask<'a> {
    /// Hosts the URL and its redirects may be on.
    pub hosts: &'a [String],
    /// Retries on load shedding.
    pub retry: RetryPolicy,
    /// Largest body accepted on the wire.
    pub max_wire: usize,
    /// Largest body accepted once inflated.
    pub max_inflated: usize,
    /// The ETag of the copy in hand.
    pub etag: Option<&'a str>,
}

/// GETs `url` as `ask` says.
///
/// # Errors
///
/// [`IngestError`] when the URL is not on the feed's hosts, the server
/// keeps failing, or the answer exceeds its bounds.
pub async fn get(http: &reqwest::Client, url: &str, ask: Ask<'_>) -> Result<Answer, IngestError> {
    let hosts: Vec<&str> = ask.hosts.iter().map(String::as_str).collect();
    check_host(url, &hosts)?;
    with_retry(url, ask.retry, || async {
        let mut request = http.get(url).header(ACCEPT_ENCODING, "gzip");
        if let Some(etag) = ask.etag {
            request = request.header(IF_NONE_MATCH, etag);
        }
        let response = request.send().await.map_err(|source| IngestError::Http {
            url: url.to_owned(),
            source,
        })?;
        // A redirect may not leave the feed's hosts.
        check_host(response.url().as_str(), &hosts)?;
        match response.status() {
            StatusCode::NOT_MODIFIED => return Ok(Answer::NotModified),
            StatusCode::NOT_FOUND => return Ok(Answer::NotFound),
            _ => {}
        }
        let response = check_status(url, response).await?;
        let etag = response
            .headers()
            .get(ETAG)
            .and_then(|v| v.to_str().ok())
            .filter(|v| v.len() <= 200)
            .map(str::to_owned);
        let gzipped = response
            .headers()
            .get(CONTENT_ENCODING)
            .and_then(|v| v.to_str().ok())
            .is_some_and(|v| v.trim().eq_ignore_ascii_case("gzip"));
        let bytes = read_capped(url, response, ask.max_wire).await?;
        let bytes = if gzipped {
            inflate(url, &bytes, ask.max_inflated)?
        } else if bytes.len() > ask.max_inflated {
            return Err(IngestError::TooLarge {
                url: url.to_owned(),
                limit: ask.max_inflated,
            });
        } else {
            bytes
        };
        Ok(Answer::Body { bytes, etag })
    })
    .await
}

/// Inflates a gzip body, reading at most `limit` bytes: a small answer that
/// inflates without end is refused, not held.
///
/// # Errors
///
/// [`IngestError::Inflate`] when it is not gzip, [`IngestError::TooLarge`]
/// past `limit`.
pub fn inflate(url: &str, gzipped: &[u8], limit: usize) -> Result<Vec<u8>, IngestError> {
    use std::io::Read as _;
    let mut out = Vec::new();
    flate2::read::GzDecoder::new(gzipped)
        .take(u64::try_from(limit).unwrap_or(u64::MAX) + 1)
        .read_to_end(&mut out)
        .map_err(|source| IngestError::Inflate {
            what: url.to_owned(),
            source,
        })?;
    if out.len() > limit {
        return Err(IngestError::TooLarge {
            url: url.to_owned(),
            limit,
        });
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_gzip_bomb_is_refused_within_its_bound() {
        use std::io::Write as _;
        let mut z = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::best());
        z.write_all(&vec![b' '; 2_000_000]).unwrap();
        let bomb = z.finish().unwrap();
        assert!(matches!(
            inflate("u", &bomb, 1_000_000),
            Err(IngestError::TooLarge { .. })
        ));
        assert_eq!(inflate("u", &bomb, 2_000_000).unwrap().len(), 2_000_000);
        assert!(matches!(
            inflate("u", b"plain", 10),
            Err(IngestError::Inflate { .. })
        ));
    }
}

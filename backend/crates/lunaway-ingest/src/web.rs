//! Checks on URLs that come from a source: a website the app will show as a
//! link, and a download location read from a source's metadata.

use reqwest::Url;

use crate::IngestError;

/// A website as a link the app may open: an `http` or `https` URL with a
/// dotted host and no credentials. A bare host (`www.camping.fr`) gets
/// `http://`, as the sources mean it; the first of a `;` list is kept, as
/// OSM separates several values. Anything else is dropped: `javascript:`,
/// `data:`, `mailto:`, a phone number, free text. The value is otherwise
/// kept as the source wrote it.
#[must_use]
pub fn website(raw: &str) -> Option<String> {
    let first = raw.split(';').map(str::trim).find(|s| !s.is_empty())?;
    let lower = first.to_ascii_lowercase();
    let candidate = if lower.starts_with("http://") || lower.starts_with("https://") {
        first.to_owned()
    } else if first.contains("://") {
        return None;
    } else {
        // Without a scheme, `mailto:x@y.fr` reads as credentials and
        // `javascript:alert(1)` as a port, both refused below.
        format!("http://{first}")
    };
    let url = Url::parse(&candidate).ok()?;
    let host = url.host_str()?;
    let link = matches!(url.scheme(), "http" | "https")
        && url.username().is_empty()
        && url.password().is_none()
        && host.contains('.');
    link.then_some(candidate)
}

/// Refuses `url` unless it is HTTP(S) on one of `hosts`: a location read
/// from a source's metadata must point where the source publishes.
///
/// # Errors
///
/// [`IngestError::UntrustedUrl`] otherwise.
pub(crate) fn check_host(url: &str, hosts: &[&str]) -> Result<(), IngestError> {
    let refuse = |reason| IngestError::UntrustedUrl {
        url: url.to_owned(),
        reason,
    };
    let parsed = Url::parse(url).map_err(|_| refuse("not a URL"))?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err(refuse("not an HTTP URL"));
    }
    let host = parsed.host_str().ok_or_else(|| refuse("no host"))?;
    if hosts.iter().any(|h| h.eq_ignore_ascii_case(host)) {
        Ok(())
    } else {
        Err(refuse("host not in the source's allowlist"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn websites_keep_only_web_links() {
        assert_eq!(
            website("https://www.camping.fr/fr").as_deref(),
            Some("https://www.camping.fr/fr")
        );
        assert_eq!(
            website(" www.camping.fr ").as_deref(),
            Some("http://www.camping.fr")
        );
        assert_eq!(
            website("https://a.fr;https://b.fr").as_deref(),
            Some("https://a.fr")
        );
        for hostile in [
            "javascript:alert(1)",
            "JavaScript://%0aalert(1)",
            "data:text/html,<script>alert(1)</script>",
            "mailto:accueil@camping.fr",
            "tel:+33241000000",
            "ftp://files.camping.fr",
            "file:///etc/passwd",
            "https://user:secret@camping.fr",
            "voir la mairie",
            "",
        ] {
            assert_eq!(website(hostile), None, "{hostile:?} must not become a link");
        }
    }

    #[test]
    fn a_download_must_stay_on_the_source_hosts() {
        let hosts = ["data.classement.atout-france.fr"];
        assert!(
            check_host(
                "https://data.classement.atout-france.fr/static/x.csv",
                &hosts
            )
            .is_ok()
        );
        for url in [
            "https://evil.example/x.csv",
            "https://data.classement.atout-france.fr.evil.example/x.csv",
            "file:///etc/passwd",
            "not a url",
        ] {
            assert!(
                matches!(
                    check_host(url, &hosts),
                    Err(IngestError::UntrustedUrl { .. })
                ),
                "{url}"
            );
        }
    }
}

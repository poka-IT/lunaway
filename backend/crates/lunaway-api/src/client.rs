//! Who is asking: the key a client's requests are counted under.
//!
//! The API listens on loopback behind Caddy, which sets `X-Forwarded-For` to
//! the address it received the request from. The header is believed only
//! when the connection itself comes from loopback: anything else reaching
//! the API directly would choose its own key with it. An IPv6 client is
//! counted by its /64, the block a single subscriber gets, so cycling
//! addresses inside it gives no new budget; its /48, which one site or one
//! tunnel account often holds whole, has a shared budget of its own on top.

use std::net::{IpAddr, SocketAddr};

use axum::http::HeaderMap;

/// The key a client's requests are counted under. It is never logged: it is
/// derived from an IP address, which is personal data.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub(crate) enum ClientKey {
    /// An IPv4 address.
    V4(u32),
    /// The /64 of an IPv6 address.
    V6(u64),
    /// The /48 of an IPv6 address: 65 536 /64s that one holder may rotate
    /// through.
    V6Site(u64),
    /// A connection whose peer is unknown (tests without a socket).
    Unknown,
}

impl ClientKey {
    /// The key of `ip`; an IPv4-mapped IPv6 address counts as its IPv4.
    #[must_use]
    pub(crate) fn of(ip: IpAddr) -> Self {
        match ip {
            IpAddr::V4(v4) => Self::V4(u32::from(v4)),
            IpAddr::V6(v6) => match v6.to_ipv4_mapped() {
                Some(v4) => Self::V4(u32::from(v4)),
                None => {
                    let [a, b, c, d, ..] = v6.segments();
                    Self::V6(
                        (u64::from(a) << 48)
                            | (u64::from(b) << 32)
                            | (u64::from(c) << 16)
                            | u64::from(d),
                    )
                }
            },
        }
    }

    /// The wider block whose budget this key also draws on, if any.
    #[must_use]
    pub(crate) const fn site(self) -> Option<Self> {
        match self {
            Self::V6(prefix) => Some(Self::V6Site(prefix >> 16)),
            _ => None,
        }
    }

    /// Whether this key is a block shared by several clients.
    #[must_use]
    pub(crate) const fn is_site(self) -> bool {
        matches!(self, Self::V6Site(_))
    }

    /// The key of a request reaching the API from `peer` with `headers`.
    #[must_use]
    pub(crate) fn from_request(peer: Option<SocketAddr>, headers: &HeaderMap) -> Self {
        let Some(peer) = peer else {
            return Self::Unknown;
        };
        if peer.ip().is_loopback()
            && let Some(forwarded) = forwarded_for(headers)
        {
            return Self::of(forwarded);
        }
        Self::of(peer.ip())
    }
}

/// The address the nearest proxy saw: the last valid entry of the last
/// `X-Forwarded-For` header. Earlier entries were written by the client or
/// by proxies before Caddy, which nothing vouches for.
fn forwarded_for(headers: &HeaderMap) -> Option<IpAddr> {
    let last = headers.get_all("x-forwarded-for").iter().next_back()?;
    last.to_str()
        .ok()?
        .rsplit(',')
        .map(str::trim)
        .find(|s| !s.is_empty())?
        .parse()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn headers(xff: &[&str]) -> HeaderMap {
        let mut h = HeaderMap::new();
        for v in xff {
            h.append("x-forwarded-for", v.parse().unwrap());
        }
        h
    }

    fn peer(s: &str) -> Option<SocketAddr> {
        Some(s.parse().unwrap())
    }

    #[test]
    fn the_header_is_believed_from_the_local_proxy_only() {
        let from_caddy =
            ClientKey::from_request(peer("127.0.0.1:50000"), &headers(&["203.0.113.9"]));
        assert_eq!(from_caddy, ClientKey::of("203.0.113.9".parse().unwrap()));
        let direct =
            ClientKey::from_request(peer("198.51.100.1:50000"), &headers(&["203.0.113.9"]));
        assert_eq!(
            direct,
            ClientKey::of("198.51.100.1".parse().unwrap()),
            "a client reaching the API directly cannot choose its key"
        );
        let local_v6 = ClientKey::from_request(peer("[::1]:50000"), &headers(&["203.0.113.9"]));
        assert_eq!(local_v6, from_caddy);
    }

    #[test]
    fn the_nearest_proxy_s_entry_wins() {
        let spoofed = ClientKey::from_request(
            peer("127.0.0.1:1"),
            &headers(&["10.0.0.1, 192.0.2.1", "203.0.113.9"]),
        );
        assert_eq!(spoofed, ClientKey::of("203.0.113.9".parse().unwrap()));
        let garbage = ClientKey::from_request(peer("127.0.0.1:1"), &headers(&["not an ip"]));
        assert_eq!(garbage, ClientKey::of("127.0.0.1".parse().unwrap()));
    }

    #[test]
    fn ipv6_counts_by_its_64_and_mapped_ipv4_as_ipv4() {
        let a = ClientKey::of("2001:db8:1:2:aaaa::1".parse().unwrap());
        let b = ClientKey::of("2001:db8:1:2:bbbb::2".parse().unwrap());
        let c = ClientKey::of("2001:db8:1:3::1".parse().unwrap());
        assert_eq!(a, b, "one subscriber, one budget");
        assert_ne!(a, c);
        assert_eq!(a.site(), c.site(), "one /48, one shared budget");
        assert_ne!(
            a.site(),
            ClientKey::of("2001:db8:2:2::1".parse().unwrap()).site()
        );
        assert_eq!(ClientKey::of("203.0.113.9".parse().unwrap()).site(), None);
        assert_eq!(
            ClientKey::of("::ffff:203.0.113.9".parse().unwrap()),
            ClientKey::of("203.0.113.9".parse().unwrap())
        );
    }
}

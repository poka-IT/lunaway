//! A streaming reader of the DATEX II feeds: it walks the document once and
//! builds a small tree for each repeated unit (a DIR situation, a DiaLog
//! order), dropped once read, so a 78 MB file is read in one pass with the
//! memory of one unit.
//!
//! DATEX II types its elements with `xsi:type` and prefixes them freely
//! (`ns2:situation` in the DIR aggregate, `situation` in its increments):
//! elements are matched by local name, and the local part of `xsi:type` is
//! kept. No DTD is read and no entity but the five of XML and character
//! references is expanded, so a payload cannot pull in an external file or
//! grow by entity expansion.

use quick_xml::{
    Reader, XmlVersion,
    events::{BytesRef, BytesStart, Event},
};

/// Deepest nesting accepted: DATEX II documents nest about twenty levels.
const MAX_DEPTH: usize = 64;
/// Most nodes in one unit: a DiaLog order with hundreds of street sections
/// holds a few thousand.
const MAX_UNIT_NODES: usize = 500_000;
/// Most leaf values kept outside the units (the publication header).
const MAX_OUTSIDE: usize = 256;

/// Why a document could not be read.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum XmlError {
    /// Not well-formed XML.
    #[error("malformed XML at byte {position}")]
    Malformed {
        /// Where the reader stopped.
        position: u64,
        /// The cause.
        #[source]
        source: quick_xml::Error,
    },
    /// Nested deeper than any DATEX II document.
    #[error("XML nested deeper than {MAX_DEPTH} levels")]
    TooDeep,
    /// One unit holds more nodes than any real one.
    #[error("an XML unit holds more than {MAX_UNIT_NODES} nodes")]
    TooLarge,
    /// The body is not UTF-8.
    #[error("the document is not UTF-8")]
    Encoding(#[source] std::str::Utf8Error),
}

/// An element of a unit: its local name, the local part of its `xsi:type`,
/// its attributes by local name, its text, its children, and where it lies
/// in the document.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Node {
    /// Local name.
    pub name: String,
    /// Local part of `xsi:type`.
    pub xsi_type: Option<String>,
    /// Attributes, by local name.
    pub attrs: Vec<(String, String)>,
    /// Text content (trimmed), entities expanded.
    pub text: String,
    /// Child elements, in order.
    pub children: Vec<Node>,
    /// Byte range of the element in the document.
    pub span: (usize, usize),
}

impl Node {
    /// The first child named `name`.
    #[must_use]
    pub fn child(&self, name: &str) -> Option<&Self> {
        self.children.iter().find(|c| c.name == name)
    }

    /// Every child named `name`.
    pub fn children_named<'a>(&'a self, name: &'a str) -> impl Iterator<Item = &'a Self> + 'a {
        self.children.iter().filter(move |c| c.name == name)
    }

    /// The node at `path` below this one, first match at each step.
    #[must_use]
    pub fn at(&self, path: &[&str]) -> Option<&Self> {
        path.iter().try_fold(self, |n, name| n.child(name))
    }

    /// The trimmed, non-empty text at `path`.
    #[must_use]
    pub fn text_at(&self, path: &[&str]) -> Option<&str> {
        self.at(path)
            .map(|n| n.text.as_str())
            .filter(|t| !t.is_empty())
    }

    /// The first descendant named `name`, depth first.
    #[must_use]
    pub fn find(&self, name: &str) -> Option<&Self> {
        self.children.iter().find_map(|c| {
            if c.name == name {
                Some(c)
            } else {
                c.find(name)
            }
        })
    }

    /// Every descendant named `name`, depth first, without looking inside
    /// a match.
    #[must_use]
    pub fn find_all(&self, name: &str) -> Vec<&Self> {
        let mut out = Vec::new();
        self.collect(name, &mut out);
        out
    }

    fn collect<'a>(&'a self, name: &str, out: &mut Vec<&'a Self>) {
        for c in &self.children {
            if c.name == name {
                out.push(c);
            } else {
                c.collect(name, out);
            }
        }
    }

    /// The attribute of local name `name`.
    #[must_use]
    pub fn attr(&self, name: &str) -> Option<&str> {
        self.attrs
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }

    /// The texts of the `value` elements below, joined by a space: a DATEX
    /// multilingual string.
    #[must_use]
    pub fn values_text(&self) -> Option<String> {
        let texts: Vec<&str> = self
            .find_all("value")
            .into_iter()
            .map(|v| v.text.as_str())
            .filter(|t| !t.is_empty())
            .collect();
        (!texts.is_empty()).then(|| texts.join(" "))
    }
}

/// What a walk found outside the units: the leaf values of the header
/// (`publicationTime`, `feedType`), by local name, in order.
#[derive(Debug, Clone, Default)]
pub struct Outside {
    /// Leaf values, by local name.
    pub leaves: Vec<(String, String)>,
}

impl Outside {
    /// The first value of local name `name`.
    #[must_use]
    pub fn get(&self, name: &str) -> Option<&str> {
        self.leaves
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }
}

fn local(name: &str) -> String {
    name.to_owned()
}

fn start_node(e: &BytesStart<'_>, at: usize) -> Node {
    let mut node = Node {
        name: local(e.local_name().as_ref()),
        span: (at, at),
        ..Node::default()
    };
    for attr in e.attributes().flatten() {
        let key = local(attr.key.local_name().as_ref());
        let value = attr.normalized_value(XmlVersion::Implicit1_0).map_or_else(
            |_| attr.value.clone().into_owned(),
            std::borrow::Cow::into_owned,
        );
        if key == "type" && attr.key.prefix().is_some_and(|p| p.as_ref() == "xsi") {
            let t = value.rsplit(':').next().unwrap_or_default().to_owned();
            node.xsi_type = Some(t);
        } else {
            node.attrs.push((key, value));
        }
    }
    node
}

/// Appends an entity or character reference to `text`: the five XML
/// entities and character references expand, anything else stays as
/// written.
fn push_ref(text: &mut String, r: &BytesRef<'_>) {
    if r.is_char_ref() {
        if let Ok(Some(c)) = r.resolve_char_ref() {
            text.push(c);
        }
        return;
    }
    let name: &str = r;
    match name {
        "amp" => text.push('&'),
        "lt" => text.push('<'),
        "gt" => text.push('>'),
        "quot" => text.push('"'),
        "apos" => text.push('\''),
        other => {
            text.push('&');
            text.push_str(other);
            text.push(';');
        }
    }
}

/// Walks `xml` once, calling `unit` with the tree of each element named
/// `unit_name` (a nested one is part of its enclosing unit). Stops early
/// when `unit` returns false.
///
/// # Errors
///
/// [`XmlError`] when the document is not UTF-8, not well-formed, or deeper
/// or larger than any real feed.
pub fn walk(
    xml: &[u8],
    unit_name: &str,
    mut unit: impl FnMut(Node) -> bool,
) -> Result<Outside, XmlError> {
    let text = std::str::from_utf8(xml).map_err(XmlError::Encoding)?;
    let mut reader = Reader::from_str(text);
    // Text is trimmed once its element ends: trimming each text event
    // would eat the spaces around an entity ("A &amp; B").
    reader.config_mut().trim_text(false);
    let mut outside = Outside::default();
    // Open elements outside a unit: their names and texts.
    let mut open: Vec<(String, String)> = Vec::new();
    // The unit being built: its stack of open nodes.
    let mut stack: Vec<Node> = Vec::new();
    let mut nodes = 0_usize;
    loop {
        let before = usize::try_from(reader.buffer_position()).unwrap_or(usize::MAX);
        let event = reader.read_event().map_err(|source| XmlError::Malformed {
            position: reader.error_position(),
            source,
        })?;
        let after = usize::try_from(reader.buffer_position()).unwrap_or(usize::MAX);
        match event {
            Event::Start(e) => {
                if open.len() + stack.len() >= MAX_DEPTH {
                    return Err(XmlError::TooDeep);
                }
                let in_unit = !stack.is_empty() || e.local_name().as_ref() == unit_name;
                if in_unit {
                    nodes += 1;
                    if nodes > MAX_UNIT_NODES {
                        return Err(XmlError::TooLarge);
                    }
                    stack.push(start_node(&e, before));
                } else {
                    open.push((local(e.local_name().as_ref()), String::new()));
                }
            }
            Event::Empty(e) => {
                if let Some(parent) = stack.last_mut() {
                    nodes += 1;
                    if nodes > MAX_UNIT_NODES {
                        return Err(XmlError::TooLarge);
                    }
                    let mut node = start_node(&e, before);
                    node.span.1 = after;
                    parent.children.push(node);
                }
            }
            Event::Text(t) => {
                let content = t.xml10_content();
                match (stack.last_mut(), open.last_mut()) {
                    (Some(n), _) => n.text.push_str(&content),
                    (None, Some((_, s))) => s.push_str(&content),
                    _ => {}
                }
            }
            Event::CData(c) => {
                let content: &str = &c;
                match (stack.last_mut(), open.last_mut()) {
                    (Some(n), _) => n.text.push_str(content),
                    (None, Some((_, s))) => s.push_str(content),
                    _ => {}
                }
            }
            Event::GeneralRef(r) => match (stack.last_mut(), open.last_mut()) {
                (Some(n), _) => push_ref(&mut n.text, &r),
                (None, Some((_, s))) => push_ref(s, &r),
                _ => {}
            },
            Event::End(_) => {
                if let Some(mut node) = stack.pop() {
                    node.span.1 = after;
                    node.text = node.text.trim().to_owned();
                    if let Some(parent) = stack.last_mut() {
                        parent.children.push(node);
                    } else {
                        nodes = 0;
                        if !unit(node) {
                            return Ok(outside);
                        }
                    }
                } else if let Some((name, text)) = open.pop() {
                    let text = text.trim();
                    if !text.is_empty() && outside.leaves.len() < MAX_OUTSIDE {
                        outside.leaves.push((name, text.to_owned()));
                    }
                }
            }
            Event::Eof => break,
            Event::Decl(_) | Event::PI(_) | Event::Comment(_) | Event::DocType(_) => {}
        }
    }
    Ok(outside)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn units_are_read_by_local_name_with_their_type_and_span() {
        let xml = br#"<?xml version="1.0"?><a:root xmlns:a="u" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <a:publicationTime>2026-10-06T12:57:45+02:00</a:publicationTime>
            <a:situation id="s1" version="2"><a:rec xsi:type="a:MaintenanceWorks"><a:v>A &amp; B &#233;</a:v><a:e/></a:rec></a:situation>
            <situation id="s2"><rec><![CDATA[x<y]]></rec></situation>
        </a:root>"#;
        let mut units = Vec::new();
        let outside = walk(xml, "situation", |n| {
            units.push(n);
            true
        })
        .unwrap();
        assert_eq!(
            outside.get("publicationTime"),
            Some("2026-10-06T12:57:45+02:00")
        );
        assert_eq!(units.len(), 2);
        let s1 = &units[0];
        assert_eq!(s1.attr("id"), Some("s1"));
        let rec = s1.child("rec").unwrap();
        assert_eq!(rec.xsi_type.as_deref(), Some("MaintenanceWorks"));
        assert_eq!(rec.text_at(&["v"]), Some("A & B é"));
        assert!(rec.child("e").is_some(), "an empty element is a child");
        let raw = std::str::from_utf8(&xml[s1.span.0..s1.span.1]).unwrap();
        assert!(
            raw.starts_with("<a:situation") && raw.ends_with("</a:situation>"),
            "{raw}"
        );
        assert_eq!(units[1].text_at(&["rec"]), Some("x<y"));
    }

    #[test]
    fn an_external_entity_is_never_fetched_nor_expanded() {
        let xml = br#"<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><r><situation><v>&x;</v></situation></r>"#;
        let mut texts = Vec::new();
        walk(xml, "situation", |n| {
            texts.push(n.text_at(&["v"]).unwrap_or_default().to_owned());
            true
        })
        .unwrap();
        assert_eq!(texts, ["&x;"], "the reference stays as written");
    }

    #[test]
    fn broken_or_hostile_documents_are_refused() {
        assert!(matches!(
            walk(b"<r><situation></r>", "situation", |_| true),
            Err(XmlError::Malformed { .. })
        ));
        let deep = "<a>".repeat(100) + &"</a>".repeat(100);
        assert!(matches!(
            walk(deep.as_bytes(), "situation", |_| true),
            Err(XmlError::TooDeep)
        ));
        assert!(matches!(
            walk(&[0xff, 0xfe, b'<'], "situation", |_| true),
            Err(XmlError::Encoding(_))
        ));
    }
}

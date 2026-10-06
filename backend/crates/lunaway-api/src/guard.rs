//! Bounds on a GraphQL document, checked before async-graphql works on it,
//! and the per-client charge once its cost is known.
//!
//! async-graphql bounds depth and complexity, but walks the document with
//! every fragment spread expanded again, without memoisation and on the
//! async thread, first to check its recursion depth right after parsing,
//! then to compute its complexity: a 900-byte document whose fragments
//! spread each other twice per level (`F0 { ...F1 ...F1 }`, 26 levels) took
//! 13 s to be refused. Its parser recurses once per nesting level, and 5 000
//! nested braces (15 KB) overflowed the stack and aborted the process. So,
//! before async-graphql parses a document, it is refused by its size and its
//! count of opening brackets (which bounds any nesting), then parsed here
//! and refused by the number of selections it expands to (each fragment
//! counted once); the parsed document is handed on, so it is parsed once.

use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use async_graphql::{
    Request, ServerError, ServerResult, ValidationResult,
    extensions::{
        Extension, ExtensionContext, ExtensionFactory, NextPrepareRequest, NextValidation,
    },
    parser::types::{ExecutableDocument, Selection, SelectionSet},
};

use crate::{
    client::ClientKey,
    error::{INVALID_INPUT, rate_limited},
    schema::{ApiState, CostShare},
};

/// Longest query text, bytes: the app's largest document is under 2 KB.
pub const MAX_QUERY_BYTES: usize = 16 * 1024;
/// Most opening brackets (`{`, `(`, `[`) in the text, wherever they are. The
/// app's sync document holds about 15 and the standard introspection query
/// about 70; the parser recurses once per nesting level and overflowed a
/// worker's 2 MiB stack at 5 000 levels (the test below parses this many on
/// such a stack).
pub const MAX_BRACKETS: usize = 256;
/// Most selections (fields, fragment spreads, inline fragments) a document
/// may hold once every fragment is expanded. A full sync page holds about
/// 50, the standard introspection query about 250.
pub const MAX_EXPANDED_SELECTIONS: usize = 1_000;

fn refused(message: impl Into<String>) -> ServerError {
    let mut e = ServerError::new(message, None);
    let mut ext = async_graphql::ErrorExtensionValues::default();
    ext.set("code", INVALID_INPUT);
    e.extensions = Some(ext);
    e
}

/// Refuses a query text too large, or holding more opening brackets than
/// [`MAX_BRACKETS`], counted in the whole text, strings and comments
/// included. The parser can nest no deeper than the number of openers, so
/// the bound holds however the text is lexed: a scan that skipped strings
/// and comments could be fooled by a comment ending in `\r` or a block
/// string with backslashes, which the parser reads differently.
///
/// # Errors
///
/// Why the text is refused.
pub fn check_text(query: &str) -> Result<(), String> {
    if query.len() > MAX_QUERY_BYTES {
        return Err(format!(
            "the query holds {} bytes, more than the {MAX_QUERY_BYTES} allowed",
            query.len()
        ));
    }
    let openers = query
        .bytes()
        .filter(|b| matches!(b, b'{' | b'(' | b'['))
        .count();
    if openers > MAX_BRACKETS {
        return Err(format!(
            "the query holds {openers} opening brackets, more than the {MAX_BRACKETS} allowed"
        ));
    }
    Ok(())
}

/// The number of selections `doc`'s operations hold once every fragment
/// spread is replaced by its fragment: what a walk that follows the spreads
/// visits. Each fragment is counted once and multiplied by its spreads.
///
/// # Errors
///
/// When fragments spread each other in a cycle, which would never end.
pub fn expanded_selections(doc: &ExecutableDocument) -> Result<usize, String> {
    let mut walk = Walk {
        doc,
        memo: HashMap::new(),
        open: HashSet::new(),
    };
    doc.operations.iter().try_fold(0usize, |total, (_, op)| {
        Ok(total.saturating_add(walk.count(&op.node.selection_set.node)?))
    })
}

struct Walk<'d> {
    doc: &'d ExecutableDocument,
    memo: HashMap<&'d str, usize>,
    open: HashSet<&'d str>,
}

impl<'d> Walk<'d> {
    fn count(&mut self, set: &'d SelectionSet) -> Result<usize, String> {
        let mut n = 0usize;
        for item in &set.items {
            let inner = match &item.node {
                Selection::Field(f) => self.count(&f.node.selection_set.node)?,
                Selection::InlineFragment(i) => self.count(&i.node.selection_set.node)?,
                Selection::FragmentSpread(s) => {
                    let name = s.node.fragment_name.node.as_str();
                    match self.memo.get(name) {
                        Some(known) => *known,
                        // An unknown fragment is reported by the validation;
                        // the spread itself still counts.
                        None => match self.doc.fragments.get(name) {
                            None => 0,
                            Some(def) => {
                                if !self.open.insert(name) {
                                    return Err(format!(
                                        "fragment {name} spreads itself through a cycle"
                                    ));
                                }
                                let c = self.count(&def.node.selection_set.node)?;
                                self.open.remove(name);
                                self.memo.insert(name, c);
                                c
                            }
                        },
                    }
                }
            };
            n = n.saturating_add(1).saturating_add(inner);
        }
        Ok(n)
    }
}

/// The extension that applies these bounds, charges the client, and holds
/// the request's share of the cost in flight.
pub(crate) struct DocumentGuard;

impl ExtensionFactory for DocumentGuard {
    fn create(&self) -> std::sync::Arc<dyn Extension> {
        std::sync::Arc::new(Self)
    }
}

#[async_graphql::async_trait::async_trait]
impl Extension for DocumentGuard {
    async fn prepare_request(
        &self,
        ctx: &ExtensionContext<'_>,
        mut request: Request,
        next: NextPrepareRequest<'_>,
    ) -> ServerResult<Request> {
        check_text(&request.query).map_err(refused)?;
        // Parsed once here; async-graphql reuses this document.
        let parsed = request.parsed_query().map_err(|mut e| {
            e.extensions
                .get_or_insert_with(Default::default)
                .set("code", INVALID_INPUT);
            e
        })?;
        let selections = expanded_selections(parsed).map_err(refused)?;
        if selections > MAX_EXPANDED_SELECTIONS {
            return Err(refused(format!(
                "the query holds {selections} fields and fragment spreads once its fragments \
                 are expanded, more than the {MAX_EXPANDED_SELECTIONS} allowed"
            )));
        }
        next.run(ctx, request).await
    }

    async fn validation(
        &self,
        ctx: &ExtensionContext<'_>,
        next: NextValidation<'_>,
    ) -> Result<ValidationResult, Vec<ServerError>> {
        let result = next.run(ctx).await?;
        let Some(state) = ctx.data_opt::<ApiState>() else {
            return Ok(result);
        };
        if let Some(key) = ctx.data_opt::<ClientKey>()
            && let Err(wait) = state.rate.charge(*key, result.complexity)
        {
            return Err(vec![rate_limited(
                "this client's request budget is spent; wait and try again",
                wait,
            )]);
        }
        // The memory a request holds grows with its cost: the costs running
        // at once are bounded across clients, whoever sends them.
        if let Some(share) = ctx.data_opt::<CostShare>() {
            let limits = state.config.limits;
            let cost = result.complexity.clamp(1, limits.max_cost_in_flight);
            let permits = u32::try_from(cost).unwrap_or(u32::MAX);
            let acquired = tokio::time::timeout(
                limits.queue_wait,
                Arc::clone(&state.in_flight).acquire_many_owned(permits),
            )
            .await;
            let Ok(Ok(permit)) = acquired else {
                return Err(vec![rate_limited(
                    "the server is busy; try again in a moment",
                    std::time::Duration::from_secs(1),
                )]);
            };
            *share
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(permit);
        }
        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brackets_are_counted_wherever_they_are() {
        assert!(check_text("{ a { b { c } } }").is_ok());
        let deep = format!(
            "{}{}",
            "{a".repeat(MAX_BRACKETS + 1),
            "}".repeat(MAX_BRACKETS + 1)
        );
        assert!(check_text(&deep).is_err());
        // Both passed a scan that skipped strings and comments, then
        // overflowed the parser's stack: a comment the parser ends at `\r`,
        // and a block string whose backslashes the parser does not escape.
        let comment = format!("#\r{{{}b{}}}", "a{".repeat(5000), "}".repeat(5000));
        assert!(check_text(&comment).is_err());
        let block = format!(
            "{{ f(a: \"\"\"\\\\\"\"\" \"\"\", b: {}{}) }}",
            "[".repeat(5000),
            "]".repeat(5000)
        );
        assert!(check_text(&block).is_err());
        assert!(check_text(&"a".repeat(MAX_QUERY_BYTES + 1)).is_err());
    }

    #[test]
    fn documents_at_the_bracket_limit_are_parsed_on_a_worker_sized_stack() {
        // tokio's worker threads have 2 MiB of stack, and an overflow aborts
        // the whole process: reaching the end of this test is the check.
        // The parser may refuse a document (its own selection limit is 64
        // levels); it must not crash on one.
        let n = MAX_BRACKETS - 2;
        let shapes = [
            format!("{{{}b{}}}", "a{".repeat(n), "}".repeat(n)),
            format!("{{ f(a: {}1{}) }}", "[".repeat(n), "]".repeat(n)),
            format!("{{ f(a: {}1{}) }}", "{a: ".repeat(n), "}".repeat(n)),
        ];
        for q in shapes {
            assert!(check_text(&q).is_ok());
            std::thread::Builder::new()
                .stack_size(2 * 1024 * 1024)
                .spawn(move || async_graphql::parser::parse_query(&q).is_ok())
                .unwrap()
                .join()
                .unwrap();
        }
    }

    #[test]
    fn the_introspection_query_fits() {
        assert!(check_text(INTROSPECTION).is_ok());
        assert!(expanded_selections(&doc(INTROSPECTION)).unwrap() <= MAX_EXPANDED_SELECTIONS);
    }

    /// The query GraphiQL and the codegen tools send.
    const INTROSPECTION: &str = r"
    query IntrospectionQuery {
      __schema {
        queryType { name } mutationType { name } subscriptionType { name }
        types { ...FullType }
        directives { name description locations args { ...InputValue } }
      }
    }
    fragment FullType on __Type {
      kind name description
      fields(includeDeprecated: true) {
        name description args { ...InputValue } type { ...TypeRef }
        isDeprecated deprecationReason
      }
      inputFields { ...InputValue }
      interfaces { ...TypeRef }
      enumValues(includeDeprecated: true) { name description isDeprecated deprecationReason }
      possibleTypes { ...TypeRef }
    }
    fragment InputValue on __InputValue { name description type { ...TypeRef } defaultValue }
    fragment TypeRef on __Type {
      kind name
      ofType { kind name ofType { kind name ofType { kind name ofType { kind name
        ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } }
    }";

    fn doc(q: &str) -> ExecutableDocument {
        async_graphql::parser::parse_query(q).unwrap()
    }

    #[test]
    fn fragments_are_counted_once_and_multiplied_by_their_spreads() {
        assert_eq!(expanded_selections(&doc("{ a b { c } }")).unwrap(), 3);
        assert_eq!(
            expanded_selections(&doc("{ ...F ...F } fragment F on Query { a b }")).unwrap(),
            6,
            "two spreads of two fields each"
        );
        // The fan-out of the review: 2^30 selections at the bottom from a
        // 1.2 KB document, counted without expanding anything.
        let mut q = String::from("query { ...F0 }\n");
        for i in 0..30 {
            q.push_str(&format!(
                "fragment F{i} on Query {{ ...F{} ...F{} }}\n",
                i + 1,
                i + 1
            ));
        }
        q.push_str("fragment F30 on Query { apiVersion }");
        let started = std::time::Instant::now();
        assert!(expanded_selections(&doc(&q)).unwrap() > 1 << 30);
        assert!(started.elapsed() < std::time::Duration::from_secs(1));
        // Spreads of a fragment that does not exist fan out as well.
        let mut q = String::from("query { ...F0 }\n");
        for i in 0..30 {
            q.push_str(&format!(
                "fragment F{i} on Query {{ ...F{} ...F{} }}\n",
                i + 1,
                i + 1
            ));
        }
        assert!(expanded_selections(&doc(&q)).unwrap() > 1 << 30);
    }

    #[test]
    fn a_fragment_cycle_is_refused_not_followed() {
        let cyclic = doc("{ ...A } fragment A on Query { ...B } fragment B on Query { ...A }");
        assert!(expanded_selections(&cyclic).is_err());
    }
}

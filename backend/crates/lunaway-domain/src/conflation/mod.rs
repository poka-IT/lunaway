//! Conflation: several sources describe the same spot, the app shows one
//! place with every source credited (`docs/architecture.md`, "Conflation").
//!
//! The steps, each pure and deterministic:
//!
//! 1. [`normalize`]: names folded, generic words removed, phones and
//!    websites reduced to one form;
//! 2. [`score`]: the match score of a pair, with its components;
//! 3. [`cluster`]: union-find of the merge decisions under the same-source
//!    rule and the human constraints;
//! 4. [`resolve`]: each field of a place from the best-ranked source;
//!    [`public_dump`] resolves it again, for a published dump, without the
//!    sources an agreement keeps out of the open licence.
//!
//! The database side (finding candidates, storing decisions, writing places)
//! is `lunaway-conflate`.

pub mod cluster;
pub mod normalize;
pub mod public_dump;
pub mod resolve;
pub mod score;
pub mod similarity;

pub use cluster::{Clustering, Constraint, ConstraintKind, MergeEdge, cluster};
pub use resolve::{
    AlternativeValue, Contribution, ExternalLink, Field, FieldProvenance, LocalizedText,
    PlaceContent, ResolvedPlace, resolve, trust_prior, wikipedia_url,
};
pub use score::{
    Decision, IdentifierKind, MERGE_THRESHOLD, MatchCandidate, MatchScore, REVIEW_THRESHOLD,
    Reason, ScoreComponents, score,
};

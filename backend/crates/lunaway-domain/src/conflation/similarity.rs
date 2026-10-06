//! String similarity measures on folded names.

/// The trigram set of a folded string, computed the way PostgreSQL's
/// `pg_trgm` does: each space-separated word is padded with two spaces in
/// front and one behind, and every window of three characters is a trigram.
/// Sorted and deduplicated, so two sets intersect in linear time.
#[must_use]
pub fn trigrams(folded: &str) -> Vec<[char; 3]> {
    let mut out = Vec::new();
    for word in folded.split(' ').filter(|w| !w.is_empty()) {
        let padded: Vec<char> = "  "
            .chars()
            .chain(word.chars())
            .chain(std::iter::once(' '))
            .collect();
        out.extend(padded.windows(3).map(|w| [w[0], w[1], w[2]]));
    }
    out.sort_unstable();
    out.dedup();
    out
}

/// Size of the intersection of two sorted, deduplicated slices.
fn intersection_len<T: Ord>(a: &[T], b: &[T]) -> usize {
    let (mut i, mut j, mut n) = (0, 0, 0);
    while i < a.len() && j < b.len() {
        match a[i].cmp(&b[j]) {
            std::cmp::Ordering::Less => i += 1,
            std::cmp::Ordering::Greater => j += 1,
            std::cmp::Ordering::Equal => {
                n += 1;
                i += 1;
                j += 1;
            }
        }
    }
    n
}

/// Jaccard index of two trigram sets (what `pg_trgm`'s `similarity` returns):
/// shared trigrams over distinct trigrams. 0 when either set is empty.
#[must_use]
pub fn trigram_similarity(a: &[[char; 3]], b: &[[char; 3]]) -> f64 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    let shared = intersection_len(a, b);
    shared as f64 / (a.len() + b.len() - shared) as f64
}

/// Share of the smaller token set found in the larger one: 1 when every word
/// of the shorter name appears in the longer, which is how a name and the
/// same name with an operator's brand in front ("Agis Varennes", "Varennes")
/// compare. Tokens must be sorted and deduplicated. 0 when either is empty.
#[must_use]
pub fn token_containment(a: &[&str], b: &[&str]) -> f64 {
    let smaller = a.len().min(b.len());
    if smaller == 0 {
        return 0.0;
    }
    intersection_len(a, b) as f64 / smaller as f64
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;

    fn sim(a: &str, b: &str) -> f64 {
        trigram_similarity(&trigrams(a), &trigrams(b))
    }

    #[test]
    fn trigrams_follow_pg_trgm() {
        // SELECT show_trgm('cat') => {"  c"," ca","at ","cat"}
        let t: Vec<String> = trigrams("cat").iter().map(|t| t.iter().collect()).collect();
        assert_eq!(t, ["  c", " ca", "at ", "cat"]);
        // SELECT similarity('varennes', 'varenes') => 0.7
        assert!((sim("varennes", "varenes") - 0.7).abs() < 1e-9);
        // SELECT similarity('lac bleu', 'lac') => 0.4444444
        assert!((sim("lac bleu", "lac") - 4.0 / 9.0).abs() < 1e-9);
    }

    #[test]
    fn identical_and_disjoint_names() {
        assert!((sim("lac", "lac") - 1.0).abs() < f64::EPSILON);
        assert!(sim("pins", "mer") < f64::EPSILON);
        assert!(
            sim("", "lac") < f64::EPSILON,
            "an empty name shares nothing"
        );
    }

    #[test]
    fn containment_ignores_a_brand_prefix() {
        assert!((token_containment(&["agis", "varennes"], &["varennes"]) - 1.0).abs() < 1e-12);
        assert!((token_containment(&["lac", "pins"], &["lac", "mer"]) - 0.5).abs() < 1e-12);
        assert!(token_containment(&[], &["lac"]) < f64::EPSILON);
    }

    proptest! {
        #[test]
        fn similarities_are_symmetric_and_bounded(a in "[a-e ]{0,12}", b in "[a-e ]{0,12}") {
            let (ta, tb) = (trigrams(&a), trigrams(&b));
            let s = trigram_similarity(&ta, &tb);
            prop_assert!((0.0..=1.0).contains(&s));
            prop_assert_eq!(s.to_bits(), trigram_similarity(&tb, &ta).to_bits());
            let mut wa: Vec<&str> = a.split(' ').filter(|w| !w.is_empty()).collect();
            let mut wb: Vec<&str> = b.split(' ').filter(|w| !w.is_empty()).collect();
            wa.sort_unstable();
            wa.dedup();
            wb.sort_unstable();
            wb.dedup();
            let c = token_containment(&wa, &wb);
            prop_assert!((0.0..=1.0).contains(&c));
            prop_assert_eq!(c.to_bits(), token_containment(&wb, &wa).to_bits());
            if !ta.is_empty() {
                prop_assert!((trigram_similarity(&ta, &ta) - 1.0).abs() < f64::EPSILON);
            }
        }
    }
}

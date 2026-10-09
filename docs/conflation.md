# Conflation

Several sources describe the same spot; the app shows one place with every
source credited. This page specifies the matching precisely enough to
implement it a second time: the backend scores records in Rust
(`backend/crates/lunaway-domain/src/conflation/`), the app scores overlay
items against synced places in Dart, and both run the shared cases of
`schema/conflation-vectors.json`. Every constant below is in that file's
`parameters`; the Rust test fails when the two disagree.

## 1. Normalisation

**Fold** a string: Unicode compatibility decomposition (NFKD), drop the
combining marks, expand the letters NFKD keeps whole (`ligatures`: `œ` to
`oe`, `ß` to `ss`, `ø` to `o`, ...), lower-case, turn every character that is
neither a letter nor a digit into a space, collapse runs of spaces, trim.
`L'Île-d'Yeu (Port)` folds to `l ile d yeu port`.

**Core words** of a folded name: split on spaces, replace an abbreviation by
its expansion (`st` to `saint`, `ste` to `sainte`), drop the generic words
(`genericWords`: articles and prepositions, and the words that say what kind
of place it is, such as `aire`, `camping`, `car`, `parking`, `municipal`;
French and English, and since the external community source the German,
Spanish and Italian ones, such as `am`, `del`, `di`, `parkplatz`,
`autocaravanas`, `parcheggio`: on synthetic spots named the way visitors
name them in those languages, they raised the share of same-spot pairs
that merge from 0.38 to 0.50, for one merge of two different spots in 280,
which the grouping refused: no place held two spots,
`backend/crates/lunaway-domain/tests/extcom_synthetic.rs`; with the missing
name made neutral (section 2), 0.87, for 9 merges of two different spots,
of which the grouping refused 8: 1 place in 911 held two spots).
The normalised name is the core words joined by spaces; it is empty for a
name made of generic words only ("Camping municipal").

**Phone**: keep the first number of a list (`;`, `,`, `/`), keep the digits
and a leading `+`; `00` becomes `+`; `+330` becomes `+33` (the trunk zero of
"+33 (0)1"); a national number of ten digits starting with 0 is French
(`+33` and the nine digits). Fewer than eight digits identify nothing.

**Website**: first URL of a list, lower case, without scheme, `www.`, query,
fragment and trailing slashes: `host/path`. A host without a dot is nothing;
the bare host of a platform (`platformHosts`: Facebook, Booking, ...) is
nothing, a page on it is something.

**Wikidata**: `Q` and digits, upper-cased.

## 2. The score of a pair

Inputs of a record: source, kind, name, position, `accuracyM` (how far the
real spot may be from the point: half the diagonal of a mapped area, the
precision of a geocoded address, 0 for a point), and optionally an OSM
element, a Wikidata item, a phone, a website, a postcode, a municipality
code.

1. **Distance.** `d` is the haversine distance (Earth radius
   `earthRadiusM`). Each accuracy is clamped to `[0, accuracyCapM]`;
   `dEff = max(0, d - accA - accB)`. The radius `R` is the larger
   `kindRadiusM` of the two kinds. `distance = max(0, 1 - (dEff / R)^2)`:
   flat near the spot, where sources disagree by a few metres for no reason,
   steep towards the radius.
2. **Name.** If either record has no name (or a name that folds to nothing),
   the name is absent: it is reported as `nameUnknown` (0.5) in the
   components and left out of the base, so it counts neither for nor
   against, and distance, kind and shared identifiers decide (two unnamed
   car parks 80 m apart stay distinct: past the car park radius the
   distance is 0). Otherwise compare the
   core words of both, or the full folded names when either core is empty.
   `name = max(trigram, containment)`:
   - `trigram` is PostgreSQL `pg_trgm` similarity: each word padded with two
     spaces before and one after, the set of 3-character windows, then
     shared trigrams over distinct trigrams;
   - `containment` is the number of distinct words both share over the
     number of distinct words of the shorter name, so a brand in front of a
     name ("Agis Varennes" against "Varennes") does not hide it.
3. **Kind.** `kind` is 1 for equal kinds, the value of `kindCompatibility`
   for a listed pair (symmetric), 0 otherwise: a campsite and a car park are
   never one spot.
4. **Municipality.** When both records have a municipality code, 1 if equal
   and 0 if not; otherwise the same with the postcode; otherwise absent.
5. **Base**: the weighted mean of distance (`weights.distance`), name
   (`weights.name`) when both records have one, and, when present,
   municipality
   (`weights.municipality`), divided by the sum of the weights used.
   `score = base * kind`.
6. **Identifiers**, in this order:
   - kind 0: the score stays 0 (reason `incompatible_kinds`);
   - both records name a different OSM element or a different Wikidata item,
     and share none: `score = 0`, distinct (`conflicting_identifier`). The
     OSM element counts only between two sources: every OpenStreetMap
     record names its own element, so a campsite mapped twice (a node and a
     way) must still reach the review queue as a same-source duplicate;
   - they share an OSM element or a Wikidata item and `dEff <=
     globalIdReachM` (300 m, the largest kind radius):
     `score = max(score, globalIdFloor * kind)`. Farther apart the shared
     identifier is ignored: a Wikidata item that names a lake or a town is
     shared by spots kilometres apart, and the server only compares records
     within that reach (section 5);
   - they share a phone or a website and `distance > 0`:
     `score = max(score, localIdFloor * kind)`. A chain shares its phone
     across sites, a town its website across its campsite and its motorhome
     area: the radius and the kind keep those apart.
7. **Decision**: `merge` at `mergeThreshold` and above, `review` from
   `reviewThreshold`, `distinct` below. Two records of the same source never
   merge: a `merge` becomes `review` (reason `same_source`), a duplicate to
   report.

Every component is stored with the decision (`match_pairs.components`), so a
merge can be explained.

## 3. Groups

Records joined by `merge` decisions form one place, by union-find:

- human `must_link` constraints are applied first; one that would join a
  `cannot_link` pair is refused and reported;
- merge edges are applied strongest first; an edge is refused when the
  two groups hold a record of the same source, or a `cannot_link` pair.
  Scores equal to the millionth are a tie, broken by the distance between
  the two points (`distance_m`, before the accuracies are taken off), the
  nearer pair first, then by the name component, the higher first, and
  only then by record id. Both sides of a motorway area are inside the
  accuracy of a pin of the other source, so the score cannot tell which
  side the pin is on; by record id, the two pins of the A7 at
  Saint-Rambert-d'Albon each joined the far side, and at Le
  Pont-de-Montvert the tourist office's area joined a car park 79 m away
  rather than the service area 17 m away (2026-10-07, both scored alike,
  `lunaway-conflate/tests/conflate/extcom.rs`).

The result depends on the input only, never on its order. A record's match
score in its place is the best accepted edge touching it (1 for a
`must_link`).

A merge the score gets wrong is corrected by a human decision on the two
records, kept with its note and applied by every later run:
`lunaway conflate --same <source:id> <source:id> --note TEXT` for a
`must_link`, `--distinct` for a `cannot_link` (records named as
`osm:node/5327741281`). The case that brought it: a DATAtourisme motorhome
area placed by its office in the town centre, 880 m from its spot (240 m of
accuracy, `datatourisme.rs`), merged with an unnamed car park of the
external community source there and gave it its name, while the area
itself, mapped by OpenStreetMap under the same name, stayed a place of its
own: two places of one name in the list (2026-10-09, Donzère).

A group whose records are all placed only at their municipality (an Atout
France campsite the geocoder could not place better, flagged
`position_approximate`) makes no place: its point is the town hall's, a few
kilometres from the campsite, too far for the score to pair it with the
campsite OpenStreetMap maps (195 of 225 such groups had one of a close name
in the same commune on 2026-10-06). Held back, the record still enriches
the place it merges with once a better position or a human merge brings
it close.

## 4. Field values

Each field of a place comes from the record ranked first for that field: by
the trust prior of its source for the field (`trust_prior` in
`resolve.rs`), then the most recent fetch, then the source id and external
id. OpenStreetMap leads on position, vehicle limits (height, length, width,
weight) and opening hours;
Atout France on the classification, the pitches and the postal address; the
community on what visitors know (overnight status, services, prices). The
external community source (`extcom`, a partner's community) ranks just below
Lunaway's own users on what visitors report (overnight status 0.95,
services and prices 0.85, activities 0.8, descriptions 0.75), and low on
what a visitor's phone or a free-text form gets wrong: its position (0.65)
loses to OpenStreetMap's mapped geometry and to Lunaway's reviewed pins, its
vehicle limits (0.5) to the sign OpenStreetMap maps, its kind (0.6) to the
finer taxonomy of the others, its stars (0.2) to Atout France. A pin of
that source carries 20 m of accuracy unless the feed says otherwise
(`docs/feeds.md`). DATAtourisme, the tourist offices' catalogue, leads with
Atout France on the address, the website and the phone (0.8), and ranks
low on the position (0.4): an office places its point by hand, often on the
town's street, so its records carry 240 m of accuracy
(`datatourisme::POSITION_ACCURACY_M`) and a generic name ("Aire de
stationnement pour camping-car") is stored as no name. An unnamed office
area 300 m from a mapped area of the same commune then merges, and goes to
review in the next commune (vectors `datatourisme-*-300m`). The other
sources' differing values stay visible as alternatives (`Place.provenance`).

## 5. On the server

`lunaway conflate` runs incrementally in one transaction under an advisory
lock: the records flagged since the last run (new, changed, gone, or under a
new constraint) are scored against the live records within reach (a GiST
search over `MAX_KIND_RADIUS_M` plus the accuracies, which holds every pair
a kind radius or a shared identifier can merge); the set grows to whole
components (merge edges, `must_link`, shared places), which are grouped
again; each group keeps the place most of its records had; only places whose
content or records changed are written, taking a new position in the change
feed; places left without records become tombstones pointing to the place
that absorbed them. A run with nothing flagged writes nothing, and a full
rebuild (`--full`) lands where the incremental runs did.

The importers take the same advisory lock for each batch they write, so an
import and a conflation never interleave: the conflation locks the flagged
records in id order, an import statement in its own, and the two would
otherwise deadlock. The wait for the lock is bounded at half an hour on its
own, so the import role's statement limit does not cut it short. The scoring, the grouping and the field resolution run
on blocking threads, as pure functions of what was read.

## 6. Opening hours

The device cannot evaluate the OSM `opening_hours` syntax, so each place
carries its open intervals for the 14 days from local midnight of the day of
computation, in UTC (`openingIntervals`), computed with the `opening-hours`
crate: the timezone comes from the place's country (`FR` is
`Europe/Paris`), and from its island for the Canary Islands, the Azores and
Madeira, which keep another time than their mainland; public holidays from
the national calendar of that country, embedded in the crate (regional ones,
as in Alsace-Moselle or a German Land, are not applied); sun events from the
place's position. Only `open` periods count. `openingIntervalsUntil` is
the end of the window the intervals cover: before it a time in no interval is
closed, after it nothing is known (a device that has not synced for two
weeks). Each window starts on the place's own local date and moves at its
next local midnight (`opening_refresh_at`), so a place in Lisbon and one in
Helsinki each begin their day at their own midnight; `conflate` moves the
windows whose midnight has passed, and a place whose intervals or window end
change takes a new position in the change feed.

Hours that are dates without times (`Apr 01-Oct 31`, `Jan 01-Dec 31`,
`24/7`, a list of such periods) are a season instead
(`lunaway_domain::season`, `places.opening_season`, `Place.openingSeason`):
the days of a leap year the place is open, one or two ranges, without
intervals or window. Whether it is open on a day follows from the dates
alone, so nothing moves at midnight: a window that did would give every
such place a new position in the change feed each day, and the external
community source alone says "open all year" of tens of thousands of
places. A place stored with intervals before it had a season loses them at
its next refresh, once; an app older than the season then shows its hours
without the line that says open or closed. A season is read again only
when the place's hours change: a parser that comes to read more forms
needs a pass over the places it now reads. The points of interest keep their intervals
whatever their hours: a fuel station open `24/7` answers "open now" from
them.

Two bounds keep a broken or hostile value cheap: an expression longer than
the 255 characters OSM allows is not evaluated (`openingHoursParsed` false),
and at most 256 intervals are kept, the window then ending where the first
one left out starts.

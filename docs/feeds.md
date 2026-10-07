# Partner feeds

The format a partner's data arrives in, and what Lunaway does with it. One
feed exists today: the external community source (source id `extcom`), a
community platform of motorhome spots whose places, reviews and photos
Lunaway receives under a written agreement. In the product it is named
"Source communautaire externe" (English: "External community source"),
the wording of the agreement; it is never presented as an endorsement of
Lunaway or an affiliation with it. The partner's name appears nowhere in
this repository (a denylist hook refuses it).

The importer is `lunaway ingest extcom --file <path|url>`
(`backend/crates/lunaway-ingest/src/extcom.rs`); the rules that check what
the feed says are in `backend/crates/lunaway-domain/src/extcom.rs`.

## The file

- UTF-8 JSON Lines: one JSON object per line, lines separated by `\n`
  (a `\r\n` is accepted). Blank lines are ignored.
- Compressed or not: a file starting with the gzip magic bytes is read as
  gzip (one member or several concatenated).
- A file on the server, or an `https` URL the partner gives for its
  export (downloaded once into the cache, at most 8 GiB; `--refresh`
  downloads it again).
- Bounds, checked while reading: a line holds at most 1 MiB once
  inflated (a longer line is skipped and counted); a feed holds at most
  2 000 000 places (past it the import stops and retires nothing); a place
  keeps its 200 newest reviews and its first 30 photos.
- Line 1 is the header. Every other line is a place.

## The header

```json
{
  "type": "header",
  "format": "lunaway-extcom-1",
  "generated_at": "2026-10-07T03:00:00Z",
  "complete": true,
  "agreement": {
    "reference": "AGREEMENT-REFERENCE",
    "grantor": "the partner's legal name",
    "grantee": "Lunaway",
    "signed_on": "2026-10-07",
    "valid_until": null,
    "scope": ["places", "reviews", "photos"],
    "attribution": "the attribution text the agreement words",
    "licence_url": null
  }
}
```

| field | required | meaning |
|---|---|---|
| `type` | yes | `"header"` |
| `format` | yes | exactly `"lunaway-extcom-1"`; any other value refuses the feed |
| `generated_at` | yes | when the partner produced the file (RFC 3339) |
| `complete` | no, default `true` | `true`: the file lists every live item, and an item absent from it is deleted on Lunaway's side. `false`: a delta, which lists only what changed; nothing absent is deleted, a deletion is a line marked `"deleted": true` |
| `agreement.reference` | yes | the agreement's reference: 1 to 64 characters, letters, digits and `._/-`, starting with a letter or a digit. It must equal the reference the server is configured with (below); a feed naming another is refused |
| `agreement.grantor` | yes | who granted the rights (one line, at most 200 characters) |
| `agreement.grantee` | yes | who received them |
| `agreement.signed_on` | yes | the day it was signed (`YYYY-MM-DD`); a date after the day of the import refuses the feed |
| `agreement.valid_until` | no | its last day; a date before the day of the import refuses the feed |
| `agreement.scope` | yes | what it covers, among `places`, `reviews`, `photos`; reviews or photos outside the scope are not stored |
| `agreement.attribution` | yes | the text shown with the data, at most 300 characters |
| `agreement.licence_url` | no | an `https` URL of public terms, if any |

A feed without a header, without an agreement, with an agreement missing a
required field, or with one not in force on the day of the import is
refused before anything is stored. Other fields of the header are ignored.

## Server configuration

Set at deploy time, never in the repository:

| variable | meaning |
|---|---|
| `LUNAWAY_EXTCOM_AGREEMENT_REF` | the reference of the signed agreement. The importer refuses to run without it, and refuses a feed whose header names another. It is the reference stored on every record, review, rating and photo (their licence) |
| `LUNAWAY_EXTCOM_PHOTO_HOSTS` | the host names photos may be downloaded from, comma separated (`img.example.org,cdn.example.org`): DNS names of two labels or more, no IP address. A photo URL on another host is dropped at import, and refused again by the photo proxy |

The hosts come from the server's configuration and not from the feed: the
feed is untrusted, and must not be able to widen where the server
downloads from.

## A place

```json
{
  "type": "place",
  "id": "123456",
  "kind": "parking",
  "name": "Parking du lac",
  "descriptions": {"fr": "Calme la nuit, eau au cimetière.", "de": "Ruhig."},
  "lat": 45.8992,
  "lon": 6.1294,
  "accuracy_m": 15,
  "address": {"street": "Rue du Port", "postcode": "74000", "city": "Annecy", "country_code": "FR"},
  "services": ["drinking_water", "waste_bin"],
  "activities": ["swimming", "hiking"],
  "prices": {"parking": {"amount": 0, "currency": "EUR"}, "services": {"amount": 2, "currency": "EUR"}},
  "limits": {"max_height_m": 2.5, "max_length_m": 8},
  "opening": {"periods": [{"from": "04-01", "to": "10-31"}]},
  "overnight": {"status": "tolerated", "reports_allowed": 14, "reports_forbidden": 1},
  "rating": {"average": 4.2, "count": 87},
  "reviews": [
    {"id": "r-998", "author_id": "u-42", "author": "Marie", "date": "2026-08-14",
     "lang": "fr", "rating": 4, "text": "Très calme.", "vehicle": "campervan"}
  ],
  "photos": [
    {"id": "p-77", "url": "https://img.example.org/p-77.jpg", "author_id": "u-42",
     "author": "Marie", "licence": null, "taken_at": "2026-08-14"}
  ],
  "website": "https://example.org",
  "phone": "+33 4 50 00 00 00",
  "created_at": "2019-05-02T10:00:00Z",
  "updated_at": "2026-08-15T07:12:00Z"
}
```

| field | required | meaning |
|---|---|---|
| `type` | yes | `"place"` |
| `id` | yes | the partner's id of the spot, stable across feeds: 1 to 128 bytes, no space nor control character. A second line with an id already seen is dropped |
| `deleted` | no | `true`: the spot is gone. The line needs nothing but `type` and `id`; the spot is removed with its reviews and photos, whether the feed is complete or not |
| `kind` | yes | a code of the kinds table below; a code the table does not know drops the line and is reported |
| `name` | no | one line, at most 200 characters |
| `descriptions` | no | by BCP 47 language tag (`fr`, `de`, `es`, `it`, `pt-BR`); a key that is not a language tag is filed as `und`. At most 12 languages, 8000 characters each |
| `lat`, `lon` | yes | WGS 84 degrees; `0, 0` and positions off the Earth drop the line |
| `accuracy_m` | no | how far the spot may be from the point, metres; 20 when absent (a pin dropped by a visitor), at most 200 |
| `address` | no | `country_code` is ISO 3166-1 alpha-2 |
| `services` | no | codes of the services table |
| `activities` | no | codes of the activities table |
| `prices` | no | euros only (`currency` `EUR`), 0 to 500; `0` means free. Another currency is dropped |
| `limits` | no | maximum vehicle height (1.5 to 6 m) and length (3 to 30 m); a value outside is dropped |
| `opening` | no | seasonal periods `MM-DD` to `MM-DD`, at most 12; a period may cross the new year |
| `overnight.status` | no | `allowed`, `tolerated`, `day_only`, `forbidden`, `unknown` |
| `overnight.reports_allowed`, `reports_forbidden` | no | visitors' reports; used when `status` is absent or `unknown`: two or more reports one way, outnumbering the other, decide |
| `rating` | no | the partner's summary of all its ratings of the spot: `average` 1 to 5, `count` above 0 |
| `reviews` | no | the spot's reviews (below), complete for the spot: a review of the spot absent from the line is deleted |
| `photos` | no | the spot's photos (below), complete for the spot: a photo absent from the line is removed |
| `website`, `phone` | no | a web link (`http` or `https`) and a phone number |
| `created_at`, `updated_at` | no | kept in the stored payload, for audit |

Any other field is kept in the stored payload and not used. The reviews and
photos are not kept in the payload: they have their own tables, each row
with its provenance.

### A review

| field | required | meaning |
|---|---|---|
| `id` | yes | the partner's id of the review, unique in the feed |
| `author_id` | no | the partner's id of the author: never shown, used for erasure requests (below) |
| `author` | no | the pseudonym shown beside the review, one line of at most 64 characters; a value that looks like an e-mail address is dropped |
| `date` | yes | when it was written: `YYYY-MM-DD` or RFC 3339 |
| `lang` | no | BCP 47 tag of the text |
| `rating` | no | 1 to 5; a half star rounds up |
| `text` | no | at most 4000 characters once reduced to plain text |
| `vehicle` | no | `van`, `campervan`, `motorhome`, `caravan`, `other` (`car` and `tent` read as `other`) |
| `deleted` | no | `true`: the review is gone (as if absent) |

A review needs a rating or a text. Texts are reduced to plain text: HTML
tags are dropped (a paragraph or a line break becomes a line break), the
common entities decoded, control characters and the characters that
reorder or hide text dropped, spaces collapsed.

### A photo

| field | required | meaning |
|---|---|---|
| `id` | yes | the partner's id of the photo |
| `url` | yes | `https`, on a host of `LUNAWAY_EXTCOM_PHOTO_HOSTS`, port 443, no user information, at most 2048 bytes |
| `author_id` | no | the partner's id of the author, for erasure requests |
| `author` | no | the pseudonym shown with the photo |
| `licence` | no | the photo's own licence when it has one; the agreement's reference otherwise |
| `taken_at` | no | `YYYY-MM-DD` or RFC 3339 |
| `deleted` | no | `true`: the photo is gone (as if absent) |

A photo whose URL changes is a new picture: the old one is removed and the
new one downloaded when first viewed.

## Mapping tables

The tables are in `lunaway-ingest/src/extcom.rs` (`KINDS`, `SERVICES`,
`ACTIVITIES`, `VEHICLES`, `OVERNIGHT`); every code of the taxonomy maps to
itself, so a feed may always use Lunaway's own codes. A code the tables do
not know is reported by the import (`codes no table maps`) and dropped,
never guessed; the partner's categories are mapped by adding rows.

| feed `kind` | Lunaway kind |
|---|---|
| `motorhome_area`, `motorhome_area_free`, `motorhome_area_paid` | motorhome area |
| `service_area` | service area |
| `campsite` | campsite |
| `parking`, `parking_day_night` | car park |
| `parking_day_only` | car park, overnight status "day only" unless the line says otherwise |
| `rest_area` | rest area |
| `picnic_area` | picnic area |
| `nature`, `wild_spot` | spot in nature |
| `off_road` | off-road spot |
| `farm`, `winery` | farm |
| `homestay`, `private_host` | private host |
| `extra_service`, `laundry`, `lpg_station`, `vehicle_wash` | other useful stop |
| `restaurant`, `shop`, `hotel`, `other` | not a place to stop: the line is dropped |

| feed service | Lunaway services |
|---|---|
| each code of the taxonomy (`drinking_water`, `grey_water`, `black_water`, `waste_bin`, `toilets`, `showers`, `electricity`, `wifi`, `laundry`, `lpg`, `gas_bottles`, `vehicle_wash`, `bakery`, `swimming_pool`, `pets_allowed`, `mobile_data`, `winter_caravanning`) | itself |
| `water` | drinking water |
| `dump_station` | grey water and black water |
| `disabled_access`, `restaurant`, `shop` | none (dropped on purpose) |

| feed activity | Lunaway activity |
|---|---|
| each code of the taxonomy (`monuments`, `windsurf_kitesurf`, `mountain_biking`, `hiking`, `climbing`, `canoe_kayak`, `fishing`, `shore_fishing`, `swimming`, `motorcycling`, `viewpoint`, `playground`) | itself |
| `skiing` | none (dropped on purpose) |

## What the import does

- **Refusals first.** No `LUNAWAY_EXTCOM_AGREEMENT_REF`, a header naming
  another reference, an agreement not in force, a source hidden or purged
  (below): nothing is stored.
- **Records.** Each place becomes a record of the `extcom` source in
  `source_records`, its licence column set to the agreement's reference,
  its payload the line without its reviews and photos.
- **Incremental.** A record, review, rating or photo is written only when
  what the feed says of it changed: a feed read twice writes nothing the
  second time.
- **Resumable.** The number of lines stored is kept in the cache after
  each batch of 500 places, under the feed's SHA-256; a run stopped half
  way, run again on the same file, resumes after the last batch stored.
- **Deletions.** The agreement makes Lunaway a separate controller of the
  data and asks it to pass erasures on. A complete feed removes every spot
  it does not list, unless it lists less than half of the spots stored (a
  truncated file: nothing is removed and the import fails, for a person to
  look). A line marked `"deleted": true` removes its spot in any feed. A
  removed spot's record is emptied (no name, no position, no payload), its
  reviews and rating deleted, its photos retired. A review or photo absent
  from its spot's line, or marked deleted, is deleted or retired. Retired
  photos are never served again; their files are removed by
  `lunaway extcom purge-media --yes`, run with the API's role after each
  import.
- **Merging.** The records then go through the conflation like any
  source's (`docs/conflation.md`): a spot of the feed and the same spot in
  OpenStreetMap become one place, each field taken from the source trusted
  most for it.

## Erasure of one author

`lunaway extcom erase-author <author-id> [--yes]` (import role), for an
erasure request the partner forwards: deletes every review and retires
every photo whose `author_id` is that id, and keeps the SHA-256 of the id
(never the id itself) so that later feeds do not bring them back while
the partner propagates the erasure. Then `purge-media --yes` removes the
files.

## What the product shows

- Each place lists its sources (`Place.sources`): the `extcom` one as
  "Source communautaire externe", with the licence (the agreement's
  reference) and the attribution of the agreement.
- A place's card reads, when it opens, the partner's reviews
  (`Place.externalReviews`), its rating summary (`Place.externalRatings`)
  and its photos (`Place.externalPhotos`), each with the author's
  pseudonym and the source's label. None of them is in the change feed,
  in a region pack or in a map tile.
- A photo is downloaded from the partner the first time a device asks for
  it, through the API's photo proxy (`GET /external-photos/{id}/thumb` or
  `/large`): checked against the configured hosts and redirects included,
  resolved to public addresses only, at most 10 MB, then re-encoded
  without its metadata and resized like an upload, stored under the media
  root, and served from Lunaway's host. A failed download waits an hour
  before the next try, doubling up to a week.

## Switches

For the day the agreement ends or is suspended:

| command | role | effect |
|---|---|---|
| `lunaway extcom hide [--note TEXT]` | import | the API stops serving the source's reviews, ratings, photos and its entry in a place's sources at once; the conflation worker, woken, takes its records off every place, and the change feed hands the places so changed to every device. Nothing is deleted. The importer refuses to run while the source is hidden |
| `lunaway extcom show [--note TEXT]` | import | undoes `hide` |
| `lunaway extcom purge --yes [--note TEXT]` | import | hides the source, empties and retires all its records, deletes its reviews and ratings, retires its photos (URL and author forgotten) |
| `lunaway extcom purge-media --yes` | API, as the API's user | removes the files of the retired photos no other photo uses, then their rows |
| `lunaway extcom status` | import | the switch and the counts |

The switch is a row of `source_switches`, read by the API on every request
and by the conflation: it takes effect without a restart or a release. The
region packs are built again after a purge, so a new device gets none of
it.

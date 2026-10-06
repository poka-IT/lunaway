# /// script
# requires-python = ">=3.11"
# dependencies = ["shapely==2.1.2", "pyproj==3.7.2"]
# ///
"""Builds the outlines of the offline basemap packs, infra/tiles/packs/regions.geojson.

    uv run infra/tiles/packs/regions.py

Run on a workstation, never on a server: the output is committed and the
backend's pack job (lunaway-tiles-packs) only reads it. Two open sources,
pinned by SHA-256 and cached under data/tmp/packs/:

- the French regions: "Contours administratifs" of data.gouv.fr (dataset
  683424e996857155175d4f68), regions 2025 simplified to 100 m, built from
  IGN Admin Express and OpenStreetMap, ODbL;
- the countries: Natural Earth 1:10m admin 0 countries, release v5.1.2,
  public domain.

Each outline is filled (an enclave such as San Marino falls inside Italy),
widened by a margin so a pack covers its coast, its islands near the shore
and the roads that cross the border, then simplified, in an azimuthal
equidistant projection centred on the region, so the margin is in metres
anywhere on Earth. Natural Earth draws coasts at 1:10 million, hence a wider
margin for the countries than for the French regions, drawn at 100 m.
"""

import hashlib
import json
import os
import sys
import urllib.request
import gzip

from pyproj import Transformer
from shapely import make_valid
from shapely.geometry import MultiPolygon, Polygon, mapping, shape
from shapely.ops import transform, unary_union

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(REPO, "data", "tmp", "packs")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "regions.geojson")
USER_AGENT = "Lunaway infra (+https://lunaway.net)"

FR_REGIONS = {
    "url": "https://object.data.gouv.fr/contours-administratifs/2025/geojson/regions-100m.geojson.gz",
    "sha256": "396b35422d1f10332b85bb07f7747baf7e86e79b7175070fc03431e34114924c",
    "file": "regions-100m.geojson.gz",
    "source": "Contours administratifs 2025, data.gouv.fr (IGN Admin Express, OpenStreetMap), ODbL",
}
COUNTRIES = {
    "url": "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_0_countries.geojson",
    "sha256": "239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255",
    "file": "ne_10m_admin_0_countries.geojson",
    "source": "Natural Earth 1:10m admin 0 countries v5.1.2, public domain",
}

# Margins and simplification, in metres.
FR_MARGIN = 3000
COUNTRY_MARGIN = 8000
SIMPLIFY = 500

# French regions: INSEE code of the source, pack id (ISO 3166-2, lower case),
# names. The overseas collectivities (codes 975 and above) are not regions.
FR = [
    ("84", "fr-ara", "Auvergne-Rhône-Alpes", "Auvergne-Rhône-Alpes"),
    ("27", "fr-bfc", "Bourgogne-Franche-Comté", "Bourgogne-Franche-Comté"),
    ("53", "fr-bre", "Bretagne", "Brittany"),
    ("24", "fr-cvl", "Centre-Val de Loire", "Centre-Val de Loire"),
    ("94", "fr-20r", "Corse", "Corsica"),
    ("44", "fr-ges", "Grand Est", "Grand Est"),
    ("32", "fr-hdf", "Hauts-de-France", "Hauts-de-France"),
    ("11", "fr-idf", "Île-de-France", "Île-de-France"),
    ("28", "fr-nor", "Normandie", "Normandy"),
    ("75", "fr-naq", "Nouvelle-Aquitaine", "Nouvelle-Aquitaine"),
    ("76", "fr-occ", "Occitanie", "Occitania"),
    ("52", "fr-pdl", "Pays de la Loire", "Pays de la Loire"),
    ("93", "fr-pac", "Provence-Alpes-Côte d'Azur", "Provence-Alpes-Côte d'Azur"),
    ("01", "fr-971", "Guadeloupe", "Guadeloupe"),
    ("02", "fr-972", "Martinique", "Martinique"),
    ("03", "fr-973", "Guyane", "French Guiana"),
    ("04", "fr-974", "La Réunion", "Réunion"),
    ("06", "fr-976", "Mayotte", "Mayotte"),
]

# Countries: Natural Earth ADM0_A3, pack id (ISO 3166-1 alpha-2, lower case),
# names. Andorra is not in the brief's list; motorhomes cross it often and
# the margins of Spain and Occitanie do not cover it.
COUNTRY_LIST = [
    ("ESP", "es", "Espagne", "Spain"),
    ("PRT", "pt", "Portugal", "Portugal"),
    ("ITA", "it", "Italie", "Italy"),
    ("DEU", "de", "Allemagne", "Germany"),
    ("AUT", "at", "Autriche", "Austria"),
    ("CHE", "ch", "Suisse", "Switzerland"),
    ("BEL", "be", "Belgique", "Belgium"),
    ("NLD", "nl", "Pays-Bas", "Netherlands"),
    ("LUX", "lu", "Luxembourg", "Luxembourg"),
    ("GBR", "gb", "Royaume-Uni", "United Kingdom"),
    ("IRL", "ie", "Irlande", "Ireland"),
    ("DNK", "dk", "Danemark", "Denmark"),
    ("NOR", "no", "Norvège", "Norway"),
    ("SWE", "se", "Suède", "Sweden"),
    ("FIN", "fi", "Finlande", "Finland"),
    ("HRV", "hr", "Croatie", "Croatia"),
    ("SVN", "si", "Slovénie", "Slovenia"),
    ("GRC", "gr", "Grèce", "Greece"),
    ("POL", "pl", "Pologne", "Poland"),
    ("CZE", "cz", "Tchéquie", "Czechia"),
    ("AND", "ad", "Andorre", "Andorra"),
]

# A country's parts outside this box are left out: Svalbard and Bouvet
# Island (Norway), the Caribbean Netherlands. The Canary Islands, Madeira and
# the Azores stay. Two roadless islets inside it would stretch a pack's
# bounding box over the ocean: Jan Mayen (Norway) and Rockall (United
# Kingdom).
EUROPE = (-32.0, 27.0, 45.0, 72.0)
LEFT_OUT = [(-10.0, 70.0, -7.0, 72.0), (-14.5, 57.0, -13.0, 58.0)]


def fetch(src):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, src["file"])
    if not os.path.exists(path):
        req = urllib.request.Request(src["url"], headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=120) as r, open(path + ".part", "wb") as f:
            f.write(r.read())
        os.replace(path + ".part", path)
    with open(path, "rb") as f:
        data = f.read()
    got = hashlib.sha256(data).hexdigest()
    if got != src["sha256"]:
        sys.exit(f"{src['file']} hashes to {got}, the pin says {src['sha256']}")
    if path.endswith(".gz"):
        data = gzip.decompress(data)
    return json.loads(data)


def parts(geom):
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return list(geom.geoms)
    return [g for g in getattr(geom, "geoms", []) if isinstance(g, (Polygon, MultiPolygon))]


def in_box(poly, box):
    x, y = poly.representative_point().coords[0]
    return box[0] <= x <= box[2] and box[1] <= y <= box[3]


def outline(geom, margin):
    """Fills, widens and simplifies geom; returns WGS84 geometry."""
    lon, lat = geom.centroid.coords[0]
    aeqd = f"+proj=aeqd +lat_0={lat:.4f} +lon_0={lon:.4f} +datum=WGS84 +units=m"
    fwd = Transformer.from_crs("EPSG:4326", aeqd, always_xy=True).transform
    back = Transformer.from_crs(aeqd, "EPSG:4326", always_xy=True).transform
    # The sources hold a few self-touching rings: each filled part is
    # repaired before the union.
    filled = unary_union([make_valid(Polygon(p.exterior)) for p in parts(make_valid(geom))])
    wide = transform(fwd, filled).buffer(margin, quad_segs=4)
    wide = unary_union([Polygon(p.exterior) for p in parts(wide)])
    simple = make_valid(wide.simplify(SIMPLIFY, preserve_topology=True))
    out = transform(back, simple)
    return unary_union([Polygon(p.exterior) for p in parts(out)])


def rounded(geom):
    """GeoJSON geometry with 4 decimals (about 11 m) and exteriors only."""
    polys = []
    for p in parts(geom):
        ring = [[round(x, 4), round(y, 4)] for x, y in p.exterior.coords]
        polys.append([ring])
    if len(polys) == 1:
        return {"type": "Polygon", "coordinates": polys[0]}
    return {"type": "MultiPolygon", "coordinates": polys}


def bbox(g):
    xs, ys = [], []
    for poly in (g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]):
        for x, y in poly[0]:
            xs.append(x)
            ys.append(y)
    return [min(xs), min(ys), max(xs), max(ys)]


def main():
    features = []
    fr = {f["properties"]["code"]: f for f in fetch(FR_REGIONS)["features"]}
    for code, rid, name_fr, name_en in FR:
        geom = outline(shape(fr[code]["geometry"]), FR_MARGIN)
        features.append((rid, name_fr, name_en, "region", "fr", geom, FR_REGIONS["source"], FR_MARGIN))
    ne = {f["properties"]["ADM0_A3"]: f for f in fetch(COUNTRIES)["features"]}
    for a3, rid, name_fr, name_en in COUNTRY_LIST:
        kept = [
            p for p in parts(shape(ne[a3]["geometry"]))
            if in_box(p, EUROPE) and not any(in_box(p, box) for box in LEFT_OUT)
        ]
        geom = outline(unary_union(kept), COUNTRY_MARGIN)
        features.append((rid, name_fr, name_en, "country", rid, geom, COUNTRIES["source"], COUNTRY_MARGIN))

    out = {"type": "FeatureCollection", "features": []}
    vertices = 0
    for rid, name_fr, name_en, kind, country, geom, source, margin in features:
        g = rounded(geom)
        n = sum(len(p[0]) for p in (g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]))
        vertices += n
        out["features"].append({
            "type": "Feature",
            "properties": {
                "id": rid,
                "name_fr": name_fr,
                "name_en": name_en,
                "kind": kind,
                "country": country,
                "bbox": bbox(g),
                "margin_m": margin,
                "source": source,
            },
            "geometry": g,
        })
        print(f"{rid:7} {kind:7} {n:5} vertices  {name_en}")
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{len(features)} regions, {vertices} vertices, {os.path.getsize(OUT)} bytes: {OUT}")


if __name__ == "__main__":
    main()

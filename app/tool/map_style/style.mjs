// Builds the Lunaway basemap styles, Aube (light) and Minuit (dark), from
// @protomaps/basemaps. Upstream supplies the layer structure and the label
// expressions (local names, scripts, the reader's language); this file
// recolours them from the brand palette and reworks what upstream does not
// fit to: a road hierarchy readable from a motorhome cab, quiet minor roads
// and tracks, no points of interest that would compete with the app's pins,
// and town and village names that come first.
//
// generate.mjs writes the results to the app's assets; preview/render.mjs
// also imports stockStyle() to compare against upstream.
import { layers, namedFlavor } from "@protomaps/basemaps";

/** The placeholders the app replaces in the JSON text before use. */
export const PLACEHOLDERS = {
  tiles: "__LUNAWAY_TILES__",
  glyphs: "__LUNAWAY_GLYPHS__",
  sprite: "__LUNAWAY_SPRITE__",
  lang: "__LUNAWAY_LANG__",
};

/**
 * Label languages the styles are checked against (see generate.mjs): the
 * app's own, `basemapLanguages` in app/lib/features/map/domain/basemap_style.dart.
 */
export const LANGUAGES = ["fr", "en", "de", "es", "it", "nl"];

/** The languages of the copies served under /styles/ for the website. */
export const DEPLOYED_LANGUAGES = ["fr", "en"];

const SOURCE = "protomaps";

// The OpenStreetMap link points at www.openstreetmap.org, a host the app
// already allows, rather than upstream's osm.org.
const ATTRIBUTION =
  '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';

// Brand colours (brand/README.md). Amber and coral are the app's own
// accents, for the selection and for alerts, and never appear below.
const NAVY = "#061F43";
const CREAM = "#FDF1DB";

/**
 * The two palettes. Every value is derived from the brand: Aube from the
 * cream, a shade darker than the app's surfaces so sheets stand off the
 * map, with teal water and sage greens; Minuit from the navy, with deep
 * teal water and a greener navy for woods. Roads carry the hierarchy in
 * tone and width only: neutral fills, with the motorway set apart by a
 * slate tint and a darker casing.
 */
const PALETTES = {
  aube: {
    sheet: "light",
    land: "#F3EAD9",
    landLow: { farmland: "#EFE7D3", grassland: "#E8E6CD", forest: "#DCE2C6", scrub: "#E4E4CB", barren: "#F0E6D3", glacier: "#FAF6EE", urban: "#E9DDC9" },
    urban: "#EDE2CF",
    industrial: "#EBE1D2",
    hospital: "#F0E3D8",
    school: "#EFE4D3",
    pedestrian: "#F7F0E3",
    park: "#DCE4C7",
    wood: "#D3DDBE",
    scrub: "#E1E5CA",
    glacier: "#FAF7F0",
    sand: "#F0E5CC",
    beach: "#F2E7CC",
    military: "#ECE3D3",
    aerodrome: "#ECE4D5",
    runway: "#E1D8C7",
    water: "#AED6D8",
    waterLabel: "#2F6E78",
    waterLabelHalo: "#C4E2E3",
    buildings: "#E4D7C3",
    buildingsOutline: "#D8C8B1",
    pier: "#EDE5D7",
    rail: "#A79C8A",
    boundaryCountry: "rgba(6, 31, 67, 0.38)",
    boundaryRegion: "rgba(6, 31, 67, 0.2)",

    motorway: { low: "#97A3BB", fill: "#D6DEEA", casing: "#7F8DA8" },
    trunk: { low: "#B3A58B", fill: "#FFFFFF", casing: "#C2B194" },
    secondary: { low: "#C4B8A1", fill: "#FFFFFF", casing: "#D0C3AA" },
    tertiary: { low: "#D1C6B1", fill: "#FFFDF8", casing: "#D8CDB7" },
    minor: { low: "#E7DCC8", fill: "#FFFDF8", casing: "#DED2BD" },
    service: { fill: "#FBF6EC", casing: "#E2D7C4" },
    track: "#B5A283",
    path: "#C9B99F",
    tunnel: { fill: "#F2ECE2", casing: "#D5CAB8" },

    roadLabel: "#4D5870",
    roadLabelMinor: "#6E7484",
    roadLabelHalo: "#FBF6EC",
    shieldText: NAVY,
    place: NAVY,
    placeMinor: "#4A5973",
    placeSub: "#6F7A8C",
    placeHalo: "#F8F1E4",
    region: "#7D8698",
    country: "#55627A",
    island: "#5E6B80",
  },
  minuit: {
    sheet: "dark",
    land: "#0A1C36",
    landLow: { farmland: "#0B1E38", grassland: "#0C2236", forest: "#0D2636", scrub: "#0C2336", barren: "#0D1F39", glacier: "#1A2D49", urban: "#10233F" },
    urban: "#0D213D",
    industrial: "#0E213D",
    hospital: "#0F213D",
    school: "#0E213C",
    pedestrian: "#102440",
    park: "#11303D",
    wood: "#0D2837",
    scrub: "#0E2537",
    glacier: "#18304A",
    sand: "#132640",
    beach: "#142842",
    military: "#0E203B",
    aerodrome: "#0E213D",
    runway: "#1A2E4D",
    water: "#104059",
    waterLabel: "#79B8BE",
    waterLabelHalo: "#104059",
    buildings: "#132A49",
    buildingsOutline: "#18325A",
    pier: "#11253F",
    rail: "#3E5272",
    boundaryCountry: "rgba(253, 241, 219, 0.32)",
    boundaryRegion: "rgba(253, 241, 219, 0.16)",

    motorway: { low: "#6C84AA", fill: "#6A84AD", casing: "#04122A" },
    trunk: { low: "#3D5274", fill: "#3B5175", casing: "#04122A" },
    secondary: { low: "#2E4364", fill: "#304668", casing: "#05142C" },
    tertiary: { low: "#2A3F60", fill: "#283D5E", casing: "#06152D" },
    minor: { low: "#1C2F4D", fill: "#22375A", casing: "#07162E" },
    service: { fill: "#1D3152", casing: "#07162E" },
    track: "#3C5070",
    path: "#33476A",
    tunnel: { fill: "#152945", casing: "#0A1B33" },

    roadLabel: "#C9C6BC",
    roadLabelMinor: "#A3A59F",
    roadLabelHalo: "#0A1C36",
    shieldText: "#E9E2D4",
    place: CREAM,
    placeMinor: "#D2CCC0",
    placeSub: "#A7AEB8",
    placeHalo: NAVY,
    region: "#8B95A6",
    country: "#B9BDC4",
    island: "#AEB5BE",
  },
};

/**
 * Upstream's flavor keys, filled from a palette; the patches below refine
 * them. The flavor has no `pois` entry, so upstream builds no layer of
 * points of interest: the app draws its own pins (campsites, car parks,
 * services, nature) and the basemap's shops, cafes and campsites would
 * compete with them.
 */
function flavor(p) {
  return {
    background: p.land,
    earth: p.land,
    park_a: p.park,
    park_b: p.park,
    hospital: p.hospital,
    industrial: p.industrial,
    school: p.school,
    wood_a: p.wood,
    wood_b: p.wood,
    pedestrian: p.pedestrian,
    scrub_a: p.scrub,
    scrub_b: p.scrub,
    glacier: p.glacier,
    sand: p.sand,
    beach: p.beach,
    aerodrome: p.aerodrome,
    runway: p.runway,
    water: p.water,
    zoo: p.military,
    military: p.military,

    tunnel_other_casing: p.tunnel.casing,
    tunnel_minor_casing: p.tunnel.casing,
    tunnel_link_casing: p.tunnel.casing,
    tunnel_major_casing: p.tunnel.casing,
    tunnel_highway_casing: p.tunnel.casing,
    tunnel_other: p.tunnel.fill,
    tunnel_minor: p.tunnel.fill,
    tunnel_link: p.tunnel.fill,
    tunnel_major: p.tunnel.fill,
    tunnel_highway: p.tunnel.fill,

    pier: p.pier,
    buildings: p.buildings,

    minor_service_casing: p.service.casing,
    minor_casing: p.minor.casing,
    link_casing: p.trunk.casing,
    major_casing_late: p.trunk.casing,
    highway_casing_late: p.motorway.casing,
    other: p.path,
    minor_service: p.service.fill,
    minor_a: p.minor.fill,
    minor_b: p.minor.fill,
    link: p.trunk.fill,
    major_casing_early: p.trunk.casing,
    major: p.trunk.fill,
    highway_casing_early: p.motorway.casing,
    highway: p.motorway.fill,

    railway: p.rail,
    boundaries: p.boundaryRegion,

    bridges_other_casing: p.service.casing,
    bridges_minor_casing: p.minor.casing,
    bridges_link_casing: p.trunk.casing,
    bridges_major_casing: p.trunk.casing,
    bridges_highway_casing: p.motorway.casing,
    bridges_other: p.path,
    bridges_minor: p.minor.fill,
    bridges_link: p.trunk.fill,
    bridges_major: p.trunk.fill,
    bridges_highway: p.motorway.fill,

    roads_label_minor: p.roadLabelMinor,
    roads_label_minor_halo: p.roadLabelHalo,
    roads_label_major: p.roadLabel,
    roads_label_major_halo: p.roadLabelHalo,
    ocean_label: p.waterLabel,
    subplace_label: p.placeSub,
    subplace_label_halo: p.placeHalo,
    city_label: p.place,
    city_label_halo: p.placeHalo,
    state_label: p.region,
    state_label_halo: p.placeHalo,
    country_label: p.country,

    address_label: p.roadLabelMinor,
    address_label_halo: p.roadLabelHalo,

    landcover: {
      grassland: p.landLow.grassland,
      barren: p.landLow.barren,
      urban_area: p.landLow.urban,
      farmland: p.landLow.farmland,
      glacier: p.landLow.glacier,
      scrub: p.landLow.scrub,
      forest: p.landLow.forest,
    },
  };
}

// Widths in pixels at a fixed set of zooms, interpolated exponentially like
// upstream. Major roads share one set of stops so a single expression can
// pick the class with a match on kind_detail.
const STOPS = [5, 6, 8, 10, 12, 15, 18];
const WIDTH = {
  motorway: [0.6, 0.9, 1.6, 2.4, 3.4, 7.5, 21],
  trunk: [0, 0.6, 1.2, 1.8, 2.8, 6.2, 18],
  secondary: [0, 0, 0.6, 1.2, 2.1, 5.2, 15.5],
  tertiary: [0, 0, 0, 0.6, 1.5, 4.4, 13.5],
  minor: [0, 0, 0, 0, 0.6, 2.9, 11],
  service: [0, 0, 0, 0, 0, 1.3, 7],
  link: [0, 0, 0, 0, 0.9, 2.6, 9],
};

const TRUNK_DETAILS = ["trunk", "primary"];
const SECONDARY_DETAILS = ["secondary"];

function widthOf(name) {
  return ["interpolate", ["exponential", 1.6], ["zoom"], ...STOPS.flatMap((z, i) => [z, WIDTH[name][i]])];
}

/** Width of a major road, by class: trunk and primary, secondary, tertiary. */
function majorWidth() {
  const at = (i) => [
    "match", ["get", "kind_detail"],
    TRUNK_DETAILS, WIDTH.trunk[i],
    SECONDARY_DETAILS, WIDTH.secondary[i],
    WIDTH.tertiary[i],
  ];
  return ["interpolate", ["exponential", 1.6], ["zoom"], ...STOPS.flatMap((z, i) => [z, at(i)])];
}

/** Fill colour of a major road, by class, darker while the line is thin. */
function majorColor(p) {
  return [
    "interpolate", ["linear"], ["zoom"],
    10.5, ["match", ["get", "kind_detail"], TRUNK_DETAILS, p.trunk.low, SECONDARY_DETAILS, p.secondary.low, p.tertiary.low],
    12, ["match", ["get", "kind_detail"], TRUNK_DETAILS, p.trunk.fill, SECONDARY_DETAILS, p.secondary.fill, p.tertiary.fill],
  ];
}

function majorCasingColor(p) {
  return ["match", ["get", "kind_detail"], TRUNK_DETAILS, p.trunk.casing, SECONDARY_DETAILS, p.secondary.casing, p.tertiary.casing];
}

const CASING = {
  motorway: ["interpolate", ["linear"], ["zoom"], 6.5, 0, 7.5, 0.8, 12, 1, 15, 1.4, 18, 2],
  major: ["interpolate", ["linear"], ["zoom"], 11, 0, 12, 0.7, 15, 1.1, 18, 1.5],
  minor: ["interpolate", ["linear"], ["zoom"], 12, 0, 13, 0.6, 15, 0.9, 18, 1.2],
  link: ["interpolate", ["linear"], ["zoom"], 12, 0, 13, 0.7, 18, 1.2],
};

// Upstream's layers, labels included: their text expressions pick the name
// in the reader's language and handle names in other scripts. The language
// is the placeholder in the shipped styles, a real code for the checks.
function upstream(p, lang) {
  return layers(SOURCE, flavor(p), { lang });
}

function insertAfter(list, id, layer) {
  const i = list.findIndex((l) => l.id === id);
  if (i < 0) throw new Error(`no layer ${id}`);
  list.splice(i + 1, 0, layer);
}

// Localities by OSM place type: cities from the country view, towns from
// the regional one, villages once roads can be followed, hamlets only close
// up, where they help find a spot. Upstream shows every place the tile
// carries, which fills the regional views with hamlet names.
const PLACE_MIN_ZOOM = ["match", ["get", "kind_detail"], "city", 0, "town", 7, "village", 10, "hamlet", 13, ["isolated_dwelling", "farm", "locality"], 14, 12];
const PLACE_MAJOR = ["city", "town", "village"];

function placeSize() {
  const kd = ["get", "kind_detail"];
  const big = (rank, above, below) => ["case", [">=", ["get", "population_rank"], rank], above, below];
  return [
    "interpolate", ["linear"], ["zoom"],
    4, ["match", kd, "city", big(13, 13, 10.5), 10],
    7, ["match", kd, "city", big(12, 17, 13), "town", 12, 11],
    9, ["match", kd, "city", big(10, 19, 15.5), "town", 14, 11.5],
    11, ["match", kd, "city", big(10, 20, 17), "town", 15.5, "village", 13, 11.5],
    14, ["match", kd, "city", 22, "town", 18, "village", 15.5, 12.5],
    17, ["match", kd, "city", 24, "town", 20, "village", 17, 14],
  ];
}

function patch(p, list) {
  const byId = new Map(list.map((l) => [l.id, l]));
  // An upstream release that renames a layer stops the generator here.
  const layer = (id) => {
    const found = byId.get(id);
    if (!found) throw new Error(`upstream has no layer ${id}`);
    return found;
  };
  const set = (id, kind, values) => Object.assign((layer(id)[kind] ??= {}), values);

  // Built-up areas, which upstream leaves blank between the low-zoom land
  // cover and the buildings: villages read as places on the regional views.
  insertAfter(list, "landcover", {
    id: "landuse_urban",
    type: "fill",
    source: SOURCE,
    "source-layer": "landuse",
    filter: ["in", "kind", "residential", "commercial", "retail"],
    paint: {
      "fill-color": p.urban,
      "fill-opacity": ["interpolate", ["linear"], ["zoom"], 6, 0, 8, 1],
    },
  });

  // Woods and parks in sage; protected areas and national parks stay
  // unfilled, since they span whole massifs and would tint everything.
  set("landuse_park", "paint", {
    "fill-color": [
      "match", ["get", "kind"],
      ["forest", "wood"], p.wood,
      ["park", "cemetery", "golf_course"], p.park,
      ["scrub", "grassland", "grass"], p.scrub,
      "glacier", p.glacier,
      "sand", p.sand,
      ["military", "naval_base", "airfield"], p.military,
      p.land,
    ],
  });
  layer("landuse_park").filter = ["in", "kind", "park", "cemetery", "forest", "golf_course", "wood", "scrub", "grassland", "grass", "glacier", "sand", "military", "naval_base", "airfield"];

  set("buildings", "paint", {
    "fill-color": p.buildings,
    "fill-outline-color": p.buildingsOutline,
    "fill-opacity": ["interpolate", ["linear"], ["zoom"], 13, 0, 14, 1],
  });

  // Motorways: the widest line, a slate tint over a darker casing.
  for (const id of ["roads_highway", "roads_bridges_highway"]) {
    set(id, "paint", {
      "line-color": ["interpolate", ["linear"], ["zoom"], 7, p.motorway.low, 9.5, p.motorway.fill],
      "line-width": widthOf("motorway"),
    });
  }
  for (const id of ["roads_highway_casing_early", "roads_highway_casing_late", "roads_bridges_highway_casing"]) {
    set(id, "paint", {
      "line-color": p.motorway.casing,
      "line-gap-width": widthOf("motorway"),
      "line-width": CASING.motorway,
    });
  }
  set("roads_tunnels_highway", "paint", { "line-width": widthOf("motorway") });
  set("roads_tunnels_highway_casing", "paint", { "line-gap-width": widthOf("motorway"), "line-width": CASING.motorway });

  // Trunk and primary, secondary, tertiary: one layer each upstream, split
  // here by width and casing tone.
  for (const id of ["roads_major", "roads_bridges_major"]) {
    set(id, "paint", { "line-color": majorColor(p), "line-width": majorWidth() });
  }
  for (const id of ["roads_major_casing_early", "roads_major_casing_late", "roads_bridges_major_casing"]) {
    set(id, "paint", { "line-color": majorCasingColor(p), "line-gap-width": majorWidth(), "line-width": CASING.major });
  }
  set("roads_tunnels_major", "paint", { "line-width": majorWidth() });
  set("roads_tunnels_major_casing", "paint", { "line-gap-width": majorWidth(), "line-width": CASING.major });

  // Slip roads take the colours of the road they belong to.
  const linkFill = ["match", ["get", "kind"], "highway", p.motorway.fill, p.trunk.fill];
  const linkCasing = ["match", ["get", "kind"], "highway", p.motorway.casing, p.trunk.casing];
  for (const id of ["roads_link", "roads_bridges_link"]) {
    set(id, "paint", { "line-color": linkFill, "line-width": widthOf("link") });
  }
  for (const id of ["roads_link_casing", "roads_bridges_link_casing"]) {
    set(id, "paint", { "line-color": linkCasing, "line-gap-width": widthOf("link"), "line-width": CASING.link });
  }
  layer("roads_link_casing").minzoom = 12;

  // Minor roads and service roads: thin and close to the land colour.
  for (const id of ["roads_minor", "roads_bridges_minor"]) {
    set(id, "paint", {
      "line-color": ["interpolate", ["linear"], ["zoom"], 12, p.minor.low, 14, p.minor.fill],
      "line-width": widthOf("minor"),
    });
  }
  for (const id of ["roads_minor_casing", "roads_bridges_minor_casing"]) {
    set(id, "paint", { "line-color": p.minor.casing, "line-gap-width": widthOf("minor"), "line-width": CASING.minor });
  }
  set("roads_minor_service", "paint", { "line-width": widthOf("service") });
  set("roads_minor_service_casing", "paint", { "line-gap-width": widthOf("service"), "line-width": CASING.minor });
  layer("roads_minor_service").minzoom = 13;

  // Tracks dashed, footways and cycleways dotted and faint; upstream draws
  // them all as one solid line.
  const others = layer("roads_other");
  others.filter = ["all", ["!has", "is_tunnel"], ["!has", "is_bridge"], ["in", "kind", "other", "path"], ["!in", "kind_detail", "pier", "track"]];
  others.minzoom = 14;
  others.paint = {
    "line-color": p.path,
    "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 14, 0.6, 16, 1, 18, 2],
    "line-dasharray": [1, 1.5],
  };
  insertAfter(list, "roads_other", {
    id: "roads_track",
    type: "line",
    source: SOURCE,
    "source-layer": "roads",
    minzoom: 13,
    filter: ["all", ["!has", "is_tunnel"], ["==", "kind_detail", "track"]],
    paint: {
      "line-color": p.track,
      "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 13, 0.6, 15, 1.1, 18, 2.6],
      "line-dasharray": [3, 2],
    },
  });

  // Railways: a fine dashed line, quieter than any road.
  set("roads_rail", "paint", { "line-color": p.rail, "line-opacity": 0.75 });

  set("boundaries_country", "paint", {
    "line-color": p.boundaryCountry,
    "line-width": ["interpolate", ["linear"], ["zoom"], 4, 0.8, 10, 1.4],
    "line-dasharray": [3, 2],
  });
  // Countries, regions and departments; municipal boundaries would cross
  // every regional view with dashes that read like tracks.
  layer("boundaries").filter = ["all", [">", "kind_detail", 2], ["<=", "kind_detail", 6]];
  set("boundaries", "paint", {
    "line-color": p.boundaryRegion,
    "line-width": ["interpolate", ["linear"], ["zoom"], 4, 0.6, 10, 1],
    "line-dasharray": [3, 2],
  });

  const locality = layer("places_locality");
  locality.filter = ["all", ["==", ["get", "kind"], "locality"], [">=", ["zoom"], PLACE_MIN_ZOOM]];
  set("places_locality", "layout", {
    "text-font": ["case", ["in", ["get", "kind_detail"], ["literal", PLACE_MAJOR]], ["literal", ["Noto Sans Medium"]], ["literal", ["Noto Sans Regular"]]],
    "text-size": placeSize(),
  });
  set("places_locality", "paint", {
    "text-color": ["match", ["get", "kind_detail"], PLACE_MAJOR, p.place, p.placeMinor],
    "text-halo-color": p.placeHalo,
    "text-halo-width": 1.6,
    "text-halo-blur": 0.4,
  });
  layer("places_subplace").minzoom = 12;
  set("places_subplace", "paint", { "text-halo-width": 1.4 });
  set("places_region", "paint", { "text-halo-width": 1.4 });
  set("places_country", "paint", { "text-halo-color": p.placeHalo, "text-halo-width": 1.4 });
  set("earth_label_islands", "paint", { "text-color": p.island, "text-halo-color": p.placeHalo });

  for (const id of ["water_label_ocean", "water_label_lakes", "water_waterway_label"]) {
    set(id, "paint", { "text-color": p.waterLabel, "text-halo-color": p.waterLabelHalo, "text-halo-width": 1.2 });
  }
  for (const id of ["roads_labels_major", "roads_labels_minor"]) {
    set(id, "paint", { "text-halo-width": 1.6 });
  }
  set("roads_shields", "paint", { "text-color": p.shieldText });
  set("roads_shields", "layout", { "text-size": 9 });
  return list;
}

function shell(name, sheet, builtLayers, metadata = undefined) {
  return {
    version: 8,
    name,
    ...(metadata ? { metadata } : {}),
    sources: {
      [SOURCE]: { type: "vector", url: PLACEHOLDERS.tiles, attribution: ATTRIBUTION },
    },
    sprite: `${PLACEHOLDERS.sprite}/${sheet}`,
    glyphs: `${PLACEHOLDERS.glyphs}/{fontstack}/{range}.pbf`,
    layers: builtLayers,
  };
}

/**
 * A Lunaway style, "aube" or "minuit". [lang] is the label language; the
 * shipped styles keep the placeholder.
 */
export function lunawayStyle(name, upstreamVersion, lang = PLACEHOLDERS.lang) {
  const p = PALETTES[name];
  if (!p) throw new Error(`unknown style ${name}`);
  const title = { aube: "Lunaway Aube", minuit: "Lunaway Minuit" }[name];
  return shell(title, p.sheet, patch(p, upstream(p, lang)), {
    "lunaway:generator": "app/tool/map_style/generate.mjs",
    "lunaway:protomaps-basemaps": upstreamVersion,
  });
}

/** Upstream light or dark, with the same placeholders, for comparisons. */
export function stockStyle(flavorName) {
  return shell(`Protomaps ${flavorName}`, flavorName, layers(SOURCE, namedFlavor(flavorName), { lang: PLACEHOLDERS.lang }));
}

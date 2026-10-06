// Browser side of the preview: loads a style with its placeholders filled
// the way the app fills them (plain string replacement of the JSON text),
// renders it over a local PMTiles extract, and reports to render.mjs through
// window.__state once every visible tile is drawn.
//
// The app runs two builds of MapLibre GL JS: the module build of the web app
// (app/web/maplibre-gl/, the default here) and the script build of the
// desktop web view (app/assets/map/, with engine=desktop).

const params = new URLSearchParams(location.search);

function loadScript(src) {
  return new Promise((ok, fail) => {
    const script = document.createElement("script");
    script.src = src;
    script.onload = ok;
    script.onerror = () => fail(new Error(`cannot load ${src}`));
    document.head.append(script);
  });
}

let maplibregl;
if (params.get("engine") === "desktop") {
  await loadScript("/maplibre-desktop/maplibre-gl.js");
  maplibregl = window.maplibregl;
} else {
  maplibregl = await import("/maplibre/maplibre-gl.mjs");
}
const styleName = params.get("style");
const region = params.get("region");
const lang = params.get("lang") || "fr";
const center = [Number(params.get("lon")), Number(params.get("lat"))];
const zoom = Number(params.get("zoom"));

window.__state = "loading";
window.__version = maplibregl.getVersion();
window.__errors = [];

const protocol = new pmtiles.Protocol();
maplibregl.addProtocol("pmtiles", protocol.tile);

function fill(text) {
  return text
    .replaceAll("__LUNAWAY_TILES__", `pmtiles://${location.origin}/tiles/${region}.pmtiles`)
    .replaceAll("__LUNAWAY_GLYPHS__", `${location.origin}/fonts`)
    .replaceAll("__LUNAWAY_SPRITE__", `${location.origin}/sprites/protomaps-v4`)
    .replaceAll("__LUNAWAY_LANG__", lang);
}

// Stand-ins for the app's pins: a white-rimmed disc per family colour and one
// selected pin with the amber halo, scattered around the centre, to judge
// whether the basemap competes with them.
const PIN_COLOURS = ["#2C5FA8", "#1F7F86", "#3F8A4A", "#8B6A9F"];
function pins() {
  const features = [];
  const span = 360 / 2 ** zoom;
  let seed = 7;
  const random = () => {
    seed = (seed * 16807) % 2147483647;
    return seed / 2147483647;
  };
  for (let i = 0; i < 14; i += 1) {
    features.push({
      type: "Feature",
      properties: { colour: PIN_COLOURS[i % PIN_COLOURS.length], selected: i === 3 },
      geometry: { type: "Point", coordinates: [center[0] + (random() - 0.5) * span * 0.7, center[1] + (random() - 0.5) * span * 1.0] },
    });
  }
  return { type: "FeatureCollection", features };
}

function addPins(map) {
  map.addSource("pins", { type: "geojson", data: pins() });
  map.addLayer({
    id: "pins-halo", type: "circle", source: "pins", filter: ["==", ["get", "selected"], true],
    paint: { "circle-radius": 24, "circle-color": "#F2A541", "circle-opacity": 0.28 },
  });
  map.addLayer({
    id: "pins", type: "circle", source: "pins",
    paint: {
      "circle-radius": ["case", ["get", "selected"], 12, 9],
      "circle-color": ["get", "colour"],
      "circle-stroke-color": ["case", ["get", "selected"], "#F2A541", "#FFFFFF"],
      "circle-stroke-width": 3,
    },
  });
}

// Distinct kind / kind_detail pairs per source layer in the loaded tiles, to
// check which features a filter actually catches.
function inventory(map) {
  const out = {};
  for (const layer of ["roads", "pois", "landuse", "landcover", "water", "places", "earth", "boundaries"]) {
    const seen = {};
    for (const f of map.querySourceFeatures("protomaps", { sourceLayer: layer })) {
      const key = `${f.properties.kind}/${f.properties.kind_detail ?? ""}`;
      seen[key] = (seen[key] || 0) + 1;
    }
    out[layer] = seen;
  }
  out.placeList = map.querySourceFeatures("protomaps", { sourceLayer: "places" })
    .map((f) => `${f.properties.name}|${f.properties.kind_detail}|mz ${f.properties.min_zoom}|pr ${f.properties.population_rank}`);
  out.renderedPlaces = map.queryRenderedFeatures({ layers: ["places_locality"] }).map((f) => f.properties.name);
  return out;
}

const text = await (await fetch(`/styles/${styleName}.json`)).text();
const style = JSON.parse(fill(text));
const map = new maplibregl.Map({
  container: "map",
  style,
  center,
  zoom,
  interactive: false,
  attributionControl: false,
  fadeDuration: 0,
});
map.on("error", (e) => {
  window.__errors.push(String(e.error?.message || e.error || e));
});
map.on("load", () => {
  if (params.get("pins") === "1") addPins(map);
  map.once("idle", () => {
    if (params.get("debug") === "1") window.__debug = inventory(map);
    window.__state = "ready";
  });
});

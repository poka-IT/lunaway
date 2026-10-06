// Writes app/assets/map/styles/aube.json and minuit.json.
//
//   npm ci && node generate.mjs
//   node generate.mjs --deploy DIR   also the server copies, see README
//
// The output depends only on the pinned packages and on style.mjs: two runs
// give byte-identical files. Before writing, it checks each style against
// the MapLibre style specification with sample values in the placeholders,
// checks that filling the language placeholder gives exactly the style
// upstream builds for that language, and refuses warm saturated colours
// (the amber and coral the app keeps for itself).
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { format, validateStyleMin } from "@maplibre/maplibre-gl-style-spec";
import { LANGUAGES, PLACEHOLDERS, lunawayStyle } from "./style.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "..", "assets", "map", "styles");
const require = createRequire(import.meta.url);
const upstreamVersion = JSON.parse(readFileSync(require.resolve("@protomaps/basemaps/package.json"), "utf8")).version;

const SAMPLE = {
  [PLACEHOLDERS.tiles]: "https://tiles.example.org/planet.json",
  [PLACEHOLDERS.glyphs]: "https://tiles.example.org/fonts",
  [PLACEHOLDERS.sprite]: "https://tiles.example.org/sprites/protomaps-v4",
  [PLACEHOLDERS.lang]: "fr",
};

// U+2013 and U+2014, which no authored file of the repository holds.
const DASHES = new RegExp("[\\u2013\\u2014]");

function fill(text, values) {
  let out = text;
  for (const [token, value] of Object.entries(values)) out = out.replaceAll(token, value);
  return out;
}

function hexColours(text) {
  return [...text.matchAll(/#([0-9a-fA-F]{6})\b/g)].map((m) => m[1]);
}

// Hue in degrees and chroma (0 to 1) of a hex colour.
function hueChroma(hex) {
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const c = max - min;
  if (c === 0) return { hue: 0, chroma: 0 };
  let h;
  if (max === r) h = ((g - b) / c) % 6;
  else if (max === g) h = (b - r) / c + 2;
  else h = (r - g) / c + 4;
  return { hue: (h * 60 + 360) % 360, chroma: c };
}

function check(name, style, text) {
  const errors = validateStyleMin(JSON.parse(fill(text, SAMPLE)));
  if (errors.length > 0) throw new Error(`${name}: ${errors.map((e) => e.message).join("; ")}`);

  for (const token of Object.values(PLACEHOLDERS)) {
    if (!text.includes(token)) throw new Error(`${name}: placeholder ${token} missing`);
  }

  // The language placeholder sits where upstream writes the language code,
  // so filling it must give upstream's own output for that language.
  for (const lang of LANGUAGES) {
    const direct = JSON.stringify(lunawayStyle(name, upstreamVersion, lang).layers);
    const filled = fill(JSON.stringify(style.layers), { [PLACEHOLDERS.lang]: lang });
    if (direct !== filled) throw new Error(`${name}: filling ${PLACEHOLDERS.lang} with ${lang} differs from upstream's ${lang} labels`);
  }

  // Amber (selection, actions) and coral (alerts) belong to the app; a warm
  // saturated colour on the basemap would read as one of them.
  for (const hex of hexColours(text)) {
    const { hue, chroma } = hueChroma(hex);
    if (chroma > 0.35 && (hue >= 330 || hue <= 70)) throw new Error(`${name}: #${hex} is a warm saturated colour`);
  }

  if (DASHES.test(text)) throw new Error(`${name}: em or en dash in the output`);
}

// The copies the tile host serves under /styles/, for the website and any
// client that reads a style by URL: filled for https://tiles.lunaway.net,
// which the server rewrites to the host it answers on
// (infra/deploy-basemap-assets.sh), one per label language.
const DEPLOYED = {
  [PLACEHOLDERS.tiles]: "https://tiles.lunaway.net/planet.json",
  [PLACEHOLDERS.glyphs]: "https://tiles.lunaway.net/fonts",
  [PLACEHOLDERS.sprite]: "https://tiles.lunaway.net/sprites/protomaps-v4",
};

const deployAt = process.argv.indexOf("--deploy");
const deployDir = deployAt === -1 ? null : process.argv[deployAt + 1];
if (deployAt !== -1 && !deployDir) throw new Error("--deploy needs a directory");

mkdirSync(OUT, { recursive: true });
if (deployDir) mkdirSync(deployDir, { recursive: true });
for (const name of ["aube", "minuit"]) {
  const style = lunawayStyle(name, upstreamVersion);
  const text = `${format(style, 1)}\n`;
  check(name, style, text);
  const file = join(OUT, `${name}.json`);
  writeFileSync(file, text);
  console.log(`${file}: ${style.layers.length} layers, ${Buffer.byteLength(text)} bytes`);
  if (!deployDir) continue;
  for (const lang of LANGUAGES) {
    const deployed = fill(text, { ...DEPLOYED, [PLACEHOLDERS.lang]: lang });
    const errors = validateStyleMin(JSON.parse(deployed));
    if (errors.length > 0) throw new Error(`${name}-${lang}: ${errors.map((e) => e.message).join("; ")}`);
    const out = join(deployDir, `${name}-${lang}.json`);
    writeFileSync(out, deployed);
    console.log(`${out}`);
  }
}

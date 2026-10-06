// Downloads what the previews render with, into data/tmp/map_style/ (gitignored):
// the go-pmtiles CLI, the Protomaps glyphs and sprites, and three small
// extracts of a recent Protomaps planet build. Nothing here ships with the
// app; the styles themselves do not depend on these files.
//
//   node preview/fetch.mjs                  # newest planet build
//   node preview/fetch.mjs --build 20261005 # a given build (builds are kept a few weeks)
//
// Each step is skipped when its output is already there, so a second run
// only fetches what is missing. Delete a region's .pmtiles to extract it again.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { createWriteStream, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { BASEMAPS_ASSETS_COMMIT, PMTILES_VERSION, PMTILES_ZIPS, REGIONS } from "./pins.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..", "..", "..");
const WORK = join(REPO, "data", "tmp", "map_style");

const BUILDS_INDEX = "https://build-metadata.protomaps.dev/builds.json";
const BUILD_BASE = "https://build.protomaps.com";
const USER_AGENT = "lunaway-map-style-preview (+https://lunaway.net)";

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

async function download(url, path) {
  const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  const partial = `${path}.download`;
  await pipeline(Readable.fromWeb(res.body), createWriteStream(partial));
  renameSync(partial, path);
}

function sha256(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

async function pmtilesCli() {
  if (process.platform !== "darwin") {
    throw new Error("this script fetches the macOS build of go-pmtiles; elsewhere put a pmtiles binary at data/tmp/map_style/bin/pmtiles");
  }
  const bin = join(WORK, "bin", "pmtiles");
  if (existsSync(bin)) return bin;
  const pin = PMTILES_ZIPS[process.arch];
  if (!pin) throw new Error(`no pinned go-pmtiles build for ${process.arch}`);
  mkdirSync(join(WORK, "downloads"), { recursive: true });
  const zip = join(WORK, "downloads", `go-pmtiles-${PMTILES_VERSION}-${process.arch}.zip`);
  if (!existsSync(zip)) {
    console.log(`go-pmtiles ${PMTILES_VERSION}`);
    await download(pin.url, zip);
  }
  const got = sha256(zip);
  if (got !== pin.sha256) throw new Error(`${zip} hashes to ${got}, the pin says ${pin.sha256}`);
  mkdirSync(join(WORK, "bin"), { recursive: true });
  execFileSync("unzip", ["-o", "-q", zip, "pmtiles", "-d", join(WORK, "bin")]);
  return bin;
}

async function basemapsAssets() {
  const root = join(WORK, "assets", `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}`);
  if (existsSync(join(root, "sprites", "v4", "light.json"))) return root;
  mkdirSync(join(WORK, "downloads"), { recursive: true });
  const tarball = join(WORK, "downloads", `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}.tar.gz`);
  if (!existsSync(tarball)) {
    console.log(`basemaps-assets ${BASEMAPS_ASSETS_COMMIT.slice(0, 12)}`);
    await download(`https://codeload.github.com/protomaps/basemaps-assets/tar.gz/${BASEMAPS_ASSETS_COMMIT}`, tarball);
  }
  mkdirSync(join(WORK, "assets"), { recursive: true });
  // Only the font stacks the styles name and the v4 sprites.
  execFileSync("tar", [
    "-xzf", tarball, "-C", join(WORK, "assets"),
    `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}/fonts/Noto Sans Regular`,
    `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}/fonts/Noto Sans Medium`,
    `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}/fonts/Noto Sans Italic`,
    `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}/fonts/Noto Sans Devanagari Regular v1`,
    `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}/fonts/OFL.txt`,
    `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}/sprites/v4`,
  ]);
  return root;
}

async function planetBuild() {
  const wanted = arg("--build");
  if (wanted) return `${wanted}.pmtiles`;
  const res = await fetch(BUILDS_INDEX, { headers: { "User-Agent": USER_AGENT } });
  if (!res.ok) throw new Error(`${BUILDS_INDEX}: HTTP ${res.status}`);
  const builds = await res.json();
  return builds[builds.length - 1].key;
}

async function extracts(bin) {
  const dir = join(WORK, "tiles");
  mkdirSync(dir, { recursive: true });
  const missing = Object.entries(REGIONS).filter(([name]) => !existsSync(join(dir, `${name}.pmtiles`)));
  if (missing.length === 0) return;
  const build = await planetBuild();
  for (const [name, region] of missing) {
    console.log(`extract ${name} from ${build}: bbox ${region.bbox.join(",")}, z0 to z${region.maxzoom}`);
    const partial = join(dir, `${name}.partial.pmtiles`);
    execFileSync(bin, [
      "extract", `${BUILD_BASE}/${build}`, partial,
      `--bbox=${region.bbox.join(",")}`, `--maxzoom=${region.maxzoom}`,
      "--download-threads=4",
    ], { stdio: "inherit" });
    renameSync(partial, join(dir, `${name}.pmtiles`));
    writeFileSync(join(dir, `${name}.build`), `${build}\n`);
  }
}

const bin = await pmtilesCli();
await basemapsAssets();
await extracts(bin);
console.log(`ready in ${WORK}`);

// Renders the generated styles over the local extracts (preview/fetch.mjs)
// in a headless Brave started for this run only, and saves PNGs.
//
//   node preview/render.mjs                       # every shot, both styles
//   node preview/render.mjs --styles aube --shots z12,z15
//   node preview/render.mjs --stock               # the stock Protomaps light and dark, for comparison
//   node preview/render.mjs --tag v2              # suffix the file names, to keep an iteration
//   node preview/render.mjs --inventory z15       # print the kinds found in the tiles of a shot
//   node preview/render.mjs --engine desktop      # the MapLibre build of the desktop web view
//
// The browser talks over --remote-debugging-pipe, so no debugging port is
// opened; the only port is the static server's, on 127.0.0.1, chosen by the
// system. The profile is a new directory under data/tmp/map_style/profiles/.

import { spawn } from "node:child_process";
import { createReadStream, existsSync, mkdirSync, mkdtempSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { BASEMAPS_ASSETS_COMMIT } from "./pins.mjs";
import { stockStyle } from "../style.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TOOL = join(HERE, "..");
const REPO = join(TOOL, "..", "..", "..");
const WORK = join(REPO, "data", "tmp", "map_style");
const ASSETS = join(WORK, "assets", `basemaps-assets-${BASEMAPS_ASSETS_COMMIT}`);
const OUT_DEFAULT = join(REPO, "plan", "screenshots", "pass2", "map-style");
const BROWSER = "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser";

const PHONE = { width: 412, height: 915, scale: 2, mobile: true };
const DESKTOP = { width: 1440, height: 900, scale: 1, mobile: false };

// Views around Annecy: the A41 motorway, national and departmental roads,
// villages, the lake and mountain tracks. z6 covers the Rhone valley from the
// Mediterranean to Burgundy; z11 is the zoom at which villages appear.
const SHOTS = {
  z6: { region: "france", lon: 4.8, lat: 45.9, zoom: 6, viewport: PHONE },
  z9: { region: "alps", lon: 6.05, lat: 45.85, zoom: 9, viewport: PHONE },
  z11: { region: "annecy", lon: 6.05, lat: 45.88, zoom: 11, viewport: PHONE },
  z12: { region: "annecy", lon: 6.11, lat: 45.905, zoom: 12, viewport: PHONE },
  z15: { region: "annecy", lon: 6.1295, lat: 45.899, zoom: 15, viewport: PHONE },
  pins12: { region: "annecy", lon: 6.11, lat: 45.905, zoom: 12, viewport: PHONE, pins: true },
  desktop: { region: "alps", lon: 6.1, lat: 45.95, zoom: 9, viewport: DESKTOP },
};

function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

const stock = process.argv.includes("--stock");
const styles = (arg("--styles", stock ? "stock-light,stock-dark" : "aube,minuit")).split(",");
const inventoryShot = arg("--inventory");
const shots = inventoryShot ? [inventoryShot] : arg("--shots", Object.keys(SHOTS).join(",")).split(",");
const tag = arg("--tag");
const lang = arg("--lang", "fr");
const engine = arg("--engine", "web");
const out = resolve(arg("--out", OUT_DEFAULT));

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".pbf": "application/x-protobuf",
  ".pmtiles": "application/octet-stream",
};

// Maps a URL path to a file under one of the served roots, refusing anything
// that would resolve outside its root.
function route(pathname) {
  const decoded = decodeURIComponent(pathname);
  const table = [
    ["/maplibre/", join(REPO, "app", "web", "maplibre-gl")],
    ["/maplibre-desktop/", join(REPO, "app", "assets", "map")],
    ["/tiles/", join(WORK, "tiles")],
    ["/fonts/", join(ASSETS, "fonts")],
    ["/sprites/protomaps-v4/", join(ASSETS, "sprites", "v4")],
    ["/styles/", join(REPO, "app", "assets", "map", "styles")],
  ];
  if (decoded === "/" || decoded === "/index.html") return join(HERE, "index.html");
  if (decoded === "/preview.js") return join(HERE, "preview.js");
  if (decoded === "/pmtiles.js") return join(TOOL, "node_modules", "pmtiles", "dist", "pmtiles.js");
  for (const [prefix, root] of table) {
    if (decoded.startsWith(prefix)) {
      const file = resolve(root, decoded.slice(prefix.length));
      return file.startsWith(root + sep) ? file : null;
    }
  }
  return null;
}

function serve(req, res) {
  const { pathname } = new URL(req.url, "http://localhost");
  const stockMatch = pathname.match(/^\/styles\/(stock-light|stock-dark)\.json$/);
  if (stockMatch) {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(stockStyle(stockMatch[1].slice("stock-".length))));
    return;
  }
  const file = route(pathname);
  if (!file || !existsSync(file) || !statSync(file).isFile()) {
    res.writeHead(404);
    res.end();
    return;
  }
  const size = statSync(file).size;
  const type = TYPES[extname(file)] || "application/octet-stream";
  // PMTiles reads its archive with byte ranges.
  const range = req.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
  if (range) {
    const start = Number(range[1]);
    const end = range[2] ? Math.min(Number(range[2]), size - 1) : size - 1;
    res.writeHead(206, { "Content-Type": type, "Content-Range": `bytes ${start}-${end}/${size}`, "Content-Length": end - start + 1, "Accept-Ranges": "bytes" });
    createReadStream(file, { start, end }).pipe(res);
    return;
  }
  res.writeHead(200, { "Content-Type": type, "Content-Length": size, "Accept-Ranges": "bytes" });
  createReadStream(file).pipe(res);
}

// Chrome DevTools protocol over the pipe pair the browser opens on fds 3
// (commands in) and 4 (replies out), one JSON message per NUL-terminated frame.
class Pipe {
  constructor(input, output) {
    this.input = input;
    this.next = 1;
    this.pending = new Map();
    this.listeners = new Set();
    let buffer = Buffer.alloc(0);
    output.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      let end;
      while ((end = buffer.indexOf(0)) >= 0) {
        const message = JSON.parse(buffer.subarray(0, end).toString("utf8"));
        buffer = buffer.subarray(end + 1);
        this.dispatch(message);
      }
    });
  }

  send(method, params = {}, sessionId = undefined) {
    const id = this.next++;
    const message = { id, method, params };
    if (sessionId) message.sessionId = sessionId;
    this.input.write(`${JSON.stringify(message)}\0`);
    return new Promise((ok, fail) => this.pending.set(id, { ok, fail, method }));
  }

  dispatch(message) {
    const waiting = message.id && this.pending.get(message.id);
    if (waiting) {
      this.pending.delete(message.id);
      if (message.error) waiting.fail(new Error(`${waiting.method}: ${message.error.message}`));
      else waiting.ok(message.result);
      return;
    }
    for (const listener of this.listeners) listener(message);
  }
}

function launch() {
  if (!existsSync(BROWSER)) throw new Error(`no browser at ${BROWSER}`);
  mkdirSync(join(WORK, "profiles"), { recursive: true });
  const profile = mkdtempSync(join(WORK, "profiles", "brave-"));
  const child = spawn(BROWSER, [
    "--headless=new",
    "--remote-debugging-pipe",
    `--user-data-dir=${profile}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-extensions",
    "--disable-sync",
    "--disable-background-networking",
    "--disable-component-update",
    "--hide-scrollbars",
    "--mute-audio",
    // WebGL through SwiftShader when the headless browser has no GPU context.
    "--enable-unsafe-swiftshader",
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"] });
  let stderr = "";
  child.stderr.on("data", (d) => {
    stderr = (stderr + d.toString()).slice(-4000);
  });
  return { child, pipe: new Pipe(child.stdio[3], child.stdio[4]), profile, stderr: () => stderr };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function shoot(pipe, origin, styleName, shotName) {
  const shot = SHOTS[shotName];
  if (!shot) throw new Error(`unknown shot ${shotName}`);
  const { targetId } = await pipe.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await pipe.send("Target.attachToTarget", { targetId, flatten: true });
  const logs = [];
  const listener = (m) => {
    if (m.sessionId !== sessionId) return;
    if (m.method === "Runtime.exceptionThrown") logs.push(m.params.exceptionDetails.exception?.description || m.params.exceptionDetails.text);
    if (m.method === "Runtime.consoleAPICalled" && (m.params.type === "error" || m.params.type === "warning")) {
      logs.push(m.params.args.map((a) => a.value ?? a.description).join(" "));
    }
  };
  pipe.listeners.add(listener);
  try {
    await pipe.send("Runtime.enable", {}, sessionId);
    await pipe.send("Page.enable", {}, sessionId);
    const v = shot.viewport;
    await pipe.send("Emulation.setDeviceMetricsOverride", { width: v.width, height: v.height, deviceScaleFactor: v.scale, mobile: v.mobile }, sessionId);
    const query = new URLSearchParams({
      style: styleName, region: shot.region, lon: shot.lon, lat: shot.lat, zoom: shot.zoom, lang,
      pins: shot.pins ? "1" : "0", debug: inventoryShot ? "1" : "0", engine,
    });
    await pipe.send("Page.navigate", { url: `${origin}/?${query}` }, sessionId);
    const deadline = Date.now() + 120_000;
    let state;
    while (Date.now() < deadline) {
      const r = await pipe.send("Runtime.evaluate", {
        expression: "JSON.stringify({ state: window.__state, errors: window.__errors, debug: window.__debug, version: window.__version })",
        returnByValue: true,
      }, sessionId);
      state = JSON.parse(r.result.value || "{}");
      if (state.state === "ready") break;
      await sleep(250);
    }
    if (state?.state !== "ready") throw new Error(`${styleName} ${shotName}: the map did not settle\n${logs.join("\n")}`);
    const noise = (e) => /204|AbortError/.test(e);
    for (const e of [...(state.errors || []).filter((e) => !noise(e)), ...logs]) console.log(`  ${styleName} ${shotName}: ${e}`);
    if (inventoryShot) {
      console.log(JSON.stringify(state.debug, null, 1));
      return;
    }
    const { data } = await pipe.send("Page.captureScreenshot", { format: "png" }, sessionId);
    mkdirSync(out, { recursive: true });
    const file = join(out, `${styleName}-${shotName}${tag ? `-${tag}` : ""}.png`);
    writeFileSync(file, Buffer.from(data, "base64"));
    console.log(`${file} (MapLibre GL JS ${state.version})`);
  } finally {
    pipe.listeners.delete(listener);
    await pipe.send("Target.closeTarget", { targetId });
  }
}

if (!existsSync(join(WORK, "tiles", "annecy.pmtiles"))) {
  throw new Error("no extracts yet: run node preview/fetch.mjs first");
}
const server = createServer(serve);
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = launch();
try {
  await browser.pipe.send("Browser.getVersion");
  for (const styleName of styles) {
    for (const shotName of shots) await shoot(browser.pipe, origin, styleName, shotName);
  }
} catch (e) {
  console.error(e.message);
  console.error(browser.stderr());
  process.exitCode = 1;
} finally {
  await Promise.race([browser.pipe.send("Browser.close").catch(() => {}), sleep(3000)]);
  if (browser.child.exitCode === null) browser.child.kill("SIGTERM");
  server.close();
  console.log(`profile left in ${browser.profile}`);
}


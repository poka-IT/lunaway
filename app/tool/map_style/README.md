# Basemap styles: Aube and Minuit

`generate.mjs` builds the two basemap styles of the app from
[@protomaps/basemaps](https://github.com/protomaps/basemaps) (pinned in
`package.json`) and writes them to:

- `app/assets/map/styles/aube.json`, the light style (cream land, teal water,
  sage woods, navy labels);
- `app/assets/map/styles/minuit.json`, the dark style (navy land, deep teal
  water, cream labels).

Both read vector tiles of the Protomaps basemap schema, version 4 (the daily
planet builds of build.protomaps.com, and what the server's refresh accepts,
see `infra/tiles/version.sh`).

```bash
cd app/tool/map_style
npm ci
node generate.mjs
```

The output depends only on the pinned packages and `style.mjs`, so two runs
give byte-identical files. The generator refuses to write a style that fails
the MapLibre style specification, that misses a placeholder, whose language
placeholder filled with any of the app's languages (`fr`, `en`, `de`, `es`,
`it`, `nl`) differs from upstream's own labels for that language, or that
holds a warm saturated colour (amber and coral are the app's selection and
alert colours).

## The copies the tile host serves

The app ships the templates and fills them itself. For the website and any
client that reads a style by URL, the tile host serves filled copies under
`/styles/`:

```bash
node generate.mjs --deploy ../../../data/tmp/deploy-styles
infra/deploy-basemap-assets.sh styles data/tmp/deploy-styles   # from the root, by the maintainer
```

`--deploy` writes `aube-fr.json`, `aube-en.json`, `minuit-fr.json` and
`minuit-en.json`, filled for `https://tiles.lunaway.net`; the server rewrites
that prefix to the host it answers on.

## What the app replaces

The styles are templates. Before handing one to MapLibre, the app replaces
four tokens in the JSON text with plain string replacement (every
occurrence), then parses it. Each token sits inside a JSON string, so a value
must not contain a double quote or a backslash; URLs and language codes do
not.

| token | replace with | example |
|---|---|---|
| `__LUNAWAY_TILES__` | URL of the vector source: a TileJSON document | `https://tiles.lunaway.net/planet.json` |
| `__LUNAWAY_GLYPHS__` | base URL of the glyph server, no trailing slash; the style appends `/{fontstack}/{range}.pbf` | `https://tiles.lunaway.net/fonts` |
| `__LUNAWAY_SPRITE__` | base URL of the Protomaps v4 sprite sheets, no trailing slash; Aube appends `/light`, Minuit `/dark` | `https://tiles.lunaway.net/sprites/protomaps-v4` |
| `__LUNAWAY_LANG__` | the label language: `fr`, `en`, `de`, `es`, `it` or `nl` | `fr` |

The example URLs follow the layout the infra serves (`infra/caddy/Caddyfile`,
snippet `tiles`); the real host is the deployment's.

- Glyphs: the styles name the font stacks `Noto Sans Regular`,
  `Noto Sans Medium`, `Noto Sans Italic` and `Noto Sans Devanagari Regular v1`,
  all in protomaps/basemaps-assets. There is no `Noto Sans Bold`: a layer the
  app adds on top must use one of these stacks.
- Sprite: MapLibre fetches `<base>/light.json`, `light.png`, `light@2x.json`
  and `light@2x.png` (or `dark`). The styles use only the road shields, the
  town dot, the capital star and the one-way arrow from these sheets.
- Language: any language whose names the tiles carry as `name:<code>` and
  that is written in the Latin script works the same way. A language in
  another script (`ja`, `ru`, `ar`...) needs its own generated style, because
  upstream builds a different expression for it.

### If the tiles come as a PMTiles archive

Replace `__LUNAWAY_TILES__` with the archive's URL behind the `pmtiles://`
scheme, for example `pmtiles://https://tiles.lunaway.net/planet.pmtiles`.

- Android and iOS (MapLibre Native) read `pmtiles://` URLs themselves: PMTiles
  support arrived in the Android SDK 11.8.0 and the iOS SDK 6.10.0, and
  maplibre_gl 0.27.1 ships 13.5.0 and 6.28.0.
- The web build and the desktop web view run MapLibre GL JS, which needs the
  protocol registered first, from the `pmtiles` JavaScript library shipped
  with the app (no CDN):
  `maplibregl.addProtocol("pmtiles", new pmtiles.Protocol().tile)`.
  `preview/preview.js` does exactly this.

The archive must be served with byte ranges and CORS exposing `Content-Range`,
`ETag` and `Accept-Ranges`.

## What the styles change from upstream

Upstream supplies the layers and the label expressions (local names, other
scripts, the reader's language). `style.mjs` then:

- colours everything from the brand palette (`brand/README.md`);
- gives the roads a hierarchy by width and tone: motorways widest, in a slate
  tint over a dark casing; trunk and primary, secondary, tertiary split by
  width and casing (upstream draws them as one class); minor and service roads
  thin and close to the land colour; tracks dashed from zoom 13, footways and
  cycleways dotted from zoom 14;
- removes the points of interest (shops, cafes, campsites...), which would
  compete with the app's pins;
- shows cities from the country view, towns from zoom 7, villages from 10 and
  hamlets from 13, in larger type with a solid halo (upstream shows every
  hamlet the tile carries);
- fills built-up areas, so villages read as places on regional views, and
  leaves national parks and protected areas unfilled (they span whole
  massifs);
- hides municipal boundaries, which read like tracks.

There is no hillshade: relief would need a raster elevation source beside
the vector tiles.

## Previews

`preview/` renders both styles over real Protomaps tiles in a headless Brave,
to tune them by eye.

```bash
node preview/fetch.mjs     # go-pmtiles, glyphs and sprites, three extracts of the newest planet build
node preview/render.mjs    # every view, both styles, into plan/screenshots/pass2/map-style/
node preview/render.mjs --styles aube --shots z12,z15 --tag v2
node preview/render.mjs --stock          # upstream light and dark, for comparison
node preview/render.mjs --lang en --shots z6
node preview/render.mjs --inventory z15  # the kinds of features in a view's tiles
```

`fetch.mjs` puts everything under `data/tmp/map_style/` (gitignored): the
go-pmtiles CLI of the version the server runs (SHA-256 checked), the
basemaps-assets commit the server installs, and extracts of France to zoom 7,
the northern Alps to zoom 10 and Annecy to zoom 15 (about 60 MB together).
`--build <YYYYMMDD>` picks a given planet build; builds are kept a few weeks.

`render.mjs` serves the page, the extracts, glyphs and sprites on a port of
127.0.0.1 the system picks, starts Brave headless with a new profile under
`data/tmp/map_style/profiles/` and talks to it over a pipe (no debugging
port), then closes both. Phone views are 412 x 915 at 2x, the desktop view
1440 x 900 at 1x. The `pins12` views add stand-ins for the app's pins in their
four family colours and a selected pin with its amber halo. Profiles are kept;
delete `data/tmp/map_style/profiles` by its literal path when done.

## Updating upstream

Change the version of `@protomaps/basemaps` in `package.json`, run
`npm install`, then `node generate.mjs`: a layer that upstream renamed makes
the generator stop. Render the previews and compare before shipping. A tile
schema 5 would need the styles reviewed first (`PROTOMAPS_SCHEMA_MAJOR` in
`infra/tiles/version.sh`).

## Licences

@protomaps/basemaps is BSD-3-Clause (Protomaps LLC, Kelso Cartography); its
visual design is CC0; the v4 sprites derive from the MIT-licensed
tangrams/icons; the glyphs are Noto Sans under the SIL Open Font License 1.1.
The map data is OpenStreetMap (ODbL), credited in the source attribution of
both styles.

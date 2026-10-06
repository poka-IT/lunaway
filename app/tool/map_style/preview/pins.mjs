// What the previews download, pinned. Shared by fetch.mjs and render.mjs.

// The same go-pmtiles release as the server (infra/tiles/version.sh). The
// digests are those GitHub records for the macOS release assets.
export const PMTILES_VERSION = "1.31.2";
export const PMTILES_ZIPS = {
  arm64: {
    url: `https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles-${PMTILES_VERSION}_Darwin_arm64.zip`,
    sha256: "40528f7f616fcbf91207cd48c8fc023d213f6d86c0cbf1f748732803d1880f3d",
  },
  x64: {
    url: `https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles-${PMTILES_VERSION}_Darwin_x86_64.zip`,
    sha256: "1f0dc02eee6c58312dd6c509faee1b5c32f0596568af1bf51f1b034e7a88a65b",
  },
};

// Glyphs and sprites: the commit the server installs (infra/tiles/version.sh).
export const BASEMAPS_ASSETS_COMMIT = "028c18f713baecad011301ff7a69acc39bcc2ae7";

// The planet extracts the previews read. Each covers the views that use it at
// the deepest zoom they need; beyond its maxzoom MapLibre overzooms.
export const REGIONS = {
  // Mainland France for the country-wide view.
  france: { bbox: [-5.6, 41.2, 9.8, 51.2], maxzoom: 7 },
  // The northern French Alps around Annecy, Geneva and Chambery, for the
  // regional views.
  alps: { bbox: [5.0, 45.2, 7.2, 46.6], maxzoom: 10 },
  // Annecy, its lake and the A41 motorway, down to street level.
  annecy: { bbox: [5.8, 45.7, 6.4, 46.1], maxzoom: 15 },
};

// Loads MapLibre GL JS with the page, beside the Flutter engine rather than
// after it, and publishes it as the `maplibregl` global the maplibre_gl
// plugin reads (MapLibreJsSource.preloaded in lib/main.dart). A file of its
// own: the Content-Security-Policy of /app/ refuses inline scripts.
//
// Its Map differs from MapLibre's in one way. The plugin gives the map a new
// style when the theme turns (or the language changes) and asks MapLibre to
// load it whole, which drops every tile, image, source and layer of the app
// and freezes the page while they come back. Here the new style is diffed
// against the loaded one instead, with the app's own sources and layers
// carried over: a theme is a few hundred paint properties and a sprite,
// applied at the next frame. When MapLibre cannot diff, it loads the style
// whole as before and the app sets itself up again on `style.load`.
(function () {
  'use strict';

  // The app's own layers keep their place relative to the basemap's: each
  // goes before the basemap layer that followed it in the loaded style.
  function keepOwn(previous, next) {
    if (!previous || !previous.layers || !next || !next.layers) return next;
    var basemap = {};
    next.layers.forEach(function (layer) { basemap[layer.id] = true; });
    var sources = Object.assign({}, next.sources);
    Object.keys(previous.sources || {}).forEach(function (id) {
      if (!(id in sources)) sources[id] = previous.sources[id];
    });
    var before = {};
    var pending = [];
    previous.layers.forEach(function (layer) {
      if (basemap[layer.id]) {
        if (pending.length) {
          before[layer.id] = (before[layer.id] || []).concat(pending);
          pending = [];
        }
      } else if (layer.source === undefined || sources[layer.source]) {
        pending.push(layer);
      }
    });
    var layers = [];
    next.layers.forEach(function (layer) {
      (before[layer.id] || []).forEach(function (own) { layers.push(own); });
      layers.push(layer);
    });
    pending.forEach(function (own) { layers.push(own); });
    return Object.assign({}, next, { sources: sources, layers: layers });
  }

  // Marks, in the page's performance timeline, the first frame that draws
  // the places of the tiles: the startup budget of docs/architecture.md is
  // measured against it ("points visible").
  function markPlacesDrawn(map) {
    var loaded = false;
    function onData(e) {
      if (e.sourceId === 'lw-place-tiles' && e.isSourceLoaded && e.tile) loaded = true;
    }
    function onRender() {
      if (!loaded) return;
      map.off('sourcedata', onData);
      map.off('render', onRender);
      if (window.performance && performance.mark) performance.mark('lunaway-places-drawn');
    }
    map.on('sourcedata', onData);
    map.on('render', onRender);
  }

  var url = new URL('maplibre-gl/maplibre-gl.mjs', document.baseURI).href;
  import(url).then(function (lib) {
    var Base = lib.Map;
    class LunawayMap extends Base {
      constructor(options) {
        super(options);
        markPlacesDrawn(this);
      }

      setStyle(style, options) {
        // The first style, given to the constructor, loads as usual.
        if (!this.style || this.style._loaded === false) return super.setStyle(style, options);
        return super.setStyle(style, Object.assign({}, options, { diff: true, transformStyle: keepOwn }));
      }
    }
    globalThis.maplibregl = Object.assign({}, lib, { Map: LunawayMap });
  }).catch(function (error) {
    // The plugin waits for the global and reports its absence; this line
    // says why it never came.
    console.error('MapLibre GL JS did not load', error);
  });
})();

// The first map of the web app: drawn by the page itself with MapLibre GL
// JS while the Flutter engine downloads and starts, which takes seconds on a
// mobile network. It opens where the user left the map, with its basemap,
// its places and its filters (kept by the app in localStorage under
// "lunaway.premap", lib/features/map/presentation/premap_spec.dart), or on
// France at a first visit. It can be moved and zoomed. Once the app's own map
// has drawn the same view, the app takes the camera from it and asks it to go
// (window.lunawayPremap.handOver()); it fades out. A file of its own: the
// Content-Security-Policy of /app/ refuses inline scripts.
(function () {
  'use strict';

  // A copy of premapDefaults() in premap_spec.dart, kept equal to it by
  // test/unit/premap_test.dart (UPDATE_PREMAP=1 rewrites it).
  var DEFAULTS = /* BEGIN DEFAULTS */ {"v":1,"base":"https://tiles.lunaway.net","places":"https://api.lunaway.net/places/tiles.json","bounds":[-5.5,41.2,9.9,51.3],"maxZoom":10.0,"pinZoom":10.0,"layers":{"aube":[{"id":"lw-place-dots","type":"circle","source":"lw-place-tiles","source-layer":"place_dots","maxzoom":10.0,"filter":["has","kind"],"layout":{"circle-sort-key":["match",["get","night"],"allowed",4,"tolerated",3,"day_only",1,"forbidden",0,"unknown",2,2]},"paint":{"circle-color":["match",["get","kind"],["motorhome_area","parking","rest_area","picnic_area"],"#2d5da8",["campsite","farm","homestay"],"#8a4b82",["nature","off_road"],"#4a8a43",["service_area","extra_service"],"#237f89","#237f89"],"circle-radius":["interpolate",["linear"],["zoom"],3,1.6,6,2.6,9,3.8,12,5],"circle-stroke-width":["interpolate",["linear"],["zoom"],3,0.3,8,0.9,12,1.4],"circle-stroke-color":"#fdf1db","circle-opacity":0.95}},{"id":"lw-place-pin-dots","type":"circle","source":"lw-place-tiles","source-layer":"places","minzoom":10.0,"filter":["has","kind"],"layout":{"circle-sort-key":["match",["get","night"],"allowed",4,"tolerated",3,"day_only",1,"forbidden",0,"unknown",2,2]},"paint":{"circle-color":["match",["get","kind"],["motorhome_area","parking","rest_area","picnic_area"],"#2d5da8",["campsite","farm","homestay"],"#8a4b82",["nature","off_road"],"#4a8a43",["service_area","extra_service"],"#237f89","#237f89"],"circle-radius":["interpolate",["linear"],["zoom"],3,1.6,6,2.6,9,3.8,12,5],"circle-stroke-width":["interpolate",["linear"],["zoom"],3,0.3,8,0.9,12,1.4],"circle-stroke-color":"#fdf1db","circle-opacity":0.95}},{"id":"lw-place-pins","type":"symbol","source":"lw-place-tiles","source-layer":"places","minzoom":10.0,"filter":["has","kind"],"layout":{"icon-image":["match",["get","kind"],"motorhome_area",["match",["get","night"],"allowed","pin-motorhomeArea-allowed","tolerated","pin-motorhomeArea-tolerated","day_only","pin-motorhomeArea-dayOnly","forbidden","pin-motorhomeArea-forbidden","unknown","pin-motorhomeArea-unknown","pin-motorhomeArea-unknown"],"service_area",["match",["get","night"],"allowed","pin-serviceArea-allowed","tolerated","pin-serviceArea-tolerated","day_only","pin-serviceArea-dayOnly","forbidden","pin-serviceArea-forbidden","unknown","pin-serviceArea-unknown","pin-serviceArea-unknown"],"campsite",["match",["get","night"],"allowed","pin-campsite-allowed","tolerated","pin-campsite-tolerated","day_only","pin-campsite-dayOnly","forbidden","pin-campsite-forbidden","unknown","pin-campsite-unknown","pin-campsite-unknown"],"parking",["match",["get","night"],"allowed","pin-parking-allowed","tolerated","pin-parking-tolerated","day_only","pin-parking-dayOnly","forbidden","pin-parking-forbidden","unknown","pin-parking-unknown","pin-parking-unknown"],"nature",["match",["get","night"],"allowed","pin-nature-allowed","tolerated","pin-nature-tolerated","day_only","pin-nature-dayOnly","forbidden","pin-nature-forbidden","unknown","pin-nature-unknown","pin-nature-unknown"],"rest_area",["match",["get","night"],"allowed","pin-restArea-allowed","tolerated","pin-restArea-tolerated","day_only","pin-restArea-dayOnly","forbidden","pin-restArea-forbidden","unknown","pin-restArea-unknown","pin-restArea-unknown"],"picnic_area",["match",["get","night"],"allowed","pin-picnicArea-allowed","tolerated","pin-picnicArea-tolerated","day_only","pin-picnicArea-dayOnly","forbidden","pin-picnicArea-forbidden","unknown","pin-picnicArea-unknown","pin-picnicArea-unknown"],"farm",["match",["get","night"],"allowed","pin-farm-allowed","tolerated","pin-farm-tolerated","day_only","pin-farm-dayOnly","forbidden","pin-farm-forbidden","unknown","pin-farm-unknown","pin-farm-unknown"],"homestay",["match",["get","night"],"allowed","pin-homestay-allowed","tolerated","pin-homestay-tolerated","day_only","pin-homestay-dayOnly","forbidden","pin-homestay-forbidden","unknown","pin-homestay-unknown","pin-homestay-unknown"],"off_road",["match",["get","night"],"allowed","pin-offRoad-allowed","tolerated","pin-offRoad-tolerated","day_only","pin-offRoad-dayOnly","forbidden","pin-offRoad-forbidden","unknown","pin-offRoad-unknown","pin-offRoad-unknown"],"extra_service",["match",["get","night"],"allowed","pin-extraService-allowed","tolerated","pin-extraService-tolerated","day_only","pin-extraService-dayOnly","forbidden","pin-extraService-forbidden","unknown","pin-extraService-unknown","pin-extraService-unknown"],"pin-extraService-unknown"],"icon-size":["interpolate",["linear"],["zoom"],6,0.72,12,1.0],"icon-anchor":"bottom","icon-allow-overlap":false,"icon-ignore-placement":false,"icon-padding":0,"symbol-sort-key":["match",["get","night"],"allowed",-4,"tolerated",-3,"day_only",-1,"forbidden",0,"unknown",-2,-2]}}],"minuit":[{"id":"lw-place-dots","type":"circle","source":"lw-place-tiles","source-layer":"place_dots","maxzoom":10.0,"filter":["has","kind"],"layout":{"circle-sort-key":["match",["get","night"],"allowed",4,"tolerated",3,"day_only",1,"forbidden",0,"unknown",2,2]},"paint":{"circle-color":["match",["get","kind"],["motorhome_area","parking","rest_area","picnic_area"],"#2d5da8",["campsite","farm","homestay"],"#8a4b82",["nature","off_road"],"#4a8a43",["service_area","extra_service"],"#237f89","#237f89"],"circle-radius":["interpolate",["linear"],["zoom"],3,1.6,6,2.6,9,3.8,12,5],"circle-stroke-width":["interpolate",["linear"],["zoom"],3,0.3,8,0.9,12,1.4],"circle-stroke-color":"#061f43","circle-opacity":0.95}},{"id":"lw-place-pin-dots","type":"circle","source":"lw-place-tiles","source-layer":"places","minzoom":10.0,"filter":["has","kind"],"layout":{"circle-sort-key":["match",["get","night"],"allowed",4,"tolerated",3,"day_only",1,"forbidden",0,"unknown",2,2]},"paint":{"circle-color":["match",["get","kind"],["motorhome_area","parking","rest_area","picnic_area"],"#2d5da8",["campsite","farm","homestay"],"#8a4b82",["nature","off_road"],"#4a8a43",["service_area","extra_service"],"#237f89","#237f89"],"circle-radius":["interpolate",["linear"],["zoom"],3,1.6,6,2.6,9,3.8,12,5],"circle-stroke-width":["interpolate",["linear"],["zoom"],3,0.3,8,0.9,12,1.4],"circle-stroke-color":"#061f43","circle-opacity":0.95}},{"id":"lw-place-pins","type":"symbol","source":"lw-place-tiles","source-layer":"places","minzoom":10.0,"filter":["has","kind"],"layout":{"icon-image":["match",["get","kind"],"motorhome_area",["match",["get","night"],"allowed","pin-motorhomeArea-allowed","tolerated","pin-motorhomeArea-tolerated","day_only","pin-motorhomeArea-dayOnly","forbidden","pin-motorhomeArea-forbidden","unknown","pin-motorhomeArea-unknown","pin-motorhomeArea-unknown"],"service_area",["match",["get","night"],"allowed","pin-serviceArea-allowed","tolerated","pin-serviceArea-tolerated","day_only","pin-serviceArea-dayOnly","forbidden","pin-serviceArea-forbidden","unknown","pin-serviceArea-unknown","pin-serviceArea-unknown"],"campsite",["match",["get","night"],"allowed","pin-campsite-allowed","tolerated","pin-campsite-tolerated","day_only","pin-campsite-dayOnly","forbidden","pin-campsite-forbidden","unknown","pin-campsite-unknown","pin-campsite-unknown"],"parking",["match",["get","night"],"allowed","pin-parking-allowed","tolerated","pin-parking-tolerated","day_only","pin-parking-dayOnly","forbidden","pin-parking-forbidden","unknown","pin-parking-unknown","pin-parking-unknown"],"nature",["match",["get","night"],"allowed","pin-nature-allowed","tolerated","pin-nature-tolerated","day_only","pin-nature-dayOnly","forbidden","pin-nature-forbidden","unknown","pin-nature-unknown","pin-nature-unknown"],"rest_area",["match",["get","night"],"allowed","pin-restArea-allowed","tolerated","pin-restArea-tolerated","day_only","pin-restArea-dayOnly","forbidden","pin-restArea-forbidden","unknown","pin-restArea-unknown","pin-restArea-unknown"],"picnic_area",["match",["get","night"],"allowed","pin-picnicArea-allowed","tolerated","pin-picnicArea-tolerated","day_only","pin-picnicArea-dayOnly","forbidden","pin-picnicArea-forbidden","unknown","pin-picnicArea-unknown","pin-picnicArea-unknown"],"farm",["match",["get","night"],"allowed","pin-farm-allowed","tolerated","pin-farm-tolerated","day_only","pin-farm-dayOnly","forbidden","pin-farm-forbidden","unknown","pin-farm-unknown","pin-farm-unknown"],"homestay",["match",["get","night"],"allowed","pin-homestay-allowed","tolerated","pin-homestay-tolerated","day_only","pin-homestay-dayOnly","forbidden","pin-homestay-forbidden","unknown","pin-homestay-unknown","pin-homestay-unknown"],"off_road",["match",["get","night"],"allowed","pin-offRoad-allowed","tolerated","pin-offRoad-tolerated","day_only","pin-offRoad-dayOnly","forbidden","pin-offRoad-forbidden","unknown","pin-offRoad-unknown","pin-offRoad-unknown"],"extra_service",["match",["get","night"],"allowed","pin-extraService-allowed","tolerated","pin-extraService-tolerated","day_only","pin-extraService-dayOnly","forbidden","pin-extraService-forbidden","unknown","pin-extraService-unknown","pin-extraService-unknown"],"pin-extraService-unknown"],"icon-size":["interpolate",["linear"],["zoom"],6,0.72,12,1.0],"icon-anchor":"bottom","icon-allow-overlap":false,"icon-ignore-placement":false,"icon-padding":0,"symbol-sort-key":["match",["get","night"],"allowed",-4,"tolerated",-3,"day_only",-1,"forbidden",0,"unknown",-2,-2]}}]},"frame":{"mediumFrom":600.0,"expandedFrom":840.0,"railFolded":[92.0,76.0],"railExtended":[232.0,200.0],"pane":[380.0,420.0],"paneWideFrom":1280.0,"overlay":[132.0,116.0],"listPeek":170.0,"dock":88.0,"fit":16.0}} /* END DEFAULTS */;

  var container = document.getElementById('premap');
  if (!container || !DEFAULTS || !window.fetch) return;

  // The app took too long or failed to draw its map: the page gives way all
  // the same, rather than hide the app for good. Armed now, since the app's
  // first frame may come before this map's style.
  var gone = false;
  var giveUp = null;
  window.addEventListener('flutter-first-frame', function () {
    giveUp = setTimeout(function () { handOver(); }, 15000);
  });

  // Only the map has a map to show: a link to the profile or the favourites
  // waits for the app.
  var route = (location.hash || '').replace(/^#/, '');
  if (route !== '' && route !== '/' && route.indexOf('/map') !== 0) return;

  var saved = null;
  try {
    saved = JSON.parse(localStorage.getItem('lunaway.premap') || 'null');
  } catch (e) {
    saved = null;
  }
  // What the app kept, only as the app writes it: the same hosts, a
  // language code, a view on the map, at most the zoom the app keeps.
  function valid(s) {
    return !!s && s.v === DEFAULTS.v && Array.isArray(s.layers) &&
      s.base === DEFAULTS.base && s.places === DEFAULTS.places &&
      (s.style === 'aube' || s.style === 'minuit') &&
      typeof s.lang === 'string' && /^[a-z]{2,3}$/.test(s.lang) &&
      Array.isArray(s.center) && s.center.length === 2 &&
      typeof s.center[0] === 'number' && isFinite(s.center[0]) && Math.abs(s.center[0]) <= 180 &&
      typeof s.center[1] === 'number' && isFinite(s.center[1]) && Math.abs(s.center[1]) <= 85 &&
      typeof s.zoom === 'number' && isFinite(s.zoom) && s.zoom >= 0 &&
      s.layers.every(function (l) { return l && typeof l === 'object' && l.source === 'lw-place-tiles'; });
  }
  if (!valid(saved)) saved = null;

  // Where the app's map will stand in this window, and the room its first
  // fit leaves (premapFrame in premap_spec.dart): this map fills the window
  // but frames its view there, so that nothing moves when the app takes
  // over. The app keeps what it measured; a window of another size, or a
  // first visit, gets the layout's rules (DEFAULTS.frame).
  function measuredFrame() {
    var f = null;
    try {
      f = JSON.parse(localStorage.getItem('lunaway.premapFrame') || 'null');
    } catch (e) {
      return null;
    }
    if (!f || typeof f !== 'object') return null;
    var keys = ['w', 'h', 'l', 't', 'r', 'b', 'pl', 'pt', 'pr', 'pb'];
    for (var i = 0; i < keys.length; i++) {
      var v = f[keys[i]];
      if (typeof v !== 'number' || !isFinite(v) || v < 0 || v > 10000) return null;
    }
    if (Math.abs(f.w - innerWidth) > 1 || Math.abs(f.h - innerHeight) > 1) return null;
    return f;
  }
  // The safe areas of the window (a phone's notch, its home bar), which
  // the app reads as its padding.
  function safeAreas() {
    var probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;' +
      'padding:env(safe-area-inset-top) env(safe-area-inset-right) ' +
      'env(safe-area-inset-bottom) env(safe-area-inset-left)';
    document.body.appendChild(probe);
    var s = getComputedStyle(probe);
    var out = {
      t: parseFloat(s.paddingTop) || 0, r: parseFloat(s.paddingRight) || 0,
      b: parseFloat(s.paddingBottom) || 0, l: parseFloat(s.paddingLeft) || 0
    };
    probe.remove();
    return out;
  }
  function modelFrame() {
    var m = DEFAULTS.frame;
    var w = innerWidth;
    var safe = safeAreas();
    // The desktop look of pointerDensity (lib/core/layout/pointer_input.dart):
    // a desktop system, in a window wider than a phone's.
    var ua = navigator.userAgent || '';
    var desktop = !/Android|iPhone|iPad|iPod/.test(ua) &&
      !(/Mac/.test(navigator.platform || '') && navigator.maxTouchPoints > 2);
    var mouse = desktop && w >= m.mediumFrom ? 1 : 0;
    var f = { l: 0, t: 0, r: 0, b: 0, pl: m.fit, pt: m.fit, pr: m.fit, pb: m.fit };
    if (w < m.mediumFrom) {
      // A phone: the map under everything, the search and the chips above,
      // the list's sheet at rest above the dock below.
      f.pt += safe.t + m.overlay[0];
      f.pb += m.listPeek + m.dock + safe.b;
    } else if (w < m.expandedFrom) {
      // The folded rail, the search and the chips over the map.
      f.l = m.railFolded[mouse] + safe.l;
      f.pt += safe.t + m.overlay[mouse];
    } else {
      // The extended rail and the list's pane beside the map.
      f.l = m.railExtended[mouse] + safe.l + m.pane[w >= m.paneWideFrom ? 1 : 0];
    }
    return f;
  }
  // A frame that leaves the view less than 40 px either way (a very short
  // window under the search and the sheet) would have MapLibre fit nothing
  // and show the world: the whole window then, with a margin.
  function roomy(f) {
    return !!f &&
      innerWidth - f.l - f.r - f.pl - f.pr >= 40 &&
      innerHeight - f.t - f.b - f.pt - f.pb >= 40;
  }
  var frame = measuredFrame();
  if (!roomy(frame)) frame = modelFrame();
  if (!roomy(frame)) frame = { l: 0, t: 0, r: 0, b: 0, pl: 24, pt: 24, pr: 24, pb: 24 };

  // A first visit: the day's basemap by day, the night's after dark (the
  // app then turns it by the sun), labels in the browser's language.
  var hour = new Date().getHours();
  var styleName = saved ? saved.style : (hour >= 7 && hour < 20 ? 'aube' : 'minuit');
  var lang = saved ? saved.lang : ((navigator.language || '').toLowerCase().indexOf('fr') === 0 ? 'fr' : 'en');
  var base = saved ? saved.base : DEFAULTS.base;
  var places = saved ? saved.places : DEFAULTS.places;
  var layers = saved ? saved.layers : DEFAULTS.layers[styleName];
  if (styleName !== 'aube' && styleName !== 'minuit') return;

  var map = null;
  var pendingPlace = null;
  var styleUrl = new URL('assets/assets/map/styles/' + styleName + '.json', document.baseURI).href;
  var libUrl = new URL('maplibre-gl/maplibre-gl.mjs', document.baseURI).href;

  // The tokens the style generator leaves (BasemapTokens in
  // basemap_style.dart), filled as fillBasemapStyle fills them.
  function filled(text) {
    var root = base.replace(/\/+$/, '');
    return text
      .split('__LUNAWAY_TILES__').join(root + '/planet.json')
      .split('__LUNAWAY_GLYPHS__').join(root + '/fonts')
      .split('__LUNAWAY_SPRITE__').join(root + '/sprites/protomaps-v4')
      .split('__LUNAWAY_LANG__').join(lang);
  }

  // The places first, the basemap once they are drawn (or after 1.5 s):
  // the basemap's tiles of a country view weigh about five times the
  // places' and, fetched together, take the mobile link from them.
  var full = null;
  var basemap = false;
  function addBasemap() {
    if (basemap || gone || !map) return;
    basemap = true;
    map.setStyle(full);
  }

  function markPlacesDrawn() {
    var loaded = false;
    map.on('sourcedata', function onData(e) {
      if (e.sourceId === 'lw-place-tiles' && e.isSourceLoaded && e.tile) {
        loaded = true;
        map.off('sourcedata', onData);
      }
    });
    map.on('render', function onRender() {
      if (!loaded) return;
      map.off('render', onRender);
      if (window.performance && performance.mark) performance.mark('lunaway-premap-places-drawn');
      addBasemap();
    });
  }

  function handOver() {
    if (gone) return;
    gone = true;
    if (giveUp) clearTimeout(giveUp);
    container.classList.add('done');
    setTimeout(function () {
      if (map) map.remove();
      if (container.parentNode) container.parentNode.removeChild(container);
    }, 300);
  }

  window.lunawayPremap = {
    // The camera the user may have moved meanwhile, for the app's map to
    // open on; null before the map exists. Given a point of the window
    // (x, y), the place drawn there: the centre of a map that stands
    // around that point and draws the same view.
    camera: function (x, y) {
      if (!map || gone) return null;
      var c = typeof x === 'number' && typeof y === 'number' && isFinite(x) && isFinite(y)
        ? map.unproject([x, y])
        : map.getCenter();
      return { lat: c.lat, lon: c.lng, zoom: map.getZoom() };
    },
    // The place clicked on this map that the app has to open, once: its
    // tile properties and its [lon, lat].
    takePlace: function () {
      var place = pendingPlace;
      pendingPlace = null;
      return place;
    },
    handOver: handOver
  };

  Promise.all([
    fetch(styleUrl).then(function (r) { return r.ok ? r.text() : Promise.reject(r.status); }),
    import(libUrl)
  ]).then(function (loaded) {
    if (gone) return;
    var style = JSON.parse(filled(loaded[0]));
    var lib = loaded[1];
    style.sources['lw-place-tiles'] = { type: 'vector', url: places };
    layers.forEach(function (layer) { style.layers.push(layer); });
    var options = {
      container: container,
      style: style,
      attributionControl: { compact: true },
      dragRotate: false,
      pitchWithRotate: false,
      touchPitch: false
    };
    if (saved) {
      options.center = saved.center;
      options.zoom = Math.min(saved.zoom, DEFAULTS.maxZoom);
    } else {
      // France where the app fits it: inside its map, clear of what floats
      // over it.
      var b = DEFAULTS.bounds;
      options.bounds = [[b[0], b[1]], [b[2], b[3]]];
      options.fitBoundsOptions = {
        padding: {
          left: frame.l + frame.pl, top: frame.t + frame.pt,
          right: frame.r + frame.pr, bottom: frame.b + frame.pb
        }
      };
    }
    full = style;
    options.style = Object.assign({}, style, {
      sources: { 'lw-place-tiles': style.sources['lw-place-tiles'] },
      layers: style.layers.filter(function (l) {
        return l.type === 'background' || l.source === 'lw-place-tiles';
      })
    });
    map = new lib.Map(options);
    if (saved) {
      // The view kept is the centre of the app's map: drawn where that map
      // will have its centre, not in the middle of the window.
      var cx = (frame.l + innerWidth - frame.r) / 2;
      var cy = (frame.t + innerHeight - frame.b) / 2;
      map.jumpTo({ center: map.unproject([innerWidth - cx, innerHeight - cy]) });
    }
    setTimeout(addBasemap, 1500);
    if (window.lunawayLoadMissingPins) window.lunawayLoadMissingPins(map);
    // Its places answer the pointer as the app's do (lunawayHits in
    // lunaway_maplibre.js): a dot brings the map closer around it, a
    // place waits for the app, which opens it when it takes over.
    var hits = window.lunawayHits;
    if (hits) {
      hits.hover(map);
      map.on('click', function (e) {
        var hit = hits.pick(map, e.point);
        if (!hit || !hit.coordinates) return;
        if (hit.properties.id !== undefined) {
          pendingPlace = { properties: hit.properties, coordinates: hit.coordinates };
        } else {
          map.easeTo({ center: hit.coordinates, zoom: Math.max(map.getZoom() + 3, DEFAULTS.pinZoom + 0.5) });
        }
      });
    }
    markPlacesDrawn();
    map.once('style.load', function () { container.classList.add('shown'); });
  }).catch(function (error) {
    console.info('The first map was not drawn', error);
    handOver();
  });
})();

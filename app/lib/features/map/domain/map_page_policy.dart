/// What the desktop map's web view does with a navigation.
enum MapPageNavigation {
  /// Our own map page: load it.
  allow,

  /// A web link (the basemap's attribution): open it in the browser, never
  /// in the web view that holds the app's bridge.
  openExternally,

  /// Anything else: refused.
  block,
}

/// The page the web view must hold: the map page shipped in the app's
/// assets. Only a file URL ending with this path qualifies the first time;
/// after that, only the very URL that loaded.
const mapPagePath = '/assets/map/map.html';

/// Decides a navigation of the desktop map's web view to [target]. [mapPage]
/// is the URL the map page loaded from, once known. The bridge to the app is
/// injected only into that page, so everything else is kept out of the
/// view.
MapPageNavigation decideMapNavigation(Uri? target, {required Uri? mapPage}) {
  if (target == null) return MapPageNavigation.block;
  if (mapPage != null ? isMapPage(target, mapPage: mapPage) : _isShippedMapPage(target)) {
    return MapPageNavigation.allow;
  }
  if ((target.scheme == 'https' || target.scheme == 'http') && target.host.isNotEmpty) {
    return MapPageNavigation.openExternally;
  }
  return MapPageNavigation.block;
}

/// Whether [url] is the map page that loaded from [mapPage] (a fragment
/// change stays on the page).
bool isMapPage(Uri? url, {required Uri mapPage}) =>
    url != null &&
    url.scheme == mapPage.scheme &&
    url.host == mapPage.host &&
    url.port == mapPage.port &&
    url.path == mapPage.path &&
    url.query == mapPage.query;

bool _isShippedMapPage(Uri url) =>
    url.scheme == 'file' && url.query.isEmpty && url.path.endsWith(mapPagePath);

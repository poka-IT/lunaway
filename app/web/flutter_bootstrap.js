{{flutter_js}}
{{flutter_build_config}}

// The web engine downloads a Noto font for any character that neither the
// app's fonts nor Roboto (bundled by --no-web-resources-cdn) can draw, from
// fonts.gstatic.com unless told otherwise. The Content-Security-Policy of
// /app/ only allows our own origin, and the app talks to no third party, so
// the engine reads them from web/fonts/, which mirrors the paths it asks for.
//
// CanvasKit is named here so that tool/web/fingerprint.py can move it to a
// directory named after its content, which /app/ serves immutable.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: new URL('fonts/', document.baseURI).href,
    canvasKitBaseUrl: 'canvaskit/',
  },
});

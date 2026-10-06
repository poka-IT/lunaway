// Fades out the loading screen of index.html once Flutter has drawn its first
// frame. A file of its own because the Content-Security-Policy of /app/
// (script-src 'self') refuses inline scripts: left inline, the splash would
// stay on top of the app and swallow every click.
window.addEventListener('flutter-first-frame', function () {
  var splash = document.getElementById('splash');
  if (!splash) return;
  splash.classList.add('done');
  setTimeout(function () { splash.remove(); }, 400);
});

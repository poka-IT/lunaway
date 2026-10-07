// Registers the service worker that keeps the app's files for the next
// visit (lunaway_sw.js, written for each build by
// app/tool/web/service_worker.py), a few seconds after the app's first
// frame: its downloads must not compete with the first visit's engine and
// map (the page's load event may come before the engine is fetched). A build
// without the worker (a developer's) registers nothing. A file of its own:
// the Content-Security-Policy of /app/ refuses inline scripts.
(function () {
  'use strict';
  if (!('serviceWorker' in navigator) || !window.isSecureContext) return;
  function register() {
    navigator.serviceWorker.register('lunaway_sw.js').catch(function () {});
  }
  function later() { setTimeout(register, 5000); }
  // This script loads async: the engine may have drawn its view already.
  if (document.querySelector('flutter-view')) {
    later();
  } else {
    window.addEventListener('flutter-first-frame', later);
  }
})();

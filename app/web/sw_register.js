// Registers the service worker that keeps the app's files for the next
// visit (lunaway_sw.js, written for each build by
// app/tool/web/service_worker.py), a few seconds after the page has loaded:
// its downloads must not compete with the first visit's map. A build
// without the worker (a developer's) registers nothing. A file of its own:
// the Content-Security-Policy of /app/ refuses inline scripts.
(function () {
  'use strict';
  if (!('serviceWorker' in navigator) || !window.isSecureContext) return;
  function register() {
    navigator.serviceWorker.register('lunaway_sw.js').catch(function () {});
  }
  function later() { setTimeout(register, 5000); }
  if (document.readyState === 'complete') {
    later();
  } else {
    window.addEventListener('load', later);
  }
})();

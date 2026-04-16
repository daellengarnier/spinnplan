// Spinnplan Service Worker
// Note: Push notifications handled by OneSignalSDKWorker.js
const CACHE_NAME = 'spinnplan-v2';
const STATIC = ['/'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(STATIC)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys =>
    Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
  ));
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  // Don't cache API calls
  if (e.request.url.includes('supabase') || e.request.url.includes('onesignal')) return;
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});

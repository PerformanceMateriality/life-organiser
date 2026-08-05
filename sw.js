// Self-destroying service worker.
// A previous version cached the app shell; this version removes that cache and
// unregisters itself so the app always loads fresh during development.
// (Offline caching will return as a deliberate feature in a later phase.)
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    clients.forEach((c) => c.navigate(c.url));
  })());
});

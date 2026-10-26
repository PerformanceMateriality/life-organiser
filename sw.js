// Life Organiser service worker — build 26.
//
// Two jobs: web push, and (since build 21) opening the app without a connection.
//
// Offline is NETWORK-FIRST, never cache-first. An early version served the app shell from
// cache and kept showing stale builds, so here the network always wins when it answers:
// with signal you get the newest build and live data, exactly as before. Only when the
// network fails (or takes over 6 s and a saved copy exists) does the last good copy step in.
//   lo-shell  the app's own files (index.html, font, icons, manifest), keyed without ?v=
//   lo-data   Supabase REST GETs, one copy per table — the last answer that came back
// Writes never pass through here: the page queues them in its own outbox (index.html).
// Signing out deletes lo-data.
//
// The server owns the message text. This worker renders whatever the Edge Function
// sends and composes nothing itself.

const SW_VERSION = 'build26';
const FALLBACK = {
  title: 'Life Organiser',
  body: 'You have something open today.',
};

self.addEventListener('install', () => {
  // Take over immediately — a notification tapped now should not wait for a reload.
  self.skipWaiting();
});

const SHELL = 'lo-shell';
const DATA = 'lo-data';

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Clear anything that isn't ours (the pre-build-11 caching worker's leftovers).
      if (self.caches) {
        const keys = await caches.keys();
        await Promise.all(keys.filter((k) => k !== SHELL && k !== DATA).map((k) => caches.delete(k)));
      }
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin === self.location.origin) {
    // The worker's own file is fetched by the browser's update check; leave it alone.
    if (url.pathname.endsWith('/sw.js')) return;
    event.respondWith(networkFirst(req, SHELL, url.origin + url.pathname));
  } else if (/\.supabase\.co$/.test(url.hostname) && url.pathname.startsWith('/rest/v1/')) {
    event.respondWith(networkFirst(req, DATA, req.url));
  }
});

async function networkFirst(req, cacheName, key) {
  const cache = await caches.open(cacheName);
  const path = new URL(key).pathname;
  // Any earlier copy of the same file / table, whatever its query string.
  const saved = (await cache.match(key)) || (await cache.match(key, { ignoreSearch: true }));
  const fromNet = fetch(req).then(async (res) => {
    if (res && res.ok) {
      const copy = res.clone();
      // One copy per path: drop older query variants (e.g. yesterday's "since" date).
      for (const old of await cache.keys()) if (new URL(old.url).pathname === path && old.url !== key) await cache.delete(old);
      await cache.put(key, copy);
    }
    return res;
  });
  try {
    if (!saved) return await fromNet;
    // A copy exists: give the network 6 s, then fall back so a weak gym signal can't hang the app.
    return await Promise.race([fromNet, new Promise((_, rej) => setTimeout(() => rej(new Error('slow')), 6000))]);
  } catch (e) {
    if (saved) return saved;
    return new Response('offline', { status: 503, statusText: 'offline' });
  }
}

self.addEventListener('push', (event) => {
  let payload = {};
  if (event.data) {
    // Push services can deliver an empty or non-JSON body; never let that throw,
    // because a throw here means no notification at all.
    try {
      payload = event.data.json() || {};
    } catch (e) {
      try {
        payload = { body: event.data.text() };
      } catch (e2) {
        payload = {};
      }
    }
  }

  const title = payload.title || FALLBACK.title;
  const body = payload.body || FALLBACK.body;
  // One notification per slot: a second morning nudge replaces the first rather than
  // stacking up. `renotify` still alerts, so a replacement isn't silent.
  const tag = payload.tag || (payload.slot ? 'lo-' + payload.slot : 'lo-reminder');

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      tag,
      renotify: true,
      icon: payload.icon || 'icon-192.png',
      badge: payload.badge || 'icon-192.png',
      data: { url: payload.url || './', slot: payload.slot || null },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || './';

  event.waitUntil(
    (async () => {
      const url = new URL(target, self.location.href).href;
      const clients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      // Prefer an app window that is already open — tapping a nudge should land in the
      // running app, not a second copy of it.
      for (const client of clients) {
        if (client.url.startsWith(self.registration.scope) && 'focus' in client) {
          if ('navigate' in client && client.url !== url) {
            try {
              await client.navigate(url);
            } catch (e) {
              /* cross-origin or not allowed — focusing is still the right outcome */
            }
          }
          return client.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })(),
  );
});

// Small message channel so the page can confirm which worker it is actually talking to
// (the reminders screen uses this to tell "no worker yet" from "worker from an older
// build"), and can render a local test notification through the worker — on iOS
// `new Notification()` does not exist, so everything must go through the registration.
self.addEventListener('message', (event) => {
  const msg = event.data || {};
  const reply = (data) => {
    if (event.ports && event.ports[0]) event.ports[0].postMessage(data);
    else if (event.source && event.source.postMessage) event.source.postMessage(data);
  };

  if (msg.type === 'ping') {
    reply({ type: 'pong', version: SW_VERSION });
    return;
  }
  if (msg.type === 'show') {
    event.waitUntil(
      self.registration.showNotification(msg.title || FALLBACK.title, {
        body: msg.body || '',
        tag: msg.tag || 'lo-local',
        renotify: true,
        icon: 'icon-192.png',
        badge: 'icon-192.png',
        data: { url: './', slot: null },
      }),
    );
    return;
  }
  if (msg.type === 'skipWaiting') self.skipWaiting();
});

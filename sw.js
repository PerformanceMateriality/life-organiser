// Life Organiser service worker — build 14.
//
// Its only job is web push. There is DELIBERATELY NO `fetch` HANDLER: the app must
// always load fresh from the network. An earlier version cached the app shell and kept
// serving stale builds during development, which is why it was replaced by a
// self-destroying worker. This one comes back only because push requires a worker —
// offline caching returns later as its own feature, with a write queue, not as a
// side effect of notifications.
//
// The server owns the message text. This worker renders whatever the Edge Function
// sends and composes nothing itself.

const SW_VERSION = 'build14';
const FALLBACK = {
  title: 'Life Organiser',
  body: 'You have something open today.',
};

self.addEventListener('install', () => {
  // Take over immediately — a notification tapped now should not wait for a reload.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      // Clear anything the pre-build-11 caching worker left behind. Nothing is cached
      // from here on, so this is a one-time sweep rather than cache management.
      if (self.caches) {
        const keys = await caches.keys();
        await Promise.all(keys.map((k) => caches.delete(k)));
      }
      await self.clients.claim();
    })(),
  );
});

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

const CACHE_NAME = 'hankkut-routine-v4';
const ASSETS = [
  '/youthit-routine/',
  '/youthit-routine/index.html',
  '/youthit-routine/manifest.json',
  '/youthit-routine/icon-192.png',
  '/youthit-routine/icon-512.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', e => {
  if (!e.request.url.startsWith(self.location.origin)) return;
  e.respondWith(
    fetch(e.request)
      .then(res => {
        const clone = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});

self.addEventListener('push', e => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; }
  catch { data = { title: '한끗루틴', body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(data.title || '한끗루틴', {
    body: data.body || '',
    icon: '/youthit-routine/icon-192.png',
    badge: '/youthit-routine/icon-192.png',
    data: { url: data.url || '/youthit-routine/' },
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/youthit-routine/';
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) {
        if (c.url.includes('/youthit-routine') && 'focus' in c) return c.focus();
      }
      return clients.openWindow(url);
    })
  );
});

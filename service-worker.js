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
  const tabMatch = url.match(/[?&]tab=(\w+)/);
  const tab = tabMatch ? tabMatch[1] : null;
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) {
        if (c.url.includes('/youthit-routine') && 'focus' in c) {
          // 앱이 이미 열려있으면 postMessage로 탭 전환을 알려줌 — Client.navigate()는 iOS
          // Safari 등 일부 환경에서 안정적으로 동작 안 해서(그냥 focus만 되고 탭은 그대로
          // "홈"에 남아있는 것처럼 보이던 문제), 새로고침 없이 페이지 쪽에서 직접 탭을
          // 바꾸도록 위임
          if (tab) c.postMessage({ type: 'notif-navigate', tab });
          return c.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});

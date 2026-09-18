// Take over as soon as a new version is served instead of waiting for every
// app window/PWA instance to close — otherwise SW behavior changes (e.g.
// showWhenFocused) don't reach an installed PWA until it's fully quit.
self.addEventListener('install', function () {
  self.skipWaiting();
});
self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

// Persist a notification click so the page can act on it even when there was no
// live page to receive the postMessage — the common mobile case, where the
// "closed" PWA is actually killed and the tap cold-relaunches it at the manifest
// start_url instead of the notification's target url. The page drains this store
// on load / resume and routes in-app. IndexedDB is shared origin-wide with the
// page and survives the SW being evicted (unlike SW globals, which iOS discards).
function openPushDb() {
  return new Promise(function (resolve, reject) {
    var req = indexedDB.open('floot-push', 1);
    req.onupgradeneeded = function () {
      try { req.result.createObjectStore('clicks', { keyPath: 'id' }); } catch (e) {}
    };
    req.onsuccess = function () { resolve(req.result); };
    req.onerror = function () { reject(req.error); };
  });
}

// Delete clicks older than a few minutes so an app whose page code drains via
// the postMessage and never reads IndexedDB (older builds) can't accumulate
// entries forever. Runs in the same transaction as each write.
function prunePendingClicks(store, now) {
  try {
    var cutoff = now - 5 * 60 * 1000;
    var req = store.openCursor();
    req.onsuccess = function () {
      var cursor = req.result;
      if (!cursor) return;
      var v = cursor.value;
      if (!v || typeof v.ts !== 'number' || v.ts < cutoff) cursor.delete();
      cursor.continue();
    };
  } catch (e) {}
}

function persistPendingClick(entry) {
  return openPushDb().then(function (db) {
    return new Promise(function (resolve) {
      try {
        var tx = db.transaction('clicks', 'readwrite');
        var store = tx.objectStore('clicks');
        store.put(entry);
        prunePendingClicks(store, entry.ts);
        tx.oncomplete = function () { resolve(); };
        tx.onerror = function () { resolve(); };
        tx.onabort = function () { resolve(); };
      } catch (e) { resolve(); }
    });
  }).catch(function () {});
}

function buildNotificationOptions(payload) {
  var actionUrls = {};
  var actions = [];
  if (Array.isArray(payload.actions)) {
    payload.actions.slice(0, 5).forEach(function (a) {
      if (!a || typeof a.action !== 'string') return;
      actions.push({ action: a.action, title: a.title || a.action, icon: a.icon });
      if (typeof a.url === 'string') actionUrls[a.action] = a.url;
    });
  }
  var options = {
    body: payload.body || '',
    icon: payload.icon,
    tag: payload.tag,
    data: { url: payload.url, custom: payload.data || {}, actionUrls: actionUrls }
  };
  // Forward the optional Notification fields the sender may have set.
  if (actions.length) options.actions = actions;
  if (payload.image) options.image = payload.image;
  if (payload.badge) options.badge = payload.badge;
  if (payload.requireInteraction) options.requireInteraction = true;
  if (payload.renotify) options.renotify = true;
  if (typeof payload.silent === 'boolean') options.silent = payload.silent;
  if (payload.vibrate) options.vibrate = payload.vibrate;
  if (typeof payload.timestamp === 'number') options.timestamp = payload.timestamp;
  if (payload.dir) options.dir = payload.dir;
  if (payload.lang) options.lang = payload.lang;
  return options;
}

// Returns the setAppBadge/clearAppBadge promise so the caller can keep the push
// event alive until it settles — iOS drops the badge if the event ends first.
function applyAppBadge(payload) {
  if (typeof payload.badgeCount !== 'number') return null;
  if (!self.navigator || !self.navigator.setAppBadge) return null;
  try {
    if (payload.badgeCount > 0) return self.navigator.setAppBadge(payload.badgeCount);
    if (self.navigator.clearAppBadge) return self.navigator.clearAppBadge();
  } catch (e) {}
  return null;
}

self.addEventListener('push', function (event) {
  var payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (e) {}
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      var tasks = [];
      // Keep the event alive until the badge update settles (required on iOS).
      var badgeTask = applyAppBadge(payload);
      if (badgeTask && typeof badgeTask.then === 'function') tasks.push(badgeTask);
      var focused = clientList.filter(function (c) {
        return c.focused || c.visibilityState === 'visible';
      });
      // Hand every push to any open app window so app code can react in-app
      // (toast, badge, live update) regardless of whether the OS banner shows.
      clientList.forEach(function (c) {
        try { c.postMessage({ type: 'floot-push', payload: payload }); } catch (e) {}
      });
      // When the app is focused and the sender opted out, skip the OS banner and
      // let app code (via onPushMessage) own the presentation.
      var suppressBanner = focused.length > 0 && payload.showWhenFocused === false;
      if (!suppressBanner) {
        tasks.push(self.registration.showNotification(payload.title || '', buildNotificationOptions(payload)));
      }
      return Promise.all(tasks);
    })
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var data = event.notification.data || {};
  // An action-button click resolves to that action's url; a body click uses the
  // base url. url may be undefined — then the app owns routing via onNotificationClick.
  var actionUrls = data.actionUrls || {};
  var url = (event.action && actionUrls[event.action]) || data.url;
  // Unique id so the page claims this click exactly once, whether it handles it
  // live (via the poke below) or replays it from IndexedDB after a cold start.
  var id = 'c-' + Date.now() + '-' + Math.random().toString(16).slice(2);
  var clickInfo = {
    type: 'floot-notificationclick',
    id: id,
    action: event.action || '',
    url: url || null,
    data: data.custom || {}
  };
  event.waitUntil(
    // Persist the click FIRST so it is never lost when there is no live page to
    // poke and the app relaunches at start_url instead of the target url.
    persistPendingClick({
      id: id,
      ts: Date.now(),
      action: clickInfo.action,
      url: clickInfo.url,
      data: clickInfo.data
    }).then(function () {
      return self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    }).then(function (clientList) {
      // Poke open windows to drain the pending click and route in-app without a
      // full reload. Old app builds still read this payload directly; new builds
      // ignore it and claim the click from IndexedDB (dedupe by id).
      clientList.forEach(function (c) {
        try { c.postMessage(clickInfo); } catch (e) {}
      });
      // Focus an existing window, else open one. We do NOT call client.navigate()
      // — this SW is registered at scope /floot-push-sdk/, which controls no
      // pages, so navigate() always rejects. Routing is owned by the page (the
      // live poke, or the cold-start replay of the persisted click).
      for (var i = 0; i < clientList.length; i++) {
        var client = clientList[i];
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url || '/');
      return undefined;
    })
  );
});

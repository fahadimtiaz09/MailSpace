// sw.js — DoMailit service worker: shows notifications for new email and calls,
// even when no DoMailit tab is open (the browser itself must be running).

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { title: "DoMailit", body: event.data ? event.data.text() : "" };
  }
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const lookingAtDoMailit = windows.some((w) => w.focused && w.visibilityState === "visible");
    // The open page already rings for calls; don't double up while the person is looking at it
    if (data.type === "call" && lookingAtDoMailit) return;
    await self.registration.showNotification(data.title || "DoMailit", {
      body: data.body || "",
      icon: "/apple-touch-icon.png",
      badge: "/notification-badge.png",
      tag: data.tag || undefined,
      renotify: Boolean(data.tag),
      requireInteraction: data.type === "call",
      vibrate: data.type === "call" ? [300, 150, 300, 150, 300] : [150],
      data: { url: data.url || "/inbox" },
    });
  })());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || "/inbox", self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const inbox = windows.find((w) => new URL(w.url).pathname.startsWith("/inbox"));
    if (inbox) {
      await inbox.focus();
      inbox.postMessage({ type: "open-url", url });
      return;
    }
    await self.clients.openWindow(url);
  })());
});

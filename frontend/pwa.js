// pwa.js — lets the browser (and the Microsoft Store app) install DoMailit as an app.
// The same /sw.js also shows notifications (see push.js).
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {});
  });
}

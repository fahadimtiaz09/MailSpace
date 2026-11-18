// ============================================================
// push.js — notifications on this browser (new email, calls).
// Settings → Notifications switches them on/off. The inbox also
// offers them once. Needs api.js and ui.js. Uses /sw.js.
// ============================================================

const Push = (() => {
  const supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  let registrationPromise = null;

  function registration() {
    if (!registrationPromise) {
      registrationPromise = navigator.serviceWorker.register("/sw.js").then(() => navigator.serviceWorker.ready);
    }
    return registrationPromise;
  }

  function keyBytes(base64url) {
    const text = (base64url + "=".repeat((4 - (base64url.length % 4)) % 4)).replace(/-/g, "+").replace(/_/g, "/");
    return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  }

  function deviceName() {
    const ua = navigator.userAgent;
    const browser = /Edg\//.test(ua) ? "Edge" : /Firefox\//.test(ua) ? "Firefox" : /Chrome\//.test(ua) ? "Chrome" : /Safari\//.test(ua) ? "Safari" : "Browser";
    const os = /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iPhone" : /Windows/.test(ua) ? "Windows" : /Mac OS/.test(ua) ? "Mac" : /Linux/.test(ua) ? "Linux" : "";
    return os ? `${browser} on ${os}` : browser;
  }

  async function currentSubscription() {
    if (!supported) return null;
    const reg = await registration();
    return reg.pushManager.getSubscription();
  }

  async function save(subscription) {
    await api("/api/push/subscribe", {
      method: "POST",
      body: { kind: "web", subscription: subscription.toJSON(), device: deviceName() },
    });
  }

  /** Ask permission (must be called from a click) and sign this browser up. */
  async function enable() {
    if (!supported) throw new Error("This browser can't show notifications. Try Chrome or Edge.");
    const permission = await Notification.requestPermission();
    if (permission === "denied") {
      throw new Error("Notifications are blocked for DoMailit. Click the lock icon next to the address bar, allow Notifications, then try again.");
    }
    if (permission !== "granted") throw new Error("Notifications weren't allowed.");
    const { web_public_key: key } = await api("/api/push/config");
    const reg = await registration();
    let subscription = await reg.pushManager.getSubscription();
    if (!subscription) {
      try {
        subscription = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(key) });
      } catch {
        throw new Error("This browser couldn't turn on notifications. In Brave, switch on \u201cUse Google services for push messaging\u201d in Settings \u2192 Privacy. Otherwise try Chrome or Edge.");
      }
    }
    await save(subscription);
  }

  async function disable() {
    const subscription = await currentSubscription().catch(() => null);
    if (!subscription) return;
    try {
      await api("/api/push/unsubscribe", { method: "POST", body: { kind: "web", subscription: subscription.toJSON() } });
    } catch {
      // still stop it on this browser
    }
    await subscription.unsubscribe().catch(() => {});
  }

  async function isOn() {
    if (!supported || Notification.permission !== "granted") return false;
    return Boolean(await currentSubscription().catch(() => null));
  }

  /** On every page: keep this browser linked to the account that is logged in now. */
  async function sync() {
    if (!(await isOn())) return;
    try {
      await save(await currentSubscription());
    } catch {
      // try again on the next page load
    }
  }

  // A click on a notification while the inbox is already open
  if (supported) {
    navigator.serviceWorker.addEventListener("message", (event) => {
      if (event.data?.type !== "open-url") return;
      const url = new URL(event.data.url, location.origin);
      const id = url.searchParams.get("open");
      if (location.pathname.startsWith("/inbox") && id) {
        document.dispatchEvent(new CustomEvent("push-open", { detail: { id } }));
      } else if (location.href !== url.href) {
        location.href = url.href;
      }
    });
  }

  // Offer notifications once, in the inbox
  const DISMISS_KEY = "domailit-push-prompt-dismissed";
  function offer() {
    if (!supported || Notification.permission !== "default" || !location.pathname.startsWith("/inbox")) return;
    try { if (localStorage.getItem(DISMISS_KEY)) return; } catch { /* private mode */ }
    const card = el("div", "push-prompt");
    card.setAttribute("role", "region");
    card.setAttribute("aria-label", "Turn on notifications");
    const text = el("div", "push-prompt-text");
    text.append(el("strong", null, "Get notified about new email and calls"), el("span", null, "Pop-ups on this computer, even when this tab is closed."));
    const on = el("button", "btn btn-primary btn-sm", "Turn on");
    const later = el("button", "btn btn-ghost btn-sm", "Not now");
    on.type = later.type = "button";
    const dismiss = () => { try { localStorage.setItem(DISMISS_KEY, "1"); } catch { /* ignore */ } card.remove(); };
    later.addEventListener("click", dismiss);
    on.addEventListener("click", async () => {
      setBusy(on, true, "Turning on…");
      try {
        await enable();
        toast("Notifications are on for this browser.", "success");
        card.remove();
      } catch (err) {
        setBusy(on, false);
        toast(err.message, "error");
        if (Notification.permission === "denied") dismiss();
      }
    });
    const actions = el("div", "push-prompt-actions");
    actions.append(later, on);
    const badge = el("span", "push-prompt-icon");
    badge.append(icon("bell"));
    card.append(badge, text, actions);
    document.body.append(card);
  }

  if (typeof Shell !== "undefined") {
    Shell.userReady.then(() => { sync(); setTimeout(offer, 2500); }).catch(() => {});
  }

  return { supported, enable, disable, isOn, deviceName, permission: () => (supported ? Notification.permission : "unsupported") };
})();

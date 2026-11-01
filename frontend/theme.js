// ============================================================
// theme.js — light / dark / system theme for every page.
// Loaded in <head> (not deferred) so the right colours are
// applied before the page is drawn — no white flash in dark mode.
// The choice is saved in this browser only (localStorage).
// ============================================================
(function () {
  const KEY = "mailspace-theme";          // "light" | "dark" | "system"
  const root = document.documentElement;
  const media = window.matchMedia("(prefers-color-scheme: dark)");

  function readPreference() {
    try {
      const saved = localStorage.getItem(KEY);
      return saved === "light" || saved === "dark" ? saved : "system";
    } catch {
      return "system"; // storage blocked (private mode): follow the system
    }
  }

  function resolve(pref) {
    if (pref === "system") return media.matches ? "dark" : "light";
    return pref;
  }

  function apply(pref, animate) {
    const theme = resolve(pref);
    if (animate) {
      root.classList.add("theme-switching");
      clearTimeout(apply.timer);
      apply.timer = setTimeout(() => root.classList.remove("theme-switching"), 350);
    }
    root.dataset.theme = theme;
    root.dataset.themePref = pref;
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = theme === "dark" ? "#0B1220" : "#F7F9FF";
    document.dispatchEvent(new CustomEvent("themechange", { detail: { theme, pref } }));
  }

  function setPreference(pref) {
    try {
      if (pref === "system") localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, pref);
    } catch {
      // Not saved, but still applied for this page view
    }
    apply(pref, true);
  }

  // Apply right away (before the body is drawn)
  apply(readPreference(), false);
  root.classList.add("js"); // lets CSS know scripts are running (used for scroll reveals)

  // Follow the operating system when the user chose "system"
  media.addEventListener("change", () => {
    if (readPreference() === "system") apply("system", true);
  });

  // Keep several open tabs in sync
  window.addEventListener("storage", (event) => {
    if (event.key === KEY) apply(readPreference(), true);
  });

  // Any button with data-theme-toggle flips between light and dark
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-theme-toggle]");
    if (!button) return;
    setPreference(root.dataset.theme === "dark" ? "light" : "dark");
  });

  function syncToggleLabels() {
    document.querySelectorAll("[data-theme-toggle]").forEach((b) => {
      const label = root.dataset.theme === "dark" ? "Switch to light theme" : "Switch to dark theme";
      b.setAttribute("aria-label", label);
      if (b.hasAttribute("data-tip")) b.setAttribute("data-tip", label.replace("Switch to ", "").replace(/^./, (c) => c.toUpperCase()));
    });
  }
  document.addEventListener("themechange", syncToggleLabels);
  document.addEventListener("DOMContentLoaded", syncToggleLabels);

  window.MailSpaceTheme = { get: readPreference, set: setPreference };
})();

// ============================================================
// shell.js — the header and sidebar shared by Inbox, My domains
// and Settings. Each page has <body data-page="..."> and empty
// <header id="topbar"> and <aside id="sidebar"> elements.
// Needs api.js and ui.js.
// ============================================================

const Shell = (() => {
  // DoMailit logo (blue "D" with an envelope fold, navy "D" behind), inline SVG
  let logoCount = 0;
  function makeLogo() {
    const id = "sh" + (++logoCount);
    const box = document.createElement("span");
    box.innerHTML = `<svg class="logo" viewBox="0 0 42 46" aria-hidden="true" focusable="false"><path class="l-back" d="M7.5 7H22.5A17 19 0 0 1 22.5 45H7.5Z"/><path class="l-front" d="M3 3H18A17 19 0 0 1 18 41H3Z"/><path class="l-fold" d="M3.6 10.4 17.6 21.6 32.2 12.7" fill="none" stroke-width="2.7" stroke-linejoin="round"/></svg>`;
    return box.firstChild;
  }
  function makeWordmark() {
    const word = el("span", "brand-text", "Do");
    word.append(el("span", "brand-space", "Mailit"));
    return word;
  }

  const page = document.body.dataset.page; // "inbox" | "domains" | "settings"
  const onInbox = page === "inbox";

  const FOLDER_LINKS = [
    { key: "inbox", label: "Inbox", icon: "inbox", count: true },
    { key: "starred", label: "Starred", icon: "star" },
    { key: "sent", label: "Sent", icon: "send" },
    { key: "drafts", label: "Drafts", icon: "draft", count: true },
    { key: "spam", label: "Spam", icon: "spam", count: true },
    { key: "trash", label: "Trash", icon: "trash" },
  ];

  let user = null;
  const userReady = loadUser();

  // ---------- Header ----------
  function buildHeader() {
    const header = document.getElementById("topbar");
    header.className = "topbar";

    const menuBtn = iconButton("menu", "Open navigation", "icon-btn only-drawer");
    menuBtn.id = "menu-btn";
    menuBtn.addEventListener("click", openSidebar);

    const brand = el("a", "brand");
    brand.href = "/";
    const logo = makeLogo();
    brand.append(logo, makeWordmark());

    // Search
    const form = el("form", "search");
    form.setAttribute("role", "search");
    const searchIcon = icon("search", "search-icon");
    const input = el("input");
    input.type = "search";
    input.id = "search-input";
    input.placeholder = "Search emails...";
    input.setAttribute("aria-label", "Search mail");
    input.autocomplete = "off";
    const clear = iconButton("x", "Clear search", "icon-btn icon-btn-sm search-clear");
    clear.addEventListener("click", () => {
      input.value = "";
      input.focus();
      form.classList.remove("has-value");
      if (onInbox) document.dispatchEvent(new CustomEvent("mailsearch", { detail: "" }));
    });
    input.addEventListener("input", () => form.classList.toggle("has-value", input.value !== ""));
    form.append(searchIcon, input, clear);
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const q = input.value.trim();
      header.classList.remove("searching");
      if (onInbox) document.dispatchEvent(new CustomEvent("mailsearch", { detail: q }));
      else window.location.href = "/inbox" + (q ? "?q=" + encodeURIComponent(q) : "");
    });

    const actions = el("div", "topbar-actions");
    const searchToggle = iconButton("search", "Search mail", "icon-btn only-mobile");
    searchToggle.addEventListener("click", () => {
      header.classList.add("searching");
      input.focus();
    });
    const searchBack = iconButton("arrow-left", "Close search", "icon-btn search-back");
    searchBack.addEventListener("click", () => header.classList.remove("searching"));
    form.prepend(searchBack);

    const themeBtn = el("button", "icon-btn theme-toggle");
    themeBtn.type = "button";
    themeBtn.dataset.themeToggle = "";
    themeBtn.dataset.tip = "Theme";
    themeBtn.append(icon("moon", "i-moon"), icon("sun", "i-sun"));

    // Account menu
    const wrap = el("div", "menu-wrap");
    const accountBtn = el("button", "account-btn");
    accountBtn.type = "button";
    accountBtn.dataset.menuButton = "";
    accountBtn.setAttribute("aria-expanded", "false");
    accountBtn.setAttribute("aria-haspopup", "menu");
    accountBtn.setAttribute("aria-label", "Account menu");
    accountBtn.append(el("span", "avatar avatar-sm skeleton"));
    const menu = el("div", "menu account-menu");
    menu.setAttribute("role", "menu");
    const menuHead = el("div", "menu-head");
    menuHead.append(el("strong", null, " "), el("span", null, " "));
    // Other accounts signed in on this browser + "Add another account" (filled by renderAccounts)
    const switcher = el("div", "account-list");
    const settingsLink = menuLink("/settings.html", "settings", "Settings");
    const domainsLink = menuLink("/domains.html", "globe", "My domains");
    const logout = el("button", "menu-item");
    logout.type = "button";
    logout.id = "menu-logout";
    logout.setAttribute("role", "menuitem");
    logout.append(icon("log-out"), el("span", null, "Log out"));
    logout.addEventListener("click", () => signOut(false));
    const logoutAll = el("button", "menu-item hidden");
    logoutAll.type = "button";
    logoutAll.id = "menu-logout-all";
    logoutAll.setAttribute("role", "menuitem");
    logoutAll.append(icon("log-out"), el("span", null, "Log out of all accounts"));
    logoutAll.addEventListener("click", () => signOut(true));
    menu.append(menuHead, switcher, el("div", "menu-sep"), settingsLink, domainsLink, el("div", "menu-sep"), logout, logoutAll);
    wrap.append(accountBtn, menu);

    actions.append(searchToggle, themeBtn, wrap);
    header.append(menuBtn, brand, form, actions);

    // Pre-fill search from ?q= (coming from another page)
    const q = new URLSearchParams(location.search).get("q");
    if (q) {
      input.value = q;
      form.classList.add("has-value");
    }
  }

  function menuLink(href, iconName, label) {
    const a = el("a", "menu-item");
    a.href = href;
    a.setAttribute("role", "menuitem");
    a.append(icon(iconName), el("span", null, label));
    return a;
  }

  // ---------- Sidebar ----------
  function buildSidebar() {
    const aside = document.getElementById("sidebar");
    aside.className = "sidebar";
    aside.setAttribute("aria-label", "Mail folders");

    const head = el("div", "sidebar-head");
    const brand = el("a", "brand");
    brand.href = "/";
    brand.append(makeLogo(), makeWordmark());
    const close = iconButton("x", "Close navigation");
    close.addEventListener("click", closeSidebar);
    head.append(brand, close);

    const compose = el("button", "btn btn-primary compose-btn");
    compose.type = "button";
    compose.id = "compose-btn";
    compose.append(icon("pencil"), el("span", null, "Compose"));
    compose.addEventListener("click", () => {
      closeSidebar();
      if (onInbox) document.dispatchEvent(new CustomEvent("compose"));
      else window.location.href = "/inbox?compose=1";
    });

    const nav = el("nav", "nav");
    const mailGroup = el("div", "nav-group");
    FOLDER_LINKS.forEach((f) => {
      const a = el("a", "nav-link");
      a.href = (onInbox ? "" : "/inbox") + "#" + f.key;
      a.dataset.folder = f.key;
      a.append(icon(f.icon), el("span", "nav-label", f.label));
      if (f.count) {
        const c = el("span", "count");
        c.id = "count-" + f.key;
        a.append(c);
      }
      a.addEventListener("click", closeSidebar);
      mailGroup.append(a);
    });

       const manageGroup = el("div", "nav-group");
    manageGroup.append(el("div", "nav-title", "Manage"));
    [["domains", "/domains.html", "globe", "My domains"], ["settings", "/settings.html", "settings", "Settings"]]
      .forEach(([key, href, iconName, label]) => {
        const a = el("a", "nav-link" + (page === key ? " active" : ""));
        a.href = href;
        if (page === key) a.setAttribute("aria-current", "page");
        a.append(icon(iconName), el("span", "nav-label", label));
        manageGroup.append(a);
      });

    // Admin link — added only once we know the user is an admin
    const adminLink = el("a", "nav-link hidden" + (page === "admin" ? " active" : ""));
    adminLink.href = "/admin.html";
    adminLink.id = "nav-admin";
    if (page === "admin") adminLink.setAttribute("aria-current", "page");
    adminLink.append(icon("shield"), el("span", "nav-label", "Admin"));
    manageGroup.append(adminLink);

    nav.append(mailGroup, manageGroup);

    const plan = el("div", "plan-card");
    plan.id = "plan-card";
    plan.append(el("span", "skeleton", ""));

    aside.append(head, compose, nav, plan);

    const overlay = el("div", "drawer-overlay");
    overlay.id = "drawer-overlay";
    overlay.addEventListener("click", closeSidebar);
    aside.after(overlay);

    // Mobile: floating compose button
    const fab = el("button", "fab");
    fab.type = "button";
    fab.setAttribute("aria-label", "Compose");
    fab.append(icon("pencil", "i-lg"));
    fab.addEventListener("click", () => compose.click());
    document.body.append(fab);
  }

  function openSidebar() {
    document.body.classList.add("drawer-open");
    const first = document.querySelector("#sidebar .compose-btn");
    if (first) setTimeout(() => first.focus(), 50);
  }
  function closeSidebar() {
    document.body.classList.remove("drawer-open");
  }
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && document.body.classList.contains("drawer-open")) closeSidebar();
  });

  function setActiveFolder(folder) {
    document.querySelectorAll(".nav-link[data-folder]").forEach((a) => {
      const active = onInbox && a.dataset.folder === folder;
      a.classList.toggle("active", active);
      if (active) a.setAttribute("aria-current", "page");
      else a.removeAttribute("aria-current");
    });
  }

  // ---------- Data ----------
  async function loadUser() {
    try {
      const data = await api("/api/auth/me");
      // A notification for another account signed in here: ?u=<account id>
      const params = new URLSearchParams(location.search);
      const wanted = params.get("u");
      if (wanted) {
        params.delete("u");
        const clean = location.pathname + (params.toString() ? "?" + params : "") + location.hash;
        if (wanted !== data.user.id) {
          try {
            await api("/api/auth/switch", { method: "POST", body: { id: wanted } });
            window.location.replace(clean);
            return new Promise(() => {});
          } catch {
            // not signed in here any more — stay on this account
          }
        }
        history.replaceState(null, "", clean);
      }
      user = data.user;
      currentAccountId = user.id;
      fillUser(user);
      loadAccounts();
      return user;
    } catch (err) {
      if (err.status === 401) {
        window.location.href = "/login.html";
        return new Promise(() => {}); // stop here while the browser navigates
      }
      showBanner(err.message, "error");
      throw err;
    }
  }

    function fillUser(u) {
    user = u;
    People.remember(u.email, { name: u.display_name, avatar: u.avatar });
    const btn = document.querySelector(".account-btn");
    btn.replaceChildren(avatar(u.email, "sm", u.display_name), icon("chevron-down", "i-sm"));
    const head = document.querySelector(".menu-head");
    const who = el("div", "menu-head-text");
    who.append(el("strong", null, u.display_name || u.username), el("span", null, u.email));
    head.replaceChildren(avatar(u.email, "lg", u.display_name), who);
    if (u.role === "admin") {
      const link = document.getElementById("nav-admin");
      if (link) link.classList.remove("hidden");
    }
    renderPlan(u);
  }

  const ACCOUNT_TYPES = {
    regular: "Regular account",
    temp15: "Temporary · 15 days",
    temp30: "Temporary · 30 days",
  };

  function renderPlan(u) {
    const card = document.getElementById("plan-card");
    card.replaceChildren();
    const top = el("div", "plan-top");
    top.append(avatar(u.email, "sm", u.display_name));
    const who = el("div", "plan-who");
    who.append(el("strong", "truncate", u.email), el("span", null, ACCOUNT_TYPES[u.account_type] || u.account_type));
    top.append(who);
    card.append(top);

    if (u.expires_at) {
      card.classList.add("temporary");
      const count = el("div", "plan-countdown");
      count.append(icon("hourglass", "i-sm"), el("span"));
      const bar = el("div", "plan-bar");
      const fill = el("span");
      bar.append(fill);
      card.append(count, bar);
      startCountdown(new Date(u.created_at), new Date(u.expires_at), count.lastChild, fill, card);
    }
  }

  let countdownTimer;
  function formatRemaining(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    const m = Math.floor((s % 3600) / 60);
    if (d > 0) return d + "d " + h + "h left";
    const pad = (n) => String(n).padStart(2, "0");
    return pad(h) + ":" + pad(m) + ":" + pad(s % 60) + " left";
  }

  function startCountdown(createdAt, expiresAt, label, fill, card) {
    clearInterval(countdownTimer);
    let warned = false;
    const total = expiresAt - createdAt;
    function tick() {
      const remaining = expiresAt - Date.now();
      if (remaining <= 0) {
        clearInterval(countdownTimer);
        label.textContent = "Account expired";
        card.classList.add("urgent");
        showBanner("This temporary account has expired. You'll be taken to the login page.", "error");
        setTimeout(() => (window.location.href = "/login.html"), 3000);
        return;
      }
      label.textContent = formatRemaining(remaining);
      fill.style.width = Math.max(2, Math.min(100, (remaining / total) * 100)) + "%";
      card.classList.toggle("urgent", remaining < 24 * 3600 * 1000);
      if (!warned && remaining < 3 * 24 * 3600 * 1000) {
        warned = true;
        showBanner("Your temporary account expires in " + formatRemaining(remaining).replace(" left", "") +
          ". Download anything you want to keep.", "warning");
      }
    }
    tick();
    countdownTimer = setInterval(tick, 1000);
  }

  async function refreshCounts() {
    try {
      const counts = await api("/api/messages/counts");
      ["inbox", "drafts", "spam"].forEach((name) => {
        const node = document.getElementById("count-" + name);
        const n = counts[name] || 0;
        if (!node) return;
        if (String(n || "") !== node.textContent) {
          node.textContent = n > 0 ? (n > 999 ? "999+" : n) : "";
          node.classList.remove("bump");
          void node.offsetWidth;
          if (n > 0) node.classList.add("bump");
        }
      });
      const inboxUnread = counts.inbox || 0;
      const base = document.title.replace(/^\(\d+\+?\)\s*/, "");
      document.title = (onInbox && inboxUnread > 0 ? "(" + inboxUnread + ") " : "") + base;
    } catch {
      // Counts are optional
    }
  }

  // ---------- Banner ----------
  function showBanner(text, type = "info") {
    let banner = document.getElementById("app-banner");
    if (!banner) {
      banner = el("div", "app-banner");
      banner.id = "app-banner";
      banner.setAttribute("role", "status");
      document.getElementById("topbar").after(banner);
    }
    banner.className = "app-banner " + type;
    const close = iconButton("x", "Dismiss", "icon-btn icon-btn-sm");
    close.addEventListener("click", () => banner.classList.add("hidden"));
    banner.replaceChildren(icon(type === "error" || type === "warning" ? "alert" : "info", "i-sm"), el("span", null, text), close);
  }

  // ---------- Accounts signed in on this browser (Gmail-style) ----------
  let accounts = [];

  async function loadAccounts() {
    try {
      const data = await api("/api/auth/accounts");
      accounts = data.accounts || [];
      renderAccounts(data.max || 5);
    } catch {
      renderAccounts(5);
    }
  }

  function renderAccounts(max) {
    const list = document.querySelector(".account-list");
    if (!list) return;
    const others = accounts.filter((a) => !a.active);
    const rows = others.map((a) => {
      People.remember(a.email, { name: a.display_name, avatar: a.avatar });
      const row = el("button", "menu-item account-row");
      row.type = "button";
      row.setAttribute("role", "menuitem");
      const text = el("span", "account-row-text");
      text.append(el("strong", null, a.display_name || a.username), el("small", null, a.email));
      row.append(avatar(a.email, "sm", a.display_name), text);
      row.addEventListener("click", () => switchTo(a.id, row));
      return row;
    });
    if (accounts.length < max) {
      const add = el("a", "menu-item");
      add.href = "/login.html?add=1";
      add.setAttribute("role", "menuitem");
      add.append(icon("user-plus"), el("span", null, "Add another account"));
      rows.push(add);
    }
    list.replaceChildren(...rows);
    const many = accounts.length > 1;
    document.getElementById("menu-logout-all")?.classList.toggle("hidden", !many);
    const one = document.querySelector("#menu-logout span");
    if (one && user) one.textContent = many ? "Log out of " + user.email : "Log out";
  }

  async function switchTo(id, row) {
    row.disabled = true;
    try {
      await api("/api/auth/switch", { method: "POST", body: { id } });
      window.location.href = "/inbox";
    } catch (err) {
      row.disabled = false;
      showBanner(err.message, "error");
      loadAccounts();
    }
  }

  // all=false: only the account in use (the next signed-in account opens).
  // all=true: every account on this browser.
  async function signOut(all = false) {
    let remaining = 0;
    try {
      // Stop notifications for the account(s) leaving, so the next person here doesn't get yours
      if (typeof Push !== "undefined") await (all || accounts.length <= 1 ? Push.disable() : Push.forget());
      const res = await api("/api/auth/logout", { method: "POST", body: { all } });
      remaining = res.remaining || 0;
    } catch {
      // Even if this fails, go to the login page
    }
    window.location.href = remaining ? "/inbox" : "/login.html";
  }

  buildHeader();
  buildSidebar();
  userReady.then(refreshCounts).catch(() => {});

  return { userReady, refreshCounts, setActiveFolder, showBanner, closeSidebar, signOut, refreshUser: fillUser, get user() { return user; }, get accounts() { return accounts; } };
})();

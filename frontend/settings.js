// ============================================================
// settings.js — profile, appearance, sending addresses, security.
// Needs api.js, ui.js and shell.js.
// ============================================================

const ACCOUNT_LABELS = {
  regular: "Regular — doesn't expire",
  temp15: "Temporary — 15 days",
  temp30: "Temporary — 30 days",
};

function settingRow(label, value, note) {
  const row = el("div", "setting-row");
  const text = el("div", "grow");
  text.append(el("strong", null, label));
  if (note) text.append(el("p", null, note));
  row.append(text, el("div", "value", value));
  return row;
}

function renderProfile(u) {
  const hero = document.getElementById("profile-hero");
  const text = el("div");
  text.style.minWidth = "0";
  text.append(el("h3", null, u.username), el("p", null, u.email));
  hero.replaceChildren(avatar(u.email, "lg"), text);

  const rows = document.getElementById("profile-rows");
  rows.replaceChildren(
    settingRow("MailSpace address", u.email, "Your main address. It can't be changed."),
    settingRow("Account type", ACCOUNT_LABELS[u.account_type] || u.account_type),
    settingRow("Member since", new Date(u.created_at).toLocaleDateString([], { day: "numeric", month: "long", year: "numeric" }))
  );
  if (u.expires_at) {
    rows.append(settingRow("Expires", formatFullDate(u.expires_at),
      "Temporary accounts and their messages are deleted when they expire. Download anything you want to keep."));
  }
}

async function renderFromAddresses() {
  const list = document.getElementById("from-list");
  try {
    const data = await api("/api/domains/from-addresses");
    list.replaceChildren();
    data.addresses.forEach((email, i) => {
      const li = el("li");
      li.append(icon("at", "i-sm"), el("span", "truncate", email));
      if (i === 0) li.append(el("span", "badge badge-info no-dot", "Main"));
      list.append(li);
    });
  } catch (err) {
    list.replaceChildren(el("li", null, err.message));
  }
}

// Theme radios
function syncThemeRadios() {
  const pref = window.MailSpaceTheme.get();
  document.querySelectorAll('input[name="theme"]').forEach((r) => (r.checked = r.value === pref));
}
document.querySelectorAll('input[name="theme"]').forEach((radio) => {
  radio.addEventListener("change", () => {
    window.MailSpaceTheme.set(radio.value);
    toast("Theme set to " + radio.value, "success");
  });
});
document.addEventListener("themechange", syncThemeRadios);
syncThemeRadios();

// Section nav: highlight the section in view
const navLinks = [...document.querySelectorAll(".settings-nav a")];
const scroller = document.getElementById("main");
const sections = [...document.querySelectorAll(".settings-sections > section")];
function highlightSection() {
  const line = scroller.getBoundingClientRect().top + scroller.clientHeight * 0.3;
  let current = sections[0];
  sections.forEach((s) => { if (s.getBoundingClientRect().top <= line) current = s; });
  // At the very bottom, the last section wins
  if (scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 4) current = sections[sections.length - 1];
  navLinks.forEach((a) => a.classList.toggle("active", a.getAttribute("href") === "#" + current.id));
}
scroller.addEventListener("scroll", highlightSection, { passive: true });
navLinks.forEach((a) => a.addEventListener("click", (event) => {
  event.preventDefault();
  const target = document.querySelector(a.getAttribute("href"));
  target.scrollIntoView({ behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
}));

document.getElementById("logout-here").addEventListener("click", async () => {
  try {
    await api("/api/auth/logout", { method: "POST" });
  } catch {
    // Even if this fails, go to the login page
  }
  window.location.href = "/login.html";
});

Shell.userReady.then((u) => {
  renderProfile(u);
  renderFromAddresses();
  highlightSection();
}).catch(() => {});

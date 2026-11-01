// ============================================================
// admin.js — platform admin console.
// Three tabs: Overview, Users, Mail. Opening a message's
// content asks for a reason and is logged on the server.
// Needs api.js, ui.js, shell.js.
// ============================================================

const view = document.getElementById("admin-view");
const state = { tab: "overview", page: 1, totalPages: 1, q: "", userId: "", userLabel: "" };

// ---------- Shell ----------
function pageHead() {
  const head = el("div", "page-head");
  const left = el("div");
  left.append(el("h1", null, "Admin console"));
  left.append(el("p", null, "You are viewing data across all of MailSpace. Opening a message is recorded in the audit log."));
  head.append(left);
  return head;
}

function notice() {
  const box = el("div", "admin-notice");
  box.append(icon("shield", "i-sm"),
    el("span", null, "Admin access is logged. Open message content only for safety or policy reasons."));
  return box;
}

function tabs() {
  const row = el("div", "admin-tabs");
  [["overview", "Overview"], ["users", "Users"], ["mail", "Mail"], ["audit", "Audit log"]].forEach(([key, label]) => {
    const b = el("button", "admin-tab" + (state.tab === key ? " active" : ""), label);
    b.type = "button";
    b.addEventListener("click", () => {
      state.tab = key;
      state.page = 1;
      state.q = "";
      if (key !== "mail") { state.userId = ""; state.userLabel = ""; }
      render();
    });
    row.append(b);
  });
  return row;
}

function render() {
  view.replaceChildren(pageHead(), notice(), tabs(), el("div", null, "Loading…"));
  if (state.tab === "overview") renderOverview();
  else if (state.tab === "users") renderUsers();
  else if (state.tab === "mail") renderMail();
  else renderAudit();
}

function body(...nodes) {
  // Re-render keeping head + notice + tabs, replacing only the body (last child)
  view.replaceChildren(pageHead(), notice(), tabs(), ...nodes);
}

// ---------- Overview ----------
async function renderOverview() {
  try {
    const s = await api("/api/admin/stats");
    const grid = el("div", "stat-grid");
    const cards = [
      ["users", "Users"], ["admins", "Admins"], ["temporary", "Temporary accounts"],
      ["messages", "Messages"], ["domains", "Verified domains"], ["addresses", "Custom addresses"],
      ["reviews", "Logged reviews"],
    ];
    cards.forEach(([key, label]) => {
      const card = el("div", "stat-card");
      card.append(el("div", "stat-num", String(s[key] ?? 0)), el("div", "stat-label", label));
      grid.append(card);
    });
    body(grid);
  } catch (err) {
    body(errorBox(err));
  }
}

// ---------- Users ----------
async function renderUsers() {
  const search = el("form", "admin-search");
  const input = el("input", "input");
  input.type = "search";
  input.placeholder = "Search username or email…";
  input.value = state.q;
  const go = el("button", "btn btn-primary", "Search");
  go.type = "submit";
  search.append(input, go);
  search.addEventListener("submit", (e) => { e.preventDefault(); state.q = input.value.trim(); state.page = 1; renderUsers(); });

  body(search, el("div", null, "Loading…"));
  try {
    const data = await api("/api/admin/users?page=" + state.page + "&q=" + encodeURIComponent(state.q));
    state.totalPages = data.total_pages;

    const table = el("table", "admin-table");
    const thead = el("thead");
    const htr = el("tr");
    ["User", "Type", "Status", "Inbox", "Joined", ""].forEach((h) => htr.append(el("th", null, h)));
    thead.append(htr);
    const tbody = el("tbody");

    data.users.forEach((u) => {
      const tr = el("tr");
      const who = el("td");
      const wrap = el("div", "who");
      wrap.append(avatar(u.email, "sm"));
      const col = el("div");
      const name = el("strong", null, u.username);
      if (u.role === "admin") name.append(" ", badge("Admin", "info"));
      col.append(name, el("div", "sub", u.email));
      wrap.append(col);
      who.append(wrap);

      const type = el("td", null, u.account_type === "regular" ? "Regular" : "Temporary");
      const status = el("td");
      status.append(badge(u.status === "active" ? "Active" : u.status, u.status === "active" ? "success" : "warning"));
      const inbox = el("td", null, String(u.inbox_count));
      const joined = el("td", "sub", shortDate(u.created_at));

      const act = el("td");
      const mailBtn = el("button", "btn btn-sm", "View mail");
      mailBtn.type = "button";
      mailBtn.addEventListener("click", () => {
        state.tab = "mail"; state.userId = u.id; state.userLabel = u.email; state.q = ""; state.page = 1;
        render();
      });
      act.append(mailBtn);

      tr.append(who, type, status, inbox, joined, act);
      tbody.append(tr);
    });

    table.append(thead, tbody);
    const wrap = el("div", "table-wrap");
    wrap.append(table);
    body(search, wrap, pager(renderUsers), countLine(data.total, "users"));
  } catch (err) {
    body(search, errorBox(err));
  }
}

// ---------- Mail ----------
async function renderMail() {
  const search = el("form", "admin-search");
  const input = el("input", "input");
  input.type = "search";
  input.placeholder = "Search sender, recipient or subject…";
  input.value = state.q;
  const go = el("button", "btn btn-primary", "Search");
  go.type = "submit";
  search.append(input, go);
  if (state.userId) {
    const chip = el("button", "btn btn-sm", "");
    chip.type = "button";
    chip.append(icon("x", "i-sm"), el("span", null, "Filtered: " + state.userLabel));
    chip.addEventListener("click", () => { state.userId = ""; state.userLabel = ""; state.page = 1; renderMail(); });
    search.append(chip);
  }
  search.addEventListener("submit", (e) => { e.preventDefault(); state.q = input.value.trim(); state.page = 1; renderMail(); });

  body(search, el("div", null, "Loading…"));
  try {
    const url = "/api/admin/messages?page=" + state.page +
      "&q=" + encodeURIComponent(state.q) +
      (state.userId ? "&user_id=" + state.userId : "");
    const data = await api(url);
    state.totalPages = data.total_pages;

    const table = el("table", "admin-table");
    const thead = el("thead");
    const htr = el("tr");
    ["From", "To", "Subject", "When", ""].forEach((h) => htr.append(el("th", null, h)));
    thead.append(htr);
    const tbody = el("tbody");

    if (data.messages.length === 0) {
      const tr = el("tr");
      const td = el("td", "sub", "No messages match.");
      td.colSpan = 5;
      tr.append(td);
      tbody.append(tr);
    }

    data.messages.forEach((m) => {
      const tr = el("tr");
      tr.append(el("td", "clip", m.from));
      tr.append(el("td", "clip", (m.to || []).join(", ")));
      const subj = el("td");
      const s = el("span", null, m.subject || "(no subject)");
      subj.append(s);
      if (m.has_attachments) subj.append(" ", icon("paperclip", "i-sm"));
      if (m.external) subj.append(" ", badge("External", "info"));
      tr.append(subj);
      tr.append(el("td", "sub", shortDate(m.created_at)));

      const act = el("td");
      const open = el("button", "btn btn-sm", "Open");
      open.type = "button";
      open.addEventListener("click", () => openMessage(m));
      act.append(open);
      tr.append(act);
      tbody.append(tr);
    });

    table.append(thead, tbody);
    const wrap = el("div", "table-wrap");
    wrap.append(table);
    body(search, wrap, pager(renderMail), countLine(data.total, "messages"));
  } catch (err) {
    body(search, errorBox(err));
  }
}

// ---------- Open a message (asks reason, then shows content) ----------
async function openMessage(m) {
  const box = el("div", "modal");
  box.style.maxWidth = "640px";
  const head = el("div", "modal-head");
  head.append(el("h2", null, "Open message content"));
  box.append(head);

  box.append(el("p", "reason-note",
    "Opening “" + (m.subject || "(no subject)") + "” from " + m.from +
    ". This is logged. Give a short reason:"));

  const field = el("div", "field");
  const input = el("input", "input");
  input.placeholder = "e.g. reported spam, safety review";
  field.append(input);
  box.append(field);

  const foot = el("div", "modal-foot");
  foot.style.paddingTop = "18px";
  const cancel = el("button", "btn", "Cancel");
  const ok = el("button", "btn btn-primary", "Open and log");
  cancel.type = ok.type = "button";
  foot.append(cancel, ok);
  box.append(foot);

  const close = openModal(box);
  cancel.addEventListener("click", close);
  ok.addEventListener("click", async () => {
    const reason = input.value.trim();
    if (reason.length < 3) { input.focus(); toast("Please type a short reason.", "error"); return; }
    setBusy(ok, true, "Opening…");
    try {
      const data = await api("/api/admin/messages/" + m.id + "/view", { method: "POST", body: { reason } });
      close();
      showContent(data.message);
    } catch (err) {
      setBusy(ok, false);
      toast(err.message, "error");
    }
  });
}

function showContent(m) {
  const box = el("div", "modal");
  box.style.maxWidth = "680px";
  const head = el("div", "modal-head");
  head.append(el("h2", null, m.subject || "(no subject)"));
  box.append(head);

  const meta = el("div", "reason-note");
  meta.append(el("div", null, "From: " + m.from));
  meta.append(el("div", null, "To: " + (m.to || []).join(", ")));
  meta.append(el("div", null, "Date: " + formatFullDate(m.created_at)));
  box.append(meta);

  box.append(el("div", "read-body-admin", m.body || "(empty)"));

  if ((m.attachments || []).length) {
    const row = el("div", "att-row");
    m.attachments.forEach((a) => {
      const link = el("a", "att-chip");
      link.href = "/api/admin/attachments/" + encodeURIComponent(a.id);
      link.append(icon("download", "i-sm"), el("span", null, a.filename + " · " + formatSize(a.size)));
      row.append(link);
    });
    box.append(row);
  }

  const foot = el("div", "modal-foot");
  foot.style.paddingTop = "16px";
  const done = el("button", "btn btn-primary", "Close");
  done.type = "button";
  foot.append(done);
  box.append(foot);
  const close = openModal(box);
  done.addEventListener("click", close);
}

// ---------- Audit log ----------
async function renderAudit() {
  body(el("div", null, "Loading…"));
  try {
    const data = await api("/api/admin/audit?page=" + state.page);
    state.totalPages = data.total_pages;

    const table = el("table", "admin-table");
    const thead = el("thead");
    const htr = el("tr");
    ["Admin", "Action", "Target", "Reason", "When"].forEach((h) => htr.append(el("th", null, h)));
    thead.append(htr);
    const tbody = el("tbody");

    if (data.logs.length === 0) {
      const tr = el("tr");
      const td = el("td", "sub", "No reviews yet.");
      td.colSpan = 5;
      tr.append(td);
      tbody.append(tr);
    }
    const ACTIONS = { view_message: "Viewed message", download_attachment: "Downloaded file" };
    data.logs.forEach((r) => {
      const tr = el("tr");
      tr.append(el("td", "clip", r.admin_email));
      tr.append(el("td", null, ACTIONS[r.action] || r.action));
      tr.append(el("td", "clip", r.target_email));
      tr.append(el("td", "clip", r.reason));
      tr.append(el("td", "sub", formatFullDate(r.created_at)));
      tbody.append(tr);
    });

    table.append(thead, tbody);
    const wrap = el("div", "table-wrap");
    wrap.append(table);
    body(wrap, pager(renderAudit), countLine(data.total, "entries"));
  } catch (err) {
    body(errorBox(err));
  }
}

// ---------- Small helpers ----------
function badge(text, kind) { return el("span", "badge badge-" + kind, text); }
function shortDate(iso) { return iso ? new Date(iso).toLocaleDateString([], { day: "numeric", month: "short", year: "numeric" }) : "—"; }
function countLine(total, noun) { const p = el("p", "sub"); p.style.marginTop = "10px"; p.textContent = total + " " + noun; return p; }

function pager(reload) {
  if (state.totalPages <= 1) return el("span");
  const box = el("div", "pager");
  box.append(el("span", "page-info", "Page " + state.page + " of " + state.totalPages));
  const nav = el("div");
  const prev = iconButton("chevron-left", "Previous", "icon-btn icon-btn-sm");
  const next = iconButton("chevron-right", "Next", "icon-btn icon-btn-sm");
  prev.disabled = state.page <= 1;
  next.disabled = state.page >= state.totalPages;
  prev.addEventListener("click", () => { state.page--; reload(); });
  next.addEventListener("click", () => { state.page++; reload(); });
  nav.append(prev, next);
  box.append(nav);
  return box;
}

function errorBox(err) {
  const box = el("div", "empty");
  box.append(el("div", "empty-art", ""));
  box.append(el("h3", null, err.status === 403 ? "Admins only" : "Something went wrong"));
  box.append(el("p", null, err.message));
  return box;
}

// ---------- Start ----------
Shell.userReady.then((u) => {
  if (!u || u.role !== "admin") {
    view.replaceChildren(errorBox({ status: 403, message: "This page is for administrators." }));
    return;
  }
  render();
}).catch(() => {});
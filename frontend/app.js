// ============================================================
// app.js — the inbox page: folders, message list, reading pane,
// reply / forward and the compose window.
// Needs api.js, ui.js and shell.js.
// ============================================================

const FOLDERS = {
  inbox:   { title: "Inbox",   icon: "inbox",  emptyTitle: "You're all caught up",   emptyText: "New messages sent to your address will show up here.", action: "compose" },
  sent:    { title: "Sent",    icon: "send",   emptyTitle: "Nothing sent yet",       emptyText: "Messages you send will be kept here.", action: "compose" },
  drafts:  { title: "Drafts",  icon: "draft",  emptyTitle: "No drafts",              emptyText: "Use “Save draft” in the compose window to finish a message later." },
  starred: { title: "Starred", icon: "star",   emptyTitle: "No starred messages",    emptyText: "Star important messages to find them here quickly." },
  spam:    { title: "Spam",    icon: "spam",   emptyTitle: "No spam",                emptyText: "Messages you report as spam are moved here." },
  trash:   { title: "Trash",   icon: "trash",  emptyTitle: "Trash is empty",         emptyText: "Deleted messages stay here until you delete them forever." },
};

const MAX_FILES = 5;
const MAX_FILE_MB = 10;
const ALLOWED_EXTENSIONS = ["jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "txt"];
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const state = {
  folder: "inbox",
  page: 1,
  totalPages: 1,
  total: 0,
  query: "",
  items: [],        // messages in the current list
  selectedId: null, // the open message's id
  picked: new Set(), // ids ticked with the checkboxes
  current: null,    // the open message (full)
  draftId: null,    // set when editing an existing draft
  files: [],        // files chosen in compose
  composeSnapshot: "",
};

const $ = (id) => document.getElementById(id);
let listRequest = 0; // ignore out-of-date responses

// ---------- Folders ----------
function folderFromHash() {
  const name = location.hash.replace("#", "");
  return FOLDERS[name] ? name : "inbox";
}

function updateHeading() {
  Shell.setActiveFolder(state.query ? null : state.folder);
  $("folder-title").textContent = state.query ? "Search results" : FOLDERS[state.folder].title;
  const titleBase = state.query ? "Search" : FOLDERS[state.folder].title;
  document.title = titleBase + " · MailSpace";
}

function updateMeta() {
  let text;
  if (state.query) text = state.total + (state.total === 1 ? " match" : " matches") + " for “" + state.query + "”";
  else text = state.total === 0 ? "No messages" : state.total + (state.total === 1 ? " message" : " messages");
  $("folder-meta").textContent = text;
}

// ---------- Message list ----------
function showSkeleton() {
  const list = $("message-list");
  list.replaceChildren();
  for (let i = 0; i < 7; i++) {
    const row = el("li", "skeleton-row");
    row.setAttribute("aria-hidden", "true");
    const lines = el("div", "lines");
    const a = el("span", "skeleton"); a.style.width = (40 + (i * 13) % 35) + "%";
    const b = el("span", "skeleton"); b.style.width = (70 + (i * 7) % 25) + "%";
    const c = el("span", "skeleton"); c.style.width = (50 + (i * 11) % 30) + "%";
    lines.append(a, b, c);
    row.append(el("span", "skeleton avatar-s"), lines);
    list.append(row);
  }
}

async function loadMessages({ quiet = false } = {}) {
  updateHeading();
  state.picked.clear();
  updateBulk();
  const requestId = ++listRequest;
  if (!quiet) {
    showSkeleton();
    $("pager").classList.add("hidden");
  }

  const params = new URLSearchParams({ folder: state.query ? "all" : state.folder, page: state.page });
  if (state.query) params.set("q", state.query);

  try {
    const data = await api("/api/messages?" + params.toString());
    if (requestId !== listRequest) return;
    state.totalPages = data.total_pages || 1;
    state.total = data.total || 0;
    state.items = data.messages;
    renderList();
    updateMeta();
    updatePager();
  } catch (err) {
    if (requestId !== listRequest) return;
    renderListError(err.message);
  }
  Shell.refreshCounts();
}

function renderList() {
  const list = $("message-list");
  list.replaceChildren();
  updateBulk();
  if (state.items.length === 0) {
    list.append(state.query ? searchEmpty() : folderEmpty());
    return;
  }
  state.items.forEach((m, index) => {
    const row = renderRow(m);
    row.style.animationDelay = Math.min(index, 12) * 18 + "ms";
    list.append(row);
  });
}

function folderEmpty() {
  const f = FOLDERS[state.folder];
  const li = el("li", "empty");
  const art = el("div", "empty-art");
  art.append(icon(f.icon));
  li.append(art, el("h3", null, f.emptyTitle), el("p", null, f.emptyText));
  if (f.action === "compose") {
    const b = el("button", "btn btn-soft btn-sm");
    b.type = "button";
    b.append(icon("pencil", "i-sm"), el("span", null, "Write a message"));
    b.addEventListener("click", () => openCompose());
    li.append(b);
  }
  return li;
}

function searchEmpty() {
  const li = el("li", "empty");
  const art = el("div", "empty-art");
  art.append(icon("search"));
  const b = el("button", "btn btn-sm", "Clear search");
  b.type = "button";
  b.addEventListener("click", () => setSearch(""));
  li.append(art, el("h3", null, "No matches"), el("p", null, "Nothing in your mail matches “" + state.query + "”. Try a name, address or word from the subject."), b);
  return li;
}

function renderListError(message) {
  const list = $("message-list");
  const li = el("li", "empty");
  const art = el("div", "empty-art");
  art.style.background = "var(--error-soft)";
  art.style.color = "var(--error-text)";
  art.append(icon("alert"));
  const b = el("button", "btn btn-sm", "Try again");
  b.type = "button";
  b.addEventListener("click", () => loadMessages());
  li.append(art, el("h3", null, "Couldn't load messages"), el("p", null, message), b);
  list.replaceChildren(li);
  $("folder-meta").textContent = " ";
}

function isOutgoing(m) {
  return m.folder === "sent" || m.folder === "drafts";
}

function renderRow(m) {
  const li = el("li", "msg" + (m.is_read ? "" : " unread") + (m.id === state.selectedId ? " selected" : ""));
  li.dataset.id = m.id;
  li.tabIndex = 0;

  const outgoing = isOutgoing(m);
  const who = outgoing
    ? (m.to && m.to.length ? "To: " + m.to.join(", ") : "(no recipients)")
    : nameFromEmail(m.from);
  const avatarEmail = outgoing ? (m.to && m.to[0]) || "?" : m.from;
  li.setAttribute("aria-label",
    (m.is_read ? "" : "Unread, ") + (outgoing ? who : "From " + m.from) + ", " + (m.subject || "no subject"));

  const top = el("div", "msg-top");
  const from = el("span", "msg-from truncate", who);
  if (!outgoing) from.title = m.from;
  const flags = el("span", "msg-flags");
  if (m.folder === "drafts") flags.append(el("span", "badge badge-warning no-dot", "Draft"));
  if (m.has_attachments) flags.append(icon("paperclip"));
  if (m.is_starred) flags.append(icon("star-fill", "is-starred"));
  top.append(from, flags, el("span", "msg-date", formatDate(m.created_at)));

  const lines = el("div", "msg-lines");
  lines.append(
    el("div", "msg-subject truncate", m.subject || "(no subject)"),
    el("div", "msg-snippet truncate", m.snippet || " ")
  );

  // Quick actions
  const actions = el("div", "msg-actions");
  if (m.folder === "trash") {
    actions.append(quickAction("restore", "Restore", () => rowAction(m, "restore", "Restored")));
  } else {
    const star = quickAction(m.is_starred ? "star-fill" : "star", m.is_starred ? "Unstar" : "Star", () => toggleStar(m));
    if (m.is_starred) star.classList.add("starred");
    actions.append(star);
    if (m.folder !== "drafts") {
      actions.append(quickAction(m.is_read ? "mail" : "mail-open", m.is_read ? "Mark as unread" : "Mark as read",
        () => toggleRead(m)));
    }
    actions.append(quickAction("trash", "Move to trash", () => rowAction(m, "trash", "Moved to trash")));
  }

  // Avatar doubles as a checkbox for selecting several messages
  const av = el("span", "msg-av");
  const pick = el("input", "pick");
  pick.type = "checkbox";
  pick.checked = state.picked.has(m.id);
  pick.setAttribute("aria-label", "Select “" + (m.subject || "no subject") + "”");
  pick.addEventListener("click", (event) => event.stopPropagation());
  pick.addEventListener("change", () => {
    if (pick.checked) state.picked.add(m.id);
    else state.picked.delete(m.id);
    li.classList.toggle("picked", pick.checked);
    updateBulk();
  });
  av.append(avatar(avatarEmail), pick);
  if (pick.checked) li.classList.add("picked");

  li.append(av, top, lines, actions);

  const open = () => (m.folder === "drafts" ? openDraft(m.id) : openMessage(m.id));
  li.addEventListener("click", open);
  li.addEventListener("keydown", (event) => {
    if (event.target !== li) return;
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); open(); }
    if (event.key === "ArrowDown" && li.nextElementSibling) { event.preventDefault(); li.nextElementSibling.focus(); }
    if (event.key === "ArrowUp" && li.previousElementSibling) { event.preventDefault(); li.previousElementSibling.focus(); }
  });
  return li;
}

function quickAction(iconName, label, handler) {
  const b = iconButton(iconName, label, "icon-btn");
  b.dataset.tip = label;
  b.addEventListener("click", (event) => {
    event.stopPropagation();
    handler();
  });
  return b;
}

function rowFor(id) {
  return document.querySelector('.msg[data-id="' + CSS.escape(id) + '"]');
}

function replaceRow(m) {
  const row = rowFor(m.id);
  if (row) {
    const fresh = renderRow(m);
    fresh.style.animation = "none";
    row.replaceWith(fresh);
  }
}

function removeRow(id) {
  const row = rowFor(id);
  state.items = state.items.filter((m) => m.id !== id);
  state.total = Math.max(0, state.total - 1);
  updateMeta();
  if (!row) return;
  row.classList.add("removing");
  setTimeout(() => {
    row.remove();
    if (state.items.length === 0) loadMessages({ quiet: true });
  }, 210);
}

function messageAction(id, action) {
  return api("/api/messages/" + encodeURIComponent(id), { method: "PATCH", body: { action } });
}

async function toggleStar(m) {
  const action = m.is_starred ? "unstar" : "star";
  try {
    await messageAction(m.id, action);
    m.is_starred = !m.is_starred;
    if (state.current && state.current.id === m.id) {
      state.current.is_starred = m.is_starred;
      updateToolbar(state.current);
    }
    if (state.folder === "starred" && !state.query && !m.is_starred) removeRow(m.id);
    else replaceRow(m);
    toast(m.is_starred ? "Starred" : "Star removed", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

async function toggleRead(m) {
  const action = m.is_read ? "unread" : "read";
  try {
    await messageAction(m.id, action);
    m.is_read = !m.is_read;
    replaceRow(m);
    Shell.refreshCounts();
    toast(m.is_read ? "Marked as read" : "Marked as unread", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

async function rowAction(m, action, doneText) {
  try {
    await messageAction(m.id, action);
    if (state.selectedId === m.id) closeReader();
    removeRow(m.id);
    Shell.refreshCounts();
    toast(doneText, "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

function updatePager() {
  const show = state.totalPages > 1;
  $("pager").classList.toggle("hidden", !show);
  if (!show) return;
  const start = (state.page - 1) * 20 + 1;
  const end = Math.min(state.total, state.page * 20);
  $("page-info").textContent = start + "–" + end + " of " + state.total;
  $("prev-btn").disabled = state.page <= 1;
  $("next-btn").disabled = state.page >= state.totalPages;
}

// ---------- Selecting several messages ----------
const BULK_ACTIONS = {
  read: "Marked as read",
  unread: "Marked as unread",
  star: "Starred",
  not_spam: "Moved to inbox",
  restore: "Restored",
  trash: "Moved to trash",
  delete_forever: "Deleted forever",
};

function bulkAllowed(action) {
  const f = state.query ? "all" : state.folder;
  if (action === "restore" || action === "delete_forever") return f === "trash";
  if (action === "not_spam") return f === "spam";
  if (action === "trash") return f !== "trash";
  if (action === "star") return f !== "trash";
  return f !== "trash" && f !== "drafts";
}

function updateBulk() {
  const n = state.picked.size;
  const total = state.items.length;
  const all = $("pick-all");
  all.checked = n > 0 && n === total;
  all.indeterminate = n > 0 && n < total;
  all.disabled = total === 0;
  $("bulk").classList.toggle("hidden", n === 0);
  document.querySelector(".list-pane").classList.toggle("picking", n > 0);
  document.querySelectorAll("[data-bulk]").forEach((b) => b.classList.toggle("hidden", !bulkAllowed(b.dataset.bulk)));
  $("tools-label").textContent = n > 0 ? n + " selected" : (state.query ? "All folders" : "Newest first");
}

$("pick-all").addEventListener("change", (event) => {
  state.picked = event.target.checked ? new Set(state.items.map((m) => m.id)) : new Set();
  document.querySelectorAll(".msg").forEach((row) => {
    const on = state.picked.has(row.dataset.id);
    row.classList.toggle("picked", on);
    const box = row.querySelector(".pick");
    if (box) box.checked = on;
  });
  updateBulk();
});

document.querySelectorAll("[data-bulk]").forEach((button) => {
  button.addEventListener("click", async () => {
    const action = button.dataset.bulk;
    const ids = [...state.picked];
    if (ids.length === 0) return;
    if (action === "delete_forever") {
      const ok = await confirmDialog({
        title: "Delete " + ids.length + (ids.length === 1 ? " message" : " messages") + " forever?",
        message: "They'll be removed from your mailbox and can't be recovered.",
        confirmText: "Delete forever",
        danger: true,
      });
      if (!ok) return;
    }
    document.querySelectorAll("[data-bulk]").forEach((b) => (b.disabled = true));
    const results = await Promise.allSettled(ids.map((id) => messageAction(id, action)));
    document.querySelectorAll("[data-bulk]").forEach((b) => (b.disabled = false));
    const done = results.filter((r) => r.status === "fulfilled").length;
    const failed = results.length - done;
    if (state.selectedId && ids.includes(state.selectedId) && !["read", "star"].includes(action)) closeReader();
    if (done) toast(BULK_ACTIONS[action] + " · " + done + (done === 1 ? " message" : " messages"), "success");
    if (failed) toast(failed + (failed === 1 ? " message" : " messages") + " couldn't be changed: " + results.find((r) => r.status === "rejected").reason.message, "error");
    loadMessages({ quiet: true });
  });
});

// ---------- Reading pane ----------
async function openMessage(id) {
  state.selectedId = id;
  document.querySelectorAll(".msg.selected").forEach((r) => r.classList.remove("selected"));
  const row = rowFor(id);
  if (row) row.classList.add("selected");

  showReader();
  const article = $("read-article");
  article.replaceChildren(readerSkeleton());

  try {
    const data = await api("/api/messages/" + encodeURIComponent(id));
    if (state.selectedId !== id) return;
    state.current = data.message;
    renderReader(data.message);
    $("read-scroll").scrollTop = 0;

    // The server marks it as read
    const item = state.items.find((m) => m.id === id);
    if (item && !item.is_read) {
      item.is_read = true;
      replaceRow(item);
      const fresh = rowFor(id);
      if (fresh) fresh.classList.add("selected");
    }
    Shell.refreshCounts();
  } catch (err) {
    article.replaceChildren(el("div", "alert alert-error", err.message));
  }
}

function readerSkeleton() {
  const box = el("div", "read-loading");
  [["60%", 26], ["35%", 14], ["100%", 12], ["94%", 12], ["88%", 12], ["40%", 12]].forEach(([w, h]) => {
    const s = el("span", "skeleton");
    s.style.width = w;
    s.style.height = h + "px";
    box.append(s);
  });
  return box;
}

function showReader() {
  $("read-empty").classList.add("hidden");
  $("read-view").classList.remove("hidden");
  const mail = $("mail");
  document.body.classList.add("mail-reading");
  if (!mail.classList.contains("reading")) {
    mail.classList.add("reading");
    if (window.matchMedia("(max-width: 900px)").matches) history.pushState({ reading: true }, "");
  }
}

function closeReader({ fromHistory = false } = {}) {
  const mail = $("mail");
  const wasReading = mail.classList.contains("reading");
  state.current = null;
  state.selectedId = null;
  mail.classList.remove("reading");
  document.body.classList.remove("mail-reading");
  document.querySelectorAll(".msg.selected").forEach((r) => r.classList.remove("selected"));
  $("read-view").classList.add("hidden");
  $("read-empty").classList.remove("hidden");
  if (wasReading && !fromHistory && history.state && history.state.reading) history.back();
}

window.addEventListener("popstate", () => {
  if ($("mail").classList.contains("reading") && !(history.state && history.state.reading)) {
    closeReader({ fromHistory: true });
  }
});

// ---- Email design (HTML) ----
// The server has already cleaned the HTML (no scripts, no forms...). On top of
// that it is shown inside a sandboxed iframe: no scripts can run, links open in
// a new tab, and a Content-Security-Policy decides which images may load.
// Pictures from other websites can tell the sender you opened the email, so
// they stay hidden until the user clicks "Show images" (like Gmail).
function hasRemoteImages(html) {
  return /<img[^>]+src="https?:/i.test(html);
}

function htmlBody(html) {
  const wrap = el("div", "read-body read-html");
  const remote = hasRemoteImages(html);

  const frame = document.createElement("iframe");
  frame.className = "mail-html";
  frame.title = "Message";
  frame.setAttribute("sandbox", "allow-same-origin allow-popups allow-popups-to-escape-sandbox");
  frame.setAttribute("referrerpolicy", "no-referrer");

  const fit = () => {
    try {
      const doc = frame.contentDocument;
      if (doc && doc.documentElement) {
        frame.style.height = Math.max(doc.documentElement.scrollHeight, 60) + "px";
      }
    } catch (_) { /* ignore */ }
  };
  frame.addEventListener("load", () => {
    fit();
    try {
      frame.contentDocument.querySelectorAll("img").forEach((img) => {
        if (!img.complete) img.addEventListener("load", fit);
      });
    } catch (_) { /* ignore */ }
    setTimeout(fit, 400);
  });

  const show = (allowRemote) => {
    const imgSrc = allowRemote ? "data: https: http:" : "data:";
    frame.srcdoc =
      '<!doctype html><html><head><meta charset="utf-8">' +
      '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src ' + imgSrc +
      '; style-src \'unsafe-inline\'; font-src data:">' +
      '<meta name="viewport" content="width=device-width, initial-scale=1">' +
      '<base target="_blank">' +
      "<style>html,body{margin:0;padding:0;background:#fff;color:#202124}" +
      "body{padding:16px;font:14px/1.5 Arial,Helvetica,sans-serif;overflow-wrap:anywhere}" +
      "img{max-width:100%;height:auto}table{max-width:100%}a{color:#1a73e8}</style>" +
      "</head><body>" + html + "</body></html>";
  };

  if (remote) {
    const bar = el("div", "images-bar");
    bar.append(el("span", null, "Images are hidden to protect your privacy."));
    const btn = el("button", "btn btn-ghost btn-sm", "Show images");
    btn.type = "button";
    btn.addEventListener("click", () => { show(true); bar.remove(); });
    bar.append(btn);
    wrap.append(bar);
  }
  wrap.append(frame);
  show(false);
  return wrap;
}

function renderReader(m) {
  const article = $("read-article");
  const outgoing = isOutgoing(m);

  const subject = el("h2", "read-subject", m.subject || "(no subject)");
  const tags = el("div", "read-tags");
  tags.append(el("span", "badge no-dot", FOLDERS[m.folder] ? FOLDERS[m.folder].title : m.folder));
  if (m.is_starred) tags.append(el("span", "badge badge-warning no-dot", "Starred"));

  const from = el("div", "read-from");
  const text = el("div", "read-from-text");
  const name = el("div", "read-from-name", nameFromEmail(m.from));
  name.append(el("span", null, "<" + m.from + ">"));
  text.append(name, el("div", "read-to", "To: " + ((m.to || []).join(", ") || "(no recipients)")));
  const date = el("time", "read-date", formatFullDate(m.created_at));
  date.dateTime = m.created_at;
  from.append(avatar(m.from, "lg"), text, date);

  // Email design (Gmail templates: logos, header, footer) is shown in a locked
  // frame; otherwise the plain text is shown.
  const body = m.body_html ? htmlBody(m.body_html) : el("div", "read-body", m.body || "");

  article.replaceChildren(subject, tags, from, body);

  if (m.attachments && m.attachments.length) {
    const box = el("div", "attachments");
    const title = el("div", "attachments-title");
    title.append(icon("paperclip", "i-sm"), el("span", null, m.attachments.length + (m.attachments.length === 1 ? " attachment" : " attachments")));
    const grid = el("div", "attachment-grid");
    m.attachments.forEach((a) => {
      const ext = (a.filename.split(".").pop() || "").toLowerCase();
      const link = el("a", "attachment");
      link.href = "/api/attachments/" + encodeURIComponent(a.id);
      link.setAttribute("download", a.filename);
      link.setAttribute("aria-label", "Download " + a.filename);
      const kind = ext === "pdf" ? "pdf" : ["jpg", "jpeg", "png", "gif"].includes(ext) ? "img" : "";
      const badge = el("span", "attachment-icon " + kind);
      badge.append(icon(kind === "img" ? "image" : "file"));
      const t = el("span", "attachment-text");
      t.append(el("strong", null, a.filename), el("span", null, ext.toUpperCase() + " · " + formatSize(a.size)));
      link.append(badge, t, icon("download", "i-sm"));
      grid.append(link);
    });
    box.append(title, grid);
    article.append(box);
  }

  if (m.folder !== "trash") {
    const bar = el("div", "reply-bar");
    const reply = el("button", "btn");
    reply.type = "button";
    reply.append(icon("reply", "i-sm"), el("span", null, outgoing ? "Write again" : "Reply"));
    reply.addEventListener("click", () => replyTo(m));
    const forward = el("button", "btn");
    forward.type = "button";
    forward.append(icon("forward", "i-sm"), el("span", null, "Forward"));
    forward.addEventListener("click", () => forwardMessage(m));
    bar.append(reply);
    if (canReplyAll(m)) {
      const all = el("button", "btn");
      all.type = "button";
      all.append(icon("reply-all", "i-sm"), el("span", null, "Reply all"));
      all.addEventListener("click", () => replyAll(m));
      bar.append(all);
    }
    bar.append(forward);
    article.append(bar);
  }

  updateToolbar(m);
}

function setIcon(button, name) {
  button.querySelector("use").setAttribute("href", "/icons.svg#" + name);
}

function updateToolbar(m) {
  const inTrash = m.folder === "trash";
  const inSpam = m.folder === "spam";
  const star = $("star-btn");
  setIcon(star, m.is_starred ? "star-fill" : "star");
  star.style.color = m.is_starred ? "#E9A23B" : "";
  star.setAttribute("aria-pressed", String(m.is_starred));
  star.setAttribute("aria-label", m.is_starred ? "Unstar" : "Star");
  star.dataset.tip = m.is_starred ? "Unstar" : "Star";

  star.classList.toggle("hidden", inTrash);
  $("unread-btn").classList.toggle("hidden", inTrash);
  $("spam-btn").classList.toggle("hidden", m.folder !== "inbox");
  $("trash-btn").classList.toggle("hidden", inTrash);
  $("restore-btn").classList.toggle("hidden", !(inTrash || inSpam));
  $("restore-btn").querySelector("span").textContent = inSpam ? "Not spam" : "Restore";
  $("delete-forever-btn").classList.toggle("hidden", !inTrash);
  $("reply-btn-top").classList.toggle("hidden", inTrash);
  $("forward-btn-top").classList.toggle("hidden", inTrash);
  $("reply-all-btn-top").classList.toggle("hidden", !canReplyAll(m));
}

async function toolbarAction(action, successText) {
  const m = state.current;
  if (!m) return;
  try {
    await messageAction(m.id, action);
    toast(successText, "success");
    const id = m.id;
    closeReader();
    removeRow(id);
    Shell.refreshCounts();
  } catch (err) {
    toast(err.message, "error");
  }
}

// ---------- Reply and forward (prefill compose; sending uses the normal send) ----------
function quoteBody(m) {
  const lines = (m.body || "").split("\n").map((line) => "> " + line).join("\n");
  return "\n\nOn " + formatFullDate(m.created_at) + ", " + m.from + " wrote:\n" + lines;
}

function withPrefix(prefix, subject) {
  const s = subject || "";
  return new RegExp("^" + prefix + ":\\s", "i").test(s) ? s : prefix + ": " + s;
}

function myAddressIn(list) {
  const mine = [...composeForm.elements.from.options].map((o) => o.value);
  return (list || []).find((email) => mine.includes(email));
}

function replyTo(m) {
  const outgoing = isOutgoing(m);
  const to = outgoing ? m.to || [] : [m.from];
  const from = outgoing ? m.from : myAddressIn(m.to);
  openCompose({ to, from, subject: withPrefix("Re", m.subject), body: quoteBody(m), focus: "body", title: "Reply" });
}

// Everyone on the message except you
function replyAllRecipients(m) {
  const mine = [...composeForm.elements.from.options].map((o) => o.value);
  const list = [m.from, ...(m.to || [])].filter((email) => !mine.includes(email));
  return [...new Set(list)];
}

function canReplyAll(m) {
  return !isOutgoing(m) && m.folder !== "trash" && replyAllRecipients(m).length > 1;
}

function replyAll(m) {
  openCompose({
    to: replyAllRecipients(m),
    from: myAddressIn(m.to),
    subject: withPrefix("Re", m.subject),
    body: quoteBody(m),
    focus: "body",
    title: "Reply all",
  });
}

function forwardMessage(m) {
  const header = "\n\n---------- Forwarded message ----------\n" +
    "From: " + m.from + "\n" +
    "Date: " + formatFullDate(m.created_at) + "\n" +
    "Subject: " + (m.subject || "(no subject)") + "\n" +
    "To: " + (m.to || []).join(", ") + "\n\n" + (m.body || "");
  openCompose({
    from: isOutgoing(m) ? m.from : myAddressIn(m.to),
    subject: withPrefix("Fwd", m.subject),
    body: header,
    title: "Forward",
    notice: m.attachments && m.attachments.length
      ? "Attachments from the original message aren't included when forwarding. Attach them again if needed."
      : "",
  });
}

// ---------- Compose ----------
const compose = $("compose");
const composeForm = $("compose-form");

function composeSnapshot() {
  return [composeForm.elements.to.value, composeForm.elements.subject.value, composeForm.elements.body.value, state.files.length].join("\u0000");
}

function showComposeMessage(text, type = "error") {
  const box = $("compose-message");
  box.className = "alert alert-" + type;
  box.replaceChildren(icon(type === "error" ? "alert" : "info", "i-sm"), el("span", null, text));
}

function hideComposeMessage() {
  $("compose-message").className = "alert hidden";
}

function openCompose(prefill = {}) {
  if (compose.classList.contains("open") && isComposeDirty()) {
    // Don't throw away what's being written: bring the window back instead
    compose.classList.remove("minimized");
    toast("Finish or close the message you're writing first.");
    composeForm.elements.body.focus();
    return;
  }
  composeForm.reset();
  if (prefill.from && [...composeForm.elements.from.options].some((o) => o.value === prefill.from)) {
    composeForm.elements.from.value = prefill.from;
  }
  state.files = [];
  renderFileList();
  state.draftId = prefill.id || null;
  composeForm.elements.to.value = (prefill.to || []).join(", ");
  composeForm.elements.subject.value = prefill.subject || "";
  composeForm.elements.body.value = prefill.body || "";
  $("compose-title").textContent = prefill.title || (state.draftId ? "Edit draft" : "New message");
  if (prefill.notice) showComposeMessage(prefill.notice, "info");
  else hideComposeMessage();

  compose.classList.remove("minimized");
  compose.classList.add("open");
  compose.setAttribute("aria-hidden", "false");
  document.body.classList.add("compose-open");
  state.composeSnapshot = composeSnapshot();

  requestAnimationFrame(() => {
    const target = prefill.focus === "body" ? composeForm.elements.body
      : composeForm.elements.to.value ? composeForm.elements.subject : composeForm.elements.to;
    target.focus();
    if (prefill.focus === "body") target.setSelectionRange(0, 0);
  });
}

function isComposeDirty() {
  return composeSnapshot() !== state.composeSnapshot;
}

function hideCompose() {
  compose.classList.remove("open", "expanded");
  compose.setAttribute("aria-hidden", "true");
  document.body.classList.remove("compose-open");
  state.draftId = null;
  const button = $("compose-btn");
  if (button && window.matchMedia("(min-width: 1181px)").matches) button.focus();
}

// Closing with unsaved changes asks what to do
function closeCompose() {
  if (!compose.classList.contains("open")) return;
  if (!isComposeDirty()) {
    hideCompose();
    return;
  }
  const box = el("div", "modal");
  const head = el("div", "modal-head");
  const text = el("div");
  const h = el("h2", null, "Save this message as a draft?");
  h.id = "discard-title";
  box.setAttribute("aria-labelledby", "discard-title");
  text.append(h, el("p", null, state.files.length
    ? "Your text will be saved. Attachments aren't stored in drafts."
    : "You can finish it later from Drafts."));
  head.append(text);
  const foot = el("div", "modal-foot");
  foot.style.paddingTop = "22px";
  const discard = el("button", "btn btn-danger", "Discard");
  const keep = el("button", "btn", "Keep editing");
  const save = el("button", "btn btn-primary", "Save draft");
  [discard, keep, save].forEach((b) => (b.type = "button"));
  foot.append(discard, keep, save);
  box.append(head, foot);
  const close = openModal(box);
  keep.addEventListener("click", close);
  discard.addEventListener("click", () => {
    close();
    hideCompose();
    toast("Message discarded");
  });
  save.addEventListener("click", async () => {
    close();
    if (await saveDraft()) hideCompose();
  });
}

function renderFileList() {
  const list = $("file-list");
  list.replaceChildren();
  state.files.forEach((file, index) => {
    const item = el("li", "file-chip");
    const remove = iconButton("x", "Remove " + file.name, "icon-btn");
    remove.addEventListener("click", () => {
      state.files.splice(index, 1);
      renderFileList();
    });
    item.append(icon("paperclip", "i-sm"), el("span", null, file.name), el("small", null, formatSize(file.size)), remove);
    list.append(item);
  });
  const total = state.files.reduce((sum, f) => sum + f.size, 0);
  $("compose-hint").textContent = state.files.length
    ? state.files.length + " of " + MAX_FILES + " files · " + formatSize(total)
    : "Up to 5 files, 10 MB each";
}

function parseRecipients(text) {
  return text.split(/[,;\s]+/).map((s) => s.trim().toLowerCase()).filter(Boolean);
}

async function openDraft(id) {
  try {
    const data = await api("/api/messages/" + encodeURIComponent(id));
    openCompose(data.message);
  } catch (err) {
    toast(err.message, "error");
  }
}

async function saveDraft() {
  const button = $("save-draft-btn");
  setBusy(button, true, "Saving…");
  try {
    const result = await api("/api/drafts", {
      method: "POST",
      body: {
        draft_id: state.draftId,
        to: parseRecipients(composeForm.elements.to.value),
        subject: composeForm.elements.subject.value,
        body: composeForm.elements.body.value,
      },
    });
    state.draftId = result.draft_id;
    state.composeSnapshot = composeSnapshot();
    toast(state.files.length ? "Draft saved (attachments aren't kept in drafts)" : "Draft saved", "success");
    if (state.folder === "drafts" && !state.query) loadMessages({ quiet: true });
    Shell.refreshCounts();
    return true;
  } catch (err) {
    showComposeMessage(err.message);
    return false;
  } finally {
    setBusy(button, false);
  }
}

async function loadFromAddresses() {
  const select = $("compose-from");
  try {
    const data = await api("/api/domains/from-addresses");
    select.replaceChildren();
    data.addresses.forEach((email) => {
      const option = el("option", null, email);
      option.value = email;
      select.append(option);
    });
    select.closest(".compose-row").classList.toggle("hidden", data.addresses.length < 2);
  } catch {
    // If this fails, the server uses your main address
    select.closest(".compose-row").classList.add("hidden");
  }
}

$("attachments").addEventListener("change", (event) => {
  hideComposeMessage();
  for (const file of event.target.files) {
    const ext = file.name.includes(".") ? file.name.split(".").pop().toLowerCase() : "";
    if (!ALLOWED_EXTENSIONS.includes(ext)) {
      showComposeMessage("“" + file.name + "” can't be attached. Allowed: images, PDF, Word and text files.");
      continue;
    }
    if (file.size > MAX_FILE_MB * 1024 * 1024) {
      showComposeMessage("“" + file.name + "” is larger than " + MAX_FILE_MB + " MB.");
      continue;
    }
    if (state.files.length >= MAX_FILES) {
      showComposeMessage("You can attach up to " + MAX_FILES + " files.");
      break;
    }
    state.files.push(file);
  }
  event.target.value = ""; // allow choosing the same file again
  renderFileList();
});

// The paperclip is a <label>; make it work with the keyboard too
document.querySelector(".attach-btn").addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    $("attachments").click();
  }
});

composeForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  hideComposeMessage();

  const recipients = parseRecipients(composeForm.elements.to.value);
  if (recipients.length === 0) {
    showComposeMessage("Add at least one recipient.");
    composeForm.elements.to.focus();
    return;
  }
  const invalid = recipients.find((r) => !EMAIL_PATTERN.test(r));
  if (invalid) {
    showComposeMessage("“" + invalid + "” isn't a valid email address.");
    composeForm.elements.to.focus();
    return;
  }
  if (!composeForm.elements.subject.value.trim()) {
    const ok = await confirmDialog({
      title: "Send without a subject?",
      message: "A short subject helps people find your message later.",
      confirmText: "Send anyway",
      cancelText: "Add a subject",
      iconName: "info",
    });
    if (!ok) {
      composeForm.elements.subject.focus();
      return;
    }
  }

  // FormData is needed because we are sending files
  const formData = new FormData();
  if (composeForm.elements.from.value) formData.append("from", composeForm.elements.from.value);
  formData.append("to", recipients.join(","));
  formData.append("subject", composeForm.elements.subject.value.trim());
  formData.append("body", composeForm.elements.body.value);
  if (state.draftId) formData.append("draft_id", state.draftId);
  state.files.forEach((file) => formData.append("attachments", file));

  const sendButton = $("send-btn");
  setBusy(sendButton, true, "Sending…");
  try {
    const result = await api("/api/messages/send", { method: "POST", body: formData });
    setBusy(sendButton, false);
    hideCompose();
    toast((result && result.message) || "Message sent", "success");
    if (["sent", "drafts"].includes(state.folder) || state.query) loadMessages({ quiet: true });
    else Shell.refreshCounts();
  } catch (err) {
    setBusy(sendButton, false);
    showComposeMessage(err.message);
  }
});

$("save-draft-btn").addEventListener("click", saveDraft);
$("compose-close").addEventListener("click", closeCompose);
$("discard-btn").addEventListener("click", async () => {
  if (isComposeDirty()) {
    const ok = await confirmDialog({
      title: "Discard this message?",
      message: state.draftId ? "Changes since you last saved will be lost. The saved draft stays in Drafts." : "What you've written will be lost.",
      confirmText: "Discard",
      danger: true,
    });
    if (!ok) return;
  }
  hideCompose();
  toast("Message discarded");
});
$("compose-min").addEventListener("click", () => {
  compose.classList.toggle("minimized");
  compose.classList.remove("expanded");
});
$("compose-expand").addEventListener("click", () => {
  compose.classList.toggle("expanded");
  compose.classList.remove("minimized");
  setIcon($("compose-expand"), "expand");
});
document.querySelector(".compose-head").addEventListener("click", (event) => {
  if (compose.classList.contains("minimized") && !event.target.closest("button")) compose.classList.remove("minimized");
});
composeForm.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
    event.preventDefault();
    composeForm.requestSubmit();
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && compose.classList.contains("open") && !document.querySelector(".modal-backdrop")) {
    if (compose.contains(document.activeElement)) closeCompose();
  }
});

// ---------- Toolbar ----------
$("back-btn").addEventListener("click", () => closeReader());
$("star-btn").addEventListener("click", () => {
  const m = state.current;
  if (!m) return;
  const item = state.items.find((x) => x.id === m.id) || m;
  toggleStar(item);
});
$("unread-btn").addEventListener("click", async () => {
  const m = state.current;
  if (!m) return;
  try {
    await messageAction(m.id, "unread");
    const item = state.items.find((x) => x.id === m.id);
    closeReader();
    if (item) { item.is_read = false; replaceRow(item); }
    Shell.refreshCounts();
    toast("Marked as unread", "success");
  } catch (err) {
    toast(err.message, "error");
  }
});
$("spam-btn").addEventListener("click", () => toolbarAction("spam", "Moved to spam"));
$("trash-btn").addEventListener("click", () => toolbarAction("trash", "Moved to trash"));
$("restore-btn").addEventListener("click", () => {
  const inSpam = state.current && state.current.folder === "spam";
  toolbarAction(inSpam ? "not_spam" : "restore", inSpam ? "Moved to inbox" : "Message restored");
});
$("delete-forever-btn").addEventListener("click", async () => {
  const ok = await confirmDialog({
    title: "Delete this message forever?",
    message: "It will be removed from your mailbox and can't be recovered.",
    confirmText: "Delete forever",
    danger: true,
  });
  if (ok) toolbarAction("delete_forever", "Message deleted forever");
});
$("reply-btn-top").addEventListener("click", () => state.current && replyTo(state.current));
$("reply-all-btn-top").addEventListener("click", () => state.current && replyAll(state.current));
$("forward-btn-top").addEventListener("click", () => state.current && forwardMessage(state.current));

// ---------- Search, refresh, pages ----------
function setSearch(q) {
  state.query = q;
  state.page = 1;
  const input = $("search-input");
  if (input && input.value !== q) {
    input.value = q;
    input.closest("form").classList.toggle("has-value", q !== "");
  }
  closeReader();
  loadMessages();
}
document.addEventListener("mailsearch", (event) => setSearch(event.detail));
document.addEventListener("compose", () => openCompose());

$("refresh-btn").addEventListener("click", (event) => {
  const svg = event.currentTarget.querySelector("svg");
  svg.animate([{ transform: "rotate(0)" }, { transform: "rotate(360deg)" }], { duration: 600, easing: "ease-out" });
  loadMessages({ quiet: true });
});
$("prev-btn").addEventListener("click", () => {
  if (state.page > 1) { state.page--; loadMessages(); $("message-list").scrollTop = 0; }
});
$("next-btn").addEventListener("click", () => {
  if (state.page < state.totalPages) { state.page++; loadMessages(); $("message-list").scrollTop = 0; }
});

// Clicking a folder changes the #hash
window.addEventListener("hashchange", () => {
  const folder = folderFromHash();
  if (folder === state.folder && !state.query && location.hash !== "") return;
  state.folder = folder;
  state.page = 1;
  state.query = "";
  const input = $("search-input");
  if (input) { input.value = ""; input.closest("form").classList.remove("has-value"); }
  closeReader({ fromHistory: true });
  loadMessages();
});

// Check for new mail every minute while the tab is visible
setInterval(async () => {
  if (document.hidden) return;
  const before = document.getElementById("count-inbox").textContent;
  await Shell.refreshCounts();
  const after = document.getElementById("count-inbox").textContent;
  if (after !== before && state.folder === "inbox" && !state.query && state.page === 1) {
    loadMessages({ quiet: true });
  }
}, 60000);

// ---------- Start ----------
(function start() {
  const params = new URLSearchParams(location.search);
  state.folder = folderFromHash();
  state.query = (params.get("q") || "").trim();
  if (params.has("q") || params.has("compose")) {
    history.replaceState(null, "", "/inbox" + location.hash);
  }
  Shell.userReady.then(() => {
    loadMessages();
    loadFromAddresses().then(() => {
      if (params.has("compose")) openCompose();
    });
  }).catch(() => renderListError("Couldn't reach MailSpace. Check your connection and refresh."));
})();

// ============================================================
// Resizable divider between the message list and reading pane
// ============================================================
(function () {
  const mail = document.getElementById("mail");
  const handle = document.getElementById("pane-resizer");
  if (!mail || !handle) return;
  const KEY = "mailspace-list-width";
  const DEFAULT = 380, MIN = 280, MIN_READ = 360;

  const maxWidth = () => Math.max(MIN, mail.clientWidth - MIN_READ);
  const clamp = (w) => Math.round(Math.min(maxWidth(), Math.max(MIN, w)));
  let width = DEFAULT;

  function apply(w, save) {
    width = clamp(w);
    mail.style.setProperty("--list-w", width + "px");
    handle.setAttribute("aria-valuenow", String(width));
    handle.setAttribute("aria-valuemin", String(MIN));
    handle.setAttribute("aria-valuemax", String(maxWidth()));
    if (save) { try { localStorage.setItem(KEY, String(width)); } catch (e) {} }
  }

  let saved = DEFAULT;
  try { saved = parseInt(localStorage.getItem(KEY), 10) || DEFAULT; } catch (e) {}
  apply(saved, false);

  handle.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    handle.setPointerCapture(e.pointerId);
    const left = mail.getBoundingClientRect().left;
    document.body.classList.add("resizing");
    const move = (ev) => apply(ev.clientX - left, false);
    const up = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", up);
      handle.removeEventListener("pointercancel", up);
      document.body.classList.remove("resizing");
      apply(width, true);
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", up);
    handle.addEventListener("pointercancel", up);
  });

  // Keyboard: arrows move 20px (Shift = 60px), Home/End jump to the limits
  handle.addEventListener("keydown", (e) => {
    const step = e.shiftKey ? 60 : 20;
    const map = { ArrowLeft: width - step, ArrowRight: width + step, Home: MIN, End: maxWidth() };
    if (!(e.key in map)) return;
    e.preventDefault();
    apply(map[e.key], true);
  });

  handle.addEventListener("dblclick", () => apply(DEFAULT, true));
  window.addEventListener("resize", () => apply(width, false));
})();

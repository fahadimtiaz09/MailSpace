// ============================================================
// app.js — the inbox page (folders, reading, compose)
// ============================================================

const FOLDERS = {
  inbox:   { title: "Inbox",   empty: "Your inbox is empty 🎉" },
  sent:    { title: "Sent",    empty: "You haven't sent any messages yet." },
  drafts:  { title: "Drafts",  empty: "No drafts saved." },
  starred: { title: "Starred", empty: "No starred messages." },
  spam:    { title: "Spam",    empty: "No spam. Nice!" },
  trash:   { title: "Trash",   empty: "Trash is empty." },
};

const MAX_FILES = 5;
const MAX_FILE_MB = 10;
const ALLOWED_EXTENSIONS = ["jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "txt"];
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Everything the page needs to remember
const state = {
  folder: "inbox",
  page: 1,
  totalPages: 1,
  query: "",
  current: null,   // the message that is open right now
  draftId: null,   // set when editing an existing draft
  files: [],       // files chosen in the compose window
};

const $ = (id) => document.getElementById(id);

// ---------- Small helpers ----------
let toastTimer;
function showToast(text, isError = false) {
  const toast = $("toast");
  toast.textContent = text;
  toast.className = "toast" + (isError ? " error" : "");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toast.className = "toast hidden"), 3000);
}

function showBanner(text) {
  $("banner").textContent = text;
  $("banner").classList.remove("hidden");
}

function showState(type, text) {
  const box = $("list-state");
  box.className = "state" + (type === "error" ? " error" : "");
  box.replaceChildren();
  if (type === "loading") {
    box.append(el("div", "spinner"), el("div", null, "Loading messages..."));
  } else {
    box.append(el("div", null, text));
  }
}

function hideState() {
  $("list-state").className = "state hidden";
}

// ---------- Logged-in user ----------
async function loadUser() {
  try {
    const data = await api("/api/auth/me");
    // Logged in: show email and Log out
    $("user-email").textContent = data.user.email;
    $("logout-btn").classList.remove("hidden");
    renderProfile(data.user);
  } catch (err) {
    if (err.status === 401) {
      window.location.href = "/login.html"; // not logged in -> go to login page
      return;
    }
    // Backend not ready yet: show Log in / Sign up buttons
    $("login-link").classList.remove("hidden");
    $("signup-link").classList.remove("hidden");
    showBanner("⚠️ " + err.message + " You are seeing the design only.");
  }
}

function renderProfile(user) {
  $("profile-box").replaceChildren(
    el("div", "profile-name", user.username),
    el("div", null, user.email)
  );
}

// ---------- Folders ----------
function folderFromHash() {
  const name = location.hash.replace("#", "");
  return FOLDERS[name] ? name : "inbox";
}

function updateHeading() {
  document.querySelectorAll(".folder-link").forEach((link) => {
    link.classList.toggle("active", !state.query && link.dataset.folder === state.folder);
  });
  $("folder-title").textContent = state.query
    ? 'Search results for "' + state.query + '"'
    : FOLDERS[state.folder].title;
}

// ---------- Message list ----------
async function loadMessages() {
  updateHeading();
  $("message-list").replaceChildren();
  $("pager").classList.add("hidden");
  showState("loading");

  const params = new URLSearchParams({
    folder: state.query ? "all" : state.folder,
    page: state.page,
  });
  if (state.query) params.set("q", state.query);

  try {
    const data = await api("/api/messages?" + params.toString());
    state.totalPages = data.total_pages || 1;

    if (data.messages.length === 0) {
      showState("empty", state.query ? "No messages match your search." : FOLDERS[state.folder].empty);
    } else {
      hideState();
      data.messages.forEach((m) => $("message-list").append(renderMessageItem(m)));
    }
    updatePager();
  } catch (err) {
    showState("error", err.message);
  }
  loadCounts();
}

function renderMessageItem(m) {
  const li = el("li", "message-item" + (m.is_read ? "" : " unread"));

  // Star button
  const star = el("button", "star-toggle" + (m.is_starred ? " starred" : ""), m.is_starred ? "★" : "☆");
  star.title = m.is_starred ? "Unstar" : "Star";
  star.addEventListener("click", async (event) => {
    event.stopPropagation(); // don't open the message
    try {
      await messageAction(m.id, m.is_starred ? "unstar" : "star");
      m.is_starred = !m.is_starred;
      if (state.folder === "starred" && !state.query) loadMessages();
      else li.replaceWith(renderMessageItem(m));
    } catch (err) {
      showToast(err.message, true);
    }
  });

  // Sender (or recipients for sent mail and drafts)
  const outgoing = m.folder === "sent" || m.folder === "drafts";
  const who = outgoing
    ? "To: " + (m.to && m.to.length ? m.to.join(", ") : "(no recipients)")
    : m.from;

  const main = el("div", "msg-main");
  const text = el("div", "msg-text");
  text.append(
    el("span", null, m.subject || "(no subject)"),
    el("span", "msg-snippet", m.snippet ? " — " + m.snippet : "")
  );
  main.append(el("div", "msg-from", who), text);

  const date = el("div", "msg-date", (m.has_attachments ? "📎 " : "") + formatDate(m.created_at));

  li.append(star, main, date);
  li.addEventListener("click", () => (m.folder === "drafts" ? openDraft(m.id) : openMessage(m.id)));
  return li;
}

function updatePager() {
  $("pager").classList.toggle("hidden", state.totalPages <= 1);
  $("page-info").textContent = "Page " + state.page + " of " + state.totalPages;
  $("prev-btn").disabled = state.page <= 1;
  $("next-btn").disabled = state.page >= state.totalPages;
}

async function loadCounts() {
  try {
    const counts = await api("/api/messages/counts");
    ["inbox", "drafts", "spam"].forEach((name) => {
      const n = counts[name] || 0;
      $("count-" + name).textContent = n > 0 ? n : "";
    });
  } catch {
    // Counts are optional. Ignore errors here.
  }
}

// ---------- Reading one message ----------
function messageAction(id, action) {
  return api("/api/messages/" + encodeURIComponent(id), { method: "PATCH", body: { action } });
}

async function openMessage(id) {
  try {
    const data = await api("/api/messages/" + encodeURIComponent(id));
    state.current = data.message;
    renderReadView(data.message);
    $("list-view").classList.add("hidden");
    $("read-view").classList.remove("hidden");
    loadCounts(); // the backend marks it as read
  } catch (err) {
    showToast(err.message, true);
  }
}

function metaLine(label, value) {
  const line = el("div");
  line.append(el("strong", null, label + ": "), document.createTextNode(value));
  return line;
}

function renderReadView(m) {
  $("read-subject").textContent = m.subject || "(no subject)";
  $("read-meta").replaceChildren(
    metaLine("From", m.from),
    metaLine("To", (m.to || []).join(", ")),
    metaLine("Date", new Date(m.created_at).toLocaleString())
  );
  $("read-body").textContent = m.body || ""; // shown as plain text, never as HTML

  const box = $("read-attachments");
  box.replaceChildren();
  (m.attachments || []).forEach((a) => {
    const link = el("a", "attachment", "📎 " + a.filename + " (" + formatSize(a.size) + ")");
    link.href = "/api/attachments/" + encodeURIComponent(a.id);
    box.append(link);
  });

  updateToolbar(m);
}

function updateToolbar(m) {
  const inTrash = m.folder === "trash";
  const inSpam = m.folder === "spam";
  $("star-btn").textContent = m.is_starred ? "★ Starred" : "☆ Star";
  $("star-btn").classList.toggle("hidden", inTrash);
  $("unread-btn").classList.toggle("hidden", inTrash);
  $("spam-btn").classList.toggle("hidden", inTrash || inSpam || m.folder === "sent");
  $("trash-btn").classList.toggle("hidden", inTrash);
  $("restore-btn").classList.toggle("hidden", !(inTrash || inSpam));
  $("restore-btn").textContent = inSpam ? "Not spam" : "Restore";
  $("delete-forever-btn").classList.toggle("hidden", !inTrash);
}

function showListView() {
  state.current = null;
  $("read-view").classList.add("hidden");
  $("list-view").classList.remove("hidden");
}

async function toolbarAction(action, successText, goBackToList) {
  const m = state.current;
  if (!m) return;
  try {
    await messageAction(m.id, action);
    showToast(successText);
    if (goBackToList) {
      showListView();
      loadMessages();
    } else {
      if (action === "star") m.is_starred = true;
      if (action === "unstar") m.is_starred = false;
      updateToolbar(m);
    }
  } catch (err) {
    showToast(err.message, true);
  }
}

// ---------- Compose ----------
function showComposeMessage(text) {
  $("compose-message").textContent = text;
  $("compose-message").className = "alert alert-error";
}

function hideComposeMessage() {
  $("compose-message").className = "alert hidden";
}

function openCompose(prefill = {}) {
  const form = $("compose-form");
  form.reset();
  state.files = [];
  renderFileList();
  state.draftId = prefill.id || null;
  form.elements.to.value = (prefill.to || []).join(", ");
  form.elements.subject.value = prefill.subject || "";
  form.elements.body.value = prefill.body || "";
  $("compose-title").textContent = state.draftId ? "Edit draft" : "New message";
  hideComposeMessage();
  $("compose-modal").classList.remove("hidden");
  form.elements.to.focus();
}

function closeCompose() {
  $("compose-modal").classList.add("hidden");
}

async function openDraft(id) {
  try {
    const data = await api("/api/messages/" + encodeURIComponent(id));
    openCompose(data.message);
  } catch (err) {
    showToast(err.message, true);
  }
}

function parseRecipients(text) {
  return text
    .split(/[,;\s]+/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
}

function renderFileList() {
  const list = $("file-list");
  list.replaceChildren();
  state.files.forEach((file, index) => {
    const item = el("li");
    const remove = el("button", "icon-btn", "✕");
    remove.type = "button";
    remove.title = "Remove";
    remove.addEventListener("click", () => {
      state.files.splice(index, 1);
      renderFileList();
    });
    item.append(el("span", null, file.name + " (" + formatSize(file.size) + ")"), remove);
    list.append(item);
  });
}

// ---------- Button and form events ----------
$("compose-btn").addEventListener("click", () => {
  closeSidebar();
  openCompose();
});
$("compose-close").addEventListener("click", closeCompose);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeCompose();
});

$("attachments").addEventListener("change", (event) => {
  hideComposeMessage();
  for (const file of event.target.files) {
    const ext = file.name.includes(".") ? file.name.split(".").pop().toLowerCase() : "";
    if (!ALLOWED_EXTENSIONS.includes(ext)) {
      showComposeMessage('"' + file.name + '" is not an allowed file type.');
      continue;
    }
    if (file.size > MAX_FILE_MB * 1024 * 1024) {
      showComposeMessage('"' + file.name + '" is larger than ' + MAX_FILE_MB + " MB.");
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

$("compose-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.target;
  hideComposeMessage();

  const recipients = parseRecipients(form.elements.to.value);
  if (recipients.length === 0) {
    showComposeMessage("Please add at least one recipient.");
    return;
  }
  const invalid = recipients.find((r) => !EMAIL_PATTERN.test(r));
  if (invalid) {
    showComposeMessage('"' + invalid + "\" doesn't look like an email address.");
    return;
  }
  if (!form.elements.subject.value.trim() && !confirm("Send this message without a subject?")) {
    return;
  }

  // FormData is needed because we are sending files
  const formData = new FormData();
  formData.append("to", recipients.join(","));
  formData.append("subject", form.elements.subject.value.trim());
  formData.append("body", form.elements.body.value);
  if (state.draftId) formData.append("draft_id", state.draftId);
  state.files.forEach((file) => formData.append("attachments", file));

  const sendButton = $("send-btn");
  sendButton.disabled = true;
  sendButton.textContent = "Sending...";
  try {
    const result = await api("/api/messages/send", { method: "POST", body: formData });
    closeCompose();
    showToast((result && result.message) || "Message sent");
    loadMessages();
  } catch (err) {
    showComposeMessage(err.message);
  } finally {
    sendButton.disabled = false;
    sendButton.textContent = "Send";
  }
});

$("save-draft-btn").addEventListener("click", async () => {
  const form = $("compose-form");
  try {
    const result = await api("/api/drafts", {
      method: "POST",
      body: {
        draft_id: state.draftId,
        to: parseRecipients(form.elements.to.value),
        subject: form.elements.subject.value,
        body: form.elements.body.value,
      },
    });
    state.draftId = result.draft_id;
    showToast("Draft saved");
    if (state.folder === "drafts") loadMessages();
  } catch (err) {
    showComposeMessage(err.message);
  }
});

// Toolbar buttons in the reading view
$("back-btn").addEventListener("click", () => {
  showListView();
  loadMessages();
});
$("star-btn").addEventListener("click", () => {
  const starred = state.current && state.current.is_starred;
  toolbarAction(starred ? "unstar" : "star", starred ? "Star removed" : "Starred", false);
});
$("unread-btn").addEventListener("click", () => toolbarAction("unread", "Marked as unread", true));
$("spam-btn").addEventListener("click", () => toolbarAction("spam", "Moved to spam", true));
$("trash-btn").addEventListener("click", () => toolbarAction("trash", "Moved to trash", true));
$("restore-btn").addEventListener("click", () => {
  const action = state.current && state.current.folder === "spam" ? "not_spam" : "restore";
  toolbarAction(action, "Message restored", true);
});
$("delete-forever-btn").addEventListener("click", () => {
  if (confirm("Delete this message forever? This cannot be undone.")) {
    toolbarAction("delete_forever", "Message deleted forever", true);
  }
});

// Search
$("search-form").addEventListener("submit", (event) => {
  event.preventDefault();
  state.query = $("search-input").value.trim();
  state.page = 1;
  showListView();
  loadMessages();
});

// Refresh and pages
$("refresh-btn").addEventListener("click", loadMessages);
$("prev-btn").addEventListener("click", () => {
  if (state.page > 1) {
    state.page--;
    loadMessages();
  }
});
$("next-btn").addEventListener("click", () => {
  if (state.page < state.totalPages) {
    state.page++;
    loadMessages();
  }
});

// Logout
$("logout-btn").addEventListener("click", async () => {
  try {
    await api("/api/auth/logout", { method: "POST" });
  } catch {
    // Even if this fails, go to the login page
  }
  window.location.href = "/login.html";
});

// Mobile sidebar
function closeSidebar() {
  $("sidebar").classList.remove("open");
  $("overlay").classList.add("hidden");
}
$("menu-btn").addEventListener("click", () => {
  $("sidebar").classList.add("open");
  $("overlay").classList.remove("hidden");
});
$("overlay").addEventListener("click", closeSidebar);

// Clicking a folder changes the #hash in the address bar
window.addEventListener("hashchange", () => {
  state.folder = folderFromHash();
  state.page = 1;
  state.query = "";
  $("search-input").value = "";
  closeSidebar();
  showListView();
  loadMessages();
});

// ---------- Start ----------
state.folder = folderFromHash();
loadUser();
loadMessages();
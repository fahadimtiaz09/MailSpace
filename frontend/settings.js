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
  const text = el("div", "grow");
  text.style.minWidth = "0";
  text.append(el("h3", null, u.display_name || u.username), el("p", null, u.email));

  // Profile picture: change / remove
  const photoBox = el("div", "profile-photo");
  photoBox.append(avatar(u.email, "profile", u.display_name));
  const actions = el("div", "profile-photo-actions");
  const change = el("button", "btn btn-sm", u.avatar ? "Change photo" : "Upload photo");
  change.type = "button";
  change.prepend(icon("image", "i-sm"));
  change.addEventListener("click", () => pickPhoto(change));
  actions.append(change);
  if (u.avatar) {
    const remove = el("button", "btn btn-sm btn-ghost", "Remove");
    remove.type = "button";
    remove.addEventListener("click", () => removePhoto(remove));
    actions.append(remove);
  }
  text.append(actions);
  hero.replaceChildren(photoBox, text);

  const rows = document.getElementById("profile-rows");
  const nameRow = settingRow("Name", u.display_name || "Not set",
    "Shown to people you email — in DoMailit and in Gmail, Outlook and others.");
  const editName = el("button", "btn btn-sm", u.display_name ? "Change" : "Add name");
  editName.type = "button";
  editName.addEventListener("click", () => nameModal(u));
  nameRow.append(editName);
  rows.replaceChildren(
    nameRow,
    settingRow("DoMailit address", u.email, "Your main address. It can't be changed."),
    settingRow("Account type", ACCOUNT_LABELS[u.account_type] || u.account_type),
    settingRow("Member since", new Date(u.created_at).toLocaleDateString([], { day: "numeric", month: "long", year: "numeric" }))
  );
  if (u.expires_at) {
    rows.append(settingRow("Expires", formatFullDate(u.expires_at),
      "Temporary accounts and their messages are deleted when they expire. Download anything you want to keep."));
  }
}

// Show the new name / photo everywhere on the page
async function reloadProfile() {
  const { user } = await api("/api/auth/me");
  Shell.refreshUser(user);
  renderProfile(user);
}

function nameModal(u) {
  recoveryModal({
    title: "Your name",
    intro: "People see this next to your address, e.g. \u201cNimra Noor\u201d. Leave it empty to show only your address.",
    fields: [{ key: "name", label: "Name", placeholder: "Your full name", value: u.display_name || "" }],
    onSave: async (inputs) => {
      const name = inputs.name.value.trim();
      if (name.length > 50) throw new Error("Use 50 characters or fewer.");
      await api("/api/auth/profile", { method: "PATCH", body: { display_name: name } });
      await reloadProfile();
    },
  });
}

// Shrink the picture to a 256 × 256 square in the browser before uploading
function squarePhoto(file, size = 256) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const side = Math.min(img.naturalWidth, img.naturalHeight);
      const canvas = document.createElement("canvas");
      canvas.width = canvas.height = size;
      canvas.getContext("2d").drawImage(img,
        (img.naturalWidth - side) / 2, (img.naturalHeight - side) / 2, side, side, 0, 0, size, size);
      URL.revokeObjectURL(url);
      canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("Could not read that picture."))), "image/jpeg", 0.88);
    };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("That file isn't a picture we can read.")); };
    img.src = url;
  });
}

function pickPhoto(button) {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = "image/png,image/jpeg,image/webp,image/gif";
  input.addEventListener("change", async () => {
    const file = input.files && input.files[0];
    if (!file) return;
    if (file.size > 15 * 1024 * 1024) { toast("That picture is too big.", "error"); return; }
    setBusy(button, true, "Uploading…");
    try {
      const form = new FormData();
      form.append("avatar", await squarePhoto(file), "avatar.jpg");
      await api("/api/auth/avatar", { method: "POST", body: form });
      await reloadProfile();
      toast("Profile picture updated.", "success");
    } catch (err) {
      toast(err.message, "error");
      setBusy(button, false);
    }
  });
  input.click();
}

async function removePhoto(button) {
  setBusy(button, true, "Removing…");
  try {
    await api("/api/auth/avatar", { method: "DELETE" });
    await reloadProfile();
    toast("Profile picture removed.");
  } catch (err) {
    toast(err.message, "error");
    setBusy(button, false);
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
  const pref = window.DoMailitTheme.get();
  document.querySelectorAll('input[name="theme"]').forEach((r) => (r.checked = r.value === pref));
}
document.querySelectorAll('input[name="theme"]').forEach((radio) => {
  radio.addEventListener("change", () => {
    window.DoMailitTheme.set(radio.value);
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
// ---------- Change password ----------
document.getElementById("change-pw-btn").addEventListener("click", () => {
  const box = el("div", "modal");

  const head = el("div", "modal-head");
  const headText = el("div");
  headText.append(el("h2", null, "Change password"), el("p", null, "Enter your current password, then choose a new one."));
  head.append(headText);

  const body = el("div", "modal-body");
  const msg = el("div", "alert alert-error hidden");
  msg.setAttribute("role", "alert");
  body.append(msg);

  function pwField(labelText, autodata) {
    const field = el("div", "field");
    const label = el("label", null, labelText);
    const group = el("div", "input-group");
    const input = el("input", "input");
    input.type = "password";
    input.autocomplete = autodata;
    const toggle = iconButton("eye", "Show password", "icon-btn icon-btn-sm pw-toggle");
    toggle.addEventListener("click", () => {
      const show = input.type === "password";
      input.type = show ? "text" : "password";
      toggle.querySelector("use").setAttribute("href", "/icons.svg#" + (show ? "eye-off" : "eye"));
    });
    group.append(input, toggle);
    field.append(label, group);
    return { field, input };
  }
  const cur = pwField("Current password", "current-password");
  const nw = pwField("New password", "new-password");
  const cf = pwField("Confirm new password", "new-password");
  nw.field.style.marginBottom = "16px";
  body.append(cur.field, nw.field, cf.field);

  const foot = el("div", "modal-foot");
  const cancel = el("button", "btn", "Cancel");
  const save = el("button", "btn btn-primary", "Update password");
  cancel.type = save.type = "button";
  foot.append(cancel, save);

  box.append(head, body, foot);

  function showErr(text) { msg.textContent = text; msg.classList.remove("hidden"); }

  const close = openModal(box);
  cancel.addEventListener("click", close);
  save.addEventListener("click", async () => {
    msg.classList.add("hidden");
    if (nw.input.value.length < 8) return showErr("New password must be at least 8 characters.");
    if (nw.input.value !== cf.input.value) return showErr("The new passwords don't match.");
    setBusy(save, true, "Saving…");
    try {
      await api("/api/auth/change-password", {
        method: "POST",
        body: { current_password: cur.input.value, new_password: nw.input.value },
      });
      close();
      toast("Password updated.", "success");
    } catch (err) {
      setBusy(save, false);
      showErr(err.message);
    }
  });
});
// ---------- Recovery email & security question ----------
function recoveryModal({ title, intro, fields, onSave }) {
  const box = el("div", "modal");
  const head = el("div", "modal-head");
  const headText = el("div");
  headText.append(el("h2", null, title), el("p", null, intro));
  head.append(headText);

  const body = el("div", "modal-body");
  const msg = el("div", "alert alert-error hidden");
  msg.setAttribute("role", "alert");
  body.append(msg);

  const inputs = {};
  fields.forEach((f) => {
    const field = el("div", "field");
    field.append(el("label", null, f.label));
    const input = el("input", "input");
    input.type = f.type || "text";
    if (f.placeholder) input.placeholder = f.placeholder;
    if (f.value) input.value = f.value;
    field.append(input);
    body.append(field);
    inputs[f.key] = input;
  });

  const foot = el("div", "modal-foot");
  const cancel = el("button", "btn", "Cancel");
  const save = el("button", "btn btn-primary", "Save");
  cancel.type = save.type = "button";
  foot.append(cancel, save);
  box.append(head, body, foot);

  function showErr(t) { msg.textContent = t; msg.classList.remove("hidden"); }
  const close = openModal(box);
  cancel.addEventListener("click", close);
  save.addEventListener("click", async () => {
    msg.classList.add("hidden");
    setBusy(save, true, "Saving…");
    try {
      await onSave(inputs);
      close();
      toast("Saved.", "success");
      Shell.userReady; // refresh note text
      refreshRecoveryNotes();
    } catch (err) {
      setBusy(save, false);
      showErr(err.message);
    }
  });
}

async function refreshRecoveryNotes() {
  try {
    const data = await api("/api/auth/me");
    const u = data.user;
    const emailNote = document.getElementById("recovery-email-note");
    const emailBtn = document.getElementById("recovery-email-btn");
    if (u.recovery_email) {
      emailNote.textContent = "Reset codes go to " + u.recovery_email;
      emailBtn.lastChild.textContent = "Change";
    } else {
      emailNote.textContent = "Where we can send a reset code if you forget your password.";
      emailBtn.lastChild.textContent = "Set up";
    }
    const qNote = document.getElementById("security-q-note");
    const qBtn = document.getElementById("security-q-btn");
    if (u.security_question) {
      qNote.textContent = "Question: " + u.security_question;
      qBtn.lastChild.textContent = "Change";
    } else {
      qNote.textContent = "A question only you can answer, as a backup way to reset.";
      qBtn.lastChild.textContent = "Set up";
    }
  } catch { /* ignore */ }
}

document.getElementById("recovery-email-btn").addEventListener("click", () => {
  recoveryModal({
    title: "Recovery email",
    intro: "A reset code can be emailed here if you forget your password. Confirm your current password to save.",
    fields: [
      { key: "email", label: "Recovery email", type: "email", placeholder: "you@gmail.com" },
      { key: "current", label: "Current password", type: "password" },
    ],
    onSave: (inputs) => api("/api/auth/recovery", {
      method: "POST",
      body: { recovery_email: inputs.email.value.trim(), current_password: inputs.current.value },
    }),
  });
});

document.getElementById("security-q-btn").addEventListener("click", () => {
  recoveryModal({
    title: "Security question",
    intro: "Pick a question only you can answer. Confirm your current password to save.",
    fields: [
      { key: "q", label: "Question", placeholder: "e.g. What was your first school?" },
      { key: "a", label: "Answer", placeholder: "Something only you know" },
      { key: "current", label: "Current password", type: "password" },
    ],
    onSave: (inputs) => {
      if (!inputs.q.value.trim() || inputs.a.value.trim().length < 2) {
        return Promise.reject(new Error("Fill in both the question and an answer."));
      }
      return api("/api/auth/recovery", {
        method: "POST",
        body: {
          security_question: inputs.q.value.trim(),
          security_answer: inputs.a.value.trim(),
          current_password: inputs.current.value,
        },
      });
    },
  });
});
document.getElementById("logout-here").addEventListener("click", async () => {
  try {
    await api("/api/auth/logout", { method: "POST" });
  } catch {
    // Even if this fails, go to the login page
  }
  window.location.href = "/login.html";
});

// ---------- Privacy: show when I'm online ----------
function renderPrivacy(u) {
  const box = document.getElementById("show-online");
  box.checked = u.show_online !== false;
  box.disabled = false;
}
document.getElementById("show-online").addEventListener("change", async (e) => {
  const box = e.target;
  const wanted = box.checked;
  box.disabled = true;
  try {
    await api("/api/auth/profile", { method: "PATCH", body: { show_online: wanted } });
    toast(wanted ? "People can now see when you're online." : "You now appear offline to everyone.", "success");
  } catch (err) {
    box.checked = !wanted;
    toast(err.message, "error");
  } finally {
    box.disabled = false;
  }
});

// ---------- Delete account ----------
document.getElementById("delete-account-btn").addEventListener("click", () => {
  const box = el("div", "modal");
  const head = el("div", "modal-head");
  const headText = el("div");
  headText.append(el("h2", null, "Delete your account?"),
    el("p", null, "This can't be undone. All your emails, attachments, domains, addresses and your photo will be deleted, and your address can't be used again."));
  head.append(headText);

  const body = el("div", "modal-body");
  const msg = el("div", "alert alert-error hidden");
  msg.setAttribute("role", "alert");
  body.append(msg);

  const pwField = el("div", "field");
  const pwLabel = el("label", null, "Your password");
  const pw = el("input", "input");
  pw.type = "password";
  pw.autocomplete = "current-password";
  pw.id = "delete-pw";
  pwLabel.htmlFor = "delete-pw";
  pwField.append(pwLabel, pw);

  const cfField = el("div", "field");
  const cfLabel = el("label", null, "Type DELETE to confirm");
  const cf = el("input", "input");
  cf.id = "delete-confirm";
  cf.autocomplete = "off";
  cf.spellcheck = false;
  cfLabel.htmlFor = "delete-confirm";
  cfField.append(cfLabel, cf);
  body.append(pwField, cfField);

  const foot = el("div", "modal-foot");
  const cancel = el("button", "btn", "Cancel");
  const confirm = el("button", "btn btn-danger-solid", "Delete account forever");
  cancel.type = confirm.type = "button";
  confirm.disabled = true;
  foot.append(cancel, confirm);
  box.append(head, body, foot);

  const ready = () => { confirm.disabled = !(pw.value && cf.value.trim().toUpperCase() === "DELETE"); };
  pw.addEventListener("input", ready);
  cf.addEventListener("input", ready);

  const close = openModal(box);
  cancel.addEventListener("click", close);
  confirm.addEventListener("click", async () => {
    msg.classList.add("hidden");
    setBusy(confirm, true, "Deleting…");
    try {
      await api("/api/auth/delete-account", { method: "POST", body: { password: pw.value, confirm: cf.value } });
      window.location.href = "/?deleted=1";
    } catch (err) {
      setBusy(confirm, false);
      ready();
      msg.textContent = err.message;
      msg.classList.remove("hidden");
    }
  });
});

Shell.userReady.then((u) => {
  renderProfile(u);
  renderPrivacy(u);
  renderFromAddresses();
  refreshRecoveryNotes();
  highlightSection();
}).catch(() => {});

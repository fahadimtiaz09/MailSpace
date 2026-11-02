// ============================================================
// forgot.js — reset your password with a recovery email code
// or a security question. Needs api.js and ui.js.
// ============================================================

const root = document.getElementById("forgot-root");
let account = null; // { login, recovery_email, security_question }

function card(title, subtitle) {
  root.replaceChildren();
  root.append(el("h1", null, title), el("p", "muted", subtitle));
  const msg = el("div", "alert alert-error hidden");
  msg.setAttribute("role", "alert");
  root.append(msg);
  return msg;
}
function showErr(msg, text) { msg.textContent = text; msg.className = "alert alert-error"; }
function backLink(text, onClick) {
  const p = el("p", "auth-switch");
  const a = el("a", null, text);
  a.href = onClick ? "#" : "/login.html";
  if (onClick) a.addEventListener("click", (e) => { e.preventDefault(); onClick(); });
  p.append(a);
  return p;
}
function newPasswordFields() {
  const nw = el("div", "field");
  nw.append(el("label", null, "New password"));
  const nwi = el("input", "input"); nwi.type = "password"; nwi.autocomplete = "new-password";
  nw.append(nwi);
  const cf = el("div", "field");
  cf.append(el("label", null, "Confirm new password"));
  const cfi = el("input", "input"); cfi.type = "password"; cfi.autocomplete = "new-password";
  cf.append(cfi);
  return { nw, nwi, cf, cfi };
}
function validateNew(nwi, cfi) {
  if (nwi.value.length < 8) return "New password must be at least 8 characters.";
  if (nwi.value !== cfi.value) return "The passwords don't match.";
  return null;
}

// ---------- Step 1: who are you ----------
function stepIdentify() {
  const msg = card("Reset your password", "Enter your username or email to start.");
  const form = el("form"); form.noValidate = true;
  const field = el("div", "field");
  field.append(el("label", null, "Username or email"));
  const input = el("input", "input");
  input.type = "text"; input.autocapitalize = "off"; input.spellcheck = false;
  field.append(input);
  const btn = el("button", "btn btn-primary btn-lg btn-block", "Continue"); btn.type = "submit";
  form.append(field, btn);
  root.append(form, backLink("Back to log in"));
  input.focus();

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    msg.className = "alert alert-error hidden";
    setBusy(btn, true, "Checking…");
    try {
      account = await api("/api/auth/forgot/start", { method: "POST", body: { login: input.value.trim() } });
      stepChoose();
    } catch (err) { setBusy(btn, false); showErr(msg, err.message); }
  });
}

// ---------- Step 2: choose a method ----------
function stepChoose() {
  const msg = card("Choose a way to reset", "Verify it's you, then set a new password.");
  const wrap = el("div"); wrap.style.cssText = "display:grid; gap:10px";
  if (account.recovery_email) {
    const b = el("button", "btn btn-lg btn-block", "Email a code to " + account.recovery_email);
    b.type = "button";
    b.addEventListener("click", stepEmailCode);
    wrap.append(b);
  }
  if (account.security_question) {
    const b = el("button", "btn btn-lg btn-block", "Answer your security question");
    b.type = "button";
    b.addEventListener("click", stepQuestion);
    wrap.append(b);
  }
  if (!account.recovery_email && !account.security_question) {
    showErr(msg, "This account has no recovery email or security question set. Please ask an administrator to reset it.");
  }
  root.append(wrap, backLink("Back to log in"));
}

// ---------- Step 3a: email code ----------
function stepEmailCode() {
  const msg = card("Check your email", "Sending a 6-digit code to " + account.recovery_email + "…");
  api("/api/auth/forgot/send-code", { method: "POST", body: { login: account.login } })
    .then(() => { msg.className = "alert hidden"; })
    .catch((err) => showErr(msg, err.message));

  const form = el("form"); form.noValidate = true;
  const codeField = el("div", "field");
  codeField.append(el("label", null, "6-digit code"));
  const code = el("input", "input");
  code.type = "text"; code.inputMode = "numeric"; code.maxLength = 6;
  codeField.append(code);
  const pf = newPasswordFields();
  const btn = el("button", "btn btn-primary btn-lg btn-block", "Reset password"); btn.type = "submit";
  form.append(codeField, pf.nw, pf.cf, btn);

  const resend = el("p", "auth-switch");
  const ra = el("a", null, "Resend code"); ra.href = "#";
  ra.addEventListener("click", (e) => {
    e.preventDefault();
    api("/api/auth/forgot/send-code", { method: "POST", body: { login: account.login } })
      .then(() => toast("New code sent.", "success"))
      .catch((err) => toast(err.message, "error"));
  });
  resend.append(ra);

  root.append(form, resend, backLink("Use another method", stepChoose));
  code.focus();

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const v = validateNew(pf.nwi, pf.cfi);
    if (v) return showErr(msg, v);
    setBusy(btn, true, "Resetting…");
    try {
      await api("/api/auth/forgot/reset", {
        method: "POST",
        body: { login: account.login, method: "email", code: code.value.trim(), new_password: pf.nwi.value },
      });
      done();
    } catch (err) { setBusy(btn, false); showErr(msg, err.message); }
  });
}

// ---------- Step 3b: security question ----------
function stepQuestion() {
  const msg = card("Security question", account.security_question);
  const form = el("form"); form.noValidate = true;
  const aField = el("div", "field");
  aField.append(el("label", null, "Your answer"));
  const ans = el("input", "input"); ans.type = "text"; ans.autocomplete = "off";
  aField.append(ans);
  const pf = newPasswordFields();
  const btn = el("button", "btn btn-primary btn-lg btn-block", "Reset password"); btn.type = "submit";
  form.append(aField, pf.nw, pf.cf, btn);
  root.append(form, backLink("Use another method", stepChoose));
  ans.focus();

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const v = validateNew(pf.nwi, pf.cfi);
    if (v) return showErr(msg, v);
    setBusy(btn, true, "Resetting…");
    try {
      await api("/api/auth/forgot/reset", {
        method: "POST",
        body: { login: account.login, method: "question", answer: ans.value, new_password: pf.nwi.value },
      });
      done();
    } catch (err) { setBusy(btn, false); showErr(msg, err.message); }
  });
}

// ---------- Done ----------
function done() {
  card("Password reset", "You can now log in with your new password.");
  const a = el("a", "btn btn-primary btn-lg btn-block", "Go to log in");
  a.href = "/login.html";
  a.style.textDecoration = "none";
  root.append(a);
}

stepIdentify();
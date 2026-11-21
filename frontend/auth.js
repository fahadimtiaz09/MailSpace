// ============================================================
// auth.js — login and signup pages
// ============================================================

// Shown in the address preview. The backend decides the real address.
const MAIL_DOMAIN = "domailit.com";

function showMessage(text, type = "error") {
  const box = document.getElementById("form-message");
  box.className = "alert alert-" + type;
  box.replaceChildren(icon(type === "success" ? "check-circle" : "alert", "i-sm"), el("span", null, text));
}

function hideMessage() {
  document.getElementById("form-message").className = "alert hidden";
}

function markInvalid(input, invalid) {
  if (invalid) input.setAttribute("aria-invalid", "true");
  else input.removeAttribute("aria-invalid");
}

// Show / hide password buttons
document.querySelectorAll(".pw-toggle").forEach((button) => {
  button.addEventListener("click", () => {
    const input = button.parentElement.querySelector("input");
    const show = input.type === "password";
    input.type = show ? "text" : "password";
    button.setAttribute("aria-label", show ? "Hide password" : "Show password");
    button.querySelector("use").setAttribute("href", "/icons.svg#" + (show ? "eye-off" : "eye"));
    input.focus();
  });
});

// ---------- Login page ----------
const loginForm = document.getElementById("login-form");

if (loginForm) {
  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault(); // stop the browser from reloading the page
    hideMessage();

    const login = loginForm.elements.login.value.trim();
    const password = loginForm.elements.password.value;
    markInvalid(loginForm.elements.login, !login);
    markInvalid(loginForm.elements.password, !password);
    if (!login || !password) {
      showMessage("Enter your username or email and your password.");
      (login ? loginForm.elements.password : loginForm.elements.login).focus();
      return;
    }

    const button = loginForm.querySelector("button[type=submit]");
    setBusy(button, true, "Logging in…");
    try {
      await api("/api/auth/login", { method: "POST", body: { login, password } });
      window.location.href = "/inbox";
    } catch (err) {
      setBusy(button, false);
      showMessage(err.message);
      loginForm.elements.password.select();
    }
  });
}

// ---------- Signup page ----------
const signupForm = document.getElementById("signup-form");

if (signupForm) {
  const usernameInput = signupForm.elements.username;
  const passwordInput = signupForm.elements.password;

  // Live preview of the email address while typing
  usernameInput.addEventListener("input", () => {
    usernameInput.value = usernameInput.value.toLowerCase().replace(/\s/g, "");
    const name = usernameInput.value || "username";
    document.getElementById("email-preview").textContent = name + "@" + MAIL_DOMAIN;
    markInvalid(usernameInput, false);
  });

  // Simple strength hint (the server only requires 8+ characters)
  passwordInput.addEventListener("input", () => {
    const p = passwordInput.value;
    let level = 0;
    if (p.length >= 8) level = 1;
    if (p.length >= 10 && /[a-z]/i.test(p) && /\d/.test(p)) level = 2;
    if (p.length >= 12 && /[a-z]/.test(p) && /[A-Z]/.test(p) && /\d/.test(p)) level = 3;
    if (p.length >= 14 && /[^a-z0-9]/i.test(p) && level >= 2) level = 4;
    document.getElementById("strength").dataset.level = p ? Math.max(level, 1) : 0;
    markInvalid(passwordInput, false);
  });

  signupForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    hideMessage();

    const username = usernameInput.value.trim();
    const password = passwordInput.value;
    const confirmInput = signupForm.elements.confirm_password;
    const accountType = signupForm.elements.account_type.value;

    // Quick checks in the browser (the backend checks again — never trust only the browser)
    if (!/^[a-z0-9._]{3,20}$/.test(username) || username.includes("..") || username.startsWith(".") || username.endsWith(".")) {
      showMessage("Username must be 3–20 characters: lowercase letters, numbers, dot or underscore, and can't start or end with a dot.");
      markInvalid(usernameInput, true);
      usernameInput.focus();
      return;
    }
    if (password.length < 8) {
      showMessage("Password must be at least 8 characters.");
      markInvalid(passwordInput, true);
      passwordInput.focus();
      return;
    }
    if (password !== confirmInput.value) {
      showMessage("The passwords don't match.");
      markInvalid(confirmInput, true);
      confirmInput.focus();
      return;
    }
    markInvalid(confirmInput, false);

    // Like Gmail: the account is only created after "I agree"
    if (!(await termsDialog())) return;

    const button = signupForm.querySelector("button[type=submit]");
    setBusy(button, true, "Creating account…");
    try {
      await api("/api/auth/signup", {
        method: "POST",
          body: {
          username, password, account_type: accountType, accept_terms: true,
          recovery_email: (signupForm.elements.recovery_email?.value || "").trim(),
          security_question: (signupForm.elements.security_question?.value || "").trim(),
          security_answer: (signupForm.elements.security_answer?.value || "").trim(),
        },
      });
      showMessage("Account created. Opening your inbox…", "success");
      setTimeout(() => (window.location.href = "/inbox"), 700);
    } catch (err) {
      setBusy(button, false);
      showMessage(err.message);
      if (err.status === 409) {
        markInvalid(usernameInput, true);
        usernameInput.focus();
      }
    }
  });
}

// "Privacy and Terms" step before a new account is created.
// Resolves to true when the user taps "I agree", false for Cancel / Escape.
function termsDialog() {
  return new Promise((resolve) => {
    const box = el("div", "modal modal-wide terms-modal");
    box.setAttribute("aria-labelledby", "terms-title");

    const head = el("div", "modal-head");
    const text = el("div");
    const badge = el("div", "modal-icon terms-icon");
    badge.append(icon("shield"));
    const h = el("h2", null, "Privacy and Terms");
    h.id = "terms-title";
    text.append(badge, h, el("p", null,
      "To create a DoMailit account, you need to agree to the Terms of Service. " +
      "When you create an account, we process your information as described in our Privacy Policy, including these key points:"));
    head.append(text);

    const body = el("div", "modal-body terms-body");
    body.tabIndex = 0; // scrollable with the keyboard
    const points = [
      ["Data we process when you use DoMailit",
        "Your username and password (stored only as a secure hash), the emails and attachments you send and receive, " +
        "your call history (not the calls themselves), and technical data such as your IP address."],
      ["Why we process it",
        "To deliver your mail and calls, send the notifications you turn on, keep your account secure, and stop spam and abuse. " +
        "We don't show ads and we never sell your data."],
      ["Keeping DoMailit safe",
        "Administrators may review messages and attachments for illegal or harmful content. Every review is recorded in an audit log."],
      ["Acceptable use",
        "No spam, scams, phishing, malware, harassment or illegal content. Accounts that break these rules can be suspended."],
      ["You're in control",
        "Hide your online status, turn notifications on or off, and delete your account and its data at any time from Settings."],
    ];
    for (const [title, line] of points) {
      const item = el("div", "terms-point");
      item.append(el("h3", null, title), el("p", null, line));
      body.append(item);
    }
    const links = el("p", "terms-links");
    const t = el("a", null, "Terms of Service");
    t.href = "/terms.html"; t.target = "_blank"; t.rel = "noopener";
    const p = el("a", null, "Privacy Policy");
    p.href = "/privacy.html"; p.target = "_blank"; p.rel = "noopener";
    links.append("Read the full ", t, " and ", p, ".");
    body.append(links);

    const foot = el("div", "modal-foot");
    const cancel = el("button", "btn", "Cancel");
    const ok = el("button", "btn btn-primary", "I agree");
    cancel.type = ok.type = "button";
    foot.append(cancel, ok);
    box.append(head, body, foot);

    let agreed = false;
    const close = openModal(box, { onClose: () => resolve(agreed) });
    cancel.addEventListener("click", close);
    ok.addEventListener("click", () => {
      agreed = true;
      close();
    });
  });
}

// If the user is already logged in, skip these pages and open the inbox
if (loginForm || signupForm) {
  api("/api/auth/me")
    .then(() => (window.location.href = "/inbox"))
    .catch(() => {}); // not logged in — stay here
}

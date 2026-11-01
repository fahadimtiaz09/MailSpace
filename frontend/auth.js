// ============================================================
// auth.js — login and signup pages
// ============================================================

// Shown in the address preview. The backend decides the real address.
const MAIL_DOMAIN = "fahadimtiaz.site";

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

    const button = signupForm.querySelector("button[type=submit]");
    setBusy(button, true, "Creating account…");
    try {
      await api("/api/auth/signup", {
        method: "POST",
        body: { username, password, account_type: accountType },
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

// If the user is already logged in, skip these pages and open the inbox
if (loginForm || signupForm) {
  api("/api/auth/me")
    .then(() => (window.location.href = "/inbox"))
    .catch(() => {}); // not logged in — stay here
}

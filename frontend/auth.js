// ============================================================
// auth.js — login and signup pages
// ============================================================

// Temporary domain shown in the preview. The backend decides the real address.
const MAIL_DOMAIN = "fahadimtiaz.site";

function showMessage(text, type = "error") {
  const box = document.getElementById("form-message");
  box.textContent = text;
  box.className = "alert alert-" + type;
}

function setLoading(form, isLoading, loadingText) {
  const button = form.querySelector("button[type=submit]");
  button.disabled = isLoading;
  if (isLoading) {
    button.dataset.label = button.textContent;
    button.textContent = loadingText;
  } else if (button.dataset.label) {
    button.textContent = button.dataset.label;
  }
}

// ---------- Login page ----------
const loginForm = document.getElementById("login-form");

if (loginForm) {
  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault(); // stop the browser from reloading the page

    const login = loginForm.elements.login.value.trim();
    const password = loginForm.elements.password.value;

    if (!login || !password) {
      showMessage("Please enter your username/email and password.");
      return;
    }

    setLoading(loginForm, true, "Logging in...");
    try {
      await api("/api/auth/login", { method: "POST", body: { login, password } });
      window.location.href = "/inbox"; // go to the inbox
    } catch (err) {
      showMessage(err.message);
      setLoading(loginForm, false);
    }
  });
}

// ---------- Signup page ----------
const signupForm = document.getElementById("signup-form");

if (signupForm) {
  const usernameInput = signupForm.elements.username;

  // Live preview of the email address while typing
  usernameInput.addEventListener("input", () => {
    usernameInput.value = usernameInput.value.toLowerCase();
    const name = usernameInput.value || "username";
    document.getElementById("email-preview").textContent = name + "@" + MAIL_DOMAIN;
  });

  signupForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    const username = usernameInput.value.trim();
    const password = signupForm.elements.password.value;
    const confirmPassword = signupForm.elements.confirm_password.value;
        const accountType = signupForm.elements.account_type.value;

    // Quick checks in the browser (the backend will check again — never trust only the browser)
    if (!/^[a-z0-9._]{3,20}$/.test(username)) {
      showMessage("Username must be 3–20 characters: lowercase letters, numbers, dot or underscore.");
      return;
    }
    if (password.length < 8) {
      showMessage("Password must be at least 8 characters.");
      return;
    }
    if (password !== confirmPassword) {
      showMessage("Passwords do not match.");
      return;
    }

    setLoading(signupForm, true, "Creating account...");
    try {
      await api("/api/auth/signup", {
        method: "POST",
        body: { username, password, account_type: accountType  },
      });
      showMessage("Account created! Opening your inbox...", "success");
      setTimeout(() => (window.location.href = "/inbox"), 1000);
    } catch (err) {
      showMessage(err.message);
      setLoading(signupForm, false);
    }
  });
}

// If the user is already logged in, skip these pages and open the inbox
if (loginForm || signupForm) {
  api("/api/auth/me")
    .then(() => (window.location.href = "/inbox"))
    .catch(() => {}); // not logged in (or backend not ready) — stay here
}
// ============================================================
// api.js — shared helpers used by every page
// ============================================================

// A special error that also remembers the HTTP status code (401, 404, ...)
class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

// Read a cookie by name (used for CSRF protection later)
function getCookie(name) {
  const match = document.cookie.match(new RegExp("(?:^|; )" + name + "=([^;]*)"));
  return match ? decodeURIComponent(match[1]) : null;
}

// Friendly messages when the server does not send its own error text
function defaultErrorMessage(status) {
  if (status === 401) return "Please log in first.";
  if (status === 403) return "You are not allowed to do that.";
  if (status === 404 || status === 405) return "This feature isn't built on the server yet.";
  if (status === 413) return "The file is too large.";
  if (status === 429) return "Too many attempts. Please wait and try again.";
  return "Something went wrong on the server (" + status + ").";
}

// The ONE function every page uses to talk to Flask
async function api(path, options = {}) {
  const opts = { method: "GET", credentials: "same-origin", ...options };
  opts.headers = { ...(options.headers || {}) };

  // Send the CSRF token on every request that changes data
  const csrf = getCookie("csrf_token");
  if (csrf && opts.method !== "GET") {
    opts.headers["X-CSRFToken"] = csrf;
  }

  // Plain objects are sent as JSON. FormData (files) is sent as-is.
  if (opts.body && !(opts.body instanceof FormData) && typeof opts.body !== "string") {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(opts.body);
  }

  let response;
  try {
    response = await fetch(path, opts);
  } catch (networkError) {
    throw new ApiError("Cannot reach the server. Is Flask running?", 0);
  }

  let data = null;
  const type = response.headers.get("Content-Type") || "";
  if (type.includes("application/json")) {
    data = await response.json();
  }

  if (!response.ok) {
    const message = (data && data.error) || defaultErrorMessage(response.status);
    throw new ApiError(message, response.status);
  }
  return data;
}

// Create an HTML element safely (textContent never runs HTML or scripts)
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

// "14:05" for today, "25 Oct" for this year, full date otherwise
function formatDate(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) {
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  }
  if (d.getFullYear() === now.getFullYear()) {
    return d.toLocaleDateString([], { day: "numeric", month: "short" });
  }
  return d.toLocaleDateString();
}

// 2048 -> "2.0 KB"
function formatSize(bytes) {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(1) + " MB";
}
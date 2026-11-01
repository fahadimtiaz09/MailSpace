// ============================================================
// ui.js — small reusable pieces shared by the app pages:
// icons, toasts, dialogs, menus, copy buttons, avatars.
// Needs api.js (for el()) to be loaded first.
// ============================================================

// <svg class="i"><use href="/icons.svg#name"></use></svg>
function icon(name, extraClass) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("class", "i" + (extraClass ? " " + extraClass : ""));
  svg.setAttribute("aria-hidden", "true");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", "/icons.svg#" + name);
  svg.append(use);
  return svg;
}

// A button with an icon and optional text
function iconButton(name, label, className = "icon-btn") {
  const button = el("button", className);
  button.type = "button";
  button.append(icon(name));
  button.setAttribute("aria-label", label);
  return button;
}

// ---------- Toasts ----------
function toast(text, type = "info") {
  let stack = document.querySelector(".toast-stack");
  if (!stack) {
    stack = el("div", "toast-stack");
    stack.setAttribute("role", "status");
    stack.setAttribute("aria-live", "polite");
    document.body.append(stack);
  }
  const names = { success: "check-circle", error: "alert", info: "info" };
  const item = el("div", "toast " + type);
  item.append(icon(names[type] || "info"), el("span", null, text));
  stack.append(item);
  while (stack.children.length > 3) stack.firstChild.remove();

  setTimeout(() => {
    item.classList.add("leaving");
    item.addEventListener("animationend", () => item.remove(), { once: true });
  }, type === "error" ? 5000 : 3200);
}

// ---------- Modals ----------
// openModal(box) shows a .modal element and returns a close() function.
let openModals = 0;

function openModal(box, { onClose, dismissible = true } = {}) {
  const backdrop = el("div", "modal-backdrop");
  backdrop.append(box);
  box.setAttribute("role", "dialog");
  box.setAttribute("aria-modal", "true");
  const previousFocus = document.activeElement;
  document.body.append(backdrop);
  openModals++;
  document.documentElement.style.overflow = "hidden";

  let closed = false;
  function close() {
    if (closed) return;
    closed = true;
    document.removeEventListener("keydown", onKey, true);
    backdrop.classList.add("closing");
    setTimeout(() => {
      backdrop.remove();
      openModals--;
      if (openModals === 0) document.documentElement.style.overflow = "";
      if (previousFocus && previousFocus.focus) previousFocus.focus();
    }, 170);
    if (onClose) onClose();
  }

  function onKey(event) {
    if (event.key === "Escape" && dismissible) {
      event.stopPropagation();
      close();
    }
    if (event.key === "Tab") trapFocus(event, box);
  }
  document.addEventListener("keydown", onKey, true);
  backdrop.addEventListener("mousedown", (event) => {
    if (event.target === backdrop && dismissible) close();
  });

  // Focus the first field, or the first button
  requestAnimationFrame(() => {
    const target = box.querySelector("[autofocus], input, textarea, select, .btn-primary, .btn-danger-solid, button");
    if (target) target.focus();
  });
  return close;
}

function trapFocus(event, container) {
  const items = [...container.querySelectorAll("a[href], button:not(:disabled), input, select, textarea, [tabindex]:not([tabindex='-1'])")]
    .filter((n) => n.offsetParent !== null);
  if (items.length === 0) return;
  const first = items[0];
  const last = items[items.length - 1];
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}

// confirmDialog({...}) resolves to true (confirmed) or false
function confirmDialog({ title, message, confirmText = "Confirm", cancelText = "Cancel", danger = false, iconName }) {
  return new Promise((resolve) => {
    const box = el("div", "modal");
    const titleId = "dlg-" + Math.random().toString(36).slice(2);
    box.setAttribute("aria-labelledby", titleId);

    const head = el("div", "modal-head");
    const text = el("div");
    if (danger || iconName) {
      const badge = el("div", "modal-icon");
      if (!danger) badge.style.cssText = "background:var(--primary-soft);color:var(--primary)";
      badge.append(icon(iconName || "trash"));
      text.append(badge);
    }
    const h = el("h2", null, title);
    h.id = titleId;
    text.append(h);
    if (message) text.append(el("p", null, message));
    head.append(text);

    const foot = el("div", "modal-foot");
    foot.style.paddingTop = "22px";
    const cancel = el("button", "btn", cancelText);
    const ok = el("button", "btn " + (danger ? "btn-danger-solid" : "btn-primary"), confirmText);
    cancel.type = ok.type = "button";
    foot.append(cancel, ok);
    box.append(head, foot);

    let answer = false;
    const close = openModal(box, { onClose: () => resolve(answer) });
    cancel.addEventListener("click", close);
    ok.addEventListener("click", () => {
      answer = true;
      close();
    });
  });
}

// ---------- Dropdown menus ----------
// <div class="menu-wrap"><button data-menu-button aria-expanded="false">…</button><div class="menu">…</div></div>
document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-menu-button]");
  document.querySelectorAll(".menu.open").forEach((menu) => {
    if (!button || menu.parentElement !== button.parentElement) {
      menu.classList.remove("open");
      const b = menu.parentElement.querySelector("[data-menu-button]");
      if (b) b.setAttribute("aria-expanded", "false");
    }
  });
  if (button) {
    const menu = button.parentElement.querySelector(".menu");
    const open = !menu.classList.contains("open");
    menu.classList.toggle("open", open);
    button.setAttribute("aria-expanded", String(open));
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  document.querySelectorAll(".menu.open").forEach((menu) => {
    menu.classList.remove("open");
    const b = menu.parentElement.querySelector("[data-menu-button]");
    if (b) { b.setAttribute("aria-expanded", "false"); b.focus(); }
  });
});

// ---------- Copy to clipboard ----------
function copyButton(text, label = "Copy") {
  const button = el("button", "btn btn-sm copy-btn");
  button.type = "button";
  const iconNode = icon("copy", "i-sm");
  const span = el("span", null, label);
  button.append(iconNode, span);
  button.setAttribute("aria-label", "Copy " + text);
  button.addEventListener("click", async () => {
    let ok = true;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      ok = fallbackCopy(text);
    }
    button.classList.toggle("copied", ok);
    iconNode.querySelector("use").setAttribute("href", "/icons.svg#" + (ok ? "check" : "alert"));
    span.textContent = ok ? "Copied" : "Copy failed";
    clearTimeout(button.timer);
    button.timer = setTimeout(() => {
      button.classList.remove("copied");
      iconNode.querySelector("use").setAttribute("href", "/icons.svg#copy");
      span.textContent = label;
    }, 1600);
  });
  return button;
}

function fallbackCopy(text) {
  const area = el("textarea");
  area.value = text;
  area.style.cssText = "position:fixed;opacity:0";
  document.body.append(area);
  area.select();
  let ok = false;
  try { ok = document.execCommand("copy"); } catch { ok = false; }
  area.remove();
  return ok;
}

// ---------- Avatars ----------
function nameFromEmail(email) {
  const local = String(email || "").split("@")[0] || "?";
  return local
    .split(/[._-]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ") || local;
}

function avatar(email, size = "") {
  const name = nameFromEmail(email);
  const words = name.split(" ");
  const initials = (words[0][0] + (words[1] ? words[1][0] : (words[0][1] || ""))).toUpperCase();
  let hash = 0;
  for (const ch of String(email)) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  const node = el("span", "avatar" + (size ? " avatar-" + size : ""), initials);
  node.style.setProperty("--h", String(hash % 360));
  node.setAttribute("aria-hidden", "true");
  return node;
}

// ---------- Buttons with a loading state ----------
function setBusy(button, busy, busyText) {
  if (busy) {
    button.dataset.html = button.innerHTML;
    button.disabled = true;
    button.replaceChildren(el("span", "spinner"), document.createTextNode(busyText || ""));
  } else if (button.dataset.html !== undefined) {
    button.innerHTML = button.dataset.html;
    button.disabled = false;
    delete button.dataset.html;
  }
}

// "2 Mar 2026, 14:05"
function formatFullDate(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleString([], {
    day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit",
  });
}

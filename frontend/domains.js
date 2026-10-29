// ============================================================
// domains.js — the "My domains" page
// ============================================================

const $ = (id) => document.getElementById(id);

function showMessage(text, type = "error") {
  $("domain-message").textContent = text;
  $("domain-message").className = "alert alert-" + type;
}

function hideMessage() {
  $("domain-message").className = "alert hidden";
}

async function loadUser() {
  try {
    const data = await api("/api/auth/me");
    $("user-email").textContent = data.user.email;
  } catch (err) {
    if (err.status === 401) window.location.href = "/login.html";
    else showMessage(err.message);
  }
}

// ---------- List of domains ----------
async function loadDomains() {
  const list = $("domain-list");
  list.replaceChildren(el("div", "state", "Loading your domains..."));
  try {
    const data = await api("/api/domains");
    list.replaceChildren();
    if (data.domains.length === 0) {
      list.append(el("div", "state", "You haven't added a domain yet."));
      return;
    }
    data.domains.forEach((d) => list.append(renderDomain(d)));
  } catch (err) {
    list.replaceChildren(el("div", "state error", err.message));
  }
}

function copyButton(text) {
  const button = el("button", "btn btn-light btn-small", "Copy");
  button.type = "button";
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied ✓";
    } catch {
      button.textContent = "Copy failed";
    }
    setTimeout(() => (button.textContent = "Copy"), 1500);
  });
  return button;
}

function renderDomain(d) {
  const verified = d.status === "verified";
  const card = el("div", "domain-card");

  // Name + status badge
  const header = el("div", "domain-header");
  header.append(
    el("h3", null, d.name),
    el("span", "status-badge " + (verified ? "verified" : "pending"),
       verified ? "✅ Verified" : "⏳ Waiting for DNS record")
  );
  card.append(header);

  card.append(el("p", "muted", verified
    ? "Ownership confirmed on " + new Date(d.verified_at).toLocaleString() + ". Keep this record in place."
    : "Add this record to your domain's DNS, wait a few minutes, then click “Check now”."));

  // DNS records table
  const table = el("table", "dns-table");
  const head = el("tr");
  ["Type", "Host / Name", "Value", ""].forEach((h) => head.append(el("th", null, h)));
  table.append(head);

  d.dns_records.forEach((r) => {
    const row = el("tr");
    const host = el("td");
    host.append(el("code", null, r.host));
    const value = el("td");
    value.append(el("code", null, r.value));
    const copy = el("td");
    copy.append(copyButton(r.value));
    row.append(el("td", null, r.type), host, value, copy);
    table.append(row);
  });

  const wrap = el("div", "table-wrap");
  wrap.append(table);
  card.append(wrap);
  // Email addresses (only after the domain is verified)
  if (verified) card.append(renderAddresses(d));
  // Buttons
  const actions = el("div", "domain-actions");
  if (!verified) {
    const check = el("button", "btn btn-primary", "Check now");
    check.addEventListener("click", () => verifyDomain(d.id, check));
    actions.append(check);
  }
  const remove = el("button", "btn btn-danger", "Remove");
  remove.addEventListener("click", () => removeDomain(d));
  actions.append(remove);
  card.append(actions);

  return card;
}
// ---------- Addresses on a verified domain ----------
function renderAddresses(d) {
  const section = el("div", "address-section");
  section.append(el("h4", null, "Email addresses on " + d.name));

  const list = el("ul", "address-list");
  if (d.addresses.length === 0) {
    list.append(el("li", "muted", "No addresses yet. Create your first one below."));
  }
  d.addresses.forEach((a) => {
    const item = el("li");
    const remove = el("button", "btn btn-light btn-small", "Delete");
    remove.type = "button";
    remove.addEventListener("click", () => deleteAddress(d, a));
    item.append(el("span", null, "📧 " + a.email), remove);
    list.append(item);
  });
  section.append(list);

  const form = el("form", "address-form");
  const input = el("input");
  input.type = "text";
  input.placeholder = "info";
  input.maxLength = 30;
  input.setAttribute("aria-label", "New address name");
  const button = el("button", "btn btn-primary", "Create address");
  button.type = "submit";
  form.append(input, el("span", "address-suffix", "@" + d.name), button);
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    createAddress(d, input.value.trim().toLowerCase());
  });
  section.append(form);

  return section;
}

async function createAddress(d, localPart) {
  hideMessage();
  if (!localPart) {
    showMessage("Type a name for the address, for example info");
    return;
  }
  try {
    const data = await api("/api/domains/" + encodeURIComponent(d.id) + "/addresses", {
      method: "POST",
      body: { local_part: localPart },
    });
    showMessage(data.address.email + " was created. Emails to it will arrive in your inbox.", "success");
    loadDomains();
  } catch (err) {
    showMessage(err.message);
  }
}

async function deleteAddress(d, a) {
  if (!confirm("Delete " + a.email + "? New emails to it will no longer arrive.")) return;
  hideMessage();
  try {
    await api(
      "/api/domains/" + encodeURIComponent(d.id) + "/addresses/" + encodeURIComponent(a.id),
      { method: "DELETE" }
    );
    showMessage(a.email + " was deleted.", "success");
    loadDomains();
  } catch (err) {
    showMessage(err.message);
  }
}
// ---------- Actions ----------
async function verifyDomain(id, button) {
  hideMessage();
  button.disabled = true;
  button.textContent = "Checking...";
  try {
    const data = await api("/api/domains/" + encodeURIComponent(id) + "/verify", { method: "POST" });
    showMessage(data.message || "Domain verified!", "success");
    loadDomains();
  } catch (err) {
    showMessage(err.message);
    button.disabled = false;
    button.textContent = "Check now";
  }
}

async function removeDomain(d) {
    if (!confirm("Remove " + d.name + " from MailSpace? Its email addresses will be deleted too.")) return;
  hideMessage();
  try {
    await api("/api/domains/" + encodeURIComponent(d.id), { method: "DELETE" });
    showMessage(d.name + " was removed.", "success");
    loadDomains();
  } catch (err) {
    showMessage(err.message);
  }
}

$("add-domain-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  hideMessage();
  const name = $("domain-name").value.trim();
  if (!name) {
    showMessage("Please type your domain, for example yourbusiness.com");
    return;
  }
  try {
    const data = await api("/api/domains", { method: "POST", body: { name } });
    $("domain-name").value = "";
    showMessage(data.domain.name + " was added. Now add the DNS record below.", "success");
    loadDomains();
  } catch (err) {
    showMessage(err.message);
  }
});

// ---------- Start ----------
loadUser();
loadDomains();
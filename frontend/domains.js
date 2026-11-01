// ============================================================
// domains.js — "My domains": list, add-domain wizard,
// domain details (DNS record, verification, addresses).
// Needs api.js, ui.js and shell.js.
// URL: /domains.html            → list
//      /domains.html#d=<id>     → details for one domain
// ============================================================

const MAX_DOMAINS = 3;          // same limits as the server
const MAX_ADDRESSES = 10;
const view = document.getElementById("domains-view");
let domainsCache = [];

// ---------- Small helpers ----------
function statusBadge(d) {
  return d.status === "verified"
    ? el("span", "badge badge-success", "Verified")
    : el("span", "badge badge-warning badge-pending", "Waiting for DNS");
}

function shortDate(iso) {
  return iso ? new Date(iso).toLocaleDateString([], { day: "numeric", month: "short", year: "numeric" }) : "—";
}

function domainMark() {
  const m = el("span", "domain-mark");
  m.append(icon("globe"));
  return m;
}

function panel(title, description, extraClass = "") {
  const box = el("section", "panel surface " + extraClass);
  const head = el("div", "panel-head");
  const text = el("div");
  const h = el("h2", null, title);
  text.append(h);
  if (description) text.append(el("p", null, description));
  head.append(text);
  box.append(head);
  return { box, head };
}

function routeId() {
  const match = location.hash.match(/^#d=([a-f0-9]{24})$/i);
  return match ? match[1] : null;
}

// ---------- Loading ----------
async function loadDomains() {
  const data = await api("/api/domains");
  domainsCache = data.domains;
  return domainsCache;
}

async function render() {
  const id = routeId();
  view.replaceChildren(loadingState());
  try {
    await loadDomains();
  } catch (err) {
    view.replaceChildren(errorState(err.message));
    return;
  }
  if (id) {
    const d = domainsCache.find((x) => x.id === id);
    if (d) renderDetails(d);
    else {
      history.replaceState(null, "", "/domains.html");
      renderList();
      toast("That domain isn't on your account anymore.", "error");
    }
  } else {
    renderList();
  }
  document.getElementById("main").scrollTop = 0;
}

function loadingState() {
  const box = el("div");
  const head = el("div", "page-head");
  const t = el("div");
  const a = el("span", "skeleton"); a.style.cssText = "width:200px;height:30px";
  const b = el("span", "skeleton"); b.style.cssText = "width:320px;height:14px;margin-top:12px";
  t.append(a, b);
  head.append(t);
  const grid = el("div", "domain-grid");
  for (let i = 0; i < 3; i++) {
    const s = el("span", "skeleton");
    s.style.cssText = "height:190px;border-radius:16px";
    grid.append(s);
  }
  box.append(head, grid);
  return box;
}

function errorState(message) {
  const box = el("div", "empty surface");
  const art = el("div", "empty-art");
  art.style.cssText = "background:var(--error-soft);color:var(--error-text)";
  art.append(icon("alert"));
  const b = el("button", "btn btn-sm", "Try again");
  b.type = "button";
  b.addEventListener("click", render);
  box.append(art, el("h3", null, "Couldn't load your domains"), el("p", null, message), b);
  return box;
}

// ---------- List ----------
function renderList() {
  document.title = "My domains · MailSpace";
  const wrap = el("div");

  const head = el("div", "page-head");
  const text = el("div");
  text.append(
    el("h1", null, "My domains"),
    el("p", null, "Connect a domain you own, prove it's yours with one DNS record, then create addresses like info@yourbusiness.com.")
  );
  head.append(text);
  const canAdd = domainsCache.length < MAX_DOMAINS;
  if (domainsCache.length > 0) {
    const add = el("button", "btn btn-primary");
    add.type = "button";
    add.append(icon("plus", "i-sm"), el("span", null, "Add domain"));
    add.disabled = !canAdd;
    if (!canAdd) add.title = "You can add up to " + MAX_DOMAINS + " domains";
    add.addEventListener("click", openWizard);
    head.append(add);
  }
  wrap.append(head);

  if (domainsCache.length === 0) {
    wrap.append(emptyDomains());
  } else {
    const grid = el("div", "domain-grid");
    domainsCache.forEach((d, i) => {
      const card = domainCard(d);
      card.style.animationDelay = i * 60 + "ms";
      grid.append(card);
    });
    if (canAdd) {
      const add = el("button", "domain-card surface add-card");
      add.type = "button";
      add.style.animationDelay = domainsCache.length * 60 + "ms";
      const mark = domainMark();
      mark.replaceChildren(icon("plus"));
      add.append(mark, el("strong", null, "Add another domain"), el("p", null, (MAX_DOMAINS - domainsCache.length) + " of " + MAX_DOMAINS + " remaining"));
      add.addEventListener("click", openWizard);
      grid.append(add);
    }
    wrap.append(grid);
    wrap.append(el("p", "limits-note", "Each account can connect up to " + MAX_DOMAINS + " domains, with up to " + MAX_ADDRESSES + " addresses per domain."));
  }
  view.replaceChildren(wrap);
}

function domainCard(d) {
  const card = el("a", "domain-card surface");
  card.href = "#d=" + d.id;
  card.setAttribute("aria-label", "Manage " + d.name);

  const top = el("div", "domain-card-top");
  const names = el("div");
  names.style.cssText = "flex:1;min-width:0";
  names.append(el("h2", null, d.name), el("span", null, "Added " + shortDate(d.created_at)));
  top.append(domainMark(), names);

  const facts = el("div", "domain-facts");
  const f1 = el("div", "fact");
  f1.append(el("span", "fact-label", "Status"), statusBadge(d));
  const f2 = el("div", "fact");
  f2.append(el("span", "fact-label", d.status === "verified" ? "Verified on" : "Addresses"),
    el("strong", null, d.status === "verified" ? shortDate(d.verified_at) : "After verification"));
  const f3 = el("div", "fact");
  f3.style.gridColumn = "1 / -1";
  f3.append(el("span", "fact-label", "Email addresses"),
    el("strong", null, d.addresses.length ? d.addresses.length + " of " + MAX_ADDRESSES + " · " + d.addresses.slice(0, 2).map((a) => a.email.split("@")[0]).join(", ") + (d.addresses.length > 2 ? "…" : "") : "None yet"));
  if (d.status === "verified") facts.append(f1, f2, f3);
  else facts.append(f1, f3);

  const manage = el("div", "manage");
  manage.append(el("span", null, d.status === "verified" ? "Manage domain" : "Finish setup"), icon("arrow-right", "i-sm"));

  card.append(top, facts, manage);
  return card;
}

function emptyDomains() {
  const box = el("div", "surface empty domains-empty");
  const art = el("div", "empty-art");
  art.append(icon("globe"));
  const b = el("button", "btn btn-primary");
  b.type = "button";
  b.append(icon("plus", "i-sm"), el("span", null, "Add your first domain"));
  b.addEventListener("click", openWizard);
  box.append(
    art,
    el("h3", null, "Use your own domain with MailSpace"),
    el("p", null, "It takes about five minutes: enter your domain, add one TXT record where you bought it, and we'll confirm it's yours."),
    b
  );
  return box;
}

// ---------- Add-domain wizard ----------
function openWizard() {
  const box = el("div", "modal modal-wide");
  box.setAttribute("aria-labelledby", "wiz-title");

  const head = el("div", "modal-head");
  const titles = el("div");
  const h = el("h2", null, "Add a domain");
  h.id = "wiz-title";
  const sub = el("p", null, "We'll walk you through it step by step.");
  titles.append(h, sub);
  const closeBtn = iconButton("x", "Close");
  head.append(titles, closeBtn);

  const steps = el("div", "wizard-steps");
  const stepNodes = ["Your domain", "Add DNS record", "Verify"].map((label, i) => {
    const s = el("div", "wizard-step");
    s.append(el("span", "num", String(i + 1)), el("span", "text", label));
    return s;
  });
  const lines = [el("div", "wizard-line"), el("div", "wizard-line")];
  steps.append(stepNodes[0], lines[0], stepNodes[1], lines[1], stepNodes[2]);

  const body = el("div", "modal-body");
  const foot = el("div", "modal-foot");
  box.append(head, steps, body, foot);

  let domain = null;
  let changed = false;
  const close = openModal(box, { onClose: () => { if (changed) render(); } });
  closeBtn.addEventListener("click", close);

  function setStep(n) {
    stepNodes.forEach((s, i) => {
      s.classList.toggle("active", i === n);
      s.classList.toggle("done", i < n);
      s.querySelector(".num").replaceChildren(i < n ? icon("check", "i-sm") : document.createTextNode(String(i + 1)));
    });
    lines.forEach((l, i) => l.classList.toggle("done", i < n));
  }

  // Step 1 — enter the domain
  function stepDomain() {
    setStep(0);
    const pane = el("form", "wizard-pane");
    pane.noValidate = true;
    pane.id = "wiz-domain-form";
    const field = el("div", "field");
    const label = el("label", null, "Domain name");
    label.htmlFor = "wiz-domain";
    const input = el("input", "input");
    input.id = "wiz-domain";
    input.placeholder = "yourbusiness.com";
    input.autocomplete = "off";
    input.spellcheck = false;
    input.setAttribute("autocapitalize", "off");
    field.append(label, input, el("span", "hint", "Enter only the domain — without https:// or www. You must be able to change its DNS settings."));
    const alert = el("div", "alert alert-error hidden");
    alert.setAttribute("role", "alert");
    pane.append(alert, field);

    const tip = el("div", "wizard-tip");
    tip.append(icon("info", "i-sm"), el("span", null, "Adding a domain doesn't change anything on it. Nothing happens until you add the record in the next step."));
    pane.append(tip);
    body.replaceChildren(pane);

    const cancel = el("button", "btn", "Cancel");
    cancel.type = "button";
    cancel.addEventListener("click", close);
    const next = el("button", "btn btn-primary");
    next.type = "submit";
    next.setAttribute("form", "wiz-domain-form");
    next.append(el("span", null, "Continue"), icon("arrow-right", "i-sm"));
    foot.replaceChildren(cancel, next);
    input.focus();

    pane.addEventListener("submit", async (event) => {
      event.preventDefault();
      const name = input.value.trim();
      if (!name) {
        alert.replaceChildren(icon("alert", "i-sm"), el("span", null, "Type your domain, for example yourbusiness.com"));
        alert.classList.remove("hidden");
        input.setAttribute("aria-invalid", "true");
        input.focus();
        return;
      }
      setBusy(next, true, "Adding…");
      try {
        const data = await api("/api/domains", { method: "POST", body: { name } });
        domain = data.domain;
        changed = true;
        stepRecord();
      } catch (err) {
        setBusy(next, false);
        alert.replaceChildren(icon("alert", "i-sm"), el("span", null, err.message));
        alert.classList.remove("hidden");
        input.setAttribute("aria-invalid", "true");
        input.focus();
      }
    });
  }

  // Step 2 — show the DNS record
  function stepRecord(errorText) {
    setStep(1);
    sub.textContent = domain.name;
    const pane = el("div", "wizard-pane");
    if (errorText) {
      const alert = el("div", "alert alert-warning");
      alert.style.marginBottom = "14px";
      alert.append(icon("alert", "i-sm"), el("span", null, errorText));
      pane.append(alert);
    }
    pane.append(el("p", "muted small", "Sign in where you manage your domain's DNS (usually where you bought it) and add this record:"));
    const card = recordCard(domain);
    card.style.marginTop = "12px";
    pane.append(card, providerHelp(domain));
    const tip = el("div", "wizard-tip");
    tip.append(icon("clock", "i-sm"), el("span", null, "DNS changes usually appear within a few minutes, but can take up to a few hours. You can close this window and check later from the domain's page."));
    pane.append(tip);
    body.replaceChildren(pane);

    const later = el("button", "btn", "I'll do this later");
    later.type = "button";
    later.addEventListener("click", close);
    const check = el("button", "btn btn-primary");
    check.type = "button";
    check.append(icon("check-circle", "i-sm"), el("span", null, "I've added it — verify"));
    check.addEventListener("click", stepVerify);
    foot.replaceChildren(later, check);
  }

  // Step 3 — ask the server to check DNS
  async function stepVerify() {
    setStep(2);
    const pane = el("div", "wizard-pane");
    const boxV = el("div", "verify-box");
    const orb = el("span", "verify-orb checking");
    orb.append(icon("globe"));
    const t = el("div", "grow");
    t.append(el("strong", null, "Checking DNS for " + domain.name + "…"), el("p", null, "Looking up _mailspace." + domain.name + " on public DNS servers."));
    boxV.append(orb, t);
    pane.append(boxV);
    body.replaceChildren(pane);
    foot.replaceChildren();

    try {
      const data = await verifyRequest(domain.id);
      domain = data.domain;
      changed = true;
      setStep(3);
      const done = el("div", "wizard-pane");
      const art = el("div", "result-art");
      art.append(successCheck());
      const text = el("div", "result-text");
      text.append(el("h3", null, domain.name + " is verified"), el("p", null, "You can now create email addresses on this domain."));
      done.append(art, text);
      body.replaceChildren(done);
      const finish = el("button", "btn", "Close");
      finish.type = "button";
      finish.addEventListener("click", close);
      const create = el("button", "btn btn-primary");
      create.type = "button";
      create.append(icon("at", "i-sm"), el("span", null, "Create an address"));
      create.addEventListener("click", () => {
        changed = false;
        close();
        location.hash = "d=" + domain.id;
      });
      foot.replaceChildren(finish, create);
      create.focus();
    } catch (err) {
      stepRecord(err.message);
    }
  }

  stepDomain();
}

function successCheck() {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 76 76");
  svg.setAttribute("class", "success-check");
  svg.setAttribute("aria-hidden", "true");
  svg.innerHTML = '<circle cx="38" cy="38" r="38"/><path d="m25 39 9 9 17-19"/>';
  return svg;
}

async function verifyRequest(id) {
  // Show the check for at least a moment so the result doesn't flash by
  const [result] = await Promise.allSettled([
    api("/api/domains/" + encodeURIComponent(id) + "/verify", { method: "POST" }),
    new Promise((r) => setTimeout(r, 900)),
  ]);
  if (result.status === "rejected") throw result.reason;
  return result.value;
}

// The TXT record as rows with copy buttons
function recordCard(d) {
  const r = d.dns_records[0];
  const card = el("div", "record-card");
  [["Type", r.type, false], ["Host / Name", r.host, true], ["Value", r.value, true]].forEach(([label, value, copy]) => {
    const row = el("div", "record-row");
    const code = el("code", null, value);
    row.append(el("span", null, label), code);
    if (copy) row.append(copyButton(value));
    else row.append(el("span"));
    card.append(row);
  });
  return card;
}

function providerHelp(d) {
  const wrap = el("div", "dns-help");
  const guides = [
    ["Namecheap", ["Open Domain List and click Manage next to " + d.name + ".", "Go to Advanced DNS and click Add New Record.", "Choose TXT Record. In Host type _mailspace and paste the value.", "Click the green check mark to save."]],
    ["Netlify DNS", ["Open Domains and select " + d.name + ".", "In DNS settings, click Add new record.", "Choose TXT. In Name type _mailspace and paste the value.", "Save the record."]],
    ["Cloudflare", ["Select " + d.name + " and open DNS → Records.", "Click Add record and choose TXT.", "In Name type _mailspace and paste the value into Content.", "Save."]],
    ["any other provider", ["Find the DNS settings for " + d.name + ".", "Add a new TXT record.", "Host / Name: _mailspace (some providers want the full name: _mailspace." + d.name + ").", "Value: paste the value exactly, then save."]],
  ];
  guides.forEach(([name, steps]) => {
    const det = el("details");
    const sum = el("summary");
    sum.append(el("span", null, (name === "any other provider" ? "Using any other provider" : "Step-by-step for " + name)), icon("chevron-down", "i-sm"));
    const ol = el("ol");
    steps.forEach((s) => ol.append(el("li", null, s)));
    det.append(sum, ol);
    wrap.append(det);
  });
  return wrap;
}

// ---------- Details ----------
function renderDetails(d) {
  document.title = d.name + " · My domains · MailSpace";
  const verified = d.status === "verified";
  const wrap = el("div");

  const crumb = el("a", "crumb");
  crumb.href = "/domains.html";
  crumb.append(icon("arrow-left", "i-sm"), el("span", null, "All domains"));

  const head = el("div", "detail-head");
  const mark = domainMark();
  const text = el("div", "grow");
  const h = el("h1", null, d.name);
  text.append(h, el("p", null, verified
    ? "Verified on " + shortDate(d.verified_at) + ". Keep the DNS record in place."
    : "Add the DNS record below, then check verification."));
  head.append(mark, text, statusBadge(d));
  wrap.append(crumb, head);

  const grid = el("div", "detail-grid");
  const main = el("div", "detail-main");
  const side = el("div", "detail-side");

  // Ownership verification
  const own = panel("Ownership verification", "This TXT record proves you control " + d.name + ".");
  const vbox = el("div", "verify-box" + (verified ? " ok" : ""));
  const orb = el("span", "verify-orb");
  orb.append(icon(verified ? "check-circle" : "clock"));
  const vtext = el("div", "grow");
  vtext.append(
    el("strong", null, verified ? "Domain verified" : "Waiting for the DNS record"),
    el("p", null, verified ? "We found the record on " + shortDate(d.verified_at) + "." : "Once the record is published, click Check now.")
  );
  vbox.append(orb, vtext);
  if (!verified) {
    const check = el("button", "btn btn-primary btn-sm");
    check.type = "button";
    check.append(icon("refresh", "i-sm"), el("span", null, "Check now"));
    check.addEventListener("click", async () => {
      orb.classList.add("checking");
      setBusy(check, true, "Checking…");
      const old = own.box.querySelector(".verify-error");
      if (old) old.remove();
      try {
        const data = await verifyRequest(d.id);
        toast(data.domain.name + " is verified", "success");
        Object.assign(d, data.domain, { addresses: d.addresses });
        renderDetails(d);
      } catch (err) {
        orb.classList.remove("checking");
        setBusy(check, false);
        const alert = el("div", "alert alert-warning verify-error");
        alert.style.marginBottom = "16px";
        alert.append(icon("alert", "i-sm"), el("span", null, err.message));
        vbox.after(alert);
      }
    });
    vbox.append(check);
  }
  own.box.append(vbox, dnsTable(d));
  if (!verified) own.box.append(providerHelp(d));
  main.append(own.box);

  // Email authentication — honest status: MailSpace doesn't manage these yet
  const auth = panel("Email authentication", "SPF, DKIM and DMARC tell other mail servers that messages from " + d.name + " are genuine.");
  const rows = el("div", "auth-rows");
  [
    ["SPF", "Lists the servers allowed to send mail for your domain."],
    ["DKIM", "Signs each message so receivers can check it wasn't changed."],
    ["DMARC", "Tells receivers what to do with mail that fails SPF or DKIM."],
  ].forEach(([key, desc]) => {
    const row = el("div", "auth-row");
    const t = el("div", "grow");
    t.append(el("strong", null, key), el("p", null, desc));
    const tile = el("span", "auth-key");
    tile.append(icon("shield", "i-sm"));
    row.append(tile, t, el("span", "badge", "Not configured"));
    rows.append(row);
  });
  const note = el("div", "alert alert-info");
  note.style.marginTop = "14px";
  note.append(icon("info", "i-sm"), el("span", null,
    "MailSpace doesn't generate or check SPF, DKIM or DMARC records for custom domains yet, so there's nothing to add here. " +
    "Addresses on " + d.name + " currently send and receive mail between MailSpace accounts."));
  auth.box.append(rows, note);
  main.append(auth.box);

  // Addresses
  main.append(addressesPanel(d));

  // Side: overview
  const ov = panel("Overview");
  const dl = el("dl", "overview-list");
  [
    ["Domain", d.name],
    ["Ownership", verified ? "Verified" : "Pending"],
    ["Added", shortDate(d.created_at)],
    ["Verified", verified ? shortDate(d.verified_at) : "Not yet"],
    ["Addresses", d.addresses.length + " of " + MAX_ADDRESSES],
  ].forEach(([k, v]) => {
    const row = el("div");
    row.append(el("dt", null, k), el("dd", null, v));
    dl.append(row);
  });
  ov.box.append(dl);
  side.append(ov.box);

  // Side: how it works
  const how = panel("How these addresses work");
  const list = el("ul", "list-plain");
  [
    "Mail sent to an address on " + d.name + " from another MailSpace account arrives in your inbox.",
    "You can choose these addresses in the From box when writing to MailSpace users.",
    "Mail to Gmail, Outlook and other providers is sent from your main MailSpace address.",
  ].forEach((t) => {
    const li = el("li");
    li.append(icon("info", "i-sm"), el("span", null, t));
    li.querySelector(".i").style.color = "var(--primary)";
    list.append(li);
  });
  how.box.append(list);
  side.append(how.box);

  // Side: danger zone
  const danger = panel("Remove domain", "Removes " + d.name + " and deletes all of its addresses. Messages already received stay in your mailbox.", "danger-zone");
  const remove = el("button", "btn btn-danger btn-block");
  remove.type = "button";
  remove.append(icon("trash", "i-sm"), el("span", null, "Remove domain"));
  remove.addEventListener("click", () => removeDomain(d, remove));
  danger.box.append(remove);
  side.append(danger.box);

  grid.append(main, side);
  wrap.append(grid);
  view.replaceChildren(wrap);
}

function dnsTable(d) {
  const wrap = el("div", "dns-table-wrap");
  const table = el("table", "dns-table");
  const thead = el("thead");
  const hr = el("tr");
  ["Type", "Host / Name", "Value"].forEach((h) => hr.append(el("th", null, h)));
  thead.append(hr);
  const tbody = el("tbody");
  d.dns_records.forEach((r) => {
    const tr = el("tr");
    const type = el("td");
    type.dataset.label = "Type";
    type.append(el("span", "type-pill", r.type));
    const host = el("td");
    host.dataset.label = "Host / Name";
    const hc = el("div", "dns-cell-copy");
    hc.append(el("code", "nowrap", r.host), copyButton(r.host));
    host.append(hc);
    const value = el("td");
    value.dataset.label = "Value";
    const vc = el("div", "dns-cell-copy");
    vc.append(el("code", null, r.value), copyButton(r.value));
    value.append(vc);
    tr.append(type, host, value);
    tbody.append(tr);
  });
  table.append(thead, tbody);
  wrap.append(table);
  return wrap;
}

function addressesPanel(d) {
  const verified = d.status === "verified";
  const p = panel("Email addresses", verified
    ? "Create addresses on " + d.name + ". Mail to them arrives in your inbox."
    : "Available after the domain is verified.");
  if (verified) p.head.append(el("span", "badge no-dot", d.addresses.length + " / " + MAX_ADDRESSES));

  if (!verified) {
    const locked = el("div", "address-empty");
    const row = el("div");
    row.style.cssText = "display:flex;align-items:center;justify-content:center;gap:8px";
    row.append(icon("lock", "i-sm"), el("span", null, "Verify " + d.name + " to start creating addresses."));
    locked.append(row);
    locked.style.cssText += ";border:1px dashed var(--border-strong);border-radius:12px";
    p.box.append(locked);
    return p.box;
  }

  const list = el("ul", "address-list");
  if (d.addresses.length === 0) {
    list.append(el("li", "address-empty", "No addresses yet. Create your first one below — for example info or hello."));
  }
  d.addresses.forEach((a, i) => {
    const li = el("li", "address-item");
    li.style.animationDelay = i * 40 + "ms";
    const name = el("span", "grow", a.email);
    name.title = a.email;
    const del = iconButton("trash", "Delete " + a.email, "icon-btn icon-btn-sm");
    del.dataset.tip = "Delete";
    del.addEventListener("click", () => deleteAddress(d, a));
    li.append(icon("at", "i-sm"), name, copyButton(a.email), del);
    list.append(li);
  });
  p.box.append(list);

  if (d.addresses.length < MAX_ADDRESSES) {
    const form = el("form", "address-form");
    form.noValidate = true;
    const group = el("div", "input-group");
    const input = el("input", "input");
    input.placeholder = "info";
    input.maxLength = 30;
    input.autocomplete = "off";
    input.spellcheck = false;
    input.setAttribute("autocapitalize", "off");
    input.setAttribute("aria-label", "New address name");
    const suffix = el("span", "addon", "@" + d.name);
    suffix.title = "@" + d.name;
    group.append(input, suffix);
    const button = el("button", "btn btn-primary");
    button.type = "submit";
    button.append(icon("plus", "i-sm"), el("span", null, "Create address"));
    form.append(group, button);
    const hint = el("p", "hint", "Lowercase letters, numbers, dot or underscore. Up to 30 characters.");
    hint.style.marginTop = "8px";
    input.addEventListener("input", () => { input.value = input.value.toLowerCase().replace(/@.*/, ""); });
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const local = input.value.trim().toLowerCase();
      if (!local) {
        toast("Type a name for the address, for example info", "error");
        input.focus();
        return;
      }
      setBusy(button, true, "Creating…");
      try {
        const data = await api("/api/domains/" + encodeURIComponent(d.id) + "/addresses", { method: "POST", body: { local_part: local } });
        d.addresses.push(data.address);
        d.addresses.sort((x, y) => x.email.localeCompare(y.email));
        toast(data.address.email + " created", "success");
        renderDetails(d);
        const fresh = document.querySelector(".address-form input");
        if (fresh) fresh.focus();
      } catch (err) {
        setBusy(button, false);
        toast(err.message, "error");
        input.focus();
      }
    });
    p.box.append(form, hint);
  } else {
    p.box.append(el("p", "hint", "You've reached the limit of " + MAX_ADDRESSES + " addresses for this domain."));
  }
  return p.box;
}

async function deleteAddress(d, a) {
  const ok = await confirmDialog({
    title: "Delete " + a.email + "?",
    message: "New mail sent to this address won't arrive anymore. Messages you already received stay in your mailbox.",
    confirmText: "Delete address",
    danger: true,
  });
  if (!ok) return;
  try {
    await api("/api/domains/" + encodeURIComponent(d.id) + "/addresses/" + encodeURIComponent(a.id), { method: "DELETE" });
    d.addresses = d.addresses.filter((x) => x.id !== a.id);
    toast(a.email + " deleted", "success");
    renderDetails(d);
  } catch (err) {
    toast(err.message, "error");
  }
}

async function removeDomain(d, button) {
  const ok = await confirmDialog({
    title: "Remove " + d.name + "?",
    message: d.addresses.length
      ? "Its " + d.addresses.length + (d.addresses.length === 1 ? " address" : " addresses") + " will be deleted too. You can add the domain again later."
      : "You can add it again later.",
    confirmText: "Remove domain",
    danger: true,
  });
  if (!ok) return;
  setBusy(button, true, "Removing…");
  try {
    await api("/api/domains/" + encodeURIComponent(d.id), { method: "DELETE" });
    toast(d.name + " removed", "success");
    history.replaceState(null, "", "/domains.html");
    render();
  } catch (err) {
    setBusy(button, false);
    toast(err.message, "error");
  }
}

// ---------- Start ----------
window.addEventListener("hashchange", render);
Shell.userReady.then(render).catch(() => view.replaceChildren(errorState("Couldn't reach MailSpace. Check your connection and refresh.")));

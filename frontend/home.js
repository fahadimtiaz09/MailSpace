// ============================================================
// home.js — the public landing page
// ============================================================
(function () {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Logged in? Swap "Sign in / Get started" for "Open inbox"
  api("/api/auth/me")
    .then(() => {
      document.querySelectorAll(".js-guest").forEach((n) => n.classList.add("hidden"));
      document.querySelectorAll(".js-member").forEach((n) => n.classList.remove("hidden"));
    })
    .catch(() => {}); // not logged in: keep the guest buttons

  document.getElementById("year").textContent = new Date().getFullYear();

  // ---------- Sticky navigation ----------
  const nav = document.getElementById("nav");
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 8);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // Mobile menu
  const burger = document.getElementById("nav-burger");
  function setMenu(open) {
    nav.classList.toggle("menu-open", open);
    burger.setAttribute("aria-expanded", String(open));
    burger.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    burger.querySelector("use").setAttribute("href", "/icons.svg#" + (open ? "x" : "menu"));
  }
  burger.addEventListener("click", () => setMenu(!nav.classList.contains("menu-open")));
  document.querySelectorAll("#nav-links > a, .nav-mobile-actions a").forEach((a) => a.addEventListener("click", () => setMenu(false)));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") setMenu(false); });
  window.addEventListener("resize", () => { if (window.innerWidth > 920) setMenu(false); });

  // Features dropdown (click on touch, hover on desktop)
  const drop = document.querySelector(".nav-drop");
  const dropBtn = drop.querySelector(".nav-drop-btn");
  function setDrop(open) {
    drop.classList.toggle("open", open);
    dropBtn.setAttribute("aria-expanded", String(open));
  }
  dropBtn.addEventListener("click", (e) => { e.stopPropagation(); setDrop(!drop.classList.contains("open")); });
  const canHover = window.matchMedia("(hover: hover) and (min-width: 921px)");
  let leaveTimer;
  drop.addEventListener("mouseenter", () => { if (canHover.matches) { clearTimeout(leaveTimer); setDrop(true); } });
  drop.addEventListener("mouseleave", () => { if (canHover.matches) leaveTimer = setTimeout(() => setDrop(false), 160); });
  drop.querySelectorAll(".nav-drop-menu a").forEach((a) => a.addEventListener("click", () => { setDrop(false); setMenu(false); }));
  document.addEventListener("click", (e) => { if (!drop.contains(e.target)) setDrop(false); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && drop.classList.contains("open")) { setDrop(false); dropBtn.focus(); } });

  // Highlight the nav link for the section on screen
  const links = [...document.querySelectorAll(".nav-links > a[href^='#']")];
  const sections = links.map((a) => document.querySelector(a.getAttribute("href"))).filter(Boolean);
  const sectionObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      links.forEach((a) => a.classList.toggle("current", a.getAttribute("href") === "#" + entry.target.id));
    });
  }, { rootMargin: "-45% 0px -50% 0px" });
  sections.forEach((s) => sectionObserver.observe(s));

  // ---------- Scroll reveals ----------
  const revealObserver = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("in");
      revealObserver.unobserve(entry.target);
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  document.querySelectorAll(".reveal").forEach((n) => revealObserver.observe(n));

  // Steps: draw the connecting line once
  const steps = document.querySelector(".steps");
  new IntersectionObserver((entries, obs) => {
    if (entries[0].isIntersecting) {
      steps.classList.add("in-view");
      obs.disconnect();
    }
  }, { threshold: 0.4 }).observe(steps);

  // ---------- Hero: a new message arrives ----------
  const newRow = document.getElementById("hero-new");
  const count = document.getElementById("hero-count");
  function arrive() {
    newRow.classList.add("arrived");
    count.textContent = "3";
    count.classList.add("bump");
    setTimeout(() => newRow.classList.add("settled"), 2200);
  }
  if (reduceMotion) arrive();
  else setTimeout(arrive, 1600);

  // ---------- Domain preview: "checking" turns into "verified" ----------
  const status = document.getElementById("pvd-status");
  new IntersectionObserver((entries, obs) => {
    if (!entries[0].isIntersecting) return;
    obs.disconnect();
    setTimeout(() => {
      status.classList.remove("wait");
      status.classList.add("ok");
      status.querySelector("span").textContent = "Verified";
    }, reduceMotion ? 0 : 1800);
  }, { threshold: 0.5 }).observe(document.getElementById("domain-demo"));

  // ---------- FAQ: smooth open / close ----------
  document.querySelectorAll(".faq-list details").forEach((details) => {
    const summary = details.querySelector("summary");
    const answer = details.querySelector(".faq-a");
    summary.addEventListener("click", (event) => {
      if (reduceMotion) return; // let the browser toggle instantly
      event.preventDefault();
      if (details.open) {
        const anim = answer.animate([{ height: answer.offsetHeight + "px", opacity: 1 }, { height: "0px", opacity: 0 }],
          { duration: 240, easing: "cubic-bezier(.2,.7,.2,1)" });
        details.classList.add("closing");
        anim.onfinish = () => { details.open = false; details.classList.remove("closing"); };
      } else {
        details.open = true;
        const h = answer.offsetHeight;
        answer.animate([{ height: "0px", opacity: 0 }, { height: h + "px", opacity: 1 }],
          { duration: 300, easing: "cubic-bezier(.16,1,.3,1)" });
      }
    });
  });
})();

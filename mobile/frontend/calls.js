// ============================================================
// calls.js — voice & video calls between MailSpace addresses.
// Loaded on every signed-in page (Inbox, Domains, Settings, Admin).
//
//  • Every few seconds the page tells the server "I'm online"
//    (heartbeat). The answer also says if someone is calling us.
//  • The call itself uses WebRTC (built into the browser): voice and
//    video go straight between the two people. The server only passes
//    the connection details ("offer" and "answer").
//  • When the call ends the server emails both people the start time
//    and how long it lasted.
//
// Used by app.js:  Calls.presence(email)  and  Calls.start(email, "audio" | "video")
// Needs api.js and ui.js.
// ============================================================

const Calls = (() => {
  const HEARTBEAT_MS = 4000;      // "I'm online" every 4 s (server: offline after 15 s)
  const POLL_MS = 1200;           // while dialling / in a call, check the call status
  // Free public STUN servers help two devices find each other through home routers.
  const ICE_SERVERS = [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }];

  let current = null;             // the call on screen right now
  let ignored = new Set();        // incoming call ids already declined / handled in this tab
  let heartbeatTimer = null;

  // ---------- small helpers ----------
  function supported() {
    return !!(window.RTCPeerConnection && navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  }

  function formatTimer(seconds) {
    const s = Math.max(0, Math.floor(seconds));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
    const two = (n) => String(n).padStart(2, "0");
    return (h ? h + ":" + two(m) : m) + ":" + two(r);
  }

  // Wait until the browser has collected its network addresses (max 3 s),
  // so the whole offer/answer can be sent in one go.
  function waitForIce(pc) {
    if (pc.iceGatheringState === "complete") return Promise.resolve();
    return new Promise((resolve) => {
      const done = () => { clearTimeout(timer); pc.removeEventListener("icegatheringstatechange", check); resolve(); };
      const check = () => { if (pc.iceGatheringState === "complete") done(); };
      const timer = setTimeout(done, 3000);
      pc.addEventListener("icegatheringstatechange", check);
    });
  }

  async function getMedia(kind) {
    try {
      return await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true },
        video: kind === "video" ? { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: "user" } : false,
      });
    } catch (err) {
      if (err && err.name === "NotAllowedError") {
        throw new Error(kind === "video"
          ? "Allow camera and microphone access in your browser to make video calls."
          : "Allow microphone access in your browser to make calls.");
      }
      if (err && err.name === "NotFoundError") {
        throw new Error(kind === "video" ? "No camera or microphone found." : "No microphone found.");
      }
      throw new Error("Could not start your microphone / camera.");
    }
  }

  // ---------- ringtone (made with Web Audio, no sound file needed) ----------
  let ringCtx = null, ringTimer = null;
  function startRing(outgoing) {
    stopRing();
    try {
      ringCtx = new (window.AudioContext || window.webkitAudioContext)();
      const beep = () => {
        if (!ringCtx) return;
        const t = ringCtx.currentTime;
        [0, 0.45].forEach((offset) => {
          const osc = ringCtx.createOscillator();
          const gain = ringCtx.createGain();
          osc.frequency.value = outgoing ? 425 : 660;
          gain.gain.setValueAtTime(0.0001, t + offset);
          gain.gain.exponentialRampToValueAtTime(outgoing ? 0.05 : 0.12, t + offset + 0.03);
          gain.gain.exponentialRampToValueAtTime(0.0001, t + offset + 0.35);
          osc.connect(gain).connect(ringCtx.destination);
          osc.start(t + offset);
          osc.stop(t + offset + 0.4);
        });
      };
      beep();
      ringTimer = setInterval(beep, outgoing ? 3000 : 2000);
    } catch (_) { /* no sound is fine */ }
  }
  function stopRing() {
    clearInterval(ringTimer);
    ringTimer = null;
    if (ringCtx) { ringCtx.close().catch(() => {}); ringCtx = null; }
  }

  // ---------- the call window ----------
  function buildWindow(call) {
    const box = el("div", "call-overlay" + (call.kind === "video" ? " is-video" : ""));
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", (call.kind === "video" ? "Video call with " : "Call with ") + call.other);

    const remoteVideo = document.createElement("video");
    remoteVideo.className = "call-remote-video";
    remoteVideo.autoplay = true;
    remoteVideo.playsInline = true;
    const localVideo = document.createElement("video");
    localVideo.className = "call-local-video";
    localVideo.autoplay = true;
    localVideo.playsInline = true;
    localVideo.muted = true; // never play your own voice back
    const remoteAudio = document.createElement("audio");
    remoteAudio.autoplay = true;

    const info = el("div", "call-info");
    const who = avatar(call.other, "xl");
    const name = el("div", "call-name", nameFromEmail(call.other));
    const address = el("div", "call-address", call.other);
    const status = el("div", "call-status", "");
    info.append(who, name, address, status);

    const controls = el("div", "call-controls");
    box.append(remoteVideo, localVideo, remoteAudio, info, controls);
    document.body.append(box);
    document.body.classList.add("in-call");
    return { box, remoteVideo, localVideo, remoteAudio, status, controls };
  }

  function roundButton(iconName, label, extra) {
    const b = el("button", "call-btn" + (extra ? " " + extra : ""));
    b.type = "button";
    b.setAttribute("aria-label", label);
    b.title = label;
    b.append(icon(iconName));
    const text = el("span", "call-btn-label", label);
    const wrap = el("div", "call-btn-wrap");
    wrap.append(b, text);
    return { wrap, button: b, text };
  }

  function showInCallControls() {
    const ui = current.ui;
    ui.controls.replaceChildren();

    const mute = roundButton("mic", "Mute");
    mute.button.addEventListener("click", () => {
      const track = current.local && current.local.getAudioTracks()[0];
      if (!track) return;
      track.enabled = !track.enabled;
      mute.button.classList.toggle("is-off", !track.enabled);
      mute.button.querySelector("use").setAttribute("href", "/icons.svg#" + (track.enabled ? "mic" : "mic-off"));
      mute.text.textContent = track.enabled ? "Mute" : "Unmute";
    });
    ui.controls.append(mute.wrap);

    if (current.kind === "video") {
      const cam = roundButton("video", "Camera off");
      cam.button.addEventListener("click", () => {
        const track = current.local && current.local.getVideoTracks()[0];
        if (!track) return;
        track.enabled = !track.enabled;
        cam.button.classList.toggle("is-off", !track.enabled);
        cam.button.querySelector("use").setAttribute("href", "/icons.svg#" + (track.enabled ? "video" : "video-off"));
        cam.text.textContent = track.enabled ? "Camera off" : "Camera on";
        ui.localVideo.classList.toggle("hidden", !track.enabled);
      });
      ui.controls.append(cam.wrap);
    }

    const end = roundButton("phone-off", "End", "is-end");
    end.button.addEventListener("click", () => hangUp());
    ui.controls.append(end.wrap);
  }

  function setStatus(text) {
    if (current && current.ui) current.ui.status.textContent = text;
  }

  // ---------- peer connection ----------
  function makePeer(kind) {
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    pc.addEventListener("track", (event) => {
      if (!current) return;
      const stream = event.streams[0] || new MediaStream([event.track]);
      current.ui.remoteAudio.srcObject = stream;
      if (kind === "video") {
        current.ui.remoteVideo.srcObject = stream;
        current.ui.box.classList.add("has-remote-video");
      }
    });
    pc.addEventListener("connectionstatechange", () => {
      if (!current || current.pc !== pc) return;
      if (pc.connectionState === "connected") {
        setStatus(current.startedAt ? formatTimer((Date.now() - current.startedAt) / 1000) : "Connected");
      } else if (pc.connectionState === "failed") {
        hangUp("The connection was lost.");
      }
    });
    return pc;
  }

  function startTimer(startedIso) {
    if (!current || current.timer) return;
    current.startedAt = startedIso ? new Date(startedIso).getTime() : Date.now();
    // Use our own clock if the server's clock is far off
    if (Math.abs(Date.now() - current.startedAt) > 15000) current.startedAt = Date.now();
    current.timer = setInterval(() => {
      if (current && current.pc && ["connected", "completed"].includes(current.pc.connectionState || current.pc.iceConnectionState)) {
        setStatus(formatTimer((Date.now() - current.startedAt) / 1000));
      } else if (current) {
        setStatus("Connecting…");
      }
    }, 500);
  }

  // Watch the call on the server (answered? hung up by the other side?)
  function pollCall() {
    clearTimeout(current && current.pollTimer);
    if (!current || !current.id) return;
    const id = current.id;
    current.pollTimer = setTimeout(async () => {
      if (!current || current.id !== id) return;
      try {
        const { call } = await api("/api/calls/" + id);
        if (!current || current.id !== id) return;
        if (call.status === "active") {
          if (current.role === "caller" && call.answer && !current.pc.remoteDescription) {
            stopRing();
            await current.pc.setRemoteDescription(call.answer);
            showInCallControls();
          }
          startTimer(call.started_at);
        } else if (call.status !== "ringing") {
          const text = call.status === "declined" ? nameFromEmail(call.other) + " declined the call."
            : call.status === "missed" ? "No answer."
            : "Call ended · " + formatTimer(call.duration || 0);
          cleanup(text);
          return;
        }
      } catch (err) {
        if (err.status === 404) { cleanup("Call ended."); return; }
      }
      pollCall();
    }, POLL_MS);
  }

  // ---------- making a call ----------
  async function start(email, kind = "audio") {
    if (current) { toast("You are already in a call."); return; }
    if (!supported()) { toast("Calls need a newer browser (Chrome, Edge, Firefox or Safari).", "error"); return; }

    current = { kind, role: "caller", other: email, id: null };
    current.ui = buildWindow(current);
    setStatus("Starting…");
    const cancel = roundButton("phone-off", "Cancel", "is-end");
    cancel.button.addEventListener("click", () => hangUp());
    current.ui.controls.append(cancel.wrap);

    try {
      const local = await getMedia(kind);
      if (!current) { local.getTracks().forEach((t) => t.stop()); return; }
      current.local = local;
      if (kind === "video") { current.ui.localVideo.srcObject = local; current.ui.box.classList.add("has-local-video"); }
      const pc = makePeer(kind);
      current.pc = pc;
      local.getTracks().forEach((track) => pc.addTrack(track, local));
      await pc.setLocalDescription(await pc.createOffer());
      await waitForIce(pc);
      if (!current) return;
      const { call } = await api("/api/calls", {
        method: "POST",
        body: { to: email, kind, offer: { type: pc.localDescription.type, sdp: pc.localDescription.sdp } },
      });
      if (!current) { api("/api/calls/" + call.id + "/end", { method: "POST", body: {} }).catch(() => {}); return; }
      current.id = call.id;
      setStatus("Ringing…");
      startRing(true);
      pollCall();
    } catch (err) {
      cleanup(err.message || "Could not start the call.", true);
    }
  }

  // ---------- receiving a call ----------
  function showIncoming(call) {
    current = { kind: call.kind, role: "callee", other: call.other, id: call.id, offer: call.offer };
    current.ui = buildWindow(current);
    current.ui.box.classList.add("is-incoming");
    setStatus(call.kind === "video" ? "Incoming video call…" : "Incoming voice call…");
    startRing(false);

    const decline = roundButton("phone-off", "Decline", "is-end");
    decline.button.addEventListener("click", () => {
      ignored.add(call.id);
      hangUp();
    });
    const accept = roundButton(call.kind === "video" ? "video" : "phone", "Accept", "is-accept");
    accept.button.addEventListener("click", () => acceptCall());
    current.ui.controls.append(decline.wrap, accept.wrap);
    pollCall(); // notices if the caller gives up
  }

  async function acceptCall() {
    if (!current || current.role !== "callee") return;
    stopRing();
    ignored.add(current.id);
    current.ui.box.classList.remove("is-incoming");
    setStatus("Connecting…");
    current.ui.controls.replaceChildren();
    try {
      const local = await getMedia(current.kind);
      if (!current) { local.getTracks().forEach((t) => t.stop()); return; }
      current.local = local;
      if (current.kind === "video") { current.ui.localVideo.srcObject = local; current.ui.box.classList.add("has-local-video"); }
      const pc = makePeer(current.kind);
      current.pc = pc;
      await pc.setRemoteDescription(current.offer);
      local.getTracks().forEach((track) => pc.addTrack(track, local));
      await pc.setLocalDescription(await pc.createAnswer());
      await waitForIce(pc);
      if (!current) return;
      const { call } = await api("/api/calls/" + current.id + "/answer", {
        method: "POST",
        body: { answer: { type: pc.localDescription.type, sdp: pc.localDescription.sdp } },
      });
      showInCallControls();
      startTimer(call.started_at);
    } catch (err) {
      hangUp(err.message || "Could not answer the call.");
    }
  }

  // ---------- ending ----------
  async function hangUp(message) {
    if (!current) return;
    const id = current.id;
    cleanup(message || "Call ended.");
    if (id) {
      try { await api("/api/calls/" + id + "/end", { method: "POST", body: {} }); } catch (_) { /* ignore */ }
    }
  }

  function cleanup(message, isError) {
    stopRing();
    if (!current) return;
    clearTimeout(current.pollTimer);
    clearInterval(current.timer);
    if (current.local) current.local.getTracks().forEach((t) => t.stop());
    if (current.pc) { try { current.pc.close(); } catch (_) { /* ignore */ } }
    if (current.id) ignored.add(current.id);
    const box = current.ui && current.ui.box;
    current = null;
    document.body.classList.remove("in-call");
    if (box) {
      box.classList.add("leaving");
      setTimeout(() => box.remove(), 200);
    }
    if (message) toast(message, isError ? "error" : "info");
  }

  // ---------- online heartbeat ----------
  async function heartbeat() {
    try {
      const data = await api("/api/calls/heartbeat", {
        method: "POST",
        body: { call_id: current && current.id && current.pc ? current.id : null },
      });
      const incoming = data && data.incoming;
      if (incoming && !current && !ignored.has(incoming.id)) showIncoming(incoming);
    } catch (err) {
      if (err.status === 401) { stopHeartbeat(); return; }
    }
  }
  function startHeartbeat() {
    if (heartbeatTimer) return;
    heartbeat();
    heartbeatTimer = setInterval(heartbeat, HEARTBEAT_MS);
  }
  function stopHeartbeat() {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }

  // Leaving the page during a call: tell the server so the other side stops too
  window.addEventListener("pagehide", () => {
    if (current && current.id) {
      const csrf = getCookie("csrf_token") || "";
      fetch("/api/calls/" + current.id + "/end", {
        method: "POST", keepalive: true, credentials: "same-origin",
        headers: { "Content-Type": "application/json", "X-CSRFToken": csrf }, body: "{}",
      }).catch(() => {});
    }
  });

  // ---------- presence (for the dial buttons) ----------
  async function presence(email) {
    try {
      return await api("/api/calls/presence?email=" + encodeURIComponent(email));
    } catch (_) {
      return { can_call: false, online: false, reason: "Can't check right now." };
    }
  }

  // Start once the user is known to be logged in
  if (typeof Shell !== "undefined" && Shell.userReady) {
    Shell.userReady.then(startHeartbeat).catch(() => {});
  } else {
    startHeartbeat();
  }

  return { start, presence, supported, get busy() { return !!current; } };
})();

"""calls.py — voice and video calls between MailSpace addresses (VoIP over the internet).

How it works
------------
1. Online status: every open MailSpace page / app sends a "heartbeat" every
   few seconds (POST /api/calls/heartbeat). A user whose last heartbeat is
   newer than ONLINE_SECONDS is "online" -> the dial button is enabled.
2. Calling uses WebRTC (built into browsers, and flutter_webrtc in the app).
   The voice goes directly between the two devices. This server only passes
   the "connection details" (an SDP offer and answer) between them:
       caller  --offer-->  server  --(heartbeat)-->  person called
       caller  <--answer-- server  <--answer------  person called
3. When the call ends (or is missed / declined) both people get an email
   with when it started and how long it lasted.

Collections
-----------
presence  {user_id, last_seen}                       one per user
calls     {caller_id, callee_id, caller_email, callee_email, status,
           offer, answer, created_at, started_at, ended_at, duration,
           caller_seen, callee_seen, log_sent}
           status: ringing -> active -> ended
                   ringing -> missed | declined
"""
from datetime import timedelta

from flask import Blueprint, current_app, g, jsonify, request

from config import Config
from database import addresses, calls, domains, mailboxes, messages, presence, users
from security import is_expired, login_required, now_utc, parse_object_id, to_iso

calls_bp = Blueprint("calls", __name__, url_prefix="/api/calls")

ONLINE_SECONDS = 15      # no heartbeat for this long -> offline (dial button grey)
RING_SECONDS = 45        # nobody answers -> missed call
LOST_SECONDS = 25        # in a call but a device stopped answering -> call ended
MAX_SDP = 20_000         # size limit for the connection details

FINISHED = {"ended", "missed", "declined"}


def error(message, status=400):
    return jsonify({"error": message}), status


# ---------- helpers ----------
def find_user_by_address(email):
    """The MailSpace user who owns this address (main or custom domain), or None."""
    email = (email or "").strip().lower()
    if "@" not in email:
        return None
    domain = email.rsplit("@", 1)[1]
    if domain == Config.MAIL_DOMAIN:
        user = users.find_one({"email": email, "status": "active"})
    elif domains.find_one({"name": domain, "status": "verified"}):
        address = addresses.find_one({"email": email})
        user = users.find_one({"_id": address["user_id"], "status": "active"}) if address else None
    else:
        return None  # Gmail, Outlook... cannot receive MailSpace calls
    if user is None or is_expired(user):
        return None
    return user


def is_online(user_id):
    row = presence.find_one({"user_id": user_id})
    return bool(row) and row["last_seen"] > now_utc() - timedelta(seconds=ONLINE_SECONDS)


def open_call_for(user_id):
    """A call this user is already in (ringing or active), or None."""
    for call in calls.find({"status": {"$in": ["ringing", "active"]},
                            "$or": [{"caller_id": user_id}, {"callee_id": user_id}]}):
        call = expire_if_stale(call)
        if call["status"] not in FINISHED:
            return call
    return None


def my_role(call, user_id):
    if call["caller_id"] == user_id:
        return "caller"
    if call["callee_id"] == user_id:
        return "callee"
    return None


def call_json(call, user_id):
    role = my_role(call, user_id)
    other = call["callee_email"] if role == "caller" else call["caller_email"]
    data = {
        "id": str(call["_id"]),
        "status": call["status"],
        "kind": call.get("kind", "audio"),
        "role": role,
        "other": other,
        "caller": call["caller_email"],
        "callee": call["callee_email"],
        "created_at": to_iso(call.get("created_at")),
        "started_at": to_iso(call.get("started_at")),
        "ended_at": to_iso(call.get("ended_at")),
        "duration": call.get("duration"),
    }
    if role == "callee" and call["status"] == "ringing":
        data["offer"] = call["offer"]
    if role == "caller" and call.get("answer"):
        data["answer"] = call["answer"]
    return data


def format_duration(seconds):
    seconds = int(seconds or 0)
    h, rest = divmod(seconds, 3600)
    m, s = divmod(rest, 60)
    if h:
        return f"{h} hr {m} min {s} sec"
    if m:
        return f"{m} min {s} sec"
    return f"{s} sec"


def local_time(value):
    """Times in the email are shown in Pakistan time (change CALL_TIMEZONE in .env)."""
    try:
        from zoneinfo import ZoneInfo
        zone_name = current_app.config.get("CALL_TIMEZONE") or "Asia/Karachi"
        value = value.astimezone(ZoneInfo(zone_name))
        label = zone_name
    except Exception:
        label = "UTC"
    return value.strftime("%d %b %Y, %I:%M:%S %p") + f" ({label})"


def finish(call, status, now=None):
    """Close the call once (ended / missed / declined) and email both people."""
    now = now or now_utc()
    fields = {"status": status, "ended_at": now}
    if status == "ended" and call.get("started_at"):
        fields["duration"] = int((now - call["started_at"]).total_seconds())
    # Only the first request that closes the call wins (no double emails)
    result = calls.update_one({"_id": call["_id"], "status": call["status"]}, {"$set": fields})
    if result.modified_count != 1:
        return calls.find_one({"_id": call["_id"]})
    call = {**call, **fields}
    try:
        send_call_log(call)
    except Exception:
        current_app.logger.exception("Could not send the call email")
    return call


def expire_if_stale(call):
    """Ringing too long -> missed. A device disappeared during the call -> ended."""
    now = now_utc()
    if call["status"] == "ringing" and call["created_at"] < now - timedelta(seconds=RING_SECONDS):
        return finish(call, "missed", now)
    if call["status"] == "active":
        lost = now - timedelta(seconds=LOST_SECONDS)
        if call.get("caller_seen", now) < lost or call.get("callee_seen", now) < lost:
            last = min(call.get("caller_seen", now), call.get("callee_seen", now))
            return finish(call, "ended", max(last, call.get("started_at") or last))
    return call


def send_call_log(call):
    """Put a 'call details' email in both people's inbox."""
    caller, callee = call["caller_email"], call["callee_email"]
    status = call["status"]
    kind = "Video call" if call.get("kind") == "video" else "Voice call"
    if status == "ended":
        subject = f"{kind} with {{other}} — {format_duration(call.get('duration'))}"
        result = "Completed"
    elif status == "declined":
        subject = f"Declined {kind.lower()} — {{other}}"
        result = "Declined"
    else:
        subject = f"Missed {kind.lower()} — {{other}}"
        result = "Missed (not answered)"

    lines = [
        f"MailSpace {kind.lower()}",
        "",
        f"From (caller):  {caller}",
        f"To:             {callee}",
        f"Result:         {result}",
        f"Dialled at:     {local_time(call['created_at'])}",
    ]
    if call.get("started_at"):
        lines.append(f"Started at:     {local_time(call['started_at'])}")
    if call.get("ended_at"):
        lines.append(f"Ended at:       {local_time(call['ended_at'])}")
    if status == "ended":
        lines.append(f"Duration:       {format_duration(call.get('duration'))}")
    lines += ["", "This email was created automatically by MailSpace."]
    body = "\n".join(lines)

    system_from = f"calls@{Config.MAIL_DOMAIN}"
    now = now_utc()
    for user_id, other in ((call["caller_id"], callee), (call["callee_id"], caller)):
        user_subject = subject.format(other=other)
        message_id = messages.insert_one({
            "sender_id": None, "sender_email": system_from,
            "to_emails": [caller, callee], "recipient_ids": [user_id],
            "subject": user_subject, "body": body, "attachments": [],
            "is_draft": False, "created_at": now,
            "call_id": call["_id"], "flagged": False, "flag_words": [],
        }).inserted_id
        mailboxes.insert_one({
            "user_id": user_id, "message_id": message_id, "folder": "inbox",
            "is_read": False, "is_starred": False,
            "from_email": system_from, "to_emails": [caller, callee],
            "subject": user_subject, "snippet": " ".join(body.split())[:120],
            "search_text": (system_from + " " + caller + " " + callee + " " + user_subject + " call").lower(),
            "has_attachments": False, "created_at": now,
        })


def get_my_call(call_id):
    call = calls.find_one({"_id": parse_object_id(call_id)}) if parse_object_id(call_id) else None
    if call is None or my_role(call, g.user["_id"]) is None:
        return None
    return call


def clean_sdp(data, key):
    value = (data or {}).get(key)
    if not isinstance(value, dict):
        return None
    sdp, kind = value.get("sdp"), value.get("type")
    if not isinstance(sdp, str) or kind not in ("offer", "answer") or len(sdp) > MAX_SDP:
        return None
    return {"sdp": sdp, "type": kind}


# ---------- routes ----------
@calls_bp.post("/heartbeat")
@login_required
def heartbeat():
    """'I'm online.' Also tells the page if someone is calling, and keeps an
    active call alive (call_id)."""
    me = g.user["_id"]
    now = now_utc()
    presence.update_one({"user_id": me}, {"$set": {"last_seen": now}}, upsert=True)

    data = request.get_json(silent=True) or {}
    call_id = parse_object_id(data.get("call_id"))
    if call_id:
        call = calls.find_one({"_id": call_id})
        if call and my_role(call, me):
            calls.update_one({"_id": call_id}, {"$set": {my_role(call, me) + "_seen": now}})

    incoming = None
    for call in calls.find({"callee_id": me, "status": "ringing"}):
        call = expire_if_stale(call)
        if call["status"] == "ringing":
            incoming = call_json(call, me)
            break
    return jsonify({"ok": True, "incoming": incoming})


@calls_bp.get("/presence")
@login_required
def check_presence():
    """Can I call this address right now? (decides if the dial button is enabled)"""
    email = request.args.get("email", "").strip().lower()
    user = find_user_by_address(email)
    if user is None:
        return jsonify({"email": email, "can_call": False, "online": False,
                        "reason": "Calls work only between MailSpace addresses."})
    if user["_id"] == g.user["_id"]:
        return jsonify({"email": email, "can_call": False, "online": True,
                        "reason": "This is your own address."})
    online = is_online(user["_id"])
    return jsonify({"email": email, "can_call": online, "online": online,
                    "reason": None if online else f"{email} is offline."})


@calls_bp.post("")
@login_required
def start_call():
    me = g.user
    data = request.get_json(silent=True) or {}
    to_email = str(data.get("to", "")).strip().lower()
    kind = "video" if data.get("kind") == "video" else "audio"
    offer = clean_sdp(data, "offer")
    if offer is None or offer["type"] != "offer":
        return error("Missing call details. Please try again.")

    callee = find_user_by_address(to_email)
    if callee is None:
        return error("Calls work only between MailSpace addresses.")
    if callee["_id"] == me["_id"]:
        return error("You can't call yourself.")
    if not is_online(callee["_id"]):
        return error(f"{to_email} is offline right now.", 409)
    if open_call_for(me["_id"]):
        return error("You are already in a call.", 409)
    if open_call_for(callee["_id"]):
        return error(f"{to_email} is busy on another call.", 409)

    now = now_utc()
    call_id = calls.insert_one({
        "caller_id": me["_id"], "callee_id": callee["_id"],
        "caller_email": me["email"], "callee_email": to_email,
        "kind": kind, "status": "ringing", "offer": offer, "answer": None,
        "created_at": now, "started_at": None, "ended_at": None, "duration": None,
        "caller_seen": now, "callee_seen": now, "log_sent": False,
    }).inserted_id
    return jsonify({"call": call_json(calls.find_one({"_id": call_id}), me["_id"])}), 201


@calls_bp.get("/<call_id>")
@login_required
def call_status(call_id):
    call = get_my_call(call_id)
    if call is None:
        return error("Call not found.", 404)
    call = expire_if_stale(call)
    return jsonify({"call": call_json(call, g.user["_id"])})


@calls_bp.post("/<call_id>/answer")
@login_required
def answer_call(call_id):
    call = get_my_call(call_id)
    if call is None or my_role(call, g.user["_id"]) != "callee":
        return error("Call not found.", 404)
    call = expire_if_stale(call)
    if call["status"] != "ringing":
        return error("This call has already ended.", 409)
    answer = clean_sdp(request.get_json(silent=True), "answer")
    if answer is None or answer["type"] != "answer":
        return error("Missing call details. Please try again.")
    now = now_utc()
    result = calls.update_one(
        {"_id": call["_id"], "status": "ringing"},
        {"$set": {"status": "active", "answer": answer, "started_at": now,
                  "caller_seen": now, "callee_seen": now}},
    )
    if result.modified_count != 1:
        return error("This call has already ended.", 409)
    return jsonify({"call": call_json(calls.find_one({"_id": call["_id"]}), g.user["_id"])})


@calls_bp.post("/<call_id>/end")
@login_required
def end_call(call_id):
    """Hang up. Ringing + caller hangs up -> missed; ringing + callee -> declined."""
    call = get_my_call(call_id)
    if call is None:
        return error("Call not found.", 404)
    call = expire_if_stale(call)
    if call["status"] == "ringing":
        status = "declined" if my_role(call, g.user["_id"]) == "callee" else "missed"
        call = finish(call, status)
    elif call["status"] == "active":
        call = finish(call, "ended")
    return jsonify({"call": call_json(call, g.user["_id"])})

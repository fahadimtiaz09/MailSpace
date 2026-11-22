"""routes/safety.py — block senders and report emails (Gmail-style).

Block:  mail from a blocked address goes straight to Spam (no notification),
        and that person can't call you (you look offline to them).
Report: sends an email to the admins' review list (Admin → Reports), moves it
        to Spam, and can block the sender too.
"""
import re

from flask import Blueprint, g, jsonify, request
from pymongo import DESCENDING

from database import mailboxes, messages, reports, users
from push import notify
from security import admin_required, login_required, now_utc, parse_object_id, rate_limited, to_iso

safety_bp = Blueprint("safety", __name__, url_prefix="/api")

EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

MAX_BLOCKED = 1000
REASONS = {
    "spam": "Spam",
    "scam": "Scam or phishing",
    "harassment": "Harassment or threats",
    "other": "Something else",
}
PAGE_SIZE = 20


def error(message, status=400):
    return jsonify({"error": message}), status


def init_safety_indexes():
    reports.create_index([("status", 1), ("created_at", DESCENDING)])
    reports.create_index([("reporter_id", 1), ("message_id", 1)])


def blocked_list(user):
    return list(user.get("blocked_senders") or [])


def my_addresses(user):
    return {user["email"], *(user.get("aliases") or []), *(user.get("old_emails") or [])}


def block(user, email):
    """Add an address to this user's block list. Returns an error text or None."""
    email = str(email or "").strip().lower()
    if not EMAIL_PATTERN.fullmatch(email):
        return "Enter a valid email address."
    if email in my_addresses(user):
        return "You can't block your own address."
    if email in blocked_list(user):
        return None
    if len(blocked_list(user)) >= MAX_BLOCKED:
        return f"You can block at most {MAX_BLOCKED} addresses."
    users.update_one({"_id": user["_id"]}, {"$addToSet": {"blocked_senders": email}})
    return None


# ---------- Blocked addresses ----------
@safety_bp.get("/blocked")
@login_required
def list_blocked():
    return jsonify({"blocked": sorted(blocked_list(g.user))})


@safety_bp.post("/blocked")
@login_required
def add_blocked():
    email = str((request.get_json(silent=True) or {}).get("email", "")).strip().lower()
    problem = block(g.user, email)
    if problem:
        return error(problem)
    # Mail already in the inbox from this address moves to Spam too
    mailboxes.update_many({"user_id": g.user["_id"], "folder": "inbox", "from_email": email},
                          {"$set": {"folder": "spam"}})
    return jsonify({"ok": True, "email": email})


@safety_bp.post("/blocked/remove")
@login_required
def remove_blocked():
    email = str((request.get_json(silent=True) or {}).get("email", "")).strip().lower()
    users.update_one({"_id": g.user["_id"]}, {"$pull": {"blocked_senders": email}})
    return jsonify({"ok": True, "email": email})


# ---------- Report an email ----------
@safety_bp.post("/messages/<entry_id>/report")
@login_required
def report_message(entry_id):
    me = g.user
    if rate_limited("report:" + str(me["_id"]), 20, 3600):
        return error("Too many reports. Please try again later.", 429)
    entry = mailboxes.find_one({"_id": parse_object_id(entry_id), "user_id": me["_id"]}) \
        if parse_object_id(entry_id) else None
    if entry is None:
        return error("Message not found.", 404)
    message = messages.find_one({"_id": entry["message_id"]})
    if message is None:
        return error("Message not found.", 404)
    if message.get("sender_id") == me["_id"] or entry["folder"] in ("sent", "drafts"):
        return error("You can't report your own email.")

    data = request.get_json(silent=True) or {}
    reason = str(data.get("reason", ""))
    if reason not in REASONS:
        return error("Choose why you're reporting this email.")
    note = str(data.get("note", "")).strip()[:500]
    sender = (message.get("sender_email") or entry.get("from_email") or "").lower()

    now = now_utc()
    reports.update_one(
        {"reporter_id": me["_id"], "message_id": message["_id"]},
        {"$set": {"reason": reason, "note": note, "status": "open", "updated_at": now,
                  "reporter_email": me["email"], "sender_email": sender,
                  "subject": message.get("subject", ""), "entry_id": entry["_id"]},
         "$setOnInsert": {"created_at": now}},
        upsert=True)
    messages.update_one({"_id": message["_id"]}, {"$set": {"reported": True}})
    if entry["folder"] == "inbox":
        mailboxes.update_one({"_id": entry["_id"]}, {"$set": {"folder": "spam"}})

    blocked = False
    if data.get("block") is True and sender:
        blocked = block(me, sender) is None

    admins = [a["_id"] for a in users.find({"role": "admin", "status": "active"}, {"_id": 1})]
    notify(admins, "New report: " + REASONS[reason], (message.get("subject") or "(no subject)")[:120],
           url="/admin.html", type_="report", tag="report")
    return jsonify({"ok": True, "blocked": blocked})


# ---------- Admin: review reports ----------
@safety_bp.get("/admin/reports")
@admin_required
def admin_reports():
    try:
        page = max(1, int(request.args.get("page", 1)))
    except ValueError:
        page = 1
    status = request.args.get("status", "open")
    query = {"status": status} if status in ("open", "resolved", "dismissed") else {}
    total = reports.count_documents(query)
    rows = []
    for r in (reports.find(query).sort("created_at", DESCENDING)
              .skip((page - 1) * PAGE_SIZE).limit(PAGE_SIZE)):
        rows.append({
            "id": str(r["_id"]),
            "message_id": str(r["message_id"]),
            "reason": r["reason"], "reason_label": REASONS.get(r["reason"], r["reason"]),
            "note": r.get("note", ""),
            "reporter": r.get("reporter_email") or "(deleted account)",
            "from": r.get("sender_email", ""), "subject": r.get("subject", ""),
            "status": r["status"], "created_at": to_iso(r.get("created_at")),
            "count": reports.count_documents({"message_id": r["message_id"]}),
        })
    return jsonify({"reports": rows, "page": page, "total": total,
                    "total_pages": max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE),
                    "open": reports.count_documents({"status": "open"})})


@safety_bp.post("/admin/reports/<report_id>")
@admin_required
def admin_update_report(report_id):
    status = str((request.get_json(silent=True) or {}).get("status", ""))
    if status not in ("open", "resolved", "dismissed"):
        return error("Unknown status.")
    oid = parse_object_id(report_id)
    result = reports.update_one({"_id": oid}, {"$set": {"status": status, "handled_by": g.user["email"],
                                                         "handled_at": now_utc()}}) if oid else None
    if not result or not result.matched_count:
        return error("Report not found.", 404)
    # Once nobody has a copy and no report is open, the email can finally go
    report = reports.find_one({"_id": oid})
    message_id = report["message_id"]
    if status != "open" and not reports.count_documents({"message_id": message_id, "status": "open"}, limit=1) \
            and not mailboxes.count_documents({"message_id": message_id}, limit=1):
        message = messages.find_one_and_delete({"_id": message_id})
        if message:
            from routes.messages import delete_files
            delete_files(message.get("attachments", []))
    return jsonify({"ok": True})

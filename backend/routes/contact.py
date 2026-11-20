"""routes/contact.py — the "Contact us" form on the home page.

A message from the form lands in the inbox of EVERY admin (the team address
CONTACT_EMAIL, default support@<MAIL_DOMAIN>).
It appears "from" the visitor, so pressing Reply writes back to them.
"""
from flask import Blueprint, jsonify, request

from config import Config
from database import mailboxes, messages
from push import notify_new_mail
from routes.auth import EMAIL_PATTERN
from routes.messages import make_search_text, make_snippet
from security import contact_address, now_utc, rate_limited, team_members

contact_bp = Blueprint("contact", __name__, url_prefix="/api")


def error(message, status=400):
    return jsonify({"error": message}), status


@contact_bp.get("/contact")
def contact_info():
    return jsonify({"email": contact_address()})


@contact_bp.post("/contact")
def contact():
    data = request.get_json(silent=True) or {}
    if str(data.get("website", "")).strip():          # hidden field only robots fill in
        return jsonify({"ok": True})
    if rate_limited("contact:" + (request.remote_addr or "?"), 5, 3600):
        return error("Too many messages from this computer. Please try again in an hour.", 429)

    name = " ".join(str(data.get("name", "")).split())[:80]
    email = str(data.get("email", "")).strip().lower()[:254]
    topic = " ".join(str(data.get("subject", "")).split())[:120]
    text = str(data.get("message", "")).strip()[:5000]
    if not name:
        return error("Please enter your name.")
    if not EMAIL_PATTERN.fullmatch(email):
        return error("Please enter a valid email address, so we can reply.")
    if len(text) < 10:
        return error("Please write a little more (at least 10 characters).")

    team = team_members(contact_address())
    if not team:
        return error("Sorry, messages can't be received right now. Please email us instead.", 503)

    now = now_utc()
    to = contact_address()
    subject = "Contact form: " + (topic or name)
    body = f"{text}\n\n—\nSent from the Contact form on {Config.MAIL_DOMAIN}\nName: {name}\nEmail: {email}"
    message_id = messages.insert_one({
        "sender_id": None, "sender_email": email,
        "to_emails": [to], "recipient_ids": [u["_id"] for u in team],
        "subject": subject, "body": body, "attachments": [],
        "is_draft": False, "created_at": now, "flagged": False, "flag_words": [],
        "via": "contact_form",
    }).inserted_id
    entries = [{
        "user_id": admin["_id"], "message_id": message_id, "folder": "inbox",
        "is_read": False, "is_starred": False,
        "from_email": email, "from_name": name, "to_emails": [to],
        "subject": subject, "snippet": make_snippet(text),
        "search_text": make_search_text(email, [to], subject, body + " " + name),
        "has_attachments": False, "created_at": now,
    } for admin in team]
    for entry, entry_id in zip(entries, mailboxes.insert_many(entries).inserted_ids):
        notify_new_mail(entry["user_id"], entry_id, email, name, subject)
    return jsonify({"ok": True})

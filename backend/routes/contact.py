"""routes/contact.py — the "Contact us" form on the home page.

A message from the form lands in the inbox of the account that owns CONTACT_EMAIL
(default support@<MAIL_DOMAIN>, usually an alias — see rename_account.py --alias).
It appears "from" the visitor, so pressing Reply writes back to them.
"""
from flask import Blueprint, jsonify, request

from config import Config
from database import mailboxes, messages
from push import notify_new_mail
from routes.auth import EMAIL_PATTERN
from routes.messages import make_search_text, make_snippet
from security import active_user_by_email, now_utc, rate_limited

contact_bp = Blueprint("contact", __name__, url_prefix="/api")


def contact_address():
    return Config.CONTACT_EMAIL or f"support@{Config.MAIL_DOMAIN}"


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

    owner = active_user_by_email(contact_address())
    if owner is None:
        return error("Sorry, messages can't be received right now. Please email us instead.", 503)

    now = now_utc()
    to = contact_address()
    subject = "Contact form: " + (topic or name)
    body = f"{text}\n\n—\nSent from the Contact form on {Config.MAIL_DOMAIN}\nName: {name}\nEmail: {email}"
    message_id = messages.insert_one({
        "sender_id": None, "sender_email": email,
        "to_emails": [to], "recipient_ids": [owner["_id"]],
        "subject": subject, "body": body, "attachments": [],
        "is_draft": False, "created_at": now, "flagged": False, "flag_words": [],
        "via": "contact_form",
    }).inserted_id
    entry_id = mailboxes.insert_one({
        "user_id": owner["_id"], "message_id": message_id, "folder": "inbox",
        "is_read": False, "is_starred": False,
        "from_email": email, "from_name": name, "to_emails": [to],
        "subject": subject, "snippet": make_snippet(text),
        "search_text": make_search_text(email, [to], subject, body + " " + name),
        "has_attachments": False, "created_at": now,
    }).inserted_id
    notify_new_mail(owner["_id"], entry_id, email, name, subject)
    return jsonify({"ok": True})

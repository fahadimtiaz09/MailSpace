"""inbound.py — receive email from the outside world (Gmail, etc.) through Resend.
Resend sends an 'email.received' webhook; we fetch the body and deliver it."""
import re

from flask import Blueprint, jsonify, request

from config import Config
from database import addresses, domains, mailboxes, messages, users
from email_service import fetch_received_email
from safety import check_message
from security import is_expired, now_utc

inbound_bp = Blueprint("inbound", __name__, url_prefix="/api/inbound")


def make_snippet(body):
    return " ".join((body or "").split())[:160]


def find_user_for(address):
    """Which MailSpace user owns this address (main address or custom domain), or None."""
    address = address.strip().lower()
    domain = address.rsplit("@", 1)[-1]
    if domain == Config.MAIL_DOMAIN:
        return users.find_one({"email": address, "status": "active"})
    if domains.find_one({"name": domain, "status": "verified"}):
        a = addresses.find_one({"email": address})
        if a:
            return users.find_one({"_id": a["user_id"], "status": "active"})
    return None


@inbound_bp.post("/<secret>")
def receive(secret):
    # Only Resend knows this secret URL
    if not Config.INBOUND_SECRET or secret != Config.INBOUND_SECRET:
        return jsonify({"error": "not found"}), 404

    event = request.get_json(silent=True) or {}
    if event.get("type") != "email.received":
        return jsonify({"ok": True})  # ignore anything else

    data = event.get("data", {})
    email_id = data.get("email_id")
    if not email_id:
        return jsonify({"ok": True})

    full = fetch_received_email(email_id) or {}
    from_email = (full.get("from") or data.get("from") or "").strip().lower()
    to_list = [str(t).strip().lower() for t in (full.get("to") or data.get("to") or [])]
    subject = (full.get("subject") or data.get("subject") or "")[:200]

    body = full.get("text") or ""
    if not body and full.get("html"):
        body = re.sub(r"<[^>]+>", " ", full["html"])  # strip HTML tags, keep the words
    body = body.strip()[:20000]

    # Find the MailSpace recipients (there may be several), without duplicates
    recipients = {}
    for addr in to_list:
        u = find_user_for(addr)
        if u and not is_expired(u):
            recipients[u["_id"]] = u
    if not recipients:
        return jsonify({"ok": True})  # not addressed to anyone here

    now = now_utc()
    flag_words = check_message(subject, body)
    message_id = messages.insert_one({
        "sender_id": None, "sender_email": from_email,
        "to_emails": to_list, "recipient_ids": list(recipients.keys()),
        "subject": subject, "body": body, "attachments": [],
        "is_draft": False, "created_at": now,
        "inbound": True, "flagged": bool(flag_words), "flag_words": flag_words,
    }).inserted_id

    shared = {
        "message_id": message_id, "from_email": from_email, "to_emails": to_list,
        "subject": subject, "snippet": make_snippet(body),
        "search_text": (from_email + " " + " ".join(to_list) + " " + subject + " " + body).lower()[:5000],
        "has_attachments": False, "is_starred": False, "created_at": now,
    }
    mailboxes.insert_many([
        {**shared, "user_id": uid, "folder": "inbox", "is_read": False} for uid in recipients
    ])
    return jsonify({"ok": True})
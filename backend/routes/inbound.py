"""inbound.py — receive email from the outside world (Gmail, etc.) through Resend.
Resend sends an 'email.received' webhook; we fetch the body and attachments and deliver it."""
import base64
import re
import uuid

from flask import Blueprint, jsonify, request
from werkzeug.utils import secure_filename

from config import Config
from database import addresses, attachment_files, domains, mailboxes, messages, users
from email_service import download_bytes, fetch_received_attachments, fetch_received_email
from html_safety import clean_email_html
from safety import check_message
from security import is_expired, now_utc

inbound_bp = Blueprint("inbound", __name__, url_prefix="/api/inbound")

MAX_INBOUND_FILES = 5
MAX_INLINE_IMAGE = 1_500_000      # one header/footer image (bytes)
MAX_INLINE_TOTAL = 4_000_000      # all inline images in one email
INLINE_TYPES = {"image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp"}


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


def store_inbound_attachments(email_id, html=""):
    """Download each attachment from Resend.
    - Inline images used by the email's design (Gmail logos / header / footer,
      written in the HTML as src="cid:...") become data: URIs → inline_map.
    - Everything else is stored in MongoDB (GridFS) as a normal attachment.
    Returns (saved_attachments, inline_map)."""
    saved, inline_map, inline_total = [], {}, 0
    html_low = (html or "").lower()
    for a in fetch_received_attachments(email_id)[:MAX_INBOUND_FILES + 10]:
        url = a.get("download_url")
        raw_name = a.get("filename") or "attachment"
        if not url:
            continue
        ctype = (a.get("content_type") or "").split(";")[0].strip().lower()
        cid = (a.get("content_id") or "").strip().strip("<>")
        used_in_html = bool(cid) and ("cid:" + cid.lower()) in html_low

        if used_in_html and ctype in INLINE_TYPES:
            data = download_bytes(url, MAX_INLINE_IMAGE)
            if data and len(data) <= MAX_INLINE_IMAGE and inline_total + len(data) <= MAX_INLINE_TOTAL:
                inline_total += len(data)
                inline_map[cid] = f"data:{ctype};base64," + base64.b64encode(data).decode()
                continue  # part of the design, not a file to download
            # too big → fall through and keep it as a normal attachment

        if len(saved) >= MAX_INBOUND_FILES:
            continue
        data = download_bytes(url, Config.MAX_FILE_SIZE)
        if data is None or len(data) > Config.MAX_FILE_SIZE:
            continue  # skip files that fail or are too big (over 10 MB)
        display = secure_filename(raw_name) or "attachment"
        ext = display.rsplit(".", 1)[1].lower() if "." in display else ""
        file_id = attachment_files.put(data, filename=display, content_type=a.get("content_type"))
        saved.append({"id": uuid.uuid4().hex, "file_id": file_id,
                      "filename": display, "size": len(data), "ext": ext})
    return saved, inline_map


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

    raw_html = full.get("html") or ""
    body = full.get("text") or ""
    if not body and raw_html:
        no_css = re.sub(r"(?is)<(style|script|head)[^>]*>.*?</\1>", " ", raw_html)
        body = re.sub(r"<[^>]+>", " ", no_css)  # strip HTML tags, keep the words
    body = body.strip()[:20000]

    # Find the MailSpace recipients, without duplicates
    recipients = {}
    for addr in to_list:
        u = find_user_for(addr)
        if u and not is_expired(u):
            recipients[u["_id"]] = u
    if not recipients:
        return jsonify({"ok": True})  # not addressed to anyone here

    attachments, inline_map = store_inbound_attachments(email_id, raw_html)
    body_html = clean_email_html(raw_html, inline_map) or None  # the email's design (safe)

    now = now_utc()
    flag_words = check_message(subject, body)
    message_id = messages.insert_one({
        "sender_id": None, "sender_email": from_email,
        "to_emails": to_list, "recipient_ids": list(recipients.keys()),
        "subject": subject, "body": body, "body_html": body_html,
        "attachments": attachments,
        "is_draft": False, "created_at": now,
        "inbound": True, "flagged": bool(flag_words), "flag_words": flag_words,
    }).inserted_id

    shared = {
        "message_id": message_id, "from_email": from_email, "to_emails": to_list,
        "subject": subject, "snippet": make_snippet(body),
        "search_text": (from_email + " " + " ".join(to_list) + " " + subject + " " + body).lower()[:5000],
        "has_attachments": bool(attachments), "is_starred": False, "created_at": now,
    }
    mailboxes.insert_many([
        {**shared, "user_id": uid, "folder": "inbox", "is_read": False} for uid in recipients
    ])
    return jsonify({"ok": True})
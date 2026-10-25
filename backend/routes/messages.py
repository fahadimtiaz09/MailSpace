"""messages.py — inbox, sending, drafts, folders, search and attachments."""
import re
import uuid

from flask import Blueprint, current_app, g, jsonify, request, send_from_directory
from pymongo import DESCENDING
from werkzeug.utils import secure_filename

from config import Config
from database import mailboxes, messages, users
from security import is_expired, login_required, now_utc, parse_object_id, to_iso

messages_bp = Blueprint("messages", __name__, url_prefix="/api")

FOLDERS = {"inbox", "sent", "drafts", "starred", "spam", "trash", "all"}
PAGE_SIZE = 20
MAX_RECIPIENTS = 20
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")

# First bytes of real files, so a virus renamed to "photo.jpg" is rejected
FILE_SIGNATURES = {
    "jpg": [b"\xff\xd8\xff"],
    "jpeg": [b"\xff\xd8\xff"],
    "png": [b"\x89PNG\r\n\x1a\n"],
    "gif": [b"GIF87a", b"GIF89a"],
    "pdf": [b"%PDF"],
    "doc": [b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"],
    "docx": [b"PK\x03\x04"],
}
MIME_TYPES = {
    "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif",
    "pdf": "application/pdf", "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "txt": "text/plain",
}


# ---------- Helpers ----------
def error(message, status=400):
    return jsonify({"error": message}), status


def make_snippet(body):
    return " ".join(body.split())[:120]


def make_search_text(from_email, to_emails, subject, body):
    return " ".join([from_email, " ".join(to_emails), subject, body]).lower()[:5000]


def parse_recipients(value):
    parts = [str(v) for v in value] if isinstance(value, list) else re.split(r"[,;\s]+", str(value))
    cleaned = []
    for part in parts:
        address = part.strip().lower()
        if address and address not in cleaned:
            cleaned.append(address)
    return cleaned


def find_entry(entry_id):
    """Find a mailbox entry that belongs to the logged-in user (or None)."""
    oid = parse_object_id(entry_id)
    if oid is None:
        return None
    return mailboxes.find_one({"_id": oid, "user_id": g.user["_id"]})


def list_item(entry):
    return {
        "id": str(entry["_id"]),
        "folder": entry["folder"],
        "from": entry["from_email"],
        "to": entry["to_emails"],
        "subject": entry["subject"],
        "snippet": entry["snippet"],
        "created_at": to_iso(entry["created_at"]),
        "is_read": entry["is_read"],
        "is_starred": entry["is_starred"],
        "has_attachments": entry["has_attachments"],
    }


def delete_files(attachments):
    for attachment in attachments:
        try:
            (Config.UPLOAD_DIR / attachment["stored_name"]).unlink(missing_ok=True)
        except OSError:
            current_app.logger.warning("Could not delete file %s", attachment["stored_name"])


def delete_entry(entry):
    """Remove one user's copy. Delete the message itself when nobody has a copy left."""
    mailboxes.delete_one({"_id": entry["_id"]})
    if mailboxes.count_documents({"message_id": entry["message_id"]}, limit=1) == 0:
        message = messages.find_one_and_delete({"_id": entry["message_id"]})
        if message:
            delete_files(message.get("attachments", []))


# ---------- Attachments ----------
def file_content_matches(path, ext):
    with open(path, "rb") as fh:
        head = fh.read(1024)
    if ext == "txt":
        return b"\x00" not in head  # text files have no zero bytes
    return any(head.startswith(sig) for sig in FILE_SIGNATURES.get(ext, []))


def save_attachments(files):
    files = [f for f in files if f and f.filename]
    if len(files) > Config.MAX_FILES:
        raise ValueError(f"You can attach up to {Config.MAX_FILES} files.")

    Config.UPLOAD_DIR.mkdir(exist_ok=True)
    saved = []
    try:
        for file in files:
            raw_name = file.filename
            ext = raw_name.rsplit(".", 1)[1].lower() if "." in raw_name else ""
            if ext not in Config.ALLOWED_EXTENSIONS:
                raise ValueError(f'"{raw_name}" is not an allowed file type.')

            # Clean the name for display; store the file under a random name
            display_name = secure_filename(raw_name) or "attachment"
            if not display_name.lower().endswith("." + ext):
                display_name += "." + ext
            attachment_id = uuid.uuid4().hex
            stored_name = f"{attachment_id}.{ext}"
            path = Config.UPLOAD_DIR / stored_name

            file.save(path)
            size = path.stat().st_size
            if size > Config.MAX_FILE_SIZE:
                path.unlink(missing_ok=True)
                raise ValueError(f'"{display_name}" is larger than 10 MB.')
            if not file_content_matches(path, ext):
                path.unlink(missing_ok=True)
                raise ValueError(f'"{display_name}" does not look like a real .{ext} file.')

            saved.append({
                "id": attachment_id, "filename": display_name,
                "stored_name": stored_name, "size": size, "ext": ext,
            })
    except ValueError:
        delete_files(saved)  # don't leave half-uploaded files behind
        raise
    return saved


@messages_bp.get("/attachments/<attachment_id>")
@login_required
def download_attachment(attachment_id):
    if not re.fullmatch(r"[0-9a-f]{32}", attachment_id):
        return error("File not found.", 404)
    message = messages.find_one({"attachments.id": attachment_id}, {"attachments": 1})
    # Only people who have this message in their own mailbox may download it
    if message is None or not mailboxes.find_one({"user_id": g.user["_id"], "message_id": message["_id"]}):
        return error("File not found.", 404)

    attachment = next(a for a in message["attachments"] if a["id"] == attachment_id)
    return send_from_directory(
        Config.UPLOAD_DIR, attachment["stored_name"],
        as_attachment=True,
        download_name=attachment["filename"],
        mimetype=MIME_TYPES.get(attachment["ext"], "application/octet-stream"),
    )


# ---------- Listing and reading ----------
@messages_bp.get("/messages")
@login_required
def list_messages():
    folder = request.args.get("folder", "inbox")
    if folder not in FOLDERS:
        return error("Unknown folder.")
    try:
        page = max(1, int(request.args.get("page", 1)))
    except ValueError:
        page = 1

    query = {"user_id": g.user["_id"]}
    if folder == "starred":
        query.update(is_starred=True, folder={"$ne": "trash"})
    elif folder == "all":
        query["folder"] = {"$ne": "trash"}
    else:
        query["folder"] = folder

    search = request.args.get("q", "").strip().lower()[:100]
    if search:
        query["search_text"] = {"$regex": re.escape(search)}  # escape = treat as plain text

    total = mailboxes.count_documents(query)
    total_pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
    cursor = (mailboxes.find(query)
              .sort("created_at", DESCENDING)
              .skip((page - 1) * PAGE_SIZE)
              .limit(PAGE_SIZE))

    return jsonify({
        "messages": [list_item(e) for e in cursor],
        "page": page, "total_pages": total_pages, "total": total,
    })


@messages_bp.get("/messages/counts")
@login_required
def counts():
    uid = g.user["_id"]
    return jsonify({
        "inbox": mailboxes.count_documents({"user_id": uid, "folder": "inbox", "is_read": False}),
        "drafts": mailboxes.count_documents({"user_id": uid, "folder": "drafts"}),
        "spam": mailboxes.count_documents({"user_id": uid, "folder": "spam", "is_read": False}),
    })


@messages_bp.get("/messages/<entry_id>")
@login_required
def get_message(entry_id):
    entry = find_entry(entry_id)
    message = messages.find_one({"_id": entry["message_id"]}) if entry else None
    if message is None:
        return error("Message not found.", 404)

    if not entry["is_read"]:
        mailboxes.update_one({"_id": entry["_id"]}, {"$set": {"is_read": True}})
        entry["is_read"] = True

    item = list_item(entry)
    item["body"] = message["body"]
    item["attachments"] = [
        {"id": a["id"], "filename": a["filename"], "size": a["size"]}
        for a in message.get("attachments", [])
    ]
    return jsonify({"message": item})


@messages_bp.patch("/messages/<entry_id>")
@login_required
def update_message(entry_id):
    entry = find_entry(entry_id)
    if entry is None:
        return error("Message not found.", 404)

    action = str((request.get_json(silent=True) or {}).get("action", ""))
    folder = entry["folder"]

    if action == "star":
        change = {"is_starred": True}
    elif action == "unstar":
        change = {"is_starred": False}
    elif action == "read":
        change = {"is_read": True}
    elif action == "unread":
        change = {"is_read": False}
    elif action == "trash":
        if folder == "trash":
            return error("This message is already in trash.")
        change = {"folder": "trash", "previous_folder": folder}
    elif action == "restore":
        if folder != "trash":
            return error("Only messages in trash can be restored.")
        change = {"folder": entry.get("previous_folder") or "inbox"}
    elif action == "spam":
        if folder != "inbox":
            return error("Only inbox messages can be marked as spam.")
        change = {"folder": "spam"}
    elif action == "not_spam":
        if folder != "spam":
            return error("This message is not in spam.")
        change = {"folder": "inbox"}
    elif action == "delete_forever":
        if folder != "trash":
            return error("Move the message to trash first.")
        delete_entry(entry)
        return jsonify({"ok": True})
    else:
        return error("Unknown action.")

    mailboxes.update_one({"_id": entry["_id"]}, {"$set": change})
    return jsonify({"ok": True})


# ---------- Drafts ----------
@messages_bp.post("/drafts")
@login_required
def save_draft():
    data = request.get_json(silent=True) or {}
    me = g.user
    to_emails = parse_recipients(data.get("to", []))[:MAX_RECIPIENTS]
    subject = str(data.get("subject", ""))[:200]
    body = str(data.get("body", ""))[:20000]
    now = now_utc()

    fields = {
        "from_email": me["email"], "to_emails": to_emails, "subject": subject,
        "snippet": make_snippet(body),
        "search_text": make_search_text(me["email"], to_emails, subject, body),
        "has_attachments": False, "created_at": now,
    }

    draft_id = data.get("draft_id")
    if draft_id:
        entry = find_entry(draft_id)
        if entry is None or entry["folder"] != "drafts":
            return error("Draft not found.", 404)
        messages.update_one(
            {"_id": entry["message_id"]},
            {"$set": {"to_emails": to_emails, "subject": subject, "body": body, "created_at": now}},
        )
        mailboxes.update_one({"_id": entry["_id"]}, {"$set": fields})
        return jsonify({"draft_id": str(entry["_id"])})

    message_id = messages.insert_one({
        "sender_id": me["_id"], "sender_email": me["email"],
        "to_emails": to_emails, "recipient_ids": [],
        "subject": subject, "body": body, "attachments": [],
        "is_draft": True, "created_at": now,
    }).inserted_id
    entry_id = mailboxes.insert_one({
        "user_id": me["_id"], "message_id": message_id,
        "folder": "drafts", "is_read": True, "is_starred": False, **fields,
    }).inserted_id
    return jsonify({"draft_id": str(entry_id)}), 201


# ---------- Sending ----------
@messages_bp.post("/messages/send")
@login_required
def send_message():
    me = g.user
    to_emails = parse_recipients(request.form.get("to", ""))
    subject = request.form.get("subject", "").strip()[:200]
    body = request.form.get("body", "")[:20000]

    if not to_emails:
        return error("Add at least one recipient.")
    if len(to_emails) > MAX_RECIPIENTS:
        return error(f"You can send to at most {MAX_RECIPIENTS} people at once.")
    invalid = [e for e in to_emails if not EMAIL_PATTERN.fullmatch(e)]
    if invalid:
        return error(f'"{invalid[0]}" is not a valid email address.')

    external = [e for e in to_emails if not e.endswith("@" + Config.MAIL_DOMAIN)]
    if external:
        return error(
            f"Sending to outside addresses like {external[0]} isn't set up yet. "
            f"For now you can only email MailSpace users (@{Config.MAIL_DOMAIN})."
        )

    found = {
        u["email"]: u
        for u in users.find({"email": {"$in": to_emails}, "status": "active"})
        if not is_expired(u)
    }
    missing = [e for e in to_emails if e not in found]
    if missing:
        return error(f"No MailSpace account found for {missing[0]}.")

    try:
        attachments = save_attachments(request.files.getlist("attachments"))
    except ValueError as exc:
        return error(str(exc))

    now = now_utc()
    try:
        message_id = messages.insert_one({
            "sender_id": me["_id"], "sender_email": me["email"],
            "to_emails": to_emails, "recipient_ids": [u["_id"] for u in found.values()],
            "subject": subject, "body": body, "attachments": attachments,
            "is_draft": False, "created_at": now,
        }).inserted_id

        shared = {
            "message_id": message_id, "from_email": me["email"], "to_emails": to_emails,
            "subject": subject, "snippet": make_snippet(body),
            "search_text": make_search_text(me["email"], to_emails, subject, body),
            "has_attachments": bool(attachments), "is_starred": False, "created_at": now,
        }
        entries = [{**shared, "user_id": me["_id"], "folder": "sent", "is_read": True}]
        for recipient in found.values():
            entries.append({**shared, "user_id": recipient["_id"], "folder": "inbox", "is_read": False})
        mailboxes.insert_many(entries)
    except Exception:
        delete_files(attachments)
        raise

    # If this was a draft, remove the draft now that it has been sent
    draft_id = request.form.get("draft_id")
    if draft_id:
        draft = find_entry(draft_id)
        if draft and draft["folder"] == "drafts":
            delete_entry(draft)

    return jsonify({"message": "Message sent"}), 201
"""admin.py — platform admin console.
Admins can see all users and all mail. Opening a message's content is
recorded in the audit log (who, whose message, when, and why)."""
import io

from flask import Blueprint, g, jsonify, request, send_file
from pymongo import DESCENDING

from config import Config
from database import (addresses, attachment_files, audit_logs, domains,
                      mailboxes, messages, users)
from security import admin_required, now_utc, parse_object_id, to_iso

admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")

PAGE_SIZE = 25
MIME_TYPES = {
    "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif",
    "pdf": "application/pdf", "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "txt": "text/plain",
}


def error(message, status=400):
    return jsonify({"error": message}), status


def snippet(body):
    return " ".join((body or "").split())[:160]


# ---------- Overview ----------
@admin_bp.get("/stats")
@admin_required
def stats():
    return jsonify({
        "users": users.count_documents({}),
        "admins": users.count_documents({"role": "admin"}),
        "temporary": users.count_documents({"account_type": {"$ne": "regular"}}),
        "messages": messages.count_documents({"is_draft": {"$ne": True}}),
        "domains": domains.count_documents({"status": "verified"}),
        "addresses": addresses.count_documents({}),
        "reviews": audit_logs.count_documents({}),
        "flagged": messages.count_documents({"flagged": True}),
    })


# ---------- Users ----------
@admin_bp.get("/users")
@admin_required
def list_users():
    try:
        page = max(1, int(request.args.get("page", 1)))
    except ValueError:
        page = 1
    q = request.args.get("q", "").strip().lower()[:100]

    query = {}
    if q:
        query = {"$or": [
            {"username": {"$regex": q}},
            {"email": {"$regex": q}},
        ]}

    total = users.count_documents(query)
    total_pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
    cursor = (users.find(query, {"password_hash": 0})
              .sort("created_at", DESCENDING)
              .skip((page - 1) * PAGE_SIZE)
              .limit(PAGE_SIZE))

    rows = []
    for u in cursor:
        rows.append({
            "id": str(u["_id"]),
            "username": u["username"],
            "email": u["email"],
            "role": u.get("role", "user"),
            "account_type": u["account_type"],
            "status": u.get("status", "active"),
            "created_at": to_iso(u["created_at"]),
            "expires_at": to_iso(u.get("expires_at")),
            "inbox_count": mailboxes.count_documents({"user_id": u["_id"], "folder": "inbox"}),
        })
    return jsonify({"users": rows, "page": page, "total_pages": total_pages, "total": total})


# ---------- Messages (metadata only — no body yet) ----------
@admin_bp.get("/messages")
@admin_required
def list_all_messages():
    try:
        page = max(1, int(request.args.get("page", 1)))
    except ValueError:
        page = 1
    q = request.args.get("q", "").strip().lower()[:100]
    user_id = parse_object_id(request.args.get("user_id", ""))

    query = {"is_draft": {"$ne": True}}
    if request.args.get("flagged") == "1":
        query["flagged"] = True
    if user_id:
        query["$or"] = [{"sender_id": user_id}, {"recipient_ids": user_id}]
    if q:
        text = {"$regex": q, "$options": "i"}
        and_terms = [{"$or": [{"sender_email": text}, {"to_emails": text}, {"subject": text}]}]
        if "$or" in query:
            query = {"$and": [{"is_draft": {"$ne": True}}, {"$or": query.pop("$or")}] + and_terms}
        else:
            query.update(and_terms[0])

    total = messages.count_documents(query)
    total_pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
    cursor = (messages.find(query)
              .sort("created_at", DESCENDING)
              .skip((page - 1) * PAGE_SIZE)
              .limit(PAGE_SIZE))

    rows = []
    for m in cursor:
        files = m.get("attachments", [])
        rows.append({
            "id": str(m["_id"]),
            "from": m["sender_email"],
            "to": m.get("to_emails", []),
            "subject": m.get("subject", ""),
            "created_at": to_iso(m["created_at"]),
            "attachments": [{"filename": a["filename"], "size": a["size"]} for a in files],
            "has_attachments": bool(files),
            "external": bool(m.get("external_recipients")),
            "flagged": bool(m.get("flagged")),
            "flag_words": m.get("flag_words", []),
        })
    return jsonify({"messages": rows, "page": page, "total_pages": total_pages, "total": total})


# ---------- Open one message's content (LOGGED) ----------
@admin_bp.post("/messages/<message_id>/view")
@admin_required
def view_message(message_id):
    oid = parse_object_id(message_id)
    m = messages.find_one({"_id": oid}) if oid else None
    if m is None:
        return error("Message not found.", 404)

    reason = str((request.get_json(silent=True) or {}).get("reason", "")).strip()[:300]
    if len(reason) < 3:
        return error("Please give a short reason for opening this message.")

    # Record the review: who, whose message, when, why
    audit_logs.insert_one({
        "admin_id": g.user["_id"],
        "admin_email": g.user["email"],
        "action": "view_message",
        "message_id": m["_id"],
        "target_user_id": m["sender_id"],
        "target_email": m["sender_email"],
        "reason": reason,
        "created_at": now_utc(),
    })

    return jsonify({"message": {
        "id": str(m["_id"]),
        "from": m["sender_email"],
        "to": m.get("to_emails", []),
        "subject": m.get("subject", ""),
        "body": m.get("body", ""),
        "created_at": to_iso(m["created_at"]),
        "attachments": [
            {"id": a["id"], "filename": a["filename"], "size": a["size"]}
            for a in m.get("attachments", [])
        ],
    }})


# ---------- Download an attachment (LOGGED) ----------
@admin_bp.get("/attachments/<attachment_id>")
@admin_required
def download_attachment(attachment_id):
    m = messages.find_one({"attachments.id": attachment_id})
    if m is None:
        return error("File not found.", 404)
    a = next((x for x in m["attachments"] if x["id"] == attachment_id), None)
    if a is None or not a.get("file_id"):
        return error("File not found.", 404)

    audit_logs.insert_one({
        "admin_id": g.user["_id"],
        "admin_email": g.user["email"],
        "action": "download_attachment",
        "message_id": m["_id"],
        "target_user_id": m["sender_id"],
        "target_email": m["sender_email"],
        "reason": "attachment: " + a["filename"],
        "created_at": now_utc(),
    })

    stored = attachment_files.get(a["file_id"])
    return send_file(
        io.BytesIO(stored.read()),
        mimetype=MIME_TYPES.get(a["ext"], "application/octet-stream"),
        as_attachment=True, download_name=a["filename"],
    )


# ---------- Audit log ----------
@admin_bp.get("/audit")
@admin_required
def audit():
    try:
        page = max(1, int(request.args.get("page", 1)))
    except ValueError:
        page = 1
    total = audit_logs.count_documents({})
    total_pages = max(1, (total + PAGE_SIZE - 1) // PAGE_SIZE)
    cursor = (audit_logs.find({})
              .sort("created_at", DESCENDING)
              .skip((page - 1) * PAGE_SIZE)
              .limit(PAGE_SIZE))
    rows = [{
        "admin_email": r["admin_email"],
        "action": r["action"],
        "target_email": r.get("target_email", ""),
        "reason": r.get("reason", ""),
        "created_at": to_iso(r["created_at"]),
    } for r in cursor]
    return jsonify({"logs": rows, "page": page, "total_pages": total_pages, "total": total})
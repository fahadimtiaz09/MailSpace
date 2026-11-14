"""profile.py — your display name and profile picture.

  PATCH  /api/auth/profile      {display_name}     set / clear your name
  POST   /api/auth/avatar       (file "avatar")    upload a profile picture
  DELETE /api/auth/avatar                          remove it
  GET    /api/avatar/<user_id>                     the picture itself (signed-in users only)
  GET    /api/people?emails=a,b                    names + pictures of DoMailit addresses
                                                   (used to show photos next to emails)
"""
import io
import re

from bson import ObjectId
from flask import Blueprint, g, jsonify, request, send_file

from database import attachment_files, users
from routes.calls import find_user_by_address
from security import login_required, now_utc, parse_object_id

profile_bp = Blueprint("profile", __name__, url_prefix="/api")

MAX_AVATAR = 2 * 1024 * 1024        # 2 MB (the website/app shrink it before uploading)
MAX_NAME = 50
BAD_NAME_CHARS = re.compile(r'[<>"@,;\\\x00-\x1f\x7f]')  # would break an email "From:" line


def error(message, status=400):
    return jsonify({"error": message}), status


def clean_display_name(value):
    """A safe name for the 'From' line, or '' (None/blank = no name)."""
    name = " ".join(str(value or "").split())[:MAX_NAME]
    return BAD_NAME_CHARS.sub("", name).strip()


def avatar_url(user):
    if not user or not user.get("avatar_file_id"):
        return None
    return f"/api/avatar/{user['_id']}?v={user.get('avatar_version', 0)}"


def image_type(data):
    """Real file type from the first bytes (not the file name). SVG is not allowed."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


def remove_avatar_file(user):
    if user.get("avatar_file_id"):
        try:
            attachment_files.delete(user["avatar_file_id"])
        except Exception:
            pass


@profile_bp.patch("/auth/profile")
@login_required
def update_profile():
    data = request.get_json(silent=True) or {}
    if "display_name" not in data:
        return error("Nothing to change.")
    name = clean_display_name(data.get("display_name"))
    users.update_one({"_id": g.user["_id"]}, {"$set": {"display_name": name or None}})
    return jsonify({"display_name": name or None})


@profile_bp.post("/auth/avatar")
@login_required
def upload_avatar():
    file = request.files.get("avatar")
    if file is None:
        return error("Choose a picture first.")
    data = file.read(MAX_AVATAR + 1)
    if len(data) > MAX_AVATAR:
        return error("That picture is too big. Use one under 2 MB.")
    kind = image_type(data)
    if kind is None:
        return error("Use a PNG, JPG, GIF or WebP picture.")

    user = g.user
    file_id = attachment_files.put(data, filename=f"avatar-{user['_id']}", content_type=kind)
    version = int(now_utc().timestamp())
    users.update_one({"_id": user["_id"]}, {"$set": {"avatar_file_id": file_id, "avatar_version": version}})
    remove_avatar_file(user)  # the old picture
    return jsonify({"avatar": avatar_url({**user, "avatar_file_id": file_id, "avatar_version": version})})


@profile_bp.delete("/auth/avatar")
@login_required
def delete_avatar():
    remove_avatar_file(g.user)
    users.update_one({"_id": g.user["_id"]}, {"$unset": {"avatar_file_id": "", "avatar_version": ""}})
    return jsonify({"avatar": None})


@profile_bp.get("/avatar/<user_id>")
@login_required
def get_avatar(user_id):
    oid = parse_object_id(user_id)
    user = users.find_one({"_id": oid}) if oid else None
    if user is None or not user.get("avatar_file_id"):
        return error("No picture.", 404)
    try:
        stored = attachment_files.get(user["avatar_file_id"])
        data = stored.read()
    except Exception:
        return error("No picture.", 404)
    kind = image_type(data) or "application/octet-stream"
    response = send_file(io.BytesIO(data), mimetype=kind, max_age=86400)
    response.headers["Cache-Control"] = "private, max-age=86400"  # the ?v= in the URL changes on upload
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@profile_bp.get("/people")
@login_required
def people():
    """Names and pictures for DoMailit addresses. Outside addresses (Gmail…) are left out."""
    emails = [e.strip().lower() for e in request.args.get("emails", "").split(",") if "@" in e][:60]
    found = {}
    for email in dict.fromkeys(emails):
        user = find_user_by_address(email)
        if user:
            found[email] = {"name": user.get("display_name") or None, "avatar": avatar_url(user)}
    return jsonify({"people": found})

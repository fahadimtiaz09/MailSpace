"""auth.py — signup, login, logout, current user."""
import re
from datetime import timedelta

from flask import Blueprint, g, jsonify, request, session
from pymongo.errors import DuplicateKeyError
from werkzeug.security import check_password_hash, generate_password_hash

from config import Config
from database import users
from security import is_expired, login_required, now_utc, rate_limited, to_iso

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")

USERNAME_PATTERN = re.compile(r"^[a-z0-9._]{3,20}$")
ACCOUNT_DAYS = {"regular": None, "temp15": 15, "temp30": 30}


def error(message, status=400):
    return jsonify({"error": message}), status


def public_user(user):
    """What the frontend is allowed to see. Never includes password_hash."""
    return {
        "id": str(user["_id"]),
        "username": user["username"],
        "email": user["email"],
        "account_type": user["account_type"],
        "created_at": to_iso(user["created_at"]),
        "expires_at": to_iso(user.get("expires_at")),
    }


def start_session(user):
    session.clear()  # fresh session on every login
    session.permanent = True
    session["user_id"] = str(user["_id"])


@auth_bp.post("/signup")
def signup():
    if rate_limited("signup:" + (request.remote_addr or "?"), 10, 3600):
        return error("Too many sign-ups from this computer. Try again later.", 429)

    data = request.get_json(silent=True) or {}
    # str(...) makes sure nobody can send a trick object instead of text
    username = str(data.get("username", "")).strip().lower()
    password = str(data.get("password", ""))
    account_type = str(data.get("account_type", "regular"))

    if not USERNAME_PATTERN.fullmatch(username) or ".." in username \
            or username.startswith(".") or username.endswith("."):
        return error("Username must be 3–20 characters: lowercase letters, numbers, dot or underscore.")
    if not 8 <= len(password) <= 128:
        return error("Password must be between 8 and 128 characters.")
    if account_type not in ACCOUNT_DAYS:
        return error("Unknown account type.")

    created = now_utc()
    days = ACCOUNT_DAYS[account_type]
    user = {
        "username": username,
        "email": f"{username}@{Config.MAIL_DOMAIN}",
        "password_hash": generate_password_hash(password),  # never store the real password
        "account_type": account_type,
        "created_at": created,
        "expires_at": created + timedelta(days=days) if days else None,
        "status": "active",
    }

    try:
        result = users.insert_one(user)
    except DuplicateKeyError:
        return error("That username is already taken.", 409)

    user["_id"] = result.inserted_id
    start_session(user)
    return jsonify({"user": public_user(user)}), 201


@auth_bp.post("/login")
def login():
    if rate_limited("login:" + (request.remote_addr or "?"), 10, 300):
        return error("Too many login attempts. Please wait 5 minutes.", 429)

    data = request.get_json(silent=True) or {}
    login_value = str(data.get("login", "")).strip().lower()
    password = str(data.get("password", ""))
    if not login_value or not password:
        return error("Please enter your username/email and password.")

    field = "email" if "@" in login_value else "username"
    user = users.find_one({field: login_value})

    # Same message for "no such user" and "wrong password", so attackers learn nothing
    if user is None or not check_password_hash(user["password_hash"], password):
        return error("Wrong username/email or password.", 401)
    if user.get("status") != "active" or is_expired(user):
        return error("This account has expired and can no longer be used.", 403)

    start_session(user)
    return jsonify({"user": public_user(user)})


@auth_bp.post("/logout")
def logout():
    session.clear()
    return jsonify({"ok": True})


@auth_bp.get("/me")
@login_required
def me():
    return jsonify({"user": public_user(g.user)})
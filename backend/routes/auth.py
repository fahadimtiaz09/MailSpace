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
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
ACCOUNT_DAYS = {"regular": None, "temp15": 15, "temp30": 30}


def normalize_answer(text):
    """Lowercase, trim, collapse spaces — so 'New York' and ' new  york ' match."""
    return " ".join(str(text).strip().lower().split())


def mask_email(email):
    """n***@gmail.com — enough to recognise, not enough to read fully."""
    if not email or "@" not in email:
        return None
    local, domain = email.split("@", 1)
    shown = local[0] if local else "?"
    return shown + "***@" + domain


def error(message, status=400):
    return jsonify({"error": message}), status


def public_user(user):
    """What the frontend is allowed to see. Never includes password_hash."""
    return {
        "id": str(user["_id"]),
        "username": user["username"],
        "email": user["email"],
        "account_type": user["account_type"],
        "role": user.get("role", "user"),
        "created_at": to_iso(user["created_at"]),
        "expires_at": to_iso(user.get("expires_at")),
        "recovery_email": mask_email(user.get("recovery_email")),
        "security_question": user.get("security_question") or None,
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

    # Optional account-recovery info
    recovery_email = str(data.get("recovery_email", "")).strip().lower()
    if recovery_email:
        if not EMAIL_PATTERN.fullmatch(recovery_email):
            return error("That recovery email doesn't look right.")
        user["recovery_email"] = recovery_email

    question = str(data.get("security_question", "")).strip()[:120]
    answer = normalize_answer(data.get("security_answer", ""))
    if question or answer:
        if not question or len(answer) < 2:
            return error("For the security question, fill in both the question and an answer.")
        user["security_question"] = question
        user["security_answer_hash"] = generate_password_hash(answer)

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
@auth_bp.post("/change-password")
@login_required
def change_password():
    data = request.get_json(silent=True) or {}
    current = str(data.get("current_password", ""))
    new = str(data.get("new_password", ""))

    if not check_password_hash(g.user["password_hash"], current):
        return error("Your current password is wrong.", 403)
    if not 8 <= len(new) <= 128:
        return error("New password must be between 8 and 128 characters.")
    if check_password_hash(g.user["password_hash"], new):
        return error("The new password is the same as the current one.")

    users.update_one({"_id": g.user["_id"]}, {"$set": {"password_hash": generate_password_hash(new)}})
    return jsonify({"ok": True})

@auth_bp.post("/recovery")
@login_required
def set_recovery():
    """Set or change recovery email and security question. Needs the current password."""
    data = request.get_json(silent=True) or {}
    if not check_password_hash(g.user["password_hash"], str(data.get("current_password", ""))):
        return error("Your current password is wrong.", 403)

    set_fields = {}
    unset_fields = {}

    recovery_email = str(data.get("recovery_email", "")).strip().lower()
    if recovery_email:
        if not EMAIL_PATTERN.fullmatch(recovery_email):
            return error("That recovery email doesn't look right.")
        set_fields["recovery_email"] = recovery_email
    elif data.get("recovery_email") == "":   # explicitly cleared
        unset_fields["recovery_email"] = ""

    question = str(data.get("security_question", "")).strip()[:120]
    answer = normalize_answer(data.get("security_answer", ""))
    if question or answer:
        if not question or len(answer) < 2:
            return error("Fill in both the security question and an answer.")
        set_fields["security_question"] = question
        set_fields["security_answer_hash"] = generate_password_hash(answer)
    elif data.get("clear_question"):
        unset_fields["security_question"] = ""
        unset_fields["security_answer_hash"] = ""

    update = {}
    if set_fields:
        update["$set"] = set_fields
    if unset_fields:
        update["$unset"] = unset_fields
    if update:
        users.update_one({"_id": g.user["_id"]}, update)
    return jsonify({"ok": True})
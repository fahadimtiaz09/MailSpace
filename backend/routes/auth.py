"""auth.py — signup, login, logout, current user."""
import re
import secrets
from datetime import timedelta

from flask import Blueprint, g, jsonify, request, session
from pymongo.errors import DuplicateKeyError
from werkzeug.security import check_password_hash, generate_password_hash

from config import Config
from database import users
from plans import LIMITS, is_premium, plan_name, verified_kind
from security import (MAX_ACCOUNTS, note_attempt, contact_address, drop_session_account, is_expired, login_required,
                      now_utc, parse_object_id, rate_limited, session_account_ids, to_iso, usable)
from email_service import ExternalSendError, external_sending_ready, send_external

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")

USERNAME_PATTERN = re.compile(r"^[a-z0-9._]{3,20}$")
# Addresses DoMailit itself uses — nobody may sign up with them
RESERVED_USERNAMES = {"support", "admin", "administrator", "calls", "alerts", "noreply", "no-reply",
                      "postmaster", "abuse", "security", "help", "info", "contact", "team", "webmaster"}
EMAIL_PATTERN = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")
ACCOUNT_DAYS = {"regular": None, "temp15": 15, "temp30": 30}
TERMS_VERSION = "2026-11-29"  # change when terms.html / privacy.html change a lot
RESET_CODE_TTL = timedelta(minutes=15)
MAX_CODE_ATTEMPTS = 5


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
        "display_name": user.get("display_name") or None,
        "show_online": user.get("show_online", True),
        "avatar": (f"/api/avatar/{user['_id']}?v={user.get('avatar_version', 0)}"
                   if user.get("avatar_file_id") else None),
        "plan": plan_name(user),
        "verified": verified_kind(user),       # badge: "premium", "team" or None
        "premium_until": to_iso(user.get("premium_until")) if user.get("role") != "admin" else None,
    }


def start_session(user, add=False):
    """Log in. With add=True ("Add another account") the accounts already
    signed in on this browser stay signed in, and the new one becomes active."""
    user_id = str(user["_id"])
    keep = [i for i in session_account_ids() if i != user_id] if add else []
    csrf = session.get("csrf_token") if add else None
    session.clear()  # fresh session on every login
    session.permanent = True
    if csrf:
        session["csrf_token"] = csrf  # other open tabs keep working
    session["accounts"] = ([user_id] + keep)[:MAX_ACCOUNTS]
    session["user_id"] = user_id


def account_limit(extra_user=None):
    """How many accounts can be signed in at once on this browser:
    2 on the Free plan, 5 if any of them (or the one being added) is Premium."""
    ids = session_account_ids()
    people = list(users.find({"_id": {"$in": [o for o in (parse_object_id(i) for i in ids) if o]}},
                             {"premium_until": 1, "role": 1})) if ids else []
    if extra_user is not None:
        people.append(extra_user)
    return LIMITS["premium"]["accounts"] if any(is_premium(u) for u in people) else LIMITS["free"]["accounts"]


def adding_account(data, user=None):
    """True when "Add another account" was used and there's room for one more."""
    if data.get("add") is not True:
        return False
    ids = session_account_ids()
    if user is not None and str(user["_id"]) in ids:
        return True  # already signed in here: just switch to it
    return len(ids) < account_limit(user)


def account_limit_reached(data, user=None):
    """An error reply when "Add another account" can't add one more, else None."""
    if data.get("add") is True and not adding_account(data, user):
        limit = account_limit(user)
        if limit < LIMITS["premium"]["accounts"]:
            return error(f"The Free plan keeps {limit} accounts signed in at once. "
                         "Upgrade to Premium for up to 5.", 403)
        return error(f"You can keep up to {limit} accounts signed in at once.", 403)
    return None


USERNAME_RULES = "Username must be 3–20 characters: lowercase letters, numbers, dot or underscore."


def username_problem(username):
    """None if the username can be used; otherwise "invalid" or "taken"."""
    if not USERNAME_PATTERN.fullmatch(username) or ".." in username \
            or username.startswith(".") or username.endswith("."):
        return "invalid"
    # A renamed account keeps its old address, so nobody else can take it
    taken_email = f"{username}@{Config.MAIL_DOMAIN}"
    if username in RESERVED_USERNAMES or taken_email == contact_address() \
            or users.find_one({"$or": [{"username": username}, {"old_usernames": username},
                                       {"old_emails": taken_email}, {"aliases": taken_email}]},
                              {"_id": 1}):
        return "taken"
    return None


@auth_bp.get("/username-available")
def username_available():
    """Sign-up form asks while you type: is this username free?"""
    if rate_limited("uname:" + (request.remote_addr or "?"), 60, 60):
        return error("Too many checks. Please wait a minute.", 429)
    username = str(request.args.get("u", "")).strip().lower()[:40]
    problem = username_problem(username)
    messages = {
        None: f"{username}@{Config.MAIL_DOMAIN} is available.",
        "invalid": USERNAME_RULES,
        "taken": "That username is already taken.",
    }
    return jsonify({"available": problem is None, "reason": problem, "message": messages[problem]})


@auth_bp.post("/signup")
def signup():
    if rate_limited("signup:" + (request.remote_addr or "?"), 10, 3600):
        return error("Too many sign-ups from this computer. Try again later.", 429)

    data = request.get_json(silent=True) or {}
    # str(...) makes sure nobody can send a trick object instead of text
    username = str(data.get("username", "")).strip().lower()
    password = str(data.get("password", ""))
    account_type = str(data.get("account_type", "regular"))

    blocked = account_limit_reached(data)
    if blocked:
        return blocked

    problem = username_problem(username)
    if problem == "invalid":
        return error(USERNAME_RULES)
    if not 8 <= len(password) <= 128:
        return error("Password must be between 8 and 128 characters.")
    if account_type not in ACCOUNT_DAYS:
        return error("Unknown account type.")
    if data.get("accept_terms") is not True:
        return error("To create an account, please agree to the Terms of Service and Privacy Policy.")
    if problem == "taken":
        return error("That username is already taken.", 409)

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
        "terms_accepted_at": created,          # when they tapped "I agree"
        "terms_version": TERMS_VERSION,        # which version of the Terms they agreed to
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
    start_session(user, add=adding_account(data, user))
    return jsonify({"user": public_user(user)}), 201


@auth_bp.post("/login")
def login():
    data = request.get_json(silent=True) or {}
    login_value = str(data.get("login", "")).strip().lower()[:254]
    password = str(data.get("password", ""))
    if not login_value or not password:
        return error("Please enter your username/email and password.")

    # Only WRONG passwords are counted, so a whole class on one Wi-Fi can still sign in.
    # Per computer: 30 wrong tries in 15 min. Per account: 10 wrong tries in 15 min
    # (stops attackers who guess one account's password from many computers).
    ip_key = "loginfail:" + (request.remote_addr or "?")
    account_key = "loginfail-acct:" + login_value
    if rate_limited(ip_key, 30, 900, record=False) or rate_limited(account_key, 10, 900, record=False):
        return error("Too many wrong passwords. Please wait 15 minutes and try again.", 429)

    field = "email" if "@" in login_value else "username"
    # also the old address/username of a renamed account
    user = users.find_one({"$or": [{field: login_value}, {f"old_{field}s": login_value}]})

    # Same message for "no such user" and "wrong password", so attackers learn nothing
    if user is None or not user.get("password_hash") \
            or not check_password_hash(user["password_hash"], password):
        note_attempt(ip_key, 900)
        note_attempt(account_key, 900)
        return error("Wrong username/email or password.", 401)
    if user.get("status") != "active" or is_expired(user):
        return error("This account has expired and can no longer be used.", 403)

    blocked = account_limit_reached(data, user)
    if blocked:
        return blocked
    start_session(user, add=adding_account(data, user))
    return jsonify({"user": public_user(user)})


@auth_bp.post("/logout")
def logout():
    """Signs out the account in use. {"all": true} signs out every account here."""
    data = request.get_json(silent=True) or {}
    if data.get("all") is True or not session.get("user_id"):
        session.clear()
        return jsonify({"ok": True, "remaining": 0})
    return jsonify({"ok": True, "remaining": drop_session_account(session["user_id"])})


@auth_bp.get("/accounts")
def accounts():
    """Every account signed in on this browser (for the account switcher)."""
    ids = session_account_ids()
    object_ids = [o for o in (parse_object_id(i) for i in ids) if o]
    found = {str(u["_id"]): u for u in users.find({"_id": {"$in": object_ids}})} if object_ids else {}
    result, valid = [], []
    for i in ids:
        u = found.get(i)
        if not usable(u):
            continue
        valid.append(i)
        result.append({"id": i, "email": u["email"], "username": u["username"],
                       "display_name": u.get("display_name") or None,
                       "avatar": public_user(u)["avatar"],
                       "active": i == session.get("user_id")})
    if ids and valid != ids:  # forget accounts that were deleted or expired
        if valid:
            session["accounts"] = valid
            if session.get("user_id") not in valid:
                session["user_id"] = valid[0]
                result[0]["active"] = True
        else:
            session.clear()
    return jsonify({"accounts": result, "max": account_limit()})


@auth_bp.post("/switch")
def switch_account():
    """Use another account that is already signed in on this browser."""
    data = request.get_json(silent=True) or {}
    user_id = str(data.get("id", ""))
    if user_id not in session_account_ids():
        return error("That account isn't signed in here. Log in to it first.", 401)
    user = users.find_one({"_id": parse_object_id(user_id)})
    if not usable(user):
        drop_session_account(user_id)
        return error("That account can no longer be used. Log in again.", 401)
    session["user_id"] = user_id
    return jsonify({"user": public_user(user)})


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

# ---------- Forgot password ----------
def _find_login(login_value):
    login_value = str(login_value).strip().lower()
    if not login_value:
        return None
    field = "email" if "@" in login_value else "username"
    user = users.find_one({"$or": [{field: login_value}, {f"old_{field}s": login_value}]})
    if user is None or user.get("status") != "active" or is_expired(user):
        return None
    return user


@auth_bp.post("/forgot/start")
def forgot_start():
    """Step 1: tell the page which recovery methods this account has."""
    if rate_limited("forgot:" + (request.remote_addr or "?"), 20, 600):
        return error("Too many attempts. Please wait a few minutes.", 429)
    user = _find_login((request.get_json(silent=True) or {}).get("login", ""))
    if user is None:
        return error("No active account found for that username or email.", 404)
    return jsonify({
        "login": user["username"],
        "recovery_email": mask_email(user.get("recovery_email")),
        "security_question": user.get("security_question") or None,
    })


@auth_bp.post("/forgot/send-code")
def forgot_send_code():
    """Step 2a: email a 6-digit code to the recovery email."""
    if rate_limited("sendcode:" + (request.remote_addr or "?"), 8, 600):
        return error("Too many code requests. Please wait a few minutes.", 429)
    user = _find_login((request.get_json(silent=True) or {}).get("login", ""))
    if user is None or not user.get("recovery_email"):
        return error("That account has no recovery email.", 400)
    if not external_sending_ready():
        return error("Email sending isn't set up on this server yet.", 503)

    code = f"{secrets.randbelow(900000) + 100000}"  # a 6-digit number
    users.update_one({"_id": user["_id"]}, {"$set": {
        "reset_code_hash": generate_password_hash(code),
        "reset_expires": now_utc() + RESET_CODE_TTL,
        "reset_attempts": 0,
    }})

    body = (
        f"Hi {user['username']},\n\n"
        f"Your DoMailit password reset code is: {code}\n\n"
        "It expires in 15 minutes. If you didn't ask for this, you can ignore this email."
    )
    try:
        send_external(f"security@{Config.MAIL_DOMAIN}", "DoMailit Security",
                      [user["recovery_email"]], "Your DoMailit reset code", body)
    except ExternalSendError as exc:
        return error(f"Could not send the code: {exc}", 502)

    return jsonify({"ok": True, "sent_to": mask_email(user["recovery_email"])})


@auth_bp.post("/forgot/reset")
def forgot_reset():
    """Step 3: check the code OR the security answer, then set a new password."""
    if rate_limited("reset:" + (request.remote_addr or "?"), 15, 600):
        return error("Too many attempts. Please wait a few minutes.", 429)

    data = request.get_json(silent=True) or {}
    user = _find_login(data.get("login", ""))
    if user is None:
        return error("No active account found.", 404)

    new_password = str(data.get("new_password", ""))
    if not 8 <= len(new_password) <= 128:
        return error("New password must be between 8 and 128 characters.")

    method = str(data.get("method", ""))
    if method == "email":
        code = str(data.get("code", "")).strip()
        stored = user.get("reset_code_hash")
        expires = user.get("reset_expires")
        if not stored or not expires or expires <= now_utc():
            return error("That code has expired. Please request a new one.")
        if user.get("reset_attempts", 0) >= MAX_CODE_ATTEMPTS:
            return error("Too many wrong codes. Please request a new one.")
        if not check_password_hash(stored, code):
            users.update_one({"_id": user["_id"]}, {"$inc": {"reset_attempts": 1}})
            return error("That code is wrong.")
    elif method == "question":
        stored = user.get("security_answer_hash")
        if not stored:
            return error("That account has no security question.")
        if not check_password_hash(stored, normalize_answer(data.get("answer", ""))):
            return error("That answer is wrong.")
    else:
        return error("Choose how you want to reset.")

    # Success — set the new password and clear the reset code
    users.update_one({"_id": user["_id"]}, {
        "$set": {"password_hash": generate_password_hash(new_password)},
        "$unset": {"reset_code_hash": "", "reset_expires": "", "reset_attempts": ""},
    })
    return jsonify({"ok": True})
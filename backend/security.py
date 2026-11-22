"""security.py — login checks, CSRF protection, rate limiting, small helpers."""
import secrets
import time
from collections import defaultdict, deque
from datetime import datetime, timezone
from functools import wraps

from bson import ObjectId
from bson.errors import InvalidId
from flask import g, jsonify, request, session

from config import Config
from database import users

CSRF_COOKIE = "csrf_token"
SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}


def active_user_by_email(email):
    """The active account with this @MAIL_DOMAIN address — its address now, one it had
    before it was renamed, or an extra address (alias) such as support@
    (backend/rename_account.py)."""
    from database import users
    return users.find_one({"$or": [{"email": email}, {"old_emails": email}, {"aliases": email}],
                           "status": "active"})


def contact_address():
    """The team address on the website (Contact us), default support@<MAIL_DOMAIN>."""
    from config import Config
    return Config.CONTACT_EMAIL or f"support@{Config.MAIL_DOMAIN}"


def team_members(email):
    """support@ is a team address: every active admin gets a copy.
    Returns that list of admins, or None when this is not the team address."""
    if (email or "").strip().lower() != contact_address():
        return None
    from database import users
    return [u for u in users.find({"role": "admin", "status": "active"}) if not is_expired(u)]


def now_utc():
    return datetime.now(timezone.utc)


def to_iso(value):
    return value.isoformat() if value else None


def parse_object_id(value):
    """Turn text into a MongoDB ObjectId, or None if it is not a valid id."""
    try:
        return ObjectId(str(value))
    except (InvalidId, TypeError):
        return None


def is_expired(user):
    expires_at = user.get("expires_at")
    return expires_at is not None and expires_at <= now_utc()

# ---------- Signed-in accounts (Gmail-style "Add account") ----------
# One browser can be signed in to several accounts at once:
#   session["accounts"] = [user_id, ...]   every account signed in here
#   session["user_id"]  = the account being used right now
MAX_ACCOUNTS = 5


def session_account_ids():
    ids = [str(i) for i in (session.get("accounts") or []) if i]
    current = session.get("user_id")
    if current and current not in ids:
        ids.insert(0, current)  # sessions from before this feature
    return ids[:MAX_ACCOUNTS]


def usable(user):
    return user is not None and user.get("status") == "active" and not is_expired(user)


def drop_session_account(user_id):
    """Sign one account out of this browser. Moves to the next account, if any.
    Returns how many accounts are still signed in."""
    user_id = str(user_id)
    rest = [i for i in session_account_ids() if i != user_id]
    if not rest:
        session.clear()
        return 0
    session["accounts"] = rest
    if session.get("user_id") == user_id or session.get("user_id") not in rest:
        session["user_id"] = rest[0]
    return len(rest)


def _current_user():
    """(user, error_response). Checks the account in use and that this tab still shows it."""
    user_id = parse_object_id(session.get("user_id"))
    user = users.find_one({"_id": user_id}) if user_id else None
    if not usable(user):
        expired = user is not None and user.get("status") == "active" and is_expired(user)
        if session.get("user_id"):
            drop_session_account(session["user_id"])  # keep the other accounts signed in
        message = "Your temporary account has expired." if expired else "Please log in first."
        return None, (jsonify({"error": message}), 401)
    # The website sends the account its tab is showing. If another tab switched
    # accounts meanwhile, stop — otherwise this tab could act as the wrong account.
    shown = request.headers.get("X-Account")
    if shown and shown != str(user["_id"]):
        return None, (jsonify({"error": "You switched to another account in a different tab.",
                               "account_switched": True}), 409)
    return user, None


def admin_required(view):
    """Put @admin_required above a route to allow only platform admins."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        user, failed = _current_user()
        if failed:
            return failed
        if user.get("role") != "admin":
            return jsonify({"error": "Admins only."}), 403
        g.user = user
        return view(*args, **kwargs)
    return wrapper


def login_required(view):
    """Put @login_required above a route to allow only logged-in, non-expired users."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        user, failed = _current_user()
        if failed:
            return failed
        g.user = user  # the logged-in user, available inside the route
        return view(*args, **kwargs)
    return wrapper


# ---------- CSRF protection ----------
# Every API request that changes data must send back a secret token that only
# our own pages can read. Another website cannot read it, so it cannot fake requests.
def csrf_protect():
    token = session.setdefault("csrf_token", secrets.token_urlsafe(32))
    if request.method in SAFE_METHODS or not request.path.startswith("/api/"):
        return None
    if request.path.startswith("/api/inbound/"):
        return None  # Resend webhook: server-to-server, no CSRF cookie
    sent = request.headers.get("X-CSRFToken", "")
    if not secrets.compare_digest(sent.encode(), token.encode()):
        return jsonify({"error": "Security check failed. Refresh the page and try again."}), 400
    return None


def set_csrf_cookie(response):
    token = session.setdefault("csrf_token", secrets.token_urlsafe(32))
    if request.cookies.get(CSRF_COOKIE) != token:
        response.set_cookie(
            CSRF_COOKIE, token,
            samesite="Lax", secure=Config.SESSION_COOKIE_SECURE, httponly=False,
        )
    return response


# ---------- Simple rate limiting ----------
# Remembers recent attempts in memory. Resets when the server restarts.
_attempts = defaultdict(deque)


def rate_limited(key, limit, window_seconds):
    now = time.time()
    attempts = _attempts[key]
    while attempts and attempts[0] <= now - window_seconds:
        attempts.popleft()
    if len(attempts) >= limit:
        return True
    attempts.append(now)
    return False
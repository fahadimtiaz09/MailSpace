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


def login_required(view):
    """Put @login_required above a route to allow only logged-in, non-expired users."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        user_id = parse_object_id(session.get("user_id"))
        user = users.find_one({"_id": user_id}) if user_id else None
        if user is None or user.get("status") != "active":
            session.clear()
            return jsonify({"error": "Please log in first."}), 401
        if is_expired(user):
            session.clear()
            return jsonify({"error": "Your temporary account has expired."}), 401
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
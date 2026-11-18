"""routes/push.py — devices sign up here for notifications (website and app)."""
from urllib.parse import urlparse

from flask import Blueprint, g, jsonify, request
from pymongo import ASCENDING

from push import fcm_account, notify, push_subscriptions, vapid_keys
from security import login_required, now_utc

push_bp = Blueprint("push", __name__, url_prefix="/api/push")


def init_push_indexes():
    push_subscriptions.create_index("key", unique=True)
    push_subscriptions.create_index([("user_id", ASCENDING)])


# Only real browser push services — the server never posts to any other address
PUSH_HOSTS = ("fcm.googleapis.com", "updates.push.services.mozilla.com", "push.services.mozilla.com",
              "web.push.apple.com")
PUSH_HOST_ENDINGS = (".notify.windows.com", ".push.apple.com", ".googleapis.com")


def known_push_host(host):
    host = (host or "").lower()
    return host in PUSH_HOSTS or host.endswith(PUSH_HOST_ENDINGS)


def error(message, status=400):
    return jsonify({"error": message}), status


@push_bp.get("/config")
@login_required
def config():
    """The public key a browser needs to subscribe."""
    return jsonify({"web_public_key": vapid_keys()[1], "app_enabled": fcm_account() is not None})


def read_device():
    data = request.get_json(silent=True) or {}
    kind = data.get("kind")
    if kind == "web":
        sub = data.get("subscription") or {}
        endpoint = str(sub.get("endpoint", ""))
        keys = sub.get("keys") or {}
        url = urlparse(endpoint)
        if url.scheme != "https" or not known_push_host(url.hostname) or len(endpoint) > 1000 \
                or not isinstance(keys.get("p256dh"), str) or not isinstance(keys.get("auth"), str) \
                or len(keys["p256dh"]) > 200 or len(keys["auth"]) > 100:
            return None, None, None
        return kind, endpoint, {"endpoint": endpoint, "keys": {"p256dh": keys["p256dh"], "auth": keys["auth"]}}
    if kind == "fcm":
        token = str(data.get("token", "")).strip()
        if not 20 <= len(token) <= 4096:
            return None, None, None
        return kind, token, None
    return None, None, None


@push_bp.post("/subscribe")
@login_required
def subscribe():
    kind, key, subscription = read_device()
    if kind is None:
        return error("This device can't receive notifications.")
    device = str((request.get_json(silent=True) or {}).get("device", ""))[:80]
    # The same browser/phone can only belong to the account logged in on it now
    push_subscriptions.update_one(
        {"key": key},
        {"$set": {"user_id": g.user["_id"], "kind": kind, "subscription": subscription,
                  "device": device, "updated_at": now_utc()},
         "$setOnInsert": {"created_at": now_utc()}},
        upsert=True)
    return jsonify({"ok": True})


@push_bp.post("/unsubscribe")
@login_required
def unsubscribe():
    kind, key, _ = read_device()
    if kind is None:
        return error("Unknown device.")
    push_subscriptions.delete_one({"key": key, "user_id": g.user["_id"]})
    return jsonify({"ok": True})


@push_bp.post("/test")
@login_required
def test():
    if push_subscriptions.count_documents({"user_id": g.user["_id"]}, limit=1) == 0:
        return error("Turn on notifications on this device first.")
    notify([g.user["_id"]], "DoMailit notifications are on", "You'll see new emails and calls here.",
           url="/inbox", type_="test", tag="test")
    return jsonify({"ok": True})

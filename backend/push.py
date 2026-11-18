"""push.py — phone and browser notifications ("New email from Sara", "Incoming call").

Two free services do the delivery:
  * Web Push   — Chrome, Edge, Firefox (and Chrome on Android). The browser gives
                 us a "subscription" (an address at Google/Mozilla) and we send an
                 encrypted message to it. Works even when the DoMailit tab is closed.
                 The keys that prove the messages come from us ("VAPID" keys) are made
                 automatically the first time and saved in MongoDB.
  * Firebase Cloud Messaging (FCM) — the Android app. The app gives us a "token".
                 Needs FCM_SERVICE_ACCOUNT on the server (the JSON key file from
                 Firebase → Project settings → Service accounts). Without it, app
                 notifications are simply skipped.

Everything is sent in a background thread, so sending an email never waits for it.

Collection
----------
push_subscriptions {user_id, kind: "web"|"fcm", key (endpoint or token),
                    subscription (web only), device, created_at, last_ok}
"""
import base64
import json
import os
import struct
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from pymongo.errors import DuplicateKeyError

from config import Config
from database import db

push_subscriptions = db["push_subscriptions"]
app_settings = db["app_settings"]

TIMEOUT = 10  # seconds for each push request


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def b64url_decode(text: str) -> bytes:
    text = str(text)
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


# ---------------------------------------------------------------------------
# VAPID keys (identify our server to the browsers' push services)
# ---------------------------------------------------------------------------
_vapid = None


def vapid_keys():
    """(private_key, public_key_b64url). Made once, then shared by every server worker."""
    global _vapid
    if _vapid:
        return _vapid
    row = app_settings.find_one({"_id": "vapid"})
    if row is None:
        key = ec.generate_private_key(ec.SECP256R1())
        pem = key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                serialization.NoEncryption()).decode()
        try:
            app_settings.insert_one({"_id": "vapid", "private_pem": pem})
        except DuplicateKeyError:
            pass  # another worker made them at the same moment — use theirs
        row = app_settings.find_one({"_id": "vapid"})
    private = serialization.load_pem_private_key(row["private_pem"].encode(), password=None)
    public = private.public_key().public_bytes(serialization.Encoding.X962,
                                               serialization.PublicFormat.UncompressedPoint)
    _vapid = (private, b64url(public))
    return _vapid


def vapid_header(endpoint):
    private, public = vapid_keys()
    url = urllib.parse.urlparse(endpoint)
    claims = {
        "aud": f"{url.scheme}://{url.netloc}",
        "exp": int(time.time()) + 12 * 3600,
        "sub": f"mailto:support@{Config.MAIL_DOMAIN}",
    }
    signing_input = (b64url(json.dumps({"typ": "JWT", "alg": "ES256"}).encode()) + "."
                     + b64url(json.dumps(claims, separators=(",", ":")).encode()))
    r, s = decode_dss_signature(private.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256())))
    token = signing_input + "." + b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
    return f"vapid t={token}, k={public}"


# ---------------------------------------------------------------------------
# Web Push message encryption (RFC 8291, "aes128gcm")
# ---------------------------------------------------------------------------
def _hkdf(salt, ikm, info, length):
    return HKDF(algorithm=hashes.SHA256(), length=length, salt=salt, info=info).derive(ikm)


def encrypt_web_push(payload: bytes, p256dh: str, auth: str, salt: bytes = None, server_key=None) -> bytes:
    """Encrypt the notification so only the user's browser can read it."""
    ua_public = b64url_decode(p256dh)
    auth_secret = b64url_decode(auth)
    server_key = server_key or ec.generate_private_key(ec.SECP256R1())
    as_public = server_key.public_key().public_bytes(serialization.Encoding.X962,
                                                     serialization.PublicFormat.UncompressedPoint)
    shared = server_key.exchange(ec.ECDH(), ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), ua_public))
    ikm = _hkdf(auth_secret, shared, b"WebPush: info\x00" + ua_public + as_public, 32)
    salt = salt or os.urandom(16)
    cek = _hkdf(salt, ikm, b"Content-Encoding: aes128gcm\x00", 16)
    nonce = _hkdf(salt, ikm, b"Content-Encoding: nonce\x00", 12)
    ciphertext = AESGCM(cek).encrypt(nonce, payload + b"\x02", None)
    return salt + struct.pack("!IB", 4096, len(as_public)) + as_public + ciphertext


def send_web(subscription, data, urgent=False, ttl=86400):
    """Returns "ok", "gone" (subscription no longer valid) or "error"."""
    try:
        body = encrypt_web_push(json.dumps(data).encode(), subscription["keys"]["p256dh"],
                                subscription["keys"]["auth"])
        req = urllib.request.Request(subscription["endpoint"], data=body, method="POST", headers={
            "Authorization": vapid_header(subscription["endpoint"]),
            "Content-Encoding": "aes128gcm",
            "Content-Type": "application/octet-stream",
            "TTL": str(ttl),
            "Urgency": "high" if urgent else "normal",
        })
        with urllib.request.urlopen(req, timeout=TIMEOUT):
            return "ok"
    except urllib.error.HTTPError as exc:
        return "gone" if exc.code in (404, 410) else "error"
    except Exception:
        return "error"


# ---------------------------------------------------------------------------
# Firebase Cloud Messaging (Android app)
# ---------------------------------------------------------------------------
_fcm_token = {"value": None, "expires": 0}
_fcm_lock = threading.Lock()


def fcm_account():
    raw = os.getenv("FCM_SERVICE_ACCOUNT", "").strip()
    if not raw:
        return None
    try:
        if not raw.startswith("{"):
            raw = base64.b64decode(raw).decode()
        return json.loads(raw)
    except Exception:
        print("[PUSH] FCM_SERVICE_ACCOUNT is not valid JSON — app notifications are off.", flush=True)
        return None


def fcm_access_token(account):
    with _fcm_lock:
        if _fcm_token["value"] and _fcm_token["expires"] > time.time() + 60:
            return _fcm_token["value"]
        now = int(time.time())
        claims = {"iss": account["client_email"], "scope": "https://www.googleapis.com/auth/firebase.messaging",
                  "aud": account.get("token_uri", "https://oauth2.googleapis.com/token"),
                  "iat": now, "exp": now + 3600}
        signing_input = (b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode()) + "."
                         + b64url(json.dumps(claims).encode()))
        key = serialization.load_pem_private_key(account["private_key"].encode(), password=None)
        signature = key.sign(signing_input.encode(), padding.PKCS1v15(), hashes.SHA256())
        form = urllib.parse.urlencode({
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": signing_input + "." + b64url(signature),
        }).encode()
        req = urllib.request.Request(claims["aud"], data=form, method="POST")
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            answer = json.loads(resp.read())
        _fcm_token.update(value=answer["access_token"], expires=now + int(answer.get("expires_in", 3600)))
        return _fcm_token["value"]


def send_fcm(token, data, urgent=False, ttl=86400):
    account = fcm_account()
    if account is None:
        return "error"
    message = {
        "token": token,
        "notification": {"title": data["title"], "body": data["body"]},
        "data": {k: str(v) for k, v in data.items() if v is not None},
        "android": {
            "priority": "high",
            "ttl": f"{ttl}s",
            "notification": {
                "channel_id": "calls" if data.get("type") == "call" else "mail",
                "tag": data.get("tag") or "",
                "default_sound": True,
            },
        },
    }
    try:
        req = urllib.request.Request(
            f"https://fcm.googleapis.com/v1/projects/{account['project_id']}/messages:send",
            data=json.dumps({"message": message}).encode(), method="POST",
            headers={"Authorization": "Bearer " + fcm_access_token(account),
                     "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=TIMEOUT):
            return "ok"
    except urllib.error.HTTPError as exc:
        text = exc.read().decode(errors="ignore")
        if exc.code == 404 or "UNREGISTERED" in text or ("INVALID_ARGUMENT" in text and "token" in text.lower()):
            return "gone"
        return "error"
    except Exception:
        return "error"


# ---------------------------------------------------------------------------
# Sending to a user (all their devices)
# ---------------------------------------------------------------------------
def _deliver(user_ids, data, urgent, ttl):
    from security import now_utc
    for sub in list(push_subscriptions.find({"user_id": {"$in": list(user_ids)}})):
        if sub["kind"] == "web":
            result = send_web(sub["subscription"], data, urgent, ttl)
        else:
            result = send_fcm(sub["key"], data, urgent, ttl)
        if result == "gone":
            push_subscriptions.delete_one({"_id": sub["_id"]})
        elif result == "ok":
            push_subscriptions.update_one({"_id": sub["_id"]}, {"$set": {"last_ok": now_utc()}})


def notify(user_ids, title, body, url="/inbox", type_="mail", tag=None, urgent=False, ttl=86400, **extra):
    """Send a notification to every device of these users. Never raises."""
    user_ids = [u for u in user_ids if u]
    if not user_ids:
        return
    data = {"title": title[:120], "body": body[:200], "url": url, "type": type_, "tag": tag, **extra}
    try:
        threading.Thread(target=_deliver, args=(user_ids, data, urgent, ttl), daemon=True).start()
    except Exception:
        pass


def notify_new_mail(user_id, entry_id, from_email, from_name, subject):
    notify([user_id], from_name or from_email, subject or "(no subject)",
           url=f"/inbox?open={entry_id}", type_="mail", tag=f"mail-{entry_id}", entry_id=str(entry_id))

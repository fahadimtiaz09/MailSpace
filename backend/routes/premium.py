"""premium.py — DoMailit Premium: plan status and payment through Binance Pay.

How a purchase works
--------------------
1. Settings → "Upgrade" calls POST /api/premium/checkout {"period": "month"|"year"}.
   We create an order at Binance Pay and send the user to Binance's checkout page.
2. The user pays with their Binance account (USDT, no network fee).
3. Binance calls our webhook /api/premium/webhook, and the user is sent back to
   /settings.html?premium=<order no>, which calls POST /api/premium/confirm.
4. In both cases we ASK Binance for the order's status ourselves (order query,
   signed with our secret key). Only "PAID" turns Premium on, and each order
   is counted once. So a fake webhook can't give anyone Premium.

Settings on the server (/etc/domailit.env):
   BINANCE_PAY_API_KEY   Binance Pay merchant API key  (header BinancePay-Certificate-SN)
   BINANCE_PAY_SECRET    Binance Pay merchant secret key (signs every request)

Collection
----------
payments  {user_id, trade_no, period, days, amount, currency, status,
           prepay_id, checkout_url, created_at, paid_at, binance_status}
          status: created -> paid | failed
"""
import hashlib
import hmac
import json
import secrets
import string
import time
import urllib.error
import urllib.request

from flask import Blueprint, g, jsonify, request

from config import Config
from database import payments, users
from plans import LIMITS, PRICES, extend_premium, plan_summary, storage_limit_bytes, storage_used
from security import login_required, now_utc, rate_limited, to_iso

premium_bp = Blueprint("premium", __name__, url_prefix="/api/premium")

BINANCE_HOST = "https://bpay.binanceapi.com"
TRADE_NO_CHARS = string.ascii_uppercase + string.digits


def error(message, status=400):
    return jsonify({"error": message}), status


def payments_ready():
    return bool(Config.BINANCE_PAY_API_KEY and Config.BINANCE_PAY_SECRET)


# ---------- Binance Pay API ----------

def binance_call(path, body):
    """POST a signed request to Binance Pay. Returns the parsed reply (dict)."""
    payload = json.dumps(body, separators=(",", ":"))
    timestamp = str(int(time.time() * 1000))
    nonce = "".join(secrets.choice(string.ascii_letters) for _ in range(32))
    to_sign = f"{timestamp}\n{nonce}\n{payload}\n".encode()
    signature = hmac.new(Config.BINANCE_PAY_SECRET.encode(), to_sign, hashlib.sha512).hexdigest().upper()
    req = urllib.request.Request(
        BINANCE_HOST + path, data=payload.encode(), method="POST",
        headers={
            "Content-Type": "application/json",
            "BinancePay-Timestamp": timestamp,
            "BinancePay-Nonce": nonce,
            "BinancePay-Certificate-SN": Config.BINANCE_PAY_API_KEY,
            "BinancePay-Signature": signature,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode() or "{}")
    except urllib.error.HTTPError as exc:
        try:
            return json.loads(exc.read().decode() or "{}")
        except ValueError:
            return {"status": "FAIL", "errorMessage": f"HTTP {exc.code}"}
    except (urllib.error.URLError, TimeoutError, ValueError) as exc:
        return {"status": "FAIL", "errorMessage": str(exc)}


def binance_order_status(trade_no):
    """'PAID', 'INITIAL', 'PENDING', 'EXPIRED', … or None if Binance can't be asked."""
    reply = binance_call("/binancepay/openapi/v2/order/query", {"merchantTradeNo": trade_no})
    if reply.get("status") != "SUCCESS":
        return None
    return (reply.get("data") or {}).get("status")


# ---------- Turning Premium on ----------

def settle(payment):
    """Ask Binance about this order; if it's paid, give Premium (once). Returns the payment's status."""
    if payment["status"] == "paid":
        return "paid"
    remote = binance_order_status(payment["trade_no"])
    if remote is None:
        return payment["status"]
    if remote != "PAID":
        if remote in ("CANCELED", "EXPIRED", "ERROR"):
            payments.update_one({"_id": payment["_id"], "status": "created"},
                                {"$set": {"status": "failed", "binance_status": remote}})
            return "failed"
        return payment["status"]
    # Mark it paid exactly once, even if the webhook and the return page arrive together
    won = payments.find_one_and_update(
        {"_id": payment["_id"], "status": {"$ne": "paid"}},
        {"$set": {"status": "paid", "paid_at": now_utc(), "binance_status": "PAID"}},
    )
    if won:
        user = users.find_one({"_id": payment["user_id"]}, {"premium_until": 1})
        if user:
            new_until = extend_premium(user.get("premium_until"), payment["days"])
            users.update_one({"_id": user["_id"]},
                             {"$set": {"premium_until": new_until, "premium_since": user.get("premium_since") or now_utc()}})
    return "paid"


# ---------- Endpoints ----------

@premium_bp.get("")
@login_required
def premium_status():
    me = g.user
    return jsonify({
        **plan_summary(me),
        "prices": PRICES,
        "plans": LIMITS,
        "storage": {"used": storage_used(me["_id"]), "limit": storage_limit_bytes(me)},
        "payments_ready": payments_ready(),
    })


@premium_bp.post("/checkout")
@login_required
def checkout():
    if not payments_ready():
        return error("Payments are not set up yet. Please try again later.", 503)
    if rate_limited("checkout:" + str(g.user["_id"]), 10, 3600):
        return error("Too many attempts. Please wait a little and try again.", 429)
    period = str((request.get_json(silent=True) or {}).get("period", ""))
    price = PRICES.get(period)
    if not price:
        return error("Choose a monthly or yearly plan.")

    trade_no = "DM" + "".join(secrets.choice(TRADE_NO_CHARS) for _ in range(22))
    site = Config.SITE_URL.rstrip("/")
    body = {
        "env": {"terminalType": "WEB"},
        "merchantTradeNo": trade_no,
        "orderAmount": float(price["amount"]),
        "currency": "USDT",
        "goods": {
            "goodsType": "02",              # virtual goods
            "goodsCategory": "Z000",        # others
            "referenceGoodsId": "premium-" + period,
            "goodsName": "DoMailit Premium " + price["label"],
        },
        "returnUrl": f"{site}/settings.html?premium={trade_no}",
        "cancelUrl": f"{site}/settings.html?premium=cancelled",
        "webhookUrl": f"{site}/api/premium/webhook",
        "orderExpireTime": int(time.time() * 1000) + 60 * 60 * 1000,   # 1 hour
    }
    reply = binance_call("/binancepay/openapi/v2/order", body)
    data = reply.get("data") or {}
    if reply.get("status") != "SUCCESS" or not data.get("checkoutUrl"):
        return error("Binance Pay is not available right now. Please try again in a few minutes.", 502)

    payments.insert_one({
        "user_id": g.user["_id"], "trade_no": trade_no, "period": period, "days": price["days"],
        "amount": price["amount"], "currency": "USDT", "status": "created",
        "prepay_id": data.get("prepayId"), "checkout_url": data["checkoutUrl"],
        "created_at": now_utc(),
    })
    return jsonify({"checkout_url": data["checkoutUrl"], "trade_no": trade_no})


@premium_bp.post("/confirm")
@login_required
def confirm():
    trade_no = str((request.get_json(silent=True) or {}).get("trade_no", ""))[:40]
    payment = payments.find_one({"trade_no": trade_no, "user_id": g.user["_id"]})
    if not payment:
        return error("Payment not found.", 404)
    status = settle(payment)
    me = users.find_one({"_id": g.user["_id"]})
    return jsonify({"status": status, **plan_summary(me)})


@premium_bp.post("/webhook")
def webhook():
    """Binance tells us an order changed. We don't trust the message itself:
    settle() asks Binance directly before anything is turned on."""
    data = request.get_json(silent=True) or {}
    inner = data.get("data")
    if isinstance(inner, str):
        try:
            inner = json.loads(inner)
        except ValueError:
            inner = {}
    trade_no = str((inner or {}).get("merchantTradeNo", ""))[:40]
    payment = payments.find_one({"trade_no": trade_no}) if trade_no else None
    if payment:
        settle(payment)
    return jsonify({"returnCode": "SUCCESS", "returnMessage": None})


@premium_bp.get("/payments")
@login_required
def my_payments():
    rows = payments.find({"user_id": g.user["_id"], "status": "paid"}).sort("paid_at", -1).limit(24)
    return jsonify({"payments": [
        {"period": p["period"], "amount": p["amount"], "currency": p["currency"],
         "paid_at": to_iso(p.get("paid_at")), "trade_no": p["trade_no"]}
        for p in rows
    ]})


def init_premium_indexes():
    payments.create_index("trade_no", unique=True)
    payments.create_index([("user_id", 1), ("created_at", -1)])

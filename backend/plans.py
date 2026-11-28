"""plans.py — the Free and Premium plans: what each one allows.

Premium is bought for a month ($1) or a year ($10) through Binance Pay
(routes/premium.py). A user is Premium while `premium_until` is in the future.
Admins always get Premium limits.

Everything not listed here (calls, privacy controls, temporary accounts,
apps, support) is the same on both plans.
"""
import time
from datetime import timedelta

from database import mailboxes, users
from security import now_utc

GB = 1024 ** 3
MB = 1024 ** 2

LIMITS = {
    "free":    {"accounts": 2, "file_mb": 10, "storage_gb": 1,  "domains": 0, "addresses_per_domain": 10},
    "premium": {"accounts": 5, "file_mb": 25, "storage_gb": 10, "domains": 3, "addresses_per_domain": 10},
}

# What can be bought. Amounts are in USDT (1 USDT ≈ 1 US dollar).
PRICES = {
    "month": {"amount": "1.00", "days": 30, "label": "1 month"},
    "year": {"amount": "10.00", "days": 365, "label": "1 year"},
}


def premium_until(user):
    return (user or {}).get("premium_until")


def is_premium(user):
    if not user:
        return False
    if user.get("role") == "admin":
        return True
    until = premium_until(user)
    return until is not None and until > now_utc()


def plan_name(user):
    return "premium" if is_premium(user) else "free"


def limits(user):
    return LIMITS[plan_name(user)]


def max_file_bytes(user):
    return limits(user)["file_mb"] * MB


def storage_limit_bytes(user):
    return limits(user)["storage_gb"] * GB


# ---------- Storage used ----------
# Text + attachments of every email this user still has (not deleted forever).
# A message shared by two people counts for both, like Gmail.
# Cached for a few minutes because it adds up all of the user's mail.
_storage_cache = {}
STORAGE_CACHE_SECONDS = 300


def storage_used(user_id, fresh=False):
    key = str(user_id)
    cached = _storage_cache.get(key)
    if cached and not fresh and time.time() - cached[0] < STORAGE_CACHE_SECONDS:
        return cached[1]
    pipeline = [
        {"$match": {"user_id": user_id}},
        {"$lookup": {
            "from": "messages", "localField": "message_id", "foreignField": "_id", "as": "m",
            "pipeline": [{"$project": {"bytes": {"$add": [
                {"$sum": {"$ifNull": ["$attachments.size", []]}},
                {"$strLenBytes": {"$ifNull": ["$body", ""]}},
            ]}}}],
        }},
        {"$unwind": "$m"},
        {"$group": {"_id": None, "total": {"$sum": "$m.bytes"}}},
    ]
    result = list(mailboxes.aggregate(pipeline))
    total = int(result[0]["total"]) if result else 0
    _storage_cache[key] = (time.time(), total)
    return total


def forget_storage(user_id):
    _storage_cache.pop(str(user_id), None)


def extend_premium(current_until, days):
    """New end date: `days` after today, or after the current end if still running."""
    start = current_until if current_until and current_until > now_utc() else now_utc()
    return start + timedelta(days=days)


def verified_kind(user):
    """Verified badge next to a name: "team" for DoMailit staff, "premium" for Premium, else None."""
    if not user:
        return None
    if user.get("role") == "admin":
        return "team"
    return "premium" if is_premium(user) else None


def official_addresses():
    """DoMailit's own addresses (support@, alerts@, calls@ …): always shown as verified."""
    from config import Config
    from security import contact_address
    d = Config.MAIL_DOMAIN
    return {contact_address(), f"support@{d}", f"alerts@{d}", f"calls@{d}",
            f"noreply@{d}", f"no-reply@{d}", f"team@{d}"}


def verified_emails(emails):
    """{address: "premium" | "team"} for the verified senders among these addresses.
    Looks at each account's address, its old addresses and its extra ones (aliases)."""
    wanted = list({(e or "").strip().lower() for e in emails if e})
    if not wanted:
        return {}
    official = official_addresses()
    result = {e: "team" for e in wanted if e in official}
    rest = [e for e in wanted if e not in result]
    if rest:
        found = users.find({"$and": [
            {"$or": [{"email": {"$in": rest}}, {"aliases": {"$in": rest}}, {"old_emails": {"$in": rest}}]},
            {"$or": [{"role": "admin"}, {"premium_until": {"$gt": now_utc()}}]},
        ]}, {"email": 1, "aliases": 1, "old_emails": 1, "role": 1, "premium_until": 1})
        for u in found:
            kind = verified_kind(u)
            if not kind:
                continue
            for addr in [u.get("email")] + list(u.get("aliases") or []) + list(u.get("old_emails") or []):
                if addr and addr.lower() in rest:
                    result[addr.lower()] = kind
    return result


def plan_summary(user):
    """What the website/app shows about the user's plan."""
    return {
        "plan": plan_name(user),
        "premium_until": premium_until(user).isoformat() if premium_until(user) and user.get("role") != "admin" else None,
        "limits": limits(user),
    }

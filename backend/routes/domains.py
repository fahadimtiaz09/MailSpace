"""domains.py — customers add their own domain and prove they own it with a DNS record."""
import re
import secrets

import dns.exception
import dns.resolver
from flask import Blueprint, g, jsonify, request
from pymongo.errors import DuplicateKeyError

from config import Config
from database import domains
from security import login_required, now_utc, parse_object_id, rate_limited, to_iso

domains_bp = Blueprint("domains", __name__, url_prefix="/api/domains")

DOMAIN_PATTERN = re.compile(r"^(?=.{4,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")
VERIFY_HOST = "_mailspace"
MAX_DOMAINS_PER_USER = 3


def error(message, status=400):
    return jsonify({"error": message}), status


def clean_domain_name(value):
    """'https://www.Example.com/' -> 'www.example.com'"""
    name = str(value).strip().lower()
    name = re.sub(r"^https?://", "", name)
    return name.split("/")[0].rstrip(".")


def public_domain(d):
    return {
        "id": str(d["_id"]),
        "name": d["name"],
        "status": d["status"],
        "created_at": to_iso(d["created_at"]),
        "verified_at": to_iso(d.get("verified_at")),
        "dns_records": [
            {
                "type": "TXT",
                "host": VERIFY_HOST,
                "value": f"mailspace-verify={d['token']}",
                "purpose": "Proves you own this domain",
            },
        ],
    }


def find_domain(domain_id):
    """Find a domain that belongs to the logged-in user (or None)."""
    oid = parse_object_id(domain_id)
    if oid is None:
        return None
    return domains.find_one({"_id": oid, "owner_id": g.user["_id"]})


def lookup_txt(hostname):
    """Ask public DNS servers for the TXT records of a hostname."""
    resolver = dns.resolver.Resolver(configure=False)
    resolver.nameservers = ["1.1.1.1", "8.8.8.8"]  # Cloudflare and Google public DNS
    resolver.lifetime = 5
    try:
        answers = resolver.resolve(hostname, "TXT")
    except (dns.resolver.NXDOMAIN, dns.resolver.NoAnswer,
            dns.resolver.NoNameservers, dns.exception.Timeout):
        return []
    return [b"".join(r.strings).decode("utf-8", "replace") for r in answers]


@domains_bp.get("")
@login_required
def list_domains():
    cursor = domains.find({"owner_id": g.user["_id"]}).sort("created_at", 1)
    return jsonify({"domains": [public_domain(d) for d in cursor]})


@domains_bp.post("")
@login_required
def add_domain():
    name = clean_domain_name((request.get_json(silent=True) or {}).get("name", ""))

    if not DOMAIN_PATTERN.fullmatch(name):
        return error("Please enter a domain like yourbusiness.com")
    if name == Config.MAIL_DOMAIN:
        return error("That is MailSpace's own domain.")
    if domains.count_documents({"owner_id": g.user["_id"]}) >= MAX_DOMAINS_PER_USER:
        return error(f"You can add up to {MAX_DOMAINS_PER_USER} domains.")
    if domains.find_one({"name": name, "status": "verified"}):
        return error("This domain is already verified by another MailSpace account.", 409)

    doc = {
        "owner_id": g.user["_id"],
        "name": name,
        "token": secrets.token_hex(16),  # the secret code the owner must publish
        "status": "pending",
        "created_at": now_utc(),
    }
    try:
        doc["_id"] = domains.insert_one(doc).inserted_id
    except DuplicateKeyError:
        return error("You have already added this domain.", 409)

    return jsonify({"domain": public_domain(doc)}), 201


@domains_bp.post("/<domain_id>/verify")
@login_required
def verify_domain(domain_id):
    if rate_limited(f"verify:{g.user['_id']}", 20, 600):
        return error("Too many checks. Please wait a few minutes.", 429)

    d = find_domain(domain_id)
    if d is None:
        return error("Domain not found.", 404)
    if d["status"] == "verified":
        return jsonify({"domain": public_domain(d), "message": "This domain is already verified."})

    expected = f"mailspace-verify={d['token']}"
    found = lookup_txt(f"{VERIFY_HOST}.{d['name']}")

    if expected not in found:
        if found:
            return error(
                f"We found a TXT record at {VERIFY_HOST}.{d['name']}, but its value is different. "
                f"Expected: {expected}"
            )
        return error(
            f"We couldn't find the TXT record at {VERIFY_HOST}.{d['name']} yet. "
            "DNS changes usually take a few minutes, sometimes longer. Please try again soon."
        )

    try:
        domains.update_one(
            {"_id": d["_id"]},
            {"$set": {"status": "verified", "verified_at": now_utc()}},
        )
    except DuplicateKeyError:
        return error("Another MailSpace account has already verified this domain.", 409)

    d = domains.find_one({"_id": d["_id"]})
    return jsonify({"domain": public_domain(d), "message": f"{d['name']} is verified! 🎉"})


@domains_bp.delete("/<domain_id>")
@login_required
def remove_domain(domain_id):
    d = find_domain(domain_id)
    if d is None:
        return error("Domain not found.", 404)
    domains.delete_one({"_id": d["_id"]})
    return jsonify({"ok": True})
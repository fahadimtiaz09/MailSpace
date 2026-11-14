"""migrate_domain.py — ONE-TIME script for moving to a new main domain.

Changes every @OLD address in the database to @MAIL_DOMAIN (from .env).
Example (moving fahadimtiaz.site → domailit.com):
    1. In .env set   MAIL_DOMAIN=domailit.com
    2. Run           python backend\\migrate_domain.py fahadimtiaz.site
Old emails stay; only the addresses inside them change.
"""
import sys

from config import Config
from database import calls, mailboxes, messages, users

if len(sys.argv) != 2:
    raise SystemExit("Usage: python backend\\migrate_domain.py OLD_DOMAIN   (e.g. fahadimtiaz.site)")

OLD = "@" + sys.argv[1].strip().lower().lstrip("@")
NEW = "@" + Config.MAIL_DOMAIN

if NEW == OLD or NEW.endswith("mailspace.local"):
    raise SystemExit(f"First set MAIL_DOMAIN to the NEW domain in your .env file (now: {Config.MAIL_DOMAIN}).")

answer = input(f"Change every address ending in {OLD} to {NEW}? Type yes: ")
if answer.strip().lower() != "yes":
    raise SystemExit("Cancelled. Nothing was changed.")


def swap(field):
    # $ifNull: some old documents don't have the field
    return {"$replaceAll": {"input": {"$ifNull": [field, ""]}, "find": OLD, "replacement": NEW}}


def swap_list(field):
    return {"$map": {"input": {"$ifNull": [field, []]}, "as": "e", "in": swap("$$e")}}


old_regex = OLD.replace(".", r"\.") + "$"
u = users.update_many({"email": {"$regex": old_regex}}, [{"$set": {"email": swap("$email")}}])
m = messages.update_many({}, [{"$set": {
    "sender_email": swap("$sender_email"),
    "to_emails": swap_list("$to_emails"),
}}])
b = mailboxes.update_many({}, [{"$set": {
    "from_email": swap("$from_email"),
    "to_emails": swap_list("$to_emails"),
    "search_text": swap("$search_text"),
}}])
c = calls.update_many({}, [{"$set": {
    "caller_email": swap("$caller_email"),
    "callee_email": swap("$callee_email"),
}}])

print(f"Users updated: {u.modified_count}")
print(f"Messages updated: {m.modified_count}")
print(f"Mailbox entries updated: {b.modified_count}")
print(f"Calls updated: {c.modified_count}")
print(f"Done. Addresses now end with {NEW}")

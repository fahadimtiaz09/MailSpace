"""migrate_domain.py — ONE-TIME script.
Changes every @mailspace.local address in the database to the new MAIL_DOMAIN.
Run it only once:  python backend\\migrate_domain.py
"""
from config import Config
from database import mailboxes, messages, users

OLD = "@mailspace.local"
NEW = "@" + Config.MAIL_DOMAIN

if NEW == OLD:
    raise SystemExit("First set MAIL_DOMAIN=fahadimtiaz.site in your .env file.")


def swap(field):
    return {"$replaceAll": {"input": field, "find": OLD, "replacement": NEW}}


def swap_list(field):
    return {"$map": {"input": field, "as": "e", "in": swap("$$e")}}


u = users.update_many({"email": {"$regex": r"@mailspace\.local$"}}, [{"$set": {"email": swap("$email")}}])
m = messages.update_many({}, [{"$set": {
    "sender_email": swap("$sender_email"),
    "to_emails": swap_list("$to_emails"),
}}])
b = mailboxes.update_many({}, [{"$set": {
    "from_email": swap("$from_email"),
    "to_emails": swap_list("$to_emails"),
    "search_text": swap("$search_text"),
}}])

print(f"Users updated: {u.modified_count}")
print(f"Messages updated: {m.modified_count}")
print(f"Mailbox entries updated: {b.modified_count}")
print(f"Done. Addresses now end with {NEW}")
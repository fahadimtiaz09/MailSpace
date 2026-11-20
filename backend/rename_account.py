"""rename_account.py — give an account a new @domailit.com address.

Everything stays with the account (emails, sent mail, domains, photo, password,
admin rights). Only the address changes, everywhere it is written:
    fahad@domailit.com  →  mfahadimtiaz@domailit.com

The OLD address keeps working: mail sent to it still arrives in the same inbox,
you can still log in with it, and nobody else can sign up with it.

Run on the server (once):
    cd /opt/domailit && venv/bin/python backend/rename_account.py fahad mfahadimtiaz

Extra address on the same inbox (e.g. support@domailit.com for the Contact form):
    cd /opt/domailit && venv/bin/python backend/rename_account.py --alias mfahadimtiaz support
"""
import os
import re
import sys

# Read the server settings (/etc/domailit.env) before config.py looks at them
ENV_FILE = "/etc/domailit.env"
if os.path.exists(ENV_FILE):
    with open(ENV_FILE) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip())

from config import Config  # noqa: E402
from database import calls, mailboxes, messages, users  # noqa: E402

USERNAME_PATTERN = re.compile(r"^[a-z0-9._]{3,20}$")


def rename(old_username, new_username):
    old_username = old_username.strip().lower()
    new_username = new_username.strip().lower()
    if not USERNAME_PATTERN.fullmatch(new_username) or ".." in new_username \
            or new_username.startswith(".") or new_username.endswith("."):
        return "New username must be 3–20 characters: lowercase letters, numbers, dot or underscore."

    old_email = f"{old_username}@{Config.MAIL_DOMAIN}"
    new_email = f"{new_username}@{Config.MAIL_DOMAIN}"
    user = users.find_one({"username": old_username})
    if user is None:
        return f"No account called {old_username}."
    if users.find_one({"$or": [{"username": new_username}, {"email": new_email},
                               {"old_usernames": new_username}, {"old_emails": new_email}],
                       "_id": {"$ne": user["_id"]}}):
        return f"{new_email} is already used by another account."

    users.update_one({"_id": user["_id"]}, {
        "$set": {"username": new_username, "email": new_email},
        "$addToSet": {"old_usernames": old_username, "old_emails": old_email},
    })

    # The address written inside emails and calls (exact matches only)
    def one(field):
        return {"$cond": [{"$eq": [field, old_email]}, new_email, field]}

    def each(field):
        return {"$map": {"input": {"$ifNull": [field, []]}, "as": "e", "in": one("$$e")}}

    m = messages.update_many(
        {"$or": [{"sender_email": old_email}, {"to_emails": old_email}]},
        [{"$set": {"sender_email": one("$sender_email"), "to_emails": each("$to_emails")}}])
    b = mailboxes.update_many(
        {"$or": [{"from_email": old_email}, {"to_emails": old_email}]},
        [{"$set": {"from_email": one("$from_email"), "to_emails": each("$to_emails"),
                   "search_text": {"$concat": [{"$ifNull": ["$search_text", ""]}, " " + new_email]}}}])
    c = calls.update_many(
        {"$or": [{"caller_email": old_email}, {"callee_email": old_email}]},
        [{"$set": {"caller_email": one("$caller_email"), "callee_email": one("$callee_email")}}])
    return (f"Done: {old_email} → {new_email}. Emails {m.modified_count}, "
            f"inbox/sent entries {b.modified_count}, calls {c.modified_count}. "
            f"Mail to {old_email} still arrives in this account.")


def add_alias(username, alias):
    """Give an account an extra address (e.g. support@) that delivers to the same inbox
    and that it can send from."""
    username = username.strip().lower()
    alias = alias.strip().lower()
    if not USERNAME_PATTERN.fullmatch(alias) or ".." in alias or alias.startswith(".") or alias.endswith("."):
        return "The extra address must be 3–20 characters: lowercase letters, numbers, dot or underscore."
    alias_email = f"{alias}@{Config.MAIL_DOMAIN}"
    user = users.find_one({"username": username})
    if user is None:
        return f"No account called {username}."
    if users.find_one({"$or": [{"username": alias}, {"email": alias_email}, {"old_usernames": alias},
                               {"old_emails": alias_email}, {"aliases": alias_email}]}):
        return f"{alias_email} is already used."
    users.update_one({"_id": user["_id"]}, {"$addToSet": {"aliases": alias_email}})
    return f"Done: mail to {alias_email} now arrives in {user['email']}, and you can send from it."


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--alias":
        print(add_alias(sys.argv[2], sys.argv[3]))
        raise SystemExit(0)
    if len(sys.argv) != 3:
        raise SystemExit("Usage: venv/bin/python backend/rename_account.py OLD_USERNAME NEW_USERNAME\n"
                         "   or: venv/bin/python backend/rename_account.py --alias USERNAME EXTRA_NAME")
    old, new = sys.argv[1], sys.argv[2]
    answer = input(f"Change {old}@{Config.MAIL_DOMAIN} to {new}@{Config.MAIL_DOMAIN}? Type yes: ")
    if answer.strip().lower() != "yes":
        raise SystemExit("Cancelled. Nothing was changed.")
    print(rename(old, new))

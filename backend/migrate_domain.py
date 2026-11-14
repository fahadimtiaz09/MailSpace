"""migrate_domain.py — moves every address from an OLD main domain to MAIL_DOMAIN.

Old emails stay; only the addresses inside them change
(e.g. nimra@fahadimtiaz.site → nimra@domailit.com).

Two ways to run it (only once is needed; running again changes nothing):
  • Online (Render): add the setting  MIGRATE_FROM_DOMAIN = fahadimtiaz.site
    → it runs when the server starts. Remove the setting afterwards.
  • On a computer:   python backend\\migrate_domain.py fahadimtiaz.site
"""
import sys

from config import Config
from database import calls, mailboxes, messages, users


def migrate(old_domain):
    old = "@" + old_domain.strip().lower().lstrip("@")
    new = "@" + Config.MAIL_DOMAIN
    if new == old or new.endswith("mailspace.local"):
        return f"[MIGRATE] Skipped: set MAIL_DOMAIN to the NEW domain first (now {Config.MAIL_DOMAIN})."

    def swap(field):
        return {"$replaceAll": {"input": field, "find": old, "replacement": new}}

    def swap_list(field):
        return {"$map": {"input": field, "as": "e", "in": swap("$$e")}}

    old_regex = old.replace(".", r"\.") + "$"
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
    return (f"[MIGRATE] {old} → {new}: users {u.modified_count}, messages {m.modified_count}, "
            f"mailbox entries {b.modified_count}, calls {c.modified_count}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python backend\\migrate_domain.py OLD_DOMAIN   (e.g. fahadimtiaz.site)")
    answer = input(f"Change every address ending in @{sys.argv[1]} to @{Config.MAIL_DOMAIN}? Type yes: ")
    if answer.strip().lower() != "yes":
        raise SystemExit("Cancelled. Nothing was changed.")
    print(migrate(sys.argv[1]))

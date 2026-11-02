"""set_password.py — set a user's password directly (admin/CLI reset).
Usage:  python backend\\set_password.py fahad NewPass123
"""
import sys

from werkzeug.security import generate_password_hash

from database import users


def main(args):
    if len(args) != 2:
        print("Usage: python backend\\set_password.py <username> <new_password>")
        return
    username, password = args[0].strip().lower(), args[1]
    if len(password) < 8:
        print("Password must be at least 8 characters.")
        return
    result = users.update_one({"username": username}, {"$set": {"password_hash": generate_password_hash(password)}})
    if result.matched_count == 0:
        print(f"No user named '{username}'. Here are the usernames that exist:")
        for u in users.find({}, {"username": 1, "email": 1}):
            print("  -", u["username"], "(", u["email"], ")")
    else:
        print(f"Done. '{username}' can now log in with the password you set.")


if __name__ == "__main__":
    main(sys.argv[1:])
    
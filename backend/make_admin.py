"""make_admin.py — make a user an admin, or remove admin.
Usage:
  python backend\\make_admin.py fahad          -> make fahad an admin
  python backend\\make_admin.py nimra --remove -> remove nimra's admin
  python backend\\make_admin.py --list         -> list all admins
"""
import sys

from database import users


def main(args):
    if "--list" in args:
        admins = list(users.find({"role": "admin"}, {"username": 1, "email": 1}))
        if not admins:
            print("No admins yet.")
        for a in admins:
            print(f"  admin: {a['username']} ({a['email']})")
        return

    remove = "--remove" in args
    names = [a for a in args if not a.startswith("--")]
    if len(names) != 1:
        print("Usage: python backend\\make_admin.py <username> [--remove]")
        return

    username = names[0].strip().lower()
    new_role = "user" if remove else "admin"
    result = users.update_one({"username": username}, {"$set": {"role": new_role}})

    if result.matched_count == 0:
        print(f"No user named '{username}'.")
    else:
        print(f"'{username}' is now {'a normal user' if remove else 'an ADMIN'}.")


if __name__ == "__main__":
    main(sys.argv[1:])
"""grant_premium.py — give (or take away) Premium by hand, e.g. for a refund or a gift.

    python backend/grant_premium.py <username> <days>     # add days (30 = one month)
    python backend/grant_premium.py <username> 0          # end Premium now
"""
import sys

from database import users
from plans import extend_premium
from security import now_utc

if len(sys.argv) != 3 or not sys.argv[2].isdigit():
    print(__doc__)
    sys.exit(1)

username, days = sys.argv[1].strip().lower(), int(sys.argv[2])
user = users.find_one({"username": username})
if not user:
    print("No account with that username.")
    sys.exit(1)

until = extend_premium(user.get("premium_until"), days) if days else now_utc()
users.update_one({"_id": user["_id"]}, {"$set": {"premium_until": until}})
print(f"{username}: Premium until {until:%d %b %Y %H:%M} UTC" if days else f"{username}: Premium ended.")

"""safety.py — a simple keyword check that flags messages for admin review.

This is a basic word-match filter. It catches obvious terms but misses
cleverly worded content and can false-alarm on innocent uses. Real services
use machine learning. For this project it demonstrates the concept."""
import re

# Words/phrases that mark a message for review. Keep lowercase.
FLAG_WORDS = [
    "bomb", "explosive", "detonate", "terrorist", "terrorism",
    "attack plan", "kill everyone", "shooting", "massacre",
    "child abuse", "csam",
]

# Build one regex that matches any whole phrase, case-insensitive
_PATTERN = re.compile(
    r"(?<!\w)(" + "|".join(re.escape(w) for w in FLAG_WORDS) + r")(?!\w)",
    re.IGNORECASE,
)


def check_message(subject, body):
    """Return the list of flag words found in the subject or body (empty if none)."""
    text = (subject or "") + " " + (body or "")
    found = sorted(set(m.group(1).lower() for m in _PATTERN.finditer(text)))
    return found
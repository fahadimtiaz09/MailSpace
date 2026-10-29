"""email_service.py — sends email to outside addresses (Gmail, Outlook, ...) through Resend."""
import base64
import json
import urllib.error
import urllib.request

from config import Config

RESEND_URL = "https://api.resend.com/emails"


class ExternalSendError(Exception):
    """The email provider did not accept the email."""


def external_sending_ready():
    return bool(Config.RESEND_API_KEY)


def send_external(from_email, from_name, to_emails, subject, body, attachments=None):
    """Hand the email to Resend and return Resend's id for it.
    attachments = list of (filename, bytes). Raises ExternalSendError if it fails."""
    payload = {
        "from": f"{from_name} <{from_email}>",
        "to": to_emails,
        "subject": subject or "(no subject)",
        "text": body or " ",
    }
    if attachments:
        payload["attachments"] = [
            {"filename": name, "content": base64.b64encode(data).decode("ascii")}
            for name, data in attachments
        ]

    request = urllib.request.Request(
        RESEND_URL,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Bearer {Config.RESEND_API_KEY}",  # the secret key from .env
            "Content-Type": "application/json",
            "User-Agent": "MailSpace/1.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        try:
            detail = json.loads(exc.read().decode("utf-8")).get("message", "")
        except Exception:
            detail = ""
        raise ExternalSendError(detail or f"The email provider returned error {exc.code}.") from None
    except (urllib.error.URLError, TimeoutError):
        raise ExternalSendError("Could not reach the email provider. Please try again.") from None

    return result.get("id")
"""config.py — all settings in one place. Secrets come from the .env file."""
import os
from datetime import timedelta
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent  # the main project folder
load_dotenv(BASE_DIR / ".env")


class Config:
    APP_ENV = os.getenv("APP_ENV", "development")
    IS_PRODUCTION = APP_ENV == "production"
    DEBUG = not IS_PRODUCTION

    SECRET_KEY = os.getenv("SECRET_KEY")
    MONGODB_URI = os.getenv("MONGODB_URI")
    MONGODB_DATABASE = os.getenv("MONGODB_DATABASE", "mailspace")
    MAIL_DOMAIN = os.getenv("MAIL_DOMAIN", "mailspace.local").lower()

    FRONTEND_DIR = BASE_DIR / "frontend"
    UPLOAD_DIR = BASE_DIR / "uploads"  # outside the frontend folder, so not public

    # Attachments
    MAX_FILES = 5
    MAX_FILE_SIZE = 10 * 1024 * 1024          # 10 MB per file
    MAX_CONTENT_LENGTH = 55 * 1024 * 1024     # whole request limit
    ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "txt"}

    # Session cookie settings
    SESSION_COOKIE_HTTPONLY = True            # JavaScript cannot read the login cookie
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = IS_PRODUCTION     # HTTPS-only once deployed
    PERMANENT_SESSION_LIFETIME = timedelta(days=7)


def check_config():
    missing = [name for name in ("SECRET_KEY", "MONGODB_URI") if not getattr(Config, name)]
    if missing:
        raise RuntimeError(
            "Missing settings in .env: " + ", ".join(missing)
            + ". Copy .env.example to .env and fill in the values."
        )
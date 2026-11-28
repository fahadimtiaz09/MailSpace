"""app.py — starts the DoMailit server (locally and online)."""
import json
import os
import re

from flask import Flask, jsonify, request, send_from_directory
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix

from config import Config
from database import init_indexes, ping
from routes.auth import auth_bp
from routes.calls import calls_bp
from routes.profile import profile_bp
from routes.domains import domains_bp
from routes.admin import admin_bp
from routes.inbound import inbound_bp
from routes.contact import contact_bp
from routes.messages import messages_bp
from routes.push import init_push_indexes, push_bp
from routes.premium import init_premium_indexes, premium_bp
from routes.safety import init_safety_indexes, safety_bp
from headers import add_security_headers
from security import csrf_protect, set_csrf_cookie

ERROR_TEXT = {
    400: "Bad request.",
    404: "Not found.",
    405: "This action is not allowed here.",
    413: "The upload is too large.",
}


ANALYTICS_JS = """// analytics.js: visitor statistics for the public pages of domailit.com
(function () {
  var GA = "__GA__", CLARITY = "__CLARITY__";
  if (!GA && !CLARITY) return;
  // Respect "Do Not Track" / "Global Privacy Control", and never count local testing
  if (navigator.globalPrivacyControl || navigator.doNotTrack === "1") return;
  if (!/(^|\\.)domailit\\.com$/.test(location.hostname)) return;

  if (GA) {
    var g = document.createElement("script");
    g.async = true;
    g.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(GA);
    document.head.appendChild(g);
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag("js", new Date());
    window.gtag("config", GA);
  }
  if (CLARITY) {
    window.clarity = window.clarity || function () { (window.clarity.q = window.clarity.q || []).push(arguments); };
    var c = document.createElement("script");
    c.async = true;
    c.src = "https://www.clarity.ms/tag/" + encodeURIComponent(CLARITY);
    document.head.appendChild(c);
  }
})();
"""

def create_app():
    app = Flask(__name__, static_folder=str(Config.FRONTEND_DIR), static_url_path="")
    app.config.from_object(Config)

    if Config.IS_PRODUCTION:
        # Online, the app sits behind Render's proxy. Trust its headers so we see
        # the visitor's real IP (needed for rate limiting) and that the page uses https.
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    app.before_request(csrf_protect)
    app.after_request(set_csrf_cookie)
    app.after_request(add_security_headers)

    app.register_blueprint(auth_bp)
    app.register_blueprint(messages_bp)
    app.register_blueprint(domains_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(inbound_bp)
    app.register_blueprint(calls_bp)
    app.register_blueprint(profile_bp)
    app.register_blueprint(push_bp)
    app.register_blueprint(contact_bp)
    app.register_blueprint(safety_bp)
    app.register_blueprint(premium_bp)

    @app.route("/")
    def home():
        # Public landing page for visitors
        return send_from_directory(Config.FRONTEND_DIR, "home.html")

    @app.route("/inbox")
    def inbox():
        # The email app itself
        return send_from_directory(Config.FRONTEND_DIR, "index.html")

    # Android app: "Download for Android" on the home page.
    # The APK files are copied to Config.DOWNLOADS_DIR on the server (scp), not kept in git.
    @app.route("/download/android")
    @app.route("/download/android/<variant>")
    def download_android(variant="arm64"):
        files = {"arm64": "DoMailit-arm64.apk", "all": "DoMailit-universal.apk"}
        name = files.get(variant)
        if name is None or not os.path.isfile(os.path.join(Config.DOWNLOADS_DIR, name)):
            return send_from_directory(Config.FRONTEND_DIR, "404.html"), 404
        response = send_from_directory(Config.DOWNLOADS_DIR, name, as_attachment=True,
                                       download_name="DoMailit.apk",
                                       mimetype="application/vnd.android.package-archive")
        response.headers["Cache-Control"] = "no-cache"  # always the newest version
        return response

    # The newest Android version on the server (android.json is uploaded next to
    # the APKs by mobile/publish_android.ps1). The app compares it with its own
    # build number and offers "Update available".
    @app.route("/api/app/android")
    def android_latest():
        path = os.path.join(Config.DOWNLOADS_DIR, "android.json")
        try:
            with open(path, encoding="utf-8-sig") as f:  # PowerShell writes a BOM
                info = json.load(f)
            build = int(info["build"])
        except (OSError, ValueError, KeyError, TypeError):
            return jsonify({"error": "No Android version published yet."}), 404
        return jsonify({"version_name": str(info.get("version_name", "")), "build": build,
                        "url": "/download/android", "notes": str(info.get("notes", ""))[:500]})

    # Windows app (Microsoft Store): links to domailit.com open in the DoMailit app.
    # Windows reads this file to check that the app really belongs to this website.
    @app.route("/analytics.js")
    def analytics_js():
        # Loads Google Analytics and Microsoft Clarity on the public pages only.
        # Turned on by GA_MEASUREMENT_ID / CLARITY_PROJECT_ID in /etc/domailit.env.
        ga = Config.GA_MEASUREMENT_ID if re.fullmatch(r"G-[A-Z0-9]{4,20}", Config.GA_MEASUREMENT_ID) else ""
        clarity = Config.CLARITY_PROJECT_ID if re.fullmatch(r"[a-z0-9]{6,20}", Config.CLARITY_PROJECT_ID) else ""
        body = ANALYTICS_JS.replace("__GA__", ga).replace("__CLARITY__", clarity)
        response = app.response_class(body, mimetype="text/javascript")
        response.headers["Cache-Control"] = "public, max-age=3600"
        return response

    @app.route("/.well-known/security.txt")
    def security_txt():
        # Standard file that tells security researchers how to report a problem (RFC 9116).
        body = (
            "Contact: mailto:support@domailit.com\n"
            "Expires: 2027-11-30T00:00:00.000Z\n"
            "Preferred-Languages: en, ur\n"
            "Canonical: https://domailit.com/.well-known/security.txt\n"
            "Policy: https://domailit.com/terms.html\n"
        )
        return app.response_class(body, mimetype="text/plain")

    @app.route("/.well-known/windows-app-web-link")
    def windows_app_web_link():
        return jsonify([{
            "packageFamilyName": Config.WINDOWS_PACKAGE_FAMILY,
            "paths": ["*"],
            "excludePaths": ["/api/*", "/.well-known/*"],
        }])

    @app.route("/api/health")
    def health():
        try:
            ping()
            database = "connected"
        except Exception:
            database = "not connected"
        return jsonify({"status": "ok", "message": "DoMailit backend is running", "database": database})

    @app.errorhandler(HTTPException)
    def handle_http_error(exc):
        if request.path.startswith("/api/"):
            return jsonify({"error": ERROR_TEXT.get(exc.code, exc.name)}), exc.code
        return exc

    @app.errorhandler(Exception)
    def handle_unexpected_error(exc):
        app.logger.exception("Unexpected error")  # full details only in the server log
        return jsonify({"error": "Something went wrong on the server."}), 500

    return app


# Connect to MongoDB and prepare indexes when the server starts.
# This runs both for "python backend\app.py" and for the online server (gunicorn).
try:
    init_indexes()
    init_push_indexes()
    init_safety_indexes()
    init_premium_indexes()
    print("[OK] Connected to MongoDB. Indexes are ready.")
except Exception as exc:
    print("[ERROR] Could not connect to MongoDB:", exc)
    print("Check MONGODB_URI in your .env file and Network Access in Atlas.")
    raise SystemExit(1)

# One-time move to a new main domain: set MIGRATE_FROM_DOMAIN on Render
# (e.g. fahadimtiaz.site), then remove it. Safe to run again (nothing left to change),
# and a problem here never stops the website.
if os.getenv("MIGRATE_FROM_DOMAIN"):
    try:
        from migrate_domain import migrate
        print(migrate(os.getenv("MIGRATE_FROM_DOMAIN")), flush=True)
    except Exception as exc:
        print("[MIGRATE] Failed:", exc, flush=True)

app = create_app()

if __name__ == "__main__":
    app.run(debug=Config.DEBUG)
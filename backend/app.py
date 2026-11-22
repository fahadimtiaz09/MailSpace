"""app.py — starts the DoMailit server (locally and online)."""
import os

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
from routes.safety import init_safety_indexes, safety_bp
from security import csrf_protect, set_csrf_cookie

ERROR_TEXT = {
    400: "Bad request.",
    404: "Not found.",
    405: "This action is not allowed here.",
    413: "The upload is too large.",
}


def create_app():
    app = Flask(__name__, static_folder=str(Config.FRONTEND_DIR), static_url_path="")
    app.config.from_object(Config)

    if Config.IS_PRODUCTION:
        # Online, the app sits behind Render's proxy. Trust its headers so we see
        # the visitor's real IP (needed for rate limiting) and that the page uses https.
        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    app.before_request(csrf_protect)
    app.after_request(set_csrf_cookie)

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

    @app.route("/")
    def home():
        # Public landing page for visitors
        return send_from_directory(Config.FRONTEND_DIR, "home.html")

    @app.route("/inbox")
    def inbox():
        # The email app itself
        return send_from_directory(Config.FRONTEND_DIR, "index.html")

    # Windows app (Microsoft Store): links to domailit.com open in the DoMailit app.
    # Windows reads this file to check that the app really belongs to this website.
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
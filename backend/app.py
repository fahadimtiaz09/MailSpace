"""app.py — starts the MailSpace server."""
from flask import Flask, jsonify, request, send_from_directory
from werkzeug.exceptions import HTTPException

from config import Config
from database import init_indexes, ping
from routes.auth import auth_bp
from routes.messages import messages_bp
from routes.domains import domains_bp
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

    app.before_request(csrf_protect)
    app.after_request(set_csrf_cookie)

    app.register_blueprint(auth_bp)
    app.register_blueprint(messages_bp)
    app.register_blueprint(domains_bp)

    @app.route("/")
    def home():
        # Public landing page for visitors
        return send_from_directory(Config.FRONTEND_DIR, "home.html")

    @app.route("/inbox")
    def inbox():
        # The email app itself
        return send_from_directory(Config.FRONTEND_DIR, "index.html")

    @app.route("/api/health")
    def health():
        try:
            ping()
            database = "connected"
        except Exception:
            database = "not connected"
        return jsonify({"status": "ok", "message": "MailSpace backend is running", "database": database})

    @app.errorhandler(HTTPException)
    def handle_http_error(exc):
        if request.path.startswith("/api/"):
            return jsonify({"error": ERROR_TEXT.get(exc.code, exc.name)}), exc.code
        return exc

    @app.errorhandler(Exception)
    def handle_unexpected_error(exc):
        app.logger.exception("Unexpected error")  # full details only in the terminal
        return jsonify({"error": "Something went wrong on the server."}), 500

    return app


app = create_app()

if __name__ == "__main__":
    try:
        init_indexes()
        print("[OK] Connected to MongoDB. Indexes are ready.")
    except Exception as exc:
        print("[ERROR] Could not connect to MongoDB:", exc)
        print("Check MONGODB_URI in your .env file and Network Access in Atlas.")
        raise SystemExit(1)

    app.run(debug=Config.DEBUG)
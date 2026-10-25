from pathlib import Path
from flask import Flask, jsonify, send_from_directory

BASE_DIR = Path(__file__).resolve().parent.parent
FRONTEND_DIR = BASE_DIR / "frontend"

app = Flask(__name__, static_folder=str(FRONTEND_DIR), static_url_path="")


@app.route("/")
def home():
    return send_from_directory(FRONTEND_DIR, "index.html")


@app.route("/api/health")
def health():
    return jsonify({"status": "ok", "message": "MailSpace backend is running"})


if __name__ == "__main__":
    app.run(debug=True)
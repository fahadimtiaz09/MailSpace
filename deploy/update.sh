#!/usr/bin/env bash
# update.sh — after you push new code to GitHub, run this on the server:
#   bash /opt/domailit/deploy/update.sh
set -euo pipefail
APP_DIR="/opt/domailit"
git -C "$APP_DIR" config --global --add safe.directory "$APP_DIR" || true
git -C "$APP_DIR" pull --ff-only
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"
chown -R domailit:domailit "$APP_DIR"
systemctl restart domailit
sleep 3
curl -fsS -H "Host: domailit.com" http://127.0.0.1/api/health && echo && echo "✅ Updated and running."

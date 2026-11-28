#!/usr/bin/env bash
# update.sh — after you push new code to GitHub, run this on the server:
#   bash /opt/domailit/deploy/update.sh
set -euo pipefail
APP_DIR="/opt/domailit"
git -C "$APP_DIR" config --global --add safe.directory "$APP_DIR" || true
git -C "$APP_DIR" pull --ff-only
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/backend/requirements.txt"
chown -R domailit:domailit "$APP_DIR"
systemctl restart domailit
# Health check: ask the app itself (gunicorn on port 8000), not nginx —
# nginx sends plain http to https, which only prints "301 Moved Permanently".
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS http://127.0.0.1:8000/api/health; then
    echo && echo "✅ Updated and running."
    exit 0
  fi
  sleep 2
done
echo "❌ The app did not start. See: journalctl -u domailit -n 50"
exit 1

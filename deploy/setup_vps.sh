#!/usr/bin/env bash
# setup_vps.sh — installs DoMailit on a fresh Ubuntu server (Contabo VPS).
#
# Run once, as root:
#   curl -fsSL https://raw.githubusercontent.com/fahadimtiaz09/MailSpace/main/deploy/setup_vps.sh -o setup.sh
#   bash setup.sh
#
# What it does:
#   1. updates Ubuntu, installs Python, nginx, firewall, automatic security updates
#   2. downloads the DoMailit code to /opt/domailit
#   3. asks for the settings (same values as on Render → Environment)
#   4. runs the app 24/7 with gunicorn (restarts by itself after crashes/reboots)
#   5. puts nginx in front of it (port 80) — HTTPS comes later with enable_https.sh
set -euo pipefail

REPO="https://github.com/fahadimtiaz09/MailSpace.git"
APP_DIR="/opt/domailit"
ENV_FILE="/etc/domailit.env"
DOMAIN="domailit.com"

if [ "$(id -u)" -ne 0 ]; then echo "Run as root:  sudo bash setup.sh"; exit 1; fi
step() { echo; echo "==== $* ===="; }

step "1/6  Updating Ubuntu and installing packages (takes a few minutes)"
export DEBIAN_FRONTEND=noninteractive
timedatectl set-timezone Asia/Karachi || true
apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-venv python3-pip git nginx certbot python3-certbot-nginx \
                   ufw fail2ban unattended-upgrades curl
dpkg-reconfigure -f noninteractive unattended-upgrades || true

step "2/6  Downloading DoMailit"
id -u domailit >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin domailit
git config --global --add safe.directory "$APP_DIR" || true
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull --ff-only
else
  git clone "$REPO" "$APP_DIR"
fi
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/backend/requirements.txt"
chown -R domailit:domailit "$APP_DIR"

step "3/6  Settings (copy each value from Render → your service → Environment)"
if [ -f "$ENV_FILE" ]; then
  echo "Settings already saved in $ENV_FILE — keeping them. (Edit with: nano $ENV_FILE)"
else
  ask() {  # ask NAME "question" [default] [secret]
    local name="$1" question="$2" default="${3:-}" secret="${4:-}" value=""
    while [ -z "$value" ]; do
      if [ -n "$secret" ]; then read -r -s -p "$question: " value; echo
      else read -r -p "$question${default:+ [$default]}: " value; fi
      value="${value:-$default}"
    done
    printf '%s=%s\n' "$name" "$value" >> "$ENV_FILE"
  }
  umask 077
  : > "$ENV_FILE"
  echo "APP_ENV=production" >> "$ENV_FILE"
  ask MONGODB_URI      "MONGODB_URI (paste, it stays hidden)" "" secret
  ask MONGODB_DATABASE "MONGODB_DATABASE" "mailspace"
  ask SECRET_KEY       "SECRET_KEY (paste, hidden)" "" secret
  ask MAIL_DOMAIN      "MAIL_DOMAIN" "$DOMAIN"
  ask RESEND_API_KEY   "RESEND_API_KEY (paste, hidden)" "" secret
  ask INBOUND_SECRET   "INBOUND_SECRET (paste, hidden)" "" secret
  ask CALL_TIMEZONE    "CALL_TIMEZONE" "Asia/Karachi"
  chown root:domailit "$ENV_FILE"
  chmod 640 "$ENV_FILE"
  echo "Saved in $ENV_FILE"
fi

step "4/6  Running the app 24/7 (gunicorn + systemd)"
cat > /etc/systemd/system/domailit.service <<UNIT
[Unit]
Description=DoMailit (Flask + gunicorn)
After=network-online.target
Wants=network-online.target

[Service]
User=domailit
Group=domailit
WorkingDirectory=$APP_DIR/backend
EnvironmentFile=$ENV_FILE
ExecStart=$APP_DIR/venv/bin/gunicorn app:app --bind 127.0.0.1:8000 \\
  --worker-class gthread --workers 3 --threads 8 --timeout 120 \\
  --access-logfile - --error-logfile -
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now domailit
sleep 3

step "5/6  nginx (web server in front of the app)"
cat > /etc/nginx/sites-available/domailit <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    client_max_body_size 60m;          # attachments (the app allows 55 MB)

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_read_timeout 120s;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/domailit /etc/nginx/sites-enabled/domailit
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

step "6/6  Firewall (only SSH + web open)"
ufw allow OpenSSH
ufw allow "Nginx Full"
ufw --force enable
systemctl enable --now fail2ban

echo
echo "================ CHECK ================"
if curl -fsS -H "Host: $DOMAIN" http://127.0.0.1/api/health; then
  echo; echo "✅ DoMailit is running on this server."
else
  echo "❌ The app did not answer. Most common cause: MongoDB Atlas → Network Access doesn't allow this server's IP."
  echo "   See the error with:  journalctl -u domailit -n 50 --no-pager"
fi
IP=$(curl -fsS https://api.ipify.org || hostname -I | awk '{print $1}')
echo
echo "Server IP: $IP"
echo "Next:"
echo "  1. Namecheap → Advanced DNS → A record  @  →  $IP   (and delete the ALIAS record)"
echo "  2. When http://domailit.com opens, run:  bash $APP_DIR/deploy/enable_https.sh"

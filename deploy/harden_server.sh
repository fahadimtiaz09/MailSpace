#!/usr/bin/env bash
# harden_server.sh — extra security for the DoMailit server. Safe to run again.
#   bash /opt/domailit/deploy/harden_server.sh
#
# 1. firewall on (only SSH, HTTP, HTTPS open)
# 2. fail2ban: blocks IPs that keep guessing the SSH password
# 3. automatic Ubuntu security updates
# 4. nginx stops telling the world its version number
# 5. SSH: password login is switched OFF only if a login key is already set up
#    (so you can never lock yourself out)
# 6. nginx: per-computer request limits (floods, password guessing, slow attacks)
set -euo pipefail
step() { echo; echo "==> $1"; }

step "1/6  Firewall"
ufw allow OpenSSH >/dev/null
ufw allow "Nginx Full" >/dev/null
ufw --force enable >/dev/null
ufw status | head -8

step "2/6  fail2ban (block password guessers)"
apt-get install -y -qq fail2ban >/dev/null
cat > /etc/fail2ban/jail.d/domailit.local <<'EOF'
[sshd]
enabled  = true
maxretry = 5
findtime = 10m
bantime  = 1h
bantime.increment = true
EOF
systemctl enable --now fail2ban >/dev/null
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd | grep -E "Currently banned|Total banned" || true

step "3/6  Automatic security updates"
apt-get install -y -qq unattended-upgrades >/dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades >/dev/null
echo "on"

step "4/6  Hide nginx version"
if ! grep -qE '^\s*server_tokens\s+off;' /etc/nginx/nginx.conf; then
  sed -i 's/^\(\s*\)#\?\s*server_tokens.*/\1server_tokens off;/' /etc/nginx/nginx.conf
  grep -qE '^\s*server_tokens\s+off;' /etc/nginx/nginx.conf || \
    sed -i 's/^\(\s*\)http\s*{/&\n\1    server_tokens off;/' /etc/nginx/nginx.conf
fi
nginx -t && systemctl reload nginx

step "5/6  SSH login"
if [ -s /root/.ssh/authorized_keys ]; then
  cat > /etc/ssh/sshd_config.d/10-domailit.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
  sshd -t && (systemctl reload ssh 2>/dev/null || systemctl reload sshd)
  echo "Password login is OFF. Only your laptop's key can log in now."
else
  echo "No login key found yet, so password login stays ON (nothing changed)."
  echo "Set up the key from your laptop first, then run this script again."
fi

step "6/6  Request limits (nginx)"
LIMITS=/etc/nginx/conf.d/domailit-limits.conf
cat > "$LIMITS" <<'EOF'
# DoMailit — per-computer (per IP) request limits. Made by harden_server.sh.
# Pages, pictures and scripts are never limited; only /api/ requests are.

# Sign-in, sign-up and password reset: 60 per minute, bursts of 30 (a class on one Wi-Fi can still sign in).
map $request_uri $domailit_auth_key {
    ~^/api/auth/(login|signup|forgot/)  $binary_remote_addr;
    default                             "";
}
# Everything else under /api/: 20 per second, bursts of 120 (a whole class on one Wi-Fi is fine).
map $request_uri $domailit_api_key {
    ~^/api/   $binary_remote_addr;
    default   "";
}
limit_req_zone  $domailit_auth_key   zone=domailit_auth:10m  rate=60r/m;
limit_req_zone  $domailit_api_key    zone=domailit_api:20m   rate=20r/s;
limit_conn_zone $binary_remote_addr  zone=domailit_conn:10m;

limit_req  zone=domailit_auth burst=30  nodelay;
limit_req  zone=domailit_api  burst=120 nodelay;
limit_conn domailit_conn 100;
limit_req_status  429;
limit_conn_status 429;

# Drop connections that send their request very slowly ("slowloris" attacks)
client_header_timeout 15s;
client_body_timeout   30s;
EOF
if nginx -t 2>/dev/null; then
  systemctl reload nginx
  echo "on: /api/ limited per computer, sign-in 60/min, slow connections dropped"
else
  rm -f "$LIMITS"
  echo "nginx did not accept the limits, so they were removed (nothing changed)."
  nginx -t || true
fi

echo; echo "✅ Server hardening done."

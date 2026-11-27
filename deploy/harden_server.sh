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
set -euo pipefail
step() { echo; echo "==> $1"; }

step "1/5  Firewall"
ufw allow OpenSSH >/dev/null
ufw allow "Nginx Full" >/dev/null
ufw --force enable >/dev/null
ufw status | head -8

step "2/5  fail2ban (block password guessers)"
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

step "3/5  Automatic security updates"
apt-get install -y -qq unattended-upgrades >/dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades >/dev/null
echo "on"

step "4/5  Hide nginx version"
if ! grep -qE '^\s*server_tokens\s+off;' /etc/nginx/nginx.conf; then
  sed -i 's/^\(\s*\)#\?\s*server_tokens.*/\1server_tokens off;/' /etc/nginx/nginx.conf
  grep -qE '^\s*server_tokens\s+off;' /etc/nginx/nginx.conf || \
    sed -i 's/^\(\s*\)http\s*{/&\n\1    server_tokens off;/' /etc/nginx/nginx.conf
fi
nginx -t && systemctl reload nginx

step "5/5  SSH login"
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

echo; echo "✅ Server hardening done."

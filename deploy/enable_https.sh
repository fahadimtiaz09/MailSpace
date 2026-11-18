#!/usr/bin/env bash
# enable_https.sh — free HTTPS certificate (Let's Encrypt) for domailit.com.
# Run AFTER Namecheap's A record points to this server.  Renews automatically.
set -euo pipefail
DOMAIN="domailit.com"
read -r -p "Your email (for certificate expiry notices): " EMAIL
certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --redirect --agree-tos -m "$EMAIL" -n
systemctl reload nginx
echo "✅ HTTPS is on: https://$DOMAIN"
echo "Auto-renewal test:"; certbot renew --dry-run

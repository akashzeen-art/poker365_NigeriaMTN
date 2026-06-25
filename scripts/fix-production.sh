#!/bin/bash
# Run on the production server as root:
#   cd /var/www/vaszeen/aigamopedia/poker365_MTNNigeria && bash scripts/fix-production.sh

set -e
APP_DIR="/var/www/vaszeen/aigamopedia/poker365_MTNNigeria"
APP_NAME="aigamopedia-mtn-nigeria"
PORT=5500

echo "=== Poker365 production fix ==="
echo "App dir: $APP_DIR"
echo ""

cd "$APP_DIR"

echo "--- Node / npm ---"
node -v || { echo "ERROR: Node.js not installed. Run: curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt install -y nodejs"; exit 1; }
npm -v || true

echo ""
echo "--- Git pull ---"
git pull origin main || echo "WARN: git pull failed (check remote/credentials)"

echo ""
echo "--- npm install ---"
npm install --production

echo ""
echo "--- Stop old process ---"
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete "$APP_NAME" 2>/dev/null || true
else
  echo "PM2 not found, installing..."
  npm install -g pm2
fi

# Kill anything else on the port
if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
  echo "WARN: Port $PORT already in use:"
  ss -tlnp | grep ":$PORT " || true
  fuser -k "${PORT}/tcp" 2>/dev/null || true
  sleep 1
fi

echo ""
echo "--- Start app ---"
if [ -f ecosystem.config.js ]; then
  pm2 start ecosystem.config.js
else
  PORT=$PORT pm2 start server.js --name "$APP_NAME"
fi
pm2 save
pm2 startup systemd -u root --hp /root 2>/dev/null || true

echo ""
echo "--- Local health check ---"
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${PORT}/" || echo "000")
echo "curl http://127.0.0.1:${PORT}/ => HTTP $HTTP_CODE"

if [ "$HTTP_CODE" != "200" ]; then
  echo ""
  echo "ERROR: Node app not responding. PM2 logs:"
  pm2 logs "$APP_NAME" --lines 40 --nostream
  exit 1
fi

echo ""
echo "--- Nginx config for poker365.world ---"
NGINX_CONF=$(grep -rl "poker365" /etc/nginx/sites-enabled/ 2>/dev/null | head -1)
if [ -z "$NGINX_CONF" ]; then
  echo "WARN: No nginx config found for poker365. Create one (see DEPLOYMENT.md)."
else
  echo "Found: $NGINX_CONF"
  grep -E "proxy_pass|listen|server_name" "$NGINX_CONF" || true
  if ! grep -q "127.0.0.1:${PORT}" "$NGINX_CONF" && ! grep -q "localhost:${PORT}" "$NGINX_CONF"; then
    echo ""
    echo "WARN: nginx may proxy to wrong port. It should use: proxy_pass http://127.0.0.1:${PORT};"
  fi
fi

echo ""
echo "=== Done. App is running on port $PORT ==="
echo "Test: curl -I http://127.0.0.1:${PORT}/"
echo "Then open https://poker365.world/ in browser."

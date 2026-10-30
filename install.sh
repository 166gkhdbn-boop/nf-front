#!/usr/bin/env bash
# nf-front quick install (Ubuntu/Debian, run as root).
# Installs Node.js 20 + Caddy, runs server.js as a systemd service on
# localhost, and puts Caddy on 443 with automatic HTTPS for your domain.
# The VLESS UUID and backend are passed on the command line and are NEVER
# written into this repo; they only appear in the printed link.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/166gkhdbn-boop/nf-front/main/install.sh \
#     | bash -s -- --domain YOURDOMAIN --backend BACKENDHOST:PORT --uuid YOUR-VLESS-UUID
#
# Requirements: a domain whose DNS A record already points at this server,
# and ports 80 + 443 reachable (Caddy needs port 80 for Let's Encrypt).
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/166gkhdbn-boop/nf-front/main"
DOMAIN=""
BACKEND=""
UUID=""
FRONT_PATH="/nf-953693fb/"
NODE_PORT="8080"

usage() {
  echo "Usage: install.sh --domain DOMAIN --backend HOST:PORT --uuid VLESS-UUID [--path /nf-953693fb/] [--port 8080]"
  echo "Example: install.sh --domain front.example.com --backend 203.0.113.10:444 --uuid 00000000-0000-0000-0000-000000000000"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --domain)  DOMAIN="$2"; shift 2 ;;
    --backend) BACKEND="$2"; shift 2 ;;
    --uuid)    UUID="$2"; shift 2 ;;
    --path)    FRONT_PATH="$2"; shift 2 ;;
    --port)    NODE_PORT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

[ -n "$DOMAIN" ] && [ -n "$BACKEND" ] && [ -n "$UUID" ] || usage
if [ "$(id -u)" -ne 0 ]; then echo "Run as root."; exit 1; fi
case "$FRONT_PATH" in /*/) ;; *) echo "--path must start and end with /"; exit 1 ;; esac

echo "==> Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https > /dev/null

if ! command -v node > /dev/null 2>&1; then
  echo "==> Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
  apt-get install -y -qq nodejs > /dev/null
fi
NODE_BIN="$(command -v node)"
echo "==> Node: $($NODE_BIN --version)"

if ! command -v caddy > /dev/null 2>&1; then
  echo "==> Installing Caddy..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
  apt-get update -qq
  apt-get install -y -qq caddy > /dev/null
fi
echo "==> Caddy: $(caddy version)"

echo "==> Installing nf-front to /opt/nf-front..."
mkdir -p /opt/nf-front
curl -fsSL "$REPO_RAW/server.js" -o /opt/nf-front/server.js
chmod 644 /opt/nf-front/server.js
chmod 755 /opt/nf-front

cat > /etc/systemd/system/nf-front.service <<EOF
[Unit]
Description=nf-front XHTTP front
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
Environment=PORT=$NODE_PORT
Environment=FRONT_PATH=$FRONT_PATH
ExecStart=$NODE_BIN /opt/nf-front/server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

if [ -f /etc/caddy/Caddyfile ] && ! grep -q "nf-front" /etc/caddy/Caddyfile 2>/dev/null; then
  cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%s)"
fi
cat > /etc/caddy/Caddyfile <<EOF
# nf-front (managed by nf-front install.sh)
$DOMAIN {
  reverse_proxy 127.0.0.1:$NODE_PORT
}
EOF

if command -v ufw > /dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp > /dev/null 2>&1 || true
  ufw allow 443/tcp > /dev/null 2>&1 || true
fi

echo "==> Starting services..."
systemctl daemon-reload
systemctl enable --now nf-front
systemctl enable caddy > /dev/null 2>&1 || true
systemctl reload caddy || systemctl restart caddy
sleep 2

echo "==> Verifying (local front should answer 404)..."
if curl -fsS -o /dev/null "http://127.0.0.1:$NODE_PORT/" 2>/dev/null; then
  echo "Local front: OK (unexpected, root should 404)"
else
  echo "Local front: responds (root is 404 by design, see below)"
fi
curl -s -o /dev/null -w "Public https://%{http_code}\n" "https://$DOMAIN/" || echo "Public check failed: is DNS for $DOMAIN pointing at this server yet? (Caddy gets its certificate once DNS resolves.)"

TRIMMED="${FRONT_PATH#/}"
TRIMMED="${TRIMMED%/}"
PATH_ENC="%2F${TRIMMED}%2F"
BACKEND_ENC="${BACKEND//:/\%3A}"
LINK="vless://$UUID@$DOMAIN:443?mode=auto&path=$PATH_ENC&security=tls&alpn=h2%2Chttp%2F1.1&encryption=none&extra=%7B%22xPaddingBytes%22%3A%221-1%22%2C%22xPaddingObfsMode%22%3Atrue%2C%22scMaxEachPostBytes%22%3A%221000000%22%2C%22xPaddingKey%22%3A%22iran%22%2C%22xPaddingHeader%22%3A%22iran%22%2C%22headers%22%3A%7B%22x-host%22%3A%22$BACKEND_ENC%22%7D%7D&insecure=0&host=$DOMAIN&fp=chrome&type=xhttp&allowInsecure=0&sni=$DOMAIN#nf-front"

echo ""
echo "==> Done. Your config link:"
echo "$LINK"
echo ""
echo "Quick checks:"
echo "  curl https://$DOMAIN${FRONT_PATH}                                   # expect: Missing x-host"
echo "  curl https://$DOMAIN${FRONT_PATH} -H 'x-host: $BACKEND'            # expect: backend's own 400"
echo "Manage: systemctl status nf-front | journalctl -u nf-front -f"

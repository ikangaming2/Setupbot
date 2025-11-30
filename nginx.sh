#!/usr/bin/env bash
set -euo pipefail

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Harus dijalankan sebagai root (sudo)." >&2
    exit 1
  fi
}

mask_ip_for_log() {
  local ip="$1"
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "xxx.xxx.xxx.${ip##*.}"
  else
    echo "[censored]"
  fi
}

prepare_paths() {
  NGINX_AVAIL="/etc/nginx/sites-available"
  NGINX_ENABLED="/etc/nginx/sites-enabled"
  WEBROOT="/var/www/${DOMAIN}"

  CONF_PATH="${NGINX_AVAIL}/${DOMAIN}"
  ENABLED_LINK="${NGINX_ENABLED}/${DOMAIN}"
}

create_webroot() {
  mkdir -p "$WEBROOT"
  chown -R www-data:www-data "$WEBROOT"
  chmod 0755 "$WEBROOT"
}

generate_nginx_conf() {
  cat > "$CONF_PATH" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${WEBROOT};
        default_type "text/plain";
    }

    location / {
        proxy_pass http://${UPSTREAM_IP}:${UPSTREAM_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy no-referrer-when-downgrade always;
}
EOF
}

enable_site() {
  ln -sf "$CONF_PATH" "$ENABLED_LINK"
  nginx -t
  systemctl reload nginx
}

issue_certificate() {
  certbot --nginx \
    -d "$DOMAIN" \
    -m "$EMAIL" \
    --agree-tos \
    --non-interactive \
    --redirect
  systemctl reload nginx
}

show_summary() {
  local masked_ip
  masked_ip="$(mask_ip_for_log "$UPSTREAM_IP")"
  echo "Selesai:"
  echo "  Domain      : ${DOMAIN}"
  echo "  Upstream    : ${masked_ip}:${UPSTREAM_PORT}"
  echo "  Webroot     : ${WEBROOT}"
  echo "  Konfigurasi : ${CONF_PATH}"
  echo "  Enabled     : ${ENABLED_LINK}"
}

main() {
  require_root

  # Input interaktif
  read -rp "Masukkan domain: " DOMAIN
  read -rp "Masukkan IP privat upstream: " UPSTREAM_IP
  read -rp "Masukkan port upstream: " UPSTREAM_PORT
  read -rp "Masukkan email untuk Certbot: " EMAIL

  prepare_paths
  create_webroot
  generate_nginx_conf
  enable_site
  issue_certificate
  show_summary
}

main

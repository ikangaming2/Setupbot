#!/bin/bash

# --- Fungsi pendukung minimal ---
detect_iface() {
  # ambil interface default dari route
  ip route | awk '/default/ {print $5; exit}'
}

detect_public_ip() {
  # ambil IP publik dari layanan eksternal
  curl -s ifconfig.me
}

log_action() {
  echo "$(date '+%F %T') $1" >> /var/log/portsetup.log
}

find_random_free_port() {
  local START=$1
  local END=$2
  while :; do
    local PORT=$((RANDOM % (END-START+1) + START))
    if ! ss -ltn | awk '{print $4}' | grep -q ":$PORT$"; then
      echo $PORT
      return
    fi
  done
}

save_rules() {
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save &>/dev/null
    log_action "netfilter-persistent save"
  fi
}

# --- Variabel utama ---
DB_FILE="/etc/portsetup.db"
RANGE_NORMAL_START=40000
RANGE_NORMAL_END=40100
RANGE_MC_START=41000
RANGE_MC_END=41100

IFACE=$(detect_iface)
PUBLIC_IP=$(detect_public_ip)
TARGET_IP="$1"

# --- Validasi argumen ---
if [ -z "$TARGET_IP" ]; then
  echo "Usage: $0 <IP-privat>"
  exit 1
fi

# Validasi format IPv4
if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Format IP tidak valid"
  exit 1
fi

# Validasi apakah IP termasuk privat
if [[ "$TARGET_IP" =~ ^10\. ]] || \
   [[ "$TARGET_IP" =~ ^192\.168\. ]] || \
   ([[ "$TARGET_IP" =~ ^172\. ]] && \
    [[ "$(echo "$TARGET_IP" | cut -d. -f2)" -ge 16 ]] && \
    [[ "$(echo "$TARGET_IP" | cut -d. -f2)" -le 31 ]]); then
  echo "IP privat valid: $TARGET_IP"
else
  echo "IP bukan privat, keluar."
  exit 1
fi

# --- Port forwarding ---
PORTS_NORMAL=(22 3000 3300 4000 5000 5173 5432 6379 8000 8080 8800 8888 3030)
PORT_MC=25565

echo "Interface: $IFACE | IP Publik: $PUBLIC_IP"

for TARGET_PORT in "${PORTS_NORMAL[@]}"; do
  FREE_PORT=$(find_random_free_port $RANGE_NORMAL_START $RANGE_NORMAL_END)
  [ -z "$FREE_PORT" ] && continue
  if grep -q "$TARGET_IP,$TARGET_PORT" "$DB_FILE" 2>/dev/null; then continue; fi

  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

  echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$TARGET_PORT,$IFACE" >> "$DB_FILE"
  log_action "ADD $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT"
  echo "$PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT"
done

FREE_PORT=$(find_random_free_port $RANGE_MC_START $RANGE_MC_END)
if [ -n "$FREE_PORT" ]; then
  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$PORT_MC"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PORT_MC" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PORT_MC" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

  echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$PORT_MC,$IFACE" >> "$DB_FILE"
  log_action "ADD $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$PORT_MC"
  echo "$PUBLIC_IP:$FREE_PORT → $TARGET_IP:$PORT_MC"
fi

save_rules

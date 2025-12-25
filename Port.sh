#!/bin/bash

# ================================
#  NAT PORT FORWARDING ANTI NABRAK
# ================================

detect_iface() {
  ip route | awk '/default/ {print $5; exit}'
}

detect_public_ip() {
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

    # Cek kalau port sudah dipakai service
    if ss -ltn | awk '{print $4}' | grep -q ":$PORT$"; then
      continue
    fi
    
    # Cek kalau port sudah ada di NAT rules
    if iptables -t nat -L PREROUTING -n | grep -q ":$PORT "; then
      continue
    fi
    
    # Cek kalau sudah tercatat di DB
    if grep -q ",$PORT," "$DB_FILE" 2>/dev/null; then
      continue
    fi

    echo $PORT
    return
  done
}

save_rules() {
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save &>/dev/null
    log_action "netfilter-persistent save"
  fi
}

# ================================
# VAR
# ================================
DB_FILE="/etc/portsetup.db"
RANGE_NORMAL_START=1000
RANGE_NORMAL_END=2500
RANGE_MC_START=10000
RANGE_MC_END=10500

IFACE=$(detect_iface)
PUBLIC_IP=$(detect_public_ip)
TARGET_IP="$1"

# ================================
# VALIDASI
# ================================
if [ -z "$TARGET_IP" ]; then
  echo "Usage: $0 <IP-privat>"
  exit 1
fi

if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}.){3}[0-9]{1,3}$ ]]; then
  echo "Format IP tidak valid"
  exit 1
fi

if [[ "$TARGET_IP" =~ ^10. ]] || \
   [[ "$TARGET_IP" =~ ^192.168. ]] || \
   ([[ "$TARGET_IP" =~ ^172. ]] && \
    [[ "$(echo "$TARGET_IP" | cut -d. -f2)" -ge 16 ]] && \
    [[ "$(echo "$TARGET_IP" | cut -d. -f2)" -le 31 ]]); then
  echo "IP privat valid: $TARGET_IP"
else
  echo "IP bukan privat, keluar."
  exit 1
fi

PORTS_NORMAL=(22 3000 3300 4000 5000 5173 5432 6379 8000 8080 8800 8888 3030)
PORT_MC=25565

echo "Interface: $IFACE | IP Publik: $PUBLIC_IP"

touch "$DB_FILE"

# ================================
# PORT NORMAL
# ================================
for TARGET_PORT in "${PORTS_NORMAL[@]}"; do
  # Cek apakah mapping IP+TARGET_PORT sudah ada di DB
  # Format: PUBLIC_IP,FREE_PORT,TARGET_IP,TARGET_PORT,IFACE
  EXIST_LINE=$(grep ",$TARGET_IP,$TARGET_PORT," "$DB_FILE" 2>/dev/null | head -n1)
  if [ -n "$EXIST_LINE" ]; then
    # Sudah ada, tinggal echo mapping yang lama
    EXIST_FREE_PORT=$(echo "$EXIST_LINE" | cut -d',' -f2)
    echo "$PUBLIC_IP:$EXIST_FREE_PORT → $TARGET_IP:$TARGET_PORT (existing)"
    continue
  fi

  # Kalau belum ada, baru cari FREE_PORT baru
  FREE_PORT=$(find_random_free_port $RANGE_NORMAL_START $RANGE_NORMAL_END)
  [ -z "$FREE_PORT" ] && continue

  # Tambah rule NAT & FORWARD
  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

  echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$TARGET_PORT,$IFACE" >> "$DB_FILE"
  log_action "ADD $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT"
  echo "$PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT (new)"
done

# ================================
# MINECRAFT PORT
# ================================
# Cek dulu kalau mapping MC sudah ada
EXIST_LINE_MC=$(grep ",$TARGET_IP,$PORT_MC," "$DB_FILE" 2>/dev/null | head -n1)
if [ -n "$EXIST_LINE_MC" ]; then
  EXIST_FREE_PORT_MC=$(echo "$EXIST_LINE_MC" | cut -d',' -f2)
  echo "$PUBLIC_IP:$EXIST_FREE_PORT_MC → $TARGET_IP:$PORT_MC (existing)"
else
  FREE_PORT=$(find_random_free_port $RANGE_MC_START $RANGE_MC_END)
  if [ -n "$FREE_PORT" ]; then
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$PORT_MC"
    iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PORT_MC" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PORT_MC" -j ACCEPT
    iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

    echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$PORT_MC,$IFACE" >> "$DB_FILE"
    log_action "ADD $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$PORT_MC"
    echo "$PUBLIC_IP:$FREE_PORT → $TARGET_IP:$PORT_MC (new)"
  fi
fi

save_rules

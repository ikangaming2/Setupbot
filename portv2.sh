#!/bin/bash

IFACE="ens3"
RANGE_NORMAL_START=2000
RANGE_NORMAL_END=5000
RANGE_MC_START=20000       # Khusus Minecraft → publik 5 digit
RANGE_MC_END=50000
DB_FILE="/var/lib/portfw.db"
mkdir -p "$(dirname "$DB_FILE")"
touch "$DB_FILE"

find_random_free_port() {
  local start=$1
  local end=$2
  shuf -i "$start"-"$end" | while read port; do
    ss -ltn | awk '{print $4}' | grep -q ":$port" || { echo "$port"; return 0; }
  done
  return 1
}

show_mapping() {
  echo "=== Daftar Port Forwarding Aktif ==="
  printf "%-18s %-10s %-10s\n" "TARGET_IP" "PUBLIC" "PRIVATE"
  grep -v '^#' "$DB_FILE" | while read line; do
    IFS="," read -r ip pub pri <<< "$line"
    printf "%-18s %-10s %-10s\n" "$ip" "$pub" "$pri"
  done
}

add_auto() {
  read -p "Masukkan IP tujuan (contoh: 192.168.11.21): " TARGET_IP
  if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "❌ Format IP tidak valid."; return
  fi

  # Daftar port private populer (service normal)
  PORTS_NORMAL=(
    22 3000 3300 4000 5000 5173 5432 6379
    8000 8080 8800 8888 3030
  )
  # Port Minecraft
  PORT_MC=25565

  echo "=== Membuat aturan port forwarding untuk $TARGET_IP ==="

  # Service normal → publik 4 digit (2000–5000)
  for TARGET_PORT in "${PORTS_NORMAL[@]}"; do
    FREE_PORT=$(find_random_free_port $RANGE_NORMAL_START $RANGE_NORMAL_END)
    [ -z "$FREE_PORT" ] && { echo "❌ Tidak ada port kosong (normal)."; continue; }
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" \
      -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
    iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT
    iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE
    echo "$TARGET_IP,$FREE_PORT,$TARGET_PORT" >> "$DB_FILE"
    echo "✅ $FREE_PORT → $TARGET_IP:$TARGET_PORT"
  done

  # Minecraft → publik 5 digit (20000–50000)
  FREE_PORT=$(find_random_free_port $RANGE_MC_START $RANGE_MC_END)
  if [ -n "$FREE_PORT" ]; then
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" \
      -j DNAT --to-destination "$TARGET_IP:$PORT_MC"
    iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PORT_MC" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PORT_MC" -j ACCEPT
    iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE
    echo "$TARGET_IP,$FREE_PORT,$PORT_MC" >> "$DB_FILE"
    echo "✅ (Minecraft) $FREE_PORT → $TARGET_IP:$PORT_MC"
  else
    echo "❌ Tidak ada port kosong untuk Minecraft."
  fi
}

add_manual() {
  read -p "IP tujuan: " TARGET_IP
  read -p "Port publik: " PUB
  read -p "Port privat: " PRI
  if [[ -z "$TARGET_IP" || -z "$PUB" || -z "$PRI" ]]; then
    echo "❌ Data tidak lengkap."; return
  fi
  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$PUB" \
    -j DNAT --to-destination "$TARGET_IP:$PRI"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PRI" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PRI" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE
  echo "$TARGET_IP,$PUB,$PRI" >> "$DB_FILE"
  echo "✅ Manual $PUB → $TARGET_IP:$PRI"
}

list_ip() {
  echo "=== Daftar IP Tercatat ==="
  cut -d',' -f1 "$DB_FILE" | sort -u
}

menu() {
  echo "----------------------------"
  echo " Port Forwarding Manager"
  echo "----------------------------"
  echo "1) Tambah otomatis (IP + port preset)"
  echo "2) Tambah manual (IP + port custom)"
  echo "3) Lihat semua mapping port"
  echo "4) List IP yang tersimpan"
  echo "5) Keluar"
  echo "----------------------------"
  read -p "Pilih menu [1-5]: " choice
  case $choice in
    1) add_auto ;;
    2) add_manual ;;
    3) show_mapping ;;
    4) list_ip ;;
    5) exit 0 ;;
    *) echo "Pilihan tidak valid." ;;
  esac
}

while true; do
  menu
done

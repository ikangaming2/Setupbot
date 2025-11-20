#!/bin/bash

DB_FILE="/var/lib/portfw.db"
LOG_FILE="/var/log/portfw.log"
RANGE_NORMAL_START=2000
RANGE_NORMAL_END=5000
RANGE_MC_START=20000
RANGE_MC_END=50000

mkdir -p "$(dirname "$DB_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$DB_FILE" "$LOG_FILE"

detect_iface() { ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}'; }
detect_public_ip() {
  curl -4 -s https://ifconfig.me || curl -4 -s https://api.ipify.org
}
find_random_free_port() {
  local start=$1
  local end=$2
  shuf -i "$start"-"$end" | while read port; do
    ss -ltn | awk '{print $4}' | grep -q ":$port" || { echo "$port"; return 0; }
  done
}

log_action() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOG_FILE"
}

save_rules() {
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save &>/dev/null
    log_action "netfilter-persistent save"
  fi
}

restore_from_db() {
  while read line; do
    [ -z "$line" ] && continue
    IFS="," read -r pub_ip pub_port priv_ip priv_port iface <<< "$line"
    iptables -t nat -A PREROUTING -i "$iface" -p tcp --dport "$pub_port" -j DNAT --to-destination "$priv_ip:$priv_port"
    iptables -A FORWARD -p tcp -d "$priv_ip" --dport "$priv_port" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$priv_ip" --sport "$priv_port" -j ACCEPT
    iptables -t nat -A POSTROUTING -s "$priv_ip" -o "$iface" -j MASQUERADE
  done < "$DB_FILE"
  save_rules
}

show_mapping() {
  echo "=== Daftar Port Forwarding Aktif ==="
  printf "%-22s %-22s %-18s\n" "PUB_ADDR:PORT" "PRIV_ADDR:PORT" "INTERFACE"
  echo "-----------------------------------------------------------------------"
  grep -v '^#' "$DB_FILE" | while read line; do
    IFS="," read -r pub_ip pub_port priv_ip priv_port iface <<< "$line"
    printf "%-22s %-22s %-18s\n" "$pub_ip:$pub_port" "$priv_ip:$priv_port" "$iface"
  done
}

list_ip() {
  echo "=== Daftar IP Privat Tersimpan ==="
  cut -d',' -f3 "$DB_FILE" | sort -u
}

show_port_per_ip() {
  list_ip
  echo "-------------------------------------------"
  read -p "Masukkan IP privat dari daftar di atas: " TARGET_IP
  if ! grep -q "$TARGET_IP" "$DB_FILE"; then
    echo "IP tidak ditemukan."
    return
  fi
  echo "=== Daftar Port untuk $TARGET_IP ==="
  printf "%-22s %-22s %-18s\n" "PUB_ADDR:PORT" "PRIV_ADDR:PORT" "INTERFACE"
  echo "-----------------------------------------------------------------------"
  grep "$TARGET_IP" "$DB_FILE" | while read line; do
    IFS="," read -r pub_ip pub_port priv_ip priv_port iface <<< "$line"
    printf "%-22s %-22s %-18s\n" "$pub_ip:$pub_port" "$priv_ip:$priv_port" "$iface"
  done
}

add_auto() {
  IFACE=$(detect_iface)
  PUBLIC_IP=$(detect_public_ip)
  echo "Interface: $IFACE | IP Publik: $PUBLIC_IP"
  read -p "Masukkan IP privat tujuan: " TARGET_IP
  if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return; fi
  PORTS_NORMAL=(22 3000 3300 4000 5000 5173 5432 6379 8000 8080 8800 8888 3030)
  PORT_MC=25565
  for TARGET_PORT in "${PORTS_NORMAL[@]}"; do
    FREE_PORT=$(find_random_free_port $RANGE_NORMAL_START $RANGE_NORMAL_END)
    [ -z "$FREE_PORT" ] && continue
    if grep -q "$TARGET_IP,$TARGET_PORT" "$DB_FILE"; then continue; fi
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
  fi
  save_rules
}

add_manual() {
  IFACE=$(detect_iface)
  PUBLIC_IP=$(detect_public_ip)
  echo "Interface: $IFACE | IP Publik: $PUBLIC_IP"
  read -p "IP privat: " TARGET_IP
  read -p "Port publik: " PUB
  read -p "Port privat: " PRI
  if grep -q "$PUBLIC_IP,$PUB,$TARGET_IP,$PRI" "$DB_FILE"; then return; fi
  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$PUB" -j DNAT --to-destination "$TARGET_IP:$PRI"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PRI" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PRI" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE
  echo "$PUBLIC_IP,$PUB,$TARGET_IP,$PRI,$IFACE" >> "$DB_FILE"
  log_action "ADD $PUBLIC_IP:$PUB → $TARGET_IP:$PRI"
  echo "$PUBLIC_IP:$PUB → $TARGET_IP:$PRI"
  save_rules
}

delete_ip() {
  read -p "Masukkan IP privat yang ingin dihapus: " TARGET_IP
  if ! grep -q "$TARGET_IP" "$DB_FILE"; then return; fi
  grep "$TARGET_IP" "$DB_FILE" | while read line; do
    IFS="," read -r pub_ip pub_port priv_ip priv_port iface <<< "$line"
    iptables -t nat -D PREROUTING -i "$iface" -p tcp --dport "$pub_port" -j DNAT --to-destination "$priv_ip:$priv_port" 2>/dev/null
    iptables -D FORWARD -p tcp -d "$priv_ip" --dport "$priv_port" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -p tcp -s "$priv_ip" --sport "$priv_port" -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -s "$priv_ip" -o "$iface" -j MASQUERADE 2>/dev/null
    log_action "DEL $pub_ip:$pub_port → $priv_ip:$priv_port"
  done
  sed -i "/$TARGET_IP/d" "$DB_FILE"
  save_rules
}

menu() {
  echo "-------------------------------------------"
  echo " Port Forwarding Manager"
  echo "-------------------------------------------"
  echo "1) Tambah otomatis"
  echo "2) Tambah manual"
  echo "3) Lihat semua mapping"
  echo "4) Lihat port per IP"
  echo "5) Hapus aturan IP"
  echo "6) Reload database"
  echo "7) Keluar"
  echo "-------------------------------------------"
  read -p "Pilih menu [1-7]: " choice
  case $choice in
    1) add_auto ;;
    2) add_manual ;;
    3) show_mapping ;;
    4) show_port_per_ip ;;
    5) delete_ip ;;
    6) restore_from_db ;;
    7) exit 0 ;;
  esac
}

if [ -s "$DB_FILE" ]; then
  restore_from_db
fi

while true; do
  menu
done

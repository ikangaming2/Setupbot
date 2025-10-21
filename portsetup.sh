#!/bin/bash
# ============================================================
# ⚙️  Port Forwarding Manager by Nauval v4
# ============================================================

DB_FILE="/var/lib/portfw.db"
RANGE_NORMAL_START=2000
RANGE_NORMAL_END=5000
RANGE_MC_START=20000
RANGE_MC_END=50000

mkdir -p "$(dirname "$DB_FILE")"
touch "$DB_FILE"

# ============================================================
# 🔹 Auto deteksi interface publik
# ============================================================
detect_iface() {
  ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}'
}

# ============================================================
# 🔹 Dapatkan IP publik eksternal
# ============================================================
detect_public_ip() {
  curl -s https://ifconfig.me || curl -s https://api.ipify.org
}

# ============================================================
# 🔹 Cari port kosong
# ============================================================
find_random_free_port() {
  local start=$1
  local end=$2
  shuf -i "$start"-"$end" | while read port; do
    ss -ltn | awk '{print $4}' | grep -q ":$port" || { echo "$port"; return 0; }
  done
  return 1
}

# ============================================================
# 🔹 Tampilkan semua mapping
# ============================================================
show_mapping() {
  echo "=== Daftar Port Forwarding Aktif ==="
  printf "%-22s %-22s %-18s\n" "PUB_ADDR:PORT" "PRIV_ADDR:PORT" "INTERFACE"
  echo "-----------------------------------------------------------------------"
  grep -v '^#' "$DB_FILE" | while read line; do
    IFS="," read -r pub_ip pub_port priv_ip priv_port iface <<< "$line"
    printf "%-22s %-22s %-18s\n" "$pub_ip:$pub_port" "$priv_ip:$priv_port" "$iface"
  done
}

# ============================================================
# 🔹 Tambah otomatis (preset)
# ============================================================
add_auto() {
  IFACE=$(detect_iface)
  PUBLIC_IP=$(detect_public_ip)

  echo "Interface terdeteksi: $IFACE"
  echo "IP Publik: $PUBLIC_IP"
  read -p "Masukkan IP privat tujuan (contoh: 192.168.11.21): " TARGET_IP

  if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "❌ Format IP tidak valid."; return
  fi

  PORTS_NORMAL=(22 3000 3300 4000 5000 5173 5432 6379 8000 8080 8800 8888 3030)
  PORT_MC=25565

  echo "=== Membuat aturan port forwarding untuk $TARGET_IP ==="

  for TARGET_PORT in "${PORTS_NORMAL[@]}"; do
    FREE_PORT=$(find_random_free_port $RANGE_NORMAL_START $RANGE_NORMAL_END)
    [ -z "$FREE_PORT" ] && { echo "❌ Tidak ada port kosong."; continue; }

    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
    iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT
    iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

    echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$TARGET_PORT,$IFACE" >> "$DB_FILE"
    echo "✅ $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$TARGET_PORT"
  done

  FREE_PORT=$(find_random_free_port $RANGE_MC_START $RANGE_MC_END)
  if [ -n "$FREE_PORT" ]; then
    iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$PORT_MC"
    iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PORT_MC" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PORT_MC" -j ACCEPT
    iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE
    echo "$PUBLIC_IP,$FREE_PORT,$TARGET_IP,$PORT_MC,$IFACE" >> "$DB_FILE"
    echo "✅ (Minecraft) $PUBLIC_IP:$FREE_PORT → $TARGET_IP:$PORT_MC"
  fi
}

# ============================================================
# 🔹 Tambah manual
# ============================================================
add_manual() {
  IFACE=$(detect_iface)
  PUBLIC_IP=$(detect_public_ip)

  echo "Interface terdeteksi: $IFACE"
  echo "IP Publik: $PUBLIC_IP"
  read -p "IP privat: " TARGET_IP
  read -p "Port publik: " PUB
  read -p "Port privat: " PRI

  if [[ -z "$TARGET_IP" || -z "$PUB" || -z "$PRI" ]]; then
    echo "❌ Data tidak lengkap."; return
  fi

  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$PUB" -j DNAT --to-destination "$TARGET_IP:$PRI"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$PRI" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$PRI" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

  echo "$PUBLIC_IP,$PUB,$TARGET_IP,$PRI,$IFACE" >> "$DB_FILE"
  echo "✅ Manual $PUBLIC_IP:$PUB → $TARGET_IP:$PRI"
}

# ============================================================
# 🔹 List IP unik
# ============================================================
list_ip() {
  echo "=== Daftar IP Privat Tercatat ==="
  cut -d',' -f3 "$DB_FILE" | sort -u
}

# ============================================================
# 🔹 Lihat port per IP privat
# ============================================================
show_port_per_ip() {
  list_ip
  echo "---------------------------------------------"
  read -p "Masukkan IP privat yang ingin dilihat: " TARGET_IP
  if ! grep -q "$TARGET_IP" "$DB_FILE"; then
    echo "❌ IP tidak ditemukan di database."
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

# ============================================================
# 🔹 Hapus semua aturan untuk IP privat
# ============================================================
delete_ip() {
  list_ip
  echo "---------------------------------------------"
  read -p "Masukkan IP privat yang ingin dihapus: " TARGET_IP
  if ! grep -q "$TARGET_IP" "$DB_FILE"; then
    echo "❌ IP tidak ditemukan di database."
    return
  fi

  echo "🧹 Menghapus semua aturan untuk $TARGET_IP..."
  grep "$TARGET_IP" "$DB_FILE" | while read line; do
    IFS="," read -r pub_ip pub_port priv_ip priv_port iface <<< "$line"
    iptables -t nat -D PREROUTING -i "$iface" -p tcp --dport "$pub_port" -j DNAT --to-destination "$priv_ip:$priv_port" 2>/dev/null
    iptables -D FORWARD -p tcp -d "$priv_ip" --dport "$priv_port" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -p tcp -s "$priv_ip" --sport "$priv_port" -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -s "$priv_ip" -o "$iface" -j MASQUERADE 2>/dev/null
    echo "❌ Hapus: $pub_ip:$pub_port → $priv_ip:$priv_port"
  done

  sed -i "/$TARGET_IP/d" "$DB_FILE"
  echo "✅ Semua aturan untuk $TARGET_IP telah dihapus."
}

# ============================================================
# 🔹 Menu utama
# ============================================================
menu() {
  echo "-------------------------------------------"
  echo " 🌐 Port Forwarding Manager by Nauval v4"
  echo "-------------------------------------------"
  echo "1) Tambah otomatis (preset framework + MC)"
  echo "2) Tambah manual (custom port)"
  echo "3) Lihat semua mapping port"
  echo "4) List IP privat tersimpan"
  echo "5) Lihat port per IP privat"
  echo "6) Hapus semua aturan dari IP privat"
  echo "7) Keluar"
  echo "-------------------------------------------"
  read -p "Pilih menu [1-7]: " choice
  case $choice in
    1) add_auto ;;
    2) add_manual ;;
    3) show_mapping ;;
    4) list_ip ;;
    5) show_port_per_ip ;;
    6) delete_ip ;;
    7) exit 0 ;;
    *) echo "Pilihan tidak valid." ;;
  esac
}

while true; do
  menu
done

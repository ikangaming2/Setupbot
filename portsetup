#!/bin/bash

# Konfigurasi
IFACE="ens3"
TARGET_PORT="22"
PORT_RANGE_START=2000
PORT_RANGE_END=5000

# Input IP target
read -p "Masukkan IP tujuan (contoh: 192.168.11.21): " TARGET_IP

# Validasi IP sederhana
if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Format IP tidak valid."
  exit 1
fi

# Cari port kosong
find_free_port() {
  for ((port=PORT_RANGE_START; port<=PORT_RANGE_END; port++)); do
    ss -ltn | awk '{print $4}' | grep -q ":$port" || {
      echo "$port"
      return 0
    }
  done
  return 1
}

FREE_PORT=$(find_free_port)
if [ -z "$FREE_PORT" ]; then
  echo "Tidak ada port kosong tersedia dalam rentang $PORT_RANGE_START-$PORT_RANGE_END"
  exit 1
fi

# Tambahkan aturan iptables
iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT
iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

echo "Port publik: $FREE_PORT diarahkan ke $TARGET_IP:$TARGET_PORT"

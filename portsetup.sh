#!/bin/bash

IFACE="ens3"
PORT_RANGE_START=2000
PORT_RANGE_END=5000

read -p "Masukkan IP tujuan (contoh: 192.168.11.21): " TARGET_IP

# Validasi IP sederhana
if ! [[ "$TARGET_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  echo "Format IP tidak valid."
  exit 1
fi

# Fungsi cari port kosong
find_random_free_port() {
  shuf -i "$PORT_RANGE_START"-"$PORT_RANGE_END" | while read port; do
    ss -ltn | awk '{print $4}' | grep -q ":$port" || {
      echo "$port"
      return 0
    }
  done
  return 1
}

# Daftar port tujuan (di dalam VM/LXC)
PORTS=(22 3000 8000 3300 8800 3030 4000)

echo "=== Membuat aturan port forwarding untuk $TARGET_IP ==="

for TARGET_PORT in "${PORTS[@]}"; do
  FREE_PORT=$(find_random_free_port)
  if [ -z "$FREE_PORT" ]; then
    echo "❌ Tidak ada port kosong tersedia dalam rentang $PORT_RANGE_START-$PORT_RANGE_END"
    continue
  fi

  # Tambahkan aturan iptables
  iptables -t nat -A PREROUTING -i "$IFACE" -p tcp --dport "$FREE_PORT" -j DNAT --to-destination "$TARGET_IP:$TARGET_PORT"
  iptables -A FORWARD -p tcp -d "$TARGET_IP" --dport "$TARGET_PORT" -j ACCEPT
  iptables -A FORWARD -p tcp -s "$TARGET_IP" --sport "$TARGET_PORT" -j ACCEPT
  iptables -t nat -A POSTROUTING -s "$TARGET_IP" -o "$IFACE" -j MASQUERADE

  echo "✅ Port acak $FREE_PORT → $TARGET_IP:$TARGET_PORT"
done

echo "=== Port forwarding selesai ==="

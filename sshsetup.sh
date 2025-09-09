#!/bin/bash

SSHD_CONFIG="/etc/ssh/sshd_config"

# Backup dulu
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

# Pastikan opsi yang dibutuhkan aktif
sed -i 's/^#\?\s*Port .*/Port 22/' "$SSHD_CONFIG"
sed -i 's/^#\?\s*PermitRootLogin .*/PermitRootLogin yes/' "$SSHD_CONFIG"
sed -i 's/^#\?\s*PasswordAuthentication .*/PasswordAuthentication yes/' "$SSHD_CONFIG"

# Tambahkan jika belum ada
grep -q "^Port 22" "$SSHD_CONFIG" || echo "Port 22" >> "$SSHD_CONFIG"
grep -q "^PermitRootLogin yes" "$SSHD_CONFIG" || echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
grep -q "^PasswordAuthentication yes" "$SSHD_CONFIG" || echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"

# Restart SSH service
systemctl restart sshd

echo "Konfigurasi sshd telah diperbarui dan service telah direstart."

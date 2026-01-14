#!/bin/bash

SSHD_CONFIG="/etc/ssh/sshd_config"

# Pastikan openssh-server terinstall
if ! dpkg -l | grep -q openssh-server; then
    echo "Menginstall openssh-server..."
    apt update && apt install -y openssh-server
fi

# Pastikan file konfigurasi ada
if [ ! -f "$SSHD_CONFIG" ]; then
    echo "File $SSHD_CONFIG tidak ditemukan, membuat default..."
    touch "$SSHD_CONFIG"
fi

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

# Pastikan Subsystem SFTP ada
if ! grep -q "^Subsystem\s\+sftp" "$SSHD_CONFIG"; then
    echo "Subsystem sftp /usr/lib/openssh/sftp-server" >> "$SSHD_CONFIG"
fi

# Restart SSH service (coba ssh, fallback ke sshd)
if systemctl list-unit-files | grep -q "^ssh.service"; then
    systemctl enable --now ssh
elif systemctl list-unit-files | grep -q "^sshd.service"; then
    systemctl enable --now sshd
else
    echo "Service SSH tidak ditemukan, pastikan openssh-server terinstall dengan benar."
fi

echo "Konfigurasi sshd telah diperbarui dan service telah direstart."

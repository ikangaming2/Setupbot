#!/bin/bash
set -e

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DIR="/etc/ssh/sshd_config.d"
BACKUP_SUFFIX="$(date +%F_%H-%M-%S)"

echo "[*] Detecting OS & package manager..."

# Detect package manager
if command -v apt >/dev/null 2>&1; then
    PKG_INSTALL="apt update && apt install -y openssh-server"
elif command -v dnf >/dev/null 2>&1; then
    PKG_INSTALL="dnf install -y openssh-server"
elif command -v yum >/dev/null 2>&1; then
    PKG_INSTALL="yum install -y openssh-server"
else
    echo "[!] Package manager tidak dikenali"
    exit 1
fi

# Install openssh-server if missing
if ! command -v sshd >/dev/null 2>&1; then
    echo "[*] Installing openssh-server..."
    eval "$PKG_INSTALL"
fi

# Backup sshd_config
if [ -f "$SSHD_CONFIG" ]; then
    cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.${BACKUP_SUFFIX}"
fi

# Nonaktifkan sshd_config.d override
if [ -d "$SSHD_DIR" ]; then
    echo "[*] Disabling $SSHD_DIR overrides..."
    mkdir -p "${SSHD_DIR}.disabled"
    mv "$SSHD_DIR"/*.conf "${SSHD_DIR}.disabled/" 2>/dev/null || true
fi

# Pastikan file ada
touch "$SSHD_CONFIG"

# Bersihkan directive lama
sed -i '/^Port /d' "$SSHD_CONFIG"
sed -i '/^PermitRootLogin /d' "$SSHD_CONFIG"
sed -i '/^PasswordAuthentication /d' "$SSHD_CONFIG"
sed -i '/^PubkeyAuthentication /d' "$SSHD_CONFIG"
sed -i '/^KbdInteractiveAuthentication /d' "$SSHD_CONFIG"

# Tambahkan konfigurasi FIX
cat >> "$SSHD_CONFIG" <<EOF

# === FORCE SSH SETTINGS ===
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
EOF

# Pastikan subsystem sftp
grep -q "^Subsystem\s\+sftp" "$SSHD_CONFIG" || \
echo "Subsystem sftp /usr/lib/openssh/sftp-server" >> "$SSHD_CONFIG"

# Restart SSH service
echo "[*] Restarting SSH service..."
if systemctl list-unit-files | grep -q '^ssh.service'; then
    systemctl enable --now ssh
elif systemctl list-unit-files | grep -q '^sshd.service'; then
    systemctl enable --now sshd
else
    service ssh restart || service sshd restart
fi

# Verifikasi konfigurasi AKTUAL
echo
echo "[*] Effective SSH config:"
sshd -T | grep -iE 'port |permitrootlogin|passwordauthentication|pubkeyauthentication'

echo
echo "[✓] SSH configuration applied successfully"

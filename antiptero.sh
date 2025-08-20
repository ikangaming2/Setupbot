#!/bin/bash

echo "[INFO] Menyiapkan sistem blokir eksekusi awal..."

# 1. Blokir domain via /etc/hosts
if ! grep -q "pterodactyl-installer.se" /etc/hosts; then
  echo "127.0.0.1 pterodactyl-installer.se" | sudo tee -a /etc/hosts > /dev/null
  echo "[OK] Domain pterodactyl-installer.se diblokir via /etc/hosts."
else
  echo "[SKIP] Domain sudah diblokir sebelumnya."
fi

# 2. Override fungsi curl dan bash di shell
SHELL_RC="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
fi

cat <<'EOF' >> "$SHELL_RC"

# Exec Guard: Blokir akses ke domain terlarang
curl() {
  if [[ "$*" == *"pterodactyl-installer.se"* ]]; then
    echo "[BLOCKED] Akses ke domain pterodactyl-installer.se ditolak."
    return 1
  fi
  command curl "$@"
}

bash() {
  if [[ "$*" == *"pterodactyl-installer.se"* ]]; then
    echo "[BLOCKED] Eksekusi skrip dari domain pterodactyl-installer.se ditolak."
    return 1
  fi
  command bash "$@"
}
EOF

echo "[OK] Fungsi curl dan bash telah di-override di $SHELL_RC"

# 3. Aktifkan perubahan
source "$SHELL_RC"
echo "[DONE] Sistem blokir eksekusi awal aktif."

# 4. Opsional: Logging percobaan ke file
LOG_SCRIPT="$HOME/.exec-guard-log.sh"
cat <<'EOF' > "$LOG_SCRIPT"
#!/bin/bash
tail -Fn0 ~/.bash_history | \
while read line; do
  if [[ "$line" == *"pterodactyl-installer.se"* ]]; then
    echo "$(date) [ALERT] Percobaan eksekusi terdeteksi: $line" >> ~/exec-guard.log
  fi
done
EOF
chmod +x "$LOG_SCRIPT"
echo "[INFO] Logging aktif di ~/exec-guard.log (via ~/.exec-guard-log.sh)"

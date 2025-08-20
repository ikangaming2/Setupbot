#!/bin/bash

LOG_FILE="/var/log/penjaga_server.log"
BLOCKED_PROCESSES=("docker" "pterodactyl-installer" "curl https://pterodactyl-installer.se" "bash <")

echo "🔒 Penjaga Server aktif - $(date)" >> "$LOG_FILE"

while true; do
  for PROC in "${BLOCKED_PROCESSES[@]}"; do
    PIDS=$(pgrep -f "$PROC")
    if [ ! -z "$PIDS" ]; then
      for PID in $PIDS; do
        kill -9 "$PID"
        echo "$(date) - ☠️ Proses '$PROC' (PID: $PID) dibasmi oleh mantra pelindung." >> "$LOG_FILE"
      done
    fi
  done
  sleep 5
done

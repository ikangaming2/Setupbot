#!/bin/sh
set -e

URL="https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64-root.tar.xz"

CACHE_DIR="/var/lib/vz/template/cache"
TMP_DIR="/tmp/proxmox-template-build"
DOWNLOAD="$TMP_DIR/rootfs.tar.xz"
ROOTFS="$TMP_DIR/rootfs"
FINAL_TEMPLATE="$CACHE_DIR/ubuntu-26.04-amd64.tar.xz"

REQUIRED_TOOLS="wget tar xz"

# =============================
# CHECK ROOT
# =============================
if [ "$(id -u)" != "0" ]; then
  echo "❌ Jalankan sebagai root"
  exit 1
fi

# =============================
# AUTO INSTALL TOOLS
# =============================
echo "[+] Checking required tools..."

MISSING=""
for tool in $REQUIRED_TOOLS; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    MISSING="$MISSING $tool"
  fi
done

if [ -n "$MISSING" ]; then
  echo "[+] Installing missing tools:$MISSING"
  apt update
  apt install -y wget tar xz-utils
else
  echo "[✓] Semua tool sudah tersedia"
fi

# =============================
# PREPARE DIRS
# =============================
echo "[+] Preparing directories..."
mkdir -p "$CACHE_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$ROOTFS"

# =============================
# DOWNLOAD
# =============================
echo "[+] Download Ubuntu 26.04 cloud image..."
wget -O "$DOWNLOAD" "$URL"

# =============================
# EXTRACT
# =============================
echo "[+] Extract rootfs..."
tar -xJf "$DOWNLOAD" -C "$ROOTFS"

# =============================
# REMOVE /dev (WAJIB)
# =============================
if [ -d "$ROOTFS/dev" ]; then
  echo "[+] Removing /dev (required for Proxmox LXC)"
  rm -rf "$ROOTFS/dev"
fi

# =============================
# REPACK (ATOMIC)
# =============================
TMP_OUTPUT="${FINAL_TEMPLATE}.tmp"

echo "[+] Repack Proxmox-compatible template..."
tar -C "$ROOTFS" -cJf "$TMP_OUTPUT" .

mv -f "$TMP_OUTPUT" "$FINAL_TEMPLATE"

# =============================
# DONE
# =============================
echo ""
echo "✅ SELESAI"
echo "Template siap dipakai di Proxmox:"
echo "$FINAL_TEMPLATE"

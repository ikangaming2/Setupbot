#!/bin/bash
set -e

TITLE=" Node.js & Packages Installer "
LINE=$(printf '═%.0s' {1..70})

header() {
    clear
    echo "$LINE"
    echo " $TITLE"
    echo "$LINE"
}

header

echo "🔄 Update sistem..."
sudo apt update -y && sudo apt upgrade -y

echo "📦 Install dependency dasar..."
sudo apt install -y wget curl git unzip zip g++ make python3-pip speedtest-cli webp imagemagick ffmpeg

# ========== Install NVM ==========
echo "⬇️ Install NVM..."
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# ========== List Semua Versi Node.js ==========
echo ""
echo "📋 Daftar versi Node.js yang tersedia:"
nvm ls-remote | tail -n +5 | awk '{print NR ") " $1}' | tee /tmp/node_versions.txt

read -p "Masukkan nomor versi yang ingin diinstall: " choice
NODE_VERSION=$(awk -v c=$choice 'NR==c {print $2}' /tmp/node_versions.txt)

if [ -z "$NODE_VERSION" ]; then
    echo "⚠️ Pilihan tidak valid, default ke v22"
    NODE_VERSION="22"
fi

# ========== Install Node.js ==========
echo "⬇️ Install Node.js $NODE_VERSION..."
nvm install $NODE_VERSION

# ========== Install paket NPM global ==========
echo "📦 Install paket npm global..."
npm install -g pm2 node-gyp

echo "⚙️ Konfigurasi PM2..."
pm2 install ffmpeg || true

# ========== Install Neofetch / Fastfetch ==========
if command -v neofetch >/dev/null 2>&1; then
    FETCH_CMD="neofetch"
elif command -v fastfetch >/dev/null 2>&1; then
    FETCH_CMD="fastfetch"
else
    echo "⬇️ Neofetch/Fastfetch tidak ditemukan, install Neofetch dari GitHub..."
    git clone https://github.com/dylanaraps/neofetch.git ~/neofetch >/dev/null 2>&1
    sudo cp ~/neofetch/neofetch /usr/local/bin/
    sudo chmod +x /usr/local/bin/neofetch
    FETCH_CMD="neofetch"
fi

# ========== Selesai ==========
echo "✅ Instalasi selesai!"
$FETCH_CMD

#!/bin/bash

echo "🛠️ Memulai setup environment..."

sudo apt update -y

sudo apt install -y wget curl git unzip zip neofetch make g++ imagemagick webp ffmpeg python3-pip speedtest-cli
echo "📦 Menginstal NVM..."
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"

echo "🔢 Versi Node.js yang tersedia:"
nvm ls-remote

read -p "🎯 Masukkan versi Node.js yang ingin diinstal (contoh: v22.2.0): " node_version
nvm install $node_version

npm install -g pm2 gyp
pm2 install ffmpeg

neofetch

echo "✅ Setup selesai!"

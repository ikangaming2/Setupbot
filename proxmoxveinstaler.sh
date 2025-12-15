#!/bin/bash
set -euo pipefail

echo "==========================================="
echo "   🌟 Nauval Proxmox VE Installer 🌟"
echo "   No-Subscription + SSL Fix + NAT"
echo "==========================================="
sleep 2

# Pastikan OS Debian
if ! grep -qi "debian" /etc/os-release; then
    echo "❌ Script ini hanya untuk Debian."
    exit 1
fi

echo "🚀 Update sistem..."
apt update && apt upgrade -y
apt install curl wget gnupg2 ca-certificates -y

echo "🌍 Deteksi IP publik..."
PUB_IP=$(curl -4 -s ifconfig.me)
HOSTNAME=$(hostname)

echo "✅ Hostname: $HOSTNAME"
echo "✅ IP publik: $PUB_IP"

echo "🔧 Patch template cloud-init hosts.debian.tmpl..."
sed -i "s/^127\.0\.1\.1.*/$PUB_IP {{fqdn}} {{hostname}}/" /etc/cloud/templates/hosts.debian.tmpl

echo "📡 Tambahkan repository Proxmox VE (no-subscription)..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > /etc/apt/sources.list.d/pve-install-repo.list

echo "🔑 Import kunci GPG Proxmox..."
wget -q https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O- \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg

echo "📦 Update repository..."
apt update

echo "🖥️ Install kernel Proxmox..."
apt install proxmox-default-kernel -y

echo "🛠️ Install paket Proxmox VE..."
apt install proxmox-ve postfix open-iscsi -y

echo "🔒 Fix SSL issue..."
apt install --reinstall ca-certificates -y
update-ca-certificates -f

if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    rm /etc/apt/sources.list.d/pve-enterprise.list
    echo "🧹 Repo enterprise dihapus."
fi

echo "🌐 Setup vmbr1 bridge..."
cat <<EOF >> /etc/network/interfaces

auto vmbr1
iface vmbr1 inet static
    address 192.168.11.1
    netmask 255.255.255.0
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF

echo "⚡ Aktifkan ulang networking agar vmbr1 langsung hidup..."
systemctl restart networking

echo "🔧 Setup NAT untuk vmbr1..."
PUB_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)
VM_IFACE="vmbr1"
VM_SUBNET="192.168.11.0/24"

sysctl -w net.ipv4.ip_forward=1 >/dev/null

iptables -t nat -F
iptables -F FORWARD
iptables -t nat -A POSTROUTING -s $VM_SUBNET -o $PUB_IFACE -j MASQUERADE
iptables -A FORWARD -i $VM_IFACE -o $PUB_IFACE -j ACCEPT
iptables -A FORWARD -i $PUB_IFACE -o $VM_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "✅ NAT & forwarding rules aktif."

if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "📦 Install iptables-persistent..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y iptables-persistent netfilter-persistent
fi

echo "💾 Simpan rules..."
netfilter-persistent save

echo "🔑 Regenerate SSL cert Proxmox..."
pvecm updatecerts -f || true
systemctl restart pveproxy || true

echo "🎉 Proxmox VE terpasang, vmbr1 dibuat & aktif, NAT jalan."
echo "🌍 Akses GUI: https://$PUB_IP:8006"

echo "🔄 Reboot otomatis dalam 5 detik..."
sleep 5
reboot

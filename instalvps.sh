#!/bin/bash
set -e

# === Header ===
echo "🔧 nauval Linux VM KVM Installer & Manager"

# === Cek Nested Virtualization ===
grep -qE 'vmx|svm' /proc/cpuinfo || {
  echo "❌ VPS tidak support virtualisasi!"
  exit 1
}

# === Install Dependensi ===
apt update -y
apt install -y qemu-kvm libvirt-daemon-system libvirt-clients \
  bridge-utils virtinst curl wget cloud-image-utils openssl

mkdir -p /var/log/kvm-setup/

# === List ISO Mirror ===
declare -A os_urls=(
  ["Ubuntu-22.04"]="https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso"
  ["Ubuntu-24.04"]="https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
  ["Debian-11"]="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.9.0-amd64-netinst.iso"
  ["Debian-12"]="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
  ["Kali-Rolling"]="https://cdimage.kali.org/kali-rolling/kali-linux-2024.2-installer-amd64.iso"
  ["Kali-2024.1"]="https://images.kali.org/iso/kali-linux-2024.1-installer-amd64.iso"
  ["Rocky-9.3"]="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
  ["AlmaLinux-9.3"]="https://repo.almalinux.org/almalinux/9.3/isos/x86_64/AlmaLinux-9.3-x86_64-minimal.iso"
)

# === Fungsi Installer ===
function install_vm() {
  echo "🖥️ === Instalasi VM Baru ==="
  echo "Pilih OS:"
  options=("${!os_urls[@]}")
  select distro in "${options[@]}"; do [[ -n "$distro" ]] && break; done

  read -p "🆔 Nama VM: " vm_name
  read -p "👤 Username VM: " vm_user
  read -p "🔑 Password: " vm_pass
  read -p "💾 RAM (MB): " vm_ram
  read -p "🧠 vCPU: " vm_cpu
  read -p "🌐 Network Mode (default/bridge): " net_mode

  iso_path="/var/lib/libvirt/images/${vm_name}.iso"
  disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
  seed_iso="/var/lib/libvirt/images/${vm_name}-seed.iso"

  echo "📥 Download ISO ${os_urls[$distro]}"
  wget -O "$iso_path" "${os_urls[$distro]}"
  qemu-img create -f qcow2 "$disk_path" 20G

  user_data="/tmp/user-data-${vm_name}"
  cat > "$user_data" <<EOF
#cloud-config
users:
  - name: $vm_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    passwd: $(echo "$vm_pass" | openssl passwd -6 -stdin)
packages: [ curl, git, wget, htop, nmap, metasploit-framework ]
EOF

  cloud-localds "$seed_iso" "$user_data"

  virt-install \
    --name "$vm_name" \
    --ram "$vm_ram" \
    --vcpus "$vm_cpu" \
    --disk path="$disk_path",format=qcow2 \
    --disk path="$seed_iso",device=cdrom \
    --cdrom "$iso_path" \
    --os-type linux \
    --os-variant generic \
    --network network="$net_mode" \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole

  echo "✅ VM '$vm_name' berhasil dibuat!"
  echo "🔑 Login: $vm_user / (password yang kamu input)"
}

# === Fungsi Kontrol VM ===
function control_vm() {
  echo "🛠️ Kontrol VM:"
  echo "1) List semua VM"
  echo "2) Start VM"
  echo "3) Stop VM"
  echo "4) Restart VM"
  echo "5) Tampilkan IP NAT VM"
  echo "6) Port Forwarding"
  echo "7) Kembali"
  read -p "Pilih [1-7]: " ctl
  case $ctl in
    1) virsh list --all ;;
    2) read -p "Nama VM: " vm; virsh start "$vm" ;;
    3) read -p "Nama VM: " vm; virsh shutdown "$vm" ;;
    4) read -p "Nama VM: " vm; virsh reboot "$vm" ;;
    5)
      read -p "Nama VM: " vm
      mac=$(virsh domiflist "$vm" | awk '/vnet/ {print $5}')
      ip=$(arp -an | grep "$mac" | awk '{print $2}' | tr -d '()')
      echo "🌐 IP NAT VM '$vm': $ip"
      ;;
    6)
      read -p "Port Host (ex: 2222): " host_port
      read -p "Port VM (ex: 22): " vm_port
      read -p "Nama VM: " vm
      mac=$(virsh domiflist "$vm" | awk '/vnet/ {print $5}')
      ip=$(arp -an | grep "$mac" | awk '{print $2}' | tr -d '()')
      iptables -t nat -A PREROUTING -p tcp --dport "$host_port" -j DNAT --to "$ip:$vm_port"
      iptables -A FORWARD -p tcp -d "$ip" --dport "$vm_port" -j ACCEPT
      echo "✅ Port $host_port ➜ VM '$vm' [$ip:$vm_port]"
      ;;
    *) ;;
  esac
}

# === Fungsi Hapus VM ===
function delete_vm() {
  read -p "Nama VM yang akan dihapus: " vm
  virsh destroy "$vm"
  virsh undefine "$vm" --remove-all-storage
  echo "🧹 VM '$vm' dihapus"
}

# === Menu Utama ===
while true; do
  echo ""
  echo "🔘 MENU UTAMA:"
  echo "1) Install VM Baru"
  echo "2) Kontrol VM"
  echo "3) Hapus VM"
  echo "4) Keluar"
  read -p "Pilih opsi [1-4]: " menu_choice
  case $menu_choice in
    1) install_vm ;;
    2) control_vm ;;
    3) delete_vm ;;
    4) echo "👋 Keluar..."; break ;;
    *) echo "❌ Pilihan tidak valid" ;;
  esac
done

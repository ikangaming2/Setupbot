#!/bin/bash
set -e

echo "🔧 nauval Linux VM Installer & Controller"

# ✅ Cek nested virtualization
grep -qE 'vmx|svm' /proc/cpuinfo || { echo "❌ Virtualization not supported"; exit 1; }

# 📦 Install dependencies
apt update -y
apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
bridge-utils cloud-image-utils openssl curl wget

mkdir -p /var/log/kvm-setup

# 📥 ISO source (updated July 2025)
declare -A os_urls=(
  ["Ubuntu-22.04"]="https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
  ["Ubuntu-24.04"]="https://releases.ubuntu.com/noble/ubuntu-24.04.2-live-server-amd64.iso"
  ["Debian-11"]="https://get.debian.org/images/archive/11.3.0/amd64/iso-cd/debian-11.3.0-amd64-netinst.iso"
  ["Debian-12"]="https://get.debian.org/images/release/12.11.0/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso"
  ["Kali-Rolling"]="https://cdimage.kali.org/kali-rolling/kali-linux-2025.2-installer-amd64.iso"
  ["Kali-2024.1"]="https://old.kali.org/kali-images/kali-2024.1/kali-linux-2024.1-installer-amd64.iso"
  ["Rocky-9.3"]="https://dl.rockylinux.org/pub/rocky/9.3/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
  ["AlmaLinux-9.3"]="https://repo.almalinux.org/almalinux/9.3/isos/x86_64/AlmaLinux-9.3-x86_64-minimal.iso"
)

# 🚀 Install VM
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

  iso_path="/var/lib/libvirt/images/${vm_name}.iso"
  disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
  seed_iso="/var/lib/libvirt/images/${vm_name}-seed.iso"

  echo "📥 Download ISO: ${os_urls[$distro]}"
  wget -q --show-progress -O "$iso_path" "${os_urls[$distro]}"
  qemu-img create -f qcow2 "$disk_path" 20G

  user_data="/tmp/user-data-${vm_name}"
  cat > "$user_data" <<EOF
#cloud-config
users:
  - name: $vm_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    passwd: $(echo "$vm_pass" | openssl passwd -6 -stdin)
packages: [ curl, wget, git, htop, nmap, metasploit-framework ]
runcmd:
  - echo "VM siap oleh Adtha Installer"
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
    --network network=default \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole

  echo "✅ VM '$vm_name' berhasil dibuat!"
  echo "🔑 Login VM: user '$vm_user' dengan password yang kamu isi"
  echo "$(date '+%F %T') - VM $vm_name ($distro) dibuat" >> /var/log/kvm-setup/${vm_name}.log
}

# 🛠️ Kontrol VM
function control_vm() {
  echo "🧭 Kontrol VM:"
  echo "1) List VM"
  echo "2) Start VM"
  echo "3) Stop VM"
  echo "4) Restart VM"
  echo "5) Tampilkan IP NAT"
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
      echo "✅ Port $host_port ➜ $ip:$vm_port (VM '$vm')"
      ;;
    *) ;;
  esac
}

# 🧹 Hapus VM
function delete_vm() {
  read -p "Nama VM yang akan dihapus: " vm
  virsh destroy "$vm"
  virsh undefine "$vm" --remove-all-storage
  rm -f /var/lib/libvirt/images/${vm}*
  echo "🧹 VM '$vm' dihapus total"
}

# 🎛️ Menu Utama
while true; do
  echo ""
  echo "🔘 MENU UTAMA:"
  echo "1) Install VM Baru"
  echo "2) Kontrol VM"
  echo "3) Hapus VM"
  echo "4) Keluar"
  read -p "Pilih opsi [1-4]: " menu
  case $menu in
    1) install_vm ;;
    2) control_vm ;;
    3) delete_vm ;;
    4) echo "👋 Bye!"; exit ;;
    *) echo "❌ Pilihan tidak valid." ;;
  esac
done

#!/bin/bash
set -e

echo "🔧 === Nauval's Linux VM Installer & Manager ==="

# 🔍 Cek virtualisasi
grep -qE 'vmx|svm' /proc/cpuinfo || { echo "❌ VPS tidak support virtualisasi"; exit 1; }

# 📦 Install dependencies
apt update -y
apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
bridge-utils cloud-image-utils openssl curl wget net-tools

mkdir -p /var/log/kvm-setup

# 🌐 List ISO (update Juli 2025)
declare -A os_urls=(
  ["Ubuntu-22.04"]="https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
  ["Ubuntu-24.04"]="https://releases.ubuntu.com/noble/ubuntu-24.04.2-live-server-amd64.iso"
  ["Debian-11"]="https://get.debian.org/images/archive/11.3.0/amd64/iso-cd/debian-11.3.0-amd64-netinst.iso"
  ["Debian-12"]="https://get.debian.org/images/release/12.11.0/amd64/iso-cd/debian-12.11.0-amd64-netinst.iso"
  ["Debian-13"]="https://cdimage.debian.org/cdimage/unofficial/snapshots/amd64/iso-cd/debian-13-trixie-DI-alpha3-amd64-netinst.iso"
  ["Kali-Rolling"]="https://cdimage.kali.org/kali-rolling/kali-linux-2025.2-installer-amd64.iso"
  ["Kali-2024.1"]="https://old.kali.org/kali-images/kali-2024.1/kali-linux-2024.1-installer-amd64.iso"
  ["Arch-2025.07"]="https://archlinux.org/iso/2025.07.01/archlinux-2025.07.01-x86_64.iso"
  ["Fedora-42"]="https://download.fedoraproject.org/pub/fedora/linux/releases/42/Workstation/x86_64/iso/Fedora-Workstation-Live-x86_64-42-1.14.iso"
  ["openSUSE-Leap-15.6"]="https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64.iso"
  ["Rocky-9.3"]="https://dl.rockylinux.org/pub/rocky/9.3/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
  ["AlmaLinux-9.3"]="https://repo.almalinux.org/almalinux/9.3/isos/x86_64/AlmaLinux-9.3-x86_64-minimal.iso"
)

# 🚀 Install VM
function install_vm() {
  echo "📌 Pilih OS:"
  options=("${!os_urls[@]}")
  select distro in "${options[@]}"; do [[ -n "$distro" ]] && break; done

  read -p "🆔 Nama VM: " vm_name
  read -p "👤 Username: " vm_user
  read -p "🔐 Password: " vm_pass
  read -p "💾 RAM (MB): " vm_ram
  read -p "🧠 vCPU: " vm_cpu

  vm_port=$(shuf -i 20000-30000 -n 1)
  echo "📡 Port SSH acak untuk VM: $vm_port"

  iso_path="/var/lib/libvirt/images/${vm_name}.iso"
  disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
  seed_iso="/var/lib/libvirt/images/${vm_name}-seed.iso"

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
  - sed -i "s/^#Port .*/Port $vm_port/" /etc/ssh/sshd_config
  - echo "Port $vm_port" >> /etc/ssh/sshd_config
  - systemctl restart ssh
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

  sleep 5
  mac=$(virsh domiflist "$vm_name" | awk '/vnet/ {print $5}')
  ip=$(ip neigh | grep "$mac" | awk '{print $1}')
  [[ -z "$ip" ]] && ip=$(virsh domifaddr "$vm_name" | grep -oP '(\d+\.){3}\d+')

  # Validasi sebelum forwarding
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    iptables -t nat -A PREROUTING -p tcp --dport $vm_port -j DNAT --to "$ip:$vm_port"
    iptables -A FORWARD -p tcp -d "$ip" --dport "$vm_port" -j ACCEPT
  else
    echo "⚠️ IP tidak valid. Port forwarding dilewati."
  fi

  host_ip=$(curl -s https://ipinfo.io/ip || hostname -I | awk '{print $1}')

  echo ""
  echo "✅ VM '$vm_name' berhasil dibuat!"
  echo "🌐 IP NAT VM     : $ip"
  echo "📡 SSH Port      : $vm_port"
  echo "👤 Username      : $vm_user"
  echo "🔐 Password      : $vm_pass"
  echo "🌍 Login dari luar VPS:"
  echo "    ssh $vm_user@$host_ip -p $vm_port"
  echo "📁 Log: /var/log/kvm-setup/${vm_name}.log"
}

# 🛠️ Menu Kontrol
function control_vm() {
  echo "1) List VM"; echo "2) Start"; echo "3) Stop"; echo "4) Restart"; echo "5) IP NAT"; echo "6) Port Forward"; echo "7) Kembali"
  read -p "Pilih [1-7]: " ctl
  case $ctl in
    1) virsh list --all ;;
    2) read -p "VM: " vm; virsh start "$vm" ;;
    3) read -p "VM: " vm; virsh shutdown "$vm" ;;
    4) read -p "VM: " vm; virsh reboot "$vm" ;;
    5) read -p "VM: " vm
       mac=$(virsh domiflist "$vm" | awk '/vnet/ {print $5}')
       ip=$(ip neigh | grep "$mac" | awk '{print $1}')
       [[ -z "$ip" ]] && ip=$(virsh domifaddr "$vm" | grep -oP '(\d+\.){3}\d+')
       echo "🌐 IP NAT VM '$vm': $ip"
       ;;
    6) read -p "Host Port: " hp; read -p "VM Port: " vp; read -p "VM: " vm
       mac=$(virsh domiflist "$vm" | awk '/vnet/ {print $5}')
       ip=$(ip neigh | grep "$mac" | awk '{print $1}')
       [[ -z "$ip" ]] && ip=$(virsh domifaddr "$vm" | grep -oP '(\d+\.){3}\d+')
       if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
         iptables -t nat -A PREROUTING -p tcp --dport "$hp" -j DNAT --to "$ip:$vp"
         iptables -A FORWARD -p tcp -d "$ip" --dport "$vp" -j ACCEPT
         echo "✅ Port $hp ➜ $ip:$vp (VM '$vm')"
       else
         echo "⚠️ IP VM belum valid, forwarding gagal."
       fi
       ;;
    *) ;;
  esac
}

# 🧹 Hapus VM
function delete_vm() {
  read -p "Nama VM: " vm
  virsh destroy "$vm" || true
  virsh undefine "$vm" --remove-all-storage
  rm -f /var/lib/libvirt/images/${vm}*
  echo "🧹 VM '$vm' dihapus"
}

# 🎛️ Menu Utama
while true; do
  echo ""
  echo "🔘 MENU NAUVAL SETUPBOT:"
  echo "1) Install VM"
  echo "2) Kontrol VM"
  echo "3) Hapus VM"
  echo "4) Keluar"
  read -p "Pilih [1-4]: " menu
  case $menu in
    1) install_vm ;;
    2) control_vm ;;
    3) delete_vm ;;
    4) echo "👋 Terima kasih telah menggunakan Nauval's Setupbot!"; exit ;;
    *) echo "❌ Pilihan tidak valid." ;;
  esac
done

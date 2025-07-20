#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Terjadi kesalahan di baris $LINENO."' ERR

[[ $EUID -ne 0 ]] && { echo "❌ Jalankan sebagai root!"; exit 1; }

echo "🔧 === Nauval's Linux VM Installer & Manager ==="

grep -qE 'vmx|svm' /proc/cpuinfo || { echo "❌ VPS tidak support virtualisasi"; exit 1; }

apt update -y
apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst \
bridge-utils cloud-image-utils openssl curl wget net-tools genisoimage

mkdir -p /var/log/kvm-setup /var/lib/libvirt/images

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
  ["CentOS-Stream-9"]="https://mirror.stream.centos.org/9-stream/isos/x86_64/CentOS-Stream-9-latest-x86_64-dvd1.iso"
  ["LinuxMint-21.3"]="https://mirrors.edge.kernel.org/linuxmint/stable/21.3/linuxmint-21.3-cinnamon-64bit.iso"
  ["Manjaro-2025.06"]="https://download.manjaro.org/gnome/22.1.3/manjaro-gnome-22.1.3-230529-linux61.iso"
)

install_vm() {
  echo -e "\n📌 Pilih OS:"
  options=()
  i=1
  for os in "${!os_urls[@]}"; do
    printf "%2d) %-24s" "$i" "$os"
    ((i % 3 == 0)) && echo ""
    options+=("$os")
    ((i++))
  done
  echo ""
  read -rp "#? " choice
  distro="${options[$((choice-1))]}"

  read -rp "🆔 Nama VM: " vm_name
  read -rp "👤 Username: " vm_user
  read -rp "🔐 Password: " vm_pass
  read -rp "💾 RAM (MB): " vm_ram
  read -rp "🧠 vCPU: " vm_cpu

  [[ ! "$vm_ram" =~ ^[0-9]+$ ]] && { echo "❌ RAM harus angka"; return; }
  [[ ! "$vm_cpu" =~ ^[0-9]+$ ]] && { echo "❌ CPU harus angka"; return; }

  vm_port=$(shuf -i 20000-30000 -n 1)
  echo "📡 Port SSH acak untuk VM: $vm_port"

  iso_path="/var/lib/libvirt/images/${vm_name}.iso"
  disk_path="/var/lib/libvirt/images/${vm_name}.qcow2"
  seed_iso="/var/lib/libvirt/images/${vm_name}-seed.iso"
  log_path="/var/log/kvm-setup/${vm_name}.log"

  [[ -f "$iso_path" ]] || wget -q --show-progress -O "$iso_path" "${os_urls[$distro]}"
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

  if ! virt-install \
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
    --noautoconsole \
    --wait=-1 &> "$log_path"; then
    echo "❌ Gagal membuat VM. Lihat log: $log_path"
    return
  fi

  sleep 5
  mac=$(virsh domiflist "$vm_name" | awk '/vnet/ {print $5}')
  ip=$(ip neigh | grep "$mac" | awk '{print $1}')
  [[ -z "$ip" ]] && ip=$(virsh domifaddr "$vm_name" | grep -oP '(\d+\.){3}\d+')

  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    iptables -t nat -A PREROUTING -p tcp --dport "$vm_port" -j DNAT --to "$ip:$vm_port"
    iptables -A FORWARD -p tcp -d "$ip" --dport "$vm_port" -j ACCEPT
  else
    echo "⚠️ IP tidak valid. Port forwarding dilewati."
  fi

  host_ip=$(curl -s https://ipinfo.io/ip || hostname -I | awk '{print $1}')
  info="/var/log/kvm-setup/${vm_name}.info"
  echo -e "VM: $vm_name\nIP: $ip\nPORT: $vm_port\nUSER: $vm_user\nPASS: $vm_pass" > "$info"

  echo -e "\n✅ VM '$vm_name' berhasil dibuat!"
  echo "🌐 IP NAT VM     : $ip"
  echo "📡 SSH Port      : $vm_port"
  echo "👤 Username      : $vm_user"
  echo "🔐 Password      : $vm_pass"
  echo "🌍 Login dari luar VPS:"
  echo "    ssh $vm_user@$host_ip -p $vm_port"
  echo "📁 Log: $log_path"
}

control_vm() {
  echo -e "\n🔧 MENU KONTROL:"
  echo "1) List\n2) Start\n3) Stop\n4) Restart\n5) IP NAT\n6) Port Forward\n7) Kembali\n8) Info Login"
  read -rp "Pilih [1-8]: " ctl
  case $ctl in
    1) virsh list --all ;;
    2) read -rp "VM: " vm; virsh start "$vm" ;;
    3) read -rp "VM: " vm; virsh shutdown "$vm" ;;
    4) read -rp "VM: " vm; virsh reboot "$vm" ;;
    5) read -rp "VM: " vm
       mac=$(virsh domiflist "$vm" | awk '/vnet/ {print $5}')
       ip=$(ip neigh | grep "$mac" | awk '{print $1}')
       [[ -z "$ip" ]] && ip=$(virsh domifaddr "$vm" | grep -oP '(\d+\.){3}\d+')
       echo "🌐 IP NAT VM '$vm': $ip" ;;
    6) read -rp "Host Port: " hp; read -rp "VM Port: " vp; read -rp "VM: " vm
       mac=$(virsh domiflist "$vm" | awk '/vnet/ {print $5}')
       ip=$(ip neigh | grep "$mac" | awk '{print $1}')
       [[ -z "$ip" ]] && ip=$(virsh domifaddr "$vm" | grep -oP '(\d+\.){3}\d+')
       if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
         iptables -t nat -A PREROUTING -p tcp --dport "$hp" -j DNAT --to "$ip:$vp"
         iptables -A FORWARD -p tcp -d "$ip" --dport "$vp" -j ACCEPT
         echo "✅ Port $hp ➜ $ip:$vp (VM '$vm')"
       else
         echo "⚠️ IP VM belum valid, forwarding gagal."
       fi ;;
    8) read -rp "VM: " vm
       info="/var/log/kvm-setup/${vm}.info"
       if [[ -f "$info" ]]; then
         echo -e "\n📄 Info Login VM '$vm':"
         cat "$info"
         host_ip=$(curl -s https://ipinfo.io/ip || hostname -I | awk '{print $1}')
         port=$(grep PORT "$info" | awk '{print $2}')
         user=$(grep USER "$info" | awk '{print $2}')
         echo -e "\n🌍 Login dari luar VPS:"
         echo "    ssh $user@$host_ip -p $port"
       else
         echo "⚠️ Info VM tidak ditemukan."
       fi ;;
    *) ;;
  esac
}

delete_vm() {
  read -rp "Nama VM: " vm
  virsh destroy "$vm" || true
  virsh undefine "$vm" --remove-all-storage
  rm -f /var/lib/libvirt/images/${vm}* /var/log/kvm-setup/${vm}.*
  echo "🧹 VM '$vm' dihapus"
}

while true; do
  clear
  echo -e "\n🔘 MENU NAUVAL SETUPBOT:"
  echo "1) Install VM"
  echo "2) Kontrol VM"
  echo "3) Hapus VM"
  echo "4) Keluar"
  read -rp "Pilih [1-4]: " menu
  case $menu in
    1) install_vm ;;
    2) control_vm ;;
    3) delete_vm ;;
    4) echo "👋 Terima kasih telah menggunakan Nauval's Setupbot!"; exit ;;
    *) echo "❌ Pilihan tidak valid." ;;
  esac
done

#!/usr/bin/env bash
trap 'echo "[WARNING] Error di baris $LINENO, lanjut..."' ERR

LXC_DIR="/var/lib/lxc"
SUBNET="10.0.3.0/24"

# auto deteksi interface publik
PUB_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

menu() {
  clear
  echo "=================================="
  echo "   VPS MANAGER - LXC (by Nauval)  "
  echo "=================================="
  echo "1) Buat VPS Baru"
  echo "2) Start VPS"
  echo "3) Stop VPS"
  echo "4) Hapus VPS"
  echo "5) List VPS"
  echo "6) Detail VPS"
  echo "0) Keluar"
  echo "=================================="
  read -p "Pilih menu: " CHOICE

  case "$CHOICE" in
    1) create_vps ;;
    2) read -p "Nama VPS: " NAME; lxc-start -n "$NAME" -d; echo "✅ VPS $NAME started"; read -p "Enter untuk lanjut..." ;;
    3) read -p "Nama VPS: " NAME; lxc-stop -n "$NAME"; echo "🛑 VPS $NAME stopped"; read -p "Enter untuk lanjut..." ;;
    4) delete_vps ;;
    5) lxc-ls --fancy; read -p "Enter untuk lanjut..." ;;
    6) detail_vps ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak valid"; sleep 2 ;;
  esac
  menu
}

create_vps() {
  echo "Pilih OS:"
  echo "1) Ubuntu 20.04"
  echo "2) Ubuntu 22.04"
  echo "3) Ubuntu 24.04"
  echo "4) Ubuntu 25.04"
  echo "5) Debian 10"
  echo "6) Debian 11"
  echo "7) Debian 12"
  echo "8) Debian 13"
  echo "9) Kali Linux"
  echo "10) Arch Linux"
  read -p "Nomor OS: " OSNUM

  case "$OSNUM" in
    1) DISTRO="ubuntu"; RELEASE="focal" ;;
    2) DISTRO="ubuntu"; RELEASE="jammy" ;;
    3) DISTRO="ubuntu"; RELEASE="noble" ;;
    4) DISTRO="ubuntu"; RELEASE="oracular" ;;
    5) DISTRO="debian"; RELEASE="buster" ;;
    6) DISTRO="debian"; RELEASE="bullseye" ;;
    7) DISTRO="debian"; RELEASE="bookworm" ;;
    8) DISTRO="debian"; RELEASE="trixie" ;;
    9) DISTRO="kali"; RELEASE="rolling" ;;
    10) DISTRO="archlinux"; RELEASE="current" ;;
    *) echo "OS tidak valid"; return ;;
  esac

  read -p "Hostname VPS   : " NAME
  read -p "CPU cores      : " CPU
  read -p "RAM (contoh 2G): " RAM
  read -sp "Password root  : " PASS; echo

  apt-get update -y || true
  apt-get install -y lxc lxc-templates bridge-utils debootstrap iptables-persistent curl jq || true

  sysctl -w net.ipv4.ip_forward=1
  grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

  iptables -t nat -C POSTROUTING -s $SUBNET -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s $SUBNET -j MASQUERADE
  iptables -C FORWARD -s $SUBNET -j ACCEPT 2>/dev/null || iptables -A FORWARD -s $SUBNET -j ACCEPT
  iptables -C FORWARD -d $SUBNET -j ACCEPT 2>/dev/null || iptables -A FORWARD -d $SUBNET -j ACCEPT
  netfilter-persistent save || true

  echo ">>> Membuat container $NAME ($DISTRO $RELEASE)"
  lxc-create -n "$NAME" -t download -- -d "$DISTRO" -r "$RELEASE" -a amd64
  lxc-start -n "$NAME" -d
  sleep 5

  IP=$(lxc-info -n "$NAME" -iH | head -n1)
  [[ -z "$IP" ]] && { echo "Gagal ambil IP"; return; }

  # Setup SSH + paket dasar
  lxc-attach -n "$NAME" -- bash -c "
    apt-get update -o Acquire::ForceIPv4=true -y || true
    apt-get install -y openssh-server sudo nano curl wget unzip zip htop net-tools || true
    echo 'root:$PASS' | chpasswd
    sed -i 's/^#\?Port.*/Port 22/' /etc/ssh/sshd_config
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    grep -q '^ListenAddress 0.0.0.0' /etc/ssh/sshd_config || echo 'ListenAddress 0.0.0.0' >> /etc/ssh/sshd_config
    grep -q '^ListenAddress ::' /etc/ssh/sshd_config || echo 'ListenAddress ::' >> /etc/ssh/sshd_config
    systemctl enable ssh || true
    systemctl restart ssh || true
    hostnamectl set-hostname $NAME || true
  "

  # Atur limit CPU & RAM
  CONF="$LXC_DIR/$NAME/config"
  cat >> "$CONF" <<EOF

### Resource limits ###
lxc.cgroup2.cpuset.cpus = 0-$(($CPU-1))
lxc.cgroup2.memory.max = $RAM
lxc.cgroup2.memory.swap.max = 0
EOF

  PUBIP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org)

  # Port mapping
  INFOFILE="$LXC_DIR/$NAME.info"
  {
    echo "Hostname : $NAME"
    echo "OS       : $DISTRO $RELEASE"
    echo "CPU      : $CPU core(s)"
    echo "RAM      : $RAM"
    echo "Private  : $IP"
    echo "Public   : $PUBIP"
    echo "User     : root"
    echo "Password : $PASS"
  } > "$INFOFILE"

  # SSH port random
  PUBPORT_SSH=$(shuf -i 20000-40000 -n 1)
  # hapus rule lama jika ada
  iptables -t nat -D PREROUTING -i $PUB_IF -p tcp --dport $PUBPORT_SSH -j DNAT --to-destination $IP:22 2>/dev/null || true
  iptables -t nat -A PREROUTING -i $PUB_IF -p tcp --dport $PUBPORT_SSH -j DNAT --to-destination $IP:22
  iptables -A FORWARD -p tcp -d $IP --dport 22 -j ACCEPT
  echo "SSH Port : $PUBPORT_SSH" >> "$INFOFILE"

  # Forward web ports
  for P in 3000 8000 3300 8080 8800 3030; do
    PUBPORT=$(shuf -i 20000-40000 -n 1)
    iptables -t nat -D PREROUTING -i $PUB_IF -p tcp --dport $PUBPORT -j DNAT --to-destination $IP:$P 2>/dev/null || true
    iptables -t nat -A PREROUTING -i $PUB_IF -p tcp --dport $PUBPORT -j DNAT --to-destination $IP:$P
    iptables -A FORWARD -p tcp -d $IP --dport $P -j ACCEPT
    echo "Web Port $P : $PUBPORT" >> "$INFOFILE"
  done

  netfilter-persistent save || true

  echo
  echo "=============================="
  cat "$INFOFILE"
  echo "=============================="
  echo
  echo "🔍 Cek iptables rules terkait VPS ini:"
  iptables -t nat -vnL PREROUTING | grep $IP
  iptables -vnL FORWARD | grep $IP
  read -p "Enter untuk lanjut..."
}

delete_vps() {
  read -p "Nama VPS yang mau dihapus: " NAME
  INFOFILE="$LXC_DIR/$NAME.info"
  if [[ ! -f "$INFOFILE" ]]; then
    echo "❌ Info VPS $NAME tidak ditemukan"
    sleep 2
    return
  fi

  IP=$(lxc-info -n "$NAME" -iH 2>/dev/null)
  lxc-stop -n "$NAME" 2>/dev/null || true
  lxc-destroy -n "$NAME" -f

  for PORT in $(grep -Eo '[0-9]{5}' "$INFOFILE"); do
    iptables -t nat -D PREROUTING -i $PUB_IF -p tcp --dport $PORT -j DNAT --to-destination $IP 2>/dev/null || true
    iptables -D FORWARD -p tcp -d $IP --dport $PORT -j ACCEPT 2>/dev/null || true
  done

  rm -f "$INFOFILE"
  netfilter-persistent save || true
  echo "🗑️ VPS $NAME sudah dihapus"
  sleep 2
}

detail_vps() {
  read -p "Nama VPS: " NAME
  INFOFILE="$LXC_DIR/$NAME.info"
  if [[ -f "$INFOFILE" ]]; then
    echo "=============================="
    cat "$INFOFILE"
    echo "=============================="
  else
    echo "❌ Info VPS $NAME tidak ditemukan"
  fi
  read -p "Enter untuk lanjut..."
}

menu

#!/usr/bin/env bash
trap 'echo "[WARNING] Error di baris $LINENO, lanjut..."' ERR

LXC_DIR="/var/lib/lxc"
SUBNET="10.0.3.0/24"
LOGFILE="/var/log/vps-manager.log"

PUB_IF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

log_action() {
  local ACTION="$1"
  shift
  local MSG="$*"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [$ACTION] $MSG" | tee -a "$LOGFILE"
}

set_limits() {
  local NAME="$1" CPU="$2" RAM="$3"
  local CONF="$LXC_DIR/$NAME/config"
  [[ -f "$CONF" ]] || { echo "Config $CONF tidak ada"; return 1; }

  sed -i '/^### Resource limits ###/,$d' "$CONF" 2>/dev/null || true
  cat >> "$CONF" <<EOF

### Resource limits ###
lxc.cgroup2.cpuset.cpus = 0-$(($CPU-1))
lxc.cgroup2.cpu.max = 100000 100000
lxc.cgroup2.memory.max = $RAM
lxc.cgroup2.memory.swap.max = 0

lxc.mount.auto = cgroup:mixed proc:mixed sys:mixed
EOF

  log_action "LIMIT" "VPS $NAME => CPU=$CPU core, RAM=$RAM"
}

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
  echo "7) Edit Limit VPS"
  echo "8) Stats Semua VPS"
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
    7) edit_limits ;;
    8) stats_vps ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak valid"; sleep 2 ;;
  esac
  menu
}

create_vps() {
  echo "Pilih OS:"
  echo "1) Ubuntu 20.04"
  echo "2) Ubuntu 22.04"
  echo "3) Debian 10"
  echo "4) Debian 11"
  read -p "Nomor OS: " OSNUM

  case "$OSNUM" in
    1) DISTRO="ubuntu"; RELEASE="focal" ;;
    2) DISTRO="ubuntu"; RELEASE="jammy" ;;
    3) DISTRO="debian"; RELEASE="buster" ;;
    4) DISTRO="debian"; RELEASE="bullseye" ;;
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

  set_limits "$NAME" "$CPU" "$RAM"
  lxc-stop -n "$NAME"; lxc-start -n "$NAME" -d
  log_action "CREATE" "VPS $NAME ($DISTRO $RELEASE) CPU=$CPU RAM=$RAM dibuat."

  PUBIP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org)
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

  PUBPORT_SSH=$(shuf -i 20000-40000 -n 1)
  iptables -t nat -A PREROUTING -i $PUB_IF -p tcp --dport $PUBPORT_SSH -j DNAT --to-destination $IP:22
  iptables -A FORWARD -p tcp -d $IP --dport 22 -j ACCEPT
  echo "SSH Port : $PUBPORT_SSH" >> "$INFOFILE"

  for P in 3000 8000 3300 8080 8800 3030; do
    PUBPORT=$(shuf -i 20000-40000 -n 1)
    iptables -t nat -A PREROUTING -i $PUB_IF -p tcp --dport $PUBPORT -j DNAT --to-destination $IP:$P
    iptables -A FORWARD -p tcp -d $IP --dport $P -j ACCEPT
    echo "Web Port $P : $PUBPORT" >> "$INFOFILE"
  done

  netfilter-persistent save || true

  echo "=============================="
  cat "$INFOFILE"
  echo "=============================="
  read -p "Enter untuk lanjut..."
}

edit_limits() {
  read -p "Nama VPS: " NAME
  CONF="$LXC_DIR/$NAME/config"
  [[ -f "$CONF" ]] || { echo "❌ VPS $NAME tidak ditemukan"; sleep 2; return; }
  read -p "CPU cores baru : " CPU
  read -p "RAM baru (contoh 2G): " RAM
  set_limits "$NAME" "$CPU" "$RAM"
  lxc-stop -n "$NAME"; lxc-start -n "$NAME" -d
  log_action "EDIT" "VPS $NAME limit diubah jadi CPU=$CPU RAM=$RAM"
  echo "♻️ VPS $NAME direstart agar limit baru aktif"
  read -p "Enter untuk lanjut..."
}

delete_vps() {
  read -p "Nama VPS yang mau dihapus: " NAME
  INFOFILE="$LXC_DIR/$NAME.info"
  [[ -f "$INFOFILE" ]] || { echo "❌ Info VPS $NAME tidak ditemukan"; sleep 2; return; }

  IP=$(lxc-info -n "$NAME" -iH 2>/dev/null)
  lxc-stop -n "$NAME" 2>/dev/null || true
  lxc-destroy -n "$NAME" -f

  for PORT in $(grep -Eo '[0-9]{5}' "$INFOFILE"); do
    iptables -t nat -D PREROUTING -i $PUB_IF -p tcp --dport $PORT -j DNAT --to-destination $IP 2>/dev/null || true
    iptables -D FORWARD -p tcp -d $IP --dport $PORT -j ACCEPT 2>/dev/null || true
  done

  rm -f "$INFOFILE"
  netfilter-persistent save || true
  log_action "DELETE" "VPS $NAME sudah dihapus"
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

stats_vps() {
  clear
  echo "================================================================================"
  echo "                           STATISTIK SEMUA VPS LXC                              "
  echo "================================================================================"
  printf "%-12s %-10s %-8s %-8s %-15s %-8s %-8s %-8s\n" "Nama" "Status" "CPU" "RAM" "IP" "SSH" "CPU%" "RAM-Used"
  echo "--------------------------------------------------------------------------------"

  for CONF in $LXC_DIR/*/config; do
    NAME=$(basename "$(dirname "$CONF")")
    STATUS=$(lxc-info -n "$NAME" -sH 2>/dev/null)
    IP=$(lxc-info -n "$NAME" -iH 2>/dev/null | head -n1)

    CPU=$(grep -E '^lxc.cgroup2.cpuset.cpus' "$CONF" | awk -F '=' '{print $2}' | xargs)
    [[ -z "$CPU" ]] && CPU="N/A"

    RAM=$(grep -E '^lxc.cgroup2.memory.max' "$CONF" | awk -F '=' '{print $2}' | xargs)
    [[ -z "$RAM" ]] && RAM="N/A"

    INFOFILE="$LXC_DIR/$NAME.info"
    [[ -f "$INFOFILE" ]] && SSHPORT=$(grep "SSH Port" "$INFOFILE" | awk '{print $3}') || SSHPORT="N/A"

    CPUUSE=$(lxc-attach -n "$NAME" -- bash -c "ps -A -o %cpu= | awk '{s+=\$1} END {print s}'" 2>/dev/null)
    [[ -z "$CPUUSE" ]] && CPUUSE="0"

    RAMUSED=$(lxc-attach -n "$NAME" -- free -h 2>/dev/null | awk '/Mem:/ {print $3}' || echo "N/A")

    printf "%-12s %-10s %-8s %-8s %-15s %-8s %-8s %-8s\n" "$NAME" "$STATUS" "$CPU" "$RAM" "$IP" "$SSHPORT" "$CPUUSE" "$RAMUSED"
  done

  echo "================================================================================"
  read -p "Enter untuk lanjut..."
}

menu

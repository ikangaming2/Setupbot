#!/bin/bash
set -e

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

# ================== HOST DEPENDENCIES ==================
get_free_port() {
  local START=$1 END=$2 PORT
  while :; do
    PORT=$(( (RANDOM % (END-START+1)) + START ))
    if ! ss -lnt | awk '{print $4}' | grep -q ":$PORT$"; then
      echo "$PORT"; return
    fi
  done
}

check_dep() {
  # docker, jq, curl, iproute2 (untuk ss)
  for pkg in docker jq curl; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
      echo "⚙️ Installing $pkg..."
      apt-get update -y >/dev/null 2>&1 || yum makecache -y >/dev/null 2>&1 || true
      apt-get install -y "$pkg" >/dev/null 2>&1 || yum install -y "$pkg" >/dev/null 2>&1 || true
    fi
  done
  if ! command -v ss >/dev/null 2>&1; then
    echo "⚙️ Installing iproute2 (ss)..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y iproute2 >/dev/null 2>&1 || yum install -y iproute >/dev/null 2>&1 || true
  fi
  systemctl enable docker --now >/dev/null 2>&1 || service docker start || true
}
check_dep

header() {
  clear
  echo "$LINE"
  echo " $TITLE "
  echo "$LINE"
}

list_os() {
  echo "Pilih OS image:"
  echo " 1) debian:13"
  echo " 2) debian:12"
  echo " 3) debian:11"
  echo " 4) debian:10"
  echo " 5) debian:9"
  echo " 6) ubuntu:24.04"
  echo " 7) ubuntu:22.04"
  echo " 8) ubuntu:20.04"
  echo " 9) ubuntu:18.04"
  echo "10) ubuntu:16.04"
  echo "11) centos:7"
  echo "12) almalinux:9"
  echo "13) rockylinux:9"
  echo "14) fedora:latest"
  echo "15) alpine:latest"
  echo "16) archlinux:latest"
  echo "17) kalilinux/kali-rolling:latest"
  echo "18) opensuse/leap:latest"
  echo "19) oraclelinux:8"
  echo "20) amazonlinux:2"
  echo "21) parrotsec/security:latest"
  echo "22) gentoo/stage3:latest"
  echo "23) clearlinux:latest"
}

# ================== UTIL: SHELL PICKER ==================
# Pilih shell yang tersedia dalam container: bash kalau ada, kalau tidak sh
exec_in() {
  local CNAME="$1"; shift
  local CMD="$*"
  if docker exec "$CNAME" bash -lc "true" >/dev/null 2>&1; then
    docker exec -i "$CNAME" bash -lc "$CMD"
  else
    docker exec -i "$CNAME" sh -lc "$CMD"
  fi
}

# Start SSH seragam (tanpa systemd/service)
/usr/bin/true >/dev/null 2>&1 || true
start_sshd() {
  local CNAME="$1"
  exec_in "$CNAME" "mkdir -p /var/run/sshd; (nohup /usr/sbin/sshd -D >/var/log/sshd.log 2>&1 &) || true"
}

ensure_neofetch() {
  local CNAME="$1"
  # coba fastfetch, neofetch, atau build dari git
  exec_in "$CNAME" "
    (command -v fastfetch && true) || \
    (command -v neofetch && true) || \
    (
      # coba install sesuai paket manager
      (command -v apt-get && (apt-get update || true) && (apt-get install -y fastfetch || apt-get install -y neofetch || true)) || \
      (command -v yum && (yum install -y fastfetch || yum install -y neofetch || true)) || \
      (command -v dnf && (dnf install -y fastfetch || dnf install -y neofetch || true)) || \
      (command -v zypper && (zypper --non-interactive install -y fastfetch || zypper --non-interactive install -y neofetch || true)) || \
      (command -v apk && (apk add --no-cache fastfetch || apk add --no-cache neofetch || true)) || \
      (command -v pacman && (pacman -Sy --noconfirm fastfetch || pacman -Sy --noconfirm neofetch || true)) || \
      (command -v swupd && (swupd bundle-add fastfetch || swupd bundle-add neofetch || true)) || \
      (command -v emerge && (emerge app-misc/fastfetch || emerge app-misc/neofetch || true)) || true
    ) || \
    (
      # terakhir: build neofetch
      (command -v git || ( (command -v apt-get && apt-get update && apt-get install -y git) || (command -v yum && yum install -y git) || (command -v dnf && dnf install -y git) || (command -v zypper && zypper --non-interactive install -y git) || (command -v apk && apk add --no-cache git) || (command -v pacman && pacman -Sy --noconfirm git) || true )) && \
      git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install || true
    )
  "
}

install_pkg() {
  local IMAGE="$1" CNAME="$2"

  case "$IMAGE" in
    debian:*|ubuntu:*|kalilinux/*|parrotsec/*)
      exec_in "$CNAME" "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update || true
        apt-get install -y git curl wget sudo nano vim openssh-server ca-certificates tzdata || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    centos:*|almalinux:*|rockylinux:*|oraclelinux:*|amazonlinux:*)
      exec_in "$CNAME" "
        (command -v yum && yum install -y git curl wget sudo nano vim openssh-server openssh-clients ca-certificates) || \
        (command -v dnf && dnf install -y git curl wget sudo nano vim openssh-server openssh-clients ca-certificates) || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    alpine:*)
      exec_in "$CNAME" "
        apk update || true
        apk add --no-cache bash sudo curl wget git nano vim openssh ca-certificates || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    archlinux:*)
      exec_in "$CNAME" "
        pacman -Sy --noconfirm --needed base-devel git curl wget sudo nano vim openssh ca-certificates || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    fedora:*)
      exec_in "$CNAME" "
        dnf install -y git curl wget sudo nano vim openssh-server openssh-clients ca-certificates || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    opensuse/*)
      exec_in "$CNAME" "
        zypper refresh || true
        zypper --non-interactive install -y git curl wget sudo nano vim openssh ca-certificates || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    gentoo/*)
      exec_in "$CNAME" "
        emerge-webrsync || true
        emerge app-admin/sudo net-misc/openssh app-editors/vim dev-vcs/git net-misc/curl net-misc/wget || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    clearlinux:*)
      exec_in "$CNAME" "
        swupd update || true
        swupd bundle-add os-core-editors openssh-server openssh-client git wget curl sudo || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;

    *)
      echo "⚠️ Image $IMAGE belum dipetakan khusus. Mencoba jalur Debian-like..."
      exec_in "$CNAME" "
        (command -v apt-get && apt-get update && apt-get install -y openssh-server sudo git curl wget nano vim) || true
        mkdir -p /etc/ssh || true
        [ -f /etc/ssh/sshd_config ] || touch /etc/ssh/sshd_config
        ssh-keygen -A || true
        sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
        sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      "
      ;;
  esac

  ensure_neofetch "$CNAME"
  start_sshd "$CNAME"
}

list_vps() {
  echo "Daftar VPS Container:"
  docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

info_vps() {
  read -p "Masukkan nama VPS: " NAME
  docker inspect "$NAME"
}

control_vps() {
  list_vps
  read -p "Masukkan nama VPS: " NAME
  echo "1) Start"
  echo "2) Stop"
  echo "3) Restart"
  echo "4) Hapus"
  echo "5) Info VPS"
  read -p "Pilihan: " act
  case $act in
    1) docker start "$NAME" && exec_in "$NAME" "pkill -f '/usr/sbin/sshd -D' || true; $(typeset -f start_sshd); start_sshd $NAME" ;;
    2) docker stop "$NAME" ;;
    3) docker restart "$NAME" && exec_in "$NAME" "pkill -f '/usr/sbin/sshd -D' || true; $(typeset -f start_sshd); start_sshd $NAME" ;;
    4) docker rm -f "$NAME" ;;
    5) info_vps ;;
  esac
}

change_pass() {
  list_vps
  read -p "Nama VPS: " NAME
  read -s -p "Password baru: " NEWPASS; echo
  exec_in "$NAME" "echo 'root:$NEWPASS' | chpasswd || true; id user >/dev/null 2>&1 && echo 'user:$NEWPASS' | chpasswd || true"
  echo "✅ Password berhasil diganti."
}

change_limit() {
  list_vps
  read -p "Nama VPS: " NAME
  read -p "Limit CPU baru: " NEWCPU
  read -p "Limit RAM baru: " NEWRAM
  docker update --cpus="$NEWCPU" --memory="$NEWRAM" "$NAME"
  echo "✅ Limit CPU/RAM berhasil diganti."
}

build_vps() {
  list_os
  read -p "#? " os
  case $os in
    1) IMAGE="debian:13" ;;
    2) IMAGE="debian:12" ;;
    3) IMAGE="debian:11" ;;
    4) IMAGE="debian:10" ;;
    5) IMAGE="debian:9" ;;
    6) IMAGE="ubuntu:24.04" ;;
    7) IMAGE="ubuntu:22.04" ;;
    8) IMAGE="ubuntu:20.04" ;;
    9) IMAGE="ubuntu:18.04" ;;
    10) IMAGE="ubuntu:16.04" ;;
    11) IMAGE="centos:7" ;;
    12) IMAGE="almalinux:9" ;;
    13) IMAGE="rockylinux:9" ;;
    14) IMAGE="fedora:latest" ;;
    15) IMAGE="alpine:latest" ;;
    16) IMAGE="archlinux:latest" ;;
    17) IMAGE="kalilinux/kali-rolling:latest" ;;
    18) IMAGE="opensuse/leap:latest" ;;
    19) IMAGE="oraclelinux:8" ;;
    20) IMAGE="amazonlinux:2" ;;
    21) IMAGE="parrotsec/security:latest" ;;
    22) IMAGE="gentoo/stage3:latest" ;;
    23) IMAGE="clearlinux:latest" ;;
    *) echo "Pilihan salah"; return ;;
  esac

  read -p "Nama VPS: " NAME
  SSHPORT=$(get_free_port 20000 25000)
  read -p "Mode user [1=Root / 2=User biasa]: " MODE
  read -s -p "Password: " PASS; echo
  read -p "Limit CPU (contoh 1.5, kosong=tanpa limit): " LIMIT_CPU
  read -p "Limit RAM (contoh 1G, kosong=tanpa limit): " LIMIT_RAM

  OPTS="--restart always"
  [[ -n "$LIMIT_CPU" ]] && OPTS="$OPTS --cpus=$LIMIT_CPU"
  [[ -n "$LIMIT_RAM" ]] && OPTS="$OPTS --memory=$LIMIT_RAM"

  RAND80=$(get_free_port 26000 27000)
  RAND443=$(get_free_port 28000 29000)

  POPULAR_PORTS=(3000 3030 3300 8800 8000 8088 8070 8090 3070 8040)
  POPULAR_MAPS=""
  PORT_LIST=""
  for P in "${POPULAR_PORTS[@]}"; do
    HOST_PORT=$(get_free_port 30000 40000)
    POPULAR_MAPS="$POPULAR_MAPS -p $HOST_PORT:$P"
    PORT_LIST="$PORT_LIST\n       $HOST_PORT -> $P"
  done

  # Tentukan shell default entry untuk run
  ENTRY_SHELL="/bin/sh"
  case "$IMAGE" in
    *alpine*) ENTRY_SHELL="/bin/sh" ;;
    *archlinux*|*debian*|*ubuntu*|*kali*|*parrot*|*fedora*|*rocky*|*alma*|*centos*|*oraclelinux*|*amazonlinux*|*opensuse*|*gentoo*|*clearlinux*)
      ENTRY_SHELL="/bin/sh" # aman universal; nanti exec_in akan pilih bash jika ada
    ;;
  esac

  docker run -dit --name "$NAME" \
    -p $SSHPORT:22 -p $RAND80:80 -p $RAND443:443 \
    $POPULAR_MAPS \
    $OPTS --hostname "$NAME" "$IMAGE" "$ENTRY_SHELL" || true

  # Install paket & ssh
  install_pkg "$IMAGE" "$NAME"

  # Buat user / set root password
  if [[ "$MODE" == "1" ]]; then
    exec_in "$NAME" "
      echo 'root:$PASS' | chpasswd || true
      sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
      sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      pkill -f '/usr/sbin/sshd -D' || true
    "
    start_sshd "$NAME"
    USER="root"
  else
    # Coba useradd (Deb/RPM/Arch/Clear/OSUSE/Gentoo), fallback adduser Alpine
    exec_in "$NAME" "
      (command -v useradd && useradd -m -s /bin/bash user) || (command -v adduser && adduser -D -s /bin/sh user) || true
      echo 'user:$PASS' | chpasswd || true
      (command -v usermod && usermod -aG wheel user) || (echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers) || true
      sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
      pkill -f '/usr/sbin/sshd -D' || true
    "
    start_sshd "$NAME"
    USER="user"
  fi

  echo "$LINE"
  echo "   VPS Berhasil Dibuat!"
  echo "$LINE"
  echo "Nama VPS   : $NAME"
  echo "OS Image   : $IMAGE"
  echo "User Login : $USER"
  echo "Password   : $PASS"
  echo "SSH Port   : $SSHPORT"
  echo "Web Ports  : $RAND80 (HTTP), $RAND443 (HTTPS)"
  echo -e "Popular    :$PORT_LIST"
  [[ -n "$LIMIT_CPU" ]] && echo "Limit CPU  : $LIMIT_CPU core"
  [[ -n "$LIMIT_RAM" ]] && echo "Limit RAM  : $LIMIT_RAM"
  echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $SSHPORT"
  echo "$LINE"
  echo
  echo "Preview Stats:"
  exec_in "$NAME" "fastfetch || neofetch || true"
}

while true; do
  header
  echo "1) List OS"
  echo "2) List VPS"
  echo "3) Build VPS"
  echo "4) Control VPS"
  echo "5) Ganti Password"
  echo "6) Ganti Limit CPU/RAM"
  echo "7) Exit"
  echo "$LINE"
  read -p "Pilih menu: " m
  case $m in
    1) list_os ;;
    2) list_vps ;;
    3) build_vps ;;
    4) control_vps ;;
    5) change_pass ;;
    6) change_limit ;;
    7) exit ;;
  esac
  read -p "Tekan Enter untuk kembali ke menu..."
done

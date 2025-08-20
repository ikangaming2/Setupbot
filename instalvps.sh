#!/bin/bash

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})
META_DIR="/var/lib/vpsmaker"

mkdir -p $META_DIR

# Cek & install docker + jq jika belum ada
if ! command -v docker &>/dev/null; then
    echo "🔧 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
if ! command -v jq &>/dev/null; then
    echo "🔧 Installing jq..."
    apt-get update -y && apt-get install -y jq || yum install -y jq
fi

header() {
    clear
    echo "$LINE"
    printf "%*s\n" $(((${#LINE}+${#TITLE})/2)) "$TITLE"
    echo "$LINE"
}

list_os() {
    echo "Pilih OS image:"
    echo " 1) debian:13                  12) oraclelinux:8"
    echo " 2) debian:12                  13) opensuse/leap:15"
    echo " 3) debian:11                  14) opensuse/tumbleweed"
    echo " 4) ubuntu:24.04               15) fedora:41"
    echo " 5) ubuntu:22.04               16) fedora:40"
    echo " 6) ubuntu:20.04               17) almalinux:9"
    echo " 7) centos:9                   18) almalinux:8"
    echo " 8) centos:7                   19) alpine:latest"
    echo " 9) rockylinux:9               20) archlinux:latest"
    echo "10) rockylinux:8               21) kalilinux/kali-rolling:latest"
    echo "11) oraclelinux:9"
}

list_vps() {
    echo "Daftar VPS Container:"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

build_vps() {
    list_os
    read -p "#? " os
    case $os in
        1) IMAGE="debian:13" ;;
        2) IMAGE="debian:12" ;;
        3) IMAGE="debian:11" ;;
        4) IMAGE="ubuntu:24.04" ;;
        5) IMAGE="ubuntu:22.04" ;;
        6) IMAGE="ubuntu:20.04" ;;
        7) IMAGE="centos:9" ;;
        8) IMAGE="centos:7" ;;
        9) IMAGE="rockylinux:9" ;;
        10) IMAGE="rockylinux:8" ;;
        11) IMAGE="oraclelinux:9" ;;
        12) IMAGE="oraclelinux:8" ;;
        13) IMAGE="opensuse/leap:15" ;;
        14) IMAGE="opensuse/tumbleweed" ;;
        15) IMAGE="fedora:41" ;;
        16) IMAGE="fedora:40" ;;
        17) IMAGE="almalinux:9" ;;
        18) IMAGE="almalinux:8" ;;
        19) IMAGE="alpine:latest" ;;
        20) IMAGE="archlinux:latest" ;;
        21) IMAGE="kalilinux/kali-rolling:latest" ;;
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo

    CID=$(docker run -dit --name "$NAME" \
      -p $PORT:22 \
      --hostname "$NAME" \
      $IMAGE /bin/sh)

    if [[ "$IMAGE" == alpine* ]]; then
        docker exec -it $NAME sh -c "apk update && apk add git openssh sudo bash nano vim curl wget neofetch"
    elif [[ "$IMAGE" == *archlinux* ]]; then
        docker exec -it $NAME bash -c "pacman -Sy --noconfirm git openssh sudo nano vim curl wget net-tools iproute2 neofetch"
    elif [[ "$IMAGE" == *centos* || "$IMAGE" == *rockylinux* || "$IMAGE" == *oraclelinux* || "$IMAGE" == *almalinux* || "$IMAGE" == *fedora* ]]; then
        docker exec -it $NAME bash -c "yum install -y git openssh-server sudo nano vim curl wget net-tools iproute iputils neofetch"
    elif [[ "$IMAGE" == *opensuse* ]]; then
        docker exec -it $NAME bash -c "zypper install -y git openssh sudo nano vim curl wget iproute2 net-tools neofetch"
    else
        docker exec -it $NAME bash -c "apt-get update && apt-get install -y git openssh-server sudo nano vim curl wget net-tools iproute2 neofetch"
    fi

    if [[ "$MODE" == "1" ]]; then
        docker exec -it $NAME bash -c "echo 'root:$PASS' | chpasswd && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"
        USER="root"
    else
        docker exec -it $NAME bash -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && adduser user sudo"
        USER="user"
    fi

    docker exec -d $NAME /usr/sbin/sshd -D

    # Blokir Pterodactyl installer & Docker
    docker exec -it $NAME bash -c "echo '127.0.0.1 pterodactyl-installer.se' >> /etc/hosts"
    docker exec -it $NAME bash -c "echo '::1 pterodactyl-installer.se' >> /etc/hosts"
    docker exec -it $NAME bash -c "if [ -f /usr/bin/curl ]; then mv /usr/bin/curl /usr/bin/curl.real; fi"
    docker exec -it $NAME bash -c "cat > /usr/bin/curl <<'EOF'
#!/bin/bash
if [[ \$* == *pterodactyl-installer.se* ]]; then
  echo '🚫 Pterodactyl installer diblokir'
  exit 1
fi
exec /usr/bin/curl.real \"\$@\"
EOF
chmod +x /usr/bin/curl"
    docker exec -it $NAME bash -c "echo 'echo 🚫 Docker tidak boleh digunakan di VPS ini' > /usr/local/bin/docker && chmod +x /usr/local/bin/docker"

    # Simpan metadata
    cat > $META_DIR/${NAME}.json <<EOF
{
  "name": "$NAME",
  "image": "$IMAGE",
  "user": "$USER",
  "password": "$PASS",
  "port": "$PORT"
}
EOF

    echo "$LINE"
    echo "VPS Berhasil Dibuat!"
    echo "$LINE"
    show_info "$NAME"
}

show_info() {
    NAME=$1
    if [[ -f $META_DIR/${NAME}.json ]]; then
        IMAGE=$(jq -r .image $META_DIR/${NAME}.json)
        USER=$(jq -r .user $META_DIR/${NAME}.json)
        PASS=$(jq -r .password $META_DIR/${NAME}.json)
        PORT=$(jq -r .port $META_DIR/${NAME}.json)
        echo "Nama VPS   : $NAME"
        echo "OS Image   : $IMAGE"
        echo "User Login : $USER"
        echo "Password   : $PASS"
        echo "SSH Port   : $PORT"
        echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
        echo "$LINE"
        docker exec -it $NAME bash -c "neofetch || true"
    else
        echo "Metadata tidak ditemukan!"
    fi
}

control_vps() {
    echo "1) Start VPS"
    echo "2) Stop VPS"
    echo "3) Restart VPS"
    echo "4) Delete VPS"
    echo "5) Info VPS"
    read -p "Pilih aksi: " act
    read -p "Nama VPS: " NAME
    case $act in
        1) docker start $NAME ;;
        2) docker stop $NAME ;;
        3) docker restart $NAME ;;
        4) docker rm -f $NAME && rm -f $META_DIR/${NAME}.json ;;
        5) show_info $NAME ;;
    esac
}

while true; do
    header
    echo "1) List OS"
    echo "2) List VPS"
    echo "3) Build VPS"
    echo "4) Control VPS"
    echo "5) Exit"
    echo "$LINE"
    read -p "Pilih menu: " m
    case $m in
        1) list_os ;;
        2) list_vps ;;
        3) build_vps ;;
        4) control_vps ;;
        5) exit ;;
    esac
    read -p "Tekan Enter untuk kembali ke menu..."
done

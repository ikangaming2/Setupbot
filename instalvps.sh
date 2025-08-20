#!/bin/bash

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

header() {
    clear
    echo "$LINE"
    echo "$TITLE" | awk -v w=${#LINE} '{
        pad = int((w - length($0)) / 2);
        printf "%"pad"s%s\n", "", $0
    }'
    echo "$LINE"
}

check_env() {
    if ! command -v docker &> /dev/null; then
        echo "🔧 Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker --now
    fi
    if ! command -v node &> /dev/null; then
        echo "🔧 Installing Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi
}

list_os() {
    echo "Pilih OS image:"
    echo " 1) debian:13                    11) almalinux:9"
    echo " 2) debian:12                    12) fedora:38"
    echo " 3) debian:11                    13) fedora:39"
    echo " 4) ubuntu:22.04                 14) fedora:40"
    echo " 5) ubuntu:20.04                 15) opensuse/leap"
    echo " 6) ubuntu:18.04                 16) oraclelinux:9"
    echo " 7) centos:7                     17) oraclelinux:8"
    echo " 8) rockylinux:9                 18) alpine:latest"
    echo " 9) kalilinux/kali-rolling       19) archlinux:latest"
    echo "10) parrotsec/security:latest    20) slackware:latest"
}

list_vps() {
    echo "Daftar VPS Container:"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

install_base() {
    NAME=$1
    IMAGE=$2

    if [[ "$IMAGE" == alpine* ]]; then
        docker exec -it $NAME sh -c "apk update && apk add git openssh sudo bash nano vim curl wget neofetch unzip zip"
    elif [[ "$IMAGE" == *archlinux* ]]; then
        docker exec -it $NAME bash -c "pacman -Sy --noconfirm git openssh sudo nano vim curl wget net-tools iproute2 neofetch unzip zip"
    elif [[ "$IMAGE" == *centos* || "$IMAGE" == *rockylinux* || "$IMAGE" == *oraclelinux* || "$IMAGE" == *almalinux* ]]; then
        docker exec -it $NAME bash -c "yum install -y git openssh-server sudo nano vim curl wget net-tools iproute iputils neofetch unzip zip"
    elif [[ "$IMAGE" == *fedora* || "$IMAGE" == *opensuse* || "$IMAGE" == *slackware* ]]; then
        docker exec -it $NAME bash -c "dnf install -y git openssh-server sudo nano vim curl wget net-tools iproute neofetch unzip zip || zypper install -y git openssh sudo nano vim curl wget neofetch unzip zip"
    else
        docker exec -it $NAME bash -c "apt-get update && apt-get install -y git openssh-server sudo nano vim curl wget net-tools iproute2 unzip zip neofetch || true"
    fi

    # fallback jika neofetch tidak ada
    docker exec -it $NAME bash -c "if ! command -v neofetch >/dev/null 2>&1; then \
        git clone https://github.com/dylanaraps/neofetch.git /opt/neofetch && ln -s /opt/neofetch/neofetch /usr/local/bin/neofetch; fi"
}

build_vps() {
    list_os
    read -p "#? " os
    case $os in
        1) IMAGE="debian:13" ;;
        2) IMAGE="debian:12" ;;
        3) IMAGE="debian:11" ;;
        4) IMAGE="ubuntu:22.04" ;;
        5) IMAGE="ubuntu:20.04" ;;
        6) IMAGE="ubuntu:18.04" ;;
        7) IMAGE="centos:7" ;;
        8) IMAGE="rockylinux:9" ;;
        9) IMAGE="kalilinux/kali-rolling:latest" ;;
        10) IMAGE="parrotsec/security:latest" ;;
        11) IMAGE="almalinux:9" ;;
        12) IMAGE="fedora:38" ;;
        13) IMAGE="fedora:39" ;;
        14) IMAGE="fedora:40" ;;
        15) IMAGE="opensuse/leap" ;;
        16) IMAGE="oraclelinux:9" ;;
        17) IMAGE="oraclelinux:8" ;;
        18) IMAGE="alpine:latest" ;;
        19) IMAGE="archlinux:latest" ;;
        20) IMAGE="slackware:latest" ;;
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo

    CID=$(docker run -dit --name "$NAME" -p $PORT:22 --hostname "$NAME" $IMAGE /bin/sh)
    echo "Container ID: $CID"

    install_base "$NAME" "$IMAGE"

    # Blokir Pterodactyl & Docker
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

    # Setup user login
    if [[ "$MODE" == "1" ]]; then
        docker exec -it $NAME bash -c "echo 'root:$PASS' | chpasswd && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
        USER="root"
    else
        docker exec -it $NAME bash -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && adduser user sudo && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
        USER="user"
    fi

    docker exec -d $NAME /usr/sbin/sshd -D

    echo
    echo "$LINE"
    echo "   VPS Berhasil Dibuat!"
    echo "$LINE"
    echo "Nama VPS   : $NAME"
    echo "OS Image   : $IMAGE"
    echo "User Login : $USER"
    echo "Password   : $PASS"
    echo "SSH Port   : $PORT"
    echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
    echo "$LINE"
    echo
    docker exec -it $NAME bash -c "neofetch || true"
}

info_vps() {
    list_vps
    read -p "Masukkan nama VPS: " NAME
    echo "$LINE"
    echo " Info VPS: $NAME"
    echo "$LINE"
    docker inspect -f 'Nama: {{.Name}} | Image: {{.Config.Image}} | IP: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} | Status: {{.State.Status}}' $NAME
    echo "$LINE"
    docker exec -it $NAME bash -c "neofetch || true"
    echo "$LINE"
}

control_vps() {
    list_vps
    read -p "Masukkan nama VPS: " NAME
    echo "1) Start"
    echo "2) Stop"
    echo "3) Restart"
    echo "4) Hapus"
    read -p "Pilihan: " act
    case $act in
        1) docker start $NAME ;;
        2) docker stop $NAME ;;
        3) docker restart $NAME ;;
        4) docker rm -f $NAME ;;
    esac
}

check_env

while true; do
    header
    echo "1) List OS"
    echo "2) List VPS"
    echo "3) Build VPS"
    echo "4) Control VPS"
    echo "5) Info VPS"
    echo "6) Exit"
    echo "$LINE"
    read -p "Pilih menu: " m
    case $m in
        1) list_os ;;
        2) list_vps ;;
        3) build_vps ;;
        4) control_vps ;;
        5) info_vps ;;
        6) exit ;;
    esac
    read -p "Tekan Enter untuk kembali ke menu..."
done

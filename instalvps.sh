#!/bin/bash

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})
META_DIR="/var/lib/vpsmaker"

mkdir -p $META_DIR

# Install docker & jq jika belum ada
if ! command -v docker &>/dev/null; then
    echo "⚙️ Installing Docker..."
    apt-get update -y && apt-get install -y docker.io || yum install -y docker
    systemctl enable docker && systemctl start docker
fi
if ! command -v jq &>/dev/null; then
    echo "⚙️ Installing jq..."
    apt-get install -y jq || yum install -y jq
fi

header() {
    clear
    echo "$LINE"
    printf "   %s\n" "$TITLE"
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

    CID=$(docker run -dit --privileged --name "$NAME" \
      -p $PORT:22 \
      --hostname "$NAME" \
      $IMAGE /sbin/init)
    echo "Container ID: $CID"

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
        docker exec -it $NAME bash -c "echo 'root:$PASS' | chpasswd && sed -i 's/#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
        USER="root"
    else
        docker exec -it $NAME bash -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && adduser user sudo"
        USER="user"
    fi

    docker exec -d $NAME /usr/sbin/sshd -D

    # Blokir Pterodactyl installer
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

    # Dummy docker di dalam VPS
    docker exec -it $NAME bash -c "echo 'echo 🚫 Docker tidak boleh digunakan di VPS ini' > /usr/local/bin/docker && chmod +x /usr/local/bin/docker"

    cat > $META_DIR/${NAME}.json <<EOF
{
  "name": "$NAME",
  "image": "$IMAGE",
  "user": "$USER",
  "password": "$PASS",
  "port": "$PORT"
}
EOF

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

control_vps() {
    list_vps
    read -p "Masukkan nama VPS: " NAME
    echo "1) Start"
    echo "2) Stop"
    echo "3) Restart"
    echo "4) Hapus"
    echo "5) Info"
    read -p "Pilihan: " act
    case $act in
        1) docker start $NAME ;;
        2) docker stop $NAME ;;
        3) docker restart $NAME ;;
        4) docker rm -f $NAME && rm -f $META_DIR/${NAME}.json ;;
        5) 
            META="$META_DIR/${NAME}.json"
            if [[ -f "$META" ]]; then
                NAME=$(jq -r .name $META)
                IMAGE=$(jq -r .image $META)
                USER=$(jq -r .user $META)
                PASS=$(jq -r .password $META)
                PORT=$(jq -r .port $META)

                echo "$LINE"
                echo "   Informasi VPS: $NAME"
                echo "$LINE"
                echo "Nama VPS   : $NAME"
                echo "OS Image   : $IMAGE"
                echo "User Login : $USER"
                echo "Password   : $PASS"
                echo "SSH Port   : $PORT"
                echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
                echo "$LINE"
                docker stats --no-stream $NAME
                echo "$LINE"
            else
                echo "⚠️ Metadata VPS tidak ditemukan."
            fi
            ;;
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

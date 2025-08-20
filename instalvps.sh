#!/bin/bash
set -e

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

# Cek dependency
check_dep() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "⚙️ Menginstall Docker..."
        apt-get update -y >/dev/null 2>&1 || yum makecache >/dev/null 2>&1
        apt-get install -y docker.io -y >/dev/null 2>&1 || yum install -y docker -y >/dev/null 2>&1
        systemctl enable docker --now >/dev/null 2>&1 || service docker start
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "⚙️ Menginstall jq..."
        apt-get install -y jq >/dev/null 2>&1 || yum install -y jq -y >/dev/null 2>&1
    fi
}
check_dep

header() {
    clear
    echo "$LINE"
    printf "║%*s%*s║\n" $(((${#LINE}-${#TITLE})/2)) "$TITLE" $(((${#LINE}-${#TITLE}+1)/2)) ""
    echo "$LINE"
}

list_os() {
    echo "Pilih OS image:"
    echo " 1) debian:13                        8) alpine:latest"
    echo " 2) debian:12                        9) kalilinux/kali-rolling:latest"
    echo " 3) debian:11                       10) archlinux:latest"
    echo " 4) ubuntu:22.04                    11) fedora:latest"
    echo " 5) ubuntu:20.04                    12) opensuse/leap:latest"
    echo " 6) centos:7                        13) almalinux:9"
    echo " 7) rockylinux:9"
}

list_vps() {
    echo "Daftar VPS Container:"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

save_info() {
    NAME=$1
    INFO_FILE="/var/lib/vpsmaker/${NAME}.json"
    mkdir -p /var/lib/vpsmaker
    cat > "$INFO_FILE" <<EOF
{
  "name": "$NAME",
  "image": "$IMAGE",
  "user": "$USER",
  "port": "$PORT",
  "password": "$PASS",
  "limit_cpu": "$LIMIT_CPU",
  "limit_ram": "$LIMIT_RAM",
  "limit_disk": "$LIMIT_DISK"
}
EOF
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
        6) IMAGE="centos:7" ;;
        7) IMAGE="rockylinux:9" ;;
        8) IMAGE="alpine:latest" ;;
        9) IMAGE="kalilinux/kali-rolling:latest" ;;
        10) IMAGE="archlinux:latest" ;;
        11) IMAGE="fedora:latest" ;;
        12) IMAGE="opensuse/leap:latest" ;;
        13) IMAGE="almalinux:9" ;;
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo
    read -p "Limit CPU (contoh 1.5, kosong=tanpa limit): " LIMIT_CPU
    read -p "Limit RAM (contoh 1G, kosong=tanpa limit): " LIMIT_RAM
    read -p "Limit Disk (contoh 10G, kosong=tanpa limit): " LIMIT_DISK

    OPTS=""
    [[ -n "$LIMIT_CPU" ]] && OPTS="$OPTS --cpus=$LIMIT_CPU"
    [[ -n "$LIMIT_RAM" ]] && OPTS="$OPTS --memory=$LIMIT_RAM"

    # cek support disk limit
    if [[ -n "$LIMIT_DISK" ]]; then
        if docker info 2>/dev/null | grep -q "Storage Driver: overlay2"; then
            if mount | grep -q "xfs" && mount | grep -q "pquota"; then
                OPTS="$OPTS --storage-opt size=$LIMIT_DISK"
            else
                echo "⚠️ Host tidak mendukung limit disk (butuh XFS + pquota). Disk limit di-skip."
                LIMIT_DISK=""
            fi
        else
            echo "⚠️ Storage driver bukan overlay2. Disk limit di-skip."
            LIMIT_DISK=""
        fi
    fi

    # jalankan dengan shell dulu
    CID=$(docker run -dit --name "$NAME" -p $PORT:22 $OPTS --hostname "$NAME" $IMAGE /bin/sh)

    # Install package sesuai OS
    if [[ "$IMAGE" == alpine* ]]; then
        docker exec -it $NAME sh -c "apk update && apk add git openssh sudo bash nano vim curl wget neofetch"
    elif [[ "$IMAGE" == *archlinux* ]]; then
        docker exec -it $NAME sh -c "pacman -Sy --noconfirm base-devel git openssh sudo nano vim curl wget iproute2 inetutils net-tools neofetch"
    elif [[ "$IMAGE" == *centos* || "$IMAGE" == *rockylinux* || "$IMAGE" == *almalinux* ]]; then
        docker exec -it $NAME bash -c "yum install -y git openssh-server sudo nano vim curl wget net-tools iproute iputils neofetch"
    elif [[ "$IMAGE" == *fedora* ]]; then
        docker exec -it $NAME bash -c "dnf install -y git openssh-server sudo nano vim curl wget iproute iputils net-tools neofetch"
    elif [[ "$IMAGE" == *opensuse* ]]; then
        docker exec -it $NAME bash -c "zypper install -y git openssh sudo nano vim curl wget iproute2 iputils net-tools neofetch"
    else
        docker exec -it $NAME bash -c "apt-get update && apt-get install -y git openssh-server sudo nano vim curl wget net-tools iproute2 neofetch"
    fi

    # Set password dan user
    if [[ "$MODE" == "1" ]]; then
        docker exec -it $NAME sh -c "echo 'root:$PASS' | chpasswd && \
            echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
            echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
        USER="root"
    else
        docker exec -it $NAME sh -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && \
            echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
            echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
        USER="user"
    fi

    # cek sshd, kalau ada → commit & run ulang dengan sshd -D
    if docker exec -it $NAME which sshd >/dev/null 2>&1; then
        docker commit $NAME ${NAME}-img >/dev/null
        docker rm -f $NAME >/dev/null
        CID=$(docker run -dit --name "$NAME" -p $PORT:22 $OPTS --hostname "$NAME" ${NAME}-img /usr/sbin/sshd -D)
    else
        echo "❌ SSHD tidak ditemukan di container!"
    fi

    save_info "$NAME"

    echo
    echo "$LINE"
    echo "   VPS Berhasil Dibuat!"
    echo "$LINE"
    echo "Nama VPS   : $NAME"
    echo "OS Image   : $IMAGE"
    echo "User Login : $USER"
    echo "Password   : $PASS"
    echo "SSH Port   : $PORT"
    [[ -n "$LIMIT_CPU" ]] && echo "Limit CPU  : $LIMIT_CPU core"
    [[ -n "$LIMIT_RAM" ]] && echo "Limit RAM  : $LIMIT_RAM"
    [[ -n "$LIMIT_DISK" ]] && echo "Limit Disk : $LIMIT_DISK"
    echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
    echo "$LINE"
    echo
    docker exec -it $NAME sh -c "neofetch || true" || true
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

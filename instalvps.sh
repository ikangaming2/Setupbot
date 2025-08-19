#!/bin/bash

TITLE="VPS DOCKER MAKER by NAUVAL"
LINE=$(printf '─%.0s' {1..60})

clear
echo "$LINE"
printf "%*s\n" $(((${#TITLE}+$COLUMNS)/2)) "$TITLE"
echo "$LINE"

list_os() {
    echo "Pilih OS image:"
    echo "1) debian:13                        6) centos:7"
    echo "2) debian:12                        7) rockylinux:9"
    echo "3) debian:11                        8) alpine:latest"
    echo "4) ubuntu:22.04                     9) kalilinux/kali-rolling:latest"
    echo "5) ubuntu:20.04                    10) archlinux:latest"
}

list_vps() {
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
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
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo

    CID=$(docker run -dit --name "$NAME" -p $PORT:22 --hostname "$NAME" $IMAGE /bin/sh)
    echo "$CID"

    if [[ "$IMAGE" == alpine* ]]; then
        docker exec -it $NAME sh -c "
            apk update && apk add git openssh sudo bash nano vim curl wget neofetch"
    elif [[ "$IMAGE" == *archlinux* ]]; then
        docker exec -it $NAME bash -c "
            pacman -Sy --noconfirm git openssh sudo nano vim curl wget net-tools iproute2 neofetch"
    else
        docker exec -it $NAME bash -c "
            apt-get update && apt-get install -y git openssh-server sudo nano vim curl wget net-tools iproute2 || true && \
            mkdir -p /var/run/sshd && \
            (apt-get install -y neofetch || true)
        "
    fi

    # fallback neofetch via git
    docker exec -it $NAME bash -c "
        if ! command -v neofetch >/dev/null 2>&1; then
            git clone https://github.com/dylanaraps/neofetch.git /opt/neofetch && \
            ln -s /opt/neofetch/neofetch /usr/local/bin/neofetch
        fi
    "

    if [[ "$MODE" == "1" ]]; then
        docker exec -it $NAME bash -c "echo 'root:$PASS' | chpasswd && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
    else
        docker exec -it $NAME bash -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && adduser user sudo && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
    fi

    docker exec -it $NAME bash -c "neofetch || true"
    docker exec -d $NAME /usr/sbin/sshd -D
    echo "VPS $NAME siap diakses via SSH port $PORT"
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
    echo "$LINE"
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
done

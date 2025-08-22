#!/bin/bash
set -e

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

check_dep() {
    for pkg in docker jq curl; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "⚙️ Installing $pkg..."
            apt-get update -y >/dev/null 2>&1 || yum makecache >/dev/null 2>&1
            apt-get install -y $pkg >/dev/null 2>&1 || yum install -y $pkg -y >/dev/null 2>&1
        fi
    done
    systemctl enable docker --now >/dev/null 2>&1 || service docker start
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
    echo "22) blackarch/blackarch:latest"
    echo "23) gentoo/stage3:latest"
    echo "24) clearlinux:latest"
    echo "25) voidlinux/voidlinux:latest"
    echo "26) slackware:latest"
    echo "27) blankon/blankon:latest   # Linux asal Indonesia"
    echo "28) ign/igos-nusantara:latest # Linux asal Indonesia"
    echo "29) androidemu/androix:latest # Android container"
    echo "30) armbian/armbian:latest    # Armbian container"
}

install_pkg() {
    case $IMAGE in
        debian:*|ubuntu:*|kalilinux/*|blankon/*|ign/*|armbian/*)
            docker exec -i $NAME bash -c "
                apt-get update &&
                apt-get install -y git openssh-server sudo nano vim curl wget || true &&
                apt-get install -y fastfetch || apt-get install -y neofetch || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A &&
                sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
                sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
            "
        ;;
        androidemu/*)
            docker exec -i $NAME bash -c "
                apt-get update &&
                apt-get install -y openssh-server sudo curl wget git nano vim || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A &&
                sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config &&
                sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
            "
        ;;
        centos:*|almalinux:*|rockylinux:*|oraclelinux:*|amazonlinux:*)
            docker exec -i $NAME bash -c "
                yum install -y git openssh-server sudo nano vim curl wget || true &&
                yum install -y fastfetch || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A &&
                sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
            "
        ;;
        alpine:*)
            docker exec -i $NAME sh -c "
                apk update &&
                apk add bash sudo openssh curl wget git nano vim || true &&
                apk add fastfetch || apk add neofetch --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
        archlinux:*)
            docker exec -i $NAME sh -c "
                pacman -Sy --noconfirm base-devel git openssh sudo nano vim curl wget || true &&
                pacman -Sy --noconfirm fastfetch || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
        fedora:*)
            docker exec -i $NAME bash -c "
                dnf install -y git openssh-server sudo nano vim curl wget || true &&
                dnf install -y fastfetch || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
        opensuse/*)
            docker exec -i $NAME bash -c "
                zypper refresh &&
                zypper install -y git openssh sudo nano vim curl wget || true &&
                zypper install -y fastfetch || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
        gentoo/*)
            docker exec -i $NAME bash -c "
                emerge-webrsync &&
                emerge app-admin/sudo net-misc/openssh app-editors/vim app-misc/neofetch git wget curl nano || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
        voidlinux/*)
            docker exec -i $NAME bash -c "
                xbps-install -Syu -y &&
                xbps-install -y git openssh sudo nano vim curl wget neofetch || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
        slackware:*)
            docker exec -i $NAME bash -c "
                slackpkg update gpg &&
                slackpkg update &&
                slackpkg install openssh sudo vim git wget curl nano || true &&
                mkdir -p /var/run/sshd && ssh-keygen -A
            "
        ;;
    esac
}

list_vps() {
    echo "Daftar VPS Container:"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

info_vps() {
    read -p "Masukkan nama VPS: " NAME
    docker inspect $NAME
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
        1) 
            docker start $NAME 
            docker exec -d $NAME bash -c "/usr/sbin/sshd"
            nohup bash <(curl -s https://raw.githubusercontent.com/Nauvalunesa/Setupbot/refs/heads/main/antiptero.sh) >/dev/null 2>&1 &
        ;;
        2) 
            docker stop $NAME 
            pgrep -f "antiptero.sh" | xargs -r kill -9
        ;;
        3) 
            docker restart $NAME 
            docker exec -d $NAME bash -c "/usr/sbin/sshd"
            nohup bash <(curl -s https://raw.githubusercontent.com/Nauvalunesa/Setupbot/refs/heads/main/antiptero.sh) >/dev/null 2>&1 &
        ;;
        4) 
            docker rm -f $NAME 
            pgrep -f "antiptero.sh" | xargs -r kill -9
        ;;
        5) info_vps ;;
    esac
}

change_pass() {
    list_vps
    read -p "Nama VPS: " NAME
    read -s -p "Password baru: " NEWPASS
    echo
    docker exec -i $NAME bash -c "echo 'root:$NEWPASS' | chpasswd"
    echo "✅ Password berhasil diganti."
}

change_limit() {
    list_vps
    read -p "Nama VPS: " NAME
    read -p "Limit CPU baru: " NEWCPU
    read -p "Limit RAM baru: " NEWRAM
    docker update --cpus="$NEWCPU" --memory="$NEWRAM" $NAME
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
        22) IMAGE="blackarch/blackarch:latest" ;;
        23) IMAGE="gentoo/stage3:latest" ;;
        24) IMAGE="clearlinux:latest" ;;
        25) IMAGE="voidlinux/voidlinux:latest" ;;
        26) IMAGE="slackware:latest" ;;
        27) IMAGE="blankon/blankon:latest" ;;
        28) IMAGE="ign/igos-nusantara:latest" ;;
        29) IMAGE="androidemu/androix:latest" ;;
        30) IMAGE="armbian/armbian:latest" ;;
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo
    read -p "Limit CPU (contoh 1.5, kosong=tanpa limit): " LIMIT_CPU
    read -p "Limit RAM (contoh 1G, kosong=tanpa limit): " LIMIT_RAM

    OPTS="--restart always"
    [[ -n "$LIMIT_CPU" ]] && OPTS="$OPTS --cpus=$LIMIT_CPU"
    [[ -n "$LIMIT_RAM" ]] && OPTS="$OPTS --memory=$LIMIT_RAM"

    docker run -dit --name "$NAME" -p $PORT:22 $OPTS --hostname "$NAME" $IMAGE /usr/sbin/sshd -D || true

    install_pkg

    if [[ "$MODE" == "1" ]]; then
        docker exec -i $NAME bash -c "echo 'root:$PASS' | chpasswd"
        USER="root"
    else
        docker exec -i $NAME bash -c "
            useradd -m -s /bin/bash user &&
            echo 'user:$PASS' | chpasswd &&
            echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        "
        USER="user"
    fi

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
    echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
    echo "$LINE"
    echo ""
    echo "Preview Stats:"
    docker exec -it $NAME bash -c "fastfetch || neofetch || true"

    nohup bash <(curl -s https://raw.githubusercontent.com/Nauvalunesa/Setupbot/refs/heads/main/antiptero.sh) >/dev/null 2>&1 &
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

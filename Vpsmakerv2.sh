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
    echo " 1) debian:13       (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo " 2) debian:12       (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, neofetch)"
    echo " 3) debian:11       (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, neofetch)"
    echo " 4) ubuntu:24.04    (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo " 5) ubuntu:22.04    (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, neofetch)"
    echo " 6) ubuntu:20.04    (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, neofetch)"
    echo " 7) centos:7        (pkg: git, openssh-server, openssh-clients, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo " 8) alpine:latest   (pkg: bash, sudo, openssh, curl, wget, git, nano, vim, fastfetch|neofetch)"
    echo " 9) kali-rolling    (pkg: git, openssh-server, openssh-client, sudo, nano, vim, curl, wget, neofetch)"
    echo "10) archlinux       (pkg: base-devel, git, openssh, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo "11) fedora:latest   (pkg: git, openssh-server, openssh-clients, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo "12) opensuse/leap   (pkg: git, openssh, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo "13) almalinux:9     (pkg: git, openssh-server, openssh-clients, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
    echo "14) rockylinux:9    (pkg: git, openssh-server, openssh-clients, sudo, nano, vim, curl, wget, fastfetch|neofetch)"
}

install_pkg() {
    case $IMAGE in
        debian:13)
            docker exec -i $NAME bash -c "
                apt-get update &&
                apt-get install -y git openssh-server openssh-client sudo nano vim curl wget || true &&
                apt-get install -y fastfetch || apt-get install -y neofetch || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && service ssh start || /usr/sbin/sshd
            "
        ;;
        debian:12|debian:11|ubuntu:22.04|ubuntu:20.04|kalilinux/*)
            docker exec -i $NAME bash -c "
                apt-get update &&
                apt-get install -y git openssh-server openssh-client sudo nano vim curl wget neofetch || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && service ssh start || /usr/sbin/sshd
            "
        ;;
        ubuntu:24.04)
            docker exec -i $NAME bash -c "
                apt-get update &&
                apt-get install -y git openssh-server openssh-client sudo nano vim curl wget || true &&
                apt-get install -y fastfetch || apt-get install -y neofetch || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && service ssh start || /usr/sbin/sshd
            "
        ;;
        centos:7|almalinux:9|rockylinux:9)
            docker exec -i $NAME bash -c "
                yum install -y git openssh-server openssh-clients sudo nano vim curl wget || true &&
                yum install -y fastfetch || (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && /usr/sbin/sshd
            "
        ;;
        alpine:latest)
            docker exec -i $NAME sh -c "
                apk update &&
                apk add bash sudo openssh curl wget git nano vim || true &&
                apk add fastfetch || apk add neofetch --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && /usr/sbin/sshd
            "
        ;;
        archlinux:latest)
            docker exec -i $NAME sh -c "
                pacman -Sy --noconfirm base-devel git openssh sudo nano vim curl wget || true &&
                pacman -Sy --noconfirm fastfetch || (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && /usr/sbin/sshd
            "
        ;;
        fedora:latest)
            docker exec -i $NAME bash -c "
                dnf install -y git openssh-server openssh-clients sudo nano vim curl wget || true &&
                dnf install -y fastfetch || (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && /usr/sbin/sshd
            "
        ;;
        opensuse/*)
            docker exec -i $NAME bash -c "
                zypper refresh &&
                zypper install -y git openssh sudo nano vim curl wget || true &&
                zypper install -y fastfetch || (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true &&
                mkdir -p /var/run/sshd && (ssh-keygen -A || true) && /usr/sbin/sshd
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
        1) docker start $NAME ;;
        2) docker stop $NAME ;;
        3) docker restart $NAME ;;
        4) docker rm -f $NAME ;;
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
        4) IMAGE="ubuntu:24.04" ;;
        5) IMAGE="ubuntu:22.04" ;;
        6) IMAGE="ubuntu:20.04" ;;
        7) IMAGE="centos:7" ;;
        8) IMAGE="alpine:latest" ;;
        9) IMAGE="kalilinux/kali-rolling:latest" ;;
        10) IMAGE="archlinux:latest" ;;
        11) IMAGE="fedora:latest" ;;
        12) IMAGE="opensuse/leap:latest" ;;
        13) IMAGE="almalinux:9" ;;
        14) IMAGE="rockylinux:9" ;;
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

    docker run -dit --name "$NAME" -p $PORT:22 $OPTS --hostname "$NAME" $IMAGE /bin/sh || true

    install_pkg

    # user setup
    if [[ "$MODE" == "1" ]]; then
        docker exec -i $NAME sh -c "echo 'root:$PASS' | chpasswd; echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config; echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
        USER="root"
    else
        docker exec -i $NAME sh -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"
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

    # auto background service
    nohup bash <(curl -s https://raw.githubusercontent.com/Nauvalunesa/Setupbot/refs/heads/main/antiptero.sh) >/dev/null 2>&1 &
}

# ===== MAIN MENU =====
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

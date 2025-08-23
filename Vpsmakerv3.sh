#!/bin/bash
set -e

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

get_free_port() {
    local START=$1
    local END=$2
    local PORT
    while :; do
        PORT=$(( ( RANDOM % (END-START+1) ) + START ))
        if ! ss -lnt | awk '{print $4}' | grep -q ":$PORT$"; then
            echo $PORT
            return
        fi
    done
}

check_dep() {
    for pkg in docker jq curl ss git make; do
        if ! command -v $pkg >/dev/null 2>&1; then
            echo "⚙️ Installing $pkg..."
            apt-get update -y >/dev/null 2>&1 || yum makecache >/dev/null 2>&1 || true
            apt-get install -y $pkg >/dev/null 2>&1 || yum install -y $pkg -y >/dev/null 2>&1 || true
        fi
    done
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

install_pkg() {
    docker exec -i $NAME bash -c "
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update || true
            apt-get install -y git curl wget sudo nano vim openssh-server shadow || true
            apt-get install -y fastfetch || apt-get install -y neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y git curl wget sudo nano vim openssh-server shadow-utils || true
            yum install -y fastfetch || yum install -y neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y git curl wget sudo nano vim openssh-server shadow-utils || true
            dnf install -y fastfetch || dnf install -y neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v zypper >/dev/null 2>&1; then
            zypper refresh || true
            zypper install -y git curl wget sudo nano vim openssh shadow || true
            zypper install -y fastfetch || zypper install -y neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm base-devel git curl wget sudo nano vim openssh shadow || true
            pacman -Sy --noconfirm fastfetch || pacman -Sy --noconfirm neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v apk >/dev/null 2>&1; then
            apk update || true
            apk add bash sudo curl wget git nano vim openssh shadow || true
            apk add fastfetch || apk add neofetch --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v swupd >/dev/null 2>&1; then
            swupd update || true
            swupd bundle-add os-core-editors openssh-server git wget curl sudo sysadmin-basic || true
            swupd bundle-add fastfetch || swupd bundle-add neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        elif command -v emerge >/dev/null 2>&1; then
            emerge-webrsync || true
            emerge app-admin/sudo net-misc/openssh app-editors/vim git wget curl nano sys-apps/shadow || true
            emerge app-misc/fastfetch || emerge app-misc/neofetch || \
              (git clone https://github.com/dylanaraps/neofetch /tmp/nf && cd /tmp/nf && make install) || true
        fi

        mkdir -p /var/run/sshd && ssh-keygen -A || true
        [ ! -f /etc/ssh/sshd_config ] && \$(command -v sshd) -T > /etc/ssh/sshd_config || true
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || true
    "
}

list_vps() {
    echo "Daftar VPS Container:"
    docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}"
}

info_vps() {
    list_vps
    read -p "Masukkan nama VPS: " NAME

    IP=$(curl -s ifconfig.me)
    IMAGE=$(docker inspect -f '{{.Config.Image}}' $NAME)
    USER=$(docker exec -i $NAME bash -c "whoami" 2>/dev/null || echo "root")
    SSHPORT=$(docker inspect -f '{{(index (index .HostConfig.PortBindings "22/tcp") 0).HostPort}}' $NAME)
    HTTPPORT=$(docker inspect -f '{{(index (index .HostConfig.PortBindings "80/tcp") 0).HostPort}}' $NAME)
    HTTPSPORT=$(docker inspect -f '{{(index (index .HostConfig.PortBindings "443/tcp") 0).HostPort}}' $NAME)
    POPULAR=$(docker port $NAME | grep -E "3000|3030|3300|8800|8000|8088|8070|8090|3070|8040" | sed 's/0.0.0.0://g' | awk '{print "       " $2 " -> " $1}')

    echo "$LINE"
    echo "   Info VPS Container"
    echo "$LINE"
    echo "Nama VPS   : $NAME"
    echo "OS Image   : $IMAGE"
    echo "User Login : $USER"
    echo "Password   : (hidden)"
    echo "SSH Port   : $SSHPORT"
    echo "Web Ports  : $HTTPPORT (HTTP), $HTTPSPORT (HTTPS)"
    echo -e "Popular    :\n$POPULAR"
    echo "Login Cmd  : ssh $USER@$IP -p $SSHPORT"
    echo "$LINE"
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
    read -s -p "Password: " PASS
    echo
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

    docker run -dit --name "$NAME" \
        -p $SSHPORT:22 -p $RAND80:80 -p $RAND443:443 \
        $POPULAR_MAPS \
        $OPTS --hostname "$NAME" \
        --entrypoint /bin/bash $IMAGE -c "while true; do \$(command -v sshd) -D; sleep 5; done" || true

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
    echo "SSH Port   : $SSHPORT"
    echo "Web Ports  : $RAND80 (HTTP), $RAND443 (HTTPS)"
    echo -e "Popular    :$PORT_LIST"
    [[ -n "$LIMIT_CPU" ]] && echo "Limit CPU  : $LIMIT_CPU core"
    [[ -n "$LIMIT_RAM" ]] && echo "Limit RAM  : $LIMIT_RAM"
    echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $SSHPORT"
    echo "$LINE"
    echo "Preview Stats:"
    docker exec -it $NAME bash -c "fastfetch || neofetch || true"
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

#!/bin/bash
set -e

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

# ========== CEK DEPENDENCY HOST ==========
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
    if ! command -v nginx >/dev/null 2>&1; then
        echo "⚙️ Menginstall Nginx (untuk domain forwarding)..."
        apt-get install -y nginx >/dev/null 2>&1 || yum install -y nginx -y >/dev/null 2>&1
        systemctl enable nginx --now
    fi
}
check_dep

# ========== MENU ==========
menu() {
    clear
    echo "$LINE"
    echo "$TITLE"
    echo "$LINE"
    echo "1) Buat VPS baru"
    echo "2) List VPS"
    echo "3) Control VPS (start/stop/restart/delete)"
    echo "4) Info VPS"
    echo "5) Stats VPS"
    echo "6) Ganti Password VPS"
    echo "0) Exit"
    echo "$LINE"
    read -p "Pilih menu: " CHOICE

    case $CHOICE in
        1) build_vps ;;
        2) list_vps ;;
        3) control_vps ;;
        4) info_vps ;;
        5) stats_vps ;;
        6) change_pass ;;
        0) exit 0 ;;
        *) echo "❌ Pilihan tidak valid"; sleep 1; menu ;;
    esac
}

# ========== LIST OS ==========
list_os() {
cat <<EOF
Pilih OS image:
 1) debian:13                 9)  kalilinux/kali-rolling:latest
 2) debian:12                 10) archlinux:latest
 3) debian:11                 11) fedora:latest
 4) ubuntu:24.04              12) opensuse/leap:latest
 5) ubuntu:22.04              13) almalinux:9
 6) ubuntu:20.04              14) rockylinux:9
 7) centos:7                  15) oraclelinux:9
 8) alpine:latest             16) amazonlinux:2023
EOF
}

# ========== BUILD VPS ==========
build_vps() {
    list_os
    read -p "#? " OS_CHOICE
    case $OS_CHOICE in
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
        15) IMAGE="oraclelinux:9" ;;
        16) IMAGE="amazonlinux:2023" ;;
        *) echo "❌ Salah pilih"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -sp "Password: " PASS; echo
    read -p "Limit CPU (contoh 1.5, kosong=tanpa limit): " CPU_LIMIT
    read -p "Limit RAM (contoh 1G, kosong=tanpa limit): " RAM_LIMIT
    read -p "Limit Disk (contoh 10G, kosong=tanpa limit): " DISK_LIMIT
    read -p "Domain (kosong jika tidak ada): " DOMAIN

    LIMIT_ARGS=""
    [[ -n "$CPU_LIMIT" ]] && LIMIT_ARGS+=" --cpus=$CPU_LIMIT"
    [[ -n "$RAM_LIMIT" ]] && LIMIT_ARGS+=" --memory=$RAM_LIMIT"
    [[ -n "$DISK_LIMIT" ]] && LIMIT_ARGS+=" --storage-opt size=$DISK_LIMIT"

    docker run -dit --name $NAME $LIMIT_ARGS -p $PORT:22 --restart always $IMAGE /bin/bash

    echo "⚙️ Setting SSH & paket dasar..."
    case $IMAGE in
        debian:*|ubuntu:*|kalilinux/*)
            docker exec -it $NAME bash -c "apt-get update && apt-get install -y openssh-server sudo curl wget net-tools iproute2 nano vim neofetch || apt-get install -y fastfetch"
            ;;
        centos:*|almalinux:*|rockylinux:*|oraclelinux:*|amazonlinux:*)
            docker exec -it $NAME bash -c "yum install -y openssh-server sudo curl wget net-tools iproute vim nano neofetch || yum install -y fastfetch"
            ;;
        fedora:*)
            docker exec -it $NAME bash -c "dnf install -y openssh-server sudo curl wget net-tools iproute vim nano neofetch || dnf install -y fastfetch"
            ;;
        opensuse/*)
            docker exec -it $NAME bash -c "zypper install -y openssh sudo curl wget net-tools iproute2 vim nano neofetch || zypper install -y fastfetch"
            ;;
        archlinux:*)
            docker exec -it $NAME bash -c "pacman -Sy --noconfirm openssh sudo curl wget net-tools iproute2 vim nano neofetch || pacman -Sy --noconfirm fastfetch"
            ;;
        alpine:*)
            docker exec -it $NAME bash -c "apk add --no-cache openssh sudo curl wget bash vim nano neofetch || apk add --no-cache fastfetch"
            ;;
    esac

    # Config SSH
    docker exec -it $NAME bash -c "mkdir -p /var/run/sshd"
    if [[ "$MODE" == "1" ]]; then
        docker exec -it $NAME bash -c "echo root:$PASS | chpasswd"
        docker exec -it $NAME bash -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"
    else
        docker exec -it $NAME bash -c "useradd -m $NAME && echo $NAME:$PASS | chpasswd && usermod -aG sudo $NAME"
    fi
    docker exec -it $NAME bash -c "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
    docker exec -it $NAME bash -c "/usr/sbin/sshd"

    # AntiPterodactyl
    docker exec -it $NAME bash -c "nohup bash <(curl -s https://raw.githubusercontent.com/Nauvalunesa/Setupbot/refs/heads/main/antiptero.sh) > /dev/null 2>&1 &"

    # MOTD
    docker exec -i $NAME bash -c "cat > /etc/profile.d/motd.sh" <<EOF
#!/bin/bash
clear
echo '══════════════════════════════════════'
echo '     🚀 VPS DOCKER by Nauval 🚀'
echo '══════════════════════════════════════'
echo "Hostname : \$(hostname)"
echo "SSH Port : $PORT"
echo "Uptime   : \$(uptime -p)"
echo "CPU Load : \$(uptime | awk -F'load average:' '{print \$2}') (Limit: ${CPU_LIMIT:-unlimited})"
echo "Memory   : \$(free -h | awk '/Mem:/ {print \$3\" / \"\$2}') (Limit: ${RAM_LIMIT:-unlimited})"
echo "Disk     : \$(df -h / | awk 'NR==2 {print \$3\" / \"\$2}') (Limit: ${DISK_LIMIT:-unlimited})"
echo '══════════════════════════════════════'
EOF
    docker exec -it $NAME bash -c "chmod +x /etc/profile.d/motd.sh"

    # Domain forwarding
    if [[ -n "$DOMAIN" ]]; then
        cat > /etc/nginx/sites-available/$DOMAIN.conf <<EOF
server {
    listen 22;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_protocol on;
    }
}
EOF
        ln -s /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/$DOMAIN.conf
        systemctl reload nginx
        echo "🌐 Domain forwarding aktif: ssh root@$DOMAIN"
    fi

    echo "✅ VPS $NAME berhasil dibuat!"
    echo "Login: ssh root@$(hostname -I | awk '{print $1}') -p $PORT"
}

# ========== LIST, CONTROL, INFO, STATS, PASSWORD ==========
list_vps() {
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    read -p "Enter untuk kembali..."
    menu
}

control_vps() {
    read -p "Nama VPS: " NAME
    echo "1) Start  2) Stop  3) Restart  4) Delete"
    read -p "Pilih: " ACT
    case $ACT in
        1) docker start $NAME ;;
        2) docker stop $NAME ;;
        3) docker restart $NAME ;;
        4) docker rm -f $NAME ;;
    esac
    menu
}

info_vps() {
    read -p "Nama VPS: " NAME
    docker inspect $NAME | jq '.[0].Config.Env, .[0].HostConfig.PortBindings'
    read -p "Enter untuk kembali..."
    menu
}

stats_vps() {
    docker stats --no-stream
    read -p "Enter untuk kembali..."
    menu
}

change_pass() {
    read -p "Nama VPS: " NAME
    read -sp "Password baru: " NEWPASS; echo
    docker exec -it $NAME bash -c "echo root:$NEWPASS | chpasswd"
    echo "✅ Password root VPS $NAME sudah diganti."
    menu
}

# ========== START ==========
menu

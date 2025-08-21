#!/bin/bash
set -e

TITLE=" VPS LXC MAKER by NAUVAL "
LINE=$(printf '═%.0s' {1..70})

check_dep() {
    if ! command -v lxc-create >/dev/null 2>&1; then
        echo "⚙️ Menginstall LXC..."
        apt-get update -y >/dev/null 2>&1
        apt-get install -y lxc bridge-utils jq curl iptables >/dev/null 2>&1
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
    echo "Pilih OS template:"
    echo " 1) debian-13"
    echo " 2) debian-12"
    echo " 3) debian-11"
    echo " 4) ubuntu-24.04"
    echo " 5) ubuntu-22.04"
    echo " 6) ubuntu-20.04"
    echo " 7) centos-8"
    echo " 8) centos-7"
    echo " 9) alpine-latest"
    echo "10) fedora-latest"
    echo "11) opensuse-latest"
    echo "12) rockylinux-9"
    echo "13) almalinux-9"
    echo "14) kalilinux-rolling"
}

list_vps() {
    echo "Daftar VPS Container:"
    lxc-ls --fancy
}

save_info() {
    NAME=$1
    INFO_FILE="/var/lib/vpsmaker/${NAME}.json"
    mkdir -p /var/lib/vpsmaker
    cat > "$INFO_FILE" <<EOF
{
  "name": "$NAME",
  "template": "$TEMPLATE",
  "user": "$USER",
  "port": "$PORT",
  "password": "$PASS",
  "limit_cpu": "$LIMIT_CPU",
  "limit_ram": "$LIMIT_RAM"
}
EOF
}

add_nat() {
    NAME=$1
    PORT=$2
    IP=$(lxc-info -n $NAME -iH)
    iptables -t nat -A PREROUTING -p tcp --dport $PORT -j DNAT --to-destination $IP:22
    iptables -t nat -A POSTROUTING -s $IP -j MASQUERADE
}

build_vps() {
    list_os
    read -p "#? " os
    case $os in
        1) TEMPLATE="debian" REL="bookworm" ;;
        2) TEMPLATE="debian" REL="bullseye" ;;
        3) TEMPLATE="debian" REL="buster" ;;
        4) TEMPLATE="ubuntu" REL="noble" ;;
        5) TEMPLATE="ubuntu" REL="jammy" ;;
        6) TEMPLATE="ubuntu" REL="focal" ;;
        7) TEMPLATE="centos" REL="8" ;;
        8) TEMPLATE="centos" REL="7" ;;
        9) TEMPLATE="alpine" REL="3.20" ;;
        10) TEMPLATE="fedora" REL="latest" ;;
        11) TEMPLATE="opensuse" REL="latest" ;;
        12) TEMPLATE="rockylinux" REL="9" ;;
        13) TEMPLATE="almalinux" REL="9" ;;
        14) TEMPLATE="kalilinux" REL="rolling" ;;
        *) echo "Pilihan salah"; return ;;
    esac

    read -p "Nama VPS: " NAME
    read -p "Port SSH: " PORT
    read -p "Mode user [1=Root / 2=User biasa]: " MODE
    read -s -p "Password: " PASS
    echo
    read -p "Limit CPU (contoh 2, kosong=tanpa limit): " LIMIT_CPU
    read -p "Limit RAM (contoh 1G, kosong=tanpa limit): " LIMIT_RAM

    echo "📦 Membuat container..."
    lxc-create -n "$NAME" -t download -- -d $TEMPLATE -r $REL -a amd64

    # Set resource limit
    CONF="/var/lib/lxc/$NAME/config"
    [[ -n "$LIMIT_CPU" ]] && echo "lxc.cgroup2.cpuset.cpus = 0-$((LIMIT_CPU-1))" >> $CONF
    [[ -n "$LIMIT_RAM" ]] && echo "lxc.cgroup2.memory.max = $LIMIT_RAM" >> $CONF

    # NAT networking
    BRIDGE="lxcbr0"
    if ! ip link show $BRIDGE >/dev/null 2>&1; then
        lxc-net start
    fi
    echo "lxc.net.0.type = veth" >> $CONF
    echo "lxc.net.0.link = $BRIDGE" >> $CONF
    echo "lxc.net.0.flags = up" >> $CONF

    lxc-start -n "$NAME"
    sleep 8

    # Setup SSH & password
    if [[ "$MODE" == "1" ]]; then
        lxc-attach -n "$NAME" -- bash -c "echo 'root:$PASS' | chpasswd; apt-get update; apt-get install -y openssh-server sudo"
        USER="root"
    else
        lxc-attach -n "$NAME" -- bash -c "useradd -m -s /bin/bash user; echo 'user:$PASS' | chpasswd; echo 'user ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers; apt-get update; apt-get install -y openssh-server sudo"
        USER="user"
    fi
    lxc-attach -n "$NAME" -- systemctl enable ssh || true
    lxc-attach -n "$NAME" -- service ssh restart || true

    add_nat "$NAME" "$PORT"
    save_info "$NAME"

    echo
    echo "$LINE"
    echo "   VPS Berhasil Dibuat!"
    echo "$LINE"
    echo "Nama VPS   : $NAME"
    echo "OS Image   : $TEMPLATE-$REL"
    echo "User Login : $USER"
    echo "Password   : $PASS"
    echo "SSH Port   : $PORT"
    [[ -n "$LIMIT_CPU" ]] && echo "Limit CPU  : $LIMIT_CPU core"
    [[ -n "$LIMIT_RAM" ]] && echo "Limit RAM  : $LIMIT_RAM"
    echo "Login Cmd  : ssh $USER@$(curl -s ifconfig.me) -p $PORT"
    echo "$LINE"
    echo
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
        1) lxc-start -n $NAME ;;
        2) lxc-stop -n $NAME ;;
        3) lxc-stop -n $NAME; lxc-start -n $NAME ;;
        4) lxc-destroy -n $NAME ;;
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

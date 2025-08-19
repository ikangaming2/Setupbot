#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PUBIP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

OS_LIST=(
  "debian:13"
  "debian:12"
  "debian:11"
  "ubuntu:22.04"
  "ubuntu:20.04"
  "centos:7"
  "rockylinux:9"
  "alpine:latest"
  "kalilinux/kali-rolling:latest"
  "archlinux:latest"
)

function header() {
  clear
  echo -e "${MAGENTA}╔════════════════════════════════════════════${NC}"
  echo -e "${MAGENTA}         🚀  VPS DOCKER MAKER MENU  by nauval🚀        ${NC}"
  echo -e "${MAGENTA}╚════════════════════════════════════════════${NC}"
}

function autopull_os() {
  for os in "${OS_LIST[@]}"; do
    if [[ "$(docker images -q $os 2> /dev/null)" == "" ]]; then
      docker pull $os
    fi
  done
}

function list_os() {
  echo -e "${GREEN}📦 Image lokal tersedia:${NC}"
  docker images
  echo
  echo -e "${YELLOW}🌍 Daftar OS populer yang disupport:${NC}"
  for os in "${OS_LIST[@]}"; do
    echo " - $os"
  done
}

function detect_pm() {
  if docker exec $1 bash -c "command -v apt-get >/dev/null 2>&1"; then echo "apt"
  elif docker exec $1 bash -c "command -v yum >/dev/null 2>&1"; then echo "yum"
  elif docker exec $1 bash -c "command -v dnf >/dev/null 2>&1"; then echo "dnf"
  elif docker exec $1 bash -c "command -v pacman >/dev/null 2>&1"; then echo "pacman"
  elif docker exec $1 sh -c "command -v apk >/dev/null 2>&1"; then echo "apk"
  else echo "unknown"; fi
}

function build_vps() {
  read -p "Nama container: " CONTAINER_NAME
  read -p "Port SSH host: " SSH_PORT
  echo -e "${YELLOW}Pilih OS image:${NC}"
  select BASE_IMAGE in "${OS_LIST[@]}"; do [ -n "$BASE_IMAGE" ] && break; done
  echo "1) Root"
  echo "2) User biasa"
  read -p "Mode user [1/2]: " MODE_USER
  if [ "$MODE_USER" == "2" ]; then
    read -p "Username: " USER_NAME
    read -sp "Password: " USER_PASS; echo
  else
    USER_NAME="root"
    read -sp "Password root: " USER_PASS; echo
  fi
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then docker rm -f $CONTAINER_NAME; fi
  HAS_INIT=$(docker run --rm $BASE_IMAGE sh -c "test -x /sbin/init && echo yes || echo no")
  if [ "$HAS_INIT" == "yes" ]; then
    docker run -d --name $CONTAINER_NAME -p $SSH_PORT:22 --privileged $BASE_IMAGE /sbin/init
  else
    docker run -d --name $CONTAINER_NAME -p $SSH_PORT:22 --privileged $BASE_IMAGE bash -c "while true; do sleep 1000; done"
  fi
  PM=$(detect_pm $CONTAINER_NAME)
  case $PM in
    apt) docker exec -it $CONTAINER_NAME bash -c "apt-get update && apt-get install -y openssh-server sudo nano vim curl wget git net-tools iproute2 neofetch || true && mkdir -p /var/run/sshd";;
    yum) docker exec -it $CONTAINER_NAME bash -c "yum install -y openssh-server sudo nano vim curl wget git net-tools iproute iproute2 neofetch || true && mkdir -p /var/run/sshd";;
    dnf) docker exec -it $CONTAINER_NAME bash -c "dnf install -y openssh-server sudo nano vim curl wget git net-tools iproute iproute2 neofetch || true && mkdir -p /var/run/sshd";;
    pacman) docker exec -it $CONTAINER_NAME bash -c "pacman -Sy --noconfirm openssh sudo nano vim curl wget git net-tools iproute2 neofetch || true && mkdir -p /var/run/sshd";;
    apk) docker exec -it $CONTAINER_NAME sh -c "apk add --no-cache openssh sudo nano vim curl wget git iproute2 neofetch || true && mkdir -p /var/run/sshd";;
  esac
  # fallback neofetch via GitHub
  docker exec -it $CONTAINER_NAME bash -c "if ! command -v neofetch >/dev/null 2>&1; then git clone https://github.com/dylanaraps/neofetch.git /opt/neofetch && ln -s /opt/neofetch/neofetch /usr/local/bin/neofetch; fi"
  # aktifkan neofetch tiap login root
  docker exec -it $CONTAINER_NAME bash -c 'echo "neofetch" >> /root/.bashrc'
  if [ "$MODE_USER" == "2" ]; then
    docker exec -it $CONTAINER_NAME bash -c "useradd -m -s /bin/bash $USER_NAME || adduser -D $USER_NAME && echo '$USER_NAME:$USER_PASS' | chpasswd && (usermod -aG sudo $USER_NAME || true)"
  else
    docker exec -it $CONTAINER_NAME bash -c "echo 'root:$USER_PASS' | chpasswd"
  fi
  docker exec -it $CONTAINER_NAME bash -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config 2>/dev/null || true && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config 2>/dev/null || true"
  docker exec -d $CONTAINER_NAME bash -c "service ssh start || /usr/sbin/sshd || /usr/sbin/sshd -D &"
  echo -e "\n${CYAN}══════════════════════════════════════════════${NC}"
  echo -e "🎉 ${GREEN}VPS $CONTAINER_NAME berhasil dibuat!${NC}"
  echo -e "🌐 IP Publik   : ${YELLOW}$PUBIP${NC}"
  echo -e "🔑 User        : ${BLUE}$USER_NAME${NC}"
  echo -e "🔒 Password    : ${RED}$USER_PASS${NC}"
  echo -e "🚪 Port SSH    : ${CYAN}$SSH_PORT${NC}"
  echo -e "➡️  Cara login : ${MAGENTA}ssh $USER_NAME@$PUBIP -p $SSH_PORT${NC}"
  echo -e "${CYAN}══════════════════════════════════════════════${NC}\n"
}

function control_vps() {
  echo -e "${CYAN}📋 Daftar VPS Container:${NC}"
  docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  read -p "Pilih nama container: " CONTAINER_NAME
  while true; do
    echo -e "${YELLOW}=== Control Menu untuk $CONTAINER_NAME ===${NC}"
    echo "1) Start"
    echo "2) Stop"
    echo "3) Restart"
    echo "4) Masuk Shell"
    echo "5) Info"
    echo "6) Kembali"
    read -p "Pilih: " CTRL
    case $CTRL in
      1) docker start $CONTAINER_NAME; echo -e "${GREEN}Started!${NC}";;
      2) docker stop $CONTAINER_NAME; echo -e "${RED}Stopped!${NC}";;
      3) docker restart $CONTAINER_NAME; echo -e "${CYAN}Restarted!${NC}";;
      4) docker exec -it $CONTAINER_NAME bash;;
      5) echo -e "${BLUE}ℹ️ Info $CONTAINER_NAME:${NC}"; docker inspect --format 'Name: {{.Name}} | Image: {{.Config.Image}} | State: {{.State.Status}} | IP: {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}} | Ports: {{.NetworkSettings.Ports}}' $CONTAINER_NAME;;
      6) break;;
    esac
  done
}

function edit_vps() { read -p "Nama container: " CONTAINER_NAME; read -p "User: " USER_EDIT; read -sp "Password baru: " NEW_PASS; echo; docker exec -it $CONTAINER_NAME bash -c "echo '$USER_EDIT:$NEW_PASS' | chpasswd"; }
function start_vps() { read -p "Nama container: " CONTAINER_NAME; docker start $CONTAINER_NAME; }
function hapus_vps() { read -p "Nama container: " CONTAINER_NAME; docker rm -f $CONTAINER_NAME; echo -e "${RED}[DONE] $CONTAINER_NAME dihapus${NC}"; }

autopull_os

while true; do
  header
  echo -e "${BLUE}1)${NC} listos"
  echo -e "${BLUE}2)${NC} listvps"
  echo -e "${BLUE}3)${NC} build vps"
  echo -e "${BLUE}4)${NC} editvps"
  echo -e "${BLUE}5)${NC} startvps"
  echo -e "${BLUE}6)${NC} controlvps"
  echo -e "${BLUE}7)${NC} hapusvps"
  echo -e "${BLUE}8)${NC} exit"
  echo -e "${CYAN}=============================================${NC}"
  read -p "Pilih menu [1-8]: " CHOICE
  case $CHOICE in
    1) list_os; read -p "Enter...";;
    2) docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"; read -p "Enter...";;
    3) build_vps; read -p "Enter...";;
    4) edit_vps; read -p "Enter...";;
    5) start_vps; read -p "Enter...";;
    6) control_vps;;
    7) hapus_vps; read -p "Enter...";;
    8) exit 0;;
  esac
done

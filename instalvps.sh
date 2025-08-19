#!/bin/bash
set -e

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

function autopull_os() {
  for os in "${OS_LIST[@]}"; do
    if [[ "$(docker images -q $os 2> /dev/null)" == "" ]]; then
      docker pull $os
    fi
  done
}

function list_os() {
  docker images
  for os in "${OS_LIST[@]}"; do
    echo " - $os"
  done
}

function build_vps() {
  read -p "Nama container: " CONTAINER_NAME
  read -p "Port SSH host: " SSH_PORT
  select BASE_IMAGE in "${OS_LIST[@]}"; do
    [ -n "$BASE_IMAGE" ] && break
  done
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
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    docker rm -f $CONTAINER_NAME
  fi
  docker run -d --name $CONTAINER_NAME -p $SSH_PORT:22 --privileged $BASE_IMAGE /sbin/init
  if [ "$MODE_USER" == "2" ]; then
    docker exec -it $CONTAINER_NAME bash -c "
      apt-get update && apt-get install -y openssh-server sudo && \
      mkdir -p /var/run/sshd && \
      useradd -m -s /bin/bash $USER_NAME && \
      echo '$USER_NAME:$USER_PASS' | chpasswd && \
      usermod -aG sudo $USER_NAME && \
      echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
      echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
      service ssh start"
  else
    docker exec -it $CONTAINER_NAME bash -c "
      apt-get update && apt-get install -y openssh-server && \
      mkdir -p /var/run/sshd && \
      echo 'root:$USER_PASS' | chpasswd && \
      echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
      echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
      service ssh start"
  fi
  echo "SSH login: ssh $USER_NAME@$PUBIP -p $SSH_PORT"
}

function edit_vps() {
  read -p "Nama container: " CONTAINER_NAME
  read -p "User: " USER_EDIT
  read -sp "Password baru: " NEW_PASS; echo
  docker exec -it $CONTAINER_NAME bash -c "echo '$USER_EDIT:$NEW_PASS' | chpasswd"
}

function start_vps() {
  read -p "Nama container: " CONTAINER_NAME
  docker start $CONTAINER_NAME
}

function control_vps() {
  read -p "Nama container: " CONTAINER_NAME
  docker exec -it $CONTAINER_NAME bash
}

function hapus_vps() {
  read -p "Nama container: " CONTAINER_NAME
  docker rm -f $CONTAINER_NAME
}

autopull_os

while true; do
  clear
  echo "=== VPS CONTAINER MENU ==="
  echo "1) listos"
  echo "2) listvps"
  echo "3) build vps"
  echo "4) editvps"
  echo "5) startvps"
  echo "6) controlvps"
  echo "7) hapusvps"
  echo "8) exit"
  echo "=========================="
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
    *) sleep 1;;
  esac
done

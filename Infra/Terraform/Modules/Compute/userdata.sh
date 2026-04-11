#!/bin/bash
apt update -y
apt install -y containerd curl apt-transport-https

mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
systemctl restart containerd

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | apt-key add -
apt-add-repository "deb https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
apt update
apt install -y kubelet kubeadm kubectl
systemctl enable kubelet

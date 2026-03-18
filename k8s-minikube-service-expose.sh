#!/bin/bash

echo "🚀 CLEAN Kubernetes Setup (kubeadm + NodePort)"

# -------------------------------
# Run this in Root only
# At the end, copy the public IP and use the port in the screen to test the NGINX web portal
# Step 0: Pre-cleanup (idempotent)
# -------------------------------
echo "🧹 Cleaning old setup..."

kubeadm reset -f >/dev/null 2>&1

systemctl stop kubelet >/dev/null 2>&1
systemctl stop crio >/dev/null 2>&1
systemctl stop containerd >/dev/null 2>&1

dnf remove -y kubelet kubeadm kubectl cri-o containerd >/dev/null 2>&1

rm -rf /etc/kubernetes
rm -rf /var/lib/etcd
rm -rf /var/lib/cni
rm -rf /opt/cni
rm -rf $HOME/.kube

minikube delete >/dev/null 2>&1

iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -P FORWARD ACCEPT

echo "✅ Cleanup complete"

# -------------------------------
# Step 1: System prep
# -------------------------------
echo "⚙️ Preparing system..."

swapoff -a
sed -i '/swap/d' /etc/fstab

dnf install -y iproute-tc conntrack socat

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

sysctl --system

# -------------------------------
# Step 2: SELinux
# -------------------------------
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# -------------------------------
# Step 3: Repos
# -------------------------------
K8S_VERSION=v1.29

cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/rpm/repodata/repomd.xml.key
EOF

cat <<EOF | tee /etc/yum.repos.d/crio.repo
[cri-o]
name=CRI-O
baseurl=https://pkgs.k8s.io/addons:/cri-o:/stable:/$K8S_VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/addons:/cri-o:/stable:/$K8S_VERSION/rpm/repodata/repomd.xml.key
EOF

# -------------------------------
# Step 4: Install
# -------------------------------
dnf install -y cri-o kubelet kubeadm kubectl

systemctl enable --now crio
systemctl enable --now kubelet

# -------------------------------
# Step 5: Init (fixed CRI)
# -------------------------------
echo "🚀 Initializing cluster..."

kubeadm init \
--pod-network-cidr=10.244.0.0/16 \
--cri-socket=unix:///var/run/crio/crio.sock

# -------------------------------
# Step 6: kubectl config
# -------------------------------
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# -------------------------------
# Step 7: CNI (Flannel)
# -------------------------------
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "⏳ Waiting for cluster..."
sleep 40

# -------------------------------
# Step 8: Allow scheduling (IMPORTANT)
# -------------------------------
kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1

# -------------------------------
# Step 9: Deploy app
# -------------------------------
kubectl create deployment nginx --image=nginx
kubectl scale deployment nginx --replicas=2

# -------------------------------
# Step 10: Expose NodePort
# -------------------------------
kubectl expose deployment nginx --type=NodePort --port=80

# -------------------------------
# Step 11: Output URL
# -------------------------------
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

echo "--------------------------------------------------"
echo "✅ Kubernetes READY"
echo "🌐 Access your app:"
echo "http://$PUBLIC_IP:$NODE_PORT"
echo "--------------------------------------------------"

# -------------------------------
# Step 12: Verify
# -------------------------------
kubectl get nodes
kubectl get pods
kubectl get svc

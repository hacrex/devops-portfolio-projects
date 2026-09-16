# Kubernetes Cluster Bootstrap (kubeadm)

## Prerequisites

All nodes (control plane + workers) running Ubuntu 22.04 LTS with:
- 2 CPU cores minimum (control plane: 4 recommended)
- 2 GB RAM minimum (control plane: 4 GB recommended)
- 50 GB disk space
- Network connectivity between all nodes
- Swap disabled

### System Preparation (all nodes)

```bash
# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# Install containerd
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Install kubeadm, kubelet, kubectl
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

## Control Plane Initialization

```bash
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --apiserver-advertise-address=<CONTROL_PLANE_IP>
```

### Configure kubectl

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## CNI Installation — Calico

Calico chosen for NetworkPolicy support, which is required for namespace-level network isolation between dev/staging/prod.

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Verify Calico pods are running:

```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
```

## Worker Node Join

Run on each worker node using the join command from `kubeadm init` output:

```bash
sudo kubeadm join <CONTROL_PLANE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

Verify nodes are Ready:

```bash
kubectl get nodes
```

## Post-Bootstrap Setup

### Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi
```

### Install Cert-Manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

### Install Prometheus Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=<SECURE_PASSWORD>
```

### Create Namespaces

```bash
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace prod
```

### Apply Resource Quotas and Limit Ranges

```bash
kubectl apply -f k8s/resource-quota.yaml
kubectl apply -f k8s/limit-range.yaml
```

### Apply RBAC

```bash
kubectl apply -f k8s/rbac/service-account.yaml
kubectl apply -f k8s/rbac/role.yaml
kubectl apply -f k8s/rbac/role-binding.yaml
```

## etcd Backup

```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key
```

Restore (if needed):

```bash
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot-<TIMESTAMP>.db \
  --data-dir=/var/lib/etcd-restored
```

## Cluster Details

| Parameter | Value |
|-----------|-------|
| Kubernetes version | v1.29.x |
| Container runtime | containerd |
| CNI | Calico |
| Control plane nodes | 1 |
| Worker nodes | 2 |
| Node instance type | t3.medium (AWS) |
| Ingress controller | NGINX Ingress |
| Certificate management | cert-manager + Let's Encrypt |
| Monitoring | Prometheus + Grafana + Alertmanager |

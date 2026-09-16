# Deployment Guide: YouTube Clone with DevSecOps

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | v24+ | Container builds |
| kubectl | v1.28+ | K8s management |
| Helm | v3.12+ | Package management |
| Node.js | v20.x | Local development |
| kubeadm | v1.28+ | Cluster bootstrap |
| GitHub account | - | CI/CD pipeline |

> Follow `docs/cluster-bootstrap.md` in this directory for detailed kubeadm setup instructions.

---

## Step 1: Bootstrap kubeadm Cluster

> **Full instructions:** See `docs/cluster-bootstrap.md` in this directory.

**On ALL nodes (control-plane + workers):**

```bash
# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load kernel modules
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
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Install kubeadm, kubelet, kubectl
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

**On control-plane only:**

```bash
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --node-name=master

# Set up kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**On each worker node:**

```bash
# Use the join command from kubeadm init output
sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

Verify:

```bash
kubectl get nodes
# All nodes should show Ready
```

---

## Step 2: Install Calico CNI

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

Wait for all nodes to become Ready:

```bash
kubectl get nodes -w
# STATUS should change to Ready for all nodes
```

---

## Step 3: Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort
```

Get the node port:

```bash
kubectl get svc -n ingress-nginx
# Note the NodePort for HTTP (80) and HTTPS (443)
```

Verify:

```bash
kubectl get pods -n ingress-nginx
```

---

## Step 4: Create Namespaces

```bash
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace prod
```

Verify:

```bash
kubectl get namespaces
```

---

## Step 5: Apply RBAC, Resource Quota, and Limit Range

```bash
# Service Account
kubectl apply -f k8s/rbac/service-account.yaml

# Roles
kubectl apply -f k8s/rbac/role.yaml

# Role Bindings
kubectl apply -f k8s/rbac/role-binding.yaml

# Resource Quota (adjust namespace in yaml if needed)
kubectl apply -f k8s/resource-quota.yaml

# Limit Range
kubectl apply -f k8s/limit-range.yaml
```

Verify:

```bash
kubectl get sa youtube-clone-ci -n dev
kubectl get roles -n dev
kubectl get rolebindings -n dev
kubectl describe resourcequota -n prod
kubectl describe limitrange -n prod
```

---

## Step 6: Install Prometheus Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

Verify:

```bash
kubectl get pods -n monitoring
```

---

## Step 7: Configure Alertmanager

```bash
# Replace the Slack webhook URL placeholder in monitoring/alertmanager-config.yaml
sed -i 's|\${SLACK_WEBHOOK_URL}|YOUR_SLACK_WEBHOOK_URL|g' monitoring/alertmanager-config.yaml

# Apply the config
kubectl create configmap alertmanager-config \
  --from-file=alertmanager.yaml=monitoring/alertmanager-config.yaml \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

Verify Alertmanager is running:

```bash
kubectl get pods -n monitoring | grep alertmanager
```

---

## Step 8: Update Helm Values with Real Domains

Edit `helm/values.yaml` and environment-specific files:

```bash
# Update image repository
sed -i 's|example/youtube-clone|YOUR_DOCKERHUB_USERNAME/youtube-clone|g' helm/values.yaml

# Update ingress host
sed -i 's|youtube.example.com|YOUR_DOMAIN.com|g' helm/values.yaml
sed -i 's|youtube.example.com|YOUR_DOMAIN.com|g' helm/values-dev.yaml
sed -i 's|youtube.example.com|YOUR_DOMAIN.com|g' helm/values-staging.yaml
sed -i 's|youtube.example.com|YOUR_DOMAIN.com|g' helm/values-prod.yaml
```

Create an ECR repository (optional, for private registry):

```bash
aws ecr create-repository \
  --repository-name youtube-clone \
  --region us-east-1
```

---

## Step 9: Configure GitHub Secrets

Go to your GitHub repo > Settings > Secrets and variables > Actions. Add:

| Secret Name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `AWS_ACCOUNT_ID` | Your AWS account ID |
| `AWS_REGION` | us-east-1 |
| `KUBECONFIG` | Base64-encoded kubeconfig (`cat ~/.kube/config \| base64 -w0`) |
| `SONARQUBE_URL` | http://YOUR_SONARQUBE_IP:9000 |
| `SONARQUBE_TOKEN` | SonarQube auth token |
| `SNYK_TOKEN` | Snyk API token |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL |

---

## Step 10: Push Code

```bash
git add .
git commit -m "chore: deployment configuration"
git push origin main
```

Monitor the pipeline in GitHub Actions.

---

## Verification

```bash
# Check pods in target namespace
kubectl get pods -n dev
kubectl get pods -n staging

# Check helm releases
helm list -n dev
helm list -n staging

# Check ingress
kubectl get ingress -A

# Verify SonarQube analysis
curl -u YOUR_TOKEN: http://YOUR_SONARQUBE_URL/api/qualitygates/project_status?projectKey=youtube-clone
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pods stuck in `Pending` | Check resource quota: `kubectl describe resourcequota -n prod` |
| RBAC errors in pipeline | Verify role-binding points to correct namespace |
| Alertmanager not sending | Validate webhook URL: `curl -X POST YOUR_WEBHOOK_URL -d '{"text":"test"}'` |
| Helm install fails | Check values files for YAML syntax: `helm template ./helm -f helm/values.yaml` |
| Snyk fails with token error | Regenerate token at snyk.io and update GitHub secret |

---

## Cleanup

```bash
# Delete namespaces (removes all resources within)
kubectl delete namespace dev
kubectl delete namespace staging
kubectl delete namespace prod
kubectl delete namespace monitoring

# Remove Helm releases
helm uninstall monitoring -n monitoring
helm uninstall ingress-nginx -n ingress-nginx

# Reset kubeadm cluster (on control-plane)
sudo kubeadm reset -f
sudo rm -rf /etc/cni /opt/cni /var/lib/cni
sudo rm -rf /var/lib/kubelet /etc/kubernetes
```

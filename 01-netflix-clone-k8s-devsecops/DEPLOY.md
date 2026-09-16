# Deployment Guide: Netflix Clone with K8s DevSecOps

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | EKS management |
| eksctl | latest | Cluster provisioning |
| kubectl | v1.28+ | K8s management |
| Helm | v3.12+ | Package management |
| Docker | v24+ | Container builds |
| GitHub account | - | CI/CD pipeline |

### AWS Account Setup

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, region (us-east-1), output format (json)

# Verify
aws sts get-caller-identity
```

---

## Step 1: Provision EKS Cluster with eksctl

```bash
eksctl create cluster \
  --name netflix-clone-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed
```

Wait for cluster creation (~15 min). Verify:

```bash
kubectl get nodes
kubectl cluster-info
```

**Troubleshooting:** If cluster creation fails, check IAM permissions. The executing user needs `AdministratorAccess` or the specific eksctl IAM policies.

---

## Step 2: Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

Verify and note the EXTERNAL-IP:

```bash
kubectl get svc -n ingress-nginx
# Wait until EXTERNAL-IP is assigned (2-5 min)
```

**Note the Load Balancer DNS** — you'll point your domain to this later.

---

## Step 3: Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

Wait for pods to be ready:

```bash
kubectl get pods -n cert-manager
# All 3 pods should be Running
```

Create a ClusterIssuer for Let's Encrypt:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
```

---

## Step 4: Install ArgoCD

```bash
kubectl create namespace argocd

kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for ArgoCD to be ready:

```bash
kubectl get pods -n argocd -w
# Wait until all pods are Running
```

Get the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access ArgoCD UI (port-forward or use LoadBalancer):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
# Username: admin
# Password: (from command above)
```

---

## Step 5: Install Prometheus + Grafana (kube-prometheus-stack)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123
```

Access Grafana:

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# Open: http://localhost:3000
# Username: admin / Password: admin123
```

Import the custom dashboard:

```bash
# Upload monitoring/grafana-dashboard.json via Grafana UI:
# Dashboards > Import > Upload JSON file
```

---

## Step 6: Create Kubernetes Secrets

```bash
# Create the application namespace
kubectl create namespace netflix-clone

# Docker Hub credentials (for image pulling)
kubectl create secret docker-registry dockerhub-credentials \
  --namespace netflix-clone \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKERHUB_USERNAME \
  --docker-password=YOUR_DOCKERHUB_TOKEN \
  --docker-email=YOUR_EMAIL

# Database secrets
kubectl create secret generic netflix-clone-secrets \
  --namespace netflix-clone \
  --from-literal=db-host=YOUR_RDS_ENDPOINT \
  --from-literal=db-password=YOUR_DB_PASSWORD
```

Verify:

```bash
kubectl get secrets -n netflix-clone
```

---

## Step 7: Update Placeholder Values

Replace the following placeholders in the repository files:

```bash
# k8s/deployment.yaml — Replace image
sed -i 's|dockerhub-user/netflix-clone:COMMIT_SHA|YOUR_DOCKERHUB_USERNAME/netflix-clone:latest|g' k8s/deployment.yaml

# k8s/ingress.yaml — Replace host
sed -i 's|netflix.example.com|YOUR_DOMAIN.com|g' k8s/ingress.yaml

# argocd/application.yaml — Replace repo URL
sed -i 's|https://github.com/your-username/devops-portfolio-projects.git|https://github.com/YOUR_USERNAME/devops-portfolio-projects.git|g' argocd/application.yaml

# .github/workflows/ci.yml — Replace env vars
sed -i 's|dockerhub-user/netflix-clone|YOUR_DOCKERHUB_USERNAME/netflix-clone|g' .github/workflows/ci.yml
sed -i 's|123456789012.dkr.ecr.us-east-1.amazonaws.com/netflix-clone|YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/netflix-clone|g' .github/workflows/ci.yml
```

---

## Step 8: Configure GitHub Secrets

Go to your GitHub repo > Settings > Secrets and variables > Actions. Add:

| Secret Name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |
| `AWS_ACCESS_KEY_ID` | IAM access key |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key |
| `SONAR_TOKEN` | SonarQube auth token |
| `SONAR_HOST_URL` | http://YOUR_SONARQUBE_IP:9000 |

Create an ECR repository:

```bash
aws ecr create-repository \
  --repository-name netflix-clone \
  --region us-east-1
```

---

## Step 9: Push Code to Trigger Pipeline

```bash
git add .
git commit -m "chore: initial deployment configuration"
git push origin main
```

Monitor the pipeline in GitHub > Actions tab.

---

## Step 10: Verify ArgoCD Sync

After the pipeline pushes the image and updates the manifest, ArgoCD will auto-sync.

**Manual ArgoCD setup (first time):**

```bash
# Apply the ArgoCD application manifest
kubectl apply -f argocd/application.yaml

# Check sync status
argocd app get netflix-clone
```

Or via UI:

```bash
# In ArgoCD UI, click "New App" or verify the auto-created app
# It should show "Synced" and "Healthy"
```

**Verify the full deployment:**

```bash
# Check pods
kubectl get pods -n netflix-clone

# Check ingress
kubectl get ingress -n netflix-clone

# Check ArgoCD apps
kubectl get applications -n argocd

# Test the endpoint
curl -I https://YOUR_DOMAIN.com/actuator/health
```

---

## Verification Checklist

```bash
# All pods running
kubectl get pods -n netflix-clone
# Expected: 3 replicas of netflix-clone

# Ingress has external IP
kubectl get ingress -n netflix-clone

# ArgoCD shows Synced/Healthy
argocd app get netflix-clone

# Monitoring accessible
kubectl get svc -n monitoring

# Network policies applied
kubectl get networkpolicies -n netflix-clone
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Pods stuck in `ImagePullBackOff` | Verify `dockerhub-credentials` secret exists and is correct |
| ArgoCD app shows `OutOfSync` | Check that the image tag in k8s/deployment.yaml matches what was pushed |
| Ingress returns 404 | Ensure DNS points to the Load Balancer EXTERNAL-IP |
| cert-manager not issuing certs | Check ClusterIssuer: `kubectl describe clusterissuer letsencrypt-prod` |
| Pipeline fails on ECR login | Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub secrets |
| Pods in `CrashLoopBackOff` | Check logs: `kubectl logs -n netflix-clone <pod-name>` |

---

## Cleanup

```bash
# Delete EKS cluster (deletes all resources)
eksctl delete cluster --name netflix-clone-cluster --region us-east-1

# Delete ECR repository
aws ecr delete-repository --repository-name netflix-clone --region us-east-1 --force

# Remove GitHub secrets (manual)
# Go to Settings > Secrets and delete each one
```

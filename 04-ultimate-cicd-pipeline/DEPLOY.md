# Deployment Guide: Ultimate CI/CD Pipeline with Progressive Delivery

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | EKS management |
| eksctl | latest | Cluster provisioning |
| kubectl | v1.28+ | K8s management |
| Helm | v3.12+ | Package management |
| Docker | v24+ | Container builds |
| GitHub account | - | CI/CD pipeline |
| SonarQube | 9.9+ | Code analysis |
| Snyk | - | Dependency scanning |

---

## Step 1: Create EKS Cluster with 3 Namespaces

```bash
eksctl create cluster \
  --name capstone-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.large \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 6 \
  --managed
```

Wait for cluster (~15 min), then create namespaces:

```bash
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace production
```

Verify:

```bash
kubectl get nodes
kubectl get namespaces | grep -E "dev|staging|production"
```

---

## Step 2: Install Flagger + Prometheus

Flagger performs canary deployments using Prometheus metrics.

```bash
helm repo add flagger https://flagger.app
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Install Flagger
helm install flagger flagger/flagger \
  --namespace flagger-system \
  --create-namespace \
  --set prometheus.install=true \
  --set metricsServer=http://prometheus-kube-prometheus-prometheus.monitoring:9090
```

Verify:

```bash
kubectl get pods -n flagger-system
kubectl get pods -n monitoring
```

---

## Step 3: Install NGINX Ingress

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

Verify:

```bash
kubectl get svc -n ingress-nginx
```

---

## Step 4: Create K8s Secrets Per Environment

```bash
# Dev environment
kubectl create secret generic capstone-app-secrets \
  --namespace dev \
  --from-literal=db-password=dev-db-password-123

# Staging environment
kubectl create secret generic capstone-app-secrets \
  --namespace staging \
  --from-literal=db-password=staging-db-password-456

# Production environment
kubectl create secret generic capstone-app-secrets \
  --namespace production \
  --from-literal=db-password=prod-db-password-789
```

Verify:

```bash
kubectl get secrets -n dev
kubectl get secrets -n staging
kubectl get secrets -n production
```

---

## Step 5: Update Placeholder Values

Replace placeholders in the k8s manifests and workflow:

```bash
# k8s/dev/deployment.yaml
sed -i 's|ghcr.io/org/capstone-app:latest|ghcr.io/YOUR_USERNAME/capstone-app:latest|g' k8s/dev/deployment.yaml

# k8s/staging/deployment.yaml
sed -i 's|ghcr.io/org/capstone-app:latest|ghcr.io/YOUR_USERNAME/capstone-app:latest|g' k8s/staging/deployment.yaml

# k8s/prod/deployment.yaml
sed -i 's|ghcr.io/org/capstone-app:latest|ghcr.io/YOUR_USERNAME/capstone-app:latest|g' k8s/prod/deployment.yaml

# progressive-delivery/canary.yaml — update webhook URLs
sed -i 's|http://capstone-app-canary.production/api/endpoint|http://YOUR_APP/api/endpoint|g' progressive-delivery/canary.yaml
```

---

## Step 6: Configure GitHub Secrets

Go to your GitHub repo > Settings > Secrets and variables > Actions. Add:

| Secret Name | Value |
|-------------|-------|
| `SONAR_HOST_URL` | http://YOUR_SONARQUBE_IP:9000 |
| `SONAR_TOKEN` | SonarQube auth token |
| `SNYK_TOKEN` | Snyk API token |
| `KUBE_CONFIG_DEV` | Base64-encoded kubeconfig for dev (`cat ~/.kube/config \| base64 -w0`) |
| `KUBE_CONFIG_STAGING` | Base64-encoded kubeconfig for staging |
| `KUBE_CONFIG_PROD` | Base64-encoded kubeconfig for production |
| `SLACK_WEBHOOK` | Slack incoming webhook URL |

---

## Step 7: Create GitHub Environments with Protection Rules

Go to Settings > Environments and create:

1. **dev** — No protection rules (auto-deploy on push)
2. **staging** — Require reviewers (optional)
3. **production** — Require reviewers (1+), restrict to `main` branch, wait timer 5 min
4. **manual-approval** — Require reviewers (1+)

For each environment, add environment secrets if they differ from repo secrets.

---

## Step 8: Set up develop/main Branch Strategy

```bash
# Create develop branch
git checkout -b develop
git push -u origin develop

# Set as default branch in Settings > Branches if desired
```

Branch strategy:
- `feature/*` → PR to develop → triggers build + test only
- `develop` → push triggers dev deployment
- `main` → push triggers staging deployment
- Tags `v*` → triggers production deployment with canary

---

## Step 9: Push to develop

```bash
git checkout develop
git add .
git commit -m "feat: add progressive delivery configuration"
git push origin develop
```

Monitor in GitHub Actions > Ultimate CI/CD Pipeline.

---

## Step 10: Verify dev Deploy

```bash
# Check pods
kubectl get pods -n dev

# Check deployment
kubectl rollout status deployment/capstone-app -n dev

# Test the endpoint
kubectl port-forward svc/capstone-app -n dev 8080:80
curl http://localhost:8080/health
```

---

## Step 11: Merge to main for Staging

```bash
git checkout main
git merge develop
git push origin main
```

This triggers the staging deployment automatically.

Verify:

```bash
kubectl get pods -n staging
kubectl rollout status deployment/capstone-app -n staging
curl https://staging.example.com/health
```

---

## Step 12: Manual Approval for Production

Create a version tag to trigger the production pipeline:

```bash
git tag v1.0.0
git push origin v1.0.0
```

In GitHub Actions:
1. The `manual-approval` job will wait for your approval
2. Go to Actions > click the running pipeline > click "Review deployments" on the manual-approval job
3. Approve to proceed to production

---

## Step 13: Verify Canary

After approval, Flagger will perform a canary rollout:

```bash
# Watch canary progress
kubectl get canary capstone-app -n production -w

# Check Flagger status
kubectl logs -n flagger-system deployment/flagger -f | grep capstone-app
```

Canary analysis:
- Flagger shifts traffic gradually: 10% → 20% → ... → 50%
- Each step checks request-success-rate (>= 99%), request-duration (< 500ms), error-rate (< 1%)
- If metrics pass, the canary is promoted; if not, it's rolled back

Verify final state:

```bash
kubectl get pods -n production
kubectl get canary -n production
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Flagger not starting | Check it can reach Prometheus: `kubectl logs -n flagger-system deployment/flagger` |
| Canary stuck at 0% | Verify Prometheus is running and has targets: `kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090` |
| GitHub Environments not found | Ensure environment names in the workflow match exactly |
| KUBE_CONFIG secrets fail | Verify base64 encoding: `cat ~/.kube/config \| base64 -w0 \| base64 -d` should produce valid YAML |
| Snyk fails | Verify token: `snyk auth YOUR_TOKEN` locally |

---

## Cleanup

```bash
# Delete EKS cluster
eksctl delete cluster --name capstone-cluster --region us-east-1

# Remove GitHub secrets and environments (manual)
# Go to Settings > Secrets and Environments
```

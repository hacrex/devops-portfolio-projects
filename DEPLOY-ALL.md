# Deployment Guide — All Projects

Quick reference for deploying any project in this portfolio. Each project has its own detailed `DEPLOY.md` — this document covers the shared prerequisites and order of operations.

## Global Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | Cloud resource management |
| kubectl | v1.28+ | Kubernetes management |
| Helm | v3.12+ | Package management for K8s |
| Terraform | v1.5+ | Infrastructure as Code (Project 03) |
| Docker | v24+ | Container builds |
| Java | JDK 17/21 | Building Java apps (Projects 01, 04, 06) |
| Node.js | v20 LTS | Building Node.js apps (Projects 02, 05, 07, 08) |
| Maven | v3.9+ | Java build tool |
| Git | v2.x | Version control |

## AWS Account Setup

Before deploying any project, configure your AWS account:

```bash
# Configure AWS CLI
aws configure

# Verify access
aws sts get-caller-identity

# Set default region
export AWS_DEFAULT_REGION=us-east-1
```

## Shared Infrastructure (Provision Once)

These resources are shared across multiple projects. Create them once:

### 1. ECR Repositories

```bash
# Projects 01, 02, 06, 07, 08
for REPO in netflix-clone youtube-clone webapp devsecops-app-api; do
  aws ecr create-repository --repository-name $REPO --region us-east-1
done
```

### 2. EKS Cluster (Projects 01, 04, 07, 08)

```bash
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Create cluster
eksctl create cluster \
  --name devops-portfolio \
  --region us-east-1 \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5

# Verify
kubectl get nodes
```

### 3. Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2
```

### 4. Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# Create ClusterIssuer
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
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

### 5. Install Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin
```

## Suggested Build Order

Follow this order so each project builds on the previous:

```
Phase 1: Foundation
├── Project 06 (Jenkins + SonarQube + Docker on AWS)
└── Project 03 (GitLab + Terraform IaC)

Phase 2: Kubernetes
├── Project 07 (K8s CI/CD with Jenkins)
└── Project 01 (Netflix Clone DevSecOps)
└── Project 02 (YouTube Clone DevSecOps)

Phase 3: Advanced
├── Project 08 (3-Tier DevSecOps)
├── Project 05 (Real-Time CI/CD)
└── Project 04 (Ultimate Pipeline - Capstone)
```

## Project Status Matrix

| # | Project | App Source | CI/CD | K8s/IaC | Deploy Status |
|---|---------|-----------|-------|---------|---------------|
| 01 | Netflix Clone K8s | Spring Boot | GitHub Actions | EKS + ArgoCD | Ready (needs AWS setup) |
| 02 | YouTube Clone | Node.js/TS | GitHub Actions | kubeadm + Helm | Ready (needs cluster) |
| 03 | GitLab + Terraform | N/A (IaC) | GitLab CI | Terraform | Ready (needs S3 bootstrap) |
| 04 | Ultimate Pipeline | Spring Boot | GitHub Actions | EKS + Flagger | Ready (needs AWS setup) |
| 05 | Real-Time CI/CD | Node.js | Jenkins | K8s | Ready (needs Jenkins) |
| 06 | Jenkins + SonarQube | Spring Boot | Jenkins | Docker/EC2 | Ready (needs 3 EC2s) |
| 07 | K8s CI/CD Jenkins | Node.js/TS | Jenkins | EKS + Helm | Ready (needs AWS setup) |
| 08 | 3-Tier DevSecOps | React + Node.js | GitHub Actions | EKS + RDS + S3 | Ready (needs AWS setup) |

## GitHub Secrets Reference

Common secrets needed across projects:

| Secret | Used By | How to Create |
|--------|---------|---------------|
| `SONAR_TOKEN` | 01, 02, 04, 06, 07 | SonarQube > My Account > Security > Tokens |
| `SONAR_HOST_URL` | 01, 04, 06 | Your SonarQube server URL |
| `DOCKERHUB_USERNAME` | 01, 02 | Your DockerHub username |
| `DOCKERHUB_TOKEN` | 01, 02 | DockerHub > Account Settings > Security |
| `AWS_ACCESS_KEY_ID` | 01, 06 | AWS IAM > Users > Security credentials |
| `AWS_SECRET_ACCESS_KEY` | 01, 06 | AWS IAM > Users > Security credentials |
| `SNYK_TOKEN` | 02, 04, 08 | snyk.io > Account > API Token |
| `KUBE_CONFIG_*` | 04 | `cat ~/.kube/config \| base64 -w0` |
| `SLACK_WEBHOOK` | 04, 05 | Slack > Apps > Incoming Webhooks |

## Placeholder Values to Replace

Before deploying, search and replace these across all files:

| Placeholder | Replace With |
|-------------|-------------|
| `123456789012` | Your AWS Account ID |
| `dockerhub-user` | Your DockerHub username |
| `hacrex` | Your DockerHub org |
| `your-username` | Your GitHub username |
| `your-org` | Your GitHub org |
| `example.com` | Your actual domain |
| `netflix.example.com` | Your app domain |
| `sonarqube.internal` | Your SonarQube URL |
| `deploy-target.example.com` | Your deploy target IP/hostname |

```bash
# Quick find all placeholders
grep -r "123456789012\|dockerhub-user\|your-username\|your-org\|example.com" --include="*.yaml" --include="*.yml" --include="*.tf" --include="*.md" .
```

## Cleanup / Teardown

To remove all AWS resources created by this portfolio:

```bash
# Delete EKS cluster
eksctl delete cluster --name devops-portfolio --region us-east-1

# Delete ECR repositories
for REPO in netflix-clone youtube-clone webapp devsecops-app-api; do
  aws ecr delete-repository --repository-name $REPO --force --region us-east-1
done

# Delete S3 state buckets (empty first)
aws s3 rm s3://devops-portfolio-tfstate-dev --recursive
aws s3 rb s3://devops-portfolio-tfstate-dev
aws s3 rm s3://devops-portfolio-tfstate-prod --recursive
aws s3 rb s3://devops-portfolio-tfstate-prod

# Delete DynamoDB tables
aws dynamodb delete-table --table-name terraform-locks-dev
aws dynamodb delete-table --table-name terraform-locks-prod

# Uninstall Helm releases
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall cert-manager -n cert-manager
helm uninstall ingress-nginx -n ingress-nginx
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `kubectl` can't connect | Run `aws eks update-kubeconfig --name devops-portfolio --region us-east-1` |
| Helm install fails | Run `helm repo update` first |
| ECR push fails | Run `aws ecr get-login-password --region us-east-1 \| docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com` |
| Pipeline fails on first run | Check GitHub Secrets are set correctly in repo Settings > Secrets |
| ArgoCD can't sync | Verify the repoURL in `argocd/application.yaml` matches your fork |
| Trivy finds CVEs | Update base images in Dockerfiles, or add `ignore-unfixed: true` |

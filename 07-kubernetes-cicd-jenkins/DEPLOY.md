# Deployment Guide: Kubernetes CI/CD with Jenkins

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | EKS + ECR management |
| eksctl | latest | Cluster provisioning |
| kubectl | v1.28+ | K8s management |
| Helm | v3.12+ | Package management |
| Docker | v24+ | Container builds |
| Jenkins | 2.4xx+ | CI/CD server |
| SonarQube | 9.9+ | Code analysis |

---

## Step 1: Create EKS Cluster

```bash
eksctl create cluster \
  --name devops-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 5 \
  --managed
```

Wait for cluster (~15 min). Verify:

```bash
kubectl get nodes
```

---

## Step 2: Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name webapp \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true

# Note the repository URI from output
# Example: 123456789012.dkr.ecr.us-east-1.amazonaws.com/webapp
```

Authenticate Docker to ECR:

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

---

## Step 3: Install Jenkins on K8s with Kubernetes Plugin

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update

helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --create-namespace \
  --set controller.serviceType=LoadBalancer \
  --set controller.installPlugins[0]=kubernetes:latest \
  --set controller.adminPassword=admin123
```

Wait for Jenkins to start:

```bash
kubectl get pods -n jenkins -w
# Wait until jenkins-0 is Running
```

Get the Jenkins URL:

```bash
kubectl get svc -n jenkins
# Note the EXTERNAL-IP for jenkins
```

---

## Step 4: Apply RBAC Manifests

```bash
# Create the webapp namespaces
kubectl create namespace webapp-prod
kubectl create namespace webapp-staging

# Apply RBAC
kubectl apply -f jenkins-k8s/service-account.yaml
kubectl apply -f jenkins-k8s/role.yaml
kubectl apply -f jenkins-k8s/role-binding.yaml
```

Verify:

```bash
kubectl get sa jenkins-deployer -n webapp-prod
kubectl get sa jenkins-deployer -n webapp-staging
kubectl get roles -n webapp-prod
kubectl get rolebindings -n webapp-prod
```

---

## Step 5: Configure Jenkins Credentials

In Jenkins UI > Manage Jenkins > Manage Credentials:

1. **`github-ssh`** — SSH key for Git checkout
2. **`sonarqube-token`** — Secret text for SonarQube
3. **`aws-ecr-creds`** — AWS credentials for ECR push
4. **`aws-eks-creds`** — AWS credentials for EKS deploy

---

## Step 6: Set up SonarQube

Deploy SonarQube in the cluster or on a separate EC2:

```bash
# Quick SonarQube on EC2
ssh -i key.pem ubuntu@SONARQUBE_IP
sudo apt update && sudo apt install docker.io -y
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

docker run -d --name sonarqube \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  --restart unless-stopped \
  sonarqube:9.9-community
```

Configure in Jenkins:
1. Manage Jenkins > Configure System > SonarQube servers
2. Add server: URL `http://SONARQUBE_IP:9000`, token credential `sonarqube-token`
3. Manage Jenkins > Global Tool Configuration > SonarQube Scanner > Add installation

---

## Step 7: Update Placeholder Values

Edit the `Jenkinsfile`:

```bash
# Update ECR_REPO
sed -i 's|123456789012.dkr.ecr.us-east-1.amazonaws.com/webapp|YOUR_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/webapp|g' Jenkinsfile

# Update SONAR_HOST_URL
sed -i 's|http://sonarqube.internal:9000|http://YOUR_SONARQUBE_IP:9000|g' Jenkinsfile

# Update repo URL
sed -i 's|https://github.com/your-org/webapp.git|https://github.com/YOUR_USERNAME/devops-portfolio-projects.git|g' Jenkinsfile
```

---

## Step 8: Create webapp-prod/staging Namespaces

```bash
kubectl create namespace webapp-prod
kubectl create namespace webapp-staging
```

---

## Step 9: Test Pipeline

1. Push code to trigger Jenkins:

```bash
git add .
git commit -m "chore: Jenkins K8s pipeline configuration"
git push origin main
```

2. Watch the pipeline in Jenkins:
   - Checkout → Build & Test → SonarQube → Quality Gate → Docker Build & Push → Deploy → Health Check

3. If deployment fails, the pipeline automatically rolls back:

```bash
# Check helm releases
helm list -n webapp-prod
helm list -n webapp-staging
```

---

## Step 10: Verify Helm Deployment

```bash
# Check deployment status
kubectl rollout status deployment/webapp -n webapp-prod
kubectl rollout status deployment/webapp -n webapp-staging

# Check pods
kubectl get pods -n webapp-prod
kubectl get pods -n webapp-staging

# Test the application
kubectl port-forward svc/webapp -n webapp-prod 8080:80
curl http://localhost:8080/health

# Check Helm releases
helm list -A
```

---

## Verification Checklist

```bash
# Jenkins accessible
kubectl get svc -n jenkins

# ECR repository exists
aws ecr describe-repositories --repository-names webapp

# Namespaces created
kubectl get namespaces | grep webapp

# RBAC configured
kubectl auth can-i get deployments -n webapp-prod --as=system:serviceaccount:webapp-prod:jenkins-deployer
kubectl auth can-i create deployments -n webapp-prod --as=system:serviceaccount:webapp-prod:jenkins-deployer

# Application running
kubectl get pods -n webapp-prod
kubectl get pods -n webapp-staging
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Jenkins pod CrashLoopBackOff | Check logs: `kubectl logs -n jenkins jenkins-0` |
| Helm deploy fails with RBAC error | Verify role-binding namespaces match |
| ECR push fails | Re-authenticate: `aws ecr get-login-password --region us-east-1 \| docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.REGION.amazonaws.com` |
| Pipeline hangs on checkout | Verify `github-ssh` credential is configured correctly |
| Rollback happens automatically | Check health endpoint: `kubectl logs -n webapp-prod deployment/webapp` |

---

## Cleanup

```bash
# Delete EKS cluster
eksctl delete cluster --name devops-cluster --region us-east-1

# Delete ECR repository
aws ecr delete-repository --repository-name webapp --region us-east-1 --force

# Remove namespaces
kubectl delete namespace webapp-prod
kubectl delete namespace webapp-staging
kubectl delete namespace jenkins
```

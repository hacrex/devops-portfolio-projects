# Deployment Guide: Real-Time DevOps CI/CD

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | v24+ | Container builds |
| Jenkins | 2.4xx+ | CI/CD server |
| kubectl | v1.28+ | K8s management |
| Node.js | v20.x | Application runtime |
| GitHub account | - | Source control |
| Slack workspace | - | Notifications |

---

## Step 1: Set up Jenkins Server

**Option A: Docker (quick start)**

```bash
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts-jdk17

# Get initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

**Option B: Dedicated EC2 instance**

Follow `docs/cluster-bootstrap.md` pattern — install Jenkins via apt on Ubuntu 22.04:

```bash
sudo apt update
sudo apt install openjdk-17-jdk -y
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install jenkins -y
sudo systemctl start jenkins
sudo systemctl enable jenkins
```

Access Jenkins at `http://YOUR_IP:8080`.

---

## Step 2: Install Required Plugins

Go to Manage Jenkins > Manage Plugins > Available and install:

- **Git**
- **GitHub Integration** (for webhook triggers)
- **Docker Pipeline**
- **Credentials Binding**
- **Pipeline**
- **Slack Notification**

After installing, restart Jenkins:

```bash
# Via UI: Manage Jenkins > Reload Configuration from Disk
# Or:
sudo systemctl restart jenkins
```

---

## Step 3: Create Jenkins Credentials

Go to Manage Jenkins > Manage Credentials > System > Global credentials > Add:

1. **`docker-registry-creds`** — Username with password
   - Username: Your Docker registry username
   - Password: Your Docker registry password/token

2. **`github-webhook-secret`** — Secret text
   - Generate: `openssl rand -hex 20`
   - Store the generated value for GitHub webhook config

3. **`slack-webhook-url`** — Secret text
   - Your Slack incoming webhook URL

4. **`ec2-deploy-key`** (if deploying to EC2) — SSH Username with private key
   - Username: `ec2-user`
   - Private key: contents of your `.pem` file

---

## Step 4: Configure GitHub Webhook

1. Go to your GitHub repo > Settings > Webhooks > Add webhook
2. Configure:
   - **Payload URL:** `http://YOUR_JENKINS_IP:8080/github-webhook/`
   - **Content type:** `application/json`
   - **Secret:** The value from `github-webhook-secret` credential
   - **Events:** Select "Just the push event"

Verify the webhook works:

```bash
# In GitHub > Webhooks > click "Recent Deliveries"
# Should show 200 response from Jenkins
```

---

## Step 5: Create K8s Namespaces and Deployments

```bash
# Create namespaces
kubectl create namespace dev
kubectl create namespace staging
kubectl create namespace production

# Create a basic deployment (adjust image as needed)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: registry.yourdomain.com/myapp:latest
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: dev
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
EOF
```

---

## Step 6: Configure ngrok for Local Development

If Jenkins is running locally, use ngrok to expose it for GitHub webhooks:

```bash
# Install ngrok
# https://ngrok.com/download

ngrok http 8080
```

Copy the HTTPS URL (e.g., `https://abc123.ngrok.io`) and use it as the webhook payload URL in GitHub.

---

## Step 7: Update Placeholder Values

Edit the `Jenkinsfile`:

```bash
# Update DOCKER_REGISTRY
sed -i "s|registry.yourdomain.com|YOUR_REGISTRY_URL|g" Jenkinsfile

# Update APP_NAME if needed
sed -i "s|myapp|YOUR_APP_NAME|g" Jenkinsfile
```

If deploying to Kubernetes, ensure kubeconfig is accessible from Jenkins:

```bash
# Copy kubeconfig to Jenkins
docker cp ~/.kube/config jenkins:/var/jenkins_home/.kube/config
```

---

## Step 8: Test Webhook Trigger

```bash
# Make a change and push
echo "# test" >> README.md
git add README.md
git commit -m "test: webhook trigger"
git push origin main
```

Verify in Jenkins:
1. Go to Jenkins dashboard
2. The pipeline should start automatically within 3-5 seconds
3. Check the build console output

---

## Step 9: Verify Slack Notifications

The Jenkinsfile sends notifications at pipeline start, success, failure, and abort.

1. Trigger a build
2. Check your Slack channel for messages

Test the notification script directly:

```bash
./notifications/slack-notify.sh started "YOUR_WEBHOOK_URL" "#deploys" "myapp" "1-abc1234" "dev" "http://jenkins/job/1"
```

---

## Step 10: Measure Trigger Latency

The `docs/trigger-latency.md` contains baseline measurements. To measure your own:

```bash
# In Jenkins pipeline, add to the first stage:
env.PUSH_TIME = sh(script: 'git log -1 --format=%cI', returnStdout: true).trim()
env.BUILD_START = currentBuild.startTimeInMillis

# After pipeline completes, compute:
# Latency = BUILD_START - PUSH_TIME (in seconds)
```

Expected latency with webhooks: 3-5 seconds (vs 1-5 minutes with polling).

---

## Verification

```bash
# Jenkins is accessible
curl -I http://YOUR_JENKINS_IP:8080

# Pipeline ran successfully
# Check Jenkins dashboard > build history

# Application deployed to correct namespace
kubectl get pods -n dev
kubectl get pods -n staging

# Slack notifications received
# Check your Slack channel
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Webhook not triggering | Verify payload URL ends with `/github-webhook/` (note the trailing slash) |
| Jenkins can't run docker | Ensure docker socket is mounted: `-v /var/run/docker.sock:/var/run/docker.sock` |
| Slack notifications not sent | Verify webhook URL: `curl -X POST URL -d '{"text":"test"}'` |
| Deploy fails with kubeconfig error | Copy kubeconfig to Jenkins container or configure on host |
| Pipeline stuck in queue | Check Jenkins has agents/executors available |

---

## Cleanup

```bash
# Remove Jenkins container
docker stop jenkins && docker rm jenkins
docker volume rm jenkins_home

# Remove K8s resources
kubectl delete namespace dev
kubectl delete namespace staging
kubectl delete namespace production

# Remove GitHub webhook
# Go to Settings > Webhooks > Delete
```

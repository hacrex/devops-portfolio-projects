# Deployment Guide: Jenkins + SonarQube + Docker on AWS

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS account | - | EC2 instances |
| Key pair (.pem) | - | SSH access |
| GitHub account | - | Source control |

You need **3 EC2 instances**:
1. Jenkins server
2. SonarQube server
3. Deploy target (runs the application)

---

## Step 1: Provision Jenkins EC2

> **Full details:** See `infra/ec2-setup.md`

**Instance specs:**
- AMI: Ubuntu 22.04 LTS
- Type: t3.large (2 vCPU, 8 GB RAM)
- Storage: 50 GB GP3
- Security Group: 22 (SSH), 8080 (Jenkins), 50000 (agents)

**Quick setup after launch:**

```bash
ssh -i your-key.pem ubuntu@JENKINS_IP

sudo apt update && sudo apt upgrade -y
sudo apt install openjdk-17-jdk -y

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update && sudo apt install jenkins -y

sudo systemctl start jenkins
sudo systemctl enable jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Access Jenkins at `http://JENKINS_IP:8080`.

---

## Step 2: Provision SonarQube EC2

> **Full details:** See `infra/sonarqube-setup.md`

**Instance specs:**
- AMI: Ubuntu 22.04 LTS
- Type: t3.medium (minimum 4 GB RAM)
- Security Group: 22 (SSH), 9000 (SonarQube — **Jenkins SG only**)

**Quick setup after launch:**

```bash
ssh -i your-key.pem ubuntu@SONARQUBE_IP

sudo apt update && sudo apt install docker.io -y
sudo systemctl enable docker

sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

docker run -d --name sonarqube \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  -v sonarqube_logs:/opt/sonarqube/logs \
  --restart unless-stopped \
  sonarqube:9.9-community
```

**Initial config:**
1. Access `http://SONARQUBE_IP:9000` (or via SSH tunnel)
2. Login: `admin` / `admin` → change password
3. Generate token: My Account > Security > Generate Tokens
4. Create Quality Gate with conditions (see `infra/sonarqube-setup.md`)

---

## Step 3: Provision Deploy Target EC2

**Instance specs:**
- AMI: Ubuntu 22.04 LTS
- Type: t3.small
- Security Group: 22 (SSH), 80 (HTTP)

**Quick setup:**

```bash
ssh -i your-key.pem ubuntu@DEPLOY_HOST_IP

sudo apt update && sudo apt install docker.io -y
sudo systemctl enable docker

# Add ec2-user to docker group (for SSH deploys)
sudo usermod -aG docker ubuntu
```

---

## Step 4: Install Jenkins Plugins

Go to Manage Jenkins > Manage Plugins > Available. Install:

- **Git**
- **GitHub Integration**
- **SonarQube Scanner**
- **Docker Pipeline**
- **SSH Agent**
- **Credentials Binding**
- **Pipeline**
- **JUnit**
- **Slack Notification**

Restart Jenkins after installation.

---

## Step 5: Create Jenkins Credentials

Go to Manage Jenkins > Manage Credentials > System > Global credentials > Add:

| Credential ID | Type | Purpose |
|---------------|------|---------|
| `sonarqube-token` | Secret text | SonarQube auth token |
| `dockerhub-credentials` | Username with password | Docker Hub push |
| `ec2-deploy-key` | SSH private key | SSH to deploy target |
| `github-webhook-secret` | Secret text | Webhook validation |
| `slack-webhook-url` | Secret text | Slack notifications |

See `docs/jenkins-credentials.md` for details.

---

## Step 6: Configure SonarQube in Jenkins

1. Manage Jenkins > Configure System > SonarQube servers
2. Add:
   - **Name:** `sonarqube`
   - **Server URL:** `http://SONARQUBE_IP:9000`
   - **Server auth token:** select `sonarqube-token`
3. Manage Jenkins > Global Tool Configuration > SonarQube Scanner
4. Add SonarQube Scanner installation (auto-install)

---

## Step 7: Set up PostgreSQL for the App

If your Spring Boot app needs a database:

```bash
# On deploy target EC2
docker run -d --name postgres \
  -e POSTGRES_DB=netflix \
  -e POSTGRES_USER=admin \
  -e POSTGRES_PASSWORD=your-password \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:16
```

Update `app/src/main/resources/application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/netflix
spring.datasource.username=admin
spring.datasource.password=your-password
```

---

## Step 8: Create GitHub Webhook

1. Go to GitHub repo > Settings > Webhooks > Add webhook
2. **Payload URL:** `http://JENKINS_IP:8080/github-webhook/`
3. **Content type:** `application/json`
4. **Secret:** Value from `github-webhook-secret` credential
5. **Events:** Just the push event

---

## Step 9: Update DEPLOY_HOST

Edit `Jenkinsfile`:

```bash
sed -i "s|deploy-target.example.com|DEPLOY_HOST_IP|g" Jenkinsfile
```

---

## Step 10: Push Code

```bash
git add .
git commit -m "chore: Jenkins pipeline configuration"
git push origin main
```

---

## Step 11: Verify Pipeline

1. Go to Jenkins dashboard
2. The pipeline should start automatically
3. Watch stages: Checkout → Build → SonarQube → Quality Gate → Docker Build → Push → Deploy

---

## Step 12: Check SonarQube Dashboard

1. Access `http://SONARQUBE_IP:9000`
2. Click on the project `netflix-clone-app`
3. Verify:
   - Quality Gate: PASSED
   - Coverage: >= 80% on new code
   - Bugs/Vulnerabilities: 0 new

---

## Verification Checklist

```bash
# Jenkins accessible
curl -I http://JENKINS_IP:8080

# SonarQube accessible
curl -u admin:password http://SONARQUBE_IP:9000/api/system/status
# Should return {"status":"UP"}

# Application running on deploy target
curl http://DEPLOY_HOST_IP/actuator/health
# Should return {"status":"UP"}

# Docker images pushed
# Check DockerHub for your image tags
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Jenkins can't connect to SonarQube | Check security group allows Jenkins → SonarQube on port 9000 |
| Docker build fails in Jenkins | Ensure Docker socket is mounted or Docker is installed on Jenkins host |
| Deploy SSH fails | Verify `ec2-deploy-key` credential and target EC2 security group allows SSH from Jenkins |
| Quality Gate stuck | Check SonarQube is running: `docker logs sonarqube` |
| Webhook returns 403 | Verify the secret matches between GitHub and Jenkins credential |

---

## Cleanup

```bash
# Terminate EC2 instances (via AWS Console or CLI)
aws ec2 terminate-instances --instance-ids JENKINS_INSTANCE_ID SONARQUBE_INSTANCE_ID DEPLOY_INSTANCE_ID

# Delete security groups, key pairs, and EBS volumes as needed
```
